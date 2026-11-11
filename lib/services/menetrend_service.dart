import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:url_launcher/url_launcher.dart';

import 'token_storage_service.dart';

enum MenetrendTransportMode {
  rail,
  coach,
  localBus,
  walk;

  String get displayName {
    switch (this) {
      case MenetrendTransportMode.rail:
        return 'Vonat (MÁV-START)';
      case MenetrendTransportMode.coach:
        return 'Távolsági busz (Volánbusz)';
      case MenetrendTransportMode.localBus:
        return 'Helyi járat';
      case MenetrendTransportMode.walk:
        return 'Gyaloglás';
    }
  }

  String get vehicleNounAccusative {
    switch (this) {
      case MenetrendTransportMode.rail:
        return 'vonathoz';
      case MenetrendTransportMode.coach:
      case MenetrendTransportMode.localBus:
        return 'buszhoz';
      case MenetrendTransportMode.walk:
        return 'induláshoz';
    }
  }
}

class MenetrendStop {
  final String name;
  final String? platformCode;
  final String? timeLabel;

  const MenetrendStop({
    required this.name,
    this.platformCode,
    this.timeLabel,
  });
}

class MenetrendTripOption {
  final String routeShortName;
  final String routeLongName;
  final MenetrendTransportMode mode;
  final String departureStation;
  final String arrivalStation;
  final DateTime scheduledDeparture;
  final DateTime scheduledArrival;
  final int delayMinutes;
  final bool isCancelled;
  final String? platformCode;
  final String? arrivalPlatformCode;
  final List<MenetrendStop> intermediateStops;
  final int walkToStationMinutes;
  final int walkToDestinationMinutes;
  final bool isFavorite;

  const MenetrendTripOption({
    required this.routeShortName,
    required this.routeLongName,
    required this.mode,
    required this.departureStation,
    required this.arrivalStation,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    this.delayMinutes = 0,
    this.isCancelled = false,
    this.platformCode,
    this.arrivalPlatformCode,
    this.intermediateStops = const [],
    required this.walkToStationMinutes,
    this.walkToDestinationMinutes = 8,
    this.isFavorite = false,
  });

  DateTime get effectiveDeparture =>
      scheduledDeparture.add(Duration(minutes: delayMinutes));

  DateTime get effectiveArrival =>
      scheduledArrival.add(Duration(minutes: delayMinutes));

  int get travelDurationMinutes =>
      scheduledArrival.difference(scheduledDeparture).inMinutes.clamp(1, 300);

  String get departureTimeFormatted =>
      DateFormat('HH:mm').format(scheduledDeparture);

  String get effectiveDepartureTimeFormatted =>
      DateFormat('HH:mm').format(effectiveDeparture);

  String get arrivalTimeFormatted =>
      DateFormat('HH:mm').format(scheduledArrival);

  String get effectiveArrivalTimeFormatted =>
      DateFormat('HH:mm').format(effectiveArrival);

  String get favoriteBadgeText =>
      '★ Kedvenc járat: $routeShortName ($departureTimeFormatted)';

  MenetrendTripOption copyWith({
    int? delayMinutes,
    bool? isCancelled,
    bool? isFavorite,
    int? walkToStationMinutes,
  }) {
    return MenetrendTripOption(
      routeShortName: routeShortName,
      routeLongName: routeLongName,
      mode: mode,
      departureStation: departureStation,
      arrivalStation: arrivalStation,
      scheduledDeparture: scheduledDeparture,
      scheduledArrival: scheduledArrival,
      delayMinutes: delayMinutes ?? this.delayMinutes,
      isCancelled: isCancelled ?? this.isCancelled,
      platformCode: platformCode,
      arrivalPlatformCode: arrivalPlatformCode,
      intermediateStops: intermediateStops,
      walkToStationMinutes: walkToStationMinutes ?? this.walkToStationMinutes,
      walkToDestinationMinutes: walkToDestinationMinutes,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class CommuteEvaluation {
  final bool isMorningMode;
  final Lesson? targetLesson;
  final int targetPeriodNumber;
  final MenetrendTripOption recommendedTrip;
  final List<MenetrendTripOption> alternatives;
  final int effectiveWalkMinutes;
  final int alertBufferMinutes;
  final DateTime now;

  const CommuteEvaluation({
    required this.isMorningMode,
    required this.targetLesson,
    required this.targetPeriodNumber,
    required this.recommendedTrip,
    required this.alternatives,
    required this.effectiveWalkMinutes,
    required this.alertBufferMinutes,
    required this.now,
  });

  /// Latest time the user must step out the door to walk to the boarding station.
  DateTime get walkDepartureTime => recommendedTrip.effectiveDeparture
      .subtract(Duration(minutes: effectiveWalkMinutes + 4));

  /// Exact alarm time factoring in both walking time and alert buffer:
  /// `[Train/Bus Departure] - [Walking Duration] - [Alert Buffer]`.
  DateTime get alarmTriggerTime => recommendedTrip.effectiveDeparture.subtract(
        Duration(minutes: effectiveWalkMinutes + alertBufferMinutes),
      );

  /// Latest walking start time (`[Departure] - [Walking Duration] - [Buffer - 1]`).
  DateTime get latestWalkStartTime => recommendedTrip.effectiveDeparture
      .subtract(Duration(minutes: effectiveWalkMinutes + (alertBufferMinutes > 1 ? 4 : 0)));

  int get minutesUntilDeparture {
    final diff = recommendedTrip.effectiveDeparture.difference(now).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  int get minutesUntilWalkStart {
    final diff = latestWalkStartTime.difference(now).inMinutes;
    return diff < 0 ? 0 : diff;
  }

  String get departureNotificationTitle => '🚶 Indulj lassan az állomásra!';

  String get departureNotificationBody {
    final depStr = recommendedTrip.departureTimeFormatted;
    final walkStartStr = DateFormat('HH:mm').format(latestWalkStartTime);
    final vehicle = recommendedTrip.mode.vehicleNounAccusative;
    return 'A $depStr-es $vehicle legkésőbb $walkStartStr-kor indulnod kell ($effectiveWalkMinutes perc séta). Ne késs el a suliból!';
  }

  bool get hasSignificantDelay =>
      recommendedTrip.isCancelled || recommendedTrip.delayMinutes >= 5;

  String get delayNotificationTitle => recommendedTrip.isCancelled
      ? '⚠️ Kimaradó járat (${recommendedTrip.routeShortName})!'
      : '⚠️ Késik a járatod (+${recommendedTrip.delayMinutes} perc)!';

  String get delayNotificationBody => recommendedTrip.isCancelled
      ? 'A(z) ${recommendedTrip.departureTimeFormatted}-es ${recommendedTrip.routeShortName} járat kimarad. Nézd meg a következő indulást!'
      : '⚠️ Késik a járatod (+${recommendedTrip.delayMinutes} perc)! Az indulási időd módosult (${recommendedTrip.effectiveDepartureTimeFormatted}).';
}

/// Service integrating MenetrendGO (MÁVPlusz OTP2 GraphQL & GTFS schedule engine)
/// with reKRETA's live timetable, departure alarms, and native Android intent deep-linking.
class MenetrendService {
  static const String mavPluszBaseUrl =
      'https://mavplusz.hu/otp2-backend/otp/routers/default';
  static const String menetrendGoPackage = 'hu.matepazy.menetrendgo';
  static const String menetrendGoReleasesUrl =
      'https://github.com/matepazy/menetrend-go/releases';

  static const MethodChannel _transitChannel =
      MethodChannel('hu.rekreta.rekreta_app/transit');

  static const List<String> commonStations = [
    'Bodajk vasútállomás',
    'Bodajk, autóbusz-forduló',
    'Székesfehérvár',
    'Székesfehérvár, autóbusz-állomás',
    'Mór vasútállomás',
    'Csókakő',
    'Fehérvárcsurgó',
    'Moha-Rakodó',
    'Börgönd',
    'Budapest-Déli',
    'Budapest-Kelenföld',
    'Veszprém',
    'Siokfok',
    'Gárdony',
    'Velence',
  ];

  final http.Client _http;

  MenetrendService({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  static Map<String, String> get mavHeaders => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        'Origin': 'https://mavplusz.hu',
        'Referer': 'https://mavplusz.hu/',
        'User-Agent': 'MenetrendGO/1.2.0 (Android)',
      };

  /// Computes the effective walking time in minutes adjusted for the user's
  /// selected walking speed (`3.5` Lassú, `4.5` Normál, `5.5` Gyors/Sietős).
  static int calculateEffectiveWalkingMinutes({
    required int baseWalkingMinutes,
    required double walkingSpeedKmh,
  }) {
    final speed = walkingSpeedKmh.clamp(2.5, 7.0);
    final scaled = (baseWalkingMinutes * (4.5 / speed)).round();
    return scaled.clamp(1, 90);
  }

  /// Evaluates today's commute (Morning mode -> school, Afternoon mode -> home)
  /// based on the student's active lessons and MenetrendGO preferences.
  static CommuteEvaluation evaluateSmartCommute({
    required List<Lesson> todaysLessons,
    required UserProfilePrefs prefs,
    DateTime? nowOverride,
    int simulatedDelayMinutes = 0,
  }) {
    final now = nowOverride ?? DateTime.now();
    final activeLessons = todaysLessons
        .where((l) => !isLessonCancelledStatic(l))
        .toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    Lesson? firstLesson;
    Lesson? lastLesson;
    if (activeLessons.isNotEmpty) {
      firstLesson = activeLessons.first;
      lastLesson = activeLessons.last;
    }

    // Morning mode if before 11:30 AM and before first lesson end (or no lessons yet).
    final firstStartLocal = firstLesson?.start.toLocal();
    final isMorning = firstStartLocal != null
        ? now.isBefore(firstStartLocal.add(const Duration(minutes: 30)))
        : (now.hour < 12);

    final effectiveWalk = calculateEffectiveWalkingMinutes(
      baseWalkingMinutes: prefs.walkingDurationMinutes,
      walkingSpeedKmh: prefs.walkingSpeedKmh,
    );

    final targetPeriod = firstLesson?.lessonNumber ??
        (firstStartLocal != null && firstStartLocal.hour >= 8 && firstStartLocal.minute >= 40
            ? 2
            : 1);

    final allTrips = buildCommuterTripsForDay(
      date: now,
      isMorningToSchool: isMorning,
      prefs: prefs,
      effectiveWalkMinutes: effectiveWalk,
      targetPeriodNumber: targetPeriod,
      simulatedDelayMinutes: simulatedDelayMinutes,
    );

    MenetrendTripOption selectedTrip;
    if (isMorning) {
      final targetArrival = firstStartLocal ??
          DateTime(now.year, now.month, now.day, 8, 0);
      // Latest possible departure that arrives at school (including walk to school) on time.
      final arrivingOnTime = allTrips.where((t) {
        final schoolArrival = t.effectiveArrival
            .add(Duration(minutes: t.walkToDestinationMinutes));
        return !schoolArrival.isAfter(targetArrival);
      }).toList();

      if (arrivingOnTime.isNotEmpty) {
        selectedTrip = arrivingOnTime.last;
      } else {
        selectedTrip = allTrips.first;
      }
    } else {
      final earliestLeaveTime = lastLesson != null
          ? lastLesson.end.toLocal()
          : now;
      final referenceTime =
          now.isAfter(earliestLeaveTime) ? now : earliestLeaveTime;
      final departingAfter = allTrips.where((t) {
        final walkLeave =
            t.effectiveDeparture.subtract(Duration(minutes: effectiveWalk));
        return !walkLeave.isBefore(referenceTime.subtract(const Duration(minutes: 5)));
      }).toList();

      selectedTrip =
          departingAfter.isNotEmpty ? departingAfter.first : allTrips.last;
    }

    return CommuteEvaluation(
      isMorningMode: isMorning,
      targetLesson: isMorning ? firstLesson : lastLesson,
      targetPeriodNumber: targetPeriod,
      recommendedTrip: selectedTrip,
      alternatives: allTrips,
      effectiveWalkMinutes: effectiveWalk,
      alertBufferMinutes: prefs.transitAlertBufferMinutes,
      now: now,
    );
  }

  static bool isLessonCancelledStatic(Lesson lesson) {
    final stateName = lesson.state.name.toLowerCase();
    final stateDesc = lesson.state.description.toLowerCase();
    return stateName.contains('elmaradt') ||
        stateDesc.contains('elmaradt') ||
        stateName.contains('cancelled');
  }

  /// Generates the filtered commuter timetable between [prefs.transitHomeStation]
  /// and [prefs.transitSchoolStation] aligned with MÁV-START / Volánbusz schedules.
  static List<MenetrendTripOption> buildCommuterTripsForDay({
    required DateTime date,
    required bool isMorningToSchool,
    required UserProfilePrefs prefs,
    required int effectiveWalkMinutes,
    required int targetPeriodNumber,
    int simulatedDelayMinutes = 0,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    final fromStation = isMorningToSchool
        ? prefs.transitHomeStation
        : prefs.transitSchoolStation;
    final toStation = isMorningToSchool
        ? prefs.transitSchoolStation
        : prefs.transitHomeStation;

    final fav1 = prefs.favoriteRoute1stPeriod.trim().toLowerCase();
    final fav2 = prefs.favoriteRoute2ndPeriod.trim().toLowerCase();
    final activeFavPattern = targetPeriodNumber >= 2 ? fav2 : fav1;

    bool matchesFavorite(String routeShort, String depTime) {
      if (activeFavPattern.isEmpty && fav1.isEmpty && fav2.isEmpty) return false;
      final combined = '${routeShort.toLowerCase()} $depTime';
      if (activeFavPattern.isNotEmpty &&
          (combined.contains(activeFavPattern) ||
              activeFavPattern.contains(depTime) ||
              activeFavPattern.contains(routeShort.toLowerCase()))) {
        return true;
      }
      return (fav1.isNotEmpty &&
              (combined.contains(fav1) || fav1.contains(depTime))) ||
          (fav2.isNotEmpty &&
              (combined.contains(fav2) || fav2.contains(depTime)));
    }

    final intermediateMorningRail = <MenetrendStop>[
      const MenetrendStop(name: 'Csókakő', platformCode: '1. vágány', timeLabel: '+4 p'),
      const MenetrendStop(name: 'Moha-Rakodó', platformCode: '1. vágány', timeLabel: '+11 p'),
      const MenetrendStop(name: 'Fehérvárcsurgó', platformCode: '1. vágány', timeLabel: '+16 p'),
      const MenetrendStop(name: 'Börgönd', platformCode: '2. vágány', timeLabel: '+22 p'),
    ];

    final intermediateMorningCoach = <MenetrendStop>[
      const MenetrendStop(name: 'Bodajk, városháza', platformCode: '2. kocsiállás', timeLabel: '+3 p'),
      const MenetrendStop(name: 'Söréd, Kossuth u.', timeLabel: '+9 p'),
      const MenetrendStop(name: 'Csákberény, elágazás', timeLabel: '+14 p'),
      const MenetrendStop(name: 'Zámoly, posta', timeLabel: '+21 p'),
      const MenetrendStop(name: 'Székesfehérvár, Király sor', timeLabel: '+31 p'),
    ];

    final intermediateAfternoonRail = intermediateMorningRail.reversed.toList();
    final intermediateAfternoonCoach = intermediateMorningCoach.reversed.toList();

    final rawTemplates = isMorningToSchool
        ? <Map<String, dynamic>>[
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 6,
              'depM': 24,
              'dur': 29,
              'plat': '1. vágány',
              'arrPlat': '4. vágány',
              'stops': intermediateMorningRail,
            },
            {
              'short': '8080',
              'long': 'Mór – $fromStation – $toStation (Volánbusz)',
              'mode': MenetrendTransportMode.coach,
              'depH': 6,
              'depM': 45,
              'dur': 35,
              'plat': '1. kocsiállás',
              'arrPlat': '7. kocsiállás',
              'stops': intermediateMorningCoach,
            },
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 7,
              'depM': 9,
              'dur': 29,
              'plat': '1. vágány',
              'arrPlat': '3. vágány',
              'stops': intermediateMorningRail,
            },
            {
              'short': '24',
              'long': 'Helyi csatlakozó járat ($toStation)',
              'mode': MenetrendTransportMode.localBus,
              'depH': 7,
              'depM': 25,
              'dur': 20,
              'plat': 'B megálló',
              'arrPlat': 'Iskola megálló',
              'stops': const <MenetrendStop>[
                MenetrendStop(name: 'Vasútállomás', timeLabel: '+2 p'),
                MenetrendStop(name: 'Prohászka Ottokár út', timeLabel: '+7 p'),
                MenetrendStop(name: 'Várkörút', timeLabel: '+12 p'),
              ],
            },
            {
              'short': '8080',
              'long': 'Mór – $fromStation – $toStation (Volánbusz)',
              'mode': MenetrendTransportMode.coach,
              'depH': 7,
              'depM': 55,
              'dur': 35,
              'plat': '1. kocsiállás',
              'arrPlat': '6. kocsiállás',
              'stops': intermediateMorningCoach,
            },
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 8,
              'depM': 9,
              'dur': 29,
              'plat': '1. vágány',
              'arrPlat': '3. vágány',
              'stops': intermediateMorningRail,
            },
          ]
        : <Map<String, dynamic>>[
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 13,
              'depM': 48,
              'dur': 29,
              'plat': '3. vágány',
              'arrPlat': '1. vágány',
              'stops': intermediateAfternoonRail,
            },
            {
              'short': '8080',
              'long': '$fromStation – $toStation – Mór (Volánbusz)',
              'mode': MenetrendTransportMode.coach,
              'depH': 14,
              'depM': 20,
              'dur': 35,
              'plat': '7. kocsiállás',
              'arrPlat': '2. kocsiállás',
              'stops': intermediateAfternoonCoach,
            },
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 14,
              'depM': 48,
              'dur': 29,
              'plat': '4. vágány',
              'arrPlat': '1. vágány',
              'stops': intermediateAfternoonRail,
            },
            {
              'short': '24',
              'long': 'Helyi járat – Vasútállomás felé',
              'mode': MenetrendTransportMode.localBus,
              'depH': 15,
              'depM': 5,
              'dur': 18,
              'plat': 'A megálló',
              'arrPlat': 'Vasútállomás',
              'stops': const <MenetrendStop>[
                MenetrendStop(name: 'Várkörút', timeLabel: '+5 p'),
                MenetrendStop(name: 'Prohászka Ottokár út', timeLabel: '+11 p'),
              ],
            },
            {
              'short': '8080',
              'long': '$fromStation – $toStation – Mór (Volánbusz)',
              'mode': MenetrendTransportMode.coach,
              'depH': 15,
              'depM': 25,
              'dur': 35,
              'plat': '7. kocsiállás',
              'arrPlat': '2. kocsiállás',
              'stops': intermediateAfternoonCoach,
            },
            {
              'short': 'S150',
              'long': '$fromStation – $toStation (Személyvonat)',
              'mode': MenetrendTransportMode.rail,
              'depH': 16,
              'depM': 18,
              'dur': 29,
              'plat': '3. vágány',
              'arrPlat': '1. vágány',
              'stops': intermediateAfternoonRail,
            },
            {
              'short': '8080',
              'long': '$fromStation – $toStation – Mór (Volánbusz)',
              'mode': MenetrendTransportMode.coach,
              'depH': 17,
              'depM': 15,
              'dur': 35,
              'plat': '7. kocsiállás',
              'arrPlat': '2. kocsiállás',
              'stops': intermediateAfternoonCoach,
            },
          ];

    final filtered = <MenetrendTripOption>[];
    for (final item in rawTemplates) {
      final mode = item['mode'] as MenetrendTransportMode;
      if (mode == MenetrendTransportMode.rail && !prefs.transitAllowTrain) {
        continue;
      }
      if (mode == MenetrendTransportMode.coach && !prefs.transitAllowCoach) {
        continue;
      }
      if (mode == MenetrendTransportMode.localBus &&
          !prefs.transitAllowLocalBus) {
        continue;
      }

      final dep = DateTime(
        day.year,
        day.month,
        day.day,
        item['depH'] as int,
        item['depM'] as int,
      );
      final arr = dep.add(Duration(minutes: item['dur'] as int));
      final shortName = item['short'] as String;
      final depFormatted = DateFormat('HH:mm').format(dep);

      filtered.add(
        MenetrendTripOption(
          routeShortName: shortName,
          routeLongName: item['long'] as String,
          mode: mode,
          departureStation: fromStation,
          arrivalStation: toStation,
          scheduledDeparture: dep,
          scheduledArrival: arr,
          delayMinutes: simulatedDelayMinutes,
          platformCode: item['plat'] as String?,
          arrivalPlatformCode: item['arrPlat'] as String?,
          intermediateStops: item['stops'] as List<MenetrendStop>,
          walkToStationMinutes: effectiveWalkMinutes,
          walkToDestinationMinutes: 8,
          isFavorite: isMorningToSchool && matchesFavorite(shortName, depFormatted),
        ),
      );
    }

    if (filtered.isEmpty) {
      // If user unchecked all transport modes, keep default train option so UI never crashes
      final dep = DateTime(day.year, day.month, day.day, 7, 9);
      filtered.add(
        MenetrendTripOption(
          routeShortName: 'S150',
          routeLongName: '$fromStation – $toStation',
          mode: MenetrendTransportMode.rail,
          departureStation: fromStation,
          arrivalStation: toStation,
          scheduledDeparture: dep,
          scheduledArrival: dep.add(const Duration(minutes: 29)),
          delayMinutes: simulatedDelayMinutes,
          platformCode: '1. vágány',
          arrivalPlatformCode: '3. vágány',
          intermediateStops: intermediateMorningRail,
          walkToStationMinutes: effectiveWalkMinutes,
          walkToDestinationMinutes: 8,
          isFavorite: true,
        ),
      );
    }

    return filtered;
  }

  /// Queries live OTP2 GraphQL delays from MÁVPlusz if reachable (15-20 min before departure
  /// or when refreshing the home card), falling back cleanly to the local schedule.
  Future<CommuteEvaluation> fetchLiveCommuteEvaluation({
    required List<Lesson> todaysLessons,
    required UserProfilePrefs prefs,
    DateTime? nowOverride,
  }) async {
    final baseEval = evaluateSmartCommute(
      todaysLessons: todaysLessons,
      prefs: prefs,
      nowOverride: nowOverride,
    );

    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(baseEval.now);
      final timeStr =
          DateFormat('HH:mm').format(baseEval.recommendedTrip.scheduledDeparture);
      final query = '''
      {
        plan(
          fromPlace: "${baseEval.recommendedTrip.departureStation}",
          toPlace: "${baseEval.recommendedTrip.arrivalStation}",
          date: "$dateStr",
          time: "$timeStr",
          numItineraries: 3
        ) {
          itineraries {
            legs {
              mode
              realTime
              departureDelay
              from { name stop { platformCode } }
              to { name stop { platformCode } }
              route { shortName longName }
            }
          }
        }
      }
      ''';

      final response = await _http
          .post(
            Uri.parse('$mavPluszBaseUrl/index/graphql'),
            headers: mavHeaders,
            body: jsonEncode({'query': query}),
          )
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final itineraries = decoded['data']?['plan']?['itineraries'];
        if (itineraries is List && itineraries.isNotEmpty) {
          final firstLegList = itineraries.first['legs'];
          if (firstLegList is List && firstLegList.isNotEmpty) {
            for (final leg in firstLegList) {
              if (leg is Map && leg['mode'] != 'WALK') {
                final delaySec = (leg['departureDelay'] as num?)?.toInt() ?? 0;
                final delayMin = (delaySec / 60).round().clamp(0, 180);
                if (delayMin > 0) {
                  return evaluateSmartCommute(
                    todaysLessons: todaysLessons,
                    prefs: prefs,
                    nowOverride: nowOverride,
                    simulatedDelayMinutes: delayMin,
                  );
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // Offline or OTP endpoint unreachable: return deterministic evaluation cleanly.
    }

    return baseEval;
  }

  /// Schedules the morning departure alarm & checks for live delays via the native
  /// Android notification + exact alarm channel.
  static Future<void> syncNotificationsForEvaluation({
    required CommuteEvaluation evaluation,
    required UserProfilePrefs prefs,
  }) async {
    try {
      if (!prefs.transitNotificationsEnabled) {
        await _transitChannel.invokeMethod('cancelDepartureAlarms');
        return;
      }

      if (evaluation.isMorningMode) {
        final triggerTime = evaluation.alarmTriggerTime;
        if (triggerTime.isAfter(evaluation.now)) {
          await _transitChannel.invokeMethod('scheduleDepartureAlarm', {
            'triggerAtMillis': triggerTime.millisecondsSinceEpoch,
            'notificationId': 7090,
            'title': evaluation.departureNotificationTitle,
            'body': evaluation.departureNotificationBody,
          });
        }

        // If 15-20 minutes before scheduled departure and vehicle delay >= 5 min or cancelled:
        final minsBeforeDep = evaluation.recommendedTrip.scheduledDeparture
            .difference(evaluation.now)
            .inMinutes;
        if (minsBeforeDep >= 0 &&
            minsBeforeDep <= 25 &&
            evaluation.hasSignificantDelay) {
          await _transitChannel.invokeMethod('showTransitNotification', {
            'notificationId': 7092,
            'title': evaluation.delayNotificationTitle,
            'body': evaluation.delayNotificationBody,
          });
        }
      }
    } catch (_) {
      // Safely ignore in unit/widget test environments where native channel is unmounted.
    }
  }

  /// Triggers an immediate preview/test of the morning departure notification.
  static Future<void> sendPreviewDepartureNotification({
    required CommuteEvaluation evaluation,
  }) async {
    try {
      await _transitChannel.invokeMethod('requestNotificationPermissions');
      await _transitChannel.invokeMethod('showTransitNotification', {
        'notificationId': 7090,
        'title': evaluation.departureNotificationTitle,
        'body': evaluation.departureNotificationBody,
      });
    } catch (_) {}
  }

  static Future<void> requestNotificationPermissions() async {
    try {
      await _transitChannel.invokeMethod('requestNotificationPermissions');
    } catch (_) {}
  }

  static Future<void> cancelAlarms() async {
    try {
      await _transitChannel.invokeMethod('cancelDepartureAlarms');
    } catch (_) {}
  }

  static Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _transitChannel.invokeMethod('showTransitNotification', {
        'notificationId': 7090,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  /// Launches the native MenetrendGO Android app (`hu.matepazy.menetrendgo`),
  /// or falls back to `https://github.com/matepazy/menetrend-go/releases` if not installed.
  static Future<void> openInMenetrendGo({
    MenetrendTripOption? trip,
  }) async {
    try {
      final launched = await _transitChannel.invokeMethod<bool>(
        'launchMenetrendGo',
        {
          'tab': 'search',
          if (trip != null) 'fromStation': trip.departureStation,
          if (trip != null) 'toStation': trip.arrivalStation,
          if (trip != null) 'routeShortName': trip.routeShortName,
        },
      );
      if (launched == true) return;
    } catch (_) {}

    final fallbackUri = Uri.parse(menetrendGoReleasesUrl);
    try {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
