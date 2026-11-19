import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:rekreta_app/providers/app_providers.dart';
import 'package:rekreta_app/screens/grades_screen.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Grade _sampleGrade({
  required String uid,
  required String subjectName,
  required int value,
  int weightPercentage = 100,
  String teacher = 'Kiss Anna',
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
    'ErtekeloTanarNeve': teacher,
    'Jelleg': 'Ertekeles',
    'SzamErtek': value,
    'SzovegesErtek': '$value',
    'SulySzazalekErteke': weightPercentage,
    'SzovegesErtekelesRovidNev': '$value',
    'OsztalyCsoport': {'Uid': 'g1'},
    'SortIndex': 1,
  });
}

void main() {
  testWidgets(
    'SubjectGradesDetailScreen customization modal saves edits, custom color & closes cleanly without _dependents.isEmpty crash',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const storage = TokenStorageService();
      final settingsProvider = SettingsProvider(
        initialPrefs: const UserProfilePrefs(cardBlurEnabled: true),
        storage: storage,
      );
      final themeProvider = ThemeProvider(settingsProvider);
      final commuteProvider = CommuteProvider(settingsProvider);
      addTearDown(() {
        commuteProvider.dispose();
        themeProvider.dispose();
        settingsProvider.dispose();
      });

      final g1 = _sampleGrade(uid: 'g1', subjectName: 'Matematika', value: 5);
      final g2 = _sampleGrade(uid: 'g2', subjectName: 'Matematika', value: 4);
      final allGrades = [g1, g2];
      final subjects = SubjectGradeSummary.groupBySubject(
        allGrades,
        prefs: settingsProvider.prefs,
      );

      await tester.pumpWidget(
        AppProvidersScope(
          settings: settingsProvider,
          theme: themeProvider,
          commute: commuteProvider,
          child: ListenableBuilder(
            listenable: Listenable.merge([settingsProvider, themeProvider]),
            builder: (context, _) {
              final prefs = settingsProvider.prefs;
              return MaterialApp(
                theme: OledTheme.buildTheme(prefs: prefs),
                home: SubjectGradesDetailScreen(
                  summary: subjects.first,
                  allSubjects: subjects,
                  prefs: prefs,
                  onPrefsChanged: (next) => settingsProvider.updatePrefs(next),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Open "Tantárgy testreszabása" sheet from top-right AppBar button.
      await tester.tap(find.byTooltip('Tantárgy testreszabása'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Tantárgy testreszabása'), findsOneWidget);

      // Focus & edit both TextFields, plus select a custom color circle.
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await tester.tap(textFields.first);
      await tester.pump();
      await tester.enterText(textFields.first, 'Matek emelt');
      await tester.pump();

      await tester.tap(textFields.at(1));
      await tester.pump();
      await tester.enterText(textFields.at(1), 'Tanár Úr');
      await tester.pump();

      // Tap a custom palette color dot (InkWell next to Automatikus ChoiceChip).
      final customColorDot = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle &&
              (w.decoration as BoxDecoration).color ==
                  OledTheme.gradeColorPalette.first,
        ),
      );
      await tester.ensureVisible(customColorDot);
      await tester.tap(customColorDot);
      await tester.pump();

      final saveBtn = find.widgetWithText(FilledButton, 'Mentés');
      await tester.ensureVisible(saveBtn);
      await tester.pump();

      // Tap "Mentés" while TextField was focused & verify clean pop without assertions.
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Tantárgy testreszabása'), findsNothing);
      expect(find.text('Matek emelt'), findsNWidgets(2));
      expect(find.textContaining('Tanár Úr'), findsNWidgets(2));
      expect(
        settingsProvider.prefs.subjectCustomNames['Matematika'],
        'Matek emelt',
      );
      expect(
        settingsProvider.prefs.teacherCustomNames['Kiss Anna'],
        'Tanár Úr',
      );
      expect(
        settingsProvider.prefs.subjectCustomColors[subjects.first.heroId],
        OledTheme.gradeColorPalette.first.toARGB32(),
      );
    },
  );

  testWidgets(
    'Dismissing Tantárgy testreszabása sheet via scrim tap after editing TextField cleans up cleanly with zero assertions',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const storage = TokenStorageService();
      final settingsProvider = SettingsProvider(storage: storage);
      final themeProvider = ThemeProvider(settingsProvider);
      final commuteProvider = CommuteProvider(settingsProvider);
      addTearDown(() {
        commuteProvider.dispose();
        themeProvider.dispose();
        settingsProvider.dispose();
      });

      final allGrades = [
        _sampleGrade(uid: 'g1', subjectName: 'Fizika', value: 5),
      ];

      await tester.pumpWidget(
        AppProvidersScope(
          settings: settingsProvider,
          theme: themeProvider,
          commute: commuteProvider,
          child: ListenableBuilder(
            listenable: Listenable.merge([settingsProvider, themeProvider]),
            builder: (context, _) {
              final prefs = settingsProvider.prefs;
              return MaterialApp(
                theme: OledTheme.buildTheme(prefs: prefs),
                home: GradesScreen(
                  allGrades: allGrades,
                  prefs: prefs,
                  onPrefsChanged: (next) => settingsProvider.updatePrefs(next),
                  onRefresh: () async {},
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Navigate into SubjectGradesDetailScreen via GradesTab card tap.
      await tester.tap(find.text('Fizika'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byTooltip('Tantárgy testreszabása'), findsOneWidget);

      // Open customization sheet, focus & edit text field, then tap top scrim to dismiss.
      await tester.tap(find.byTooltip('Tantárgy testreszabása'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final firstField = find.byType(TextField).first;
      await tester.tap(firstField);
      await tester.pump();
      await tester.enterText(firstField, 'Nem mentett');
      await tester.pump();

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.text('Tantárgy testreszabása'), findsNothing);
      expect(settingsProvider.prefs.subjectCustomNames['Fizika'], isNull);

      // Re-open, save an alias, close sheet, and pop route back to GradesTab.
      await tester.tap(find.byTooltip('Tantárgy testreszabása'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField).first, 'Fizika fakt');
      await tester.pump();
      final saveBtn = find.widgetWithText(FilledButton, 'Mentés');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(
        settingsProvider.prefs.subjectCustomNames['Fizika'],
        'Fizika fakt',
      );

      // Navigate back to GradesTab and verify alias persists without errors.
      await tester.pageBack();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull);
      expect(find.text('Fizika fakt'), findsOneWidget);
    },
  );
}
