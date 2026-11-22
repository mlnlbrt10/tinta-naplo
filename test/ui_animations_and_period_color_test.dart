import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/grades_screen.dart';
import 'package:tinta_naplo/screens/home_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/screens/timetable_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/menetrend_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestKretaClient extends KretaClient {
  final DashboardData? data;
  final List<Lesson> lessons;

  _TestKretaClient({this.data, this.lessons = const []}) : super();

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async =>
      data;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession session, {
    DateTime? date,
  }) async {
    return data ??
        DashboardData(
          student: null,
          todaysLessons: lessons,
          allGrades: const [],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );
  }

  @override
  Future<List<Lesson>> fetchTimetableForRange(
    StoredSession session, {
    required DateTime from,
    required DateTime to,
  }) async =>
      lessons;
}

StoredSession _fakeSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

Grade _fakeGrade({
  required String uid,
  required String subjectName,
  required int value,
  required DateTime recordDate,
  int weightPercentage = 100,
}) {
  final iso = recordDate.toUtc().toIso8601String();
  return Grade.fromJson({
    'Uid': uid,
    'RogzitesDatuma': iso,
    'KeszitesDatuma': iso,
    'LattamozasDatuma': iso,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'cat', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Tema': 'Felelet',
    'Tipus': {
      'Uid': 'evkozi',
      'Nev': 'evkozi_jegy_ertekeles',
      'Leiras': 'Évközi jegy',
    },
    'Mod': {'Uid': 'm1', 'Nev': 'Írásbeli', 'Leiras': 'Írásbeli'},
    'ErtekFajta': {
      'Uid': '1,Szazalekos',
      'Nev': 'Szazalekos',
      'Leiras': 'Százalékos',
    },
    'ErtekeloTanarNeve': 'Teszt Tanár',
    'Jelleg': 'Ertekeles',
    'SzamErtek': value,
    'SzovegesErtek': '$value',
    'SulySzazalekErteke': weightPercentage,
    'SzovegesErtekelesRovidNev': '$value',
    'OsztalyCsoport': {'Uid': 'g1'},
    'SortIndex': 1,
  });
}

Lesson _fakeLesson({
  required String uid,
  required int lessonNumber,
  required String subjectName,
  required DateTime start,
  String stateName = 'Megtartott',
  String stateDesc = 'Megtartott óra',
  String? substituteTeacher,
  String roomName = '204',
  String teacherName = 'Nagy Péter',
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
    'TanarNeve': teacherName,
    'HelyettesTanarNeve': substituteTeacher,
    'TeremNeve': roomName,
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Allapot': {
      'Uid': stateName,
      'Nev': stateName,
      'Leiras': stateDesc,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('Feature 1: Főoldal per-card collapse & upward reflow', () {
    testWidgets(
      'Filter switches collapse non-matching cards and empty date headers in place, letting matching cards glide upward with zero BackdropFilter',
      (tester) async {
        final session = _fakeSession();
        final todayGrade = _fakeGrade(
          uid: 'g1',
          subjectName: 'Matematika',
          value: 5,
          recordDate: DateTime(2026, 11, 13, 10, 0),
        );
        final hwDue = DateTime(2026, 11, 12, 8, 0);
        final todayHw = Homework.fromJson({
          'Uid': 'hw1',
          'RogzitesIdopontja': hwDue.toIso8601String(),
          'FeladasDatuma': hwDue.toIso8601String(),
          'HataridoDatuma': hwDue.toIso8601String(),
          'Szoveg': 'Deriválási példatár',
          'RogzitoTanarNeve': 'Nagy Péter',
          'Tantargy': {
            'Uid': 'sub-fiz',
            'Nev': 'Fizika',
            'Kategoria': {'Uid': 'f', 'Nev': 'Fizika', 'Leiras': 'Fizika'},
          },
        });
        final olderExam = Test(
          uid: 't1',
          date: DateTime(2026, 11, 10, 11, 0),
          reportDate: DateTime(2026, 11, 10, 8, 0),
          teacherName: 'Tóth Éva',
          lessonNumber: 3,
          subject: Subject(
            uid: 'sub-tori',
            name: 'Történelem',
            category: NameUidDesc(uid: 'c', name: 'Történelem', description: ''),
            sortIndex: 2,
          ),
          subjectName: 'Történelem',
          theme: 'Reformkor témazáró',
          method: NameUidDesc(uid: 'm', name: 'Írásbeli', description: 'Írásbeli'),
          classGroup: UidObj(uid: 'g1'),
        );

        final cached = DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: [todayGrade],
          latestGrades: [todayGrade],
          homeworks: [todayHw],
          tests: [olderExam],
          omissions: const [],
          messages: const [],
          activeSession: session,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(
              prefs: const UserProfilePrefs(
                themeStyle: AppThemeStyle.oledPureBlack,
                cardBlurEnabled: true,
              ),
            ),
            home: HomeScreen(
              initialSession: session,
              initialCachedData: cached,
              kretaClient: _TestKretaClient(data: cached),
              prefs: const UserProfilePrefs(
                themeStyle: AppThemeStyle.oledPureBlack,
                cardBlurEnabled: true,
              ),
              onPrefsChanged: (_) {},
              onLogout: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mathCard = find
            .ancestor(of: find.text('Matematika'), matching: find.byType(SoftGlassCard))
            .first;
        final hwCard = find
            .ancestor(
              of: find.textContaining('Deriválási példatár'),
              matching: find.byType(SoftGlassCard),
            )
            .first;
        final examCard = find
            .ancestor(
              of: find.textContaining('Reformkor témazáró'),
              matching: find.byType(SoftGlassCard),
            )
            .first;

        // Scroll feed cards must never use BackdropFilter (120fps invariant)
        expect(
          find.descendant(of: mathCard, matching: find.byType(BackdropFilter)),
          findsNothing,
        );
        expect(
          find.descendant(of: hwCard, matching: find.byType(BackdropFilter)),
          findsNothing,
        );

        final mathSlot = find
            .ancestor(of: mathCard, matching: find.byType(ClipRect))
            .first;
        final hwSlot = find
            .ancestor(of: hwCard, matching: find.byType(ClipRect))
            .first;
        final examSlot = find
            .ancestor(of: examCard, matching: find.byType(ClipRect))
            .first;

        final initialHwTop = tester.getTopLeft(hwSlot).dy;
        final initialExamTop = tester.getTopLeft(examSlot).dy;
        expect(tester.getSize(mathSlot).height, greaterThan(0));
        expect(tester.getSize(hwSlot).height, greaterThan(0));
        expect(tester.getSize(examSlot).height, greaterThan(0));

        // Switch to 'Házik': Math grade & Nov 11 exam collapse to 0px while Hw glides upward
        await tester.tap(find.text('Házik'));
        await tester.pumpAndSettle();

        expect(tester.getSize(mathSlot).height, equals(0.0));
        expect(tester.getSize(examSlot).height, equals(0.0));
        expect(tester.getSize(hwSlot).height, greaterThan(0));
        expect(tester.getTopLeft(hwSlot).dy, lessThan(initialHwTop));

        // Switch to 'Számonkérések': Nov 11 exam glides up into place above previous position
        await tester.tap(find.text('Számonkérések'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.getSize(hwSlot).height, equals(0.0));
        expect(tester.getSize(examSlot).height, greaterThan(0));
        expect(tester.getTopLeft(examSlot).dy, lessThan(initialExamTop));

        // Switch back to 'Összes': cards smoothly expand back
        await tester.tap(find.text('Összes'));
        await tester.pumpAndSettle();
        expect(tester.getSize(mathSlot).height, greaterThan(0));
        expect(tester.getSize(hwSlot).height, greaterThan(0));
        expect(tester.getSize(examSlot).height, greaterThan(0));
      },
    );
  });

  group('Feature 2: LiquidBubbleTabBar across screens & 320px viewports', () {
    testWidgets(
      'LiquidBubbleTabBar fits 100% within 320px width with zero horizontal scrolling & FittedBox labels',
      (tester) async {
        var selectedIdx = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatefulBuilder(
                      builder: (context, setState) => LiquidBubbleTabBar(
                        selectedIndex: selectedIdx,
                        items: const [
                          LiquidBubbleTabItem(
                            label: 'Összes',
                            icon: Icons.view_stream_rounded,
                          ),
                          LiquidBubbleTabItem(
                            label: 'Jegyek',
                            icon: Icons.star_rounded,
                          ),
                          LiquidBubbleTabItem(
                            label: 'Házik',
                            icon: Icons.menu_book_rounded,
                          ),
                          LiquidBubbleTabItem(
                            label: 'Számonkérések',
                            icon: Icons.assignment_late_rounded,
                          ),
                        ],
                        onSelected: (i) => setState(() => selectedIdx = i),
                      ),
                    ),
                    const SizedBox(height: 12),
                    LiquidBubbleTabBar(
                      selectedIndex: 0,
                      fontSize: 12.5,
                      itemPadding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 5,
                      ),
                      items: const [
                        LiquidBubbleTabItem(
                          label: 'Összes',
                          icon: Icons.view_stream_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Igazolt',
                          icon: Icons.verified_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Igazolatlan',
                          icon: Icons.report_problem_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Késések',
                          icon: Icons.schedule_rounded,
                        ),
                      ],
                      onSelected: (_) {},
                    ),
                    const SizedBox(height: 12),
                    LiquidBubbleTabBar(
                      selectedIndex: 0,
                      fontSize: 12,
                      itemPadding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 5,
                      ),
                      items: const [
                        LiquidBubbleTabItem(
                          label: 'A-Z',
                          icon: Icons.sort_by_alpha_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Átlag ↑ (Javítandó)',
                          icon: Icons.trending_down_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Átlag ↓ (Legjobb)',
                          icon: Icons.trending_up_rounded,
                        ),
                      ],
                      onSelected: (_) {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        // Zero horizontal Scrollables inside any LiquidBubbleTabBar
        expect(
          find.descendant(
            of: find.byType(LiquidBubbleTabBar),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(
          find.descendant(
            of: find.byType(LiquidBubbleTabBar),
            matching: find.byType(FittedBox),
          ),
          findsNWidgets(11),
        );

        // All labels including longest segment sit inside 0..320 viewport bounds
        final examCenter = tester.getCenter(find.text('Számonkérések'));
        expect(examCenter.dx, lessThan(320.0));
        await tester.tap(find.text('Számonkérések'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 140));
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(milliseconds: 300));
        expect(selectedIdx, 3);
      },
    );

    testWidgets(
      'LiquidBubbleTabBar and LiquidSpringPillTrack support press-and-hold magnification, continuous drag, velocity squish, and release snap',
      (tester) async {
        var barSelected = 0;
        var dockSelected = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatefulBuilder(
                        builder: (context, setState) => LiquidBubbleTabBar(
                          selectedIndex: barSelected,
                          items: const [
                            LiquidBubbleTabItem(label: 'Összes'),
                            LiquidBubbleTabItem(label: 'Jegyek'),
                            LiquidBubbleTabItem(label: 'Házik'),
                            LiquidBubbleTabItem(label: 'Számonkérések'),
                          ],
                          onSelected: (i) => setState(() => barSelected = i),
                        ),
                      ),
                      const SizedBox(height: 24),
                      StatefulBuilder(
                        builder: (context, setState) => LiquidSpringPillTrack(
                          itemCount: 4,
                          selectedIndex: dockSelected,
                          height: 62,
                          pillWidth: 56,
                          pillHeight: 42,
                          onSelected: (i) => setState(() => dockSelected = i),
                          pillBuilder: (_, __) => const LiquidGlassPillSurface(
                            pressProgress: 0.0,
                            borderRadius: BorderRadius.all(Radius.circular(22)),
                          ),
                          interactivePillBuilder: (_, __, pressProgress) =>
                              LiquidGlassPillSurface(
                                pressProgress: pressProgress,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(22),
                                ),
                              ),
                          itemBuilder: (_, idx, __) =>
                              Center(child: Text('Tab$idx')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1) Press & hold on slot 0 of LiquidBubbleTabBar
        final barStartCenter = tester.getCenter(find.text('Összes'));
        final barEndCenter = tester.getCenter(find.text('Számonkérések'));
        final barTransformFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byType(Transform),
        );
        final barSurfaceFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byType(LiquidGlassPillSurface),
        );
        final barPillPositionedFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byType(Positioned),
        );

        final restLeft = tester.widget<Positioned>(barPillPositionedFinder).left!;

        final gesture = await tester.startGesture(barStartCenter);
        // Hold > 95ms triggers Liquid Glass magnification
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 180));

        final heldTransform = tester.widget<Transform>(barTransformFinder);
        expect(heldTransform.transform.entry(0, 0), greaterThanOrEqualTo(1.08));
        expect(heldTransform.transform.entry(1, 1), greaterThanOrEqualTo(1.08));
        expect(
          tester.widget<LiquidGlassPillSurface>(barSurfaceFinder).pressProgress,
          greaterThan(0.7),
        );
        // Selection stays uncommitted while still holding/dragging
        expect(barSelected, 0);

        // Continuously slide halfway across bar without releasing
        final midPoint = Offset.lerp(barStartCenter, barEndCenter, 0.45)!;
        await gesture.moveTo(Offset.lerp(barStartCenter, midPoint, 0.5)!);
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(midPoint);
        await tester.pump(const Duration(milliseconds: 16));

        final midLeft = tester.widget<Positioned>(barPillPositionedFinder).left!;
        final midTransform = tester.widget<Transform>(barTransformFinder);
        expect(midLeft, greaterThan(restLeft + 20.0));
        // Velocity squish stretches horizontally wider than vertically during fast glide
        expect(
          midTransform.transform.entry(0, 0),
          greaterThan(midTransform.transform.entry(1, 1)),
        );
        expect(barSelected, 0);

        // Finish sliding to final slot and release
        await gesture.moveTo(barEndCenter);
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.up();
        await tester.pump();
        expect(barSelected, 3);

        await tester.pump(const Duration(milliseconds: 300));
        final releasedTransform = tester.widget<Transform>(barTransformFinder);
        expect(releasedTransform.transform.entry(0, 0), closeTo(1.0, 0.02));
        expect(releasedTransform.transform.entry(1, 1), closeTo(1.0, 0.02));

        // 2) Same interactive hold + drag + snap verification on LiquidSpringPillTrack dock
        final dockStart = tester.getCenter(find.text('Tab0'));
        final dockEnd = tester.getCenter(find.text('Tab2'));
        final dockTransformFinder = find.descendant(
          of: find.byType(LiquidSpringPillTrack),
          matching: find.byType(Transform),
        );
        final dockGesture = await tester.startGesture(dockStart);
        await tester.pump(const Duration(milliseconds: 120));
        await tester.pump(const Duration(milliseconds: 180));
        expect(
          tester.widget<Transform>(dockTransformFinder).transform.entry(0, 0),
          greaterThanOrEqualTo(1.08),
        );
        await dockGesture.moveTo(dockEnd);
        await tester.pump(const Duration(milliseconds: 16));
        await dockGesture.up();
        await tester.pump();
        expect(dockSelected, 2);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester.widget<Transform>(dockTransformFinder).transform.entry(0, 0),
          closeTo(1.0, 0.02),
        );
      },
    );

    testWidgets(
      'GradesScreen uses LiquidBubbleTabBar with smooth ~260ms animated sort reflow & zero Hero conflicts',
      (tester) async {
        final grades = [
          _fakeGrade(
            uid: 'g1',
            subjectName: 'Biológia',
            value: 5,
            recordDate: DateTime(2026, 11, 10),
          ),
          _fakeGrade(
            uid: 'g2',
            subjectName: 'Fizika',
            value: 2,
            recordDate: DateTime(2026, 11, 11),
          ),
          _fakeGrade(
            uid: 'g3',
            subjectName: 'Kémia',
            value: 4,
            recordDate: DateTime(2026, 11, 12),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: Scaffold(
              body: GradesScreen(
                allGrades: grades,
                prefs: const UserProfilePrefs(),
                onPrefsChanged: (_) {},
                onRefresh: () async {},
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        expect(
          find.byWidgetPredicate((w) => w is LiquidBubbleTabBar),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(LiquidBubbleTabBar),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);

        // Initial A-Z order: Biológia < Fizika < Kémia
        final bioCard = find
            .ancestor(of: find.text('Biológia'), matching: find.byType(SoftGlassCard))
            .first;
        final fizCard = find
            .ancestor(of: find.text('Fizika'), matching: find.byType(SoftGlassCard))
            .first;
        final bioInitDy = tester.getTopLeft(bioCard).dy;
        final fizInitDy = tester.getTopLeft(fizCard).dy;
        expect(bioInitDy, lessThan(fizInitDy));

        // Tap 'Átlag ↑ (Javítandó)': Fizika (2.0) moves to slot 0 while Biológia (5.0) moves to slot 2
        await tester.tap(find.text('Átlag ↑ (Javítandó)'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);

        final fizMidDy = tester.getTopLeft(fizCard).dy;
        final bioMidDy = tester.getTopLeft(bioCard).dy;
        expect(fizMidDy, lessThan(fizInitDy));
        expect(fizMidDy, greaterThan(bioInitDy));
        expect(bioMidDy, greaterThan(bioInitDy));

        await tester.pump(const Duration(milliseconds: 220));
        final fizFinalDy = tester.getTopLeft(fizCard).dy;
        final bioFinalDy = tester.getTopLeft(bioCard).dy;
        expect(fizFinalDy, closeTo(bioInitDy, 2.0));
        expect(bioMidDy, lessThan(bioFinalDy));
        expect(fizFinalDy, lessThan(bioFinalDy));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Feature 3: Subject detail button-toggled ghosts & strictly 100% target advisor', () {
    test('calculate100PercentNeededPlan prioritizes lowest achievable 100% grade and faster 5 when strictly fewer', () {
      // Single 3 at 100% -> threshold 3.50:
      // 4 (100%): (3+4)/2 = 3.50 -> 1 db 4-es reaches 3.50; 5 also takes 1, so only 4-es!
      final oneThree = [
        _fakeGrade(
          uid: 'g1',
          subjectName: 'Töri',
          value: 3,
          recordDate: DateTime(2026, 11, 1),
        ),
      ];
      final planSingle4 = SubjectGradeSummary.calculate100PercentNeededPlan(
        currentGrades: oneThree,
        targetThreshold: 3.50,
      );
      expect(planSingle4.isReached, isFalse);
      expect(planSingle4.lowestOption, (gradeValue: 4, count: 1));
      expect(planSingle4.fasterFiveOption, isNull);

      // Three 3s -> avg 3.00 -> threshold 3.50:
      // 4 takes 3 ((9+12)/6 = 3.50), 5 takes 1 ((9+5)/4 = 3.50)!
      final threeThrees = [
        for (int i = 0; i < 3; i++)
          _fakeGrade(
            uid: 'g_$i',
            subjectName: 'Töri',
            value: 3,
            recordDate: DateTime(2026, 11, 1 + i),
          ),
      ];
      final planChoice = SubjectGradeSummary.calculate100PercentNeededPlan(
        currentGrades: threeThrees,
        targetThreshold: 3.50,
      );
      expect(planChoice.isReached, isFalse);
      expect(planChoice.lowestOption, (gradeValue: 4, count: 3));
      expect(planChoice.fasterFiveOption, (gradeValue: 5, count: 1));

      // Threshold 4.50 -> only 5 can reach it (100%)
      final planFive = SubjectGradeSummary.calculate100PercentNeededPlan(
        currentGrades: [
          _fakeGrade(
            uid: 'm1',
            subjectName: 'Matek',
            value: 4,
            weightPercentage: 200,
            recordDate: DateTime(2026, 11, 1),
          ),
        ],
        targetThreshold: 4.50,
      );
      expect(planFive.isReached, isFalse);
      expect(planFive.lowestOption, (gradeValue: 5, count: 2));
      expect(planFive.fasterFiveOption, isNull);
    });

    testWidgets(
      'Cél érdemjegy stays always visible with 100%-only text while Szellemjegyek expands/collapses on tap',
      (tester) async {
        final grades = [
          for (int i = 0; i < 3; i++)
            _fakeGrade(
              uid: 't$i',
              subjectName: 'Történelem',
              value: 3,
              recordDate: DateTime(2026, 11, 1 + i),
            ),
        ];
        final subjects = SubjectGradeSummary.groupBySubject(grades);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
            home: SubjectGradesDetailScreen(
              summary: subjects.first,
              allSubjects: subjects,
              prefs: const UserProfilePrefs(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Always visible target card with strictly 100%-only advice (for default target 5 -> 4.50)
        expect(find.text('Cél érdemjegy'), findsOneWidget);
        expect(find.textContaining('kell (cél:'), findsOneWidget);
        expect(find.textContaining('200%'), findsNothing);

        // Select target 4 -> threshold 3.50 -> suggests 1 db 5-ös (100%) vagy 3 db 4-es (100%)
        await tester.tap(find.text('4').first);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Még 1 db 5-ös (100%) vagy 3 db 4-es (100%) kell'),
          findsOneWidget,
        );
        expect(find.textContaining('200%'), findsNothing);

        // Ghost inputs hidden by default until toggle tapped
        expect(find.text('+5'), findsNothing);
        expect(find.text('Szellemjegy súlya'), findsNothing);

        // Expand ghost simulator
        await tester.tap(find.text('Szellemjegyek'));
        await tester.pumpAndSettle();
        expect(find.text('+5'), findsOneWidget);
        expect(find.text('Szellemjegy súlya'), findsOneWidget);

        // Collapse again
        await tester.tap(find.text('Szellemjegyek'));
        await tester.pumpAndSettle();
        expect(find.text('Cél érdemjegy'), findsOneWidget);
      },
    );
  });

  group('Feature 4: Theme-Synced Circular Timetable Lesson Cards & Decluttered Header', () {
    testWidgets(
      'Settings Megjelenés removes separate Órarend óraszámok színe picker so timetable syncs strictly with active theme',
      (tester) async {
        final session = _fakeSession();
        const currentPrefs = UserProfilePrefs();
        final settings = SettingsProvider(initialPrefs: currentPrefs);
        final themeProvider = ThemeProvider(settings);
        final commute = CommuteProvider(
          settings,
          menetrendService: MenetrendService(),
        );

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: themeProvider,
            commute: commute,
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => MaterialApp(
                theme: OledTheme.buildTheme(prefs: settings.prefs),
                home: AppSettingsScreen(
                  session: session,
                  student: null,
                  kretaClient: _TestKretaClient(),
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();
        expect(find.text('Órarend óraszámok színe'), findsNothing);
        expect(find.text('Egyedi HEX / RGB'), findsNothing);

        themeProvider.dispose();
        commute.dispose();
        settings.dispose();
      },
    );

    testWidgets(
      'TimetableScreen renders circular theme-tinted lesson badges, clean Terem • Tanár metadata, 2-line tabular times, and decluttered header',
      (tester) async {
        final session = _fakeSession();
        const greenAccent = Color(0xFF2E7D32);
        const blueAccent = Color(0xFF4DA3FF);
        final initialPrefs = UserProfilePrefs(
          seedColorValue: greenAccent.toARGB32(),
        );
        final settings = SettingsProvider(initialPrefs: initialPrefs);
        final themeProvider = ThemeProvider(settings);
        final commute = CommuteProvider(
          settings,
          menetrendService: MenetrendService(),
        );

        final fakeNow = DateTime(2026, 11, 16, 8, 15);
        final dayBase = DateTime(2026, 11, 16, 8, 0);
        final lessons = [
          _fakeLesson(
            uid: 'l1',
            lessonNumber: 1,
            subjectName: 'Matematika',
            start: dayBase,
            roomName: 'M1. 110',
            teacherName: 'Vas Dominik Vajk',
          ),
          _fakeLesson(
            uid: 'l2',
            lessonNumber: 2,
            subjectName: 'Fizika',
            start: dayBase.add(const Duration(minutes: 55)),
            roomName: '205',
            teacherName: 'Nagy Réka',
            stateName: 'Elmaradt',
            stateDesc: 'Elmaradt',
          ),
          _fakeLesson(
            uid: 'l3',
            lessonNumber: 3,
            subjectName: 'Irodalom',
            start: dayBase.add(const Duration(minutes: 110)),
            roomName: '108',
            teacherName: 'Tóth Béla',
            substituteTeacher: 'Kovács Réka',
          ),
        ];

        await tester.pumpWidget(
          AppProvidersScope(
            settings: settings,
            theme: themeProvider,
            commute: commute,
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => MaterialApp(
                theme: OledTheme.buildTheme(prefs: settings.prefs),
                home: Scaffold(
                  body: TimetableScreen(
                    session: session,
                    kretaClient: _TestKretaClient(lessons: lessons),
                    initialTodaysLessons: lessons,
                    prefs: settings.prefs,
                    onPrefsChanged: (_) {},
                    clock: () => fakeNow,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Decluttered header: no clock icon beside day name, plain muted count
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.text('3 óra'), findsOneWidget);

        // Clean 2-line hierarchy: no door icon, exact "Terem • Tanár" format
        expect(find.byIcon(Icons.meeting_room_rounded), findsNothing);
        expect(find.text('M1. 110 • Vas Dominik Vajk'), findsOneWidget);
        expect(find.text('108 • Kovács Réka'), findsOneWidget);

        // Two-line right-aligned tabular times
        expect(find.text('08:00'), findsOneWidget);
        expect(find.text('08:45'), findsOneWidget);
        final startTimeRect = tester.getRect(find.text('08:00'));
        final endTimeRect = tester.getRect(find.text('08:45'));
        expect(startTimeRect.top, lessThan(endTimeRect.top));

        // Period 1 (ongoing) has circular theme-tinted badge and NO extra blueAccent card border
        final activeScheme =
            Theme.of(tester.element(find.text('1.'))).colorScheme;
        final badge1Finder = find
            .ancestor(of: find.text('1.'), matching: find.byType(Container))
            .first;
        final badge1Deco =
            tester.widget<Container>(badge1Finder).decoration as BoxDecoration;
        expect(badge1Deco.shape, BoxShape.circle);
        expect(
          badge1Deco.color,
          activeScheme.primary.withValues(alpha: 0.14),
        );
        expect(
          tester.widget<Text>(find.text('1.')).style?.color,
          activeScheme.primary,
        );

        final noBlueGlowBorder = tester
            .widgetList<SoftGlassCard>(find.byType(SoftGlassCard))
            .any(
              (c) =>
                  c.border is Border &&
                  (c.border as Border).top.color == Colors.blueAccent,
            );
        expect(noBlueGlowBorder, isFalse);

        // Cancelled period 2 & substituted period 3 keep restrained semantic tints
        final badge2Deco = tester
            .widget<Container>(
              find
                  .ancestor(of: find.text('2.'), matching: find.byType(Container))
                  .first,
            )
            .decoration as BoxDecoration;
        expect(badge2Deco.shape, BoxShape.circle);
        expect(
          badge2Deco.color,
          const Color(0xFFEF5350).withValues(alpha: 0.14),
        );

        final badge3Deco = tester
            .widget<Container>(
              find
                  .ancestor(of: find.text('3.'), matching: find.byType(Container))
                  .first,
            )
            .decoration as BoxDecoration;
        expect(badge3Deco.shape, BoxShape.circle);
        expect(
          badge3Deco.color,
          const Color(0xFFF59E0B).withValues(alpha: 0.14),
        );

        // Switching the active theme accent reactively updates the circular lesson badge & modal badge
        unawaited(
          settings.updatePrefs(
            settings.prefs.copyWith(seedColorValue: blueAccent.toARGB32()),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        final updatedScheme =
            Theme.of(tester.element(find.text('1.'))).colorScheme;
        final updatedBadge1Deco = tester
            .widget<Container>(
              find
                  .ancestor(of: find.text('1.'), matching: find.byType(Container))
                  .first,
            )
            .decoration as BoxDecoration;
        expect(
          updatedBadge1Deco.color,
          updatedScheme.primary.withValues(alpha: 0.14),
        );
        expect(
          tester.widget<Text>(find.text('1.')).style?.color,
          updatedScheme.primary,
        );

        // Opening inspection modal shows matching circular translucent theme badge
        await tester.tap(find.text('Matematika'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final modalBadgeDeco = tester
            .widget<Container>(
              find
                  .ancestor(
                    of: find.text('1.').last,
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .decoration as BoxDecoration;
        expect(modalBadgeDeco.shape, BoxShape.circle);
        expect(
          modalBadgeDeco.color,
          updatedScheme.primary.withValues(alpha: 0.16),
        );

        themeProvider.dispose();
        commute.dispose();
        settings.dispose();
      },
    );
  });
}
