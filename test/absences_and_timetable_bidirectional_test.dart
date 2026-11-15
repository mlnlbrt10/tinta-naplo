import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kreta_api/kreta_api.dart';

import 'package:rekreta_app/providers/app_providers.dart';
import 'package:rekreta_app/screens/more_screen.dart';
import 'package:rekreta_app/screens/timetable_screen.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/menetrend_service.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/animation_helpers.dart';

StoredSession _fakeSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Omission _makeOmission({
  required String uid,
  required String subjectName,
  required DateTime date,
  required int classNo,
  required OmissionState state,
  int? lateMinutes,
}) {
  final start = DateTime(date.year, date.month, date.day, 7 + classNo, 0);
  final end = start.add(const Duration(minutes: 45));
  return Omission.fromJson({
    'Uid': uid,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'c1', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Ora': {
      'KezdoDatum': start.toUtc().toIso8601String(),
      'VegDatum': end.toUtc().toIso8601String(),
      'Oraszam': classNo,
    },
    'Datum': date.toUtc().toIso8601String(),
    'RogzitoTanarNeve': 'Teszt Tanár',
    'Tipus': lateMinutes != null
        ? {'Uid': 'keses', 'Nev': 'Keses', 'Leiras': 'Késés'}
        : {'Uid': 'hianyzas', 'Nev': 'Hianyzas', 'Leiras': 'Hiányzás'},
    'KesesPercben': lateMinutes,
    'KeszitesDatuma': start.toUtc().toIso8601String(),
    'IgazolasAllapota': state.key,
  });
}

Lesson _makeLesson({
  required String uid,
  required int lessonNumber,
  required String subjectName,
  required DateTime start,
}) {
  final end = start.add(const Duration(minutes: 45));
  final dayIso = '${start.toIso8601String().split('T').first}T00:00:00Z';
  return Lesson.fromJson({
    'Uid': uid,
    'Datum': dayIso,
    'Oraszam': lessonNumber,
    'KezdetIdopont': start.toUtc().toIso8601String(),
    'VegIdopont': end.toUtc().toIso8601String(),
    'Nev': subjectName,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'c', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': lessonNumber,
    },
    'OsztalyCsoport': {'Uid': 'g1', 'Nev': '11.A'},
    'TanarNeve': 'Teszt Tanár',
    'TeremNeve': '101',
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Tema': 'Tananyag',
    'Allapot': {'Uid': '1', 'Nev': 'Megtartott', 'Leiras': 'Megtartott'},
    'HaziFeladatUid': null,
    'IsTanuloHaziFeladatEnabled': false,
    'IsHaziFeladatMegoldva': false,
    'Csatolmanyok': const <Map<String, dynamic>>[],
    'IsDigitalisOra': false,
    'Letrehozas': dayIso,
    'UtolsoModositas': dayIso,
  });
}

class _StubDashboardKretaClient extends KretaClient {
  _StubDashboardKretaClient()
      : super(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
          storage: const TokenStorageService(),
        );

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      null;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) =>
      Completer<DashboardData>().future;
}

class _SpyMultiWeekKretaClient extends KretaClient {
  final Map<DateTime, List<Lesson>> lessonsByWeekMonday;
  final List<DateTime> fetchedWeekMondays = [];

  _SpyMultiWeekKretaClient({required this.lessonsByWeekMonday})
      : super(
          httpClient: MockClient((_) async => http.Response('[]', 200)),
          storage: const TokenStorageService(),
        );

  @override
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async {
    final normalized = DateTime(from.year, from.month, from.day);
    fetchedWeekMondays.add(normalized);
    return lessonsByWeekMonday[normalized] ?? const [];
  }
}

Widget _wrapWithProviders({
  required UserProfilePrefs prefs,
  required Widget home,
}) {
  final settings = SettingsProvider(initialPrefs: prefs);
  addTearDown(settings.dispose);
  final themeProvider = ThemeProvider(settings);
  addTearDown(themeProvider.dispose);
  final commute = CommuteProvider(
    settings,
    menetrendService: MenetrendService(),
  );
  addTearDown(commute.dispose);
  return AppProvidersScope(
    settings: settings,
    theme: themeProvider,
    commute: commute,
    child: MaterialApp(
      theme: OledTheme.buildTheme(prefs: prefs),
      home: home,
    ),
  );
}

void main() {
  group('Part 1: Hiányzások fixed header, ClipRect & zero scroll animations', () {
    List<Omission> buildManyOmissions() {
      final list = <Omission>[];
      for (int i = 1; i <= 20; i++) {
        final date = DateTime(2026, 9, i);
        list.add(
          _makeOmission(
            uid: 'om_exc_$i',
            subjectName: 'Matematika $i',
            date: date,
            classNo: 1,
            state: i % 5 == 0
                ? OmissionState.unexcused
                : OmissionState.excused,
            lateMinutes: i == 19 ? 10 : null,
          ),
        );
      }
      return list;
    }

    for (final liquidGlass in [true, false]) {
      testWidgets(
        'AllOmissionsScreen keeps fixed non-overlapping header & filter bar across fast scroll, replays zero StaggeredEntranceItem, and animates filter switches (liquidGlass: $liquidGlass)',
        (tester) async {
          final prefs = UserProfilePrefs(liquidGlassEnabled: liquidGlass);
          final omissions = buildManyOmissions();

          await tester.pumpWidget(
            _wrapWithProviders(
              prefs: prefs,
              home: AllOmissionsScreen(
                omissions: omissions,
                prefs: prefs,
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));

          final titleFinder = find.text('Összes hiányzás és késés');
          final tabBarFinder = find.byType(LiquidBubbleTabBar);
          final listViewFinder = find.byType(ListView);

          expect(titleFinder, findsOneWidget);
          expect(tabBarFinder, findsOneWidget);
          expect(listViewFinder, findsOneWidget);

          // Zero scroll/mount entrance animations on absence cards
          expect(find.byType(StaggeredEntranceItem), findsNothing);

          // Solid mode must contain zero BackdropFilter widgets
          if (!liquidGlass) {
            expect(find.byType(BackdropFilter), findsNothing);
          } else {
            expect(find.byType(BackdropFilter), findsAtLeastNWidgets(1));
          }

          final initialTitleTop = tester.getTopLeft(titleFinder).dy;
          final initialTabBarRect = tester.getRect(tabBarFinder);
          final listClipRect = tester.getRect(
            find.ancestor(
              of: listViewFinder,
              matching: find.byType(ClipRect),
            ).first,
          );
          expect(
            listClipRect.top,
            greaterThanOrEqualTo(initialTabBarRect.bottom - 0.5),
          );

          // Fast scroll fling down so offscreen cards mount
          await tester.fling(listViewFinder, const Offset(0, -1400), 2500);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump(const Duration(milliseconds: 300));

          // Header & filter bar remain pinned in place and visible
          expect(titleFinder, findsOneWidget);
          expect(tabBarFinder, findsOneWidget);
          expect(tester.getTopLeft(titleFinder).dy, initialTitleTop);
          expect(tester.getRect(tabBarFinder), initialTabBarRect);
          expect(find.byType(StaggeredEntranceItem), findsNothing);

          // Switch filter segment -> AnimatedSwitcher smoothly transitions filtered items
          await tester.tap(
          find.descendant(
            of: find.byType(LiquidBubbleTabBar).last,
            matching: find.text('Késések'),
          ),
        );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          expect(find.byType(AnimatedSwitcher), findsAtLeastNWidgets(1));
          await tester.pump(const Duration(milliseconds: 220));
          expect(find.text('Matematika 19'), findsOneWidget);
          expect(find.text('Matematika 20'), findsNothing);
        },
      );
    }

    testWidgets(
      'MoreScreen attendance tab has zero StaggeredEntranceItem on absence cards and uses SliverFadeTransition on filter switches',
      (tester) async {
        const prefs = UserProfilePrefs(liquidGlassEnabled: true);
        final omissions = buildManyOmissions();
        final client = _StubDashboardKretaClient();

        await tester.pumpWidget(
          _wrapWithProviders(
            prefs: prefs,
            home: Scaffold(
              body: MoreScreen(
                session: _fakeSession(),
                student: null,
                kretaClient: client,
                initialOmissions: omissions,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Absence list items inside SliverFadeTransition must have zero StaggeredEntranceItem wrappers
        expect(find.byType(SliverFadeTransition), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverFadeTransition),
            matching: find.byType(StaggeredEntranceItem),
          ),
          findsNothing,
        );

        // Scroll fast down -> still zero entrance animations on absence cards
        await tester.fling(
          find.byType(CustomScrollView).first,
          const Offset(0, -1200),
          2200,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.descendant(
            of: find.byType(SliverFadeTransition),
            matching: find.byType(StaggeredEntranceItem),
          ),
          findsNothing,
        );

        // Switch filter segment back at top -> SliverFadeTransition runs without card entrance replay
        await tester.fling(
          find.byType(CustomScrollView).first,
          const Offset(0, 1400),
          2200,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.descendant(
            of: find.byType(LiquidBubbleTabBar).last,
            matching: find.text('Késések'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Matematika 19'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverFadeTransition),
            matching: find.byType(StaggeredEntranceItem),
          ),
          findsNothing,
        );
      },
    );
  });

  group('Part 2: Órarend bidirectional continuous multi-week PageView', () {
    test(
      'resolveTimetablePageOffset maps negative and positive relative offsets with floor division',
      () {
        expect(
          resolveTimetablePageOffset(page: 500, basePage: 500, daysPerWeek: 5),
          (weekOffset: 0, dayIndex: 0),
        );
        expect(
          resolveTimetablePageOffset(page: 504, basePage: 500, daysPerWeek: 5),
          (weekOffset: 0, dayIndex: 4),
        );
        expect(
          resolveTimetablePageOffset(page: 505, basePage: 500, daysPerWeek: 5),
          (weekOffset: 1, dayIndex: 0),
        );
        expect(
          resolveTimetablePageOffset(page: 499, basePage: 500, daysPerWeek: 5),
          (weekOffset: -1, dayIndex: 4),
        );
        expect(
          resolveTimetablePageOffset(page: 495, basePage: 500, daysPerWeek: 5),
          (weekOffset: -1, dayIndex: 0),
        );
        expect(
          resolveTimetablePageOffset(page: 494, basePage: 500, daysPerWeek: 5),
          (weekOffset: -2, dayIndex: 4),
        );
        expect(
          resolveTimetablePageOffset(page: 499, basePage: 500, daysPerWeek: 6),
          (weekOffset: -1, dayIndex: 5),
        );
      },
    );

    for (final liquidGlass in [true, false]) {
      testWidgets(
        'supports seamless backward swipe (Monday -> prev week Friday), forward swipe, arrow Monday jumps, adjacent prefetch, and outer PageView isolation (liquidGlass: $liquidGlass)',
        (tester) async {
          // Fixed Wednesday morning (2026-11-18 10:00)
          final fixedNow = DateTime(2026, 11, 18, 10, 0);
          final week0Monday = DateTime(2026, 11, 16);
          final weekMinus1Monday = DateTime(2026, 11, 9);
          final weekMinus2Monday = DateTime(2026, 11, 2);
          final weekPlus1Monday = DateTime(2026, 11, 23);

          final lessonsByWeek = <DateTime, List<Lesson>>{
            weekMinus2Monday: [
              _makeLesson(
                uid: 'w_m2_mon',
                lessonNumber: 1,
                subjectName: 'W-2_Mon',
                start: DateTime(2026, 11, 2, 8, 0),
              ),
              _makeLesson(
                uid: 'w_m2_fri',
                lessonNumber: 1,
                subjectName: 'W-2_Fri',
                start: DateTime(2026, 11, 6, 8, 0),
              ),
            ],
            weekMinus1Monday: [
              for (int d = 0; d < 5; d++)
                _makeLesson(
                  uid: 'w_m1_d$d',
                  lessonNumber: 1,
                  subjectName:
                      'W-1_${['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][d]}',
                  start: DateTime(2026, 11, 9 + d, 8, 0),
                ),
            ],
            week0Monday: [
              for (int d = 0; d < 5; d++)
                _makeLesson(
                  uid: 'w0_d$d',
                  lessonNumber: 1,
                  subjectName:
                      'W0_${['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][d]}',
                  start: DateTime(2026, 11, 16 + d, 8, 0),
                ),
            ],
            weekPlus1Monday: [
              for (int d = 0; d < 5; d++)
                _makeLesson(
                  uid: 'w1_d$d',
                  lessonNumber: 1,
                  subjectName:
                      'W1_${['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][d]}',
                  start: DateTime(2026, 11, 23 + d, 8, 0),
                ),
            ],
          };

          final client = _SpyMultiWeekKretaClient(
            lessonsByWeekMonday: lessonsByWeek,
          );
          final prefs = UserProfilePrefs(
            showWeekends: false,
            liquidGlassEnabled: liquidGlass,
          );
          final outerTabController = PageController(initialPage: 2);
          addTearDown(outerTabController.dispose);

          await tester.pumpWidget(
            _wrapWithProviders(
              prefs: prefs,
              home: Scaffold(
                body: PageView(
                  controller: outerTabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    const SizedBox.shrink(),
                    const SizedBox.shrink(),
                    TimetableScreen(
                      session: _fakeSession(),
                      kretaClient: client,
                      initialTodaysLessons: const [],
                      prefs: prefs,
                      onPrefsChanged: (_) {},
                      clock: () => fixedNow,
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          // Initial day = Wednesday of Week 0, and adjacent weeks (-1 and +1) are pre-fetched
          expect(find.text('W0_Wed'), findsOneWidget);
          expect(find.text('11. 16.–11. 20.'), findsOneWidget);
          expect(
            tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar))
                .selectedIndex,
            2,
          );
          expect(client.fetchedWeekMondays, contains(weekMinus1Monday));
          expect(client.fetchedWeekMondays, contains(weekPlus1Monday));

          // Jump to Monday ('H') of Week 0
          await tester.tap(find.text('H'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('W0_Mon'), findsOneWidget);
          expect(
            tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar))
                .selectedIndex,
            0,
          );

          // Backward cross-week swipe from Monday ('H') -> previous week's Friday ('P')!
          final innerPageView = find.byType(PageView).last;
          await tester.drag(innerPageView, const Offset(450, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(outerTabController.page, 2.0);
          expect(find.text('W-1_Fri'), findsOneWidget);
          expect(find.text('11. 09.–11. 13.'), findsOneWidget);
          final prevFriTabBar = tester.widget<LiquidBubbleTabBar>(
            find.byType(LiquidBubbleTabBar),
          );
          expect(prevFriTabBar.selectedIndex, 4);
          expect(prevFriTabBar.pageOffset, 495.0);
          expect(client.fetchedWeekMondays, contains(weekMinus2Monday));

          // Forward cross-week swipe from previous week's Friday ('P') -> Week 0 Monday ('H')!
          await tester.drag(innerPageView, const Offset(-450, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.text('W0_Mon'), findsOneWidget);
          expect(find.text('11. 16.–11. 20.'), findsOneWidget);
          final backToMonTabBar = tester.widget<LiquidBubbleTabBar>(
            find.byType(LiquidBubbleTabBar),
          );
          expect(backToMonTabBar.selectedIndex, 0);
          expect(backToMonTabBar.pageOffset, 500.0);

          // Tap Thursday ('Cs', index 3), then tap Previous Week ('<') -> both pill & list glide to Monday of Week -1!
          await tester.tap(find.text('Cs'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('W0_Thu'), findsOneWidget);

          await tester.tap(find.byTooltip('Előző hét'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump(const Duration(milliseconds: 220));
          expect(find.text('W-1_Mon'), findsOneWidget);
          expect(find.text('11. 09.–11. 13.'), findsOneWidget);
          expect(
            tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar))
                .selectedIndex,
            0,
          );

          // Tap Friday ('P', index 4) in Week -1, then tap Next Week ('>') -> both pill & list glide to Monday of Week 0!
          await tester.tap(find.text('P'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('W-1_Fri'), findsOneWidget);

          await tester.tap(find.byTooltip('Következő hét'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump(const Duration(milliseconds: 220));
          expect(find.text('W0_Mon'), findsOneWidget);
          expect(find.text('11. 16.–11. 20.'), findsOneWidget);
          expect(
            tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar))
                .selectedIndex,
            0,
          );
        },
      );
    }

    testWidgets(
      'Timetable PageView day lists & cards render statically at scroll offset 0.0 with RepaintBoundary and zero entrance animations across H -> K -> Sze -> Cs -> P swipes',
      (tester) async {
        final fixedNow = DateTime(2026, 11, 16, 10, 0); // Monday morning
        final week0Monday = DateTime(2026, 11, 16);

        final multiLessonWeek = <DateTime, List<Lesson>>{
          week0Monday: [
            for (int d = 0; d < 4; d++)
              for (int p = 1; p <= 8; p++)
                _makeLesson(
                  uid: 'static_d${d}_p$p',
                  lessonNumber: p,
                  subjectName: 'Nap${d}_Ora$p',
                  start: DateTime(2026, 11, 16 + d, 7 + p, 0),
                ),
            // Day 4 (Friday) intentionally empty to verify empty day card too
          ],
        };

        final client = _SpyMultiWeekKretaClient(
          lessonsByWeekMonday: multiLessonWeek,
        );
        const prefs = UserProfilePrefs(
          showWeekends: false,
          liquidGlassEnabled: true,
        );

        await tester.pumpWidget(
          _wrapWithProviders(
            prefs: prefs,
            home: Scaffold(
              body: TimetableScreen(
                session: _fakeSession(),
                kretaClient: client,
                initialTodaysLessons: const [],
                prefs: prefs,
                onPrefsChanged: (_) {},
                clock: () => fixedNow,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final pageViewFinder = find.byType(PageView);
        expect(pageViewFinder, findsOneWidget);

        void expectStaticDayAtZero(
          int dayOffset, {
          required bool expectFirstLesson,
        }) {
          final dayTitle = '2026. 11. ${16 + dayOffset}.';
          expect(find.textContaining(dayTitle), findsOneWidget);
          final dayListViewFinder = find.ancestor(
            of: find.textContaining(dayTitle),
            matching: find.byType(ListView),
          );
          expect(dayListViewFinder, findsOneWidget);

          expect(
            find.descendant(
              of: dayListViewFinder,
              matching: find.byType(StaggeredEntranceItem),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: dayListViewFinder,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is TweenAnimationBuilder ||
                    w is AnimatedSlide ||
                    w is AnimatedOpacity,
              ),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: dayListViewFinder,
              matching: find.byType(RepaintBoundary),
            ),
            findsAtLeastNWidgets(expectFirstLesson ? 2 : 1),
          );
          final scrollableState = tester.state<ScrollableState>(
            find.descendant(
              of: dayListViewFinder,
              matching: find.byType(Scrollable),
            ),
          );
          expect(scrollableState.position.pixels, 0.0);
          if (expectFirstLesson) {
            expect(
              find.descendant(
                of: dayListViewFinder,
                matching: find.text('1.'),
              ),
              findsOneWidget,
            );
          }
        }

        // Day 0 (H): starts statically at offset 0.0 on lesson 1.
        expectStaticDayAtZero(0, expectFirstLesson: true);
        expect(find.text('Nap0_Ora1'), findsOneWidget);

        // Scroll down on Monday before swiping -> Tuesday must still start cleanly at 0.0!
        await tester.drag(
          find.ancestor(
            of: find.text('Nap0_Ora1'),
            matching: find.byType(ListView),
          ),
          const Offset(0, -300),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Swipe horizontally across K, Sze, Cs, and P (empty day)
        for (int d = 1; d <= 4; d++) {
          await tester.drag(pageViewFinder, const Offset(-450, 0));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 450));
          if (d < 4) {
            expectStaticDayAtZero(d, expectFirstLesson: true);
            expect(find.text('Nap${d}_Ora1'), findsOneWidget);
          } else {
            expectStaticDayAtZero(d, expectFirstLesson: false);
            expect(
              find.text('Erre a napra nincs rögzített tanóra.'),
              findsOneWidget,
            );
          }
        }
      },
    );
  });
}
