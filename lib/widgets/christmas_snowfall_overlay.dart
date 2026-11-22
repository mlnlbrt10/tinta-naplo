import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import 'animated_backdrops.dart';

export '../theme/oled_theme.dart' show BackgroundPresetInfo, AdaptiveContrastTokens;
export 'animated_backdrops.dart'
    show
        TopographicContourPainter,
        AnimatedBackdropLayer,
        BackdropMotionCoordinator;

/// Visual App Icon theme presets selectable in Personalization.
class AppIconPresetInfo {
  static const String defaultIconAsset = 'assets/images/tinta_icon.png';
  static const String classicIconAsset = 'assets/images/tinta_icon_classic.png';
  static const String fitymaIconAsset = 'assets/images/fityma-icon.png';

  static const AppIconPresetInfo fitymaPreset = AppIconPresetInfo(
    id: 'icon_fityma',
    label: 'Fityma Napló',
    subtitle: 'Titkos kiadás',
    assetPath: fitymaIconAsset,
    activityAlias: '.MainActivityFityma',
    icon: Icons.auto_awesome_rounded,
    primaryColor: Color(0xFFFFB74D),
    backgroundColor: Color(0xFF14101C),
  );

  final String id;
  final String label;
  final String subtitle;
  final String assetPath;
  final String activityAlias;
  final IconData icon;
  final Color primaryColor;
  final Color backgroundColor;

  const AppIconPresetInfo({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.assetPath,
    required this.activityAlias,
    required this.icon,
    required this.primaryColor,
    required this.backgroundColor,
  });

  static const List<AppIconPresetInfo> presets = [
    AppIconPresetInfo(
      id: 'icon_normal',
      label: 'Alapértelmezett',
      subtitle: 'Új Tinta ikon',
      assetPath: defaultIconAsset,
      activityAlias: '.MainActivityNormal',
      icon: Icons.school_rounded,
      primaryColor: Colors.white,
      backgroundColor: Colors.black,
    ),
    AppIconPresetInfo(
      id: 'classic',
      label: 'Klasszikus',
      subtitle: 'Korábbi ikon',
      assetPath: classicIconAsset,
      activityAlias: '.MainActivityClassic',
      icon: Icons.history_edu_rounded,
      primaryColor: Colors.white,
      backgroundColor: Colors.black,
    ),
    AppIconPresetInfo(
      id: 'icon_oled',
      label: 'OLED Fekete',
      subtitle: 'Sötét OLED',
      assetPath: defaultIconAsset,
      activityAlias: '.MainActivityOled',
      icon: Icons.dark_mode_rounded,
      primaryColor: Colors.white,
      backgroundColor: Color(0xFF050505),
    ),
    AppIconPresetInfo(
      id: 'icon_christmas',
      label: 'Karácsonyi',
      subtitle: 'Ünnepi Normál',
      assetPath: defaultIconAsset,
      activityAlias: '.MainActivityChristmas',
      icon: Icons.ac_unit_rounded,
      primaryColor: Color(0xFFFF5252),
      backgroundColor: Color(0xFF143322),
    ),
    AppIconPresetInfo(
      id: 'icon_christmas_oled',
      label: 'Karácsonyi OLED',
      subtitle: 'Ünnepi OLED',
      assetPath: defaultIconAsset,
      activityAlias: '.MainActivityChristmasOled',
      icon: Icons.severe_cold_rounded,
      primaryColor: Color(0xFFFFD54F),
      backgroundColor: Color(0xFF060D09),
    ),
  ];

  static AppIconPresetInfo fromId(String rawId) {
    switch (rawId) {
      case 'icon_fityma':
      case 'fityma':
      case '.MainActivityFityma':
      case 'MainActivityFityma':
        return fitymaPreset;
      case 'classic':
      case 'icon_classic':
      case '.MainActivityClassic':
      case 'MainActivityClassic':
        return presets[1];
      case 'icon_oled':
      case 'oled':
      case 'minimal_oled':
      case '.MainActivityOled':
        return presets[2];
      case 'icon_christmas':
      case 'christmas':
      case '.MainActivityChristmas':
        return presets[3];
      case 'icon_christmas_oled':
      case 'christmas_oled':
      case '.MainActivityChristmasOled':
        return presets[4];
      case 'icon_normal':
      case 'normal':
      case 'default':
      case '.MainActivityNormal':
      default:
        return presets[0];
    }
  }

  /// Resolves the active icon variant based on [prefs].
  /// - When an explicit icon preset (`classic`, `icon_normal`, `icon_oled`,
  ///   `icon_christmas`, `icon_christmas_oled`) has been selected, it is respected.
  /// - When `appIconPreset` is `'default'`, Christmas Mode automatically selects
  ///   `icon_christmas_oled` (when OLED theme is active) or `icon_christmas`
  ///   (when normal theme is active).
  static AppIconPresetInfo resolve(UserProfilePrefs prefs) {
    if (prefs.fitymaModeEnabled) {
      return fitymaPreset;
    }
    final raw = prefs.appIconPreset;
    if (raw == 'classic' ||
        raw == 'icon_classic' ||
        raw == '.MainActivityClassic') {
      return fromId('classic');
    }
    if (raw == 'icon_normal' ||
        raw == 'icon_oled' ||
        raw == 'icon_christmas' ||
        raw == 'icon_christmas_oled') {
      return fromId(raw);
    }
    if (prefs.christmasModeEnabled) {
      final isOled = prefs.themeStyle == AppThemeStyle.oledPureBlack;
      return fromId(isOled ? 'icon_christmas_oled' : 'icon_christmas');
    }
    return fromId(raw);
  }
}

/// Playful cartoon mascot vector badge rendered when "Fityma Napló mód" is active.
class FitymaBrandIcon extends StatelessWidget {
  final double size;

  const FitymaBrandIcon({
    super.key,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: Image.asset(
        AppIconPresetInfo.fitymaIconAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CustomPaint(
          size: Size.square(size),
          painter: _FitymaCartoonPainter(),
        ),
      ),
    );
  }
}

class _FitymaCartoonPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1F1630), Color(0xFF0D0F18)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Lighthearted rounded hooded mascot silhouette
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.25, h * 0.28, w * 0.50, h * 0.56),
      Radius.circular(w * 0.25),
    );
    final bodyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFD180), Color(0xFFFFAB40)],
      ).createShader(bodyRect.outerRect);
    canvas.drawRRect(bodyRect, bodyPaint);

    // Cheeky hood / collar fold
    final collarPath = Path()
      ..moveTo(w * 0.24, h * 0.52)
      ..quadraticBezierTo(w * 0.50, h * 0.42, w * 0.76, h * 0.52)
      ..quadraticBezierTo(w * 0.50, h * 0.62, w * 0.24, h * 0.52)
      ..close();
    canvas.drawPath(
      collarPath,
      Paint()..color = const Color(0xFFFFE0B2).withValues(alpha: 0.72),
    );

    // Googly eyes
    final eyeWhite = Paint()..color = Colors.white;
    final pupilPaint = Paint()..color = const Color(0xFF18181B);
    canvas.drawCircle(Offset(w * 0.41, h * 0.44), w * 0.085, eyeWhite);
    canvas.drawCircle(Offset(w * 0.60, h * 0.43), w * 0.095, eyeWhite);
    canvas.drawCircle(Offset(w * 0.425, h * 0.445), w * 0.042, pupilPaint);
    canvas.drawCircle(Offset(w * 0.59, h * 0.435), w * 0.048, pupilPaint);

    // Wink / grin arc
    final smilePaint = Paint()
      ..color = const Color(0xFF27272A)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (w * 0.042).clamp(1.6, 5.0);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.50, h * 0.55),
        width: w * 0.24,
        height: h * 0.14,
      ),
      0.15,
      pi - 0.3,
      false,
      smilePaint,
    );

    // Playful graduation cap tilted at top
    final capPaint = Paint()..color = const Color(0xFF38BDF8);
    final capPath = Path()
      ..moveTo(w * 0.52, h * 0.12)
      ..lineTo(w * 0.78, h * 0.21)
      ..lineTo(w * 0.50, h * 0.31)
      ..lineTo(w * 0.22, h * 0.22)
      ..close();
    canvas.drawPath(capPath, capPaint);
    canvas.drawCircle(
      Offset(w * 0.76, h * 0.29),
      w * 0.036,
      Paint()..color = const Color(0xFFFFD54F),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Renders the customized or festive Christmas App Brand Icon Badge.
class AppBrandIconBadge extends StatelessWidget {
  final UserProfilePrefs prefs;
  final double size;

  const AppBrandIconBadge({
    super.key,
    required this.prefs,
    this.size = 76,
  });

  @override
  Widget build(BuildContext context) {
    final preset = AppIconPresetInfo.resolve(prefs);
    final isChristmas = prefs.christmasModeEnabled ||
        preset.id == 'icon_christmas' ||
        preset.id == 'icon_christmas_oled';
    final isFityma = prefs.fitymaModeEnabled;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isFityma ? const Color(0xFF14101C) : preset.backgroundColor,
            borderRadius: BorderRadius.circular(size * 0.3),
            border: Border.all(
              color: isFityma
                  ? const Color(0xFFFFB74D).withValues(alpha: 0.85)
                  : preset.primaryColor.withValues(alpha: 0.75),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isFityma
                        ? const Color(0xFFFFB74D)
                        : preset.primaryColor)
                    .withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.28),
            child: isFityma
                ? FitymaBrandIcon(size: size)
                : Image.asset(
                    preset.assetPath,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Center(
                      child: Icon(
                        preset.icon,
                        size: size * 0.5,
                        color: preset.primaryColor,
                      ),
                    ),
                  ),
          ),
        ),
        if (isChristmas)
          Positioned(
            top: -6,
            right: -6,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.8),
              ),
              child: const Icon(
                Icons.ac_unit_rounded,
                size: 13,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps a screen body with the selected background accent preset and the
/// physics-based Christmas snowfall particle overlay + soft card-edge snow drift.
class ChristmasAndBackgroundOverlay extends StatefulWidget {
  final UserProfilePrefs prefs;
  final Widget child;

  const ChristmasAndBackgroundOverlay({
    super.key,
    required this.prefs,
    required this.child,
  });

  /// Returns true when the active theme and preferences render an ambient
  /// gradient or radial glow layer behind screen content.
  static bool hasAmbientBackdrop(
    BuildContext context,
    UserProfilePrefs prefs,
  ) {
    if (prefs.hasAnimatedBackdrop) return true;
    if (prefs.hasCustomBackdrop) return true;
    final bgPreset = BackgroundPresetInfo.resolve(prefs);
    if (bgPreset.id != 'pure_oled') return true;
    final isLight = Theme.of(context).brightness == Brightness.light;
    return (!isLight && bgPreset.id != 'pure_oled') || prefs.liquidGlassEnabled;
  }

  @override
  State<ChristmasAndBackgroundOverlay> createState() =>
      _ChristmasAndBackgroundOverlayState();
}

class _ChristmasAndBackgroundOverlayState
    extends State<ChristmasAndBackgroundOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final List<_SnowParticle> _particles;
  final Random _rng = Random(42);
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _particles = List.generate(58, (_) => _SnowParticle.random(_rng));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
  }

  void _syncTicker() {
    if (!mounted) return;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final appActive =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    final shouldAnimate = widget.prefs.christmasModeEnabled &&
        tickerEnabled &&
        routeIsCurrent &&
        appActive;
    if (shouldAnimate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldAnimate && _controller.isAnimating) {
      _controller.stop(canceled: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant ChristmasAndBackgroundOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Widget _buildBackdropLayers(
    BuildContext context,
    UserProfilePrefs activePrefs,
    BackgroundPresetInfo bgPreset,
    ThemeData theme,
  ) {
    final primary = theme.colorScheme.primary;
    final secondary = theme.colorScheme.secondary;
    final baseBg = theme.scaffoldBackgroundColor;
    final isLight = theme.brightness == Brightness.light;

    if (activePrefs.hasAnimatedBackdrop) {
      return AnimatedBackdropLayer(
        preset: activePrefs.animatedBackdropPreset,
      );
    }

    if (activePrefs.hasCustomBackdrop) {
      final path = activePrefs.customBackdropPath!.trim();
      final dim = activePrefs.customBackdropDim.clamp(0.0, 0.75);
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage(
                FileImage(File(path)),
                width: 1440,
              ),
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: bgPreset.gradientColors,
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (dim > 0.001)
              ColoredBox(color: Colors.black.withValues(alpha: dim)),
          ],
        ),
      );
    }

    final hasStudioGradient = bgPreset.id != 'pure_oled';
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: bgPreset.id == 'brushed_titanium'
                    ? const Alignment(-1.0, -0.8)
                    : Alignment.topLeft,
                end: bgPreset.id == 'brushed_titanium'
                    ? const Alignment(1.0, 0.8)
                    : Alignment.bottomRight,
                colors: hasStudioGradient
                    ? bgPreset.gradientColors
                    : [
                        Color.alphaBlend(
                          primary.withValues(alpha: isLight ? 0.05 : 0.22),
                          baseBg,
                        ),
                        Color.alphaBlend(
                          primary.withValues(alpha: isLight ? 0.015 : 0.07),
                          baseBg,
                        ),
                        Color.alphaBlend(
                          secondary.withValues(alpha: isLight ? 0.04 : 0.18),
                          baseBg,
                        ),
                      ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          if (bgPreset.isVectorContour)
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: TopographicContourPainter(
                    lineColor: Colors.white.withValues(alpha: 0.055),
                  ),
                ),
              ),
            ),
          if (bgPreset.id == 'brushed_titanium')
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      stops: const [0.0, 0.45, 0.55, 1.0],
                      colors: [
                        Colors.white.withValues(alpha: 0.045),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.025),
                        Colors.black.withValues(alpha: 0.16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (bgPreset.id == 'monolith_mesh') ...[
            Positioned(
              top: -60,
              right: -40,
              child: IgnorePointer(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF3A2A22).withValues(alpha: 0.38),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -40,
              left: -50,
              child: IgnorePointer(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF1B2B3A).withValues(alpha: 0.36),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else if (bgPreset.id == 'nordic_slate' ||
              bgPreset.id == 'warm_alabaster') ...[
            Positioned(
              top: -80,
              left: -30,
              child: IgnorePointer(
                child: Container(
                  width: 360,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        (bgPreset.id == 'warm_alabaster'
                                ? Colors.white
                                : const Color(0xFF334155))
                            .withValues(
                          alpha: bgPreset.id == 'warm_alabaster' ? 0.55 : 0.22,
                        ),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ] else if (activePrefs.liquidGlassEnabled && !hasStudioGradient) ...[
            Positioned(
              top: -40,
              right: -30,
              child: IgnorePointer(
                child: Container(
                  width: 310,
                  height: 310,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primary.withValues(alpha: isLight ? 0.10 : 0.34),
                        primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 220,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 320,
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        secondary.withValues(alpha: isLight ? 0.08 : 0.28),
                        secondary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 50,
              right: -40,
              child: IgnorePointer(
                child: Container(
                  width: 290,
                  height: 290,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        primary.withValues(alpha: isLight ? 0.08 : 0.28),
                        primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs = widget.prefs;
    final bgPreset = BackgroundPresetInfo.resolve(activePrefs);
    final theme = Theme.of(context);
    final showBackdrop = ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
      context,
      activePrefs,
    );
    final isGyroHorizon = activePrefs.animatedBackdropPreset ==
        AnimatedBackdropPreset.gyroLiquidHorizon;

    // Keep widget.child inside a stable Stack slot and Listener wrapper across
    // all backdrop/glass toggles so pushed routes never unmount mid-toggle.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackdrop)
          Positioned.fill(
            child: _buildBackdropLayers(context, activePrefs, bgPreset, theme),
          ),
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: isGyroHorizon
              ? (event) {
                  final box = context.findRenderObject() as RenderBox?;
                  final size = box?.size ?? MediaQuery.sizeOf(context);
                  BackdropMotionCoordinator.addTouchWave(
                    event.localPosition,
                    size,
                  );
                }
              : null,
          onPointerMove: isGyroHorizon
              ? (event) {
                  final box = context.findRenderObject() as RenderBox?;
                  final size = box?.size ?? MediaQuery.sizeOf(context);
                  BackdropMotionCoordinator.addTouchWave(
                    event.localPosition,
                    size,
                    isMove: true,
                    strength: 0.72,
                  );
                }
              : null,
          child: widget.child,
        ),
        if (activePrefs.christmasModeEnabled)
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    for (final p in _particles) {
                      p.step();
                    }
                    return CustomPaint(
                      painter: _SnowfallPhysicsPainter(particles: _particles),
                      size: Size.infinite,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Top padding for scrollable content inside an [AdaptiveBackgroundScaffold]
/// using `extendBodyBehindAppBar: true`.
double adaptiveAppBarTopPadding(BuildContext context, {double extra = 8.0}) {
  final topInset = MediaQuery.paddingOf(context).top;
  if (_AdaptiveScaffoldBodyScope.of(context)) {
    // Inside Scaffold(extendBodyBehindAppBar: true), MediaQuery.padding.top
    // already includes statusBarHeight + kToolbarHeight.
    return topInset + extra;
  }
  return topInset + kToolbarHeight + extra;
}

class _AdaptiveScaffoldBodyScope extends InheritedWidget {
  const _AdaptiveScaffoldBodyScope({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AdaptiveScaffoldBodyScope>() !=
      null;

  @override
  bool updateShouldNotify(covariant _AdaptiveScaffoldBodyScope oldWidget) =>
      false;
}

/// Transparent [AppBar] with contrast-safe foreground color and zero scroll
/// tinting so underlying ambient backgrounds extend seamlessly behind it.
PreferredSizeWidget buildAdaptiveTransparentAppBar(
  BuildContext context, {
  required String title,
  List<Widget>? actions,
}) {
  return AppBar(
    title: Text(title),
    actions: actions,
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    foregroundColor: Theme.of(context).colorScheme.onSurface,
    systemOverlayStyle: OledTheme.systemOverlayStyleForBrightness(
      Theme.of(context).brightness,
    ),
  );
}

/// Reusable `IgnorePointer` top & bottom scroll-edge fade overlay.
///
/// Sits above the scrollable list content and cleanly below AppBar titles /
/// floating bottom navigation bars:
/// - **Top fade:** Masks [topHeaderHeight] (e.g. status bar + transparent
///   AppBar) cleanly and feathers out over [topFeatherHeight], ramping in
///   smoothly from `0.0` once scrolled when [scrollDrivenTopFeather] is true
///   so resting cards at `scrollOffset == 0` remain crisp.
/// - **Bottom fade:** Feathers smoothly into the scaffold background over
///   [bottomFadeHeight] inside `IgnorePointer` (using `ShaderMask` `dstIn` when
///   an ambient shader/wallpaper is active so the background is never tinted).
class VerticalScrollEdgeFades extends StatefulWidget {
  final Widget child;
  final UserProfilePrefs? prefs;
  final double topHeaderHeight;
  final double topFeatherHeight;
  final double bottomFadeHeight;
  final bool scrollDrivenTopFeather;

  const VerticalScrollEdgeFades({
    super.key,
    required this.child,
    this.prefs,
    this.topHeaderHeight = 0.0,
    this.topFeatherHeight = 26.0,
    this.bottomFadeHeight = 36.0,
    this.scrollDrivenTopFeather = true,
  });

  @override
  State<VerticalScrollEdgeFades> createState() =>
      _VerticalScrollEdgeFadesState();
}

class _VerticalScrollEdgeFadesState extends State<VerticalScrollEdgeFades> {
  final ValueNotifier<double> _scrollOffset = ValueNotifier<double>(0.0);

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAmbient = widget.prefs != null &&
        ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
          context,
          widget.prefs!,
        );
    final fadeColor = Theme.of(context).scaffoldBackgroundColor;
    final totalTopHeight = widget.topHeaderHeight + widget.topFeatherHeight;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) {
          final next = notification.metrics.pixels.clamp(0.0, 120.0);
          if ((_scrollOffset.value - next).abs() > 0.5) {
            _scrollOffset.value = next;
          }
        }
        return false;
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _scrollOffset,
        child: widget.child,
        builder: (context, offset, child) {
          final topFactor = widget.scrollDrivenTopFeather
              ? (offset / 18.0).clamp(0.0, 1.0)
              : 1.0;

          if (hasAmbient) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                if (bounds.height <= 0) {
                  return const LinearGradient(
                    colors: [Colors.black, Colors.black],
                  ).createShader(bounds);
                }
                final headerStop = (widget.topHeaderHeight / bounds.height)
                    .clamp(0.0, 0.35);
                final topFeatherStop =
                    (totalTopHeight / bounds.height).clamp(headerStop, 0.45);
                final bottomStartStop =
                    ((bounds.height - widget.bottomFadeHeight) / bounds.height)
                        .clamp(topFeatherStop, 1.0);

                final stops = <double>[
                  0.0,
                  if (widget.topHeaderHeight > 0) headerStop,
                  topFeatherStop,
                  bottomStartStop,
                  1.0,
                ];
                final topEdgeAlpha = 1.0 - topFactor;
                final bottomEdgeColor = widget.bottomFadeHeight > 0
                    ? Colors.transparent
                    : Colors.black;
                final topColor = Color.lerp(
                  Colors.black,
                  Colors.transparent,
                  topFactor,
                )!;
                final colors = <Color>[
                  if (widget.topHeaderHeight > 0) ...[
                    topEdgeAlpha < 0.99 ? topColor : Colors.black,
                    topEdgeAlpha < 0.99 ? topColor : Colors.black,
                  ] else
                    topColor,
                  Colors.black,
                  Colors.black,
                  bottomEdgeColor,
                ];
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: stops,
                  colors: colors,
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: child,
            );
          }

          return Stack(
            fit: StackFit.passthrough,
            children: [
              child!,
              if (totalTopHeight > 0 && topFactor > 0.01)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: totalTopHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: widget.topHeaderHeight > 0
                              ? [
                                  0.0,
                                  (widget.topHeaderHeight / totalTopHeight)
                                      .clamp(0.0, 0.92),
                                  1.0,
                                ]
                              : const [0.0, 1.0],
                          colors: widget.topHeaderHeight > 0
                              ? [
                                  fadeColor.withValues(alpha: topFactor),
                                  fadeColor.withValues(alpha: topFactor),
                                  fadeColor.withValues(alpha: 0.0),
                                ]
                              : [
                                  fadeColor.withValues(alpha: topFactor),
                                  fadeColor.withValues(alpha: 0.0),
                                ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.bottomFadeHeight > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: widget.bottomFadeHeight,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.0, 0.65, 1.0],
                          colors: [
                            fadeColor.withValues(alpha: 0.0),
                            fadeColor.withValues(alpha: 0.72),
                            fadeColor,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// [Scaffold] that extends its background and effects behind a transparent
/// [AppBar], seamlessly matching OLED pure black, Standard Dark, Light theme,
/// and active background gradients/effects.
class AdaptiveBackgroundScaffold extends StatelessWidget {
  final UserProfilePrefs? prefs;
  final PreferredSizeWidget appBar;
  final Widget body;

  const AdaptiveBackgroundScaffold({
    super.key,
    required this.prefs,
    required this.appBar,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrefs = prefs;
    final hasAmbient = effectivePrefs != null &&
        ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
          context,
          effectivePrefs,
        );
    final topHeaderH =
        MediaQuery.paddingOf(context).top + appBar.preferredSize.height;
    final scaffold = Scaffold(
      backgroundColor: hasAmbient ? Colors.transparent : null,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: _AdaptiveScaffoldBodyScope(
        child: VerticalScrollEdgeFades(
          prefs: effectivePrefs,
          topHeaderHeight: topHeaderH,
          topFeatherHeight: 28.0,
          bottomFadeHeight: 36.0,
          scrollDrivenTopFeather: true,
          child: body,
        ),
      ),
    );
    if (effectivePrefs == null) {
      return scaffold;
    }
    return ChristmasAndBackgroundOverlay(
      prefs: effectivePrefs,
      child: scaffold,
    );
  }
}

/// Optional soft snow cap decoration for the top edge of cards when Christmas Mode is active.
class ChristmasSnowCap extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const ChristmasSnowCap({
    super.key,
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: 0,
          left: 18,
          right: 18,
          height: 8,
          child: RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CardSnowDriftPainter(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SnowParticle {
  double x; // 0..1 normalized
  double y; // 0..1 normalized
  final double radius;
  final double speedY;
  final double driftAmplitude;
  final double driftFrequency;
  double phase;
  final double opacity;

  _SnowParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speedY,
    required this.driftAmplitude,
    required this.driftFrequency,
    required this.phase,
    required this.opacity,
  });

  factory _SnowParticle.random(Random rng) {
    return _SnowParticle(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      radius: 1.4 + rng.nextDouble() * 2.8,
      speedY: 0.0012 + rng.nextDouble() * 0.0022,
      driftAmplitude: 0.0005 + rng.nextDouble() * 0.0014,
      driftFrequency: 0.02 + rng.nextDouble() * 0.04,
      phase: rng.nextDouble() * pi * 2,
      opacity: 0.32 + rng.nextDouble() * 0.52,
    );
  }

  void step() {
    y += speedY;
    phase += driftFrequency;
    x += sin(phase) * driftAmplitude;
    if (y > 1.04) {
      y = -0.03;
    }
    if (x < -0.02) x = 1.02;
    if (x > 1.02) x = -0.02;
  }
}

class _SnowfallPhysicsPainter extends CustomPainter {
  final List<_SnowParticle> particles;

  const _SnowfallPhysicsPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw falling snowflakes
    for (final p in particles) {
      paint.color = Colors.white.withValues(alpha: p.opacity);
      canvas.drawCircle(
        Offset(p.x * size.width, p.y * size.height),
        p.radius,
        paint,
      );
    }

    // Soft snow accumulation ridge along the top-most card/header horizon
    final driftPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.20)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(size.width * 0.25, 6, size.width * 0.5, 2)
      ..quadraticBezierTo(size.width * 0.75, 7, size.width, 0)
      ..close();
    canvas.drawPath(path, driftPaint);
  }

  @override
  bool shouldRepaint(covariant _SnowfallPhysicsPainter oldDelegate) => true;
}

class _CardSnowDriftPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 2)
      ..quadraticBezierTo(size.width * 0.18, 7, size.width * 0.36, 3.5)
      ..quadraticBezierTo(size.width * 0.55, 8, size.width * 0.76, 3)
      ..quadraticBezierTo(size.width * 0.90, 6.5, size.width, 1.5)
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
