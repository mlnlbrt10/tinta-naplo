import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/demo_data_service.dart';
import '../services/home_widget_sync_service.dart';
import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/minimalist_tokens.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/period_countdown_badge.dart';
import '../widgets/tinta_error_state.dart';
import '../widgets/tinta_toast.dart';

export '../widgets/period_countdown_badge.dart'
    show
        isLessonCancelled,
        isInactivePlaceholderLesson,
        formatCountdownRemainingLabel,
        PeriodCountdownPhase,
        PeriodCountdownInfo,
        PeriodCountdownRingPainter,
        PeriodCountdownBadge,
        LiveCountdownProgressScope,
        LiveCountdownSnapshot,
        BreakPerimeterCountdownPainter,
        BreakCountdownCard;

/// Resolves a continuous [PageView] index into `(weekOffset, dayIndex)` using
/// floor division so negative offsets (e.g. `499` -> `weekOffset: -1`,
/// `dayIndex: daysPerWeek - 1`) map cleanly without truncating toward zero.
({int weekOffset, int dayIndex}) resolveTimetablePageOffset({
  required int page,
  int basePage = 500,
  int daysPerWeek = 5,
}) {
  final int relativeDay = page - basePage;
  final int weekOffset = (relativeDay / daysPerWeek).floor();
  final int dayIndex = relativeDay - (weekOffset * daysPerWeek);
  return (weekOffset: weekOffset, dayIndex: dayIndex);
}

/// Filters a day's sorted lessons using two independent toggles:
/// * [hideCancelled] - hides lessons flagged as cancelled ("Elmaradó órák");
/// * [hideFree] - hides synthesized free / gap ("Lyukas") placeholder periods.
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
/// - Horizontal Day Swiping via `PageView.builder` (Monday to Friday, or Mon-Sun)
///   with two-way synchronization to the top segmented weekday pill bar.
/// - Calendar Datepicker when tapping the date range pill (`11. 09.-11. 13.`).
/// - Compact lesson cards so a full school day fits comfortably without scrolling.
/// - Immersive Landscape Weekly Timetable mode (hides top AppBar & bottom dock,
///   with a single compact floating exit button `Icons.fullscreen_exit`).
class TimetableScreen extends StatefulWidget {
  final StoredSession session;
  final KretaClient kretaClient;
  final List<Lesson> initialTodaysLessons;
  final List<Homework> homeworks;
  final List<Test> tests;
  final List<Omission> omissions;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final ValueChanged<bool>? onImmersiveWeeklyModeChanged;
  final bool isActiveTab;
  final int entranceEpoch;
  final DateTime Function()? clock;

  const TimetableScreen({
    super.key,
    required this.session,
    required this.kretaClient,
    required this.initialTodaysLessons,
    this.homeworks = const [],
    this.tests = const [],
    this.omissions = const [],
    required this.prefs,
    required this.onPrefsChanged,
    this.onImmersiveWeeklyModeChanged,
    this.isActiveTab = true,
    this.entranceEpoch = 0,
    this.clock,
  });

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const int _basePage = 500;
  static const int _totalPageCount = 1000;

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

  Timer? _minuteTicker;
  late DateTime _anchorMonday;
  late int _currentPage;
  late PageController _pageController;
  bool _isAnimatingPage = false;
  int? _programmaticTargetPage;
  int _programmaticAnimToken = 0;
  bool _isWeeklyMode = false;
  bool _showFilterPanel = false;
  late final ValueNotifier<DateTime> _clockNotifier =
      ValueNotifier<DateTime>(_now());
  bool _isLoading = true;
  bool _isInitialLoadComplete = false;
  final Map<int, List<Lesson>> _weekLessonsCache = {};
  final Map<int, Future<void>> _inFlightWeekLoads = {};
  final Map<int, String> _weekErrors = {};
  final List<Homework> _extraHomeworks = [];
  final List<Test> _extraTests = [];
  Set<String> _fallbackCompletedHomeworkIds = <String>{};

  List<Homework> get _allHomeworks => [
        ...widget.homeworks,
        ..._extraHomeworks,
      ];

  List<Test> get _allTests {
    final byUid = <String, Test>{};
    final anon = <Test>[];
    for (final t in [..._extraTests, ...widget.tests]) {
      final uid = t.uid.trim();
      if (uid.isNotEmpty) {
        byUid.putIfAbsent(uid, () => t);
      } else {
        anon.add(t);
      }
    }
    return [...byUid.values, ...anon];
  }

  Homework? _resolveHomeworkForLesson(Lesson lesson) =>
      KretaClient.findHomeworkForLesson(lesson, _allHomeworks);

  String _resolveHomeworkKey(Lesson lesson, Homework? hw) {
    if (hw != null) return SettingsProvider.homeworkCompletionKey(hw);
    return lesson.homeworkUid?.trim() ?? '';
  }

  bool _isHomeworkCompleted(Lesson lesson, Homework? hw) {
    final key = _resolveHomeworkKey(lesson, hw);
    if (key.isEmpty) return false;
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      return scope.settings.isHomeworkKeyCompleted(key);
    }
    return _fallbackCompletedHomeworkIds.contains(key);
  }

  Future<void> _hydrateFallbackCompletedHomeworkIds() async {
    final ids = await SettingsProvider.loadCompletedHomeworkIdsFromPrefs();
    if (!mounted || ids.isEmpty) return;
    if (context.getInheritedWidgetOfExactType<AppProvidersScope>() != null) {
      return;
    }
    setState(() => _fallbackCompletedHomeworkIds = ids);
  }

  void _setLessonHomeworkCompletion(String key, bool completed) {
    if (key.isEmpty) return;
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      unawaited(scope.settings.setHomeworkKeyCompleted(key, completed));
      return;
    }
    final next = Set<String>.from(_fallbackCompletedHomeworkIds);
    final changed = completed ? next.add(key) : next.remove(key);
    if (!changed) return;
    setState(() => _fallbackCompletedHomeworkIds = next);
    unawaited(SettingsProvider.saveCompletedHomeworkIdsToPrefs(next));
  }

  void _toggleLessonHomework(Lesson lesson, Homework? hw) {
    final key = _resolveHomeworkKey(lesson, hw);
    if (key.isEmpty) return;
    HapticFeedback.selectionClick();
    final nextCompleted = !_isHomeworkCompleted(lesson, hw);
    _setLessonHomeworkCompletion(key, nextCompleted);
    if (!mounted) return;
    final rawSubj = lesson.subject?.name ?? lesson.name;
    final subjDisplay = widget.prefs.resolveSubjectName(
      rawSubj,
      lesson.subject?.uid,
    );
    TintaToast.dismissCurrent();
    if (nextCompleted) {
      TintaToast.success(
        context,
        uwu('Kész: $subjDisplay házi feladat'),
        duration: const Duration(seconds: 4),
        actionLabel: uwu('Visszavonás'),
        onAction: () {
          if (!mounted) return;
          _setLessonHomeworkCompletion(key, false);
        },
      );
    }
  }

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dayFormat = DateFormat('MM. dd.');

  DateTime _mondayOfWeekOffset(int weekOffset) => DateTime(
        _anchorMonday.year,
        _anchorMonday.month,
        _anchorMonday.day + (weekOffset * 7),
      );

  List<Lesson> _lessonsForWeekOffset(int weekOffset) {
    final cached = _weekLessonsCache[weekOffset];
    if (cached != null) return cached;
    if (weekOffset == 0 && widget.initialTodaysLessons.isNotEmpty) {
      return widget.initialTodaysLessons;
    }
    return const [];
  }

  bool _hasSaturdayLessonsForWeek(
    int weekOffset, {
    UserProfilePrefs? prefsOverride,
  }) {
    final cached = _weekLessonsCache[weekOffset];
    if (cached == null || cached.isEmpty) return false;
    final p = prefsOverride ?? widget.prefs;
    final monday = _mondayOfWeekOffset(weekOffset);
    final saturday = DateTime(monday.year, monday.month, monday.day + 5);
    final rawSat = cached
        .where((l) => _isSameDay(l.start.toLocal(), saturday))
        .toList();
    return filterLessonsForDisplay(
      rawSat,
      hideCancelled: p.hideCancelledLessons,
      hideFree: p.hideFreeLessons,
    ).isNotEmpty;
  }

  int _daysForWeekOffset(
    int weekOffset, {
    UserProfilePrefs? prefsOverride,
  }) {
    final p = prefsOverride ?? widget.prefs;
    if (p.showWeekends) return 7;
    return _hasSaturdayLessonsForWeek(weekOffset, prefsOverride: p) ? 6 : 5;
  }

  bool _hasAnyCachedSaturdayLessons({UserProfilePrefs? prefsOverride}) {
    for (final weekOffset in _weekLessonsCache.keys) {
      if (_hasSaturdayLessonsForWeek(weekOffset, prefsOverride: prefsOverride)) {
        return true;
      }
    }
    return false;
  }

  ({int weekOffset, int dayIndex}) _resolvePage(
    int page, {
    UserProfilePrefs? prefsOverride,
  }) {
    final p = prefsOverride ?? widget.prefs;
    if (p.showWeekends || !_hasAnyCachedSaturdayLessons(prefsOverride: p)) {
      return resolveTimetablePageOffset(
        page: page,
        basePage: _basePage,
        daysPerWeek: p.showWeekends ? 7 : 5,
      );
    }
    if (page >= _basePage) {
      int weekOffset = 0;
      int cursor = _basePage;
      while (true) {
        final span = _daysForWeekOffset(weekOffset, prefsOverride: p);
        if (cursor + span > page) {
          return (weekOffset: weekOffset, dayIndex: page - cursor);
        }
        cursor += span;
        weekOffset++;
      }
    } else {
      int weekOffset = -1;
      int cursor = _basePage - _daysForWeekOffset(-1, prefsOverride: p);
      while (cursor > page) {
        weekOffset--;
        cursor -= _daysForWeekOffset(weekOffset, prefsOverride: p);
      }
      return (weekOffset: weekOffset, dayIndex: page - cursor);
    }
  }

  int _mondayPageForWeekOffset(
    int weekOffset, {
    UserProfilePrefs? prefsOverride,
  }) {
    final p = prefsOverride ?? widget.prefs;
    if (p.showWeekends || !_hasAnyCachedSaturdayLessons(prefsOverride: p)) {
      final int daysPerWeek = p.showWeekends ? 7 : 5;
      return _basePage + (weekOffset * daysPerWeek);
    }
    int page = _basePage;
    if (weekOffset > 0) {
      for (int w = 0; w < weekOffset; w++) {
        page += _daysForWeekOffset(w, prefsOverride: p);
      }
    } else if (weekOffset < 0) {
      for (int w = -1; w >= weekOffset; w--) {
        page -= _daysForWeekOffset(w, prefsOverride: p);
      }
    }
    return page;
  }

  int _pageForWeekAndDay(
    int weekOffset,
    int dayIndex, {
    UserProfilePrefs? prefsOverride,
  }) {
    final span = _daysForWeekOffset(weekOffset, prefsOverride: prefsOverride);
    final clampedDay = dayIndex.clamp(0, span - 1);
    return (_mondayPageForWeekOffset(weekOffset, prefsOverride: prefsOverride) +
            clampedDay)
        .clamp(0, _totalPageCount - 1);
  }

  int _weekOffsetForMonday(DateTime targetMonday) {
    final anchorUtc = DateTime.utc(
      _anchorMonday.year,
      _anchorMonday.month,
      _anchorMonday.day,
    );
    final targetUtc = DateTime.utc(
      targetMonday.year,
      targetMonday.month,
      targetMonday.day,
    );
    return (targetUtc.difference(anchorUtc).inDays / 7).round();
  }

  DateTime get _currentDate {
    final pos = _resolvePage(_currentPage);
    final monday = _mondayOfWeekOffset(pos.weekOffset);
    return DateTime(monday.year, monday.month, monday.day + pos.dayIndex);
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = _now();
    var initialDay = DateUtils.dateOnly(now);
    final todaysEnded = widget.initialTodaysLessons.isNotEmpty &&
        widget.initialTodaysLessons
            .where((l) => !isLessonCancelled(l))
            .every((l) => !l.end.toLocal().isAfter(now));
    if (initialDay.weekday > 5) {
      // Weekend -> Monday.
      initialDay = DateTime(
        initialDay.year,
        initialDay.month,
        initialDay.day + (8 - initialDay.weekday),
      );
    } else if (!widget.prefs.demoModeEnabled &&
        (now.hour >= 18 || todaysEnded)) {
      // Evening / school day over -> tomorrow (Friday evening -> Monday).
      initialDay = DateTime(
        initialDay.year,
        initialDay.month,
        initialDay.day + (initialDay.weekday == 5 ? 3 : 1),
      );
    }
    _anchorMonday = _mondayOf(initialDay);
    final initialDayOffset = (initialDay.weekday - 1).clamp(
      0,
      widget.prefs.showWeekends ? 6 : 4,
    );
    _currentPage = _basePage + initialDayOffset;
    _pageController = PageController(initialPage: _currentPage);
    DemoDataService.instance.revision.addListener(_onDemoDataRevised);
    _hydrateFallbackCompletedHomeworkIds();
    _ensureWeekLoaded(0, isInitialLoad: true, prefetchNeighbors: true);
    // Updates only today's scoped lesson/break clock notifier without rebuilding
    // the full TimetableScreen tree or re-animating day pages.
    _minuteTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !widget.isActiveTab) return;
      final current = _now();
      if (_isSameDay(_currentDate, current)) {
        _clockNotifier.value = current;
      }
    });
  }

  void _onDemoDataRevised() {
    if (!mounted || !widget.prefs.demoModeEnabled) return;
    _reloadAfterSessionOrDemoSwitch(snapToTodayIfWeekday: true);
  }

  int _weekFetchGeneration = 0;

  void _reloadAfterSessionOrDemoSwitch({
    bool snapToTodayIfWeekday = false,
    bool fromDidUpdateWidget = false,
  }) {
    _weekFetchGeneration++;
    if (fromDidUpdateWidget) {
      _weekLessonsCache.clear();
      _inFlightWeekLoads.clear();
      _weekErrors.clear();
    } else {
      setState(() {
        _weekLessonsCache.clear();
        _inFlightWeekLoads.clear();
        _weekErrors.clear();
      });
    }
    if (snapToTodayIfWeekday) {
      final today = DateUtils.dateOnly(_now());
      if (today.weekday <= 5) {
        final targetMonday = _mondayOf(today);
        final weekOffset = _weekOffsetForMonday(targetMonday);
        final targetPage = _pageForWeekAndDay(weekOffset, today.weekday - 1);
        _currentPage = targetPage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(targetPage);
          }
        });
        _ensureWeekLoaded(
          weekOffset,
          forceRefresh: true,
          prefetchNeighbors: true,
        );
        return;
      }
    }
    final pos = _resolvePage(_currentPage);
    _ensureWeekLoaded(
      pos.weekOffset,
      forceRefresh: true,
      prefetchNeighbors: true,
    );
  }

  @override
  void didUpdateWidget(covariant TimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs.demoModeEnabled != widget.prefs.demoModeEnabled ||
        oldWidget.session.instituteCode != widget.session.instituteCode) {
      _reloadAfterSessionOrDemoSwitch(
        snapToTodayIfWeekday: widget.prefs.demoModeEnabled,
        fromDidUpdateWidget: true,
      );
    }
    if (!oldWidget.isActiveTab && widget.isActiveTab) {
      final current = _now();
      if (_isSameDay(_currentDate, current)) {
        _clockNotifier.value = current;
      }
    }
    if (oldWidget.isActiveTab && !widget.isActiveTab && _isWeeklyMode) {
      _applyOrientation(weeklyLandscape: false);
      widget.onImmersiveWeeklyModeChanged?.call(false);
    } else if (!oldWidget.isActiveTab && widget.isActiveTab && _isWeeklyMode) {
      _applyOrientation(weeklyLandscape: true);
      widget.onImmersiveWeeklyModeChanged?.call(true);
    }
    final prefsChanged =
        oldWidget.prefs.showWeekends != widget.prefs.showWeekends ||
            oldWidget.prefs.hideCancelledLessons !=
                widget.prefs.hideCancelledLessons ||
            oldWidget.prefs.hideFreeLessons != widget.prefs.hideFreeLessons;
    if (prefsChanged) {
      final prevPos = _resolvePage(
        _currentPage,
        prefsOverride: oldWidget.prefs,
      );
      final targetDayIdx = (!widget.prefs.showWeekends &&
              prevPos.dayIndex > _daysForWeekOffset(prevPos.weekOffset) - 1)
          ? 0
          : prevPos.dayIndex;
      final updatedPage = _pageForWeekAndDay(prevPos.weekOffset, targetDayIdx);
      if (updatedPage != _currentPage) {
        _currentPage = updatedPage;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _pageController.hasClients &&
              !_pageController.position.isScrollingNotifier.value) {
            _pageController.jumpToPage(updatedPage);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    DemoDataService.instance.revision.removeListener(_onDemoDataRevised);
    _minuteTicker?.cancel();
    _clockNotifier.dispose();
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
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentPage);
        }
      });
    }
    _applyOrientation(weeklyLandscape: weekly);
  }

  void _toggleShowWeekends() {
    HapticFeedback.lightImpact();
    final nextVal = !widget.prefs.showWeekends;
    widget.onPrefsChanged(widget.prefs.copyWith(showWeekends: nextVal));
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
    final base = AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    widget.onPrefsChanged(
      base.withExtra('hideFreeLessons', !base.hideFreeLessons),
    );
  }

  void _toggleShowTimetableExams() {
    HapticFeedback.lightImpact();
    final base = AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    widget.onPrefsChanged(
      base.withShowTimetableExams(!base.showTimetableExams),
    );
  }

  void _toggleShowTimetableHomework() {
    HapticFeedback.lightImpact();
    final base = AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    widget.onPrefsChanged(
      base.withShowTimetableHomework(!base.showTimetableHomework),
    );
  }

  DateTime _mondayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _handleTimetablePullToRefresh(int weekOffset) async {
    try {
      await _ensureWeekLoaded(
        weekOffset,
        prefetchNeighbors: true,
        forceRefresh: true,
      ).timeout(const Duration(seconds: 15));
      try {
        final freshTests = await widget.kretaClient
            .fetchTests(widget.session)
            .timeout(const Duration(seconds: 8));
        if (mounted && freshTests.isNotEmpty) {
          setState(() {
            _extraTests
              ..clear()
              ..addAll(freshTests);
          });
        }
      } catch (_) {
        // Keep existing tests visible if test fetch fails.
      }
    } catch (e) {
      if (mounted && (_weekLessonsCache[weekOffset]?.isNotEmpty ?? false)) {
        TintaToast.error(context, TintaErrorState.friendlyTitleFor(e));
      }
    } finally {
      _inFlightWeekLoads.remove(weekOffset);
      if (mounted && _isLoading) {
        setState(() {
          _isInitialLoadComplete = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _ensureWeekLoaded(
    int weekOffset, {
    bool isInitialLoad = false,
    bool prefetchNeighbors = false,
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _weekLessonsCache.containsKey(weekOffset)) {
      if (prefetchNeighbors) {
        _prefetchAdjacentWeeks(weekOffset);
      }
      return Future.value();
    }
    if (!forceRefresh) {
      final inFlight = _inFlightWeekLoads[weekOffset];
      if (inFlight != null) {
        if (prefetchNeighbors) {
          inFlight.whenComplete(() {
            if (mounted) _prefetchAdjacentWeeks(weekOffset);
          });
        }
        return inFlight.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            if (identical(_inFlightWeekLoads[weekOffset], inFlight)) {
              _inFlightWeekLoads.remove(weekOffset);
            }
          },
        );
      }
    } else {
      _inFlightWeekLoads.remove(weekOffset);
      _weekErrors.remove(weekOffset);
    }
    late final Future<void> future;
    future = _fetchWeekInternal(
      weekOffset,
      isInitialLoad: isInitialLoad,
      prefetchNeighbors: prefetchNeighbors,
    ).whenComplete(() {
      if (identical(_inFlightWeekLoads[weekOffset], future)) {
        _inFlightWeekLoads.remove(weekOffset);
      }
    });
    _inFlightWeekLoads[weekOffset] = future;
    return future;
  }

  void _prefetchAdjacentWeeks(int centerWeekOffset) {
    if (!mounted) return;
    // Asynchronously pre-fetch both adjacent weeks so bidirectional swiping
    // forward or backward renders immediately without blanking or stuttering.
    for (final neighbor in [centerWeekOffset - 1, centerWeekOffset + 1]) {
      if (!_weekLessonsCache.containsKey(neighbor) &&
          !_inFlightWeekLoads.containsKey(neighbor) &&
          !_weekErrors.containsKey(neighbor)) {
        unawaited(_ensureWeekLoaded(neighbor));
      }
    }
  }

  Future<void> _fetchWeekInternal(
    int weekOffset, {
    bool isInitialLoad = false,
    bool prefetchNeighbors = false,
  }) async {
    final fetchGen = _weekFetchGeneration;
    final monday = _mondayOfWeekOffset(weekOffset);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);

    try {
      final lessons = await widget.kretaClient
          .fetchTimetableForRange(
            widget.session,
            from: monday,
            to: sunday,
          )
          .timeout(const Duration(seconds: 14));
      if (!mounted || fetchGen != _weekFetchGeneration) return;

      final currentPos = _resolvePage(_currentPage);
      final ({int weekOffset, int dayIndex})? progPos =
          _programmaticTargetPage != null
              ? _resolvePage(_programmaticTargetPage!)
              : null;

      setState(() {
        _weekLessonsCache[weekOffset] = lessons;
        _weekErrors.remove(weekOffset);
        if (isInitialLoad || !_isInitialLoadComplete) {
          _isInitialLoadComplete = true;
          _isLoading = false;
        }
        final updatedPage = _pageForWeekAndDay(
          currentPos.weekOffset,
          currentPos.dayIndex,
        );
        if (updatedPage != _currentPage) {
          _currentPage = updatedPage;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _pageController.hasClients &&
                !_pageController.position.isScrollingNotifier.value) {
              _pageController.jumpToPage(updatedPage);
            }
          });
        }
        if (progPos != null) {
          _programmaticTargetPage = _pageForWeekAndDay(
            progPos.weekOffset,
            progPos.dayIndex,
          );
        }
      });

      if (weekOffset == 0 || weekOffset == 1) {
        unawaited(
          HomeWidgetSyncService.instance
              .syncFromLessons(
                lessons,
                prefs: widget.prefs,
                themeAccent: Theme.of(context).colorScheme.primary,
              )
              .catchError((_) => false),
        );
      }

      if (prefetchNeighbors) {
        _prefetchAdjacentWeeks(weekOffset);
      }

      // Hydrate any lesson homeworkUid not yet present in _allHomeworks
      final missingUids = <String>{};
      for (final lesson in lessons) {
        final hwUid = lesson.homeworkUid?.trim() ?? '';
        if (hwUid.isNotEmpty && _resolveHomeworkForLesson(lesson) == null) {
          missingUids.add(hwUid);
        }
      }
      if (missingUids.isNotEmpty) {
        final fetched = await Future.wait(
          missingUids.map(
            (uid) => widget.kretaClient
                .fetchHomeworkByUid(widget.session, uid)
                .catchError((_) => null),
          ),
        ).timeout(
          const Duration(seconds: 6),
          onTimeout: () => const <Homework?>[],
        );
        if (!mounted || fetchGen != _weekFetchGeneration) return;
        bool added = false;
        for (final hw in fetched) {
          if (hw != null &&
              !_allHomeworks.any((h) => h.uid == hw.uid || h.id == hw.id)) {
            _extraHomeworks.add(hw);
            added = true;
          }
        }
        if (added && mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (!mounted || fetchGen != _weekFetchGeneration) return;
      final cachedLessons = _weekLessonsCache[weekOffset];
      final hasCached = cachedLessons != null && cachedLessons.isNotEmpty;
      setState(() {
        if (!hasCached) {
          _weekErrors[weekOffset] = e.toString();
        } else {
          _weekErrors.remove(weekOffset);
        }
        if (isInitialLoad || !_isInitialLoadComplete) {
          _isInitialLoadComplete = true;
          _isLoading = false;
        }
      });
    } finally {
      if (mounted &&
          fetchGen == _weekFetchGeneration &&
          (isInitialLoad || !_isInitialLoadComplete) &&
          _isLoading) {
        setState(() {
          _isInitialLoadComplete = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _animateToPageSmooth(int targetPage) async {
    final clampedTarget = targetPage.clamp(0, _totalPageCount - 1);
    final token = ++_programmaticAnimToken;
    if (!mounted) return;
    setState(() {
      _currentPage = clampedTarget;
      _programmaticTargetPage = clampedTarget;
      _isAnimatingPage = _pageController.hasClients;
    });
    if (!_pageController.hasClients) {
      if (token == _programmaticAnimToken && mounted) {
        setState(() {
          _isAnimatingPage = false;
          _programmaticTargetPage = null;
        });
      }
      return;
    }
    final currentCtrlPage = _pageController.page?.round() ?? _currentPage;
    final distance = (clampedTarget - currentCtrlPage).abs();
    try {
      if (distance > 14) {
        _pageController.jumpToPage(clampedTarget);
      } else {
        await _pageController.animateToPage(
          clampedTarget,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      if (mounted && token == _programmaticAnimToken) {
        final corrected = _currentPage;
        setState(() {
          _isAnimatingPage = false;
          _programmaticTargetPage = null;
        });
        if (_pageController.hasClients &&
            (_pageController.page?.round() ?? corrected) != corrected) {
          _pageController.jumpToPage(corrected);
        }
      }
    }
  }

  void _shiftWeek(int deltaWeeks) {
    HapticFeedback.lightImpact();
    final currentPos = _resolvePage(_currentPage);
    final targetWeekOffset = currentPos.weekOffset + deltaWeeks;
    _ensureWeekLoaded(targetWeekOffset, prefetchNeighbors: true);
    final targetMondayPage = _mondayPageForWeekOffset(targetWeekOffset);
    unawaited(_animateToPageSmooth(targetMondayPage));
  }

  Future<void> _openDatePicker() async {
    HapticFeedback.lightImpact();
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final todayNow = _now();
    final picked = await _showTintaCalendarPicker(
      context: context,
      prefs: effectivePrefs,
      initialDate: _currentDate,
      today: DateTime(todayNow.year, todayNow.month, todayNow.day),
      firstDate: DateTime(2023, 9, 1),
      lastDate: DateTime(2030, 8, 31),
    );
    if (picked == null || !mounted) return;

    final target = DateTime(picked.year, picked.month, picked.day);
    final targetMonday = _mondayOf(target);
    final targetWeekOffset = _weekOffsetForMonday(targetMonday);
    unawaited(_ensureWeekLoaded(targetWeekOffset, prefetchNeighbors: true));

    final span = _daysForWeekOffset(targetWeekOffset);
    final targetDayIdx =
        (!widget.prefs.showWeekends && target.weekday > span)
            ? 0
            : (target.weekday - 1).clamp(0, span - 1);
    final targetPage = _pageForWeekAndDay(targetWeekOffset, targetDayIdx);
    await _animateToPageSmooth(targetPage);
  }

  Future<void> _jumpToToday() async {
    HapticFeedback.lightImpact();
    final now = _now();
    final today = DateTime(now.year, now.month, now.day);
    final targetMonday = _mondayOf(today);
    final targetWeekOffset = _weekOffsetForMonday(targetMonday);
    unawaited(_ensureWeekLoaded(targetWeekOffset, prefetchNeighbors: true));

    final span = _daysForWeekOffset(targetWeekOffset);
    final targetDayIdx =
        (!widget.prefs.showWeekends && today.weekday > span)
            ? 0
            : (today.weekday - 1).clamp(0, span - 1);
    final targetPage = _pageForWeekAndDay(targetWeekOffset, targetDayIdx);
    await _animateToPageSmooth(targetPage);
  }

  Future<void> _onSelectWeekdayPill(int idx, int weekOffset) async {
    final currentPos = _resolvePage(_currentPage);
    if (currentPos.weekOffset == weekOffset && currentPos.dayIndex == idx) {
      return;
    }
    HapticFeedback.selectionClick();
    final targetPage = _pageForWeekAndDay(weekOffset, idx);
    await _animateToPageSmooth(targetPage);
  }

  void _onPageSwiped(int pageIdx) {
    if (_isAnimatingPage &&
        _programmaticTargetPage != null &&
        pageIdx != _programmaticTargetPage) {
      return;
    }
    if (pageIdx == _currentPage) return;
    HapticFeedback.selectionClick();
    final pos = _resolvePage(pageIdx);
    setState(() {
      _currentPage = pageIdx;
    });
    _ensureWeekLoaded(pos.weekOffset, prefetchNeighbors: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scope = AppProvidersScope.maybeOf(context);
    if (scope != null) {
      return ListenableBuilder(
        listenable: scope.settings,
        builder: (context, _) =>
            _buildTimetableContent(context, scope.settings.prefs),
      );
    }
    return _buildTimetableContent(context, widget.prefs);
  }

  Widget _buildTimetableContent(
    BuildContext context,
    UserProfilePrefs effectivePrefs,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pos = _resolvePage(_currentPage);
    final mondayPage = _mondayPageForWeekOffset(pos.weekOffset);
    final monday = _mondayOfWeekOffset(pos.weekOffset);
    final visibleDaysCount = _daysForWeekOffset(pos.weekOffset);
    final endDay = DateTime(
      monday.year,
      monday.month,
      monday.day + visibleDaysCount - 1,
    );
    final currentWeekError =
        _weekLessonsCache.containsKey(pos.weekOffset)
            ? null
            : _weekErrors[pos.weekOffset];

    if (_isWeeklyMode) {
      return SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : currentWeekError != null &&
                            !_inFlightWeekLoads.containsKey(pos.weekOffset)
                        ? Center(
                            child: _buildErrorCard(
                              theme,
                              currentWeekError,
                              weekOffset: pos.weekOffset,
                            ),
                          )
                        : _buildWeeklyLandscapeBoard(
                            theme,
                            scheme,
                            monday,
                            pos.weekOffset,
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

    final min = MinimalistTokens.of(effectivePrefs);

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            min.horizontalPagePadding,
            min.enabled ? 0 : 2,
            min.horizontalPagePadding,
            0,
          ),
          child: Column(
            children: [
              _buildTopControlsCard(
                theme,
                scheme,
                effectivePrefs,
                monday,
                endDay,
                pos,
              ),
              SizedBox(height: min.enabled ? 3 : 4),
              _buildWeekdaySelector(
                theme,
                scheme,
                monday,
                pos.weekOffset,
                mondayPage,
                pos.dayIndex,
                visibleDaysCount,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: _showFilterPanel
                    ? Padding(
                        padding: EdgeInsets.only(top: min.enabled ? 4 : 5),
                        child: _buildExpandableFilterCard(
                          theme,
                          scheme,
                          effectivePrefs,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(height: min.enabled ? 1 : 2),
            ],
          ),
        ),
        Expanded(
          child: VerticalScrollEdgeFades(
            key: const ValueKey<String>('timetable-lesson-list-fade'),
            prefs: effectivePrefs,
            topHeaderHeight: 0.0,
            topFeatherHeight: min.enabled ? 14.0 : 24.0,
            bottomFadeHeight: 0.0,
            scrollDrivenTopFeather: true,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : pos.weekOffset == 0 &&
                        _weekLessonsCache.isEmpty &&
                        currentWeekError != null
                    ? Padding(
                        padding: EdgeInsets.all(min.horizontalPagePadding),
                        child: _buildErrorCard(
                          theme,
                          currentWeekError,
                          weekOffset: pos.weekOffset,
                        ),
                      )
                    : PageView.builder(
                        controller: _pageController,
                        physics: const PageScrollPhysics(),
                        allowImplicitScrolling: true,
                        itemCount: _totalPageCount,
                        onPageChanged: _onPageSwiped,
                        itemBuilder: (context, pageIdx) {
                          final pagePos = _resolvePage(pageIdx);
                          if (!_weekLessonsCache.containsKey(pagePos.weekOffset) &&
                              !_inFlightWeekLoads.containsKey(pagePos.weekOffset) &&
                              !_weekErrors.containsKey(pagePos.weekOffset)) {
                            Future.microtask(
                              () => _ensureWeekLoaded(pagePos.weekOffset),
                            );
                          }
                          final pageMonday =
                              _mondayOfWeekOffset(pagePos.weekOffset);
                          final day = DateTime(
                            pageMonday.year,
                            pageMonday.month,
                            pageMonday.day + pagePos.dayIndex,
                          );
                          final pageError =
                              _weekLessonsCache.containsKey(pagePos.weekOffset)
                                  ? null
                                  : _weekErrors[pagePos.weekOffset];
                          return _KeepAliveDayPage(
                            key: ValueKey<int>(pageIdx),
                            child: RefreshIndicator(
                              displacement: 44,
                              edgeOffset: 8,
                              strokeWidth: 2.6,
                              onRefresh: () => _handleTimetablePullToRefresh(
                                pagePos.weekOffset,
                              ),
                              child: ElasticOverscrollStretchWrapper(
                                child: pageError != null
                                    ? ListView(
                                        key: PageStorageKey<int>(pageIdx),
                                        primary: false,
                                        physics: const BouncingScrollPhysics(
                                          parent: AlwaysScrollableScrollPhysics(),
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          min.horizontalPagePadding,
                                          16,
                                          min.horizontalPagePadding,
                                          100,
                                        ),
                                        children: [
                                          _buildErrorCard(
                                            theme,
                                            pageError,
                                            weekOffset: pagePos.weekOffset,
                                          ),
                                        ],
                                      )
                                    : ListView(
                                        key: PageStorageKey<int>(pageIdx),
                                        primary: false,
                                        physics: const BouncingScrollPhysics(
                                          parent: AlwaysScrollableScrollPhysics(),
                                        ),
                                        padding: EdgeInsets.fromLTRB(
                                          min.horizontalPagePadding,
                                          0,
                                          min.horizontalPagePadding,
                                          100,
                                        ),
                                        children: _buildDailyList(
                                          theme,
                                          scheme,
                                          day,
                                          pagePos.weekOffset,
                                        ),
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  String _formatCompactWeekRange(DateTime monday, DateTime endDay) {
    final mMonth = monday.month.toString().padLeft(2, '0');
    final mDay = monday.day.toString().padLeft(2, '0');
    final eDay = endDay.day.toString().padLeft(2, '0');
    if (monday.month == endDay.month) {
      return '$mMonth.$mDay-$eDay.';
    }
    final eMonth = endDay.month.toString().padLeft(2, '0');
    return '$mMonth.$mDay-$eMonth.$eDay.';
  }

  Widget _buildWeekBubbleButton({
    required ThemeData theme,
    required ColorScheme scheme,
    required UserProfilePrefs prefs,
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final liquid = prefs.liquidGlassEnabled;
    final min = MinimalistTokens.of(prefs);
    final bubbleBorder = liquid
        ? Colors.white.withValues(alpha: isDark ? 0.20 : 0.48)
        : theme.dividerColor;

    return Tooltip(
      message: tooltip,
      child: TactileBounce(
        onTap: onTap,
        child: SoftGlassCard(
          prefs: prefs,
          padding: min.enabled
              ? const EdgeInsets.symmetric(horizontal: 7, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          borderRadius: BorderRadius.circular(min.enabled ? 11 : 20),
          border: Border.all(color: bubbleBorder, width: min.borderWidth),
          child: Icon(
            icon,
            size: min.enabled ? 16 : 18,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildTopControlsCard(
    ThemeData theme,
    ColorScheme scheme,
    UserProfilePrefs effectivePrefs,
    DateTime monday,
    DateTime endDay,
    ({int weekOffset, int dayIndex}) pos,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final liquid = effectivePrefs.liquidGlassEnabled;
    final min = MinimalistTokens.of(effectivePrefs);
    final selectedDay = DateTime(
      monday.year,
      monday.month,
      monday.day + pos.dayIndex,
    );
    final isViewingToday = _isSameDay(selectedDay, _now());

    final pillBorder = liquid
        ? Colors.white.withValues(alpha: isDark ? 0.20 : 0.46)
        : theme.dividerColor;
    final radius = BorderRadius.circular(min.enabled ? 11 : 20);
    final gap = min.enabled ? 4.0 : 6.0;

    return Row(
      children: [
        _buildWeekBubbleButton(
          theme: theme,
          scheme: scheme,
          prefs: effectivePrefs,
          tooltip: 'Előző hét',
          icon: Icons.chevron_left_rounded,
          onTap: () => _shiftWeek(-1),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Tooltip(
            message: uwu('Dátum választása'),
            child: TactileBounce(
              onTap: _openDatePicker,
              child: SoftGlassCard(
                prefs: effectivePrefs,
                padding: min.enabled
                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                borderRadius: radius,
                border: Border.all(color: pillBorder, width: min.borderWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.date_range_rounded,
                        size: min.enabled ? 12 : 14,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _formatCompactWeekRange(monday, endDay),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: min.enabled ? 11 : 12,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        _buildWeekBubbleButton(
          theme: theme,
          scheme: scheme,
          prefs: effectivePrefs,
          tooltip: 'Következő hét',
          icon: Icons.chevron_right_rounded,
          onTap: () => _shiftWeek(1),
        ),
        SizedBox(width: gap),
        Tooltip(
          message: uwu('Ugrás a mai napra'),
          child: TactileBounce(
            onTap: _jumpToToday,
            child: SoftGlassCard(
              prefs: effectivePrefs,
              color: isViewingToday
                  ? null
                  : (liquid
                      ? scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18)
                      : scheme.primary),
              padding: min.enabled
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              borderRadius: radius,
              border: Border.all(
                color: isViewingToday
                    ? pillBorder
                    : (liquid
                        ? scheme.primary.withValues(alpha: 0.65)
                        : scheme.primary),
                width: min.borderWidth,
              ),
              child: Text(
                'Ma',
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: min.enabled ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: isViewingToday
                      ? scheme.onSurface.withValues(alpha: 0.78)
                      : (liquid
                          ? (isDark ? Colors.white : scheme.primary)
                          : scheme.onPrimary),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        SoftGlassCard(
          prefs: effectivePrefs,
          padding: min.enabled
              ? const EdgeInsets.symmetric(horizontal: 3, vertical: 3)
              : const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          borderRadius: radius,
          border: Border.all(color: pillBorder, width: min.borderWidth),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCompactModeSegment(
                scheme: scheme,
                tooltip: uwu('Napi nézet'),
                icon: Icons.view_day_rounded,
                selected: !_isWeeklyMode,
                onTap: () => _setWeeklyMode(false),
              ),
              const SizedBox(width: 2),
              _buildCompactModeSegment(
                scheme: scheme,
                tooltip: uwu('Heti nézet'),
                icon: Icons.view_week_rounded,
                selected: _isWeeklyMode,
                onTap: () => _setWeeklyMode(true),
              ),
            ],
          ),
        ),
        SizedBox(width: gap),
        Tooltip(
          message: uwuLabel(
            'Órarend beállítások',
            enabled: effectivePrefs.uwuModeEnabled,
          ),
          child: TactileBounce(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _showFilterPanel = !_showFilterPanel);
            },
            child: SoftGlassCard(
              prefs: effectivePrefs,
              color: _showFilterPanel
                  ? (liquid
                      ? scheme.primary.withValues(alpha: isDark ? 0.28 : 0.18)
                      : scheme.primary)
                  : null,
              padding: min.enabled
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                  : const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              borderRadius: radius,
              border: Border.all(
                color: _showFilterPanel
                    ? (liquid
                        ? scheme.primary.withValues(alpha: 0.65)
                        : scheme.primary)
                    : pillBorder,
                width: min.borderWidth,
              ),
              child: Icon(
                Icons.tune_rounded,
                size: min.enabled ? 14 : 16,
                color: _showFilterPanel
                    ? (liquid
                        ? (isDark ? Colors.white : scheme.primary)
                        : scheme.onPrimary)
                    : scheme.onSurface,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandableFilterCard(
    ThemeData theme,
    ColorScheme scheme,
    UserProfilePrefs effectivePrefs,
  ) {
    final isDark = theme.brightness == Brightness.dark;
    final liquid = effectivePrefs.liquidGlassEnabled;
    final min = MinimalistTokens.of(effectivePrefs);
    return SoftGlassCard(
      prefs: effectivePrefs,
      isExpanded: false,
      color: liquid
          ? scheme.surfaceContainerHigh.withValues(alpha: isDark ? 0.62 : 0.78)
          : null,
      border: liquid
          ? Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.45),
              width: min.borderWidth,
            )
          : null,
      padding: min.enabled
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      borderRadius: BorderRadius.circular(min.enabled ? 11 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Elmaradó órák elrejtése',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: min.enabled ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: effectivePrefs.hideCancelledLessons,
            onChanged: (_) => _toggleHideCancelledLessons(),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Lyukas / szabad órák elrejtése',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: min.enabled ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: effectivePrefs.hideFreeLessons,
            onChanged: (_) => _toggleHideFreeLessons(),
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Hétvége mutatása',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: min.enabled ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: effectivePrefs.showWeekends,
            onChanged: (_) => _toggleShowWeekends(),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('timetable-toggle-show-exams'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Számonkérések mutatása az órarenden',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: min.enabled ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: effectivePrefs.showTimetableExams,
            onChanged: (_) => _toggleShowTimetableExams(),
          ),
          SwitchListTile.adaptive(
            key: const ValueKey<String>('timetable-toggle-show-homework'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              uwuLabel(
                'Házik mutatása az órarenden',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: TextStyle(
                fontSize: min.enabled ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            value: effectivePrefs.showTimetableHomework,
            onChanged: (_) => _toggleShowTimetableHomework(),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ActionChip(
                  avatar: const Icon(Icons.today_rounded, size: 16),
                  label: Text(
                    uwuLabel(
                      'Mai nap (Ma)',
                      enabled: effectivePrefs.uwuModeEnabled,
                    ),
                  ),
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
                  label: Text(
                    uwuLabel(
                      'Naptár...',
                      enabled: effectivePrefs.uwuModeEnabled,
                    ),
                  ),
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
    required String tooltip,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: TactileBounce(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 28,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(
            icon,
            size: 15,
            color: selected
                ? scheme.onPrimary
                : scheme.onSurface.withValues(alpha: 0.72),
          ),
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
    int weekOffset,
    int mondayPage,
    int selectedIdx,
    int visibleDaysCount,
  ) {
    final clampedIdx = selectedIdx.clamp(0, visibleDaysCount - 1);
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final min = MinimalistTokens.of(effectivePrefs);
    return LiquidBubbleTabBar(
      padding: EdgeInsets.zero,
      height: min.enabled ? 31 : 40,
      fontSize: min.enabled ? 10.5 : 12,
      itemPadding: min.enabled
          ? const EdgeInsets.symmetric(horizontal: 3, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      equalFlex: true,
      liquidGlassEnabled: effectivePrefs.liquidGlassEnabled,
      pageController: _pageController,
      pageOffset: mondayPage.toDouble(),
      ignorePageController: _isAnimatingPage,
      selectedIndex: clampedIdx,
      onSelected: (idx) => _onSelectWeekdayPill(idx, weekOffset),
      items: List.generate(visibleDaysCount, (idx) {
        final day = DateTime(monday.year, monday.month, monday.day + idx);
        return LiquidBubbleTabItem(
          key: ValueKey<String>('weekday-pill-$idx'),
          label: _weekdayShortNames[idx],
          subLabel: '${day.day}.',
          isHighlighted: _isSameDay(day, _now()),
        );
      }),
    );
  }

  List<Widget> _buildDailyList(
    ThemeData theme,
    ColorScheme scheme,
    DateTime day,
    int weekOffset,
  ) {
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final min = MinimalistTokens.of(effectivePrefs);
    final weekLessons = _lessonsForWeekOffset(weekOffset);
    final rawDayLessons = weekLessons
        .where((l) => _isSameDay(l.start.toLocal(), day))
        .toList();
    final dayLessons = filterLessonsForDisplay(
      rawDayLessons,
      hideCancelled: effectivePrefs.hideCancelledLessons,
      hideFree: effectivePrefs.hideFreeLessons,
    );
    final dayTests = effectivePrefs.showTimetableExams
        ? KretaClient.findTestsForDay(day, _allTests)
        : const <Test>[];
    final isWeekFetching = !_weekLessonsCache.containsKey(weekOffset) &&
        _inFlightWeekLoads.containsKey(weekOffset);

    final dayName = _weekdayFullNames[(day.weekday - 1).clamp(0, 6)];

    return [
      Padding(
        padding: EdgeInsets.fromLTRB(
          2,
          min.enabled ? 7 : 15,
          2,
          min.enabled ? 4 : 9,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                uwuLabel(
                  '$dayName • ${_dayFormat.format(day)}',
                  enabled: effectivePrefs.uwuModeEnabled,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: min.enabled ? 12 : 13.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            Text(
              uwuLabel(
                '${dayLessons.length} óra',
                enabled: effectivePrefs.uwuModeEnabled,
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: min.enabled ? 11 : null,
                color: scheme.onSurface.withValues(alpha: 0.52),
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
      if (dayLessons.isEmpty)
        isWeekFetching
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            : RepaintBoundary(
                child: _buildEmptyLessonsCard(theme, scheme),
              )
      else if (dayLessons.isNotEmpty && _isSameDay(day, _now()))
        _buildTodayLessonsColumn(theme, day, rawDayLessons, dayLessons, dayTests)
      else
        ...List.generate(dayLessons.length, (idx) {
          final lesson = dayLessons[idx];
          final hw = effectivePrefs.showTimetableHomework
              ? _resolveHomeworkForLesson(lesson)
              : null;
          final hwKey = hw != null ? _resolveHomeworkKey(lesson, hw) : '';
          final lessonTests = effectivePrefs.showTimetableExams
              ? KretaClient.findTestsForLesson(lesson, dayTests)
              : const <Test>[];
          final lessonOmission =
              KretaClient.findOmissionForLesson(lesson, widget.omissions);
          return buildOledLessonCard(
            context,
            theme,
            lesson,
            _timeFormat,
            prefs: effectivePrefs,
            homework: hw,
            isHomeworkCompleted: hw != null && _isHomeworkCompleted(lesson, hw),
            onToggleHomework: hwKey.isNotEmpty
                ? () => _toggleLessonHomework(lesson, hw)
                : null,
            tests: lessonTests,
            omission: lessonOmission,
          );
        }),
    ];
  }

  Widget _buildTodayLessonsColumn(
    ThemeData theme,
    DateTime day,
    List<Lesson> rawDayLessons,
    List<Lesson> dayLessons,
    List<Test> dayTests,
  ) {
    final activeDayLessons = dayLessons
        .where((l) => !isLessonCancelled(l) && !isInactivePlaceholderLesson(l))
        .toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    final breakPrevByNextUid = <String, Lesson>{};
    for (int i = 1; i < activeDayLessons.length; i++) {
      final prev = activeDayLessons[i - 1];
      final next = activeDayLessons[i];
      if (prev.end.toLocal().isBefore(next.start.toLocal())) {
        breakPrevByNextUid[next.uid] = prev;
      }
    }

    return ValueListenableBuilder<DateTime>(
      valueListenable: _clockNotifier,
      builder: (context, sampledNow, _) {
        final now = widget.clock?.call() ?? sampledNow;
        final countdownInfo = PeriodCountdownInfo.evaluate(
          rawDayLessons,
          now,
          onlyOnDate: day,
        );
        final activePrefs =
            AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lesson in dayLessons) ...[
              if (breakPrevByNextUid.containsKey(lesson.uid))
                _TimetableBreakSlot(
                  key: ValueKey<String>(
                    'break_${breakPrevByNextUid[lesson.uid]!.uid}_${lesson.uid}',
                  ),
                  breakStart: breakPrevByNextUid[lesson.uid]!.end.toLocal(),
                  breakEnd: lesson.start.toLocal(),
                  clockNotifier: _clockNotifier,
                  clock: widget.clock,
                  textTransform: uwu,
                ),
              Builder(
                builder: (context) {
                  final hw = activePrefs.showTimetableHomework
                      ? _resolveHomeworkForLesson(lesson)
                      : null;
                  final hwKey =
                      hw != null ? _resolveHomeworkKey(lesson, hw) : '';
                  final lessonTests = activePrefs.showTimetableExams
                      ? KretaClient.findTestsForLesson(lesson, dayTests)
                      : const <Test>[];
                  final lessonOmission = KretaClient.findOmissionForLesson(
                    lesson,
                    widget.omissions,
                  );
                  return buildOledLessonCard(
                    context,
                    theme,
                    lesson,
                    _timeFormat,
                    prefs: activePrefs,
                    homework: hw,
                    isHomeworkCompleted:
                        hw != null && _isHomeworkCompleted(lesson, hw),
                    onToggleHomework: hwKey.isNotEmpty
                        ? () => _toggleLessonHomework(lesson, hw)
                        : null,
                    tests: lessonTests,
                    omission: lessonOmission,
                    countdownInfo: countdownInfo,
                    nowOverride: now,
                    clock: widget.clock,
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  /// Ultra-compact, multi-column weekly grid fitted on-screen without vertical scrolling.
  Widget _buildWeeklyLandscapeBoard(
    ThemeData theme,
    ColorScheme scheme,
    DateTime monday,
    int weekOffset,
    int visibleDaysCount,
  ) {
    final weekLessons = _lessonsForWeekOffset(weekOffset);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(visibleDaysCount, (i) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        final rawDayLessons = weekLessons
            .where((l) => _isSameDay(l.start.toLocal(), day))
            .toList();
        final dayLessons = filterLessonsForDisplay(
          rawDayLessons,
          hideCancelled: widget.prefs.hideCancelledLessons,
          hideFree: widget.prefs.hideFreeLessons,
        );
        final isToday = _isSameDay(day, _now());

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
                        uwuLabel(
                          'Nincs óra',
                          enabled: widget.prefs.uwuModeEnabled,
                        ),
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
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final isPlaceholder = isInactivePlaceholderLesson(lesson);
    final isCancelled = isLessonCancelled(lesson) && !isPlaceholder;
    final hasSub = lesson.substituteTeacher != null &&
        lesson.substituteTeacher!.trim().isNotEmpty;
    final heroTag = 'weekly_lesson_num_${lesson.uid}';
    final rawSubject = lesson.subject?.name ?? lesson.name;
    final subjectDisplay =
        effectivePrefs.resolveSubjectName(rawSubject, lesson.subject?.uid);
    final homework = effectivePrefs.showTimetableHomework
        ? _resolveHomeworkForLesson(lesson)
        : null;
    final hasHomework = !isPlaceholder &&
        effectivePrefs.showTimetableHomework &&
        (homework != null ||
            (lesson.homeworkUid != null &&
                lesson.homeworkUid!.trim().isNotEmpty));
    final lessonTests = effectivePrefs.showTimetableExams && !isPlaceholder
        ? KretaClient.findTestsForLesson(lesson, _allTests)
        : const <Test>[];
    final hasExam = lessonTests.isNotEmpty;
    final lessonOmission = !isPlaceholder
        ? KretaClient.findOmissionForLesson(lesson, widget.omissions)
        : null;
    final omissionColor = lessonOmission == null
        ? null
        : switch (lessonOmission.state) {
            OmissionState.excused => OledTheme.omissionExcusedColor(theme.brightness),
            OmissionState.unexcused =>
              OledTheme.omissionUnexcusedRedColor(theme.brightness),
            OmissionState.pending ||
            OmissionState.unknown =>
              OledTheme.omissionPendingOrangeColor(theme.brightness),
          };

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showLessonInspectionModal(
          context,
          lesson,
          heroTag: heroTag,
          prefs: effectivePrefs,
          homework: homework,
          omission: lessonOmission,
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
                  : omissionColor != null
                      ? omissionColor.withValues(alpha: 0.78)
                      : hasExam
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.72)
                          : hasSub
                              ? const Color(0xFFF9A825)
                              : hasHomework
                                  ? const Color(0xFF00BFA5).withValues(alpha: 0.65)
                                  : theme.dividerColor,
              width: 0.8,
            ),
          ),
          child: Row(
            children: [
              if (lesson.lessonNumber != null)
                if (!isPlaceholder)
                  Hero(
                    tag: heroTag,
                    createRectTween: createLinearHeroRectTween,
                    flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(
                        '${lesson.lessonNumber}. ',
                        style: TextStyle(
                          fontSize: 10,
                          color: isCancelled
                              ? OledTheme.semanticForeground(
                                  const Color(0xFFEF5350),
                                  theme.brightness,
                                )
                              : hasSub
                                  ? OledTheme.semanticForeground(
                                      const Color(0xFFF59E0B),
                                      theme.brightness,
                                    )
                                  : scheme.primary,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    '${lesson.lessonNumber}. ',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurface.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              Expanded(
                child: Text(
                  uwuLabel(subjectDisplay, enabled: effectivePrefs.uwuModeEnabled),
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
              if (hasExam)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.assignment_late_rounded,
                    size: 10,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              if (hasHomework)
                const Padding(
                  padding: EdgeInsets.only(right: 3),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 10,
                    color: Color(0xFF00BFA5),
                  ),
                ),
              if (lesson.roomName != null &&
                  lesson.roomName!.trim().isNotEmpty &&
                  !isPlaceholder)
                Text(
                  uwuLabel(
                    lesson.roomName!,
                    enabled: effectivePrefs.uwuModeEnabled,
                  ),
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
              uwu(
                'Erre a napra nincs rögzített tanóra.',
                enabled: widget.prefs.uwuModeEnabled,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(ThemeData theme, String error, {int? weekOffset}) {
    return TintaErrorState(
      error: error,
      prefs: widget.prefs,
      onRetry: () {
        final targetWeek = weekOffset ?? _resolvePage(_currentPage).weekOffset;
        unawaited(_ensureWeekLoaded(targetWeek, forceRefresh: true));
      },
    );
  }
}

class _KeepAliveDayPage extends StatefulWidget {
  final Widget child;
  const _KeepAliveDayPage({super.key, required this.child});

  @override
  State<_KeepAliveDayPage> createState() => _KeepAliveDayPageState();
}

class _KeepAliveDayPageState extends State<_KeepAliveDayPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Manages smooth 320ms Curves.easeOutCubic enter/exit height+fade+scale
/// transitions ONLY when a break starts or ends live, while mounting already
/// settled (`value: 1.0`) when swiping onto a day that is already in a break.
class _TimetableBreakSlot extends StatefulWidget {
  final DateTime breakStart;
  final DateTime breakEnd;
  final ValueListenable<DateTime> clockNotifier;
  final DateTime Function()? clock;
  final String Function(String) textTransform;

  const _TimetableBreakSlot({
    super.key,
    required this.breakStart,
    required this.breakEnd,
    required this.clockNotifier,
    required this.textTransform,
    this.clock,
  });

  @override
  State<_TimetableBreakSlot> createState() => _TimetableBreakSlotState();
}

class _TimetableBreakSlotState extends State<_TimetableBreakSlot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enterCtrl;
  late final Animation<double> _curved;
  late final Animation<double> _scaleAnim;
  late bool _isActive;

  bool _isInBreakAt(DateTime now) {
    final local = now.toLocal();
    return !local.isBefore(widget.breakStart) &&
        local.isBefore(widget.breakEnd);
  }

  DateTime _sampleNow() => widget.clock?.call() ?? widget.clockNotifier.value;

  @override
  void initState() {
    super.initState();
    _isActive = _isInBreakAt(_sampleNow());
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: _isActive ? 1.0 : 0.0,
    );
    _curved = CurvedAnimation(
      parent: _enterCtrl,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(_curved);
    widget.clockNotifier.addListener(_handleClockTick);
  }

  @override
  void didUpdateWidget(covariant _TimetableBreakSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clockNotifier != widget.clockNotifier) {
      oldWidget.clockNotifier.removeListener(_handleClockTick);
      widget.clockNotifier.addListener(_handleClockTick);
    }
    _syncBreakState();
  }

  void _handleClockTick() => _syncBreakState();

  void _syncBreakState() {
    final nextActive = _isInBreakAt(_sampleNow());
    if (nextActive == _isActive) return;
    _isActive = nextActive;
    if (_isActive) {
      _enterCtrl.forward();
    } else {
      _enterCtrl.reverse();
    }
  }

  @override
  void dispose() {
    widget.clockNotifier.removeListener(_handleClockTick);
    _enterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) {
        if (_enterCtrl.value <= 0.0 && !_isActive) {
          return const SizedBox.shrink();
        }
        return ClipRect(
          child: SizeTransition(
            sizeFactor: _curved,
            alignment: AlignmentDirectional.topCenter,
            child: FadeTransition(
              opacity: _curved,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: child,
              ),
            ),
          ),
        );
      },
      child: ValueListenableBuilder<DateTime>(
        valueListenable: widget.clockNotifier,
        builder: (context, sampledNow, _) => BreakCountdownCard(
          breakStart: widget.breakStart,
          breakEnd: widget.breakEnd,
          now: widget.clock?.call() ?? sampledNow,
          clock: widget.clock,
          textTransform: widget.textTransform,
        ),
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
  Homework? homework,
  bool isHomeworkCompleted = false,
  VoidCallback? onToggleHomework,
  List<Test> tests = const [],
  Omission? omission,
  PeriodCountdownInfo? countdownInfo,
  DateTime? nowOverride,
  DateTime Function()? clock,
}) {
  final min = MinimalistTokens.of(prefs);
  final scheme = theme.colorScheme;
  final isPlaceholder = isInactivePlaceholderLesson(lesson);
  final isCancelled = isLessonCancelled(lesson) && !isPlaceholder;
  final hasSubstitute = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;
  final showHomework = prefs?.showTimetableHomework ?? true;
  final showExams = prefs?.showTimetableExams ?? true;
  final hasHomework = !isPlaceholder &&
      showHomework &&
      (homework != null ||
          (lesson.homeworkUid != null &&
              lesson.homeworkUid!.trim().isNotEmpty));
  final hasExam = !isPlaceholder && showExams && tests.isNotEmpty;

  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();

  final cancelledRed = OledTheme.semanticForeground(
    const Color(0xFFEF5350),
    theme.brightness,
  );
  final substituteAmber = OledTheme.semanticForeground(
    const Color(0xFFF59E0B),
    theme.brightness,
  );
  final effectiveOmission = isPlaceholder ? null : omission;
  final omissionIsLate = effectiveOmission != null &&
      OmissionsSummary.isTardiness(effectiveOmission);
  final omissionStatusText = effectiveOmission == null
      ? ''
      : switch (effectiveOmission.state) {
          OmissionState.excused => 'Igazolt',
          OmissionState.unexcused => 'Igazolatlan',
          OmissionState.pending || OmissionState.unknown => 'Igazolandó',
        };
  final omissionColor = effectiveOmission == null
      ? null
      : switch (effectiveOmission.state) {
          OmissionState.excused =>
            OledTheme.omissionExcusedColor(theme.brightness),
          OmissionState.unexcused =>
            OledTheme.omissionUnexcusedRedColor(theme.brightness),
          OmissionState.pending ||
          OmissionState.unknown =>
            OledTheme.omissionPendingOrangeColor(theme.brightness),
        };
  final badgeAccent = isCancelled
      ? cancelledRed
      : omissionColor ??
          (hasSubstitute ? substituteAmber : scheme.primary);
  final isLightMode = theme.brightness == Brightness.light;
  final badgeBg = isPlaceholder
      ? scheme.surfaceContainerHigh.withValues(alpha: 0.35)
      : (isLightMode
          ? OledTheme.semanticBadgeBg(badgeAccent, theme.brightness)
          : badgeAccent.withValues(alpha: 0.14));
  final badgeBorderColor = isPlaceholder
      ? theme.dividerColor.withValues(alpha: 0.5)
      : (isLightMode
          ? OledTheme.semanticBadgeBorder(badgeAccent, theme.brightness)
          : badgeAccent.withValues(alpha: 0.24));
  final badgeTextColor = isPlaceholder
      ? scheme.onSurface.withValues(alpha: 0.42)
      : badgeAccent;

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

  final nowLocal = (nowOverride ?? DateTime.now()).toLocal();
  final showsCountdownRing = !isPlaceholder &&
      !isCancelled &&
      countdownInfo != null &&
      countdownInfo.phase == PeriodCountdownPhase.ongoing &&
      countdownInfo.targetLesson.uid == lesson.uid;
  final countdownFraction =
      showsCountdownRing ? countdownInfo.remainingFraction : null;
  final ringColor = hasSubstitute ? substituteAmber : scheme.primary;

  final effectiveTeacher = hasSubstitute && subTeacherDisplay != null
      ? subTeacherDisplay.trim()
      : (teacherDisplay?.trim() ?? '');
  final cleanRoom = (lesson.roomName ?? '').trim();
  final trimmedTopic = lesson.theme?.trim() ?? '';
  final metaParts = <String>[
    if (!isPlaceholder && cleanRoom.isNotEmpty) cleanRoom,
    if (effectiveTeacher.isNotEmpty) effectiveTeacher,
    if (cleanRoom.isEmpty &&
        effectiveTeacher.isEmpty &&
        trimmedTopic.isNotEmpty &&
        trimmedTopic != subjectDisplay)
      OledTheme.capitalizeFirst(trimmedTopic),
  ];
  final metadataLine = metaParts.join(' • ');

  final Widget card = TactileBounce(
    pressedScale: 0.97,
    onTap: () => showLessonInspectionModal(
      context,
      lesson,
      heroTag: heroTag,
      prefs: prefs,
      homework: showHomework ? homework : null,
      isHomeworkCompleted: showHomework && isHomeworkCompleted,
      omission: effectiveOmission,
    ),
    child: ChristmasSnowCap(
      enabled: prefs?.christmasModeEnabled == true,
      child: SoftGlassCard(
        prefs: prefs ?? const UserProfilePrefs(),
        padding: min.enabled
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        color: isPlaceholder
            ? theme.cardTheme.color?.withValues(alpha: 0.45)
            : null,
        borderRadius: min.enabled ? min.cardRadius : BorderRadius.circular(16),
        border: Border.all(
          color: isPlaceholder
              ? theme.dividerColor.withValues(alpha: 0.45)
              : isCancelled
                  ? cancelledRed.withValues(alpha: 0.45)
                  : omissionColor != null
                      ? omissionColor.withValues(alpha: 0.56)
                      : hasSubstitute
                          ? substituteAmber.withValues(alpha: 0.45)
                          : (hasExam
                              ? substituteAmber.withValues(alpha: 0.42)
                              : theme.dividerColor),
          width: min.borderWidth,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Hero(
              tag: heroTag,
              createRectTween: createLinearHeroRectTween,
              flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
              child: Material(
                type: MaterialType.transparency,
                child: PeriodCountdownBadge(
                  label: lesson.lessonNumber != null
                      ? '${lesson.lessonNumber}.'
                      : '•',
                  backgroundColor: badgeBg,
                  textStyle: TextStyle(
                    fontSize: min.enabled ? 11.5 : 13.5,
                    fontWeight: FontWeight.w700,
                    color: badgeTextColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  ringColor: ringColor,
                  remainingFraction: countdownFraction,
                  startTime: showsCountdownRing ? startLocal : null,
                  endTime: showsCountdownRing ? endLocal : null,
                  now: showsCountdownRing ? nowLocal : null,
                  clock: showsCountdownRing ? clock : null,
                  idleShape: BoxShape.circle,
                  idleSize: min.enabled ? 28 : 38,
                  outerSize: min.enabled ? 32 : 44,
                  innerSize: min.enabled ? 24 : 34,
                  border: Border.all(color: badgeBorderColor, width: 1.0),
                ),
              ),
            ),
            SizedBox(width: min.enabled ? 9 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          uwuLabel(
                            subjectDisplay,
                            enabled: prefs?.uwuModeEnabled,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: min.enabled ? 12.8 : 14.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: (isCancelled || isPlaceholder)
                                ? scheme.onSurface.withValues(alpha: 0.48)
                                : scheme.onSurface,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                            decorationColor: isCancelled ? cancelledRed : null,
                            decorationThickness: isCancelled ? 1.8 : null,
                          ),
                        ),
                      ),
                      if (isCancelled || isPlaceholder) ...[
                        SizedBox(width: min.enabled ? 5 : 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: min.enabled ? 5 : 7,
                            vertical: min.enabled ? 1.5 : 2,
                          ),
                          decoration: BoxDecoration(
                            color: isPlaceholder
                                ? scheme.surfaceContainerHigh
                                : cancelledRed.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              min.enabled ? 5 : 7,
                            ),
                            border: Border.all(
                              color: isPlaceholder
                                  ? theme.dividerColor
                                  : cancelledRed.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Text(
                            uwuLabel(
                              isPlaceholder ? 'Nincs óra' : 'Elmarad',
                              enabled: prefs?.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: min.enabled ? 9 : 10,
                              fontWeight: FontWeight.w700,
                              color: isPlaceholder
                                  ? scheme.onSurface.withValues(alpha: 0.58)
                                  : cancelledRed,
                            ),
                          ),
                        ),
                      ] else ...[
              if (hasExam) ...[
                          SizedBox(width: min.enabled ? 5 : 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => showTestInspectionModal(
                              context,
                              tests.first,
                              heroTag: 'lesson_exam_${tests.first.uid}',
                              prefs: prefs,
                            ),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: min.enabled ? 5 : 7,
                                vertical: min.enabled ? 1.5 : 2.5,
                              ),
                              decoration: BoxDecoration(
                                color: substituteAmber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  min.enabled ? 5 : 7,
                                ),
                                border: Border.all(
                                  color: substituteAmber.withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.assignment_late_rounded,
                                    size: min.enabled ? 10 : 11.5,
                                    color: substituteAmber,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    uwuLabel(
                                      tests.length > 1
                                          ? 'Számonkérés (${tests.length})'
                                          : 'Számonkérés',
                                      enabled: prefs?.uwuModeEnabled,
                                    ),
                                    style: TextStyle(
                                      fontSize: min.enabled ? 9 : 10,
                                      fontWeight: FontWeight.w700,
                                      color: substituteAmber,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        if (hasHomework) ...[
                          SizedBox(width: min.enabled ? 5 : 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onToggleHomework,
                            child: Opacity(
                              opacity: isHomeworkCompleted ? 0.58 : 1.0,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: min.enabled ? 5 : 7,
                                  vertical: min.enabled ? 1.5 : 2.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF00BFA5)
                                      .withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(
                                    min.enabled ? 5 : 7,
                                  ),
                                  border: Border.all(
                                    color: const Color(0xFF00BFA5)
                                        .withValues(alpha: 0.42),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isHomeworkCompleted
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: min.enabled ? 10 : 11.5,
                                      color: const Color(0xFF00BFA5),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      uwuLabel(
                                        'Házi',
                                        enabled: prefs?.uwuModeEnabled,
                                      ),
                                      style: TextStyle(
                                        fontSize: min.enabled ? 9 : 10,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF00BFA5),
                                        decoration: isHomeworkCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                  if (metadataLine.isNotEmpty) ...[
                    SizedBox(height: min.enabled ? 1.5 : 3),
                    Row(
                      children: [
                        if (hasSubstitute)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.swap_horiz_rounded,
                              size: min.enabled ? 11.5 : 13,
                              color: substituteAmber,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            uwuLabel(
                              metadataLine,
                              enabled: prefs?.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: min.enabled ? 10.5 : 12,
                              fontWeight: hasSubstitute
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: hasSubstitute
                                  ? substituteAmber
                                  : scheme.onSurface.withValues(alpha: 0.58),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (effectiveOmission != null && omissionColor != null) ...[
                    SizedBox(height: min.enabled ? 3 : 5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        key: ValueKey<String>(
                          'timetable-lesson-omission-${lesson.uid}',
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: min.enabled ? 6 : 8,
                          vertical: min.enabled ? 1.5 : 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: omissionColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            min.enabled ? 5 : 7,
                          ),
                          border: Border.all(
                            color: omissionColor.withValues(alpha: 0.42),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              omissionIsLate
                                  ? Icons.schedule_rounded
                                  : Icons.event_busy_rounded,
                              size: min.enabled ? 10 : 11.5,
                              color: omissionColor,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                uwuLabel(
                                  omissionIsLate
                                      ? 'Késés${(effectiveOmission.lateForMin ?? 0) > 0 ? ' (${effectiveOmission.lateForMin}p)' : ''} • $omissionStatusText'
                                      : 'Hiányzás • $omissionStatusText',
                                  enabled: prefs?.uwuModeEnabled,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: min.enabled ? 9.5 : 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: omissionColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: min.enabled ? 8 : 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeFormat.format(startLocal),
                  style: TextStyle(
                    fontSize: min.enabled ? 11 : 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                    color: (isCancelled || isPlaceholder)
                        ? scheme.onSurface.withValues(alpha: 0.42)
                        : scheme.onSurface.withValues(alpha: 0.90),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  timeFormat.format(endLocal),
                  style: TextStyle(
                    fontSize: min.enabled ? 9.8 : 11,
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                    color: (isCancelled || isPlaceholder)
                        ? scheme.onSurface.withValues(alpha: 0.30)
                        : scheme.onSurface.withValues(alpha: 0.45),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return RepaintBoundary(
    child: Padding(
      padding: EdgeInsets.only(bottom: min.cardGap),
      child: card,
    ),
  );
}

Future<DateTime?> _showTintaCalendarPicker({
  required BuildContext context,
  required UserProfilePrefs prefs,
  required DateTime initialDate,
  required DateTime today,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showTintaDatePickerSheet(
    context: context,
    prefs: prefs,
    initialDate: initialDate,
    today: today,
    firstDate: firstDate,
    lastDate: lastDate,
  );
}
