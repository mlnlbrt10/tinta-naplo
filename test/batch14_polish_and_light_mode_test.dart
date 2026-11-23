import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinta_naplo/screens/login_screen.dart';
import 'package:tinta_naplo/services/demo_data_service.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/expandable_profile_card.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';

Lesson _makeLesson({
  required String uid,
  required int period,
  required String subjectName,
}) {
  final start = DateTime(2026, 11, 18, 12, 50);
  final dayIso = '${start.toIso8601String().split('T').first}T00:00:00Z';
  return Lesson.fromJson({
    'Uid': uid,
    'Datum': dayIso,
    'Oraszam': period,
    'KezdetIdopont': start.toUtc().toIso8601String(),
    'VegIdopont': start.add(const Duration(minutes: 45)).toUtc().toIso8601String(),
    'Nev': subjectName,
    'Tantargy': {
      'Uid': 'subj-$uid',
      'Nev': subjectName,
      'Kategoria': {
        'Uid': 'cat-$uid',
        'Nev': subjectName,
        'Leiras': subjectName,
      },
      'SortIndex': period,
    },
    'OsztalyCsoport': {'Uid': 'cg1', 'Nev': '11.A'},
    'TanarNeve': 'Horváth Zoltán',
    'TeremNeve': 'Lab-3',
    'Tipus': {
      'Uid': 'ora',
      'Nev': 'TanitasiOra',
      'Leiras': 'Tanítási óra',
    },
    'Allapot': {'Uid': 'a1', 'Nev': 'Megtartott', 'Leiras': 'Megtartott'},
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
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('1. Linear Hero / Boomerang Flight Path in FloatingGlassSheetRoute', () {
    testWidgets(
      'Badge near bottom flies directly along linear RectTween to floating sheet without shooting upward, and scrim tap dismisses',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final lesson6 = _makeLesson(
          uid: 'lesson-6',
          period: 6,
          subjectName: 'Adatbázis-kezelés',
        );
        const heroTag = 'lesson_num_lesson-6';

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(),
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    left: 28,
                    top: 670,
                    child: Builder(
                      builder: (context) => GestureDetector(
                        key: const ValueKey<String>('source-lesson-6'),
                        onTap: () => showLessonInspectionModal(
                          context,
                          lesson6,
                          heroTag: heroTag,
                        ),
                        child: const Hero(
                          tag: heroTag,
                          createRectTween: createLinearHeroRectTween,
                          flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
                          child: Material(
                            type: MaterialType.transparency,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Center(child: Text('6.')),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final sourceHero = tester.widget<Hero>(find.byType(Hero));
        expect(sourceHero.createRectTween, createLinearHeroRectTween);

        final sourceRect = tester.getRect(
          find.byKey(const ValueKey<String>('source-lesson-6')),
        );
        expect(sourceRect.top, closeTo(670, 2));

        await tester.tap(find.byKey(const ValueKey<String>('source-lesson-6')));
        await tester.pump();

        // Mid-flight sample at 150ms (~half of 340ms route transition)
        await tester.pump(const Duration(milliseconds: 150));

        final allHeroRects = find
            .byType(Hero)
            .evaluate()
            .map((e) => (e.findRenderObject() as RenderBox?)?.size)
            .toList();
        expect(allHeroRects, isNotEmpty);

        // Locate flying shuttle or badge rect during flight: never near top of screen (< 250px)
        final badgeTexts = find.text('6.').evaluate().toList();
        expect(badgeTexts, isNotEmpty);
        for (final el in badgeTexts) {
          final box = el.findRenderObject() as RenderBox;
          final globalOffset = box.localToGlobal(Offset.zero);
          expect(
            globalOffset.dy,
            greaterThan(350),
            reason: 'Hero badge must not jump upward toward top of screen',
          );
        }

        await tester.pumpAndSettle();
        expect(find.text('Adatbázis-kezelés'), findsOneWidget);

        // Destination Hero inside the floating modal also uses createLinearHeroRectTween
        final destHero = tester.widget<Hero>(
          find.descendant(
            of: find.byType(FrostedBottomSheetSurface),
            matching: find.byType(Hero),
          ),
        );
        expect(destHero.createRectTween, createLinearHeroRectTween);

        // Destination settled badge sits near the lower half of the 915px screen
        final settledBadgeRect = tester.getRect(find.text('6.').last);
        expect(settledBadgeRect.top, greaterThan(400));

        // Tapping upper dimmed scrim dismisses the floating modal cleanly
        await tester.tapAt(const Offset(20, 40));
        await tester.pumpAndSettle();
        expect(find.text('Adatbázis-kezelés'), findsNothing);
      },
    );
  });

  group('2 & 5. Profile Floating Liquid Glass Sheet & Removed Nickname Placeholder', () {
    testWidgets(
      'Profile sheet has no Alexa hint, floats with rounded FrostedBottomSheetSurface margins, linear avatar Hero, and Liquid Glass blur',
      (tester) async {
        tester.view.physicalSize = const Size(412, 915);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const glassPrefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.oledPureBlack,
          liquidGlassEnabled: true,
        );
        final student = DemoDataService.instance.buildDemoStudent();
        final session = DemoDataService.instance.buildDemoSession();

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: glassPrefs),
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: [
                    ProfileTopBarAvatar(
                      prefs: glassPrefs,
                      onTap: () => showStreamlinedProfileSheet(
                        context: context,
                        student: student,
                        session: session,
                        prefs: glassPrefs,
                        onPrefsChanged: (_) {},
                        onOpenFullSettings: () {},
                      ),
                    ),
                  ],
                ),
                body: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pump();

        // TopBar avatar Hero uses linear RectTween
        final barHero = tester.widget<Hero>(find.byType(Hero));
        expect(barHero.createRectTween, createLinearHeroRectTween);

        await tester.tap(find.byType(ProfileTopBarAvatar));
        await tester.pumpAndSettle();

        // Profile modal uses clean tap-to-edit interactions (no inline nickname TextField clutter)
        final surfaceFinder = find.byKey(
          const ValueKey<String>('profile-floating-sheet-surface'),
        );
        expect(surfaceFinder, findsOneWidget);
        expect(
          find.descendant(
            of: surfaceFinder,
            matching: find.byType(TextField),
          ),
          findsNothing,
        );
        expect(find.text('Alexa'), findsNothing);

        final surfaceWidget =
            tester.widget<FrostedBottomSheetSurface>(surfaceFinder);
        expect(surfaceWidget.topRadius, 26.0);

        final cardRect = tester.getRect(
          find
              .descendant(
                of: surfaceFinder,
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(cardRect.left, closeTo(12.0, 0.5));
        expect(cardRect.right, closeTo(400.0, 0.5));
        expect(cardRect.bottom, lessThanOrEqualTo(903.0));

        // Translucent BackdropFilter inside floating sheet when Liquid Glass is ON
        expect(
          find.descendant(
            of: surfaceFinder,
            matching: find.byType(BackdropFilter),
          ),
          findsOneWidget,
        );

        // Destination avatar Hero preserves linear RectTween
        final sheetHero = tester.widget<Hero>(
          find.descendant(
            of: surfaceFinder,
            matching: find.byType(Hero),
          ),
        );
        expect(sheetHero.createRectTween, createLinearHeroRectTween);

        // Tapping profile avatar opens modern photo action popup (without Delete when no photo set)
        await tester.tap(find.byKey(const ValueKey<String>('profile-avatar-tap')));
        await tester.pumpAndSettle();
        expect(find.text('Új profilkép választása'), findsOneWidget);
        expect(find.text('Jelenlegi kép törlése'), findsNothing);
        await tester.tapAt(const Offset(20, 80));
        await tester.pumpAndSettle();

        // Tapping user name opens modern nickname popup (and no Alexa hint exists)
        await tester.tap(find.byKey(const ValueKey<String>('profile-name-tap')));
        await tester.pumpAndSettle();
        expect(find.text('Alexa'), findsNothing);
        final nickField = tester.widget<TextField>(
          find.byKey(const ValueKey<String>('profile-nickname-input')),
        );
        expect(nickField.decoration?.labelText, 'Megjelenített név / Becenév');
        expect(nickField.decoration?.hintText, isNot(contains('Alexa')));
        await tester.tapAt(const Offset(20, 80));
        await tester.pumpAndSettle();

        // Dismiss main profile sheet via top scrim tap
        await tester.tapAt(const Offset(20, 80));
        await tester.pumpAndSettle();
        expect(surfaceFinder, findsNothing);
      },
    );
  });

  group('3 & 4. Showcase Metadata Clock Parser & Clean Login Loading Copy', () {
    test('formatStatusBarTimeFromMetadata parses EXIF, Android filenames, DateTime, and fallback', () {
      expect(
        LoginScreen.formatStatusBarTimeFromMetadata(
          exifDateTime: '2026:11:18 20:31:55',
        ),
        '20:31',
      );
      expect(
        LoginScreen.formatStatusBarTimeFromMetadata(
          filename: 'Screenshot_20261118_142709_Tinta.png',
        ),
        '14:27',
      );
      expect(
        LoginScreen.formatStatusBarTimeFromMetadata(
          modifiedAt: DateTime(2026, 11, 18, 9, 5),
        ),
        '09:05',
      );
      expect(LoginScreen.formatStatusBarTimeFromMetadata(), '08:02');
      expect(LoginScreen.fixedStatusBarTime, '08:02');
    });

    test('WebViewLoginScreen replaces technical OAuth/token jargon with Bejelentkezés...', () {
      final src = File('lib/screens/webview_login_screen.dart').readAsStringSync();
      expect(src, contains("'Bejelentkezés...'"));
      expect(src, isNot(contains('Token beváltása')));
      expect(src, isNot(contains('Kód beváltása tokenre')));
      expect(src, isNot(contains('/connect/token')));
      expect(src, isNot(contains('PKCE munkamenettel')));
    });
  });

  group('6. Complete Light Mode Redesign', () {
    testWidgets(
      'Light Mode configures dark status/nav bar icons, #F4F6F8 canvas, crisp white cards with soft shadows, and high-contrast semantic tokens',
      (tester) async {
        const lightSolidPrefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.light,
          liquidGlassEnabled: false,
        );
        const lightGlassPrefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.light,
          liquidGlassEnabled: true,
        );

        final theme = OledTheme.buildTheme(prefs: lightSolidPrefs);
        expect(theme.brightness, Brightness.light);
        expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F6F8));
        expect(theme.colorScheme.surfaceContainer, Colors.white);
        expect(theme.colorScheme.onSurface, const Color(0xFF0F172A));
        expect(theme.colorScheme.onSurfaceVariant, const Color(0xFF64748B));
        expect(
          theme.appBarTheme.systemOverlayStyle?.statusBarIconBrightness,
          Brightness.dark,
        );
        expect(
          theme.appBarTheme.systemOverlayStyle?.statusBarBrightness,
          Brightness.light,
        );
        expect(
          theme.appBarTheme.systemOverlayStyle?.systemNavigationBarIconBrightness,
          Brightness.dark,
        );

        // Richer semantic foreground in Light Mode vs Dark Mode
        const rawAmber = Color(0xFFF59E0B);
        final lightAmber = OledTheme.semanticForeground(rawAmber, Brightness.light);
        expect(
          lightAmber.computeLuminance(),
          lessThan(rawAmber.computeLuminance() * 0.55),
        );

        // Standard Light Mode SoftGlassCard: pure white + subtle hairline + soft elevation shadow
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Column(
                children: [
                  SoftGlassCard(
                    prefs: lightSolidPrefs,
                    child: Text('Világos kártya'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        final solidContainer = tester.widget<Container>(
          find.descendant(
            of: find.byType(SoftGlassCard),
            matching: find.byType(Container),
          ),
        );
        final solidDeco = solidContainer.decoration! as BoxDecoration;
        expect(solidDeco.color, Colors.white);
        expect(solidDeco.boxShadow, isNotEmpty);
        expect((solidDeco.border! as Border).top.color.a, closeTo(0.06, 0.01));

        // Liquid Glass Light Mode SoftGlassCard: bright frosted white gradient + soft shadow
        final glassTheme = OledTheme.buildTheme(prefs: lightGlassPrefs);
        await tester.pumpWidget(
          MaterialApp(
            theme: glassTheme,
            home: const Scaffold(
              body: SoftGlassCard(
                prefs: lightGlassPrefs,
                child: Text('Üveg világos kártya'),
              ),
            ),
          ),
        );
        await tester.pump();

        final glassContainer = tester.widget<Container>(
          find.descendant(
            of: find.byType(SoftGlassCard),
            matching: find.byType(Container),
          ),
        );
        final glassDeco = glassContainer.decoration! as BoxDecoration;
        final glassGrad = glassDeco.gradient! as LinearGradient;
        expect(glassGrad.colors.first.r, closeTo(1.0, 0.02));
        expect(glassGrad.colors.first.a, greaterThanOrEqualTo(0.78));
      },
    );
  });
}
