import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/calendar_sync_service.dart';
import '../services/demo_data_service.dart';
import '../services/github_updater_service.dart';
import '../services/home_widget_sync_service.dart';
import '../services/kreta_client.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/expandable_profile_card.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/menetrend_hero_card.dart';
import '../widgets/skeleton_shimmer.dart';
import '../widgets/tinta_toast.dart';
import 'grades_screen.dart';
import 'more_screen.dart';
import 'timetable_screen.dart';

/// Filter categories for the unified Főoldal activity feed.
enum ActivityFeedFilter {
  all('Összes', Icons.view_stream_rounded),
  grades('Jegyek', Icons.star_rounded),
  homeworks('Házik', Icons.menu_book_rounded),
  tests('Számonkérések', Icons.assignment_late_rounded);

  final String label;
  final IconData icon;
  const ActivityFeedFilter(this.label, this.icon);
}

/// State machine output for the 'Következő óra' (Next Lesson) Hero Card.
enum NextLessonPhase {
  ongoing,
  beforeFirstWithinTwoHours,
  beforeFirstFarAway,
  betweenLessons,
  completedForToday,
}

class NextLessonStatus {
  final NextLessonPhase phase;
  final Lesson? targetLesson;
  final Lesson? upcomingLesson;
  final Lesson? previousLesson;
  final String headline;
  final String countdownLabel;
  final int remainingLessonsCount;
  final int totalLessonsCount;
  final double remainingFraction;
  final int remainingMinutes;

  const NextLessonStatus({
    required this.phase,
    required this.targetLesson,
    this.upcomingLesson,
    this.previousLesson,
    required this.headline,
    required this.countdownLabel,
    required this.remainingLessonsCount,
    required this.totalLessonsCount,
    this.remainingFraction = 1.0,
    this.remainingMinutes = 0,
  });

  static String formatRemainingLessonsLabel(int remaining) {
    if (remaining <= 0) return 'Ma már nincs több órád!';
    if (remaining == 1) return 'Már csak 1 órád van hátra';
    return 'Még $remaining órád van hátra';
  }

  static String formatFirstLessonCountdown(Duration remaining) {
    if (remaining.isNegative || remaining == Duration.zero) {
      return 'Kezdés: hamarosan';
    }
    final totalSeconds = remaining.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours >= 1) {
      return 'Kezdés: $hoursó ${minutes}p ${seconds}mp';
    }
    return 'Kezdés: ${minutes}p ${seconds}mp';
  }

  /// Evaluates the 'Következő óra' card state machine comparing local
  /// `KezdetIdopont` (`lesson.start.toLocal()`) and `VegIdopont` (`lesson.end.toLocal()`)
  /// against [now], normalized by [DateUtils.dateOnly].
  static NextLessonStatus evaluate(
    List<Lesson> lessons,
    DateTime now, {
    UserProfilePrefs? prefs,
  }) {
    final localNow = now.toLocal();
    final todayDate = DateUtils.dateOnly(localNow);
    final todaysMatches = lessons
        .where((l) => DateUtils.dateOnly(l.start.toLocal()) == todayDate)
        .toList();
    final scopedLessons = todaysMatches.isNotEmpty ? todaysMatches : lessons;
    final activeLessons = scopedLessons
        .where((l) => !isLessonCancelled(l))
        .toList()
      ..sort((a, b) => a.start.toLocal().compareTo(b.start.toLocal()));

    final totalCount = activeLessons.length;
    final remainingLessons = activeLessons
        .where((l) => l.end.toLocal().isAfter(localNow))
        .toList();
    final remainingCount = remainingLessons.length;

    final countdown = PeriodCountdownInfo.evaluate(activeLessons, localNow);

    if (totalCount == 0 || remainingCount == 0) {
      return NextLessonStatus(
        phase: NextLessonPhase.completedForToday,
        targetLesson: null,
        headline: 'Mára vége az óráknak!',
        countdownLabel: 'Mára vége az óráknak!',
        remainingLessonsCount: 0,
        totalLessonsCount: totalCount,
        remainingFraction: 0.0,
      );
    }

    // 1. Check if currently between start and end of any lesson (start <= now < end)
    for (int i = 0; i < activeLessons.length; i++) {
      final lesson = activeLessons[i];
      final startLocal = lesson.start.toLocal();
      final endLocal = lesson.end.toLocal();
      if (!localNow.isBefore(startLocal) && localNow.isBefore(endLocal)) {
        final rawSubj = lesson.subject?.name ?? lesson.name;
        final subjName = prefs != null
            ? prefs.resolveSubjectName(rawSubj, lesson.subject?.uid)
            : rawSubj;
        final minsLeft = endLocal.difference(localNow).inMinutes.clamp(1, 999);
        final totalSecs = endLocal.difference(startLocal).inSeconds;
        final remSecs = endLocal.difference(localNow).inSeconds;
        final remFraction = countdown?.phase == PeriodCountdownPhase.ongoing
            ? countdown!.remainingFraction
            : (totalSecs > 0 ? (remSecs / totalSecs).clamp(0.0, 1.0) : 0.0);
        final nextUp = (i + 1 < activeLessons.length)
            ? activeLessons[i + 1]
            : null;
        return NextLessonStatus(
          phase: NextLessonPhase.ongoing,
          targetLesson: lesson,
          upcomingLesson: nextUp,
          headline: 'Folyamatban lévő óra: $subjName',
          countdownLabel: 'Még $minsLeft perc',
          remainingLessonsCount: remainingCount,
          totalLessonsCount: totalCount,
          remainingFraction: remFraction,
          remainingMinutes: minsLeft,
        );
      }
    }

    // 2. Check if before the very first lesson of today
    final firstLesson = activeLessons.first;
    final firstStartLocal = firstLesson.start.toLocal();
    if (localNow.isBefore(firstStartLocal)) {
      final diff = firstStartLocal.difference(localNow);
      final rawSubj = firstLesson.subject?.name ?? firstLesson.name;
      final subjName = prefs != null
          ? prefs.resolveSubjectName(rawSubj, firstLesson.subject?.uid)
          : rawSubj;
      final countdownStr = formatFirstLessonCountdown(diff);

      return NextLessonStatus(
        phase: diff <= const Duration(hours: 2)
            ? NextLessonPhase.beforeFirstWithinTwoHours
            : NextLessonPhase.beforeFirstFarAway,
        targetLesson: firstLesson,
        headline: subjName,
        countdownLabel: countdownStr,
        remainingLessonsCount: remainingCount,
        totalLessonsCount: totalCount,
        remainingFraction: countdown?.remainingFraction ?? 1.0,
      );
    }

    // Between lessons during the school day
    final nextLesson = remainingLessons.first;
    final nextStartLocal = nextLesson.start.toLocal();
    final minsUntilNext =
        nextStartLocal.difference(localNow).inMinutes.clamp(1, 999);
    final rawSubj = nextLesson.subject?.name ?? nextLesson.name;
    final subjName = prefs != null
        ? prefs.resolveSubjectName(rawSubj, nextLesson.subject?.uid)
        : rawSubj;

    return NextLessonStatus(
      phase: NextLessonPhase.betweenLessons,
      targetLesson: nextLesson,
      previousLesson: countdown?.previousLesson,
      headline: subjName,
      countdownLabel: 'Szünet • $minsUntilNext perc múlva kezdődik',
      remainingLessonsCount: remainingCount,
      totalLessonsCount: totalCount,
      remainingFraction: countdown?.remainingFraction ?? 0.0,
    );
  }
}

class HomeActivityItem {
  final DateTime sortDate;
  final Grade? grade;
  final Homework? homework;
  final Test? test;

  HomeActivityItem.grade(Grade this.grade)
      : sortDate = grade.recordedAt,
        homework = null,
        test = null;

  /// Homeworks are grouped and sorted on Főoldal strictly by their deadline
  /// (`HataridoDatuma` -> `dueDate`), so upcoming deadlines appear at the very
  /// top above "Ma", nearest deadline first.
  HomeActivityItem.homework(Homework this.homework)
      : sortDate = homework.dueDate,
        grade = null,
        test = null;

  HomeActivityItem.test(Test this.test)
      : sortDate = test.date,
        grade = null,
        homework = null;

  bool matchesFilter(ActivityFeedFilter filter) {
    switch (filter) {
      case ActivityFeedFilter.all:
        return true;
      case ActivityFeedFilter.grades:
        return grade != null;
      case ActivityFeedFilter.homeworks:
        return homework != null;
      case ActivityFeedFilter.tests:
        return test != null;
    }
  }

  String get uniqueKey {
    if (grade != null) return 'g-${grade!.uid}';
    if (homework != null) return 'hw-${homework!.uid}';
    return 't-${test!.uid}';
  }
}

/// Groups Főoldal feed items into calendar day buckets relative to [today].
///
/// Future-dated sections (upcoming exams & future homework deadlines) are
/// placed first above "Ma" ordered nearest-date-first; "Ma" and past dates
/// follow below in reverse chronological order.
List<({DateTime day, List<HomeActivityItem> items})> groupHomeActivityItemsByDay(
  List<HomeActivityItem> items,
  DateTime today,
) {
  final normalizedToday = DateUtils.dateOnly(today);
  final byDay = <DateTime, List<HomeActivityItem>>{};
  for (final item in items) {
    final day = DateUtils.dateOnly(item.sortDate.toLocal());
    byDay.putIfAbsent(day, () => <HomeActivityItem>[]).add(item);
  }

  final futureDays = <DateTime>[];
  final currentAndPastDays = <DateTime>[];
  for (final day in byDay.keys) {
    if (day.isAfter(normalizedToday)) {
      futureDays.add(day);
    } else {
      currentAndPastDays.add(day);
    }
  }

  futureDays.sort((a, b) => a.compareTo(b));
  currentAndPastDays.sort((a, b) => b.compareTo(a));

  final groups = <({DateTime day, List<HomeActivityItem> items})>[];
  for (final day in futureDays) {
    final dayItems = byDay[day]!
      ..sort((a, b) {
        final aLesson = a.test?.lessonNumber;
        final bLesson = b.test?.lessonNumber;
        if (aLesson != null && bLesson != null) {
          final cmp = aLesson.compareTo(bLesson);
          if (cmp != 0) return cmp;
        }
        return a.sortDate.compareTo(b.sortDate);
      });
    groups.add((day: day, items: dayItems));
  }
  for (final day in currentAndPastDays) {
    final dayItems = byDay[day]!
      ..sort((a, b) => b.sortDate.compareTo(a.sortDate));
    groups.add((day: day, items: dayItems));
  }
  return groups;
}

class _KeepAliveTabWrapper extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabWrapper({super.key, required this.child});

  @override
  State<_KeepAliveTabWrapper> createState() => _KeepAliveTabWrapperState();
}

class _KeepAliveTabWrapperState extends State<_KeepAliveTabWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _PreClassCountdownBanner extends StatefulWidget {
  final DateTime targetStartLocal;
  final String Function(String) textTransform;
  final VoidCallback? onReachedStart;
  final DateTime Function()? clock;

  const _PreClassCountdownBanner({
    required this.targetStartLocal,
    required this.textTransform,
    this.onReachedStart,
    this.clock,
  });

  @override
  State<_PreClassCountdownBanner> createState() =>
      _PreClassCountdownBannerState();
}

class _PreClassCountdownBannerState extends State<_PreClassCountdownBanner>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _auraCtrl;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  AppLifecycleState? _lifecycleState;
  bool _notifiedStart = false;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _auraCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _refreshRemaining(notifyParent: false);
  }

  void _syncActiveControllers() {
    if (!mounted) return;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final appActive = _lifecycleState == null ||
        _lifecycleState == AppLifecycleState.resumed;
    final shouldRun =
        tickerEnabled && appActive && _remaining > Duration.zero;

    if (shouldRun) {
      if (!_auraCtrl.isAnimating) {
        _auraCtrl.repeat(reverse: true);
      }
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _refreshRemaining(notifyParent: true);
      });
    } else {
      _auraCtrl.stop();
      _timer?.cancel();
      _timer = null;
    }
  }

  void _refreshRemaining({required bool notifyParent}) {
    final now = widget.clock?.call() ?? DateTime.now();
    final diff = widget.targetStartLocal.difference(now);
    final clamped = diff.isNegative ? Duration.zero : diff;
    if (notifyParent && mounted) {
      setState(() => _remaining = clamped);
    } else {
      _remaining = clamped;
    }
    if (clamped <= Duration.zero) {
      _timer?.cancel();
      _timer = null;
      _auraCtrl.stop();
      if (notifyParent && !_notifiedStart) {
        _notifiedStart = true;
        widget.onReachedStart?.call();
      }
    } else {
      _notifiedStart = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActiveControllers();
  }

  @override
  void didUpdateWidget(covariant _PreClassCountdownBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetStartLocal != widget.targetStartLocal) {
      _notifiedStart = false;
      _refreshRemaining(notifyParent: false);
    }
    _syncActiveControllers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _refreshRemaining(notifyParent: true);
    }
    _syncActiveControllers();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _auraCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final formatted = widget.textTransform(
      NextLessonStatus.formatFirstLessonCountdown(_remaining),
    );
    const windowSecs = 7200.0; // 2-hour morning pre-class progress horizon.
    final progress = _remaining <= Duration.zero
        ? 1.0
        : (1.0 - (_remaining.inSeconds / windowSecs)).clamp(0.08, 1.0);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _auraCtrl,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_auraCtrl.value);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment(-1.0 + t * 0.6, -1.0),
                end: Alignment(1.0, 1.0 - t * 0.4),
                colors: [
                  accent.withValues(alpha: (isDark ? 0.16 : 0.11) + t * 0.08),
                  scheme.surfaceContainerHigh,
                  accent.withValues(alpha: (isDark ? 0.10 : 0.06) + t * 0.05),
                ],
              ),
              border: Border.all(
                color: accent.withValues(alpha: 0.28 + t * 0.26),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.10 + t * 0.14),
                  blurRadius: 12 + t * 6,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wb_twilight_rounded,
                    size: 16,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatted,
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                          fontFeatures: const [
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                backgroundColor:
                    scheme.onSurface.withValues(alpha: isDark ? 0.12 : 0.09),
                valueColor: AlwaysStoppedAnimation<Color>(accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingStatusDot extends StatefulWidget {
  final Color color;
  const _PulsingStatusDot({required this.color});

  @override
  State<_PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<_PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      if (!_ctrl.isAnimating) _ctrl.repeat(reverse: true);
    } else {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_ctrl.value);
          return Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.color.withValues(alpha: 0.65 + t * 0.35),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.35 + t * 0.4),
                  blurRadius: 4 + t * 4,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Main authenticated shell for Tinta Napló with:
/// 1. Dynamic time-based Hungarian greeting + sleek top-right `CircleAvatar`
///    action in the AppBar (opening the streamlined Profile & Settings sheet).
/// 2. Android predictive back / `PopScope` handling: pressing back on Jegyek,
///    Órarend, or Továbbiak returns to Főoldal (tab index 0).
/// 3. 'Következő óra' (Next Lesson) live hero card with local DateTime state machine.
/// 4. Minimalist Icon-Only Floating Dock with fluid sliding pill indicator.
class HomeScreen extends StatefulWidget {
  final StoredSession initialSession;
  final DashboardData? initialCachedData;
  final KretaClient kretaClient;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;
  final DateTime Function()? clock;

  const HomeScreen({
    super.key,
    required this.initialSession,
    this.initialCachedData,
    required this.kretaClient,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
    this.clock,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  late final PageController _tabPageController =
      PageController(initialPage: _selectedIndex);
  final int _tabSwitchEpoch = 0;
  bool _homeInitialEntrancePlayed = false;
  bool _homeEntranceActive = false;
  ActivityFeedFilter _feedFilter = ActivityFeedFilter.all;
  bool _isImmersiveWeeklyMode = false;

  late StoredSession _session;
  DashboardData? _data;
  StoredSession? _realSessionBackup;
  DashboardData? _realDataBackup;
  bool _lastDemoModeActive = false;
  SettingsProvider? _settingsProvider;
  bool _isLoading = true;
  String? _error;
  Timer? _countdownTimer;
  final ValueNotifier<int> _countdownTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _commuteTick = ValueNotifier<int>(0);
  bool? _lastCommuteWindow;
  bool? _lastTickedCommuteWindow;
  int? _lastCommuteMinuteBucket;
  DateTime _lastCommuteSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasInitialCommuteSynced = false;
  bool _hasPushedWearProfileMetadata = false;
  Set<String> _fallbackCompletedHomeworkIds = <String>{};

  final DateFormat _timeFormat = DateFormat('HH:mm');

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastDemoModeActive = widget.prefs.demoModeEnabled;
    if (!DemoDataService.isDemoSession(widget.initialSession)) {
      _realSessionBackup = widget.initialSession;
    }
    if (widget.initialCachedData != null &&
        !DemoDataService.isDemoSession(widget.initialCachedData!.activeSession)) {
      _realDataBackup = widget.initialCachedData;
    }
    if (_lastDemoModeActive) {
      _session = DemoDataService.instance.buildDemoSession(
        nowOverride: widget.clock?.call(),
      );
      _data = DemoDataService.instance.buildDashboardData(
        nowOverride: widget.clock?.call(),
      );
    } else {
      _session = widget.initialSession;
      _data = widget.initialCachedData;
    }
    _isLoading = _data == null;
    DemoDataService.instance.revision.addListener(_onDemoRevisionChanged);
    HomeWidgetSyncService.instance.openTimetableSignal
        .addListener(_onOpenTimetableSignal);
    _hydrateFallbackCompletedHomeworkIds();
    if (_data != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_activePrefs.demoModeEnabled) {
          AppProvidersScope.maybeOf(context)
              ?.settings
              .ingestGrades(_data!.allGrades);
        }
        if (!_hasInitialCommuteSynced) {
          _maybeSyncCommuteOnTick(forceWindowCheck: true);
        }
        _syncHomeWidgetsFromDashboard(_data!);
      });
    }
    _loadDashboard(silentIfCached: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GitHubUpdaterService.checkForUpdates(context, manual: false);
        unawaited(_checkPendingOpenTimetableTab());
      }
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _maybeSyncCommuteOnTick();
      if (_selectedIndex == 0 && (_data?.todaysLessons.isNotEmpty ?? false)) {
        _countdownTick.value++;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSettings = AppProvidersScope.maybeOf(context)?.settings;
    if (_settingsProvider != nextSettings) {
      _settingsProvider?.removeListener(_onSettingsChangedForDemo);
      _settingsProvider = nextSettings;
      _settingsProvider?.addListener(_onSettingsChangedForDemo);
    }
  }

  void _onSettingsChangedForDemo() {
    if (!mounted) return;
    final enabled = _activePrefs.demoModeEnabled;
    if (enabled != _lastDemoModeActive) {
      _applyDemoModeTransition(enabled);
    }
  }

  void _onDemoRevisionChanged() {
    if (!mounted || !_activePrefs.demoModeEnabled) return;
    final nextData = DemoDataService.instance.buildDashboardData(
      nowOverride: widget.clock?.call(),
    );
    setState(() {
      _session = nextData.activeSession;
      _data = nextData;
      _messagesOverride = null;
      _isLoading = false;
      _error = null;
    });
    _syncHomeWidgetsFromDashboard(nextData, forceUpcomingRefresh: true);
  }

  void _applyDemoModeTransition(bool enabled) {
    HomeWidgetSyncService.instance.clearMemoryCache();
    if (enabled) {
      if (!DemoDataService.isDemoSession(_session)) {
        _realSessionBackup = _session;
      }
      if (_data != null &&
          !DemoDataService.isDemoSession(_data!.activeSession)) {
        _realDataBackup = _data;
      }
      final demoData = DemoDataService.instance.buildDashboardData(
        nowOverride: widget.clock?.call(),
      );
      setState(() {
        _lastDemoModeActive = true;
        _session = demoData.activeSession;
        _data = demoData;
        _messagesOverride = null;
        _isLoading = false;
        _error = null;
      });
      _syncHomeWidgetsFromDashboard(demoData, forceUpcomingRefresh: true);
    } else {
      final restoredSession = _realSessionBackup ?? widget.initialSession;
      final restoredData = _realDataBackup;
      setState(() {
        _lastDemoModeActive = false;
        _session = restoredSession;
        _data = restoredData;
        _messagesOverride = null;
        _isLoading = restoredData == null;
        _error = null;
      });
      if (restoredData != null) {
        _syncHomeWidgetsFromDashboard(restoredData, forceUpcomingRefresh: true);
      }
      unawaited(_loadDashboard(silentIfCached: true));
    }
  }

  void _onOpenTimetableSignal() {
    if (!mounted) return;
    _openTimetableFromNative();
  }

  Future<void> _checkPendingOpenTimetableTab() async {
    final openTimetable =
        await HomeWidgetSyncService.instance.consumePendingOpenTimetableTab();
    if (openTimetable && mounted) {
      _openTimetableFromNative();
    }
  }

  void _openTimetableFromNative() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectBottomTab(_timetableTabIndex);
  }

  void _syncHomeWidgetsFromDashboard(
    DashboardData data, {
    bool forceUpcomingRefresh = false,
  }) {
    if (!mounted) return;
    unawaited(
      HomeWidgetSyncService.instance.syncFromDashboard(
        dashboard: data,
        kretaClient: widget.kretaClient,
        prefs: _activePrefs,
        themeAccent: Theme.of(context).colorScheme.primary,
        nowOverride: widget.clock?.call(),
        forceUpcomingRefresh: forceUpcomingRefresh,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _maybeSyncCommuteOnTick(forceWindowCheck: true);
      unawaited(_checkPendingOpenTimetableTab());
    }
  }

  void _maybeSyncCommuteOnTick({bool forceWindowCheck = false}) {
    final data = _data;
    if (data == null) return;
    final lessons = data.todaysLessons;
    final prefs = _activePrefs;
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    final now = _now();

    if (!prefs.transitCardEnabled || !prefs.transitConfigured) {
      if (scope != null) {
        scope.commute.revalidateForNow(now, todaysLessons: lessons);
      } else if (_commuteEval != null || _commuteLoading) {
        setState(() {
          _commuteEval = null;
          _commuteLoading = false;
        });
      }
      return;
    }

    final currentWindow = MenetrendService.commuteWindowForLessons(
      now: now,
      lessons: lessons,
    );
    if (scope != null) {
      scope.commute.revalidateForNow(now, todaysLessons: lessons);
    } else if (_commuteEval != null) {
      final nextEval = MenetrendService.filterVisibleEvaluation(
        evaluation: _commuteEval,
        todaysLessons: lessons,
        prefs: prefs,
        now: now,
      );
      final changed = nextEval == null ||
          !_commuteEval!.isMeaningfullyEqual(nextEval) ||
          _commuteEval!.minutesUntilDeparture != nextEval.minutesUntilDeparture ||
          _commuteEval!.minutesUntilWalkStart != nextEval.minutesUntilWalkStart;
      if (changed) {
        setState(() => _commuteEval = nextEval);
      }
    }

    final minuteBucket = now.millisecondsSinceEpoch ~/ 60000;
    if (minuteBucket != _lastCommuteMinuteBucket ||
        currentWindow != _lastTickedCommuteWindow) {
      _lastCommuteMinuteBucket = minuteBucket;
      _lastTickedCommuteWindow = currentWindow;
      _commuteTick.value++;
    }

    final windowChanged =
        !_hasInitialCommuteSynced || currentWindow != _lastCommuteWindow;
    final stalePeriod = now.difference(_lastCommuteSyncAt).abs() >=
        const Duration(seconds: 60);
    if (windowChanged ||
        (forceWindowCheck && stalePeriod) ||
        (currentWindow != null && stalePeriod)) {
      _lastCommuteWindow = currentWindow;
      _lastCommuteSyncAt = now;
      _hasInitialCommuteSynced = true;
      unawaited(_refreshCommute(allowDelayNotifications: windowChanged));
    }
  }

  Widget _maybeHomeEntrance(Widget child, int index, {Key? key}) =>
      child.staggeredEntrance(
        index,
        animationKey: key,
        enabled: _homeEntranceActive,
      );

  UserProfilePrefs get _activePrefs {
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    return scope?.settings.prefs ?? widget.prefs;
  }

  Future<void> _hydrateFallbackCompletedHomeworkIds() async {
    final ids = await SettingsProvider.loadCompletedHomeworkIdsFromPrefs();
    if (!mounted || ids.isEmpty) return;
    if (context.getInheritedWidgetOfExactType<AppProvidersScope>() != null) {
      return;
    }
    setState(() => _fallbackCompletedHomeworkIds = ids);
  }

  bool _isHomeworkCompleted(Homework homework) {
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      return scope.settings.isHomeworkCompleted(homework);
    }
    return _fallbackCompletedHomeworkIds
        .contains(SettingsProvider.homeworkCompletionKey(homework));
  }

  void _setHomeworkCompletionState(Homework homework, bool completed) {
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      unawaited(scope.settings.setHomeworkCompleted(homework, completed));
      return;
    }
    final key = SettingsProvider.homeworkCompletionKey(homework);
    final next = Set<String>.from(_fallbackCompletedHomeworkIds);
    final changed = completed ? next.add(key) : next.remove(key);
    if (!changed) return;
    setState(() => _fallbackCompletedHomeworkIds = next);
    unawaited(SettingsProvider.saveCompletedHomeworkIdsToPrefs(next));
  }

  void _toggleHomeworkCompletion(Homework homework, String subjectTitle) {
    HapticFeedback.selectionClick();
    final nextCompleted = !_isHomeworkCompleted(homework);
    _setHomeworkCompletionState(homework, nextCompleted);
    if (!mounted) return;
    TintaToast.dismissCurrent();
    if (nextCompleted) {
      TintaToast.success(
        context,
        uwu('Kész: $subjectTitle házi feladat'),
        duration: const Duration(seconds: 4),
        actionLabel: uwu('Visszavonás'),
        onAction: () {
          if (!mounted) return;
          _setHomeworkCompletionState(homework, false);
        },
      );
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefs.demoModeEnabled != _lastDemoModeActive) {
      _applyDemoModeTransition(widget.prefs.demoModeEnabled);
    }
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      // CommuteProvider listens to SettingsProvider directly and handles both
      // instant local recalculation (e.g. walking speed) and non-spammy sync.
      return;
    }

    final oldP = oldWidget.prefs;
    final newP = widget.prefs;
    if (oldP == newP) return;

    final transitEnabledOrConfiguredChanged =
        oldP.transitCardEnabled != newP.transitCardEnabled ||
            oldP.transitHomeStation != newP.transitHomeStation ||
            oldP.transitSchoolStation != newP.transitSchoolStation ||
            oldP.transitAllowTrain != newP.transitAllowTrain ||
            oldP.transitAllowCoach != newP.transitAllowCoach ||
            oldP.transitAllowLocalBus != newP.transitAllowLocalBus ||
            oldP.homeAddress != newP.homeAddress ||
            oldP.schoolAddress != newP.schoolAddress ||
            oldP.extras != newP.extras;

    final localCommuteOnlyChanged =
        oldP.walkingSpeedKmh != newP.walkingSpeedKmh ||
            oldP.walkingDurationMinutes != newP.walkingDurationMinutes ||
            oldP.walkHomeToBusMinutes != newP.walkHomeToBusMinutes ||
            oldP.walkHomeToTrainMinutes != newP.walkHomeToTrainMinutes ||
            oldP.walkSchoolToBusMinutes != newP.walkSchoolToBusMinutes ||
            oldP.walkSchoolToTrainMinutes != newP.walkSchoolToTrainMinutes ||
            oldP.transitAlertBufferMinutes != newP.transitAlertBufferMinutes ||
            oldP.transitNotificationsEnabled !=
                newP.transitNotificationsEnabled ||
            oldP.favoriteRoute1stPeriod != newP.favoriteRoute1stPeriod ||
            oldP.favoriteRoute2ndPeriod != newP.favoriteRoute2ndPeriod;

    if (!newP.transitCardEnabled || !newP.transitConfigured) {
      if (_commuteEval != null || _commuteLoading) {
        setState(() {
          _commuteEval = null;
          _commuteLoading = false;
        });
      }
      MenetrendService.cancelAlarms();
      return;
    }

    if ((localCommuteOnlyChanged || transitEnabledOrConfiguredChanged) &&
        _commuteEval != null) {
      final recalculated = _commuteEval!.recalculateForPrefs(newP);
      final filtered = MenetrendService.filterVisibleEvaluation(
        evaluation: recalculated,
        todaysLessons: _data?.todaysLessons,
        prefs: newP,
        now: _now(),
      );
      setState(() => _commuteEval = filtered);
      if (filtered != null) {
        MenetrendService.syncNotificationsForEvaluation(
          evaluation: filtered,
          prefs: newP,
          allowDelayNotification: false,
        );
      } else {
        MenetrendService.cancelAlarms();
      }
    }

    if (transitEnabledOrConfiguredChanged ||
        (localCommuteOnlyChanged && _commuteEval == null && _data != null)) {
      _refreshCommute(allowDelayNotifications: false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    DemoDataService.instance.revision.removeListener(_onDemoRevisionChanged);
    HomeWidgetSyncService.instance.openTimetableSignal
        .removeListener(_onOpenTimetableSignal);
    _settingsProvider?.removeListener(_onSettingsChangedForDemo);
    _countdownTimer?.cancel();
    _countdownTick.dispose();
    _commuteTick.dispose();
    _tabPageController.dispose();
    super.dispose();
  }

  CommuteEvaluation? _commuteEval;
  bool _commuteLoading = false;
  final MenetrendService _menetrendService = MenetrendService();

  Future<void> _refreshCommute({bool allowDelayNotifications = true}) async {
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    final lessons = _data?.todaysLessons ?? const <Lesson>[];
    final now = _now();
    final window = MenetrendService.commuteWindowForLessons(
      now: now,
      lessons: lessons,
    );
    _lastCommuteWindow = window;
    _lastCommuteSyncAt = now;
    _hasInitialCommuteSynced = true;

    if (scope != null) {
      await scope.commute.syncLive(
        todaysLessons: lessons,
        allowDelayNotifications: allowDelayNotifications,
        nowOverride: widget.clock?.call(),
      );
      return;
    }

    final prefs = _activePrefs;
    if (!prefs.transitCardEnabled || !prefs.transitConfigured || window == null) {
      if (_commuteEval != null || _commuteLoading) {
        setState(() {
          _commuteEval = null;
          _commuteLoading = false;
        });
      }
      unawaited(MenetrendService.cancelAlarms());
      return;
    }
    if (_commuteEval != null && _commuteEval!.isMorningMode != window) {
      setState(() => _commuteEval = null);
    }
    if (_commuteEval == null && !_commuteLoading) {
      setState(() => _commuteLoading = true);
    }
    final eval = await _menetrendService.fetchLiveCommuteEvaluation(
      todaysLessons: lessons,
      prefs: prefs,
      nowOverride: widget.clock?.call(),
    );
    if (!mounted) return;
    setState(() {
      _commuteEval = eval;
      _commuteLoading = false;
    });
    if (eval != null) {
      unawaited(
        MenetrendService.syncNotificationsForEvaluation(
          evaluation: eval,
          prefs: prefs,
          allowDelayNotification: allowDelayNotifications,
        ),
      );
    }
  }

  Future<void> _handleHomePullToRefresh() async {
    AppProvidersScope.maybeOf(context)?.settings.clearAllGradeGlows();
    await _loadDashboard();
  }

  Future<void> _loadDashboard({bool silentIfCached = false}) async {
    if (_activePrefs.demoModeEnabled) {
      final demoData = DemoDataService.instance.buildDashboardData(
        nowOverride: widget.clock?.call(),
      );
      if (!mounted) return;
      setState(() {
        _session = demoData.activeSession;
        _data = demoData;
        _messagesOverride = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    if (_data == null) {
      final cached = await widget.kretaClient.loadCachedDashboard(_session);
      if (mounted && cached != null && _data == null) {
        final playInitialEntrance = !_homeInitialEntrancePlayed;
        setState(() {
          _data = cached;
          _isLoading = false;
          _error = null;
          if (playInitialEntrance) {
            _homeInitialEntrancePlayed = true;
            _homeEntranceActive = true;
          }
        });
        unawaited(
          AppProvidersScope.maybeOf(context)
              ?.settings
              .ingestGrades(cached.allGrades),
        );
        if (playInitialEntrance) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _homeEntranceActive = false;
          });
        }
        unawaited(_refreshCommute(allowDelayNotifications: false));
      }
    }

    if (mounted && _data == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final previousRefreshToken = _session.refreshToken;
      final result = await widget.kretaClient.fetchDashboardData(_session);
      if (!mounted) return;
      final playInitialEntrance = !_homeInitialEntrancePlayed;
      setState(() {
        _session = result.activeSession;
        _data = result;
        _messagesOverride = null;
        _isLoading = false;
        _error = null;
        if (playInitialEntrance) {
          _homeInitialEntrancePlayed = true;
          _homeEntranceActive = true;
        }
      });
      unawaited(
        AppProvidersScope.maybeOf(context)
            ?.settings
            .ingestGrades(result.allGrades),
      );
      if (playInitialEntrance) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeEntranceActive = false;
        });
      }
      _refreshCommute();
      unawaited(
        WearSyncService.instance.cacheSessionSnapshot(
          session: result.activeSession,
          student: result.student,
          nickname: _activePrefs.nickname,
        ),
      );
      if (result.activeSession.refreshToken != previousRefreshToken) {
        unawaited(
          WearSyncService.instance.syncSessionToWatch(
            session: result.activeSession,
            student: result.student,
            nickname: _activePrefs.nickname,
            forceSync: false,
          ),
        );
      }
      if (result.student != null && !_hasPushedWearProfileMetadata) {
        _hasPushedWearProfileMetadata = true;
        unawaited(_syncWearStudentMetadataIfConnected(result));
      }
      unawaited(
        CalendarSyncService.instance.syncFromDashboardIfEnabled(
          result,
          prefs: _activePrefs,
        ),
      );
      _syncHomeWidgetsFromDashboard(result);
    } on InvalidGrantException {
      if (!mounted) return;
      widget.onLogout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!silentIfCached || _data == null) {
          _error = e.toString();
        }
      });
    }
  }

  Future<void> _syncWearStudentMetadataIfConnected(DashboardData data) async {
    final status = await WearSyncService.instance.getConnectionStatus();
    if (!status.isConnected) return;
    await WearSyncService.instance.syncSessionToWatch(
      session: data.activeSession,
      student: data.student,
      nickname: _activePrefs.nickname,
      forceSync: false,
    );
  }

  static const int _timetableTabIndex = 2;

  List<KretaMessage>? _messagesOverride;

  int get _unreadMessagesCount {
    final list = _messagesOverride ?? _data?.messages ?? const <KretaMessage>[];
    return list.where((m) => !m.isRead && !m.isSent).length;
  }

  void _selectBottomTab(int idx) {
    if (_selectedIndex == idx) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedIndex == _timetableTabIndex && idx != _timetableTabIndex) {
        _isImmersiveWeeklyMode = false;
      }
      _selectedIndex = idx;
    });
    if (_tabPageController.hasClients) {
      _tabPageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _openMessagesScreen() {
    HapticFeedback.lightImpact();
    final currentMessages =
        _messagesOverride ?? _data?.messages ?? const <KretaMessage>[];
    final currentPrefs = _activePrefs;
    Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: Scaffold(
          appBar: AppBar(
            title: Text(uwu('Üzenetek')),
          ),
          body: ChristmasAndBackgroundOverlay(
            prefs: currentPrefs,
            child: MoreScreen(
              session: _session,
              student: _data?.student,
              kretaClient: widget.kretaClient,
              dashboardData: _data,
              initialOmissions: _data?.omissions ?? const <Omission>[],
              initialMessages: currentMessages,
              prefs: currentPrefs,
              onPrefsChanged: widget.onPrefsChanged,
              onLogout: widget.onLogout,
              messagesOnly: true,
              onMessagesChanged: (updated) {
                if (mounted) {
                  setState(() => _messagesOverride = updated);
                }
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBarMessagesButton(ThemeData theme, ColorScheme scheme) {
    final unread = _unreadMessagesCount;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: uwu('Üzenetek'),
        child: TactileBounce(
          onTap: _openMessagesScreen,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(
                color: unread > 0
                    ? scheme.primary.withValues(alpha: 0.55)
                    : theme.dividerColor,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  unread > 0
                      ? Icons.mark_email_unread_rounded
                      : Icons.mail_outline_rounded,
                  size: 20,
                  color: unread > 0
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.85),
                ),
                if (unread > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 1.5,
                        ),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProfileAndSettingsModal() {
    final currentPrefs = _activePrefs;
    showStreamlinedProfileSheet(
      context: context,
      student: _data?.student,
      session: _session,
      kretaClient: widget.kretaClient,
      prefs: currentPrefs,
      onPrefsChanged: widget.onPrefsChanged,
      onOpenFullSettings: () {
        Navigator.of(context).push(
          SmoothSharedAxisRoute(
            page: AppSettingsScreen(
              session: _session,
              student: _data?.student,
              kretaClient: widget.kretaClient,
              dashboardData: _data,
              prefs: _activePrefs,
              onPrefsChanged: widget.onPrefsChanged,
              onLogout: widget.onLogout,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    if (scope == null) {
      return _buildHomeScaffold(context, widget.prefs);
    }
    return ListenableBuilder(
      listenable: scope.settings,
      builder: (context, _) => _buildHomeScaffold(context, scope.settings.prefs),
    );
  }

  Widget _buildHomeScaffold(BuildContext context, UserProfilePrefs activePrefs) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final student = _data?.student;
    final hideChromeForLandscapeTimetable =
        _isImmersiveWeeklyMode && _selectedIndex == _timetableTabIndex;

    final resolvedName = GreetingUtils.resolveDisplayName(
      customNickname: activePrefs.demoModeEnabled ? null : activePrefs.nickname,
      fullStudentName: student?.name,
    );
    final greetingText = GreetingUtils.buildGreeting(
      name: resolvedName,
      uwuMode: activePrefs.uwuModeEnabled,
      tsundereMode: activePrefs.tsundereModeEnabled,
    );

    final hasAmbientBackdrop = ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
      context,
      activePrefs,
    );

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          _selectBottomTab(0);
        }
      },
      child: ChristmasAndBackgroundOverlay(
        prefs: activePrefs,
        child: Scaffold(
          backgroundColor: hasAmbientBackdrop ? Colors.transparent : null,
          extendBody: !hideChromeForLandscapeTimetable,
          appBar: hideChromeForLandscapeTimetable
              ? null
              : AppBar(
                  backgroundColor:
                      hasAmbientBackdrop ? Colors.transparent : null,
                  toolbarHeight: 68,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        greetingText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        student?.instituteName ?? _session.instituteCode,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.62),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  actions: [
                    _buildTopBarMessagesButton(theme, scheme),
                    ProfileTopBarAvatar(
                      prefs: activePrefs,
                      onTap: _openProfileAndSettingsModal,
                    ),
                  ],
                ),
          body: _buildKeepAliveTabStack(theme, scheme, student, activePrefs),
          bottomNavigationBar: hideChromeForLandscapeTimetable
              ? null
              : _buildMinimalistFloatingDock(theme, scheme),
        ),
      ),
    );
  }

  Widget _buildKeepAliveTabStack(
    ThemeData theme,
    ColorScheme scheme,
    Student? student,
    UserProfilePrefs activePrefs,
  ) {
    final tabs = <Widget>[
      _KeepAliveTabWrapper(
        key: const PageStorageKey<String>('tab-home'),
        child: _buildHomeTab(theme, scheme),
      ),
      GradesScreen(
        key: const PageStorageKey<String>('tab-grades'),
        allGrades: _data?.allGrades ?? const <Grade>[],
        prefs: activePrefs,
        onPrefsChanged: widget.onPrefsChanged,
        onRefresh: _loadDashboard,
        isActiveTab: _selectedIndex == 1,
        entranceEpoch: _tabSwitchEpoch,
      ),
      TimetableScreen(
        key: const PageStorageKey<String>('tab-timetable'),
        session: _session,
        kretaClient: widget.kretaClient,
        initialTodaysLessons: _data?.todaysLessons ?? const <Lesson>[],
        homeworks: _data?.homeworks ?? const <Homework>[],
        prefs: activePrefs,
        onPrefsChanged: widget.onPrefsChanged,
        onImmersiveWeeklyModeChanged: (immersive) {
          if (mounted && _isImmersiveWeeklyMode != immersive) {
            setState(() => _isImmersiveWeeklyMode = immersive);
          }
        },
        isActiveTab: _selectedIndex == _timetableTabIndex,
        entranceEpoch: _tabSwitchEpoch,
        clock: widget.clock,
      ),
      MoreScreen(
        key: const PageStorageKey<String>('tab-more'),
        session: _session,
        student: student,
        kretaClient: widget.kretaClient,
        dashboardData: _data,
        initialOmissions: _data?.omissions ?? const <Omission>[],
        initialMessages:
            _messagesOverride ?? _data?.messages ?? const <KretaMessage>[],
        prefs: activePrefs,
        onPrefsChanged: widget.onPrefsChanged,
        onLogout: widget.onLogout,
        isActiveTab: _selectedIndex == 3,
        onMessagesChanged: (updated) {
          if (mounted) {
            setState(() => _messagesOverride = updated);
          }
        },
      ),
    ];

    return PageView(
      controller: _tabPageController,
      physics: const NeverScrollableScrollPhysics(),
      children: tabs,
    );
  }

  /// Floating bottom dock with frosted liquid glass (`BackdropFilter` blur +
  /// translucent tint + 1px specular border) when Settings Liquid Glass is ON
  /// or clean opaque Material 3 container (`secondaryContainer` pill) when OFF,
  /// paired with dual-mode 2D liquid spring / M3 cubic sliding physics.
  Widget _buildMinimalistFloatingDock(ThemeData theme, ColorScheme scheme) {
    final isDark = theme.brightness == Brightness.dark ||
        _activePrefs.themeStyle != AppThemeStyle.light;
    final liquidGlass = _activePrefs.liquidGlassEnabled;
    final activeIconColor = liquidGlass
        ? (isDark ? Colors.white : const Color(0xFF0F172A))
        : scheme.onSecondaryContainer;
    final inactiveIconColor = liquidGlass
        ? (isDark
            ? Colors.white.withValues(alpha: 0.72)
            : const Color(0xFF0F172A).withValues(alpha: 0.65))
        : scheme.onSurfaceVariant;

    const tabs = <({
      IconData icon,
      IconData selectedIcon,
      String tooltip,
    })>[
      (
        icon: Icons.home_outlined,
        selectedIcon: Icons.home_rounded,
        tooltip: 'Főoldal',
      ),
      (
        icon: Icons.star_outline_rounded,
        selectedIcon: Icons.star_rounded,
        tooltip: 'Jegyek',
      ),
      (
        icon: Icons.calendar_month_outlined,
        selectedIcon: Icons.calendar_month_rounded,
        tooltip: 'Órarend',
      ),
      (
        icon: Icons.timer_outlined,
        selectedIcon: Icons.timer_rounded,
        tooltip: 'Hiányzások',
      ),
    ];

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: LiquidGlassSurface(
          prefs: _activePrefs,
          isDockStyle: true,
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
          child: LiquidSpringPillTrack(
            itemCount: tabs.length,
            selectedIndex: _selectedIndex,
            height: 62,
            pillWidth: 56.0,
            pillHeight: 42.0,
            liquidGlassEnabled: liquidGlass,
            pressScale: liquidGlass ? 1.12 : 1.0,
            clipBehavior: liquidGlass ? Clip.none : Clip.hardEdge,
            clipBorderRadius: liquidGlass ? null : BorderRadius.circular(28),
            onSelected: _selectBottomTab,
            pillBuilder: (context, _) => liquidGlass
                ? const LiquidGlassPillSurface(
                    pressProgress: 0.0,
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                  )
                : const Material3TonalPillSurface(
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                  ),
            interactivePillBuilder: liquidGlass
                ? (context, _, pressProgress) => LiquidGlassPillSurface(
                      pressProgress: pressProgress,
                      borderRadius: const BorderRadius.all(Radius.circular(22)),
                    )
                : null,
            itemBuilder: (context, idx, activeProgress) {
              final item = tabs[idx];
              final isSelected = _selectedIndex == idx;
              final iconColor = Color.lerp(
                inactiveIconColor,
                activeIconColor,
                activeProgress,
              )!;
              return Semantics(
                label: item.tooltip,
                selected: isSelected,
                button: true,
                child: Tooltip(
                  message: item.tooltip,
                  triggerMode: TooltipTriggerMode.manual,
                  child: SizedBox(
                    height: 62,
                    child: Center(
                      child: IconTheme(
                        data: IconThemeData(color: iconColor, size: 25),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            isSelected ? item.selectedIcon : item.icon,
                            key: ValueKey<String>(
                              'dock-$idx-$isSelected-$isDark',
                            ),
                            size: 25,
                            color: iconColor,
                          ),
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
    );
  }

  static const List<String> _shortMonthsHu = [
    'Jan.',
    'Febr.',
    'Márc.',
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

  static const List<String> _weekdayNamesHu = [
    '',
    'Hétfő',
    'Kedd',
    'Szerda',
    'Csütörtök',
    'Péntek',
    'Szombat',
    'Vasárnap',
  ];

  String _formatFeedCardDate(DateTime dt) {
    final local = dt.toLocal();
    final month = _shortMonthsHu[(local.month - 1).clamp(0, 11)].toLowerCase();
    return '$month ${local.day}.';
  }

  String _formatDaySectionTitle(DateTime day, DateTime today) {
    final month = _shortMonthsHu[(day.month - 1).clamp(0, 11)];
    final weekday = _weekdayNamesHu[day.weekday.clamp(1, 7)];
    if (day == today.add(const Duration(days: 1))) {
      return 'Holnap • $month ${day.day}.';
    }
    if (day.isAfter(today.add(const Duration(days: 1)))) {
      return '$month ${day.day}. • $weekday';
    }
    if (day == today) return 'Ma';
    if (day == today.subtract(const Duration(days: 1))) return 'Tegnap';
    return '$month ${day.day}.';
  }

  List<({DateTime day, List<HomeActivityItem> items})> _groupFeedItemsByDay(
    List<HomeActivityItem> items,
    DateTime today,
  ) =>
      groupHomeActivityItemsByDay(items, today);

  Widget _buildHomeTransitCard({
    required UserProfilePrefs prefs,
    required CommuteEvaluation? rawEval,
    required bool isLoading,
    required List<Lesson> lessons,
  }) {
    final now = _now();
    final eval = MenetrendService.filterVisibleEvaluation(
      evaluation: rawEval,
      todaysLessons: lessons,
      prefs: prefs,
      now: now,
    );
    if (eval == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _maybeHomeEntrance(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: MenetrendHomeCard(
              evaluation: eval,
              isLoading: isLoading,
              prefs: prefs,
              todaysLessons: lessons,
              now: now,
              onOpenSettings: _openProfileAndSettingsModal,
              onRetry: () => _refreshCommute(),
            ),
          ),
          0,
          key: const ValueKey('home-transit'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHomeTab(ThemeData theme, ColorScheme scheme) {
    final Widget tabChild;
    if (_isLoading && _data == null) {
      tabChild = HomeSkeletonFeed(
        key: const ValueKey<String>('home-skeleton-feed'),
        prefs: widget.prefs,
      );
    } else {
      final lessons = _data?.todaysLessons ?? const <Lesson>[];
      final allFeedItems = _buildAllFeedItems();
      final today = DateUtils.dateOnly(DateTime.now());
      final allDayGroups = _groupFeedItemsByDay(allFeedItems, today);
      bool isFeedItemVisible(HomeActivityItem item) {
        if (!item.matchesFilter(_feedFilter)) return false;
        // On Főoldal ('Összes'), automatically hide completed homeworks so only
        // active/unfinished tasks appear in the upcoming section; keep them
        // visible in the dedicated 'Házik' view for inspection and undo.
        if (_feedFilter == ActivityFeedFilter.all && item.homework != null) {
          return !_isHomeworkCompleted(item.homework!);
        }
        return true;
      }

      final feedRows = <_HomeFeedRow>[];
      int visibleGroupOrdinal = 0;
      for (int gIdx = 0; gIdx < allDayGroups.length; gIdx++) {
        final group = allDayGroups[gIdx];
        final matchingCount = group.items.where(isFeedItemVisible).length;
        final headerVisible = matchingCount > 0;
        final isFirstVisibleGroup = headerVisible && visibleGroupOrdinal == 0;
        feedRows.add(
          _HomeFeedHeaderRow(
            day: group.day,
            matchingCount: matchingCount,
            groupIndex: gIdx,
            isVisible: headerVisible,
            topSpacing: (headerVisible && !isFirstVisibleGroup) ? 20.0 : 0.0,
          ),
        );
        int visibleItemIdx = 0;
        for (int i = 0; i < group.items.length; i++) {
          final item = group.items[i];
          final itemVisible = isFeedItemVisible(item);
          feedRows.add(
            _HomeFeedItemRow(
              item: item,
              itemIndex: itemVisible ? visibleItemIdx++ : 0,
              groupIndex: gIdx,
              isVisible: itemVisible,
            ),
          );
        }
        if (headerVisible) {
          visibleGroupOrdinal++;
        }
      }
      const int animatedPreviewLimit = 18;
      final hasAnyMatching = visibleGroupOrdinal > 0;
      final previewRows = feedRows.take(animatedPreviewLimit).toList();
      final tailRows = feedRows.length > animatedPreviewLimit
          ? feedRows.sublist(animatedPreviewLimit)
          : const <_HomeFeedRow>[];

      tabChild = CustomScrollView(
        key: const ValueKey<String>('home-live-feed'),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildErrorCard(theme, _error!),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ValueListenableBuilder<int>(
                    valueListenable: _commuteTick,
                    builder: (context, _, _) {
                      final scope = AppProvidersScope.maybeOf(context);
                      final activePrefs = scope?.settings.prefs ?? widget.prefs;
                      if (scope != null) {
                        return ListenableBuilder(
                          listenable:
                              Listenable.merge([scope.settings, scope.commute]),
                          builder: (context, _) => _buildHomeTransitCard(
                            prefs: scope.settings.prefs,
                            rawEval: scope.commute.evaluation ?? _commuteEval,
                            isLoading: scope.commute.isLoading,
                            lessons: lessons,
                          ),
                        );
                      }
                      return _buildHomeTransitCard(
                        prefs: activePrefs,
                        rawEval: _commuteEval,
                        isLoading: _commuteLoading,
                        lessons: lessons,
                      );
                    },
                  ),
                  _maybeHomeEntrance(
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _countdownTick,
                        builder: (context, _, _) =>
                            _buildNextLessonHeroCard(theme, scheme, lessons),
                      ),
                    ),
                    1,
                    key: const ValueKey('home-next'),
                  ),
                  const SizedBox(height: 24),
                  _maybeHomeEntrance(
                    _buildFilterChipBar(theme, scheme),
                    2,
                    key: const ValueKey('home-chips'),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              tailRows.isEmpty ? 116 : 0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _CollapsibleFeedItem(
                    key: const ValueKey<String>('home-feed-empty'),
                    visible: !hasAnyMatching,
                    child: _buildEmptyStateCard(
                      theme,
                      scheme,
                      icon: Icons.inbox_rounded,
                      message: uwu(
                        'Nincs megjeleníthető elem ebben a kategóriában.',
                      ),
                    ),
                  ),
                  for (final row in previewRows)
                    _buildFeedRowWidget(theme, scheme, row, today),
                ],
              ),
            ),
          ),
          if (tailRows.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 116),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildFeedRowWidget(
                    theme,
                    scheme,
                    tailRows[index],
                    today,
                  ),
                  childCount: tailRows.length,
                ),
              ),
            ),
        ],
      );
    }

    return RefreshIndicator(
      displacement: 44,
      edgeOffset: 8,
      strokeWidth: 2.6,
      onRefresh: _handleHomePullToRefresh,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        ),
        child: tabChild,
      ),
    );
  }

  Widget _buildFeedRowWidget(
    ThemeData theme,
    ColorScheme scheme,
    _HomeFeedRow row,
    DateTime today,
  ) {
    if (row is _HomeFeedHeaderRow) {
      final header = _buildFeedDayHeaderRow(
        theme,
        scheme,
        row.day,
        row.matchingCount,
        today,
        topSpacing: row.topSpacing,
      );
      return RepaintBoundary(
        key: ValueKey('day-boundary-${row.day.toIso8601String()}'),
        child: _CollapsibleFeedItem(
          visible: row.isVisible,
          child: _maybeHomeEntrance(
            header,
            row.groupIndex < 6 ? row.groupIndex + 2 : 8,
            key: ValueKey('day-${row.day.toIso8601String()}'),
          ),
        ),
      );
    }
    final itemRow = row as _HomeFeedItemRow;
    final tile = Padding(
      padding: EdgeInsets.only(top: itemRow.itemIndex > 0 ? 2 : 0),
      child: _buildActivityFeedTile(theme, scheme, itemRow.item),
    );
    final staggerIndex = itemRow.groupIndex + itemRow.itemIndex;
    return RepaintBoundary(
      key: ValueKey('feed-boundary-${itemRow.item.uniqueKey}'),
      child: _CollapsibleFeedItem(
        visible: itemRow.isVisible,
        child: _maybeHomeEntrance(
          tile,
          staggerIndex < 6 ? staggerIndex + 2 : 8,
          key: ValueKey('feed-item-${itemRow.item.uniqueKey}'),
        ),
      ),
    );
  }

  Widget _buildFeedDayHeaderRow(
    ThemeData theme,
    ColorScheme scheme,
    DateTime day,
    int matchingCount,
    DateTime today, {
    double topSpacing = 0,
  }) {
    final isUpcomingDay = day.isAfter(today);
    final isTomorrow = day == today.add(const Duration(days: 1));
    final title = _formatDaySectionTitle(day, today);
    final weekday = _weekdayNamesHu[day.weekday.clamp(1, 7)];
    // For later future days ("Nov. 16. • Hétfő"), weekday is already in title;
    // for tomorrow ("Holnap • Nov. 13.") and today/past, show weekday alongside.
    final showSecondaryWeekday = !isUpcomingDay || isTomorrow;

    return Padding(
      padding: EdgeInsets.fromLTRB(4, topSpacing, 4, 10),
      child: Row(
        children: [
          if (isUpcomingDay) ...[
            const Icon(
              Icons.upcoming_rounded,
              size: 16,
              color: Color(0xFFFF7043),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            uwu(title),
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color:
                  isUpcomingDay ? const Color(0xFFFF7043) : scheme.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          if (showSecondaryWeekday) ...[
            const SizedBox(width: 8),
            Text(
              weekday,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.52),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: isUpcomingDay
                  ? const Color(0xFFFF7043).withValues(alpha: 0.18)
                  : scheme.surfaceContainerHigh.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$matchingCount',
              style: theme.textTheme.labelSmall?.copyWith(
                color: isUpcomingDay
                    ? const Color(0xFFFF7043)
                    : scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the dynamic 'Következő óra' / Live Activity hero card using
  /// [NextLessonStatus.evaluate] with local DateTime comparisons.
  Widget _buildNextLessonHeroCard(
    ThemeData theme,
    ColorScheme scheme,
    List<Lesson> lessons,
  ) {
    final activePrefs = _activePrefs;
    final status = NextLessonStatus.evaluate(
      lessons,
      _now(),
      prefs: activePrefs,
    );
    final currentOrNext = status.targetLesson;
    final upcoming = status.upcomingLesson;
    final isOngoing = status.phase == NextLessonPhase.ongoing;
    final isBreak = status.phase == NextLessonPhase.betweenLessons;

    final progressText = NextLessonStatus.formatRemainingLessonsLabel(
      status.remainingLessonsCount,
    );

    final heroTag =
        currentOrNext != null ? 'home_lesson_num_${currentOrNext.uid}' : null;

    Widget buildHeroPeriodBadge() {
      final lesson = currentOrNext!;
      final baseAccent = activePrefs.timetablePeriodColor ?? scheme.primary;
      final readableAccent = activePrefs.timetablePeriodColor != null
          ? OledTheme.readableInlineColor(
              activePrefs.timetablePeriodColor!,
              theme.brightness,
            )
          : scheme.primary;
      final periodLabel =
          lesson.lessonNumber != null ? '${lesson.lessonNumber}.' : '•';
      return Hero(
        tag: heroTag!,
        child: Material(
          type: MaterialType.transparency,
          child: PeriodCountdownBadge(
            label: periodLabel,
            backgroundColor: baseAccent.withValues(alpha: 0.2),
            textStyle: theme.textTheme.titleMedium!.copyWith(
              color: readableAccent,
              fontWeight: FontWeight.w900,
            ),
            ringColor: readableAccent,
            startTime: isOngoing ? lesson.start.toLocal() : null,
            endTime: isOngoing ? lesson.end.toLocal() : null,
            clock: widget.clock,
            remainingFraction: null,
            outerSize: 58,
            innerSize: 42,
            idleSize: 46,
            idleBorderRadius: BorderRadius.circular(14),
            strokeWidth: 4.0,
          ),
        ),
      );
    }

    final rawCurrentSubj = currentOrNext != null
        ? (currentOrNext.subject?.name ?? currentOrNext.name)
        : '';
    final currentSubjTitle = currentOrNext != null
        ? activePrefs.resolveSubjectName(
            rawCurrentSubj,
            currentOrNext.subject?.uid,
          )
        : '';

    return TactileBounce(
      pressedScale: 0.97,
      onTap: currentOrNext != null
          ? () => showLessonInspectionModal(
                context,
                currentOrNext,
                heroTag: heroTag,
                prefs: activePrefs,
                homework: KretaClient.findHomeworkForLesson(
                  currentOrNext,
                  _data?.homeworks ?? const <Homework>[],
                ),
              )
          : () => _selectBottomTab(_timetableTabIndex),
      child: ChristmasSnowCap(
        enabled: activePrefs.christmasModeEnabled,
        child: SoftGlassCard(
          prefs: activePrefs,
          padding: const EdgeInsets.all(20),
          borderRadius: OledTheme.largeRadius,
          border: Border.all(
            color: isOngoing
                ? Colors.blueAccent.withValues(alpha: 0.85)
                : currentOrNext != null
                    ? scheme.primary.withValues(alpha: 0.65)
                    : theme.dividerColor,
            width: currentOrNext != null ? 1.5 : 1.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status.phase != NextLessonPhase.completedForToday) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isBreak) ...[
                            _PulsingStatusDot(color: scheme.primary),
                            const SizedBox(width: 6),
                          ] else ...[
                            Icon(
                              isOngoing
                                  ? Icons.sensors_rounded
                                  : Icons.schedule_rounded,
                              size: 15,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            uwu(
                              isOngoing
                                  ? 'Folyamatban lévő óra'
                                  : isBreak
                                      ? 'Szünet'
                                      : 'Következő óra',
                            ),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isOngoing
                                ? scheme.primary.withValues(alpha: 0.16)
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: isOngoing && currentOrNext != null
                                ? LiveCountdownProgressScope(
                                    startTime: currentOrNext.start.toLocal(),
                                    endTime: currentOrNext.end.toLocal(),
                                    clock: widget.clock,
                                    builder: (_, snap) => Text(
                                      uwu(snap.formattedRemaining()),
                                      maxLines: 1,
                                      softWrap: false,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: scheme.primary,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  )
                                : Text(
                                    uwu(progressText),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurface.withValues(
                                        alpha: 0.78,
                                      ),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (status.phase == NextLessonPhase.completedForToday ||
                  currentOrNext == null)
                Row(
                  children: [
                    Icon(
                      Icons.celebration_rounded,
                      color: scheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uwu('Ma már nincs több órád!'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status.totalLessonsCount > 0
                                ? 'Mind a(z) ${status.totalLessonsCount} mai tanóra lezajlott. Koppints a teljes órarendért!'
                                : 'Mára nincs rögzített tanóra. Koppints a heti órarend megnyitásához!',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else if (isOngoing) ...[
                // Live Activity Style Current & Next Lesson Card
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    buildHeroPeriodBadge(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSubjTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_timeFormat.format(currentOrNext.start.toLocal())} - ${_timeFormat.format(currentOrNext.end.toLocal())}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (currentOrNext.roomName != null &&
                                  currentOrNext.roomName!.trim().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.meeting_room_rounded,
                                      size: 14,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Terem: ${currentOrNext.roomName}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          LiveCountdownProgressScope(
                            startTime: currentOrNext.start.toLocal(),
                            endTime: currentOrNext.end.toLocal(),
                            clock: widget.clock,
                            builder: (_, snap) {
                              final teacherPrefix = currentOrNext.substituteTeacher !=
                                          null &&
                                      currentOrNext.substituteTeacher!
                                          .trim()
                                          .isNotEmpty
                                  ? 'Helyettes: ${activePrefs.resolveTeacherName(currentOrNext.substituteTeacher)} • '
                                  : (currentOrNext.teacher != null
                                      ? '${activePrefs.resolveTeacherName(currentOrNext.teacher)} • '
                                      : '');
                              return Text(
                                '$teacherPrefix${snap.formattedRemaining()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(color: theme.dividerColor, height: 1),
                const SizedBox(height: 12),
                _buildUpcomingNextLessonRow(theme, scheme, upcoming),
              ] else ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    buildHeroPeriodBadge(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            status.headline,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time_rounded,
                                    size: 14,
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_timeFormat.format(currentOrNext.start.toLocal())} - ${_timeFormat.format(currentOrNext.end.toLocal())}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              if (currentOrNext.roomName != null &&
                                  currentOrNext.roomName!.trim().isNotEmpty)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.meeting_room_rounded,
                                      size: 14,
                                      color: scheme.onSurface
                                          .withValues(alpha: 0.65),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Terem: ${currentOrNext.roomName}',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          if ((currentOrNext.substituteTeacher != null &&
                                  currentOrNext.substituteTeacher!
                                      .trim()
                                      .isNotEmpty) ||
                              (currentOrNext.teacher != null &&
                                  currentOrNext.teacher!
                                      .trim()
                                      .isNotEmpty)) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  currentOrNext.substituteTeacher != null &&
                                          currentOrNext.substituteTeacher!
                                              .trim()
                                              .isNotEmpty
                                      ? Icons.swap_horiz_rounded
                                      : Icons.person_outline_rounded,
                                  size: 14,
                                  color: currentOrNext.substituteTeacher !=
                                              null &&
                                          currentOrNext.substituteTeacher!
                                              .trim()
                                              .isNotEmpty
                                      ? const Color(0xFFFFB300)
                                      : scheme.onSurface
                                          .withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    currentOrNext.substituteTeacher != null &&
                                            currentOrNext.substituteTeacher!
                                                .trim()
                                                .isNotEmpty
                                        ? 'Helyettes: ${activePrefs.resolveTeacherName(currentOrNext.substituteTeacher)}'
                                        : activePrefs.resolveTeacherName(
                                            currentOrNext.teacher,
                                          ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: currentOrNext.substituteTeacher !=
                                                  null &&
                                              currentOrNext.substituteTeacher!
                                                  .trim()
                                                  .isNotEmpty
                                          ? const Color(0xFFFFB300)
                                          : scheme.onSurface
                                              .withValues(alpha: 0.72),
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
                const SizedBox(height: 12),
                if (status.phase == NextLessonPhase.beforeFirstFarAway ||
                    status.phase == NextLessonPhase.beforeFirstWithinTwoHours)
                  _PreClassCountdownBanner(
                    targetStartLocal: currentOrNext.start.toLocal(),
                    textTransform: uwu,
                    clock: widget.clock,
                    onReachedStart: () {
                      if (mounted) _countdownTick.value++;
                    },
                  )
                else if (isBreak && status.previousLesson != null)
                  LiveCountdownProgressScope(
                    startTime: status.previousLesson!.end.toLocal(),
                    endTime: currentOrNext.start.toLocal(),
                    clock: widget.clock,
                    builder: (_, snap) {
                      final elapsed = (1.0 - snap.progress).clamp(0.02, 1.0);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.hourglass_top_rounded,
                                  size: 16,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    uwu(
                                      'Szünet • ${snap.formattedRemaining()}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.w900,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: elapsed,
                                minHeight: 5,
                                backgroundColor: scheme.onSurface
                                    .withValues(alpha: 0.12),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            status.countdownLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpcomingNextLessonRow(
    ThemeData theme,
    ColorScheme scheme,
    Lesson? upcoming,
  ) {
    if (upcoming == null) {
      return Row(
        children: [
          Icon(
            Icons.done_all_rounded,
            size: 16,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              uwu('Utolsó óra ma • Utána vége a tanításnak!'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    final rawNext = upcoming.subject?.name ?? upcoming.name;
    final nextSubj = widget.prefs.resolveSubjectName(
      rawNext,
      upcoming.subject?.uid,
    );

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.prefs.timetablePeriodColor ??
                scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: widget.prefs.timetablePeriodColor != null
                  ? OledTheme.contrastTextFor(
                      widget.prefs.timetablePeriodColor!,
                    ).withValues(alpha: 0.22)
                  : theme.dividerColor,
            ),
          ),
          child: Text(
            upcoming.lessonNumber != null ? '${upcoming.lessonNumber}.' : '•',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: widget.prefs.timetablePeriodColor != null
                  ? OledTheme.contrastTextFor(
                      widget.prefs.timetablePeriodColor!,
                    )
                  : scheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uwu('Következő: $nextSubj'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                '${_timeFormat.format(upcoming.start.toLocal())} - ${_timeFormat.format(upcoming.end.toLocal())}'
                '${upcoming.roomName != null && upcoming.roomName!.trim().isNotEmpty ? ' • Terem: ${upcoming.roomName}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChipBar(ThemeData theme, ColorScheme scheme) {
    final selectedIndex = ActivityFeedFilter.values.indexOf(_feedFilter);
    return LiquidBubbleTabBar(
      height: 40,
      fontSize: 12.5,
      itemPadding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      liquidGlassEnabled: _activePrefs.liquidGlassEnabled,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      items: [
        for (final filter in ActivityFeedFilter.values)
          LiquidBubbleTabItem(
            label: uwu(filter.label),
            icon: filter.icon,
          ),
      ],
      onSelected: (idx) {
        final filter = ActivityFeedFilter.values[idx];
        if (_feedFilter != filter) {
          setState(() => _feedFilter = filter);
        }
      },
    );
  }

  List<HomeActivityItem> _buildAllFeedItems() {
    final grades = _data?.allGrades ?? const <Grade>[];
    final homeworks = _data?.homeworks ?? const <Homework>[];
    final tests = _data?.tests ?? const <Test>[];

    return <HomeActivityItem>[
      ...grades.map(HomeActivityItem.grade),
      ...homeworks.map(HomeActivityItem.homework),
      ...tests.map(HomeActivityItem.test),
    ];
  }

  Widget _buildActivityFeedTile(
    ThemeData theme,
    ColorScheme scheme,
    HomeActivityItem item,
  ) {
    if (item.grade != null) {
      return _buildGradeFeedCard(theme, scheme, item.grade!);
    }
    if (item.homework != null) {
      return _buildHomeworkFeedCard(theme, scheme, item.homework!);
    }
    return _buildTestFeedCard(theme, scheme, item.test!);
  }

  /// Compact, clutter-free grade card on Főoldal (`Part B #13`) with boomerang
  /// Hero badge transition (`Part B #1`).
  Widget _buildGradeFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Grade grade,
  ) {
    final badgeColor = OledTheme.gradeColor(grade.numericValue, widget.prefs);
    final badgeText = grade.numericValue?.toString() ??
        grade.shortStrValue ??
        (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');

    final topicOrMode =
        (grade.topic != null && grade.topic!.trim().isNotEmpty)
            ? grade.topic!.trim()
            : (grade.mode?.description.isNotEmpty == true
                ? grade.mode!.description
                : grade.type.description);

    final subjectDisplay = widget.prefs.resolveSubjectName(
      grade.subject.name,
      grade.subject.uid,
    );
    final heroTag = 'home_grade_${grade.uid}';
    final settings = AppProvidersScope.maybeOf(context)?.settings;

    Widget buildCard(bool isGlowing) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TactileBounce(
          pressedScale: 0.97,
          onTap: () {
            settings?.dismissGradeGlow(grade);
            showGradeInspectionModal(
              context,
              grade,
              prefs: _activePrefs,
              heroTag: heroTag,
            );
          },
          child: ChristmasSnowCap(
            enabled: widget.prefs.christmasModeEnabled,
            child: GradeFirstSeenGlow(
              isGlowing: isGlowing,
              accentColor: badgeColor,
              borderRadius: BorderRadius.circular(18),
              child: SoftGlassCard(
                prefs: _activePrefs,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Hero(
                      tag: heroTag,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatFeedCardDate(grade.recordedAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.56),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            topicOrMode,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

    if (settings == null) {
      return buildCard(false);
    }

    return ListenableBuilder(
      listenable: settings,
      builder: (_, __) => buildCard(settings.isGradeGlowing(grade)),
    );
  }

  Widget _buildHomeworkFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Homework homework,
  ) {
    const hwColor = Color(0xFF00BFA5);
    final rawSubjectTitle = homework.subject.name.isNotEmpty
        ? homework.subject.name
        : homework.subjectName;
    final subjectTitle = widget.prefs.resolveSubjectName(
      rawSubjectTitle,
      homework.subject.uid,
    );
    final teacherDisplay =
        widget.prefs.resolveTeacherName(homework.teacherName);
    final cleanText = Homework.stripHtmlTags(homework.description);
    final heroTag = 'home_hw_${homework.uid}';
    final isCompleted = _isHomeworkCompleted(homework);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showHomeworkInspectionModal(
          context,
          homework,
          prefs: _activePrefs,
          heroTag: heroTag,
          isCompletedOverride: isCompleted,
        ),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: _activePrefs,
            padding: const EdgeInsets.all(14),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: isCompleted ? 0.58 : 1.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: heroTag,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hwColor.withValues(
                            alpha: isCompleted ? 0.12 : 0.2,
                          ),
                          borderRadius: OledTheme.badgeRadius,
                          border: Border.all(
                            color: hwColor.withValues(
                              alpha: isCompleted ? 0.45 : 1.0,
                            ),
                          ),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.task_alt_rounded
                              : Icons.menu_book_rounded,
                          color: hwColor,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                subjectTitle,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.onSurface,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  decorationThickness:
                                      isCompleted ? 1.8 : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Határidő: ${_formatFeedCardDate(homework.dueDate)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: hwColor,
                                fontWeight: FontWeight.w700,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          cleanText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.78),
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          teacherDisplay,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.54),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: isCompleted
                        ? uwu('Visszavonás (aktívvá tétel)')
                        : uwu('Megjelölés készként'),
                    child: InkResponse(
                      radius: 22,
                      onTap: () =>
                          _toggleHomeworkCompletion(homework, subjectTitle),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            isCompleted
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            key: ValueKey<bool>(isCompleted),
                            size: 24,
                            color: isCompleted
                                ? hwColor
                                : scheme.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ),
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

  /// Announced exam / test card with clean line break between weekday and date
  /// (`Part B #25`) and boomerang Hero transition (`Part B #1`).
  Widget _buildTestFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Test test,
  ) {
    const testColor = Color(0xFFFF7043);
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
    final weekdayName = weekdayNames[testLocal.weekday.clamp(1, 7)];
    final rawSubjectTitle =
        test.subject.name.isNotEmpty ? test.subject.name : test.subjectName;
    final subjectTitle = widget.prefs.resolveSubjectName(
      rawSubjectTitle,
      test.subject.uid,
    );
    final heroTag = 'home_test_${test.uid}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showTestInspectionModal(
          context,
          test,
          prefs: _activePrefs,
          heroTag: heroTag,
        ),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: _activePrefs,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            borderRadius: BorderRadius.circular(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Hero(
                  tag: heroTag,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: testColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: testColor),
                      ),
                      child: const Icon(
                        Icons.assignment_late_rounded,
                        color: testColor,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              subjectTitle,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$weekdayName, ${_formatFeedCardDate(testLocal)}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: testColor,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${test.method.description} (${test.lessonNumber}. óra)'
                        '${test.theme != null && test.theme!.trim().isNotEmpty ? ' • ${test.theme!.trim()}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: testColor,
                          fontWeight: FontWeight.w600,
                        ),
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

  Widget _buildErrorCard(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF2B1111),
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: Colors.redAccent),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyStateCard(
    ThemeData theme,
    ColorScheme scheme, {
    required IconData icon,
    required String message,
  }) {
    return SoftGlassCard(
      prefs: _activePrefs,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      borderRadius: OledTheme.cardRadius,
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurface.withValues(alpha: 0.54)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsibleFeedItem extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _CollapsibleFeedItem({
    super.key,
    required this.visible,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: visible ? 1.0 : 0.0),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, t, builtChild) {
        final clamped = t.clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: !visible,
          child: ExcludeSemantics(
            excluding: clamped <= 0.001 && !visible,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: clamped,
                child: Opacity(
                  opacity: clamped,
                  child: Transform.translate(
                    offset: Offset(0, (1.0 - clamped) * -8.0),
                    child: builtChild,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

sealed class _HomeFeedRow {
  const _HomeFeedRow();
}

class _HomeFeedHeaderRow extends _HomeFeedRow {
  const _HomeFeedHeaderRow({
    required this.day,
    required this.matchingCount,
    required this.groupIndex,
    required this.isVisible,
    required this.topSpacing,
  });

  final DateTime day;
  final int matchingCount;
  final int groupIndex;
  final bool isVisible;
  final double topSpacing;
}

class _HomeFeedItemRow extends _HomeFeedRow {
  const _HomeFeedItemRow({
    required this.item,
    required this.itemIndex,
    required this.groupIndex,
    required this.isVisible,
  });

  final HomeActivityItem item;
  final int itemIndex;
  final int groupIndex;
  final bool isVisible;
}
