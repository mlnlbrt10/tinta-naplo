import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';

Lesson _makeLesson({
  required String uid,
  required int period,
  required String subjectName,
  required DateTime start,
  required DateTime end,
  bool cancelled = false,
}) {
  final dayIso = '${start.toIso8601String().split('T').first}T00:00:00Z';
  final stateName = cancelled ? 'Elmaradt' : 'Megtartott';
  return Lesson.fromJson({
    'Uid': uid,
    'Datum': dayIso,
    'Oraszam': period,
    'KezdetIdopont': start.toUtc().toIso8601String(),
    'VegIdopont': end.toUtc().toIso8601String(),
    'Nev': subjectName,
    'Tantargy': {
      'Uid': 'sub-$uid',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'k', 'Nev': 'Közismeret', 'Leiras': 'Közismeret'},
      'SortIndex': period,
    },
    'TanarNeve': 'Teszt Tanár',
    'TeremNeve': '101',
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Allapot': {
      'Uid': stateName,
      'Nev': stateName,
      'Leiras': stateName,
    },
    'Tema': 'Tananyag $period',
    'OsztalyCsoport': {'Uid': '11A', 'Nev': '11.A'},
    'IsTanuloHaziFeladatEnabled': false,
    'IsHaziFeladatMegoldva': false,
    'Csatolmanyok': const <Map<String, dynamic>>[],
    'IsDigitalisOra': false,
    'Letrehozas': dayIso,
    'UtolsoModositas': dayIso,
  });
}

StoredSession _fakeSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

class _FakeTimetableKretaClient extends KretaClient {
  final List<Lesson> lessons;
  _FakeTimetableKretaClient({required this.lessons}) : super();

  @override
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async =>
      lessons;
}

class _FakeHomeKretaClient extends KretaClient {
  final DashboardData data;
  _FakeHomeKretaClient(this.data) : super();

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      data;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession session, {
    DateTime? date,
  }) async =>
      data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PeriodCountdownInfo state machine', () {
    final day = DateTime(2026, 11, 13); // Friday
    final lesson1 = _makeLesson(
      uid: 'l1',
      period: 1,
      subjectName: 'Matematika',
      start: DateTime(2026, 11, 13, 8, 0),
      end: DateTime(2026, 11, 13, 8, 45),
    );
    final lesson2Cancelled = _makeLesson(
      uid: 'l2c',
      period: 2,
      subjectName: 'Tesi',
      start: DateTime(2026, 11, 13, 8, 50),
      end: DateTime(2026, 11, 13, 9, 35),
      cancelled: true,
    );
    final lesson3 = _makeLesson(
      uid: 'l3',
      period: 3,
      subjectName: 'Történelem',
      start: DateTime(2026, 11, 13, 9, 45),
      end: DateTime(2026, 11, 13, 10, 30),
    );

    test('before school (>45m -> 1.0 ready ring, <=45m -> smooth depletion)', () {
      final farBefore = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 6, 30),
        onlyOnDate: day,
      );
      expect(farBefore, isNotNull);
      expect(farBefore!.phase, PeriodCountdownPhase.beforeSchool);
      expect(farBefore.targetLesson.uid, 'l1');
      expect(farBefore.remainingFraction, closeTo(1.0, 0.0001));

      final at45m = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 7, 15),
        onlyOnDate: day,
      );
      expect(at45m!.phase, PeriodCountdownPhase.beforeSchool);
      expect(at45m.remainingFraction, closeTo(1.0, 0.0001));

      final atHalfway = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 7, 37, 30),
        onlyOnDate: day,
      );
      expect(atHalfway!.phase, PeriodCountdownPhase.beforeSchool);
      expect(atHalfway.targetLesson.uid, 'l1');
      expect(atHalfway.remainingFraction, closeTo(0.5, 0.0001));
    });

    test('ongoing lesson and break (Szünet) calculate exact remaining fractions', () {
      final ongoing = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 8, 22, 30),
        onlyOnDate: day,
      );
      expect(ongoing!.phase, PeriodCountdownPhase.ongoing);
      expect(ongoing.targetLesson.uid, 'l1');
      expect(ongoing.remainingFraction, closeTo(0.5, 0.0001));

      // Between 08:45 (lesson1.end) and 09:45 (lesson3.start) -> 60m break, cancelled lesson2 skipped
      final midpointBreak = PeriodCountdownInfo.evaluate(
        [lesson1, lesson2Cancelled, lesson3],
        DateTime(2026, 11, 13, 9, 15, 0),
        onlyOnDate: day,
      );
      expect(midpointBreak, isNotNull);
      expect(midpointBreak!.phase, PeriodCountdownPhase.inBreak);
      expect(midpointBreak.targetLesson.uid, 'l3');
      expect(midpointBreak.remainingFraction, closeTo(0.5, 0.0001));

      final lateBreak = PeriodCountdownInfo.evaluate(
        [lesson1, lesson2Cancelled, lesson3],
        DateTime(2026, 11, 13, 9, 39, 0),
        onlyOnDate: day,
      );
      expect(lateBreak!.phase, PeriodCountdownPhase.inBreak);
      expect(lateBreak.targetLesson.uid, 'l3');
      expect(lateBreak.remainingFraction, closeTo(0.1, 0.0001));
    });

    test('returns null after final lesson ends or when viewing another date', () {
      final afterAll = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 10, 30, 0),
        onlyOnDate: day,
      );
      expect(afterAll, isNull);

      final otherDate = PeriodCountdownInfo.evaluate(
        [lesson1, lesson3],
        DateTime(2026, 11, 13, 9, 15, 0),
        onlyOnDate: DateTime(2026, 11, 12),
      );
      expect(otherDate, isNull);
    });
  });

  group('TimetableScreen circular period countdown ring', () {
    List<PeriodCountdownRingPainter> findRingPainters(WidgetTester tester) {
      return tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((cp) => cp.painter)
          .whereType<PeriodCountdownRingPainter>()
          .toList();
    }

    Future<void> pumpTimetableAt(
      WidgetTester tester, {
      required List<Lesson> lessons,
      required DateTime Function() clock,
    }) async {
      final prefs = const UserProfilePrefs();
      final settings = SettingsProvider(initialPrefs: prefs);
      addTearDown(settings.dispose);
      final theme = ThemeProvider(settings);
      addTearDown(theme.dispose);
      final commute = CommuteProvider(settings);
      addTearDown(commute.dispose);

      await tester.pumpWidget(
        AppProvidersScope(
          settings: settings,
          theme: theme,
          commute: commute,
          child: MaterialApp(
            theme: OledTheme.buildTheme(prefs: prefs),
            home: Scaffold(
              body: TimetableScreen(
                session: _fakeSession(),
                kretaClient: _FakeTimetableKretaClient(lessons: lessons),
                initialTodaysLessons: lessons,
                prefs: prefs,
                onPrefsChanged: (_) {},
                clock: clock,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
      'inserts animated glowing BreakCountdownCard between lessons and shows zero ring on next period during Break (Szünet)',
      (tester) async {
        var fakeNow = DateTime(2026, 11, 13, 8, 52, 30); // Halfway in 15m break
        final lessons = [
          _makeLesson(
            uid: 'l1',
            period: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 11, 13, 8, 0),
            end: DateTime(2026, 11, 13, 8, 45),
          ),
          _makeLesson(
            uid: 'l2',
            period: 2,
            subjectName: 'Fizika',
            start: DateTime(2026, 11, 13, 9, 0),
            end: DateTime(2026, 11, 13, 9, 45),
          ),
        ];

        await pumpTimetableAt(
          tester,
          lessons: lessons,
          clock: () => fakeNow,
        );

        // NO circular countdown rings on either period 1 or period 2 during break
        expect(findRingPainters(tester), isEmpty);

        // BreakCountdownCard renders immediately without replay when mounted mid-break
        expect(find.byType(BreakCountdownCard), findsOneWidget);
        expect(find.text('Szünet'), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
        expect(find.text('08:45 – 09:00'), findsOneWidget);

        Iterable<BreakPerimeterCountdownPainter> findBreakPainters() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((cp) => cp.foregroundPainter)
            .whereType<BreakPerimeterCountdownPainter>();

        expect(findBreakPainters().length, 1);
        expect(findBreakPainters().first.progress, closeTo(0.5, 0.01));

        // Advance clock by 3 minutes (4.5m / 15m = 0.30 remaining) & pump 1s ticker
        fakeNow = fakeNow.add(const Duration(minutes: 3));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));
        expect(findBreakPainters().first.progress, closeTo(0.3, 0.01));

        // Advance to next lesson -> break card collapses & exits cleanly, lesson 2 ring appears
        fakeNow = DateTime(2026, 11, 13, 9, 5, 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 350));
        expect(findBreakPainters(), isEmpty);
        expect(findRingPainters(tester).length, 1);
      },
    );

    testWidgets(
      'shows zero circular countdown rings and zero BreakCountdownCard before school (Suli előtt)',
      (tester) async {
        var fakeNow = DateTime(2026, 11, 13, 6, 45); // 75m before 08:00
        final lessons = [
          _makeLesson(
            uid: 'l1',
            period: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 11, 13, 8, 0),
            end: DateTime(2026, 11, 13, 8, 45),
          ),
          _makeLesson(
            uid: 'l2',
            period: 2,
            subjectName: 'Fizika',
            start: DateTime(2026, 11, 13, 9, 0),
            end: DateTime(2026, 11, 13, 9, 45),
          ),
        ];

        await pumpTimetableAt(
          tester,
          lessons: lessons,
          clock: () => fakeNow,
        );

        expect(findRingPainters(tester), isEmpty);
        expect(find.byType(BreakCountdownCard), findsNothing);

        // Even inside <=45m pre-school window, zero circular ring before school starts
        fakeNow = DateTime(2026, 11, 13, 7, 37, 30);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        expect(findRingPainters(tester), isEmpty);
        expect(find.byType(BreakCountdownCard), findsNothing);
      },
    );

    testWidgets(
      'BreakCountdownCard animates in when ongoing lesson transitions live into break',
      (tester) async {
        var fakeNow = DateTime(2026, 11, 13, 8, 44, 59);
        final lessons = [
          _makeLesson(
            uid: 'l1',
            period: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 11, 13, 8, 0),
            end: DateTime(2026, 11, 13, 8, 45),
          ),
          _makeLesson(
            uid: 'l2',
            period: 2,
            subjectName: 'Fizika',
            start: DateTime(2026, 11, 13, 9, 0),
            end: DateTime(2026, 11, 13, 9, 45),
          ),
        ];

        await pumpTimetableAt(
          tester,
          lessons: lessons,
          clock: () => fakeNow,
        );

        expect(findRingPainters(tester).length, 1);
        expect(find.byType(BreakCountdownCard), findsNothing);

        fakeNow = DateTime(2026, 11, 13, 8, 45, 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.byType(BreakCountdownCard), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 220));
        expect(findRingPainters(tester), isEmpty);
        expect(find.byType(BreakCountdownCard), findsOneWidget);
      },
    );

    testWidgets(
      'final-minute <=60s triggers smooth refill animation and seconds label without false refill when mounted mid-minute',
      (tester) async {
        final start = DateTime(2026, 11, 13, 8, 0);
        final end = DateTime(2026, 11, 13, 8, 45);
        var fakeNow = DateTime(2026, 11, 13, 8, 43, 50); // 70s remaining

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: LiveCountdownProgressScope(
                startTime: start,
                endTime: end,
                clock: () => fakeNow,
                builder: (_, snap) => Row(
                  children: [
                    PeriodCountdownBadge(
                      label: '1.',
                      backgroundColor: Colors.blue.withValues(alpha: 0.2),
                      textStyle: const TextStyle(fontSize: 13),
                      ringColor: Colors.blue,
                      remainingFraction: snap.progress,
                    ),
                    Text(snap.formattedRemaining()),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('2 perc van hátra'), findsOneWidget);
        expect(findRingPainters(tester).first.remainingFraction,
            closeTo(70 / 2700, 0.002));

        // Cross into final 60s -> starts 500ms refill + switches label to seconds
        fakeNow = DateTime(2026, 11, 13, 8, 44, 1); // 59s remaining
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: LiveCountdownProgressScope(
                startTime: start,
                endTime: end,
                clock: () => fakeNow,
                builder: (_, snap) => Row(
                  children: [
                    PeriodCountdownBadge(
                      label: '1.',
                      backgroundColor: Colors.blue.withValues(alpha: 0.2),
                      textStyle: const TextStyle(fontSize: 13),
                      ringColor: Colors.blue,
                      remainingFraction: snap.progress,
                    ),
                    Text(snap.formattedRemaining()),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('59 mp'), findsOneWidget);

        await tester.pump(const Duration(milliseconds: 250));
        final midRefill = findRingPainters(tester).first.remainingFraction;
        expect(midRefill, greaterThan(0.5));
        expect(midRefill, lessThan(1.0));

        await tester.pump(const Duration(milliseconds: 300));
        expect(findRingPainters(tester).first.remainingFraction,
            closeTo(59 / 60, 0.01));

        // Mounted already inside final minute (30s left) -> immediate 0.5 without refill
        final midMinuteClock = DateTime(2026, 11, 13, 8, 44, 30);
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: PeriodCountdownBadge(
                label: '1.',
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                textStyle: const TextStyle(fontSize: 13),
                ringColor: Colors.blue,
                startTime: start,
                endTime: end,
                clock: () => midMinuteClock,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(findRingPainters(tester).first.remainingFraction,
            closeTo(0.5, 0.005));
      },
    );

    testWidgets(
      'shows zero active countdown rings after all lessons today end',
      (tester) async {
        // 16:00 (after last lesson, before 18:00 auto-advance threshold when jumping via Today)
        final fakeNow = DateTime(2026, 11, 13, 16, 0);
        final lessons = [
          _makeLesson(
            uid: 'l1',
            period: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 11, 13, 8, 0),
            end: DateTime(2026, 11, 13, 8, 45),
          ),
        ];

        await pumpTimetableAt(
          tester,
          lessons: lessons,
          clock: () => fakeNow,
        );

        // Even if explicitly switched back to Today ('P')
        await tester.tap(find.text('P'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(findRingPainters(tester), isEmpty);
      },
    );
  });

  group('HomeScreen NextLessonHeroCard countdown & break state', () {
    testWidgets(
      'displays pause icon + Szünet status without ring during break, shows zero ring before school, and clears once completed',
      (tester) async {
        var fakeNow = DateTime(2026, 11, 13, 7, 30, 0); // Before school
        final lessons = [
          _makeLesson(
            uid: 'l1',
            period: 1,
            subjectName: 'Matematika',
            start: DateTime(2026, 11, 13, 8, 0),
            end: DateTime(2026, 11, 13, 8, 45),
          ),
          _makeLesson(
            uid: 'l2',
            period: 2,
            subjectName: 'Kémia',
            start: DateTime(2026, 11, 13, 9, 0),
            end: DateTime(2026, 11, 13, 9, 45),
          ),
        ];
        final data = DashboardData(
          student: null,
          todaysLessons: lessons,
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: _fakeSession(),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: HomeScreen(
              initialSession: _fakeSession(),
              initialCachedData: data,
              kretaClient: _FakeHomeKretaClient(data),
              prefs: const UserProfilePrefs(),
              onPrefsChanged: (_) {},
              onLogout: () {},
              clock: () => fakeNow,
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Before school: NO circular progress ring
        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((cp) => cp.painter)
              .whereType<PeriodCountdownRingPainter>(),
          isEmpty,
        );

        // During break (08:52:30): clean pause icon & Szünet status, still zero ring
        fakeNow = DateTime(2026, 11, 13, 8, 52, 30);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byIcon(Icons.pause_rounded), findsWidgets);
        expect(find.text('Szünet'), findsOneWidget);
        expect(find.text('Szünet • 8 perc van hátra'), findsOneWidget);
        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((cp) => cp.painter)
              .whereType<PeriodCountdownRingPainter>(),
          isEmpty,
        );

        // Ongoing lesson (09:22:30): circular countdown ring renders actively
        fakeNow = DateTime(2026, 11, 13, 9, 22, 30);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        final rings = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((cp) => cp.painter)
            .whereType<PeriodCountdownRingPainter>()
            .toList();
        expect(rings.length, 1);
        expect(rings.first.remainingFraction, closeTo(0.5, 0.005));

        // Fast-forward past all lessons today -> no ring and no Szünet status
        fakeNow = DateTime(2026, 11, 13, 10, 0);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((cp) => cp.painter)
              .whereType<PeriodCountdownRingPainter>(),
          isEmpty,
        );
        expect(find.text('Szünet'), findsNothing);
      },
    );
  });
}
