import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/period_countdown_badge.dart';

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
  final List<Homework> homeworks;
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

  List<Homework> get _allHomeworks => [
        ...widget.homeworks,
        ..._extraHomeworks,
      ];

  Homework? _resolveHomeworkForLesson(Lesson lesson) =>
      KretaClient.findHomeworkForLesson(lesson, _allHomeworks);

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dayFormat = DateFormat('MM. dd.');
  final DateFormat _fullDateFormat = DateFormat('yyyy. MM. dd.');

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
    } else if (now.hour >= 18 || todaysEnded) {
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

  @override
  void didUpdateWidget(covariant TimetableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    widget.onPrefsChanged(
      widget.prefs.withExtra('hideFreeLessons', !widget.prefs.hideFreeLessons),
    );
  }

  DateTime _mondayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day - (date.weekday - 1));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    final inFlight = _inFlightWeekLoads[weekOffset];
    if (inFlight != null) {
      if (prefetchNeighbors) {
        inFlight.whenComplete(() {
          if (mounted) _prefetchAdjacentWeeks(weekOffset);
        });
      }
      return inFlight;
    }
    if (forceRefresh) {
      _weekErrors.remove(weekOffset);
    }
    final future = _fetchWeekInternal(
      weekOffset,
      isInitialLoad: isInitialLoad,
      prefetchNeighbors: prefetchNeighbors,
    );
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
    final monday = _mondayOfWeekOffset(weekOffset);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);

    try {
      final lessons = await widget.kretaClient.fetchTimetableForRange(
        widget.session,
        from: monday,
        to: sunday,
      );
      _inFlightWeekLoads.remove(weekOffset);
      if (!mounted) return;

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
            (uid) => widget.kretaClient.fetchHomeworkByUid(widget.session, uid),
          ),
        );
        if (!mounted) return;
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
      _inFlightWeekLoads.remove(weekOffset);
      if (!mounted) return;
      setState(() {
        _weekErrors[weekOffset] = e.toString();
        if (isInitialLoad || !_isInitialLoadComplete) {
          _isInitialLoadComplete = true;
          _isLoading = false;
        }
      });
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentDate,
      firstDate: DateTime(2023, 9, 1),
      lastDate: DateTime(2030, 8, 31),
      helpText: 'Ugrás kiválasztott dátumra',
      cancelText: 'Mégse',
      confirmText: 'Ugrás',
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
                        ? Center(child: _buildErrorCard(theme, currentWeekError))
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            children: [
              _buildTopControlsCard(theme, scheme, monday, endDay),
              const SizedBox(height: 6),
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
              : pos.weekOffset == 0 &&
                      _weekLessonsCache.isEmpty &&
                      currentWeekError != null
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildErrorCard(theme, currentWeekError),
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
                            onRefresh: () => _ensureWeekLoaded(
                              pagePos.weekOffset,
                              prefetchNeighbors: true,
                              forceRefresh: true,
                            ),
                            child: pageError != null
                                ? ListView(
                                    key: PageStorageKey<int>(pageIdx),
                                    primary: false,
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      16,
                                      16,
                                      100,
                                    ),
                                    children: [_buildErrorCard(theme, pageError)],
                                  )
                                : ListView(
                                    key: PageStorageKey<int>(pageIdx),
                                    primary: false,
                                    physics: const BouncingScrollPhysics(
                                      parent: AlwaysScrollableScrollPhysics(),
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      2,
                                      16,
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
    int weekOffset,
    int mondayPage,
    int selectedIdx,
    int visibleDaysCount,
  ) {
    final clampedIdx = selectedIdx.clamp(0, visibleDaysCount - 1);
    final effectivePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    return LiquidBubbleTabBar(
      padding: EdgeInsets.zero,
      height: 40,
      fontSize: 12,
      itemPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
    final weekLessons = _lessonsForWeekOffset(weekOffset);
    final rawDayLessons = weekLessons
        .where((l) => _isSameDay(l.start.toLocal(), day))
        .toList();
    final dayLessons = filterLessonsForDisplay(
      rawDayLessons,
      hideCancelled: widget.prefs.hideCancelledLessons,
      hideFree: widget.prefs.hideFreeLessons,
    );
    final isWeekFetching = !_weekLessonsCache.containsKey(weekOffset) &&
        _inFlightWeekLoads.containsKey(weekOffset);

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
        isWeekFetching
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            : RepaintBoundary(
                child: _buildEmptyLessonsCard(theme, scheme),
              )
      else if (_isSameDay(day, _now()))
        _buildTodayLessonsColumn(theme, day, rawDayLessons, dayLessons)
      else
        ...List.generate(dayLessons.length, (idx) {
          final lesson = dayLessons[idx];
          return buildOledLessonCard(
            context,
            theme,
            lesson,
            _timeFormat,
            prefs: widget.prefs,
            homework: _resolveHomeworkForLesson(lesson),
          );
        }),
    ];
  }

  Widget _buildTodayLessonsColumn(
    ThemeData theme,
    DateTime day,
    List<Lesson> rawDayLessons,
    List<Lesson> dayLessons,
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
              buildOledLessonCard(
                context,
                theme,
                lesson,
                _timeFormat,
                prefs: widget.prefs,
                homework: _resolveHomeworkForLesson(lesson),
                countdownInfo: countdownInfo,
                nowOverride: now,
                clock: widget.clock,
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
    final heroTag = 'weekly_lesson_num_${lesson.uid}';
    final rawSubject = lesson.subject?.name ?? lesson.name;
    final subjectDisplay =
        widget.prefs.resolveSubjectName(rawSubject, lesson.subject?.uid);
    final homework = _resolveHomeworkForLesson(lesson);
    final hasHomework = !isPlaceholder &&
        (homework != null ||
            (lesson.homeworkUid != null &&
                lesson.homeworkUid!.trim().isNotEmpty));

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showLessonInspectionModal(
          context,
          lesson,
          heroTag: heroTag,
          prefs: widget.prefs,
          homework: homework,
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
                      : hasHomework
                          ? const Color(0xFF00BFA5).withValues(alpha: 0.65)
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
                            : widget.prefs.timetablePeriodColor != null
                                ? OledTheme.readableInlineColor(
                                    widget.prefs.timetablePeriodColor!,
                                    theme.brightness,
                                  )
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
  PeriodCountdownInfo? countdownInfo,
  DateTime? nowOverride,
  DateTime Function()? clock,
}) {
  final scheme = theme.colorScheme;
  final isPlaceholder = isInactivePlaceholderLesson(lesson);
  final isCancelled = isLessonCancelled(lesson) && !isPlaceholder;
  final hasSubstitute = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;
  final hasHomework = !isPlaceholder &&
      (homework != null ||
          (lesson.homeworkUid != null &&
              lesson.homeworkUid!.trim().isNotEmpty));
  final hwSummary = homework != null
      ? Homework.stripHtmlTags(homework.description)
      : '';

  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();
  final timeRange =
      '${timeFormat.format(startLocal)} - ${timeFormat.format(endLocal)}';

  final customPeriodColor = prefs?.timetablePeriodColor;
  final badgeBg = isPlaceholder
      ? scheme.surfaceContainerHigh.withValues(alpha: 0.45)
      : isCancelled
          ? const Color(0xFFC62828)
          : hasSubstitute
              ? const Color(0xFFF9A825)
              : (customPeriodColor ?? scheme.surfaceContainerHigh);

  final badgeTextColor = isPlaceholder
      ? scheme.onSurface.withValues(alpha: 0.45)
      : isCancelled
          ? Colors.white
          : hasSubstitute
              ? Colors.black
              : (customPeriodColor != null
                  ? OledTheme.contrastTextFor(customPeriodColor)
                  : scheme.onSurface);

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
  final isOngoing = !isPlaceholder &&
      !isCancelled &&
      !nowLocal.isBefore(startLocal) &&
      nowLocal.isBefore(endLocal);
  final showsCountdownRing = !isPlaceholder &&
      !isCancelled &&
      countdownInfo != null &&
      countdownInfo.phase == PeriodCountdownPhase.ongoing &&
      countdownInfo.targetLesson.uid == lesson.uid;
  final countdownFraction =
      showsCountdownRing ? countdownInfo.remainingFraction : null;
  final ringColor = hasSubstitute
      ? const Color(0xFFF9A825)
      : (customPeriodColor != null
          ? OledTheme.readableInlineColor(
              customPeriodColor,
              theme.brightness,
            )
          : scheme.primary);

  Widget card = TactileBounce(
      pressedScale: 0.97,
      onTap: () => showLessonInspectionModal(
        context,
        lesson,
        heroTag: heroTag,
        prefs: prefs,
        homework: homework,
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
                  child: PeriodCountdownBadge(
                    label: lesson.lessonNumber != null
                        ? '${lesson.lessonNumber}.'
                        : '•',
                    backgroundColor: badgeBg,
                    textStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: badgeTextColor,
                    ),
                    ringColor: ringColor,
                    remainingFraction: countdownFraction,
                    startTime: showsCountdownRing ? startLocal : null,
                    endTime: showsCountdownRing ? endLocal : null,
                    now: showsCountdownRing ? nowLocal : null,
                    clock: showsCountdownRing ? clock : null,
                    border: Border.all(
                      color: (!isPlaceholder &&
                              !isCancelled &&
                              !hasSubstitute &&
                              customPeriodColor != null)
                          ? OledTheme.contrastTextFor(customPeriodColor)
                              .withValues(alpha: 0.22)
                          : theme.dividerColor,
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
                        ] else if (hasHomework) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00BFA5)
                                  .withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF00BFA5)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.menu_book_rounded,
                                  size: 10.5,
                                  color: Color(0xFF00BFA5),
                                ),
                                SizedBox(width: 3),
                                Text(
                                  'Házi',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF00BFA5),
                                  ),
                                ),
                              ],
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
                    if (hasHomework && hwSummary.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.menu_book_rounded,
                            size: 11.5,
                            color: Color(0xFF00BFA5),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              hwSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF00BFA5),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  return RepaintBoundary(
    child: Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: card,
    ),
  );
}
