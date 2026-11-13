import 'dart:math';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';

/// Visual App Icon theme presets selectable in Personalization.
class AppIconPresetInfo {
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
      label: 'Normál',
      subtitle: 'Alapértelmezett',
      assetPath: 'assets/images/tinta_icon.png',
      activityAlias: '.MainActivityNormal',
      icon: Icons.school_rounded,
      primaryColor: Colors.white,
      backgroundColor: Colors.black,
    ),
    AppIconPresetInfo(
      id: 'icon_oled',
      label: 'OLED Fekete',
      subtitle: 'Sötét OLED',
      assetPath: 'assets/icons/icon_oled.png',
      activityAlias: '.MainActivityOled',
      icon: Icons.dark_mode_rounded,
      primaryColor: Colors.white,
      backgroundColor: Color(0xFF050505),
    ),
    AppIconPresetInfo(
      id: 'icon_christmas',
      label: 'Karácsonyi',
      subtitle: 'Ünnepi Normál',
      assetPath: 'assets/icons/icon_christmas.png',
      activityAlias: '.MainActivityChristmas',
      icon: Icons.ac_unit_rounded,
      primaryColor: Color(0xFFFF5252),
      backgroundColor: Color(0xFF143322),
    ),
    AppIconPresetInfo(
      id: 'icon_christmas_oled',
      label: 'Karácsonyi OLED',
      subtitle: 'Ünnepi OLED',
      assetPath: 'assets/icons/icon_christmas_oled.png',
      activityAlias: '.MainActivityChristmasOled',
      icon: Icons.severe_cold_rounded,
      primaryColor: Color(0xFFFFD54F),
      backgroundColor: Color(0xFF060D09),
    ),
  ];

  static AppIconPresetInfo fromId(String rawId) {
    switch (rawId) {
      case 'icon_oled':
      case 'oled':
      case 'minimal_oled':
      case '.MainActivityOled':
        return presets[1];
      case 'icon_christmas':
      case 'christmas':
      case '.MainActivityChristmas':
        return presets[2];
      case 'icon_christmas_oled':
      case 'christmas_oled':
      case '.MainActivityChristmasOled':
        return presets[3];
      case 'icon_normal':
      case 'normal':
      case 'default':
      case '.MainActivityNormal':
      default:
        return presets[0];
    }
  }

  /// Resolves the active icon variant based on [prefs].
  /// - When an explicit icon preset (`icon_normal`, `icon_oled`, `icon_christmas`,
  ///   `icon_christmas_oled`) has been selected, it is respected.
  /// - When `appIconPreset` is `'default'`, Christmas Mode automatically selects
  ///   `icon_christmas_oled` (when OLED theme is active) or `icon_christmas`
  ///   (when normal theme is active).
  static AppIconPresetInfo resolve(UserProfilePrefs prefs) {
    final raw = prefs.appIconPreset;
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

/// Visual Background Accent presets selectable in Personalization.
class BackgroundPresetInfo {
  final String id;
  final String label;
  final IconData icon;
  final List<Color> gradientColors;

  const BackgroundPresetInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.gradientColors,
  });

  static const List<BackgroundPresetInfo> presets = [
    BackgroundPresetInfo(
      id: 'pure_oled',
      label: 'OLED Fekete (Pure Black)',
      icon: Icons.contrast_rounded,
      gradientColors: [Colors.black, Colors.black],
    ),
    BackgroundPresetInfo(
      id: 'brand_navy',
      label: 'Mély Ciánkék (Brand Cyan/Navy #0B1E28)',
      icon: Icons.water_drop_rounded,
      gradientColors: [Color(0xFF0B1E28), Color(0xFF0B1E28)],
    ),
    BackgroundPresetInfo(
      id: 'midnight_aurora',
      label: 'Éjszakai Aurora',
      icon: Icons.auto_awesome_rounded,
      gradientColors: [Color(0xFF071324), Color(0xFF000000), Color(0xFF091A18)],
    ),
    BackgroundPresetInfo(
      id: 'cyber_violet',
      label: 'Cyber Ibolya',
      icon: Icons.blur_on_rounded,
      gradientColors: [Color(0xFF190A26), Color(0xFF000000), Color(0xFF0B1528)],
    ),
    BackgroundPresetInfo(
      id: 'sunset_ember',
      label: 'Alkonyati Parázs',
      icon: Icons.wb_twilight_rounded,
      gradientColors: [Color(0xFF240E0B), Color(0xFF000000), Color(0xFF180B1E)],
    ),
    BackgroundPresetInfo(
      id: 'winter_frost',
      label: 'Téli Fagy (Ünnepi)',
      icon: Icons.ac_unit_rounded,
      gradientColors: [Color(0xFF0A1E29), Color(0xFF03080C), Color(0xFF0E2419)],
    ),
  ];

  static BackgroundPresetInfo resolve(UserProfilePrefs prefs) {
    if (prefs.christmasModeEnabled && prefs.backgroundPreset == 'pure_oled') {
      return presets.firstWhere((p) => p.id == 'winter_frost');
    }
    return presets.firstWhere(
      (p) => p.id == prefs.backgroundPreset,
      orElse: () => presets.first,
    );
  }
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

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: preset.backgroundColor,
            borderRadius: BorderRadius.circular(size * 0.3),
            border: Border.all(
              color: preset.primaryColor.withValues(alpha: 0.75),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: preset.primaryColor.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.28),
            child: Image.asset(
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
    final bgPreset = BackgroundPresetInfo.resolve(prefs);
    final isLight = Theme.of(context).brightness == Brightness.light;
    return (!isLight && bgPreset.id != 'pure_oled') || prefs.cardBlurEnabled;
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

  @override
  Widget build(BuildContext context) {
    final bgPreset = BackgroundPresetInfo.resolve(widget.prefs);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final hasGradient = !isLight && bgPreset.id != 'pure_oled';

    Widget content = widget.child;
    if (ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
      context,
      widget.prefs,
    )) {
      final primary = theme.colorScheme.primary;
      final secondary = theme.colorScheme.secondary;
      final baseBg = theme.scaffoldBackgroundColor;
      content = Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: hasGradient
                          ? bgPreset.gradientColors
                          : [
                              Color.alphaBlend(
                                primary.withValues(alpha: isLight ? 0.14 : 0.22),
                                baseBg,
                              ),
                              Color.alphaBlend(
                                primary.withValues(alpha: isLight ? 0.04 : 0.07),
                                baseBg,
                              ),
                              Color.alphaBlend(
                                secondary.withValues(alpha: isLight ? 0.12 : 0.18),
                                baseBg,
                              ),
                            ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
                if (widget.prefs.cardBlurEnabled) ...[
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
                              primary.withValues(alpha: isLight ? 0.26 : 0.34),
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
                              secondary.withValues(alpha: isLight ? 0.22 : 0.28),
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
                              primary.withValues(alpha: isLight ? 0.22 : 0.28),
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
          ),
          content,
        ],
      );
    }

    if (!widget.prefs.christmasModeEnabled) {
      return content;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        RepaintBoundary(
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
      ],
    );
  }
}

/// Top padding for scrollable content inside an [AdaptiveBackgroundScaffold]
/// using `extendBodyBehindAppBar: true`.
double adaptiveAppBarTopPadding(BuildContext context, {double extra = 12.0}) {
  return MediaQuery.paddingOf(context).top + kToolbarHeight + extra;
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
  );
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
    final scaffold = Scaffold(
      backgroundColor: hasAmbient ? Colors.transparent : null,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      body: body,
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
