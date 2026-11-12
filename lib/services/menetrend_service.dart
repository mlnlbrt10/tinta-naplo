import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
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

  const MenetrendLeg({
    required this.routeShortName,
    required this.mode,
    required this.fromName,
    required this.toName,
    required this.departure,
    required this.arrival,
    this.platformCode,
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
  final List<MenetrendLeg> legs;
  final double? fromLat;
  final double? fromLon;
  final double? toLat;
  final double? toLon;

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
    this.legs = const [],
    this.fromLat,
    this.fromLon,
    this.toLat,
    this.toLon,
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
      legs: legs,
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
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
        'User-Agent': 'MenetrendGO/1.2.6 (Android)',
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
    final speed = normalizeWalkingSpeed(walkingSpeedKmh);
    final scaled = (baseWalkingMinutes * (5.0 / speed)).round();
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
            t.effectiveDeparture
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
            .where((t) => !t.effectiveArrival.isAfter(firstStartLocal))
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
  /// before the (delay-adjusted) departure.
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
        'User-Agent': 'reKRETA-Android/1.2.6',
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
          .get(photonUri, headers: const {'User-Agent': 'reKRETA-Android/1.2.6'})
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
    final walkScale = 4.8 / normalizeWalkingSpeed(prefs.walkingSpeedKmh);

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
        final allLegs = (it['legs'] as List?)?.whereType<Map>().toList() ??
            const <Map>[];
        final legs = allLegs.where((l) => l['mode'] != 'WALK').toList();
        if (legs.isEmpty) continue;
        if (!dayUseLocalBus && legs.any(_isLocalBusLeg)) continue;
        // Door-to-door walking legs reported by the planner (exact addresses).
        int walkMinutesOf(Map? leg) {
          if (leg == null) return 0;
          final secs = (((leg['endTime'] as num).toInt() -
                      (leg['startTime'] as num).toInt()) /
                  1000)
              .round();
          return ((secs / 60) * walkScale).ceil().clamp(1, 90);
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
            MenetrendLeg(
              routeShortName: HtmlSanitizer.clean((l['route']?['shortName'] ??
                      l['route']?['longName'] ??
                      '')
                  .toString()),
              mode: _modeFor(l),
              fromName:
                  HtmlSanitizer.clean((l['from']?['name'] ?? '').toString()),
              toName: HtmlSanitizer.clean((l['to']?['name'] ?? '').toString()),
              departure: ms(l['startTime']),
              arrival: ms(l['endTime']),
              platformCode: platformOf(l, 'from', _modeFor(l)),
            ),
        ];
        final shortNames = tripLegs
            .map((l) => l.routeShortName)
            .where((n) => n.isNotEmpty)
            .join(' → ');
        final stops = <MenetrendStop>[
          for (final st in (firstLeg['intermediateStops'] as List? ?? const []))
            if (st is Map && st['name'] != null)
              MenetrendStop(name: HtmlSanitizer.clean(st['name'].toString())),
        ];
        final delaySec = (firstLeg['departureDelay'] as num?)?.toInt() ?? 0;
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
              walkingSpeedKmh: prefs.walkingSpeedKmh,
            );
        trips.add(
          MenetrendTripOption(
            routeShortName: shortNames.isEmpty ? 'Járat' : shortNames,
            routeLongName: HtmlSanitizer.clean(
                (firstLeg['route']?['longName'] ?? '').toString()),
            mode: mode,
            departureStation: HtmlSanitizer.clean(
                (firstLeg['from']?['name'] ?? fromName).toString()),
            arrivalStation: HtmlSanitizer.clean(toName),
            scheduledDeparture: ms(firstLeg['startTime']),
            scheduledArrival: ms(it['endTime']),
            delayMinutes: (delaySec / 60).round().clamp(0, 180),
            platformCode: platformOf(firstLeg, 'from', mode),
            arrivalPlatformCode: platformOf(lastLeg, 'to', lastMode),
            intermediateStops: stops,
            walkToStationMinutes: fromExact && leadWalk != null
                ? walkMinutesOf(leadWalk)
                : (fromExact ? 1 : scaled(walkFromBase)),
            walkToDestinationMinutes: toExact && tailWalk != null
                ? walkMinutesOf(tailWalk)
                : (toExact ? 0 : scaled(walkToBase)),
            isFavorite: _matchesFavorite(
              shortNames,
              ms(firstLeg['startTime']),
              [
                dayLine,
                if (dayLine.isEmpty) ...[
                  prefs.favoriteRoute1stPeriod,
                  prefs.favoriteRoute2ndPeriod,
                ],
              ],
            ),
            legs: tripLegs,
            fromLat: from.lat,
            fromLon: from.lon,
            toLat: to.lat,
            toLon: to.lon,
          ),
        );
      }

      // Only keep departures the user can physically catch (walking time +
      // live delay). Nothing catchable => hide the card for now.
      final catchable =
          trips.where((t) => isTripCatchable(t, now)).toList();
      if (catchable.isEmpty) return null;

      return buildEvaluation(
        trips: catchable,
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
              from { name }
              to { name }
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
          .timeout(const Duration(seconds: 7));
      if (response.statusCode != 200) return const [];
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final itineraries = decoded['data']?['plan']?['itineraries'];
      if (itineraries is! List) return const [];

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
        final dep = DateTime.fromMillisecondsSinceEpoch(
          (legs.first['startTime'] as num).toInt(),
        );
        final arr = DateTime.fromMillisecondsSinceEpoch(
          (it['endTime'] as num).toInt(),
        );
        final routeNames = legs
            .map((l) => HtmlSanitizer.clean(
                (l['route']?['shortName'] ?? l['route']?['longName'] ?? '')
                    .toString()))
            .where((s) => s.isNotEmpty)
            .join(' → ');
        final depTime = fmt.format(dep);
        final arrTime = fmt.format(arr);
        final lineCode = routeNames.isEmpty ? 'Járat' : routeNames;
        final value = '$depTime / $lineCode';
        if (!seen.add(value)) continue;
        out.add((
          value: value,
          label: '$depTime → $arrTime  •  $lineCode',
        ));
      }
      return out;
    } catch (_) {
      return const [];
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
