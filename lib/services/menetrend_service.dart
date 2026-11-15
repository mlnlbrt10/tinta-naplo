import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/html_sanitizer.dart';
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
        return 'Helyközi / Távolsági busz (Volánbusz)';
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

/// One vehicle segment of a (possibly multi-leg) trip.
class MenetrendLeg {
  final String routeShortName;
  final MenetrendTransportMode mode;
  final String fromName;
  final String toName;
  final DateTime departure;
  final DateTime arrival;
  final String? platformCode;
  final int delayMinutes;
  final int arrivalDelayMinutes;
  final String tripShortName;
  final String headsign;

  const MenetrendLeg({
    required this.routeShortName,
    required this.mode,
    required this.fromName,
    required this.toName,
    required this.departure,
    required this.arrival,
    this.platformCode,
    this.delayMinutes = 0,
    this.arrivalDelayMinutes = 0,
    this.tripShortName = '',
    this.headsign = '',
  });

  DateTime get effectiveDeparture =>
      departure.add(Duration(minutes: delayMinutes));

  DateTime get effectiveArrival => arrival.add(
        Duration(
          minutes: arrivalDelayMinutes > 0 ? arrivalDelayMinutes : delayMinutes,
        ),
      );
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
  final int? arrivalDelayMinutes;
  final bool isCancelled;
  final String? platformCode;
  final String? arrivalPlatformCode;
  final List<MenetrendStop> intermediateStops;
  final int walkToStationMinutes;
  final int walkToDestinationMinutes;
  final bool isFavorite;
  final List<MenetrendLeg> legs;
  final double? fromLat;
  final double? fromLon;
  final double? toLat;
  final double? toLon;
  final String? destinationLabel;
  final int? baseWalkToStationSeconds;
  final int? baseWalkToDestinationSeconds;
  final String tripId;

  const MenetrendTripOption({
    required this.routeShortName,
    required this.routeLongName,
    required this.mode,
    required this.departureStation,
    required this.arrivalStation,
    required this.scheduledDeparture,
    required this.scheduledArrival,
    this.delayMinutes = 0,
    this.arrivalDelayMinutes,
    this.isCancelled = false,
    this.platformCode,
    this.arrivalPlatformCode,
    this.intermediateStops = const [],
    required this.walkToStationMinutes,
    this.walkToDestinationMinutes = 0,
    this.isFavorite = false,
    this.legs = const [],
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
    this.destinationLabel,
    this.baseWalkToStationSeconds,
    this.baseWalkToDestinationSeconds,
    this.tripId = '',
  });

  /// Route name guaranteed to be stripped of MÁV GTFS font glyphs (e.g. "Ű").
  String get safeRouteShortName => MenetrendService.sanitizeTransitLineName(
        rawShortName: routeShortName,
        rawLongName: routeLongName,
        rawTripShortName:
            legs.isNotEmpty ? legs.first.tripShortName : '',
        mode: mode,
      );

  DateTime get effectiveDeparture =>
      scheduledDeparture.add(Duration(minutes: delayMinutes));

  DateTime get effectiveArrival => scheduledArrival.add(
        Duration(minutes: arrivalDelayMinutes ?? delayMinutes),
      );

  /// Official scheduled arrival at the final destination (vehicle alighting
  /// time at [arrivalStation] + [walkToDestinationMinutes] walk leg).
  DateTime get scheduledDestinationArrival =>
      scheduledArrival.add(Duration(minutes: walkToDestinationMinutes));

  /// Delay-adjusted estimated arrival at the final destination.
  DateTime get effectiveDestinationArrival =>
      effectiveArrival.add(Duration(minutes: walkToDestinationMinutes));

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

  String get destinationArrivalTimeFormatted =>
      DateFormat('HH:mm').format(scheduledDestinationArrival);

  String get effectiveDestinationArrivalTimeFormatted =>
      DateFormat('HH:mm').format(effectiveDestinationArrival);

  String get favoriteBadgeText =>
      '★ Kedvenc járat: $safeRouteShortName ($departureTimeFormatted)';

  MenetrendTripOption copyWith({
    int? delayMinutes,
    int? arrivalDelayMinutes,
    bool? isCancelled,
    bool? isFavorite,
    int? walkToStationMinutes,
    int? walkToDestinationMinutes,
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
      arrivalDelayMinutes: arrivalDelayMinutes ?? this.arrivalDelayMinutes,
      isCancelled: isCancelled ?? this.isCancelled,
      platformCode: platformCode,
      arrivalPlatformCode: arrivalPlatformCode,
      intermediateStops: intermediateStops,
      walkToStationMinutes: walkToStationMinutes ?? this.walkToStationMinutes,
      walkToDestinationMinutes:
          walkToDestinationMinutes ?? this.walkToDestinationMinutes,
      isFavorite: isFavorite ?? this.isFavorite,
      legs: legs,
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
      destinationLabel: destinationLabel,
      baseWalkToStationSeconds: baseWalkToStationSeconds,
      baseWalkToDestinationSeconds: baseWalkToDestinationSeconds,
      tripId: tripId,
    );
  }

  /// Synchronously recalculates walking durations and favorite match against
  /// updated [prefs] (e.g. immediately when walking speed changes in Settings).
  MenetrendTripOption recalculateForPrefs(
    UserProfilePrefs prefs, {
    required bool isMorning,
  }) {
    final speed = MenetrendService.normalizeWalkingSpeed(prefs.walkingSpeedKmh);
    final lastMode = legs.isNotEmpty ? legs.last.mode : mode;
    final fromTrain = mode == MenetrendTransportMode.rail;
    final toTrain = lastMode == MenetrendTransportMode.rail;

    int calcFromBaseMinutes(int baseMins) {
      if (baseMins <= 0) return 0;
      return MenetrendService.calculateEffectiveWalkingMinutes(
        baseWalkingMinutes: baseMins,
        walkingSpeedKmh: speed,
      );
    }

    int calcWalk({
      required int? baseSeconds,
      required int prefsBaseMinutes,
      required int fallbackCurrent,
    }) {
      if (baseSeconds != null) {
        if (baseSeconds == 0) return 0;
        return MenetrendService.calculateWalkMinutesFromSeconds(
          baseSeconds,
          speed,
        );
      }
      if (prefsBaseMinutes > 0) {
        return calcFromBaseMinutes(prefsBaseMinutes);
      }
      return fallbackCurrent;
    }

    final fromExact = isMorning
        ? (prefs.homeAddressLat != null && prefs.homeAddressLon != null)
        : (prefs.schoolAddressLat != null && prefs.schoolAddressLon != null);
    final toExact = isMorning
        ? (prefs.schoolAddressLat != null && prefs.schoolAddressLon != null)
        : (prefs.homeAddressLat != null && prefs.homeAddressLon != null);

    final prefsFromBase = fromExact
        ? 0
        : (isMorning
            ? (fromTrain ? prefs.walkHomeToTrainMinutes : prefs.walkHomeToBusMinutes)
            : (fromTrain ? prefs.walkSchoolToTrainMinutes : prefs.walkSchoolToBusMinutes));
    final prefsToBase = toExact
        ? 0
        : (isMorning
            ? (toTrain ? prefs.walkSchoolToTrainMinutes : prefs.walkSchoolToBusMinutes)
            : (toTrain ? prefs.walkHomeToTrainMinutes : prefs.walkHomeToBusMinutes));

    final nextWalkFrom = calcWalk(
      baseSeconds: baseWalkToStationSeconds,
      prefsBaseMinutes: prefsFromBase,
      fallbackCurrent: walkToStationMinutes,
    );
    final nextWalkTo = calcWalk(
      baseSeconds: baseWalkToDestinationSeconds,
      prefsBaseMinutes: prefsToBase,
      fallbackCurrent: walkToDestinationMinutes,
    );

    final dayPlan = prefs.commutePlanForWeekday(scheduledDeparture.weekday);
    final dayLine = ((isMorning
                ? dayPlan['morningLine']
                : dayPlan['afternoonLine']) ??
            dayPlan['line'] ??
            '')
        .toString()
        .trim();
    final matchedFav = MenetrendService._matchesFavorite(
      safeRouteShortName,
      scheduledDeparture,
      [
        dayLine,
        if (dayLine.isEmpty) ...[
          prefs.favoriteRoute1stPeriod,
          prefs.favoriteRoute2ndPeriod,
        ],
      ],
    );

    return copyWith(
      walkToStationMinutes: nextWalkFrom,
      walkToDestinationMinutes: nextWalkTo,
      isFavorite: matchedFav,
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

  /// Latest time the user must step out the door to walk to the boarding
  /// station in time for the **official scheduled departure** (even when a
  /// live delay is reported, in case the vehicle catches up).
  DateTime get walkDepartureTime => recommendedTrip.scheduledDeparture
      .subtract(Duration(minutes: effectiveWalkMinutes + 4));

  /// Exact alarm time factoring in both walking time and alert buffer:
  /// `[Official Scheduled Departure] - [Walking Duration] - [Alert Buffer]`.
  DateTime get alarmTriggerTime => recommendedTrip.scheduledDeparture.subtract(
        Duration(minutes: effectiveWalkMinutes + alertBufferMinutes),
      );

  /// Latest walking start time (`[Scheduled Departure] - [Walking Duration] - [Buffer - 1]`).
  DateTime get latestWalkStartTime => recommendedTrip.scheduledDeparture
      .subtract(Duration(minutes: effectiveWalkMinutes + (alertBufferMinutes > 1 ? 4 : 0)));

  int get minutesUntilDeparture {
    final diff = recommendedTrip.scheduledDeparture.difference(now).inMinutes;
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
      ? '⚠️ Kimaradó járat (${recommendedTrip.safeRouteShortName})!'
      : '⚠️ Késik a járatod (+${recommendedTrip.delayMinutes} perc)!';

  String get delayNotificationBody => recommendedTrip.isCancelled
      ? 'A(z) ${recommendedTrip.departureTimeFormatted}-es ${recommendedTrip.safeRouteShortName} járat kimarad. Nézd meg a következő indulást!'
      : '⚠️ Késik a járatod (+${recommendedTrip.delayMinutes} perc)! Menetrend szerinti ind.: ${recommendedTrip.departureTimeFormatted}, becsült ind.: ${recommendedTrip.effectiveDepartureTimeFormatted}.';

  /// Synchronously recalculates walking durations, buffer, and favorite status
  /// for [prefs] without performing network calls or firing notifications.
  CommuteEvaluation recalculateForPrefs(
    UserProfilePrefs prefs, {
    DateTime? now,
  }) {
    final updatedRec = recommendedTrip.recalculateForPrefs(
      prefs,
      isMorning: isMorningMode,
    );
    final updatedAlts = [
      for (final trip in alternatives)
        trip.recalculateForPrefs(prefs, isMorning: isMorningMode),
    ];
    return CommuteEvaluation(
      isMorningMode: isMorningMode,
      targetLesson: targetLesson,
      targetPeriodNumber: targetPeriodNumber,
      recommendedTrip: updatedRec,
      alternatives: updatedAlts,
      effectiveWalkMinutes: updatedRec.walkToStationMinutes,
      alertBufferMinutes: prefs.transitAlertBufferMinutes,
      now: now ?? this.now,
    );
  }
}

/// Service integrating MenetrendGO (MÁVPlusz OTP2 GraphQL & GTFS schedule engine)
/// with Tinta Napló's live timetable, departure alarms, and native Android intent deep-linking.
class MenetrendService {
  static const String mavPluszBaseUrl =
      'https://mavplusz.hu/otp2-backend/otp/routers/default';
  static const String menetrendGoPackage = 'hu.matepazy.menetrendgo';
  static const String menetrendGoReleasesUrl =
      'https://github.com/matepazy/menetrend-go/releases';
  static const String lastNotifiedDelayPrefsKey =
      'menetrend_last_notified_delay_v1';
  static const String notifiedDelayKeysPrefsKey =
      'menetrend_notified_delay_keys_v1';

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
        'User-Agent': 'MenetrendGO/1.1.0 (Android)',
      };

  /// Snaps any stored walking speed to one of the three supported presets:
  /// `4.0` Lassú, `5.0` Normál, `6.0` Gyors (km/h).
  static double normalizeWalkingSpeed(double kmh) {
    if (kmh <= 4.4) return 4.0;
    if (kmh < 5.5) return 5.0;
    return 6.0;
  }

  /// Human readable label for a walking speed preset.
  static String walkingSpeedLabel(double kmh) {
    switch (normalizeWalkingSpeed(kmh).round()) {
      case 4:
        return 'Lassú (4 km/h)';
      case 6:
        return 'Gyors (6 km/h)';
      default:
        return 'Normál (5 km/h)';
    }
  }

  /// Computes the effective walking time in minutes adjusted for the user's
  /// selected walking speed preset (4 / 5 / 6 km/h).
  static int calculateEffectiveWalkingMinutes({
    required int baseWalkingMinutes,
    required double walkingSpeedKmh,
  }) {
    if (baseWalkingMinutes <= 0) return 0;
    final speed = normalizeWalkingSpeed(walkingSpeedKmh);
    final scaled = (baseWalkingMinutes * (5.0 / speed)).round();
    return scaled.clamp(1, 90);
  }

  /// Converts a raw OTP walking leg duration in seconds to scaled minutes.
  static int calculateWalkMinutesFromSeconds(
    int seconds,
    double walkingSpeedKmh,
  ) {
    if (seconds < 30) return 0;
    final speed = normalizeWalkingSpeed(walkingSpeedKmh);
    final scaled = ((seconds / 60.0) * (5.0 / speed)).round();
    return scaled.clamp(1, 90);
  }

  /// Returns `true` when [rawShortName] is a MÁV GTFS icon-font glyph
  /// (e.g. `<span class="MNR2007">&#368;</span>`, `"Ű"`, `"ſ"`, `"ǚ"`, `"Ü"`)
  /// or another non-alphanumeric symbol rather than a human-readable line code.
  static bool isIconFontGlyph(
    String rawShortName, {
    required MenetrendTransportMode mode,
  }) {
    if (rawShortName.toLowerCase().contains('mnr')) return true;
    final cleaned = HtmlSanitizer.clean(rawShortName).trim();
    if (cleaned.isEmpty) return true;
    if (cleaned.runes.any((r) => r >= 0xE000 && r <= 0xF8FF || r == 0xFFFD)) {
      return true;
    }
    if (cleaned.runes.length == 1) {
      final r = cleaned.runes.first;
      final isAsciiAlnum = (r >= 48 && r <= 57) ||
          (r >= 65 && r <= 90) ||
          (r >= 97 && r <= 122);
      if (!isAsciiAlnum) return true;
      if (mode == MenetrendTransportMode.rail && !(r >= 48 && r <= 57)) {
        return true;
      }
    }
    return false;
  }

  /// Strips MÁV icon-font HTML/glyph artifacts from `route.longName`.
  static String sanitizeRouteLongName(String rawLongName) {
    if (rawLongName.toLowerCase().contains('mnr')) return '';
    final cleaned = HtmlSanitizer.clean(rawLongName).trim();
    if (cleaned.isEmpty) return '';
    if (isIconFontGlyph(cleaned, mode: MenetrendTransportMode.rail)) return '';
    return cleaned;
  }

  static final RegExp _trainNumberPattern = RegExp(r'\b(\d{3,5})\b');
  static final RegExp _lineCodePattern =
      RegExp(r'\b([SGZ]\d{1,3}|IC|EC|EN|IR|Ex|rjx)\b', caseSensitive: false);

  /// Resolves a clean human-readable transit designation from OTP route & trip
  /// metadata, completely eliminating MÁV MNR2007 icon glyphs like `"Ű"`.
  static String sanitizeTransitLineName({
    required String rawShortName,
    String rawLongName = '',
    String rawTripShortName = '',
    String headsign = '',
    required MenetrendTransportMode mode,
  }) {
    if (!isIconFontGlyph(rawShortName, mode: mode)) {
      return HtmlSanitizer.clean(rawShortName).trim();
    }

    final cleanLong = sanitizeRouteLongName(rawLongName);
    final isGenericRailWord = RegExp(
      r'^(személyvonat|gyorsvonat|sebesvonat|expresszvonat|intercity|eurocity|interr[eé]gi[oó]|vonat|passenger train|train)$',
      caseSensitive: false,
    ).hasMatch(cleanLong);
    if (cleanLong.isNotEmpty && !isGenericRailWord) {
      // Handle multi-train GTFS labels like "S 9792/9793/9794..."
      if (cleanLong.contains('/') && cleanLong.length > 16) {
        final match = RegExp(r'^([A-Za-z]{1,3})\s*(\d+)').firstMatch(cleanLong);
        if (match != null) {
          return '${match.group(1)}${match.group(2)}';
        }
      }
      if (!cleanLong.contains(' - ') && cleanLong.length <= 18) {
        return cleanLong;
      }
      final extractedCode = _lineCodePattern.firstMatch(cleanLong)?.group(1);
      if (extractedCode != null && extractedCode.isNotEmpty) {
        return extractedCode.toUpperCase();
      }
    }

    final cleanTrip = HtmlSanitizer.clean(rawTripShortName).trim();
    final lowerTrip = cleanTrip.toLowerCase();
    final lowerLong = cleanLong.toLowerCase();
    final trainNum = _trainNumberPattern.firstMatch(cleanTrip)?.group(1);

    if (mode == MenetrendTransportMode.rail) {
      final lineInTrip = _lineCodePattern.firstMatch(cleanTrip)?.group(1);
      if (lineInTrip != null &&
          RegExp(r'^[sgz]\d', caseSensitive: false).hasMatch(lineInTrip)) {
        return lineInTrip.toUpperCase();
      }

      String category = 'Személyvonat';
      if (lowerTrip.contains('intercity') || lowerLong.contains('intercity')) {
        category = 'InterCity';
      } else if (lowerTrip.contains('eurocity') || lowerLong.contains('eurocity')) {
        category = 'EuroCity';
      } else if (lowerTrip.contains('interrégió') ||
          lowerTrip.contains('interregio') ||
          lowerLong.contains('interrégió')) {
        category = 'InterRégió';
      } else if (lowerTrip.contains('express') || lowerLong.contains('express')) {
        category = 'Expresszvonat';
      } else if (lowerTrip.contains('sebes') ||
          lowerTrip.contains('fast train') ||
          lowerLong.contains('sebes')) {
        category = 'Sebesvonat';
      } else if (lowerTrip.contains('gyors') || lowerLong.contains('gyors')) {
        category = 'Gyorsvonat';
      } else if (lowerTrip.contains('passenger') ||
          lowerTrip.contains('személy') ||
          cleanTrip.isNotEmpty) {
        category = 'Személyvonat';
      } else {
        category = 'Vonat';
      }

      return trainNum != null ? '$category $trainNum' : category;
    }

    if (mode == MenetrendTransportMode.coach) {
      if (cleanLong.isNotEmpty && cleanLong.length <= 20) return cleanLong;
      return 'Helyközi busz';
    }
    if (mode == MenetrendTransportMode.localBus) {
      if (cleanLong.isNotEmpty && cleanLong.length <= 16) return cleanLong;
      return 'Helyi járat';
    }
    return cleanLong.isNotEmpty ? cleanLong : 'Járat';
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
              .where((t) => !t.effectiveDestinationArrival.isAfter(targetArrival))
              .toList();
      selectedTrip =
          arrivingOnTime.isNotEmpty ? arrivingOnTime.last : allTrips.first;
    } else {
      final earliestLeaveTime =
          lastLesson != null ? lastLesson.end.toLocal() : now;
      final referenceTime =
          now.isAfter(earliestLeaveTime) ? now : earliestLeaveTime;
      final departingAfter = allTrips.where((t) {
        final walkLeave = t.scheduledDeparture
            .subtract(Duration(minutes: t.walkToStationMinutes));
        return !walkLeave
            .isBefore(referenceTime.subtract(const Duration(minutes: 5)));
      }).toList();
      selectedTrip =
          departingAfter.isNotEmpty ? departingAfter.first : allTrips.last;
    }

    final favorite = allTrips.where((t) => t.isFavorite).toList();
    if (favorite.isNotEmpty && !favorite.contains(selectedTrip)) {
      if (isMorning && firstStartLocal != null) {
        final onTime = favorite
            .where((t) => !t.effectiveDestinationArrival.isAfter(firstStartLocal))
            .toList();
        if (onTime.isNotEmpty) selectedTrip = onTime.last;
      } else if (!isMorning) {
        selectedTrip = favorite.first;
      }
    }

    return CommuteEvaluation(
      isMorningMode: isMorning,
      targetLesson: isMorning ? firstLesson : lastLesson,
      targetPeriodNumber: firstLesson?.lessonNumber ?? 1,
      recommendedTrip: selectedTrip,
      alternatives: allTrips,
      effectiveWalkMinutes: selectedTrip.walkToStationMinutes,
      alertBufferMinutes: prefs.transitAlertBufferMinutes,
      now: now,
    );
  }

  /// Smart visibility window:
  /// * morning: from 2 h before the first lesson until it starts;
  /// * afternoon: from 30 min before the last lesson ends until 1 h after.
  /// Returns `true` (morning), `false` (afternoon) or `null` when hidden.
  static bool? commuteWindow({
    required DateTime now,
    required DateTime? firstStart,
    required DateTime? lastEnd,
  }) {
    if (firstStart != null &&
        !now.isBefore(firstStart.subtract(const Duration(hours: 2))) &&
        now.isBefore(firstStart)) {
      return true;
    }
    if (lastEnd != null &&
        !now.isBefore(lastEnd.subtract(const Duration(minutes: 30))) &&
        !now.isAfter(lastEnd.add(const Duration(hours: 1)))) {
      return false;
    }
    return null;
  }

  /// A trip is catchable when the user can still walk to the boarding point
  /// before the scheduled or estimated departure.
  static bool isTripCatchable(MenetrendTripOption t, DateTime now) {
    if (t.isCancelled) return false;
    final mustLeaveBy = t.effectiveDeparture
        .subtract(Duration(minutes: t.walkToStationMinutes));
    return !mustLeaveBy.isBefore(now);
  }

  static bool _matchesFavorite(
    String routeName,
    DateTime departure,
    List<String> prefs,
  ) {
    final time = DateFormat('HH:mm').format(departure);
    for (final pref in prefs) {
      for (final token in pref.split(RegExp(r'[\/,;]'))) {
        final t = token.trim().toLowerCase();
        if (t.isEmpty) continue;
        if (time == t || routeName.toLowerCase().contains(t)) return true;
      }
    }
    return false;
  }

  static bool _isLocalBusLeg(Map leg) {
    if ((leg['mode'] ?? '').toString().toUpperCase() != 'BUS') return false;
    final short = (leg['route']?['shortName'] ?? '').toString();
    return short.replaceAll(RegExp(r'\D'), '').length <= 2;
  }

  static final Map<String, ({double lat, double lon})> _addressCache = {};

  /// Estimates walking duration in minutes between two geographic coordinates
  /// using a 1.28 urban street detour factor and the user's walking speed preset.
  static int estimateWalkingMinutesBetween({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
    required double walkingSpeedKmh,
  }) {
    const r = 6371.0; // km
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final streetKm = r * c * 1.28;
    final speed = normalizeWalkingSpeed(walkingSpeedKmh);
    final mins = ((streetKm / speed) * 60.0).ceil();
    return mins.clamp(1, 90);
  }

  /// Live geocoding autocomplete via OpenStreetMap Nominatim (with Photon fallback).
  Future<List<TransitStopResult>> searchAddresses(String query) async {
    final q = query.trim();
    if (q.length < 3) return const [];
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'json',
        'limit': '6',
        'countrycodes': 'hu',
        'addressdetails': '1',
      });
      final response = await _http.get(uri, headers: const {
        'User-Agent': 'TintaNaplo-Android/1.1.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is List && decoded.isNotEmpty) {
          final seen = <String>{};
          final out = <TransitStopResult>[];
          for (final item in decoded) {
            if (item is! Map) continue;
            final rawDisplay = (item['display_name'] ?? '').toString().trim();
            final lat = double.tryParse('${item['lat']}');
            final lon = double.tryParse('${item['lon']}');
            if (rawDisplay.isEmpty || lat == null || lon == null) continue;
            final parts = rawDisplay
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty && s.toLowerCase() != 'magyarország')
                .take(4)
                .toList();
            final label = parts.isNotEmpty ? parts.join(', ') : rawDisplay;
            if (!seen.add(label)) continue;
            _addressCache[label.toLowerCase()] = (lat: lat, lon: lon);
            out.add(TransitStopResult(name: label, lat: lat, lon: lon));
          }
          if (out.isNotEmpty) return out;
        }
      }
    } catch (_) {
      // Fallback to Photon below
    }

    try {
      final photonUri = Uri.https('photon.komoot.io', '/api/', {
        'q': q,
        'limit': '6',
      });
      final res = await _http
          .get(photonUri, headers: const {'User-Agent': 'TintaNaplo-Android/1.1.0'})
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final features = decoded['features'];
        if (features is List) {
          final out = <TransitStopResult>[];
          final seen = <String>{};
          for (final f in features) {
            if (f is! Map) continue;
            final props = f['properties'] as Map? ?? const {};
            final coords = f['geometry']?['coordinates'] as List?;
            if (coords == null || coords.length < 2) continue;
            final lon = (coords[0] as num?)?.toDouble();
            final lat = (coords[1] as num?)?.toDouble();
            if (lat == null || lon == null) continue;
            final city = (props['city'] ?? props['locality'] ?? '').toString();
            final street = (props['street'] ?? props['name'] ?? '').toString();
            final house = (props['housenumber'] ?? '').toString();
            final label = [
              if (city.isNotEmpty) city,
              if (street.isNotEmpty)
                house.isNotEmpty ? '$street $house.' : street,
            ].join(', ');
            if (label.isEmpty || !seen.add(label)) continue;
            _addressCache[label.toLowerCase()] = (lat: lat, lon: lon);
            out.add(TransitStopResult(name: label, lat: lat, lon: lon));
          }
          return out;
        }
      }
    } catch (_) {}
    return const [];
  }

  /// Geocodes an exact street address (Nominatim / OpenStreetMap).
  Future<({double lat, double lon})?> _geocodeAddress(String address) async {
    final key = address.trim().toLowerCase();
    final cached = _addressCache[key];
    if (cached != null) return cached;
    final list = await searchAddresses(address);
    if (list.isNotEmpty) {
      final first = list.first;
      return _addressCache[key] = (lat: first.lat, lon: first.lon);
    }
    return null;
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
    // Regional (Volánbusz) buses, e.g. 1215 / 8093, are intercity coaches.
    return MenetrendTransportMode.coach;
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

    // Smart visibility window: outside of it the card stays hidden.
    final window = commuteWindow(
      now: now,
      firstStart: firstStartLocal,
      lastEnd: lastLesson?.end.toLocal(),
    );
    if (window == null) return null;
    final isMorning = window;

    final effectiveWalk = calculateEffectiveWalkingMinutes(
      baseWalkingMinutes: prefs.walkingDurationMinutes,
      walkingSpeedKmh: prefs.walkingSpeedKmh,
    );

    final homeExact = prefs.homeAddress.isNotEmpty;
    final schoolExact = prefs.schoolAddress.isNotEmpty;
    final fromExact = isMorning ? homeExact : schoolExact;
    final toExact = isMorning ? schoolExact : homeExact;

    final fromStopName =
        isMorning ? prefs.primaryHomeStop : prefs.primarySchoolStop;
    final toStopName =
        isMorning ? prefs.primarySchoolStop : prefs.primaryHomeStop;

    final fromName = isMorning
        ? (homeExact ? prefs.homeAddress : fromStopName)
        : (schoolExact ? prefs.schoolAddress : fromStopName);
    final toName = isMorning
        ? (schoolExact ? prefs.schoolAddress : toStopName)
        : (homeExact ? prefs.homeAddress : toStopName);

    final dayPlan = prefs.commutePlanForWeekday(now.weekday);
    final rawDirLine = isMorning
        ? (dayPlan['morningLine'] ?? dayPlan['line'])
        : (dayPlan['afternoonLine'] ?? dayPlan['line']);
    final dayLine = (rawDirLine as String?)?.trim() ?? '';
    final rawDirLocalBus = isMorning
        ? (dayPlan['morningUseLocalBus'] ?? dayPlan['useLocalBus'])
        : (dayPlan['afternoonUseLocalBus'] ?? dayPlan['useLocalBus']);
    final dayUseLocalBus = rawDirLocalBus != false;

    try {
      Future<({double lat, double lon})?> resolveOrigin() async {
        if (isMorning &&
            prefs.homeAddressLat != null &&
            prefs.homeAddressLon != null) {
          return (lat: prefs.homeAddressLat!, lon: prefs.homeAddressLon!);
        }
        if (!isMorning &&
            prefs.schoolAddressLat != null &&
            prefs.schoolAddressLon != null) {
          return (lat: prefs.schoolAddressLat!, lon: prefs.schoolAddressLon!);
        }
        return fromExact
            ? await _geocodeAddress(fromName)
            : await _resolve(fromName);
      }

      Future<({double lat, double lon})?> resolveDestination() async {
        if (isMorning &&
            prefs.schoolAddressLat != null &&
            prefs.schoolAddressLon != null) {
          return (lat: prefs.schoolAddressLat!, lon: prefs.schoolAddressLon!);
        }
        if (!isMorning &&
            prefs.homeAddressLat != null &&
            prefs.homeAddressLon != null) {
          return (lat: prefs.homeAddressLat!, lon: prefs.homeAddressLon!);
        }
        return toExact ? await _geocodeAddress(toName) : await _resolve(toName);
      }

      final from = await resolveOrigin();
      final to = await resolveDestination();
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
              arrivalDelay
              realTime
              headsign
              start { scheduledTime estimated { time delay } }
              end { scheduledTime estimated { time delay } }
              from { name stop { platformCode } }
              to { name stop { platformCode } }
              route { shortName longName agency { name } }
              trip { gtfsId tripShortName }
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

      return parseItinerariesForCommute(
        itineraries: itineraries,
        isMorning: isMorning,
        firstLesson: firstLesson,
        lastLesson: lastLesson,
        prefs: prefs,
        effectiveWalk: effectiveWalk,
        fromName: fromName,
        toName: toName,
        fromExact: fromExact,
        toExact: toExact,
        fromLat: from.lat,
        fromLon: from.lon,
        toLat: to.lat,
        toLon: to.lon,
        dayLine: dayLine,
        dayUseLocalBus: dayUseLocalBus,
        now: now,
      );
    } catch (_) {
      return null;
    }
  }

  static int? _parseIsoDurationSeconds(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    final match = RegExp(
      r'^(-?)PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$',
      caseSensitive: false,
    ).firstMatch(s);
    if (match == null) return null;
    final neg = match.group(1) == '-';
    final h = int.tryParse(match.group(2) ?? '0') ?? 0;
    final m = int.tryParse(match.group(3) ?? '0') ?? 0;
    final sec = double.tryParse(match.group(4) ?? '0')?.round() ?? 0;
    final total = h * 3600 + m * 60 + sec;
    return neg ? -total : total;
  }

  static ({DateTime scheduled, int delayMinutes}) _parseLegTimestamp({
    required Map leg,
    required String endpointKey,
    required String msKey,
    required String delayKey,
  }) {
    final msRaw = leg[msKey];
    final msTime = msRaw is num
        ? DateTime.fromMillisecondsSinceEpoch(msRaw.toInt()).toLocal()
        : DateTime.now();

    final endpointMap = leg[endpointKey];
    final scheduledStr =
        endpointMap is Map ? endpointMap['scheduledTime']?.toString() : null;
    final parsedScheduled = scheduledStr != null
        ? DateTime.tryParse(scheduledStr)?.toLocal()
        : null;

    final estimatedMap =
        endpointMap is Map ? endpointMap['estimated'] : null;
    final estimatedStr =
        estimatedMap is Map ? estimatedMap['time']?.toString() : null;
    final parsedEstimated = estimatedStr != null
        ? DateTime.tryParse(estimatedStr)?.toLocal()
        : null;

    int? delaySec = (leg[delayKey] as num?)?.toInt();
    if (delaySec == null &&
        estimatedMap is Map &&
        estimatedMap['delay'] != null) {
      delaySec = _parseIsoDurationSeconds(estimatedMap['delay']);
    }

    final DateTime scheduled;
    if (parsedScheduled != null) {
      scheduled = parsedScheduled;
      if (delaySec == null && parsedEstimated != null) {
        delaySec = parsedEstimated.difference(parsedScheduled).inSeconds;
      }
    } else {
      // OTP2 leg `startTime` / `endTime` ALREADY reflect live delay
      // (`departureDelay` / `arrivalDelay`), so subtract delaySec to recover
      // the official scheduled timestamp.
      scheduled = msTime.subtract(Duration(seconds: delaySec ?? 0));
    }

    final delayMinutes = ((delaySec ?? 0) / 60).round().clamp(0, 180);
    return (scheduled: scheduled, delayMinutes: delayMinutes);
  }

  /// Parses OTP2 GraphQL `itineraries` into a [CommuteEvaluation].
  /// Kept public & static so both live sync and unit tests exercise the exact
  /// same timestamp, line-name sanitization, and walking-leg breakdown logic.
  static CommuteEvaluation? parseItinerariesForCommute({
    required List itineraries,
    required bool isMorning,
    required Lesson? firstLesson,
    required Lesson? lastLesson,
    required UserProfilePrefs prefs,
    required int effectiveWalk,
    required String fromName,
    required String toName,
    required bool fromExact,
    required bool toExact,
    double? fromLat,
    double? fromLon,
    double? toLat,
    double? toLon,
    String dayLine = '',
    bool dayUseLocalBus = true,
    required DateTime now,
    bool filterUnCatchable = true,
  }) {
    final trips = <MenetrendTripOption>[];
    final normalizedSpeed = normalizeWalkingSpeed(prefs.walkingSpeedKmh);

    for (final it in itineraries) {
      if (it is! Map) continue;
      final allLegs =
          (it['legs'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      final legs = allLegs.where((l) => l['mode'] != 'WALK').toList();
      if (legs.isEmpty) continue;
      if (!dayUseLocalBus && legs.any(_isLocalBusLeg)) continue;

      int walkSecondsOf(Map? leg) {
        if (leg == null) return 0;
        return (((leg['endTime'] as num).toInt() -
                    (leg['startTime'] as num).toInt()) /
                1000)
            .round()
            .clamp(0, 36000);
      }

      final leadWalk = allLegs.isNotEmpty && allLegs.first['mode'] == 'WALK'
          ? allLegs.first
          : null;
      final tailWalk = allLegs.length > 1 && allLegs.last['mode'] == 'WALK'
          ? allLegs.last
          : null;
      final firstLeg = legs.first;
      final lastLeg = legs.last;
      final mode = _modeFor(firstLeg);
      final lastMode = _modeFor(lastLeg);
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

      String? platformOf(Map leg, String key, MenetrendTransportMode m) =>
          m == MenetrendTransportMode.rail
              ? (leg[key]?['stop']?['platformCode'])?.toString()
              : null;

      final tripLegs = <MenetrendLeg>[
        for (final l in legs)
          () {
            final legMode = _modeFor(l);
            final depParsed = _parseLegTimestamp(
              leg: l,
              endpointKey: 'start',
              msKey: 'startTime',
              delayKey: 'departureDelay',
            );
            final arrParsed = _parseLegTimestamp(
              leg: l,
              endpointKey: 'end',
              msKey: 'endTime',
              delayKey: 'arrivalDelay',
            );
            final rawShort = (l['route']?['shortName'] ?? '').toString();
            final rawLong = (l['route']?['longName'] ?? '').toString();
            final rawTripShort = (l['trip']?['tripShortName'] ?? '').toString();
            final rawHeadsign = (l['headsign'] ?? '').toString();
            final cleanLine = sanitizeTransitLineName(
              rawShortName: rawShort,
              rawLongName: rawLong,
              rawTripShortName: rawTripShort,
              headsign: rawHeadsign,
              mode: legMode,
            );
            return MenetrendLeg(
              routeShortName: cleanLine,
              mode: legMode,
              fromName:
                  HtmlSanitizer.clean((l['from']?['name'] ?? '').toString()),
              toName: HtmlSanitizer.clean((l['to']?['name'] ?? '').toString()),
              departure: depParsed.scheduled,
              arrival: arrParsed.scheduled,
              platformCode: platformOf(l, 'from', legMode),
              delayMinutes: depParsed.delayMinutes,
              arrivalDelayMinutes: arrParsed.delayMinutes,
              tripShortName: HtmlSanitizer.clean(rawTripShort).trim(),
              headsign: HtmlSanitizer.clean(rawHeadsign).trim(),
            );
          }(),
      ];

      final shortNames = tripLegs
          .map((l) => l.routeShortName)
          .where((n) => n.isNotEmpty)
          .join(' → ');
      final firstDepParsed = _parseLegTimestamp(
        leg: firstLeg,
        endpointKey: 'start',
        msKey: 'startTime',
        delayKey: 'departureDelay',
      );
      final lastArrParsed = _parseLegTimestamp(
        leg: lastLeg,
        endpointKey: 'end',
        msKey: 'endTime',
        delayKey: 'arrivalDelay',
      );

      final stops = <MenetrendStop>[
        for (final st in (firstLeg['intermediateStops'] as List? ?? const []))
          if (st is Map && st['name'] != null)
            MenetrendStop(name: HtmlSanitizer.clean(st['name'].toString())),
      ];

      final fromTrain = mode == MenetrendTransportMode.rail;
      final toTrain = lastMode == MenetrendTransportMode.rail;
      final walkFromBase = isMorning
          ? (fromTrain
              ? prefs.walkHomeToTrainMinutes
              : prefs.walkHomeToBusMinutes)
          : (fromTrain
              ? prefs.walkSchoolToTrainMinutes
              : prefs.walkSchoolToBusMinutes);
      final walkToBase = isMorning
          ? (toTrain
              ? prefs.walkSchoolToTrainMinutes
              : prefs.walkSchoolToBusMinutes)
          : (toTrain
              ? prefs.walkHomeToTrainMinutes
              : prefs.walkHomeToBusMinutes);
      int scaled(int base) => calculateEffectiveWalkingMinutes(
            baseWalkingMinutes: base,
            walkingSpeedKmh: normalizedSpeed,
          );

      final leadWalkSeconds = fromExact && leadWalk != null
          ? walkSecondsOf(leadWalk)
          : null;
      final tailWalkSeconds = toExact && tailWalk != null
          ? walkSecondsOf(tailWalk)
          : null;

      final walkToStationMinutes = leadWalkSeconds != null
          ? calculateWalkMinutesFromSeconds(leadWalkSeconds, normalizedSpeed)
          : (fromExact ? 0 : scaled(walkFromBase));
      final walkToDestinationMinutes = tailWalkSeconds != null
          ? calculateWalkMinutesFromSeconds(tailWalkSeconds, normalizedSpeed)
          : (toExact ? 0 : scaled(walkToBase));

      // Use the ACTUAL transit alighting stop name (`lastLeg['to']['name']`)
      // and the vehicle's arrival time at that stop (`lastArrParsed.scheduled`),
      // never overwriting them with the final street address or `it['endTime']`.
      final actualAlightingStop = HtmlSanitizer.clean(
        (lastLeg['to']?['name'] ?? '').toString(),
      ).trim();
      final cleanDestLabel = HtmlSanitizer.clean(toName).trim();

      final resolvedRouteShort =
          shortNames.isEmpty ? (mode == MenetrendTransportMode.rail ? 'Vonat' : 'Járat') : shortNames;
      final resolvedTripId = (firstLeg['trip']?['gtfsId'] ?? '').toString().trim();

      trips.add(
        MenetrendTripOption(
          routeShortName: resolvedRouteShort,
          routeLongName: sanitizeRouteLongName(
            (firstLeg['route']?['longName'] ?? '').toString(),
          ),
          mode: mode,
          departureStation: HtmlSanitizer.clean(
            (firstLeg['from']?['name'] ?? fromName).toString(),
          ),
          arrivalStation:
              actualAlightingStop.isNotEmpty ? actualAlightingStop : cleanDestLabel,
          scheduledDeparture: firstDepParsed.scheduled,
          scheduledArrival: lastArrParsed.scheduled,
          delayMinutes: firstDepParsed.delayMinutes,
          arrivalDelayMinutes: lastArrParsed.delayMinutes,
          platformCode: platformOf(firstLeg, 'from', mode),
          arrivalPlatformCode: platformOf(lastLeg, 'to', lastMode),
          intermediateStops: stops,
          walkToStationMinutes: walkToStationMinutes,
          walkToDestinationMinutes: walkToDestinationMinutes,
          isFavorite: _matchesFavorite(
            resolvedRouteShort,
            firstDepParsed.scheduled,
            [
              dayLine,
              if (dayLine.isEmpty) ...[
                prefs.favoriteRoute1stPeriod,
                prefs.favoriteRoute2ndPeriod,
              ],
            ],
          ),
          legs: tripLegs,
          fromLat: fromLat,
          fromLon: fromLon,
          toLat: toLat,
          toLon: toLon,
          destinationLabel:
              cleanDestLabel.isNotEmpty ? cleanDestLabel : null,
          baseWalkToStationSeconds: leadWalkSeconds,
          baseWalkToDestinationSeconds: tailWalkSeconds,
          tripId: resolvedTripId,
        ),
      );
    }

    final usable = filterUnCatchable
        ? trips.where((t) => isTripCatchable(t, now)).toList()
        : trips;
    if (usable.isEmpty) return null;

    return buildEvaluation(
      trips: usable,
      isMorning: isMorning,
      firstLesson: firstLesson,
      lastLesson: lastLesson,
      prefs: prefs,
      effectiveWalk: effectiveWalk,
      now: now,
    );
  }

  /// Fetches actual scheduled departures for a given weekday (`1..5`) and
  /// direction (`isMorning`: true = Odafele, false = Hazafele) so the user can
  /// pick a real departure/line in the Settings per-day commute selector.
  Future<List<({String value, String label})>> fetchScheduledDepartureOptions({
    required UserProfilePrefs prefs,
    required bool isMorning,
    required int weekday,
    required bool useLocalBus,
  }) async {
    if (!prefs.transitConfigured) return const [];
    final homeName = prefs.homeAddress.isNotEmpty
        ? prefs.homeAddress
        : prefs.primaryHomeStop;
    final schoolName = prefs.schoolAddress.isNotEmpty
        ? prefs.schoolAddress
        : prefs.primarySchoolStop;
    final fromName = isMorning ? homeName : schoolName;
    final toName = isMorning ? schoolName : homeName;
    if (fromName.isEmpty || toName.isEmpty) return const [];

    try {
      Future<({double lat, double lon})?> resolveEndpoint(
        bool isHome,
        String name,
      ) async {
        if (isHome &&
            prefs.homeAddressLat != null &&
            prefs.homeAddressLon != null) {
          return (lat: prefs.homeAddressLat!, lon: prefs.homeAddressLon!);
        }
        if (!isHome &&
            prefs.schoolAddressLat != null &&
            prefs.schoolAddressLon != null) {
          return (lat: prefs.schoolAddressLat!, lon: prefs.schoolAddressLon!);
        }
        final stopCoord = await _resolve(name);
        if (stopCoord != null) return stopCoord;
        return _geocodeAddress(name);
      }

      final from = await resolveEndpoint(isMorning, fromName);
      final to = await resolveEndpoint(!isMorning, toName);
      if (from == null || to == null) return const [];

      final now = DateTime.now();
      var targetDate = DateTime(now.year, now.month, now.day);
      while (targetDate.weekday != weekday.clamp(1, 5)) {
        targetDate = targetDate.add(const Duration(days: 1));
      }
      final timeStr = isMorning ? '06:30' : '13:45';
      final query = '''
      {
        plan(
          from: {lat: ${from.lat}, lon: ${from.lon}},
          to: {lat: ${to.lat}, lon: ${to.lon}},
          date: "${DateFormat('yyyy-MM-dd').format(targetDate)}",
          time: "$timeStr",
          arriveBy: false,
          numItineraries: 8
        ) {
          itineraries {
            startTime
            endTime
            legs {
              mode
              startTime
              endTime
              departureDelay
              arrivalDelay
              start { scheduledTime }
              end { scheduledTime }
              from { name }
              to { name }
              route { shortName longName }
              trip { tripShortName }
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
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final itineraries = decoded['data']?['plan']?['itineraries'];
      if (itineraries is! List) return const [];

      return parseScheduledOptionsFromItineraries(
        itineraries: itineraries,
        useLocalBus: useLocalBus,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Parses selector dropdown options from OTP2 [itineraries], sanitizing icon
  /// glyphs and using official scheduled timestamps.
  static List<({String value, String label})>
      parseScheduledOptionsFromItineraries({
    required List itineraries,
    required bool useLocalBus,
  }) {
    final fmt = DateFormat('HH:mm');
    final seen = <String>{};
    final out = <({String value, String label})>[];
    for (final it in itineraries) {
      if (it is! Map) continue;
      final allLegs =
          (it['legs'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      final legs = allLegs.where((l) => l['mode'] != 'WALK').toList();
      if (legs.isEmpty) continue;
      if (!useLocalBus && legs.any(_isLocalBusLeg)) continue;

      final firstDepParsed = _parseLegTimestamp(
        leg: legs.first,
        endpointKey: 'start',
        msKey: 'startTime',
        delayKey: 'departureDelay',
      );
      final lastArrParsed = _parseLegTimestamp(
        leg: legs.last,
        endpointKey: 'end',
        msKey: 'endTime',
        delayKey: 'arrivalDelay',
      );

      final routeNames = legs
          .map(
            (l) => sanitizeTransitLineName(
              rawShortName: (l['route']?['shortName'] ?? '').toString(),
              rawLongName: (l['route']?['longName'] ?? '').toString(),
              rawTripShortName:
                  (l['trip']?['tripShortName'] ?? '').toString(),
              mode: _modeFor(l),
            ),
          )
          .where((s) => s.isNotEmpty)
          .join(' → ');
      final depTime = fmt.format(firstDepParsed.scheduled);
      final arrTime = fmt.format(lastArrParsed.scheduled);
      final lineCode = routeNames.isEmpty ? 'Járat' : routeNames;
      final value = '$depTime / $lineCode';
      if (!seen.add(value)) continue;
      out.add((
        value: value,
        label: '$depTime → $arrTime  •  $lineCode',
      ));
    }
    return out;
  }

  /// Builds a deterministic deduplication key for live transit delay alerts.
  static String buildDelayNotificationKey(MenetrendTripOption trip) {
    final dateStr = DateFormat('yyyy-MM-dd').format(trip.scheduledDeparture);
    final depStr = DateFormat('HH:mm').format(trip.scheduledDeparture);
    final idPart = trip.tripId.trim().isNotEmpty
        ? trip.tripId.trim()
        : '${trip.safeRouteShortName}|${trip.departureStation.trim()}';
    return '$dateStr|$idPart|$depStr|${trip.delayMinutes}|${trip.isCancelled}';
  }

  /// Schedules the morning departure alarm & checks for live delays via the native
  /// Android notification + exact alarm channel.
  ///
  /// Delay notifications are strictly deduplicated via [SharedPreferences] keyed
  /// by `(date, tripId/route, scheduledDeparture, delayMinutes, isCancelled)` and
  /// are ONLY emitted during actual commute syncs (`allowDelayNotification: true`),
  /// never on pull-to-refresh with an unchanged delay or on Settings toggles.
  /// Returns `true` if a live delay notification was newly dispatched.
  static Future<bool> syncNotificationsForEvaluation({
    required CommuteEvaluation evaluation,
    required UserProfilePrefs prefs,
    bool allowDelayNotification = true,
    Future<dynamic> Function(String method, Map<String, dynamic> arguments)?
        invokeNativeChannel,
  }) async {
    Future<dynamic> callChannel(
      String method, [
      Map<String, dynamic> args = const {},
    ]) {
      if (invokeNativeChannel != null) {
        return invokeNativeChannel(method, args);
      }
      return _transitChannel.invokeMethod(method, args);
    }

    var sentDelayNotification = false;
    try {
      if (!prefs.transitNotificationsEnabled) {
        await callChannel('cancelDepartureAlarms');
        return false;
      }

      if (evaluation.isMorningMode) {
        final triggerTime = evaluation.alarmTriggerTime;
        if (triggerTime.isAfter(evaluation.now)) {
          await callChannel('scheduleDepartureAlarm', {
            'triggerAtMillis': triggerTime.millisecondsSinceEpoch,
            'notificationId': 7090,
            'title': evaluation.departureNotificationTitle,
            'body': evaluation.departureNotificationBody,
          });
        }
      }

      final trip = evaluation.recommendedTrip;
      final minsBeforeDep =
          trip.scheduledDeparture.difference(evaluation.now).inMinutes;
      final hasDelay = trip.delayMinutes > 0 || trip.isCancelled;
      if (allowDelayNotification &&
          hasDelay &&
          minsBeforeDep >= -5 &&
          minsBeforeDep <= 120) {
        final key = buildDelayNotificationKey(trip);
        final todayPrefix =
            '${DateFormat('yyyy-MM-dd').format(trip.scheduledDeparture)}|';

        bool alreadyNotified = false;
        SharedPreferences? sp;
        try {
          sp = await SharedPreferences.getInstance();
          final lastKey = sp.getString(lastNotifiedDelayPrefsKey);
          final knownKeys =
              sp.getStringList(notifiedDelayKeysPrefsKey) ?? const <String>[];
          alreadyNotified = lastKey == key || knownKeys.contains(key);
        } catch (_) {}

        if (!alreadyNotified) {
          await callChannel('showTransitNotification', {
            'notificationId': 7092,
            'title': evaluation.delayNotificationTitle,
            'body': evaluation.delayNotificationBody,
          });
          sentDelayNotification = true;

          if (sp != null) {
            try {
              final existing =
                  sp.getStringList(notifiedDelayKeysPrefsKey) ?? const <String>[];
              final todayKeys = existing
                  .where((k) => k.startsWith(todayPrefix))
                  .toList();
              todayKeys.add(key);
              if (todayKeys.length > 50) {
                todayKeys.removeRange(0, todayKeys.length - 50);
              }
              await sp.setString(lastNotifiedDelayPrefsKey, key);
              await sp.setStringList(notifiedDelayKeysPrefsKey, todayKeys);
            } catch (_) {}
          }
        }
      }
    } catch (_) {
      // Safely ignore in unit/widget test environments where native channel is unmounted.
    }
    return sentDelayNotification;
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

  /// Launches the native MenetrendGO Android app (`hu.matepazy.menetrendgo`)
  /// with pre-filled Origin -> Destination route search parameters (`from`, `to`,
  /// coordinates, date/time) across `menetrendgo://`, `https://menetrendgo.hu/...`,
  /// and Android Intent data URI/extras, falling back cleanly to launching the
  /// app or website normally if parameters are not handled.
  static Future<void> openInMenetrendGo({
    MenetrendTripOption? trip,
    CommuteEvaluation? evaluation,
    UserProfilePrefs? prefs,
  }) async {
    final effectiveTrip = trip ?? evaluation?.recommendedTrip;
    final isMorning = evaluation?.isMorningMode ?? true;
    final fallbackFrom = prefs != null
        ? (isMorning ? prefs.primaryHomeStop : prefs.primarySchoolStop)
        : '';
    final fallbackTo = prefs != null
        ? (isMorning ? prefs.primarySchoolStop : prefs.primaryHomeStop)
        : '';

    final fromStation = (effectiveTrip?.departureStation ?? fallbackFrom).trim();
    final toStation = (effectiveTrip?.arrivalStation ?? fallbackTo).trim();
    final fromLat = effectiveTrip?.fromLat ??
        (isMorning ? prefs?.homeAddressLat : prefs?.schoolAddressLat);
    final fromLon = effectiveTrip?.fromLon ??
        (isMorning ? prefs?.homeAddressLon : prefs?.schoolAddressLon);
    final toLat = effectiveTrip?.toLat ??
        (isMorning ? prefs?.schoolAddressLat : prefs?.homeAddressLat);
    final toLon = effectiveTrip?.toLon ??
        (isMorning ? prefs?.schoolAddressLon : prefs?.homeAddressLon);

    final depDateTime = effectiveTrip?.scheduledDeparture ?? DateTime.now();
    final timeStr = DateFormat('HH:mm').format(depDateTime);
    final dateStr = DateFormat('yyyy-MM-dd').format(depDateTime);
    final routeName = effectiveTrip?.routeShortName ?? '';

    final queryParams = <String, String>{
      if (fromStation.isNotEmpty) ...{
        'from': fromStation,
        'origin': fromStation,
        'indulas': fromStation,
      },
      if (toStation.isNotEmpty) ...{
        'to': toStation,
        'destination': toStation,
        'erkezes': toStation,
      },
      if (fromLat != null && fromLon != null) ...{
        'fromLat': fromLat.toString(),
        'fromLon': fromLon.toString(),
        'fromCoord': '$fromLat,$fromLon',
      },
      if (toLat != null && toLon != null) ...{
        'toLat': toLat.toString(),
        'toLon': toLon.toString(),
        'toCoord': '$toLat,$toLon',
      },
      'time': timeStr,
      'date': dateStr,
      if (routeName.isNotEmpty) 'route': routeName,
    };

    final candidateDeepLinkUris = <String>[
      if (fromStation.isNotEmpty && toStation.isNotEmpty) ...[
        Uri(
          scheme: 'menetrendgo',
          host: 'search',
          queryParameters: queryParams,
        ).toString(),
        Uri(
          scheme: 'menetrendgo',
          host: 'route',
          queryParameters: queryParams,
        ).toString(),
        Uri(
          scheme: 'menetrendgo',
          host: 'trip',
          queryParameters: queryParams,
        ).toString(),
        Uri.https('menetrendgo.hu', '/search', queryParams).toString(),
        Uri.https('menetrendgo.hu', '/', queryParams).toString(),
      ],
    ];

    try {
      final launched = await _transitChannel.invokeMethod<bool>(
        'launchMenetrendGo',
        {
          'tab': effectiveTrip != null ? 'trip' : 'search',
          if (fromStation.isNotEmpty) ...{
            'from': fromStation,
            'origin': fromStation,
            'fromStation': fromStation,
            'fromName': fromStation,
            'startStation': fromStation,
            'indulas': fromStation,
          },
          if (toStation.isNotEmpty) ...{
            'to': toStation,
            'destination': toStation,
            'toStation': toStation,
            'toName': toStation,
            'endStation': toStation,
            'erkezes': toStation,
          },
          if (fromStation.isNotEmpty && toStation.isNotEmpty)
            'query': '$fromStation -> $toStation',
          if (fromLat != null && fromLon != null) ...{
            'fromLat': fromLat,
            'fromLon': fromLon,
          },
          if (toLat != null && toLon != null) ...{
            'toLat': toLat,
            'toLon': toLon,
          },
          if (routeName.isNotEmpty) ...{
            'route': routeName,
            'routeShortName': routeName,
          },
          'time': timeStr,
          'departureTime': timeStr,
          'date': dateStr,
          'departureDate': dateStr,
          'departureIso': depDateTime.toIso8601String(),
          'departureEpochMs': depDateTime.millisecondsSinceEpoch.toString(),
          'autoSearch': 'true',
          if (candidateDeepLinkUris.isNotEmpty) ...{
            'deepLinkUri': candidateDeepLinkUris.first,
            'deepLinkUris': candidateDeepLinkUris,
          },
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
