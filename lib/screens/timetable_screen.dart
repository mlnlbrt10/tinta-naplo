import 'dart:async';
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
import '../widgets/glass_card.dart';

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

/// Filters a day's sorted lessons using two independent toggles:
/// * [hideCancelled] – hides lessons flagged as cancelled ("Elmaradó órák");
/// * [hideFree] – hides synthesized free / gap ("Lyukas") placeholder periods.
///
/// When [hideFree] is false, muted placeholder cards are synthesized for the
/// inactive leading period(s) and for numbered periods missing between lessons,
/// so the student clearly sees free slots.
List<Lesson> filterLessonsForDisplay(
  List<Lesson> rawDayLessons, {
  required bool hideCancelled,
  required bool hideFree,
}) {
  final sorted = List<Lesson>.from(rawDayLessons)
    ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));
  final real = sorted
      .where((l) => !isInactivePlaceholderLesson(l))
      .where((l) => !(hideCancelled && isLessonCancelled(l)))
      .toList();
  if (hideFree || real.isEmpty) return real;

  // Period numbers that actually exist (cancelled lessons still occupy a slot).
  final numbered = sorted
      .where((l) => l.lessonNumber != null && !isInactivePlaceholderLesson(l))
      .toList();
  final firstLocal = sorted.first.start.toLocal();
  final presentNumbers = numbered.map((l) => l.lessonNumber!).toSet();
  final firstPeriodNum = sorted.first.lessonNumber ??
      ((firstLocal.hour > 8 ||
              (firstLocal.hour == 8 && firstLocal.minute >= 40))
          ? 2
          : 1);
  final lastPeriodNum = numbered.isEmpty
      ? firstPeriodNum
      : numbered.map((l) => l.lessonNumber!).reduce((a, b) => a > b ? a : b);

  final missing = <int>[];
  if (!presentNumbers.contains(1)) {
    for (int p = 1; p < firstPeriodNum; p++) {
      missing.add(p);
    }
  }
  for (int p = firstPeriodNum; p <= lastPeriodNum; p++) {
    if (!presentNumbers.contains(p) && !missing.contains(p)) missing.add(p);
  }
  if (missing.isEmpty) return real;

  Lesson placeholder(int p) {
    final startTime = DateTime(
      firstLocal.year,
      firstLocal.month,
      firstLocal.day,
      8 + ((p - 1) * 55) ~/ 60,
      ((p - 1) * 55) % 60,
    );
    final endTime = startTime.add(const Duration(minutes: 45));
    final dateStr = DateFormat('yyyy-MM-dd').format(firstLocal);
    return Lesson(
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
    );
  }

  final merged = [...real, ...missing.map(placeholder)]..sort((a, b) {
      final an = a.lessonNumber ?? 99;
      final bn = b.lessonNumber ?? 99;
      final cmp = an.compareTo(bn);
      return cmp != 0
          ? cmp
          : a.start.toLocal().compareTo(b.start.toLocal());
    });
  return merged;
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
  Timer? _minuteTicker;

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
  bool _showFilterPanel = false;
  bool _initialEntrancePlayed = false;
  bool _entranceActive = false;
  bool _isLoading = false;
  String? _error;
  List<Lesson> _weekLessons = const [];

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dayFormat = DateFormat('MM. dd.');
  final DateFormat _fullDateFormat = DateFormat('yyyy. MM. dd.');

  int get _visibleDaysCount => widget.prefs.showWeekends ? 7 : 5;

  void _armInitialEntranceIfNeeded() {
    if (!_initialEntrancePlayed && widget.isActiveTab && !_isLoading) {
      _initialEntrancePlayed = true;
      _entranceActive = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _entranceActive = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    var initialDay = DateUtils.dateOnly(now);
    final todaysEnded = widget.initialTodaysLessons.isNotEmpty &&
        widget.initialTodaysLessons
            .where((l) => !isLessonCancelled(l))
            .every((l) => !l.end.toLocal().isAfter(now));
    if (initialDay.weekday > 5) {
      // Weekend -> Monday.
      initialDay = initialDay.add(Duration(days: 8 - initialDay.weekday));
    } else if (now.hour >= 18 || todaysEnded) {
      // Evening / school day over -> tomorrow (Friday evening -> Monday).
      initialDay = initialDay.add(
        Duration(days: initialDay.weekday == 5 ? 3 : 1),
      );
    }
    _selectedDate = initialDay;
    final initialPage =
        (_selectedDate.weekday - 1).clamp(0, _visibleDaysCount - 1);
    _pageController = PageController(initialPage: initialPage);
    _weekLessons = _isSameDay(initialDay, DateUtils.dateOnly(now))
        ? List<Lesson>.from(widget.initialTodaysLessons)
        : const [];
    _loadCurrentWeek(showFullSpinner: true);
    // Keeps the "ongoing lesson" glow in sync with the clock.
    _minuteTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && widget.isActiveTab) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActiveTab && widget.isActiveTab) {
      _armInitialEntranceIfNeeded();
    }
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
    _minuteTicker?.cancel();
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
        });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  void _toggleHideCancelledLessons() {
    HapticFeedback.lightImpact();
    widget.onPrefsChanged(
      widget.prefs
          .withExtra('hideCancelledLessons', !widget.prefs.hideCancelledLessons),
    );
  }

  void _toggleHideFreeLessons() {
    HapticFeedback.lightImpact();
    widget.onPrefsChanged(
      widget.prefs.withExtra('hideFreeLessons', !widget.prefs.hideFreeLessons),
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
        _armInitialEntranceIfNeeded();
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
              _buildTopControlsCard(theme, scheme, monday, endDay)
                  .staggeredEntrance(0, enabled: _entranceActive),
              const SizedBox(height: 6),
              _buildWeekdaySelector(theme, scheme, monday, visibleDaysCount)
                  .staggeredEntrance(1, enabled: _entranceActive),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _showFilterPanel
                    ? Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: _buildExpandableFilterCard(theme, scheme),
                      )
                    : const SizedBox.shrink(),
              ),
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
                      physics: const PageScrollPhysics(),
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
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: theme.dividerColor),
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
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Órarend beállítások',
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() => _showFilterPanel = !_showFilterPanel);
              },
              icon: Icon(
                Icons.tune_rounded,
                size: 18,
                color: _showFilterPanel ? scheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandableFilterCard(ThemeData theme, ColorScheme scheme) {
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: theme.dividerColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Elmaradó órák elrejtése',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            value: widget.prefs.hideCancelledLessons,
            onChanged: (_) => _toggleHideCancelledLessons(),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Lyukas / szabad órák elrejtése',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            value: widget.prefs.hideFreeLessons,
            onChanged: (_) => _toggleHideFreeLessons(),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Hétvége mutatása',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            value: widget.prefs.showWeekends,
            onChanged: (_) => _toggleShowWeekends(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ActionChip(
                  avatar: const Icon(Icons.today_rounded, size: 16),
                  label: const Text('Mai nap (Ma)'),
                  onPressed: () {
                    setState(() => _showFilterPanel = false);
                    _jumpToToday();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ActionChip(
                  avatar: const Icon(Icons.calendar_month_rounded, size: 16),
                  label: const Text('Naptár...'),
                  onPressed: () {
                    setState(() => _showFilterPanel = false);
                    _openDatePicker();
                  },
                ),
              ),
            ],
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

  /// Weekday selector with a smooth sliding pill indicator that is driven
  /// 1:1 by the horizontal [PageView] scroll position.
  Widget _buildWeekdaySelector(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int visibleDaysCount,
  ) {
    final selectedIdx =
        (_selectedDate.weekday - 1).clamp(0, visibleDaysCount - 1);
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.all(3),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.dividerColor),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / visibleDaysCount;
          return AnimatedBuilder(
            animation: _pageController,
            builder: (context, _) {
              double page = selectedIdx.toDouble();
              if (_pageController.hasClients &&
                  _pageController.position.haveDimensions) {
                page = (_pageController.page ?? page)
                    .clamp(0.0, (visibleDaysCount - 1).toDouble());
              }
              return SizedBox(
                height: 34,
                child: Stack(
                  children: [
                    Positioned(
                      left: page * slotWidth,
                      top: 0,
                      bottom: 0,
                      width: slotWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(visibleDaysCount, (idx) {
                        final day = monday.add(Duration(days: idx));
                        final t = (1 - (page - idx).abs()).clamp(0.0, 1.0);
                        final mainColor = Color.lerp(
                          scheme.onSurface,
                          scheme.onPrimary,
                          t,
                        )!;
                        final subColor = Color.lerp(
                          scheme.onSurface.withValues(alpha: 0.62),
                          scheme.onPrimary.withValues(alpha: 0.88),
                          t,
                        )!;
                        return Expanded(
                          child: TactileBounce(
                            onTap: () => _onSelectWeekdayPill(idx, monday),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _weekdayShortNames[idx],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: mainColor,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${day.day}.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: subColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              );
            },
          );
        },
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
      hideCancelled: widget.prefs.hideCancelledLessons,
      hideFree: widget.prefs.hideFreeLessons,
    );

    final dayName = _weekdayFullNames[(day.weekday - 1).clamp(0, 6)];

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
            .staggeredEntrance(2, enabled: _entranceActive)
      else
        ...List.generate(dayLessons.length, (idx) {
          final lesson = dayLessons[idx];
          return buildOledLessonCard(
            context,
            theme,
            lesson,
            _timeFormat,
            prefs: widget.prefs,
          ).staggeredEntrance(idx + 2, enabled: _entranceActive);
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
          hideCancelled: widget.prefs.hideCancelledLessons,
          hideFree: widget.prefs.hideFreeLessons,
        );
        final isToday = _isSameDay(day, DateTime.now());

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < visibleDaysCount - 1 ? 6 : 0),
            child: SoftGlassCard(
            prefs: widget.prefs,
            padding: const EdgeInsets.all(6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isToday ? scheme.primary : theme.dividerColor,
              width: isToday ? 1.4 : 1.0,
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
    return SoftGlassCard(
      prefs: widget.prefs,
      padding: const EdgeInsets.all(16),
      borderRadius: OledTheme.cardRadius,
      border: Border.all(color: theme.dividerColor),
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

  final nowLocal = DateTime.now();
  final isOngoing = !isPlaceholder &&
      !isCancelled &&
      !nowLocal.isBefore(startLocal) &&
      !nowLocal.isAfter(endLocal);

  Widget card = TactileBounce(
      pressedScale: 0.97,
      onTap: () => showLessonInspectionModal(
        context,
        lesson,
        heroTag: heroTag,
        prefs: prefs,
      ),
      child: ChristmasSnowCap(
        enabled: prefs?.christmasModeEnabled == true,
        child: SoftGlassCard(
          prefs: prefs ?? const UserProfilePrefs(),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          color: isPlaceholder
              ? theme.cardTheme.color?.withValues(alpha: 0.55)
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOngoing
                ? Colors.blueAccent
                : isPlaceholder
                ? theme.dividerColor.withValues(alpha: 0.45)
                : isCancelled
                    ? const Color(0xFFC62828).withValues(alpha: 0.75)
                    : hasSubstitute
                        ? const Color(0xFFF9A825).withValues(alpha: 0.65)
                        : theme.dividerColor,
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
    );

  if (isOngoing) {
    card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: card,
    );
  }

  return Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: card,
  );
}
