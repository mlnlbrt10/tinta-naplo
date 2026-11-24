import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import 'animated_backdrops.dart';

/// Physical-optics tuning derived from [LiquidGlassMode] and [UserProfilePrefs].
@immutable
class RealLiquidGlassOptics {
  final double bezelWidth;
  final double refractionStrength;
  final double chromaticAberration;
  final double blurRadius;
  final double lightAngle;

  const RealLiquidGlassOptics({
    required this.bezelWidth,
    required this.refractionStrength,
    required this.chromaticAberration,
    required this.blurRadius,
    this.lightAngle = -2.35,
  });

  factory RealLiquidGlassOptics.resolve({
    required LiquidGlassMode mode,
    double blurSigma = 4.0,
    bool compact = false,
  }) {
    final sigma = blurSigma.clamp(2.0, 14.0);
    final baseBlur = (sigma * (compact ? 1.15 : 1.55)).clamp(3.0, 18.0);
    switch (mode) {
      case LiquidGlassMode.classicFrost:
        return RealLiquidGlassOptics(
          bezelWidth: compact ? 14.0 : 18.0,
          refractionStrength: compact ? 11.0 : 14.5,
          chromaticAberration: 0.16,
          blurRadius: baseBlur,
        );
      case LiquidGlassMode.hydroMercury:
        return RealLiquidGlassOptics(
          bezelWidth: compact ? 15.0 : 20.0,
          refractionStrength: compact ? 14.0 : 18.5,
          chromaticAberration: 0.11,
          blurRadius: (baseBlur * 0.78).clamp(2.5, 15.0),
        );
      case LiquidGlassMode.opticalPrism:
        return RealLiquidGlassOptics(
          bezelWidth: compact ? 16.0 : 21.0,
          refractionStrength: compact ? 13.5 : 17.5,
          chromaticAberration: 0.34,
          blurRadius: (baseBlur * 0.65).clamp(2.0, 12.0),
        );
      case LiquidGlassMode.smokedObsidian:
        return RealLiquidGlassOptics(
          bezelWidth: compact ? 14.0 : 16.0,
          refractionStrength: compact ? 8.5 : 10.5,
          chromaticAberration: 0.08,
          blurRadius: (baseBlur * 1.10).clamp(3.5, 18.0),
        );
      case LiquidGlassMode.rippleGel:
        return RealLiquidGlassOptics(
          bezelWidth: compact ? 15.0 : 19.5,
          refractionStrength: compact ? 13.0 : 16.5,
          chromaticAberration: 0.21,
          blurRadius: (baseBlur * 0.85).clamp(2.5, 16.0),
        );
    }
  }
}

/// Global cache and startup pre-warmer for `shaders/liquid_glass.frag`.
class RealLiquidGlassShaderCache {
  RealLiquidGlassShaderCache._();

  static const String shaderAssetPath = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loadFuture;
  static bool _failed = false;

  /// Optional test hook to simulate shader support or failure in unit tests.
  @visibleForTesting
  static bool? debugOverrideShaderSupport;

  static ui.FragmentProgram? get cachedProgram => _program;
  static bool get hasFailed => _failed;

  static bool get isRuntimeShaderAvailable {
    if (debugOverrideShaderSupport != null) {
      return debugOverrideShaderSupport! && !_failed && _program != null;
    }
    return ui.ImageFilter.isShaderFilterSupported &&
        !_failed &&
        _program != null;
  }

  /// Marks runtime shader filter creation as unsupported on the current device
  /// so subsequent frames skip shader compilation and use the crisp fallback.
  static void markRuntimeUnsupported() {
    _failed = true;
  }

  /// Pre-warms and caches the compiled [ui.FragmentProgram] without throwing.
  static Future<ui.FragmentProgram?> prewarm() {
    if (_program != null) {
      return Future<ui.FragmentProgram?>.value(_program);
    }
    if (_failed) {
      return Future<ui.FragmentProgram?>.value(null);
    }
    return _loadFuture ??= _loadInternal();
  }

  static Future<ui.FragmentProgram?> _loadInternal() async {
    try {
      final program = await ui.FragmentProgram.fromAsset(shaderAssetPath);
      _program = program;
      return program;
    } catch (_) {
      _failed = true;
      return null;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _program = null;
    _loadFuture = null;
    _failed = false;
    debugOverrideShaderSupport = null;
  }
}

/// Reusable iOS 26-style optical Liquid Glass surface backed by the custom
/// Impeller GLSL shader (`shaders/liquid_glass.frag`) with automatic graceful
/// fallback to enhanced [BackdropFilter] + [RealLiquidGlassOpticalRimPainter]
/// on older GPUs, Skia backends, or headless test environments.
class RealLiquidGlassSurface extends StatefulWidget {
  final Widget child;
  final UserProfilePrefs? prefs;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tintColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final bool isDockStyle;
  final bool isHeaderStyle;
  final bool compactOptics;
  final bool highContrast;
  final double? opacityScale;
  final double? bezelWidthOverride;
  final double? refractionStrengthOverride;
  final double? chromaticAberrationOverride;
  final double? blurRadiusOverride;
  final LiquidGlassMode? modeOverride;
  final Animation<double>? contentOpacityAnimation;
  final bool interactiveHighlight;

  const RealLiquidGlassSurface({
    super.key,
    required this.child,
    this.prefs,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.tintColor,
    this.border,
    this.boxShadow,
    this.isDockStyle = false,
    this.isHeaderStyle = false,
    this.compactOptics = false,
    this.highContrast = false,
    this.opacityScale,
    this.bezelWidthOverride,
    this.refractionStrengthOverride,
    this.chromaticAberrationOverride,
    this.blurRadiusOverride,
    this.modeOverride,
    this.contentOpacityAnimation,
    this.interactiveHighlight = true,
  });

  /// Pre-warms the optical shader program once at app startup.
  static Future<ui.FragmentProgram?> prewarmShader() =>
      RealLiquidGlassShaderCache.prewarm();

  /// Returns true when OS reduced-motion / animation-disable accessibility or
  /// battery-saver states are active.
  static bool isReducedMotionEnabled(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media != null && media.disableAnimations) return true;
    if (WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      return true;
    }
    return !TickerMode.valuesOf(context).enabled;
  }

  @override
  State<RealLiquidGlassSurface> createState() => _RealLiquidGlassSurfaceState();
}

class _RealLiquidGlassSurfaceState extends State<RealLiquidGlassSurface>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<_OpticalMotionState> _motion =
      ValueNotifier<_OpticalMotionState>(_OpticalMotionState.zero);

  AnimationController? _settleController;
  double _settleStartAngle = 0.0;
  ScrollPosition? _observedScroll;
  double _lastScrollPixels = 0.0;
  bool _reducedMotion = false;
  bool _localShaderDisabled = false;

  ui.FragmentShader? _shader;
  ui.ImageFilter? _cachedShaderFilter;
  _ShaderUniformKey? _cachedUniformKey;

  @override
  void initState() {
    super.initState();
    BackdropMotionCoordinator.lightBiasNotifier.addListener(_onAmbientLightChanged);
    _ensureShaderWarmup();
  }

  void _ensureShaderWarmup() {
    if (RealLiquidGlassShaderCache.cachedProgram == null &&
        !RealLiquidGlassShaderCache.hasFailed &&
        ui.ImageFilter.isShaderFilterSupported) {
      unawaited(
        RealLiquidGlassShaderCache.prewarm().then((program) {
          if (mounted && program != null) {
            setState(() {});
          }
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduced = RealLiquidGlassSurface.isReducedMotionEnabled(context);
    if (_reducedMotion != nextReduced) {
      _reducedMotion = nextReduced;
      if (_reducedMotion) {
        _settleController?.stop();
        _motion.value = _OpticalMotionState.zero;
      }
    }
    _syncScrollObserver();
  }

  @override
  void didUpdateWidget(covariant RealLiquidGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interactiveHighlight != widget.interactiveHighlight) {
      _syncScrollObserver();
      if (!widget.interactiveHighlight) {
        _settleController?.stop();
        _motion.value = _OpticalMotionState.zero;
      }
    }
  }

  void _syncScrollObserver() {
    final shouldListen = widget.interactiveHighlight && !_reducedMotion;
    final nextPos = shouldListen ? Scrollable.maybeOf(context)?.position : null;
    if (_observedScroll == nextPos) return;
    _observedScroll?.removeListener(_onScrollChanged);
    _observedScroll = nextPos;
    if (nextPos != null) {
      _lastScrollPixels = nextPos.hasPixels ? nextPos.pixels : 0.0;
      nextPos.addListener(_onScrollChanged);
    }
  }

  void _onScrollChanged() {
    final pos = _observedScroll;
    if (pos == null || !pos.hasPixels || _reducedMotion) return;
    final pixels = pos.pixels;
    if ((pixels - _lastScrollPixels).abs() < 1.5) return;
    _lastScrollPixels = pixels;
    final current = _motion.value;
    _motion.value = current.copyWith(scrollOffset: pixels);
  }

  void _onAmbientLightChanged() {
    if (!mounted || _reducedMotion || !widget.interactiveHighlight) return;
    final bias = BackdropMotionCoordinator.lightBiasNotifier.value;
    final current = _motion.value;
    if ((current.ambientBiasDx - bias.dx).abs() < 0.01 &&
        (current.ambientBiasDy - bias.dy).abs() < 0.01) {
      return;
    }
    _motion.value = current.copyWith(
      ambientBiasDx: bias.dx,
      ambientBiasDy: bias.dy,
    );
  }

  void _handlePointerMove(PointerEvent event) {
    if (_reducedMotion || !widget.interactiveHighlight) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return;
    final local = box.globalToLocal(event.position);
    final center = box.size.center(Offset.zero);
    final dx = ((local.dx - center.dx) / (box.size.width * 0.5)).clamp(-1.0, 1.0);
    final dy = ((local.dy - center.dy) / (box.size.height * 0.5)).clamp(-1.0, 1.0);
    final angleDelta = (dx * 0.42 + dy * 0.18).clamp(-0.55, 0.55);
    _settleController?.stop();
    final current = _motion.value;
    if ((current.pointerAngleDelta - angleDelta).abs() > 0.01) {
      _motion.value = current.copyWith(pointerAngleDelta: angleDelta);
    }
  }

  void _handlePointerRelease(PointerEvent _) {
    final startAngle = _motion.value.pointerAngleDelta;
    if (_reducedMotion || startAngle.abs() < 0.01) {
      if (startAngle != 0.0) {
        _motion.value = _motion.value.copyWith(pointerAngleDelta: 0.0);
      }
      return;
    }
    _settleStartAngle = startAngle;
    _settleController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_settleController!.value);
        _motion.value = _motion.value.copyWith(
          pointerAngleDelta: _settleStartAngle * (1.0 - t),
        );
      });
    _settleController!.forward(from: 0.0);
  }

  ui.ImageFilter? _resolveShaderFilter({
    required Size size,
    required double dpr,
    required double cornerRadiusPx,
    required double bezelWidthPx,
    required double refractionStrengthPx,
    required double chromaticAberration,
    required double blurRadiusPx,
    required double lightAngle,
    required double scrollOffset,
    required Color tintColor,
    required bool isDark,
  }) {
    if (_localShaderDisabled ||
        !RealLiquidGlassShaderCache.isRuntimeShaderAvailable) {
      return null;
    }
    final program = RealLiquidGlassShaderCache.cachedProgram;
    if (program == null) return null;

    final nextKey = _ShaderUniformKey(
      widthPx: (size.width * dpr).roundToDouble(),
      heightPx: (size.height * dpr).roundToDouble(),
      cornerRadiusPx: cornerRadiusPx,
      bezelWidthPx: bezelWidthPx,
      refractionStrengthPx: refractionStrengthPx,
      chromaticAberration: chromaticAberration,
      blurRadiusPx: blurRadiusPx,
      lightAngle: lightAngle,
      scrollOffset: scrollOffset,
      tintArgb: tintColor.toARGB32(),
      isDark: isDark,
      dpr: dpr,
    );
    if (_cachedShaderFilter != null && _cachedUniformKey == nextKey) {
      return _cachedShaderFilter;
    }

    try {
      final shader = program.fragmentShader();
      shader.setFloat(0, math.max(2.0, size.width * dpr));
      shader.setFloat(1, math.max(2.0, size.height * dpr));
      shader.setFloat(2, cornerRadiusPx);
      shader.setFloat(3, bezelWidthPx);
      shader.setFloat(4, refractionStrengthPx);
      shader.setFloat(5, chromaticAberration);
      shader.setFloat(6, blurRadiusPx);
      shader.setFloat(7, lightAngle);
      shader.setFloat(8, scrollOffset);
      shader.setFloat(9, tintColor.r);
      shader.setFloat(10, tintColor.g);
      shader.setFloat(11, tintColor.b);
      shader.setFloat(12, tintColor.a);
      shader.setFloat(13, isDark ? 1.0 : 0.0);
      shader.setFloat(14, dpr);

      final filter = ui.ImageFilter.shader(shader);
      _shader?.dispose();
      _shader = shader;
      _cachedShaderFilter = filter;
      _cachedUniformKey = nextKey;
      return filter;
    } catch (_) {
      _localShaderDisabled = true;
      RealLiquidGlassShaderCache.markRuntimeUnsupported();
      _shader?.dispose();
      _shader = null;
      _cachedShaderFilter = null;
      _cachedUniformKey = null;
      return null;
    }
  }

  @override
  void dispose() {
    BackdropMotionCoordinator.lightBiasNotifier
        .removeListener(_onAmbientLightChanged);
    _observedScroll?.removeListener(_onScrollChanged);
    _observedScroll = null;
    _settleController?.dispose();
    _motion.dispose();
    _shader?.dispose();
    _shader = null;
    _cachedShaderFilter = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectivePrefs =
        widget.prefs ?? AppProvidersScope.maybeOf(context)?.settings.prefs;
    final mode = widget.modeOverride ??
        effectivePrefs?.liquidGlassMode ??
        UserProfilePrefs.activeLiquidGlassMode;
    final cardOpacity = widget.opacityScale ??
        effectivePrefs?.cardOpacity ??
        0.9;
    final cardBlurSigma =
        effectivePrefs?.cardBlurSigma ?? UserProfilePrefs.activeSoftBlurSigma;

    final optics = RealLiquidGlassOptics.resolve(
      mode: mode,
      blurSigma: cardBlurSigma,
      compact: widget.compactOptics,
    );

    final baseTint = OledTheme.realLiquidGlassTintForTheme(
      theme,
      overrideTint: widget.tintColor,
      opacityScale: cardOpacity,
      highContrast: widget.highContrast,
    );
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;

    final rawContent = Material(
      type: MaterialType.transparency,
      child: widget.child,
    );
    final contentChild = widget.contentOpacityAnimation != null
        ? FadeTransition(
            opacity: widget.contentOpacityAnimation!,
            child: rawContent,
          )
        : rawContent;

    Widget buildSurface({
      required double factor,
      required _OpticalMotionState motionState,
      required Size layoutSize,
      required Widget innerContent,
    }) {
      final t = factor.clamp(0.0, 1.0);
      final animatedTint = t >= 0.999
          ? baseTint
          : baseTint.withValues(alpha: baseTint.a * t);
      final bezelWidth =
          widget.bezelWidthOverride ?? optics.bezelWidth;
      final refractionStrength =
          (widget.refractionStrengthOverride ?? optics.refractionStrength) * t;
      final chromatic =
          widget.chromaticAberrationOverride ?? optics.chromaticAberration;
      final blurRadius =
          (widget.blurRadiusOverride ?? optics.blurRadius) * t;

      final resolvedCornerRadius = widget.isHeaderStyle
          ? 1.0
          : widget.borderRadius.topLeft.x;
      final effectiveLightAngle = optics.lightAngle +
          (_reducedMotion
              ? 0.0
              : (motionState.pointerAngleDelta +
                  motionState.ambientBiasDx * 0.35));
      final effectiveScroll = _reducedMotion ? 0.0 : motionState.scrollOffset;

      final shaderFilter = _resolveShaderFilter(
        size: layoutSize,
        dpr: dpr,
        cornerRadiusPx: (resolvedCornerRadius * dpr).clamp(1.0, 200.0),
        bezelWidthPx: (bezelWidth * dpr).clamp(4.0, 120.0),
        refractionStrengthPx: refractionStrength * dpr,
        chromaticAberration: chromatic,
        blurRadiusPx: blurRadius * dpr,
        lightAngle: effectiveLightAngle,
        scrollOffset: effectiveScroll,
        tintColor: animatedTint,
        isDark: isDark,
      );

      final Widget glassLayer;
      if (shaderFilter != null) {
        final filtered = BackdropFilter(
          filter: shaderFilter,
          child: widget.border != null
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: widget.borderRadius,
                    border: widget.border,
                  ),
                  child: widget.isDockStyle || widget.isHeaderStyle
                      ? const SizedBox.expand()
                      : Padding(padding: widget.padding, child: innerContent),
                )
              : (widget.isDockStyle || widget.isHeaderStyle
                  ? const SizedBox.expand()
                  : Padding(padding: widget.padding, child: innerContent)),
        );
        glassLayer = widget.isHeaderStyle
            ? ClipRect(child: filtered)
            : ClipRRect(borderRadius: widget.borderRadius, child: filtered);
      } else {
        // Graceful fallback: enhanced BackdropFilter blur + CustomPainter
        // optical specular rim & chromatic edge highlights.
        final fallbackSigma =
            (blurRadius * 0.78).clamp(0.0, 16.0);
        final fallbackHighlight = Color.alphaBlend(
          Colors.white.withValues(alpha: isDark ? 0.05 : 0.16),
          animatedTint,
        );
        final fallbackBody = AnimatedContainer(
          duration: Duration.zero,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                fallbackHighlight,
                animatedTint,
                animatedTint.withValues(
                  alpha: (animatedTint.a * (isDark ? 1.06 : 0.94))
                      .clamp(0.0, 0.96),
                ),
              ],
            ),
            borderRadius: widget.isHeaderStyle ? null : widget.borderRadius,
            border: widget.border,
          ),
          child: CustomPaint(
            painter: RealLiquidGlassOpticalRimPainter(
              borderRadius: widget.isHeaderStyle
                  ? BorderRadius.zero
                  : widget.borderRadius,
              isDark: isDark,
              mode: mode,
              lightAngle: effectiveLightAngle,
              scrollOffset: effectiveScroll,
              chromaticAberration: chromatic,
              intensity: t,
              bottomBorderOnly: widget.isHeaderStyle,
            ),
            child: widget.isDockStyle || widget.isHeaderStyle
                ? const SizedBox.expand()
                : Padding(padding: widget.padding, child: innerContent),
          ),
        );
        final filtered = BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: fallbackSigma,
            sigmaY: fallbackSigma,
          ),
          child: fallbackBody,
        );
        glassLayer = widget.isHeaderStyle
            ? ClipRect(child: filtered)
            : ClipRRect(borderRadius: widget.borderRadius, child: filtered);
      }

      final Widget composed;
      if (widget.isDockStyle) {
        composed = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(child: glassLayer),
              ),
            ),
            Padding(
              padding: widget.padding,
              child: innerContent,
            ),
          ],
        );
      } else {
        composed = glassLayer;
      }

      if (widget.boxShadow == null || widget.boxShadow!.isEmpty) {
        return composed;
      }

      final outerShadows = widget.boxShadow!
          .map(
            (s) => BoxShadow(
              color: s.color.withValues(alpha: s.color.a * t),
              offset: s.offset,
              blurRadius: s.blurRadius,
              spreadRadius: s.spreadRadius,
              blurStyle: BlurStyle.outer,
            ),
          )
          .toList(growable: false);

      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.isHeaderStyle ? null : widget.borderRadius,
          boxShadow: outerShadows,
        ),
        child: composed,
      );
    }

    Widget surfaceBody = LayoutBuilder(
      builder: (context, constraints) {
        final fallbackSize = Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 320.0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 88.0,
        );
        return ValueListenableBuilder<_OpticalMotionState>(
          valueListenable: _motion,
          child: contentChild,
          builder: (context, motionState, staticChild) {
            if (widget.contentOpacityAnimation == null) {
              return buildSurface(
                factor: 1.0,
                motionState: motionState,
                layoutSize: fallbackSize,
                innerContent: staticChild!,
              );
            }
            return AnimatedBuilder(
              animation: widget.contentOpacityAnimation!,
              child: staticChild,
              builder: (context, animatedChild) {
                return buildSurface(
                  factor: widget.contentOpacityAnimation!.value,
                  motionState: motionState,
                  layoutSize: fallbackSize,
                  innerContent: animatedChild!,
                );
              },
            );
          },
        );
      },
    );

    if (widget.interactiveHighlight && !_reducedMotion) {
      surfaceBody = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerMove,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerRelease,
        onPointerCancel: _handlePointerRelease,
        child: surfaceBody,
      );
    }

    return RepaintBoundary(child: surfaceBody);
  }
}

/// Custom optical rim & chromatic edge highlight painter used in graceful
/// fallback mode (Skia / older GPUs / tests) to emulate curved-glass Fresnel
/// edges, RGB dispersion fringes, and subtle internal caustic sheen.
class RealLiquidGlassOpticalRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final bool isDark;
  final LiquidGlassMode mode;
  final double lightAngle;
  final double scrollOffset;
  final double chromaticAberration;
  final double intensity;
  final bool bottomBorderOnly;

  const RealLiquidGlassOpticalRimPainter({
    required this.borderRadius,
    required this.isDark,
    required this.mode,
    required this.lightAngle,
    required this.scrollOffset,
    required this.chromaticAberration,
    this.intensity = 1.0,
    this.bottomBorderOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intensity <= 0.01) return;
    final rect = Offset.zero & size;
    final dynamicAngle = lightAngle + math.sin(scrollOffset * 0.015) * 0.35;
    final lightBegin = Alignment(math.cos(dynamicAngle), math.sin(dynamicAngle));
    final lightEnd = Alignment(-lightBegin.x, -lightBegin.y);

    if (bottomBorderOnly) {
      final y = size.height - 0.65;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFFFFB86C).withValues(alpha: 0.24 * intensity),
            Colors.white.withValues(alpha: (isDark ? 0.34 : 0.55) * intensity),
            const Color(0xFF8BE9FD).withValues(alpha: 0.24 * intensity),
          ],
        ).createShader(rect);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final outer = borderRadius.toRRect(rect).scaleRadii();
    final prismBoost = chromaticAberration.clamp(0.0, 1.0);
    final warmFringe =
        const Color(0xFFFFC178).withValues(alpha: (0.18 + prismBoost * 0.48) * intensity);
    final coolFringe =
        const Color(0xFF8AE6FF).withValues(alpha: (0.18 + prismBoost * 0.48) * intensity);
    final specPeak =
        Colors.white.withValues(alpha: (isDark ? 0.46 : 0.78) * intensity);
    final specMid =
        Colors.white.withValues(alpha: (isDark ? 0.14 : 0.24) * intensity);
    final bounceColor = mode == LiquidGlassMode.opticalPrism
        ? coolFringe
        : Colors.white.withValues(alpha: (isDark ? 0.26 : 0.38) * intensity);

    // Subtle internal caustic sheen across curved glass surface
    final causticPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: lightBegin,
        end: lightEnd,
        stops: const [0.0, 0.28, 0.65, 1.0],
        colors: [
          Colors.white.withValues(alpha: (isDark ? 0.08 : 0.16) * intensity),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: (isDark ? 0.03 : 0.06) * intensity),
        ],
      ).createShader(rect);
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(rect, causticPaint);
    canvas.restore();

    // Outer chromatic dispersion fringe stroke (1.35px)
    final chromaticStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: lightBegin,
        end: lightEnd,
        stops: const [0.0, 0.22, 0.55, 0.80, 1.0],
        colors: [
          warmFringe,
          specPeak,
          specMid,
          bounceColor,
          coolFringe,
        ],
      ).createShader(rect);
    canvas.drawRRect(outer.deflate(0.7), chromaticStroke);

    // Crisp 1.0px inner specular bevel rim
    final innerRim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: lightBegin,
        end: lightEnd,
        stops: const [0.0, 0.35, 0.72, 1.0],
        colors: [
          specPeak,
          specMid,
          Colors.white.withValues(alpha: (isDark ? 0.05 : 0.12) * intensity),
          bounceColor.withValues(alpha: bounceColor.a * 0.75),
        ],
      ).createShader(rect);
    final innerRRect = outer.deflate(1.3);
    if (innerRRect.width > 0 && innerRRect.height > 0) {
      canvas.drawRRect(innerRRect, innerRim);
    }
  }

  @override
  bool shouldRepaint(covariant RealLiquidGlassOpticalRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.isDark != isDark ||
      oldDelegate.mode != mode ||
      (oldDelegate.lightAngle - lightAngle).abs() > 0.005 ||
      (oldDelegate.scrollOffset - scrollOffset).abs() > 1.0 ||
      oldDelegate.chromaticAberration != chromaticAberration ||
      oldDelegate.intensity != intensity ||
      oldDelegate.bottomBorderOnly != bottomBorderOnly;
}

@immutable
class _OpticalMotionState {
  final double scrollOffset;
  final double pointerAngleDelta;
  final double ambientBiasDx;
  final double ambientBiasDy;

  const _OpticalMotionState({
    required this.scrollOffset,
    required this.pointerAngleDelta,
    required this.ambientBiasDx,
    required this.ambientBiasDy,
  });

  static const _OpticalMotionState zero = _OpticalMotionState(
    scrollOffset: 0.0,
    pointerAngleDelta: 0.0,
    ambientBiasDx: 0.0,
    ambientBiasDy: 0.0,
  );

  _OpticalMotionState copyWith({
    double? scrollOffset,
    double? pointerAngleDelta,
    double? ambientBiasDx,
    double? ambientBiasDy,
  }) {
    return _OpticalMotionState(
      scrollOffset: scrollOffset ?? this.scrollOffset,
      pointerAngleDelta: pointerAngleDelta ?? this.pointerAngleDelta,
      ambientBiasDx: ambientBiasDx ?? this.ambientBiasDx,
      ambientBiasDy: ambientBiasDy ?? this.ambientBiasDy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _OpticalMotionState &&
          other.scrollOffset == scrollOffset &&
          other.pointerAngleDelta == pointerAngleDelta &&
          other.ambientBiasDx == ambientBiasDx &&
          other.ambientBiasDy == ambientBiasDy;

  @override
  int get hashCode => Object.hash(
        scrollOffset,
        pointerAngleDelta,
        ambientBiasDx,
        ambientBiasDy,
      );
}

@immutable
class _ShaderUniformKey {
  final double widthPx;
  final double heightPx;
  final double cornerRadiusPx;
  final double bezelWidthPx;
  final double refractionStrengthPx;
  final double chromaticAberration;
  final double blurRadiusPx;
  final double lightAngle;
  final double scrollOffset;
  final int tintArgb;
  final bool isDark;
  final double dpr;

  const _ShaderUniformKey({
    required this.widthPx,
    required this.heightPx,
    required this.cornerRadiusPx,
    required this.bezelWidthPx,
    required this.refractionStrengthPx,
    required this.chromaticAberration,
    required this.blurRadiusPx,
    required this.lightAngle,
    required this.scrollOffset,
    required this.tintArgb,
    required this.isDark,
    required this.dpr,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ShaderUniformKey &&
          other.widthPx == widthPx &&
          other.heightPx == heightPx &&
          other.cornerRadiusPx == cornerRadiusPx &&
          other.bezelWidthPx == bezelWidthPx &&
          other.refractionStrengthPx == refractionStrengthPx &&
          other.chromaticAberration == chromaticAberration &&
          other.blurRadiusPx == blurRadiusPx &&
          other.lightAngle == lightAngle &&
          other.scrollOffset == scrollOffset &&
          other.tintArgb == tintArgb &&
          other.isDark == isDark &&
          other.dpr == dpr;

  @override
  int get hashCode => Object.hash(
        widthPx,
        heightPx,
        cornerRadiusPx,
        bezelWidthPx,
        refractionStrengthPx,
        chromaticAberration,
        blurRadiusPx,
        lightAngle,
        scrollOffset,
        tintArgb,
        isDark,
        dpr,
      );
}
