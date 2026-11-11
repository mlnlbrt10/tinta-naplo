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

/// A real stop/station returned by the transit service search.
class TransitStopResult {
  final String name;
  final double lat;
  final double lon;

  const TransitStopResult({
    required this.name,
    required this.lat,
    required this.lon,
  });
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
    this.walkToDestinationMinutes = 0,
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
    return 'A $depStr-es $vehicle legkésőbb $walkStartStr-kor indulnod kell ($effectiveWalkMinutes perc séta). Ne késs el!';
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

  /// Builds a [CommuteEvaluation] from real [trips] returned by the transit
  /// service. Returns `null` when no trip is available.
  static CommuteEvaluation? buildEvaluation({
    required List<MenetrendTripOption> trips,
    required bool isMorning,
    required Lesson? firstLesson,
    required Lesson? lastLesson,
    required UserProfilePrefs prefs,
    required int effectiveWalk,
    required DateTime now,
  }) {
    if (trips.isEmpty) return null;
    final allTrips = [...trips]
      ..sort((a, b) => a.scheduledDeparture.compareTo(b.scheduledDeparture));
    final firstStartLocal = firstLesson?.start.toLocal();

    MenetrendTripOption selectedTrip;
    if (isMorning) {
      final targetArrival = firstStartLocal;
      final arrivingOnTime = targetArrival == null
          ? <MenetrendTripOption>[]
          : allTrips
              .where((t) => !t.effectiveArrival.isAfter(targetArrival))
              .toList();
      selectedTrip =
          arrivingOnTime.isNotEmpty ? arrivingOnTime.last : allTrips.first;
    } else {
      final earliestLeaveTime =
          lastLesson != null ? lastLesson.end.toLocal() : now;
      final referenceTime =
          now.isAfter(earliestLeaveTime) ? now : earliestLeaveTime;
      final departingAfter = allTrips.where((t) {
        final walkLeave =
            t.effectiveDeparture.subtract(Duration(minutes: effectiveWalk));
        return !walkLeave
            .isBefore(referenceTime.subtract(const Duration(minutes: 5)));
      }).toList();
      selectedTrip =
          departingAfter.isNotEmpty ? departingAfter.first : allTrips.last;
    }

    return CommuteEvaluation(
      isMorningMode: isMorning,
      targetLesson: isMorning ? firstLesson : lastLesson,
      targetPeriodNumber: firstLesson?.lessonNumber ?? 1,
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

  static final Map<String, ({double lat, double lon})> _coordCache = {};

  /// Searches real stops/stations by name in the MÁVPlusz OTP2 backend.
  Future<List<TransitStopResult>> searchStops(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final escaped = jsonEncode(q);
    final response = await _http
        .post(
          Uri.parse('$mavPluszBaseUrl/index/graphql'),
          headers: mavHeaders,
          body: jsonEncode({
            'query':
                '{ stops(name: $escaped) { gtfsId name lat lon } }',
          }),
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) return const [];
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final stops = decoded['data']?['stops'];
    if (stops is! List) return const [];
    final seen = <String>{};
    final out = <TransitStopResult>[];
    for (final st in stops) {
      if (st is! Map) continue;
      final name = (st['name'] ?? '').toString();
      final lat = (st['lat'] as num?)?.toDouble();
      final lon = (st['lon'] as num?)?.toDouble();
      if (name.isEmpty || lat == null || lon == null) continue;
      if (!seen.add(name)) continue;
      _coordCache[name] = (lat: lat, lon: lon);
      out.add(TransitStopResult(name: name, lat: lat, lon: lon));
    }
    return out;
  }

  Future<({double lat, double lon})?> _resolve(String name) async {
    final cached = _coordCache[name];
    if (cached != null) return cached;
    final results = await searchStops(name);
    if (results.isEmpty) return null;
    final exact = results.firstWhere(
      (r) => r.name.toLowerCase() == name.toLowerCase(),
      orElse: () => results.first,
    );
    return (lat: exact.lat, lon: exact.lon);
  }

  static MenetrendTransportMode _modeFor(Map leg) {
    final mode = (leg['mode'] ?? '').toString().toUpperCase();
    if (mode == 'RAIL' || mode == 'SUBWAY' || mode == 'TRAM') {
      return MenetrendTransportMode.rail;
    }
    final agency =
        (leg['route']?['agency']?['name'] ?? '').toString().toLowerCase();
    if (agency.contains('volán') || agency.contains('volan')) {
      return MenetrendTransportMode.coach;
    }
    return MenetrendTransportMode.localBus;
  }

  /// Fetches the real commute from the transit service (MÁVPlusz OTP2).
  /// Returns `null` when stops are not configured, not found or no itinerary
  /// exists. Never fabricates routes.
  Future<CommuteEvaluation?> fetchLiveCommuteEvaluation({
    required List<Lesson> todaysLessons,
    required UserProfilePrefs prefs,
    DateTime? nowOverride,
  }) async {
    if (!prefs.transitConfigured) return null;
    final now = nowOverride ?? DateTime.now();
    final activeLessons = todaysLessons
        .where((l) => !isLessonCancelledStatic(l))
        .toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
    final firstLesson = activeLessons.isNotEmpty ? activeLessons.first : null;
    final lastLesson = activeLessons.isNotEmpty ? activeLessons.last : null;
    final firstStartLocal = firstLesson?.start.toLocal();
    final isMorning = firstStartLocal != null
        ? now.isBefore(firstStartLocal.add(const Duration(minutes: 30)))
        : now.hour < 12;

    final effectiveWalk = calculateEffectiveWalkingMinutes(
      baseWalkingMinutes: prefs.walkingDurationMinutes,
      walkingSpeedKmh: prefs.walkingSpeedKmh,
    );

    final fromName =
        isMorning ? prefs.transitHomeStation : prefs.transitSchoolStation;
    final toName =
        isMorning ? prefs.transitSchoolStation : prefs.transitHomeStation;

    try {
      final from = await _resolve(fromName);
      final to = await _resolve(toName);
      if (from == null || to == null) return null;

      final DateTime refTime;
      final bool arriveBy;
      if (isMorning) {
        arriveBy = firstStartLocal != null;
        refTime = firstStartLocal ?? now;
      } else {
        arriveBy = false;
        final lastEnd = lastLesson?.end.toLocal() ?? now;
        refTime = now.isAfter(lastEnd) ? now : lastEnd;
      }

      final query = '''
      {
        plan(
          from: {lat: ${from.lat}, lon: ${from.lon}},
          to: {lat: ${to.lat}, lon: ${to.lon}},
          date: "${DateFormat('yyyy-MM-dd').format(refTime)}",
          time: "${DateFormat('HH:mm').format(refTime)}",
          arriveBy: $arriveBy,
          numItineraries: 6
        ) {
          itineraries {
            startTime
            endTime
            legs {
              mode
              startTime
              endTime
              departureDelay
              from { name stop { platformCode } }
              to { name stop { platformCode } }
              route { shortName longName agency { name } }
              intermediateStops { name }
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
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final itineraries = decoded['data']?['plan']?['itineraries'];
      if (itineraries is! List) return null;

      DateTime ms(dynamic v) => DateTime.fromMillisecondsSinceEpoch(
            (v as num).toInt(),
          );

      final trips = <MenetrendTripOption>[];
      for (final it in itineraries) {
        if (it is! Map) continue;
        final legs = (it['legs'] as List?)
                ?.whereType<Map>()
                .where((l) => l['mode'] != 'WALK')
                .toList() ??
            const [];
        if (legs.isEmpty) continue;
        final firstLeg = legs.first;
        final mode = _modeFor(firstLeg);
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
        final shortNames = legs
            .map((l) => (l['route']?['shortName'] ??
                    l['route']?['longName'] ??
                    '')
                .toString())
            .where((n) => n.isNotEmpty)
            .join(' → ');
        final stops = <MenetrendStop>[
          for (final st in (firstLeg['intermediateStops'] as List? ?? const []))
            if (st is Map && st['name'] != null)
              MenetrendStop(name: st['name'].toString()),
        ];
        final delaySec = (firstLeg['departureDelay'] as num?)?.toInt() ?? 0;
        trips.add(
          MenetrendTripOption(
            routeShortName: shortNames.isEmpty ? 'Járat' : shortNames,
            routeLongName:
                (firstLeg['route']?['longName'] ?? '').toString(),
            mode: mode,
            departureStation:
                (firstLeg['from']?['name'] ?? fromName).toString(),
            arrivalStation: toName,
            scheduledDeparture: ms(firstLeg['startTime']),
            scheduledArrival: ms(it['endTime']),
            delayMinutes: (delaySec / 60).round().clamp(0, 180),
            platformCode:
                firstLeg['from']?['stop']?['platformCode']?.toString(),
            arrivalPlatformCode:
                (legs.last['to']?['stop']?['platformCode'])?.toString(),
            intermediateStops: stops,
            walkToStationMinutes: effectiveWalk,
            walkToDestinationMinutes: 0,
          ),
        );
      }

      return buildEvaluation(
        trips: trips,
        isMorning: isMorning,
        firstLesson: firstLesson,
        lastLesson: lastLesson,
        prefs: prefs,
        effectiveWalk: effectiveWalk,
        now: now,
      );
    } catch (_) {
      return null;
    }
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
