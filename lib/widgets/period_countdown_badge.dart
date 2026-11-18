import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import 'glass_card.dart';

/// Returns true if [lesson] is marked as cancelled (`Allapot.Nev == "elmaradt"`).
bool isLessonCancelled(Lesson lesson) {
  final stateName = lesson.state.name.toLowerCase().trim();
  final stateDesc = lesson.state.description.toLowerCase().trim();
  return stateName == 'elmaradt' ||
      stateName.contains('elmarad') ||
      stateDesc.contains('elmarad');
}

/// Returns true if [lesson] is a synthesized placeholder for an inactive morning period.
bool isInactivePlaceholderLesson(Lesson lesson) =>
    lesson.uid.startsWith('inactive_period_');

/// Active countdown state for a period number badge on today's schedule.
enum PeriodCountdownPhase {
  ongoing,
  inBreak,
  beforeSchool,
}

/// Computed period countdown snapshot indicating which lesson receives the
/// circular progress ring and the remaining fraction (`0.0..1.0`).
class PeriodCountdownInfo {
  /// Default pre-school countdown window (`45 minutes` before the first bell).
  static const Duration defaultPreSchoolWindow = Duration(minutes: 45);

  final PeriodCountdownPhase phase;
  final Lesson targetLesson;
  final Lesson? previousLesson;
  final double remainingFraction;

  const PeriodCountdownInfo({
    required this.phase,
    required this.targetLesson,
    this.previousLesson,
    required this.remainingFraction,
  });

  /// Evaluates [lessons] at [now] to determine if an ongoing class, a break
  /// (`Szünet`), or pre-school period (`Suli előtt`) is currently active.
  ///
  /// When [onlyOnDate] is provided, returns `null` unless [onlyOnDate] is the
  /// same calendar day as `now.toLocal()`. Returns `null` after the final lesson
  /// of the day has ended or when there are no active lessons.
  static PeriodCountdownInfo? evaluate(
    List<Lesson> lessons,
    DateTime now, {
    DateTime? onlyOnDate,
    Duration preSchoolWindow = defaultPreSchoolWindow,
  }) {
    final localNow = now.toLocal();
    final todayDate = DateUtils.dateOnly(localNow);
    if (onlyOnDate != null &&
        DateUtils.dateOnly(onlyOnDate.toLocal()) != todayDate) {
      return null;
    }

    final todaysMatches = lessons
        .where((l) => DateUtils.dateOnly(l.start.toLocal()) == todayDate)
        .toList();
    final scoped = onlyOnDate != null
        ? todaysMatches
        : (todaysMatches.isNotEmpty ? todaysMatches : lessons);

    final active = scoped
        .where((l) => !isLessonCancelled(l) && !isInactivePlaceholderLesson(l))
        .toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    if (active.isEmpty) return null;

    // 1. Active ongoing lesson (`start <= now < end`).
    for (final lesson in active) {
      final start = lesson.start.toLocal();
      final end = lesson.end.toLocal();
      if (!localNow.isBefore(start) && localNow.isBefore(end)) {
        final totalMs = end.difference(start).inMilliseconds;
        final remainingMs = end.difference(localNow).inMilliseconds;
        final fraction = totalMs > 0
            ? (remainingMs / totalMs).clamp(0.0, 1.0)
            : 0.0;
        return PeriodCountdownInfo(
          phase: PeriodCountdownPhase.ongoing,
          targetLesson: lesson,
          remainingFraction: fraction,
        );
      }
    }

    // 2. Before school (`now < firstLesson.start`): clamps at 1.0 outside window.
    final firstLesson = active.first;
    final firstStart = firstLesson.start.toLocal();
    if (localNow.isBefore(firstStart)) {
      final remainingMs = firstStart.difference(localNow).inMilliseconds;
      final windowMs = preSchoolWindow.inMilliseconds;
      final fraction = windowMs > 0
          ? (remainingMs / windowMs).clamp(0.0, 1.0)
          : 1.0;
      return PeriodCountdownInfo(
        phase: PeriodCountdownPhase.beforeSchool,
        targetLesson: firstLesson,
        remainingFraction: fraction,
      );
    }

    // 3. Break (`Szünet`) between `prevLesson.end` and `nextLesson.start`.
    for (int i = 1; i < active.length; i++) {
      final nextLesson = active[i];
      final nextStart = nextLesson.start.toLocal();
      if (nextStart.isAfter(localNow)) {
        final previousLesson = active[i - 1];
        final prevEnd = previousLesson.end.toLocal();
        final breakMs = nextStart.difference(prevEnd).inMilliseconds;
        final remainingMs = nextStart.difference(localNow).inMilliseconds;
        final fraction = breakMs > 0
            ? (remainingMs / breakMs).clamp(0.0, 1.0)
            : 0.0;
        return PeriodCountdownInfo(
          phase: PeriodCountdownPhase.inBreak,
          targetLesson: nextLesson,
          previousLesson: previousLesson,
          remainingFraction: fraction,
        );
      }
    }

    // 4. All lessons for today have ended.
    return null;
  }

  /// Start timestamp of the active ongoing or break window, or `null` pre-school.
  DateTime? get windowStart => switch (phase) {
        PeriodCountdownPhase.ongoing => targetLesson.start.toLocal(),
        PeriodCountdownPhase.inBreak => previousLesson?.end.toLocal(),
        PeriodCountdownPhase.beforeSchool => null,
      };

  /// End timestamp of the active ongoing or break window, or `null` pre-school.
  DateTime? get windowEnd => switch (phase) {
        PeriodCountdownPhase.ongoing => targetLesson.end.toLocal(),
        PeriodCountdownPhase.inBreak => targetLesson.start.toLocal(),
        PeriodCountdownPhase.beforeSchool => null,
      };
}

/// Formats remaining duration consistently for active lessons and breaks,
/// switching to `"59 mp"`, `"58 mp"`, ..., `"1 mp"` in the final minute.
String formatCountdownRemainingLabel(
  Duration remaining, {
  String finalSuffix = ' mp',
  String minuteSuffix = ' perc van hátra',
}) {
  final ms = remaining.inMilliseconds;
  if (ms <= 0) return '0$finalSuffix';
  if (ms <= 60000) {
    final secs = ((ms + 999) ~/ 1000).clamp(1, 60);
    return '$secs$finalSuffix';
  }
  final mins = ((ms + 59999) ~/ 60000).clamp(1, 600);
  return '$mins$minuteSuffix';
}

/// Snapshot emitted by [LiveCountdownProgressScope] for countdown rings and
/// perimeter borders.
class LiveCountdownSnapshot {
  final double progress;
  final int remainingMillis;
  final bool isFinalMinute;
  final bool isRefilling;

  const LiveCountdownSnapshot({
    required this.progress,
    required this.remainingMillis,
    required this.isFinalMinute,
    required this.isRefilling,
  });

  Duration get remainingDuration =>
      Duration(milliseconds: remainingMillis < 0 ? 0 : remainingMillis);

  String formattedRemaining({
    String finalSuffix = ' mp',
    String minuteSuffix = ' perc van hátra',
  }) =>
      formatCountdownRemainingLabel(
        remainingDuration,
        finalSuffix: finalSuffix,
        minuteSuffix: minuteSuffix,
      );
}

/// Scopes final-minute (`<= 60s`) 500ms easeOutCubic refill and smooth 120Hz
/// `Ticker` depletion strictly around the active countdown badge / break card
/// inside a [RepaintBoundary] so the surrounding screen never rebuilds on vsync.
class LiveCountdownProgressScope extends StatefulWidget {
  final DateTime startTime;
  final DateTime endTime;
  final DateTime? now;
  final DateTime Function()? clock;
  final Widget Function(BuildContext context, LiveCountdownSnapshot snapshot)
      builder;

  const LiveCountdownProgressScope({
    super.key,
    required this.startTime,
    required this.endTime,
    this.now,
    this.clock,
    required this.builder,
  });

  @override
  State<LiveCountdownProgressScope> createState() =>
      _LiveCountdownProgressScopeState();
}

class _LiveCountdownProgressScopeState
    extends State<LiveCountdownProgressScope>
    with TickerProviderStateMixin {
  late final AnimationController _refillCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );
  Ticker? _finalMinuteTicker;
  Timer? _boundaryTimer;
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  bool _wasAboveOneMinute = false;
  double _lastNormalFraction = 1.0;
  double _refillFrom = 0.0;

  int get _totalMs => widget.endTime
      .difference(widget.startTime)
      .inMilliseconds
      .clamp(1, 86400000);

  DateTime _sampleNow({bool forLiveTick = false}) {
    if (widget.clock != null) return widget.clock!();
    if (forLiveTick) return DateTime.now();
    return widget.now ?? DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    final remMs = widget.endTime.difference(_sampleNow()).inMilliseconds;
    _lastNormalFraction = (remMs / _totalMs).clamp(0.0, 1.0);
    if (remMs <= 60000) {
      // Mounted already inside final minute: start directly at proportional fraction
      // without triggering a false refill sweep.
      _wasAboveOneMinute = false;
      _refillCtrl.value = 1.0;
    } else {
      _wasAboveOneMinute = true;
      _refillCtrl.value = 1.0;
    }
    _syncTimingState(allowRefillTrigger: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTimingState(allowRefillTrigger: true);
  }

  @override
  void didUpdateWidget(covariant LiveCountdownProgressScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    final windowChanged = oldWidget.startTime != widget.startTime ||
        oldWidget.endTime != widget.endTime;
    if (windowChanged) {
      final remMs = widget.endTime.difference(_sampleNow()).inMilliseconds;
      _lastNormalFraction = (remMs / _totalMs).clamp(0.0, 1.0);
      _wasAboveOneMinute = remMs > 60000;
      _refillCtrl.value = 1.0;
    }
    _syncTimingState(allowRefillTrigger: !windowChanged);
  }

  void _syncTimingState({required bool allowRefillTrigger}) {
    final remMs = widget.endTime.difference(_sampleNow()).inMilliseconds;
    if (remMs > 60000) {
      _wasAboveOneMinute = true;
      _lastNormalFraction = (remMs / _totalMs).clamp(0.0, 1.0);
      _stopFinalMinuteTicker();
      _scheduleBoundaryTimer(remMs - 60000 + 2);
      return;
    }

    _boundaryTimer?.cancel();
    _boundaryTimer = null;

    if (remMs <= 0) {
      _wasAboveOneMinute = false;
      _stopFinalMinuteTicker();
      return;
    }

    if (allowRefillTrigger && _wasAboveOneMinute) {
      _wasAboveOneMinute = false;
      _refillFrom = _lastNormalFraction;
      _refillCtrl.forward(from: 0.0);
    } else {
      _wasAboveOneMinute = false;
    }

    if (widget.clock == null && TickerMode.valuesOf(context).enabled) {
      _ensureFinalMinuteTicker();
    } else {
      _stopFinalMinuteTicker();
    }
  }

  void _scheduleBoundaryTimer(int delayMs) {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    if (widget.clock != null || delayMs <= 0) return;
    _boundaryTimer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted) return;
      _syncTimingState(allowRefillTrigger: true);
      _frameTick.value++;
    });
  }

  void _ensureFinalMinuteTicker() {
    _finalMinuteTicker ??= createTicker((_) {
      if (!mounted) return;
      final remMs =
          widget.endTime.difference(_sampleNow(forLiveTick: true)).inMilliseconds;
      _frameTick.value++;
      if (remMs <= 0) {
        _stopFinalMinuteTicker();
      }
    });
    if (!_finalMinuteTicker!.isActive) {
      _finalMinuteTicker!.start();
    }
  }

  void _stopFinalMinuteTicker() {
    if (_finalMinuteTicker?.isActive ?? false) {
      _finalMinuteTicker!.stop();
    }
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    _finalMinuteTicker?.dispose();
    _refillCtrl.dispose();
    _frameTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_frameTick, _refillCtrl]),
        builder: (context, _) {
          final isTickerLive = _finalMinuteTicker?.isActive ?? false;
          final now = _sampleNow(forLiveTick: isTickerLive);
          final remMs = widget.endTime.difference(now).inMilliseconds;
          final clampedRem = remMs < 0 ? 0 : remMs;
          final bool isFinalMinute = clampedRem > 0 && clampedRem <= 60000;
          final bool isRefilling = _refillCtrl.isAnimating;

          double progress;
          if (clampedRem <= 0) {
            progress = 0.0;
          } else if (clampedRem > 60000) {
            progress = (clampedRem / _totalMs).clamp(0.0, 1.0);
          } else {
            final target = (clampedRem / 60000.0).clamp(0.0, 1.0);
            if (_refillCtrl.value < 1.0) {
              final t = Curves.easeOutCubic.transform(_refillCtrl.value);
              progress = ui.lerpDouble(_refillFrom, target, t)!.clamp(0.0, 1.0);
            } else {
              progress = target;
            }
          }

          return widget.builder(
            context,
            LiveCountdownSnapshot(
              progress: progress,
              remainingMillis: clampedRem,
              isFinalMinute: isFinalMinute,
              isRefilling: isRefilling,
            ),
          );
        },
      ),
    );
  }
}

/// Paints a circular track, soft radial glow, and clockwise remaining-progress
/// arc around a period number badge.
class PeriodCountdownRingPainter extends CustomPainter {
  final double remainingFraction;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;
  final StrokeCap strokeCap;
  final double glowSigma;

  const PeriodCountdownRingPainter({
    required this.remainingFraction,
    required this.ringColor,
    required this.trackColor,
    this.strokeWidth = 3.2,
    this.strokeCap = StrokeCap.round,
    this.glowSigma = 4.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final clamped = remainingFraction.clamp(0.0, 1.0);
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2.0;
    if (radius <= 0) return;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    if (clamped <= 0.0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * clamped;

    if (glowSigma > 0) {
      final glowPaint = Paint()
        ..color = ringColor.withValues(alpha: 0.42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 1.75
        ..strokeCap = strokeCap
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma);
      canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
    }

    final arcPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant PeriodCountdownRingPainter oldDelegate) =>
      oldDelegate.remainingFraction != remainingFraction ||
      oldDelegate.ringColor != ringColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.strokeCap != strokeCap ||
      oldDelegate.glowSigma != glowSigma;
}

/// Period number badge that displays either a quiet rounded-square badge or,
/// when [remainingFraction] (or a live [startTime]/[endTime] window) is active,
/// a circular badge encircled by [PeriodCountdownRingPainter].
class PeriodCountdownBadge extends StatelessWidget {
  final String label;
  final Widget? centerChild;
  final Color backgroundColor;
  final TextStyle textStyle;
  final Color ringColor;
  final double? remainingFraction;
  final DateTime? startTime;
  final DateTime? endTime;
  final DateTime? now;
  final DateTime Function()? clock;
  final BoxBorder? border;
  final double outerSize;
  final double innerSize;
  final double idleSize;
  final double strokeWidth;
  final double glowSigma;
  final BorderRadius idleBorderRadius;

  const PeriodCountdownBadge({
    super.key,
    required this.label,
    this.centerChild,
    required this.backgroundColor,
    required this.textStyle,
    required this.ringColor,
    this.remainingFraction,
    this.startTime,
    this.endTime,
    this.now,
    this.clock,
    this.border,
    this.outerSize = 44,
    this.innerSize = 30,
    this.idleSize = 34,
    this.strokeWidth = 3.2,
    this.glowSigma = 4.5,
    this.idleBorderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  Widget _buildCenterContent() {
    if (centerChild != null) return centerChild!;
    final existingFeatures = textStyle.fontFeatures;
    final tabularStyle = textStyle.copyWith(
      fontFeatures: (existingFeatures != null && existingFeatures.isNotEmpty)
          ? existingFeatures
          : const [ui.FontFeature.tabularFigures()],
    );
    return Text(label, style: tabularStyle);
  }

  Widget _buildActiveRingBadge(double fraction) {
    return RepaintBoundary(
      child: SizedBox(
        width: outerSize,
        height: outerSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: PeriodCountdownRingPainter(
                  remainingFraction: fraction,
                  ringColor: ringColor,
                  trackColor: ringColor.withValues(alpha: 0.16),
                  strokeWidth: strokeWidth,
                  glowSigma: glowSigma,
                ),
              ),
            ),
            Container(
              width: innerSize,
              height: innerSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: backgroundColor,
                shape: BoxShape.circle,
                border: border,
              ),
              child: _buildCenterContent(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLiveWindow = startTime != null && endTime != null;
    if (remainingFraction == null && !hasLiveWindow) {
      return Container(
        width: idleSize,
        height: idleSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: idleBorderRadius,
          border: border,
        ),
        child: _buildCenterContent(),
      );
    }

    if (hasLiveWindow) {
      return LiveCountdownProgressScope(
        startTime: startTime!,
        endTime: endTime!,
        now: now,
        clock: clock,
        builder: (_, snapshot) => _buildActiveRingBadge(snapshot.progress),
      );
    }

    return _buildActiveRingBadge(remainingFraction!);
  }
}

/// CustomPainter drawing a continuous, glowing full-perimeter rounded-rectangle
/// countdown progress border starting at top-center and sweeping clockwise.
class BreakPerimeterCountdownPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;
  final double radius;
  final double strokeWidth;
  final double glowSigma;

  const BreakPerimeterCountdownPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
    this.radius = 20.0,
    this.strokeWidth = 2.2,
    this.glowSigma = 6.0,
  });

  static Path _buildTopCenterClockwiseRRect(Rect rect, double cornerRadius) {
    final maxR = math.min(rect.width, rect.height) / 2.0;
    final r = Radius.circular(cornerRadius.clamp(0.0, maxR));
    final rx = r.x;
    final ry = r.y;
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - rx, rect.top)
      ..arcToPoint(Offset(rect.right, rect.top + ry), radius: r)
      ..lineTo(rect.right, rect.bottom - ry)
      ..arcToPoint(Offset(rect.right - rx, rect.bottom), radius: r)
      ..lineTo(rect.left + rx, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - ry), radius: r)
      ..lineTo(rect.left, rect.top + ry)
      ..arcToPoint(Offset(rect.left + rx, rect.top), radius: r)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final inset = strokeWidth / 2.0 + 0.5;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      math.max(0.0, size.width - inset * 2),
      math.max(0.0, size.height - inset * 2),
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    final trackPath = _buildTopCenterClockwiseRRect(
      rect,
      math.max(0.0, radius - inset),
    );

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(trackPath, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0.0) return;

    final extracted = Path();
    for (final metric in trackPath.computeMetrics()) {
      extracted.addPath(
        metric.extractPath(0.0, metric.length * clamped),
        Offset.zero,
      );
    }

    if (glowSigma > 0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma);
      canvas.drawPath(extracted, glowPaint);
    }

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(extracted, arcPaint);
  }

  @override
  bool shouldRepaint(covariant BreakPerimeterCountdownPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.glowSigma != glowSigma;
}

/// Dedicated glowing full-perimeter Break (`Szünet`) card rendered between
/// consecutive lessons during an active break. Uses a 120Hz GPU-friendly
/// multi-stop Liquid Glass gradient surface wrapped in [RepaintBoundary] when
/// Liquid Glass mode is enabled (zero per-item BackdropFilter stalls).
class BreakCountdownCard extends StatelessWidget {
  final DateTime breakStart;
  final DateTime breakEnd;
  final DateTime? now;
  final DateTime Function()? clock;
  final String Function(String)? textTransform;
  final UserProfilePrefs? prefs;

  const BreakCountdownCard({
    super.key,
    required this.breakStart,
    required this.breakEnd,
    this.now,
    this.clock,
    this.textTransform,
    this.prefs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final transform = textTransform ?? (s) => s;
    final timeFormat = DateFormat('HH:mm');
    final accent = scheme.primary;
    final effectivePrefs =
        prefs ?? AppProvidersScope.maybeOf(context)?.settings.prefs;
    final liquidGlass = resolveLiquidGlassEnabled(effectivePrefs);
    final solidFill =
        scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.92 : 0.98);
    final glassGradient = isDark
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.38, 1.0],
            colors: [
              Colors.white.withValues(alpha: 0.09),
              const Color(0xFF141820).withValues(alpha: 0.56),
              const Color(0xFF0A0D13).withValues(alpha: 0.68),
            ],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.4, 1.0],
            colors: [
              Colors.white.withValues(alpha: 0.84),
              scheme.surfaceContainerHigh.withValues(alpha: 0.62),
              scheme.surfaceContainer.withValues(alpha: 0.72),
            ],
          );

    return RepaintBoundary(
      child: LiveCountdownProgressScope(
        startTime: breakStart,
        endTime: breakEnd,
        now: now,
        clock: clock,
        builder: (context, snapshot) {
          final remainingLabel = transform(
            snapshot.formattedRemaining(
              finalSuffix: ' mp',
              minuteSuffix: ' perc van hátra',
            ),
          );
          final Widget body = Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: liquidGlass
                ? BoxDecoration(
                    gradient: glassGradient,
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(
                          alpha: isDark ? 0.20 : 0.62,
                        ),
                        width: 0.85,
                      ),
                    ),
                  )
                : BoxDecoration(color: solidFill),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.pause_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        transform('Szünet'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${timeFormat.format(breakStart)} – ${timeFormat.format(breakEnd)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [
                            ui.FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    remainingLabel,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [
                        ui.FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

          final Widget clippedSurface = ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: body,
          );

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: isDark ? 0.16 : 0.10),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: CustomPaint(
              foregroundPainter: BreakPerimeterCountdownPainter(
                progress: snapshot.progress,
                color: accent,
                trackColor: accent.withValues(alpha: isDark ? 0.18 : 0.16),
                radius: 20.0,
                strokeWidth: 2.2,
                glowSigma: 6.0,
              ),
              child: clippedSurface,
            ),
          );
        },
      ),
    );
  }
}
