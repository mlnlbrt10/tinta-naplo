import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kreta_api/kreta_api.dart';

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
}

/// Paints a circular track and clockwise remaining-progress arc around a period
/// number badge.
class PeriodCountdownRingPainter extends CustomPainter {
  final double remainingFraction;
  final Color ringColor;
  final Color trackColor;
  final double strokeWidth;
  final StrokeCap strokeCap;

  const PeriodCountdownRingPainter({
    required this.remainingFraction,
    required this.ringColor,
    required this.trackColor,
    this.strokeWidth = 3.2,
    this.strokeCap = StrokeCap.round,
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

    final arcPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * clamped,
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
      oldDelegate.strokeCap != strokeCap;
}

/// Period number badge that displays either a quiet rounded-square badge or,
/// when [remainingFraction] is non-null, a circular badge encircled by
/// [PeriodCountdownRingPainter].
class PeriodCountdownBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final TextStyle textStyle;
  final Color ringColor;
  final double? remainingFraction;
  final BoxBorder? border;
  final double outerSize;
  final double innerSize;
  final double idleSize;
  final double strokeWidth;
  final BorderRadius idleBorderRadius;

  const PeriodCountdownBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textStyle,
    required this.ringColor,
    this.remainingFraction,
    this.border,
    this.outerSize = 42,
    this.innerSize = 30,
    this.idleSize = 34,
    this.strokeWidth = 3.2,
    this.idleBorderRadius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    final fraction = remainingFraction;
    if (fraction == null) {
      return Container(
        width: idleSize,
        height: idleSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: idleBorderRadius,
          border: border,
        ),
        child: Text(label, style: textStyle),
      );
    }

    return SizedBox(
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
                trackColor: ringColor.withValues(alpha: 0.18),
                strokeWidth: strokeWidth,
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
            child: Text(label, style: textStyle),
          ),
        ],
      ),
    );
  }
}
