import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/calendar_sync_service.dart';
import '../services/demo_data_service.dart';
import '../services/dynamic_icon_service.dart';
import '../services/github_updater_service.dart';
import '../services/kreta_client.dart';
import '../services/kreta_notification_service.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../theme/minimalist_tokens.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/edge_fade_horizontal_scroll.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/period_countdown_badge.dart'
    show isInactivePlaceholderLesson, isLessonCancelled;
import '../widgets/tinta_toast.dart';
import 'about_app_screen.dart';
import 'developer_options_screen.dart';
import 'notifications_settings_screen.dart';

enum _AttendanceFilter {
  all('Összes'),
  certified('Igazolt'),
  uncertified('Igazolatlan'),
  tardiness('Késések');

  final String label;
  const _AttendanceFilter(this.label);
}

/// Absences and tardiness entries grouped into a single calendar day.
class DailyOmissionGroup {
  final DateTime day;
  final List<Omission> entries;

  const DailyOmissionGroup({
    required this.day,
    required this.entries,
  });

  int get missedCount =>
      entries.where((o) => !OmissionsSummary.isTardiness(o)).length;

  int get certifiedCount =>
      entries.where((o) => o.state == OmissionState.excused).length;

  int get uncertifiedCount =>
      entries.where((o) => o.state == OmissionState.unexcused).length;

  int get pendingCount => entries
      .where(
        (o) =>
            o.state == OmissionState.pending ||
            o.state == OmissionState.unknown,
      )
      .length;

  /// Compact count/status badge label for the daily header pill.
  String get summaryLabel {
    final missed = missedCount;
    final tardyCount = entries.length - missed;
    if (missed > 0 && tardyCount > 0) {
      return '$missed óra • $tardyCount késés';
    }
    if (tardyCount > 0) {
      return '$tardyCount késés';
    }
    return '$missed óra';
  }

  String get statusLabel {
    if (uncertifiedCount > 0) return 'Igazolatlan';
    if (pendingCount > 0) return 'Igazolandó';
    return 'Igazolt';
  }

  Color resolveAccentColor([Brightness brightness = Brightness.dark]) {
    if (entries.any((o) => o.state == OmissionState.unexcused)) {
      return OledTheme.omissionUnexcusedRedColor(brightness);
    }
    if (entries.any(
      (o) =>
          o.state == OmissionState.pending || o.state == OmissionState.unknown,
    )) {
      return OledTheme.omissionPendingOrangeColor(brightness);
    }
    return OledTheme.omissionExcusedColor(brightness);
  }
}

/// Absences and tardiness entries grouped by school subject with percentage
/// relative to held lessons so far.
class SubjectAbsenceGroup {
  final String subjectKey;
  final String subjectName;
  final List<Omission> items;
  final int missedHours;
  final int certifiedHours;
  final int uncertifiedHours;
  final int pendingHours;
  final int tardinessCount;
  final int tardinessMinutes;
  final int totalHeldLessons;

  const SubjectAbsenceGroup({
    required this.subjectKey,
    required this.subjectName,
    required this.items,
    required this.missedHours,
    required this.certifiedHours,
    required this.uncertifiedHours,
    required this.pendingHours,
    required this.tardinessCount,
    required this.tardinessMinutes,
    required this.totalHeldLessons,
  });

  double get absencePercentage =>
      totalHeldLessons > 0 ? (missedHours / totalHeldLessons) * 100.0 : 0.0;
}

/// Subtle color coding for subject absence percentages relative to the 30% limit.
Color resolveAbsencePercentageColor(double percentage, ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  if (percentage >= 25.0) {
    return isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);
  }
  if (percentage >= 15.0) {
    return isDark ? const Color(0xFFF59E0B) : const Color(0xFFB45309);
  }
  return scheme.primary;
}

int _estimateSubjectWeeklyFrequency(
  String normSubject, {
  required List<Omission> subjectOmissions,
  int? observedCount,
  int sampledWeekdays = 0,
  double? observedWeeklyAvg,
}) {
  final dailyOmissionCounts = <DateTime, int>{};
  final omissionWeekdays = <int>{};
  for (final o in subjectOmissions) {
    final local = o.date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    dailyOmissionCounts[day] = (dailyOmissionCounts[day] ?? 0) + 1;
    if (local.weekday >= 1 && local.weekday <= 5) {
      omissionWeekdays.add(local.weekday);
    }
  }
  final maxDailyOmission = dailyOmissionCounts.values.fold<int>(
    0,
    (prev, v) => v > prev ? v : prev,
  );
  final minFromOmissions =
      math.max(maxDailyOmission, omissionWeekdays.length).clamp(1, 10);

  // When a full or nearly full school week (4-5 weekdays) of real timetable data
  // is present and contains this subject, trust its exact weekly schedule count!
  if (sampledWeekdays >= 4 && observedWeeklyAvg != null && observedWeeklyAvg > 0) {
    final scaledWeekly = sampledWeekdays >= 5
        ? observedWeeklyAvg.round()
        : (observedWeeklyAvg * 5.0 / sampledWeekdays).round();
    return math.max(minFromOmissions, scaledWeekly).clamp(1, 20);
  }

  // Fallback curriculum heuristics when only 0-3 days of timetable are cached.
  int heuristic;
  final s = normSubject;
  if (s.contains('osztályfőn') ||
      s.contains('osztalyfon') ||
      s.contains('ének') ||
      s.contains('enek') ||
      s.contains('rajz') ||
      s.contains('vizuális') ||
      s.contains('vizualis') ||
      s.contains('etika') ||
      s.contains('hit-') ||
      s.contains('hittan') ||
      s.contains('állampolgár') ||
      s.contains('allampolgar') ||
      s.contains('dráma') ||
      s.contains('drama') ||
      s.contains('honvédel') ||
      s.contains('honvedel') ||
      s.contains('művészet') ||
      s.contains('muveszet') ||
      s.contains('munkavállal') ||
      s.contains('munkavallal')) {
    heuristic = 1;
  } else if (s.contains('testnevel') || s == 'tesi') {
    heuristic = 5;
  } else if (s.contains('matemat') ||
      s.contains('matek') ||
      s.contains('magyar') ||
      s.contains('irodalom') ||
      s.contains('nyelvtan') ||
      s.contains('angol') ||
      s.contains('német') ||
      s.contains('nemet') ||
      s.contains('francia') ||
      s.contains('olasz') ||
      s.contains('spanyol') ||
      s.contains('orosz')) {
    heuristic = 4;
  } else if (s.contains('történel') ||
      s.contains('tortenel') ||
      s.contains('fizika') ||
      s.contains('kémia') ||
      s.contains('kemia') ||
      s.contains('biológ') ||
      s.contains('biolog') ||
      s.contains('földrajz') ||
      s.contains('foldrajz') ||
      s.contains('informatika') ||
      s.contains('digitális') ||
      s.contains('digitalis') ||
      s.contains('hálózat') ||
      s.contains('halozat') ||
      s.contains('programoz') ||
      s.contains('szoftver') ||
      s.contains('adatbázis') ||
      s.contains('adatbazis') ||
      s.contains('projekt') ||
      s.contains('szakmai')) {
    heuristic = 3;
  } else {
    heuristic = 2;
  }

  final partialFloor = observedCount ?? 0;
  return math.max(math.max(heuristic, minFromOmissions), partialFloor).clamp(1, 20);
}

/// Groups [omissions] by resolved subject name with absence percentages against
/// [heldLessonsBySubject] or a deterministic per-subject weekly schedule estimate.
List<SubjectAbsenceGroup> groupOmissionsBySubject(
  List<Omission> omissions, {
  UserProfilePrefs? prefs,
  Map<String, int>? heldLessonsBySubject,
  List<Lesson>? referenceLessons,
  DateTime? referenceDate,
}) {
  if (omissions.isEmpty) return const <SubjectAbsenceGroup>[];

  final sampledDatesByWeekday = <int, Set<DateTime>>{};
  final countsBySubjectAndDate = <String, Map<DateTime, int>>{};
  if (referenceLessons != null && referenceLessons.isNotEmpty) {
    final activeRefs = referenceLessons
        .where((l) => !isInactivePlaceholderLesson(l) && !isLessonCancelled(l))
        .toList();
    final sourceLessons = activeRefs.isNotEmpty ? activeRefs : referenceLessons;
    for (final lesson in sourceLessons) {
      final localStart = lesson.start.toLocal();
      final day = DateTime(localStart.year, localStart.month, localStart.day);
      sampledDatesByWeekday
          .putIfAbsent(localStart.weekday, () => <DateTime>{})
          .add(day);
      final rawName = lesson.subject?.name ?? lesson.name;
      final display = prefs != null
          ? prefs.resolveSubjectName(rawName, lesson.subject?.uid)
          : rawName;
      final norm = display.trim().toLowerCase();
      if (norm.isEmpty) continue;
      final dayMap =
          countsBySubjectAndDate.putIfAbsent(norm, () => <DateTime, int>{});
      dayMap[day] = (dayMap[day] ?? 0) + 1;
    }
  }

  final sampledSchoolWeekdays =
      sampledDatesByWeekday.keys.where((w) => w >= 1 && w <= 5).length;

  double? computeObservedWeeklyAvg(String normKey) {
    final dayCounts = countsBySubjectAndDate[normKey];
    if (dayCounts == null || dayCounts.isEmpty) return null;
    double sum = 0.0;
    for (final entry in sampledDatesByWeekday.entries) {
      if (entry.key < 1 || entry.key > 5) continue;
      final datesOnWeekday = entry.value;
      if (datesOnWeekday.isEmpty) continue;
      var totalForWeekday = 0;
      for (final d in datesOnWeekday) {
        totalForWeekday += dayCounts[d] ?? 0;
      }
      sum += totalForWeekday / datesOnWeekday.length;
    }
    return sum > 0.0 ? sum : null;
  }

  final byKey = <String, List<Omission>>{};
  final displayNames = <String, String>{};
  final uids = <String, String>{};

  for (final o in omissions) {
    final resolvedName = prefs != null
        ? prefs.resolveSubjectName(o.subject.name, o.subject.uid).trim()
        : o.subject.name.trim();
    final safeName = resolvedName.isEmpty ? 'Ismeretlen tantárgy' : resolvedName;
    final normKey = safeName.toLowerCase();
    byKey.putIfAbsent(normKey, () => <Omission>[]).add(o);
    displayNames.putIfAbsent(normKey, () => safeName);
    if (o.subject.uid.trim().isNotEmpty) {
      uids.putIfAbsent(normKey, () => o.subject.uid.trim());
    }
  }

  final result = <SubjectAbsenceGroup>[];
  for (final entry in byKey.entries) {
    final normKey = entry.key;
    final subjectName = displayNames[normKey]!;
    final subjectUid = uids[normKey] ?? normKey;
    final sortedItems = List<Omission>.from(entry.value)
      ..sort((a, b) {
        final dateCmp = b.date.compareTo(a.date);
        if (dateCmp != 0) return dateCmp;
        final periodA = a.lesson?.classNo ?? 999;
        final periodB = b.lesson?.classNo ?? 999;
        return periodA.compareTo(periodB);
      });

    var missed = 0;
    var certified = 0;
    var uncertified = 0;
    var pending = 0;
    var tardinessCount = 0;
    var tardinessMinutes = 0;
    DateTime latestDate = sortedItems.first.date.toLocal();

    for (final o in sortedItems) {
      final localDate = o.date.toLocal();
      if (localDate.isAfter(latestDate)) {
        latestDate = localDate;
      }
      if (OmissionsSummary.isTardiness(o)) {
        tardinessCount++;
        tardinessMinutes += o.lateForMin ?? 0;
      } else {
        missed++;
        if (o.state == OmissionState.excused) {
          certified++;
        } else if (o.state == OmissionState.unexcused) {
          uncertified++;
        } else {
          pending++;
        }
      }
    }

    final explicitHeld = heldLessonsBySubject?[subjectUid] ??
        heldLessonsBySubject?[subjectName] ??
        heldLessonsBySubject?[normKey];

    late final int totalHeld;
    if (explicitHeld != null && explicitHeld > 0) {
      totalHeld = math.max(explicitHeld, missed);
    } else {
      final ref = referenceDate ?? latestDate;
      final schoolStart = KretaClient.getFirstSchoolDay(ref);
      final elapsedDays = ref.difference(schoolStart).inDays;
      final elapsedWeeks =
          elapsedDays > 0 ? (elapsedDays / 7.0).clamp(1.0, 38.0) : 10.0;
      final dayMap = countsBySubjectAndDate[normKey];
      final maxObservedDay = (dayMap != null && dayMap.isNotEmpty)
          ? dayMap.values.reduce(math.max)
          : null;
      final weeklyFreq = _estimateSubjectWeeklyFrequency(
        normKey,
        subjectOmissions: sortedItems,
        observedCount: maxObservedDay,
        sampledWeekdays: sampledSchoolWeekdays,
        observedWeeklyAvg: computeObservedWeeklyAvg(normKey),
      );
      final estimatedHeld = (elapsedWeeks * weeklyFreq).round();
      totalHeld = math.max(
        missed + tardinessCount,
        math.max(weeklyFreq, estimatedHeld),
      );
    }

    result.add(
      SubjectAbsenceGroup(
        subjectKey: subjectUid,
        subjectName: subjectName,
        items: List<Omission>.unmodifiable(sortedItems),
        missedHours: missed,
        certifiedHours: certified,
        uncertifiedHours: uncertified,
        pendingHours: pending,
        tardinessCount: tardinessCount,
        tardinessMinutes: tardinessMinutes,
        totalHeldLessons: totalHeld,
      ),
    );
  }

  result.sort((a, b) {
    final missedCmp = b.missedHours.compareTo(a.missedHours);
    if (missedCmp != 0) return missedCmp;
    final tardyCmp = b.tardinessMinutes.compareTo(a.tardinessMinutes);
    if (tardyCmp != 0) return tardyCmp;
    return a.subjectName.toLowerCase().compareTo(b.subjectName.toLowerCase());
  });
  return result;
}

/// Groups omissions by local calendar date (newest day first), sorting entries
/// within each day by lesson period (`classNo`) ascending.
List<DailyOmissionGroup> groupOmissionsByDay(List<Omission> omissions) {
  final grouped = <DateTime, List<Omission>>{};
  for (final o in omissions) {
    final local = o.date.toLocal();
    final dayKey = DateTime(local.year, local.month, local.day);
    grouped.putIfAbsent(dayKey, () => <Omission>[]).add(o);
  }

  final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
  return sortedDays.map((day) {
    final entries = grouped[day]!
      ..sort((a, b) {
        final periodA = a.lesson?.classNo ?? 999;
        final periodB = b.lesson?.classNo ?? 999;
        final periodCmp = periodA.compareTo(periodB);
        if (periodCmp != 0) return periodCmp;
        final startA = a.lesson?.start ?? a.date;
        final startB = b.lesson?.start ?? b.date;
        final timeCmp = startA.compareTo(startB);
        if (timeCmp != 0) return timeCmp;
        return a.subject.name.compareTo(b.subject.name);
      });
    return DailyOmissionGroup(day: day, entries: List.unmodifiable(entries));
  }).toList(growable: false);
}

/// Formats a calendar day concisely as Hungarian `Month Day. • Weekday`.
String formatHungarianOmissionDay(DateTime day, {int? referenceYear}) {
  const shortMonths = [
    'Jan.',
    'Feb.',
    'Már.',
    'Ápr.',
    'Máj.',
    'Jún.',
    'Júl.',
    'Aug.',
    'Szept.',
    'Okt.',
    'Nov.',
    'Dec.',
  ];
  const weekdays = [
    '',
    'Hétfő',
    'Kedd',
    'Szerda',
    'Csütörtök',
    'Péntek',
    'Szombat',
    'Vasárnap',
  ];
  final currentYear = referenceYear ?? DateTime.now().year;
  final yearPrefix = day.year == currentYear ? '' : '${day.year}. ';
  final month = shortMonths[(day.month - 1).clamp(0, 11)];
  final weekday = weekdays[day.weekday.clamp(1, 7)];
  return '$yearPrefix$month ${day.day}. • $weekday';
}

List<Omission> _filterOmissions(
  OmissionsSummary summary,
  _AttendanceFilter filter,
) {
  switch (filter) {
    case _AttendanceFilter.certified:
      return summary.missedLessons
          .where((o) => o.state == OmissionState.excused)
          .toList();
    case _AttendanceFilter.uncertified:
      return summary.missedLessons
          .where((o) => o.state != OmissionState.excused)
          .toList();
    case _AttendanceFilter.tardiness:
      return summary.tardinessEntries;
    case _AttendanceFilter.all:
      return summary.allOmissions;
  }
}

Widget _buildOmissionFilterChips({
  required _AttendanceFilter selected,
  required ValueChanged<_AttendanceFilter> onSelected,
  bool? liquidGlassEnabled,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
  PageController? pageController,
  bool ignorePageController = false,
}) {
  IconData iconFor(_AttendanceFilter f) {
    switch (f) {
      case _AttendanceFilter.all:
        return Icons.view_stream_rounded;
      case _AttendanceFilter.certified:
        return Icons.verified_rounded;
      case _AttendanceFilter.uncertified:
        return Icons.report_problem_rounded;
      case _AttendanceFilter.tardiness:
        return Icons.schedule_rounded;
    }
  }

  final selectedIdx = _AttendanceFilter.values.indexOf(selected);
  return LiquidBubbleTabBar(
    padding: padding,
    height: 40,
    fontSize: 12.5,
    itemPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    liquidGlassEnabled: liquidGlassEnabled,
    pageController: pageController,
    ignorePageController: ignorePageController,
    selectedIndex: selectedIdx < 0 ? 0 : selectedIdx,
    items: [
      for (final f in _AttendanceFilter.values)
        LiquidBubbleTabItem(
          label: uwuLabel(f.label),
          icon: iconFor(f),
        ),
    ],
    onSelected: (idx) => onSelected(_AttendanceFilter.values[idx]),
  );
}

Widget _buildEmptyOmissionCard({
  required UserProfilePrefs prefs,
  required String message,
}) {
  return SoftGlassCard(
    prefs: prefs,
    padding: const EdgeInsets.all(20),
    borderRadius: OledTheme.largeRadius,
    child: Row(
      children: [
        Icon(
          Icons.verified_rounded,
          color: Colors.greenAccent.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(uwu(message, enabled: prefs.uwuModeEnabled)),
        ),
      ],
    ),
  );
}

void _showOmissionDetailModal(
  BuildContext context, {
  required UserProfilePrefs prefs,
  required DateFormat dateFormat,
  required Omission omission,
  String? heroTag,
}) {
  final isLate = OmissionsSummary.isTardiness(omission);
  final isExcused = omission.state == OmissionState.excused;
  final isUnexcused = omission.state == OmissionState.unexcused;
  final statusColor = _omissionStatusColor(
    omission,
    Theme.of(context).brightness,
  );
  final statusLabel = isExcused
      ? 'Igazolt'
      : isUnexcused
          ? 'Igazolatlan'
          : 'Igazolandó';
  final subjDisplay = prefs.resolveSubjectName(
    omission.subject.name,
    omission.subject.uid,
  );
  final teacherClean = prefs.resolveTeacherName(omission.teacher).trim();
  final classNo = omission.lesson?.classNo;
  final proofDesc = omission.proofType?.description.trim() ?? '';

  showFrostedModal(
    context: context,
    closeMode: prefs.modalCloseMode,
    prefs: prefs,
    heroTag: heroTag,
    categoryIcon: Icons.event_busy_rounded,
    accentColor: statusColor,
    title: subjDisplay,
    subtitle: isLate
        ? 'Késés (${omission.lateForMin ?? 0} perc) • $statusLabel'
        : 'Hiányzás • $statusLabel',
    badgeText: isLate
        ? '${omission.lateForMin ?? 0}p'
        : (classNo != null ? '$classNo.' : '!'),
    badgeShape: BoxShape.circle,
    rows: [
      FrostedDetailRow(
        label: 'Dátum',
        value: dateFormat.format(omission.date.toLocal()),
      ),
      if (classNo != null)
        FrostedDetailRow(
          label: 'Óra',
          value: '$classNo. óra',
        ),
      FrostedDetailRow(
        label: 'Státusz',
        value: statusLabel,
        valueColor: statusColor,
      ),
      if (proofDesc.isNotEmpty)
        FrostedDetailRow(
          label: 'Igazolás',
          value: proofDesc,
        ),
      if (teacherClean.isNotEmpty)
        FrostedDetailRow(
          label: 'Tanár',
          value: teacherClean,
        ),
    ],
  );
}

String _omissionStatusLabel(Omission o) {
  switch (o.state) {
    case OmissionState.excused:
      return 'Igazolt';
    case OmissionState.unexcused:
      return 'Igazolatlan';
    case OmissionState.pending:
    case OmissionState.unknown:
      return 'Igazolandó';
  }
}

Color _omissionStatusColor(
  Omission o, [
  Brightness brightness = Brightness.dark,
]) {
  switch (o.state) {
    case OmissionState.excused:
      return OledTheme.omissionExcusedColor(brightness);
    case OmissionState.unexcused:
      return OledTheme.omissionUnexcusedRedColor(brightness);
    case OmissionState.pending:
    case OmissionState.unknown:
      return OledTheme.omissionPendingOrangeColor(brightness);
  }
}

class _SubjectAbsenceCard extends StatelessWidget {
  final SubjectAbsenceGroup group;
  final UserProfilePrefs prefs;
  final DateFormat dateFormat;

  const _SubjectAbsenceCard({
    required this.group,
    required this.prefs,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final min = MinimalistTokens.of(prefs);
    final pctColor = resolveAbsencePercentageColor(
      group.absencePercentage,
      scheme,
    );
    final pendingOrange = OledTheme.omissionPendingOrangeColor(theme.brightness);
    final hasPendingItems = group.pendingHours > 0 ||
        group.items.any((o) => OmissionsSummary.isPendingExcuse(o));

    final parts = <String>[
      '${group.missedHours} / ${group.totalHeldLessons} óra',
      if (group.uncertifiedHours > 0) '${group.uncertifiedHours} igazolatlan',
      if (group.pendingHours > 0) '${group.pendingHours} igazolandó',
      if (group.tardinessCount > 0)
        '${group.tardinessCount} késés (${group.tardinessMinutes}p)',
    ];
    final progressValue = group.missedHours <= 0
        ? 0.0
        : (group.absencePercentage / 30.0).clamp(0.04, 1.0);

    return TactileBounce(
      pressedScale: 0.985,
      onTap: () => _showSubjectAbsencesSheet(
        context,
        group: group,
        prefs: prefs,
        dateFormat: dateFormat,
      ),
      child: SoftGlassCard(
        prefs: prefs,
        borderRadius: min.enabled ? min.cardRadius : OledTheme.largeRadius,
        border: hasPendingItems
            ? Border.all(
                color: pendingOrange.withValues(alpha: 0.44),
                width: min.borderWidth,
              )
            : null,
        child: ClipRRect(
          borderRadius: min.enabled ? min.cardRadius : OledTheme.largeRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: min.enabled
                    ? const EdgeInsets.fromLTRB(10, 7, 10, 6)
                    : const EdgeInsets.fromLTRB(16, 14, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uwuLabel(
                              group.subjectName,
                              enabled: prefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: min.enabled ? 13 : 15.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: scheme.onSurface,
                            ),
                          ),
                          SizedBox(height: min.enabled ? 2 : 4),
                          Text(
                            uwuLabel(
                              parts.join(' • '),
                              enabled: prefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: min.enabled ? 11 : 12.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.60),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasPendingItems) ...[
                      SizedBox(width: min.enabled ? 5 : 8),
                      Container(
                        key: ValueKey<String>(
                          'subject-pending-badge-${group.subjectKey}',
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: min.enabled ? 6 : 8,
                          vertical: min.enabled ? 2.5 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: pendingOrange.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(
                            min.enabled ? 6 : 9,
                          ),
                          border: Border.all(
                            color: pendingOrange.withValues(alpha: 0.40),
                          ),
                        ),
                        child: Text(
                          uwuLabel(
                            'Igazolandó',
                            enabled: prefs.uwuModeEnabled,
                          ),
                          style: TextStyle(
                            fontSize: min.enabled ? 10 : 11,
                            fontWeight: FontWeight.w800,
                            color: pendingOrange,
                          ),
                        ),
                      ),
                    ],
                    SizedBox(width: min.enabled ? 6 : 8),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: min.enabled ? 7 : 10,
                        vertical: min.enabled ? 3 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: pctColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          min.enabled ? 7 : 10,
                        ),
                        border: Border.all(
                          color: pctColor.withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        '${group.absencePercentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: min.enabled ? 11.5 : 13.5,
                          fontWeight: FontWeight.w800,
                          color: pctColor,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: min.enabled ? 16 : 18,
                      color: scheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: min.enabled ? 2 : 3,
                child: LinearProgressIndicator(
                  value: progressValue,
                  backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showSubjectAbsencesSheet(
  BuildContext context, {
  required SubjectAbsenceGroup group,
  required UserProfilePrefs prefs,
  required DateFormat dateFormat,
}) {
  HapticFeedback.lightImpact();
  final timeFmt = DateFormat('HH:mm');
  return showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(context, prefs: prefs),
    builder: (sheetContext) {
      final closeMode = prefs.modalCloseMode;
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final pctColor = resolveAbsencePercentageColor(
        group.absencePercentage,
        scheme,
      );
      final hairline =
          scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);

      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84,
          ),
          child: FrostedBottomSheetSurface(
            prefs: prefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uwuLabel(
                              group.subjectName,
                              enabled: prefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            uwuLabel(
                              '${group.missedHours} / ${group.totalHeldLessons} óra • ${group.absencePercentage.toStringAsFixed(1)}%',
                              enabled: prefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: pctColor,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (closeMode.showTopX) ...[
                      const SizedBox(width: 8),
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, thickness: 1, color: hairline),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: group.items.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, thickness: 1, color: hairline),
                    itemBuilder: (itemCtx, idx) {
                      final o = group.items[idx];
                      final isLate = OmissionsSummary.isTardiness(o);
                      final statusColor = _omissionStatusColor(
                        o,
                        theme.brightness,
                      );
                      final statusLabel = isLate
                          ? 'Késés (${o.lateForMin ?? 0}p)'
                          : _omissionStatusLabel(o);
                      final classNo = o.lesson?.classNo;
                      final periodLabel = classNo != null ? '$classNo.' : '-';
                      final dayText = formatHungarianOmissionDay(o.date);
                      final timeRange = o.lesson != null
                          ? '${timeFmt.format(o.lesson!.start.toLocal())} - ${timeFmt.format(o.lesson!.end.toLocal())}'
                          : '';

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showOmissionDetailModal(
                          sheetContext,
                          prefs: prefs,
                          dateFormat: dateFormat,
                          omission: o,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  periodLabel,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      uwuLabel(
                                        dayText,
                                        enabled: prefs.uwuModeEnabled,
                                      ),
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (timeRange.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        uwuLabel(
                                          classNo != null
                                              ? '$classNo. óra • $timeRange'
                                              : timeRange,
                                          enabled: prefs.uwuModeEnabled,
                                        ),
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          fontSize: 12,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.56),
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  uwuLabel(
                                    statusLabel,
                                    enabled: prefs.uwuModeEnabled,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 14),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(sheetContext).pop(),
                    uwuEnabled: prefs.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CompactDayOmissionCard extends StatelessWidget {
  final DailyOmissionGroup group;
  final UserProfilePrefs prefs;
  final DateFormat dateFormat;
  final StoredSession? session;
  final KretaClient? kretaClient;
  final List<Lesson>? referenceLessons;

  const _CompactDayOmissionCard({
    required this.group,
    required this.prefs,
    required this.dateFormat,
    this.session,
    this.kretaClient,
    this.referenceLessons,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final headerColor = group.resolveAccentColor(theme.brightness);
    final hasPendingHighlight = group.pendingCount > 0 ||
        group.entries.any((o) => OmissionsSummary.isPendingExcuse(o));
    final subjectNames = <String>[];
    final seenSubjects = <String>{};
    for (final o in group.entries) {
      final resolved = prefs.resolveSubjectName(o.subject.name, o.subject.uid);
      final clean = resolved.trim();
      if (clean.isNotEmpty && seenSubjects.add(clean.toLowerCase())) {
        subjectNames.add(clean);
      }
    }
    final subjectsSummary = subjectNames.join(', ');

    return TactileBounce(
      pressedScale: 0.985,
      onTap: () => showDayTimetableOmissionsSheet(
        context,
        group: group,
        prefs: prefs,
        dateFormat: dateFormat,
        session: session,
        kretaClient: kretaClient,
        dayLessons: (session != null && kretaClient != null)
            ? kretaClient!.getCachedTimetableForDate(session!, group.day)
            : null,
        referenceLessons: referenceLessons,
      ),
      child: SoftGlassCard(
        prefs: prefs,
        borderRadius: OledTheme.largeRadius,
        border: hasPendingHighlight
            ? Border.all(color: headerColor.withValues(alpha: 0.42))
            : null,
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    uwuLabel(
                      formatHungarianOmissionDay(group.day),
                      enabled: prefs.uwuModeEnabled,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subjectsSummary.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      uwuLabel(
                        subjectsSummary,
                        enabled: prefs.uwuModeEnabled,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        color: scheme.onSurface.withValues(alpha: 0.60),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: headerColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: headerColor.withValues(alpha: 0.36),
                    ),
                  ),
                  child: Text(
                    uwuLabel(
                      group.summaryLabel,
                      enabled: prefs.uwuModeEnabled,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: headerColor,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: headerColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      uwuLabel(
                        group.statusLabel,
                        enabled: prefs.uwuModeEnabled,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: headerColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a Timetable-Style Day View bottom sheet displaying that day's lessons
/// in chronological order (`1.`, `2.`, `3.`...) with every missed lesson clearly
/// highlighted in red.
Future<void> showDayTimetableOmissionsSheet(
  BuildContext context, {
  required DailyOmissionGroup group,
  required UserProfilePrefs prefs,
  DateFormat? dateFormat,
  StoredSession? session,
  KretaClient? kretaClient,
  List<Lesson>? dayLessons,
  List<Lesson>? referenceLessons,
}) {
  HapticFeedback.lightImpact();
  return showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(context, prefs: prefs),
    builder: (_) => _DayTimetableOmissionsSheet(
      group: group,
      prefs: prefs,
      dateFormat: dateFormat ?? DateFormat('yyyy. MM. dd.'),
      session: session,
      kretaClient: kretaClient,
      initialDayLessons: dayLessons,
      referenceLessons: referenceLessons,
    ),
  );
}

class DayTimetableSlot {
  final int? classNo;
  final String subjectName;
  final String timeRange;
  final String roomName;
  final DateTime? sortTime;
  final Omission? omission;

  const DayTimetableSlot({
    required this.classNo,
    required this.subjectName,
    required this.timeRange,
    required this.roomName,
    this.sortTime,
    this.omission,
  });

  bool get isMissed => omission != null;
}

/// Merges a calendar day's timetable [dayLessons] with all [omissions] for
/// that date without dropping unnumbered lessons or missed periods absent
/// from the timetable response, sorted chronologically (`1.`, `2.`, `3.`...).
List<DayTimetableSlot> mergeDayTimetableWithOmissions({
  required DateTime day,
  required List<Omission> omissions,
  required List<Lesson> dayLessons,
  required UserProfilePrefs prefs,
}) {
  final timeFmt = DateFormat('HH:mm');
  final sortedLessons = List<Lesson>.from(dayLessons)
    ..sort((a, b) {
      if (a.lessonNumber != null && b.lessonNumber != null) {
        final cmp = a.lessonNumber!.compareTo(b.lessonNumber!);
        if (cmp != 0) return cmp;
      }
      final tCmp = a.start.toLocal().compareTo(b.start.toLocal());
      if (tCmp != 0) return tCmp;
      return a.name.compareTo(b.name);
    });

  final matchedOmissions = List<Omission?>.filled(sortedLessons.length, null);
  final unmatchedOmissions = <Omission>[];

  for (final om in omissions) {
    final targetNo = om.lesson?.classNo;
    final omStart = om.lesson?.start.toLocal();
    final omSubjNorm = prefs
        .resolveSubjectName(om.subject.name, om.subject.uid)
        .trim()
        .toLowerCase();

    int? bestIdx;
    // 1. Match by period number (prefer subject match on split lessons).
    if (targetNo != null && targetNo >= 0) {
      for (int i = 0; i < sortedLessons.length; i++) {
        if (matchedOmissions[i] != null) continue;
        if (sortedLessons[i].lessonNumber != targetNo) continue;
        bestIdx ??= i;
        final lessonSubjNorm = prefs
            .resolveSubjectName(
              sortedLessons[i].subject?.name ?? sortedLessons[i].name,
              sortedLessons[i].subject?.uid,
            )
            .trim()
            .toLowerCase();
        if (lessonSubjNorm == omSubjNorm && omSubjNorm.isNotEmpty) {
          bestIdx = i;
          break;
        }
      }
    }

    // 2. Fallback match by start time proximity (<= 15 minutes).
    if (bestIdx == null && omStart != null) {
      int bestDiff = 999999;
      for (int i = 0; i < sortedLessons.length; i++) {
        if (matchedOmissions[i] != null) continue;
        final diff = sortedLessons[i]
            .start
            .toLocal()
            .difference(omStart)
            .inMinutes
            .abs();
        if (diff <= 15) {
          final lessonSubjNorm = prefs
              .resolveSubjectName(
                sortedLessons[i].subject?.name ?? sortedLessons[i].name,
                sortedLessons[i].subject?.uid,
              )
              .trim()
              .toLowerCase();
          final subjectMatches =
              omSubjNorm.isNotEmpty && lessonSubjNorm == omSubjNorm;
          if (subjectMatches || diff < bestDiff) {
            bestIdx = i;
            bestDiff = diff;
            if (subjectMatches && diff == 0) break;
          }
        }
      }
    }

    // 3. Fallback match by subject name when period/time metadata is absent.
    if (bestIdx == null &&
        targetNo == null &&
        om.lesson == null &&
        omSubjNorm.isNotEmpty) {
      for (int i = 0; i < sortedLessons.length; i++) {
        if (matchedOmissions[i] != null) continue;
        final lessonSubjNorm = prefs
            .resolveSubjectName(
              sortedLessons[i].subject?.name ?? sortedLessons[i].name,
              sortedLessons[i].subject?.uid,
            )
            .trim()
            .toLowerCase();
        if (lessonSubjNorm == omSubjNorm) {
          bestIdx = i;
          break;
        }
      }
    }

    if (bestIdx != null) {
      matchedOmissions[bestIdx] = om;
    } else {
      unmatchedOmissions.add(om);
    }
  }

  final slots = <DayTimetableSlot>[];
  for (int i = 0; i < sortedLessons.length; i++) {
    final lesson = sortedLessons[i];
    final om = matchedOmissions[i];
    final rawSubj = (om != null && om.subject.name.trim().isNotEmpty)
        ? om.subject.name
        : (lesson.subject?.name ?? lesson.name);
    final rawUid = (om != null && om.subject.uid.trim().isNotEmpty)
        ? om.subject.uid
        : lesson.subject?.uid;
    final subj = prefs.resolveSubjectName(rawSubj, rawUid);
    final startLocal = lesson.start.toLocal();
    final endLocal = lesson.end.toLocal();
    final timeSpan =
        '${timeFmt.format(startLocal)} - ${timeFmt.format(endLocal)}';
    slots.add(
      DayTimetableSlot(
        classNo: om?.lesson?.classNo ?? lesson.lessonNumber,
        subjectName: subj,
        timeRange: timeSpan,
        roomName: (lesson.roomName ?? '').trim(),
        sortTime: startLocal,
        omission: om,
      ),
    );
  }

  for (final om in unmatchedOmissions) {
    final subj = prefs.resolveSubjectName(om.subject.name, om.subject.uid);
    final omLesson = om.lesson;
    final timeSpan = omLesson != null
        ? '${timeFmt.format(omLesson.start.toLocal())} - ${timeFmt.format(omLesson.end.toLocal())}'
        : '';
    slots.add(
      DayTimetableSlot(
        classNo: omLesson?.classNo,
        subjectName: subj,
        timeRange: timeSpan,
        roomName: '',
        sortTime: omLesson?.start.toLocal() ?? om.date.toLocal(),
        omission: om,
      ),
    );
  }

  slots.sort((a, b) {
    if (a.classNo != null && b.classNo != null) {
      final cmp = a.classNo!.compareTo(b.classNo!);
      if (cmp != 0) return cmp;
    }
    if (a.sortTime != null && b.sortTime != null) {
      final tCmp = a.sortTime!.compareTo(b.sortTime!);
      if (tCmp != 0) return tCmp;
    }
    if (a.classNo != null && b.classNo == null) return -1;
    if (a.classNo == null && b.classNo != null) return 1;
    return a.subjectName.toLowerCase().compareTo(b.subjectName.toLowerCase());
  });

  return slots;
}

class _DayTimetableOmissionsSheet extends StatefulWidget {
  final DailyOmissionGroup group;
  final UserProfilePrefs prefs;
  final DateFormat dateFormat;
  final StoredSession? session;
  final KretaClient? kretaClient;
  final List<Lesson>? initialDayLessons;
  final List<Lesson>? referenceLessons;

  const _DayTimetableOmissionsSheet({
    required this.group,
    required this.prefs,
    required this.dateFormat,
    this.session,
    this.kretaClient,
    this.initialDayLessons,
    this.referenceLessons,
  });

  @override
  State<_DayTimetableOmissionsSheet> createState() =>
      _DayTimetableOmissionsSheetState();
}

class _DayTimetableOmissionsSheetState
    extends State<_DayTimetableOmissionsSheet> {
  List<Lesson>? _fetchedDayLessons;
  bool _loadingDay = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialDayLessons ??
        ((widget.session != null && widget.kretaClient != null)
            ? widget.kretaClient!.getCachedTimetableForDate(
                widget.session!,
                widget.group.day,
              )
            : null);
    if (initial != null) {
      _fetchedDayLessons = initial;
    } else if (widget.session != null && widget.kretaClient != null) {
      _loadingDay = true;
      _loadDayTimetable();
    }
  }

  Future<void> _loadDayTimetable() async {
    if (!_loadingDay) {
      setState(() => _loadingDay = true);
    }
    try {
      final lessons = await widget.kretaClient!.fetchTimetableForDate(
        widget.session!,
        widget.group.day,
      );
      if (mounted) {
        setState(() {
          _fetchedDayLessons = lessons;
          _loadingDay = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _fetchedDayLessons ??= const <Lesson>[];
          _loadingDay = false;
        });
      }
    }
  }

  List<DayTimetableSlot> _buildSlots() {
    final targetDay = DateUtils.dateOnly(widget.group.day);
    final exactRefLessons = (widget.referenceLessons ?? const <Lesson>[])
        .where((l) => DateUtils.dateOnly(l.start.toLocal()) == targetDay)
        .toList();
    final sourceLessons = (_fetchedDayLessons != null &&
            _fetchedDayLessons!.isNotEmpty)
        ? _fetchedDayLessons!
        : exactRefLessons;
    return mergeDayTimetableWithOmissions(
      day: widget.group.day,
      omissions: widget.group.entries,
      dayLessons: sourceLessons,
      prefs: widget.prefs,
    );
  }

  Widget _buildLoadingSkeleton(
    ThemeData theme,
    ColorScheme scheme,
    bool isDark,
  ) {
    final fill = scheme.onSurface.withValues(alpha: isDark ? 0.05 : 0.04);
    final border = scheme.onSurface.withValues(alpha: 0.06);
    final pill = scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.09);
    return ListView.separated(
      key: const ValueKey<String>('day-timetable-loading'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, idx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: pill,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: idx.isEven ? 0.58 : 0.72,
                    child: Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: pill,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  FractionallySizedBox(
                    widthFactor: 0.36,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: pill.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final groupAccent = widget.group.resolveAccentColor(theme.brightness);
    final hairline =
        scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);
    final slots = _loadingDay ? const <DayTimetableSlot>[] : _buildSlots();

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: FrostedBottomSheetSurface(
          prefs: widget.prefs,
          showDragHandle: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwuLabel(
                            formatHungarianOmissionDay(widget.group.day),
                            enabled: widget.prefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          uwuLabel(
                            '${widget.group.summaryLabel} • Napi órarend nézet',
                            enabled: widget.prefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: groupAccent,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingDay)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (widget.prefs.modalCloseMode.showTopX) ...[
                    const SizedBox(width: 8),
                    PopupTopCloseButton(
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, thickness: 1, color: hairline),
              const SizedBox(height: 10),
              Flexible(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _loadingDay
                      ? _buildLoadingSkeleton(theme, scheme, isDark)
                      : ListView.separated(
                          key: const ValueKey<String>('day-timetable-loaded'),
                          shrinkWrap: true,
                          itemCount: slots.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (itemCtx, idx) {
                            final slot = slots[idx];
                            final omission = slot.omission;
                            final isMissed = omission != null;
                            final isLate = isMissed &&
                                OmissionsSummary.isTardiness(omission);
                            final slotColor = isMissed
                                ? _omissionStatusColor(
                                    omission,
                                    theme.brightness,
                                  )
                                : null;
                            final periodLabel =
                                slot.classNo != null ? '${slot.classNo}.' : '•';

                            final cardFill = slotColor != null
                                ? slotColor.withValues(
                                    alpha: isDark ? 0.16 : 0.11,
                                  )
                                : scheme.onSurface
                                    .withValues(alpha: isDark ? 0.04 : 0.03);
                            final cardBorder = slotColor != null
                                ? slotColor.withValues(
                                    alpha: isDark ? 0.48 : 0.40,
                                  )
                                : scheme.onSurface.withValues(alpha: 0.07);

                            final metaParts = <String>[
                              if (slot.timeRange.isNotEmpty) slot.timeRange,
                              if (slot.roomName.isNotEmpty)
                                uwuLabel(
                                  slot.roomName,
                                  enabled: widget.prefs.uwuModeEnabled,
                                ),
                            ];

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: omission != null
                                  ? () => _showOmissionDetailModal(
                                        context,
                                        prefs: widget.prefs,
                                        dateFormat: widget.dateFormat,
                                        omission: omission,
                                      )
                                  : null,
                              child: Container(
                                key: ValueKey<String>(
                                  'day-timetable-slot-${slot.classNo ?? idx}',
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: cardFill,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: cardBorder,
                                    width: isMissed ? 1.2 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34,
                                      height: 34,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: slotColor ??
                                            scheme.onSurface
                                                .withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        periodLabel,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isMissed
                                              ? Colors.white
                                              : scheme.onSurface
                                                  .withValues(alpha: 0.65),
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            uwuLabel(
                                              slot.subjectName,
                                              enabled:
                                                  widget.prefs.uwuModeEnabled,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontSize: 14,
                                              fontWeight: isMissed
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: isMissed
                                                  ? scheme.onSurface
                                                  : scheme.onSurface
                                                      .withValues(alpha: 0.68),
                                            ),
                                          ),
                                          if (metaParts.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              metaParts.join(' • '),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontSize: 11.5,
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.54),
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (omission != null && slotColor != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              slotColor.withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          uwuLabel(
                                            isLate
                                                ? 'Késés (${omission.lateForMin ?? 0}p) • ${_omissionStatusLabel(omission)}'
                                                : 'Hiányzás • ${_omissionStatusLabel(omission)}',
                                            enabled:
                                                widget.prefs.uwuModeEnabled,
                                          ),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: slotColor,
                                          ),
                                        ),
                                      ),
                                    ] else
                                      Text(
                                        uwuLabel('Megtartva'),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontSize: 11,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.42),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              if (widget.prefs.modalCloseMode.showBottomButton) ...[
                const SizedBox(height: 14),
                PopupBottomCloseButton(
                  onTap: () => Navigator.of(context).pop(),
                  uwuEnabled: widget.prefs.uwuModeEnabled,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Standalone full-screen App Settings page opened EXCLUSIVELY from the
/// top-right Profile & Settings sheet in the HomeScreen AppBar.
/// Maintains its own reactive `_prefs` state so all checkmarks and sliders
/// update on the exact frame the user interacts with them.
class AppSettingsScreen extends StatefulWidget {
  final StoredSession session;
  final Student? student;
  final KretaClient kretaClient;
  final DashboardData? dashboardData;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;
  final WearSyncService? wearSyncService;

  const AppSettingsScreen({
    super.key,
    required this.session,
    required this.student,
    required this.kretaClient,
    this.dashboardData,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
    this.wearSyncService,
  });

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  late UserProfilePrefs _prefs;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs;
  }

  @override
  void didUpdateWidget(covariant AppSettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      _prefs = widget.prefs;
    }
  }

  void _handlePrefsChanged(UserProfilePrefs next) {
    setState(() => _prefs = next);
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      if (!identical(scope.settings.prefs, next)) {
        unawaited(scope.settings.updatePrefs(next));
      }
    } else {
      TokenStorageService.saveProfilePrefsToSharedPrefs(next);
    }
    widget.onPrefsChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    Widget buildScaffold(UserProfilePrefs activePrefs) {
      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Alkalmazás beállítások'),
        ),
        body: MoreScreen(
          session: widget.session,
          student: widget.student,
          kretaClient: widget.kretaClient,
          dashboardData: widget.dashboardData,
          prefs: activePrefs,
          onPrefsChanged: _handlePrefsChanged,
          onLogout: widget.onLogout,
          settingsOnly: true,
          wearSyncService: widget.wearSyncService,
        ),
      );
    }

    if (scope == null) {
      return buildScaffold(_prefs);
    }
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (context, _) => buildScaffold(scope.settings.prefs),
    );
  }
}

/// "Továbbiak" tab (`settingsOnly == false`):
/// 1. Hiányzások és Késések (`/ellenorzo/v3/sajat/Mulasztasok`) module with
///    prominent "Összes hiányzás megtekintése" full-screen list button.
/// 2. Kréta Üzenetek (`/ellenorzo/v3/sajat/Uzenetek` - Beérkezett / Elküldött)
///    with Message Detail view and in-app Message Composer dialog featuring
///    live teacher/staff recipient autocomplete.
///
/// Main Settings screen (`settingsOnly == true`, opened exclusively via Profile):
/// Grouped accordions for MenetrendGO Commuter Transit, Appearance & Icons,
/// Grade Colors, Rounding & Timetable, JSON Backup, Account, and About App.
class MoreScreen extends StatefulWidget {
  final StoredSession session;
  final Student? student;
  final KretaClient? kretaClient;
  final DashboardData? dashboardData;
  final List<Omission> initialOmissions;
  final List<KretaMessage> initialMessages;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;
  final bool settingsOnly;

  /// When `true` (and not [settingsOnly]) only the Kréta messages module is
  /// shown; otherwise the non-settings view shows only absences (Hiányzások tab).
  final bool messagesOnly;

  /// Notified whenever the message list changes (refresh, read state).
  final ValueChanged<List<KretaMessage>>? onMessagesChanged;

  /// Whether this tab is currently visible in the bottom navigation IndexedStack.
  final bool isActiveTab;

  final WearSyncService? wearSyncService;

  const MoreScreen({
    super.key,
    required this.session,
    required this.student,
    this.kretaClient,
    this.dashboardData,
    this.initialOmissions = const [],
    this.initialMessages = const [],
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
    this.settingsOnly = false,
    this.messagesOnly = false,
    this.onMessagesChanged,
    this.isActiveTab = true,
    this.wearSyncService,
  });

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late UserProfilePrefs _currentPrefsStorage;
  SettingsProvider? _settingsProvider;

  UserProfilePrefs get _currentPrefs =>
      _settingsProvider?.prefs ?? _currentPrefsStorage;

  UserProfilePrefs _livePrefs(BuildContext ctx) =>
      AppProvidersScope.maybeOf(ctx)?.settings.prefs ?? _currentPrefs;

  set _currentPrefs(UserProfilePrefs value) {
    _currentPrefsStorage = value;
  }

  int _selectedGradeToCustomize = 5;
  _AttendanceFilter _attendanceFilter = _AttendanceFilter.all;
  late final PageController _attendancePageController =
      PageController(initialPage: _attendanceFilter.index);
  bool _isAnimatingAttendancePage = false;
  List<Lesson> _cachedWeekLessons = const <Lesson>[];
  bool _showSentMessages = false;
  late final PageController _messagesPageController =
      PageController(initialPage: _showSentMessages ? 1 : 0);
  bool _isAnimatingMessagesPage = false;
  bool _isLoadingModules = false;
  bool _markingAllRead = false;
  String _appVersion = GitHubUpdaterService.fallbackAppVersion;
  bool _initialEntrancePlayed = false;
  bool _entranceActive = false;

  static const MethodChannel _fileChannel =
      MethodChannel('hu.mlnlbrt.tintanaplo/updater');

  late List<Omission> _omissions;
  late List<KretaMessage> _messages;
  final Set<String> _readMessageIds = {};

  late final TextEditingController _homeAddressController;
  late final TextEditingController _schoolAddressController;
  final ValueNotifier<int> _stateVersion = ValueNotifier<int>(0);
  final TextEditingController _settingsSearchController =
      TextEditingController();
  String _settingsSearchQuery = '';
  CalendarSyncSettings? _calendarSyncSettings;
  WearConnectionStatus _wearStatus = WearConnectionStatus.disconnected;

  WearSyncService get _wearService =>
      widget.wearSyncService ?? WearSyncService.instance;

  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final DateFormat _dateTimeFormat = DateFormat('yyyy. MM. dd. HH:mm');

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _stateVersion.value++;
  }

  @override
  void initState() {
    super.initState();
    _currentPrefs = widget.prefs;
    GitHubUpdaterService.getAppVersionInfo().then((info) {
      if (mounted && info.$1.isNotEmpty) setState(() => _appVersion = info.$1);
    }).catchError((_) {});
    _omissions = List<Omission>.from(widget.initialOmissions);
    _messages = List<KretaMessage>.from(widget.initialMessages);
    if (_messages.isNotEmpty || _omissions.isNotEmpty) {
      // Cached content already available on first frame: avoid playing staggered
      // entrance animations on open / background refresh to eliminate flicker.
      _initialEntrancePlayed = true;
      _entranceActive = false;
    }
    _loadPersistedReadIds();
    _loadCalendarSyncSettings();
    if (widget.settingsOnly) {
      unawaited(_loadWearStatus());
    }
    _homeAddressController =
        TextEditingController(text: _currentPrefs.homeAddress);
    _schoolAddressController =
        TextEditingController(text: _currentPrefs.schoolAddress);

    if (!widget.settingsOnly &&
        widget.kretaClient != null &&
        (widget.messagesOnly || (_omissions.isEmpty && _messages.isEmpty))) {
      _refreshModules();
    } else if (widget.isActiveTab) {
      _armInitialEntranceIfNeeded();
    }
    if (!widget.settingsOnly && !widget.messagesOnly) {
      unawaited(_hydrateReferenceLessonsForAttendance());
    }
  }

  List<Lesson>? get _effectiveReferenceLessons {
    final merged = <String, Lesson>{};
    for (final l in [
      ..._cachedWeekLessons,
      ...?widget.dashboardData?.todaysLessons,
    ]) {
      final k = l.uid.trim().isNotEmpty
          ? l.uid.trim()
          : '${l.lessonNumber ?? ''}_${l.start.toIso8601String()}_${l.name}';
      merged[k] = l;
    }
    return merged.isEmpty ? null : merged.values.toList();
  }

  Future<void> _hydrateReferenceLessonsForAttendance() async {
    final client = widget.kretaClient;
    if (client == null) return;
    final fromCache = client.getAllCachedTimetableLessons(widget.session);
    final combined = <Lesson>[
      ...fromCache,
      ...?widget.dashboardData?.todaysLessons,
    ];
    if (combined.isNotEmpty && mounted) {
      setState(() => _cachedWeekLessons = combined);
    }
    final weekdays = combined
        .map((l) => l.start.toLocal().weekday)
        .where((w) => w >= 1 && w <= 5)
        .toSet();
    if (weekdays.length >= 4) return;
    try {
      final now = DateTime.now();
      final monday =
          DateUtils.dateOnly(now).subtract(Duration(days: now.weekday - 1));
      final friday = monday.add(const Duration(days: 4));
      final weekLessons = await client
          .fetchTimetableForRange(widget.session, from: monday, to: friday)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final refreshed = client.getAllCachedTimetableLessons(widget.session);
      final next = refreshed.isNotEmpty ? refreshed : weekLessons;
      if (next.isNotEmpty) {
        setState(() => _cachedWeekLessons = next);
      }
    } catch (_) {}
  }

  bool _isMessageRead(KretaMessage msg) {
    if (msg.isRead) return true;
    if (_readMessageIds.contains(msg.uid)) return true;
    if (msg.messageId != null && _readMessageIds.contains(msg.messageId)) {
      return true;
    }
    if (msg.isSystemMessage && _readMessageIds.contains('sys:${msg.uid}')) {
      return true;
    }
    return false;
  }

  Future<void> _loadWearStatus() async {
    final status = await _wearService.getConnectionStatus();
    if (!mounted) return;
    setState(() => _wearStatus = status);
  }

  void _loadPersistedReadIds() {
    const TokenStorageService()
        .loadReadMessageIds(
          accountKey: TokenStorageService.accountKeyForSession(widget.session),
        )
        .then((ids) {
      if (!mounted || ids.isEmpty) return;
      var changed = false;
      setState(() {
        _readMessageIds.addAll(ids);
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (!m.isRead && _isMessageRead(m)) {
            _messages[i] = m.copyWith(isRead: true);
            changed = true;
          }
        }
      });
      if (changed) {
        widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
      }
    }).catchError((_) {});
  }

  void _armInitialEntranceIfNeeded() {
    if (_initialEntrancePlayed) return;
    _initialEntrancePlayed = true;
    _entranceActive = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _entranceActive = false;
      }
    });
  }

  @override
  void didUpdateWidget(covariant MoreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs != oldWidget.prefs) {
      _currentPrefs = widget.prefs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _stateVersion.value++;
        }
      });
    }
    if (widget.prefs.demoModeEnabled != oldWidget.prefs.demoModeEnabled ||
        widget.session.instituteCode != oldWidget.session.instituteCode) {
      _omissions = List<Omission>.from(widget.initialOmissions);
      _messages = widget.initialMessages
          .map(
            (m) => !m.isRead && _isMessageRead(m) ? m.copyWith(isRead: true) : m,
          )
          .toList();
    } else if (widget.initialOmissions.isNotEmpty && _omissions.isEmpty) {
      _omissions = List<Omission>.from(widget.initialOmissions);
    }
    if (widget.initialMessages != oldWidget.initialMessages &&
        widget.initialMessages.isNotEmpty) {
      final merged = _mergeIncomingMessages(widget.initialMessages);
      if (_messagesFingerprint(merged) != _messagesFingerprint(_messages)) {
        _messages = merged;
      }
    }
    if (widget.isActiveTab && !oldWidget.isActiveTab && !_isLoadingModules) {
      if (_messages.isEmpty && _omissions.isEmpty) {
        setState(() {
          _armInitialEntranceIfNeeded();
        });
      }
    }
  }

  void _handleSettingsProviderChanged() {
    if (!mounted) return;
    final latest = _settingsProvider?.prefs;
    if (latest != null) {
      _currentPrefsStorage = latest;
    }
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextProvider = AppProvidersScope.maybeOf(context)?.settings;
    if (_settingsProvider != nextProvider) {
      _settingsProvider?.removeListener(_handleSettingsProviderChanged);
      _settingsProvider = nextProvider;
      _settingsProvider?.addListener(_handleSettingsProviderChanged);
    }
    if (_settingsProvider != null) {
      _currentPrefsStorage = _settingsProvider!.prefs;
    }
  }

  @override
  void dispose() {
    _settingsProvider?.removeListener(_handleSettingsProviderChanged);
    _settingsSearchController.dispose();
    _attendancePageController.dispose();
    _messagesPageController.dispose();
    _homeAddressController.dispose();
    _schoolAddressController.dispose();
    _stateVersion.dispose();
    super.dispose();
  }

  Future<void> _loadCalendarSyncSettings() async {
    final loaded = await CalendarSyncService.instance.loadSettings();
    if (!mounted) return;
    setState(() => _calendarSyncSettings = loaded);
  }

  void _updatePrefs(UserProfilePrefs nextPrefs) {
    var effectiveNext = nextPrefs;
    if (!_currentPrefs.transitConfigured &&
        effectiveNext.transitConfigured &&
        !effectiveNext.transitCardEnabled) {
      effectiveNext = effectiveNext.copyWith(transitCardEnabled: true);
    }
    UserProfilePrefs.syncActiveGlobals(effectiveNext);
    _currentPrefsStorage = effectiveNext;
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      // Update SettingsProvider & ThemeProvider synchronously BEFORE disk IO.
      unawaited(scope.settings.updatePrefs(effectiveNext));
    } else {
      TokenStorageService.saveProfilePrefsToSharedPrefs(effectiveNext);
    }
    if (mounted) {
      setState(() => _currentPrefsStorage = effectiveNext);
    } else {
      _stateVersion.value++;
    }
    widget.onPrefsChanged(effectiveNext);
  }

  /// Recalculates coordinate-derived walk times immediately when walking speed changes.
  UserProfilePrefs _withUpdatedWalkingSpeed(
    UserProfilePrefs current,
    double nextKmh,
  ) {
    var next = current.copyWith(walkingSpeedKmh: nextKmh);
    final homeLat = current.homeAddressLat;
    final homeLon = current.homeAddressLon;
    if (homeLat != null && homeLon != null) {
      final busLat = (current.extras['homeBusLat'] as num?)?.toDouble();
      final busLon = (current.extras['homeBusLon'] as num?)?.toDouble();
      if (busLat != null && busLon != null) {
        final mins = MenetrendService.estimateWalkingMinutesBetween(
          lat1: homeLat,
          lon1: homeLon,
          lat2: busLat,
          lon2: busLon,
          walkingSpeedKmh: nextKmh,
        );
        next = next.copyWith(
          walkHomeToBusMinutes: mins,
          walkingDurationMinutes: mins,
        );
      }
      final trainLat = (current.extras['homeTrainLat'] as num?)?.toDouble();
      final trainLon = (current.extras['homeTrainLon'] as num?)?.toDouble();
      if (trainLat != null && trainLon != null) {
        next = next.copyWith(
          walkHomeToTrainMinutes: MenetrendService.estimateWalkingMinutesBetween(
            lat1: homeLat,
            lon1: homeLon,
            lat2: trainLat,
            lon2: trainLon,
            walkingSpeedKmh: nextKmh,
          ),
        );
      }
    }

    final schoolLat = current.schoolAddressLat;
    final schoolLon = current.schoolAddressLon;
    if (schoolLat != null && schoolLon != null) {
      final busLat = (current.extras['schoolBusLat'] as num?)?.toDouble();
      final busLon = (current.extras['schoolBusLon'] as num?)?.toDouble();
      if (busLat != null && busLon != null) {
        next = next.copyWith(
          walkSchoolToBusMinutes: MenetrendService.estimateWalkingMinutesBetween(
            lat1: schoolLat,
            lon1: schoolLon,
            lat2: busLat,
            lon2: busLon,
            walkingSpeedKmh: nextKmh,
          ),
        );
      }
      final trainLat = (current.extras['schoolTrainLat'] as num?)?.toDouble();
      final trainLon = (current.extras['schoolTrainLon'] as num?)?.toDouble();
      if (trainLat != null && trainLon != null) {
        next = next.copyWith(
          walkSchoolToTrainMinutes:
              MenetrendService.estimateWalkingMinutesBetween(
            lat1: schoolLat,
            lon1: schoolLon,
            lat2: trainLat,
            lon2: trainLon,
            walkingSpeedKmh: nextKmh,
          ),
        );
      }
    }
    return next;
  }

  String _messagesFingerprint(List<KretaMessage> list) {
    final buf = StringBuffer();
    for (final m in list) {
      buf
        ..write(m.uid)
        ..write('|')
        ..write(_isMessageRead(m) ? '1' : '0')
        ..write('|')
        ..write(m.isSent ? '1' : '0')
        ..write('|')
        ..write(m.subject)
        ..write('|')
        ..write(m.body.length)
        ..write('|')
        ..write(m.sentAt.millisecondsSinceEpoch)
        ..write(';');
    }
    return buf.toString();
  }

  List<KretaMessage> _mergeIncomingMessages(List<KretaMessage> incoming) {
    final existingByKey = <String, KretaMessage>{
      for (final m in _messages) '${m.isSystemMessage}:${m.uid}': m,
    };
    return incoming.map((m) {
      final prev = existingByKey['${m.isSystemMessage}:${m.uid}'];
      final effectiveRead = m.isRead || _isMessageRead(m);
      var next = (effectiveRead && !m.isRead) ? m.copyWith(isRead: true) : m;
      if (prev != null && prev.detailsLoaded && !m.detailsLoaded) {
        next = next.copyWith(
          body: prev.body.isNotEmpty ? prev.body : next.body,
          recipients:
              prev.recipients.isNotEmpty ? prev.recipients : next.recipients,
          attachments:
              prev.attachments.isNotEmpty ? prev.attachments : next.attachments,
          detailsLoaded: true,
        );
      }
      return next;
    }).toList();
  }

  Future<void> _markAllMessagesAsRead() async {
    if (_markingAllRead) return;
    final unread =
        _messages.where((m) => !m.isSent && !_isMessageRead(m)).toList();
    if (unread.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _markingAllRead = true;
      for (final msg in unread) {
        _readMessageIds.add(msg.uid);
        if (msg.messageId != null && msg.messageId!.isNotEmpty) {
          _readMessageIds.add(msg.messageId!);
        }
        if (msg.isSystemMessage) {
          _readMessageIds.add('sys:${msg.uid}');
        }
      }
      _messages = _messages.map((m) {
        if (m.isSent || m.isRead) return m;
        if (_isMessageRead(m)) return m.copyWith(isRead: true);
        return m;
      }).toList();
    });
    widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));

    try {
      final client = widget.kretaClient;
      if (client != null) {
        await client.markAllMessagesAsRead(widget.session, unread);
      } else {
        final localKeys = <String>[
          for (final msg in unread) ...[
            msg.uid,
            if (msg.messageId != null && msg.messageId!.isNotEmpty)
              msg.messageId!,
            if (msg.isSystemMessage) 'sys:${msg.uid}',
          ],
        ];
        await const TokenStorageService().markMessagesReadLocally(
          localKeys,
          accountKey: TokenStorageService.accountKeyForSession(widget.session),
        );
      }
      if (mounted) {
        TintaToast.success(
          context,
          uwu('Minden üzenet olvasottként megjelölve (${unread.length} db).'),
        );
      }
    } catch (_) {
      if (mounted) {
        TintaToast.error(
          context,
          uwu('Nem sikerült az összes üzenet szinkronizálása.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _markingAllRead = false);
      }
    }
  }

  Future<void> _refreshModules() async {
    final client = widget.kretaClient;
    if (client == null) return;
    final hasCachedData = widget.messagesOnly
        ? _messages.isNotEmpty
        : (_omissions.isNotEmpty || _messages.isNotEmpty);
    if (mounted && !hasCachedData) {
      setState(() => _isLoadingModules = true);
    }
    try {
      if (widget.messagesOnly) {
        final fetchedMessages = await client
            .fetchMessages(widget.session)
            .timeout(const Duration(seconds: 15));
        if (!mounted) return;
        final merged = _mergeIncomingMessages(fetchedMessages);
        final changed =
            _messagesFingerprint(merged) != _messagesFingerprint(_messages);
        if (changed) {
          setState(() {
            _messages = merged;
            if (!hasCachedData && widget.isActiveTab) {
              _armInitialEntranceIfNeeded();
            }
          });
          widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
        }
        unawaited(
          KretaNotificationService.instance
              .processOmissionsAndMessagesDiff(
                session: widget.session,
                messages: fetchedMessages,
                profilePrefs: _currentPrefs,
              )
              .catchError((_) => const <TriggeredKretaNotification>[]),
        );
        return;
      }

      final results = await Future.wait<Object>([
        client.fetchOmissions(widget.session),
        client.fetchMessages(widget.session),
      ]).timeout(const Duration(seconds: 15));
      if (!mounted) return;
      final fetchedOmissions = results[0] as List<Omission>;
      final fetchedMessages = results[1] as List<KretaMessage>;
      final merged = _mergeIncomingMessages(fetchedMessages);
      final messagesChanged =
          _messagesFingerprint(merged) != _messagesFingerprint(_messages);
      final omissionsChanged = fetchedOmissions.length != _omissions.length;
      if (messagesChanged || omissionsChanged || _isLoadingModules) {
        setState(() {
          _omissions = fetchedOmissions;
          _messages = merged;
          if (!hasCachedData && widget.isActiveTab) {
            _armInitialEntranceIfNeeded();
          }
        });
        if (messagesChanged) {
          widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
        }
      }
      unawaited(
        KretaNotificationService.instance
            .processOmissionsAndMessagesDiff(
              session: widget.session,
              omissions: fetchedOmissions,
              messages: fetchedMessages,
              profilePrefs: _currentPrefs,
            )
            .catchError((_) => const <TriggeredKretaNotification>[]),
      );
      unawaited(_hydrateReferenceLessonsForAttendance());
    } catch (_) {
      // Keep cached attendance/messages intact on timeout or network failure.
    } finally {
      if (mounted && _isLoadingModules) {
        setState(() {
          _isLoadingModules = false;
          if (!hasCachedData && widget.isActiveTab) {
            _armInitialEntranceIfNeeded();
          }
        });
      }
    }
  }

  void _setThemeStyle(AppThemeStyle style) {
    HapticFeedback.selectionClick();
    final base = _currentPrefs;
    String nextIcon = base.appIconPreset;
    if (!base.isClassicAppIcon &&
        base.christmasModeEnabled &&
        (nextIcon == 'default' ||
            nextIcon == 'christmas' ||
            nextIcon == 'icon_christmas' ||
            nextIcon == 'icon_christmas_oled')) {
      nextIcon = style == AppThemeStyle.oledPureBlack
          ? 'icon_christmas_oled'
          : 'icon_christmas';
    }
    var next = base.copyWith(
      themeStyle: style,
      appIconPreset: nextIcon,
    );
    if (base.backgroundPreset != 'pure_oled' ||
        base.hasAnimatedBackdrop ||
        base.hasCustomBackdrop) {
      next = next.copyWith(
        backgroundPreset: 'pure_oled',
        animatedBackdropPreset: AnimatedBackdropPreset.off,
        clearCustomBackdropPath: true,
      );
    }
    _updatePrefs(next);
  }

  void _toggleDynamicColor(bool value) {
    HapticFeedback.selectionClick();
    _updatePrefs(_currentPrefs.copyWith(useDynamicColor: value));
  }

  void _setSeedColor(int colorVal) {
    HapticFeedback.selectionClick();
    _updatePrefs(
      _currentPrefs.copyWith(
        seedColorValue: colorVal,
        useDynamicColor: false,
      ),
    );
  }

  void _setGradeColor(int grade, int colorValue) {
    final nextMap = Map<int, int>.from(_currentPrefs.customGradeColors);
    nextMap[grade] = colorValue;
    _updatePrefs(_currentPrefs.copyWith(customGradeColors: nextMap));
  }

  void _resetGradeColors() {
    _updatePrefs(
      _currentPrefs.copyWith(
        customGradeColors: Map<int, int>.from(
          UserProfilePrefs.defaultGradeColors,
        ),
      ),
    );
  }

  Future<void> _promptCustomHexForGrade(int grade) async {
    final currentArgb = _currentPrefs.colorForGrade(grade).toARGB32();
    final currentHex = currentArgb
        .toRadixString(16)
        .padLeft(8, '0')
        .substring(2)
        .toUpperCase();
    final controller = TextEditingController(text: '#$currentHex');
    final result = await showFloatingGlassSheet<int>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final closeMode = _currentPrefs.modalCloseMode;
        final bottomInset = MediaQuery.viewInsetsOf(dialogContext).bottom;
        return SheetDisposableScope(
          disposables: [controller],
          builder: (_) => AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight:
                    (MediaQuery.sizeOf(dialogContext).height - bottomInset) *
                        0.86,
              ),
              child: FrostedBottomSheetSurface(
                prefs: _currentPrefs,
                showDragHandle: true,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: SingleChildScrollView(
                  physics: const FloatingSheetScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Color(currentArgb).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              Icons.palette_rounded,
                              size: 19,
                              color: Color(currentArgb),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Érdemjegy ($grade) egyedi HEX színe',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (closeMode.showTopX) ...[
                            const SizedBox(width: 8),
                            PopupTopCloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'HEX színkód (#RRGGBB)',
                          hintText: '#2E7D32',
                          prefixIcon: Icon(Icons.colorize_rounded),
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Mégse'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () {
                              final cleaned = controller.text
                                  .trim()
                                  .replaceAll('#', '')
                                  .toUpperCase();
                              if (RegExp(r'^[0-9A-F]{6}$').hasMatch(cleaned)) {
                                final parsed = int.parse('FF$cleaned', radix: 16);
                                Navigator.of(dialogContext).pop(parsed);
                              }
                            },
                            child: const Text('Alkalmaz'),
                          ),
                        ],
                      ),
                      if (closeMode.showBottomButton) ...[
                        const SizedBox(height: 12),
                        PopupBottomCloseButton(
                          onTap: () => Navigator.of(dialogContext).pop(),
                          uwuEnabled: _currentPrefs.uwuModeEnabled,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    if (result != null && mounted) {
      _setGradeColor(grade, result);
    }
  }

  void _previewRounding(GradeRoundingConfig nextConfig) {
    _updateRounding(nextConfig);
  }

  void _updateRounding(GradeRoundingConfig nextConfig) {
    _updatePrefs(_currentPrefs.copyWith(roundingConfig: nextConfig));
  }

  Future<void> _exportSettingsJson() async {
    HapticFeedback.lightImpact();
    final jsonStr = _currentPrefs.toExportJsonString();
    String? savedFilePath;

    final candidateDirs = <String>[
      '/storage/emulated/0/Download',
      Directory.systemTemp.path,
    ];
    for (final dirPath in candidateDirs) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final file = File('${dir.path}/tinta_naplo_settings_backup.json');
          await file.writeAsString(jsonStr);
          savedFilePath = file.path;
          break;
        }
      } catch (_) {}
    }

    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;

    await showFloatingGlassSheet<void>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final scheme = theme.colorScheme;
        final closeMode = _currentPrefs.modalCloseMode;
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.86,
          ),
          child: FrostedBottomSheetSurface(
            prefs: _currentPrefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: SingleChildScrollView(
              physics: const FloatingSheetScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(
                          Icons.upload_file_rounded,
                          size: 19,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Beállítások exportálva (JSON)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      if (closeMode.showTopX) ...[
                        const SizedBox(width: 8),
                        PopupTopCloseButton(
                          onTap: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (savedFilePath != null) ...[
                    Text(
                      'Mentve ide:\n$savedFilePath\n\nA JSON konfiguráció a vágólapra is felkerült.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ] else
                    const Text(
                      'A JSON konfiguráció a vágólapra lett másolva.',
                      style: TextStyle(fontSize: 13),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      jsonStr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Rendben'),
                    ),
                  ),
                  if (closeMode.showBottomButton) ...[
                    const SizedBox(height: 12),
                    PopupBottomCloseButton(
                      onTap: () => Navigator.of(dialogContext).pop(),
                      uwuEnabled: _currentPrefs.uwuModeEnabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _importSettingsJson() async {
    HapticFeedback.lightImpact();
    final pathController = TextEditingController();
    final jsonController = TextEditingController();

    final availableFiles = <File>[];
    for (final dirPath in [
      '/storage/emulated/0/Download',
      Directory.systemTemp.path,
    ]) {
      try {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final found = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.toLowerCase().endsWith('.json'))
              .take(8);
          availableFiles.addAll(found);
        }
      } catch (_) {}
    }

    final restoredPrefs = await showFloatingGlassSheet<UserProfilePrefs>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        String? errorMsg;
        return SheetDisposableScope(
          disposables: [pathController, jsonController],
          builder: (_) => StatefulBuilder(
            builder: (context, setModalState) {
              final theme = Theme.of(context);
              final scheme = theme.colorScheme;
              final closeMode = _currentPrefs.modalCloseMode;
              final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    maxHeight:
                        (MediaQuery.sizeOf(context).height - bottomInset) *
                            0.88,
                  ),
                  child: FrostedBottomSheetSurface(
                    prefs: _currentPrefs,
                    showDragHandle: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: SingleChildScrollView(
                      physics: const FloatingSheetScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.download_rounded,
                                  size: 19,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Beállítások importálása (JSON)',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (closeMode.showTopX) ...[
                                const SizedBox(width: 8),
                                PopupTopCloseButton(
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (availableFiles.isNotEmpty) ...[
                            const Text(
                              'Talált JSON mentésfájlok a készüléken:',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ...availableFiles.map((file) {
                              final name = file.path.split('/').last;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    try {
                                      final content = file.readAsStringSync();
                                      jsonController.text = content;
                                      pathController.text = file.path;
                                      setModalState(() => errorMsg = null);
                                    } catch (e) {
                                      setModalState(
                                        () => errorMsg =
                                            'Nem sikerült beolvasni: $e',
                                      );
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.insert_drive_file_rounded,
                                    size: 16,
                                  ),
                                  label: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],
                          TextField(
                            controller: pathController,
                            decoration: InputDecoration(
                              labelText: 'JSON fájl elérési útja (opcionális)',
                              hintText:
                                  '/storage/.../tinta_naplo_settings_backup.json',
                              prefixIcon: const Icon(Icons.folder_open_rounded),
                              suffixIcon: IconButton(
                                tooltip: 'Beolvasás fájlból',
                                onPressed: () {
                                  final p = pathController.text.trim();
                                  if (p.isEmpty) return;
                                  try {
                                    final f = File(p);
                                    jsonController.text = f.readAsStringSync();
                                    setModalState(() => errorMsg = null);
                                  } catch (e) {
                                    setModalState(
                                      () => errorMsg = 'Fájl hiba: $e',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.file_upload_rounded),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: jsonController,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Vagy illeszd be a JSON tartalmat',
                              hintText: '{"schemaVersion": 2, ...}',
                            ),
                          ),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              errorMsg!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Mégse'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () {
                                  try {
                                    String raw = jsonController.text.trim();
                                    if (raw.isEmpty &&
                                        pathController.text.trim().isNotEmpty) {
                                      raw = File(pathController.text.trim())
                                          .readAsStringSync();
                                    }
                                    final parsed =
                                        UserProfilePrefs.fromExportJsonString(
                                      raw,
                                    );
                                    Navigator.of(dialogContext).pop(parsed);
                                  } catch (e) {
                                    setModalState(
                                      () => errorMsg =
                                          'Érvénytelen JSON formátum: $e',
                                    );
                                  }
                                },
                                icon: const Icon(Icons.restore_rounded, size: 18),
                                label: const Text('Visszaállítás'),
                              ),
                            ],
                          ),
                          if (closeMode.showBottomButton) ...[
                            const SizedBox(height: 12),
                            PopupBottomCloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              uwuEnabled: _currentPrefs.uwuModeEnabled,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (restoredPrefs != null && mounted) {
      _updatePrefs(restoredPrefs);
      TintaToast.success(
        context,
        uwu('Beállítások sikeresen visszaállítva!'),
      );
    }
  }

  /// Collects all unique teacher and staff contact names from Kréta API data
  /// (`DashboardData`, lessons, grades, homeworks, tests, omissions, messages)
  /// for the Message Composer's recipient autocomplete.
  List<String> _collectTeacherAndStaffContacts() {
    final contacts = <String>{
      'Osztályfőnök',
      'Titkárság',
      'Igazgatóság',
      'Rendszergazda',
    };

    void addContact(String? raw) {
      if (raw == null) return;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return;
      contacts.add(_currentPrefs.resolveTeacherName(trimmed));
      contacts.add(trimmed);
    }

    final dash = widget.dashboardData;
    if (dash != null) {
      for (final lesson in dash.todaysLessons) {
        addContact(lesson.teacher);
        addContact(lesson.substituteTeacher);
      }
      for (final grade in dash.allGrades) {
        addContact(grade.teacher);
      }
      for (final hw in dash.homeworks) {
        addContact(hw.teacherName);
      }
      for (final test in dash.tests) {
        addContact(test.teacherName);
      }
      for (final om in dash.omissions) {
        addContact(om.teacher);
      }
      for (final msg in dash.messages) {
        if (!msg.isSent) {
          addContact(msg.sender);
        }
        for (final r in msg.recipients) {
          addContact(r);
        }
      }
    }

    for (final om in _omissions) {
      addContact(om.teacher);
    }
    for (final msg in _messages) {
      if (!msg.isSent) {
        addContact(msg.sender);
      }
      for (final r in msg.recipients) {
        addContact(r);
      }
    }
    for (final custom in _currentPrefs.teacherCustomNames.values) {
      addContact(custom);
    }

    final sorted = contacts.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  Future<void> _downloadAndOpenAttachment(
    BuildContext feedbackContext,
    KretaMessageAttachment attachment,
    ValueNotifier<String?> downloadingIdNotifier,
    bool Function() isSheetClosed,
  ) async {
    final client = widget.kretaClient;
    if (client == null) return;
    if (!isSheetClosed()) {
      downloadingIdNotifier.value = attachment.id;
    }
    try {
      final file = await client.downloadMessageAttachment(
        widget.session,
        attachment,
      );
      if (Platform.isAndroid) {
        await _fileChannel.invokeMethod<String>('openFile', {
          'filePath': file.path,
        });
      }
    } catch (e) {
      if (feedbackContext.mounted) {
        TintaToast.error(
          feedbackContext,
          uwu('Csatolmány megnyitása sikertelen: $e'),
        );
      }
    } finally {
      if (!isSheetClosed()) {
        downloadingIdNotifier.value = null;
      }
    }
  }

  void _openMessageDetailModal(KretaMessage msg) {
    HapticFeedback.lightImpact();
    setState(() {
      _readMessageIds.add(msg.uid);
      if (msg.messageId != null && msg.messageId!.isNotEmpty) {
        _readMessageIds.add(msg.messageId!);
      }
      if (msg.isSystemMessage) {
        _readMessageIds.add('sys:${msg.uid}');
      }
      final idx = _messages.indexWhere(
        (m) => m.uid == msg.uid && m.isSystemMessage == msg.isSystemMessage,
      );
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(isRead: true);
      }
    });
    widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));

    final client = widget.kretaClient;
    if (client != null) {
      unawaited(
        client.markMessageAsRead(widget.session, msg).catchError((_) {}),
      );
    } else {
      unawaited(
        const TokenStorageService().markMessagesReadLocally(
          [
            msg.uid,
            if (msg.messageId != null && msg.messageId!.isNotEmpty)
              msg.messageId!,
            if (msg.isSystemMessage) 'sys:${msg.uid}',
          ],
          accountKey: TokenStorageService.accountKeyForSession(widget.session),
        ),
      );
    }

    final shouldFetchDetails =
        !msg.isSystemMessage && !msg.detailsLoaded && client != null;
    final msgNotifier = ValueNotifier<KretaMessage>(msg.copyWith(isRead: true));
    final loadingNotifier = ValueNotifier<bool>(shouldFetchDetails);
    final downloadingIdNotifier = ValueNotifier<String?>(null);
    var sheetClosed = false;

    if (shouldFetchDetails) {
      client.fetchMessageDetail(widget.session, msg).then((detailed) {
        final merged = detailed.copyWith(isRead: true, detailsLoaded: true);
        if (!sheetClosed) {
          msgNotifier.value = merged;
          loadingNotifier.value = false;
        }
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere(
              (m) =>
                  m.uid == msg.uid && m.isSystemMessage == msg.isSystemMessage,
            );
            if (idx != -1) {
              _messages[idx] = merged;
            }
          });
          widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
        }
      }).catchError((_) {
        if (!sheetClosed) {
          loadingNotifier.value = false;
        }
      });
    }

    showFloatingGlassSheet<void>(
      context: context,
      prefs: _currentPrefs,
      barrierColor: resolveSoftBlurBarrierColor(context, prefs: _currentPrefs),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final hairline =
            scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bottomInset =
                    math.max(12.0, MediaQuery.paddingOf(context).bottom);
                final maxAvailable =
                    math.max(320.0, constraints.maxHeight - bottomInset - 8.0);
                final sheetHeight =
                    (constraints.maxHeight * 0.84).clamp(320.0, maxAvailable);
                return FrostedBottomSheetSurface(
                  prefs: _currentPrefs,
                  topRadius: 26,
                  showDragHandle: false,
                  includeSafeAreaBottom: true,
                  child: SizedBox(
                    height: sheetHeight,
                    child: ValueListenableBuilder<KretaMessage>(
                      valueListenable: msgNotifier,
                      builder: (context, current, _) {
                        final senderDisplay =
                            _currentPrefs.resolveTeacherName(current.sender);
                        final senderLine = current.senderTitle != null &&
                                current.senderTitle!.isNotEmpty
                            ? '$senderDisplay (${current.senderTitle})'
                            : senderDisplay;
                        return ValueListenableBuilder<bool>(
                          valueListenable: loadingNotifier,
                          builder: (context, isLoadingDetails, _) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(22, 12, 14, 12),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: Container(
                                          width: 42,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: scheme.onSurface
                                                .withValues(alpha: 0.24),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: scheme.primary
                                                  .withValues(alpha: 0.18),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Icon(
                                              current.isSystemMessage
                                                  ? Icons.campaign_rounded
                                                  : Icons.mail_rounded,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  uwuLabel(current.subject),
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  uwuLabel(
                                                    'Feladó: $senderLine',
                                                  ),
                                                  style: theme
                                                      .textTheme.labelMedium
                                                      ?.copyWith(
                                                    color: scheme.primary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                if (current
                                                    .recipients.isNotEmpty) ...[
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    uwuLabel(
                                                      'Címzett: ${current.recipients.join(", ")}',
                                                    ),
                                                    style: theme
                                                        .textTheme.labelSmall
                                                        ?.copyWith(
                                                      color: scheme.onSurface
                                                          .withValues(
                                                        alpha: 0.65,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      _dateTimeFormat.format(
                                                        current.sentAt
                                                            .toLocal(),
                                                      ),
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: scheme.onSurface
                                                            .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                      ),
                                                    ),
                                                    if (current
                                                        .isSystemMessage) ...[
                                                      const SizedBox(width: 8),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                          horizontal: 7,
                                                          vertical: 2,
                                                        ),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: scheme.primary
                                                              .withValues(
                                                            alpha: 0.14,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Text(
                                                          uwuLabel('Rendszer'),
                                                          style: theme.textTheme
                                                              .labelSmall
                                                              ?.copyWith(
                                                            color:
                                                                scheme.primary,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_currentPrefs
                                              .modalCloseMode.showTopX) ...[
                                            const SizedBox(width: 8),
                                            PopupTopCloseButton(
                                              onTap: () =>
                                                  Navigator.of(sheetContext)
                                                      .pop(),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: hairline,
                                ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(
                                      22,
                                      14,
                                      22,
                                      28,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (isLoadingDetails) ...[
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                            child:
                                                const LinearProgressIndicator(
                                              minHeight: 3,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: scheme.surfaceContainerHigh,
                                            borderRadius: OledTheme.cardRadius,
                                            border: Border.all(
                                              color: theme.dividerColor,
                                            ),
                                          ),
                                          child: SelectableText(
                                            current.cleanBody.isNotEmpty
                                                ? uwu(current.cleanBody)
                                                : uwu(
                                                    isLoadingDetails
                                                        ? 'Üzenet tartalmának betöltése...'
                                                        : 'Üres üzenetszöveg.',
                                                  ),
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              height: 1.45,
                                              color: scheme.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (current.attachments.isNotEmpty ||
                                            (current.hasAttachments &&
                                                isLoadingDetails)) ...[
                                          const SizedBox(height: 14),
                                          Text(
                                            uwuLabel('Csatolmányok'),
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.78),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          if (current.attachments.isEmpty &&
                                              isLoadingDetails)
                                            Text(
                                              uwu(
                                                'Csatolmányok betöltése...',
                                              ),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: scheme.onSurface
                                                    .withValues(alpha: 0.6),
                                              ),
                                            )
                                          else
                                            ValueListenableBuilder<String?>(
                                              valueListenable:
                                                  downloadingIdNotifier,
                                              builder: (
                                                context,
                                                downloadingId,
                                                _,
                                              ) {
                                                return Column(
                                                  children: current.attachments
                                                      .map((att) {
                                                    final isDownloading =
                                                        downloadingId == att.id;
                                                    return Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(14),
                                                        onTap: isDownloading
                                                            ? null
                                                            : () =>
                                                                _downloadAndOpenAttachment(
                                                                  sheetContext,
                                                                  att,
                                                                  downloadingIdNotifier,
                                                                  () =>
                                                                      sheetClosed,
                                                                ),
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 12,
                                                            vertical: 10,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: scheme
                                                                .surfaceContainerHigh,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                              14,
                                                            ),
                                                            border: Border.all(
                                                              color: theme
                                                                  .dividerColor,
                                                            ),
                                                          ),
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .attach_file_rounded,
                                                                size: 18,
                                                                color: scheme
                                                                    .primary,
                                                              ),
                                                              const SizedBox(
                                                                width: 10,
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  att.fileName,
                                                                  style: theme
                                                                      .textTheme
                                                                      .bodySmall
                                                                      ?.copyWith(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w700,
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                              const SizedBox(
                                                                width: 8,
                                                              ),
                                                              if (isDownloading)
                                                                const SizedBox(
                                                                  width: 16,
                                                                  height: 16,
                                                                  child:
                                                                      CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                  ),
                                                                )
                                                              else
                                                                Icon(
                                                                  Icons
                                                                      .download_rounded,
                                                                  size: 18,
                                                                  color: scheme
                                                                      .primary,
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }).toList(),
                                                );
                                              },
                                            ),
                                        ],
                                        const SizedBox(height: 18),
                                        Row(
                                          children: [
                                            if (_currentPrefs.modalCloseMode
                                                .showBottomButton) ...[
                                              Expanded(
                                                child: PopupBottomCloseButton(
                                                  onTap: () =>
                                                      Navigator.of(sheetContext)
                                                          .pop(),
                                                  uwuEnabled: _currentPrefs
                                                      .uwuModeEnabled,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                            ],
                                            Expanded(
                                              flex: 2,
                                              child: FilledButton.icon(
                                                onPressed: () {
                                                  Navigator.of(sheetContext)
                                                      .pop();
                                                  _openMessageComposerDialog(
                                                    initialRecipient:
                                                        current.sender,
                                                    initialSubject: current
                                                            .subject
                                                            .startsWith('Re:')
                                                        ? current.subject
                                                        : 'Re: ${current.subject}',
                                                  );
                                                },
                                                icon: const Icon(
                                                  Icons.reply_rounded,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  uwuLabel('Válasz küldése'),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ).whenComplete(() {
      sheetClosed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        msgNotifier.dispose();
        loadingNotifier.dispose();
        downloadingIdNotifier.dispose();
      });
    });
  }

  /// Opens the Kréta Message Composer dialog with live teacher/staff
  /// recipient autocomplete suggestions.
  Future<void> _openMessageComposerDialog({
    String? initialRecipient,
    String? initialSubject,
  }) async {
    HapticFeedback.lightImpact();
    final allContacts = _collectTeacherAndStaffContacts();
    final recipientController =
        TextEditingController(text: initialRecipient ?? '');
    final subjectController =
        TextEditingController(text: initialSubject ?? '');
    final bodyController = TextEditingController();

    final sent = await showFloatingGlassSheet<KretaMessage>(
      context: context,
      prefs: _currentPrefs,
      builder: (dialogContext) {
        bool isSending = false;
        return SheetDisposableScope(
          disposables: [
            recipientController,
            subjectController,
            bodyController,
          ],
          builder: (_) => StatefulBuilder(
            builder: (context, setModalState) {
              final theme = Theme.of(context);
              final scheme = theme.colorScheme;
              final closeMode = _currentPrefs.modalCloseMode;
              final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
              final query = recipientController.text.trim().toLowerCase();
              final matchingContacts = allContacts.where((c) {
                if (query.isEmpty) return true;
                return c.toLowerCase().contains(query) &&
                    c.toLowerCase() != query;
              }).take(6).toList();

              return AnimatedPadding(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(bottom: bottomInset),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 540,
                    maxHeight:
                        (MediaQuery.sizeOf(context).height - bottomInset) *
                            0.88,
                  ),
                  child: FrostedBottomSheetSurface(
                    prefs: _currentPrefs,
                    showDragHandle: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: SingleChildScrollView(
                      physics: const FloatingSheetScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(
                                  Icons.mail_outline_rounded,
                                  size: 19,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  uwuLabel(
                                    initialRecipient != null
                                        ? 'Válasz üzenet'
                                        : 'Új Kréta üzenet',
                                    enabled: _currentPrefs.uwuModeEnabled,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              if (closeMode.showTopX) ...[
                                const SizedBox(width: 8),
                                PopupTopCloseButton(
                                  onTap: isSending
                                      ? () {}
                                      : () => Navigator.of(dialogContext).pop(),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: recipientController,
                            onChanged: (_) => setModalState(() {}),
                            decoration: InputDecoration(
                              labelText: uwuLabel(
                                'Címzett (tanár / titkárság)',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              hintText: uwuLabel(
                                'Kezdj el gépelni a kereséshez...',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              prefixIcon: const Icon(Icons.person_search_rounded),
                              suffixIcon: recipientController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 18),
                                      onPressed: () {
                                        recipientController.clear();
                                        setModalState(() {});
                                      },
                                    )
                                  : null,
                            ),
                          ),
                          if (matchingContacts.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 13,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        uwuLabel(
                                          'Javasolt címzettek (Kréta névjegyzék):',
                                          enabled: _currentPrefs.uwuModeEnabled,
                                        ),
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: matchingContacts.map((contact) {
                                      return ActionChip(
                                        visualDensity: VisualDensity.compact,
                                        avatar: Icon(
                                          Icons.person_rounded,
                                          size: 14,
                                          color: scheme.primary,
                                        ),
                                        label: Text(
                                          uwuLabel(
                                            contact,
                                            enabled:
                                                _currentPrefs.uwuModeEnabled,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        onPressed: () {
                                          HapticFeedback.selectionClick();
                                          recipientController.text = contact;
                                          recipientController.selection =
                                              TextSelection.fromPosition(
                                            TextPosition(offset: contact.length),
                                          );
                                          setModalState(() {});
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: subjectController,
                            decoration: InputDecoration(
                              labelText: uwuLabel(
                                'Tárgy',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              hintText: uwuLabel(
                                'pl. Hiányzás igazolása',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              prefixIcon: const Icon(Icons.subject_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: bodyController,
                            maxLines: 5,
                            decoration: InputDecoration(
                              labelText: uwuLabel(
                                'Üzenet szövege',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              hintText: uwuLabel(
                                'Írd ide az üzenetedet...',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: isSending
                                    ? null
                                    : () => Navigator.of(dialogContext).pop(),
                                child: Text(
                                  uwuLabel(
                                    'Mégse',
                                    enabled: _currentPrefs.uwuModeEnabled,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: isSending
                                    ? null
                                    : () async {
                                        final recip =
                                            recipientController.text.trim();
                                        final subj =
                                            subjectController.text.trim();
                                        final body = bodyController.text.trim();
                                        if (recip.isEmpty ||
                                            subj.isEmpty ||
                                            body.isEmpty) {
                                          return;
                                        }
                                        setModalState(() => isSending = true);
                                        KretaClient? tempClient;
                                        try {
                                          final client = widget.kretaClient ??
                                              (tempClient = KretaClient());
                                          final created =
                                              await client.sendMessage(
                                            widget.session,
                                            recipient: recip,
                                            subject: subj,
                                            body: body,
                                            senderName: widget.student?.name ??
                                                _currentPrefs.nickname ??
                                                widget.session.userName ??
                                                '',
                                          );
                                          if (dialogContext.mounted) {
                                            Navigator.of(dialogContext)
                                                .pop(created);
                                          }
                                        } catch (_) {
                                          if (dialogContext.mounted) {
                                            setModalState(
                                                () => isSending = false);
                                            TintaToast.error(
                                              dialogContext,
                                              uwu(
                                                'Üzenet küldése sikertelen',
                                                enabled:
                                                    _currentPrefs.uwuModeEnabled,
                                              ),
                                            );
                                          }
                                        } finally {
                                          tempClient?.close();
                                        }
                                      },
                                icon: const Icon(Icons.send_rounded, size: 18),
                                label: Text(
                                  uwuLabel(
                                    isSending ? 'Küldés...' : 'Küldés',
                                    enabled: _currentPrefs.uwuModeEnabled,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (closeMode.showBottomButton) ...[
                            const SizedBox(height: 12),
                            PopupBottomCloseButton(
                              onTap: () => Navigator.of(dialogContext).pop(),
                              uwuEnabled: _currentPrefs.uwuModeEnabled,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    final sentMsg = sent;
    if (sentMsg != null && mounted) {
      setState(() {
        _messages.insert(0, sentMsg);
        _showSentMessages = true;
      });
      widget.onMessagesChanged?.call(List<KretaMessage>.of(_messages));
      TintaToast.success(
        context,
        uwu('Üzenet sikeresen elküldve: ${sentMsg.subject}'),
      );
    }
  }

  void _openAllOmissionsScreen() {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: AllOmissionsScreen(
          omissions: _omissions,
          prefs: _currentPrefs,
          session: widget.session,
          kretaClient: widget.kretaClient,
          referenceLessons: _effectiveReferenceLessons,
        ),
      ),
    );
  }

  void _selectAttendanceFilter(
    _AttendanceFilter filter, {
    bool animatePage = true,
  }) {
    if (_attendanceFilter != filter) {
      setState(() => _attendanceFilter = filter);
    }
    if (animatePage && _attendancePageController.hasClients) {
      final target = _AttendanceFilter.values.indexOf(filter).clamp(
            0,
            _AttendanceFilter.values.length - 1,
          );
      final curPage = _attendancePageController.page?.round() ?? target;
      if (curPage != target) {
        _isAnimatingAttendancePage = true;
        _attendancePageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
          if (mounted && _isAnimatingAttendancePage) {
            setState(() => _isAnimatingAttendancePage = false);
          } else {
            _isAnimatingAttendancePage = false;
          }
        });
      }
    }
  }

  void _selectMessagesFolder(bool showSent, {bool animatePage = true}) {
    if (_showSentMessages != showSent) {
      setState(() => _showSentMessages = showSent);
    }
    if (animatePage && _messagesPageController.hasClients) {
      final target = showSent ? 1 : 0;
      final curPage = _messagesPageController.page?.round() ?? target;
      if (curPage != target) {
        _isAnimatingMessagesPage = true;
        _messagesPageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
          if (mounted && _isAnimatingMessagesPage) {
            setState(() => _isAnimatingMessagesPage = false);
          } else {
            _isAnimatingMessagesPage = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final expFormat = DateFormat('yyyy. MM. dd. HH:mm');

    // B6: On the 'Továbbiak' bottom tab (!widget.settingsOnly), render ONLY
    // the Attendance and Kréta Messages modules. Settings are accessible
    // EXCLUSIVELY via the top-right Profile sheet (`AppSettingsScreen`).
    if (!widget.settingsOnly) {
      if (widget.messagesOnly) {
        return RefreshIndicator(
          displacement: 44,
          edgeOffset: 8,
          strokeWidth: 2.6,
          notificationPredicate: nestedScrollRefreshNotificationPredicate,
          onRefresh: _refreshModules,
          child: ElasticOverscrollStretchWrapper(
            child: NestedScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              headerSliverBuilder: (context, _) =>
                  _buildMessagesHeaderSlivers(theme, scheme),
              body: HorizontalSubTabSwipeDetector(
                key: const ValueKey<String>('messages-subtab-swipe'),
                currentIndex: _showSentMessages ? 1 : 0,
                itemCount: 2,
                pageController: _messagesPageController,
                onIndexChanged: (idx) =>
                    _selectMessagesFolder(idx == 1, animatePage: false),
                pageBuilder: (pageCtx, pageIdx) => _buildMessagesPageViewBody(
                  theme,
                  scheme,
                  showSent: pageIdx == 1,
                  isActivePage: pageIdx == (_showSentMessages ? 1 : 0),
                ),
              ),
            ),
          ),
        );
      }
      return RefreshIndicator(
        displacement: 44,
        edgeOffset: 8,
        strokeWidth: 2.6,
        notificationPredicate: nestedScrollRefreshNotificationPredicate,
        onRefresh: _refreshModules,
        child: ElasticOverscrollStretchWrapper(
          child: NestedScrollView(
            floatHeaderSlivers: true,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
          headerSliverBuilder: (context, _) =>
              _buildAttendanceHeaderSlivers(theme, scheme),
          body: HorizontalSubTabSwipeDetector(
            key: const ValueKey<String>('attendance-subtab-swipe'),
            currentIndex: _AttendanceFilter.values
                .indexOf(_attendanceFilter)
                .clamp(0, _AttendanceFilter.values.length - 1),
            itemCount: _AttendanceFilter.values.length,
            pageController: _attendancePageController,
            onIndexChanged: (idx) => _selectAttendanceFilter(
              _AttendanceFilter.values[idx],
              animatePage: false,
            ),
            pageBuilder: (pageCtx, pageIdx) {
              final pageFilter = _AttendanceFilter.values[pageIdx];
              final isActivePage = pageFilter == _attendanceFilter;
              return HeroMode(
                enabled: isActivePage,
                child: _buildAttendancePageViewBody(
                  theme,
                  scheme,
                  pageFilter,
                  isActivePage: isActivePage,
                ),
              );
            },
          ),
          ),
        ),
      );
    }

    // Main Settings view (`widget.settingsOnly == true`):
    final query = _settingsSearchQuery.trim();
    final isSearching = query.isNotEmpty;
    final searchResults = isSearching
        ? _filterSettingsSearchCatalog(query, theme, scheme, expFormat)
        : const <_SettingsSearchEntry>[];

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        adaptiveAppBarTopPadding(context),
        16,
        36,
      ),
      children: [
        SizedBox(
          height: 46,
          child: SoftGlassCard(
            prefs: _currentPrefs,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            borderRadius: OledTheme.largeRadius,
            child: Center(
              child: TextField(
                key: const ValueKey<String>('settings-fuzzy-search-field'),
                controller: _settingsSearchController,
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface,
                ),
                onChanged: (value) {
                  if (_settingsSearchQuery != value) {
                    setState(() => _settingsSearchQuery = value);
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  hintText: uwu('Keresés a beállításokban...'),
                  hintStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface.withValues(alpha: 0.56),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: scheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  suffixIcon: isSearching
                      ? IconButton(
                          tooltip: 'Keresés törlése',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          onPressed: () {
                            _settingsSearchController.clear();
                            setState(() => _settingsSearchQuery = '');
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: scheme.onSurface.withValues(alpha: 0.62),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (isSearching) ...[
          if (searchResults.isEmpty)
            SoftGlassCard(
              prefs: _currentPrefs,
              padding: const EdgeInsets.all(20),
              borderRadius: OledTheme.largeRadius,
              child: Row(
                children: [
                  Icon(
                    Icons.search_off_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      uwu('Nincs találat erre: "$query"'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final entry in searchResults) ...[
              SoftGlassCard(
                prefs: _currentPrefs,
                padding: EdgeInsets.zero,
                borderRadius: OledTheme.largeRadius,
                child: TactileBounce(
                  pressedScale: 0.98,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    entry.onTap();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            entry.icon,
                            size: 19,
                            color: scheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uwuLabel(
                                  entry.title,
                                  enabled: _currentPrefs.uwuModeEnabled,
                                ),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                uwuLabel(
                                  '${entry.category} • ${entry.description}',
                                  enabled: _currentPrefs.uwuModeEnabled,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.62),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
        ] else ...[
          _SettingsAccordionCard(
            icon: Icons.manage_accounts_rounded,
            title: 'Fiók és munkamenet',
            subtitle: (_currentPrefs.demoModeEnabled
                    ? DemoDataService.demoStudentName
                    : widget.student?.name) ??
                widget.session.userName ??
                '-',
            christmasCap: _currentPrefs.christmasModeEnabled,
            prefs: _currentPrefs,
            stateListenable: _stateVersion,
            prefsGetter: () => _currentPrefs,
            childrenBuilder: (subCtx) =>
                _buildAccountSettingsChildren(subCtx, expFormat),
          ),
          const SizedBox(height: 12),
          _SettingsAccordionCard(
            icon: Icons.palette_rounded,
            title: 'Megjelenés és témák',
            subtitle: 'Alaptéma, Liquid Glass, Elrendezés és Ikon',
            christmasCap: _currentPrefs.christmasModeEnabled,
            prefs: _currentPrefs,
            stateListenable: _stateVersion,
            prefsGetter: () => _currentPrefs,
            childrenBuilder: _buildAppearanceSettingsChildren,
          ),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          ChristmasSnowCap(
            enabled: _currentPrefs.christmasModeEnabled,
            child: SoftGlassCard(
              key: const ValueKey<String>('settings-notifications-card'),
              prefs: _currentPrefs,
              padding: EdgeInsets.zero,
              borderRadius: _currentPrefs.minimalistModeEnabled
                  ? MinimalistTokens.of(_currentPrefs).cardRadius
                  : OledTheme.largeRadius,
              child: TactileBounce(
                pressedScale: 0.98,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).push(
                    SmoothSharedAxisRoute(
                      page: NotificationsSettingsScreen(prefs: _currentPrefs),
                    ),
                  );
                },
                child: Padding(
                  padding: _currentPrefs.minimalistModeEnabled
                      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
                      : const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: _currentPrefs.minimalistModeEnabled ? 30 : 40,
                        height: _currentPrefs.minimalistModeEnabled ? 30 : 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(
                            _currentPrefs.minimalistModeEnabled ? 9 : 13,
                          ),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.08)
                                : scheme.onSurface.withValues(alpha: 0.10),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.notifications_active_rounded,
                          size: _currentPrefs.minimalistModeEnabled ? 16 : 20,
                          color: scheme.primary,
                        ),
                      ),
                      SizedBox(
                        width: _currentPrefs.minimalistModeEnabled ? 10 : 12,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uwuLabel(
                                'Értesítések',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              style: (_currentPrefs.minimalistModeEnabled
                                      ? theme.textTheme.labelLarge
                                      : theme.textTheme.titleSmall)
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              uwuLabel(
                                'Új jegy, számonkérés, óraváltozás, késés, hiányzás, üzenet',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontSize: _currentPrefs.minimalistModeEnabled
                                    ? 10.5
                                    : null,
                                color: scheme.onSurface.withValues(alpha: 0.62),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: _currentPrefs.minimalistModeEnabled ? 18 : 24,
                        color: scheme.onSurface.withValues(alpha: 0.72),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          _buildMenetrendSettingsAccordion(theme, scheme),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          _buildCalendarSyncSettingsAccordion(theme, scheme),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          _SettingsAccordionCard(
            icon: Icons.tune_rounded,
            title: 'Órarend',
            subtitle: 'Átlag küszöbök, elmaradt/nulladik órák és hétvége',
            christmasCap: _currentPrefs.christmasModeEnabled,
            prefs: _currentPrefs,
            stateListenable: _stateVersion,
            prefsGetter: () => _currentPrefs,
            childrenBuilder: _buildTimetableSettingsChildren,
          ),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          _SettingsAccordionCard(
            icon: Icons.import_export_rounded,
            title: 'Beállítások exportálása / importálása',
            subtitle: 'JSON biztonsági mentés készítése és visszaállítása',
            christmasCap: _currentPrefs.christmasModeEnabled,
            prefs: _currentPrefs,
            stateListenable: _stateVersion,
            prefsGetter: () => _currentPrefs,
            childrenBuilder: _buildExportImportChildren,
          ),
          SizedBox(height: _currentPrefs.minimalistModeEnabled ? 6 : 12),
          _SettingsAccordionCard(
            icon: Icons.info_outline_rounded,
            title: uwu('Rendszer / Névjegy'),
            subtitle: uwu('Tinta Napló v$_appVersion • GitHub OTA frissítő'),
            christmasCap: _currentPrefs.christmasModeEnabled,
            prefs: _currentPrefs,
            stateListenable: _stateVersion,
            prefsGetter: () => _currentPrefs,
            childrenBuilder: _buildSystemAboutChildren,
          ),
        ],
      ],
    );
  }

  Future<void> _pushSettingsSubScreen(
    String title,
    List<Widget> Function(BuildContext subCtx) childrenBuilder,
  ) {
    return Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: _SettingsSubScreen(
          title: title,
          prefs: _currentPrefs,
          prefsGetter: () => _currentPrefs,
          stateListenable: _stateVersion,
          childrenBuilder: childrenBuilder,
        ),
      ),
    );
  }

  List<_SettingsSearchEntry> _filterSettingsSearchCatalog(
    String query,
    ThemeData theme,
    ColorScheme scheme,
    DateFormat expFormat,
  ) {
    final entries = <_SettingsSearchEntry>[
      _SettingsSearchEntry(
        icon: Icons.blur_on_rounded,
        title: 'Liquid Glass effekt és módok',
        category: 'Megjelenés és témák',
        description: 'Classic Frost, Hydro Mercury, Optical Prism, Obsidian',
        keywords: const [
          'uveg',
          'üveg',
          'liquid',
          'glass',
          'frost',
          'mercury',
          'prism',
          'obsidian',
          'ripple',
          'atlatszo',
          'elmosas',
          'blur',
          'felulet',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.palette_rounded,
        title: 'Alaptéma, színek és OLED mód',
        category: 'Megjelenés és témák',
        description: 'OLED Fekete, Sötét M3, Világos, Material You',
        keywords: const [
          'tema',
          'szin',
          'oled',
          'fekete',
          'sotet',
          'vilagos',
          'material',
          'dinamikus',
          'hatter',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.view_quilt_rounded,
        title: 'Kártyák, elrendezés és ablakbezárás',
        category: 'Megjelenés és témák',
        description: 'Felugró ablak bezárás, megjelenítési elrendezés',
        keywords: const [
          'kartya',
          'elrendezes',
          'felugro',
          'modal',
          'bezaras',
          'betutipus',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.apps_rounded,
        title: 'Indítóikon stílusa és alkalmazás ikon',
        category: 'Megjelenés és témák',
        description: 'Alapértelmezett vagy Klasszikus ikon kiválasztása',
        keywords: const [
          'ikon',
          'icon',
          'inditoikon',
          'alkalmazas ikon',
          'klasszikus',
          'logo',
          'launcher',
          'firka',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.sentiment_very_satisfied_rounded,
        title: 'Fun üdvözlő üzenetek',
        category: 'Megjelenés és témák',
        description: 'Laza, vicces és napszakhoz illő köszönések a főoldalon',
        keywords: const [
          'fun',
          'udvozlo',
          'üdvözlő',
          'koszones',
          'köszönés',
          'vicces',
          'fooldal',
          'főoldal',
          'greeting',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.subtitles_outlined,
        title: 'Köszönés alatti szöveg',
        category: 'Megjelenés és témák',
        description:
            'Mikor végzel ma, dátum, holnapi számonkérések, fun factek',
        keywords: const [
          'koszones',
          'köszönés',
          'alatti',
          'szoveg',
          'szöveg',
          'vegzel',
          'végzel',
          'datum',
          'dátum',
          'fun fact',
          'szamonkeres',
          'számonkérés',
          'iskola',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Megjelenés és témák',
          _buildAppearanceSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.calculate_rounded,
        title: 'Átlagszámítás és kerekítési határok',
        category: 'Órarend & Átlagok',
        description: '0.05 léptékű határok (2-5), súlyozás (100% / 200%)',
        keywords: const [
          'atlag',
          'átlag',
          'kerekites',
          'hatar',
          'kuszob',
          'csuszka',
          'sulyozas',
          'kalkulator',
          'cel',
          '200%',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Órarend',
          _buildTimetableSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.calendar_view_day_rounded,
        title: 'Órarend megjelenítése és szűrés',
        category: 'Órarend',
        description: 'Elmaradt órák, lyukasórák, hétvége megjelenítése',
        keywords: const [
          'ora',
          'óra',
          'orarend',
          'órarend',
          'elmaradt',
          'lyukas',
          'szabad',
          'hetvege',
          'nulladik',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Órarend',
          _buildTimetableSettingsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.color_lens_rounded,
        title: 'Érdemjegyek színeinek testreszabása',
        category: 'Megjelenés és témák',
        description: '1-5 jegyek egyedi HEX és paletta színei',
        keywords: const [
          'jegy',
          'erdemjegy',
          'szin',
          'hex',
          'otos',
          'egyes',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Érdemjegyek Színeinek Testreszabása',
          _buildGradeColorsChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.manage_accounts_rounded,
        title: 'Fiók, Okosóra (Wear OS) és munkamenet',
        category: 'Fiók és munkamenet',
        description: 'Tanuló adatok, intézmény, becenév, kijelentkezés',
        keywords: const [
          'fiok',
          'munkamenet',
          'becenev',
          'intezmeny',
          'token',
          'kijelentkezes',
          'wear',
          'okosora',
          'ora',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Fiók és munkamenet',
          (subCtx) => _buildAccountSettingsChildren(subCtx, expFormat),
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.directions_railway_filled_rounded,
        title: 'MenetrendGO ingázás és útvonalak',
        category: 'MenetrendGO',
        description: 'Otthoni/iskolai cím, közlekedési módok, sétatempó, járatok',
        keywords: const [
          'menetrend',
          'busz',
          'vonat',
          'megallo',
          'seta',
          'otthon',
          'iskola',
          'utazas',
        ],
        onTap: () => _pushSettingsSubScreen(
          'MenetrendGO',
          _buildMenetrendChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.notifications_active_rounded,
        title: 'Értesítések és sablonok',
        category: 'Értesítések',
        description:
            'Új jegy, számonkérés, elmaradt óra, helyettesítés, késés, hiányzás, üzenet',
        keywords: const [
          'ertesites',
          'értesítés',
          'push',
          'sablon',
          'jegy',
          'szamonkeres',
          'elmaradt',
          'helyettesites',
          'keses',
          'késés',
          'hianyzas',
          'hiányzás',
          'uzenet',
          'üzenet',
          'hatter',
          'riaszto',
        ],
        onTap: () {
          Navigator.of(context).push(
            SmoothSharedAxisRoute(
              page: NotificationsSettingsScreen(prefs: _currentPrefs),
            ),
          );
        },
      ),
      _SettingsSearchEntry(
        icon: Icons.event_available_rounded,
        title: 'Naptár szinkronizálás',
        category: 'Naptár',
        description: 'Órarend és számonkérések naptárba mentése',
        keywords: const ['naptar', 'calendar', 'szinkron'],
        onTap: () => _pushSettingsSubScreen(
          'Naptár szinkronizálás',
          (subCtx) => [
            _CalendarSyncSettingsSection(
              session: widget.session,
              kretaClient: widget.kretaClient,
              dashboardData: widget.dashboardData,
              profilePrefs: _currentPrefs,
              onSettingsChanged: (updated) {
                if (!mounted) return;
                setState(() => _calendarSyncSettings = updated);
              },
            ),
          ],
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.import_export_rounded,
        title: 'Beállítások exportálása és importálása',
        category: 'Biztonsági mentés',
        description: 'JSON mentés létrehozása és visszaállítása',
        keywords: const ['export', 'import', 'json', 'mentes', 'backup'],
        onTap: () => _pushSettingsSubScreen(
          'Beállítások exportálása / importálása',
          _buildExportImportChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.info_outline_rounded,
        title: 'Névjegy, verzió és OTA frissítések',
        category: 'Rendszer / Névjegy',
        description: 'Tinta Napló v$_appVersion és GitHub kiadások',
        keywords: const [
          'nevjegy',
          'verzio',
          'frissites',
          'ota',
          'github',
          'rendszer',
        ],
        onTap: () => _pushSettingsSubScreen(
          'Rendszer / Névjegy',
          _buildSystemAboutChildren,
        ),
      ),
      _SettingsSearchEntry(
        icon: Icons.auto_awesome_rounded,
        title: 'Fityma Napló mód & Easter Egg témák',
        category: 'Fejlesztői beállítások',
        description: 'Fityma Napló, UwU, animált hátterek, CSS skin',
        keywords: const [
          'fityma',
          'fityma naplo',
          'uwu',
          'easter',
          'fejlesztoi',
          'skin',
          'css',
          'animalt',
        ],
        onTap: () {
          Navigator.of(context).push(
            SmoothSharedAxisRoute(
              page: DeveloperAppearanceSubPage(
                initialPrefs: _currentPrefs,
                onPrefsChanged: _updatePrefs,
              ),
            ),
          );
        },
      ),
      _SettingsSearchEntry(
        icon: Icons.terminal_rounded,
        title: 'Fejlesztői beállítások központ',
        category: 'Fejlesztői beállítások',
        description: 'Demó mód, minimalista nézet, KRÉTA auth, cache',
        keywords: const [
          'fejlesztoi',
          'dev',
          'demo',
          'minimalista',
          'debug',
          'cache',
          'auth',
        ],
        onTap: () {
          Navigator.of(context).push(
            SmoothSharedAxisRoute(
              page: DeveloperOptionsHubScreen(
                prefs: _currentPrefs,
                onPrefsChanged: _updatePrefs,
                kretaClient: widget.kretaClient,
                wearSyncService: widget.wearSyncService,
              ),
            ),
          );
        },
      ),
    ];

    final scored = <({int score, _SettingsSearchEntry entry})>[];
    for (final entry in entries) {
      final score = _scoreSettingsSearch(query, entry);
      if (score > 0) {
        scored.add((score: score, entry: entry));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.entry).toList();
  }

  Widget _buildAppearanceSectionHeader(
    ThemeData theme,
    ColorScheme scheme,
    IconData icon,
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Text(
            uwuLabel(title),
            style: theme.textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.15,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAccountSettingsChildren(
    BuildContext subCtx,
    DateFormat expFormat,
  ) {
    final activePrefs = _livePrefs(subCtx);
    final scheme = Theme.of(subCtx).colorScheme;
    final isDemo = activePrefs.demoModeEnabled;
    final displayStudent =
        isDemo ? DemoDataService.instance.buildDemoStudent() : widget.student;
    final displaySession =
        isDemo ? DemoDataService.instance.buildDemoSession() : widget.session;
    return [
      _buildRow(
        scheme,
        uwuLabel('Tanuló neve', enabled: activePrefs.uwuModeEnabled),
        uwuLabel(
          displayStudent?.name ?? displaySession.userName ?? '-',
          enabled: activePrefs.uwuModeEnabled,
        ),
      ),
      _buildRow(
        scheme,
        uwuLabel('Beállított becenév', enabled: activePrefs.uwuModeEnabled),
        uwuLabel(
          isDemo
              ? 'Alapértelmezett'
              : ((activePrefs.nickname?.trim().isNotEmpty ?? false)
                  ? activePrefs.nickname!
                  : 'Alapértelmezett'),
          enabled: activePrefs.uwuModeEnabled,
        ),
      ),
      _buildRow(
        scheme,
        uwuLabel('Intézménykód (iss)', enabled: activePrefs.uwuModeEnabled),
        displaySession.instituteCode,
      ),
      if (displayStudent != null)
        _buildRow(
          scheme,
          uwuLabel('Intézmény', enabled: activePrefs.uwuModeEnabled),
          uwuLabel(
            displayStudent.instituteName,
            enabled: activePrefs.uwuModeEnabled,
          ),
        ),
      _buildRow(
        scheme,
        uwuLabel('Token lejárat', enabled: activePrefs.uwuModeEnabled),
        expFormat.format(displaySession.expiresAt.toLocal()),
      ),
      if (_wearStatus.isConnected)
        _buildRow(
          scheme,
          uwuLabel('Wear OS óra', enabled: activePrefs.uwuModeEnabled),
          uwuLabel(
            _wearStatus.resolvedDeviceName != null
                ? 'Csatlakozva (${_wearStatus.resolvedDeviceName})'
                : 'Csatlakozva',
            enabled: activePrefs.uwuModeEnabled,
          ),
        ),
      const SizedBox(height: 12),
      FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFC62828),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: OledTheme.cardRadius,
          ),
        ),
        onPressed: () async {
          final rootNav = Navigator.of(context, rootNavigator: true);
          try {
            await TokenStorageService.recordLogoutReason(
              caller: 'MoreScreen.logoutButton',
              reason: 'Felhasználó által indított kijelentkezés',
            );
            await TokenStorageService.setPreviousLoginMarker(false);
            await Future.sync(widget.onLogout);
          } catch (_) {}
          if (rootNav.mounted) {
            rootNav.pushNamedAndRemoveUntil('/login', (route) => false);
          }
        },
        icon: const Icon(Icons.logout_rounded),
        label: Text(
          uwu('Kijelentkezés (beállítások megtartásával)'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    ];
  }

  List<Widget> _buildAppearanceSettingsChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    final isClassicIcon = activePrefs.isClassicAppIcon;

    void selectAppIcon(String presetKey) {
      HapticFeedback.selectionClick();
      _updatePrefs(_livePrefs(subCtx).copyWith(appIconPreset: presetKey));
      unawaited(DynamicIconService.setAppIcon(presetKey));
      TintaToast.dismissCurrent();
      TintaToast.info(
        subCtx,
        uwu('Alkalmazás ikon frissítve (a kezdőképernyő ikonja pár másodperc alatt frissül)'),
      );
    }

    Widget buildIconOptionCard({
      required String presetKey,
      required String assetPath,
      required String title,
      required String subtitle,
      required bool selected,
    }) {
      return TactileBounce(
        pressedScale: 0.97,
        onTap: () => selectAppIcon(presetKey),
        child: AnimatedContainer(
          key: ValueKey<String>('app-icon-option-$presetKey'),
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : theme.dividerColor,
              width: selected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.asset(
                      assetPath,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11.5,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildSectionGroup({
      required IconData icon,
      required String title,
      required List<Widget> cardChildren,
    }) {
      return _StandaloneSettingsChild(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _buildAppearanceSectionHeader(
                theme,
                scheme,
                icon,
                title,
              ),
            ),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in cardChildren)
                    if (child is _FullBleedChild ||
                        child is EdgeFadeHorizontalScroll)
                      child
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: child,
                      ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildAppearanceSelectorRow({
      Key? rowKey,
      required IconData icon,
      required String title,
      required String valueLabel,
      String? subtitle,
      required VoidCallback onTap,
    }) {
      return _FullBleedChild(
        child: InkWell(
          key: rowKey,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(icon, size: 19, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uwuLabel(title, enabled: activePrefs.uwuModeEnabled),
                        style: const TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        uwuLabel(
                          valueLabel,
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(
                          uwuLabel(
                            subtitle,
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Future<void> showAppearanceOptionPicker<T>({
      required String title,
      required String subtitle,
      required IconData headerIcon,
      required List<
          ({
            T value,
            String label,
            String? description,
            Widget? leading,
            bool selected,
          })> options,
      required ValueChanged<T> onPicked,
    }) async {
      final prefsNow = _livePrefs(subCtx);
      final chosen = await showFloatingGlassSheet<T>(
        context: subCtx,
        prefs: prefsNow,
        barrierColor: resolveSoftBlurBarrierColor(subCtx, prefs: prefsNow),
        builder: (sheetCtx) {
          final sheetTheme = Theme.of(sheetCtx);
          final sheetScheme = sheetTheme.colorScheme;
          final isDark = sheetTheme.brightness == Brightness.dark;
          final closeMode = prefsNow.modalCloseMode;
          final hairline =
              sheetScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);

          return Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1.0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 540,
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.80,
              ),
              child: FrostedBottomSheetSurface(
                prefs: prefsNow,
                showDragHandle: true,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: sheetScheme.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: sheetScheme.primary.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Icon(
                            headerIcon,
                            size: 20,
                            color: sheetScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uwuLabel(
                                  title,
                                  enabled: prefsNow.uwuModeEnabled,
                                ),
                                style: sheetTheme.textTheme.titleMedium?.copyWith(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                uwuLabel(
                                  subtitle,
                                  enabled: prefsNow.uwuModeEnabled,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: sheetTheme.textTheme.labelSmall?.copyWith(
                                  color: sheetScheme.onSurface
                                      .withValues(alpha: 0.65),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (closeMode.showTopX) ...[
                          const SizedBox(width: 8),
                          PopupTopCloseButton(
                            onTap: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, thickness: 1, color: hairline),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const FloatingSheetScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: options.map((opt) {
                            final selected = opt.selected;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TactileBounce(
                                pressedScale: 0.985,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  Navigator.of(sheetCtx).pop(opt.value);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 13,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? sheetScheme.primary
                                            .withValues(alpha: 0.14)
                                        : sheetScheme.onSurface.withValues(
                                            alpha: isDark ? 0.045 : 0.03,
                                          ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: selected
                                          ? sheetScheme.primary
                                              .withValues(alpha: 0.62)
                                          : hairline,
                                      width: selected ? 1.4 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (opt.leading != null) ...[
                                        opt.leading!,
                                        const SizedBox(width: 12),
                                      ],
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              uwuLabel(
                                                opt.label,
                                                enabled:
                                                    prefsNow.uwuModeEnabled,
                                              ),
                                              style: TextStyle(
                                                fontSize: 13.8,
                                                fontWeight: selected
                                                    ? FontWeight.w900
                                                    : FontWeight.w700,
                                                color: selected
                                                    ? sheetScheme.primary
                                                    : sheetScheme.onSurface,
                                              ),
                                            ),
                                            if (opt.description != null &&
                                                opt.description!
                                                    .trim()
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                uwuLabel(
                                                  opt.description!,
                                                  enabled:
                                                      prefsNow.uwuModeEnabled,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 11.8,
                                                  height: 1.32,
                                                  color: sheetScheme.onSurface
                                                      .withValues(alpha: 0.68),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        selected
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        size: 20,
                                        color: selected
                                            ? sheetScheme.primary
                                            : sheetScheme.onSurface
                                                .withValues(alpha: 0.30),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    if (closeMode.showBottomButton) ...[
                      const SizedBox(height: 10),
                      PopupBottomCloseButton(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                        uwuEnabled: prefsNow.uwuModeEnabled,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
      if (chosen != null) {
        onPicked(chosen);
      }
    }

    IconData iconForAnimatedBackdrop(AnimatedBackdropPreset preset) =>
        switch (preset) {
          AnimatedBackdropPreset.off => Icons.layers_clear_outlined,
          AnimatedBackdropPreset.gyroLiquidHorizon => Icons.sensors_rounded,
          AnimatedBackdropPreset.causticWater => Icons.water_outlined,
          AnimatedBackdropPreset.ferrofluidDrift => Icons.blur_on_rounded,
          AnimatedBackdropPreset.sunbeamDust => Icons.wb_sunny_outlined,
          AnimatedBackdropPreset.topographicPulse => Icons.terrain_outlined,
          AnimatedBackdropPreset.analogFilmLight => Icons.camera_roll_outlined,
        };

    IconData iconForLiquidGlassMode(LiquidGlassMode mode) => switch (mode) {
          LiquidGlassMode.classicFrost => Icons.ac_unit_rounded,
          LiquidGlassMode.hydroMercury => Icons.water_drop_rounded,
          LiquidGlassMode.opticalPrism => Icons.lens_blur_rounded,
          LiquidGlassMode.smokedObsidian => Icons.contrast_rounded,
          LiquidGlassMode.rippleGel => Icons.waves_rounded,
        };

    IconData iconForGreetingSubtitle(GreetingSubtitleMode mode) =>
        switch (mode) {
          GreetingSubtitleMode.finishTime => Icons.schedule_rounded,
          GreetingSubtitleMode.date => Icons.calendar_today_rounded,
          GreetingSubtitleMode.tomorrowExams => Icons.assignment_late_rounded,
          GreetingSubtitleMode.funFacts => Icons.psychology_alt_rounded,
          GreetingSubtitleMode.schoolName => Icons.school_rounded,
          GreetingSubtitleMode.none => Icons.visibility_off_outlined,
        };

    final activeBackdrop = BackgroundPresetInfo.resolve(activePrefs);

    return [
      // Section 1: Alaptéma & Színek
      buildSectionGroup(
        icon: Icons.brightness_6_rounded,
        title: 'Alaptéma & Színek',
        cardChildren: [
          Text(
            uwuLabel(
              'Alkalmazás megjelenési módja:',
              enabled: activePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildThemeOptionChip(
                  scheme: scheme,
                  dividerColor: theme.dividerColor,
                  label: uwuLabel(
                    'OLED Fekete',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  icon: Icons.dark_mode_rounded,
                  selected:
                      activePrefs.themeStyle == AppThemeStyle.oledPureBlack,
                  onTap: () => _setThemeStyle(AppThemeStyle.oledPureBlack),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThemeOptionChip(
                  scheme: scheme,
                  dividerColor: theme.dividerColor,
                  label: uwuLabel(
                    'Sötét M3',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  icon: Icons.nights_stay_rounded,
                  selected:
                      activePrefs.themeStyle == AppThemeStyle.standardDark,
                  onTap: () => _setThemeStyle(AppThemeStyle.standardDark),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildThemeOptionChip(
                  scheme: scheme,
                  dividerColor: theme.dividerColor,
                  label: uwuLabel(
                    'Világos',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  icon: Icons.light_mode_rounded,
                  selected: activePrefs.themeStyle == AppThemeStyle.light,
                  onTap: () => _setThemeStyle(AppThemeStyle.light),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 6),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Material You (Rendszerszín követése)',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              uwuLabel(
                'Automatikus színpaletta az Android háttérképből',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: activePrefs.useDynamicColor,
            onChanged: _toggleDynamicColor,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  uwuLabel(
                    'Egyedi Material 3 alapszín:',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (activePrefs.useDynamicColor)
                Text(
                  uwuLabel(
                    'Koppints a váltáshoz',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            spacing: 10,
            children: OledTheme.avatarColors.map((color) {
              final colorVal = color.toARGB32();
              final selected = !activePrefs.useDynamicColor &&
                  activePrefs.seedColorValue == colorVal;
              return InkWell(
                key: ValueKey<String>(
                  'seed-color-swatch-${colorVal.toRadixString(16)}',
                ),
                borderRadius: BorderRadius.circular(22),
                onTap: () => _setSeedColor(colorVal),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: selected
                      ? const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        )
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 12)),

      // Section 2: Liquid Glass & Felületek
      buildSectionGroup(
        icon: Icons.blur_on_rounded,
        title: 'Liquid Glass & Felületek',
        cardChildren: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel('Liquid Glass', enabled: activePrefs.uwuModeEnabled),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              uwuLabel(
                'Átlátszó üveghatású felületek és rugalmas, folyadékfizikás csúszkák',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            value: activePrefs.liquidGlassEnabled,
            onChanged: (v) =>
                _updatePrefs(activePrefs.copyWith(liquidGlassEnabled: v)),
          ),
          _FullBleedChild(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: activePrefs.liquidGlassEnabled
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Divider(
                                height: 1,
                                color:
                                    theme.dividerColor.withValues(alpha: 0.45),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    uwuLabel(
                                      'Áttetszőség',
                                      enabled: activePrefs.uwuModeEnabled,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${(activePrefs.cardOpacity.clamp(0.0, 1.0) * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: activePrefs.cardOpacity.clamp(0.0, 1.0),
                                min: 0.0,
                                max: 1.0,
                                divisions: 20,
                                onChanged: (v) => _updatePrefs(
                                  activePrefs.copyWith(cardOpacity: v),
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    uwuLabel(
                                      'Elmosás erőssége',
                                      enabled: activePrefs.uwuModeEnabled,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    activePrefs.cardBlurSigma
                                        .toStringAsFixed(0),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              Slider(
                                value: activePrefs.cardBlurSigma
                                    .clamp(2.0, 8.0),
                                min: 2,
                                max: 8,
                                divisions: 6,
                                onChanged: (v) => _updatePrefs(
                                  activePrefs.copyWith(cardBlurSigma: v),
                                ),
                              ),
                              const SizedBox(height: 6),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: theme.dividerColor.withValues(alpha: 0.45),
                        ),
                        buildAppearanceSelectorRow(
                          rowKey: const ValueKey<String>(
                            'appearance-liquid-glass-mode-row',
                          ),
                          icon: iconForLiquidGlassMode(
                            activePrefs.liquidGlassMode,
                          ),
                          title: 'Liquid Glass Mód (Fizikai optika)',
                          valueLabel:
                              '${activePrefs.liquidGlassMode.label} • ${activePrefs.liquidGlassMode.subtitle}',
                          subtitle: activePrefs.liquidGlassMode.description,
                          onTap: () => showAppearanceOptionPicker<
                              LiquidGlassMode>(
                            title: 'Liquid Glass módok',
                            subtitle:
                                'Válaszd ki a fénytörési és rugalmassági optikát',
                            headerIcon: Icons.blur_on_rounded,
                            options: [
                              for (final mode in LiquidGlassMode.values)
                                (
                                  value: mode,
                                  label: '${mode.label} (${mode.subtitle})',
                                  description: mode.description,
                                  selected:
                                      activePrefs.liquidGlassMode == mode,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: scheme.primary
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      iconForLiquidGlassMode(mode),
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                            onPicked: (mode) => _updatePrefs(
                              _livePrefs(subCtx)
                                  .copyWith(liquidGlassMode: mode),
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: theme.dividerColor.withValues(alpha: 0.45),
                        ),
                        buildAppearanceSelectorRow(
                          rowKey: const ValueKey<String>(
                            'appearance-backdrop-effect-row',
                          ),
                          icon: activePrefs.hasCustomBackdrop
                              ? Icons.photo_rounded
                              : activeBackdrop.icon,
                          title: 'Effektek',
                          valueLabel: activePrefs.hasCustomBackdrop
                              ? 'Saját háttérkép aktív'
                              : activeBackdrop.label,
                          subtitle: 'Stúdió háttér effektus és atmoszféra',
                          onTap: () => showAppearanceOptionPicker<
                              BackgroundPresetInfo>(
                            title: 'Effektek',
                            subtitle:
                                'Válassz stúdió hátteret vagy atmoszférát',
                            headerIcon: Icons.gradient_rounded,
                            options: [
                              for (final bg in BackgroundPresetInfo.presets)
                                (
                                  value: bg,
                                  label: bg.label,
                                  description: bg.isVectorContour
                                      ? 'Vektoros szintvonalas stúdió háttér'
                                      : (bg.isLightPreset
                                          ? 'Világos stúdió árnyalat adaptív kontraszttal'
                                          : 'Sötét stúdió színátmenet'),
                                  selected: !activePrefs.hasCustomBackdrop &&
                                      activePrefs.backgroundPreset == bg.id,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: bg.gradientColors.length >= 2
                                            ? bg.gradientColors
                                            : [
                                                bg.gradientColors.first,
                                                bg.gradientColors.first,
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.18),
                                      ),
                                    ),
                                    child: Icon(
                                      bg.icon,
                                      size: 17,
                                      color: bg.isLightPreset
                                          ? const Color(0xFF101318)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                            onPicked: (bg) => _updatePrefs(
                              _livePrefs(subCtx).copyWith(
                                backgroundPreset: bg.id,
                                clearCustomBackdropPath: true,
                              ),
                            ),
                          ),
                        ),
                        Divider(
                          height: 1,
                          indent: 66,
                          endIndent: 16,
                          color: theme.dividerColor.withValues(alpha: 0.45),
                        ),
                        buildAppearanceSelectorRow(
                          rowKey: const ValueKey<String>(
                            'appearance-animated-backdrop-row',
                          ),
                          icon: iconForAnimatedBackdrop(
                            activePrefs.animatedBackdropPreset,
                          ),
                          title: 'Élő hátterek',
                          valueLabel:
                              '${activePrefs.animatedBackdropPreset.label} • ${activePrefs.animatedBackdropPreset.subtitle}',
                          subtitle:
                              'Valós idejű GPU-barát animált háttérjelenet',
                          onTap: () => showAppearanceOptionPicker<
                              AnimatedBackdropPreset>(
                            title: 'Élő hátterek',
                            subtitle:
                                'Animált háttérjelenetek és giroszkópos effektek',
                            headerIcon: Icons.auto_awesome_motion_rounded,
                            options: [
                              for (final preset
                                  in AnimatedBackdropPreset.values)
                                (
                                  value: preset,
                                  label: preset.label,
                                  description: preset.subtitle,
                                  selected:
                                      activePrefs.animatedBackdropPreset ==
                                          preset,
                                  leading: Container(
                                    width: 36,
                                    height: 36,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: preset ==
                                              AnimatedBackdropPreset.off
                                          ? scheme.surfaceContainerHighest
                                          : preset.baseColor,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: scheme.onSurface
                                            .withValues(alpha: 0.16),
                                      ),
                                    ),
                                    child: Icon(
                                      iconForAnimatedBackdrop(preset),
                                      size: 18,
                                      color: preset ==
                                              AnimatedBackdropPreset.off
                                          ? scheme.onSurface
                                              .withValues(alpha: 0.72)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                            onPicked: (preset) => _updatePrefs(
                              _livePrefs(subCtx).copyWith(
                                animatedBackdropPreset: preset,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 16)),

      // Section 3: Kártyák & Elrendezés
      buildSectionGroup(
        icon: Icons.view_quilt_rounded,
        title: uwuLabel(
          'Kártyák & Elrendezés',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          SwitchListTile.adaptive(
            key: const ValueKey<String>('appearance-minimalist-mode-switch'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.compress_rounded,
              color: scheme.primary,
            ),
            title: Text(
              uwuLabel(
                'Minimalista mód',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              uwuLabel(
                'Megőrzi a Liquid Glass dizájnt és a lekerekített sarkokat, miközben a kártyákat és térközöket kompaktabbá teszi',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: activePrefs.minimalistModeEnabled,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              _updatePrefs(activePrefs.withMinimalistMode(val));
            },
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            uwuLabel(
              'Felugró ablakok bezárása (Modális vezérlők):',
              enabled: activePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            spacing: 8,
            children: ModalCloseButtonMode.values.map((mode) {
              final selected = activePrefs.modalCloseMode == mode;
              return ChoiceChip(
                label: Text(
                  uwuLabel(mode.label, enabled: activePrefs.uwuModeEnabled),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                selected: selected,
                onSelected: (_) {
                  HapticFeedback.selectionClick();
                  _updatePrefs(activePrefs.copyWith(modalCloseMode: mode));
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 4),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('appearance-fun-greetings-switch'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.sentiment_very_satisfied_rounded,
              color: scheme.primary,
            ),
            title: Text(
              uwuLabel(
                'Fun üdvözlő üzenetek',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              uwuLabel(
                'Laza, vicces és napszakhoz illő köszönések a főoldalon',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: activePrefs.funGreetingsEnabled,
            onChanged: (val) {
              HapticFeedback.selectionClick();
              GreetingUtils.refreshSessionGreeting();
              _updatePrefs(activePrefs.withFunGreetings(val));
            },
          ),
          const SizedBox(height: 6),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 4),
          buildAppearanceSelectorRow(
            rowKey: const ValueKey<String>(
              'appearance-greeting-subtitle-row',
            ),
            icon: iconForGreetingSubtitle(activePrefs.greetingSubtitleMode),
            title: 'Köszönés alatti szöveg',
            valueLabel: activePrefs.greetingSubtitleMode.label,
            subtitle: activePrefs.greetingSubtitleMode.description,
            onTap: () => showAppearanceOptionPicker<GreetingSubtitleMode>(
              title: 'Köszönés alatti szöveg',
              subtitle:
                  'Válaszd ki, mi jelenjen meg a főoldali köszönés alatt',
              headerIcon: Icons.subtitles_outlined,
              options: [
                for (final mode in GreetingSubtitleMode.values)
                  (
                    value: mode,
                    label: mode.label,
                    description: mode.description,
                    selected: activePrefs.greetingSubtitleMode == mode,
                    leading: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        iconForGreetingSubtitle(mode),
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
              onPicked: (mode) {
                if (mode == GreetingSubtitleMode.funFacts) {
                  unawaited(GreetingUtils.ensureFunFactsLoaded());
                  GreetingUtils.pickFunFact(forceRefresh: true);
                }
                _updatePrefs(
                  _livePrefs(subCtx).withGreetingSubtitleMode(mode),
                );
              },
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 16)),

      // Section 4: Ikon & Betűtípus
      buildSectionGroup(
        icon: Icons.apps_rounded,
        title: uwuLabel(
          'Ikon & Betűtípus',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          Text(
            uwuLabel('Alkalmazás ikon', enabled: activePrefs.uwuModeEnabled),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: buildIconOptionCard(
                  presetKey: 'default',
                  assetPath: AppIconPresetInfo.defaultIconAsset,
                  title: uwuLabel(
                    'Alapértelmezett',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  subtitle: uwuLabel(
                    'Új Tinta ikon',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  selected: !isClassicIcon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: buildIconOptionCard(
                  presetKey: 'classic',
                  assetPath: AppIconPresetInfo.classicIconAsset,
                  title: uwuLabel(
                    'Klasszikus',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  subtitle: uwuLabel(
                    'Korábbi ikon',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  selected: isClassicIcon,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            uwuLabel(
              'Az ikonokat a Firka (QwIT) inspirálta.',
              enabled: activePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            color: theme.dividerColor.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.color_lens_outlined, color: scheme.primary),
            title: Text(
              uwuLabel(
                'Érdemjegyek színpalettája',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              uwuLabel(
                '1-5 jegyek színének és HEX kódjának módosítása',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _pushSettingsSubScreen(
              'Érdemjegyek Színeinek Testreszabása',
              _buildGradeColorsChildren,
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildGradeColorsChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              uwuLabel(
                'Koppints egy érdemjegyre (1-5), majd válassz színt:',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: _resetGradeColors,
            child: Text(
              uwuLabel('Alapértelmezett', enabled: activePrefs.uwuModeEnabled),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [5, 4, 3, 2, 1].map((g) {
          final badgeColor = activePrefs.colorForGrade(g);
          final selected = _selectedGradeToCustomize == g;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => setState(() => _selectedGradeToCustomize = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: selected ? 3 : 0,
                    ),
                  ),
                  child: Text(
                    '$g',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 14),
      EdgeFadeHorizontalScroll(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        spacing: 10,
        children: [
          ...OledTheme.gradeColorPalette.map((paletteColor) {
            final val = paletteColor.toARGB32();
            final currentVal = activePrefs
                .colorForGrade(_selectedGradeToCustomize)
                .toARGB32();
            final isCurrent = val == currentVal;
            return InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => _setGradeColor(_selectedGradeToCustomize, val),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: paletteColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isCurrent ? scheme.onSurface : Colors.transparent,
                    width: 2.2,
                  ),
                ),
                child: isCurrent
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 18,
                      )
                    : null,
              ),
            );
          }),
          ActionChip(
            avatar: const Icon(Icons.tag_rounded, size: 16),
            label: Text(
              uwuLabel('Egyedi HEX', enabled: activePrefs.uwuModeEnabled),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            onPressed: () =>
                _promptCustomHexForGrade(_selectedGradeToCustomize),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildTimetableSettingsChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    return [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          uwuLabel(
            'Elmaradó órák elrejtése',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          uwuLabel(
            'Az elmaradt tanórák nem jelennek meg az órarendben',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        value: activePrefs.hideCancelledLessons,
        onChanged: (val) => _updatePrefs(
          activePrefs.withExtra('hideCancelledLessons', val),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          uwuLabel(
            'Lyukas / szabad órák elrejtése',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          uwuLabel(
            'A szabad sávok (nulladik óra, lyukasóra) nem jelennek meg',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        value: activePrefs.hideFreeLessons,
        onChanged: (val) => _updatePrefs(
          activePrefs.withExtra('hideFreeLessons', val),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          uwuLabel(
            'Hétvége mutatása az órarendben',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        value: activePrefs.showWeekends,
        onChanged: (val) => _updatePrefs(
          activePrefs.copyWith(showWeekends: val),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          uwuLabel(
            'Számonkérések mutatása az órarenden',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          uwuLabel(
            'Dolgozatok és számonkérések jelzése a tanítási napokon és órákon.',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        value: activePrefs.showTimetableExams,
        onChanged: (val) => _updatePrefs(
          activePrefs.withShowTimetableExams(val),
        ),
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(
          uwuLabel(
            'Házik mutatása az órarenden',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          uwuLabel(
            'Házi feladat jelvény megjelenítése a tanórákon.',
            enabled: activePrefs.uwuModeEnabled,
          ),
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
        value: activePrefs.showTimetableHomework,
        onChanged: (val) => _updatePrefs(
          activePrefs.withShowTimetableHomework(val),
        ),
      ),
      const Divider(height: 20),
      Text(
        uwuLabel(
          'Kalkulátor jegy súlyozása:',
          enabled: activePrefs.uwuModeEnabled,
        ),
        style: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 8),
      EdgeFadeHorizontalScroll(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        spacing: 8,
        children: [
          ChoiceChip(
            showCheckmark: false,
            label: Text(
              uwuLabel('100% alapeset', enabled: activePrefs.uwuModeEnabled),
            ),
            selected: !activePrefs.calcAllow200Weight,
            onSelected: (_) => _updatePrefs(
              activePrefs.copyWith(calcAllow200Weight: false),
            ),
          ),
          ChoiceChip(
            showCheckmark: false,
            label: Text(
              uwuLabel(
                '200% témazáró engedélyezése',
                enabled: activePrefs.uwuModeEnabled,
              ),
            ),
            selected: activePrefs.calcAllow200Weight,
            onSelected: (_) => _updatePrefs(
              activePrefs.copyWith(calcAllow200Weight: true),
            ),
          ),
        ],
      ),
      const Divider(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              uwuLabel(
                'Globális kerekítési határok:',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _updateRounding(const GradeRoundingConfig()),
            child: Text(
              uwuLabel('Alaphelyzet', enabled: activePrefs.uwuModeEnabled),
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      _buildThresholdSlider(
        theme: theme,
        scheme: scheme,
        gradeLabel: uwuLabel(
          'Jeles (5) határ',
          enabled: activePrefs.uwuModeEnabled,
        ),
        color: activePrefs.colorForGrade(5),
        value: activePrefs.roundingConfig.threshold5,
        min: 4.00,
        max: 4.95,
        onChanged: (v) => _previewRounding(
          activePrefs.roundingConfig.copyWith(
            threshold5: double.parse(v.toStringAsFixed(2)),
          ),
        ),
        onChangeEnd: (v) => _updateRounding(
          activePrefs.roundingConfig.copyWith(
            threshold5: double.parse(v.toStringAsFixed(2)),
          ),
        ),
      ),
      _buildThresholdSlider(
        theme: theme,
        scheme: scheme,
        gradeLabel: uwuLabel(
          'Jó (4) határ',
          enabled: activePrefs.uwuModeEnabled,
        ),
        color: activePrefs.colorForGrade(4),
        value: activePrefs.roundingConfig.threshold4,
        min: 3.00,
        max: 3.95,
        onChanged: (v) => _previewRounding(
          activePrefs.roundingConfig.copyWith(
            threshold4: double.parse(v.toStringAsFixed(2)),
          ),
        ),
        onChangeEnd: (v) => _updateRounding(
          activePrefs.roundingConfig.copyWith(
            threshold4: double.parse(v.toStringAsFixed(2)),
          ),
        ),
      ),
      _buildThresholdSlider(
        theme: theme,
        scheme: scheme,
        gradeLabel: uwuLabel(
          'Közepes (3) határ',
          enabled: activePrefs.uwuModeEnabled,
        ),
        color: activePrefs.colorForGrade(3),
        value: activePrefs.roundingConfig.threshold3,
        min: 2.00,
        max: 2.95,
        onChanged: (v) => _previewRounding(
          activePrefs.roundingConfig.copyWith(
            threshold3: double.parse(v.toStringAsFixed(2)),
          ),
        ),
        onChangeEnd: (v) => _updateRounding(
          activePrefs.roundingConfig.copyWith(
            threshold3: double.parse(v.toStringAsFixed(2)),
          ),
        ),
      ),
      _buildThresholdSlider(
        theme: theme,
        scheme: scheme,
        gradeLabel: uwuLabel(
          'Elégséges (2) határ',
          enabled: activePrefs.uwuModeEnabled,
        ),
        color: activePrefs.colorForGrade(2),
        value: activePrefs.roundingConfig.threshold2,
        min: 1.10,
        max: 2.20,
        onChanged: (v) => _previewRounding(
          activePrefs.roundingConfig.copyWith(
            threshold2: double.parse(v.toStringAsFixed(2)),
          ),
        ),
        onChangeEnd: (v) => _updateRounding(
          activePrefs.roundingConfig.copyWith(
            threshold2: double.parse(v.toStringAsFixed(2)),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildExportImportChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    return [
      Text(
        uwuLabel(
          'Minden testreszabás (színek, becenév, tantárgy- és tanár-átnevezések, kerekítési határok, MenetrendGO beállítások) automatikusan megmarad kijelentkezés után is, vagy JSON fájlba exportálható:',
          enabled: activePrefs.uwuModeEnabled,
        ),
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.72),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _exportSettingsJson,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(
                uwuLabel(
                  'Exportálás (JSON)',
                  enabled: activePrefs.uwuModeEnabled,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: _importSettingsJson,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(
                uwuLabel(
                  'Importálás (JSON)',
                  enabled: activePrefs.uwuModeEnabled,
                ),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildSystemAboutChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    return [
      _buildRow(
        scheme,
        uwuLabel('Alkalmazás', enabled: activePrefs.uwuModeEnabled),
        uwuLabel('Tinta Napló v$_appVersion', enabled: activePrefs.uwuModeEnabled),
      ),
      _buildRow(
        scheme,
        uwuLabel('GitHub', enabled: activePrefs.uwuModeEnabled),
        'github.com/mlnlbrt10/tinta-naplo',
      ),
      const SizedBox(height: 12),
      TactileBounce(
        onTap: () {
          Navigator.of(context).push(
            SmoothSharedAxisRoute(
              page: AboutAppScreen(
                prefs: activePrefs,
                onPrefsChanged: _updatePrefs,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 16,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  uwuLabel(
                    'Az alkalmazásról & Frissítések megnyitása',
                    enabled: activePrefs.uwuModeEnabled,
                  ),
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
      if (activePrefs.developerModeUnlocked) ...[
        const SizedBox(height: 12),
        TactileBounce(
          pressedScale: 0.98,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              SmoothSharedAxisRoute(
                page: DeveloperOptionsHubScreen(
                  prefs: activePrefs,
                  onPrefsChanged: _updatePrefs,
                  kretaClient: widget.kretaClient,
                  wearSyncService: widget.wearSyncService,
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 14,
            ),
            decoration: BoxDecoration(
              color: OledTheme.uwuPastelPink.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: OledTheme.uwuPastelPink.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                const DeveloperIconBubble(
                  icon: Icons.terminal_rounded,
                  accentColor: OledTheme.uwuPastelPink,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uwuLabel(
                          'Fejlesztői beállítások',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        uwuLabel(
                          'Megjelenés, Demó mód, KRÉTA Auth, Wear OS és Cache',
                          enabled: activePrefs.uwuModeEnabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
                if (activePrefs.demoModeEnabled ||
                    activePrefs.uwuModeEnabled ||
                    activePrefs.customSkinEnabled ||
                    activePrefs.fitymaModeEnabled) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: OledTheme.uwuPastelPink.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      uwuLabel('Aktív', enabled: activePrefs.uwuModeEnabled),
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: OledTheme.uwuPastelPink,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.72),
                ),
              ],
            ),
          ),
        ),
      ],
    ];
  }

  /// Google Calendar Sync (CalendarContract) Settings Accordion.
  Widget _buildCalendarSyncSettingsAccordion(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final calSettings = _calendarSyncSettings;
    final subtitle = calSettings != null && calSettings.enabled
        ? (calSettings.targetCalendarName?.isNotEmpty == true
            ? '${calSettings.contentMode.label} • ${calSettings.targetCalendarName}'
            : calSettings.contentMode.label)
        : 'Kikapcsolva';

    return _SettingsAccordionCard(
      icon: Icons.event_available_rounded,
      title: 'Naptár szinkronizálás',
      subtitle: subtitle,
      christmasCap: _currentPrefs.christmasModeEnabled,
      prefs: _currentPrefs,
      stateListenable: _stateVersion,
      prefsGetter: () => _currentPrefs,
      childrenBuilder: (subCtx) {
        final activePrefs = _livePrefs(subCtx);
        return [
          _CalendarSyncSettingsSection(
            session: widget.session,
            kretaClient: widget.kretaClient,
            dashboardData: widget.dashboardData,
            profilePrefs: activePrefs,
            onSettingsChanged: (updated) {
              if (!mounted) return;
              setState(() => _calendarSyncSettings = updated);
            },
          ),
        ];
      },
    );
  }

  /// Part A #4: MenetrendGO Commuter Transit Settings Accordion grouped under Main Settings.
  Widget _buildMenetrendSettingsAccordion(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final homeLabel = _currentPrefs.homeAddress.isNotEmpty
        ? _currentPrefs.homeAddress
        : _currentPrefs.primaryHomeStop;
    final schoolLabel = _currentPrefs.schoolAddress.isNotEmpty
        ? _currentPrefs.schoolAddress
        : _currentPrefs.primarySchoolStop;
    return _SettingsAccordionCard(
      icon: Icons.directions_railway_filled_rounded,
      title: 'MenetrendGO',
      subtitle: _currentPrefs.transitConfigured
          ? '$homeLabel <-> $schoolLabel'
          : 'Nincs beállítva',
      christmasCap: _currentPrefs.christmasModeEnabled,
      prefs: _currentPrefs,
      stateListenable: _stateVersion,
      prefsGetter: () => _currentPrefs,
      childrenBuilder: _buildMenetrendChildren,
    );
  }

  List<Widget> _buildMenetrendChildren(BuildContext subCtx) {
    final activePrefs = _livePrefs(subCtx);
    final theme = Theme.of(subCtx);
    final scheme = theme.colorScheme;
    final currentSpeed =
        MenetrendService.normalizeWalkingSpeed(activePrefs.walkingSpeedKmh);

    Widget buildSectionGroup({
      required IconData icon,
      required String title,
      required List<Widget> cardChildren,
    }) {
      return _StandaloneSettingsChild(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: _buildAppearanceSectionHeader(
                theme,
                scheme,
                icon,
                title,
              ),
            ),
            SoftGlassCard(
              prefs: activePrefs,
              padding: const EdgeInsets.symmetric(vertical: 14),
              borderRadius: OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final child in cardChildren)
                    if (child is _FullBleedChild ||
                        child is EdgeFadeHorizontalScroll)
                      child
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: child,
                      ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Future<void> resolveNearestStop({
      required bool isHome,
      required double lat,
      required double lon,
    }) async {
      final stop = await MenetrendService().resolveNearestStopForCoordinates(
        lat: lat,
        lon: lon,
      );
      if (!mounted || stop == null) return;
      final walkMins = MenetrendService.estimateWalkingMinutesBetween(
        lat1: lat,
        lon1: lon,
        lat2: stop.lat,
        lon2: stop.lon,
        walkingSpeedKmh: activePrefs.walkingSpeedKmh,
      );
      final latestPrefs = _currentPrefs;
      if (isHome) {
        _updatePrefs(
          latestPrefs
              .copyWith(
                transitHomeStation: stop.name,
                walkHomeToBusMinutes: walkMins,
                walkingDurationMinutes: walkMins,
              )
              .withExtras({
            'homeBusLat': stop.lat,
            'homeBusLon': stop.lon,
          }),
        );
      } else {
        _updatePrefs(
          latestPrefs
              .copyWith(
                transitSchoolStation: stop.name,
                walkSchoolToBusMinutes: walkMins,
              )
              .withExtras({
            'schoolBusLat': stop.lat,
            'schoolBusLon': stop.lon,
          }),
        );
      }
    }

    return [
      // Card 1: Master visibility toggle
      buildSectionGroup(
        icon: Icons.directions_railway_filled_rounded,
        title: uwuLabel('MenetrendGO', enabled: activePrefs.uwuModeEnabled),
        cardChildren: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'MenetrendGO kártya megjelenítése a főoldalon',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              uwuLabel(
                'Következő indulás, sétaidő és valós késések a főképernyőn',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: activePrefs.transitCardEnabled,
            onChanged: (v) => _updatePrefs(
              activePrefs.copyWith(transitCardEnabled: v),
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 14)),

      // Card 2: Addresses only (auto-resolves nearest transit stops)
      buildSectionGroup(
        icon: Icons.route_rounded,
        title: uwuLabel(
          'Útvonal & címek',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          _TransitStopSearchField(
            controller: _homeAddressController,
            label: uwuLabel(
              'Otthoni cím',
              enabled: activePrefs.uwuModeEnabled,
            ),
            hint: uwuLabel(
              'Kezdd el gépelni a címed (pl. Szolnok, Kossuth tér 1.)',
              enabled: activePrefs.uwuModeEnabled,
            ),
            icon: Icons.home_work_rounded,
            isAddressSearch: true,
            onSelectedResult: (r) {
              var next = _currentPrefs.withExtras({
                'homeAddress': r.name,
                'homeAddressLat': r.lat,
                'homeAddressLon': r.lon,
              });
              if (next.transitHomeStation.isEmpty) {
                next = next.copyWith(transitHomeStation: r.name);
              }
              _updatePrefs(next);
              unawaited(resolveNearestStop(isHome: true, lat: r.lat, lon: r.lon));
            },
            onSelected: (_) {},
            onCleared: () => _updatePrefs(
              _currentPrefs.copyWith(transitHomeStation: '').withExtras({
                'homeAddress': null,
                'homeAddressLat': null,
                'homeAddressLon': null,
                'homeBusLat': null,
                'homeBusLon': null,
              }),
            ),
          ),
          const SizedBox(height: 12),
          _TransitStopSearchField(
            controller: _schoolAddressController,
            label: uwuLabel('Iskola címe', enabled: activePrefs.uwuModeEnabled),
            hint: uwuLabel(
              'Kezdd el gépelni az iskola címét (pl. Szolnok, Ady Endre út)',
              enabled: activePrefs.uwuModeEnabled,
            ),
            icon: Icons.apartment_rounded,
            isAddressSearch: true,
            onSelectedResult: (r) {
              var next = _currentPrefs.withExtras({
                'schoolAddress': r.name,
                'schoolAddressLat': r.lat,
                'schoolAddressLon': r.lon,
              });
              if (next.transitSchoolStation.isEmpty) {
                next = next.copyWith(transitSchoolStation: r.name);
              }
              _updatePrefs(next);
              unawaited(
                resolveNearestStop(isHome: false, lat: r.lat, lon: r.lon),
              );
            },
            onSelected: (_) {},
            onCleared: () => _updatePrefs(
              _currentPrefs.copyWith(transitSchoolStation: '').withExtras({
                'schoolAddress': null,
                'schoolAddressLat': null,
                'schoolAddressLon': null,
                'schoolBusLat': null,
                'schoolBusLon': null,
              }),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            uwuLabel(
              'A legközelebbi megállók és a gyaloglási idő automatikusan frissülnek.',
              enabled: activePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.60),
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 14)),

      // Card 3: Transit Modes & Continuous Walking Speed Slider
      buildSectionGroup(
        icon: Icons.commute_rounded,
        title: uwuLabel(
          'Közlekedési módok & séta',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.train_rounded, size: 20),
            title: Text(
              uwuLabel('Vonat', enabled: activePrefs.uwuModeEnabled),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            value: activePrefs.transitAllowTrain,
            onChanged: (v) => _updatePrefs(
              activePrefs.copyWith(transitAllowTrain: v),
            ),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.directions_bus_filled_rounded, size: 20),
            title: Text(
              uwuLabel(
                'Helyközi / távolsági busz',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            value: activePrefs.transitAllowCoach,
            onChanged: (v) => _updatePrefs(
              activePrefs.copyWith(transitAllowCoach: v),
            ),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.directions_bus_rounded, size: 20),
            title: Text(
              uwuLabel('Helyi járat', enabled: activePrefs.uwuModeEnabled),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            value: activePrefs.transitAllowLocalBus,
            onChanged: (v) => _updatePrefs(
              activePrefs.copyWith(transitAllowLocalBus: v),
            ),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.tram_rounded, size: 20),
            title: Text(
              uwuLabel(
                'Villamos / HÉV / Metró',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            value: activePrefs.transitAllowTramSubway,
            onChanged: (v) => _updatePrefs(
              activePrefs.withTransitAllowTramSubway(v),
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                uwuLabel('Sétatempó', enabled: activePrefs.uwuModeEnabled),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              Text(
                uwuLabel(
                  MenetrendService.walkingSpeedLabel(currentSpeed),
                  enabled: activePrefs.uwuModeEnabled,
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey<String>('menetrend-walking-speed-slider'),
            value: currentSpeed,
            min: 3.0,
            max: 8.0,
            divisions: 10,
            label: uwuLabel(
              MenetrendService.walkingSpeedLabel(currentSpeed),
              enabled: activePrefs.uwuModeEnabled,
            ),
            onChanged: (v) => _updatePrefs(
              _withUpdatedWalkingSpeed(
                activePrefs,
                MenetrendService.normalizeWalkingSpeed(v),
              ),
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 14)),

      // Card 4: Daily Commute Editor
      buildSectionGroup(
        icon: Icons.calendar_today_rounded,
        title: uwuLabel(
          'Napi ingázási beállítások',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          _FullBleedChild(
            child: _DayCommuteEditor(
              prefs: activePrefs,
              onChanged: _updatePrefs,
            ),
          ),
        ],
      ),
      const _StandaloneSettingsChild(child: SizedBox(height: 14)),

      // Card 5: Reworked Notifications Card
      buildSectionGroup(
        icon: Icons.notifications_active_rounded,
        title: uwuLabel(
          'Indulási értesítések',
          enabled: activePrefs.uwuModeEnabled,
        ),
        cardChildren: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Indulási & késés riasztások',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style:
                  const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              uwuLabel(
                'Indulás előtti figyelmeztetés és élő járatkésés riasztás',
                enabled: activePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: 11.5,
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
            value: activePrefs.transitNotificationsEnabled,
            onChanged: (val) async {
              try {
                if (val) {
                  await MenetrendService.requestNotificationPermissions();
                } else {
                  await MenetrendService.cancelAlarms();
                }
              } catch (_) {}
              if (!mounted) return;
              _updatePrefs(
                _currentPrefs.copyWith(transitNotificationsEnabled: val),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                uwuLabel(
                  'Értesítési időtartalék (indulás előtt)',
                  enabled: activePrefs.uwuModeEnabled,
                ),
                style:
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              Text(
                uwuLabel(
                  '${activePrefs.transitAlertBufferMinutes} perc',
                  enabled: activePrefs.uwuModeEnabled,
                ),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: activePrefs.transitAlertBufferMinutes
                .clamp(1, 20)
                .toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            label: uwuLabel(
              '${activePrefs.transitAlertBufferMinutes} perc',
              enabled: activePrefs.uwuModeEnabled,
            ),
            onChanged: (v) => _updatePrefs(
              activePrefs.copyWith(transitAlertBufferMinutes: v.round()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    await MenetrendService.requestNotificationPermissions();
                    final mins = _currentPrefs.transitAlertBufferMinutes > 0
                        ? _currentPrefs.transitAlertBufferMinutes
                        : 5;
                    await MenetrendService.showImmediateNotification(
                      title: 'Indulás $mins perc múlva • S150',
                      body:
                          '07:09-es járat (Bodajk -> Székesfehérvár) • ${_currentPrefs.walkingDurationMinutes}p séta az állomásra',
                    );
                  },
                  icon: const Icon(Icons.notifications_active_rounded, size: 17),
                  label: Text(
                    uwuLabel(
                      'Teszt értesítés',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    MenetrendService.openInMenetrendGo();
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: Text(
                    uwuLabel(
                      'MenetrendGO',
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ];
  }

  /// Module 1 header slivers: Hiányzások és Késések summary card + synced chip bar.
  List<Widget> _buildAttendanceHeaderSlivers(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final min = MinimalistTokens.of(_currentPrefs);
    final summary = OmissionsSummary.fromList(_omissions);

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          min.horizontalPagePadding,
          min.enabled ? 6 : 12,
          min.horizontalPagePadding,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: ChristmasSnowCap(
            enabled: _currentPrefs.christmasModeEnabled,
            child: SoftGlassCard(
              prefs: _currentPrefs,
              padding: min.enabled
                  ? const EdgeInsets.all(10)
                  : const EdgeInsets.all(18),
              borderRadius: min.enabled ? min.largeRadius : OledTheme.largeRadius,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: min.enabled ? 30 : 40,
                        height: min.enabled ? 30 : 40,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(
                            min.enabled ? 9 : 14,
                          ),
                        ),
                        child: Icon(
                          Icons.event_busy_rounded,
                          color: scheme.primary,
                          size: min.enabled ? 17 : 22,
                        ),
                      ),
                      SizedBox(width: min.enabled ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uwu(
                                'Hiányzások és Késések',
                                enabled: _currentPrefs.uwuModeEnabled,
                              ),
                              style: (min.enabled
                                      ? theme.textTheme.labelLarge
                                      : theme.textTheme.titleMedium)
                                  ?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (!min.enabled)
                              Text(
                                uwuLabel(
                                  'Mulasztott órák és késések részletes összesítése',
                                  enabled: _currentPrefs.uwuModeEnabled,
                                ),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurface.withValues(alpha: 0.62),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_isLoadingModules)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  SizedBox(height: min.enabled ? 8 : 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatPill(
                          theme,
                          scheme,
                          label: uwuLabel(
                            'Összes óra',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          value: uwuLabel(
                            '${summary.totalMissedHours} óra',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          color: scheme.primary,
                        ),
                      ),
                      SizedBox(width: min.enabled ? 4 : 8),
                      Expanded(
                        child: _buildStatPill(
                          theme,
                          scheme,
                          label: uwuLabel(
                            'Igazolt',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          value: uwuLabel(
                            '${summary.certifiedHours} óra',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          color: OledTheme.omissionExcusedColor(theme.brightness),
                        ),
                      ),
                      SizedBox(width: min.enabled ? 4 : 8),
                      Expanded(
                        child: _buildStatPill(
                          theme,
                          scheme,
                          label: uwuLabel(
                            'Igazolatlan',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          value: uwuLabel(
                            '${summary.uncertifiedHours} óra',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          color:
                              OledTheme.omissionUnexcusedRedColor(theme.brightness),
                        ),
                      ),
                      if (summary.pendingHours > 0) ...[
                        SizedBox(width: min.enabled ? 4 : 8),
                        Expanded(
                          child: _buildStatPill(
                            theme,
                            scheme,
                            label: uwuLabel(
                              'Igazolandó',
                              enabled: _currentPrefs.uwuModeEnabled,
                            ),
                            value: uwuLabel(
                              '${summary.pendingHours} óra',
                              enabled: _currentPrefs.uwuModeEnabled,
                            ),
                            color: OledTheme.omissionPendingOrangeColor(
                              theme.brightness,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(width: min.enabled ? 4 : 8),
                      Expanded(
                        child: _buildStatPill(
                          theme,
                          scheme,
                          label: uwuLabel(
                            'Késések',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          value: uwuLabel(
                            '${summary.totalTardinessMinutes} perc',
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          color: OledTheme.omissionPendingOrangeColor(
                            theme.brightness,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: min.enabled ? 8 : 14),
                  // B5: Prominent "Összes hiányzás megtekintése" button
                  FilledButton.tonalIcon(
                    onPressed: _openAllOmissionsScreen,
                    icon: Icon(
                      Icons.list_alt_rounded,
                      size: min.enabled ? 15 : 18,
                    ),
                    label: Text(
                      uwu(
                        'Összes hiányzás megtekintése (${summary.allOmissions.length} tétel)',
                        enabled: _currentPrefs.uwuModeEnabled,
                      ),
                      style: TextStyle(
                        fontSize: min.enabled ? 12 : 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        vertical: min.enabled ? 8 : 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          min.enabled ? 10 : 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ).staggeredEntrance(0, enabled: _entranceActive),
        ),
      ),
      SliverToBoxAdapter(child: SizedBox(height: min.enabled ? 6 : 12)),
      SliverToBoxAdapter(
        child: _buildOmissionFilterChips(
          selected: _attendanceFilter,
          onSelected: _selectAttendanceFilter,
          pageController: _attendancePageController,
          ignorePageController: _isAnimatingAttendancePage,
          liquidGlassEnabled:
              (AppProvidersScope.maybeOf(context)?.settings.prefs ??
                      _currentPrefs)
                  .liquidGlassEnabled,
        ),
      ),
      SliverToBoxAdapter(child: SizedBox(height: min.enabled ? 6 : 12)),
    ];
  }

  Widget _buildAttendancePageViewBody(
    ThemeData theme,
    ColorScheme scheme,
    _AttendanceFilter pageFilter, {
    required bool isActivePage,
  }) {
    final min = MinimalistTokens.of(_currentPrefs);
    final summary = OmissionsSummary.fromList(_omissions);
    final filtered = _filterOmissions(summary, pageFilter);
    final subjectGroups = groupOmissionsBySubject(
      filtered,
      prefs: _currentPrefs,
      referenceLessons: _effectiveReferenceLessons,
    );

    return CustomScrollView(
      key: isActivePage
          ? const ValueKey<String>('attendance-active-scroll')
          : PageStorageKey<String>('attendance-scroll-${pageFilter.name}'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (subjectGroups.isEmpty)
          SliverFadeTransition(
            opacity: const AlwaysStoppedAnimation<double>(1.0),
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(
                min.horizontalPagePadding,
                0,
                min.horizontalPagePadding,
                112,
              ),
              sliver: SliverToBoxAdapter(
                child: _buildEmptyOmissionCard(
                  prefs: _currentPrefs,
                  message: uwuLabel(
                    'Nincs rögzített mulasztás vagy késés ebben a kategóriában.',
                    enabled: _currentPrefs.uwuModeEnabled,
                  ),
                ),
              ),
            ),
          )
        else
          SliverFadeTransition(
            opacity: const AlwaysStoppedAnimation<double>(1.0),
            sliver: SliverPadding(
              padding: EdgeInsets.fromLTRB(
                min.horizontalPagePadding,
                0,
                min.horizontalPagePadding,
                112,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => RepaintBoundary(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: min.enabled ? 5 : 10),
                      child: _SubjectAbsenceCard(
                        group: subjectGroups[i],
                        prefs: _currentPrefs,
                        dateFormat: _dateFormat,
                      ),
                    ),
                  ),
                  childCount: subjectGroups.length,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatPill(
    ThemeData theme,
    ColorScheme scheme, {
    required String label,
    required String value,
    required Color color,
  }) {
    final min = MinimalistTokens.of(_currentPrefs);
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: min.enabled ? 5 : 10,
        horizontal: min.enabled ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(min.enabled ? 9 : 16),
        border: Border.all(
          color: color.withValues(alpha: 0.55),
          width: min.borderWidth,
        ),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
              fontSize: min.enabled ? 11 : 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
              fontSize: min.enabled ? 9 : 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// Module 2 header slivers: Kréta Üzenetek header + synced folder bar.
  List<Widget> _buildMessagesHeaderSlivers(
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final min = MinimalistTokens.of(_currentPrefs);
    final unreadMessages = _messages
        .where((m) => !m.isSent && !_isMessageRead(m))
        .toList();
    final liquidGlass =
        (AppProvidersScope.maybeOf(context)?.settings.prefs ?? _currentPrefs)
            .liquidGlassEnabled;

    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          min.horizontalPagePadding,
          min.enabled ? 6 : 12,
          min.horizontalPagePadding,
          0,
        ),
        sliver: SliverToBoxAdapter(
          child: ChristmasSnowCap(
            enabled: _currentPrefs.christmasModeEnabled,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: min.enabled ? 10 : 18),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: min.enabled ? min.largeRadius : OledTheme.largeRadius,
                border: Border.all(
                  color: theme.dividerColor,
                  width: min.borderWidth,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: min.enabled ? 11 : 18,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: min.enabled ? 30 : 40,
                          height: min.enabled ? 30 : 40,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(
                              min.enabled ? 9 : 14,
                            ),
                          ),
                          child: Icon(
                            Icons.mail_outline_rounded,
                            color: scheme.primary,
                            size: min.enabled ? 16 : 22,
                          ),
                        ),
                        SizedBox(width: min.enabled ? 8 : 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uwu(
                                  'Kréta Üzenetek',
                                  enabled: _currentPrefs.uwuModeEnabled,
                                ),
                                style: (min.enabled
                                        ? theme.textTheme.labelLarge
                                        : theme.textTheme.titleMedium)
                                    ?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (!min.enabled)
                                Text(
                                  uwuLabel(
                                    'Beérkezett és elküldött üzenetek',
                                    enabled: _currentPrefs.uwuModeEnabled,
                                  ),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.62),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () => _openMessageComposerDialog(),
                          style: min.enabled
                              ? FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                )
                              : null,
                          icon: Icon(
                            Icons.edit_rounded,
                            size: min.enabled ? 14 : 16,
                          ),
                          label: Text(
                            uwuLabel(
                              'Új üzenet',
                              enabled: _currentPrefs.uwuModeEnabled,
                            ),
                            style: min.enabled
                                ? const TextStyle(fontSize: 12)
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: min.enabled ? 7 : 12),
                  LiquidBubbleTabBar(
                    padding: EdgeInsets.symmetric(
                      horizontal: min.enabled ? 11 : 18,
                    ),
                    height: min.enabled ? 32 : 40,
                    fontSize: min.enabled ? 11.5 : 12.5,
                    itemPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    equalFlex: true,
                    liquidGlassEnabled: liquidGlass,
                    pageController: _messagesPageController,
                    ignorePageController: _isAnimatingMessagesPage,
                    selectedIndex: _showSentMessages ? 1 : 0,
                    onSelected: (idx) => _selectMessagesFolder(idx == 1),
                    items: [
                      LiquidBubbleTabItem(
                        label: uwuLabel(
                          'Beérkezett',
                          enabled: _currentPrefs.uwuModeEnabled,
                        ),
                        icon: Icons.inbox_rounded,
                      ),
                      LiquidBubbleTabItem(
                        label: uwuLabel(
                          'Elküldött',
                          enabled: _currentPrefs.uwuModeEnabled,
                        ),
                        icon: Icons.send_rounded,
                      ),
                    ],
                  ),
                  if (!_showSentMessages && unreadMessages.isNotEmpty) ...[
                    SizedBox(height: min.enabled ? 6 : 10),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: min.enabled ? 11 : 18,
                      ),
                      child: SizedBox(
                        height: min.enabled ? 32 : 38,
                        child: OutlinedButton.icon(
                          key: const ValueKey<String>(
                            'messages-mark-all-read-btn',
                          ),
                          onPressed:
                              _markingAllRead ? null : _markAllMessagesAsRead,
                          icon: Icon(
                            Icons.done_all_rounded,
                            size: min.enabled ? 15 : 17,
                          ),
                          label: Text(
                            uwuLabel(
                              'Összes megjelölése olvasottként (${unreadMessages.length})',
                              enabled: _currentPrefs.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: min.enabled ? 11.5 : 12.5,
                              fontWeight: FontWeight.w800,
                            ),
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
      SliverToBoxAdapter(child: SizedBox(height: min.enabled ? 6 : 10)),
    ];
  }

  Widget _buildMessagesPageViewBody(
    ThemeData theme,
    ColorScheme scheme, {
    required bool showSent,
    required bool isActivePage,
  }) {
    final min = MinimalistTokens.of(_currentPrefs);
    final visibleMessages =
        _messages.where((m) => showSent ? m.isSent : !m.isSent).toList();
    final unreadMessages = !showSent
        ? visibleMessages.where((m) => !_isMessageRead(m)).toList()
        : const <KretaMessage>[];
    final readMessages = !showSent
        ? visibleMessages.where((m) => _isMessageRead(m)).toList()
        : visibleMessages;

    Widget buildSectionHeader({
      required Key? key,
      required String title,
      required int count,
      required Color accent,
    }) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(
          min.horizontalPagePadding,
          min.enabled ? 2 : 4,
          min.horizontalPagePadding,
          min.enabled ? 4 : 6,
        ),
        sliver: SliverToBoxAdapter(
          child: Row(
            key: key,
            children: [
              Container(
                width: min.enabled ? 6 : 8,
                height: min.enabled ? 6 : 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                uwuLabel(title, enabled: _currentPrefs.uwuModeEnabled),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontSize: min.enabled ? 11.5 : 13,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: min.enabled ? 6 : 8,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: min.enabled ? 10 : 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      key: isActivePage
          ? const ValueKey<String>('messages-active-scroll')
          : PageStorageKey<String>('messages-scroll-${showSent ? 'sent' : 'inbox'}'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        if (visibleMessages.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              min.horizontalPagePadding,
              0,
              min.horizontalPagePadding,
              112,
            ),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: EdgeInsets.all(min.enabled ? 10 : 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: min.enabled
                      ? min.cardRadius
                      : BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.dividerColor,
                    width: min.borderWidth,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.mark_email_read_rounded,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                      size: min.enabled ? 17 : 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        uwu(
                          showSent
                              ? 'Még nincs elküldött üzenet. Koppints az „Új üzenet” gombra!'
                              : 'Nincs megjeleníthető beérkezett üzenet.',
                          enabled: _currentPrefs.uwuModeEnabled,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (!showSent) ...[
          if (unreadMessages.isNotEmpty) ...[
            buildSectionHeader(
              key: isActivePage
                  ? const ValueKey<String>('messages-unread-section-header')
                  : null,
              title: 'Olvasatlan',
              count: unreadMessages.length,
              accent: scheme.primary,
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                min.horizontalPagePadding,
                0,
                min.horizontalPagePadding,
                readMessages.isNotEmpty ? (min.enabled ? 6 : 12) : 112,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final msg = unreadMessages[idx];
                    return RepaintBoundary(
                      key: ValueKey<String>(
                        'msg-unread-${msg.isSystemMessage ? 'sys_' : ''}${msg.uid}',
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: min.cardGap),
                        child: _buildMessageTile(theme, scheme, msg),
                      ),
                    );
                  },
                  childCount: unreadMessages.length,
                ),
              ),
            ),
          ],
          if (readMessages.isNotEmpty) ...[
            if (unreadMessages.isNotEmpty)
              buildSectionHeader(
                key: isActivePage
                    ? const ValueKey<String>('messages-read-section-header')
                    : null,
                title: 'Olvasott',
                count: readMessages.length,
                accent: scheme.onSurface.withValues(alpha: 0.65),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                min.horizontalPagePadding,
                0,
                min.horizontalPagePadding,
                112,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, idx) {
                    final msg = readMessages[idx];
                    return RepaintBoundary(
                      key: ValueKey<String>(
                        'msg-read-${msg.isSystemMessage ? 'sys_' : ''}${msg.uid}',
                      ),
                      child: Padding(
                        padding: EdgeInsets.only(bottom: min.cardGap),
                        child: _buildMessageTile(theme, scheme, msg),
                      ),
                    );
                  },
                  childCount: readMessages.length,
                ),
              ),
            ),
          ],
        ] else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              min.horizontalPagePadding,
              0,
              min.horizontalPagePadding,
              112,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, idx) {
                  final msg = visibleMessages[idx];
                  return RepaintBoundary(
                    key: ValueKey<String>('msg-sent-${msg.uid}'),
                    child: Padding(
                      padding: EdgeInsets.only(bottom: min.cardGap),
                      child: _buildMessageTile(theme, scheme, msg),
                    ),
                  );
                },
                childCount: visibleMessages.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageTile(
    ThemeData theme,
    ColorScheme scheme,
    KretaMessage msg,
  ) {
    final min = MinimalistTokens.of(_currentPrefs);
    final isRead = _isMessageRead(msg);
    final senderDisplay = _currentPrefs.resolveTeacherName(msg.sender);

    return TactileBounce(
      onTap: () => _openMessageDetailModal(msg),
      child: Container(
        padding: min.enabled
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
            : const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: min.enabled ? min.cardRadius : BorderRadius.circular(18),
          border: Border.all(
            color: !isRead
                ? scheme.primary.withValues(alpha: 0.7)
                : theme.dividerColor,
            width: !isRead ? (min.enabled ? 1.15 : 1.4) : min.borderWidth,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: min.enabled ? 7 : 10,
              height: min.enabled ? 7 : 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !isRead
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.25),
              ),
            ),
            SizedBox(width: min.enabled ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          uwuLabel(
                            msg.isSent && msg.recipients.isNotEmpty
                                ? 'Címzett: ${msg.recipients.first}'
                                : senderDisplay,
                            enabled: _currentPrefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontSize: min.enabled ? 11 : null,
                            fontWeight:
                                !isRead ? FontWeight.w900 : FontWeight.w700,
                            color: scheme.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (msg.isSystemMessage) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            uwuLabel(
                              'Rendszer',
                              enabled: _currentPrefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                      if (msg.hasAttachments || msg.attachments.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.attach_file_rounded,
                          size: min.enabled ? 11.5 : 13,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(
                        _dateFormat.format(msg.sentAt.toLocal()),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: min.enabled ? 10 : null,
                          color: scheme.onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: min.enabled ? 1 : 3),
                  Text(
                    uwu(msg.subject, enabled: _currentPrefs.uwuModeEnabled),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: min.enabled ? 12.5 : null,
                      fontWeight: !isRead ? FontWeight.w900 : FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!min.enabled && msg.cleanBody.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      uwu(msg.cleanBody, enabled: _currentPrefs.uwuModeEnabled),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: min.enabled ? 4 : 8),
            Icon(
              Icons.chevron_right_rounded,
              size: min.enabled ? 16 : 18,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeOptionChip({
    required ColorScheme scheme,
    required Color dividerColor,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.22)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? scheme.primary : dividerColor,
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: selected
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.72),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.78),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThresholdSlider({
    required ThemeData theme,
    required ColorScheme scheme,
    required String gradeLabel,
    required Color color,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
  }) {
    double snap005(double v) => ((v * 20).round() / 20.0).clamp(min, max);
    final clamped = snap005(value);
    final divisions = ((max - min) * 20).round();

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  gradeLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  clamped.toStringAsFixed(2),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : null,
            activeColor: color,
            onChanged: (v) => onChanged(snap005(v)),
            onChangeEnd:
                onChangeEnd == null ? null : (v) => onChangeEnd(snap005(v)),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ColorScheme scheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 145,
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated full-screen list view for all past absences, tardiness, and
/// certifications ("Összes hiányzás megtekintése" - Part B #5).
class AllOmissionsScreen extends StatefulWidget {
  final List<Omission> omissions;
  final UserProfilePrefs prefs;
  final StoredSession? session;
  final KretaClient? kretaClient;
  final List<Lesson>? referenceLessons;

  const AllOmissionsScreen({
    super.key,
    required this.omissions,
    required this.prefs,
    this.session,
    this.kretaClient,
    this.referenceLessons,
  });

  @override
  State<AllOmissionsScreen> createState() => _AllOmissionsScreenState();
}

class _AllOmissionsScreenState extends State<AllOmissionsScreen> {
  _AttendanceFilter _filter = _AttendanceFilter.all;
  late final PageController _omissionPageController =
      PageController(initialPage: _filter.index);
  bool _isAnimatingFilterPage = false;
  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');

  @override
  void dispose() {
    _omissionPageController.dispose();
    super.dispose();
  }

  void _selectFilter(_AttendanceFilter filter, {bool animatePage = true}) {
    if (_filter != filter) {
      setState(() => _filter = filter);
    }
    if (animatePage && _omissionPageController.hasClients) {
      final target = _AttendanceFilter.values.indexOf(filter).clamp(
            0,
            _AttendanceFilter.values.length - 1,
          );
      final curPage = _omissionPageController.page?.round() ?? target;
      if (curPage != target) {
        _isAnimatingFilterPage = true;
        _omissionPageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
          if (mounted && _isAnimatingFilterPage) {
            setState(() => _isAnimatingFilterPage = false);
          } else {
            _isAnimatingFilterPage = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    Widget buildScaffold(UserProfilePrefs activePrefs) {
      final summary = OmissionsSummary.fromList(widget.omissions);

      return AdaptiveBackgroundScaffold(
        prefs: activePrefs,
        appBar: buildAdaptiveTransparentAppBar(
          context,
          title: uwu('Összes hiányzás és késés'),
        ),
        body: Builder(
          builder: (bodyContext) {
            final theme = Theme.of(bodyContext);
            final scheme = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            final effectivePrefs = activePrefs;
          final liquidGlass = resolveLiquidGlassEnabled(effectivePrefs);
          final blurSigma = resolveSoftBlurBackdropSigma(effectivePrefs);
          final topPad = adaptiveAppBarTopPadding(bodyContext, extra: 4);
          final borderColor = scheme.outlineVariant.withValues(
            alpha: isDark ? 0.28 : 0.42,
          );

          final Widget headerBackdrop;
          if (liquidGlass) {
            final tintColor = (isDark
                    ? scheme.surfaceContainerHigh
                    : theme.scaffoldBackgroundColor)
                .withValues(alpha: isDark ? 0.62 : 0.72);
            headerBackdrop = Positioned.fill(
              child: RepaintBoundary(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: blurSigma,
                      sigmaY: blurSigma,
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tintColor,
                        border: Border(
                          bottom: BorderSide(color: borderColor, width: 0.7),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          } else {
            headerBackdrop = Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: 0.7),
                  ),
                ),
              ),
            );
          }

          return Column(
            children: [
              // Fixed header spans under the transparent AppBar down past the
              // filter bar; ClipRect below isolates scrolled items from bleeding.
              Stack(
                clipBehavior: Clip.none,
                children: [
                  headerBackdrop,
                  Padding(
                    padding: EdgeInsets.only(top: topPad, bottom: 12),
                    child: _buildOmissionFilterChips(
                      selected: _filter,
                      onSelected: _selectFilter,
                      pageController: _omissionPageController,
                      ignorePageController: _isAnimatingFilterPage,
                      liquidGlassEnabled: liquidGlass,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: MediaQuery.removePadding(
                  context: bodyContext,
                  removeTop: true,
                  child: ClipRect(
                    child: VerticalScrollEdgeFades(
                      prefs: effectivePrefs,
                      topHeaderHeight: 0.0,
                      topFeatherHeight: 22.0,
                      bottomFadeHeight: 0.0,
                      scrollDrivenTopFeather: true,
                      child: HorizontalSubTabSwipeDetector(
                        key: const ValueKey<String>('all-omissions-subtab-swipe'),
                        currentIndex: _AttendanceFilter.values
                            .indexOf(_filter)
                            .clamp(0, _AttendanceFilter.values.length - 1),
                        itemCount: _AttendanceFilter.values.length,
                        pageController: _omissionPageController,
                        onIndexChanged: (idx) => _selectFilter(
                          _AttendanceFilter.values[idx],
                          animatePage: false,
                        ),
                        pageBuilder: (pageCtx, pageIdx) {
                          final pageFilter = _AttendanceFilter.values[pageIdx];
                          final pageFiltered =
                              _filterOmissions(summary, pageFilter);
                          final dailyGroups =
                              groupOmissionsByDay(pageFiltered);
                          final isActivePage = pageFilter == _filter;
                          return HeroMode(
                            enabled: isActivePage,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: dailyGroups.isEmpty
                                  ? ListView(
                                      key: ValueKey<String>(
                                        'all-omissions-empty-${pageFilter.name}',
                                      ),
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        36,
                                      ),
                                      children: [
                                        _buildEmptyOmissionCard(
                                          prefs: effectivePrefs,
                                          message:
                                              'Nincs rögzített mulasztás vagy késés ebben a szűrőben.',
                                        ),
                                      ],
                                    )
                                  : ListView.builder(
                                      key: ValueKey<String>(
                                        'all-omissions-list-${pageFilter.name}',
                                      ),
                                      physics: const BouncingScrollPhysics(
                                        parent: AlwaysScrollableScrollPhysics(),
                                      ),
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        36,
                                      ),
                                      itemCount: dailyGroups.length,
                                      itemBuilder: (context, i) =>
                                          RepaintBoundary(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 10),
                                          child: _CompactDayOmissionCard(
                                            group: dailyGroups[i],
                                            prefs: effectivePrefs,
                                            dateFormat: _dateFormat,
                                            session: widget.session,
                                            kretaClient: widget.kretaClient,
                                            referenceLessons:
                                                widget.referenceLessons,
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          );
                        },
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

    if (scope == null) {
      return buildScaffold(widget.prefs);
    }
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (context, _) => buildScaffold(scope.settings.prefs),
    );
  }
}

/// Settings category row. Tapping it pushes a dedicated, full-screen
/// sub-screen (no cramped inline accordions). The sub-screen stays reactive:
/// whenever [stateListenable] fires, [childrenBuilder] and [prefsGetter] are
/// re-evaluated immediately inside the open route.
class _SettingsAccordionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> Function(BuildContext subCtx)? childrenBuilder;
  final ValueListenable<int>? stateListenable;
  final UserProfilePrefs Function()? prefsGetter;
  final bool christmasCap;
  final UserProfilePrefs? prefs;

  const _SettingsAccordionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.childrenBuilder,
    this.stateListenable,
    this.prefsGetter,
    this.christmasCap = false,
    this.prefs,
  });

  @override
  State<_SettingsAccordionCard> createState() => _SettingsAccordionCardState();
}

class _SettingsAccordionCardState extends State<_SettingsAccordionCard> {
  Future<void> _openSubScreen() async {
    HapticFeedback.selectionClick();
    await Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: _SettingsSubScreen(
          title: widget.title,
          prefs: widget.prefs,
          prefsGetter: widget.prefsGetter,
          stateListenable: widget.stateListenable,
          childrenBuilder: widget.childrenBuilder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scope = AppProvidersScope.maybeOf(context);
    final listenables = <Listenable>[
      if (widget.stateListenable != null) widget.stateListenable!,
      if (scope != null) scope.settings,
    ];

    Widget buildCard(UserProfilePrefs activePrefs) {
      final min = MinimalistTokens.of(activePrefs);
      return ChristmasSnowCap(
        enabled: activePrefs.christmasModeEnabled,
        child: SoftGlassCard(
          prefs: activePrefs,
          padding: EdgeInsets.zero,
          borderRadius: min.enabled ? min.cardRadius : OledTheme.largeRadius,
          child: TactileBounce(
            pressedScale: 0.98,
            onTap: _openSubScreen,
            child: Padding(
              padding: min.enabled
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
                  : const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: min.enabled ? 30 : 40,
                    height: min.enabled ? 30 : 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(min.enabled ? 9 : 13),
                      border: Border.all(
                        color: theme.brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.08)
                            : scheme.onSurface.withValues(alpha: 0.10),
                        width: min.borderWidth,
                      ),
                    ),
                    child: Icon(
                      widget.icon,
                      size: min.enabled ? 16 : 20,
                      color: scheme.primary,
                    ),
                  ),
                  SizedBox(width: min.enabled ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwuLabel(
                            widget.title,
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                          style: (min.enabled
                                  ? theme.textTheme.labelLarge
                                  : theme.textTheme.titleSmall)
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          uwuLabel(
                            widget.subtitle,
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: min.enabled ? 10.5 : null,
                            color: scheme.onSurface.withValues(alpha: 0.62),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: min.enabled ? 18 : 24,
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (listenables.isEmpty) {
      final activePrefs =
          widget.prefsGetter?.call() ?? widget.prefs ?? const UserProfilePrefs();
      return buildCard(activePrefs);
    }
    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final activePrefs = scope?.settings.prefs ??
            widget.prefsGetter?.call() ??
            widget.prefs ??
            const UserProfilePrefs();
        return buildCard(activePrefs);
      },
    );
  }
}

/// Marks a settings child as full-bleed inside [_SettingsSubScreen] so
/// horizontal scroll bars reach the card edges without outer padding clipping.
class _FullBleedChild extends StatelessWidget {
  final Widget child;

  const _FullBleedChild({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Marks a child returned to [_SettingsSubScreen] as owning its own card(s)
/// and spacing instead of being wrapped inside one shared outer [SoftGlassCard].
class _StandaloneSettingsChild extends StatelessWidget {
  final Widget child;

  const _StandaloneSettingsChild({required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// Dedicated settings sub-screen pushed by [_SettingsAccordionCard].
class _SettingsSubScreen extends StatefulWidget {
  final String title;
  final UserProfilePrefs? prefs;
  final UserProfilePrefs Function()? prefsGetter;
  final ValueListenable<int>? stateListenable;
  final List<Widget> Function(BuildContext subCtx)? childrenBuilder;

  const _SettingsSubScreen({
    required this.title,
    required this.prefs,
    this.prefsGetter,
    this.stateListenable,
    this.childrenBuilder,
  });

  @override
  State<_SettingsSubScreen> createState() => _SettingsSubScreenState();
}

class _SettingsSubScreenState extends State<_SettingsSubScreen> {
  static final ValueNotifier<int> _fallbackListenable = ValueNotifier<int>(0);
  AppProvidersScope? _scope;
  late Listenable _mergedListenable;

  void _rebuildListenable() {
    final sources = <Listenable>[
      widget.stateListenable ?? _fallbackListenable,
      if (_scope != null) _scope!.settings,
      if (_scope != null) _scope!.theme,
    ];
    _mergedListenable =
        sources.length == 1 ? sources.first : Listenable.merge(sources);
  }

  @override
  void initState() {
    super.initState();
    _rebuildListenable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextScope = AppProvidersScope.maybeOf(context);
    if (_scope?.settings != nextScope?.settings ||
        _scope?.theme != nextScope?.theme) {
      _scope = nextScope;
      _rebuildListenable();
    }
  }

  @override
  void didUpdateWidget(covariant _SettingsSubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.stateListenable != oldWidget.stateListenable) {
      _rebuildListenable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _mergedListenable,
      builder: (context, _) {
        // Actively subscribe to MaterialApp's inherited Theme so color-swatch
        // and base-theme changes repaint immediately inside this open route.
        Theme.of(context);
        final currentPrefs =
            _scope?.settings.prefs ?? widget.prefsGetter?.call() ?? widget.prefs;
        return AdaptiveBackgroundScaffold(
          prefs: currentPrefs,
          appBar: buildAdaptiveTransparentAppBar(
            context,
            title: uwu(
              widget.title,
              enabled: currentPrefs?.uwuModeEnabled,
            ),
          ),
          body: Builder(
            builder: (subContext) {
              Theme.of(subContext);
              final currentChildren = widget.childrenBuilder != null
                  ? widget.childrenBuilder!(subContext)
                  : const <Widget>[];
              final hasStandaloneLayout =
                  currentChildren.any((c) => c is _StandaloneSettingsChild);
              return ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  adaptiveAppBarTopPadding(subContext),
                  16,
                  40,
                ),
                children: hasStandaloneLayout
                    ? currentChildren
                    : [
                        SoftGlassCard(
                          prefs: currentPrefs ?? const UserProfilePrefs(),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          borderRadius: OledTheme.largeRadius,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final child in currentChildren)
                                if (child is _FullBleedChild ||
                                    child is EdgeFadeHorizontalScroll)
                                  child
                                else
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: child,
                                  ),
                            ],
                          ),
                        ),
                      ],
              );
            },
          ),
        );
      },
    );
  }
}

/// Bidirectional per-weekday commute preferences (Hétfő-Péntek):
/// - Direction selector: "Odafele (Reggeli bejárás)" vs "Hazafele (Délutáni hazaút)"
/// - Scheduled departure picker fetched from the real timetable
/// - Per-direction/day toggle between "Helyi járat használata" vs "Gyaloglás"
class _DayCommuteEditor extends StatefulWidget {
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onChanged;

  const _DayCommuteEditor({required this.prefs, required this.onChanged});

  @override
  State<_DayCommuteEditor> createState() => _DayCommuteEditorState();
}

class _DayCommuteEditorState extends State<_DayCommuteEditor> {
  static const _shortDays = ['H', 'K', 'Sze', 'Cs', 'P'];
  static const _fullDays = ['Hétfő', 'Kedd', 'Szerda', 'Csütörtök', 'Péntek'];
  final MenetrendService _service = MenetrendService();
  int _selected = (DateTime.now().weekday - 1).clamp(0, 4);
  bool _isMorning = true;
  late final TextEditingController _lineController;
  List<({String value, String label})> _scheduledOptions = const [];
  bool _loadingOptions = false;

  Map<String, dynamic> get _plan =>
      widget.prefs.commutePlanForWeekday(_selected + 1);

  int _optionsFetchEpoch = 0;

  String get _currentLine {
    final key = _isMorning ? 'morningLine' : 'afternoonLine';
    final specific = _plan[key]?.toString().trim() ?? '';
    if (specific.isNotEmpty) return specific;
    return _isMorning ? (_plan['line']?.toString().trim() ?? '') : '';
  }

  bool get _currentUseLocalBus {
    final key = _isMorning ? 'morningUseLocalBus' : 'afternoonUseLocalBus';
    if (_plan.containsKey(key)) {
      return _plan[key] != false;
    }
    return _plan['useLocalBus'] != false;
  }

  @override
  void initState() {
    super.initState();
    _lineController = TextEditingController(text: _currentLine);
    _fetchOptions(fromLifecycle: true);
  }

  @override
  void didUpdateWidget(covariant _DayCommuteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.primaryHomeStop != widget.prefs.primaryHomeStop ||
        oldWidget.prefs.primarySchoolStop != widget.prefs.primarySchoolStop ||
        oldWidget.prefs.homeAddress != widget.prefs.homeAddress ||
        oldWidget.prefs.schoolAddress != widget.prefs.schoolAddress) {
      _fetchOptions(fromLifecycle: true);
    }
  }

  @override
  void dispose() {
    _lineController.dispose();
    super.dispose();
  }

  Future<void> _fetchOptions({bool fromLifecycle = false}) async {
    final epoch = ++_optionsFetchEpoch;
    if (!widget.prefs.transitConfigured) {
      if (fromLifecycle) {
        _scheduledOptions = const [];
        _loadingOptions = false;
      } else if (mounted) {
        setState(() {
          _scheduledOptions = const [];
          _loadingOptions = false;
        });
      }
      return;
    }
    if (fromLifecycle) {
      _loadingOptions = true;
    } else if (mounted) {
      setState(() => _loadingOptions = true);
    }
    try {
      final opts = await _service.fetchScheduledDepartureOptions(
        prefs: widget.prefs,
        isMorning: _isMorning,
        weekday: _selected + 1,
        useLocalBus: _currentUseLocalBus,
      );
      if (!mounted || epoch != _optionsFetchEpoch) return;
      setState(() {
        _scheduledOptions = opts;
        _loadingOptions = false;
      });
    } catch (_) {
      if (!mounted || epoch != _optionsFetchEpoch) return;
      setState(() {
        _scheduledOptions = const [];
        _loadingOptions = false;
      });
    }
  }

  void _syncTextController() {
    final text = _currentLine;
    if (_lineController.text != text) {
      _lineController.text = text;
    }
  }

  void _save({String? line, bool? useLocalBus}) {
    final plan = Map<String, dynamic>.from(_plan);
    if (line != null) {
      if (_isMorning) {
        plan['morningLine'] = line;
        plan['line'] = line;
      } else {
        plan['afternoonLine'] = line;
      }
    }
    if (useLocalBus != null) {
      if (_isMorning) {
        plan['morningUseLocalBus'] = useLocalBus;
        plan['useLocalBus'] = useLocalBus;
      } else {
        plan['afternoonUseLocalBus'] = useLocalBus;
      }
    }
    widget.onChanged(widget.prefs.withCommutePlan(_selected + 1, plan));
  }

  Widget _buildBinarySegmentedToggle({
    required ThemeData theme,
    required ColorScheme scheme,
    required bool isFirstSelected,
    required String firstLabel,
    required IconData firstIcon,
    required String secondLabel,
    required IconData secondIcon,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final liquidGlass = resolveLiquidGlassEnabled(widget.prefs);

    Widget buildLabel(
      String label,
      IconData icon,
      bool selected,
      VoidCallback onTap,
    ) {
      final color = selected
          ? (isDark ? scheme.primary : scheme.onSurface)
          : scheme.onSurface.withValues(alpha: 0.62);
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 15, color: color),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment(isFirstSelected ? -1.0 : 1.0, 0.0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1.0,
              child: liquidGlass
                  ? LiquidGlassPillSurface(
                      pressProgress: 0.0,
                      borderRadius: BorderRadius.circular(10),
                      accentColor: scheme.primary,
                      mode: widget.prefs.liquidGlassMode,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? scheme.primary.withValues(alpha: 0.24)
                            : scheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: isDark
                            ? Border.all(
                                color: scheme.primary.withValues(alpha: 0.42),
                              )
                            : null,
                        boxShadow: isDark
                            ? null
                            : [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                      ),
                    ),
            ),
          ),
          Row(
            children: [
              buildLabel(firstLabel, firstIcon, isFirstSelected, () => onChanged(true)),
              buildLabel(secondLabel, secondIcon, !isFirstSelected, () => onChanged(false)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final useLocalBus = _currentUseLocalBus;
    final selectedLine = _currentLine;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact 5-column weekday pills (H, K, Sze, Cs, P)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var i = 0; i < _shortDays.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _selected = i);
                      _syncTextController();
                      _fetchOptions();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _selected == i
                            ? scheme.primary.withValues(alpha: isDark ? 0.24 : 0.14)
                            : scheme.onSurface.withValues(alpha: isDark ? 0.06 : 0.045),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: _selected == i
                              ? scheme.primary.withValues(alpha: 0.65)
                              : scheme.onSurface.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        uwuLabel(
                          _shortDays[i],
                          enabled: widget.prefs.uwuModeEnabled,
                        ),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _selected == i ? FontWeight.w800 : FontWeight.w600,
                          color: _selected == i
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Clean 2-option sliding direction toggle: Odafele / Hazafele
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildBinarySegmentedToggle(
            theme: theme,
            scheme: scheme,
            isFirstSelected: _isMorning,
            firstLabel: uwuLabel(
              'Odafele',
              enabled: widget.prefs.uwuModeEnabled,
            ),
            firstIcon: Icons.wb_sunny_rounded,
            secondLabel: uwuLabel(
              'Hazafele',
              enabled: widget.prefs.uwuModeEnabled,
            ),
            secondIcon: Icons.home_rounded,
            onChanged: (toMorning) {
              if (_isMorning == toMorning) return;
              setState(() => _isMorning = toMorning);
              _syncTextController();
              _fetchOptions();
            },
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: Column(
              key: ValueKey<String>('day-commute-$_selected-$_isMorning'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildBinarySegmentedToggle(
                    theme: theme,
                    scheme: scheme,
                    isFirstSelected: !useLocalBus,
                    firstLabel: uwuLabel(
                      'Gyaloglás',
                      enabled: widget.prefs.uwuModeEnabled,
                    ),
                    firstIcon: Icons.directions_walk_rounded,
                    secondLabel: uwuLabel(
                      'Helyi járat',
                      enabled: widget.prefs.uwuModeEnabled,
                    ),
                    secondIcon: Icons.directions_bus_rounded,
                    onChanged: (walk) {
                      _save(useLocalBus: !walk);
                      setState(() {});
                      _fetchOptions();
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          uwuLabel(
                            'Preferált indulás (${_fullDays[_selected]} • ${_isMorning ? "Odafele" : "Hazafele"})',
                            enabled: widget.prefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.78),
                          ),
                        ),
                      ),
                      if (_loadingOptions)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: uwuLabel(
                            'Járatok frissítése',
                            enabled: widget.prefs.uwuModeEnabled,
                          ),
                          onPressed: _fetchOptions,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                        ),
                    ],
                  ),
                ),
                if (_scheduledOptions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  EdgeFadeHorizontalScroll(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(
                          uwuLabel(
                            'Automatikus (legjobb)',
                            enabled: widget.prefs.uwuModeEnabled,
                          ),
                        ),
                        selected: selectedLine.isEmpty,
                        onSelected: (_) {
                          _lineController.clear();
                          _save(line: '');
                          setState(() {});
                        },
                      ),
                      for (final opt in _scheduledOptions)
                        ChoiceChip(
                          showCheckmark: false,
                          label: Text(
                            uwuLabel(
                              opt.label,
                              enabled: widget.prefs.uwuModeEnabled,
                            ),
                          ),
                          selected: selectedLine == opt.value ||
                              (selectedLine.isNotEmpty &&
                                  opt.value.contains(selectedLine)),
                          onSelected: (_) {
                            _lineController.text = opt.value;
                            _save(line: opt.value);
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                ] else if (!_loadingOptions) ...[
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      uwuLabel(
                        widget.prefs.transitConfigured
                            ? 'Nincs lekérdezhető menetrendi indulás, vagy add meg kézzel alább.'
                            : 'Állítsd be fent az otthoni és iskolai címet a járatok betöltéséhez.',
                        enabled: widget.prefs.uwuModeEnabled,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _lineController,
                    decoration: InputDecoration(
                      labelText: uwuLabel(
                        '${_fullDays[_selected]} (${_isMorning ? "Odafele" : "Hazafele"}): kiválasztott járat',
                        enabled: widget.prefs.uwuModeEnabled,
                      ),
                      hintText: uwuLabel(
                        'pl. 07:09 S150',
                        enabled: widget.prefs.uwuModeEnabled,
                      ),
                      prefixIcon: const Icon(Icons.schedule_rounded, size: 18),
                      suffixIcon: _lineController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _lineController.clear();
                                _save(line: '');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) {
                      _save(line: v.trim());
                      setState(() {});
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Text field with live stop/station or street address search.
class _TransitStopSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool isAddressSearch;
  final ValueChanged<String> onSelected;
  final ValueChanged<TransitStopResult>? onSelectedResult;
  final VoidCallback onCleared;

  const _TransitStopSearchField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.isAddressSearch = false,
    required this.onSelected,
    this.onSelectedResult,
    required this.onCleared,
  });

  @override
  State<_TransitStopSearchField> createState() =>
      _TransitStopSearchFieldState();
}

class _TransitStopSearchFieldState extends State<_TransitStopSearchField> {
  final MenetrendService _service = MenetrendService();
  Timer? _debounce;
  List<TransitStopResult> _results = const [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
      });
      widget.onCleared();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 420), () async {
      setState(() {
        _searching = true;
        _error = null;
      });
      try {
        final res = widget.isAddressSearch
            ? await _service.searchAddresses(q)
            : await _service.searchStops(q);
        if (!mounted) return;
        setState(() {
          _results = res.take(6).toList();
          _searching = false;
          if (res.isEmpty) _error = 'Nincs találat.';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _results = const [];
          _searching = false;
          _error = 'A keresés nem érhető el.';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: Icon(widget.icon),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : (widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {
                            _results = const [];
                            _error = null;
                          });
                          widget.onCleared();
                        },
                      )
                    : null),
          ),
        ),
        for (final r in _results)
          ListTile(
            dense: true,
            leading: Icon(
              widget.isAddressSearch
                  ? Icons.location_on_rounded
                  : Icons.directions_transit_rounded,
              size: 18,
            ),
            title: Text(
              r.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              widget.controller.text = r.name;
              setState(() => _results = const []);
              widget.onSelected(r.name);
              widget.onSelectedResult?.call(r);
              FocusScope.of(context).unfocus();
            },
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(_error!, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _CalendarSyncSettingsSection extends StatefulWidget {
  final StoredSession session;
  final KretaClient? kretaClient;
  final DashboardData? dashboardData;
  final UserProfilePrefs profilePrefs;
  final ValueChanged<CalendarSyncSettings> onSettingsChanged;

  const _CalendarSyncSettingsSection({
    required this.session,
    required this.kretaClient,
    required this.dashboardData,
    required this.profilePrefs,
    required this.onSettingsChanged,
  });

  @override
  State<_CalendarSyncSettingsSection> createState() =>
      _CalendarSyncSettingsSectionState();
}

class _CalendarSyncSettingsSectionState
    extends State<_CalendarSyncSettingsSection> {
  final CalendarSyncService _service = CalendarSyncService.instance;
  final DateFormat _timeFormat = DateFormat('yyyy. MM. dd. HH:mm');

  CalendarSyncSettings _settings = const CalendarSyncSettings(
    enabled: false,
    targetCalendarId: null,
    targetCalendarName: null,
    targetCalendarAccount: null,
    contentMode: CalendarSyncContentMode.both,
    trackedEventCount: 0,
    lastSyncAt: null,
  );
  List<DeviceCalendarInfo> _calendars = const [];
  List<CalendarEventColorOption> _calendarColors = const [];
  bool _loading = true;
  bool _busy = false;
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final loaded = await _service.loadSettings();
    final hasPerm = await _service.hasCalendarPermissions();
    var cals = const <DeviceCalendarInfo>[];
    var calColors = const <CalendarEventColorOption>[];
    if (hasPerm) {
      cals = await _service.getAvailableCalendars();
      if (loaded.enabled) {
        final selected = await _service.ensureTargetCalendarSelected(cals);
        if (selected != null) {
          calColors = await _service.getCalendarEventColors(selected.id);
        }
      }
    }
    final refreshed = await _service.loadSettings();
    if (calColors.isEmpty &&
        hasPerm &&
        refreshed.targetCalendarId != null &&
        refreshed.targetCalendarId!.isNotEmpty) {
      calColors =
          await _service.getCalendarEventColors(refreshed.targetCalendarId!);
    }
    if (!mounted) return;
    setState(() {
      _settings = refreshed;
      _hasPermission = hasPerm;
      _calendars = cals;
      _calendarColors = calColors;
      _loading = false;
    });
    widget.onSettingsChanged(refreshed);
  }

  Future<List<Lesson>> _fetchCalendarTimetableRange(
    DateTime from,
    DateTime to,
  ) async {
    final client = widget.kretaClient;
    if (client == null) return const [];
    return client.fetchTimetableForRange(widget.session, from: from, to: to);
  }

  Future<DashboardData?> _resolveDashboard() async {
    if (widget.dashboardData != null) return widget.dashboardData;
    final client = widget.kretaClient;
    if (client == null) return null;
    try {
      return await client.loadCachedDashboard(widget.session);
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    TintaToast.show(
      context,
      message,
      type: isError ? TintaToastType.error : TintaToastType.info,
    );
  }

  Future<void> _reloadSettings() async {
    final refreshed = await _service.loadSettings();
    if (!mounted) return;
    setState(() => _settings = refreshed);
    widget.onSettingsChanged(refreshed);
  }

  Future<void> _toggleEnabled(bool value) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      if (!value) {
        await _service.setEnabled(false);
        await _reloadSettings();
        _showSnack('Naptár szinkronizálás kikapcsolva.');
        return;
      }

      var granted = await _service.hasCalendarPermissions();
      if (!granted) {
        granted = await _service.requestCalendarPermissions();
      }
      if (!granted) {
        await _service.setEnabled(false);
        if (!mounted) return;
        setState(() => _hasPermission = false);
        await _reloadSettings();
        _showSnack(
          'A naptár szinkronizáláshoz engedélyezd a naptár hozzáférést.',
          isError: true,
        );
        return;
      }

      final cals = await _service.getAvailableCalendars();
      await _service.ensureTargetCalendarSelected(cals);
      await _service.setEnabled(true);
      if (mounted) {
        setState(() {
          _hasPermission = true;
          _calendars = cals;
        });
      }

      if (cals.isEmpty) {
        await _reloadSettings();
        _showSnack(
          'Nem található írható naptár ezen az eszközön.',
          isError: true,
        );
        return;
      }

      final dash = await _resolveDashboard();
      if (dash != null) {
        final result = await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
        await _reloadSettings();
        if (result.errorMessage != null) {
          _showSnack(result.errorMessage!, isError: true);
        } else {
          _showSnack(
            'Bekapcsolva • ${result.syncedCount} közelgő esemény szinkronizálva.',
          );
        }
      } else {
        await _reloadSettings();
        _showSnack(
          'Naptár szinkronizálás bekapcsolva. A következő adatfrissítéskor indul a szinkronizálás.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _selectContentMode(CalendarSyncContentMode mode) async {
    if (_busy || _settings.contentMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await _service.setContentMode(mode);
      final dash = await _resolveDashboard();
      if (dash != null && _settings.enabled) {
        final result = await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
        await _reloadSettings();
        if (result.errorMessage == null) {
          _showSnack(
            '${mode.label} • ${result.syncedCount} közelgő esemény aktív (eltávolítva: ${result.deletedCount}).',
          );
        } else {
          _showSnack(result.errorMessage!, isError: true);
        }
      } else {
        await _service.cleanupOutOfScopeEvents();
        await _reloadSettings();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTargetCalendar() async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    var cals = _calendars;
    if (cals.isEmpty && await _service.hasCalendarPermissions()) {
      cals = await _service.getAvailableCalendars();
      if (mounted) setState(() => _calendars = cals);
    }
    if (!mounted) return;
    if (cals.isEmpty) {
      _showSnack(
        'Nincs elérhető írható naptár az eszközön.',
        isError: true,
      );
      return;
    }

    final chosen = await showFloatingGlassSheet<DeviceCalendarInfo>(
      context: context,
      prefs: widget.profilePrefs,
      barrierColor: resolveSoftBlurBarrierColor(
        context,
        prefs: widget.profilePrefs,
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final closeMode = widget.profilePrefs.modalCloseMode;
        final hairline =
            scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 540,
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.78,
            ),
            child: FrostedBottomSheetSurface(
              prefs: widget.profilePrefs,
              showDragHandle: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Icon(
                          Icons.calendar_month_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          uwuLabel(
                            'Cél naptár kiválasztása',
                            enabled: widget.profilePrefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (closeMode.showTopX) ...[
                        const SizedBox(width: 8),
                        PopupTopCloseButton(
                          onTap: () => Navigator.of(sheetCtx).pop(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, thickness: 1, color: hairline),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: cals.map((cal) {
                          final selected = cal.id == _settings.targetCalendarId;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: TactileBounce(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                Navigator.of(sheetCtx).pop(cal);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? scheme.primary.withValues(alpha: 0.13)
                                      : scheme.onSurface.withValues(
                                          alpha: isDark ? 0.045 : 0.03,
                                        ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected
                                        ? scheme.primary.withValues(alpha: 0.55)
                                        : hairline,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 15,
                                      backgroundColor: Color(cal.color),
                                      child: Icon(
                                        cal.isGoogle
                                            ? Icons.event_available_rounded
                                            : Icons.calendar_today_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            uwuLabel(
                                              cal.displayName,
                                              enabled: widget.profilePrefs
                                                  .uwuModeEnabled,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            uwuLabel(
                                              [
                                                if (cal.accountName.isNotEmpty)
                                                  cal.accountName,
                                                if (cal.isGoogle)
                                                  'Google'
                                                else
                                                  'Helyi',
                                                if (cal.isPrimary)
                                                  'Elsődleges',
                                              ].join(' • '),
                                              enabled: widget.profilePrefs
                                                  .uwuModeEnabled,
                                            ),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.62),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: scheme.primary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (closeMode.showBottomButton) ...[
                    const SizedBox(height: 12),
                    PopupBottomCloseButton(
                      onTap: () => Navigator.of(sheetCtx).pop(),
                      uwuEnabled: widget.profilePrefs.uwuModeEnabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );

    if (chosen == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.setTargetCalendar(chosen);
      final calColors = await _service.getCalendarEventColors(chosen.id);
      if (mounted) {
        setState(() => _calendarColors = calColors);
      }
      final dash = await _resolveDashboard();
      if (dash != null && _settings.enabled) {
        final result = await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
        await _reloadSettings();
        if (result.errorMessage == null) {
          _showSnack(
            'Naptár váltva: ${chosen.displayName} (${result.syncedCount} közelgő esemény).',
          );
        } else {
          _showSnack(result.errorMessage!, isError: true);
        }
      } else {
        await _reloadSettings();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleSyncTimetable(bool value) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    try {
      await _service.setSyncTimetable(value);
      final dash = await _resolveDashboard();
      if (dash != null && _settings.enabled) {
        final result = await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
        await _reloadSettings();
        if (result.errorMessage == null) {
          _showSnack(
            value
                ? 'Órarend szinkronizálása bekapcsolva (${result.syncedCount} esemény).'
                : 'Órarend órái eltávolítva a szinkronból.',
          );
        } else {
          _showSnack(result.errorMessage!, isError: true);
        }
      } else {
        await _service.cleanupOutOfScopeEvents();
        await _reloadSettings();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCategoryColor(CalendarEventColorCategory category) async {
    if (_busy) return;
    HapticFeedback.selectionClick();
    final palette = _calendarColors.isNotEmpty
        ? _calendarColors.map((e) => e.color).toList()
        : kDefaultCalendarColorPalette;
    final currentColor = _settings.colorFor(category);

    final picked = await showFloatingGlassSheet<int>(
      context: context,
      prefs: widget.profilePrefs,
      barrierColor: resolveSoftBlurBarrierColor(
        context,
        prefs: widget.profilePrefs,
      ),
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final closeMode = widget.profilePrefs.modalCloseMode;
        final hairline =
            scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);
        final activeAccent = Color(currentColor);
        return Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.72,
            ),
            child: FrostedBottomSheetSurface(
              prefs: widget.profilePrefs,
              showDragHandle: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: activeAccent.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: activeAccent.withValues(alpha: 0.45),
                              width: 1.2,
                            ),
                          ),
                          child: Icon(
                            Icons.palette_rounded,
                            size: 20,
                            color: activeAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                uwuLabel(
                                  '${category.label} esemény színe',
                                  enabled: widget.profilePrefs.uwuModeEnabled,
                                ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              Text(
                                uwuLabel(
                                  'Válassz színt a naptáreseményekhez',
                                  enabled: widget.profilePrefs.uwuModeEnabled,
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (closeMode.showTopX) ...[
                          const SizedBox(width: 8),
                          PopupTopCloseButton(
                            onTap: () => Navigator.of(sheetCtx).pop(),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(height: 1, thickness: 1, color: hairline),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 14,
                      runSpacing: 14,
                      children: palette.map((argb) {
                        final isSelected = argb == currentColor;
                        final swatchColor = Color(argb);
                        return TactileBounce(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(sheetCtx).pop(argb);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: swatchColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? scheme.onSurface
                                    : Colors.white.withValues(alpha: 0.25),
                                width: isSelected ? 2.8 : 1.2,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: swatchColor.withValues(
                                          alpha: 0.45,
                                        ),
                                        blurRadius: 12,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: isSelected
                                ? Center(
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: 20,
                                      color: OledTheme.contrastTextFor(
                                        swatchColor,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(sheetCtx).pop(category.defaultArgb);
                            },
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.restore_rounded, size: 17),
                            label: Text(
                              uwuLabel(
                                'Alapértelmezett',
                                enabled: widget.profilePrefs.uwuModeEnabled,
                              ),
                            ),
                          ),
                        ),
                        if (closeMode.showBottomButton) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: PopupBottomCloseButton(
                              onTap: () => Navigator.of(sheetCtx).pop(),
                              accentColor: activeAccent,
                              uwuEnabled: widget.profilePrefs.uwuModeEnabled,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _service.setCategoryColor(category, picked);
      final dash = await _resolveDashboard();
      if (dash != null && _settings.enabled) {
        await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
      }
      await _reloadSettings();
      _showSnack('${category.label} színe mentve.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetCategoryColors() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await _service.resetEventColors();
      final dash = await _resolveDashboard();
      if (dash != null && _settings.enabled) {
        await _service.syncNow(
          dashboard: dash,
          profilePrefs: widget.profilePrefs,
          fetchLessonsForRange: _fetchCalendarTimetableRange,
        );
      }
      await _reloadSettings();
      _showSnack('Esemény színek visszaállítva.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncNowManual() async {
    if (_busy) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      final dash = await _resolveDashboard();
      if (dash == null) {
        _showSnack(
          'Még nincs betöltött Kréta adat a szinkronizáláshoz.',
          isError: true,
        );
        return;
      }
      if (!_hasPermission) {
        final granted = await _service.requestCalendarPermissions();
        if (!granted) {
          _showSnack(
            'Nincs naptár hozzáférési engedély.',
            isError: true,
          );
          return;
        }
        if (mounted) setState(() => _hasPermission = true);
      }
      final result = await _service.syncNow(
        dashboard: dash,
        profilePrefs: widget.profilePrefs,
        fetchLessonsForRange: _fetchCalendarTimetableRange,
      );
      await _reloadSettings();
      if (result.errorMessage != null) {
        _showSnack(result.errorMessage!, isError: true);
      } else {
        _showSnack(
          '${result.syncedCount} közelgő esemény szinkronizálva '
          '(új: ${result.createdCount}, frissítve: ${result.updatedCount}, '
          'törölve: ${result.deletedCount}).',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAllManual() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      final removed = await _service.clearAllSyncedEvents();
      await _reloadSettings();
      _showSnack(
        removed > 0
            ? '$removed szinkronizált esemény eltávolítva a naptárból.'
            : 'Nincs eltávolítható Tinta Napló naptáresemény.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final calendarTitle = _settings.targetCalendarName?.isNotEmpty == true
        ? _settings.targetCalendarName!
        : (_calendars.isNotEmpty
            ? _calendars.first.displayName
            : 'Nincs kiválasztott naptár');
    final calendarSubtitle =
        _settings.targetCalendarAccount?.isNotEmpty == true
            ? _settings.targetCalendarAccount!
            : (_calendars.isNotEmpty
                ? _calendars.first.accountName
                : 'Koppints a naptárak betöltéséhez');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey<String>('calendar-sync-main-switch'),
          contentPadding: EdgeInsets.zero,
          secondary: Icon(
            Icons.event_available_rounded,
            color: _settings.enabled ? scheme.primary : null,
          ),
          title: Text(
            uwuLabel(
              'Automatikus naptár szinkronizálás',
              enabled: widget.profilePrefs.uwuModeEnabled,
            ),
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            uwuLabel(
              'Kizárólag jövőbeli dolgozatok és házi feladatok szinkronizálása az eszköz naptárába.',
              enabled: widget.profilePrefs.uwuModeEnabled,
            ),
            style: const TextStyle(fontSize: 11.5),
          ),
          value: _settings.enabled,
          onChanged: _busy ? null : _toggleEnabled,
        ),
        if (_settings.enabled) ...[
          const Divider(height: 20),
          Text(
            uwuLabel(
              'Cél naptár',
              enabled: widget.profilePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _busy ? null : _pickTargetCalendar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uwuLabel(
                            calendarTitle,
                            enabled: widget.profilePrefs.uwuModeEnabled,
                          ),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (calendarSubtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            uwuLabel(
                              calendarSubtitle,
                              enabled: widget.profilePrefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.68),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    uwuLabel(
                      _calendars.length > 1 ? 'Váltás' : 'Választás',
                      enabled: widget.profilePrefs.uwuModeEnabled,
                    ),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            uwuLabel(
              'Szinkronizálandó tartalom',
              enabled: widget.profilePrefs.uwuModeEnabled,
            ),
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: CalendarSyncContentMode.values.map((mode) {
              final selected = _settings.contentMode == mode;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _busy ? null : () => _selectContentMode(mode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? scheme.primary.withValues(alpha: 0.16)
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? scheme.primary
                            : scheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 18,
                          color: selected
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            uwuLabel(
                              mode.label,
                              enabled: widget.profilePrefs.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w800 : FontWeight.w600,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('calendar-sync-timetable-switch'),
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              Icons.calendar_view_day_rounded,
              color: _settings.syncTimetable ? scheme.primary : null,
            ),
            title: Text(
              uwuLabel(
                'Órarend szinkronizálása',
                enabled: widget.profilePrefs.uwuModeEnabled,
              ),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              uwuLabel(
                'Közelgő tanórák hozzáadása a kiválasztott naptárhoz.',
                enabled: widget.profilePrefs.uwuModeEnabled,
              ),
              style: const TextStyle(fontSize: 11),
            ),
            value: _settings.syncTimetable,
            onChanged: _busy ? null : _toggleSyncTimetable,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  uwuLabel(
                    'Esemény színek',
                    enabled: widget.profilePrefs.uwuModeEnabled,
                  ),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_settings.eventColors.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _resetCategoryColors,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    uwuLabel(
                      'Alaphelyzet',
                      enabled: widget.profilePrefs.uwuModeEnabled,
                    ),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CalendarEventColorCategory.values.map((cat) {
              final argb = _settings.colorFor(cat);
              return InkWell(
                key: ValueKey<String>('calendar-color-${cat.name}'),
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : () => _pickCategoryColor(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color(argb).withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Color(argb),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        uwuLabel(
                          cat.label,
                          enabled: widget.profilePrefs.uwuModeEnabled,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _syncNowManual,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              uwuLabel(
                'Szinkronizálás most',
                enabled: widget.profilePrefs.uwuModeEnabled,
              ),
            ),
          ),
        ],
        if (_settings.enabled || _settings.trackedEventCount > 0) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _clearAllManual,
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text(
              uwuLabel(
                'Szinkronizált események törlése',
                enabled: widget.profilePrefs.uwuModeEnabled,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          uwuLabel(
            [
              'Követett események: ${_settings.trackedEventCount} db',
              if (_settings.lastSyncAt != null)
                'Utolsó szinkron: ${_timeFormat.format(_settings.lastSyncAt!.toLocal())}',
              'Csak jövőbeli tételek kerülnek át (múltbeli visszatöltés nélkül).',
            ].join(' • '),
            enabled: widget.profilePrefs.uwuModeEnabled,
          ),
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: scheme.onSurface.withValues(alpha: 0.62),
          ),
        ),
      ],
    );
  }
}

class _SettingsSearchEntry {
  final IconData icon;
  final String title;
  final String category;
  final String description;
  final List<String> keywords;
  final VoidCallback onTap;

  const _SettingsSearchEntry({
    required this.icon,
    required this.title,
    required this.category,
    required this.description,
    required this.keywords,
    required this.onTap,
  });
}

String _normalizeHuSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    switch (rune) {
      case 0x00E1: // á
        buffer.write('a');
        break;
      case 0x00E9: // é
        buffer.write('e');
        break;
      case 0x00ED: // í
        buffer.write('i');
        break;
      case 0x00F3: // ó
      case 0x00F6: // ö
      case 0x0151: // ő
        buffer.write('o');
        break;
      case 0x00FA: // ú
      case 0x00FC: // ü
      case 0x0171: // ű
        buffer.write('u');
        break;
      default:
        buffer.writeCharCode(rune);
    }
  }
  return buffer.toString().trim();
}

bool _isSubsequence(String needle, String haystack) {
  if (needle.isEmpty) return true;
  if (needle.length > haystack.length) return false;
  var ni = 0;
  for (var hi = 0; hi < haystack.length && ni < needle.length; hi++) {
    if (haystack.codeUnitAt(hi) == needle.codeUnitAt(ni)) {
      ni++;
    }
  }
  return ni == needle.length;
}

bool _levenshteinWithin1(String a, String b) {
  if ((a.length - b.length).abs() > 1) return false;
  if (a == b) return true;
  if (a.length == b.length) {
    var diffs = 0;
    for (var i = 0; i < a.length; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i)) {
        diffs++;
        if (diffs > 1) return false;
      }
    }
    return diffs <= 1;
  }
  final shorter = a.length < b.length ? a : b;
  final longer = a.length < b.length ? b : a;
  var si = 0;
  var li = 0;
  var skipped = false;
  while (si < shorter.length && li < longer.length) {
    if (shorter.codeUnitAt(si) == longer.codeUnitAt(li)) {
      si++;
      li++;
    } else if (skipped) {
      return false;
    } else {
      skipped = true;
      li++;
    }
  }
  return true;
}

int _scoreSettingsSearch(String rawQuery, _SettingsSearchEntry entry) {
  final normQuery = _normalizeHuSearch(rawQuery);
  if (normQuery.isEmpty) return 0;

  final tokens = normQuery
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return 0;

  final normTitle = _normalizeHuSearch(entry.title);
  final normCat = _normalizeHuSearch(entry.category);
  final normDesc = _normalizeHuSearch(entry.description);
  final normKeywords = entry.keywords.map(_normalizeHuSearch).toList();
  final wordPool = <String>{
    ...normTitle.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty),
    ...normKeywords
        .expand((k) => k.split(RegExp(r'[^a-z0-9]+')))
        .where((w) => w.isNotEmpty),
  };

  var totalScore = 0;
  for (final token in tokens) {
    var tokenBest = 0;
    if (normTitle.contains(token)) {
      tokenBest = normTitle.startsWith(token) ? 100 : 75;
    } else if (normKeywords.any((k) => k.contains(token))) {
      tokenBest = 60;
    } else if (normCat.contains(token) || normDesc.contains(token)) {
      tokenBest = 40;
    } else if (token.length >= 3) {
      for (final word in wordPool) {
        if (_levenshteinWithin1(token, word) ||
            (word.length >= token.length && _isSubsequence(token, word))) {
          tokenBest = 20;
          break;
        }
      }
    }
    if (tokenBest == 0) return 0;
    totalScore += tokenBest;
  }
  return totalScore;
}
