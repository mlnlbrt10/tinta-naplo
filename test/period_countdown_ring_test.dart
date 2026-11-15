import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rekreta_app/providers/app_providers.dart';
import 'package:rekreta_app/screens/home_screen.dart';
import 'package:rekreta_app/screens/timetable_screen.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';

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
      'renders live second-by-second circular ring on next period during Break (Szünet)',
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

        // Ring is specifically on upcoming period '2.' (not '1.') at 50% remaining
        expect(findRingPainters(tester).length, 1);
        final period2Ring = tester.widget<CustomPaint>(
          find.descendant(
            of: find.ancestor(
              of: find.text('2.'),
              matching: find.byType(PeriodCountdownBadge),
            ),
            matching: find.byType(CustomPaint),
          ),
        );
        final initialPainter =
            period2Ring.painter as PeriodCountdownRingPainter;
        expect(initialPainter.remainingFraction, closeTo(0.5, 0.001));

        // Period 1 has NO countdown ring anymore
        expect(
          find.descendant(
            of: find.ancestor(
              of: find.text('1.'),
              matching: find.byType(PeriodCountdownBadge),
            ),
            matching: find.byType(CustomPaint),
          ),
          findsNothing,
        );

        // Advance clock by 3 minutes (now 4.5m / 15m = 0.30 remaining) & pump 1s ticker
        fakeNow = fakeNow.add(const Duration(minutes: 3));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        final updatedPainter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.ancestor(
                  of: find.text('2.'),
                  matching: find.byType(PeriodCountdownBadge),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter as PeriodCountdownRingPainter;
        expect(updatedPainter.remainingFraction, closeTo(0.3, 0.001));
      },
    );

    testWidgets(
      'renders full 1.0 ring >45m before school and depleting ring <=45m before school',
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

        var ring = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.ancestor(
                  of: find.text('1.'),
                  matching: find.byType(PeriodCountdownBadge),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter as PeriodCountdownRingPainter;
        expect(ring.remainingFraction, closeTo(1.0, 0.001));

        // Jump to 22m 30s before first bell (07:37:30 -> 50% of 45m window)
        fakeNow = DateTime(2026, 11, 13, 7, 37, 30);
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(milliseconds: 50));

        ring = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.ancestor(
                  of: find.text('1.'),
                  matching: find.byType(PeriodCountdownBadge),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter as PeriodCountdownRingPainter;
        expect(ring.remainingFraction, closeTo(0.5, 0.001));
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

  group('HomeScreen NextLessonHeroCard countdown ring', () {
    testWidgets(
      'displays circular countdown ring on NextLessonHeroCard during break and removes it once completed',
      (tester) async {
        var fakeNow = DateTime(2026, 11, 13, 8, 52, 30);
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

        final heroRing = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.ancestor(
                  of: find.text('2.'),
                  matching: find.byType(PeriodCountdownBadge),
                ),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter as PeriodCountdownRingPainter;
        expect(heroRing.remainingFraction, closeTo(0.5, 0.001));

        // Fast-forward past all lessons today and tick 1s timer -> no countdown ring
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
      },
    );
  });
}
