import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';

/// Returns true if [lesson] is marked as cancelled (`Allapot.Nev == "elmaradt"`).
bool isLessonCancelled(Lesson lesson) {
  final stateName = lesson.state.name.toLowerCase().trim();
  final stateDesc = lesson.state.description.toLowerCase().trim();
  return stateName == 'elmaradt' ||
      stateName.contains('elmarad') ||
      stateDesc.contains('elmarad');
}

/// Filters a day's sorted lessons according to [showCancelledLessons].
/// When [showCancelledLessons] is true, all cancelled lessons (including 0th/1st
/// morning lessons) remain in the list. When false, cancelled lessons are skipped.
List<Lesson> filterLessonsForDisplay(
  List<Lesson> rawDayLessons, {
  required bool showCancelledLessons,
}) {
  final sorted = List<Lesson>.from(rawDayLessons)
    ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
  if (showCancelledLessons) {
    return sorted;
  }
  return sorted.where((l) => !isLessonCancelled(l)).toList();
}

/// "Órarend" tab providing:
/// - Horizontal Day Swiping via `PageView.builder` (Monday to Friday, or Mon–Sun)
///   with two-way synchronization to the top weekday pill selector.
/// - Clean dedicated row for lesson time spans (`08:00 - 08:45`).
/// - Cancelled lesson styling (distinct red strikethrough + `"Elmarad"` red chip)
///   and `"Elmaradt órák megjelenítése (nulladik/első óra is)"` toggle.
/// - Shared Element "Boomerang" Hero animations (`lesson_num_${lesson.uid}`).
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
  late PageController _pageController;
  bool _isAnimatingPage = false;
  bool _isWeeklyMode = false;
  bool _isLoading = false;
  String? _error;
  List<Lesson> _weekLessons = const [];
  int _daySwitchEpoch = 0;

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dayFormat = DateFormat('MM. dd.');
  final DateFormat _fullDateFormat = DateFormat('yyyy. MM. dd.');

  int get _visibleDaysCount => widget.prefs.showWeekends ? 7 : 5;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    var initialDay = DateTime(now.year, now.month, now.day);
    if (!widget.prefs.showWeekends && initialDay.weekday > 5) {
      initialDay = _mondayOf(initialDay);
    }
    _selectedDate = initialDay;
    final initialPage =
        (_selectedDate.weekday - 1).clamp(0, _visibleDaysCount - 1);
    _pageController = PageController(initialPage: initialPage);
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
    _pageController.dispose();
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
    if (!weekly) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          final targetPage =
              (_selectedDate.weekday - 1).clamp(0, _visibleDaysCount - 1);
          _pageController.jumpToPage(targetPage);
        }
      });
    }
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
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  void _toggleShowCancelledLessons() {
    HapticFeedback.lightImpact();
    final nextVal = !widget.prefs.showCancelledLessons;
    widget.onPrefsChanged(
      widget.prefs.copyWith(showCancelledLessons: nextVal),
    );
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
      final lessons = await widget.kretaClient.fetchTimetableForRange(
        widget.session,
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
    var today = DateTime(now.year, now.month, now.day);
    if (!widget.prefs.showWeekends && today.weekday > 5) {
      today = _mondayOf(today);
    }
    final weekChanged = !_isSameDay(_mondayOf(_selectedDate), _mondayOf(today));
    final pageIdx = (today.weekday - 1).clamp(0, _visibleDaysCount - 1);
    setState(() {
      _selectedDate = today;
      _daySwitchEpoch++;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        pageIdx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    if (weekChanged) {
      _loadCurrentWeek(showFullSpinner: true);
    }
  }

  Future<void> _onSelectWeekdayPill(int idx, DateTime monday) async {
    final targetDay = monday.add(Duration(days: idx));
    if (_isSameDay(targetDay, _selectedDate)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = targetDay;
      _daySwitchEpoch++;
    });
    if (_pageController.hasClients) {
      _isAnimatingPage = true;
      await _pageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      _isAnimatingPage = false;
    }
  }

  void _onPageSwiped(int pageIdx, DateTime monday) {
    if (_isAnimatingPage) return;
    final swipedDay = monday.add(Duration(days: pageIdx));
    if (_isSameDay(swipedDay, _selectedDate)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = swipedDay;
      _daySwitchEpoch++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final monday = _mondayOf(_selectedDate);
    final visibleDaysCount = _visibleDaysCount;
    final endDay = monday.add(Duration(days: visibleDaysCount - 1));

    if (_isWeeklyMode) {
      return RefreshIndicator(
        onRefresh: () => _loadCurrentWeek(showFullSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
          children: [
            _buildTopControlsCard(theme, scheme, monday, endDay),
            const SizedBox(height: 10),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildErrorCard(theme, _error!)
            else
              _buildWeeklyLandscapeBoard(
                theme,
                scheme,
                monday,
                visibleDaysCount,
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              _buildTopControlsCard(theme, scheme, monday, endDay),
              const SizedBox(height: 8),
              _buildWeekdaySelector(theme, scheme, monday, visibleDaysCount),
              const SizedBox(height: 8),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildErrorCard(theme, _error!),
                    )
                  : PageView.builder(
                      controller: _pageController,
                      itemCount: visibleDaysCount,
                      onPageChanged: (idx) => _onPageSwiped(idx, monday),
                      itemBuilder: (context, pageIdx) {
                        final day = monday.add(Duration(days: pageIdx));
                        return RefreshIndicator(
                          onRefresh: () =>
                              _loadCurrentWeek(showFullSpinner: false),
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(16, 4, 16, 112),
                            children: _buildDailyList(theme, scheme, day),
                          ),
                        );
                      },
                    ),
        ),
      ],
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
                } else if (val == 'toggle_cancelled') {
                  _toggleShowCancelledLessons();
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
                  value: 'toggle_cancelled',
                  checked: widget.prefs.showCancelledLessons,
                  child: const Text(
                    'Elmaradt órák megjelenítése (nulladik/első óra is)',
                  ),
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
        final rawDayLessons = _weekLessons
            .where((l) => _isSameDay(l.start.toLocal(), day))
            .toList();
        final dayLessonsCount = filterLessonsForDisplay(
          rawDayLessons,
          showCancelledLessons: widget.prefs.showCancelledLessons,
        ).length;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: TactileBounce(
              onTap: () => _onSelectWeekdayPill(idx, monday),
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
    final rawDayLessons = _weekLessons
        .where((l) => _isSameDay(l.start.toLocal(), day))
        .toList();
    final dayLessons = filterLessonsForDisplay(
      rawDayLessons,
      showCancelledLessons: widget.prefs.showCancelledLessons,
    );

    final dayName = _weekdayFullNames[(day.weekday - 1).clamp(0, 6)];
    final combinedEpoch = '${widget.entranceEpoch}-$_daySwitchEpoch-${day.day}';

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
            prefs: widget.prefs,
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
        final rawDayLessons = _weekLessons
            .where((l) => _isSameDay(l.start.toLocal(), day))
            .toList();
        final dayLessons = filterLessonsForDisplay(
          rawDayLessons,
          showCancelledLessons: widget.prefs.showCancelledLessons,
        );
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
    final isCancelled = isLessonCancelled(lesson);
    final hasSub = lesson.substituteTeacher != null &&
        lesson.substituteTeacher!.trim().isNotEmpty;
    final startLocal = lesson.start.toLocal();
    final endLocal = lesson.end.toLocal();
    final heroTag = 'lesson_num_${lesson.uid}';
    final rawSubject = lesson.subject?.name ?? lesson.name;
    final subjectDisplay =
        widget.prefs.resolveSubjectName(rawSubject, lesson.subject?.uid);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactileBounce(
        pressedScale: 0.96,
        onTap: () => showLessonInspectionModal(
          context,
          lesson,
          heroTag: heroTag,
          prefs: widget.prefs,
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
                    Hero(
                      tag: heroTag,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Text(
                          '${lesson.lessonNumber}. ',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isCancelled
                                ? const Color(0xFFFF5252)
                                : scheme.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC62828),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Elmarad',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subjectDisplay,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isCancelled
                      ? scheme.onSurface.withValues(alpha: 0.65)
                      : scheme.onSurface,
                  decoration: isCancelled ? TextDecoration.lineThrough : null,
                  decorationColor:
                      isCancelled ? const Color(0xFFFF5252) : null,
                  decorationThickness: isCancelled ? 2.2 : null,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_timeFormat.format(startLocal)} - ${_timeFormat.format(endLocal)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                  fontSize: 10,
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
                    widget.prefs.resolveTeacherName(lesson.teacher),
                    style: theme.textTheme.labelSmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 10,
                    ),
                  ),
                Text(
                  widget.prefs.resolveTeacherName(lesson.substituteTeacher),
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

/// Shared lesson card builder with:
/// - Unique "Boomerang" Hero badge transition (`lesson_num_${lesson.uid}`),
/// - Dedicated clean row for the lesson time span (`08:00 - 08:45`),
/// - Distinct red strikethrough + `"Elmarad"` red chip for cancelled lessons,
/// - Strikethrough original teacher + bold amber substitute teacher.
Widget buildOledLessonCard(
  BuildContext context,
  ThemeData theme,
  Lesson lesson,
  DateFormat timeFormat, {
  String? heroPrefix,
  UserProfilePrefs? prefs,
}) {
  final scheme = theme.colorScheme;
  final isCancelled = isLessonCancelled(lesson);
  final hasSubstitute = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();
  final timeRange =
      '${timeFormat.format(startLocal)} - ${timeFormat.format(endLocal)}';

  final badgeBg = isCancelled
      ? const Color(0xFFC62828)
      : hasSubstitute
          ? const Color(0xFFF9A825)
          : scheme.surfaceContainerHigh;

  final badgeTextColor = isCancelled
      ? Colors.white
      : hasSubstitute
          ? Colors.black
          : scheme.onSurface;

  final heroTag = heroPrefix != null
      ? '${heroPrefix}_${lesson.uid}'
      : 'lesson_num_${lesson.uid}';

  final rawSubject = lesson.subject?.name ?? lesson.name;
  final subjectDisplay = prefs != null
      ? prefs.resolveSubjectName(rawSubject, lesson.subject?.uid)
      : rawSubject;
  final teacherDisplay = prefs != null && lesson.teacher != null
      ? prefs.resolveTeacherName(lesson.teacher)
      : lesson.teacher;
  final subTeacherDisplay =
      prefs != null && lesson.substituteTeacher != null
          ? prefs.resolveTeacherName(lesson.substituteTeacher)
          : lesson.substituteTeacher;

  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TactileBounce(
      pressedScale: 0.97,
      onTap: () => showLessonInspectionModal(
        context,
        lesson,
        heroTag: heroTag,
        prefs: prefs,
      ),
      child: ChristmasSnowCap(
        enabled: prefs?.christmasModeEnabled == true,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(
              color: isCancelled
                  ? const Color(0xFFC62828).withValues(alpha: 0.75)
                  : hasSubstitute
                      ? const Color(0xFFF9A825).withValues(alpha: 0.65)
                      : theme.dividerColor,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Hero(
                tag: heroTag,
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
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
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            subjectDisplay,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: isCancelled
                                  ? scheme.onSurface.withValues(alpha: 0.65)
                                  : scheme.onSurface,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: isCancelled
                                  ? const Color(0xFFFF5252)
                                  : null,
                              decorationThickness: isCancelled ? 2.4 : null,
                            ),
                          ),
                        ),
                        if (isCancelled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC62828),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'Elmarad',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Dedicated clean row for the lesson time span ("08:00 - 08:45")
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 14,
                          color: isCancelled
                              ? const Color(0xFFFF5252)
                              : scheme.primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          timeRange,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isCancelled
                                ? const Color(0xFFFF5252)
                                : scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
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
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.78),
                                ),
                              ),
                            ],
                          ),
                        if (hasSubstitute && subTeacherDisplay != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.swap_horiz_rounded,
                                size: 16,
                                color: Color(0xFFFFB300),
                              ),
                              const SizedBox(width: 4),
                              if (teacherDisplay != null &&
                                  teacherDisplay.trim().isNotEmpty) ...[
                                Text(
                                  teacherDisplay,
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
                                  subTeacherDisplay,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFFFFB300),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          )
                        else if (teacherDisplay != null &&
                            teacherDisplay.trim().isNotEmpty)
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
                                teacherDisplay,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.78),
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
    ),
  );
}
