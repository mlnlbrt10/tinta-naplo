import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/providers/app_providers.dart';
import 'package:rekreta_app/screens/more_screen.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/menetrend_service.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/glass_card.dart';
import 'package:rekreta_app/widgets/menetrend_hero_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Lesson _lesson({
  required int number,
  required DateTime start,
  required DateTime end,
  String subject = 'Matematika',
}) {
  return Lesson(
    uid: 'lesson-$number',
    date: '2026-11-13',
    start: start,
    end: end,
    name: subject,
    lessonNumber: number,
    lessonSeqNumber: number,
    roomName: '101',
    teacher: 'Teszt Tanár',
    type: NameUidDesc(uid: 'tanora', name: 'Tanora', description: 'Tanóra'),
    state: NameUidDesc(
      uid: 'megtartott',
      name: 'Megtartott',
      description: 'Megtartott',
    ),
    canStudentEditHomework: false,
    isHomeworkComplete: false,
    attachments: const [],
    isDigitalLesson: false,
    digitalSupportDeviceTypeList: const [],
    createdAt: start,
    lastModifiedAt: start,
  );
}

StoredSession _testSession() {
  return StoredSession(
    accessToken: 'acc',
    refreshToken: 'ref',
    idToken: 'id',
    instituteCode: 'klik001',
    expiresAt: DateTime(2027, 1, 1),
  );
}

void main() {
  group('Bug 1: Symmetrical leg breakdown (no double walk or street alighting stop)', () {
    test('Morning itinerary keeps actual rail alighting stop, vehicle arrival, and single tail walk', () {
      final now = DateTime(2026, 11, 13, 6, 40);
      final walkStart = DateTime(2026, 11, 13, 7, 4);
      final railDep = DateTime(2026, 11, 13, 7, 9);
      final railArr = DateTime(2026, 11, 13, 7, 42);
      final destArr = DateTime(2026, 11, 13, 7, 52);

      final itinerary = {
        'startTime': walkStart.millisecondsSinceEpoch,
        'endTime': destArr.millisecondsSinceEpoch,
        'legs': [
          {
            'mode': 'WALK',
            'duration': 300.0,
            'startTime': walkStart.millisecondsSinceEpoch,
            'endTime': railDep.millisecondsSinceEpoch,
            'from': {'name': 'Origin', 'lat': 47.32, 'lon': 18.21},
            'to': {'name': 'Bodajk, vasútállomás', 'lat': 47.321, 'lon': 18.215},
          },
          {
            'mode': 'RAIL',
            'startTime': railDep.millisecondsSinceEpoch,
            'endTime': railArr.millisecondsSinceEpoch,
            'realTime': false,
            'departureDelay': 0,
            'arrivalDelay': 0,
            'start': {'scheduledTime': railDep.toIso8601String()},
            'end': {'scheduledTime': railArr.toIso8601String()},
            'from': {'name': 'Bodajk, vasútállomás'},
            'to': {'name': 'Székesfehérvár vasútállomás'},
            'route': {
              'shortName': 'S150',
              'longName': 'S150 Székesfehérvár - Komárom',
              'agency': {'name': 'MÁV-START'},
            },
            'trip': {
              'gtfsId': 'MAV:34919',
              'tripShortName': '34919',
            },
          },
          {
            'mode': 'WALK',
            'duration': 600.0,
            'startTime': railArr.millisecondsSinceEpoch,
            'endTime': destArr.millisecondsSinceEpoch,
            'from': {'name': 'Székesfehérvár vasútállomás'},
            'to': {'name': 'Destination', 'lat': 47.19, 'lon': 18.41},
          },
        ],
      };

      const prefs = UserProfilePrefs(
        transitCardEnabled: true,
        transitHomeStation: 'Bodajk, vasútállomás',
        transitSchoolStation: 'Székesfehérvár, Hunyadi u. 4.',
        extras: {
          'homeAddress': 'Bodajk, Fő u. 12.',
          'schoolAddress': 'Székesfehérvár, Hunyadi u. 4.',
        },
        walkingSpeedKmh: 5.0,
        transitAlertBufferMinutes: 15,
      );

      final eval = MenetrendService.parseItinerariesForCommute(
        itineraries: [itinerary],
        isMorning: true,
        firstLesson: _lesson(
          number: 1,
          start: DateTime(2026, 11, 13, 8, 0),
          end: DateTime(2026, 11, 13, 8, 45),
        ),
        lastLesson: null,
        prefs: prefs,
        effectiveWalk: 5,
        fromName: 'Bodajk, Fő u. 12.',
        toName: 'Székesfehérvár, Hunyadi u. 4.',
        fromExact: true,
        toExact: true,
        now: now,
      );

      expect(eval, isNotNull);
      final trip = eval!.recommendedTrip;
      expect(trip.departureStation, 'Bodajk, vasútállomás');
      // Vehicle's actual drop-off stop, NEVER the school street address.
      expect(trip.arrivalStation, 'Székesfehérvár vasútállomás');
      expect(trip.arrivalStation, isNot('Székesfehérvár, Hunyadi u. 4.'));
      // Vehicle's own arrival time vs true final destination arrival time.
      expect(trip.scheduledArrival, railArr);
      expect(trip.scheduledDestinationArrival, destArr);
      expect(trip.walkToStationMinutes, 5);
      expect(trip.walkToDestinationMinutes, 10);
      expect(trip.destinationLabel, 'Székesfehérvár, Hunyadi u. 4.');
    });

    test('Afternoon itinerary keeps actual coach alighting stop and single tail walk home', () {
      final now = DateTime(2026, 11, 13, 12, 30);
      final headStart = DateTime(2026, 11, 13, 12, 57);
      final busDep = DateTime(2026, 11, 13, 13, 5);
      final busArr = DateTime(2026, 11, 13, 13, 38);
      final homeArr = DateTime(2026, 11, 13, 13, 44);

      final itinerary = {
        'startTime': headStart.millisecondsSinceEpoch,
        'endTime': homeArr.millisecondsSinceEpoch,
        'legs': [
          {
            'mode': 'WALK',
            'duration': 480.0,
            'startTime': headStart.millisecondsSinceEpoch,
            'endTime': busDep.millisecondsSinceEpoch,
            'from': {'name': 'Origin', 'lat': 47.19, 'lon': 18.41},
            'to': {'name': 'Székesfehérvár, autóbusz-állomás'},
          },
          {
            'mode': 'COACH',
            'startTime': busDep.millisecondsSinceEpoch,
            'endTime': busArr.millisecondsSinceEpoch,
            'realTime': false,
            'departureDelay': 0,
            'arrivalDelay': 0,
            'start': {'scheduledTime': busDep.toIso8601String()},
            'end': {'scheduledTime': busArr.toIso8601String()},
            'from': {'name': 'Székesfehérvár, autóbusz-állomás'},
            'to': {'name': 'Bodajk, Petőfi Sándor utca'},
            'route': {
              'shortName': '8040',
              'longName': 'Székesfehérvár - Mór',
              'agency': {'name': 'Volánbusz'},
            },
          },
          {
            'mode': 'WALK',
            'duration': 360.0,
            'startTime': busArr.millisecondsSinceEpoch,
            'endTime': homeArr.millisecondsSinceEpoch,
            'from': {'name': 'Bodajk, Petőfi Sándor utca'},
            'to': {'name': 'Destination', 'lat': 47.32, 'lon': 18.21},
          },
        ],
      };

      const prefs = UserProfilePrefs(
        transitCardEnabled: true,
        transitHomeStation: 'Bodajk, Fő u. 12.',
        transitSchoolStation: 'Székesfehérvár, Hunyadi u. 4.',
        extras: {
          'homeAddress': 'Bodajk, Fő u. 12.',
          'schoolAddress': 'Székesfehérvár, Hunyadi u. 4.',
        },
        walkingSpeedKmh: 5.0,
      );

      final eval = MenetrendService.parseItinerariesForCommute(
        itineraries: [itinerary],
        isMorning: false,
        firstLesson: null,
        lastLesson: _lesson(
          number: 5,
          start: DateTime(2026, 11, 13, 12, 0),
          end: DateTime(2026, 11, 13, 12, 45),
        ),
        prefs: prefs,
        effectiveWalk: 8,
        fromName: 'Székesfehérvár, Hunyadi u. 4.',
        toName: 'Bodajk, Fő u. 12.',
        fromExact: true,
        toExact: true,
        now: now,
      );

      expect(eval, isNotNull);
      final trip = eval!.recommendedTrip;
      expect(trip.arrivalStation, 'Bodajk, Petőfi Sándor utca');
      expect(trip.arrivalStation, isNot('Bodajk, Fő u. 12.'));
      expect(trip.scheduledArrival, busArr);
      expect(trip.scheduledDestinationArrival, homeArr);
      expect(trip.walkToStationMinutes, 8);
      expect(trip.walkToDestinationMinutes, 6);
    });

    testWidgets('Detail modal renders actual alighting stop + single tail walk in morning and afternoon', (tester) async {
      for (final isMorning in [true, false]) {
        final dep = DateTime(2026, 11, 13, isMorning ? 7 : 13, 9);
        final arr = DateTime(2026, 11, 13, isMorning ? 7 : 13, 42);
        final alightingStop = isMorning
            ? 'Székesfehérvár vasútállomás'
            : 'Bodajk, Petőfi utca';
        final streetDest = isMorning
            ? 'Székesfehérvár, Hunyadi u. 4.'
            : 'Bodajk, Fő u. 12.';
        final expectedFinalTime = isMorning ? '07:52' : '13:52';

        final trip = MenetrendTripOption(
          routeShortName: isMorning ? 'S150' : '8040',
          routeLongName: isMorning ? 'Személyvonat' : 'Regionális járat',
          mode: isMorning
              ? MenetrendTransportMode.rail
              : MenetrendTransportMode.coach,
          departureStation: isMorning
              ? 'Bodajk, vasútállomás'
              : 'Székesfehérvár, autóbusz-állomás',
          arrivalStation: alightingStop,
          scheduledDeparture: dep,
          scheduledArrival: arr,
          walkToStationMinutes: 5,
          walkToDestinationMinutes: 10,
          baseWalkToStationSeconds: 300,
          baseWalkToDestinationSeconds: 600,
          destinationLabel: streetDest,
        );
        final eval = CommuteEvaluation(
          isMorningMode: isMorning,
          targetLesson: null,
          targetPeriodNumber: isMorning ? 1 : 5,
          recommendedTrip: trip,
          alternatives: [trip],
          effectiveWalkMinutes: 5,
          alertBufferMinutes: 15,
          now: dep.subtract(const Duration(minutes: 25)),
        );
        const prefs = UserProfilePrefs(cardBlurEnabled: false);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: MenetrendHeroCard(evaluation: eval, prefs: prefs),
            ),
          ),
        );
        await tester.tap(find.byType(MenetrendHeroCard));
        await tester.pumpAndSettle();

        expect(find.text('Leszállás: $alightingStop'), findsOneWidget);
        final expectedWalkTitle =
            isMorning ? 'Séta az iskoláig' : 'Séta hazáig';
        expect(find.text(expectedWalkTitle), findsOneWidget);
        // True destination arrival time (vehicle arrival + 10 min tail walk = :52, NOT double-counted :02)
        expect(find.text(expectedFinalTime), findsWidgets);
        expect(find.textContaining('08:02'), findsNothing);
        expect(find.textContaining('14:02'), findsNothing);

        await tester.ensureVisible(find.text('Bezárás'));
        await tester.tap(find.text('Bezárás'));
        await tester.pumpAndSettle();
      }
    });
  });

  group('Bug 2: Exact official scheduled departure vs. live delay banner', () {
    test('Parser recovers official scheduled time without double-adding OTP2 delay', () {
      final now = DateTime(2026, 11, 13, 6, 40);
      final schedDep = DateTime(2026, 11, 13, 7, 14);
      final estDep = DateTime(2026, 11, 13, 7, 20); // +6 min already baked into startTime
      final schedArr = DateTime(2026, 11, 13, 7, 45);
      final estArr = DateTime(2026, 11, 13, 7, 51);

      final itinerary = {
        'startTime': estDep.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
        'endTime': estArr.millisecondsSinceEpoch,
        'legs': [
          {
            'mode': 'RAIL',
            // OTP2 already added 360s to startTime & endTime, omitting start.scheduledTime in fallback test
            'startTime': estDep.millisecondsSinceEpoch,
            'endTime': estArr.millisecondsSinceEpoch,
            'realTime': true,
            'departureDelay': 360,
            'arrivalDelay': 360,
            'from': {'name': 'Bodajk'},
            'to': {'name': 'Székesfehérvár'},
            'route': {
              'shortName': 'S150',
              'longName': 'Személyvonat',
              'agency': {'name': 'MÁV-START'},
            },
          },
        ],
      };

      final eval = MenetrendService.parseItinerariesForCommute(
        itineraries: [itinerary],
        isMorning: true,
        firstLesson: _lesson(
          number: 1,
          start: DateTime(2026, 11, 13, 8, 0),
          end: DateTime(2026, 11, 13, 8, 45),
        ),
        lastLesson: null,
        prefs: const UserProfilePrefs(transitCardEnabled: true),
        effectiveWalk: 5,
        fromName: 'Bodajk',
        toName: 'Székesfehérvár',
        fromExact: false,
        toExact: false,
        now: now,
      );

      expect(eval, isNotNull);
      final trip = eval!.recommendedTrip;
      // Exact 07:14 — never 07:15, never 07:20, never 07:26.
      expect(trip.scheduledDeparture, schedDep);
      expect(trip.delayMinutes, 6);
      expect(trip.effectiveDeparture, estDep);
      expect(trip.departureTimeFormatted, '07:14');
      expect(trip.effectiveDepartureTimeFormatted, '07:20');
      expect(trip.scheduledArrival, schedArr);
      expect(trip.effectiveArrival, estArr);
    });

    testWidgets('Hero card & detail modal display scheduled 07:14 primarily and live delay separately', (tester) async {
      final schedDep = DateTime(2026, 11, 13, 7, 14);
      final schedArr = DateTime(2026, 11, 13, 7, 45);
      final trip = MenetrendTripOption(
        routeShortName: 'S150',
        routeLongName: 'Személyvonat',
        mode: MenetrendTransportMode.rail,
        departureStation: 'Bodajk',
        arrivalStation: 'Székesfehérvár',
        scheduledDeparture: schedDep,
        scheduledArrival: schedArr,
        delayMinutes: 6,
        arrivalDelayMinutes: 6,
        walkToStationMinutes: 5,
        walkToDestinationMinutes: 8,
        destinationLabel: 'Székesfehérvár, Iskola u. 1.',
      );
      final eval = CommuteEvaluation(
        isMorningMode: true,
        targetLesson: null,
        targetPeriodNumber: 1,
        recommendedTrip: trip,
        alternatives: [trip],
        effectiveWalkMinutes: 5,
        alertBufferMinutes: 15,
        now: DateTime(2026, 11, 13, 6, 55),
      );
      const prefs = UserProfilePrefs(cardBlurEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: Scaffold(
            body: MenetrendHeroCard(evaluation: eval, prefs: prefs),
          ),
        ),
      );

      // Card headline uses official scheduled departure 07:14 + separate live delay pill
      expect(find.text('07:14'), findsOneWidget);
      expect(find.textContaining('+6 perc késés'), findsOneWidget);
      expect(find.textContaining('Becsült: 07:20'), findsOneWidget);

      await tester.tap(find.byType(MenetrendHeroCard));
      await tester.pumpAndSettle();

      expect(find.textContaining('Menetrend szerinti indulás: 07:14'), findsOneWidget);
      expect(find.textContaining('Felszállás: Bodajk'), findsOneWidget);
      expect(find.textContaining('Élő késés: +6 perc • Becsült ind.: 07:20'), findsWidgets);
    });
  });

  group('Bug 3: MÁV GTFS icon glyph "Ű" stripped and human-readable line resolved', () {
    test('Sanitizer strips MNR2007 HTML entities & single diacritic glyphs across all formats', () {
      expect(
        MenetrendService.sanitizeTransitLineName(
          rawShortName: '<span class="MNR2007">&#368;</span>',
          rawLongName: 'S150 Székesfehérvár - Komárom',
          rawTripShortName: '34919',
          mode: MenetrendTransportMode.rail,
        ),
        'S150',
      );
      expect(
        MenetrendService.sanitizeTransitLineName(
          rawShortName: 'Ű',
          rawLongName: 'személyvonat',
          rawTripShortName: '34919 passenger train',
          mode: MenetrendTransportMode.rail,
        ),
        'Személyvonat 34919',
      );
      expect(
        MenetrendService.sanitizeTransitLineName(
          rawShortName: '<span class="MNR2007">&#383;</span>',
          rawLongName: '',
          rawTripShortName: '',
          mode: MenetrendTransportMode.rail,
        ),
        anyOf('Személyvonat', 'Vonat'),
      );
      // Selector option parsing must never output "Ű"
      final options = MenetrendService.parseScheduledOptionsFromItineraries(
        useLocalBus: true,
        itineraries: [
          {
            'legs': [
              {
                'mode': 'RAIL',
                'startTime': DateTime(2026, 11, 13, 7, 14).millisecondsSinceEpoch,
                'endTime': DateTime(2026, 11, 13, 7, 45).millisecondsSinceEpoch,
                'from': {'name': 'Bodajk'},
                'to': {'name': 'Székesfehérvár'},
                'route': {
                  'shortName': '<span class="MNR2007">&#368;</span>',
                  'longName': 'személyvonat',
                },
                'trip': {'tripShortName': '34919 passenger train'},
              },
            ],
          },
        ],
      );
      expect(options, hasLength(1));
      expect(options.first.label, isNot(contains('Ű')));
      expect(options.first.label, '07:14 → 07:45  •  Személyvonat 34919');
    });

    testWidgets('Hero card and detail modal never render "Ű" even if raw routeShortName is "Ű"', (tester) async {
      final dep = DateTime(2026, 11, 13, 7, 14);
      final arr = DateTime(2026, 11, 13, 7, 45);
      final trip = MenetrendTripOption(
        routeShortName: 'Ű',
        routeLongName: 'személyvonat',
        mode: MenetrendTransportMode.rail,
        departureStation: 'Bodajk',
        arrivalStation: 'Székesfehérvár',
        scheduledDeparture: dep,
        scheduledArrival: arr,
        walkToStationMinutes: 5,
        legs: [
          MenetrendLeg(
            routeShortName: 'Ű',
            mode: MenetrendTransportMode.rail,
            fromName: 'Bodajk',
            toName: 'Székesfehérvár',
            departure: dep,
            arrival: arr,
            tripShortName: '34919 passenger train',
          ),
        ],
      );
      final eval = CommuteEvaluation(
        isMorningMode: true,
        targetLesson: null,
        targetPeriodNumber: 1,
        recommendedTrip: trip,
        alternatives: [trip],
        effectiveWalkMinutes: 5,
        alertBufferMinutes: 15,
        now: DateTime(2026, 11, 13, 6, 55),
      );
      const prefs = UserProfilePrefs(cardBlurEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: Scaffold(
            body: MenetrendHeroCard(evaluation: eval, prefs: prefs),
          ),
        ),
      );
      expect(find.textContaining('Ű'), findsNothing);
      expect(find.textContaining('Személyvonat 34919'), findsOneWidget);

      await tester.tap(find.byType(MenetrendHeroCard));
      await tester.pumpAndSettle();

      expect(find.textContaining('Ű'), findsNothing);
      expect(find.textContaining('Személyvonat 34919'), findsWidgets);
    });
  });

  group('Bugs 4 & 5: Responsive RenderFlex layout + overflow-free Hero open/close', () {
    testWidgets('Morning & Afternoon MenetrendHeroCard never overflow at 320px width and 1.5x text scale', (tester) async {
      for (final isMorning in [true, false]) {
        final dep = DateTime(2026, 11, 13, isMorning ? 7 : 12, 54);
        final arr = DateTime(2026, 11, 13, isMorning ? 7 : 13, 54);
        final trip = MenetrendTripOption(
          routeShortName: '8040',
          routeLongName: 'Regionális gyorsított autóbuszjárat',
          mode: MenetrendTransportMode.coach,
          departureStation: 'Székesfehérvár, Autóbusz-állomás 2. kocsiállás',
          arrivalStation: 'Bodajk, Petőfi Sándor utca 18.',
          scheduledDeparture: dep,
          scheduledArrival: arr,
          delayMinutes: 4,
          walkToStationMinutes: 6,
        );
        final eval = CommuteEvaluation(
          isMorningMode: isMorning,
          targetLesson: null,
          targetPeriodNumber: isMorning ? 1 : 5,
          recommendedTrip: trip,
          alternatives: [trip],
          effectiveWalkMinutes: 6,
          alertBufferMinutes: 15,
          now: dep.subtract(const Duration(minutes: 20)),
        );
        const prefs = UserProfilePrefs(cardBlurEnabled: false);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.5),
              ),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 300,
                    child: MenetrendHeroCard(evaluation: eval, prefs: prefs),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text(isMorning ? '07:54' : '12:54'), findsOneWidget);
        expect(find.text(isMorning ? 'Érk: 07:54' : 'Érk: 13:54'), findsOneWidget);
      }
    });

    testWidgets('Opening and closing MenetrendDetailsModal renders zero RenderFlex overflow on every exit frame', (tester) async {
      final dep = DateTime(2026, 11, 13, 12, 54);
      final arr = DateTime(2026, 11, 13, 13, 54);
      final trip = MenetrendTripOption(
        routeShortName: '8040',
        routeLongName: 'Regionális busz',
        mode: MenetrendTransportMode.coach,
        departureStation: 'Székesfehérvár, autóbusz-állomás',
        arrivalStation: 'Bodajk, Petőfi u.',
        scheduledDeparture: dep,
        scheduledArrival: arr,
        walkToStationMinutes: 5,
        walkToDestinationMinutes: 7,
      );
      final eval = CommuteEvaluation(
        isMorningMode: false,
        targetLesson: null,
        targetPeriodNumber: 5,
        recommendedTrip: trip,
        alternatives: [trip],
        effectiveWalkMinutes: 5,
        alertBufferMinutes: 15,
        now: DateTime(2026, 11, 13, 12, 34),
      );
      const prefs = UserProfilePrefs(cardBlurEnabled: false);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: prefs),
          home: Scaffold(
            body: MenetrendHeroCard(evaluation: eval, prefs: prefs),
          ),
        ),
      );

      await tester.tap(find.byType(MenetrendHeroCard));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.text('Bezárás'), findsOneWidget);

      await tester.ensureVisible(find.text('Bezárás'));
      await tester.tap(find.text('Bezárás'));
      // Pump frame-by-frame through the Hero pop flight to catch any transient overflow
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Bug 6: Reactive SettingsProvider, ThemeProvider, CommuteProvider & UI updates', () {
    test('Changing walkingSpeedKmh recalculates both morning and afternoon walk durations immediately & persists', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final settings = SettingsProvider(
        initialPrefs: const UserProfilePrefs(
          transitCardEnabled: true,
          transitHomeStation: 'Bodajk',
          transitSchoolStation: 'Székesfehérvár',
          walkingSpeedKmh: 5.0,
          transitAlertBufferMinutes: 15,
        ),
      );
      final theme = ThemeProvider(settings);
      final commute = CommuteProvider(settings);

      final dep = DateTime(2026, 11, 13, 7, 14);
      final arr = DateTime(2026, 11, 13, 7, 45);
      // 600s OTP walk at 5.0 km/h = 10 min; at 4.0 km/h -> 13 min; at 6.0 km/h -> 9 min.
      final trip = MenetrendTripOption(
        routeShortName: 'S150',
        routeLongName: 'Személyvonat',
        mode: MenetrendTransportMode.rail,
        departureStation: 'Bodajk',
        arrivalStation: 'Székesfehérvár',
        scheduledDeparture: dep,
        scheduledArrival: arr,
        walkToStationMinutes: 10,
        walkToDestinationMinutes: 10,
        baseWalkToStationSeconds: 600,
        baseWalkToDestinationSeconds: 600,
      );

      for (final isMorning in [true, false]) {
        await settings.updateWith((p) => p.copyWith(walkingSpeedKmh: 5.0));
        commute.setEvaluationForTesting(
          CommuteEvaluation(
            isMorningMode: isMorning,
            targetLesson: null,
            targetPeriodNumber: isMorning ? 1 : 5,
            recommendedTrip: trip,
            alternatives: [trip],
            effectiveWalkMinutes: 10,
            alertBufferMinutes: 15,
            now: dep.subtract(const Duration(minutes: 40)),
          ),
        );

        await settings.updateWith((p) => p.copyWith(walkingSpeedKmh: 4.0));
        expect(
          commute.evaluation!.effectiveWalkMinutes,
          13,
          reason: 'Slower walk speed (4.0 km/h) must increase walk time for isMorning=$isMorning',
        );
        expect(
          commute.evaluation!.recommendedTrip.walkToDestinationMinutes,
          13,
        );

        await settings.updateWith((p) => p.copyWith(walkingSpeedKmh: 6.0));
        expect(
          commute.evaluation!.effectiveWalkMinutes,
          8,
          reason: 'Faster walk speed (6.0 km/h) must decrease walk time for isMorning=$isMorning',
        );
      }

      var themeNotified = false;
      theme.addListener(() => themeNotified = true);
      await settings.updateWith(
        (p) => p.copyWith(
          themeStyle: AppThemeStyle.light,
          cardBlurEnabled: false,
          cardOpacity: 0.65,
        ),
      );
      await settings.flushPersistence();

      expect(themeNotified, isTrue);
      expect(theme.isLight, isTrue);
      expect(theme.hasSoftBlur, isFalse);
      expect(theme.cardOpacity, closeTo(0.65, 0.001));

      final reloaded = await TokenStorageService.loadProfilePrefsFromSharedPrefs();
      expect(reloaded, isNotNull);
      expect(reloaded!.walkingSpeedKmh, 6.0);
      expect(reloaded.themeStyle, AppThemeStyle.light);
      expect(reloaded.cardBlurEnabled, isFalse);
      expect(reloaded.cardOpacity, closeTo(0.65, 0.001));

      commute.dispose();
      theme.dispose();
      settings.dispose();
    });

    testWidgets('Settings toggles in AppSettingsScreen update Theme, SoftGlassCard opacity, and walking speed immediately', (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});

      final settings = SettingsProvider(
        initialPrefs: const UserProfilePrefs(
          themeStyle: AppThemeStyle.oledPureBlack,
          cardBlurEnabled: true,
          cardOpacity: 0.72,
          transitCardEnabled: true,
          transitHomeStation: 'Bodajk',
          transitSchoolStation: 'Székesfehérvár',
          walkingSpeedKmh: 5.0,
        ),
      );
      final theme = ThemeProvider(settings);
      final commute = CommuteProvider(settings);

      final dep = DateTime(2026, 11, 13, 7, 14);
      final trip = MenetrendTripOption(
        routeShortName: 'S150',
        routeLongName: 'Személyvonat',
        mode: MenetrendTransportMode.rail,
        departureStation: 'Bodajk',
        arrivalStation: 'Székesfehérvár',
        scheduledDeparture: dep,
        scheduledArrival: dep.add(const Duration(minutes: 31)),
        walkToStationMinutes: 10,
        baseWalkToStationSeconds: 600,
      );
      commute.setEvaluationForTesting(
        CommuteEvaluation(
          isMorningMode: true,
          targetLesson: null,
          targetPeriodNumber: 1,
          recommendedTrip: trip,
          alternatives: [trip],
          effectiveWalkMinutes: 10,
          alertBufferMinutes: 15,
          now: DateTime(2026, 11, 13, 6, 40),
        ),
      );

      await tester.pumpWidget(
        AppProvidersScope(
          settings: settings,
          theme: theme,
          commute: commute,
          child: ListenableBuilder(
            listenable: Listenable.merge([settings, theme, commute]),
            builder: (context, _) {
              final activeTheme = OledTheme.buildTheme(prefs: settings.prefs);
              return MaterialApp(
                theme: activeTheme,
                home: Scaffold(
                  body: Column(
                    children: [
                      MenetrendHeroCard(
                        evaluation: commute.evaluation!,
                        prefs: settings.prefs,
                      ),
                      SoftGlassCard(
                        prefs: settings.prefs,
                        child: Text(
                          'Walk:${commute.evaluation!.effectiveWalkMinutes}|Bright:${activeTheme.brightness.name}',
                        ),
                      ),
                      Expanded(
                        child: AppSettingsScreen(
                          session: _testSession(),
                          student: null,
                          kretaClient: KretaClient(),
                          prefs: settings.prefs,
                          onPrefsChanged: (next) => settings.updatePrefs(next),
                          onLogout: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Walk:10|Bright:dark'), findsOneWidget);

      // Open Appearance sub-screen inside MoreScreen/AppSettingsScreen and tap "Világos"
      await tester.tap(find.text('Megjelenés és témák'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Világos'));
      await tester.pumpAndSettle();
      expect(settings.prefs.themeStyle, AppThemeStyle.light);

      // Pop back to AppSettingsScreen, open MenetrendGO sub-screen, tap 6.0 km/h fast walk chip
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('MenetrendGO'));
      await tester.pumpAndSettle();

      final fastLabel = MenetrendService.walkingSpeedLabel(6.0);
      await tester.dragUntilVisible(
        find.text(fastLabel),
        find.byType(Scrollable).last,
        const Offset(0, -120),
      );
      await Scrollable.ensureVisible(
        tester.element(find.text(fastLabel)),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(fastLabel));
      await tester.pumpAndSettle();

      expect(settings.prefs.walkingSpeedKmh, 6.0);
      expect(commute.evaluation!.effectiveWalkMinutes, 8);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Walk:8|Bright:light'), findsOneWidget);

      commute.dispose();
      theme.dispose();
      settings.dispose();
    });
  });

  group('Bug 7: Delay notification deduplication (no spam on refresh or settings)', () {
    test('Sends delay notification once per state, skips refresh & settings updates, re-sends on delay change', () async {
      SharedPreferences.setMockInitialValues({});
      final invoked = <({String method, Map<String, dynamic> args})>[];
      Future<dynamic> fakeChannel(
        String method,
        Map<String, dynamic> args,
      ) async {
        invoked.add((method: method, args: args));
        return null;
      }

      final dep = DateTime(2026, 11, 13, 7, 14);
      CommuteEvaluation makeEval(int delayMinutes) {
        final trip = MenetrendTripOption(
          routeShortName: 'S150',
          routeLongName: 'Személyvonat',
          mode: MenetrendTransportMode.rail,
          departureStation: 'Bodajk',
          arrivalStation: 'Székesfehérvár',
          scheduledDeparture: dep,
          scheduledArrival: dep.add(const Duration(minutes: 31)),
          delayMinutes: delayMinutes,
          walkToStationMinutes: 5,
          tripId: 'MAV:34919',
        );
        return CommuteEvaluation(
          isMorningMode: true,
          targetLesson: null,
          targetPeriodNumber: 1,
          recommendedTrip: trip,
          alternatives: [trip],
          effectiveWalkMinutes: 5,
          alertBufferMinutes: 15,
          now: dep.subtract(const Duration(minutes: 25)),
        );
      }

      const prefs = UserProfilePrefs(
        transitCardEnabled: true,
        transitNotificationsEnabled: true,
        transitHomeStation: 'Bodajk',
        transitSchoolStation: 'Székesfehérvár',
      );

      // 1) Initial live sync with +6 min delay -> 1 delay notification sent
      final firstSent = await MenetrendService.syncNotificationsForEvaluation(
        evaluation: makeEval(6),
        prefs: prefs,
        allowDelayNotification: true,
        invokeNativeChannel: fakeChannel,
      );
      expect(firstSent, isTrue);
      expect(
        invoked
            .where((c) =>
                c.method == 'showTransitNotification' &&
                c.args['notificationId'] == 7092)
            .length,
        1,
      );

      // 2) Pull-to-refresh / periodic sync with unchanged +6 min delay -> ZERO spam
      final refreshSent = await MenetrendService.syncNotificationsForEvaluation(
        evaluation: makeEval(6),
        prefs: prefs,
        allowDelayNotification: true,
        invokeNativeChannel: fakeChannel,
      );
      expect(refreshSent, isFalse);
      expect(
        invoked
            .where((c) =>
                c.method == 'showTransitNotification' &&
                c.args['notificationId'] == 7092)
            .length,
        1,
      );

      // 3) Settings change sync with allowDelayNotification=false -> ZERO spam even if delay changed
      final settingsSent =
          await MenetrendService.syncNotificationsForEvaluation(
        evaluation: makeEval(10),
        prefs: prefs,
        allowDelayNotification: false,
        invokeNativeChannel: fakeChannel,
      );
      expect(settingsSent, isFalse);
      expect(
        invoked
            .where((c) =>
                c.method == 'showTransitNotification' &&
                c.args['notificationId'] == 7092)
            .length,
        1,
      );

      // 4) Actual commute sync when delay genuinely increased to +12 min -> sends updated notification
      final escalatedSent =
          await MenetrendService.syncNotificationsForEvaluation(
        evaluation: makeEval(12),
        prefs: prefs,
        allowDelayNotification: true,
        invokeNativeChannel: fakeChannel,
      );
      expect(escalatedSent, isTrue);
      expect(
        invoked
            .where((c) =>
                c.method == 'showTransitNotification' &&
                c.args['notificationId'] == 7092)
            .length,
        2,
      );
    });
  });
}
