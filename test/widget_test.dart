import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekreta_app/screens/grades_screen.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/animation_helpers.dart';

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
}
