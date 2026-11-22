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
import 'package:tinta_naplo/widgets/christmas_snowfall_overlay.dart';
import 'package:tinta_naplo/widgets/glass_card.dart';

StoredSession _testSession() => StoredSession(
      accessToken: 'acc',
      refreshToken: 'ref',
      idToken: 'id',
      instituteCode: 'klik001',
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    UserProfilePrefs.syncActiveGlobals(const UserProfilePrefs());
  });

  group('Liquid Glass preference & legacy Soft Blur migration', () {
    test('UserProfilePrefs defaults liquidGlassEnabled to false and migrates legacy keys', () {
      const defaults = UserProfilePrefs();
      expect(defaults.liquidGlassEnabled, isFalse);
      expect(defaults.cardBlurEnabled, isFalse);

      final fromCardBlur = UserProfilePrefs.fromJson({'cardBlurEnabled': true});
      expect(fromCardBlur.liquidGlassEnabled, isTrue);

      final fromSoftBlur = UserProfilePrefs.fromJson({'softBlur': true});
      expect(fromSoftBlur.liquidGlassEnabled, isTrue);

      final overrideNew = UserProfilePrefs.fromJson({
        'liquidGlassEnabled': false,
        'cardBlurEnabled': true,
      });
      expect(overrideNew.liquidGlassEnabled, isFalse);

      final roundTripOn = const UserProfilePrefs(liquidGlassEnabled: true);
      final jsonOn = roundTripOn.toJson();
      expect(jsonOn['liquidGlassEnabled'], isTrue);
      expect(UserProfilePrefs.fromJson(jsonOn).liquidGlassEnabled, isTrue);
    });

    test('TokenStorageService migrates kreta_card_blur_enabled to kreta_liquid_glass_enabled', () async {
      FlutterSecureStorage.setMockInitialValues({
        'kreta_card_blur_enabled': 'true',
      });
      const storage = TokenStorageService();

      final migrated = await storage.loadProfilePrefs();
      expect(migrated.liquidGlassEnabled, isTrue);

      await storage.saveProfilePrefs(migrated.copyWith(liquidGlassEnabled: false));
      final reloaded = await storage.loadProfilePrefs();
      expect(reloaded.liquidGlassEnabled, isFalse);
    });
  });

  group('Settings UI & Opaque M3 vs Frosted Surfaces', () {
    testWidgets('Settings renders Liquid Glass toggle, subtitle, and conditionally reveals sliders', (tester) async {
      final settings = SettingsProvider(
        initialPrefs: const UserProfilePrefs(liquidGlassEnabled: false),
      );
      addTearDown(settings.dispose);
      final theme = ThemeProvider(settings);
      addTearDown(theme.dispose);

      await tester.pumpWidget(
        ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            return MaterialApp(
              theme: OledTheme.buildTheme(prefs: settings.prefs),
              home: AppSettingsScreen(
                session: _testSession(),
                student: null,
                kretaClient: KretaClient(),
                prefs: settings.prefs,
                onPrefsChanged: (next) => settings.updatePrefs(next),
                onLogout: () {},
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Megjelenés és témák'));
      await tester.pumpAndSettle();

      expect(find.text('Liquid Glass'), findsOneWidget);
      expect(
        find.text(
          'Átlátszó üveghatású felületek és rugalmas, folyadékfizikás csúszkák',
        ),
        findsOneWidget,
      );
      expect(find.text('Áttetszőség'), findsNothing);
      expect(find.text('Elmosás erőssége'), findsNothing);
      expect(find.text('Háttér effektus / atmoszféra:'), findsNothing);
      expect(find.text('Liquid Glass Mód (Fizikai optika)'), findsNothing);
      expect(theme.liquidGlassEnabled, isFalse);

      await tester.tap(find.text('Liquid Glass'));
      await tester.pumpAndSettle();

      expect(settings.prefs.liquidGlassEnabled, isTrue);
      expect(theme.liquidGlassEnabled, isTrue);
      expect(find.text('Áttetszőség'), findsOneWidget);
      expect(find.text('Elmosás erőssége'), findsOneWidget);
      expect(find.text('Háttér effektus / atmoszféra:'), findsOneWidget);
      expect(find.text('Liquid Glass Mód (Fizikai optika)'), findsOneWidget);
    });

    testWidgets('SoftGlassCard, LiquidGlassSurface, and ChristmasAndBackgroundOverlay render opaque M3 surfaces when Liquid Glass is OFF', (tester) async {
      const offPrefs = UserProfilePrefs(
        themeStyle: AppThemeStyle.standardDark,
        liquidGlassEnabled: false,
        cardOpacity: 0.65,
      );
      final builtTheme = OledTheme.buildTheme(prefs: offPrefs);
      final scheme = builtTheme.colorScheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: builtTheme,
          home: Scaffold(
            body: Column(
              children: [
                const SoftGlassCard(
                  prefs: offPrefs,
                  child: Text('Card OFF'),
                ),
                LiquidGlassSurface(
                  prefs: offPrefs,
                  solidColor: Colors.black.withValues(alpha: 0.7),
                  child: const Text('Surface OFF'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);

      final cardContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(SoftGlassCard),
          matching: find.byType(Container),
        ),
      );
      final cardDeco = cardContainer.decoration! as BoxDecoration;
      expect(cardDeco.color, scheme.surfaceContainer);
      expect(cardDeco.color!.a, closeTo(1.0, 0.001));
      expect((cardDeco.border! as Border).top.color, scheme.outlineVariant);

      final surfaceContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(LiquidGlassSurface),
          matching: find.byType(Container),
        ),
      );
      final surfaceDeco = surfaceContainer.decoration! as BoxDecoration;
      expect(surfaceDeco.color!.a, closeTo(1.0, 0.001));
      expect((surfaceDeco.border! as Border).top.color, scheme.outlineVariant);

      // Ambient radial glow orbs are disabled when Liquid Glass is OFF and enabled when ON
      await tester.pumpWidget(
        MaterialApp(
          theme: OledTheme.buildTheme(
            prefs: const UserProfilePrefs(
              themeStyle: AppThemeStyle.oledPureBlack,
              liquidGlassEnabled: false,
            ),
          ),
          home: const ChristmasAndBackgroundOverlay(
            prefs: UserProfilePrefs(
              themeStyle: AppThemeStyle.oledPureBlack,
              liquidGlassEnabled: false,
            ),
            child: SizedBox.expand(),
          ),
        ),
      );
      expect(
        ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
          tester.element(find.byType(ChristmasAndBackgroundOverlay)),
          const UserProfilePrefs(liquidGlassEnabled: false),
        ),
        isFalse,
      );

      expect(
        ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
          tester.element(find.byType(ChristmasAndBackgroundOverlay)),
          const UserProfilePrefs(liquidGlassEnabled: true),
        ),
        isTrue,
      );
    });
  });

  group('Dual-Mode Segmented Slider Physics (Liquid Glass vs Material 3)', () {
    testWidgets('LiquidBubbleTabBar in Material 3 mode (liquidGlassEnabled: false) uses secondaryContainer pill, outlineVariant border, strict edge clamping, 1.0x scale, zero Y pull, and 220ms easeOutCubic slide', (tester) async {
      int selected = 0;

      final themeData = ThemeData.dark(useMaterial3: true);
      final scheme = themeData.colorScheme;

      await tester.pumpWidget(
        MaterialApp(
          theme: themeData,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Center(
                  child: SizedBox(
                    width: 360,
                    child: LiquidBubbleTabBar(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      liquidGlassEnabled: false,
                      selectedIndex: selected,
                      onSelected: (idx) => setState(() => selected = idx),
                      items: const [
                        LiquidBubbleTabItem(
                          label: 'Első',
                          icon: Icons.home_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Második',
                          icon: Icons.star_rounded,
                        ),
                        LiquidBubbleTabItem(
                          label: 'Harmadik',
                          icon: Icons.timer_rounded,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(LiquidGlassPillSurface), findsNothing);
      expect(find.byType(Material3TonalPillSurface), findsOneWidget);

      final trackContainer = tester.widget<Container>(
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
      expect(trackContainer.clipBehavior, Clip.hardEdge);
      final trackDeco = trackContainer.decoration! as BoxDecoration;
      expect(trackDeco.color, scheme.surfaceContainer);
      expect(trackDeco.color!.a, closeTo(1.0, 0.001));
      expect((trackDeco.border! as Border).top.color, scheme.outlineVariant);

      final pillDecorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(Material3TonalPillSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      final pillBox = pillDecorated.decoration as BoxDecoration;
      expect(pillBox.color, scheme.secondaryContainer);

      // Active label text & icon use onSecondaryContainer
      final activeText = tester.widget<Text>(find.text('Első'));
      expect(activeText.style?.color, scheme.onSecondaryContainer);
      final activeIcon = tester.widget<Icon>(find.byIcon(Icons.home_rounded));
      expect(activeIcon.color, scheme.onSecondaryContainer);

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

      final restingPill = tester.widget<Positioned>(pillFinder);
      final restingLeft = restingPill.left!;
      expect(restingPill.top!, closeTo(0.0, 0.001));

      // Press-and-hold + drag across to 'Harmadik' AND straight-horizontal drag:
      // grab & drag are strictly disabled in M3 mode (pill stays put, selection stays 0).
      final holdGesture = await tester.startGesture(
        tester.getCenter(find.text('Első')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < 10; i++) {
        await holdGesture.moveBy(const Offset(18, 2));
        await tester.pump(const Duration(milliseconds: 16));
      }

      var m3Pill = tester.widget<Positioned>(pillFinder);
      expect(m3Pill.left!, closeTo(restingLeft, 0.5));
      expect(m3Pill.top!, closeTo(0.0, 0.001));
      var m = tester.widget<Transform>(transformFinder).transform;
      expect(m.entry(0, 0), closeTo(1.0, 0.001));
      expect(m.entry(1, 1), closeTo(1.0, 0.001));
      expect(m.entry(0, 1), closeTo(0.0, 0.001));
      expect(selected, 0);

      await holdGesture.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(selected, 0);

      await tester.drag(find.text('Első'), const Offset(180, 0));
      await tester.pump(const Duration(milliseconds: 250));
      m3Pill = tester.widget<Positioned>(pillFinder);
      expect(m3Pill.left!, closeTo(restingLeft, 0.5));
      expect(m3Pill.top!, closeTo(0.0, 0.001));
      m = tester.widget<Transform>(transformFinder).transform;
      expect(m.entry(0, 0), closeTo(1.0, 0.001));
      expect(selected, 0);

      // Tap last segment: monotonically glides to target via easeOutCubic (~220ms) with ZERO overshoot
      await tester.tap(find.text('Harmadik'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      final midLeft = tester.widget<Positioned>(pillFinder).left!;
      final midMatrix = tester.widget<Transform>(transformFinder).transform;
      expect(midMatrix.entry(0, 0), closeTo(1.0, 0.001));
      expect(midMatrix.entry(1, 1), closeTo(1.0, 0.001));
      expect(midLeft, greaterThan(restingLeft));

      await tester.pump(const Duration(milliseconds: 140));
      final endLeft = tester.widget<Positioned>(pillFinder).left!;
      expect(midLeft, lessThanOrEqualTo(endLeft + 0.01));
      expect(selected, 2);
      expect(
        tester.widget<Text>(find.text('Harmadik')).style?.color,
        scheme.onSecondaryContainer,
      );
    });

    testWidgets('LiquidBubbleTabBar reacts live to SettingsProvider liquidGlassEnabled toggles', (tester) async {
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
          child: MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: LiquidBubbleTabBar(
                selectedIndex: 0,
                onSelected: (_) {},
                items: const [
                  LiquidBubbleTabItem(label: 'Egy'),
                  LiquidBubbleTabItem(label: 'Kettő'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Material3TonalPillSurface), findsOneWidget);
      expect(find.byType(LiquidGlassPillSurface), findsNothing);

      settings.updateWith((p) => p.copyWith(liquidGlassEnabled: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(LiquidGlassPillSurface), findsOneWidget);
      expect(find.byType(Material3TonalPillSurface), findsNothing);

      settings.updateWith((p) => p.copyWith(liquidGlassEnabled: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Material3TonalPillSurface), findsOneWidget);
      expect(find.byType(LiquidGlassPillSurface), findsNothing);
    });

    testWidgets('LiquidSpringPillTrack disables overscroll, press magnification, and vertical pull when liquidGlassEnabled is false', (tester) async {
      int selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: LiquidGlassSurface(
                  prefs: const UserProfilePrefs(liquidGlassEnabled: false),
                  isDockStyle: true,
                  borderRadius: BorderRadius.circular(32),
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      return LiquidSpringPillTrack(
                        itemCount: 4,
                        selectedIndex: selected,
                        height: 62,
                        pillWidth: 56,
                        pillHeight: 42,
                        liquidGlassEnabled: false,
                        onSelected: (idx) => setState(() => selected = idx),
                        pillBuilder: (_, __) => const Material3TonalPillSurface(
                          borderRadius: BorderRadius.all(Radius.circular(22)),
                        ),
                        itemBuilder: (_, idx, __) => Center(child: Text('D$idx')),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byType(Material3TonalPillSurface), findsOneWidget);

      final pillFinder = find.descendant(
        of: find.byType(LiquidSpringPillTrack),
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && w.width == 56 && w.height == 42,
        ),
      );
      final stack = tester.widget<Stack>(
        find.descendant(
          of: find.byType(LiquidSpringPillTrack),
          matching: find.byType(Stack),
        ),
      );
      expect(stack.clipBehavior, Clip.hardEdge);

      final resting = tester.widget<Positioned>(pillFinder);
      final restingLeft = resting.left!;
      final restingTop = resting.top!;

      // Hold + pull across to D2 & straight horizontal drag:
      // disabled in M3 mode (stays at slot 0, zero Y offset, identity Transform),
      // while standard tap still selects and slides cleanly.
      final g = await tester.startGesture(tester.getCenter(find.text('D0')));
      await tester.pump(const Duration(milliseconds: 120));
      for (int i = 0; i < 8; i++) {
        await g.moveBy(const Offset(16, 2));
        await tester.pump(const Duration(milliseconds: 16));
      }
      var dragged = tester.widget<Positioned>(pillFinder);
      expect(dragged.left!, closeTo(restingLeft, 0.5));
      expect(dragged.top!, closeTo(restingTop, 0.001));
      expect(selected, 0);

      final transform = tester.widget<Transform>(
        find.descendant(of: pillFinder, matching: find.byType(Transform)),
      );
      expect(transform.transform.entry(0, 0), closeTo(1.0, 0.001));
      expect(transform.transform.entry(1, 1), closeTo(1.0, 0.001));

      await g.up();
      await tester.pump(const Duration(milliseconds: 250));
      expect(selected, 0);

      await tester.drag(find.text('D0'), const Offset(130, 0));
      await tester.pump(const Duration(milliseconds: 250));
      dragged = tester.widget<Positioned>(pillFinder);
      expect(dragged.left!, closeTo(restingLeft, 0.5));
      expect(selected, 0);

      await tester.tap(find.text('D2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(selected, 2);
      expect(tester.widget<Positioned>(pillFinder).left!, greaterThan(restingLeft));
    });

    testWidgets('LiquidGlassPillSurface uses uniform translucent fill and 1px–1.2px pure-white stadium perimeter rim without top grey chord strip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 36,
                child: LiquidGlassPillSurface(pressProgress: 0.0),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Zero interior Align / Container chord stripe bars inside LiquidGlassPillSurface
      expect(
        find.descendant(
          of: find.byType(LiquidGlassPillSurface),
          matching: find.byType(Align),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(LiquidGlassPillSurface),
          matching: find.byType(Container),
        ),
        findsNothing,
      );

      final decorated = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(LiquidGlassPillSurface),
          matching: find.byType(DecoratedBox),
        ),
      );
      final box = decorated.decoration as BoxDecoration;
      expect(box.gradient, isNull);
      expect(box.border, isNull);
      expect(box.color, isNotNull);
      expect(box.color!.a, inInclusiveRange(0.15, 0.40));

      final rimPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(LiquidGlassPillSurface),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is LiquidGlassRimPainter,
          ),
        ),
      );
      final painter = rimPaint.painter! as LiquidGlassRimPainter;
      expect(painter.strokeWidth, inInclusiveRange(1.0, 1.2));

      final colors = painter.buildPerimeterColors();
      for (final c in colors) {
        expect(c.r, closeTo(1.0, 0.001));
        expect(c.g, closeTo(1.0, 0.001));
        expect(c.b, closeTo(1.0, 0.001));
      }
      expect(colors[0].a, closeTo(0.32, 0.01));
      expect(colors[2].a, closeTo(0.10, 0.01));
      expect(colors[4].a, closeTo(0.18, 0.01));
    });

    testWidgets(
      'toggling Liquid Glass OFF in Megjelenés és témák synchronously updates SettingsProvider/ThemeProvider and allows immediate Backdrop Color selection on same frame',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const initialPrefs = UserProfilePrefs(
          themeStyle: AppThemeStyle.oledPureBlack,
          liquidGlassEnabled: true,
          backgroundPreset: 'pure_oled',
        );
        final settings = SettingsProvider(initialPrefs: initialPrefs);
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
                  prefs: initialPrefs, // Deliberately static to verify provider reactivity
                  onPrefsChanged: (_) {},
                  onLogout: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.text('Megjelenés és témák'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 320));

        expect(find.text('Áttetszőség'), findsOneWidget);
        expect(find.text('Elmosás erőssége'), findsOneWidget);
        expect(find.text('Háttér effektus / atmoszféra:'), findsOneWidget);

        // Select studio preset 'Nordic Slate' while Liquid Glass sub-options are expanded
        final outerScroll = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .last;
        final slateChip = find.text('Nordic Slate');
        await tester.scrollUntilVisible(
          slateChip,
          160,
          scrollable: outerScroll,
        );
        await tester.ensureVisible(slateChip);
        await tester.pumpAndSettle();
        await tester.tap(slateChip);
        await tester.pump();

        expect(settings.prefs.backgroundPreset, 'nordic_slate');
        expect(theme.backgroundPreset, 'nordic_slate');
        expect(
          ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
            tester.element(find.byType(ChristmasAndBackgroundOverlay).last),
            settings.prefs,
          ),
          isTrue,
        );

        // Toggle Liquid Glass OFF -> all sub-options (sliders, backdrop presets, physics modes) collapse immediately
        final lgSwitch = find.widgetWithText(SwitchListTile, 'Liquid Glass');
        await tester.scrollUntilVisible(
          lgSwitch,
          -160,
          scrollable: outerScroll,
        );
        await tester.ensureVisible(lgSwitch);
        await tester.pumpAndSettle();
        await tester.tap(lgSwitch);
        await tester.pump();

        expect(settings.prefs.liquidGlassEnabled, isFalse);
        expect(theme.liquidGlassEnabled, isFalse);
        expect(find.text('Áttetszőség'), findsNothing);
        expect(find.text('Elmosás erőssége'), findsNothing);
        expect(find.text('Háttér effektus / atmoszféra:'), findsNothing);
        expect(find.text('Liquid Glass Mód (Fizikai optika)'), findsNothing);
      },
    );

    testWidgets(
      'LiquidBubbleTabBar & LiquidSpringPillTrack translate strictly along X (translateY == 0), stretch horizontally during travel, and vertically rebound on arrival',
      (tester) async {
        var tabIdx = 0;
        var dockIdx = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatefulBuilder(
                        builder: (context, setState) => LiquidBubbleTabBar(
                          selectedIndex: tabIdx,
                          items: const [
                            LiquidBubbleTabItem(label: 'Első'),
                            LiquidBubbleTabItem(label: 'Második'),
                            LiquidBubbleTabItem(label: 'Harmadik'),
                            LiquidBubbleTabItem(label: 'Negyedik'),
                          ],
                          onSelected: (i) => setState(() => tabIdx = i),
                        ),
                      ),
                      const SizedBox(height: 24),
                      StatefulBuilder(
                        builder: (context, setState) => LiquidSpringPillTrack(
                          itemCount: 4,
                          selectedIndex: dockIdx,
                          height: 62,
                          pillWidth: 56,
                          pillHeight: 42,
                          onSelected: (i) => setState(() => dockIdx = i),
                          pillBuilder: (_, __) => const LiquidGlassPillSurface(
                            pressProgress: 0.0,
                            borderRadius: BorderRadius.all(Radius.circular(22)),
                          ),
                          itemBuilder: (_, idx, __) => Center(
                            child: Text('Dock$idx'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final barPillFinder = find.descendant(
          of: find.byType(LiquidBubbleTabBar),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        final barTransformFinder = find.descendant(
          of: barPillFinder,
          matching: find.byType(Transform),
        );
        final dockPillFinder = find.descendant(
          of: find.byType(LiquidSpringPillTrack),
          matching: find.byWidgetPredicate(
            (w) => w is Positioned && w.width != null && w.height != null,
          ),
        );
        final dockTransformFinder = find.descendant(
          of: dockPillFinder,
          matching: find.byType(Transform),
        );

        final restingBarTop = tester.widget<Positioned>(barPillFinder).top!;
        final restingDockTop = tester.widget<Positioned>(dockPillFinder).top!;

        // Tap rightmost tab on both bars
        await tester.tap(find.text('Negyedik'));
        await tester.tap(find.text('Dock3'));

        double maxBarTravelScaleX = 1.0;
        double minBarTravelScaleY = 1.0;
        double maxBarArrivalScaleY = 1.0;
        double maxDockTravelScaleX = 1.0;
        double minDockTravelScaleY = 1.0;
        double maxDockArrivalScaleY = 1.0;

        for (int frame = 0; frame < 30; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          final barPos = tester.widget<Positioned>(barPillFinder);
          final dockPos = tester.widget<Positioned>(dockPillFinder);
          // Strict zero vertical translation throughout entire tap animation
          expect(barPos.top!, closeTo(restingBarTop, 0.001));
          expect(dockPos.top!, closeTo(restingDockTop, 0.001));

          final barMatrix =
              tester.widget<Transform>(barTransformFinder).transform;
          final bsx = barMatrix.entry(0, 0);
          final bsy = barMatrix.entry(1, 1);
          if (bsx > maxBarTravelScaleX) maxBarTravelScaleX = bsx;
          if (bsy < minBarTravelScaleY) minBarTravelScaleY = bsy;
          if (bsy > maxBarArrivalScaleY) maxBarArrivalScaleY = bsy;

          final dockMatrix =
              tester.widget<Transform>(dockTransformFinder).transform;
          final dsx = dockMatrix.entry(0, 0);
          final dsy = dockMatrix.entry(1, 1);
          if (dsx > maxDockTravelScaleX) maxDockTravelScaleX = dsx;
          if (dsy < minDockTravelScaleY) minDockTravelScaleY = dsy;
          if (dsy > maxDockArrivalScaleY) maxDockArrivalScaleY = dsy;
        }

        // Balanced tactile travel stretch (~1.085 X, ~0.95 Y) & arrival vertical wobble (~1.055 Y)
        expect(maxBarTravelScaleX, greaterThan(1.055));
        expect(maxBarTravelScaleX, lessThanOrEqualTo(1.10));
        expect(minBarTravelScaleY, lessThan(0.975));
        expect(maxBarArrivalScaleY, greaterThan(1.035));
        expect(maxBarArrivalScaleY, lessThanOrEqualTo(1.07));

        expect(maxDockTravelScaleX, greaterThan(1.055));
        expect(maxDockTravelScaleX, lessThanOrEqualTo(1.10));
        expect(minDockTravelScaleY, lessThan(0.975));
        expect(maxDockArrivalScaleY, greaterThan(1.035));
        expect(maxDockArrivalScaleY, lessThanOrEqualTo(1.07));

        await tester.pumpAndSettle();
        final settledBar = tester.widget<Transform>(barTransformFinder).transform;
        final settledDock =
            tester.widget<Transform>(dockTransformFinder).transform;
        expect(settledBar.entry(0, 0), closeTo(1.0, 0.001));
        expect(settledBar.entry(1, 1), closeTo(1.0, 0.001));
        expect(settledDock.entry(0, 0), closeTo(1.0, 0.001));
        expect(settledDock.entry(1, 1), closeTo(1.0, 0.001));
        expect(
          tester.widget<Positioned>(barPillFinder).top!,
          closeTo(restingBarTop, 0.001),
        );
        expect(
          tester.widget<Positioned>(dockPillFinder).top!,
          closeTo(restingDockTop, 0.001),
        );
      },
    );
  });
}
