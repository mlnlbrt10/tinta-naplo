import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tinta_naplo/providers/app_providers.dart';
import 'package:tinta_naplo/screens/about_app_screen.dart';
import 'package:tinta_naplo/screens/developer_options_screen.dart';
import 'package:tinta_naplo/screens/more_screen.dart';
import 'package:tinta_naplo/services/kreta_client.dart';
import 'package:tinta_naplo/services/token_storage_service.dart';
import 'package:tinta_naplo/theme/oled_theme.dart';
import 'package:tinta_naplo/widgets/animation_helpers.dart';
import 'package:tinta_naplo/widgets/christmas_snowfall_overlay.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';
import 'package:tinta_naplo/widgets/tinta_toast.dart';

Future<Uint8List> _createSolidPngBytes(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 16, 16),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return byteData!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('Developer Options: 5 Physical-Optics Liquid Glass Modes', () {
    testWidgets(
      '5x version tap unlocks Developer Options and selecting all 5 LiquidGlassModes synchronously updates SettingsProvider & ThemeProvider',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(liquidGlassEnabled: true),
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
                home: AboutAppScreen(
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text('Fejlesztői beállítások'), findsNothing);

        // Tap version badge ('v3.1') 5 times to unlock Developer Options
        final versionFinder = find.text('v3.1');
        for (int i = 0; i < 5; i++) {
          await tester.tap(versionFinder);
          await tester.pump();
        }
        await tester.pump(const Duration(milliseconds: 500));
        TintaToast.dismissCurrent(immediate: true);

        expect(settings.prefs.developerModeUnlocked, isTrue);
        // Developer Options are NOT rendered inline inside AboutAppScreen
        expect(find.text('Fejlesztői beállítások'), findsNothing);

        final fakeSession = StoredSession(
          accessToken: 'acc',
          refreshToken: 'ref',
          idToken: 'id',
          instituteCode: 'klik001',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );

        // Mount AppSettingsScreen -> Developer Options is NOT on the Settings root
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
                  session: fakeSession,
                  student: null,
                  kretaClient: KretaClient(),
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Fejlesztői beállítások'), findsNothing);

        // Verify Liquid Glass modes were moved out of Developer Appearance sub-page
        // into main Settings -> "Megjelenés és témák"
        await tester.tap(find.text('Rendszer / Névjegy'));
        await tester.pumpAndSettle();
        expect(find.text('Fejlesztői beállítások'), findsOneWidget);

        await tester.tap(find.text('Fejlesztői beállítások'));
        await tester.pumpAndSettle();
        final devAppearanceTile = find.text('Megjelenés és UI');
        await tester.ensureVisible(devAppearanceTile);
        await tester.tap(devAppearanceTile);
        await tester.pumpAndSettle();
        expect(find.text('Liquid Glass Mód (Fizikai optika)'), findsNothing);

        // Return to AppSettingsScreen and open "Megjelenés és témák"
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        final mainAppearanceTile = find.text('Megjelenés és témák');
        await tester.ensureVisible(mainAppearanceTile);
        await tester.tap(mainAppearanceTile);
        await tester.pumpAndSettle();

        expect(find.text('Liquid Glass Mód (Fizikai optika)'), findsOneWidget);
        expect(find.text('Alaptéma & Színek'), findsOneWidget);
        expect(find.text('Liquid Glass & Felületek'), findsOneWidget);
        expect(find.text('Kártyák & Elrendezés'), findsOneWidget);
        expect(find.text('Ikon & Betűtípus'), findsOneWidget);

        expect(find.text('Élő megjelenési előnézet'), findsNothing);
        final modeRow = find.byKey(
          const ValueKey<String>('appearance-liquid-glass-mode-row'),
        );
        await tester.ensureVisible(modeRow);
        await tester.pump(const Duration(milliseconds: 300));

        // Select each of the 5 modes via floating popup and verify immediate synchronous updates
        for (final mode in LiquidGlassMode.values) {
          await tester.tap(modeRow);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 420));

          final option = find.text('${mode.label} (${mode.subtitle})');
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 420));

          expect(settings.prefs.liquidGlassMode, mode);
          expect(theme.liquidGlassMode, mode);
        }

        // Verify SharedPreferences JSON persistence round-trip
        await settings.flushPersistence();
        final reloaded =
            await TokenStorageService.loadProfilePrefsFromSharedPrefs();
        expect(reloaded, isNotNull);
        expect(reloaded!.liquidGlassMode, LiquidGlassMode.rippleGel);
      },
    );

    testWidgets(
      'Optical Prism rim renders chromatic amber & ice colors and Smoked Obsidian uses critically-damped physics',
      (tester) async {
        // Critically-damped viscous ratio check: zeta = c / (2 * sqrt(k)) >= 1.0
        const obsidian = LiquidGlassMode.smokedObsidian;
        expect(obsidian.dampingX, greaterThan(2 * 14.0));
        expect(obsidian.stretchMultiplier, lessThan(0.5));

        const painter = LiquidGlassRimPainter(
          borderRadius: BorderRadius.all(Radius.circular(24)),
          strokeWidth: 1.5,
          pressProgress: 0.4,
          highlightBias: Offset(0.5, 0.0),
          isDark: true,
          mode: LiquidGlassMode.opticalPrism,
        );
        final colors = painter.buildPerimeterColors();
        expect(colors.first.toARGB32() & 0x00FFFFFF, 0xFFB86C);
        expect(colors.last.toARGB32() & 0x00FFFFFF, 0x8BE9FD);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 100,
                  height: 36,
                  child: LiquidGlassPillSurface(
                    pressProgress: 0.5,
                    mode: LiquidGlassMode.rippleGel,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(LiquidGlassPillSurface), findsOneWidget);
        expect(find.byType(BackdropFilter), findsNothing);
      },
    );
  });

  group('Studio Backdrops, Vector Contours, Custom Image & Adaptive Contrast', () {
    testWidgets(
      'Built-in studio backdrops render and switch adaptive typography/card tokens automatically by luminance',
      (tester) async {
        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(
            developerModeUnlocked: true,
            themeStyle: AppThemeStyle.oledPureBlack,
            liquidGlassEnabled: true,
          ),
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
              builder: (context, _) {
                final builtTheme = OledTheme.buildTheme(prefs: settings.prefs);
                return MaterialApp(
                  theme: builtTheme,
                  themeAnimationDuration: Duration.zero,
                  home: AdaptiveBackgroundScaffold(
                    prefs: settings.prefs,
                    appBar: AppBar(title: const Text('Stúdió Teszt')),
                    body: SoftGlassCard(
                      prefs: settings.prefs,
                      child: const Text('Adaptív Felirat'),
                    ),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pump();

        // 1. Switch to Warm Alabaster (light backdrop >= 0.45)
        await settings.updateWith(
          (p) => p.copyWith(backgroundPreset: 'warm_alabaster'),
        );
        await tester.pump();

        expect(theme.isLight, isTrue);
        expect(theme.adaptivePrimaryText, const Color(0xFF101318));
        expect(theme.adaptiveSecondaryText, const Color(0xFF475467));
        expect(theme.adaptiveIconColor, const Color(0xFF101318));
        expect(theme.adaptiveCardFill, Colors.white.withValues(alpha: 0.78));
        expect(theme.adaptiveCardBorder, Colors.black.withValues(alpha: 0.08));

        final lightTextContext = tester.element(find.text('Adaptív Felirat'));
        expect(Theme.of(lightTextContext).brightness, Brightness.light);
        expect(
          Theme.of(lightTextContext).colorScheme.onSurface,
          const Color(0xFF101318),
        );

        // Zero BackdropFilter layers added by background/card system (120fps invariant)
        expect(find.byType(BackdropFilter), findsNothing);

        // 2. Switch to Topographic Contour (dark backdrop < 0.45 with vector painter)
        await settings.updateWith(
          (p) => p.copyWith(backgroundPreset: 'topographic_contour'),
        );
        await tester.pump();

        expect(theme.isLight, isFalse);
        expect(theme.adaptivePrimaryText, const Color(0xFFF5F7FA));
        expect(theme.adaptiveSecondaryText, const Color(0xFFB8C0CC));
        expect(theme.adaptiveCardFill, const Color(0xFF141820).withValues(alpha: 0.72));
        expect(theme.adaptiveCardBorder, Colors.white.withValues(alpha: 0.12));

        final contourPainters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((cp) => cp.painter)
            .whereType<TopographicContourPainter>();
        expect(contourPainters.length, 1);

        // Verify all remaining dark studio presets stay < 0.45 luminance
        for (final darkId in [
          'nordic_slate',
          'brushed_titanium',
          'monolith_mesh',
          'solarized_dusk',
        ]) {
          await settings.updateWith(
            (p) => p.copyWith(backgroundPreset: darkId),
          );
          await tester.pump();
          expect(theme.isLight, isFalse, reason: '$darkId must be dark');
          expect(theme.adaptivePrimaryText, const Color(0xFFF5F7FA));
        }
      },
    );

    testWidgets(
      'Custom image backdrop computes 32x32 luminance, renders with ResizeImage(width: 1440), and adapts typography across dim slider changes',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final tempDir = Directory.systemTemp.createTempSync('tinta_backdrop_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        final brightPng = (await tester.runAsync(
          () => _createSolidPngBytes(const Color(0xFFF2F2F2)),
        ))!;
        final settings = SettingsProvider(
          initialPrefs: const UserProfilePrefs(
            developerModeUnlocked: true,
            liquidGlassEnabled: true,
            customBackdropDim: 0.10,
          ),
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
                themeAnimationDuration: Duration.zero,
                home: DeveloperOptionsHubScreen(
                  prefs: settings.prefs,
                  onPrefsChanged: (_) {},
                  customImagePicker: () async => brightPng,
                  backdropDirectoryProvider: () async => tempDir,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        // Open Appearance & UI developer sub-page
        final appearanceTile = find.text('Megjelenés és UI');
        await tester.ensureVisible(appearanceTile);
        await tester.tap(appearanceTile);
        await tester.pumpAndSettle();

        // Pick bright custom wallpaper via Developer Options button
        final pickBtn = find.text('Saját háttérkép kiválasztása');
        await tester.ensureVisible(pickBtn);
        await tester.tap(pickBtn);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(settings.prefs.hasCustomBackdrop, isTrue);
        expect(
          settings.prefs.customBackdropPath,
          '${tempDir.path}/custom_backdrop.jpg',
        );
        expect(settings.prefs.customBackdropLuminance, greaterThan(0.9));
        // Effective luminance = ~0.95 * (1 - 0.10) = ~0.855 >= 0.45 -> light contrast
        expect(theme.isLight, isTrue);
        expect(theme.adaptivePrimaryText, const Color(0xFF101318));

        // Verify Image uses ResizeImage with width: 1440 inside overlay
        final imageWidget = tester.widget<Image>(find.byType(Image).first);
        expect(imageWidget.image, isA<ResizeImage>());
        final resized = imageWidget.image as ResizeImage;
        expect(resized.width, 1440);
        expect(
          find.ancestor(
            of: find.byWidget(imageWidget),
            matching: find.byType(BackdropFilter),
          ),
          findsNothing,
        );

        // Increase dim slider to 75% -> effective luminance drops below 0.45 -> switches to dark contrast
        final slider = tester.widget<Slider>(find.byType(Slider));
        slider.onChanged?.call(0.75);
        await tester.pump();

        expect(settings.prefs.customBackdropDim, closeTo(0.75, 0.001));
        expect(theme.isLight, isFalse);
        expect(theme.adaptivePrimaryText, const Color(0xFFF5F7FA));

        // Clear wallpaper button removes custom backdrop cleanly
        final deleteBtn = find.text('Háttérkép törlése');
        await tester.ensureVisible(deleteBtn);
        await tester.tap(deleteBtn);
        await tester.pump();

        expect(settings.prefs.hasCustomBackdrop, isFalse);
      },
    );
  });
}
