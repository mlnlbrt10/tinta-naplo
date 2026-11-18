import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rekreta_app/providers/app_providers.dart';
import 'package:rekreta_app/screens/about_app_screen.dart';
import 'package:rekreta_app/services/token_storage_service.dart';
import 'package:rekreta_app/theme/oled_theme.dart';
import 'package:rekreta_app/widgets/animation_helpers.dart';
import 'package:rekreta_app/widgets/christmas_snowfall_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    BackdropMotionCoordinator.clear();
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('AnimatedBackdropPreset model & adaptive contrast', () {
    test('serializes and restores every preset cleanly', () {
      for (final preset in AnimatedBackdropPreset.values) {
        final prefs = UserProfilePrefs(animatedBackdropPreset: preset);
        final roundTrip = UserProfilePrefs.fromJson(prefs.toJson());
        expect(roundTrip.animatedBackdropPreset, preset);
        expect(roundTrip.hasAnimatedBackdrop,
            preset != AnimatedBackdropPreset.off);
      }
      expect(
        AnimatedBackdropPreset.fromName('non_existent'),
        AnimatedBackdropPreset.off,
      );
    });

    test('computes adaptive dark studio contrast tokens for animated presets',
        () {
      for (final preset in AnimatedBackdropPreset.values) {
        if (preset == AnimatedBackdropPreset.off) continue;
        final prefs = UserProfilePrefs(animatedBackdropPreset: preset);
        final tokens = AdaptiveContrastTokens.resolve(prefs);
        final theme = OledTheme.buildTheme(prefs: prefs);
        expect(tokens.isLightBackdrop, isFalse);
        expect(tokens.primaryText, const Color(0xFFF5F7FA));
        expect(theme.scaffoldBackgroundColor, preset.baseColor);
      }
    });
  });

  group('BackdropMotionCoordinator & LiquidGlassRimPainter sync', () {
    test('ring buffer bounds to 6 ripples, steps lifetimes, and clears cleanly',
        () {
      BackdropMotionCoordinator.clear();
      for (int i = 0; i < 8; i++) {
        BackdropMotionCoordinator.addTouchWave(
          Offset(i * 40.0, 200.0),
          const Size(400, 800),
        );
      }
      final activeCount =
          BackdropMotionCoordinator.waves.where((w) => w.active).length;
      expect(activeCount, BackdropMotionCoordinator.maxWaves);

      BackdropMotionCoordinator.stepWaves(2.5);
      expect(
        BackdropMotionCoordinator.waves.any((w) => w.active),
        isFalse,
      );
    });

    test('lightBiasNotifier shifts LiquidGlassRimPainter without breaking neutral zero',
        () {
      const neutralPainter = LiquidGlassRimPainter(
        borderRadius: BorderRadius.all(Radius.circular(999)),
        strokeWidth: 1.2,
        pressProgress: 0.5,
        highlightBias: Offset.zero,
        isDark: true,
        mode: LiquidGlassMode.opticalPrism,
      );
      final notifier = ValueNotifier<Offset>(Offset.zero);
      final syncedPainter = LiquidGlassRimPainter(
        borderRadius: const BorderRadius.all(Radius.circular(999)),
        strokeWidth: 1.2,
        pressProgress: 0.5,
        highlightBias: Offset.zero,
        isDark: true,
        mode: LiquidGlassMode.opticalPrism,
        lightBiasListenable: notifier,
      );

      // Neutral ambient bias produces identical rim stops.
      expect(
        syncedPainter.buildPerimeterColors(),
        neutralPainter.buildPerimeterColors(),
      );

      // Shifted virtual light source swaps warm amber <-> cool ice rim dominance.
      notifier.value = const Offset(-0.9, 0.4);
      expect(
        syncedPainter.buildPerimeterColors(),
        isNot(neutralPainter.buildPerimeterColors()),
      );
      notifier.dispose();
    });
  });

  group('AnimatedBackdropLayer rendering & lifecycle auto-pause', () {
    testWidgets(
      'renders all 6 animated presets inside RepaintBoundary with zero BackdropFilter and pauses on background',
      (tester) async {
        for (final preset in AnimatedBackdropPreset.values) {
          if (preset == AnimatedBackdropPreset.off) continue;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SizedBox.expand(
                  child: AnimatedBackdropLayer(preset: preset),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 32));
          await tester.pump(const Duration(milliseconds: 32));

          expect(find.byType(RepaintBoundary), findsWidgets);
          expect(find.byType(BackdropFilter), findsNothing);
          expect(find.byType(CustomPaint), findsWidgets);

          if (preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
            expect(
              BackdropMotionCoordinator.lightBiasNotifier.value,
              isNot(Offset.zero),
            );

            // Simulate app entering background -> must stop updating & clear bias
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.paused);
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              BackdropMotionCoordinator.lightBiasNotifier.value,
              Offset.zero,
            );

            // Resume -> animation restarts immediately
            tester.binding
                .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
            await tester.pump(const Duration(milliseconds: 50));
            expect(
              BackdropMotionCoordinator.lightBiasNotifier.value,
              isNot(Offset.zero),
            );
          }
        }

        // Unmount cleans up coordinator state
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(BackdropMotionCoordinator.lightBiasNotifier.value, Offset.zero);
      },
    );

    testWidgets(
      'Gyro Liquid Horizon captures pointer ripples through ChristmasAndBackgroundOverlay and Developer Options switches animated presets synchronously',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 3200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(developerModeUnlocked: true),
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
                builder: (context, child) => ChristmasAndBackgroundOverlay(
                  prefs: settings.prefs,
                  child: child ?? const SizedBox.shrink(),
                ),
                home: AboutAppScreen(
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final appearanceTile = find.text('Megjelenés és UI');
        await tester.ensureVisible(appearanceTile);
        await tester.tap(appearanceTile);
        await tester.pumpAndSettle();

        final animatedHeader = find.text('Animált hátterek (kísérleti)');
        await tester.scrollUntilVisible(
          animatedHeader,
          200.0,
          scrollable: find.byType(Scrollable).last,
        );
        expect(animatedHeader, findsOneWidget);

        for (final preset in [
          AnimatedBackdropPreset.gyroLiquidHorizon,
          AnimatedBackdropPreset.causticWater,
          AnimatedBackdropPreset.ferrofluidDrift,
          AnimatedBackdropPreset.sunbeamDust,
          AnimatedBackdropPreset.topographicPulse,
          AnimatedBackdropPreset.analogFilmLight,
          AnimatedBackdropPreset.off,
        ]) {
          final chip = find.widgetWithText(ChoiceChip, preset.label);
          await tester.tap(chip);
          await tester.pump(const Duration(milliseconds: 30));
          expect(settings.prefs.animatedBackdropPreset, preset);
        }

        // Turn Gyro Liquid Horizon back on and send pointer down across screen
        await tester.tap(
          find.widgetWithText(
            ChoiceChip,
            AnimatedBackdropPreset.gyroLiquidHorizon.label,
          ),
        );
        await tester.pump(const Duration(milliseconds: 30));

        await tester.tapAt(const Offset(540, 1200));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          BackdropMotionCoordinator.waves.any((w) => w.active),
          isTrue,
        );
      },
    );
  });
}
