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

/// Returns true if [lesson] is a synthesized placeholder for an inactive morning period.
bool isInactivePlaceholderLesson(Lesson lesson) =>
    lesson.uid.startsWith('inactive_period_');

/// Filters a day's sorted lessons according to [showCancelledLessons].
/// When [showCancelledLessons] is true:
/// - All cancelled lessons (including 0th/1st morning lessons) remain in the list.
/// - If school starts later (e.g. first scheduled lesson is period 2+ or starts >= 08:40
///   with no period 1 record), synthesizes a muted greyed-out placeholder card for the
///   inactive first period(s) so the student clearly sees the free morning slot.
List<Lesson> filterLessonsForDisplay(
  List<Lesson> rawDayLessons, {
  required bool showCancelledLessons,
}) {
  final sorted = List<Lesson>.from(rawDayLessons)
    ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
  if (!showCancelledLessons) {
    return sorted
        .where((l) => !isLessonCancelled(l) && !isInactivePlaceholderLesson(l))
        .toList();
  }

  if (sorted.isEmpty) {
    return sorted;
  }

  final first = sorted.first;
  final firstLocal = first.start.toLocal();
  final hasPeriod1 = sorted.any((l) => l.lessonNumber == 1);
  final firstPeriodNum = first.lessonNumber ??
      ((firstLocal.hour > 8 ||
              (firstLocal.hour == 8 && firstLocal.minute >= 40))
          ? 2
          : 1);

  if (!hasPeriod1 && firstPeriodNum > 1) {
    final placeholders = <Lesson>[];
    for (int p = 1; p < firstPeriodNum; p++) {
      final startTime = DateTime(
        firstLocal.year,
        firstLocal.month,
        firstLocal.day,
        8 + ((p - 1) * 55) ~/ 60,
        ((p - 1) * 55) % 60,
      );
      final endTime = startTime.add(const Duration(minutes: 45));
      final dateStr = DateFormat('yyyy-MM-dd').format(firstLocal);
      placeholders.add(
        Lesson(
          uid: 'inactive_period_${dateStr}_$p',
          date: dateStr,
          start: startTime,
          end: endTime,
          name: 'Nincs óra (Szabad sáv)',
          lessonNumber: p,
          lessonSeqNumber: p,
          roomName: 'Inaktív óra',
          type: NameUidDesc(
            uid: 'inactive,Tanora',
            name: 'Tanora',
            description: 'Tanóra',
          ),
          state: NameUidDesc(
            uid: 'inactive_period,elmaradt',
            name: 'elmaradt',
            description: 'Nincs óra / Elmarad',
          ),
          canStudentEditHomework: false,
          isHomeworkComplete: false,
          attachments: const [],
          isDigitalLesson: false,
          digitalSupportDeviceTypeList: const [],
          createdAt: startTime,
          lastModifiedAt: startTime,
        ),
      );
    }
    return [...placeholders, ...sorted];
  }

  return sorted;
}

/// "Órarend" tab providing:
/// - Horizontal Day Swiping via `PageView.builder` (Monday to Friday, or Mon–Sun)
///   with two-way synchronization to the top segmented weekday pill bar.
/// - Calendar Datepicker when tapping the date range pill (`11. 09.–11. 13.`).
/// - Compact lesson cards so a full school day fits comfortably without scrolling.
/// - Immersive Landscape Weekly Timetable mode (hides top AppBar & bottom dock,
///   with a single compact floating exit button `Icons.fullscreen_exit`).
class TimetableScreen extends StatefulWidget {
  final StoredSession session;
  final KretaClient kretaClient;
  final List<Lesson> initialTodaysLessons;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final ValueChanged<bool>? onImmersiveWeeklyModeChanged;
  final bool isActiveTab;
  final int entranceEpoch;

  const TimetableScreen({
    super.key,
    required this.session,
    required this.kretaClient,
    required this.initialTodaysLessons,
    required this.prefs,
    required this.onPrefsChanged,
    this.onImmersiveWeeklyModeChanged,
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
      widget.onImmersiveWeeklyModeChanged?.call(false);
    } else if (!oldWidget.isActiveTab && widget.isActiveTab && _isWeeklyMode) {
      _applyOrientation(weeklyLandscape: true);
      widget.onImmersiveWeeklyModeChanged?.call(true);
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
    widget.onImmersiveWeeklyModeChanged?.call(weekly && widget.isActiveTab);
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

  Future<void> _openDatePicker() async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023, 9, 1),
      lastDate: DateTime(2030, 8, 31),
      helpText: 'Ugrás kiválasztott dátumra',
      cancelText: 'Mégse',
      confirmText: 'Ugrás',
    );
    if (picked == null || !mounted) return;

    var target = DateTime(picked.year, picked.month, picked.day);
    if (!widget.prefs.showWeekends && target.weekday > 5) {
      target = _mondayOf(target);
    }
    final weekChanged =
        !_isSameDay(_mondayOf(_selectedDate), _mondayOf(target));
    final pageIdx = (target.weekday - 1).clamp(0, _visibleDaysCount - 1);

    setState(() {
      _selectedDate = target;
      _daySwitchEpoch++;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        pageIdx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (weekChanged) {
      _loadCurrentWeek(showFullSpinner: true);
    }
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
      return SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: _buildErrorCard(theme, _error!))
                        : _buildWeeklyLandscapeBoard(
                            theme,
                            scheme,
                            monday,
                            visibleDaysCount,
                          ),
              ),
            ),
            Positioned(
              top: 10,
              right: 12,
              child: TactileBounce(
                onTap: () => _setWeeklyMode(false),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xE6141418),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Icon(
                    Icons.fullscreen_exit,
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            children: [
              _buildTopControlsCard(theme, scheme, monday, endDay),
              const SizedBox(height: 6),
              _buildWeekdaySelector(theme, scheme, monday, visibleDaysCount),
              const SizedBox(height: 6),
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
                                const EdgeInsets.fromLTRB(16, 2, 16, 100),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 19,
              tooltip: 'Előző hét',
              onPressed: () => _shiftWeek(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
          ),
          TactileBounce(
            onTap: _openDatePicker,
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
            width: 30,
            height: 30,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 19,
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
              borderRadius: BorderRadius.circular(14),
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
            width: 30,
            height: 30,
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
                } else if (val == 'pick_date') {
                  _openDatePicker();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'jump_today',
                  child: Text('Ugrás a mai napra (Ma)'),
                ),
                const PopupMenuItem<String>(
                  value: 'pick_date',
                  child: Text('Dátum választása naptárból...'),
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
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
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

  /// Modern segmented pill bar without redundant dot indicators underneath each day.
  Widget _buildWeekdaySelector(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int visibleDaysCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        children: List.generate(visibleDaysCount, (idx) {
          final day = monday.add(Duration(days: idx));
          final selected = _isSameDay(day, _selectedDate);

          return Expanded(
            child: TactileBounce(
              onTap: () => _onSelectWeekdayPill(idx, monday),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _weekdayShortNames[idx],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: selected ? scheme.onPrimary : scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${day.day}.',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: selected
                            ? scheme.onPrimary.withValues(alpha: 0.88)
                            : scheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
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
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 17,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$dayName (${_fullDateFormat.format(day)})',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                '${dayLessons.length} tanóra',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
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

  /// Ultra-compact, multi-column weekly grid fitted on-screen without vertical scrolling.
  Widget _buildWeeklyLandscapeBoard(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int visibleDaysCount,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            margin: EdgeInsets.only(right: i < visibleDaysCount - 1 ? 6 : 0),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isToday ? scheme.primary : theme.dividerColor,
                width: isToday ? 1.4 : 1.0,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isToday
                        ? scheme.primary.withValues(alpha: 0.2)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekdayShortNames[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: isToday ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _dayFormat.format(day),
                        style: TextStyle(
                          fontSize: 9.5,
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                if (dayLessons.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'Nincs óra',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.45),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      children: dayLessons
                          .take(9)
                          .map(
                            (lesson) => Expanded(
                              child: _buildCompactWeeklyLessonTile(
                                context,
                                theme,
                                scheme,
                                lesson,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
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
    final isPlaceholder = isInactivePlaceholderLesson(lesson);
    final isCancelled = isLessonCancelled(lesson) && !isPlaceholder;
    final hasSub = lesson.substituteTeacher != null &&
        lesson.substituteTeacher!.trim().isNotEmpty;
    final heroTag = 'lesson_num_${lesson.uid}';
    final rawSubject = lesson.subject?.name ?? lesson.name;
    final subjectDisplay =
        widget.prefs.resolveSubjectName(rawSubject, lesson.subject?.uid);

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showLessonInspectionModal(
          context,
          lesson,
          heroTag: heroTag,
          prefs: widget.prefs,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isPlaceholder
                ? scheme.surfaceContainerHigh.withValues(alpha: 0.35)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isCancelled
                  ? const Color(0xFFC62828)
                  : hasSub
                      ? const Color(0xFFF9A825)
                      : theme.dividerColor,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              if (lesson.lessonNumber != null)
                Text(
                  '${lesson.lessonNumber}. ',
                  style: TextStyle(
                    fontSize: 10,
                    color: isPlaceholder
                        ? scheme.onSurface.withValues(alpha: 0.45)
                        : isCancelled
                            ? const Color(0xFFFF5252)
                            : scheme.primary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              Expanded(
                child: Text(
                  subjectDisplay,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: (isCancelled || isPlaceholder)
                        ? scheme.onSurface.withValues(alpha: 0.52)
                        : scheme.onSurface,
                    decoration:
                        isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              if (lesson.roomName != null &&
                  lesson.roomName!.trim().isNotEmpty &&
                  !isPlaceholder)
                Text(
                  lesson.roomName!,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyLessonsCard(ThemeData theme, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(16),
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

/// Compact shared lesson card builder (`Part B #9` & `Part B #16`) so an entire
/// typical school day fits comfortably on screen without extensive scrolling.
Widget buildOledLessonCard(
  BuildContext context,
  ThemeData theme,
  Lesson lesson,
  DateFormat timeFormat, {
  String? heroPrefix,
  UserProfilePrefs? prefs,
}) {
  final scheme = theme.colorScheme;
  final isPlaceholder = isInactivePlaceholderLesson(lesson);
  final isCancelled = isLessonCancelled(lesson) && !isPlaceholder;
  final hasSubstitute = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();
  final timeRange =
      '${timeFormat.format(startLocal)} - ${timeFormat.format(endLocal)}';

  final badgeBg = isPlaceholder
      ? scheme.surfaceContainerHigh.withValues(alpha: 0.45)
      : isCancelled
          ? const Color(0xFFC62828)
          : hasSubstitute
              ? const Color(0xFFF9A825)
              : scheme.surfaceContainerHigh;

  final badgeTextColor = isPlaceholder
      ? scheme.onSurface.withValues(alpha: 0.45)
      : isCancelled
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
    padding: const EdgeInsets.only(bottom: 7),
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isPlaceholder
                ? theme.cardTheme.color?.withValues(alpha: 0.55)
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPlaceholder
                  ? theme.dividerColor.withValues(alpha: 0.45)
                  : isCancelled
                      ? const Color(0xFFC62828).withValues(alpha: 0.75)
                      : hasSubstitute
                          ? const Color(0xFFF9A825).withValues(alpha: 0.65)
                          : theme.dividerColor,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Hero(
                tag: heroTag,
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: badgeBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text(
                      lesson.lessonNumber != null
                          ? '${lesson.lessonNumber}.'
                          : '•',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subjectDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: (isCancelled || isPlaceholder)
                                  ? scheme.onSurface.withValues(alpha: 0.55)
                                  : scheme.onSurface,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: isCancelled
                                  ? const Color(0xFFFF5252)
                                  : null,
                              decorationThickness: isCancelled ? 2.2 : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          timeRange,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isPlaceholder
                                ? scheme.onSurface.withValues(alpha: 0.45)
                                : isCancelled
                                    ? const Color(0xFFFF5252)
                                    : scheme.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (isCancelled || isPlaceholder) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isPlaceholder
                                  ? scheme.surfaceContainerHigh
                                  : const Color(0xFFC62828),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isPlaceholder ? 'Nincs óra' : 'Elmarad',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: isPlaceholder
                                    ? scheme.onSurface.withValues(alpha: 0.65)
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 10,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (lesson.roomName != null &&
                            lesson.roomName!.trim().isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.meeting_room_rounded,
                                size: 12.5,
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                lesson.roomName!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.72),
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
                                size: 13.5,
                                color: Color(0xFFFFB300),
                              ),
                              const SizedBox(width: 3),
                              if (teacherDisplay != null &&
                                  teacherDisplay.trim().isNotEmpty) ...[
                                Text(
                                  teacherDisplay,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.48),
                                    decoration: TextDecoration.lineThrough,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  subTeacherDisplay,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFFFFB300),
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
                                size: 12.5,
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                teacherDisplay,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
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
