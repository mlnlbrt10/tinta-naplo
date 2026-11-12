import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'glass_card.dart';

/// Displays a 120Hz frosted liquid glass inspection modal (when Settings
/// Soft Blur is enabled, matching the floating bottom dock) or solid elevated
/// inspection card (when OFF) with 0.92 -> 1.0 scale-in (`Curves.easeOutCubic`),
/// clean reverse dismissal, and [heroTag] boomerang geometry transitions.
Future<void> showFrostedModal({
  required BuildContext context,
  required String categoryLabel,
  required IconData categoryIcon,
  required Color accentColor,
  required String title,
  String? subtitleTimeSpan,
  String? badgeText,
  BoxShape badgeShape = BoxShape.rectangle,
  String? heroTag,
  required List<FrostedDetailRow> rows,
  String? topicTitle,
  String? topicBody,
  Widget? extraBottomSection,
  String? tsundereNote,
  ModalCloseButtonMode? closeMode,
  UserProfilePrefs? prefs,
}) {
  HapticFeedback.lightImpact();
  final effectiveCloseMode =
      closeMode ?? UserProfilePrefs.activeModalCloseMode;
  final isSoftBlur = resolveSoftBlurEnabled(prefs);

  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Bezárás',
      barrierColor: resolveSoftBlurBarrierColor(
        context,
        prefs: prefs,
        solidDarkAlpha: 0.54,
        solidLightAlpha: 0.42,
      ),
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final cardBg = isDark
            ? const Color(0xFF14181F).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.97);

        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        Widget badgeOrIcon;
        if (badgeText != null) {
          badgeOrIcon = Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accentColor,
              shape: badgeShape,
              borderRadius:
                  badgeShape == BoxShape.circle ? null : OledTheme.badgeRadius,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Text(
                badgeText,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        } else {
          badgeOrIcon = Container(
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
          );
        }

        if (heroTag != null) {
          badgeOrIcon = Hero(
            tag: heroTag,
            flightShuttleBuilder: (
              flightContext,
              flightAnimation,
              flightDirection,
              fromHeroContext,
              toHeroContext,
            ) {
              return DefaultTextStyle(
                style: DefaultTextStyle.of(toHeroContext).style,
                child: toHeroContext.widget,
              );
            },
            child: badgeOrIcon,
          );
        }

        final modalCard = SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: GestureDetector(
                  onTap: () {}, // Prevent tap-through to barrier
                  child: Material(
                    color: Colors.transparent,
                    child: LiquidGlassSurface(
                      prefs: prefs,
                      padding: const EdgeInsets.all(22),
                      borderRadius: OledTheme.largeRadius,
                      solidColor: cardBg,
                      border: isSoftBlur
                          ? null
                          : Border.all(
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
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                badgeOrIcon,
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accentColor.withValues(
                                            alpha: 0.18,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(22),
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
                                      if (subtitleTimeSpan != null &&
                                          subtitleTimeSpan.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.access_time_rounded,
                                              size: 15,
                                              color: accentColor,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                subtitleTimeSpan,
                                                style: theme
                                                    .textTheme.labelMedium
                                                    ?.copyWith(
                                                  color: accentColor,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (effectiveCloseMode.showTopX)
                                  TactileBounce(
                                    onTap: () =>
                                        Navigator.of(dialogContext).pop(),
                                    child: const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Icon(Icons.close_rounded),
                                    ),
                                  ),
                              ],
                            ),
                            if (tsundereNote != null &&
                                tsundereNote.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: OledTheme.uwuPastelPink
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: OledTheme.uwuPastelPink
                                        .withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Text(
                                  tsundereNote,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: OledTheme.uwuPastelPink,
                                    fontWeight: FontWeight.w800,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: isSoftBlur ? 0.36 : 0.65),
                                borderRadius: OledTheme.cardRadius,
                                border: Border.all(
                                  color: isSoftBlur
                                      ? Colors.white.withValues(
                                          alpha: isDark ? 0.14 : 0.38,
                                        )
                                      : theme.dividerColor,
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
                                            const SizedBox(width: 4),
                                            SizedBox(
                                              width: 104,
                                              child: Text(
                                                r.label,
                                                softWrap: true,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: scheme.onSurface
                                                      .withValues(alpha: 0.68),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                r.value,
                                                textAlign: TextAlign.right,
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
                                      .withValues(alpha: isSoftBlur ? 0.30 : 0.50),
                                  borderRadius: OledTheme.cardRadius,
                                  border: Border.all(
                                    color: isSoftBlur
                                        ? Colors.white.withValues(
                                            alpha: isDark ? 0.14 : 0.38,
                                          )
                                        : theme.dividerColor,
                                  ),
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
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurface,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (extraBottomSection != null) ...[
                              const SizedBox(height: 14),
                              extraBottomSection,
                            ],
                            if (effectiveCloseMode.showBottomButton) ...[
                              const SizedBox(height: 18),
                              TactileBounce(
                                onTap: () => Navigator.of(dialogContext).pop(),
                                child: Container(
                                  alignment: Alignment.center,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: accentColor,
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: const Text(
                                    'Bezárás',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
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

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(dialogContext).pop(),
          child: FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
              child: RepaintBoundary(child: modalCard),
            ),
          ),
        );
      },
    ),
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
  String? heroTag,
}) {
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final color = OledTheme.gradeColor(grade.numericValue, prefs);
  final badge = grade.numericValue?.toString() ??
      grade.shortStrValue ??
      (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');
  final weightStr = grade.weightPercentage != null
      ? '${grade.weightPercentage}%'
      : '100%';

  final subjectDisplay = prefs != null
      ? prefs.resolveSubjectName(grade.subject.name, grade.subject.uid)
      : grade.subject.name;
  final teacherDisplay = prefs != null
      ? prefs.resolveTeacherName(grade.teacher)
      : grade.teacher;

  final tsundereNote = (prefs?.tsundereModeEnabled == true ||
          UwuHelper.isTsundereEnabled)
      ? UwuHelper.tsundereCommentForGrade(grade.numericValue)
      : null;

  return showFrostedModal(
    context: context,
    categoryLabel: 'Értékelés / Jegy',
    categoryIcon: Icons.star_rounded,
    accentColor: color,
    title: subjectDisplay,
    badgeText: badge,
    badgeShape: BoxShape.circle,
    heroTag: heroTag,
    tsundereNote: tsundereNote,
    closeMode: prefs?.modalCloseMode,
    prefs: prefs,
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value: subjectDisplay,
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
        value: dtFormat.format(grade.recordedAt),
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Értékelő tanár',
        value: teacherDisplay,
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
  Homework homework, {
  UserProfilePrefs? prefs,
  String? heroTag,
}) {
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final cleanedDesc = homework.description
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .trim();

  final rawSubject = homework.subject.name.isNotEmpty
      ? homework.subject.name
      : homework.subjectName;
  final subjectDisplay = prefs != null
      ? prefs.resolveSubjectName(rawSubject, homework.subject.uid)
      : rawSubject;
  final teacherDisplay = prefs != null
      ? prefs.resolveTeacherName(homework.teacherName)
      : homework.teacherName;

  return showFrostedModal(
    context: context,
    categoryLabel: 'Házi feladat',
    categoryIcon: Icons.menu_book_rounded,
    accentColor: const Color(0xFF00BFA5),
    title: subjectDisplay,
    heroTag: heroTag,
    closeMode: prefs?.modalCloseMode,
    prefs: prefs,
    tsundereNote:
        (prefs?.tsundereModeEnabled == true || UwuHelper.isTsundereEnabled)
            ? 'N-nem mintha érdekelne a házi feladatod, b-baka~!'
            : null,
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value: subjectDisplay,
      ),
      FrostedDetailRow(
        icon: Icons.event_rounded,
        label: 'Feladás ideje',
        value: dtFormat.format(homework.startDate.toLocal()),
      ),
      FrostedDetailRow(
        icon: Icons.alarm_on_rounded,
        label: 'Határidő',
        value: dtFormat.format(homework.dueDate.toLocal()),
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
        value: teacherDisplay,
      ),
    ],
    topicTitle: 'Házi feladat leírása',
    topicBody: cleanedDesc.isNotEmpty ? cleanedDesc : 'Nincs leírás.',
  );
}

/// Opens the frosted glass inspection modal for an announced [Test] / exam.
Future<void> showTestInspectionModal(
  BuildContext context,
  Test test, {
  UserProfilePrefs? prefs,
  String? heroTag,
}) {
  final dayFormat = DateFormat('yyyy. MM. dd.');
  const weekdayNames = [
    '',
    'Hétfő',
    'Kedd',
    'Szerda',
    'Csütörtök',
    'Péntek',
    'Szombat',
    'Vasárnap',
  ];
  final testLocal = test.date.toLocal();
  final weekdayLabel = weekdayNames[testLocal.weekday.clamp(1, 7)];
  final rawSubject =
      test.subject.name.isNotEmpty ? test.subject.name : test.subjectName;
  final subjectDisplay = prefs != null
      ? prefs.resolveSubjectName(rawSubject, test.subject.uid)
      : rawSubject;
  final teacherDisplay = prefs != null
      ? prefs.resolveTeacherName(test.teacherName)
      : test.teacherName;

  return showFrostedModal(
    context: context,
    categoryLabel: 'Bejelentett számonkérés',
    categoryIcon: Icons.assignment_late_rounded,
    accentColor: const Color(0xFFFF7043),
    title: subjectDisplay,
    badgeText: '${test.lessonNumber}.',
    heroTag: heroTag,
    closeMode: prefs?.modalCloseMode,
    prefs: prefs,
    rows: [
      FrostedDetailRow(
        icon: Icons.school_rounded,
        label: 'Tantárgy',
        value: subjectDisplay,
      ),
      FrostedDetailRow(
        icon: Icons.event_rounded,
        label: 'Számonkérés\nnapja',
        value:
            '$weekdayLabel (${test.lessonNumber}. óra)\n${dayFormat.format(testLocal)}',
      ),
      FrostedDetailRow(
        icon: Icons.history_edu_rounded,
        label: 'Bejelentés\ndátuma',
        value: dayFormat.format(test.reportDate.toLocal()),
      ),
      FrostedDetailRow(
        icon: Icons.category_rounded,
        label: 'Számonkérés módja',
        value: test.method.description,
      ),
      FrostedDetailRow(
        icon: Icons.person_rounded,
        label: 'Bejelentő tanár',
        value: teacherDisplay,
      ),
    ],
    topicTitle: 'Számonkérés témája',
    topicBody: (test.theme != null && test.theme!.trim().isNotEmpty)
        ? test.theme!
        : 'Nem lett külön téma megadva.',
  );
}

/// Opens the frosted glass inspection modal for a timetable [Lesson] with
/// boomerang [heroTag] transition (`lesson_num_${lesson.uid}`) and dedicated
/// clean time span row (`08:00 - 08:45`).
Future<void> showLessonInspectionModal(
  BuildContext context,
  Lesson lesson, {
  String? heroTag,
  UserProfilePrefs? prefs,
  Homework? homework,
}) {
  final dayFormat = DateFormat('yyyy. MM. dd.');
  final timeFormat = DateFormat('HH:mm');
  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();
  final timeSpan =
      '${timeFormat.format(startLocal)} - ${timeFormat.format(endLocal)}';

  final isCancelled = lesson.state.name.toLowerCase() == 'elmaradt' ||
      lesson.state.name.toLowerCase().contains('elmarad') ||
      lesson.state.description.toLowerCase().contains('elmarad');
  final hasSub = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final accent = isCancelled
      ? const Color(0xFFC62828)
      : hasSub
          ? const Color(0xFFF9A825)
          : OledTheme.accentPrimary;

  final rawSubject = lesson.subject?.name ?? lesson.name;
  final subjectDisplay = prefs != null
      ? prefs.resolveSubjectName(rawSubject, lesson.subject?.uid)
      : rawSubject;
  final teacherDisplay = prefs != null && lesson.teacher != null
      ? prefs.resolveTeacherName(lesson.teacher)
      : (lesson.teacher ?? 'Nincs megadva');
  final subTeacherDisplay =
      prefs != null && lesson.substituteTeacher != null
          ? prefs.resolveTeacherName(lesson.substituteTeacher)
          : lesson.substituteTeacher;

  const hwTeal = Color(0xFF00BFA5);
  final hasHomeworkFlag = homework != null ||
      (lesson.homeworkUid != null && lesson.homeworkUid!.trim().isNotEmpty);

  Widget? homeworkSection;
  if (hasHomeworkFlag) {
    final hwDesc = homework != null
        ? Homework.stripHtmlTags(homework.description)
        : '';
    final dueText = homework != null
        ? 'Határidő: ${DateFormat('MM. dd. HH:mm').format(homework.dueDate.toLocal())}'
        : null;
    homeworkSection = Builder(
      builder: (innerContext) {
        final theme = Theme.of(innerContext);
        final scheme = theme.colorScheme;
        return TactileBounce(
          onTap: homework != null
              ? () {
                  Navigator.of(innerContext).pop();
                  showHomeworkInspectionModal(
                    context,
                    homework,
                    prefs: prefs,
                  );
                }
              : null,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: hwTeal.withValues(alpha: 0.12),
              borderRadius: OledTheme.cardRadius,
              border: Border.all(
                color: hwTeal.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      size: 17,
                      color: hwTeal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Házi feladat ehhez az órához',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: hwTeal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (dueText != null)
                      Text(
                        dueText,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: hwTeal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  hwDesc.isNotEmpty
                      ? hwDesc
                      : 'Házi feladat rögzítve ehhez a tanórához.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  return showFrostedModal(
    context: context,
    categoryLabel: isCancelled
        ? 'Elmaradó tanóra'
        : hasSub
            ? 'Helyettesített tanóra'
            : 'Tanóra részletei',
    categoryIcon: Icons.schedule_rounded,
    accentColor: accent,
    title: subjectDisplay,
    subtitleTimeSpan: timeSpan,
    badgeText: lesson.lessonNumber != null ? '${lesson.lessonNumber}.' : '•',
    heroTag: heroTag ?? 'lesson_num_${lesson.uid}',
    closeMode: prefs?.modalCloseMode,
    prefs: prefs,
    rows: [
      FrostedDetailRow(
        icon: Icons.access_time_filled_rounded,
        label: 'Idősáv',
        value: timeSpan,
      ),
      FrostedDetailRow(
        icon: Icons.calendar_today_rounded,
        label: 'Dátum',
        value: dayFormat.format(startLocal),
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
        value: teacherDisplay,
      ),
      if (hasSub && subTeacherDisplay != null)
        FrostedDetailRow(
          icon: Icons.swap_horiz_rounded,
          label: 'Helyettesítő tanár',
          value: subTeacherDisplay,
        ),
      FrostedDetailRow(
        icon: Icons.info_outline_rounded,
        label: 'Állapot',
        value: isCancelled ? 'Elmarad' : lesson.state.description,
      ),
    ],
    topicTitle: 'Tanár által beírt tananyag / téma',
    topicBody: (lesson.theme != null && lesson.theme!.trim().isNotEmpty)
        ? lesson.theme!
        : 'Még nem lett tananyag rögzítve ehhez az órához.',
    extraBottomSection: homeworkSection,
  );
}
