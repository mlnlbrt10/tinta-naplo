import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart' show CupertinoRouteTransitionMixin;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxyBox;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../utils/platform_support.dart';
import 'animated_backdrops.dart';
import 'real_liquid_glass_surface.dart';

/// Solid Material 3 tonal indicator pill rendered inside segmented bars and
/// the bottom navigation dock when Liquid Glass mode is disabled.
class Material3TonalPillSurface extends StatelessWidget {
  final BorderRadius borderRadius;

  const Material3TonalPillSurface({
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: borderRadius,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LiquidPillMotionScope extends InheritedWidget {
  final Offset highlightBias;
  final LiquidGlassMode mode;
  final double rippleProgress;
  final Offset rippleOrigin;

  const _LiquidPillMotionScope({
    required this.highlightBias,
    this.mode = LiquidGlassMode.classicFrost,
    this.rippleProgress = 0.0,
    this.rippleOrigin = const Offset(0.5, 0.5),
    required super.child,
  });

  static _LiquidPillMotionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LiquidPillMotionScope>();

  static LiquidGlassMode modeOf(BuildContext context) =>
      maybeOf(context)?.mode ??
      AppProvidersScope.maybeOf(context)?.settings.prefs.liquidGlassMode ??
      UserProfilePrefs.activeLiquidGlassMode;

  @override
  bool updateShouldNotify(covariant _LiquidPillMotionScope oldWidget) =>
      oldWidget.highlightBias != highlightBias ||
      oldWidget.mode != mode ||
      oldWidget.rippleProgress != rippleProgress ||
      oldWidget.rippleOrigin != rippleOrigin;
}

/// Shared lively underdamped liquid spring parameters (`dampingRatio ~ 0.64`)
/// used by the floating bottom dock, weekday selector, and filter tab bars so
/// pills glide with fluid elastic overshoot and settle smoothly in-bounds.
const SpringDescription kLiquidPillSpring = SpringDescription(
  mass: 1.0,
  stiffness: 360.0,
  damping: 24.5,
);

/// Paints an ultra-thin stadium-shaped optical glass rim tracing the outer pill
/// contour (and optional Ripple Gel concentric touch pulse), tailored to
/// [mode] (`Classic Frost`, `Hydro Mercury`, `Optical Prism`, `Smoked Obsidian`,
/// and `Ripple Gel`).
class LiquidGlassRimPainter extends CustomPainter {
  final BorderRadius borderRadius;
  final double strokeWidth;
  final double pressProgress;
  final Offset highlightBias;
  final bool isDark;
  final LiquidGlassMode mode;
  final double rippleProgress;
  final Offset rippleOrigin;
  final ValueListenable<Offset>? lightBiasListenable;

  const LiquidGlassRimPainter({
    required this.borderRadius,
    required this.strokeWidth,
    required this.pressProgress,
    required this.highlightBias,
    required this.isDark,
    this.mode = LiquidGlassMode.classicFrost,
    this.rippleProgress = 0.0,
    this.rippleOrigin = const Offset(0.5, 0.5),
    this.lightBiasListenable,
  }) : super(repaint: lightBiasListenable);

  Offset get _effectiveBias {
    final ambient = lightBiasListenable?.value ?? Offset.zero;
    if (ambient == Offset.zero) return highlightBias;
    return Offset(
      (highlightBias.dx + ambient.dx * 0.55).clamp(-1.0, 1.0),
      (highlightBias.dy + ambient.dy * 0.45).clamp(-1.0, 1.0),
    );
  }

  List<Color> buildPerimeterColors() {
    final t = pressProgress.clamp(0.0, 1.0);
    final by = _effectiveBias.dy.clamp(-1.0, 1.0);
    final topBoost = (1.0 +
            0.18 * t -
            math.max(0.0, by) * 0.25 +
            math.max(0.0, -by) * 0.18)
        .clamp(0.75, 1.25);
    final bottomBoost =
        (1.0 + 0.22 * t + math.max(0.0, by) * 0.85).clamp(0.85, 1.8);

    switch (mode) {
      case LiquidGlassMode.hydroMercury:
        final top = ((isDark ? 0.44 : 0.52) * topBoost).clamp(0.0, 0.72);
        final metallicSilver = const Color(0xFFDCE4EE);
        final mid = ((isDark ? 0.16 : 0.22) * (1.0 + 0.2 * t)).clamp(0.0, 0.52);
        final bottom = ((isDark ? 0.34 : 0.40) * bottomBoost).clamp(0.0, 0.68);
        return <Color>[
          Colors.white.withValues(alpha: top),
          metallicSilver.withValues(alpha: (top * 0.52).clamp(0.0, 0.60)),
          metallicSilver.withValues(alpha: mid),
          metallicSilver.withValues(alpha: (bottom * 0.55).clamp(0.0, 0.60)),
          Colors.white.withValues(alpha: bottom),
        ];

      case LiquidGlassMode.opticalPrism:
        const warmAmber = Color(0xFFFFB86C);
        const coolIce = Color(0xFF8BE9FD);
        final bx = _effectiveBias.dx.clamp(-1.0, 1.0);
        final warmA = ((isDark ? 0.50 : 0.56) * (1.0 + bx.abs() * 0.25 + 0.2 * t))
            .clamp(0.0, 0.76);
        final iceA = ((isDark ? 0.48 : 0.54) * (1.0 + bx.abs() * 0.25 + 0.2 * t))
            .clamp(0.0, 0.76);
        return <Color>[
          (bx >= 0 ? warmAmber : coolIce).withValues(alpha: warmA),
          Colors.white.withValues(alpha: isDark ? 0.24 : 0.32),
          Colors.white.withValues(alpha: isDark ? 0.10 : 0.16),
          Colors.white.withValues(alpha: isDark ? 0.22 : 0.28),
          (bx >= 0 ? coolIce : warmAmber).withValues(alpha: iceA),
        ];

      case LiquidGlassMode.smokedObsidian:
        final topBevel = ((isDark ? 0.24 : 0.32) * topBoost).clamp(0.0, 0.50);
        final edgeBevel = isDark ? 0.08 : 0.12;
        return <Color>[
          Colors.white.withValues(alpha: topBevel),
          const Color(0xFFD0D5DD).withValues(alpha: topBevel * 0.42),
          const Color(0xFF98A2B3).withValues(alpha: edgeBevel),
          const Color(0xFF475467).withValues(alpha: 0.22),
          const Color(0xFF1D222B).withValues(alpha: isDark ? 0.36 : 0.20),
        ];

      case LiquidGlassMode.rippleGel:
      case LiquidGlassMode.classicFrost:
        if (!isDark) {
          return <Color>[
            Colors.white.withValues(alpha: 0.85),
            const Color(0xFF94A3B8).withValues(alpha: 0.22),
            const Color(0xFF94A3B8).withValues(alpha: 0.18),
            const Color(0xFF64748B).withValues(alpha: 0.20),
            const Color(0xFF64748B).withValues(alpha: 0.26),
          ];
        }
        final topAlpha = ((isDark ? 0.32 : 0.42) * topBoost).clamp(0.0, 0.62);
        final upperSideAlpha =
            ((isDark ? 0.16 : 0.22) * (0.9 + 0.2 * t)).clamp(0.0, 0.52);
        final sideAlpha =
            ((isDark ? 0.10 : 0.14) * (1.0 + 0.25 * t)).clamp(0.0, 0.42);
        final lowerSideAlpha =
            ((isDark ? 0.14 : 0.18) * (1.0 + 0.35 * math.max(0.0, by)))
                .clamp(0.0, 0.48);
        final bottomAlpha =
            ((isDark ? 0.18 : 0.24) * bottomBoost).clamp(0.0, 0.56);

        return <Color>[
          Colors.white.withValues(alpha: topAlpha),
          Colors.white.withValues(alpha: upperSideAlpha),
          Colors.white.withValues(alpha: sideAlpha),
          Colors.white.withValues(alpha: lowerSideAlpha),
          Colors.white.withValues(alpha: bottomAlpha),
        ];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final outer = borderRadius.toRRect(rect).scaleRadii();
    final effectiveStroke =
        mode == LiquidGlassMode.opticalPrism ? math.max(strokeWidth, 1.5) : strokeWidth;
    final strokeRRect = outer.deflate(effectiveStroke * 0.5);
    if (strokeRRect.width <= 0 || strokeRRect.height <= 0) return;

    if (mode == LiquidGlassMode.rippleGel &&
        rippleProgress > 0.001 &&
        rippleProgress < 0.999) {
      canvas.save();
      canvas.clipRRect(outer);
      final origin = Offset(
        size.width * rippleOrigin.dx.clamp(0.0, 1.0),
        size.height * rippleOrigin.dy.clamp(0.0, 1.0),
      );
      final maxR = math.max(size.width, size.height) * 0.95;
      final radius = maxR * Curves.easeOutCubic.transform(rippleProgress);
      final decay = (1.0 - rippleProgress).clamp(0.0, 1.0);
      final ripplePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: 0.42 * decay);
      canvas.drawCircle(origin, radius, ripplePaint);
      if (radius > 8.0) {
        final innerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = Colors.white.withValues(alpha: 0.24 * decay);
        canvas.drawCircle(origin, radius * 0.62, innerPaint);
      }
      canvas.restore();
    }

    final bx = _effectiveBias.dx.clamp(-1.0, 1.0);
    final Alignment beginAlign = mode == LiquidGlassMode.opticalPrism
        ? Alignment(-0.85 + bx * 0.3, -1.0)
        : Alignment(bx * 0.35, -1.0);
    final Alignment endAlign = mode == LiquidGlassMode.opticalPrism
        ? Alignment(0.85 - bx * 0.3, 1.0)
        : Alignment(-bx * 0.35, 1.0);
    final gradient = LinearGradient(
      begin: beginAlign,
      end: endAlign,
      stops: const <double>[0.0, 0.24, 0.50, 0.76, 1.0],
      colors: buildPerimeterColors(),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = effectiveStroke
      ..isAntiAlias = true
      ..shader = gradient.createShader(rect);

    canvas.drawRRect(strokeRRect, paint);
  }

  @override
  bool shouldRepaint(covariant LiquidGlassRimPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.pressProgress != pressProgress ||
      oldDelegate.highlightBias != highlightBias ||
      oldDelegate.isDark != isDark ||
      oldDelegate.mode != mode ||
      oldDelegate.rippleProgress != rippleProgress ||
      oldDelegate.rippleOrigin != rippleOrigin ||
      oldDelegate.lightBiasListenable != lightBiasListenable;
}

/// Translucent Liquid Glass pill surface with a uniform translucent fill and an
/// ultra-thin (`1.0px-1.2px`) pure-white perimeter specular rim tracing the
/// stadium contour, intensifying smoothly as [pressProgress] approaches `1.0`.
///
/// Uses a pure uniform color fill, `CustomPainter` perimeter stroke, and soft
/// glow shadow (zero `BackdropFilter` and zero grey/black interior stripe
/// bands) so scrolling lists and docks sustain 120fps.
class LiquidGlassPillSurface extends StatelessWidget {
  final double pressProgress;
  final BorderRadius borderRadius;
  final Color? accentColor;
  final bool solidBase;
  final Offset highlightBias;
  final LiquidGlassMode? mode;
  final bool? realLiquidGlassEnabled;

  const LiquidGlassPillSurface({
    super.key,
    required this.pressProgress,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.accentColor,
    this.solidBase = false,
    this.highlightBias = Offset.zero,
    this.mode,
    this.realLiquidGlassEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final motionScope = _LiquidPillMotionScope.maybeOf(context);
    final settingsPrefs = AppProvidersScope.maybeOf(context)?.settings.prefs;
    final effectiveMode = mode ?? _LiquidPillMotionScope.modeOf(context);
    final baseColor = accentColor ?? scheme.primary;
    final t = pressProgress.clamp(0.0, 1.0);
    final resolvedBias =
        highlightBias != Offset.zero ? highlightBias : (motionScope?.highlightBias ?? Offset.zero);
    final bx = resolvedBias.dx.clamp(-1.0, 1.0);
    final by = resolvedBias.dy.clamp(-1.0, 1.0);
    final useRealShaderPill = !isIOSPlatform &&
        !solidBase &&
        (realLiquidGlassEnabled ??
            settingsPrefs?.realLiquidGlassEnabled ??
            UserProfilePrefs.activeRealLiquidGlassEnabled);

    final Color uniformTint;
    final double rimStrokeWidth;
    if (solidBase) {
      uniformTint = Color.lerp(
        baseColor,
        Color.lerp(baseColor, Colors.white, 0.18)!,
        t,
      )!;
      rimStrokeWidth = lerpDouble(1.05, 1.20, t)!;
    } else {
      switch (effectiveMode) {
        case LiquidGlassMode.hydroMercury:
          uniformTint = Color.lerp(
            isDark ? const Color(0xFFC8D3E0) : const Color(0xFF94A3B8),
            Colors.white,
            isDark ? (0.28 + 0.18 * t) : (0.34 + 0.18 * t),
          )!.withValues(alpha: isDark ? lerpDouble(0.28, 0.42, t)! : lerpDouble(0.22, 0.34, t)!);
          rimStrokeWidth = lerpDouble(1.15, 1.35, t)!;
          break;
        case LiquidGlassMode.opticalPrism:
          uniformTint = Color.lerp(
            baseColor,
            Colors.white,
            isDark ? (0.22 + 0.14 * t) : (0.14 + 0.14 * t),
          )!.withValues(alpha: isDark ? lerpDouble(0.14, 0.24, t)! : lerpDouble(0.16, 0.24, t)!);
          rimStrokeWidth = 1.5;
          break;
        case LiquidGlassMode.smokedObsidian:
          uniformTint = (isDark ? const Color(0xFF1A1D22) : const Color(0xFF94A3B8))
              .withValues(alpha: isDark ? lerpDouble(0.46, 0.56, t)! : lerpDouble(0.26, 0.36, t)!);
          rimStrokeWidth = 1.0;
          break;
        case LiquidGlassMode.rippleGel:
          uniformTint = Color.lerp(
            baseColor,
            Colors.white,
            isDark ? (0.16 + 0.16 * t) : (0.12 + 0.16 * t),
          )!.withValues(alpha: isDark ? lerpDouble(0.24, 0.38, t)! : lerpDouble(0.22, 0.34, t)!);
          rimStrokeWidth = lerpDouble(1.10, 1.28, t)!;
          break;
        case LiquidGlassMode.classicFrost:
          uniformTint = Color.lerp(
            baseColor,
            Colors.white,
            isDark ? (0.10 + 0.14 * t) : (0.08 + 0.14 * t),
          )!.withValues(
            alpha: isDark
                ? lerpDouble(0.24, 0.36, t)!
                : lerpDouble(0.20, 0.30, t)!,
          );
          rimStrokeWidth = lerpDouble(1.05, 1.20, t)!;
          break;
      }
    }

    if (useRealShaderPill) {
      final rimPainter = LiquidGlassRimPainter(
        borderRadius: borderRadius,
        strokeWidth: rimStrokeWidth,
        pressProgress: t,
        highlightBias: Offset(bx, by),
        isDark: isDark,
        mode: effectiveMode,
        rippleProgress: motionScope?.rippleProgress ?? 0.0,
        rippleOrigin: motionScope?.rippleOrigin ?? const Offset(0.5, 0.5),
        lightBiasListenable: BackdropMotionCoordinator.lightBiasNotifier,
      );
      return RealLiquidGlassSurface(
        prefs: settingsPrefs,
        borderRadius: borderRadius,
        tintColor: uniformTint,
        opacityScale: (0.28 + 0.24 * t).clamp(0.28, 0.54),
        compactOptics: true,
        bezelWidthOverride: 10.0,
        refractionStrengthOverride: 11.0 + 4.5 * t,
        blurRadiusOverride: 3.5,
        modeOverride: effectiveMode,
        interactiveHighlight: false,
        boxShadow: [
          BoxShadow(
            color: (effectiveMode == LiquidGlassMode.smokedObsidian
                    ? Colors.black
                    : baseColor)
                .withValues(
              alpha: lerpDouble(
                isDark ? 0.16 : 0.10,
                isDark ? 0.36 : 0.24,
                t,
              )!,
            ),
            blurRadius: lerpDouble(8.0, 18.0, t)!,
            spreadRadius: lerpDouble(0.0, 1.0, t)!,
            offset: Offset(bx * 2.0, lerpDouble(2.0, 3.0, t)! + by * 2.0),
          ),
        ],
        child: CustomPaint(
          painter: rimPainter,
          child: const SizedBox.expand(),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: uniformTint,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: (effectiveMode == LiquidGlassMode.smokedObsidian
                    ? Colors.black
                    : baseColor)
                .withValues(
              alpha: lerpDouble(
                isDark ? 0.16 : 0.10,
                isDark ? 0.36 : 0.24,
                t,
              )!,
            ),
            blurRadius: lerpDouble(8.0, 18.0, t)!,
            spreadRadius: lerpDouble(0.0, 1.0, t)!,
            offset: Offset(bx * 2.0, lerpDouble(2.0, 3.0, t)! + by * 2.0),
          ),
          if (t > 0.02)
            BoxShadow(
              color: Colors.white.withValues(
                alpha: (isDark ? 0.14 : 0.24) * t,
              ),
              blurRadius: 10.0 * t,
              spreadRadius: -1.0,
              offset: Offset(bx * 1.5, by * 2.0),
            ),
        ],
      ),
      child: CustomPaint(
        painter: LiquidGlassRimPainter(
          borderRadius: borderRadius,
          strokeWidth: rimStrokeWidth,
          pressProgress: t,
          highlightBias: Offset(bx, by),
          isDark: isDark,
          mode: effectiveMode,
          rippleProgress: motionScope?.rippleProgress ?? 0.0,
          rippleOrigin: motionScope?.rippleOrigin ?? const Offset(0.5, 0.5),
          lightBiasListenable:
              solidBase ? null : BackdropMotionCoordinator.lightBiasNotifier,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Shared physics, gesture tracking, magnification (`pressScale`), continuous
/// finger following, velocity squish, and spring snap controller for both
/// [LiquidSpringPillTrack] and [LiquidBubbleTabBar].
class _LiquidInteractivePhysics {
  static const double _maxOverscrollPx = 15.0;
  static const double _maxVerticalPullPx = 7.0;

  final TickerProvider vsync;
  final VoidCallback onScheduleUpdate;
  late final AnimationController pillAnim;
  late final AnimationController pressAnim;
  late final AnimationController rippleAnim;
  final ValueNotifier<double> offsetYAnim = ValueNotifier<double>(0.0);
  Offset rippleOrigin = const Offset(0.5, 0.5);
  late final Listenable listenable = Listenable.merge([
    pillAnim,
    pressAnim,
    rippleAnim,
    offsetYAnim,
  ]);

  Ticker? _physicsTicker;
  int? _lastPhysicsUs;
  late double _renderedPos = pillAnim.value;
  double _renderedVel = 0.0;
  late double _dragTargetPos = pillAnim.value;
  late double _snapTargetPos = pillAnim.value;

  double _renderedPosY = 0.0;
  double _renderedVelY = 0.0;
  double _dragTargetPosY = 0.0;

  bool _tapSlideActive = false;
  double _tapSlideStartPos = 0.0;
  double _tapSlideTargetPos = 0.0;
  double _tapSlidePeakProgress = 0.0;
  bool _arrivalReboundActive = false;
  double _arrivalReboundT = 0.0;

  bool _isExternalFollowing = false;
  double _externalVelocity = 0.0;

  PageController? _attachedPageController;
  ScrollPosition? _observedPosition;
  double? _lastPageSample;
  int _lastPageSampleUs = 0;
  double _pageDragVelocity = 0.0;
  bool _ignorePageController = false;
  int _itemCount = 0;
  double _pageOffset = 0.0;
  bool _suppressExternalUntilScrollEnd = false;
  bool _programmaticTapInFlight = false;
  int Function()? _selectedIndexProvider;

  bool get isSuppressingExternal =>
      _suppressExternalUntilScrollEnd || _programmaticTapInFlight;

  bool isInteracting = false;
  bool _longPressActive = false;
  bool _horizontalDragActive = false;
  bool _disposed = false;
  Offset? _downGlobalPos;
  int _hoverIndex = 0;
  int? _pendingSnapTarget;
  double? _lastPointerX;
  int _lastPointerTimeUs = 0;
  double dragVelocity = 0.0;
  List<Rect> slotRects = const [];
  bool _liquidGlassEnabled = true;
  LiquidGlassMode _liquidGlassMode = LiquidGlassMode.classicFrost;

  bool get liquidGlassEnabled => _liquidGlassEnabled;
  LiquidGlassMode get liquidGlassMode => _liquidGlassMode;

  void setLiquidGlassMode(LiquidGlassMode mode) {
    _liquidGlassMode = mode;
  }

  _LiquidInteractivePhysics({
    required this.vsync,
    required int initialIndex,
    required this.onScheduleUpdate,
    bool liquidGlassEnabled = true,
    LiquidGlassMode liquidGlassMode = LiquidGlassMode.classicFrost,
  })  : _liquidGlassEnabled = liquidGlassEnabled,
        _liquidGlassMode = liquidGlassMode {
    pillAnim = AnimationController.unbounded(
      vsync: vsync,
      value: initialIndex.toDouble(),
    );
    pillAnim.addListener(_syncRenderedPosIfNotPhysicsTicking);
    pressAnim = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 220),
    );
    rippleAnim = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 360),
    );
    _hoverIndex = initialIndex;
  }

  void triggerRippleAtLocalDx(double dx) {
    if (_disposed ||
        !_liquidGlassEnabled ||
        _liquidGlassMode != LiquidGlassMode.rippleGel ||
        slotRects.isEmpty) {
      return;
    }
    final activeRect = interpolatedPillRect(_renderedPos);
    final relX = activeRect.width > 0
        ? ((dx - activeRect.left) / activeRect.width).clamp(0.1, 0.9)
        : 0.5;
    rippleOrigin = Offset(relX, 0.5);
    rippleAnim.forward(from: 0.0);
  }

  void _syncRenderedPosIfNotPhysicsTicking() {
    if (!(_physicsTicker?.isActive ?? false)) {
      _renderedPos = pillAnim.value;
    }
  }

  void setLiquidGlassEnabled(bool enabled) {
    if (_liquidGlassEnabled == enabled) return;
    _liquidGlassEnabled = enabled;
    if (!enabled) {
      _stopPhysicsTicker();
      isInteracting = false;
      _longPressActive = false;
      _horizontalDragActive = false;
      _downGlobalPos = null;
      _renderedVel = 0.0;
      _renderedPosY = 0.0;
      _renderedVelY = 0.0;
      _dragTargetPosY = 0.0;
      _tapSlideActive = false;
      _tapSlidePeakProgress = 0.0;
      _arrivalReboundActive = false;
      _arrivalReboundT = 0.0;
      _snapTargetPos = pillAnim.value;
      _dragTargetPos = pillAnim.value;
      if (offsetYAnim.value != 0.0) {
        offsetYAnim.value = 0.0;
      }
      if (pressAnim.isAnimating) {
        pressAnim.stop(canceled: true);
      }
      if (pressAnim.value != 0.0) {
        pressAnim.value = 0.0;
      }
    }
  }

  double get pressProgress =>
      Curves.easeOutCubic.transform(pressAnim.value.clamp(0.0, 1.0));

  int activeHoverIndex(int selectedIndex) {
    if (isInteracting) return _hoverIndex;
    if (_pendingSnapTarget != null) return _pendingSnapTarget!;
    return selectedIndex;
  }

  static List<Rect> buildSlotRects({
    required double totalWidth,
    required double pillHeight,
    required List<int> flexWeights,
    double? fixedPillWidth,
  }) {
    final count = flexWeights.length;
    if (count == 0 || totalWidth <= 0) return const [];
    final totalFlex = flexWeights.fold<int>(0, (a, b) => a + b);
    final safeTotalFlex = totalFlex <= 0 ? count : totalFlex;
    var cursorX = 0.0;
    return List<Rect>.generate(count, (i) {
      final wFactor = (totalFlex <= 0 ? 1 : flexWeights[i]) / safeTotalFlex;
      final slotW = totalWidth * wFactor;
      final effectiveW = fixedPillWidth ?? slotW;
      final left = cursorX + ((slotW - effectiveW) / 2);
      cursorX += slotW;
      return Rect.fromLTWH(left, 0.0, effectiveW, pillHeight);
    }, growable: false);
  }

  int indexAtX(double dx) {
    if (slotRects.isEmpty) return 0;
    final n = slotRects.length;
    final totalLeft = slotRects.first.left;
    final totalRight = slotRects.last.right;
    final clamped = dx.clamp(totalLeft, totalRight);
    // Split at consecutive slot midpoints so custom fixedPillWidth tracks map
    // cleanly across the full container width.
    for (int i = 0; i < n - 1; i++) {
      final boundary =
          (slotRects[i].center.dx + slotRects[i + 1].center.dx) * 0.5;
      if (clamped < boundary) return i;
    }
    return n - 1;
  }

  double get currentVelocity =>
      _isExternalFollowing ? _externalVelocity : _renderedVel;

  void _ensureTickerRunning() {
    if (_disposed) return;
    _physicsTicker ??= vsync.createTicker(_onPhysicsTick);
    if (!_physicsTicker!.isActive) {
      _lastPhysicsUs = null;
      _physicsTicker!.start();
    }
  }

  void _stopPhysicsTicker({bool canceled = false}) {
    _lastPhysicsUs = null;
    if (_physicsTicker != null && _physicsTicker!.isActive) {
      _physicsTicker!.stop(canceled: canceled);
    }
  }

  void _onPhysicsTick(Duration elapsed) {
    if (_disposed || _isExternalFollowing) {
      _stopPhysicsTicker(canceled: _disposed);
      return;
    }
    final nowUs = elapsed.inMicroseconds;
    final double rawDt;
    if (_lastPhysicsUs == null) {
      _lastPhysicsUs = nowUs;
      rawDt = nowUs > 0 ? (nowUs / 1000000.0).clamp(0.0005, 1.0) : 0.016;
    } else {
      rawDt = ((nowUs - _lastPhysicsUs!) / 1000000.0).clamp(0.0005, 1.0);
      _lastPhysicsUs = nowUs;
    }

    final targetX = isInteracting ? _dragTargetPos : _snapTargetPos;
    final targetY = isInteracting ? _dragTargetPosY : 0.0;
    // Active finger drags track through a crisp 2D fluid spring-damper follower;
    // releases hand off cleanly to the active physical-optics spring parameters.
    final stiffnessX = isInteracting
        ? (_liquidGlassMode == LiquidGlassMode.smokedObsidian ? 820.0 : 1180.0)
        : _liquidGlassMode.stiffnessX;
    final dampingX = isInteracting
        ? (_liquidGlassMode == LiquidGlassMode.smokedObsidian ? 58.0 : 48.0)
        : _liquidGlassMode.dampingX;
    final stiffnessY = isInteracting ? 920.0 : _liquidGlassMode.stiffnessY;
    final dampingY = isInteracting ? 38.0 : _liquidGlassMode.dampingY;
    final steps = (rawDt / 0.004).ceil().clamp(1, 250);
    final h = rawDt / steps;

    for (int i = 0; i < steps; i++) {
      final dispX = _renderedPos - targetX;
      final accelX = (-stiffnessX * dispX) - (dampingX * _renderedVel);
      _renderedVel += accelX * h;
      _renderedPos += _renderedVel * h;

      final dispY = _renderedPosY - targetY;
      final accelY = (-stiffnessY * dispY) - (dampingY * _renderedVelY);
      _renderedVelY += accelY * h;
      _renderedPosY += _renderedVelY * h;
    }

    if (_tapSlideActive && !isInteracting) {
      final span = (_tapSlideTargetPos - _tapSlideStartPos).abs();
      if (span > 0.001) {
        final rawProgress =
            ((_renderedPos - _tapSlideStartPos).abs() / span).clamp(0.0, 1.0);
        if (rawProgress > _tapSlidePeakProgress) {
          _tapSlidePeakProgress = rawProgress;
        }
      } else {
        _tapSlidePeakProgress = 1.0;
      }
      if (_tapSlidePeakProgress >= 0.72) {
        _arrivalReboundActive = true;
        _arrivalReboundT = (_arrivalReboundT + (rawDt / 0.18)).clamp(0.0, 1.0);
      }
    }

    final xSettled = (_renderedPos - targetX).abs() < 0.0005 &&
        _renderedVel.abs() < 0.002;
    final ySettled = (_renderedPosY - targetY).abs() < 0.02 &&
        _renderedVelY.abs() < 0.25;
    final tapReboundSettled =
        !_tapSlideActive || (_arrivalReboundActive && _arrivalReboundT >= 1.0);

    if (!isInteracting && xSettled && ySettled && tapReboundSettled) {
      _renderedPos = targetX;
      _renderedVel = 0.0;
      _renderedPosY = targetY;
      _renderedVelY = 0.0;
      _tapSlideActive = false;
      _tapSlidePeakProgress = 0.0;
      _arrivalReboundActive = false;
      _arrivalReboundT = 0.0;
      _pendingSnapTarget = null;
      pillAnim.value = targetX;
      offsetYAnim.value = targetY;
      _stopPhysicsTicker();
      return;
    }

    pillAnim.value = _renderedPos;
    offsetYAnim.value = _renderedPosY;
  }

  void attachPageController({
    required PageController? controller,
    required int itemCount,
    double pageOffset = 0.0,
    required bool ignore,
    required int Function() selectedIndexProvider,
  }) {
    final bool wasIgnoring = _ignorePageController;
    final bool pageOffsetChanged = (_pageOffset - pageOffset).abs() > 0.001;
    _itemCount = itemCount;
    _pageOffset = pageOffset;
    _ignorePageController = ignore;
    _selectedIndexProvider = selectedIndexProvider;
    if (wasIgnoring && !ignore) {
      _suppressExternalUntilScrollEnd = false;
      _programmaticTapInFlight = false;
      if (controller != null &&
          controller.hasClients &&
          controller.position.haveDimensions &&
          controller.position.isScrollingNotifier.value) {
        _tapSlideActive = false;
        _tapSlidePeakProgress = 0.0;
        _arrivalReboundActive = false;
        _arrivalReboundT = 0.0;
      }
    }
    if (pageOffsetChanged &&
        !ignore &&
        controller != null &&
        controller.hasClients &&
        controller.position.haveDimensions &&
        controller.position.isScrollingNotifier.value) {
      _suppressExternalUntilScrollEnd = true;
      _isExternalFollowing = false;
      _externalVelocity = 0.0;
      _pageDragVelocity = 0.0;
      _lastPageSample = null;
      _lastPageSampleUs = 0;
    }
    if (_attachedPageController == controller) {
      _attachScrollEndListener();
      return;
    }
    detachPageController();
    _attachedPageController = controller;
    controller?.addListener(_onPageControllerChanged);
    if (controller != null && controller.hasClients) {
      _attachScrollEndListener();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attachScrollEndListener();
      });
    }
  }

  void clampPositionToMax(double maxIdx) {
    if (_disposed) return;
    if (_snapTargetPos > maxIdx) {
      _snapTargetPos = maxIdx;
    }
    if (!isInteracting &&
        !_isExternalFollowing &&
        (_renderedPos > maxIdx || pillAnim.value > maxIdx)) {
      launchSpringTo(maxIdx);
    }
  }

  void detachPageController() {
    _attachedPageController?.removeListener(_onPageControllerChanged);
    _attachedPageController = null;
    _detachScrollEndListener();
  }

  void _attachScrollEndListener() {
    if (_disposed) return;
    final pc = _attachedPageController;
    if (pc == null || !pc.hasClients) return;
    final pos = pc.position;
    if (_observedPosition == pos) return;
    _detachScrollEndListener();
    _observedPosition = pos;
    pos.isScrollingNotifier.addListener(_onScrollingStateChanged);
  }

  void _detachScrollEndListener() {
    _observedPosition?.isScrollingNotifier.removeListener(
      _onScrollingStateChanged,
    );
    _observedPosition = null;
  }

  void _onScrollingStateChanged() {
    if (_disposed) return;
    final pos = _observedPosition;
    if (pos == null || pos.isScrollingNotifier.value) return;
    final wasSuppressing =
        _suppressExternalUntilScrollEnd || _programmaticTapInFlight;
    _suppressExternalUntilScrollEnd = false;
    _programmaticTapInFlight = false;
    if (_isExternalFollowing) {
      final leftoverVel = _pageDragVelocity.clamp(-8.0, 8.0);
      _isExternalFollowing = false;
      _externalVelocity = 0.0;
      _pageDragVelocity = 0.0;
      _lastPageSample = null;
      _lastPageSampleUs = 0;
      final targetIdx = _selectedIndexProvider?.call() ?? 0;
      launchSpringTo(
        targetIdx.toDouble(),
        initialVelocity: leftoverVel,
      );
    } else if (!isInteracting && !_tapSlideActive) {
      final targetIdx = (_selectedIndexProvider?.call() ?? 0).toDouble();
      if (wasSuppressing && (_snapTargetPos - targetIdx).abs() > 0.001) {
        launchSpringTo(targetIdx);
      } else if ((pillAnim.value - targetIdx).abs() > 0.001 ||
          (_snapTargetPos - targetIdx).abs() > 0.001) {
        launchSpringTo(targetIdx);
      }
    }
  }

  void _scheduleExternalSuppressionCleanupIfIdle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      final pc = _attachedPageController;
      if (pc == null ||
          !pc.hasClients ||
          !pc.position.isScrollingNotifier.value) {
        _suppressExternalUntilScrollEnd = false;
        _programmaticTapInFlight = false;
      }
    });
  }

  void _onPageControllerChanged() {
    _attachScrollEndListener();
    if (_ignorePageController ||
        _suppressExternalUntilScrollEnd ||
        _programmaticTapInFlight ||
        _tapSlideActive ||
        isInteracting) {
      return;
    }
    final pc = _attachedPageController;
    if (pc == null || !pc.hasClients || !pc.position.haveDimensions) return;
    if (!pc.position.isScrollingNotifier.value) return;
    final page = pc.page;
    if (page == null) return;
    final maxIdx = math.max(0, _itemCount - 1).toDouble();
    final clamped = (page - _pageOffset).clamp(0.0, maxIdx);
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (_lastPageSample != null && _lastPageSampleUs > 0) {
      final dtSec =
          ((nowUs - _lastPageSampleUs) / 1000000.0).clamp(0.004, 0.05);
      final instVel =
          ((clamped - _lastPageSample!) / dtSec).clamp(-18.0, 18.0);
      _pageDragVelocity = (_pageDragVelocity * 0.55) + (instVel * 0.45);
    }
    _lastPageSample = clamped;
    _lastPageSampleUs = nowUs;
    _isExternalFollowing = true;
    _externalVelocity = _pageDragVelocity;
    _renderedPos = clamped;
    _renderedVel = _pageDragVelocity;
    _snapTargetPos = clamped;
    _stopPhysicsTicker();
    pillAnim.value = clamped;
  }

  double _leftEdgeSpan() => slotRects.length >= 2
      ? math.max(1.0, slotRects[1].center.dx - slotRects.first.center.dx)
      : (slotRects.isEmpty ? 1.0 : math.max(1.0, slotRects.first.width));

  double _rightEdgeSpan() {
    final n = slotRects.length;
    if (n >= 2) {
      return math.max(1.0, slotRects.last.center.dx - slotRects[n - 2].center.dx);
    }
    return slotRects.isEmpty ? 1.0 : math.max(1.0, slotRects.last.width);
  }

  double continuousPosAtX(double dx) {
    final n = slotRects.length;
    if (n <= 1) return 0.0;
    final c0 = slotRects.first.center.dx;
    final cn = slotRects.last.center.dx;
    if (dx < c0) {
      if (!_liquidGlassEnabled) return 0.0;
      final overscrollPx =
          _maxOverscrollPx * (1.0 - math.exp(-(c0 - dx) / 26.0));
      return -(overscrollPx / _leftEdgeSpan());
    }
    if (dx > cn) {
      if (!_liquidGlassEnabled) return (n - 1).toDouble();
      final overscrollPx =
          _maxOverscrollPx * (1.0 - math.exp(-(dx - cn) / 26.0));
      return (n - 1) + (overscrollPx / _rightEdgeSpan());
    }
    for (int i = 0; i < n - 1; i++) {
      final ci = slotRects[i].center.dx;
      final cNext = slotRects[i + 1].center.dx;
      if (dx <= cNext) {
        final span = math.max(1.0, cNext - ci);
        return i + ((dx - ci) / span).clamp(0.0, 1.0);
      }
    }
    return (n - 1).toDouble();
  }

  Rect interpolatedPillRect(double pos, {double topOffset = 0.0}) {
    final n = slotRects.length;
    if (n == 0) return Rect.zero;
    final maxIdx = n - 1;
    if (pos < 0.0) {
      return slotRects.first.translate(pos * _leftEdgeSpan(), topOffset);
    }
    if (pos > maxIdx) {
      return slotRects.last
          .translate((pos - maxIdx) * _rightEdgeSpan(), topOffset);
    }
    final lo = pos.floor().clamp(0, maxIdx);
    final hi = pos.ceil().clamp(0, maxIdx);
    final t = pos - lo;
    final r = Rect.lerp(slotRects[lo], slotRects[hi], t)!;
    return r.translate(0.0, topOffset);
  }

  double overscrollPxAtPos(double pos) {
    final n = slotRects.length;
    if (n == 0) return 0.0;
    final maxIdx = n - 1;
    if (pos < 0.0) return pos * _leftEdgeSpan();
    if (pos > maxIdx) return (pos - maxIdx) * _rightEdgeSpan();
    return 0.0;
  }

  double verticalPullAtDeltaY(double rawDy) {
    if (!_liquidGlassEnabled || rawDy.abs() < 0.5) return 0.0;
    return rawDy.sign *
        _maxVerticalPullPx *
        (1.0 - math.exp(-rawDy.abs() / 22.0));
  }

  Matrix4 buildDropletTransform({
    required double pos,
    required double pressScale,
    required double pressProgress,
  }) {
    if (!_liquidGlassEnabled) return Matrix4.identity();
    final holdScale = lerpDouble(1.0, pressScale, pressProgress)!;
    final velX = currentVelocity;
    final stretchMult = _liquidGlassMode.stretchMultiplier.clamp(0.0, 1.08);

    if (_tapSlideActive && !isInteracting && !_isExternalFollowing) {
      final modeGain = switch (_liquidGlassMode) {
        LiquidGlassMode.smokedObsidian => 0.45,
        LiquidGlassMode.hydroMercury => 1.05,
        _ => 1.0,
      };
      final double scaleX;
      final double scaleY;
      final double skewX;
      if (!_arrivalReboundActive) {
        // Phase 1 (0.0 -> 0.72 travel): fluid horizontal stretch up to ~1.085
        // paired with vertical compression down to ~0.95 along strict X slide.
        final u = (_tapSlidePeakProgress / 0.72).clamp(0.0, 1.0);
        final travelArch = math.sin(math.pi * u);
        scaleX = (1.0 + (0.085 * travelArch * modeGain)) * holdScale;
        scaleY = (1.0 - (0.05 * travelArch * modeGain)) * holdScale;
        final signedDir =
            velX.abs() > 0.2 ? (velX / 10.0).clamp(-1.0, 1.0) : 0.0;
        skewX = signedDir == 0.0
            ? 0.0
            : -signedDir * 0.026 * travelArch * modeGain;
      } else {
        // Phase 2 (0.72 -> 1.0 arrival settle): lively springy vertical liquid
        // expansion (~1.055) while scaleX rebounds cleanly inside the bar.
        final reboundCurve = math.sin(
          math.pi * math.pow(_arrivalReboundT.clamp(0.0, 1.0), 0.78),
        );
        scaleX = (1.0 - (0.022 * reboundCurve * modeGain)) * holdScale;
        scaleY = (1.0 + (0.055 * reboundCurve * modeGain)) * holdScale;
        skewX = 0.0;
      }
      return Matrix4.diagonal3Values(scaleX, scaleY, 1.0)
        ..setEntry(0, 1, skewX);
    }

    final velXNorm = (velX.abs() / 10.0).clamp(0.0, 1.0);
    final edgeXPx = overscrollPxAtPos(pos);
    final edgeXNorm = (edgeXPx.abs() / _maxOverscrollPx).clamp(0.0, 1.0);
    final motionX = math.max(velXNorm, edgeXNorm * 0.65).clamp(0.0, 1.0);

    final pullYNorm = _maxVerticalPullPx > 0
        ? (_renderedPosY.abs() / _maxVerticalPullPx).clamp(0.0, 1.0)
        : 0.0;
    final velYNorm = (_renderedVelY.abs() / 180.0).clamp(0.0, 1.0);
    final motionY = math.max(pullYNorm, velYNorm * 0.65).clamp(0.0, 1.0);

    // Balanced 2D droplet glide + hold-and-drag Y-axis elasticity following finger.
    final hStretch =
        1.0 + ((motionX * 0.085) - (motionY * 0.045)) * stretchMult;
    final vStretch =
        1.0 + ((motionY * 0.085) - (motionX * 0.045)) * stretchMult;
    final gelSquishX = _liquidGlassMode == LiquidGlassMode.rippleGel
        ? (1.0 + 0.04 * pressProgress)
        : 1.0;
    final gelSquishY = _liquidGlassMode == LiquidGlassMode.rippleGel
        ? (1.0 - 0.03 * pressProgress)
        : 1.0;
    final scaleX = hStretch * holdScale * gelSquishX;
    final scaleY = vStretch * holdScale * gelSquishY;

    final signedMotion = velX.abs() > 0.25
        ? (velX / 10.0).clamp(-1.0, 1.0)
        : (edgeXPx / _maxOverscrollPx).clamp(-1.0, 1.0);
    final skewX = signedMotion.abs() < 0.001
        ? 0.0
        : -signedMotion * 0.032 * stretchMult;

    return Matrix4.diagonal3Values(scaleX, scaleY, 1.0)
      ..setEntry(0, 1, skewX);
  }

  Offset buildHighlightBias({required double pos}) {
    if (!_liquidGlassEnabled) return Offset.zero;
    final velX = currentVelocity;
    final edgeXPx = overscrollPxAtPos(pos);
    final bx = ((velX / 10.0).clamp(-1.0, 1.0) * 0.65 +
            (edgeXPx / _maxOverscrollPx).clamp(-1.0, 1.0) * 0.55)
        .clamp(-1.0, 1.0);
    final by = _maxVerticalPullPx <= 0.0
        ? 0.0
        : ((_renderedPosY / _maxVerticalPullPx) * 0.85 +
                (_renderedVelY / 180.0) * 0.35)
            .clamp(-1.0, 1.0);
    return Offset(bx, by);
  }

  void launchSpringTo(
    double target, {
    double? initialVelocity,
    double? initialVelocityY,
    bool keepInteracting = false,
  }) {
    if (_disposed) return;
    _isExternalFollowing = false;
    _externalVelocity = 0.0;
    if (!_liquidGlassEnabled) {
      _stopPhysicsTicker();
      final maxIdx = math
          .max(0, math.max(_itemCount, slotRects.length) - 1)
          .toDouble();
      final clampedTarget = target.clamp(0.0, maxIdx);
      _snapTargetPos = clampedTarget;
      _renderedVel = 0.0;
      _renderedPosY = 0.0;
      _renderedVelY = 0.0;
      _tapSlideActive = false;
      _tapSlidePeakProgress = 0.0;
      _arrivalReboundActive = false;
      _arrivalReboundT = 0.0;
      if (offsetYAnim.value != 0.0) {
        offsetYAnim.value = 0.0;
      }
      if (keepInteracting) {
        _dragTargetPos = clampedTarget;
        isInteracting = true;
        if (pillAnim.isAnimating) pillAnim.stop(canceled: true);
        pillAnim.value = clampedTarget;
        _renderedPos = clampedTarget;
      } else {
        isInteracting = false;
        _dragTargetPosY = 0.0;
        dragVelocity = 0.0;
        _lastPointerX = null;
        _lastPointerTimeUs = 0;
        if ((pillAnim.value - clampedTarget).abs() < 0.0005) {
          if (pillAnim.isAnimating) pillAnim.stop(canceled: true);
          pillAnim.value = clampedTarget;
          _renderedPos = clampedTarget;
        } else {
          pillAnim.animateTo(
            clampedTarget,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
      return;
    }
    _snapTargetPos = target;
    if (keepInteracting) {
      _dragTargetPos = target;
      isInteracting = true;
      _tapSlideActive = false;
      _tapSlidePeakProgress = 0.0;
      _arrivalReboundActive = false;
      _arrivalReboundT = 0.0;
    } else {
      isInteracting = false;
      _dragTargetPosY = 0.0;
      dragVelocity = 0.0;
      _lastPointerX = null;
      _lastPointerTimeUs = 0;
      final distSlots = (_renderedPos - target).abs();
      if (distSlots >= 0.25 && _renderedPosY.abs() < 0.05) {
        _renderedPosY = 0.0;
        _renderedVelY = 0.0;
        offsetYAnim.value = 0.0;
        _tapSlideActive = true;
        _tapSlideStartPos = _renderedPos;
        _tapSlideTargetPos = target;
        _tapSlidePeakProgress = 0.0;
        _arrivalReboundActive = false;
        _arrivalReboundT = 0.0;
      } else {
        _tapSlideActive = false;
        _tapSlidePeakProgress = 0.0;
        _arrivalReboundActive = false;
        _arrivalReboundT = 0.0;
      }
    }

    if (initialVelocity != null &&
        initialVelocity.abs() > _renderedVel.abs()) {
      _renderedVel = initialVelocity;
    }

    if (initialVelocityY != null &&
        initialVelocityY.abs() > _renderedVelY.abs()) {
      _renderedVelY = initialVelocityY;
    }

    final xSettled = (_renderedPos - target).abs() < 0.0005 &&
        _renderedVel.abs() < 0.002;
    final ySettled = _renderedPosY.abs() < 0.02 && _renderedVelY.abs() < 0.25;
    if (!keepInteracting && xSettled && ySettled && !_tapSlideActive) {
      _renderedPos = target;
      _renderedVel = 0.0;
      _renderedPosY = 0.0;
      _renderedVelY = 0.0;
      pillAnim.value = target;
      offsetYAnim.value = 0.0;
      _stopPhysicsTicker();
      return;
    }
    _ensureTickerRunning();
  }

  void onSelectedIndexUpdated(
    int newSelectedIndex, {
    bool skipSpring = false,
  }) {
    if (_pendingSnapTarget == newSelectedIndex) {
      _pendingSnapTarget = null;
      return;
    }
    _pendingSnapTarget = null;
    if (!isInteracting && (!skipSpring || _programmaticTapInFlight)) {
      launchSpringTo(newSelectedIndex.toDouble());
    }
  }

  void _beginInteractionAt(double dx, {double rawDy = 0.0}) {
    if (slotRects.isEmpty) return;
    final pos = continuousPosAtX(dx);
    final idx = indexAtX(dx);
    final wasInteracting = isInteracting;
    isInteracting = true;
    _pendingSnapTarget = null;
    _isExternalFollowing = false;
    _externalVelocity = 0.0;
    _dragTargetPos = pos;
    _dragTargetPosY = verticalPullAtDeltaY(rawDy);
    _snapTargetPos = idx.toDouble();
    _hoverIndex = idx;
    _lastPointerX = dx;
    _lastPointerTimeUs = DateTime.now().microsecondsSinceEpoch;
    dragVelocity = 0.0;

    if (!_liquidGlassEnabled) {
      _stopPhysicsTicker();
      if (pillAnim.isAnimating) pillAnim.stop(canceled: true);
      pillAnim.value = pos;
      _renderedPos = pos;
      if (offsetYAnim.value != 0.0) offsetYAnim.value = 0.0;
      if (!wasInteracting) {
        HapticFeedback.selectionClick();
        onScheduleUpdate();
      }
      return;
    }

    if (!wasInteracting) {
      HapticFeedback.selectionClick();
      pressAnim.forward();
      onScheduleUpdate();
      _ensureTickerRunning();
    }
  }

  void _updateInteractionAt(double dx, {double rawDy = 0.0}) {
    if (slotRects.isEmpty) return;
    if (!isInteracting) {
      _beginInteractionAt(dx, rawDy: rawDy);
      return;
    }
    final pos = continuousPosAtX(dx);
    final nextHover = indexAtX(dx);
    if (nextHover != _hoverIndex) {
      _hoverIndex = nextHover;
      HapticFeedback.selectionClick();
      onScheduleUpdate();
    }
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (_lastPointerX != null && _lastPointerTimeUs > 0) {
      final dtSec =
          ((nowUs - _lastPointerTimeUs) / 1000000.0).clamp(0.004, 0.05);
      final movePx = (dx - _lastPointerX!).abs();
      if (movePx < 0.35) {
        dragVelocity *= 0.55;
      } else {
        final prevPos = continuousPosAtX(_lastPointerX!);
        final instSlotVel = ((pos - prevPos) / dtSec).clamp(-18.0, 18.0);
        dragVelocity = (dragVelocity * 0.45) + (instSlotVel * 0.55);
      }
    }
    _lastPointerX = dx;
    _lastPointerTimeUs = nowUs;
    _dragTargetPos = pos;
    _dragTargetPosY = verticalPullAtDeltaY(rawDy);
    if (!_liquidGlassEnabled) {
      _stopPhysicsTicker();
      if (pillAnim.isAnimating) pillAnim.stop(canceled: true);
      pillAnim.value = pos;
      _renderedPos = pos;
      if (offsetYAnim.value != 0.0) offsetYAnim.value = 0.0;
      return;
    }
    _ensureTickerRunning();
  }

  void _endInteractionAndSnap({
    required int currentSelectedIndex,
    required ValueChanged<int>? onSelected,
    int? forcedIndex,
    double? releaseVelocity,
    double? releaseVelocityY,
  }) {
    final maxIdx = slotRects.isEmpty ? 0 : slotRects.length - 1;
    final targetIdx = (forcedIndex ?? _hoverIndex).clamp(0, maxIdx);
    final leftoverVel =
        (releaseVelocity != null && releaseVelocity.abs() > dragVelocity.abs())
            ? releaseVelocity
            : dragVelocity.clamp(-8.0, 8.0);
    final leftoverVelY = releaseVelocityY != null
        ? (releaseVelocityY * 0.25).clamp(-180.0, 180.0)
        : null;
    final switchingTab = targetIdx != currentSelectedIndex && onSelected != null;

    isInteracting = false;
    _dragTargetPosY = 0.0;
    _lastPointerX = null;
    _lastPointerTimeUs = 0;
    _isExternalFollowing = false;
    _externalVelocity = 0.0;
    _pageDragVelocity = 0.0;
    _lastPageSample = null;
    _lastPageSampleUs = 0;

    if (switchingTab) {
      _pendingSnapTarget = targetIdx;
      _programmaticTapInFlight = true;
      _suppressExternalUntilScrollEnd = true;
    }

    if (_liquidGlassEnabled || pressAnim.value > 0.0) {
      pressAnim.reverse();
    }

    // Launch the snap spring directly from the released drag position to
    // targetIdx before notifying the parent/PageController so synchronous or
    // ticker-first PageController updates cannot snap the pill backward.
    launchSpringTo(
      targetIdx.toDouble(),
      initialVelocity: _liquidGlassEnabled ? leftoverVel : null,
      initialVelocityY: _liquidGlassEnabled ? leftoverVelY : null,
    );
    onScheduleUpdate();

    if (switchingTab) {
      onSelected(targetIdx);
      _scheduleExternalSuppressionCleanupIfIdle();
    }
  }

  Widget wrapGestureDetector({
    required Widget child,
    required bool enabled,
    required int currentSelectedIndex,
    required ValueChanged<int>? onSelected,
  }) {
    if (!enabled) return child;
    if (!_liquidGlassEnabled) {
      // Material 3 mode supports tap selection only - press-and-hold grab and
      // horizontal/2D drag are strictly exclusive to Liquid Glass mode.
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(),
            (instance) {
              instance.onTapUp = (details) {
                final targetIdx = indexAtX(details.localPosition.dx);
                HapticFeedback.selectionClick();
                if (targetIdx != currentSelectedIndex && onSelected != null) {
                  _programmaticTapInFlight = true;
                  _suppressExternalUntilScrollEnd = true;
                  _isExternalFollowing = false;
                  _externalVelocity = 0.0;
                  _pendingSnapTarget = targetIdx;
                  launchSpringTo(targetIdx.toDouble());
                  onSelected(targetIdx);
                  _scheduleExternalSuppressionCleanupIfIdle();
                } else {
                  launchSpringTo(targetIdx.toDouble());
                }
              };
            },
          ),
        },
        child: child,
      );
    }
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _downGlobalPos = event.position;
      },
      onPointerMove: (event) {
        if (!isInteracting || _longPressActive || _horizontalDragActive) {
          return;
        }
        final rawDy = _downGlobalPos != null
            ? (event.position.dy - _downGlobalPos!.dy)
            : 0.0;
        _updateInteractionAt(event.localPosition.dx, rawDy: rawDy);
      },
      onPointerUp: (_) {
        _downGlobalPos = null;
        if (isInteracting && !_longPressActive && !_horizontalDragActive) {
          _endInteractionAndSnap(
            currentSelectedIndex: currentSelectedIndex,
            onSelected: onSelected,
          );
        }
      },
      onPointerCancel: (_) {
        _downGlobalPos = null;
        if (isInteracting && !_longPressActive && !_horizontalDragActive) {
          _endInteractionAndSnap(
            currentSelectedIndex: currentSelectedIndex,
            onSelected: onSelected,
          );
        }
      },
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
            () => TapGestureRecognizer(),
            (instance) {
              instance.onTapUp = (details) {
                final targetIdx = indexAtX(details.localPosition.dx);
                triggerRippleAtLocalDx(details.localPosition.dx);
                if (isInteracting) {
                  _endInteractionAndSnap(
                    currentSelectedIndex: currentSelectedIndex,
                    onSelected: onSelected,
                    forcedIndex: targetIdx,
                  );
                } else {
                  HapticFeedback.selectionClick();
                  if (targetIdx != currentSelectedIndex && onSelected != null) {
                    _programmaticTapInFlight = true;
                    _suppressExternalUntilScrollEnd = true;
                    _isExternalFollowing = false;
                    _externalVelocity = 0.0;
                    _pendingSnapTarget = targetIdx;
                    launchSpringTo(targetIdx.toDouble());
                    onSelected(targetIdx);
                    _scheduleExternalSuppressionCleanupIfIdle();
                  } else {
                    launchSpringTo(targetIdx.toDouble());
                  }
                }
                _downGlobalPos = null;
              };
            },
          ),
          LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<
              LongPressGestureRecognizer>(
            () => LongPressGestureRecognizer(
              duration: const Duration(milliseconds: 90),
            ),
            (instance) {
              instance.onLongPressStart = (details) {
                _longPressActive = true;
                final rawDy = _downGlobalPos != null
                    ? (details.globalPosition.dy - _downGlobalPos!.dy)
                    : 0.0;
                _beginInteractionAt(details.localPosition.dx, rawDy: rawDy);
              };
              instance.onLongPressMoveUpdate = (details) {
                final rawDy = _downGlobalPos != null
                    ? (details.globalPosition.dy - _downGlobalPos!.dy)
                    : 0.0;
                _updateInteractionAt(details.localPosition.dx, rawDy: rawDy);
              };
              instance.onLongPressEnd = (details) {
                _longPressActive = false;
                if (!_horizontalDragActive && isInteracting) {
                  _endInteractionAndSnap(
                    currentSelectedIndex: currentSelectedIndex,
                    onSelected: onSelected,
                    releaseVelocityY: details.velocity.pixelsPerSecond.dy,
                  );
                }
              };
              instance.onLongPressCancel = () {
                _longPressActive = false;
              };
            },
          ),
          HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<
              HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(),
            (instance) {
              instance.onStart = (details) {
                _horizontalDragActive = true;
                _beginInteractionAt(details.localPosition.dx, rawDy: 0.0);
              };
              instance.onUpdate = (details) {
                _updateInteractionAt(details.localPosition.dx, rawDy: 0.0);
              };
              instance.onEnd = (details) {
                _horizontalDragActive = false;
                final totalWidth = slotRects.isEmpty
                    ? 280.0
                    : (slotRects.last.right - slotRects.first.left);
                final avgSlotW = math.max(
                  24.0,
                  totalWidth / math.max(1, slotRects.length),
                );
                final releaseSlotVel =
                    (details.velocity.pixelsPerSecond.dx / avgSlotW)
                        .clamp(-10.0, 10.0);
                if (!_longPressActive && isInteracting) {
                  _endInteractionAndSnap(
                    currentSelectedIndex: currentSelectedIndex,
                    onSelected: onSelected,
                    releaseVelocity: releaseSlotVel,
                  );
                }
              };
              instance.onCancel = () {
                _horizontalDragActive = false;
                if (!_longPressActive && isInteracting) {
                  _endInteractionAndSnap(
                    currentSelectedIndex: currentSelectedIndex,
                    onSelected: onSelected,
                  );
                }
              };
            },
          ),
        },
        child: child,
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _selectedIndexProvider = null;
    detachPageController();
    _stopPhysicsTicker(canceled: true);
    _physicsTicker?.dispose();
    _physicsTicker = null;
    if (pillAnim.isAnimating) pillAnim.stop(canceled: true);
    if (pressAnim.isAnimating) pressAnim.stop(canceled: true);
    if (rippleAnim.isAnimating) rippleAnim.stop(canceled: true);
    pillAnim.dispose();
    pressAnim.dispose();
    rippleAnim.dispose();
    offsetYAnim.dispose();
  }
}

mixin _LiquidGlassTrackMixin<T extends StatefulWidget> on State<T> {
  SettingsProvider? _settingsProvider;

  bool? get explicitLiquidGlassEnabled;
  LiquidGlassMode? get explicitLiquidGlassMode => null;
  _LiquidInteractivePhysics get trackPhysics;

  bool get resolvedLiquidGlassEnabled =>
      explicitLiquidGlassEnabled ??
      _settingsProvider?.prefs.liquidGlassEnabled ??
      true;

  LiquidGlassMode get resolvedLiquidGlassMode =>
      explicitLiquidGlassMode ??
      _settingsProvider?.prefs.liquidGlassMode ??
      UserProfilePrefs.activeLiquidGlassMode;

  void syncLiquidGlassMode({bool notify = false}) {
    final enabled = resolvedLiquidGlassEnabled;
    final mode = resolvedLiquidGlassMode;
    final changed = trackPhysics.liquidGlassEnabled != enabled ||
        trackPhysics.liquidGlassMode != mode;
    trackPhysics.setLiquidGlassEnabled(enabled);
    trackPhysics.setLiquidGlassMode(mode);
    if (changed && notify && mounted) {
      setState(() {});
    }
  }

  void _handleSettingsChanged() => syncLiquidGlassMode(notify: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = AppProvidersScope.maybeOf(context)?.settings;
    if (_settingsProvider != nextProvider) {
      _settingsProvider?.removeListener(_handleSettingsChanged);
      _settingsProvider = nextProvider;
      _settingsProvider?.addListener(_handleSettingsChanged);
    }
    syncLiquidGlassMode(notify: false);
  }

  @override
  void dispose() {
    _settingsProvider?.removeListener(_handleSettingsChanged);
    super.dispose();
  }
}

/// Underdamped liquid spring pill track (~400ms settling + velocity-driven
/// horizontal stretch / vertical squish + optional press-and-hold Liquid Glass
/// magnification and continuous finger sliding), falling back to a clean
/// Material 3 linear/cubic sliding track when [liquidGlassEnabled] is `false`.
class LiquidSpringPillTrack extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final double height;
  final double? pillWidth;
  final double pillHeight;
  final PageController? pageController;
  final bool ignorePageController;
  final Clip clipBehavior;
  final BorderRadius? clipBorderRadius;
  final ValueChanged<int>? onSelected;
  final double pressScale;
  final bool? liquidGlassEnabled;
  final Widget Function(BuildContext context, double velocity) pillBuilder;
  final Widget Function(
    BuildContext context,
    double velocity,
    double pressProgress,
  )? interactivePillBuilder;
  final Widget Function(
    BuildContext context,
    int index,
    double activeProgress,
  ) itemBuilder;

  const LiquidSpringPillTrack({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.height,
    this.pillWidth,
    double? pillHeight,
    this.pageController,
    this.ignorePageController = false,
    this.clipBehavior = Clip.none,
    this.clipBorderRadius,
    this.onSelected,
    this.pressScale = 1.12,
    this.liquidGlassEnabled,
    required this.pillBuilder,
    this.interactivePillBuilder,
    required this.itemBuilder,
  }) : pillHeight = pillHeight ?? height;

  @override
  State<LiquidSpringPillTrack> createState() => _LiquidSpringPillTrackState();
}

class _LiquidSpringPillTrackState extends State<LiquidSpringPillTrack>
    with TickerProviderStateMixin, _LiquidGlassTrackMixin {
  late final _LiquidInteractivePhysics _physics;

  @override
  bool? get explicitLiquidGlassEnabled => widget.liquidGlassEnabled;

  @override
  _LiquidInteractivePhysics get trackPhysics => _physics;

  @override
  void initState() {
    super.initState();
    _physics = _LiquidInteractivePhysics(
      vsync: this,
      initialIndex: widget.selectedIndex,
      liquidGlassEnabled: widget.liquidGlassEnabled ?? true,
      onScheduleUpdate: () {
        if (mounted) setState(() {});
      },
    );
    _physics.attachPageController(
      controller: widget.pageController,
      itemCount: widget.itemCount,
      ignore: widget.ignorePageController,
      selectedIndexProvider: () => widget.selectedIndex,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidSpringPillTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncLiquidGlassMode(notify: false);
    _physics.attachPageController(
      controller: widget.pageController,
      itemCount: widget.itemCount,
      ignore: widget.ignorePageController,
      selectedIndexProvider: () => widget.selectedIndex,
    );
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final pc = widget.pageController;
      final isUserSwiping = !widget.ignorePageController &&
          !_physics.isSuppressingExternal &&
          pc != null &&
          pc.hasClients &&
          pc.position.isScrollingNotifier.value;
      _physics.onSelectedIndexUpdated(
        widget.selectedIndex,
        skipSpring: isUserSwiping,
      );
    }
  }

  @override
  void dispose() {
    _physics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topOffset = (widget.height - widget.pillHeight) / 2;
    final liquidGlass = resolvedLiquidGlassEnabled;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWeights = List<int>.filled(widget.itemCount, 1);
          _physics.slotRects = _LiquidInteractivePhysics.buildSlotRects(
            totalWidth: constraints.maxWidth,
            pillHeight: widget.pillHeight,
            flexWeights: slotWeights,
            fixedPillWidth: widget.pillWidth,
          );

          return _physics.wrapGestureDetector(
            enabled: widget.onSelected != null,
            currentSelectedIndex: widget.selectedIndex,
            onSelected: widget.onSelected,
            child: AnimatedBuilder(
              animation: _physics.listenable,
              builder: (context, _) {
                final pos = _physics.pillAnim.value;
                final offsetY = liquidGlass ? _physics.offsetYAnim.value : 0.0;
                final pressT = liquidGlass ? _physics.pressProgress : 0.0;
                final vel = liquidGlass ? _physics.currentVelocity : 0.0;
                final dropletTransform = _physics.buildDropletTransform(
                  pos: pos,
                  pressScale: liquidGlass ? widget.pressScale : 1.0,
                  pressProgress: pressT,
                );
                final highlightBias = _physics.buildHighlightBias(pos: pos);
                final pillRect = _physics.interpolatedPillRect(
                  pos,
                  topOffset: topOffset + offsetY,
                );

                final stack = Stack(
                  alignment: Alignment.center,
                  clipBehavior:
                      liquidGlass ? widget.clipBehavior : Clip.hardEdge,
                  children: [
                    Positioned(
                      left: pillRect.left,
                      top: pillRect.top,
                      width: pillRect.width,
                      height: pillRect.height,
                      child: IgnorePointer(
                        child: Transform(
                          transform: dropletTransform,
                          alignment: Alignment.center,
                          child: _LiquidPillMotionScope(
                            highlightBias: highlightBias,
                            mode: resolvedLiquidGlassMode,
                            rippleProgress: _physics.rippleAnim.value,
                            rippleOrigin: _physics.rippleOrigin,
                            child: widget.interactivePillBuilder != null
                                ? widget.interactivePillBuilder!(
                                    context,
                                    vel,
                                    pressT,
                                  )
                                : widget.pillBuilder(context, vel),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(widget.itemCount, (idx) {
                        final activeProgress = (1.0 - (pos - idx).abs())
                            .clamp(0.0, 1.0);
                        return Expanded(
                          child: widget.itemBuilder(context, idx, activeProgress),
                        );
                      }),
                    ),
                  ],
                );

                if (widget.clipBorderRadius != null) {
                  return RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: widget.clipBorderRadius!,
                      child: stack,
                    ),
                  );
                }
                return RepaintBoundary(child: stack);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Segment descriptor for [LiquidBubbleTabBar].
class LiquidBubbleTabItem {
  final String label;
  final String? subLabel;
  final IconData? icon;
  final Key? key;
  final bool isHighlighted;

  const LiquidBubbleTabItem({
    required this.label,
    this.subLabel,
    this.icon,
    this.key,
    this.isHighlighted = false,
  });
}

/// Shared non-scrolling full-width segmented tab/filter bar supporting both:
/// - **Liquid Glass ON:** 2D fluid droplet stretch/squash/tilt, elastic ~15px
///   edge rubber-band overscroll (`Clip.none`), press-and-hold `1.12x`
///   magnification, optical refraction highlight, and translucent pill surface.
/// - **Liquid Glass OFF:** clean Material 3 tonal pill (`secondaryContainer` /
///   `onSecondaryContainer`) inside an opaque M3 track sliding smoothly via
///   `~220ms` `Curves.easeOutCubic` within strict track bounds.
class LiquidBubbleTabBar extends StatefulWidget {
  final List<LiquidBubbleTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final EdgeInsetsGeometry padding;
  final double height;
  final double fontSize;
  final EdgeInsetsGeometry itemPadding;
  final double pressScale;
  final PageController? pageController;
  final double pageOffset;
  final bool ignorePageController;
  final bool equalFlex;
  final bool? liquidGlassEnabled;

  const LiquidBubbleTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.height = 42,
    this.fontSize = 13,
    this.itemPadding = const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    this.pressScale = 1.12,
    this.pageController,
    this.pageOffset = 0.0,
    this.ignorePageController = false,
    this.equalFlex = false,
    this.liquidGlassEnabled,
  });

  @override
  State<LiquidBubbleTabBar> createState() => _LiquidBubbleTabBarState();
}

class _LiquidBubbleTabBarState extends State<LiquidBubbleTabBar>
    with TickerProviderStateMixin, _LiquidGlassTrackMixin {
  late final _LiquidInteractivePhysics _physics;

  @override
  bool? get explicitLiquidGlassEnabled => widget.liquidGlassEnabled;

  @override
  _LiquidInteractivePhysics get trackPhysics => _physics;

  static int _flexForItem(LiquidBubbleTabItem item) {
    final labelUnits = item.label.runes.length * 10;
    final subUnits = item.subLabel != null ? item.subLabel!.runes.length * 7 : 0;
    final iconUnits = item.icon != null ? 32 : 0;
    return (labelUnits + subUnits + iconUnits + 18).clamp(90, 260);
  }

  @override
  void initState() {
    super.initState();
    _physics = _LiquidInteractivePhysics(
      vsync: this,
      initialIndex: widget.selectedIndex,
      liquidGlassEnabled: widget.liquidGlassEnabled ?? true,
      onScheduleUpdate: () {
        if (mounted) setState(() {});
      },
    );
    _physics.attachPageController(
      controller: widget.pageController,
      itemCount: widget.items.length,
      pageOffset: widget.pageOffset,
      ignore: widget.ignorePageController,
      selectedIndexProvider: () => widget.selectedIndex,
    );
  }

  @override
  void didUpdateWidget(covariant LiquidBubbleTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncLiquidGlassMode(notify: false);
    _physics.attachPageController(
      controller: widget.pageController,
      itemCount: widget.items.length,
      pageOffset: widget.pageOffset,
      ignore: widget.ignorePageController,
      selectedIndexProvider: () => widget.selectedIndex,
    );
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final pc = widget.pageController;
      final isUserSwiping = !widget.ignorePageController &&
          !_physics.isSuppressingExternal &&
          pc != null &&
          pc.hasClients &&
          pc.position.isScrollingNotifier.value;
      _physics.onSelectedIndexUpdated(
        widget.selectedIndex,
        skipSpring: isUserSwiping,
      );
    } else if (oldWidget.items.length != widget.items.length) {
      final maxIdx = math.max(0, widget.items.length - 1).toDouble();
      _physics.clampPositionToMax(maxIdx);
    }
  }

  @override
  void dispose() {
    _physics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final liquidGlass = resolvedLiquidGlassEnabled;
    final activeTextColor = liquidGlass
        ? (isDark
            ? Colors.white
            : Color.lerp(scheme.primary, const Color(0xFF0F172A), 0.35)!)
        : scheme.onSecondaryContainer;
    final inactiveTextColor = liquidGlass
        ? (isDark
            ? Colors.white.withValues(alpha: 0.72)
            : const Color(0xFF64748B))
        : scheme.onSurfaceVariant;
    final flexWeights = widget.equalFlex
        ? List<int>.filled(widget.items.length, 1)
        : [for (final item in widget.items) _flexForItem(item)];
    final pillHeight = math.max(24.0, widget.height - 8.0);

    return RepaintBoundary(
      child: Padding(
        padding: widget.padding,
        child: Container(
          height: widget.height,
          clipBehavior: liquidGlass ? Clip.none : Clip.hardEdge,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: liquidGlass
                ? (isDark
                    ? scheme.surfaceContainerHigh.withValues(alpha: 0.72)
                    : Colors.white.withValues(alpha: 0.88))
                : (isDark
                    ? scheme.surfaceContainer
                    : scheme.surfaceContainer),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: liquidGlass
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.06))
                  : scheme.outlineVariant,
            ),
            boxShadow: !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _physics.slotRects = _LiquidInteractivePhysics.buildSlotRects(
                totalWidth: constraints.maxWidth,
                pillHeight: pillHeight,
                flexWeights: flexWeights,
              );

              return _physics.wrapGestureDetector(
                enabled: true,
                currentSelectedIndex: widget.selectedIndex,
                onSelected: widget.onSelected,
                child: AnimatedBuilder(
                  animation: _physics.listenable,
                  builder: (context, _) {
                    final pos = _physics.pillAnim.value;
                    final offsetY =
                        liquidGlass ? _physics.offsetYAnim.value : 0.0;
                    final pressT = liquidGlass ? _physics.pressProgress : 0.0;
                    final dropletTransform = _physics.buildDropletTransform(
                      pos: pos,
                      pressScale: liquidGlass ? widget.pressScale : 1.0,
                      pressProgress: pressT,
                    );
                    final highlightBias = _physics.buildHighlightBias(pos: pos);
                    final pillRect = _physics.interpolatedPillRect(
                      pos,
                      topOffset: offsetY,
                    );
                    final hoverIdx = _physics.activeHoverIndex(
                      widget.selectedIndex,
                    );

                    return Stack(
                      clipBehavior: liquidGlass ? Clip.none : Clip.hardEdge,
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned(
                          left: pillRect.left,
                          top: pillRect.top,
                          width: pillRect.width,
                          height: pillRect.height,
                          child: IgnorePointer(
                            child: Transform(
                              transform: dropletTransform,
                              alignment: Alignment.center,
                              child: _LiquidPillMotionScope(
                                highlightBias: highlightBias,
                                mode: resolvedLiquidGlassMode,
                                rippleProgress: _physics.rippleAnim.value,
                                rippleOrigin: _physics.rippleOrigin,
                                child: liquidGlass
                                    ? LiquidGlassPillSurface(
                                        pressProgress: pressT,
                                        highlightBias: highlightBias,
                                        mode: resolvedLiquidGlassMode,
                                      )
                                    : const Material3TonalPillSurface(),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(widget.items.length, (idx) {
                            final item = widget.items[idx];
                            final selected = hoverIdx == idx;
                            final activeProgress = (1.0 - (pos - idx).abs())
                                .clamp(0.0, 1.0);
                            final fgColor = Color.lerp(
                              inactiveTextColor,
                              activeTextColor,
                              activeProgress,
                            )!;

                            return Expanded(
                              flex: flexWeights[idx],
                              child: KeyedSubtree(
                                key: item.key,
                                child: Container(
                                  height: pillHeight,
                                  margin: item.isHighlighted
                                      ? const EdgeInsets.symmetric(
                                          horizontal: 1.5,
                                          vertical: 1.0,
                                        )
                                      : null,
                                  decoration: item.isHighlighted
                                      ? BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          color: scheme.primary.withValues(
                                            alpha: (0.09 *
                                                    (1.0 -
                                                        activeProgress * 0.6))
                                                .clamp(0.0, 0.12),
                                          ),
                                          border: Border.all(
                                            color: scheme.primary.withValues(
                                              alpha: (0.50 *
                                                      (1.0 -
                                                          activeProgress *
                                                              0.65))
                                                  .clamp(0.14, 0.55),
                                            ),
                                            width: 1.15,
                                          ),
                                          boxShadow: activeProgress < 0.85
                                              ? [
                                                  BoxShadow(
                                                    color: scheme.primary
                                                        .withValues(
                                                      alpha: 0.16 *
                                                          (1.0 -
                                                              activeProgress),
                                                    ),
                                                    blurRadius: 8,
                                                    spreadRadius: 0,
                                                  ),
                                                ]
                                              : null,
                                        )
                                      : null,
                                  padding: widget.itemPadding,
                                  alignment: Alignment.center,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (item.icon != null) ...[
                                          Icon(
                                            item.icon,
                                            size: 14,
                                            color: fgColor,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          item.label,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(
                                            fontSize: widget.fontSize,
                                            fontWeight: selected
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                            color: fgColor,
                                          ),
                                        ),
                                        if (item.subLabel != null) ...[
                                          const SizedBox(width: 2.5),
                                          Text(
                                            item.subLabel!,
                                            maxLines: 1,
                                            softWrap: false,
                                            style: TextStyle(
                                              fontSize: math.max(
                                                9.5,
                                                widget.fontSize - 1.8,
                                              ),
                                              fontWeight: selected
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: liquidGlass
                                                  ? fgColor.withValues(
                                                      alpha: fgColor.a *
                                                          (0.72 +
                                                              (0.20 *
                                                                  activeProgress)),
                                                    )
                                                  : fgColor,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Custom 120Hz-ready Shared-Axis / Predictive-Back style page route transition
/// using `Curves.easeOutCubic` / `Curves.easeInOutCubic` (280ms forward, 240ms
/// reverse) on Android/desktop and native Cupertino interactive edge-swipe
/// transitions on iOS.
class SmoothSharedAxisRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  final Widget page;

  SmoothSharedAxisRoute({
    required this.page,
    super.settings,
  });

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Duration get transitionDuration => isIOSPlatform
      ? super.transitionDuration
      : const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => isIOSPlatform
      ? super.reverseTransitionDuration
      : const Duration(milliseconds: 240);

  @override
  Widget buildContent(BuildContext context) => page;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    if (isIOSPlatform) {
      return super.canTransitionTo(nextRoute);
    }
    return nextRoute is PageRoute && !nextRoute.fullscreenDialog;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (isIOSPlatform) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return const SmoothSharedAxisTransitionsBuilder().buildTransitions<T>(
      this,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Custom PageTransitionsBuilder so all standard routes use smooth shared-axis
/// slide + subtle scale fade transitions instead of abrupt platform cuts.
class SmoothSharedAxisTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothSharedAxisTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final primaryCurved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.05, 0.0),
        end: Offset.zero,
      ).animate(primaryCurved),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(primaryCurved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(primaryCurved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 0.97).animate(secondaryCurved),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Tactile scale-bounce wrapper that shrinks to [pressedScale] (0.96) on tap
/// down and springs back to 1.0 on release with `HapticFeedback.lightImpact()`.
class TactileBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final bool enableHaptics;

  const TactileBounce({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.borderRadius,
    this.enableHaptics = true,
  });

  @override
  State<TactileBounce> createState() => _TactileBounceState();
}

class _TactileBounceState extends State<TactileBounce> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _isPressed ? 105 : 190),
        curve: _isPressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Smoothly animates floating-point or integer number rollups (grade averages,
/// ghost simulator projected averages, countdown minutes) using
/// [TweenAnimationBuilder] and `Curves.easeOutCubic`.
class AnimatedNumberText extends StatelessWidget {
  final double value;
  final int fractionDigits;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const AnimatedNumberText({
    super.key,
    required this.value,
    this.fractionDigits = 2,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 360),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedVal, _) {
        final formatted = fractionDigits == 0
            ? animatedVal.round().toString()
            : animatedVal.toStringAsFixed(fractionDigits);
        return Text(
          '$prefix$formatted$suffix',
          style: style,
        );
      },
    );
  }
}

/// Lightweight, GPU-friendly one-shot entrance animation (`240ms`,
/// `Curves.easeOutCubic`, fade `0.0 -> 1.0` + `14px` upward translation with a
/// `35ms` stagger for initial visible items).
///
/// Runs at most once per initial load and never re-triggers during vertical
/// scrolling or tab switching. Once completed, renders [child] directly with
/// zero compositing overhead.
class StaggeredEntranceItem extends StatefulWidget {
  final Widget child;
  final int index;
  final bool enabled;
  final int stepMs;
  final int maxStaggerIndex;
  final double slideOffsetPx;
  final int durationMs;

  const StaggeredEntranceItem({
    super.key,
    required this.child,
    required this.index,
    this.enabled = true,
    this.stepMs = 35,
    this.maxStaggerIndex = 8,
    this.slideOffsetPx = 14.0,
    this.durationMs = 240,
  });

  @override
  State<StaggeredEntranceItem> createState() => _StaggeredEntranceItemState();
}

class _StaggeredEntranceItemState extends State<StaggeredEntranceItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curved;
  bool _hasAnimated = false;
  bool _completed = true;

  @override
  void initState() {
    super.initState();
    if (widget.enabled && widget.index <= widget.maxStaggerIndex) {
      _startEntrance();
    }
  }

  @override
  void didUpdateWidget(covariant StaggeredEntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled &&
        !oldWidget.enabled &&
        !_hasAnimated &&
        widget.index <= widget.maxStaggerIndex) {
      _startEntrance();
    }
  }

  void _startEntrance() {
    _hasAnimated = true;
    _completed = false;
    final effectiveIdx = widget.index.clamp(0, widget.maxStaggerIndex);
    final delayMs = effectiveIdx * widget.stepMs;
    final totalMs = delayMs + widget.durationMs;

    _curved?.dispose();
    _controller?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _controller = ctrl;
    final beginFraction =
        totalMs > 0 ? (delayMs / totalMs).clamp(0.0, 0.92) : 0.0;
    _curved = CurvedAnimation(
      parent: ctrl,
      curve: Interval(beginFraction, 1.0, curve: Curves.easeOutCubic),
    );
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _completed = true);
      }
    });
    ctrl.forward();
  }

  @override
  void dispose() {
    _curved?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_completed || _curved == null) {
      return widget.child;
    }
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _curved!,
        child: AnimatedBuilder(
          animation: _curved!,
          child: widget.child,
          builder: (context, child) {
            final dy =
                (1.0 - _curved!.value.clamp(0.0, 1.0)) * widget.slideOffsetPx;
            return Transform.translate(
              offset: Offset(0.0, dy),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// Extension applying the 120fps one-shot staggered fade (`0.0 -> 1.0`) +
/// `14px` upward translation (`240ms`, `Curves.easeOutCubic`, `35ms` stagger).
extension StaggeredListEntrance on Widget {
  Widget staggeredEntrance(
    int index, {
    Key? animationKey,
    bool enabled = true,
    int stepMs = 35,
    int maxStaggerIndex = 8,
  }) {
    return StaggeredEntranceItem(
      key: animationKey,
      index: index,
      enabled: enabled,
      stepMs: stepMs,
      maxStaggerIndex: maxStaggerIndex,
      child: this,
    );
  }
}

class _SubTabDragTracker {
  int dragStartPage = 0;
  double? dragStartPixels;
  bool userControlledScroll = false;
  bool isUserDragging = false;
}

class _SubTabPageScrollPhysics extends PageScrollPhysics {
  final _SubTabDragTracker tracker;
  final double minSwipeDistancePx;

  const _SubTabPageScrollPhysics({
    required this.tracker,
    this.minSwipeDistancePx = 48.0,
    super.parent,
  });

  @override
  _SubTabPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _SubTabPageScrollPhysics(
      tracker: tracker,
      minSwipeDistancePx: minSwipeDistancePx,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if (!tracker.userControlledScroll ||
        (velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }

    final tolerance = toleranceFor(position);
    final viewport =
        position.viewportDimension > 0 ? position.viewportDimension : 1.0;
    final maxPage = math.max(0, (position.maxScrollExtent / viewport).round());
    final startPx = tracker.dragStartPixels;

    if (velocity.abs() < tolerance.velocity && startPx != null) {
      final deltaPx = position.pixels - startPx;
      if (deltaPx.abs() >= minSwipeDistancePx &&
          deltaPx.abs() < viewport * 0.95) {
        final step = deltaPx > 0 ? 1 : -1;
        final double targetPage =
            (tracker.dragStartPage + step).clamp(0, maxPage).toDouble();
        final double targetPixels = (targetPage * viewport)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
        if ((targetPixels - position.pixels).abs() < tolerance.distance &&
            velocity.abs() < tolerance.velocity) {
          return null;
        }
        return ScrollSpringSimulation(
          spring,
          position.pixels,
          targetPixels,
          velocity,
          tolerance: tolerance,
        );
      }
    }

    return super.createBallisticSimulation(position, velocity);
  }
}

class _MeasureChildHeight extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onHeight;

  const _MeasureChildHeight({
    required this.onHeight,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderMeasureChildHeight(onHeight: onHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMeasureChildHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderMeasureChildHeight extends RenderProxyBox {
  ValueChanged<double> onHeight;
  double? _lastHeight;

  _RenderMeasureChildHeight({required this.onHeight});

  @override
  void performLayout() {
    super.performLayout();
    final h = child?.size.height ?? 0.0;
    if (_lastHeight == null || (h - _lastHeight!).abs() > 0.5) {
      _lastHeight = h;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (attached) {
          onHeight(h);
        }
      });
    }
  }
}

/// Captures horizontal swipe gestures over an in-screen scroll view to switch
/// between internal sub-tabs / filter categories without switching main bottom
/// navigation destinations or fighting with vertical scrolling.
///
/// When [pageBuilder] is provided, renders a full continuous [PageView.builder]
/// synced 1:1 with [pageController] (and any paired [LiquidBubbleTabBar]).
///
/// Set [autoHeight] to `true` when embedding inside a single unified vertical
/// scroll view (e.g., Főoldal) so the [PageView] dynamically sizes itself to the
/// active page's intrinsic height while smoothly interpolating height during swipes.
class HorizontalSubTabSwipeDetector extends StatefulWidget {
  final int currentIndex;
  final int itemCount;
  final ValueChanged<int> onIndexChanged;
  final Widget child;
  final bool enabled;
  final PageController? pageController;
  final IndexedWidgetBuilder? pageBuilder;
  final ScrollPhysics? pagePhysics;
  final bool autoHeight;
  final double minAutoHeight;
  final VoidCallback? onUserDragStart;

  const HorizontalSubTabSwipeDetector({
    super.key,
    required this.currentIndex,
    required this.itemCount,
    required this.onIndexChanged,
    this.child = const SizedBox.shrink(),
    this.enabled = true,
    this.pageController,
    this.pageBuilder,
    this.pagePhysics,
    this.autoHeight = false,
    this.minAutoHeight = 320.0,
    this.onUserDragStart,
  });

  @override
  State<HorizontalSubTabSwipeDetector> createState() =>
      _HorizontalSubTabSwipeDetectorState();
}

class _HorizontalSubTabSwipeDetectorState
    extends State<HorizontalSubTabSwipeDetector>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  PageController? _internalPageController;
  final _SubTabDragTracker _dragTracker = _SubTabDragTracker();
  final Map<int, double> _pageHeights = <int, double>{};
  final ValueNotifier<int> _heightVersion = ValueNotifier<int>(0);
  int? _lastEmittedIndex;
  double _dragDx = 0.0;
  double _snapStartDx = 0.0;

  PageController? get _effectivePageController {
    if (widget.pageBuilder == null) return null;
    if (widget.pageController != null) return widget.pageController;
    return _internalPageController ??= PageController(
      initialPage:
          widget.currentIndex.clamp(0, math.max(0, widget.itemCount - 1)),
    );
  }

  @override
  void initState() {
    super.initState();
    _snapCtrl.addListener(() {
      if (!mounted) return;
      final t = Curves.easeOutCubic.transform(_snapCtrl.value);
      setState(() {
        _dragDx = _snapStartDx * (1.0 - t);
      });
    });
  }

  @override
  void didUpdateWidget(covariant HorizontalSubTabSwipeDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController &&
        widget.pageController != null) {
      _internalPageController?.dispose();
      _internalPageController = null;
    }
    if (widget.currentIndex == _lastEmittedIndex) {
      _lastEmittedIndex = null;
      return;
    }
    final ctrl = _effectivePageController;
    if (ctrl != null &&
        ctrl.hasClients &&
        oldWidget.currentIndex != widget.currentIndex &&
        !_dragTracker.userControlledScroll &&
        !_dragTracker.isUserDragging &&
        !ctrl.position.isScrollingNotifier.value) {
      final int target = widget.currentIndex
          .clamp(0, math.max<int>(0, widget.itemCount - 1))
          .toInt();
      final currentPage = ctrl.page?.round() ?? target;
      if (currentPage != target) {
        ctrl.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _internalPageController?.dispose();
    _heightVersion.dispose();
    _snapCtrl.dispose();
    super.dispose();
  }

  void _updatePageHeight(int index, double height) {
    if (!mounted) return;
    final prev = _pageHeights[index];
    if (prev == null || (prev - height).abs() > 0.5) {
      _pageHeights[index] = height;
      _heightVersion.value++;
    }
  }

  void _onDragStart(DragStartDetails details) {
    if (_snapCtrl.isAnimating) {
      _snapCtrl.stop();
    }
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!widget.enabled || widget.itemCount <= 1) return;
    final nextRaw = _dragDx + details.delta.dx;
    final atLeftEdge = widget.currentIndex <= 0 && nextRaw > 0.0;
    final atRightEdge =
        widget.currentIndex >= widget.itemCount - 1 && nextRaw < 0.0;
    final damping = (atLeftEdge || atRightEdge) ? 0.22 : 0.82;
    setState(() {
      _dragDx = (_dragDx + details.delta.dx * damping).clamp(-160.0, 160.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.enabled && widget.itemCount > 1) {
      final vx = details.velocity.pixelsPerSecond.dx;
      if (((_dragDx <= -36.0 && vx <= 80.0) || vx <= -240.0) &&
          widget.currentIndex < widget.itemCount - 1) {
        HapticFeedback.selectionClick();
        widget.onIndexChanged(widget.currentIndex + 1);
      } else if (((_dragDx >= 36.0 && vx >= -80.0) || vx >= 240.0) &&
          widget.currentIndex > 0) {
        HapticFeedback.selectionClick();
        widget.onIndexChanged(widget.currentIndex - 1);
      }
    }
    _snapBack();
  }

  void _snapBack() {
    if (_dragDx.abs() < 0.5) {
      if (_dragDx != 0.0) {
        setState(() => _dragDx = 0.0);
      }
      return;
    }
    _snapStartDx = _dragDx;
    _snapCtrl.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.itemCount <= 1) {
      return widget.pageBuilder != null
          ? widget.pageBuilder!(context, widget.currentIndex)
          : widget.child;
    }
    if (widget.pageBuilder != null) {
      final ctrl = _effectivePageController!;
      final effectivePhysics = widget.pagePhysics ??
          _SubTabPageScrollPhysics(
            tracker: _dragTracker,
            parent: const BouncingScrollPhysics(),
          );
      final pageView = NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != Axis.horizontal) {
            return false;
          }
          if (notification is ScrollStartNotification) {
            final isUserDrag = notification.dragDetails != null;
            _dragTracker.isUserDragging = isUserDrag;
            if (isUserDrag) {
              _dragTracker.userControlledScroll = true;
              _dragTracker.dragStartPixels = notification.metrics.pixels;
              final vp = notification.metrics.viewportDimension > 0
                  ? notification.metrics.viewportDimension
                  : 1.0;
              _dragTracker.dragStartPage =
                  (notification.metrics.pixels / vp)
                      .round()
                      .clamp(0, math.max(0, widget.itemCount - 1));
              widget.onUserDragStart?.call();
            } else {
              _dragTracker.userControlledScroll = false;
              _dragTracker.dragStartPixels = null;
            }
          } else if (notification is ScrollUpdateNotification) {
            if (notification.dragDetails != null &&
                !_dragTracker.userControlledScroll) {
              _dragTracker.isUserDragging = true;
              _dragTracker.userControlledScroll = true;
              _dragTracker.dragStartPixels = notification.metrics.pixels;
              final vp = notification.metrics.viewportDimension > 0
                  ? notification.metrics.viewportDimension
                  : 1.0;
              _dragTracker.dragStartPage =
                  (notification.metrics.pixels / vp)
                      .round()
                      .clamp(0, math.max(0, widget.itemCount - 1));
              widget.onUserDragStart?.call();
            } else if (notification.dragDetails == null) {
              _dragTracker.isUserDragging = false;
            }
          } else if (notification is ScrollEndNotification) {
            final wasUserScroll = _dragTracker.userControlledScroll;
            _dragTracker.isUserDragging = false;
            _dragTracker.userControlledScroll = false;
            _dragTracker.dragStartPixels = null;
            if (wasUserScroll && ctrl.hasClients) {
              final int maxIdx = math.max<int>(0, widget.itemCount - 1);
              final int settled =
                  (ctrl.page?.round() ?? widget.currentIndex).clamp(0, maxIdx).toInt();
              if (settled != widget.currentIndex) {
                _lastEmittedIndex = settled;
                HapticFeedback.selectionClick();
                widget.onIndexChanged(settled);
              }
            }
          }
          return false;
        },
        child: PageView.builder(
          controller: ctrl,
          itemCount: widget.itemCount,
          pageSnapping: widget.pagePhysics != null,
          physics: effectivePhysics,
          onPageChanged: (idx) {
            if (!_dragTracker.userControlledScroll) return;
            if (idx == widget.currentIndex) return;
            _lastEmittedIndex = idx;
            HapticFeedback.selectionClick();
            widget.onIndexChanged(idx);
          },
          itemBuilder: (ctx, idx) {
            if (!widget.autoHeight) {
              return widget.pageBuilder!(ctx, idx);
            }
            return LayoutBuilder(
              builder: (itemCtx, constraints) {
                return Align(
                  alignment: Alignment.topCenter,
                  child: OverflowBox(
                    minWidth: constraints.maxWidth,
                    maxWidth: constraints.maxWidth,
                    minHeight: 0.0,
                    maxHeight: double.infinity,
                    alignment: Alignment.topCenter,
                    child: _MeasureChildHeight(
                      onHeight: (h) => _updatePageHeight(idx, h),
                      child: widget.pageBuilder!(itemCtx, idx),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );

      if (!widget.autoHeight) {
        return pageView;
      }

      return AnimatedBuilder(
        animation: Listenable.merge([ctrl, _heightVersion]),
        builder: (context, child) {
          final p = (ctrl.hasClients && ctrl.position.haveDimensions)
              ? (ctrl.page ?? widget.currentIndex.toDouble())
              : widget.currentIndex.toDouble();
          final maxIdx = math.max(0, widget.itemCount - 1);
          final lo = p.floor().clamp(0, maxIdx);
          final hi = p.ceil().clamp(0, maxIdx);
          final t = (p - lo).clamp(0.0, 1.0);
          final hLo = _pageHeights[lo] ?? widget.minAutoHeight;
          final hHi = _pageHeights[hi] ?? hLo;
          final h = math.max(
            widget.minAutoHeight,
            lerpDouble(hLo, hHi, t) ?? widget.minAutoHeight,
          );
          return SizedBox(
            height: h,
            child: child,
          );
        },
        child: pageView,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _snapBack,
      child: Transform.translate(
        offset: Offset(_dragDx, 0.0),
        child: widget.child,
      ),
    );
  }
}

/// Shared predicate for [RefreshIndicator]s wrapping a [NestedScrollView] +
/// [HorizontalSubTabSwipeDetector] (`PageView`), where the vertical inner
/// list sits at scroll depth `2` (`0` = outer, `1` = horizontal PageView,
/// `2` = active vertical tab feed).
bool nestedScrollRefreshNotificationPredicate(ScrollNotification notification) {
  return notification.metrics.axis == Axis.vertical &&
      (notification.depth == 0 ||
          notification.depth == 1 ||
          notification.depth == 2);
}

/// Adds a smooth vertical elastic overscroll stretch transform (both top and
/// bottom edges) to main scrollable screens using [BouncingScrollPhysics],
/// compensating for Android scrollables inside [NestedScrollView] / [PageView]
/// while preserving `RefreshIndicator` drag behavior.
class ElasticOverscrollStretchWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const ElasticOverscrollStretchWrapper({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<ElasticOverscrollStretchWrapper> createState() =>
      _ElasticOverscrollStretchWrapperState();
}

class _ElasticOverscrollStretchWrapperState
    extends State<ElasticOverscrollStretchWrapper> {
  double _topOverscroll = 0.0;
  double _bottomOverscroll = 0.0;

  bool _onScrollNotification(ScrollNotification notification) {
    if (!widget.enabled || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollEndNotification) {
      if (_topOverscroll != 0.0 || _bottomOverscroll != 0.0) {
        setState(() {
          _topOverscroll = 0.0;
          _bottomOverscroll = 0.0;
        });
      }
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      final metrics = notification.metrics;
      final topOver = (metrics.minScrollExtent - metrics.pixels).clamp(0.0, 260.0);
      final bottomOver = (metrics.pixels - metrics.maxScrollExtent).clamp(0.0, 260.0);
      if ((topOver - _topOverscroll).abs() > 0.5 ||
          (bottomOver - _bottomOverscroll).abs() > 0.5 ||
          (topOver == 0.0 && _topOverscroll != 0.0) ||
          (bottomOver == 0.0 && _bottomOverscroll != 0.0)) {
        setState(() {
          _topOverscroll = topOver;
          _bottomOverscroll = bottomOver;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isTop = _topOverscroll >= _bottomOverscroll;
    final activeOver = isTop ? _topOverscroll : _bottomOverscroll;
    final stretchY = activeOver <= 0.5
        ? 1.0
        : 1.0 + ((activeOver / (activeOver + 240.0)) * 0.055);
    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: Transform(
        alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
        transform: Matrix4.diagonal3Values(1.0, stretchY, 1.0),
        child: widget.child,
      ),
    );
  }
}
