import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';

/// Displays a frosted glass soft blur inspection modal (`BackdropFilter` with
/// `ImageFilter.blur(sigmaX: 10, sigmaY: 10)`).
Future<void> showFrostedModal({
  required BuildContext context,
  required String categoryLabel,
  required IconData categoryIcon,
  required Color accentColor,
  required String title,
  String? badgeText,
  required List<FrostedDetailRow> rows,
  String? topicTitle,
  String? topicBody,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Bezárás',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final theme = Theme.of(dialogContext);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final cardBg = isDark
          ? const Color(0xFF141418).withValues(alpha: 0.86)
          : Colors.white.withValues(alpha: 0.88);

      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: OledTheme.largeRadius,
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.55),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (badgeText != null) ...[
                                Container(
                                  width: 54,
                                  height: 54,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: OledTheme.badgeRadius,
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ] else ...[
                                Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.2),
                                    borderRadius: OledTheme.badgeRadius,
                                    border: Border.all(
                                      color: accentColor.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  child: Icon(
                                    categoryIcon,
                                    color: accentColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            accentColor.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      child: Text(
                                        categoryLabel,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: accentColor,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      title,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: scheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Bezárás',
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.65),
                              borderRadius: OledTheme.cardRadius,
                              border: Border.all(
                                color: theme.dividerColor,
                              ),
                            ),
                            child: Column(
                              children: rows
                                  .map(
                                    (r) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            r.icon,
                                            size: 17,
                                            color: accentColor,
                                          ),
                                          const SizedBox(width: 10),
                                          SizedBox(
                                            width: 118,
                                            child: Text(
                                              r.label,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.68),
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              r.value,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: scheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                          if (topicBody != null &&
                              topicBody.trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: OledTheme.cardRadius,
                                border: Border.all(color: theme.dividerColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    topicTitle ?? 'Téma / Leírás',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: accentColor,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    topicBody.trim(),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: scheme.onSurface,
                                      height: 1.35,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text(
                              'Bezárás',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class FrostedDetailRow {
  final IconData icon;
  final String label;
  final String value;

  const FrostedDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
}

/// Opens the frosted glass inspection modal for a [Grade].
Future<void> showGradeInspectionModal(
  BuildContext context,
  Grade grade, {
  UserProfilePrefs? prefs,
}) {
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final color = OledTheme.gradeColor(grade.numericValue, prefs);
  final badge = grade.numericValue?.toString() ??
      grade.shortStrValue ??
      (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');
  final weightStr = grade.weightPercentage != null
      ? '${grade.weightPercentage}%'
      : '100%';

  return showFrostedModal(
    context: context,
    categoryLabel: 'Értékelés / Jegy',
    categoryIcon: Icons.star_rounded,
    accentColor: color,
    title: grade.subject.name,
    badgeText: badge,
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value: grade.subject.name,
      ),
      FrostedDetailRow(
        icon: Icons.grade_rounded,
        label: 'Érdemjegy',
        value: grade.strValue,
      ),
      FrostedDetailRow(
        icon: Icons.scale_rounded,
        label: 'Súlyozás',
        value: weightStr,
      ),
      FrostedDetailRow(
        icon: Icons.category_rounded,
        label: 'Értékelés módja',
        value: [
          grade.type.description,
          if (grade.mode != null && grade.mode!.description.isNotEmpty)
            grade.mode!.description,
        ].join(' • '),
      ),
      FrostedDetailRow(
        icon: Icons.calendar_today_rounded,
        label: 'Rögzítés ideje',
        value: dtFormat.format(grade.recordDate),
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Értékelő tanár',
        value: grade.teacher,
      ),
    ],
    topicTitle: 'Pontosan rögzített téma',
    topicBody: (grade.topic != null && grade.topic!.trim().isNotEmpty)
        ? grade.topic!
        : 'Nem lett külön téma megadva.',
  );
}

/// Opens the frosted glass inspection modal for a [Homework] item.
Future<void> showHomeworkInspectionModal(
  BuildContext context,
  Homework homework,
) {
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final cleanedDesc = homework.description
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .trim();

  return showFrostedModal(
    context: context,
    categoryLabel: 'Házi feladat',
    categoryIcon: Icons.menu_book_rounded,
    accentColor: const Color(0xFF00BFA5),
    title: homework.subject.name.isNotEmpty
        ? homework.subject.name
        : homework.subjectName,
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value: homework.subject.name.isNotEmpty
            ? homework.subject.name
            : homework.subjectName,
      ),
      FrostedDetailRow(
        icon: Icons.event_rounded,
        label: 'Feladás ideje',
        value: dtFormat.format(homework.startDate),
      ),
      FrostedDetailRow(
        icon: Icons.alarm_on_rounded,
        label: 'Határidő',
        value: dtFormat.format(homework.dueDate),
      ),
      FrostedDetailRow(
        icon: Icons.scale_rounded,
        label: 'Súly / Státusz',
        value: homework.isDone ? 'Megoldva (Kész)' : 'Aktív házi feladat',
      ),
      FrostedDetailRow(
        icon: Icons.category_rounded,
        label: 'Típus',
        value: homework.isCreatedByTeacher
            ? 'Tanár által rögzített'
            : 'Tanulói feljegyzés',
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Rögzítő tanár',
        value: homework.teacherName,
      ),
    ],
    topicTitle: 'Házi feladat leírása',
    topicBody: cleanedDesc.isNotEmpty ? cleanedDesc : 'Nincs leírás.',
  );
}

/// Opens the frosted glass inspection modal for an announced [Test] / exam.
Future<void> showTestInspectionModal(
  BuildContext context,
  Test test,
) {
  final dayFormat = DateFormat('yyyy. MM. dd.');

  return showFrostedModal(
    context: context,
    categoryLabel: 'Bejelentett számonkérés',
    categoryIcon: Icons.assignment_late_rounded,
    accentColor: const Color(0xFFFF7043),
    title: test.subject.name.isNotEmpty ? test.subject.name : test.subjectName,
    badgeText: '${test.lessonNumber}.',
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value:
            test.subject.name.isNotEmpty ? test.subject.name : test.subjectName,
      ),
      FrostedDetailRow(
        icon: Icons.event_rounded,
        label: 'Számonkérés napja',
        value: '${dayFormat.format(test.date)} (${test.lessonNumber}. óra)',
      ),
      FrostedDetailRow(
        icon: Icons.history_edu_rounded,
        label: 'Bejelentés dátuma',
        value: dayFormat.format(test.reportDate),
      ),
      FrostedDetailRow(
        icon: Icons.category_rounded,
        label: 'Számonkérés módja',
        value: test.method.description,
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Bejelentő tanár',
        value: test.teacherName,
      ),
    ],
    topicTitle: 'Számonkérés témája',
    topicBody: (test.theme != null && test.theme!.trim().isNotEmpty)
        ? test.theme!
        : 'Nem lett külön téma megadva.',
  );
}

/// Opens the frosted glass inspection modal for a timetable [Lesson].
Future<void> showLessonInspectionModal(
  BuildContext context,
  Lesson lesson,
) {
  final dayFormat = DateFormat('yyyy. MM. dd.');
  final timeFormat = DateFormat('HH:mm');
  final isCancelled = lesson.state.name.toLowerCase().contains('elmarad');
  final hasSub = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final accent = isCancelled
      ? const Color(0xFFC62828)
      : hasSub
          ? const Color(0xFFF9A825)
          : OledTheme.accentPrimary;

  return showFrostedModal(
    context: context,
    categoryLabel: isCancelled
        ? 'Elmaradó tanóra'
        : hasSub
            ? 'Helyettesített tanóra'
            : 'Tanóra részletei',
    categoryIcon: Icons.schedule_rounded,
    accentColor: accent,
    title: lesson.subject?.name ?? lesson.name,
    badgeText: lesson.lessonNumber != null ? '${lesson.lessonNumber}.' : null,
    rows: [
      FrostedDetailRow(
        icon: Icons.access_time_filled_rounded,
        label: 'Időpont',
        value:
            '${dayFormat.format(lesson.start)} • ${timeFormat.format(lesson.start)} – ${timeFormat.format(lesson.end)}',
      ),
      FrostedDetailRow(
        icon: Icons.meeting_room_rounded,
        label: 'Tanterem',
        value: (lesson.roomName != null && lesson.roomName!.trim().isNotEmpty)
            ? lesson.roomName!
            : 'Nincs megadva',
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Tanár',
        value: lesson.teacher ?? 'Nincs megadva',
      ),
      if (hasSub)
        FrostedDetailRow(
          icon: Icons.swap_horiz_rounded,
          label: 'Helyettesítő tanár',
          value: lesson.substituteTeacher!,
        ),
      FrostedDetailRow(
        icon: Icons.info_outline_rounded,
        label: 'Állapot',
        value: lesson.state.description,
      ),
    ],
    topicTitle: 'Tanár által beírt tananyag / téma',
    topicBody: (lesson.theme != null && lesson.theme!.trim().isNotEmpty)
        ? lesson.theme!
        : 'Még nem lett tananyag rögzítve ehhez az órához.',
  );
}
