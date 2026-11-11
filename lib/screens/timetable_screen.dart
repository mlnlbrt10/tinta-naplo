import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/frosted_inspection_modal.dart';

/// "Órarend" tab providing Daily (Napi) and Landscape Weekly (Heti) views,
/// "Hétvége mutatása" toggle, strikethrough + bold amber substitution display,
/// staggered entrance animations, Hero lesson badges, and frosted-glass modals.
class TimetableScreen extends StatefulWidget {
  final StoredSession session;
  final KretaClient kretaClient;
  final List<Lesson> initialTodaysLessons;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final bool isActiveTab;
  final int entranceEpoch;

  const TimetableScreen({
    super.key,
    required this.session,
    required this.kretaClient,
    required this.initialTodaysLessons,
    required this.prefs,
    required this.onPrefsChanged,
    this.isActiveTab = true,
    this.entranceEpoch = 0,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  static const List<String> _weekdayShortNames = [
    'H',
    'K',
    'Sze',
    'Cs',
    'P',
    'Szo',
    'V',
  ];

  static const List<String> _weekdayFullNames = [
    'Hétfő',
    'Kedd',
    'Szerda',
    'Csütörtök',
    'Péntek',
    'Szombat',
    'Vasárnap',
  ];

  late DateTime _selectedDate;
  bool _isWeeklyMode = false;
  bool _isLoading = false;
  String? _error;
  List<Lesson> _weekLessons = const [];
  int _daySwitchEpoch = 0;

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dayFormat = DateFormat('MM. dd.');
  final DateFormat _fullDateFormat = DateFormat('yyyy. MM. dd.');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _weekLessons = List<Lesson>.from(widget.initialTodaysLessons);
    _loadCurrentWeek(showFullSpinner: true);
  }

  @override
  void didUpdateWidget(covariant TimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActiveTab && !widget.isActiveTab && _isWeeklyMode) {
      _applyOrientation(weeklyLandscape: false);
    } else if (!oldWidget.isActiveTab && widget.isActiveTab && _isWeeklyMode) {
      _applyOrientation(weeklyLandscape: true);
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _applyOrientation({required bool weeklyLandscape}) {
    if (weeklyLandscape) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  void _setWeeklyMode(bool weekly) {
    if (_isWeeklyMode == weekly) return;
    setState(() {
      _isWeeklyMode = weekly;
      _daySwitchEpoch++;
    });
    _applyOrientation(weeklyLandscape: weekly);
  }

  void _toggleShowWeekends() {
    HapticFeedback.lightImpact();
    final nextVal = !widget.prefs.showWeekends;
    widget.onPrefsChanged(widget.prefs.copyWith(showWeekends: nextVal));
    if (!nextVal && _selectedDate.weekday > 5) {
      setState(() {
        _selectedDate = _mondayOf(_selectedDate);
        _daySwitchEpoch++;
      });
    }
  }

  DateTime _mondayOf(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _loadCurrentWeek({bool showFullSpinner = false}) async {
    final monday = _mondayOf(_selectedDate);
    final sunday = monday.add(const Duration(days: 6));

    if (mounted && showFullSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final validSession =
          await widget.kretaClient.ensureValidSession(widget.session);
      final lessons = await widget.kretaClient.fetchTimetableForRange(
        validSession,
        from: monday,
        to: sunday,
      );
      if (!mounted) return;
      setState(() {
        _weekLessons = lessons;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _shiftWeek(int deltaWeeks) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: 7 * deltaWeeks));
      _daySwitchEpoch++;
    });
    _loadCurrentWeek(showFullSpinner: true);
  }

  void _jumpToToday() {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekChanged = !_isSameDay(_mondayOf(_selectedDate), _mondayOf(today));
    setState(() {
      _selectedDate = today;
      _daySwitchEpoch++;
    });
    if (weekChanged) {
      _loadCurrentWeek(showFullSpinner: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final monday = _mondayOf(_selectedDate);
    final visibleDaysCount = widget.prefs.showWeekends ? 7 : 5;
    final endDay = monday.add(Duration(days: visibleDaysCount - 1));

    return RefreshIndicator(
      onRefresh: () => _loadCurrentWeek(showFullSpinner: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        children: [
          _buildTopControlsCard(theme, scheme, monday, endDay),
          if (!_isWeeklyMode) ...[
            const SizedBox(height: 8),
            _buildWeekdaySelector(theme, scheme, monday, visibleDaysCount),
          ],
          const SizedBox(height: 10),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _buildErrorCard(theme, _error!)
          else if (_isWeeklyMode)
            _buildWeeklyLandscapeBoard(theme, scheme, monday, visibleDaysCount)
          else
            ..._buildDailyList(theme, scheme, _selectedDate),
        ],
      ),
    );
  }

  Widget _buildTopControlsCard(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    DateTime endDay,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              tooltip: 'Előző hét',
              onPressed: () => _shiftWeek(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
          TactileBounce(
            onTap: _jumpToToday,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.date_range_rounded,
                    size: 13,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_dayFormat.format(monday)}–${_dayFormat.format(endDay)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 20,
              tooltip: 'Következő hét',
              onPressed: () => _shiftWeek(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactModeSegment(
                  scheme: scheme,
                  label: uwu('Napi'),
                  icon: Icons.calendar_today_rounded,
                  selected: !_isWeeklyMode,
                  onTap: () => _setWeeklyMode(false),
                ),
                _buildCompactModeSegment(
                  scheme: scheme,
                  label: uwu('Heti'),
                  icon: Icons.screen_rotation_rounded,
                  selected: _isWeeklyMode,
                  onTap: () => _setWeeklyMode(true),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          SizedBox(
            width: 32,
            height: 32,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              tooltip: 'Órarend beállítások',
              icon: const Icon(Icons.tune_rounded, size: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onSelected: (val) {
                if (val == 'toggle_weekends') {
                  _toggleShowWeekends();
                } else if (val == 'jump_today') {
                  _jumpToToday();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'jump_today',
                  child: Text('Ugrás a mai napra (Ma)'),
                ),
                CheckedPopupMenuItem<String>(
                  value: 'toggle_weekends',
                  checked: widget.prefs.showWeekends,
                  child: const Text('Hétvége mutatása'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactModeSegment({
    required ColorScheme scheme,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return TactileBounce(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 9),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected
                  ? scheme.onPrimary
                  : scheme.onSurface.withValues(alpha: 0.72),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected
                    ? scheme.onPrimary
                    : scheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeekdaySelector(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int visibleDaysCount,
  ) {
    return Row(
      children: List.generate(visibleDaysCount, (idx) {
        final day = monday.add(Duration(days: idx));
        final selected = _isSameDay(day, _selectedDate);
        final dayLessonsCount =
            _weekLessons.where((l) => _isSameDay(l.start, day)).length;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: TactileBounce(
              onTap: () => setState(() {
                _selectedDate = day;
                _daySwitchEpoch++;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? scheme.primary : theme.dividerColor,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _weekdayShortNames[idx],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color:
                                selected ? scheme.onPrimary : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${day.day}.',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? scheme.onPrimary.withValues(alpha: 0.85)
                                : scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dayLessonsCount > 0
                            ? (selected ? scheme.onPrimary : scheme.primary)
                            : Colors.transparent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  List<Widget> _buildDailyList(
    ThemeData theme,
    ColorScheme scheme,
    DateTime day,
  ) {
    final dayLessons = _weekLessons
        .where((l) => _isSameDay(l.start, day))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final dayName = _weekdayFullNames[(day.weekday - 1).clamp(0, 6)];
    final combinedEpoch = '${widget.entranceEpoch}-$_daySwitchEpoch';

    return [
      Row(
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 20,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$dayName (${_fullDateFormat.format(day)})',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(
              '${dayLessons.length} tanóra',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (dayLessons.isEmpty)
        _buildEmptyLessonsCard(theme, scheme)
      else
        ...List.generate(dayLessons.length, (idx) {
          final lesson = dayLessons[idx];
          return buildOledLessonCard(
            context,
            theme,
            lesson,
            _timeFormat,
            heroPrefix: 'timetable-daily',
          ).staggeredEntrance(
            idx,
            animationKey: ValueKey('tt-${lesson.uid}-$combinedEpoch'),
          );
        }),
    ];
  }

  Widget _buildWeeklyLandscapeBoard(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int visibleDaysCount,
  ) {
    final combinedEpoch = '${widget.entranceEpoch}-$_daySwitchEpoch';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(visibleDaysCount, (i) {
        final day = monday.add(Duration(days: i));
        final dayLessons = _weekLessons
            .where((l) => _isSameDay(l.start, day))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
        final isToday = _isSameDay(day, DateTime.now());

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < visibleDaysCount - 1 ? 8 : 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: OledTheme.cardRadius,
              border: Border.all(
                color: isToday ? scheme.primary : theme.dividerColor,
                width: isToday ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 6,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isToday
                        ? scheme.primary.withValues(alpha: 0.2)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _weekdayFullNames[i],
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isToday ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      Text(
                        _dayFormat.format(day),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (dayLessons.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Nincs óra',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                else
                  ...dayLessons.map(
                    (lesson) => _buildCompactWeeklyLessonTile(
                      context,
                      theme,
                      scheme,
                      lesson,
                    ),
                  ),
              ],
            ),
          ).staggeredEntrance(
            i,
            animationKey: ValueKey('wk-col-$i-$combinedEpoch'),
          ),
        );
      }),
    );
  }

  Widget _buildCompactWeeklyLessonTile(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    Lesson lesson,
  ) {
    final isCancelled = lesson.state.name.toLowerCase().contains('elmarad');
    final hasSub = lesson.substituteTeacher != null &&
        lesson.substituteTeacher!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactileBounce(
        pressedScale: 0.96,
        onTap: () => showLessonInspectionModal(
          context,
          lesson,
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isCancelled
                  ? const Color(0xFFC62828)
                  : hasSub
                      ? const Color(0xFFF9A825)
                      : theme.dividerColor,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (lesson.lessonNumber != null)
                    Text(
                      '${lesson.lessonNumber}. ',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      '${_timeFormat.format(lesson.start)}–${_timeFormat.format(lesson.end)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                lesson.subject?.name ?? lesson.name,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              if (lesson.roomName != null &&
                  lesson.roomName!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  lesson.roomName!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
              if (hasSub) ...[
                if (lesson.teacher != null &&
                    lesson.teacher!.trim().isNotEmpty)
                  Text(
                    lesson.teacher!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                Text(
                  lesson.substituteTeacher!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFFFB300),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLessonsCard(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.event_available_rounded,
            color: scheme.onSurface.withValues(alpha: 0.54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Erre a napra nincs rögzített tanóra.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2B1111),
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: Colors.redAccent),
      ),
      child: Text(
        error,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

/// Shared lesson card builder with Hero badge transition, TactileBounce,
/// strikethrough original teacher + bold amber substitute teacher, and
/// frosted glass inspection modal.
Widget buildOledLessonCard(
  BuildContext context,
  ThemeData theme,
  Lesson lesson,
  DateFormat timeFormat, {
  String heroPrefix = 'lesson',
}) {
  final scheme = theme.colorScheme;
  final isCancelled = lesson.state.name.toLowerCase().contains('elmarad');
  final hasSubstitute = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final timeRange =
      '${timeFormat.format(lesson.start)} – ${timeFormat.format(lesson.end)}';

  final badgeBg = isCancelled
      ? const Color(0xFFC62828)
      : hasSubstitute
          ? const Color(0xFFF9A825)
          : scheme.surfaceContainerHigh;

  final badgeTextColor =
      (isCancelled || hasSubstitute) ? Colors.black : scheme.onSurface;

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TactileBounce(
      pressedScale: 0.97,
      onTap: () => showLessonInspectionModal(
        context,
        lesson,
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: OledTheme.cardRadius,
          border: Border.all(
            color: isCancelled
                ? const Color(0xFFC62828).withValues(alpha: 0.65)
                : hasSubstitute
                    ? const Color(0xFFF9A825).withValues(alpha: 0.65)
                    : theme.dividerColor,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: OledTheme.badgeRadius,
                border: Border.all(color: theme.dividerColor),
              ),
              child: Text(
                lesson.lessonNumber != null
                    ? '${lesson.lessonNumber}.'
                    : '•',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: badgeTextColor,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lesson.subject?.name ?? lesson.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            decoration:
                                isCancelled ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Text(
                          timeRange,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (lesson.roomName != null &&
                          lesson.roomName!.trim().isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.meeting_room_rounded,
                              size: 15,
                              color: scheme.onSurface.withValues(alpha: 0.62),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              lesson.roomName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                      if (hasSubstitute)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.swap_horiz_rounded,
                              size: 16,
                              color: Color(0xFFFFB300),
                            ),
                            const SizedBox(width: 4),
                            if (lesson.teacher != null &&
                                lesson.teacher!.trim().isNotEmpty) ...[
                              Text(
                                lesson.teacher!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.5),
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                lesson.substituteTeacher!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFFFFB300),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        )
                      else if (lesson.teacher != null &&
                          lesson.teacher!.trim().isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 15,
                              color: scheme.onSurface.withValues(alpha: 0.62),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              lesson.teacher!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.78),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (lesson.theme != null &&
                      lesson.theme!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Téma: ${lesson.theme}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
