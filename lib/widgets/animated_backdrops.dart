import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../services/token_storage_service.dart';

/// Mutable wave slot stored in a fixed-size ring buffer so interactive fluid
/// ripples never allocate during pointer input or 120Hz painting.
class TouchRippleWave {
  bool active = false;
  double normX = 0.5;
  double normY = 0.5;
  double age = 0.0;
  double maxDuration = 1.85;
  double strength = 1.0;

  void set({
    required double x,
    required double y,
    double duration = 1.85,
    double rippleStrength = 1.0,
  }) {
    active = true;
    normX = x;
    normY = y;
    age = 0.0;
    maxDuration = duration;
    strength = rippleStrength;
  }
}

/// Shared, zero-allocation coordination hub connecting the experimental
/// `Gyro Liquid Horizon` backdrop, global pointer ripples, and the floating
/// Liquid Glass navigation pill rim highlight.
class BackdropMotionCoordinator {
  BackdropMotionCoordinator._();

  /// Normalized optical light-source bias (`dx`, `dy` in `[-1, 1]`) driven by
  /// device tilt + gentle ambient drift while `Gyro Liquid Horizon` is active.
  /// Resets to `Offset.zero` whenever the mode is paused or disabled.
  static final ValueNotifier<Offset> lightBiasNotifier =
      ValueNotifier<Offset>(Offset.zero);

  static const int maxWaves = 6;
  static final List<TouchRippleWave> waves = List<TouchRippleWave>.generate(
    maxWaves,
    (_) => TouchRippleWave(),
    growable: false,
  );

  static int _nextSlot = 0;
  static int _activeGyroRefCount = 0;
  static DateTime? _lastMoveRippleAt;

  static void attachGyroLayer() {
    _activeGyroRefCount++;
  }

  static void detachGyroLayer() {
    if (_activeGyroRefCount > 0) {
      _activeGyroRefCount--;
    }
    if (_activeGyroRefCount == 0) {
      clear();
    }
  }

  /// Registers a localized fluid distortion wave in viewport coordinates.
  static void addTouchWave(
    Offset localPosition,
    Size size, {
    bool isMove = false,
    double strength = 1.0,
  }) {
    if (size.isEmpty) return;
    if (isMove) {
      final now = DateTime.now();
      if (_lastMoveRippleAt != null &&
          now.difference(_lastMoveRippleAt!).inMilliseconds < 95) {
        return;
      }
      _lastMoveRippleAt = now;
    } else {
      _lastMoveRippleAt = DateTime.now();
    }

    final nx = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final ny = (localPosition.dy / size.height).clamp(0.0, 1.0);
    waves[_nextSlot].set(
      x: nx,
      y: ny,
      duration: isMove ? 1.55 : 1.95,
      rippleStrength: strength.clamp(0.35, 1.25),
    );
    _nextSlot = (_nextSlot + 1) % maxWaves;
  }

  /// Advances active wave lifetimes inside the frame ticker.
  static void stepWaves(double dt) {
    if (dt <= 0) return;
    for (int i = 0; i < maxWaves; i++) {
      final w = waves[i];
      if (!w.active) continue;
      w.age += dt;
      if (w.age >= w.maxDuration) {
        w.active = false;
      }
    }
  }

  /// Resets light bias and deactivates any in-flight ripples.
  static void clear() {
    for (int i = 0; i < maxWaves; i++) {
      waves[i].active = false;
    }
    _lastMoveRippleAt = null;
    if (lightBiasNotifier.value != Offset.zero) {
      lightBiasNotifier.value = Offset.zero;
    }
  }
}

/// Shared continuous motion telemetry consumed directly by backdrop painters
/// via `CustomPainter(repaint: ...)` so animation frames trigger zero widget rebuilds.
class BackdropMotionState extends ChangeNotifier {
  double elapsed = 0.0;
  Offset tilt = Offset.zero;
  double pulsePhase = 0.0;

  void update({
    required double nextElapsed,
    required Offset nextTilt,
    required double nextPulsePhase,
  }) {
    elapsed = nextElapsed;
    tilt = nextTilt;
    pulsePhase = nextPulsePhase;
    notifyListeners();
  }
}

/// Shared lightweight architectural topographic contour painter.
/// Supports both static (`topographic_contour`) rendering when [motionState] is
/// omitted and living elevation contours (`topographicPulse`) at 120Hz.
class TopographicContourPainter extends CustomPainter {
  final Color lineColor;
  final double phase;
  final BackdropMotionState? motionState;

  const TopographicContourPainter({
    this.lineColor = const Color(0x0EFFFFFF),
    this.phase = 0.0,
    this.motionState,
  }) : super(repaint: motionState);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double livePhase = motionState?.pulsePhase ?? phase;
    final double t = motionState?.elapsed ?? 0.0;
    final bool isAnimated = motionState != null;

    if (isAnimated) {
      // Subtle deep architectural elevation sheen drifting across terrain ridges.
      final glowX = 0.35 + 0.28 * math.sin(t * 0.21);
      final glowY = 0.38 + 0.24 * math.cos(t * 0.17);
      final ambientPaint = Paint()
        ..shader = RadialGradient(
          center: Alignment(glowX * 2 - 1, glowY * 2 - 1),
          radius: 1.05,
          colors: const [
            Color(0x168CA4BF),
            Color(0x085A6F87),
            Colors.transparent,
          ],
          stops: const [0.0, 0.52, 1.0],
        ).createShader(Offset.zero & size);
      canvas.drawRect(Offset.zero & size, ambientPaint);
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..isAntiAlias = true;

    const ringCount = 11;
    final drift1 = isAnimated
        ? Offset(
            size.width * 0.018 * math.sin(t * 0.19),
            size.height * 0.015 * math.cos(t * 0.15),
          )
        : Offset.zero;
    final drift2 = isAnimated
        ? Offset(
            size.width * 0.016 * math.cos(t * 0.16),
            size.height * 0.014 * math.sin(t * 0.22),
          )
        : Offset.zero;

    final center1 = Offset(size.width * 0.24, size.height * 0.22) + drift1;
    final center2 = Offset(size.width * 0.82, size.height * 0.74) + drift2;
    final path = Path();

    final double pulseWave = isAnimated ? (0.5 + 0.5 * math.sin(t * 0.9)) : 0.0;

    for (int i = 1; i <= ringCount; i++) {
      final frac = i / ringCount;
      final ridgeHighlight = isAnimated
          ? (0.5 + 0.5 * math.sin(frac * math.pi * 2.5 - t * 0.85))
          : 0.0;
      paint.color = isAnimated
          ? Color.lerp(
              lineColor,
              const Color(0x28BACBE0),
              ridgeHighlight * (0.45 + 0.35 * pulseWave),
            )!
          : lineColor;
      paint.strokeWidth = isAnimated ? (0.95 + 0.45 * ridgeHighlight) : 1.0;

      final rx1 = size.width * (0.14 + frac * 0.95);
      final ry1 = size.height * (0.08 + frac * 0.56);
      path.reset();
      const steps = 42;
      for (int s = 0; s <= steps; s++) {
        final theta = (s / steps) * 2 * math.pi;
        final wobble = 1.0 +
            0.09 * math.sin(theta * 3.0 + i * 0.55 + livePhase) +
            0.05 * math.cos(theta * 5.0 - i * 0.35 - livePhase * 0.65);
        final x = center1.dx + rx1 * wobble * math.cos(theta);
        final y = center1.dy + ry1 * wobble * math.sin(theta);
        if (s == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);

      if (i <= 8) {
        final f2 = i / 8.0;
        final rx2 = size.width * (0.12 + f2 * 0.72);
        final ry2 = size.height * (0.09 + f2 * 0.45);
        path.reset();
        for (int s = 0; s <= steps; s++) {
          final theta = (s / steps) * 2 * math.pi;
          final wobble = 1.0 +
              0.08 * math.cos(theta * 3.0 - i * 0.45 - livePhase * 0.8) +
              0.04 * math.sin(theta * 4.0 + i * 0.65 + livePhase * 0.5);
          final x = center2.dx + rx2 * wobble * math.cos(theta);
          final y = center2.dy + ry2 * wobble * math.sin(theta);
          if (s == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant TopographicContourPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.phase != phase ||
      oldDelegate.motionState != motionState;
}

/// Ultra-experimental showcase backdrop: 3-layer gyroscopic optical horizon
/// with smoked amber & cool titanium refractive caustics, specular glass meniscus,
/// and interactive fluid touch waves.
class GyroLiquidHorizonPainter extends CustomPainter {
  final BackdropMotionState motionState;

  GyroLiquidHorizonPainter({required this.motionState})
      : super(repaint: motionState);

  final Paint _paint = Paint()..isAntiAlias = true;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final rect = Offset.zero & size;
    final t = motionState.elapsed;
    final tilt = motionState.tilt;
    final w = size.width;
    final h = size.height;

    final double swayX = 0.14 * math.sin(t * 0.27);
    final double swayY = 0.10 * math.cos(t * 0.21);
    final double px = (tilt.dx + swayX).clamp(-1.15, 1.15);
    final double py = (tilt.dy + swayY).clamp(-1.15, 1.15);

    // ── Layer 1: Far Obsidian Glass Strata (0.25x parallax) ──
    final double layer1X = px * 0.25;
    final double layer1Y = py * 0.25;
    final double horizonBaseY = h * (0.46 + layer1Y * 0.085);
    final double horizonSlope = h * (0.045 * layer1X);

    _paint
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment(layer1X * 0.35, -1.0),
        end: Alignment(-layer1X * 0.35, 1.0),
        colors: const [
          Color(0xFF090C11),
          Color(0xFF10151E),
          Color(0xFF1A222F),
          Color(0xFF0C1016),
          Color(0xFF07090D),
        ],
        stops: const [0.0, 0.34, 0.48, 0.62, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, _paint);

    // Subtle far horizon architectural strata hairlines
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..color = const Color(0x0EFFFFFF);
    for (int i = -1; i <= 1; i++) {
      final yOffset = horizonBaseY + i * (h * 0.075);
      canvas.drawLine(
        Offset(0, yOffset - horizonSlope * (1.0 - i * 0.2)),
        Offset(w, yOffset + horizonSlope * (1.0 - i * 0.2)),
        _paint,
      );
    }

    // ── Layer 2: Mid Refractive Caustics (0.65x parallax) ──
    final double layer2X = px * 0.65;
    final double layer2Y = py * 0.65;

    // Warm smoked amber caustic lobe
    final amberCenter = Offset(
      w * (0.28 + layer2X * 0.19 + 0.06 * math.sin(t * 0.35)),
      h * (0.43 + layer2Y * 0.13 + 0.04 * math.cos(t * 0.29)),
    );
    _paint
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 0.5,
        colors: [
          Color(0x28D4A36A),
          Color(0x14AD7C47),
          Color(0x00AD7C47),
        ],
        stops: [0.0, 0.46, 1.0],
      ).createShader(
        Rect.fromCircle(center: amberCenter, radius: math.max(w, h) * 0.46),
      );
    canvas.drawCircle(amberCenter, math.max(w, h) * 0.46, _paint);

    // Cool brushed titanium caustic lobe on opposite pole
    final titaniumCenter = Offset(
      w * (0.74 - layer2X * 0.17 + 0.05 * math.cos(t * 0.31)),
      h * (0.50 - layer2Y * 0.11 + 0.04 * math.sin(t * 0.26)),
    );
    _paint.shader = const RadialGradient(
      center: Alignment.center,
      radius: 0.5,
      colors: [
        Color(0x2692ADC9),
        Color(0x1266819E),
        Color(0x0066819E),
      ],
      stops: [0.0, 0.48, 1.0],
    ).createShader(
      Rect.fromCircle(center: titaniumCenter, radius: math.max(w, h) * 0.48),
    );
    canvas.drawCircle(titaniumCenter, math.max(w, h) * 0.48, _paint);

    // ── Layer 3: Foreground Liquid Meniscus & Specular Lens Arcs (1.15x) ──
    final double layer3X = px * 1.15;
    final double layer3Y = py * 1.15;

    final double mLeftY =
        horizonBaseY + h * (0.04 * layer3Y - 0.065 * layer3X) + 6 * math.sin(t * 0.7);
    final double mRightY =
        horizonBaseY + h * (0.04 * layer3Y + 0.065 * layer3X) - 6 * math.sin(t * 0.7);
    final double mCtrlY = horizonBaseY +
        h * (0.055 * layer3Y) +
        14 * math.cos(t * 0.53);
    final double mCtrlX = w * (0.5 + 0.14 * layer3X);

    // Refractive shadow pool below the liquid horizon
    _path
      ..reset()
      ..moveTo(0, mLeftY)
      ..quadraticBezierTo(mCtrlX, mCtrlY, w, mRightY)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    _paint
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x1E8EA7C2),
          Color(0x0D1A222E),
          Color(0x00090C10),
        ],
        stops: [0.0, 0.24, 0.85],
      ).createShader(Rect.fromLTRB(0, horizonBaseY - 40, w, h));
    canvas.drawPath(_path, _paint);

    // Specular meniscus highlight rim
    _path
      ..reset()
      ..moveTo(0, mLeftY)
      ..quadraticBezierTo(mCtrlX, mCtrlY, w, mRightY);

    final double rimCenterStop = (0.5 + px * 0.35).clamp(0.18, 0.82);
    _paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0x05FFFFFF),
          Color(0x28F2DFC6),
          Color(0x42FFFFFF),
          Color(0x22AEC4DB),
          Color(0x05FFFFFF),
        ],
        stops: [
          0.0,
          (rimCenterStop - 0.18).clamp(0.02, 0.96),
          rimCenterStop,
          (rimCenterStop + 0.18).clamp(0.04, 0.98),
          1.0,
        ],
      ).createShader(Rect.fromLTRB(0, horizonBaseY - 60, w, horizonBaseY + 60));
    canvas.drawPath(_path, _paint);

    // Subtle foreground optical lens flare arcs
    _paint
      ..strokeWidth = 1.0
      ..shader = null
      ..color = const Color(0x10F3E4CF);
    _path
      ..reset()
      ..moveTo(w * 0.08, h * (0.24 + layer3Y * 0.08))
      ..quadraticBezierTo(
        w * (0.48 + layer3X * 0.14),
        h * (0.19 - layer3Y * 0.05),
        w * 0.92,
        h * (0.29 + layer3Y * 0.06),
      );
    canvas.drawPath(_path, _paint);

    _paint.color = const Color(0x0EA9C0D8);
    _path
      ..reset()
      ..moveTo(w * 0.06, h * (0.76 - layer3Y * 0.06))
      ..quadraticBezierTo(
        w * (0.52 - layer3X * 0.12),
        h * (0.82 + layer3Y * 0.05),
        w * 0.94,
        h * (0.72 - layer3Y * 0.07),
      );
    canvas.drawPath(_path, _paint);

    // ── Interactive Touch Fluid Ripples ──
    final waves = BackdropMotionCoordinator.waves;
    for (int i = 0; i < BackdropMotionCoordinator.maxWaves; i++) {
      final wave = waves[i];
      if (!wave.active) continue;
      final progress = (wave.age / wave.maxDuration).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(progress);
      final fade = (1.0 - progress) * (1.0 - progress) * wave.strength;
      if (fade <= 0.005) continue;

      final cx = wave.normX * w;
      final cy = wave.normY * h;
      final maxRadius = math.max(w, h) * 0.42 * wave.strength;
      final r1 = 14.0 + eased * maxRadius;

      // Primary pearlescent refraction crest
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = (2.2 * (1.0 - progress * 0.6)).clamp(0.6, 2.2)
        ..color = Color.fromRGBO(236, 224, 208, (0.24 * fade).clamp(0.0, 0.32));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r1 * 2, height: r1 * 1.72),
        _paint,
      );

      // Secondary trailing cool wake
      if (progress > 0.12) {
        final r2 = r1 * 0.68;
        _paint
          ..strokeWidth = 1.2
          ..color =
              Color.fromRGBO(166, 194, 222, (0.16 * fade).clamp(0.0, 0.24));
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: r2 * 2,
            height: r2 * 1.72,
          ),
          _paint,
        );
      }

      // Soft refractive pool interior at touch point
      if (progress < 0.45) {
        final glowFade = (1.0 - progress / 0.45) * 0.14 * wave.strength;
        final glowR = 26.0 + eased * 64.0;
        _paint
          ..style = PaintingStyle.fill
          ..shader = RadialGradient(
            colors: [
              Color.fromRGBO(228, 206, 180, glowFade),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: glowR));
        canvas.drawCircle(Offset(cx, cy), glowR, _paint);
        _paint.shader = null;
      }
    }
  }

  @override
  bool shouldRepaint(covariant GyroLiquidHorizonPainter oldDelegate) =>
      oldDelegate.motionState != motionState;
}

/// Deep slate-teal water caustics with slow interference waves & light foci.
class CausticWaterPainter extends CustomPainter {
  final BackdropMotionState motionState;

  CausticWaterPainter({required this.motionState})
      : super(repaint: motionState);

  final Paint _paint = Paint()..isAntiAlias = true;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = motionState.elapsed;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // Deep studio slate-teal gradient
    _paint
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0E1A22),
          Color(0xFF0B1319),
          Color(0xFF080E13),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, _paint);

    // Soft overlapping refractive focus nodes
    for (int i = 0; i < 5; i++) {
      final seed = i * 1.37;
      final fx = w * (0.2 + 0.6 * (0.5 + 0.5 * math.sin(t * 0.23 + seed)));
      final fy = h * (0.18 + 0.64 * (0.5 + 0.5 * math.cos(t * 0.19 - seed * 0.8)));
      final r = math.max(w, h) * (0.26 + 0.06 * math.sin(t * 0.3 + i));
      _paint.shader = RadialGradient(
        colors: [
          Color.fromRGBO(154, 194, 210, 0.065 + 0.015 * math.sin(t * 0.4 + i)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(fx, fy), radius: r));
      canvas.drawCircle(Offset(fx, fy), r, _paint);
    }

    // Slow optical caustic ribbons (no neon cyan)
    _paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const bandCount = 6;
    for (int b = 0; b < bandCount; b++) {
      final baseY = h * (0.14 + (b / (bandCount - 1)) * 0.74);
      final amp = 18.0 + (b % 3) * 10.0;
      _path.reset();
      const segs = 28;
      for (int s = 0; s <= segs; s++) {
        final u = s / segs;
        final x = u * w;
        final y = baseY +
            amp * math.sin(u * math.pi * 2.2 + t * 0.42 + b * 0.9) +
            (amp * 0.45) * math.cos(u * math.pi * 3.7 - t * 0.31 + b * 1.4);
        if (s == 0) {
          _path.moveTo(x, y);
        } else {
          _path.lineTo(x, y);
        }
      }

      // Soft wide refraction halo + sharper caustic core
      _paint
        ..strokeWidth = 18.0
        ..color = const Color.fromRGBO(116, 160, 178, 0.032);
      canvas.drawPath(_path, _paint);

      _paint
        ..strokeWidth = 2.0
        ..color = const Color.fromRGBO(194, 220, 230, 0.072);
      canvas.drawPath(_path, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant CausticWaterPainter oldDelegate) =>
      oldDelegate.motionState != motionState;
}

/// Dark liquid-graphite ferrofluid lobes with brushed gunmetal rim sheen.
class FerrofluidDriftPainter extends CustomPainter {
  final BackdropMotionState motionState;

  FerrofluidDriftPainter({required this.motionState})
      : super(repaint: motionState);

  final Paint _paint = Paint()..isAntiAlias = true;
  final Path _path = Path();

  void _buildOrganicBlob(Offset center, double rx, double ry, double t, int id) {
    _path.reset();
    const steps = 36;
    for (int i = 0; i <= steps; i++) {
      final a = (i / steps) * 2 * math.pi;
      final deform = 1.0 +
          0.11 * math.sin(a * 3.0 + t * 0.55 + id * 1.9) +
          0.07 * math.cos(a * 4.0 - t * 0.41 + id * 0.7) +
          0.04 * math.sin(a * 6.0 + t * 0.29);
      final x = center.dx + rx * deform * math.cos(a);
      final y = center.dy + ry * deform * math.sin(a);
      if (i == 0) {
        _path.moveTo(x, y);
      } else {
        _path.lineTo(x, y);
      }
    }
    _path.close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = motionState.elapsed;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    _paint
      ..style = PaintingStyle.fill
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.45),
        radius: 1.2,
        colors: [
          Color(0xFF171B22),
          Color(0xFF0E1014),
          Color(0xFF090B0E),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, _paint);

    for (int id = 0; id < 3; id++) {
      final cx = w *
          (id == 0
              ? (0.34 + 0.14 * math.sin(t * 0.24))
              : id == 1
                  ? (0.70 + 0.12 * math.cos(t * 0.21))
                  : (0.48 + 0.16 * math.sin(t * 0.18 + 2.1)));
      final cy = h *
          (id == 0
              ? (0.29 + 0.10 * math.cos(t * 0.22))
              : id == 1
                  ? (0.58 + 0.11 * math.sin(t * 0.19))
                  : (0.81 + 0.08 * math.cos(t * 0.25 + 1.3)));
      final rx = w * (0.34 - id * 0.04);
      final ry = h * (0.19 - id * 0.02);

      _buildOrganicBlob(Offset(cx, cy), rx, ry, t, id);

      _paint
        ..style = PaintingStyle.fill
        ..shader = const RadialGradient(
          center: Alignment(-0.32, -0.36),
          radius: 0.9,
          colors: [
            Color(0xAA2B313D),
            Color(0xBB161920),
            Color(0xDD0A0C10),
          ],
          stops: [0.0, 0.55, 1.0],
        ).createShader(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2.3, height: ry * 2.3),
        );
      canvas.drawPath(_path, _paint);

      // Soft brushed gunmetal rim glint on lightward edge
      _paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0x36D2DCE8),
            Color(0x0C8E9CAE),
            Color(0x04000000),
          ],
        ).createShader(
          Rect.fromCenter(center: Offset(cx, cy), width: rx * 2.2, height: ry * 2.2),
        );
      canvas.drawPath(_path, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant FerrofluidDriftPainter oldDelegate) =>
      oldDelegate.motionState != motionState;
}

class _DustMote {
  final double baseX;
  final double baseY;
  final double speedY;
  final double driftAmp;
  final double driftFreq;
  final double radius;
  final double phase;

  const _DustMote({
    required this.baseX,
    required this.baseY,
    required this.speedY,
    required this.driftAmp,
    required this.driftFreq,
    required this.radius,
    required this.phase,
  });
}

/// Warm espresso-charcoal interior with diagonal studio sunbeams & drifting
/// dust motes glinting softly as they cross the light shafts.
class SunbeamDustPainter extends CustomPainter {
  final BackdropMotionState motionState;

  SunbeamDustPainter({required this.motionState})
      : super(repaint: motionState);

  static final List<_DustMote> _motes = _generateMotes();

  static List<_DustMote> _generateMotes() {
    final rng = math.Random(4207);
    return List<_DustMote>.generate(38, (_) {
      return _DustMote(
        baseX: rng.nextDouble(),
        baseY: rng.nextDouble(),
        speedY: 0.008 + rng.nextDouble() * 0.014,
        driftAmp: 0.012 + rng.nextDouble() * 0.022,
        driftFreq: 0.35 + rng.nextDouble() * 0.55,
        radius: 0.8 + rng.nextDouble() * 1.45,
        phase: rng.nextDouble() * 2 * math.pi,
      );
    }, growable: false);
  }

  final Paint _paint = Paint()..isAntiAlias = true;
  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = motionState.elapsed;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    _paint
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color(0xFF1A1714),
          Color(0xFF121110),
          Color(0xFF0C0B0A),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, _paint);

    // 4 volumetric diagonal sunbeams breathing calmly
    const beamStarts = [0.22, 0.45, 0.68, 0.88];
    const beamWidthsTop = [0.11, 0.16, 0.13, 0.09];
    for (int i = 0; i < beamStarts.length; i++) {
      final breath = 0.72 + 0.28 * math.sin(t * 0.28 + i * 1.5);
      final topX = w * (beamStarts[i] + 0.025 * math.sin(t * 0.17 + i));
      final topHalf = w * beamWidthsTop[i] * 0.5;
      final botX = topX - w * 0.38;
      final botHalf = topHalf * 2.15;

      _path
        ..reset()
        ..moveTo(topX - topHalf, -10)
        ..lineTo(topX + topHalf, -10)
        ..lineTo(botX + botHalf, h + 10)
        ..lineTo(botX - botHalf, h + 10)
        ..close();

      _paint.shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          Color.fromRGBO(242, 218, 178, 0.075 * breath),
          Color.fromRGBO(228, 198, 152, 0.032 * breath),
          Colors.transparent,
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);
      canvas.drawPath(_path, _paint);
    }

    // Sparse floating dust motes illuminated near diagonal beam envelope
    _paint.shader = null;
    for (int i = 0; i < _motes.length; i++) {
      final m = _motes[i];
      final ny = (m.baseY - t * m.speedY) % 1.0;
      final wrappedY = ny < 0 ? ny + 1.0 : ny;
      final nx = (m.baseX + m.driftAmp * math.sin(t * m.driftFreq + m.phase))
          .clamp(0.0, 1.0);

      // Diagonal corridor factor: brightest near sunbeam sweep (nx + ny*0.38 in 0.45..1.1)
      final beamCoord = nx + wrappedY * 0.38;
      final beamMask =
          (1.0 - ((beamCoord - 0.74).abs() / 0.46)).clamp(0.18, 1.0);
      final twinkle = 0.55 + 0.45 * math.sin(t * 1.15 + m.phase * 2.0);
      final alpha = (0.04 + 0.16 * beamMask * twinkle).clamp(0.02, 0.22);

      _paint.color = Color.fromRGBO(246, 224, 186, alpha);
      canvas.drawCircle(Offset(nx * w, wrappedY * h), m.radius, _paint);
    }
  }

  @override
  bool shouldRepaint(covariant SunbeamDustPainter oldDelegate) =>
      oldDelegate.motionState != motionState;
}

/// Warm analog darkroom tungsten edge light-leaks & cinema-cadence ultra-fine
/// procedural grain (zero per-frame heap allocation).
class AnalogFilmLightPainter extends CustomPainter {
  final BackdropMotionState motionState;

  AnalogFilmLightPainter({required this.motionState})
      : super(repaint: motionState);

  static const int _grainCount = 190;
  static final Float32List _unitGrainWarm = _seedUnitGrain(1984);
  static final Float32List _unitGrainShadow = _seedUnitGrain(2025);

  static Float32List _seedUnitGrain(int seed) {
    final rng = math.Random(seed);
    final coords = Float32List(_grainCount * 2);
    for (int i = 0; i < coords.length; i++) {
      coords[i] = rng.nextDouble();
    }
    return coords;
  }

  final Paint _paint = Paint()..isAntiAlias = true;
  final Float32List _scaledWarm = Float32List(_grainCount * 2);
  final Float32List _scaledShadow = Float32List(_grainCount * 2);
  Size _cachedSize = Size.zero;
  int _lastGrainFrame = -1;

  void _updateGrainBufferIfNeeded(Size size, double elapsed) {
    // 10fps tactile film grain step on top of 120fps smooth tungsten breathing
    final frameIndex = (elapsed * 10.0).floor();
    if (_cachedSize == size && _lastGrainFrame == frameIndex) return;

    _cachedSize = size;
    _lastGrainFrame = frameIndex;

    // Deterministic quasi-random offset per step without allocating Random
    final jx = ((frameIndex * 73) % 97) / 97.0;
    final jy = ((frameIndex * 41) % 89) / 89.0;

    for (int i = 0; i < _grainCount * 2; i += 2) {
      double wx = _unitGrainWarm[i] + jx;
      if (wx >= 1.0) wx -= 1.0;
      double wy = _unitGrainWarm[i + 1] + jy;
      if (wy >= 1.0) wy -= 1.0;
      _scaledWarm[i] = wx * size.width;
      _scaledWarm[i + 1] = wy * size.height;

      double sx = _unitGrainShadow[i] + jy;
      if (sx >= 1.0) sx -= 1.0;
      double sy = _unitGrainShadow[i + 1] + jx;
      if (sy >= 1.0) sy -= 1.0;
      _scaledShadow[i] = sx * size.width;
      _scaledShadow[i + 1] = sy * size.height;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = motionState.elapsed;
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    // Deep warm espresso film stock matte
    _paint
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF141110),
          Color(0xFF110F0E),
          Color(0xFF0C0A09),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, _paint);

    // Upper-left warm tungsten edge light-leak
    final leak1Breath = 0.72 + 0.28 * math.sin(t * 0.33);
    final leak1Center = Offset(
      w * (0.04 + 0.05 * math.sin(t * 0.21)),
      h * (0.14 + 0.07 * math.cos(t * 0.17)),
    );
    final leak1R = math.max(w, h) * 0.56;
    _paint.shader = RadialGradient(
      colors: [
        Color.fromRGBO(216, 134, 72, 0.145 * leak1Breath),
        Color.fromRGBO(172, 92, 46, 0.055 * leak1Breath),
        Colors.transparent,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: leak1Center, radius: leak1R));
    canvas.drawCircle(leak1Center, leak1R, _paint);

    // Lower-right subtle amber halogen bleed
    final leak2Breath = 0.70 + 0.30 * math.cos(t * 0.27 + 1.2);
    final leak2Center = Offset(
      w * (0.95 - 0.04 * math.cos(t * 0.19)),
      h * (0.82 - 0.05 * math.sin(t * 0.23)),
    );
    final leak2R = math.max(w, h) * 0.48;
    _paint.shader = RadialGradient(
      colors: [
        Color.fromRGBO(228, 168, 108, 0.105 * leak2Breath),
        Color.fromRGBO(164, 104, 58, 0.036 * leak2Breath),
        Colors.transparent,
      ],
      stops: const [0.0, 0.48, 1.0],
    ).createShader(Rect.fromCircle(center: leak2Center, radius: leak2R));
    canvas.drawCircle(leak2Center, leak2R, _paint);

    // Ultra-fine film grain using pre-allocated Float32List buffers
    _updateGrainBufferIfNeeded(size, t);
    _paint
      ..shader = null
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x0CF7EAE0);
    canvas.drawRawPoints(ui.PointMode.points, _scaledWarm, _paint);

    _paint
      ..strokeWidth = 1.1
      ..color = const Color(0x10000000);
    canvas.drawRawPoints(ui.PointMode.points, _scaledShadow, _paint);
  }

  @override
  bool shouldRepaint(covariant AnalogFilmLightPainter oldDelegate) =>
      oldDelegate.motionState != motionState;
}

/// Hosts an animated physical-optics studio backdrop inside a single
/// `RepaintBoundary`, automatically pausing tickers and hardware accelerometer
/// listeners whenever the app enters the background or tickers are disabled.
class AnimatedBackdropLayer extends StatefulWidget {
  final AnimatedBackdropPreset preset;

  const AnimatedBackdropLayer({
    super.key,
    required this.preset,
  });

  @override
  State<AnimatedBackdropLayer> createState() => _AnimatedBackdropLayerState();
}

class _AnimatedBackdropLayerState extends State<AnimatedBackdropLayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  final BackdropMotionState _motionState = BackdropMotionState();
  late CustomPainter _painter;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  bool _isForeground = true;
  bool _tickerEnabled = true;
  bool _hasLiveSensor = false;
  DateTime? _lastTickAt;

  // Filtered accelerometer gravity baseline & instantaneous smoothed tilt
  double? _restY;
  Offset _rawTargetTilt = Offset.zero;
  Offset _smoothedTilt = Offset.zero;
  double _elapsed = 0.0;
  double _pulsePhase = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..addListener(_onFrameTick);
    _painter = _buildPainterFor(widget.preset);

    if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
      BackdropMotionCoordinator.attachGyroLayer();
    }
    _syncMotionAndSensors();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.valuesOf(context).enabled;
    if (_tickerEnabled != enabled) {
      _tickerEnabled = enabled;
      _syncMotionAndSensors();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedBackdropLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preset != widget.preset) {
      if (oldWidget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
        BackdropMotionCoordinator.detachGyroLayer();
      }
      if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
        BackdropMotionCoordinator.attachGyroLayer();
      }
      _painter = _buildPainterFor(widget.preset);
      _restY = null;
      _rawTargetTilt = Offset.zero;
      _smoothedTilt = Offset.zero;
      _lastTickAt = null;
      _syncMotionAndSensors();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_isForeground != foreground) {
      _isForeground = foreground;
      _syncMotionAndSensors();
    }
  }

  bool get _shouldRun =>
      widget.preset != AnimatedBackdropPreset.off &&
      _isForeground &&
      _tickerEnabled;

  void _syncMotionAndSensors() {
    if (_shouldRun) {
      _lastTickAt = null;
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
      if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
        _startSensorIfNeeded();
      } else {
        _stopSensor();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _stopSensor();
      if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon &&
          !_isForeground) {
        BackdropMotionCoordinator.lightBiasNotifier.value = Offset.zero;
      }
    }
  }

  void _startSensorIfNeeded() {
    if (_accelSub != null) return;
    try {
      _accelSub = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (event) {
          _hasLiveSensor = true;
          _restY ??= event.y;
          // Gently adapt rest posture over ~6s so tilted holding re-centers
          _restY = _restY! + (event.y - _restY!) * 0.015;
          final dx = (-event.x / 6.0).clamp(-1.0, 1.0);
          final dy = ((event.y - _restY!) / 4.2).clamp(-1.0, 1.0);
          _rawTargetTilt = Offset(dx, dy);
        },
        onError: (_) {
          _hasLiveSensor = false;
          _stopSensor();
        },
        cancelOnError: true,
      );
    } on PlatformException {
      _hasLiveSensor = false;
      _accelSub = null;
    } catch (_) {
      _hasLiveSensor = false;
      _accelSub = null;
    }
  }

  void _stopSensor() {
    _accelSub?.cancel();
    _accelSub = null;
  }

  void _onFrameTick() {
    if (!_shouldRun) return;
    final now = DateTime.now();
    final rawDt = _lastTickAt == null
        ? (1.0 / 120.0)
        : now.difference(_lastTickAt!).inMicroseconds / 1000000.0;
    _lastTickAt = now;

    // Clamp dt so resuming after a pause never causes a visual jump
    final dt = rawDt.clamp(0.001, 0.05);
    _elapsed += dt;
    _pulsePhase = (_pulsePhase + dt * 0.36) % (2 * math.pi);

    if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
      BackdropMotionCoordinator.stepWaves(dt);

      final Offset target = _hasLiveSensor
          ? _rawTargetTilt
          : Offset(
              0.46 * math.sin(_elapsed * 0.35),
              0.34 * math.cos(_elapsed * 0.24),
            );
      final alpha = (1.0 - math.exp(-dt * 8.5)).clamp(0.0, 1.0);
      _smoothedTilt = Offset(
        _smoothedTilt.dx + (target.dx - _smoothedTilt.dx) * alpha,
        _smoothedTilt.dy + (target.dy - _smoothedTilt.dy) * alpha,
      );

      final biasX =
          (_smoothedTilt.dx * 0.92 + 0.10 * math.sin(_elapsed * 0.38))
              .clamp(-1.0, 1.0);
      final biasY =
          (_smoothedTilt.dy * 0.92 + 0.10 * math.cos(_elapsed * 0.29))
              .clamp(-1.0, 1.0);
      BackdropMotionCoordinator.lightBiasNotifier.value = Offset(biasX, biasY);
    }

    _motionState.update(
      nextElapsed: _elapsed,
      nextTilt: _smoothedTilt,
      nextPulsePhase: _pulsePhase,
    );
  }

  CustomPainter _buildPainterFor(AnimatedBackdropPreset preset) {
    switch (preset) {
      case AnimatedBackdropPreset.off:
      case AnimatedBackdropPreset.gyroLiquidHorizon:
        return GyroLiquidHorizonPainter(motionState: _motionState);
      case AnimatedBackdropPreset.causticWater:
        return CausticWaterPainter(motionState: _motionState);
      case AnimatedBackdropPreset.ferrofluidDrift:
        return FerrofluidDriftPainter(motionState: _motionState);
      case AnimatedBackdropPreset.sunbeamDust:
        return SunbeamDustPainter(motionState: _motionState);
      case AnimatedBackdropPreset.topographicPulse:
        return TopographicContourPainter(
          lineColor: const Color(0x16FFFFFF),
          motionState: _motionState,
        );
      case AnimatedBackdropPreset.analogFilmLight:
        return AnalogFilmLightPainter(motionState: _motionState);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSensor();
    _controller.dispose();
    _motionState.dispose();
    if (widget.preset == AnimatedBackdropPreset.gyroLiquidHorizon) {
      BackdropMotionCoordinator.detachGyroLayer();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.preset == AnimatedBackdropPreset.off) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: ColoredBox(
        color: widget.preset.baseColor,
        child: CustomPaint(
          isComplex: true,
          willChange: true,
          painter: _painter,
          size: Size.infinite,
        ),
      ),
    );
  }
}
