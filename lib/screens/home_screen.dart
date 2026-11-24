import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';
import '../services/calendar_sync_service.dart';
import '../services/demo_data_service.dart';
import '../services/github_updater_service.dart';
import '../services/home_widget_sync_service.dart';
import '../services/kreta_client.dart';
import '../services/kreta_notification_service.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../services/wear_sync_service.dart';
import '../theme/minimalist_tokens.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../utils/platform_support.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/expandable_profile_card.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/menetrend_hero_card.dart';
import '../widgets/skeleton_shimmer.dart';
import '../widgets/tinta_error_state.dart';
import '../widgets/tinta_toast.dart';
import 'grades_screen.dart';
import 'more_screen.dart';
import 'timetable_screen.dart';
import 'webview_login_screen.dart';

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
    if (totalSeconds < 60) {
      return 'Kezdés: ${totalSeconds.clamp(1, 59)}mp múlva';
    }
    final totalMinutes = totalSeconds ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours >= 1) {
      return minutes > 0
          ? 'Kezdés: $hoursó ${minutes}p múlva'
          : 'Kezdés: $hoursó múlva';
    }
    return 'Kezdés: ${minutes}p múlva';
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
  final MissingEquipmentItem? missingEquipment;

  HomeActivityItem.grade(Grade this.grade)
      : sortDate = grade.recordedAt,
        homework = null,
        test = null,
        missingEquipment = null;

  /// Homeworks are grouped and sorted on Főoldal strictly by their deadline
  /// (`HataridoDatuma` -> `dueDate`), so upcoming deadlines appear at the very
  /// top above "Ma", nearest deadline first.
  HomeActivityItem.homework(Homework this.homework)
      : sortDate = homework.dueDate,
        grade = null,
        test = null,
        missingEquipment = null;

  HomeActivityItem.test(Test this.test)
      : sortDate = test.date,
        grade = null,
        homework = null,
        missingEquipment = null;

  HomeActivityItem.missingEquipment(MissingEquipmentItem this.missingEquipment)
      : sortDate = missingEquipment.date,
        grade = null,
        homework = null,
        test = null;

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
    if (missingEquipment != null) return 'eq-${missingEquipment!.uid}';
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
    with WidgetsBindingObserver {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  AppLifecycleState? _lifecycleState;
  bool _notifiedStart = false;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _refreshRemaining(notifyParent: false);
  }

  void _syncActiveControllers() {
    if (!mounted) return;
    final appActive = _lifecycleState == null ||
        _lifecycleState == AppLifecycleState.resumed;
    final shouldRun = appActive && _remaining > Duration.zero;

    if (shouldRun) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _refreshRemaining(notifyParent: true);
      });
    } else {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = scheme.primary;
    final remainingLabel = widget.textTransform(
      NextLessonStatus.formatFirstLessonCountdown(_remaining),
    );
    const windowSecs = 7200.0; // 2-hour morning pre-class progress horizon.
    final progress = _remaining <= Duration.zero
        ? 1.0
        : (1.0 - (_remaining.inSeconds / windowSecs)).clamp(0.08, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          remainingLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3.5,
            backgroundColor:
                scheme.onSurface.withValues(alpha: isDark ? 0.10 : 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
      ],
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
  final Future<StoredSession?> Function()? onReauthenticate;
  final DateTime Function()? clock;

  const HomeScreen({
    super.key,
    required this.initialSession,
    this.initialCachedData,
    required this.kretaClient,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
    this.onReauthenticate,
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
  late final PageController _feedPageController =
      PageController(initialPage: _feedFilter.index);
  bool _isAnimatingFeedPage = false;
  int _feedPageAnimEpoch = 0;
  bool _isImmersiveWeeklyMode = false;

  late StoredSession _session;
  DashboardData? _data;
  StoredSession? _realSessionBackup;
  DashboardData? _realDataBackup;
  bool _lastDemoModeActive = false;
  SettingsProvider? _settingsProvider;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isReauthenticating = false;
  int _dashboardLoadEpoch = 0;
  int _commuteSyncEpoch = 0;
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
  String? _lastWearDashboardDigest;
  Set<String> _fallbackCompletedHomeworkIds = <String>{};
  Set<String> _dismissedUnexcusedOmissionIds = <String>{};
  bool _dismissedUnexcusedLoaded = false;
  int _funFactEpoch = 0;
  bool _funFactsPreloadStarted = false;
  String? _lastFinishTimeLabel;

  final DateFormat _timeFormat = DateFormat('HH:mm');

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  void _ensureFunFactsLoadedIfNeeded() {
    if (GreetingUtils.hasFunFactsLoaded || _funFactsPreloadStarted) return;
    _funFactsPreloadStarted = true;
    unawaited(
      GreetingUtils.ensureFunFactsLoaded().then((facts) {
        if (mounted && facts.isNotEmpty) {
          setState(() => _funFactEpoch++);
        }
      }),
    );
  }

  Future<void> _cycleFunFact() async {
    HapticFeedback.selectionClick();
    if (!GreetingUtils.hasFunFactsLoaded) {
      await GreetingUtils.ensureFunFactsLoaded();
    }
    GreetingUtils.pickFunFact(forceRefresh: true);
    if (mounted) {
      setState(() => _funFactEpoch++);
    }
  }

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
    if (_data != null) {
      // Cached or demo data is already mounted cleanly; never replay entrance
      // opacity fades on background sync completion after splash exit.
      _homeInitialEntrancePlayed = true;
      _homeEntranceActive = false;
    }
    TokenStorageService.sessionNotifier.addListener(_onGlobalSessionChanged);
    DemoDataService.instance.revision.addListener(_onDemoRevisionChanged);
    if (isAndroidPlatform) {
      HomeWidgetSyncService.instance.openTimetableSignal
          .addListener(_onOpenTimetableSignal);
    }
    _hydrateFallbackCompletedHomeworkIds();
    _loadDismissedUnexcusedOmissionIds();
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
    if (_activePrefs.greetingSubtitleMode == GreetingSubtitleMode.funFacts) {
      _ensureFunFactsLoadedIfNeeded();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GitHubUpdaterService.checkForUpdates(context, manual: false);
        unawaited(_checkPendingOpenTimetableTab());
      }
    });
    _startCountdownTimer();
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _maybeSyncCommuteOnTick();
      if (_selectedIndex == 0 && (_data?.todaysLessons.isNotEmpty ?? false)) {
        _countdownTick.value++;
        if (_activePrefs.greetingSubtitleMode ==
                GreetingSubtitleMode.finishTime &&
            !_activePrefs.minimalistModeEnabled) {
          final nextLabel = GreetingUtils.buildFinishTimeSubtitle(
            _data?.todaysLessons ?? const <Lesson>[],
            _now(),
            hasLoadedData: _data != null,
          );
          if (_lastFinishTimeLabel != null &&
              nextLabel != _lastFinishTimeLabel) {
            setState(() => _lastFinishTimeLabel = nextLabel);
          } else {
            _lastFinishTimeLabel ??= nextLabel;
          }
        }
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

  void _onGlobalSessionChanged() {
    if (!mounted || _activePrefs.demoModeEnabled) return;
    final next = TokenStorageService.sessionNotifier.value;
    if (next != null && next.accessToken != _session.accessToken) {
      setState(() => _session = next);
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
    _loadDismissedUnexcusedOmissionIds();
    _syncHomeWidgetsFromDashboard(nextData, forceUpcomingRefresh: true);
  }

  void _applyDemoModeTransition(bool enabled) {
    if (isAndroidPlatform) {
      HomeWidgetSyncService.instance.clearMemoryCache();
    }
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
    if (!isAndroidPlatform) return;
    try {
      final openTimetable =
          await HomeWidgetSyncService.instance.consumePendingOpenTimetableTab();
      if (openTimetable && mounted) {
        _openTimetableFromNative();
      }
    } catch (_) {}
  }

  void _openTimetableFromNative() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _selectBottomTab(_timetableTabIndex);
  }

  void _syncHomeWidgetsFromDashboard(
    DashboardData data, {
    bool forceUpcomingRefresh = false,
  }) {
    if (!isAndroidPlatform || !mounted) return;
    unawaited(
      HomeWidgetSyncService.instance
          .syncFromDashboard(
            dashboard: data,
            kretaClient: widget.kretaClient,
            prefs: _activePrefs,
            themeAccent: Theme.of(context).colorScheme.primary,
            nowOverride: widget.clock?.call(),
            forceUpcomingRefresh: forceUpcomingRefresh,
          )
          .catchError((_) {}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      if (_countdownTimer == null || !(_countdownTimer?.isActive ?? false)) {
        _startCountdownTimer();
      }
      _maybeSyncCommuteOnTick(forceWindowCheck: true);
      unawaited(_checkPendingOpenTimetableTab());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
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
    return (scope?.settings.prefs ?? widget.prefs).effectiveForPlatform();
  }

  Future<void> _hydrateFallbackCompletedHomeworkIds() async {
    final ids = await SettingsProvider.loadCompletedHomeworkIdsFromPrefs();
    if (!mounted || ids.isEmpty) return;
    if (context.getInheritedWidgetOfExactType<AppProvidersScope>() != null) {
      return;
    }
    setState(() => _fallbackCompletedHomeworkIds = ids);
  }

  String get _dismissedUnexcusedPrefsKey =>
      'dismissed_unexcused_omission_ids_${TokenStorageService.accountKeyForSession(_session)}';

  Future<void> _loadDismissedUnexcusedOmissionIds() async {
    final sp = await SharedPreferences.getInstance();
    final saved = sp.getStringList(_dismissedUnexcusedPrefsKey) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _dismissedUnexcusedOmissionIds = saved.toSet();
      _dismissedUnexcusedLoaded = true;
    });
  }

  Future<void> _dismissUnexcusedBanner(List<Omission> currentUnexcused) async {
    final updated = <String>{
      ..._dismissedUnexcusedOmissionIds,
      ...currentUnexcused.map(OmissionsSummary.omissionIdentityKey),
    };
    setState(() {
      _dismissedUnexcusedOmissionIds = updated;
      _dismissedUnexcusedLoaded = true;
    });
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_dismissedUnexcusedPrefsKey, updated.toList());
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

  Future<void> _markAllPendingHomeworksCompleted(
    List<Homework> pendingHomeworks,
  ) async {
    if (pendingHomeworks.isEmpty) return;
    HapticFeedback.mediumImpact();
    final scope = context.getInheritedWidgetOfExactType<AppProvidersScope>();
    if (scope != null) {
      await scope.settings.markAllHomeworksCompleted(pendingHomeworks);
    } else {
      final next = Set<String>.from(_fallbackCompletedHomeworkIds);
      var changed = false;
      for (final hw in pendingHomeworks) {
        final key = SettingsProvider.homeworkCompletionKey(hw).trim();
        if (key.isNotEmpty && next.add(key)) {
          changed = true;
        }
      }
      if (changed) {
        if (mounted) {
          setState(() => _fallbackCompletedHomeworkIds = next);
        }
        await SettingsProvider.saveCompletedHomeworkIdsToPrefs(next);
      }
    }
    if (!mounted) return;
    TintaToast.dismissCurrent();
    TintaToast.success(
      context,
      uwu('Összes házi feladat késznek jelölve (${pendingHomeworks.length})'),
    );
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
            oldP.transitAllowTramSubway != newP.transitAllowTramSubway ||
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
    TokenStorageService.sessionNotifier.removeListener(_onGlobalSessionChanged);
    DemoDataService.instance.revision.removeListener(_onDemoRevisionChanged);
    if (isAndroidPlatform) {
      HomeWidgetSyncService.instance.openTimetableSignal
          .removeListener(_onOpenTimetableSignal);
    }
    _settingsProvider?.removeListener(_onSettingsChangedForDemo);
    _countdownTimer?.cancel();
    _countdownTick.dispose();
    _commuteTick.dispose();
    _feedPageController.dispose();
    _tabPageController.dispose();
    super.dispose();
  }

  CommuteEvaluation? _commuteEval;
  bool _commuteLoading = false;
  final MenetrendService _menetrendService = MenetrendService();

  Future<void> _refreshCommute({bool allowDelayNotifications = true}) async {
    final epoch = ++_commuteSyncEpoch;
    try {
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
        unawaited(MenetrendService.cancelAlarms().catchError((_) {}));
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
      if (!mounted || epoch != _commuteSyncEpoch) return;
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
          ).then<void>((_) {}, onError: (_, _) {}),
        );
      }
    } catch (_) {
      if (mounted && epoch == _commuteSyncEpoch && _commuteLoading) {
        setState(() => _commuteLoading = false);
      }
    }
  }

  Future<void> _handleInPlaceReauthenticate() async {
    if (_isReauthenticating || !mounted) return;
    setState(() => _isReauthenticating = true);
    try {
      StoredSession? freshSession;
      if (widget.onReauthenticate != null) {
        freshSession = await widget.onReauthenticate!();
      } else {
        freshSession = await Navigator.of(context).push<StoredSession>(
          MaterialPageRoute(
            builder: (_) => WebViewLoginScreen(
              kretaClient: widget.kretaClient,
              initialInstituteCode: _session.instituteCode,
              initialUsername: _session.userName,
            ),
          ),
        );
      }
      if (!mounted) return;
      if (freshSession != null) {
        TokenStorageService.clearReauthRequired();
        setState(() {
          _session = freshSession!;
          _realSessionBackup = freshSession;
          _error = null;
        });
        TintaToast.success(context, 'Újrahitelesítés sikeres!');
        unawaited(_loadDashboard(silentIfCached: true));
      }
    } catch (e) {
      if (mounted) {
        TintaToast.error(context, TintaErrorState.friendlyTitleFor(e));
      }
    } finally {
      if (mounted) {
        setState(() => _isReauthenticating = false);
      }
    }
  }

  Future<void> _handleHomePullToRefresh() async {
    if (_isRefreshing) return;
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        if (_activePrefs.greetingSubtitleMode ==
            GreetingSubtitleMode.funFacts) {
          if (GreetingUtils.hasFunFactsLoaded) {
            GreetingUtils.pickFunFact(forceRefresh: true);
            _funFactEpoch++;
          } else {
            _ensureFunFactsLoadedIfNeeded();
          }
        }
      });
    }
    try {
      context
          .getInheritedWidgetOfExactType<AppProvidersScope>()
          ?.settings
          .clearAllGradeGlows();
      await _loadDashboard().timeout(const Duration(seconds: 15));
    } catch (e) {
      if (mounted && _data != null) {
        TintaToast.error(context, TintaErrorState.friendlyTitleFor(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDashboard({bool silentIfCached = false}) async {
    final loadEpoch = ++_dashboardLoadEpoch;
    if (_activePrefs.demoModeEnabled) {
      final demoData = DemoDataService.instance.buildDashboardData(
        nowOverride: widget.clock?.call(),
      );
      if (!mounted || loadEpoch != _dashboardLoadEpoch) return;
      setState(() {
        _session = demoData.activeSession;
        _data = demoData;
        _messagesOverride = null;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    try {
      if (_data == null) {
        DashboardData? cached;
        try {
          cached = await widget.kretaClient
              .loadCachedDashboard(_session)
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          cached = null;
        }
        if (!mounted ||
            loadEpoch != _dashboardLoadEpoch ||
            _activePrefs.demoModeEnabled) {
          return;
        }
        if (cached != null && _data == null) {
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
          final settings = context
              .getInheritedWidgetOfExactType<AppProvidersScope>()
              ?.settings;
          if (settings != null) {
            unawaited(settings.ingestGrades(cached.allGrades).catchError((_) {}));
          }
          if (playInitialEntrance) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _homeEntranceActive = false;
            });
          }
          unawaited(_refreshCommute(allowDelayNotifications: false));
        }
      }

      if (mounted && _data == null && loadEpoch == _dashboardLoadEpoch) {
        setState(() {
          _isLoading = true;
          _error = null;
        });
      }

      final previousRefreshToken = _session.refreshToken;
      final hadExistingData = _data != null;
      final result = await widget.kretaClient
          .fetchDashboardData(_session)
          .timeout(const Duration(seconds: 15));
      if (!mounted ||
          loadEpoch != _dashboardLoadEpoch ||
          _activePrefs.demoModeEnabled) {
        return;
      }
      TokenStorageService.clearReauthRequired();
      final playInitialEntrance =
          !_homeInitialEntrancePlayed && !silentIfCached && !hadExistingData;
      setState(() {
        _session = result.activeSession;
        _realSessionBackup = result.activeSession;
        _data = result;
        _realDataBackup = result;
        _messagesOverride = null;
        _isLoading = false;
        _error = null;
        if (playInitialEntrance) {
          _homeInitialEntrancePlayed = true;
          _homeEntranceActive = true;
        }
      });
      final settings = context
          .getInheritedWidgetOfExactType<AppProvidersScope>()
          ?.settings;
      if (settings != null) {
        unawaited(settings.ingestGrades(result.allGrades).catchError((_) {}));
      }
      if (playInitialEntrance) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeEntranceActive = false;
        });
      }
      unawaited(_refreshCommute());
      if (isAndroidPlatform) {
        unawaited(
          WearSyncService.instance
              .cacheSessionSnapshot(
                session: result.activeSession,
                student: result.student,
                nickname: _activePrefs.nickname,
                recentGrades: result.allGrades,
                upcomingExams: result.tests,
              )
              .catchError((_) => false),
        );
        if (result.activeSession.refreshToken != previousRefreshToken) {
          unawaited(
            WearSyncService.instance
                .syncSessionToWatch(
                  session: result.activeSession,
                  student: result.student,
                  nickname: _activePrefs.nickname,
                  forceSync: false,
                  recentGrades: result.allGrades,
                  upcomingExams: result.tests,
                )
                .catchError((_) => false),
          );
        }
        final dashboardDigest =
            '${WearSyncService.serializeRecentGradesJson(result.allGrades)}|${WearSyncService.serializeUpcomingExamsJson(result.tests)}';
        if ((result.student != null && !_hasPushedWearProfileMetadata) ||
            dashboardDigest != _lastWearDashboardDigest) {
          _hasPushedWearProfileMetadata = true;
          _lastWearDashboardDigest = dashboardDigest;
          unawaited(_syncWearStudentMetadataIfConnected(result));
        }
        unawaited(
          CalendarSyncService.instance
              .syncFromDashboardIfEnabled(
                result,
                prefs: _activePrefs,
                fetchLessonsForRange: (from, to) => widget.kretaClient
                    .fetchTimetableForRange(result.activeSession, from: from, to: to),
              )
              .then<void>((_) {}, onError: (_, _) {}),
        );
      }
      unawaited(
        KretaNotificationService.instance
            .processDashboardDiff(
              dashboard: result,
              profilePrefs: _activePrefs,
            )
            .then<void>((_) {}, onError: (_, _) {}),
      );
      _syncHomeWidgetsFromDashboard(result);
    } on VerifiedInvalidGrantException catch (e) {
      // ZERO AUTO-KICK POLICY:
      // Never wipe local cached data or instantly kick the user to LoginScreen!
      // Keep cached timetable/grades visible and surface the non-destructive
      // "A munkamenet lejárt - Újrahitelesítés szükséges" banner with in-place
      // KRÉTA WebAuth recovery.
      TokenStorageService.markReauthRequired(
        'A munkamenet lejárt (HTTP ${e.httpStatusCode}).',
      );
      unawaited(
        TokenStorageService.recordAuthEvent(
          caller: 'HomeScreen._loadDashboard',
          action: 'reauth_banner_shown_zero_kick',
          httpStatus: e.httpStatusCode,
          errorSnippet: e.responseBody,
        ).catchError((_) {}),
      );
      if (!mounted || loadEpoch != _dashboardLoadEpoch) return;
      setState(() {
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || loadEpoch != _dashboardLoadEpoch) return;
      final hasCached = _data != null;
      setState(() {
        _isLoading = false;
        if (!hasCached) {
          _error = e.toString();
        } else {
          _error = null;
        }
      });
      if (hasCached && !silentIfCached) {
        TintaToast.error(context, TintaErrorState.friendlyTitleFor(e));
      }
    } finally {
      if (mounted && loadEpoch == _dashboardLoadEpoch && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _syncWearStudentMetadataIfConnected(DashboardData data) async {
    if (!isAndroidPlatform) return;
    try {
      final status = await WearSyncService.instance.getConnectionStatus();
      if (!status.isConnected || !mounted) return;
      final nickname = _activePrefs.nickname;
      await WearSyncService.instance.syncSessionToWatch(
        session: data.activeSession,
        student: data.student,
        nickname: nickname,
        forceSync: false,
        recentGrades: data.allGrades,
        upcomingExams: data.tests,
      );
      if (!mounted) return;
      await WearSyncService.instance.syncDashboardToWatch(
        session: data.activeSession,
        student: data.student,
        nickname: nickname,
        recentGrades: data.allGrades,
        upcomingExams: data.tests,
      );
    } catch (_) {}
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
    final min = MinimalistTokens.of(_activePrefs);
    final btnSize = min.enabled ? 32.0 : 40.0;
    return Padding(
      padding: EdgeInsets.only(right: min.enabled ? 2 : 4),
      child: Tooltip(
        message: uwu('Üzenetek'),
        child: TactileBounce(
          onTap: _openMessagesScreen,
          child: Container(
            width: btnSize,
            height: btnSize,
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
                  size: min.enabled ? 16 : 20,
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
      now: _now(),
      uwuMode: activePrefs.uwuModeEnabled,
      funGreetingsEnabled: activePrefs.funGreetingsEnabled,
    );

    final hasAmbientBackdrop = ChristmasAndBackgroundOverlay.hasAmbientBackdrop(
      context,
      activePrefs,
    );
    final isMin = activePrefs.minimalistModeEnabled;
    final subtitleMode = activePrefs.greetingSubtitleMode;
    final isFunFactMode = subtitleMode == GreetingSubtitleMode.funFacts;
    if (!isMin && isFunFactMode && !GreetingUtils.hasFunFactsLoaded) {
      _ensureFunFactsLoadedIfNeeded();
    }
    final now = _now();
    final subtitleText = isMin
        ? null
        : GreetingUtils.buildGreetingSubtitle(
            mode: subtitleMode,
            now: now,
            todaysLessons: _data?.todaysLessons ?? const <Lesson>[],
            tests: _data?.tests ?? const <Test>[],
            hasLoadedData: _data != null,
            schoolName: student?.instituteName ?? _session.instituteCode,
            uwuMode: activePrefs.uwuModeEnabled,
          );
    if (subtitleMode == GreetingSubtitleMode.finishTime && _data != null) {
      _lastFinishTimeLabel = GreetingUtils.buildFinishTimeSubtitle(
        _data?.todaysLessons ?? const <Lesson>[],
        now,
        hasLoadedData: true,
      );
    }
    final appBarHeight = isMin
        ? 48.0
        : (subtitleText == null
            ? 60.0
            : (isFunFactMode ? 80.0 : 68.0));

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
                  toolbarHeight: appBarHeight,
                  title: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          greetingText,
                          style: (isMin
                                  ? theme.textTheme.titleSmall
                                  : theme.textTheme.titleMedium)
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                          ),
                          maxLines: 1,
                        ),
                      ),
                      if (!isMin && subtitleText != null) ...[
                        const SizedBox(height: 2),
                        Builder(
                          builder: (subCtx) {
                            final textWidget = Text(
                              subtitleText,
                              key: ValueKey<String>(
                                'home-greeting-subtitle-${subtitleMode.id}-$_funFactEpoch-$subtitleText',
                              ),
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontSize: isFunFactMode ? 12.0 : null,
                                height: isFunFactMode ? 1.24 : null,
                                color: scheme.onSurface.withValues(alpha: 0.66),
                              ),
                              maxLines: isFunFactMode ? 2 : 1,
                              overflow: TextOverflow.ellipsis,
                            );
                            final animated = AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              layoutBuilder:
                                  (currentChild, previousChildren) => Stack(
                                alignment: Alignment.centerLeft,
                                children: <Widget>[
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              ),
                              child: textWidget,
                            );
                            if (!isFunFactMode) return animated;
                            return GestureDetector(
                              key: const ValueKey<String>(
                                'home-fun-fact-tap-target',
                              ),
                              behavior: HitTestBehavior.opaque,
                              onTap: _cycleFunFact,
                              child: animated,
                            );
                          },
                        ),
                      ],
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
          body: VerticalScrollEdgeFades(
            prefs: activePrefs,
            topHeaderHeight: 0.0,
            topFeatherHeight: _selectedIndex == _timetableTabIndex ? 0.0 : 26.0,
            bottomFadeHeight: hideChromeForLandscapeTimetable ? 0.0 : 88.0,
            scrollDrivenTopFeather: true,
            child: _buildKeepAliveTabStack(theme, scheme, student, activePrefs),
          ),
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
        tests: _data?.tests ?? const <Test>[],
        omissions: _data?.omissions ?? const <Omission>[],
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
    final isDark = theme.brightness == Brightness.dark;
    final liquidGlass = _activePrefs.liquidGlassEnabled;
    final activeIconColor = liquidGlass
        ? (isDark
            ? Colors.white
            : OledTheme.semanticForeground(scheme.primary, Brightness.light))
        : scheme.onSecondaryContainer;
    final inactiveIconColor = liquidGlass
        ? (isDark
            ? Colors.white.withValues(alpha: 0.72)
            : const Color(0xFF64748B))
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

    final isMin = _activePrefs.minimalistModeEnabled;
    final dockHeight = isMin ? 48.0 : 62.0;
    final dockIconSize = isMin ? 20.0 : 25.0;
    final actionableUnexcused =
        OmissionsSummary.actionableUnexcused(_data?.omissions ?? const <Omission>[]);
    final hasUnexcusedOmissions = actionableUnexcused.isNotEmpty;
    final hasPendingExcuse =
        actionableUnexcused.any(OmissionsSummary.isPendingExcuse);
    final dotColor = hasPendingExcuse
        ? OledTheme.omissionPendingOrangeColor(theme.brightness)
        : OledTheme.omissionUnexcusedRedColor(theme.brightness);

    return RepaintBoundary(
      child: SafeArea(
        top: false,
        child: Padding(
        padding: EdgeInsets.fromLTRB(
          isMin ? 32 : 24,
          0,
          isMin ? 32 : 24,
          isMin ? 8 : 12,
        ),
        child: LiquidGlassSurface(
          prefs: _activePrefs,
          isDockStyle: true,
          borderRadius: BorderRadius.circular(isMin ? 16 : 32),
          boxShadow: isMin
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.07),
                    blurRadius: isDark ? 18 : 20,
                    offset: Offset(0, isDark ? 5 : 6),
                  ),
                ],
          child: LiquidSpringPillTrack(
            itemCount: tabs.length,
            selectedIndex: _selectedIndex,
            height: dockHeight,
            pillWidth: isMin ? 46.0 : 56.0,
            pillHeight: isMin ? 34.0 : 42.0,
            liquidGlassEnabled: liquidGlass,
            pressScale: liquidGlass ? 1.12 : 1.0,
            clipBehavior: liquidGlass ? Clip.none : Clip.hardEdge,
            clipBorderRadius:
                liquidGlass ? null : BorderRadius.circular(isMin ? 14 : 28),
            onSelected: _selectBottomTab,
            pillBuilder: (context, _) => liquidGlass
                ? LiquidGlassPillSurface(
                    pressProgress: 0.0,
                    borderRadius: BorderRadius.all(
                      Radius.circular(isMin ? 12 : 22),
                    ),
                  )
                : Material3TonalPillSurface(
                    borderRadius: BorderRadius.all(
                      Radius.circular(isMin ? 12 : 22),
                    ),
                  ),
            interactivePillBuilder: liquidGlass
                ? (context, _, pressProgress) => LiquidGlassPillSurface(
                      pressProgress: pressProgress,
                      borderRadius: BorderRadius.all(
                        Radius.circular(isMin ? 12 : 22),
                      ),
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
              final navLabel = uwuLabel(
                item.tooltip,
                enabled: _activePrefs.uwuModeEnabled,
              );
              return Semantics(
                label: navLabel,
                selected: isSelected,
                button: true,
                child: Tooltip(
                  message: navLabel,
                  triggerMode: TooltipTriggerMode.manual,
                  child: SizedBox(
                    height: dockHeight,
                    child: Center(
                      child: IconTheme(
                        data: IconThemeData(
                          color: iconColor,
                          size: dockIconSize,
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              child: Icon(
                                isSelected ? item.selectedIcon : item.icon,
                                key: ValueKey<String>(
                                  'dock-$idx-$isSelected-$isDark',
                                ),
                                size: dockIconSize,
                                color: iconColor,
                              ),
                            ),
                            if (idx == 3 && hasUnexcusedOmissions)
                              Positioned(
                                top: -2,
                                right: -3,
                                child: Container(
                                  key: const ValueKey<String>(
                                    'bottom-nav-absences-dot',
                                  ),
                                  width: isMin ? 7 : 8.5,
                                  height: isMin ? 7 : 8.5,
                                  decoration: BoxDecoration(
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark
                                          ? const Color(0xFF0A0D12)
                                          : Colors.white,
                                      width: 1.3,
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

  Widget _buildSessionExpiredBanner(ThemeData theme, ColorScheme scheme) {
    final accent = OledTheme.semanticForeground(
      const Color(0xFFF59E0B),
      theme.brightness,
    );
    return SoftGlassCard(
      key: const ValueKey<String>('home-session-expired-banner'),
      prefs: _activePrefs,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: OledTheme.semanticBadgeBg(
                    const Color(0xFFF59E0B),
                    theme.brightness,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: OledTheme.semanticBadgeBorder(
                      const Color(0xFFF59E0B),
                      theme.brightness,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.lock_clock_rounded,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uwu('A munkamenet lejárt - Újrahitelesítés szükséges'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      uwu(
                        'A gyorsítótárazott órarended és jegyeid továbbra is megtekinthetők. Jelentkezz be újra a friss adatok szinkronizálásához - minden beállításod megmarad.',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: const ValueKey<String>('home-reauth-button'),
              onPressed: _isReauthenticating
                  ? null
                  : _handleInPlaceReauthenticate,
              icon: _isReauthenticating
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login_rounded, size: 17),
              label: Text(
                uwu(
                  _isReauthenticating
                      ? 'Újrahitelesítés...'
                      : 'Újrahitelesítés (KRÉTA)',
                ),
              ),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectFeedFilter(
    ActivityFeedFilter filter, {
    bool animatePage = true,
  }) {
    if (_feedFilter != filter) {
      setState(() => _feedFilter = filter);
    }
    if (animatePage && _feedPageController.hasClients) {
      final target = filter.index;
      final curPage = _feedPageController.page?.round() ?? target;
      if (curPage != target) {
        final animEpoch = ++_feedPageAnimEpoch;
        _isAnimatingFeedPage = true;
        _feedPageController
            .animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
            )
            .whenComplete(() {
          if (!mounted || animEpoch != _feedPageAnimEpoch) return;
          if (_isAnimatingFeedPage) {
            setState(() => _isAnimatingFeedPage = false);
          }
        });
      }
    }
  }

  Widget _buildHomeTab(ThemeData theme, ColorScheme scheme) {
    final Widget tabChild;
    if (_isLoading && _data == null) {
      tabChild = HomeSkeletonFeed(
        key: const ValueKey<String>('home-skeleton-feed'),
        prefs: _activePrefs,
      );
    } else {
      final lessons = _data?.todaysLessons ?? const <Lesson>[];
      final allFeedItems = _buildAllFeedItems();
      final today = DateUtils.dateOnly(_now());
      final upcomingExamItems = <HomeActivityItem>[];
      final regularFeedItems = <HomeActivityItem>[];
      for (final item in allFeedItems) {
        if (item.test != null &&
            DateUtils.dateOnly(item.sortDate.toLocal()).isAfter(today)) {
          upcomingExamItems.add(item);
        } else {
          regularFeedItems.add(item);
        }
      }
      upcomingExamItems.sort((a, b) {
        final cmp = a.sortDate.compareTo(b.sortDate);
        if (cmp != 0) return cmp;
        final aLesson = a.test?.lessonNumber ?? 0;
        final bLesson = b.test?.lessonNumber ?? 0;
        return aLesson.compareTo(bLesson);
      });

      final allDayGroups = _groupFeedItemsByDay(regularFeedItems, today);
      final gradeImpacts = SubjectGradeSummary.computeChronologicalGradeImpacts(
        _data?.allGrades ?? const <Grade>[],
      );

      final min = MinimalistTokens.of(_activePrefs);
      final unexcusedOmissions = OmissionsSummary.actionableUnexcused(
        _data?.omissions ?? const <Omission>[],
      );
      final showUnexcusedBanner = _dismissedUnexcusedLoaded &&
          unexcusedOmissions.isNotEmpty &&
          unexcusedOmissions.any(
            (o) => !_dismissedUnexcusedOmissionIds
                .contains(OmissionsSummary.omissionIdentityKey(o)),
          );
      final equipmentItems = _resolveMissingEquipments();
      final recentCutoff = today.subtract(const Duration(days: 30));
      final recentEquipments = equipmentItems
          .where(
            (e) => !DateUtils.dateOnly(e.date.toLocal()).isBefore(recentCutoff),
          )
          .toList();

      final minPageHeight =
          (MediaQuery.sizeOf(context).height * 0.56).clamp(260.0, 760.0);
      tabChild = CustomScrollView(
        key: const ValueKey<String>('home-loaded-content'),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: min.enabled ? 4 : 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_activePrefs.demoModeEnabled)
                    ValueListenableBuilder<String?>(
                      valueListenable: TokenStorageService.reauthRequiredNotifier,
                      builder: (context, reauthReason, _) {
                        if (reauthReason == null) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            min.horizontalPagePadding,
                            0,
                            min.horizontalPagePadding,
                            min.enabled ? 8 : 16,
                          ),
                          child: _buildSessionExpiredBanner(theme, scheme),
                        );
                      },
                    ),
                  if (showUnexcusedBanner) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        min.horizontalPagePadding,
                        0,
                        min.horizontalPagePadding,
                        min.enabled ? 8 : 14,
                      ),
                      child: _buildUnexcusedOmissionBanner(
                        theme,
                        scheme,
                        unexcusedOmissions,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: min.horizontalPagePadding,
                      ),
                      child: _buildErrorCard(theme, _error!),
                    ),
                    SizedBox(height: min.enabled ? 8 : 16),
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
                      padding: EdgeInsets.symmetric(
                        horizontal: min.horizontalPagePadding,
                      ),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _countdownTick,
                        builder: (context, _, _) =>
                            _buildNextLessonHeroCard(theme, scheme, lessons),
                      ),
                    ),
                    1,
                    key: const ValueKey('home-next'),
                  ),
                  SizedBox(height: min.enabled ? 8 : 24),
                  _maybeHomeEntrance(
                    _buildFilterChipBar(theme, scheme),
                    2,
                    key: const ValueKey('home-chips'),
                  ),
                  SizedBox(height: min.enabled ? 6 : 12),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: HorizontalSubTabSwipeDetector(
              key: const ValueKey<String>('home-subtab-swipe'),
              autoHeight: true,
              minAutoHeight: minPageHeight,
              currentIndex: ActivityFeedFilter.values.indexOf(_feedFilter).clamp(
                0,
                ActivityFeedFilter.values.length - 1,
              ),
              itemCount: ActivityFeedFilter.values.length,
              pageController: _feedPageController,
              onUserDragStart: () {
                if (_isAnimatingFeedPage && mounted) {
                  setState(() => _isAnimatingFeedPage = false);
                }
              },
              onIndexChanged: (idx) => _selectFeedFilter(
                ActivityFeedFilter.values[idx],
                animatePage: false,
              ),
              pageBuilder: (pageCtx, pageIndex) {
                final pageFilter = ActivityFeedFilter.values[pageIndex];
                final isActivePage = pageFilter == _feedFilter;
                return HeroMode(
                  enabled: isActivePage,
                  child: _buildHomeFeedPageForFilter(
                    theme,
                    scheme,
                    min: min,
                    pageFilter: pageFilter,
                    today: today,
                    upcomingExamItems: upcomingExamItems,
                    allDayGroups: allDayGroups,
                    recentEquipments: recentEquipments,
                    gradeImpacts: gradeImpacts,
                    isActivePage: isActivePage,
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      displacement: 44,
      edgeOffset: 8,
      strokeWidth: 2.6,
      notificationPredicate: (notification) =>
          notification.depth == 0 && notification.metrics.axis == Axis.vertical,
      onRefresh: _handleHomePullToRefresh,
      child: ElasticOverscrollStretchWrapper(
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
      ),
    );
  }

  Widget _buildHomeFeedPageForFilter(
    ThemeData theme,
    ColorScheme scheme, {
    required MinimalistTokens min,
    required ActivityFeedFilter pageFilter,
    required DateTime today,
    required List<HomeActivityItem> upcomingExamItems,
    required List<({DateTime day, List<HomeActivityItem> items})> allDayGroups,
    required List<MissingEquipmentItem> recentEquipments,
    required Map<String, GradeImpactDelta> gradeImpacts,
    required bool isActivePage,
  }) {
    bool isFeedItemVisible(HomeActivityItem item) {
      if (!item.matchesFilter(pageFilter)) return false;
      if (pageFilter == ActivityFeedFilter.all && item.homework != null) {
        return !_isHomeworkCompleted(item.homework!);
      }
      return true;
    }

    final feedRows = <_HomeFeedRow>[];
    int visibleGroupOrdinal = 0;
    if (upcomingExamItems.isNotEmpty) {
      final matchingCount = upcomingExamItems.where(isFeedItemVisible).length;
      final groupVisible = matchingCount > 0;
      feedRows.add(
        _HomeFeedHeaderRow(
          day: today.add(const Duration(days: 1)),
          matchingCount: matchingCount,
          groupIndex: 0,
          isVisible: groupVisible,
          topSpacing: 0.0,
          customTitle: 'Közelgő számonkérések',
          isUpcomingExamsHeader: true,
        ),
      );
      for (int i = 0; i < upcomingExamItems.length; i++) {
        final item = upcomingExamItems[i];
        feedRows.add(
          _HomeFeedItemRow(
            item: item,
            itemIndex: i,
            groupIndex: 0,
            isVisible: isFeedItemVisible(item),
          ),
        );
      }
      if (groupVisible) {
        visibleGroupOrdinal++;
      }
    }

    for (int gIdx = 0; gIdx < allDayGroups.length; gIdx++) {
      final group = allDayGroups[gIdx];
      final matchingCount = group.items.where(isFeedItemVisible).length;
      final groupVisible = matchingCount > 0;
      final isFirstVisibleGroup = visibleGroupOrdinal == 0;
      final effectiveGroupIdx = upcomingExamItems.isNotEmpty ? gIdx + 1 : gIdx;
      feedRows.add(
        _HomeFeedHeaderRow(
          day: group.day,
          matchingCount: matchingCount,
          groupIndex: effectiveGroupIdx,
          isVisible: groupVisible,
          topSpacing: (groupVisible && !isFirstVisibleGroup) ? 20.0 : 0.0,
        ),
      );
      for (int i = 0; i < group.items.length; i++) {
        final item = group.items[i];
        feedRows.add(
          _HomeFeedItemRow(
            item: item,
            itemIndex: i,
            groupIndex: effectiveGroupIdx,
            isVisible: isFeedItemVisible(item),
          ),
        );
      }
      if (groupVisible) {
        visibleGroupOrdinal++;
      }
    }

    final hasAnyMatching = visibleGroupOrdinal > 0;

    return KeyedSubtree(
      key: isActivePage
          ? const ValueKey<String>('home-live-feed')
          : PageStorageKey<String>('home-live-feed-${pageFilter.name}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pageFilter == ActivityFeedFilter.homeworks &&
              (_data?.homeworks.isNotEmpty ?? false))
            KeyedSubtree(
              key: isActivePage
                  ? const ValueKey<String>('home-mark-all-hw-action')
                  : null,
              child: _buildMarkAllHomeworksButton(
                theme,
                scheme,
                (_data?.homeworks ?? const <Homework>[])
                    .where((h) => !_isHomeworkCompleted(h))
                    .toList(),
              ),
            ),
          if (pageFilter == ActivityFeedFilter.all && recentEquipments.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                min.horizontalPagePadding,
                0,
                min.horizontalPagePadding,
                min.enabled ? 6 : 10,
              ),
              child: _buildMissingEquipmentHighlightCard(
                theme,
                scheme,
                recentEquipments,
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              min.horizontalPagePadding,
              min.enabled ? 2 : 6,
              min.horizontalPagePadding,
              min.enabled ? 76 : 116,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasAnyMatching)
                  _buildEmptyStateCard(
                    theme,
                    scheme,
                    icon: Icons.inbox_rounded,
                    message: uwu(
                      'Nincs megjeleníthető elem ebben a kategóriában.',
                    ),
                  ),
                for (final row in feedRows)
                  _buildFeedRowWidget(
                    theme,
                    scheme,
                    row,
                    today,
                    gradeImpacts: gradeImpacts,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedRowWidget(
    ThemeData theme,
    ColorScheme scheme,
    _HomeFeedRow row,
    DateTime today, {
    Map<String, GradeImpactDelta> gradeImpacts = const {},
  }) {
    if (row is _HomeFeedHeaderRow) {
      final header = _buildFeedDayHeaderRow(
        theme,
        scheme,
        row.day,
        row.matchingCount,
        today,
        topSpacing: row.topSpacing,
        customTitle: row.customTitle,
        isUpcomingExamsHeader: row.isUpcomingExamsHeader,
      );
      return RepaintBoundary(
        key: ValueKey(
          row.isUpcomingExamsHeader
              ? 'day-boundary-upcoming-exams'
              : 'day-boundary-${row.day.toIso8601String()}',
        ),
        child: _CollapsibleFeedItem(
          visible: row.isVisible,
          child: _maybeHomeEntrance(
            header,
            row.groupIndex < 6 ? row.groupIndex + 2 : 8,
            key: ValueKey(
              row.isUpcomingExamsHeader
                  ? 'day-upcoming-exams'
                  : 'day-${row.day.toIso8601String()}',
            ),
          ),
        ),
      );
    }
    final itemRow = row as _HomeFeedItemRow;
    final tile = Padding(
      padding: EdgeInsets.only(top: itemRow.itemIndex > 0 ? 2 : 0),
      child: _buildActivityFeedTile(
        theme,
        scheme,
        itemRow.item,
        gradeImpacts: gradeImpacts,
      ),
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
    String? customTitle,
    bool isUpcomingExamsHeader = false,
  }) {
    final min = MinimalistTokens.of(_activePrefs);
    final effectiveTop = min.enabled && topSpacing > 0 ? 8.0 : topSpacing;
    if (isUpcomingExamsHeader) {
      final subtleAmber = OledTheme.semanticForeground(
        const Color(0xFFF59E0B),
        theme.brightness,
      );
      return Padding(
        padding: EdgeInsets.fromLTRB(
          4,
          effectiveTop,
          4,
          min.enabled ? 4 : 8,
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_note_rounded,
              size: min.enabled ? 13 : 16,
              color: subtleAmber,
            ),
            const SizedBox(width: 6),
            Text(
              uwu(customTitle ?? 'Közelgő számonkérések'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontSize: min.enabled ? 12 : 14.5,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                letterSpacing: 0.1,
              ),
            ),
            const Spacer(),
            if (min.enabled)
              Text(
                '$matchingCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: subtleAmber,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: OledTheme.semanticBadgeBg(
                    const Color(0xFFF59E0B),
                    theme.brightness,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$matchingCount',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: subtleAmber,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isUpcomingDay = day.isAfter(today);
    final upcomingAmber = OledTheme.semanticForeground(
      const Color(0xFFF59E0B),
      theme.brightness,
    );
    final isTomorrow = day == today.add(const Duration(days: 1));
    final title = customTitle ?? _formatDaySectionTitle(day, today);
    final weekday = _weekdayNamesHu[day.weekday.clamp(1, 7)];
    // For later future days ("Nov. 16. • Hétfő"), weekday is already in title;
    // for tomorrow ("Holnap • Nov. 13.") and today/past, show weekday alongside.
    final showSecondaryWeekday = !isUpcomingDay || isTomorrow;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        4,
        effectiveTop,
        4,
        min.enabled ? 4 : 10,
      ),
      child: Row(
        children: [
          if (isUpcomingDay) ...[
            Icon(
              Icons.upcoming_rounded,
              size: min.enabled ? 13 : 16,
              color: upcomingAmber,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            uwuLabel(title, enabled: _activePrefs.uwuModeEnabled),
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: min.enabled ? 12 : 15,
              fontWeight: FontWeight.w900,
              color: isUpcomingDay ? upcomingAmber : scheme.onSurface,
              letterSpacing: 0.2,
            ),
          ),
          if (showSecondaryWeekday) ...[
            const SizedBox(width: 8),
            Text(
              uwuLabel(weekday, enabled: _activePrefs.uwuModeEnabled),
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: min.enabled ? 11 : null,
                color: scheme.onSurface.withValues(alpha: 0.52),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const Spacer(),
          if (min.enabled)
            Text(
              '$matchingCount',
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 11,
                color: isUpcomingDay
                    ? upcomingAmber
                    : scheme.onSurface.withValues(alpha: 0.65),
                fontWeight: FontWeight.w800,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: isUpcomingDay
                    ? OledTheme.semanticBadgeBg(
                        const Color(0xFFF59E0B),
                        theme.brightness,
                      )
                    : scheme.surfaceContainerHigh.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$matchingCount',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isUpcomingDay
                      ? upcomingAmber
                      : scheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the restrained, de-AI-ified 'Következő óra' / Live Activity hero
  /// card aligned visually with the refined Home feed cards.
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
    final isDark = theme.brightness == Brightness.dark;

    final remainingCount = status.remainingLessonsCount;
    final rightCountText = remainingCount <= 0
        ? ''
        : (remainingCount == 1 ? 'Utolsó óra' : 'Még $remainingCount óra');

    final heroTag =
        currentOrNext != null ? 'home_lesson_num_${currentOrNext.uid}' : null;

    Widget buildHeroPeriodBadge() {
      final lesson = currentOrNext!;
      final accent = scheme.primary;
      final periodLabel =
          lesson.lessonNumber != null ? '${lesson.lessonNumber}.' : '•';
      return Hero(
        tag: heroTag!,
        createRectTween: createLinearHeroRectTween,
        flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
        child: Material(
          type: MaterialType.transparency,
          child: PeriodCountdownBadge(
            label: periodLabel,
            backgroundColor: accent.withValues(alpha: 0.14),
            border: Border.all(
              color: accent.withValues(alpha: 0.24),
              width: 1.0,
            ),
            textStyle: theme.textTheme.titleMedium!.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            ringColor: accent,
            startTime: isOngoing ? lesson.start.toLocal() : null,
            endTime: isOngoing ? lesson.end.toLocal() : null,
            clock: widget.clock,
            remainingFraction: null,
            outerSize: 54,
            innerSize: 40,
            idleSize: 44,
            idleShape: BoxShape.circle,
            strokeWidth: 3.5,
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

    final String timeAndRoomMeta;
    final String teacherMeta;
    final bool isSubTeacher;
    if (currentOrNext != null) {
      final timeRangeStr =
          '${_timeFormat.format(currentOrNext.start.toLocal())} - ${_timeFormat.format(currentOrNext.end.toLocal())}';
      final cleanRoom = (currentOrNext.roomName ?? '').trim();
      timeAndRoomMeta =
          cleanRoom.isNotEmpty ? '$timeRangeStr • $cleanRoom' : timeRangeStr;

      final subName = currentOrNext.substituteTeacher?.trim() ?? '';
      isSubTeacher = subName.isNotEmpty;
      final rawTeacher = isSubTeacher ? subName : (currentOrNext.teacher?.trim() ?? '');
      teacherMeta = rawTeacher.isEmpty
          ? ''
          : (isSubTeacher
              ? 'Helyettes: ${activePrefs.resolveTeacherName(rawTeacher)}'
              : activePrefs.resolveTeacherName(rawTeacher));
    } else {
      timeAndRoomMeta = '';
      teacherMeta = '';
      isSubTeacher = false;
    }

    final min = MinimalistTokens.of(activePrefs);
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
          padding: min.enabled
              ? const EdgeInsets.symmetric(horizontal: 11, vertical: 9)
              : const EdgeInsets.all(18),
          borderRadius: min.cardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (status.phase != NextLessonPhase.completedForToday) ...[
                Row(
                  children: [
                    Text(
                      uwu(
                        isOngoing
                            ? 'FOLYAMATBAN'
                            : isBreak
                                ? 'SZÜNET'
                                : 'KÖVETKEZŐ ÓRA',
                      ).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: min.enabled ? 9.5 : 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: (isOngoing || isBreak)
                            ? scheme.primary.withValues(alpha: 0.85)
                            : scheme.onSurface.withValues(alpha: 0.50),
                      ),
                    ),
                    const Spacer(),
                    if (isOngoing && currentOrNext != null)
                      LiveCountdownProgressScope(
                        startTime: currentOrNext.start.toLocal(),
                        endTime: currentOrNext.end.toLocal(),
                        clock: widget.clock,
                        builder: (_, snap) => Text(
                          uwu(snap.formattedCompactRemaining(suffix: ' hátra')),
                          maxLines: 1,
                          softWrap: false,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontSize: min.enabled ? 10.5 : 12,
                            color: scheme.onSurface.withValues(alpha: 0.56),
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      )
                    else
                      Text(
                        uwu(rightCountText),
                        maxLines: 1,
                        softWrap: false,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: min.enabled ? 10.5 : 12,
                          color: scheme.onSurface.withValues(alpha: 0.56),
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: min.enabled ? 6 : 12),
              ],
              if (status.phase == NextLessonPhase.completedForToday ||
                  currentOrNext == null)
                Row(
                  children: [
                    Icon(
                      Icons.celebration_rounded,
                      color: scheme.primary,
                      size: 26,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            uwu('Ma már nincs több órád!'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            uwu(
                              status.totalLessonsCount > 0
                                  ? 'Mind a(z) ${status.totalLessonsCount} mai tanóra lezajlott. Koppints a teljes órarendért!'
                                  : 'Mára nincs rögzített tanóra. Koppints a heti órarend megnyitásához!',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.62),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              else ...[
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
                            uwuLabel(
                              currentSubjTitle,
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              height: 1.18,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            uwuLabel(
                              timeAndRoomMeta,
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface.withValues(alpha: 0.76),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (teacherMeta.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              uwuLabel(
                                teacherMeta,
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                                fontWeight: isSubTeacher
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSubTeacher
                                    ? OledTheme.semanticForeground(
                                        const Color(0xFFF59E0B),
                                        theme.brightness,
                                      )
                                    : scheme.onSurface.withValues(alpha: 0.56),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (isOngoing) ...[
                  const SizedBox(height: 14),
                  Divider(
                    color: theme.dividerColor.withValues(alpha: 0.65),
                    height: 1,
                  ),
                  const SizedBox(height: 12),
                  _buildUpcomingNextLessonRow(theme, scheme, upcoming),
                ] else if (status.phase == NextLessonPhase.beforeFirstFarAway ||
                    status.phase ==
                        NextLessonPhase.beforeFirstWithinTwoHours) ...[
                  const SizedBox(height: 12),
                  _PreClassCountdownBanner(
                    targetStartLocal: currentOrNext.start.toLocal(),
                    textTransform: (s) => uwuLabel(
                      s,
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    clock: widget.clock,
                    onReachedStart: () {
                      if (mounted) _countdownTick.value++;
                    },
                  ),
                ] else if (isBreak && status.previousLesson != null) ...[
                  const SizedBox(height: 12),
                  LiveCountdownProgressScope(
                    startTime: status.previousLesson!.end.toLocal(),
                    endTime: currentOrNext.start.toLocal(),
                    clock: widget.clock,
                    builder: (_, snap) {
                      final elapsed = (1.0 - snap.progress).clamp(0.02, 1.0);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            uwu(
                              'Kezdés: ${snap.formattedCompactRemaining(suffix: ' múlva')}',
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 7),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: elapsed,
                              minHeight: 3.5,
                              backgroundColor: scheme.onSurface.withValues(
                                alpha: isDark ? 0.10 : 0.08,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Text(
                    uwuLabel(
                      status.countdownLabel,
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
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
      return Text(
        uwu('Utolsó óra ma • Utána vége a tanításnak!'),
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurface.withValues(alpha: 0.65),
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final rawNext = upcoming.subject?.name ?? upcoming.name;
    final nextSubj = widget.prefs.resolveSubjectName(
      rawNext,
      upcoming.subject?.uid,
    );
    final periodLabel =
        upcoming.lessonNumber != null ? '${upcoming.lessonNumber}.' : '•';

    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.14),
            shape: BoxShape.circle,
            border: Border.all(
              color: scheme.primary.withValues(alpha: 0.24),
              width: 1.0,
            ),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(
                left: periodLabel.endsWith('.') ? 1.5 : 0.0,
              ),
              child: Text(
                periodLabel,
                textAlign: TextAlign.center,
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uwuLabel(
                  'Következő: $nextSubj',
                  enabled: _activePrefs.uwuModeEnabled,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              Text(
                uwuLabel(
                  '${_timeFormat.format(upcoming.start.toLocal())} - ${_timeFormat.format(upcoming.end.toLocal())}'
                  '${upcoming.roomName != null && upcoming.roomName!.trim().isNotEmpty ? ' • ${upcoming.roomName!.trim()}' : ''}',
                  enabled: _activePrefs.uwuModeEnabled,
                ),
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

  Widget _buildMarkAllHomeworksButton(
    ThemeData theme,
    ColorScheme scheme,
    List<Homework> pendingHomeworks,
  ) {
    final hwColor = OledTheme.semanticForeground(
      const Color(0xFF00BFA5),
      theme.brightness,
    );
    const hwBase = Color(0xFF00BFA5);
    final hasPending = pendingHomeworks.isNotEmpty;
    final foreground =
        hasPending ? hwColor : scheme.onSurface.withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: hasPending
                ? () => _markAllPendingHomeworksCompleted(pendingHomeworks)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: hasPending
                    ? hwBase.withValues(alpha: 0.12)
                    : scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasPending
                      ? hwColor.withValues(alpha: 0.32)
                      : scheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.done_all_rounded,
                    size: 16,
                    color: foreground,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      uwu('Összes házi megjelölése készként'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
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

  Widget _buildFilterChipBar(ThemeData theme, ColorScheme scheme) {
    final selectedIndex = ActivityFeedFilter.values.indexOf(_feedFilter);
    final min = MinimalistTokens.of(_activePrefs);
    return LiquidBubbleTabBar(
      height: min.tabBarHeight,
      fontSize: min.tabFontSize,
      padding: EdgeInsets.symmetric(horizontal: min.horizontalPagePadding),
      itemPadding: min.enabled
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3)
          : const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      liquidGlassEnabled: _activePrefs.liquidGlassEnabled,
      pageController: _feedPageController,
      ignorePageController: _isAnimatingFeedPage,
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      items: [
        for (final filter in ActivityFeedFilter.values)
          LiquidBubbleTabItem(
            label: uwu(filter.label),
            icon: filter.icon,
          ),
      ],
      onSelected: (idx) => _selectFeedFilter(ActivityFeedFilter.values[idx]),
    );
  }

  List<MissingEquipmentItem> _resolveMissingEquipments() {
    final stored = _data?.missingEquipments ?? const <MissingEquipmentItem>[];
    final derived = MissingEquipmentItem.extractMissingEquipments(
      grades: _data?.allGrades ?? const <Grade>[],
      omissions: _data?.omissions ?? const <Omission>[],
      messages: _data?.messages ?? const <KretaMessage>[],
    );
    return MissingEquipmentItem.deduplicateAndSort([...stored, ...derived]);
  }

  List<HomeActivityItem> _buildAllFeedItems() {
    final grades = (_data?.allGrades ?? const <Grade>[])
        .where((g) => !MissingEquipmentItem.isMissingEquipmentGrade(g));
    final homeworks = _data?.homeworks ?? const <Homework>[];
    final tests = _data?.tests ?? const <Test>[];
    final equipments = _resolveMissingEquipments();

    return <HomeActivityItem>[
      ...grades.map(HomeActivityItem.grade),
      ...homeworks.map(HomeActivityItem.homework),
      ...tests.map(HomeActivityItem.test),
      ...equipments.map(HomeActivityItem.missingEquipment),
    ];
  }

  Widget _buildActivityFeedTile(
    ThemeData theme,
    ColorScheme scheme,
    HomeActivityItem item, {
    Map<String, GradeImpactDelta> gradeImpacts = const {},
  }) {
    if (item.grade != null) {
      final g = item.grade!;
      return _buildGradeFeedCard(
        theme,
        scheme,
        g,
        impactDelta: gradeImpacts[SubjectGradeSummary.gradeImpactKey(g)],
      );
    }
    if (item.homework != null) {
      return _buildHomeworkFeedCard(theme, scheme, item.homework!);
    }
    if (item.missingEquipment != null) {
      return _buildMissingEquipmentFeedCard(
        theme,
        scheme,
        item.missingEquipment!,
      );
    }
    return _buildTestFeedCard(theme, scheme, item.test!);
  }

  Widget _buildUnexcusedOmissionBanner(
    ThemeData theme,
    ColorScheme scheme,
    List<Omission> unexcusedOmissions,
  ) {
    final min = MinimalistTokens.of(_activePrefs);
    final hasPending = unexcusedOmissions.any(OmissionsSummary.isPendingExcuse);
    final accent = hasPending
        ? OledTheme.omissionPendingOrangeColor(theme.brightness)
        : OledTheme.omissionUnexcusedRedColor(theme.brightness);
    final absenceCount =
        unexcusedOmissions.where((o) => !OmissionsSummary.isTardiness(o)).length;
    final lateCount = unexcusedOmissions.length - absenceCount;

    final String headline;
    if (absenceCount > 0 && lateCount > 0) {
      headline = hasPending
          ? '$absenceCount hiányzás és $lateCount késés igazolásra vár'
          : '$absenceCount igazolatlan hiányzás és $lateCount késés';
    } else if (lateCount > 0) {
      headline = hasPending
          ? '$lateCount igazolandó késés'
          : '$lateCount igazolatlan késés';
    } else {
      headline = hasPending
          ? '$absenceCount igazolandó hiányzás'
          : '$absenceCount igazolatlan hiányzás';
    }

    final latest = unexcusedOmissions.first;
    final subj = _activePrefs.resolveSubjectName(
      latest.subject.name,
      latest.subject.uid,
    );
    final dayStr = _formatFeedCardDate(latest.date);
    final classNoStr = latest.lesson?.classNo != null
        ? ' • ${latest.lesson!.classNo}. óra'
        : '';
    final extraCount = unexcusedOmissions.length - 1;
    final detailLine = extraCount > 0
        ? '$subj • $dayStr$classNoStr (+$extraCount további)'
        : '$subj • $dayStr$classNoStr';

    return TactileBounce(
      pressedScale: 0.985,
      onTap: () => _selectBottomTab(3),
      child: SoftGlassCard(
        key: const ValueKey<String>('home-unexcused-banner'),
        prefs: _activePrefs,
        padding: min.enabled
            ? const EdgeInsets.fromLTRB(10, 8, 6, 8)
            : const EdgeInsets.fromLTRB(14, 12, 8, 12),
        borderRadius: min.enabled ? min.cardRadius : OledTheme.largeRadius,
        border: Border.all(
          color: accent.withValues(alpha: 0.56),
          width: min.enabled ? 1.0 : 1.3,
        ),
        child: Row(
          children: [
            Container(
              width: min.enabled ? 30 : 38,
              height: min.enabled ? 30 : 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.42)),
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: accent,
                size: min.enabled ? 16 : 20,
              ),
            ),
            SizedBox(width: min.enabled ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    uwuLabel(headline, enabled: _activePrefs.uwuModeEnabled),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: (min.enabled
                            ? theme.textTheme.labelMedium
                            : theme.textTheme.titleSmall)
                        ?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    uwuLabel(detailLine, enabled: _activePrefs.uwuModeEnabled),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: min.enabled ? 10.5 : 12,
                      color: scheme.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              key: const ValueKey<String>('home-unexcused-banner-dismiss'),
              tooltip: 'Elrejtés',
              visualDensity: VisualDensity.compact,
              onPressed: () => _dismissUnexcusedBanner(unexcusedOmissions),
              icon: Icon(
                Icons.close_rounded,
                size: min.enabled ? 16 : 18,
                color: scheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingEquipmentHighlightCard(
    ThemeData theme,
    ColorScheme scheme,
    List<MissingEquipmentItem> recentItems,
  ) {
    final min = MinimalistTokens.of(_activePrefs);
    final orange = OledTheme.omissionPendingOrangeColor(theme.brightness);
    final latest = recentItems.first;
    final dayStr = _formatFeedCardDate(latest.date);
    final noteClean = latest.note.trim();
    final teacherClean = _activePrefs.resolveTeacherName(latest.teacher).trim();
    final detailParts = <String>[
      latest.subjectName,
      dayStr,
      if (teacherClean.isNotEmpty) teacherClean,
    ];

    return TactileBounce(
      pressedScale: 0.985,
      onTap: () => _openMissingEquipmentModal(latest),
      child: SoftGlassCard(
        key: const ValueKey<String>('home-missing-equipment-card'),
        prefs: _activePrefs,
        padding: min.tilePadding,
        borderRadius: min.cardRadius,
        border: Border.all(
          color: orange.withValues(alpha: 0.42),
          width: min.borderWidth,
        ),
        child: Row(
          children: [
            Container(
              width: min.enabled ? 28 : 38,
              height: min.enabled ? 28 : 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: orange.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: orange.withValues(alpha: 0.34)),
              ),
              child: Icon(
                Icons.backpack_outlined,
                color: orange,
                size: min.enabled ? 15 : 19,
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
                      Text(
                        uwuLabel(
                          recentItems.length > 1
                              ? 'Felszereléshiány (${recentItems.length})'
                              : 'Felszereléshiány',
                          enabled: _activePrefs.uwuModeEnabled,
                        ),
                        style: TextStyle(
                          fontSize: min.enabled ? 12 : 13,
                          fontWeight: FontWeight.w800,
                          color: orange,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          uwuLabel(
                            detailParts.join(' • '),
                            enabled: _activePrefs.uwuModeEnabled,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: min.enabled ? 10.5 : 11.5,
                            color: scheme.onSurface.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (noteClean.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      uwuLabel(noteClean, enabled: _activePrefs.uwuModeEnabled),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: min.enabled ? 10.5 : 12,
                        color: scheme.onSurface.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: min.enabled ? 15 : 18,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingEquipmentFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    MissingEquipmentItem item,
  ) {
    final min = MinimalistTokens.of(_activePrefs);
    final orange = OledTheme.omissionPendingOrangeColor(theme.brightness);
    final dayStr = _formatFeedCardDate(item.date);
    final teacherClean = _activePrefs.resolveTeacherName(item.teacher).trim();
    final noteClean = item.note.trim();
    final primary = noteClean.isNotEmpty ? noteClean : item.title;
    final subParts = <String>[
      item.subjectName,
      if (teacherClean.isNotEmpty) teacherClean,
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: min.cardGap),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => _openMissingEquipmentModal(item),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            key: ValueKey<String>('home-equipment-item-${item.uid}'),
            prefs: _activePrefs,
            padding: min.tilePadding,
            borderRadius: min.cardRadius,
            border: Border.all(
              color: orange.withValues(alpha: 0.34),
              width: min.borderWidth,
            ),
            child: Row(
              children: [
                Container(
                  width: min.enabled ? 28 : 42,
                  height: min.enabled ? 28 : 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: OledTheme.semanticBadgeBg(orange, theme.brightness),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: orange.withValues(alpha: 0.38),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    Icons.backpack_outlined,
                    color: orange,
                    size: min.enabled ? 15 : 20,
                  ),
                ),
                SizedBox(width: min.enabled ? 9 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        uwuLabel(primary, enabled: _activePrefs.uwuModeEnabled),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: min.enabled ? 12.5 : 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: min.enabled ? 1 : 2),
                      Text(
                        uwuLabel(
                          'Felszereléshiány • ${subParts.join(' • ')}',
                          enabled: _activePrefs.uwuModeEnabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: min.enabled ? 10.5 : 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: min.enabled ? 6 : 10),
                Text(
                  uwuLabel(dayStr, enabled: _activePrefs.uwuModeEnabled),
                  style: TextStyle(
                    fontSize: min.enabled ? 10.5 : 11.5,
                    color: orange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMissingEquipmentModal(MissingEquipmentItem item) {
    final orange = OledTheme.omissionPendingOrangeColor(
      Theme.of(context).brightness,
    );
    final teacherClean = _activePrefs.resolveTeacherName(item.teacher).trim();
    showFrostedModal(
      context: context,
      closeMode: _activePrefs.modalCloseMode,
      prefs: _activePrefs,
      categoryIcon: Icons.backpack_outlined,
      accentColor: orange,
      title: 'Felszereléshiány',
      subtitle: item.subjectName,
      badgeText: '!',
      badgeShape: BoxShape.circle,
      rows: [
        FrostedDetailRow(label: 'Tantárgy', value: item.subjectName),
        FrostedDetailRow(
          label: 'Dátum',
          value: DateFormat('yyyy. MM. dd. HH:mm').format(item.date.toLocal()),
        ),
        if (teacherClean.isNotEmpty)
          FrostedDetailRow(label: 'Tanár', value: teacherClean),
        if (item.note.trim().isNotEmpty)
          FrostedDetailRow(label: 'Megjegyzés', value: item.note.trim()),
      ],
    );
  }

  /// Compact, uniform grade card on Főoldal with translucent tinted badge,
  /// auto-capitalized topic-first hierarchy, and right-side average impact delta.
  Widget _buildGradeFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Grade grade, {
    GradeImpactDelta? impactDelta,
  }) {
    final badgeColor = OledTheme.gradeColor(grade.numericValue, widget.prefs);
    final badgeText = grade.numericValue?.toString() ??
        grade.shortStrValue ??
        (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');

    final cleanTopic = OledTheme.capitalizeFirst(grade.topic ?? '');
    final hasTopic = cleanTopic.isNotEmpty;
    final rawModeOrType = (grade.mode?.description.trim().isNotEmpty == true)
        ? grade.mode!.description
        : grade.type.description;
    final modeOrType = OledTheme.capitalizeFirst(rawModeOrType);

    final subjectDisplay = widget.prefs.resolveSubjectName(
      grade.subject.name,
      grade.subject.uid,
    );
    final primaryTitle = hasTopic ? cleanTopic : subjectDisplay;
    final secondarySub = hasTopic ? subjectDisplay : modeOrType;
    final weightPct =
        (grade.weightPercentage != null && grade.weightPercentage! > 0)
            ? grade.weightPercentage!
            : 100;
    final resolvedImpact = impactDelta ??
        SubjectGradeSummary.computeChronologicalGradeImpacts(
          _data?.allGrades ?? <Grade>[grade],
        )[SubjectGradeSummary.gradeImpactKey(grade)];

    final heroTag = 'home_grade_${grade.uid}';
    final settings = AppProvidersScope.maybeOf(context)?.settings;
    final min = MinimalistTokens.of(_activePrefs);

    Widget buildCard(bool isGlowing) {
      return Padding(
        padding: EdgeInsets.only(bottom: min.cardGap),
        child: TactileBounce(
          pressedScale: 0.97,
          onTap: () {
            settings?.dismissGradeGlow(grade);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            showGradeInspectionModal(
              context,
              grade,
              prefs: _activePrefs,
              heroTag: heroTag,
              impactDeltaText: resolvedImpact?.formattedDelta,
              impactDeltaColor: resolvedImpact?.resolveSemanticColor(isDark),
            );
          },
          child: ChristmasSnowCap(
            enabled: widget.prefs.christmasModeEnabled,
            child: GradeFirstSeenGlow(
              isGlowing: isGlowing,
              accentColor: badgeColor,
              borderRadius: min.cardRadius,
              child: SoftGlassCard(
                prefs: _activePrefs,
                padding: min.tilePadding,
                borderRadius: min.cardRadius,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Hero(
                      tag: heroTag,
                      createRectTween: createLinearHeroRectTween,
                      flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
                      child: Material(
                        type: MaterialType.transparency,
                        child: TranslucentGradeBadge(
                          text: badgeText,
                          color: badgeColor,
                          size: min.enabled ? 28 : 38,
                          fontSize: min.enabled ? 13 : 16,
                        ),
                      ),
                    ),
                    SizedBox(width: min.enabled ? 9 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            uwuLabel(
                              primaryTitle,
                              enabled: _activePrefs.uwuModeEnabled,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: min.enabled ? 12.5 : 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: min.enabled ? 1 : 2),
                          Text(
                            uwuLabel(
                              secondarySub,
                              enabled: _activePrefs.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: min.enabled ? 10.5 : 11.5,
                              fontWeight: FontWeight.w500,
                              color: scheme.onSurface.withValues(alpha: 0.68),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if ((resolvedImpact != null && resolvedImpact.isNumeric) ||
                        weightPct != 100) ...[
                      const SizedBox(width: 10),
                      GradeImpactDeltaLabel(
                        impact: resolvedImpact,
                        weightPercentage: weightPct,
                      ),
                    ],
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
    final hwColor = OledTheme.semanticForeground(
      const Color(0xFF00BFA5),
      theme.brightness,
    );
    const hwBase = Color(0xFF00BFA5);
    final rawSubjectTitle = homework.subject.name.isNotEmpty
        ? homework.subject.name
        : homework.subjectName;
    final subjectTitle = widget.prefs.resolveSubjectName(
      rawSubjectTitle,
      homework.subject.uid,
    );
    final cleanText = Homework.stripHtmlTags(homework.description).trim();
    final previewText = cleanText.isEmpty ? uwu('Nincs leírás') : cleanText;
    final heroTag = 'home_hw_${homework.uid}';
    final isCompleted = _isHomeworkCompleted(homework);
    final min = MinimalistTokens.of(_activePrefs);

    return Padding(
      padding: EdgeInsets.only(bottom: min.cardGap),
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
            padding: min.tilePadding,
            borderRadius: min.cardRadius,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              opacity: isCompleted ? 0.58 : 1.0,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Hero(
                    tag: heroTag,
                    createRectTween: createLinearHeroRectTween,
                    flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        width: min.enabled ? 28 : 38,
                        height: min.enabled ? 28 : 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: hwBase.withValues(
                            alpha: isCompleted ? 0.11 : 0.14,
                          ),
                          borderRadius: min.badgeRadius,
                          border: Border.all(
                            color: hwColor.withValues(
                              alpha: isCompleted ? 0.28 : 0.42,
                            ),
                          ),
                        ),
                        child: Icon(
                          isCompleted
                              ? Icons.task_alt_rounded
                              : Icons.menu_book_rounded,
                          color: hwColor,
                          size: min.enabled ? 15 : 19,
                        ),
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
                            Expanded(
                              child: Text(
                                uwuLabel(
                                  subjectTitle,
                                  enabled: _activePrefs.uwuModeEnabled,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: min.enabled ? 12.5 : 13.5,
                                  fontWeight: FontWeight.w700,
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
                              uwuLabel(
                                'Határidő: ${_formatFeedCardDate(homework.dueDate)}',
                                enabled: _activePrefs.uwuModeEnabled,
                              ),
                              style: TextStyle(
                                fontSize: min.enabled ? 10 : 11,
                                color: hwColor,
                                fontWeight: FontWeight.w700,
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: min.enabled ? 1 : 2),
                        Text(
                          cleanText.isEmpty
                              ? uwuLabel(
                                  'Nincs leírás',
                                  enabled: _activePrefs.uwuModeEnabled,
                                )
                              : uwu(
                                  previewText,
                                  enabled: _activePrefs.uwuModeEnabled,
                                ),
                          style: TextStyle(
                            fontSize: min.enabled ? 10.5 : 11.5,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface.withValues(alpha: 0.68),
                            decoration: isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: isCompleted
                        ? uwu('Visszavonás (aktívvá tétel)')
                        : uwu('Megjelölés készként'),
                    child: InkResponse(
                      radius: 20,
                      onTap: () =>
                          _toggleHomeworkCompletion(homework, subjectTitle),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            isCompleted
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            key: ValueKey<bool>(isCompleted),
                            size: 22,
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

  /// Announced exam / test card redesigned to match the refined grade cards:
  /// circular translucent badge, clean 2-line auto-capitalized hierarchy, and
  /// subtle right-side date without heavy pill clutter.
  Widget _buildTestFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Test test,
  ) {
    const testBase = Color(0xFFF59E0B);
    final testColor = OledTheme.semanticForeground(
      testBase,
      theme.brightness,
    );
    const shortWeekdaysHu = ['', 'H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];
    final testLocal = test.date.toLocal();
    final monthStr = _shortMonthsHu[(testLocal.month - 1).clamp(0, 11)];
    final weekdayShort = shortWeekdaysHu[testLocal.weekday.clamp(1, 7)];
    final conciseDatePill = OledTheme.capitalizeFirst(
      '$monthStr ${testLocal.day}., $weekdayShort',
    );
    final rawSubjectTitle =
        test.subject.name.isNotEmpty ? test.subject.name : test.subjectName;
    final subjectTitle = widget.prefs.resolveSubjectName(
      rawSubjectTitle,
      test.subject.uid,
    );
    final heroTag = 'home_test_${test.uid}';
    final cleanTheme = OledTheme.capitalizeFirst(test.theme ?? '');
    final cleanMethod = OledTheme.capitalizeFirst(test.method.description);
    final primaryTitle = cleanTheme.isNotEmpty
        ? cleanTheme
        : (cleanMethod.isNotEmpty ? cleanMethod : subjectTitle);
    final lessonPart = test.lessonNumber > 0
        ? ' • ${test.lessonNumber}. óra'
        : (cleanTheme.isNotEmpty && cleanMethod.isNotEmpty
            ? ' • $cleanMethod'
            : '');
    final secondarySub = '$subjectTitle$lessonPart';
    final isDark = theme.brightness == Brightness.dark;
    final min = MinimalistTokens.of(_activePrefs);

    return Padding(
      padding: EdgeInsets.only(bottom: min.cardGap),
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
            padding: min.tilePadding,
            borderRadius: min.cardRadius,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Hero(
                  tag: heroTag,
                  createRectTween: createLinearHeroRectTween,
                  flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      width: min.enabled ? 28 : 42,
                      height: min.enabled ? 28 : 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: OledTheme.semanticBadgeBg(
                          testBase,
                          theme.brightness,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: OledTheme.semanticBadgeBorder(
                            testBase,
                            theme.brightness,
                          ),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(
                        Icons.assignment_outlined,
                        color: testColor,
                        size: min.enabled ? 15 : 20,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: min.enabled ? 9 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        uwuLabel(
                          primaryTitle,
                          enabled: _activePrefs.uwuModeEnabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: min.enabled ? 12.5 : 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: min.enabled ? 1 : 2),
                      Text(
                        uwuLabel(
                          secondarySub,
                          enabled: _activePrefs.uwuModeEnabled,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: min.enabled ? 10.5 : 11.5,
                          color: scheme.onSurface.withValues(alpha: 0.68),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: min.enabled ? 6 : 10),
                Text(
                  uwuLabel(
                    conciseDatePill,
                    enabled: _activePrefs.uwuModeEnabled,
                  ),
                  style: TextStyle(
                    fontSize: min.enabled ? 10.5 : 11.5,
                    color: isDark
                        ? testColor.withValues(alpha: 0.9)
                        : const Color(0xFFB45309),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
    return TintaErrorState(
      error: error,
      prefs: _activePrefs,
      compact: _data != null,
      onRetry: () => _loadDashboard(silentIfCached: false),
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
              uwu(message, enabled: _activePrefs.uwuModeEnabled),
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
    this.customTitle,
    this.isUpcomingExamsHeader = false,
  });

  final DateTime day;
  final int matchingCount;
  final int groupIndex;
  final bool isVisible;
  final double topSpacing;
  final String? customTitle;
  final bool isUpcomingExamsHeader;
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
