import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/frosted_inspection_modal.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';
import 'package:tinta_naplo/widgets/real_liquid_glass_surface.dart';

StoredSession _testSession() => StoredSession(
      accessToken: 'acc_real_glass',
      refreshToken: 'ref_real_glass',
      idToken: 'id_real_glass',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    RealLiquidGlassShaderCache.resetForTest();
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    RealLiquidGlassShaderCache.resetForTest();
  });

  group('Real Liquid Glass persistence & platform rules', () {
    test(
      'UserProfilePrefs serializes, deserializes, and exports realLiquidGlassEnabled cleanly',
      () {
        const defaults = UserProfilePrefs();
        expect(defaults.realLiquidGlassEnabled, isFalse);

        final enabled = defaults.withRealLiquidGlass(true);
        expect(enabled.realLiquidGlassEnabled, isTrue);
        expect(enabled.liquidGlassEnabled, isTrue);
        expect(enabled.minimalistModeEnabled, isFalse);

        final jsonMap = enabled.toJson();
        expect(jsonMap['realLiquidGlassEnabled'], isTrue);
        expect(jsonMap['liquidGlassEnabled'], isTrue);

        final roundTrip = UserProfilePrefs.fromJson(jsonMap);
        expect(roundTrip.realLiquidGlassEnabled, isTrue);
        expect(roundTrip.liquidGlassEnabled, isTrue);

        final exported = enabled.toExportJsonString();
        final imported = UserProfilePrefs.fromExportJsonString(exported);
        expect(imported.realLiquidGlassEnabled, isTrue);
        expect(imported.liquidGlassEnabled, isTrue);

        final disabled = enabled.withRealLiquidGlass(false);
        expect(disabled.realLiquidGlassEnabled, isFalse);
      },
    );

    test(
      'TokenStorageService persists realLiquidGlassEnabled in SharedPreferences & SecureStorage',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        const storage = TokenStorageService();

        final initial = await storage.loadProfilePrefs();
        expect(initial.realLiquidGlassEnabled, isFalse);

        await storage.saveProfilePrefs(
          const UserProfilePrefs().withRealLiquidGlass(true),
        );

        final fromShared =
            await TokenStorageService.loadProfilePrefsFromSharedPrefs();
        expect(fromShared, isNotNull);
        expect(fromShared!.realLiquidGlassEnabled, isTrue);
        expect(fromShared.liquidGlassEnabled, isTrue);

        // Clear SharedPreferences to verify SecureStorage fallback restoration
        SharedPreferences.setMockInitialValues({});
        final fromSecure = await storage.loadProfilePrefs();
        expect(fromSecure.realLiquidGlassEnabled, isTrue);
        expect(fromSecure.liquidGlassEnabled, isTrue);
      },
    );

    test(
      'realLiquidGlassEnabled auto-enables Liquid Glass and is mutually exclusive with Minimalist Mode on Android',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        final fromMinimalist = const UserProfilePrefs()
            .withMinimalistMode(true)
            .withRealLiquidGlass(true);
        expect(fromMinimalist.realLiquidGlassEnabled, isTrue);
        expect(fromMinimalist.liquidGlassEnabled, isTrue);
        expect(fromMinimalist.minimalistModeEnabled, isFalse);

        final turnedMinimalistOn = fromMinimalist.withMinimalistMode(true);
        expect(turnedMinimalistOn.minimalistModeEnabled, isTrue);
        expect(turnedMinimalistOn.realLiquidGlassEnabled, isFalse);

        final rawUnnormalized = const UserProfilePrefs(
          realLiquidGlassEnabled: true,
          liquidGlassEnabled: false,
          extras: <String, dynamic>{'minimalistModeEnabled': true},
        ).effectiveForPlatform();
        expect(rawUnnormalized.realLiquidGlassEnabled, isTrue);
        expect(rawUnnormalized.liquidGlassEnabled, isTrue);
        expect(rawUnnormalized.minimalistModeEnabled, isFalse);

        final masterOff =
            fromMinimalist.copyWith(liquidGlassEnabled: false);
        expect(masterOff.liquidGlassEnabled, isFalse);
        expect(masterOff.realLiquidGlassEnabled, isFalse);

        final settings = SettingsProvider(initialPrefs: fromMinimalist);
        addTearDown(settings.dispose);
        final theme = ThemeProvider(settings);
        addTearDown(theme.dispose);
        expect(settings.realLiquidGlassEnabled, isTrue);
        expect(theme.realLiquidGlassEnabled, isTrue);
        expect(theme.liquidGlassEnabled, isTrue);
      },
    );

    test(
      'iOS keeps native Liquid Glass locked and disables Android shader mode',
      () {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        final attempted = const UserProfilePrefs().withRealLiquidGlass(true);
        final effective = attempted.effectiveForPlatform();

        expect(effective.realLiquidGlassEnabled, isFalse);
        expect(effective.liquidGlassEnabled, isTrue);
        expect(effective.liquidGlassMode, LiquidGlassMode.classicFrost);
        expect(resolveRealLiquidGlassEnabled(attempted), isFalse);
        expect(resolveLiquidGlassEnabled(attempted), isTrue);

        final settings = SettingsProvider(initialPrefs: attempted);
        addTearDown(settings.dispose);
        expect(settings.prefs.realLiquidGlassEnabled, isFalse);
        expect(settings.prefs.liquidGlassEnabled, isTrue);
      },
    );
  });

  group('RealLiquidGlassSurface safe fallback & surface upgrades', () {
    testWidgets(
      'RealLiquidGlassSurface renders safely via BackdropFilter + optical rim fallback in tests without throwing',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        await RealLiquidGlassSurface.prewarmShader();

        for (final themeData in [
          OledTheme.buildTheme(
            prefs: const UserProfilePrefs(
              themeStyle: AppThemeStyle.oledPureBlack,
              realLiquidGlassEnabled: true,
            ),
          ),
          OledTheme.buildTheme(
            prefs: const UserProfilePrefs(
              themeStyle: AppThemeStyle.light,
              realLiquidGlassEnabled: true,
            ),
          ),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: themeData,
              home: Scaffold(
                body: ListView(
                  children: const [
                    RealLiquidGlassSurface(
                      prefs: UserProfilePrefs(
                        realLiquidGlassEnabled: true,
                      ),
                      padding: EdgeInsets.all(16),
                      child: Text('Optikai Üveg'),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byType(RealLiquidGlassSurface), findsOneWidget);
          expect(find.byType(BackdropFilter), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(RealLiquidGlassSurface),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is CustomPaint &&
                    w.painter is RealLiquidGlassOpticalRimPainter,
              ),
            ),
            findsOneWidget,
          );
        }
      },
    );

    testWidgets(
      'RealLiquidGlassSurface respects reduced motion and handles simulated shader runtime failure safely',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        RealLiquidGlassShaderCache.debugOverrideShaderSupport = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: RealLiquidGlassSurface(
                    padding: EdgeInsets.all(16),
                    child: Text('Csökkentett mozgás'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Csökkentett mozgás'), findsOneWidget);
        expect(
          RealLiquidGlassSurface.isReducedMotionEnabled(
            tester.element(find.text('Csökkentett mozgás')),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'SoftGlassCard, LiquidGlassSurface, LiquidGlassPillSurface, and FrostedBottomSheetSurface upgrade to RealLiquidGlassSurface on Android',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        final androidPrefs = const UserProfilePrefs().withRealLiquidGlass(true);

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: androidPrefs),
            home: Scaffold(
              body: Column(
                children: [
                  SoftGlassCard(
                    prefs: androidPrefs,
                    child: const Text('Shader Kártya'),
                  ),
                  LiquidGlassSurface(
                    prefs: androidPrefs,
                    isDockStyle: true,
                    child: const SizedBox(height: 54, child: Text('Dokk')),
                  ),
                  const SizedBox(
                    width: 120,
                    height: 36,
                    child: LiquidGlassPillSurface(
                      pressProgress: 0.2,
                      realLiquidGlassEnabled: true,
                    ),
                  ),
                  FrostedBottomSheetSurface(
                    prefs: androidPrefs,
                    child: const Text('Modális Lap'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(RealLiquidGlassSurface), findsNWidgets(4));
      },
    );

    testWidgets(
      'SoftGlassCard, LiquidGlassSurface, LiquidGlassPillSurface, and FrostedBottomSheetSurface stay native on iOS without RealLiquidGlassSurface',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        final rawPrefs = const UserProfilePrefs(
          liquidGlassEnabled: true,
          realLiquidGlassEnabled: true,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: OledTheme.buildTheme(prefs: rawPrefs),
            home: Scaffold(
              body: Column(
                children: [
                  SoftGlassCard(
                    prefs: rawPrefs,
                    child: const Text('iOS Kártya'),
                  ),
                  LiquidGlassSurface(
                    prefs: rawPrefs,
                    isDockStyle: true,
                    child: const SizedBox(height: 54, child: Text('iOS Dokk')),
                  ),
                  const SizedBox(
                    width: 120,
                    height: 36,
                    child: LiquidGlassPillSurface(
                      pressProgress: 0.2,
                      realLiquidGlassEnabled: true,
                    ),
                  ),
                  FrostedBottomSheetSurface(
                    prefs: rawPrefs,
                    child: const Text('iOS Modális'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(RealLiquidGlassSurface), findsNothing);
      },
    );
  });

  group('Megjelenés és témák UI platform visibility & interaction', () {
    testWidgets(
      'Android shows Valódi Liquid Glass (Shader) toggle, badge, subtitle, and live preview, enforcing mutual exclusivity with Minimalist Mode',
      variant: TargetPlatformVariant.only(TargetPlatform.android),
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(liquidGlassEnabled: false),
        );
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
            child: ListenableBuilder(
              listenable: Listenable.merge([settings, theme]),
              builder: (context, _) => MaterialApp(
                theme: OledTheme.buildTheme(prefs: settings.prefs),
                home: AppSettingsScreen(
                  session: _testSession(),
                  student: null,
                  kretaClient: KretaClient(),
                  prefs: settings.prefs,
                  onPrefsChanged: (next) => settings.updatePrefs(next),
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();

        expect(find.text('Valódi Liquid Glass (Shader)'), findsOneWidget);
        expect(find.text('BETA'), findsOneWidget);
        expect(find.text('GPU'), findsOneWidget);
        expect(
          find.text(
            'Fizikai fénytörés, kromatikus színszóródás és dinamikus élfény az üvegkártyákon (erősebb GPU ajánlott).',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey<String>('real-liquid-glass-preview')),
          findsOneWidget,
        );
        expect(find.text('Material 3 Felület'), findsOneWidget);

        // Toggle Valódi Liquid Glass (Shader) ON
        final realSwitch = find.byKey(
          const ValueKey<String>('appearance-real-liquid-glass-switch'),
        );
        await tester.ensureVisible(realSwitch);
        await tester.tap(realSwitch);
        await tester.pumpAndSettle();

        expect(settings.prefs.realLiquidGlassEnabled, isTrue);
        expect(settings.prefs.liquidGlassEnabled, isTrue);
        expect(settings.prefs.minimalistModeEnabled, isFalse);
        expect(theme.realLiquidGlassEnabled, isTrue);
        expect(find.text('Valódi Optikai Üveg'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey<String>('real-liquid-glass-preview')),
            matching: find.byType(RealLiquidGlassSurface),
          ),
          findsOneWidget,
        );

        // Scroll to Minimalist Mode and enable it -> disables & hides shader option
        final outerScroll = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last;
        final minSwitch = find.byKey(
          const ValueKey<String>('appearance-minimalist-mode-switch'),
        );
        await tester.scrollUntilVisible(
          minSwitch,
          160,
          scrollable: outerScroll,
        );
        await tester.ensureVisible(minSwitch);
        await tester.tap(minSwitch);
        await tester.pumpAndSettle();

        expect(settings.prefs.minimalistModeEnabled, isTrue);
        expect(settings.prefs.realLiquidGlassEnabled, isFalse);
        expect(find.text('Valódi Liquid Glass (Shader)'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('real-liquid-glass-preview')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'iOS Megjelenés és témák hides the Android Valódi Liquid Glass (Shader) toggle and preview',
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
      (tester) async {
        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(),
        );
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
              home: AppSettingsScreen(
                session: _testSession(),
                student: null,
                kretaClient: KretaClient(),
                prefs: settings.prefs,
                onPrefsChanged: (next) => settings.updatePrefs(next),
                onLogout: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('ios-liquid-glass-locked-card')),
          findsOneWidget,
        );
        expect(find.text('Valódi Liquid Glass (Shader)'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('real-liquid-glass-preview')),
          findsNothing,
        );
        expect(find.text('BETA'), findsNothing);
      },
    );
  });
}
