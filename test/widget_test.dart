import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rekreta_app/main.dart';
import 'package:rekreta_app/screens/about_app_screen.dart';
import 'package:rekreta_app/screens/grades_screen.dart';
import 'package:rekreta_app/screens/home_screen.dart';
import 'package:rekreta_app/screens/more_screen.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/animation_helpers.dart';
import 'package:rekreta_app/widgets/christmas_snowfall_overlay.dart';
import 'package:rekreta_app/widgets/edge_fade_horizontal_scroll.dart';
import 'package:rekreta_app/widgets/frosted_inspection_modal.dart';
import 'package:rekreta_app/widgets/glass_card.dart';
import 'package:rekreta_app/widgets/skeleton_shimmer.dart';
import 'package:rekreta_app/widgets/tinta_splash_overlay.dart';

Lesson _makeLesson({
  required String uid,
  required String subjectName,
  required DateTime start,
  required DateTime end,
  String stateName = 'Megtartott',
  String teacherName = 'Teszt Tanár',
  int count = 1,
}) {
  return Lesson.fromJson({
    'Uid': uid,
    'Datum': start.toUtc().toIso8601String(),
    'KezdetIdopont': start.toUtc().toIso8601String(),
    'VegIdopont': end.toUtc().toIso8601String(),
    'Nev': subjectName,
    'Oraszam': count,
    'OraEvesSorszama': count,
    'OsztalyCsoport': {'Uid': 'g1', 'Nev': '11.A'},
    'TanarNeve': teacherName,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'cat1', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'TeremNeve': '204',
    'Tipus': {'Uid': 't1', 'Nev': 'Tanóra', 'Leiras': 'Tanóra'},
    'TanuloJelenlet': {'Uid': 'j1', 'Nev': 'Jelen', 'Leiras': 'Jelen'},
    'Allapot': {'Uid': 'a1', 'Nev': stateName, 'Leiras': stateName},
    'Tema': 'Téma',
    'FeladatGroupUid': '',
    'NyelviFeladatGroupUid': '',
    'BejelentettSzamonkeresUid': '',
    'IsTanoranKivuliizma': false,
    'IsDigitalisOra': false,
    'HaziFeladatUid': '',
    'IsTanuloHaziFeladatEnabled': false,
    'IsHaziFeladatMegoldva': false,
    'Csatolmanyok': <Map<String, dynamic>>[],
    'Letrehozas': start.toUtc().toIso8601String(),
    'UtolsoModositas': start.toUtc().toIso8601String(),
  });
}

Grade _makeGrade({
  required String uid,
  required String subjectName,
  required int value,
  int weight = 100,
}) {
  final nowIso = DateTime(2026, 11, 10, 10, 0).toUtc().toIso8601String();
  return Grade.fromJson({
    'Uid': uid,
    'RogzitesDatuma': nowIso,
    'KeszitesDatuma': nowIso,
    'LattamozasDatuma': nowIso,
    'Tantargy': {
      'Uid': 'sub_$subjectName',
      'Nev': subjectName,
      'Kategoria': {'Uid': 'cat1', 'Nev': subjectName, 'Leiras': subjectName},
      'SortIndex': 1,
    },
    'Tema': 'Dolgozat',
    'Tipus': {
      'Uid': 'evkozi_jegy_ertekeles',
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
    'SulySzazalekErteke': weight,
    'SzovegesErtekelesRovidNev': '$value',
    'OsztalyCsoport': {'Uid': 'g1'},
    'SortIndex': 1,
  });
}

void main() {
  test('OledTheme supports OLED Pure Black, Standard Dark, and Light modes', () {
    final oled = OledTheme.buildTheme(
      prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
    );
    final stdDark = OledTheme.buildTheme(
      prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.standardDark),
    );
    final light = OledTheme.buildTheme(
      prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.light),
    );

    expect(oled.scaffoldBackgroundColor, Colors.black);
    expect(stdDark.brightness, Brightness.dark);
    expect(light.brightness, Brightness.light);
  });

  test('GradeRoundingConfig evaluates custom rounding thresholds accurately', () {
    const custom = GradeRoundingConfig(
      threshold5: 4.60,
      threshold4: 3.50,
      threshold3: 2.50,
      threshold2: 2.00,
    );

    expect(custom.evaluateRoundedGrade(4.55), 4);
    expect(custom.evaluateRoundedGrade(4.60), 5);
    expect(custom.evaluateRoundedGrade(1.85), 1);
    expect(custom.evaluateRoundedGrade(2.00), 2);
  });

  test('GhostGrade simulator computes weighted averages and needed grades', () {
    final avg = SubjectGradeSummary.computeWeightedAverage(
      const [],
      const [
        GhostGrade(value: 4, weightPercentage: 100),
        GhostGrade(value: 5, weightPercentage: 200),
      ],
    );
    expect(avg, closeTo(14.0 / 3.0, 0.001));

    final neededForFive = SubjectGradeSummary.calculateNeededGradesCount(
      currentGrades: const [],
      ghostGrades: const [GhostGrade(value: 4, weightPercentage: 100)],
      targetThreshold: 4.50,
      gradeValue: 5,
      weightPercentage: 100,
    );
    expect(neededForFive, 1);
  });

  test('NextLessonStatus state machine handles ongoing, <2h, >2h, and completed lessons', () {
    final lesson1 = _makeLesson(
      uid: 'l1',
      subjectName: 'Matematika',
      start: DateTime(2026, 11, 10, 8, 0),
      end: DateTime(2026, 11, 10, 8, 45),
      count: 1,
    );
    final lesson2 = _makeLesson(
      uid: 'l2',
      subjectName: 'Történelem',
      start: DateTime(2026, 11, 10, 9, 0),
      end: DateTime(2026, 11, 10, 9, 45),
      count: 2,
    );

    // 1. More than 2 hours before first lesson (05:30 -> 2h30m before 08:00)
    final farBefore = NextLessonStatus.evaluate(
      [lesson1, lesson2],
      DateTime(2026, 11, 10, 5, 30),
    );
    expect(farBefore.phase, NextLessonPhase.beforeFirstFarAway);
    expect(farBefore.headline, 'Matematika');
    expect(farBefore.countdownLabel, 'Kezdés: 2ó 30p 0mp');

    // 2. Within 2 hours before first lesson (07:15 -> 45 mins before 08:00)
    final nearBefore = NextLessonStatus.evaluate(
      [lesson1, lesson2],
      DateTime(2026, 11, 10, 7, 15),
    );
    expect(nearBefore.phase, NextLessonPhase.beforeFirstWithinTwoHours);
    expect(nearBefore.countdownLabel, 'Kezdés: 45p 0mp');

    expect(
      NextLessonStatus.formatRemainingLessonsLabel(1),
      'Már csak 1 órád van hátra',
    );
    expect(
      NextLessonStatus.formatRemainingLessonsLabel(5),
      'Még 5 órád van hátra',
    );

    // 3. Currently ongoing lesson (08:20 -> between 08:00 and 08:45)
    final ongoing = NextLessonStatus.evaluate(
      [lesson1, lesson2],
      DateTime(2026, 11, 10, 8, 20),
    );
    expect(ongoing.phase, NextLessonPhase.ongoing);
    expect(ongoing.headline, 'Folyamatban lévő óra: Matematika');
    expect(ongoing.countdownLabel, 'Még 25 perc');

    // 4. All scheduled lessons completed for today (10:30 -> after 09:45)
    final completed = NextLessonStatus.evaluate(
      [lesson1, lesson2],
      DateTime(2026, 11, 10, 10, 30),
    );
    expect(completed.phase, NextLessonPhase.completedForToday);
    expect(completed.headline, 'Mára vége az óráknak!');
  });

  test('SubjectGradeSummary supports sorting and Vocational Scholarship Tier calculation', () {
    final grades = [
      _makeGrade(uid: 'g1', subjectName: 'Matematika', value: 5, weight: 200),
      _makeGrade(uid: 'g2', subjectName: 'Biológia', value: 3, weight: 100),
      _makeGrade(uid: 'g3', subjectName: 'Angol nyelv', value: 4, weight: 100),
    ];

    final summariesAsc = SubjectGradeSummary.groupBySubject(
      grades,
      sortMode: SubjectSortMode.averageAsc,
    );
    expect(summariesAsc.first.subjectName, 'Biológia');
    expect(summariesAsc.last.subjectName, 'Matematika');

    final summariesAlpha = SubjectGradeSummary.groupBySubject(
      grades,
      sortMode: SubjectSortMode.alphabetical,
    );
    expect(summariesAlpha.first.subjectName, 'Angol nyelv');

    final counts = SubjectGradeSummary.computeGradeCounts(grades);
    expect(counts[5], 1);
    expect(counts[4], 1);
    expect(counts[3], 1);

    final tierIdx = ScholarshipTier.currentTierIndex(4.25);
    expect(tierIdx, 2);
    expect(ScholarshipTier.tiers[tierIdx!].estimatedMonthlyForint, 42000);
    expect(ScholarshipTier.tiers.map((t) => t.percent).toList(), [8, 25, 42, 59]);
    expect(ScholarshipTier.basicEducationMonthlyForint('technikum'), 8000);
    expect(ScholarshipTier.basicEducationMonthlyForint('szakkepzo'), 16000);
    expect(ScholarshipTier.tiers[tierIdx].rangeLabel, '4,00 – 4,49');

    final recs = SubjectGradeSummary.buildScholarshipRecommendations(
      allGrades: grades,
      subjects: summariesAsc,
      targetAverage: 4.50,
    );
    expect(recs, isNotEmpty);
  });

  test('UserProfilePrefs serializes and restores full configuration via JSON export/import', () {
    const prefs = UserProfilePrefs(
      nickname: 'Mili',
      uwuModeEnabled: true,
      tsundereModeEnabled: true,
      christmasModeEnabled: true,
      showCancelledLessons: true,
      appIconPreset: 'christmas',
      backgroundPreset: 'midnight_aurora',
      subjectRoundingOverrides: {
        'Matematika': GradeRoundingConfig(threshold5: 4.60),
      },
      subjectCustomColors: {'Matematika': 0xFFE91E63},
      subjectCustomNames: {'Matematika': 'Matek Pro'},
      teacherCustomNames: {'Teszt Tanár': 'Tanár Úr'},
    );

    final exportedJson = prefs.toExportJsonString();
    final restored = UserProfilePrefs.fromExportJsonString(exportedJson);

    expect(restored.nickname, 'Mili');
    expect(restored.uwuModeEnabled, isTrue);
    expect(restored.tsundereModeEnabled, isTrue);
    expect(restored.christmasModeEnabled, isTrue);
    expect(restored.showCancelledLessons, isTrue);
    expect(restored.appIconPreset, 'christmas');
    expect(restored.backgroundPreset, 'midnight_aurora');
    expect(restored.roundingForSubject('Matematika').threshold5, 4.60);
    expect(restored.resolveSubjectName('Matematika'), 'Matek Pro');
    expect(restored.resolveTeacherName('Teszt Tanár'), 'Tanár Úr');
    expect(restored.customColorForSubject('Matematika'), const Color(0xFFE91E63));
  });

  test('KretaMessage parses JSON payloads cleanly', () {
    final msg = KretaMessage.fromJson({
      'Uid': 'msg_42',
      'uzenet': {
        'targy': 'Osztálykirándulás',
        'szoveg': '<p>Holnap indulunk 8:00-kor!</p>',
        'feladoNev': 'Kovács Tanárnő',
        'feladoTitulus': 'Osztályfőnök',
        'kuldesDatum': '2026-11-10T08:00:00Z',
      },
      'IsElolvasva': false,
    });

    expect(msg.uid, 'msg_42');
    expect(msg.subject, 'Osztálykirándulás');
    expect(msg.sender, 'Kovács Tanárnő');
    expect(msg.cleanBody, 'Holnap indulunk 8:00-kor!');
    expect(msg.isRead, isFalse);
  });

  testWidgets('AnimatedNumberText rolls up to target value and TactileBounce handles taps', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TactileBounce(
            onTap: () => tapped = true,
            child: const AnimatedNumberText(
              value: 4.75,
              fractionDigits: 2,
              prefix: 'Átlag: ',
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Átlag: 4.75'), findsOneWidget);

    await tester.tap(find.byType(TactileBounce));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  test('AppIconPresetInfo resolves Christmas Mode and manual icon overrides accurately', () {
    const christmasOledPrefs = UserProfilePrefs(
      themeStyle: AppThemeStyle.oledPureBlack,
      christmasModeEnabled: true,
    );
    expect(AppIconPresetInfo.resolve(christmasOledPrefs).id, 'icon_christmas_oled');
    expect(
      AppIconPresetInfo.resolve(christmasOledPrefs).assetPath,
      'assets/icons/icon_christmas_oled.png',
    );

    const christmasNormalPrefs = UserProfilePrefs(
      themeStyle: AppThemeStyle.standardDark,
      christmasModeEnabled: true,
    );
    expect(AppIconPresetInfo.resolve(christmasNormalPrefs).id, 'icon_christmas');
    expect(
      AppIconPresetInfo.resolve(christmasNormalPrefs).assetPath,
      'assets/icons/icon_christmas.png',
    );

    const manualForcedPrefs = UserProfilePrefs(
      themeStyle: AppThemeStyle.oledPureBlack,
      christmasModeEnabled: true,
      appIconPreset: 'icon_oled',
    );
    expect(AppIconPresetInfo.resolve(manualForcedPrefs).id, 'icon_oled');
    expect(
      AppIconPresetInfo.resolve(manualForcedPrefs).assetPath,
      'assets/icons/icon_oled.png',
    );
  });

  testWidgets('AboutAppScreen dynamically displays the currently active icon variant', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AboutAppScreen(
          prefs: const UserProfilePrefs(
            themeStyle: AppThemeStyle.oledPureBlack,
            christmasModeEnabled: true,
            appIconPreset: 'icon_christmas_oled',
          ),
          onPrefsChanged: (_) {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/tinta_icon.png',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Karácsonyi OLED'), findsOneWidget);
    expect(find.text('v1.0.0'), findsOneWidget);
  });

  testWidgets(
    'EdgeFadeHorizontalScroll starts at offset 0 with inner padding, reverse=false, and dstIn ShaderMask',
    (tester) async {
      final controller = ScrollController(initialScrollOffset: 0.0);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                child: EdgeFadeHorizontalScroll(
                  controller: controller,
                  spacing: 8,
                  children: List.generate(
                    8,
                    (i) => SizedBox(
                      width: 80,
                      height: 36,
                      child: Center(child: Text('Chip $i')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollView = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(scrollView.scrollDirection, Axis.horizontal);
      expect(scrollView.reverse, isFalse);
      expect(scrollView.padding, const EdgeInsets.symmetric(horizontal: 16));
      expect(controller.offset, 0.0);
      expect(controller.position.maxScrollExtent, greaterThan(2.0));

      final maskStart = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(maskStart.blendMode, BlendMode.dstIn);

      controller.jumpTo(40.0);
      await tester.pumpAndSettle();
      expect(controller.offset, 40.0);

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(controller.offset, controller.position.maxScrollExtent);
    },
  );

  testWidgets(
    'EdgeFadeHorizontalScroll guards one-shot reset inside PageStorageKey and never fights manual scroll on rebuild',
    (tester) async {
      final bucket = PageStorageBucket();
      final controller = ScrollController(
        initialScrollOffset: 0.0,
        keepScrollOffset: false,
      );
      addTearDown(controller.dispose);
      int buildCount = 0;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) => MaterialApp(
            home: PageStorage(
              bucket: bucket,
              child: Scaffold(
                key: const PageStorageKey<String>('tab-home'),
                body: Column(
                  children: [
                    SizedBox(
                      width: 220,
                      child: EdgeFadeHorizontalScroll(
                        controller: controller,
                        spacing: 8,
                        children: List.generate(
                          6,
                          (i) => SizedBox(
                            width: 80,
                            height: 36,
                            child: Text('Item $i ($buildCount)'),
                          ),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => buildCount++),
                      child: const Text('Rebuild'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 0.0);

      controller.jumpTo(52.0);
      await tester.pumpAndSettle();
      expect(controller.offset, 52.0);

      await tester.tap(find.text('Rebuild'));
      await tester.pumpAndSettle();
      expect(controller.offset, 52.0);
    },
  );

  testWidgets(
    'LiquidSpringPillTrack animates with underdamped spring overshoot and velocity stretch',
    (tester) async {
      int selected = 0;
      late void Function(int) setSelected;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setSelected = (next) => setState(() => selected = next);
            return MaterialApp(
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: LiquidSpringPillTrack(
                      itemCount: 4,
                      selectedIndex: selected,
                      height: 62,
                      pillWidth: 56,
                      pillHeight: 42,
                      pillBuilder: (_, __) => Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      itemBuilder: (_, idx, progress) => Center(
                        child: Text('T$idx:${progress.toStringAsFixed(1)}'),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );

      await tester.pump();
      setSelected(3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final pillTransformFinder = find.descendant(
        of: find.byType(LiquidSpringPillTrack),
        matching: find.byType(Transform),
      );

      final stretchTransforms = tester
          .widgetList<Transform>(pillTransformFinder)
          .where((t) => t.transform.entry(0, 0) > 1.02)
          .toList();
      expect(stretchTransforms, isNotEmpty);

      await tester.pumpAndSettle();
      final settledTransform = tester.widget<Transform>(pillTransformFinder);
      expect(settledTransform.transform.entry(0, 0), closeTo(1.0, 0.001));
      expect(settledTransform.transform.entry(1, 1), closeTo(1.0, 0.001));
    },
  );

  testWidgets(
    'LiquidGlassSurface and showFrostedModal toggle BackdropFilter strictly with Soft Blur setting',
    (tester) async {
      addTearDown(
        () => UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs()),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassSurface(
              prefs: UserProfilePrefs(cardBlurEnabled: true, cardBlurSigma: 4.0),
              child: Text('Glass ON'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassSurface(
              prefs: UserProfilePrefs(cardBlurEnabled: false, cardBlurSigma: 4.0),
              child: Text('Glass OFF'),
            ),
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNothing);

      late BuildContext capturedCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedCtx = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      showFrostedModal(
        context: capturedCtx,
        categoryLabel: 'Teszt',
        categoryIcon: Icons.star_rounded,
        accentColor: Colors.blue,
        title: 'Frosted modal',
        rows: const [],
        prefs: const UserProfilePrefs(cardBlurEnabled: true, cardBlurSigma: 4.0),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsOneWidget);

      Navigator.of(capturedCtx).pop();
      await tester.pumpAndSettle();

      showFrostedModal(
        context: capturedCtx,
        categoryLabel: 'Teszt',
        categoryIcon: Icons.star_rounded,
        accentColor: Colors.blue,
        title: 'Solid modal',
        rows: const [],
        prefs: const UserProfilePrefs(cardBlurEnabled: false, cardBlurSigma: 4.0),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  test(
    'groupHomeActivityItemsByDay sorts and groups Homeworks strictly by dueDate above Ma',
    () {
      final today = DateTime(2026, 11, 12);
      final hwFarFuture = Homework.fromJson({
        'Uid': 'hw-far',
        'RogzitesIdopontja': '2026-11-11T10:00:00',
        'FeladasDatuma': '2026-11-11T10:00:00',
        'HataridoDatuma': '2026-11-16T08:00:00',
        'Szoveg': 'Sokadik határidő',
        'RogzitoTanarNeve': 'Teszt Tanár',
        'Tantargy': {'Uid': 's1', 'Nev': 'Történelem', 'Kategoria': {'Uid': 's1', 'Nev': 't', 'Leiras': 't'}},
      });
      final hwTomorrow = Homework.fromJson({
        'Uid': 'hw-tmrw',
        'RogzitesIdopontja': '2026-11-10T09:00:00',
        'FeladasDatuma': '2026-11-10T09:00:00',
        'HataridoDatuma': '2026-11-13T08:00:00',
        'Szoveg': 'Holnapi házi',
        'RogzitoTanarNeve': 'Teszt Tanár',
        'Tantargy': {'Uid': 's2', 'Nev': 'Matematika', 'Kategoria': {'Uid': 's2', 'Nev': 'm', 'Leiras': 'm'}},
      });
      final hwPastDue = Homework.fromJson({
        'Uid': 'hw-past',
        'RogzitesIdopontja': '2026-11-09T09:00:00',
        'FeladasDatuma': '2026-11-09T09:00:00',
        'HataridoDatuma': '2026-11-10T08:00:00',
        'Szoveg': 'Múltbeli házi',
        'RogzitoTanarNeve': 'Teszt Tanár',
        'Tantargy': {'Uid': 's3', 'Nev': 'Fizika', 'Kategoria': {'Uid': 's3', 'Nev': 'f', 'Leiras': 'f'}},
      });
      final gradeToday = Grade.fromJson({
        'Uid': 'g-today',
        'KeszitesDatuma': '2026-11-12T11:30:00',
        'RogzitesDatuma': '2026-11-12T11:30:00',
        'Tantargy': {'Uid': 's2', 'Nev': 'Matematika', 'Kategoria': {'Uid': 's2', 'Nev': 'm', 'Leiras': 'm'}},
        'Tipus': {'Uid': '1', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
        'ErtekFajta': {'Uid': '1', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
        'ErtekeloTanarNeve': 'Teszt Tanár',
        'SzamErtek': 5,
        'SzovegesErtek': 'Jeles(5)',
      });

      final groups = groupHomeActivityItemsByDay(
        [
          HomeActivityItem.homework(hwFarFuture),
          HomeActivityItem.homework(hwPastDue),
          HomeActivityItem.grade(gradeToday),
          HomeActivityItem.homework(hwTomorrow),
        ],
        today,
      );

      expect(
        groups.map((g) => g.day).toList(),
        [
          DateTime(2026, 11, 13),
          DateTime(2026, 11, 16),
          DateTime(2026, 11, 12),
          DateTime(2026, 11, 10),
        ],
      );
      expect(groups[0].items.single.homework?.uid, 'hw-tmrw');
      expect(groups[1].items.single.homework?.uid, 'hw-far');
      expect(groups[2].items.single.grade?.uid, 'g-today');
      expect(groups[3].items.single.homework?.uid, 'hw-past');
    },
  );

  testWidgets(
    'TintaSplashOverlay renders OLED black + breathing icon + 2px progress bar and crossfades out 450ms easeOutCubic',
    (tester) async {
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: TintaSplashOverlay(
            isLoading: true,
            accentColor: const Color(0xFF42A5F5),
            onDismissed: () => dismissed = true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      final bg = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(TintaSplashOverlay),
          matching: find.byType(ColoredBox),
        ).first,
      );
      expect(bg.color, const Color(0xFF000000));
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName == 'assets/images/tinta_icon.png',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is SizedBox && w.width == 112.0 && w.height == 2.0,
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TintaSplashOverlay(
            isLoading: false,
            accentColor: const Color(0xFF42A5F5),
            onDismissed: () => dismissed = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(dismissed, isFalse);
      final midFade = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byType(TintaSplashOverlay),
          matching: find.byType(FadeTransition),
        ).first,
      );
      final midScale = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(TintaSplashOverlay),
          matching: find.byType(ScaleTransition),
        ).first,
      );
      expect(midFade.opacity.value, inInclusiveRange(0.05, 0.95));
      expect(midScale.scale.value, greaterThan(1.0));
      expect(midScale.scale.value, lessThanOrEqualTo(1.04));

      await tester.pump(const Duration(milliseconds: 300));
      expect(dismissed, isTrue);
    },
  );

  testWidgets(
    'HomeSkeletonFeed renders Főoldal geometry placeholders without CircularProgressIndicator',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
          ),
          home: const Scaffold(
            body: HomeSkeletonFeed(
              prefs: UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SoftGlassCard), findsNWidgets(5));
    },
  );

  testWidgets(
    'ReKretaApp startup uses TintaSplashOverlay with zero CircularProgressIndicator and dissolves cleanly',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      await tester.pumpWidget(
        const ReKretaApp(tokenStorage: TokenStorageService()),
      );
      // Frame 1: splash active on top, no blocking CircularProgressIndicator anywhere
      expect(find.byType(TintaSplashOverlay), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.byType(TintaSplashOverlay), findsNothing);
      expect(find.text('Tinta Napló'), findsWidgets);
    },
  );

  test('DashboardData roundtrips via JSON and preserves same-day lessons only', () {
    final session = StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final now = DateTime.now();
    final lessonStart = DateTime(now.year, now.month, now.day, 9, 0);
    final lessonEnd = DateTime(now.year, now.month, now.day, 9, 45);
    final original = DashboardData(
      student: Student.fromJson({
        'Uid': 'stu-1',
        'Nev': 'Teszt Diák',
        'Cimek': ['Budapest'],
        'Bankszamla': {
          'BankszamlaSzam': null,
          'IsReadOnly': false,
          'BankszamlaTulajdonosNeve': null,
          'BankszamlaTulajdonosTipusId': null,
        },
        'SzuletesiEv': 2008,
        'SzuletesiHonap': 5,
        'SzuletesiNap': 12,
        'EmailCim': 'diak@example.com',
        'Telefonszam': '+36301234567',
        'TanevUid': 'tanev-1',
        'Gondviselok': [],
        'IntezmenyAzonosito': 'klik001',
        'IntezmenyNev': 'Teszt Gimnázium',
        'Intezmeny': {
          'Uid': 'inst-1',
          'RovidNev': 'TG',
          'TestreszabasBeallitasok': {
            'ErtekelesekMegjelenitesenekKesleltetesenekMerteke': 0,
            'IsOsztalyAtlagMegjeleniteseEllenorzoben': true,
            'IsTanorakTemajaMegtekinthetoEllenorzoben': true,
            'KovetkezoTelepitesDatuma': '2026-12-01',
          },
          'Rendszermodulok': [],
        },
      }),
      todaysLessons: [
        _makeLesson(
          uid: 'l1',
          subjectName: 'Matematika',
          start: lessonStart,
          end: lessonEnd,
        ),
      ],
      allGrades: [
        Grade.fromJson({
          'Uid': 'g1',
          'KeszitesDatuma': '2026-11-12T10:15:00',
          'RogzitesDatuma': '2026-11-12T00:00:00',
          'Tantargy': {
            'Uid': 'sub-m',
            'Nev': 'Matematika',
            'Kategoria': {'Uid': 'm', 'Nev': 'm', 'Leiras': 'm'},
          },
          'Tipus': {'Uid': '1', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
          'ErtekFajta': {'Uid': '1', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
          'ErtekeloTanarNeve': 'Tanár',
          'SzamErtek': 5,
          'SzovegesErtek': 'Jeles(5)',
        }),
      ],
      latestGrades: const [],
      homeworks: [
        Homework.fromJson({
          'Uid': 'hw1',
          'RogzitesIdopontja': '2026-11-12T09:00:00',
          'FeladasDatuma': '2026-11-12T09:00:00',
          'HataridoDatuma': '2026-11-15T08:00:00',
          'Szoveg': 'Feladatok 1-3.',
          'RogzitoTanarNeve': 'Tanár',
          'Tantargy': {
            'Uid': 'sub-m',
            'Nev': 'Matematika',
            'Kategoria': {'Uid': 'm', 'Nev': 'm', 'Leiras': 'm'},
          },
        }),
      ],
      tests: const [],
      omissions: const [],
      messages: [
        KretaMessage(
          uid: 'msg-1',
          sender: 'Rendszer',
          subject: 'Értesítés',
          body: 'Tartalom',
          sentAt: DateTime(2026, 11, 12, 8, 30),
          isSystemMessage: true,
        ),
      ],
      activeSession: session,
    );

    final encoded = original.toJson();
    final sameDay = DashboardData.fromJson(
      encoded,
      session,
      readMessageIds: {'msg-1'},
    );
    expect(sameDay.student?.name, 'Teszt Diák');
    expect(sameDay.todaysLessons.length, 1);
    expect(sameDay.allGrades.single.recordedAt.hour, 10);
    expect(sameDay.homeworks.single.description, 'Feladatok 1-3.');
    expect(sameDay.messages.single.isSystemMessage, isTrue);
    expect(sameDay.messages.single.isRead, isTrue);

    final staleJson = Map<String, dynamic>.from(encoded)
      ..['cacheDate'] = DateTime(2020, 1, 1).toIso8601String();
    final staleDay = DashboardData.fromJson(staleJson, session);
    expect(staleDay.todaysLessons, isEmpty);
    expect(staleDay.allGrades.length, 1);
  });

  testWidgets(
    'HomeScreen shows HomeSkeletonFeed during sync with zero CircularProgressIndicator and crossfades to live cards',
    (tester) async {
      final session = StoredSession(
        accessToken: 'acc',
        refreshToken: 'ref',
        idToken: 'id',
        instituteCode: 'klik001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final completer = Completer<DashboardData>();
      final client = _StubHomeKretaClient(fetchCompleter: completer);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
          ),
          home: HomeScreen(
            initialSession: session,
            kretaClient: client,
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
            onPrefsChanged: (_) {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(HomeSkeletonFeed), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      completer.complete(
        DashboardData(
          student: null,
          todaysLessons: const [],
          allGrades: [
            Grade.fromJson({
              'Uid': 'g-live',
              'KeszitesDatuma': '2026-11-12T10:15:00',
              'RogzitesDatuma': '2026-11-12T00:00:00',
              'Tantargy': {
                'Uid': 'sub-m',
                'Nev': 'Fizika',
                'Kategoria': {'Uid': 'm', 'Nev': 'm', 'Leiras': 'm'},
              },
              'Tipus': {'Uid': '1', 'Nev': 'Evkozi', 'Leiras': 'Évközi'},
              'ErtekFajta': {'Uid': '1', 'Nev': 'Jegy', 'Leiras': 'Jegy'},
              'ErtekeloTanarNeve': 'Tanár',
              'SzamErtek': 5,
              'SzovegesErtek': 'Jeles(5)',
            }),
          ],
          latestGrades: const [],
          homeworks: const [],
          tests: const [],
          omissions: const [],
          messages: const [],
          activeSession: session,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(HomeSkeletonFeed), findsNothing);
      expect(find.text('Fizika'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'AppSettingsScreen & AboutAppScreen hide removed options and render adaptive transparent AppBar',
    (tester) async {
      final session = StoredSession(
        accessToken: 'acc',
        refreshToken: 'ref',
        idToken: 'id',
        instituteCode: 'klik001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final client = _StubHomeKretaClient(
        fetchCompleter: Completer<DashboardData>(),
      );
      const ambientPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.oledPureBlack,
        cardBlurEnabled: true,
        backgroundPreset: 'aurora',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: ambientPrefs),
          home: AppSettingsScreen(
            session: session,
            student: null,
            kretaClient: client,
            prefs: ambientPrefs,
            onPrefsChanged: (_) {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Ösztöndíj kalkulátor'), findsNothing);
      expect(find.text('Megjelenés és témák'), findsOneWidget);

      final settingsScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(settingsScaffold.extendBodyBehindAppBar, isTrue);
      expect(settingsScaffold.backgroundColor, Colors.transparent);

      final settingsAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(settingsAppBar.backgroundColor, Colors.transparent);
      expect(settingsAppBar.surfaceTintColor, Colors.transparent);
      expect(settingsAppBar.scrolledUnderElevation, 0);

      // Push Appearance & Themes sub-screen and verify removed entries & AppBar
      await tester.tap(find.text('Megjelenés és témák'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Karácsonyi mód'), findsNothing);
      expect(find.textContaining('Alkalmazás ikon választó'), findsNothing);
      expect(find.textContaining('Kártyák soft blur'), findsOneWidget);

      final detailScaffold = tester.widget<Scaffold>(find.byType(Scaffold).last);
      expect(detailScaffold.extendBodyBehindAppBar, isTrue);
      expect(detailScaffold.backgroundColor, Colors.transparent);

      final detailAppBar = tester.widget<AppBar>(find.byType(AppBar).last);
      expect(detailAppBar.backgroundColor, Colors.transparent);
      expect(detailAppBar.surfaceTintColor, Colors.transparent);
      expect(detailAppBar.scrolledUnderElevation, 0);

      // Light mode without ambient backdrop preserves Scaffold theme background
      const lightSolidPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.light,
        cardBlurEnabled: false,
      );
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('about-light-solid'),
          theme: OledTheme.buildTheme(prefs: lightSolidPrefs),
          home: AboutAppScreen(
            prefs: lightSolidPrefs,
            onPrefsChanged: (_) {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      final aboutScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(aboutScaffold.extendBodyBehindAppBar, isTrue);
      expect(aboutScaffold.backgroundColor, isNull);
      final aboutAppBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(aboutAppBar.backgroundColor, Colors.transparent);
      expect(aboutAppBar.scrolledUnderElevation, 0);
      expect(
        aboutAppBar.foregroundColor,
        OledTheme.buildTheme(prefs: lightSolidPrefs).colorScheme.onSurface,
      );
    },
  );

  testWidgets(
    'LiquidGlassSurface uses GPU-efficient sigma 16 crystal-clear blur when Soft Blur is ON and clean solid surface when OFF',
    (tester) async {
      const blurOnPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.oledPureBlack,
        cardBlurEnabled: true,
        cardBlurSigma: 2.0,
      );
      const blurOffPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.oledPureBlack,
        cardBlurEnabled: false,
      );

      expect(resolveSoftBlurBackdropSigma(blurOnPrefs), closeTo(16.0, 0.01));

      late Color barrierBlurOn;
      late Color barrierBlurOff;

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: blurOnPrefs),
          home: Builder(
            builder: (context) {
              barrierBlurOn = resolveSoftBlurBarrierColor(
                context,
                prefs: blurOnPrefs,
                solidDarkAlpha: 0.65,
              );
              barrierBlurOff = resolveSoftBlurBarrierColor(
                context,
                prefs: blurOffPrefs,
                solidDarkAlpha: 0.65,
              );
              return const Scaffold(
                body: Center(
                  child: LiquidGlassSurface(
                    prefs: blurOnPrefs,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 20,
                      ),
                    ],
                    child: Text('Frosted'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(barrierBlurOn.a, lessThan(0.35));
      expect(barrierBlurOff.a, closeTo(0.65, 0.01));

      final backdrop = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(
        backdrop.filter,
        ImageFilter.blur(
          sigmaX: resolveSoftBlurBackdropSigma(blurOnPrefs),
          sigmaY: resolveSoftBlurBackdropSigma(blurOnPrefs),
        ),
      );

      final glassContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(Container),
        ),
      );
      final glassDeco = glassContainer.decoration! as BoxDecoration;
      expect(glassDeco.gradient, isA<LinearGradient>());
      final grad = glassDeco.gradient! as LinearGradient;
      expect(grad.colors.first.a, lessThanOrEqualTo(0.08));
      expect(grad.colors.last.a, closeTo(0.0, 0.001));
      expect(
        (glassDeco.border! as Border).top.color.a,
        closeTo(0.14, 0.01),
      );

      // Switch to Soft Blur OFF: clean solid surface without BackdropFilter
      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: blurOffPrefs),
          home: const Scaffold(
            body: Center(
              child: LiquidGlassSurface(
                prefs: blurOffPrefs,
                solidColor: Color(0xFF161922),
                child: Text('Solid'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
      final solidContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(LiquidGlassSurface),
          matching: find.byType(Container),
        ),
      );
      final solidDeco = solidContainer.decoration! as BoxDecoration;
      expect(solidDeco.color, const Color(0xFF161922));
    },
  );

  test(
    'groupOmissionsByDay groups absences by local day (newest first) and sorts periods ascending',
    () {
      final nov12Fifth = _makeOmission(
        uid: 'o-12-5',
        subjectName: 'Fizika',
        date: DateTime(2026, 11, 12),
        classNo: 5,
        state: OmissionState.unexcused,
      );
      final nov12First = _makeOmission(
        uid: 'o-12-1',
        subjectName: 'Matematika',
        date: DateTime(2026, 11, 12),
        classNo: 1,
        state: OmissionState.excused,
      );
      final nov12SecondLate = _makeOmission(
        uid: 'o-12-2',
        subjectName: 'Irodalom',
        date: DateTime(2026, 11, 12),
        classNo: 2,
        state: OmissionState.excused,
        lateMinutes: 12,
      );
      final nov10Third = _makeOmission(
        uid: 'o-10-3',
        subjectName: 'Történelem',
        date: DateTime(2026, 11, 10),
        classNo: 3,
        state: OmissionState.excused,
      );

      final groups = groupOmissionsByDay([
        nov10Third,
        nov12Fifth,
        nov12SecondLate,
        nov12First,
      ]);

      expect(groups.length, 2);
      expect(groups[0].day, DateTime(2026, 11, 12));
      expect(groups[1].day, DateTime(2026, 11, 10));
      expect(
        groups[0].entries.map((e) => e.uid).toList(),
        ['o-12-1', 'o-12-2', 'o-12-5'],
      );
      expect(groups[0].summaryLabel, '2 óra • 1 késés');
      expect(groups[1].summaryLabel, '1 óra');
      expect(
        formatHungarianOmissionDay(groups[0].day, referenceYear: 2026),
        'Nov. 12. • Csütörtök',
      );
      expect(
        formatHungarianOmissionDay(groups[1].day, referenceYear: 2026),
        'Nov. 10. • Kedd',
      );
    },
  );

  testWidgets(
    'Hiányzások tab renders daily cards below summary ordered newest-first with period ascending, filtering, and detail modal',
    (tester) async {
      final session = StoredSession(
        accessToken: 'acc',
        refreshToken: 'ref',
        idToken: 'id',
        instituteCode: 'klik001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final client = _StubHomeKretaClient(
        fetchCompleter: Completer<DashboardData>(),
      );
      final currentYear = DateTime.now().year;
      final nov12 = DateTime(currentYear, 11, 12);
      final nov10 = DateTime(currentYear, 11, 10);
      final omissions = [
        _makeOmission(
          uid: 'o-10-3',
          subjectName: 'Történelem',
          date: nov10,
          classNo: 3,
          state: OmissionState.excused,
        ),
        _makeOmission(
          uid: 'o-12-5',
          subjectName: 'Fizika',
          date: nov12,
          classNo: 5,
          state: OmissionState.unexcused,
        ),
        _makeOmission(
          uid: 'o-12-1',
          subjectName: 'Matematika',
          date: nov12,
          classNo: 1,
          state: OmissionState.excused,
        ),
        _makeOmission(
          uid: 'o-12-2',
          subjectName: 'Irodalom',
          date: nov12,
          classNo: 2,
          state: OmissionState.excused,
          lateMinutes: 12,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(prefs: const UserProfilePrefs()),
          home: Scaffold(
            body: MoreScreen(
              session: session,
              student: null,
              kretaClient: client,
              initialOmissions: omissions,
              prefs: const UserProfilePrefs(),
              onPrefsChanged: (_) {},
              onLogout: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      final nov12Label = formatHungarianOmissionDay(nov12);
      final nov10Label = formatHungarianOmissionDay(nov10);

      expect(find.text('Hiányzások és Késések'), findsOneWidget);
      expect(find.text(nov12Label), findsOneWidget);
      expect(find.text(nov10Label), findsOneWidget);
      expect(find.text('2 óra • 1 késés'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SoftGlassCard).last,
          matching: find.text('1 óra'),
        ),
        findsOneWidget,
      );

      // Newest day card appears above older day card
      expect(
        tester.getTopLeft(find.text(nov12Label)).dy,
        lessThan(tester.getTopLeft(find.text(nov10Label)).dy),
      );

      // Periods inside Nov. 12 daily card are ordered ascending (1., 12 p, 5.)
      final y1 = tester.getTopLeft(find.text('1. óra')).dy;
      final y2 = tester.getTopLeft(find.text('12 p')).dy;
      final y5 = tester.getTopLeft(find.text('5. óra')).dy;
      expect(y1, lessThan(y2));
      expect(y2, lessThan(y5));

      // Filter by 'Igazolatlan' leaves only Fizika on Nov 12
      await tester.tap(find.widgetWithText(ChoiceChip, 'Igazolatlan'));
      await tester.pumpAndSettle();
      expect(find.text(nov10Label), findsNothing);
      expect(find.text(nov12Label), findsOneWidget);
      expect(find.text('Fizika'), findsOneWidget);
      expect(find.text('Matematika'), findsNothing);

      // Tapping an entry inside the daily card opens its detail modal
      await tester.tap(find.text('Fizika'));
      await tester.pumpAndSettle();
      expect(find.text('Rögzítő tanár'), findsOneWidget);
      expect(find.text('Mulasztás / Hiányzás'), findsOneWidget);
    },
  );

  testWidgets(
    'GradesScreen persists selected sort mode in SharedPreferences and restores it after restart',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final grades = [
        _makeGrade(uid: 'g-bio', subjectName: 'Biológia', value: 2),
        _makeGrade(uid: 'g-zene', subjectName: 'Zene', value: 5),
      ];

      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('grades-session-1'),
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
      await tester.pump(const Duration(milliseconds: 500));

      // Default sort is A–Z (Biológia above Zene)
      expect(
        tester.getTopLeft(find.text('Biológia')).dy,
        lessThan(tester.getTopLeft(find.text('Zene')).dy),
      );

      // Select 'Átlag ↓ (Legjobb)' and verify immediate sort + SharedPreferences save
      await tester.tap(find.text('Átlag ↓ (Legjobb)'));
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('Zene')).dy,
        lessThan(tester.getTopLeft(find.text('Biológia')).dy),
      );
      final sp = await SharedPreferences.getInstance();
      expect(
        sp.getString(kGradesSelectedSortModeKey),
        SubjectSortMode.averageDesc.name,
      );

      // Simulate cold restart with fresh UserProfilePrefs() reading persisted SharedPreferences
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('grades-session-2'),
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
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        tester.getTopLeft(find.text('Zene')).dy,
        lessThan(tester.getTopLeft(find.text('Biológia')).dy),
      );
    },
  );

  testWidgets(
    'NextLesson hero card displays real subject headline, unclipped 5/5 pill, and full teacher name',
    (tester) async {
      final session = StoredSession(
        accessToken: 'acc',
        refreshToken: 'ref',
        idToken: 'id',
        instituteCode: 'klik001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final now = DateTime.now();
      final firstStart = now.hour < 20
          ? now.add(const Duration(hours: 3))
          : DateTime(now.year, now.month, now.day, 23, 55);
      final lessons = List<Lesson>.generate(
        5,
        (i) => _makeLesson(
          uid: 'hero-l-$i',
          subjectName: i == 0 ? 'Matematika' : 'Tantárgy $i',
          start: firstStart.add(Duration(minutes: i)),
          end: firstStart.add(Duration(minutes: i + 1)),
          teacherName: 'Dr. Ujvári Sándor',
          count: i + 1,
        ),
      );
      final cached = DashboardData(
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
      final completer = Completer<DashboardData>()..complete(cached);
      final client = _StubHomeKretaClient(fetchCompleter: completer);

      await tester.binding.setSurfaceSize(const Size(360, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
          ),
          home: HomeScreen(
            initialSession: session,
            initialCachedData: cached,
            kretaClient: client,
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
            onPrefsChanged: (_) {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Matematika'), findsOneWidget);
      expect(find.text('Még 5 órád van hátra'), findsOneWidget);
      expect(find.text('Dr. Ujvári Sándor'), findsOneWidget);
      expect(find.textContaining('Kezdés:'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Kezdés:'), findsOneWidget);
      expect(find.text('Dr. Ujvári Sándor'), findsOneWidget);
    },
  );

  testWidgets(
    'showFrostedModal and showSoftBlurDialog render BackdropFilter from frame 0 through smooth reverse fade-out without Opacity or FadeTransition ancestors',
    (tester) async {
      late BuildContext capturedCtx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedCtx = ctx;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      // Soft Blur ON: showFrostedModal blurs immediately mid-open and fades blur smoothly on close.
      showFrostedModal(
        context: capturedCtx,
        categoryLabel: 'TESZT',
        categoryIcon: Icons.info_outline_rounded,
        accentColor: Colors.teal,
        title: 'Azonnali elmosódás',
        rows: const [
          FrostedDetailRow(
            icon: Icons.schedule_rounded,
            label: 'Idő',
            value: '08:00',
          ),
        ],
        prefs: const UserProfilePrefs(cardBlurEnabled: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      final modalSettledFilter =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;

      Navigator.of(capturedCtx).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 115));
      expect(find.byType(BackdropFilter), findsOneWidget);
      final modalMidCloseFilter =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
      expect(modalMidCloseFilter, isNot(equals(modalSettledFilter)));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);

      // Soft Blur ON: showSoftBlurDialog blurs immediately mid-open and fades blur smoothly on close.
      showSoftBlurDialog<void>(
        context: capturedCtx,
        prefs: const UserProfilePrefs(cardBlurEnabled: true),
        builder: (_) => const Text('Dialog tartalom'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byType(BackdropFilter),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      await tester.pumpAndSettle();
      final dialogSettledFilter =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;

      Navigator.of(capturedCtx).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 115));
      expect(find.byType(BackdropFilter), findsOneWidget);
      final dialogMidCloseFilter =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).filter;
      expect(dialogMidCloseFilter, isNot(equals(dialogSettledFilter)));
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);

      // Soft Blur OFF: zero BackdropFilter even on frame 0 and settled.
      showFrostedModal(
        context: capturedCtx,
        categoryLabel: 'TESZT',
        categoryIcon: Icons.info_outline_rounded,
        accentColor: Colors.teal,
        title: 'Nincs elmosódás',
        rows: const [],
        prefs: const UserProfilePrefs(cardBlurEnabled: false),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
      Navigator.of(capturedCtx).pop();
      await tester.pumpAndSettle();

      showSoftBlurDialog<void>(
        context: capturedCtx,
        prefs: const UserProfilePrefs(cardBlurEnabled: false),
        builder: (_) => const Text('Solid dialog'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));
      expect(find.byType(BackdropFilter), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byType(BackdropFilter), findsNothing);
    },
  );

  testWidgets(
    'ChristmasAndBackgroundOverlay pauses its ambient ticker when TickerMode is disabled',
    (tester) async {
      const snowPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.oledPureBlack,
        christmasModeEnabled: true,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: true,
              child: ChristmasAndBackgroundOverlay(
                prefs: snowPrefs,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: ChristmasAndBackgroundOverlay(
                prefs: snowPrefs,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: true,
              child: ChristmasAndBackgroundOverlay(
                prefs: snowPrefs,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    },
  );

  testWidgets(
    'Főoldal filter chips crossfade feed content smoothly with AnimatedSwitcher without duplicate Hero conflicts',
    (tester) async {
      final session = StoredSession(
        accessToken: 'acc',
        refreshToken: 'ref',
        idToken: 'id',
        instituteCode: 'klik001',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
      final grade = _makeGrade(uid: 'g-flt-1', subjectName: 'Biológia', value: 5);
      final hw = Homework.fromJson({
        'Uid': 'hw-flt-1',
        'RogzitesIdopontja': '2026-11-12T09:00:00',
        'FeladasDatuma': '2026-11-12T09:00:00',
        'HataridoDatuma': '2026-11-15T08:00:00',
        'Szoveg': 'Növénytan feladatlap',
        'RogzitoTanarNeve': 'Tanár',
        'Tantargy': {
          'Uid': 'sub-bio',
          'Nev': 'Kémia',
          'Kategoria': {'Uid': 'k', 'Nev': 'k', 'Leiras': 'k'},
        },
      });
      final cached = DashboardData(
        student: null,
        todaysLessons: const [],
        allGrades: [grade],
        latestGrades: [grade],
        homeworks: [hw],
        tests: const [],
        omissions: const [],
        messages: const [],
        activeSession: session,
      );
      final completer = Completer<DashboardData>()..complete(cached);
      final client = _StubHomeKretaClient(fetchCompleter: completer);

      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
          ),
          home: HomeScreen(
            initialSession: session,
            initialCachedData: cached,
            kretaClient: client,
            prefs: const UserProfilePrefs(themeStyle: AppThemeStyle.oledPureBlack),
            onPrefsChanged: (_) {},
            onLogout: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey<ActivityFeedFilter>(ActivityFeedFilter.all)), findsOneWidget);
      expect(find.text('Biológia'), findsOneWidget);
      expect(find.textContaining('Növénytan feladatlap'), findsOneWidget);

      await tester.tap(find.text('Jegyek'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      // Mid-transition both outgoing & incoming subtrees exist safely inside AnimatedSwitcher.
      expect(find.byKey(const ValueKey<ActivityFeedFilter>(ActivityFeedFilter.grades)), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();
      expect(find.text('Biológia'), findsOneWidget);
      expect(find.textContaining('Növénytan feladatlap'), findsNothing);

      await tester.tap(find.text('Házik'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<ActivityFeedFilter>(ActivityFeedFilter.homeworks)), findsOneWidget);
      expect(find.textContaining('Növénytan feladatlap'), findsOneWidget);
      expect(find.text('Biológia'), findsNothing);
    },
  );
}

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

class _StubHomeKretaClient extends KretaClient {
  final Completer<DashboardData> fetchCompleter;

  _StubHomeKretaClient({required this.fetchCompleter});

  @override
  Future<DashboardData?> loadCachedDashboard(StoredSession session) async => null;

  @override
  Future<DashboardData> fetchDashboardData(
    StoredSession initialSession, {
    DateTime? date,
  }) =>
      fetchCompleter.future;
}
