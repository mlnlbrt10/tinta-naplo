import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/menetrend_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';

StoredSession _fakeSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Lesson _fakeLesson({
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
    'TanarNeve': 'Nagy Péter',
    'TeremNeve': '204',
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Allapot': {
      'Uid': 'Megtartott',
      'Nev': 'Megtartott',
      'Leiras': 'Megtartott óra',
    },
    'Tema': 'Tananyag $lessonNumber',
    'OsztalyCsoport': {'Uid': '11A', 'Nev': '11.A'},
    'IsTanuloHaziFeladatEnabled': false,
    'IsHaziFeladatMegoldva': false,
    'Csatolmanyok': const <Map<String, dynamic>>[],
    'IsDigitalisOra': false,
    'Letrehozas': dayIso,
    'UtolsoModositas': dayIso,
  });
}

class _MultiWeekKretaClient extends KretaClient {
  final Map<DateTime, List<Lesson>> lessonsByWeekMonday;

  _MultiWeekKretaClient({required this.lessonsByWeekMonday})
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
    return lessonsByWeekMonday[normalized] ?? const [];
  }
}

void main() {
  group('Feature 1: Fluid Liquid Glass Physics & Elastic Edge Overscroll', () {
    testWidgets(
      'LiquidBubbleTabBar allows ~15px rubber-band overscroll past both ends, deforms like a droplet, and springs back on release',
      (tester) async {
        int selected = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: SizedBox(
                      width: 360,
                      child: LiquidBubbleTabBar(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        selectedIndex: selected,
                        onSelected: (idx) => setState(() => selected = idx),
                        items: const [
                          LiquidBubbleTabItem(label: 'Első'),
                          LiquidBubbleTabItem(label: 'Második'),
                          LiquidBubbleTabItem(label: 'Harmadik'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tabBarFinder = find.byType(LiquidBubbleTabBar);
        final pillFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        final transformFinder = find.descendant(
          of: pillFinder,
          matching: find.byType(Transform),
        );
        final stackFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byType(Stack),
        );

        for (final stack in tester.widgetList<Stack>(stackFinder)) {
          expect(stack.clipBehavior, Clip.none);
        }

        final restingPill = tester.widget<Positioned>(pillFinder);
        final restingLeft = restingPill.left!;
        final pillWidth = restingPill.width!;

        // 1. Long-press left item & pull far past LEFT track edge (-80px)
        final firstSlotCenter = tester.getCenter(find.text('Első'));
        final leftGesture = await tester.startGesture(firstSlotCenter);
        await tester.pump(const Duration(milliseconds: 95));
        await tester.pump(const Duration(milliseconds: 95));

        final heldSurface = tester.widget<LiquidGlassPillSurface>(
          find.byType(LiquidGlassPillSurface),
        );
        expect(heldSurface.pressProgress, greaterThan(0.8));

        for (int i = 0; i < 6; i++) {
          await leftGesture.moveBy(const Offset(-14, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }

        final overscrolledLeftPill = tester.widget<Positioned>(pillFinder);
        // Smooth rubber-band displacement past left boundary (~6 to 15.5px)
        expect(overscrolledLeftPill.left!, lessThan(restingLeft - 5.0));
        expect(overscrolledLeftPill.left!, greaterThanOrEqualTo(restingLeft - 16.0));

        // Check droplet deformation: horizontal stretch, vertical squash, subtle tilt skew
        final leftDragMatrix =
            tester.widget<Transform>(transformFinder).transform;
        final dragScaleX = leftDragMatrix.entry(0, 0);
        final dragScaleY = leftDragMatrix.entry(1, 1);
        final dragSkew = leftDragMatrix.entry(0, 1);
        expect(dragScaleX, greaterThan(1.14));
        expect(dragScaleY, lessThan(dragScaleX));
        expect(dragSkew.abs(), greaterThan(0.001));

        // Release -> springs smoothly back to index 0
        await leftGesture.up();
        await tester.pumpAndSettle();

        final settledLeftPill = tester.widget<Positioned>(pillFinder);
        expect(settledLeftPill.left!, closeTo(restingLeft, 0.5));
        expect(
          tester.widget<Transform>(transformFinder).transform.entry(0, 0),
          closeTo(1.0, 0.01),
        );
        expect(selected, 0);

        // 2. Tap rightmost tab, settle, then pull past RIGHT track edge (+80px)
        await tester.tap(find.text('Harmadik'));
        await tester.pumpAndSettle();
        expect(selected, 2);

        final rightEdgePill = tester.widget<Positioned>(pillFinder);
        final rightEdgePos = rightEdgePill.left!;

        final thirdSlotCenter = tester.getCenter(find.text('Harmadik'));
        final rightGesture = await tester.startGesture(thirdSlotCenter);
        await tester.pump(const Duration(milliseconds: 95));
        for (int i = 0; i < 6; i++) {
          await rightGesture.moveBy(const Offset(14, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }

        final overscrolledRightPill = tester.widget<Positioned>(pillFinder);
        expect(overscrolledRightPill.left!, greaterThan(rightEdgePos + 5.0));
        expect(
          overscrolledRightPill.left! + pillWidth,
          lessThanOrEqualTo(rightEdgePos + pillWidth + 16.0),
        );

        await rightGesture.up();
        await tester.pumpAndSettle();

        final settledRightPill = tester.widget<Positioned>(pillFinder);
        expect(settledRightPill.left!, closeTo(rightEdgePos, 0.5));
        expect(selected, 2);
      },
    );

    testWidgets(
      'LiquidGlassSurface dock mode keeps child LiquidSpringPillTrack outside BackdropFilter ClipRRect so overscroll is never sliced',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: LiquidGlassSurface(
                    prefs: const UserProfilePrefs(cardBlurEnabled: true),
                    isDockStyle: true,
                    borderRadius: BorderRadius.circular(32),
                    child: LiquidSpringPillTrack(
                      itemCount: 4,
                      selectedIndex: 0,
                      height: 62,
                      pillWidth: 56,
                      pillHeight: 42,
                      onSelected: (_) {},
                      pillBuilder: (_, __) => const LiquidGlassPillSurface(
                        pressProgress: 0.0,
                      ),
                      itemBuilder: (_, idx, __) => Center(child: Text('T$idx')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // BackdropFilter must blur in a sibling layer behind LiquidSpringPillTrack,
        // not clip its child track via ClipRRect ancestor.
        expect(find.byType(BackdropFilter), findsOneWidget);
        expect(
          find.ancestor(
            of: find.byType(LiquidSpringPillTrack),
            matching: find.byType(ClipRRect),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'LiquidBubbleTabBar supports 2D vertical rubber-band pull, volume-preserving droplet stretch, highlight shift, and elastic jelly release',
      (tester) async {
        int selected = 1;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: SizedBox(
                      width: 340,
                      child: LiquidBubbleTabBar(
                        selectedIndex: selected,
                        onSelected: (i) => setState(() => selected = i),
                        items: const [
                          LiquidBubbleTabItem(label: 'Első'),
                          LiquidBubbleTabItem(label: 'Második'),
                          LiquidBubbleTabItem(label: 'Harmadik'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final tabBarFinder = find.byType(LiquidBubbleTabBar);
        final pillFinder = find.descendant(
          of: tabBarFinder,
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        final transformFinder = find.descendant(
          of: pillFinder,
          matching: find.byType(Transform),
        );

        final restingPill = tester.widget<Positioned>(pillFinder);
        final restingLeft = restingPill.left!;
        final restingTop = restingPill.top!;
        expect(restingTop, closeTo(0.0, 0.01));

        // Hold middle item (>= 90ms) and pull purely downward (+60px).
        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Második')),
        );
        await tester.pump(const Duration(milliseconds: 95));
        await tester.pump(const Duration(milliseconds: 95));

        expect(
          tester.widget<LiquidGlassPillSurface>(
            find.byType(LiquidGlassPillSurface),
          ).pressProgress,
          greaterThan(0.8),
        );

        for (int i = 0; i < 5; i++) {
          await gesture.moveBy(const Offset(0, 12));
          await tester.pump(const Duration(milliseconds: 16));
        }

        final downPill = tester.widget<Positioned>(pillFinder);
        // Active hold+drag allows damped vertical rubber-band pull within ±7px
        expect(downPill.top!, inInclusiveRange(3.0, 8.0));

        final downMatrix = tester.widget<Transform>(transformFinder).transform;
        final downScaleX = downMatrix.entry(0, 0);
        final downScaleY = downMatrix.entry(1, 1);
        expect(downScaleY, greaterThan(downScaleX));
        expect(downScaleY, greaterThanOrEqualTo(1.08));

        // 1px–1.2px stadium rim painter stays clean without chord stripe bars.
        final downSurface = tester.widget<LiquidGlassPillSurface>(
          find.byType(LiquidGlassPillSurface),
        );
        expect(downSurface.highlightBias.dy, greaterThan(0.35));
        expect(
          find.descendant(
            of: find.byType(LiquidGlassPillSurface),
            matching: find.byType(Align),
          ),
          findsNothing,
        );
        final downRimPaint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(LiquidGlassPillSurface),
            matching: find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is LiquidGlassRimPainter,
            ),
          ),
        );
        final rimPainter = downRimPaint.painter! as LiquidGlassRimPainter;
        expect(rimPainter.strokeWidth, inInclusiveRange(1.0, 1.2));
        for (final c in rimPainter.buildPerimeterColors()) {
          expect(c.r, closeTo(1.0, 0.001));
          expect(c.g, closeTo(1.0, 0.001));
          expect(c.b, closeTo(1.0, 0.001));
          expect(c.a, greaterThan(0.0));
        }
        expect(
          rimPainter.buildPerimeterColors().last.a,
          greaterThan(0.30),
        );

        // Diagonal drag right & upward slides X smoothly and pulls Y upward within -7px.
        for (int i = 0; i < 9; i++) {
          await gesture.moveBy(const Offset(8, -16));
          await tester.pump(const Duration(milliseconds: 16));
        }
        final diagPill = tester.widget<Positioned>(pillFinder);
        expect(diagPill.left!, greaterThan(restingLeft + 15.0));
        expect(diagPill.top!, lessThan(-3.0));
        expect(diagPill.top!, greaterThanOrEqualTo(-8.0));

        // Elastic release springs both X and Y back cleanly.
        await gesture.up();
        await tester.pumpAndSettle();

        final settledPill = tester.widget<Positioned>(pillFinder);
        expect(settledPill.top!, closeTo(0.0, 0.05));
        final restMatrix = tester.widget<Transform>(transformFinder).transform;
        expect(restMatrix.entry(0, 0), closeTo(1.0, 0.01));
        expect(restMatrix.entry(1, 1), closeTo(1.0, 0.01));
      },
    );

    testWidgets(
      'LiquidBubbleTabBar inside vertical ListView does not hijack fast vertical scroll gestures',
      (tester) async {
        final scrollCtrl = ScrollController();
        addTearDown(scrollCtrl.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: SizedBox(
                height: 320,
                child: ListView(
                  controller: scrollCtrl,
                  children: [
                    const SizedBox(height: 180),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: LiquidBubbleTabBar(
                        selectedIndex: 0,
                        onSelected: (_) {},
                        items: const [
                          LiquidBubbleTabItem(label: 'Első'),
                          LiquidBubbleTabItem(label: 'Második'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 900),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pillFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );

        // Immediate vertical scroll swipe without holding must scroll ListView normally.
        await tester.drag(find.text('Első'), const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 120));

        expect(scrollCtrl.offset, greaterThan(30.0));
        expect(tester.widget<Positioned>(pillFinder).top!, closeTo(0.0, 0.01));
        expect(
          tester.widget<LiquidGlassPillSurface>(
            find.byType(LiquidGlassPillSurface),
          ).pressProgress,
          closeTo(0.0, 0.01),
        );

        // Hold >= 90ms and drag vertically: translateY remains 0 and ListView stays steady
        scrollCtrl.jumpTo(0.0);
        await tester.pump();

        final holdGesture = await tester.startGesture(
          tester.getCenter(find.text('Első')),
        );
        await tester.pump(const Duration(milliseconds: 95));
        for (int i = 0; i < 4; i++) {
          await holdGesture.moveBy(const Offset(0, 12));
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(tester.widget<Positioned>(pillFinder).top!, inInclusiveRange(3.0, 8.0));
        expect(scrollCtrl.offset, closeTo(0.0, 0.01));

        await holdGesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Simple tap segment switch keeps translateY strictly 0 during horizontal travel and triggers arrival vertical rebound',
      (tester) async {
        int selected = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Center(
                    child: SizedBox(
                      width: 340,
                      child: LiquidBubbleTabBar(
                        selectedIndex: selected,
                        onSelected: (i) => setState(() => selected = i),
                        items: const [
                          LiquidBubbleTabItem(label: 'Első'),
                          LiquidBubbleTabItem(label: 'Második'),
                          LiquidBubbleTabItem(label: 'Harmadik'),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pillFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        final transformFinder = find.descendant(
          of: pillFinder,
          matching: find.byType(Transform),
        );
        expect(tester.widget<Positioned>(pillFinder).top!, closeTo(0.0, 0.01));

        await tester.tap(find.text('Harmadik'));
        double maxScaleX = 1.0;
        double minScaleY = 1.0;
        double maxArrivalScaleY = 1.0;
        for (int i = 0; i < 28; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final pill = tester.widget<Positioned>(pillFinder);
          expect(pill.top!, closeTo(0.0, 0.001));
          final m = tester.widget<Transform>(transformFinder).transform;
          final sx = m.entry(0, 0);
          final sy = m.entry(1, 1);
          if (sx > maxScaleX) maxScaleX = sx;
          if (sy < minScaleY) minScaleY = sy;
          if (sy > maxArrivalScaleY) maxArrivalScaleY = sy;
        }
        expect(maxScaleX, greaterThan(1.055));
        expect(maxScaleX, lessThanOrEqualTo(1.10));
        expect(minScaleY, lessThan(0.975));
        expect(maxArrivalScaleY, greaterThan(1.035));
        expect(maxArrivalScaleY, lessThanOrEqualTo(1.07));

        await tester.pumpAndSettle();
        expect(selected, 2);
        expect(tester.widget<Positioned>(pillFinder).top!, closeTo(0.0, 0.001));
        final settled = tester.widget<Transform>(transformFinder).transform;
        expect(settled.entry(0, 0), closeTo(1.0, 0.001));
        expect(settled.entry(1, 1), closeTo(1.0, 0.001));
      },
    );
  });

  group('Feature 2: Settings Screen Clean Top Margin', () {
    testWidgets(
      'AppSettingsScreen renders first Settings card cleanly below transparent AppBar without double-toolbar blank gap',
      (tester) async {
        const prefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.oledPureBlack,
        );
        final client = _MultiWeekKretaClient(lessonsByWeekMonday: const {});

        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(400, 820),
              padding: EdgeInsets.only(top: 24),
            ),
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: prefs),
              home: AppSettingsScreen(
                session: _fakeSession(),
                student: null,
                kretaClient: client,
                prefs: prefs,
                onPrefsChanged: (_) {},
                onLogout: () {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));

        final appBarRect = tester.getRect(find.byType(AppBar));
        final firstCardFinder = find
            .ancestor(
              of: find.text('Fiók és munkamenet'),
              matching: find.byType(SoftGlassCard),
            )
            .first;
        final firstCardRect = tester.getRect(firstCardFinder);

        final topGapBelowAppBar = firstCardRect.top - appBarRect.bottom;
        expect(firstCardRect.top, greaterThanOrEqualTo(appBarRect.bottom));
        expect(topGapBelowAppBar, greaterThanOrEqualTo(4.0));
        expect(topGapBelowAppBar, lessThanOrEqualTo(20.0));
      },
    );
  });

  group('Features 3 & 4: Timetable Stadium Weekday Bar, Dynamic Szo & +1 Week Auto-Monday', () {
    testWidgets(
      'TimetableScreen uses stadium LiquidBubbleTabBar, dynamically shows Szo only when Saturday has lessons, and auto-jumps to Monday on +1 week button or past-last-day swipe',
      (tester) async {
        final now = DateTime.now();
        var initialDay = DateUtils.dateOnly(now);
        if (initialDay.weekday > 5) {
          initialDay = initialDay.add(Duration(days: 8 - initialDay.weekday));
        } else if (now.hour >= 18) {
          initialDay = initialDay.add(
            Duration(days: initialDay.weekday == 5 ? 3 : 1),
          );
        }
        final week1Monday =
            initialDay.subtract(Duration(days: initialDay.weekday - 1));
        final week2Monday = week1Monday.add(const Duration(days: 7));
        final week3Monday = week1Monday.add(const Duration(days: 14));

        // Week 1: Mon-Fri only (NO Saturday lessons)
        final week1Lessons = [
          for (int d = 0; d < 5; d++)
            _fakeLesson(
              uid: 'w1_d$d',
              lessonNumber: 1,
              subjectName: 'W1_Day$d',
              start: week1Monday.add(Duration(days: d, hours: 8)),
            ),
        ];

        // Week 2: Mon-Fri PLUS Saturday lesson!
        final week2Lessons = [
          _fakeLesson(
            uid: 'w2_mon',
            lessonNumber: 1,
            subjectName: 'Második hét hétfő matek',
            start: week2Monday.add(const Duration(hours: 8)),
          ),
          _fakeLesson(
            uid: 'w2_sat',
            lessonNumber: 1,
            subjectName: 'Szombati szakkör',
            start: week2Monday.add(const Duration(days: 5, hours: 9)),
          ),
        ];

        // Week 3: Mon-Fri only (NO Saturday lessons)
        final week3Lessons = [
          _fakeLesson(
            uid: 'w3_mon',
            lessonNumber: 1,
            subjectName: 'Harmadik hét hétfő fizika',
            start: week3Monday.add(const Duration(hours: 8)),
          ),
        ];

        const prefs = UserProfilePrefs(
          showWeekends: false,
          liquidGlassEnabled: true,
        );
        final settings = SettingsProvider(initialPrefs: prefs);
        addTearDown(settings.dispose);
        final themeProvider = ThemeProvider(settings);
        addTearDown(themeProvider.dispose);
        final commute = CommuteProvider(
          settings,
          menetrendService: MenetrendService(),
        );
        addTearDown(commute.dispose);
        final client = _MultiWeekKretaClient(
          lessonsByWeekMonday: {
            week1Monday: week1Lessons,
            week2Monday: week2Lessons,
            week3Monday: week3Lessons,
          },
        );

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: themeProvider,
            commute: commute,
            child: MaterialApp(
              theme: OledTheme.buildTheme(prefs: prefs),
              home: Scaffold(
                body: TimetableScreen(
                  session: _fakeSession(),
                  kretaClient: client,
                  initialTodaysLessons: const [],
                  prefs: prefs,
                  onPrefsChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Feature 4: Full-stadium pill bar with zero horizontal scroll; no 'Szo' in Week 1
        final tabBar = tester.widget<LiquidBubbleTabBar>(
          find.byType(LiquidBubbleTabBar),
        );
        expect(tabBar.items.length, 5);
        expect(find.text('H'), findsOneWidget);
        expect(find.text('K'), findsOneWidget);
        expect(find.text('Sze'), findsOneWidget);
        expect(find.text('Cs'), findsOneWidget);
        expect(find.text('P'), findsOneWidget);
        expect(find.text('Szo'), findsNothing);

        final stadiumContainer = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(LiquidBubbleTabBar),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is Container &&
                      w.decoration is BoxDecoration &&
                      (w.decoration as BoxDecoration).borderRadius ==
                          BorderRadius.circular(999),
                ),
              )
              .first,
        );
        expect(stadiumContainer.clipBehavior, Clip.none);

        // Select Wednesday ('Sze', index 2) and confirm PageView syncs
        await tester.tap(find.text('Sze'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar)).selectedIndex,
          2,
        );
        expect(find.text('W1_Day2'), findsOneWidget);

        // Swipe PageView forward to Thursday ('Cs', index 3) -> pill bar follows
        await tester.drag(find.byType(PageView), const Offset(-450, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar)).selectedIndex,
          3,
        );
        expect(find.text('W1_Day3'), findsOneWidget);

        // Feature 3 (Part 1): Tap Next Week button -> auto-jumps to Week 2 Monday ('H', index 0)
        // AND Week 2 has Saturday lessons so 'Szo' dynamically appears!
        await tester.tap(find.byTooltip('Következő hét'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        final week2TabBar = tester.widget<LiquidBubbleTabBar>(
          find.byType(LiquidBubbleTabBar),
        );
        expect(week2TabBar.selectedIndex, 0);
        expect(week2TabBar.items.length, 6);
        expect(find.text('Szo'), findsOneWidget);
        expect(find.text('Második hét hétfő matek'), findsOneWidget);

        // Navigate to Saturday ('Szo', last day of Week 2)
        await tester.tap(find.text('Szo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester.widget<LiquidBubbleTabBar>(find.byType(LiquidBubbleTabBar)).selectedIndex,
          5,
        );
        expect(find.text('Szombati szakkör'), findsOneWidget);

        // Feature 3 (Part 2): Swipe left past the last day (Saturday) into Week 3
        // -> transitions to Week 3 Monday ('H', index 0), and 'Szo' disappears again
        await tester.drag(find.byType(PageView), const Offset(-450, 0));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 300));

        final week3TabBar = tester.widget<LiquidBubbleTabBar>(
          find.byType(LiquidBubbleTabBar),
        );
        expect(week3TabBar.selectedIndex, 0);
        expect(week3TabBar.items.length, 5);
        expect(find.text('Szo'), findsNothing);
        expect(find.text('Harmadik hét hétfő fizika'), findsOneWidget);
      },
    );

    testWidgets(
      'Tapping week/date chip opens custom Tinta OLED/Liquid Glass calendar modal (not stock CalendarDatePicker) with month nav, weekday columns, and Ma jump',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final mondayNov16 = DateTime(2026, 11, 16);
        final mondayNov23 = DateTime(2026, 11, 23);
        final client = _MultiWeekKretaClient(
          lessonsByWeekMonday: {
            mondayNov16: [
              _fakeLesson(
                uid: 'cal-nov16',
                lessonNumber: 1,
                subjectName: 'Hétfő Matek',
                start: DateTime(2026, 11, 16, 8, 0),
              ),
            ],
            mondayNov23: [
              _fakeLesson(
                uid: 'cal-nov24',
                lessonNumber: 1,
                subjectName: 'Kedd Irodalom',
                start: DateTime(2026, 11, 24, 9, 0),
              ),
            ],
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: TimetableScreen(
                session: _fakeSession(),
                kretaClient: client,
                initialTodaysLessons: const [],
                homeworks: const [],
                prefs: const UserProfilePrefs(
                  themeStyle: AppThemeStyle.oledPureBlack,
                  liquidGlassEnabled: true,
                ),
                onPrefsChanged: (_) {},
                clock: () => mondayNov16,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap week date range chip -> opens custom Tinta calendar picker
        await tester.tap(find.byTooltip('Dátum választása'));
        await tester.pumpAndSettle();

        expect(find.byType(CalendarDatePicker), findsNothing);
        expect(find.byType(DatePickerDialog), findsNothing);
        expect(find.text('2026. november'), findsOneWidget);
        for (final wd in ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V']) {
          expect(find.text(wd), findsWidgets);
        }

        // Navigate month forward & back
        await tester.tap(find.byTooltip('Következő hónap'));
        await tester.pumpAndSettle();
        expect(find.text('2026. december'), findsOneWidget);

        await tester.tap(find.byTooltip('Előző hónap'));
        await tester.pumpAndSettle();
        expect(find.text('2026. november'), findsOneWidget);

        // Pick day 24 (Tuesday Nov 24) -> jumps to that week/day
        await tester.tap(find.text('24').last);
        await tester.pumpAndSettle();
        expect(find.text('Kedd Irodalom'), findsOneWidget);

        // Reopen and tap header 'Ma' quick-jump pill -> jumps straight back to Nov 16
        await tester.tap(find.byTooltip('Dátum választása'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Ma').last);
        await tester.pumpAndSettle();
        expect(find.text('Hétfő Matek'), findsOneWidget);
      },
    );
  });
}
