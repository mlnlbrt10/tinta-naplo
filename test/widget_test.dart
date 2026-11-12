import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/screens/about_app_screen.dart';
import 'package:rekreta_app/screens/grades_screen.dart';
import 'package:rekreta_app/screens/home_screen.dart';
import 'package:rekreta_app/services/kreta_client.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/animation_helpers.dart';
import 'package:rekreta_app/widgets/christmas_snowfall_overlay.dart';

Lesson _makeLesson({
  required String uid,
  required String subjectName,
  required DateTime start,
  required DateTime end,
  String stateName = 'Megtartott',
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
    'TanarNeve': 'Teszt Tanár',
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
    expect(farBefore.countdownLabel, 'Még messze van az első órád');

    // 2. Within 2 hours before first lesson (07:15 -> 45 mins before 08:00)
    final nearBefore = NextLessonStatus.evaluate(
      [lesson1, lesson2],
      DateTime(2026, 11, 10, 7, 15),
    );
    expect(nearBefore.phase, NextLessonPhase.beforeFirstWithinTwoHours);
    expect(nearBefore.countdownLabel, contains('Első óráig:'));

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

    expect(find.textContaining('Karácsonyi OLED'), findsOneWidget);
    expect(find.text('v1.2.5'), findsOneWidget);
  });
}
