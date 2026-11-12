import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/github_updater_service.dart';
import '../services/kreta_client.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/expandable_profile_card.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/menetrend_hero_card.dart';
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
    required this.headline,
    required this.countdownLabel,
    required this.remainingLessonsCount,
    required this.totalLessonsCount,
    this.remainingFraction = 1.0,
    this.remainingMinutes = 0,
  });

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

    if (totalCount == 0 || remainingCount == 0) {
      return NextLessonStatus(
        phase: NextLessonPhase.completedForToday,
        targetLesson: null,
        headline: 'Mára vége az óráknak!',
        countdownLabel: 'Mára vége az óráknak!',
        remainingLessonsCount: 0,
        totalLessonsCount: totalCount,
      );
    }

    // 1. Check if currently between start and end of any lesson (now >= start && now <= end)
    for (int i = 0; i < activeLessons.length; i++) {
      final lesson = activeLessons[i];
      final startLocal = lesson.start.toLocal();
      final endLocal = lesson.end.toLocal();
      if (!localNow.isBefore(startLocal) && !localNow.isAfter(endLocal)) {
        final rawSubj = lesson.subject?.name ?? lesson.name;
        final subjName = prefs != null
            ? prefs.resolveSubjectName(rawSubj, lesson.subject?.uid)
            : rawSubj;
        final minsLeft = endLocal.difference(localNow).inMinutes.clamp(1, 999);
        final totalSecs = endLocal.difference(startLocal).inSeconds;
        final remSecs = endLocal.difference(localNow).inSeconds;
        final remFraction = totalSecs > 0
            ? (remSecs / totalSecs).clamp(0.0, 1.0)
            : 0.0;
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

      if (diff <= const Duration(hours: 2)) {
        final totalMins = diff.inMinutes.clamp(1, 120);
        final String countdownStr;
        if (totalMins >= 60) {
          final hrs = totalMins ~/ 60;
          final remMins = totalMins % 60;
          countdownStr = remMins > 0
              ? 'Első óráig: $hrs óra $remMins perc'
              : 'Első óráig: $hrs óra';
        } else {
          countdownStr = 'Első óráig: $totalMins perc';
        }
        return NextLessonStatus(
          phase: NextLessonPhase.beforeFirstWithinTwoHours,
          targetLesson: firstLesson,
          headline: subjName,
          countdownLabel: countdownStr,
          remainingLessonsCount: remainingCount,
          totalLessonsCount: totalCount,
        );
      } else {
        return NextLessonStatus(
          phase: NextLessonPhase.beforeFirstFarAway,
          targetLesson: firstLesson,
          headline: 'Még messze van az első órád',
          countdownLabel: 'Még messze van az első órád',
          remainingLessonsCount: remainingCount,
          totalLessonsCount: totalCount,
        );
      }
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
      headline: subjName,
      countdownLabel: 'Még $minsUntilNext perc',
      remainingLessonsCount: remainingCount,
      totalLessonsCount: totalCount,
    );
  }
}

class _ActivityItem {
  final DateTime sortDate;
  final Grade? grade;
  final Homework? homework;
  final Test? test;

  _ActivityItem.grade(Grade this.grade)
      : sortDate = grade.recordDate,
        homework = null,
        test = null;

  _ActivityItem.homework(Homework this.homework)
      : sortDate = homework.creationDate,
        grade = null,
        test = null;

  _ActivityItem.test(Test this.test)
      : sortDate = test.reportDate,
        grade = null,
        homework = null;

  String get uniqueKey {
    if (grade != null) return 'g-${grade!.uid}';
    if (homework != null) return 'hw-${homework!.uid}';
    return 't-${test!.uid}';
  }
}

/// Main authenticated shell for reKRETA with:
/// 1. Dynamic time-based Hungarian greeting + sleek top-right `CircleAvatar`
///    action in the AppBar (opening the streamlined Profile & Settings sheet).
/// 2. Android predictive back / `PopScope` handling: pressing back on Jegyek,
///    Órarend, or Továbbiak returns to Főoldal (tab index 0).
/// 3. 'Következő óra' (Next Lesson) live hero card with local DateTime state machine.
/// 4. Minimalist Icon-Only Floating Dock with fluid sliding pill indicator.
class HomeScreen extends StatefulWidget {
  final StoredSession initialSession;
  final KretaClient kretaClient;
  final UserProfilePrefs prefs;
  final ValueChanged<UserProfilePrefs> onPrefsChanged;
  final VoidCallback onLogout;

  const HomeScreen({
    super.key,
    required this.initialSession,
    required this.kretaClient,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLogout,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final int _tabSwitchEpoch = 0;
  bool _homeInitialEntrancePlayed = false;
  bool _homeEntranceActive = false;
  ActivityFeedFilter _feedFilter = ActivityFeedFilter.all;
  bool _isImmersiveWeeklyMode = false;

  late StoredSession _session;
  DashboardData? _data;
  bool _isLoading = true;
  String? _error;
  Timer? _countdownTimer;

  final DateFormat _timeFormat = DateFormat('HH:mm');
  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');

  @override
  void initState() {
    super.initState();
    _session = widget.initialSession;
    _loadDashboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        GitHubUpdaterService.checkForUpdates(context, manual: false);
      }
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _selectedIndex == 0) {
        setState(() {});
      }
    });
  }

  Widget _maybeHomeEntrance(Widget child, int index, {Key? key}) =>
      child.staggeredEntrance(
        index,
        animationKey: key,
        enabled: _homeEntranceActive,
      );

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs != widget.prefs &&
        _data != null &&
        (oldWidget.prefs.transitCardEnabled != widget.prefs.transitCardEnabled ||
            oldWidget.prefs.transitHomeStation !=
                widget.prefs.transitHomeStation ||
            oldWidget.prefs.transitSchoolStation !=
                widget.prefs.transitSchoolStation ||
            oldWidget.prefs.transitAllowTrain !=
                widget.prefs.transitAllowTrain ||
            oldWidget.prefs.transitAllowCoach !=
                widget.prefs.transitAllowCoach ||
            oldWidget.prefs.transitAllowLocalBus !=
                widget.prefs.transitAllowLocalBus ||
            oldWidget.prefs.walkingDurationMinutes !=
                widget.prefs.walkingDurationMinutes ||
            oldWidget.prefs.walkHomeToBusMinutes !=
                widget.prefs.walkHomeToBusMinutes ||
            oldWidget.prefs.walkHomeToTrainMinutes !=
                widget.prefs.walkHomeToTrainMinutes ||
            oldWidget.prefs.walkSchoolToBusMinutes !=
                widget.prefs.walkSchoolToBusMinutes ||
            oldWidget.prefs.walkSchoolToTrainMinutes !=
                widget.prefs.walkSchoolToTrainMinutes ||
            oldWidget.prefs.homeAddress != widget.prefs.homeAddress ||
            oldWidget.prefs.schoolAddress != widget.prefs.schoolAddress ||
            oldWidget.prefs.extras != widget.prefs.extras ||
            oldWidget.prefs.walkingSpeedKmh != widget.prefs.walkingSpeedKmh)) {
      _refreshCommute();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  CommuteEvaluation? _commuteEval;
  bool _commuteLoading = false;
  final MenetrendService _menetrendService = MenetrendService();

  Future<void> _refreshCommute() async {
    final prefs = widget.prefs;
    if (!prefs.transitCardEnabled || !prefs.transitConfigured) {
      if (_commuteEval != null || _commuteLoading) {
        setState(() {
          _commuteEval = null;
          _commuteLoading = false;
        });
      }
      MenetrendService.cancelAlarms();
      return;
    }
    setState(() => _commuteLoading = true);
    final eval = await _menetrendService.fetchLiveCommuteEvaluation(
      todaysLessons: _data?.todaysLessons ?? const <Lesson>[],
      prefs: prefs,
    );
    if (!mounted) return;
    setState(() {
      _commuteEval = eval;
      _commuteLoading = false;
    });
    if (eval != null) {
      MenetrendService.syncNotificationsForEvaluation(
        evaluation: eval,
        prefs: prefs,
      );
    }
  }

  Future<void> _loadDashboard() async {
    if (mounted && _data == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final result = await widget.kretaClient.fetchDashboardData(_session);
      if (!mounted) return;
      final playInitialEntrance = !_homeInitialEntrancePlayed;
      setState(() {
        _session = result.activeSession;
        _data = result;
        _isLoading = false;
        _error = null;
        if (playInitialEntrance) {
          _homeInitialEntrancePlayed = true;
          _homeEntranceActive = true;
        }
      });
      if (playInitialEntrance) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _homeEntranceActive = false;
        });
      }
      _refreshCommute();
    } on TokenExpiredException {
      if (!mounted) return;
      widget.onLogout();
    } on InvalidGrantException {
      if (!mounted) return;
      widget.onLogout();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
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
  }

  void _openMessagesScreen() {
    HapticFeedback.lightImpact();
    final currentMessages =
        _messagesOverride ?? _data?.messages ?? const <KretaMessage>[];
    Navigator.of(context).push(
      SmoothSharedAxisRoute(
        page: Scaffold(
          appBar: AppBar(
            title: Text(uwu('Üzenetek')),
          ),
          body: ChristmasAndBackgroundOverlay(
            prefs: widget.prefs,
            child: MoreScreen(
              session: _session,
              student: _data?.student,
              kretaClient: widget.kretaClient,
              dashboardData: _data,
              initialOmissions: _data?.omissions ?? const <Omission>[],
              initialMessages: currentMessages,
              prefs: widget.prefs,
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
    showStreamlinedProfileSheet(
      context: context,
      student: _data?.student,
      session: _session,
      prefs: widget.prefs,
      onPrefsChanged: widget.onPrefsChanged,
      onOpenFullSettings: () {
        Navigator.of(context).push(
          SmoothSharedAxisRoute(
            page: AppSettingsScreen(
              session: _session,
              student: _data?.student,
              kretaClient: widget.kretaClient,
              prefs: widget.prefs,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final student = _data?.student;
    final hideChromeForLandscapeTimetable =
        _isImmersiveWeeklyMode && _selectedIndex == _timetableTabIndex;

    final resolvedName = GreetingUtils.resolveDisplayName(
      customNickname: widget.prefs.nickname,
      fullStudentName: student?.name,
    );
    final greetingText = GreetingUtils.buildGreeting(
      name: resolvedName,
      uwuMode: widget.prefs.uwuModeEnabled,
      tsundereMode: widget.prefs.tsundereModeEnabled,
    );

    final hasAmbientBackdrop = widget.prefs.cardBlurEnabled ||
        widget.prefs.backgroundPreset != 'pure_oled';

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          _selectBottomTab(0);
        }
      },
      child: ChristmasAndBackgroundOverlay(
        prefs: widget.prefs,
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
                      prefs: widget.prefs,
                      onTap: _openProfileAndSettingsModal,
                    ),
                  ],
                ),
          body: _isLoading && _data == null
              ? const Center(child: CircularProgressIndicator())
              : _buildKeepAliveTabStack(theme, scheme, student),
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
  ) {
    final tabs = <Widget>[
      _buildHomeTab(theme, scheme),
      GradesScreen(
        allGrades: _data?.allGrades ?? const <Grade>[],
        prefs: widget.prefs,
        onPrefsChanged: widget.onPrefsChanged,
        onRefresh: _loadDashboard,
        isActiveTab: _selectedIndex == 1,
        entranceEpoch: _tabSwitchEpoch,
      ),
      TimetableScreen(
        session: _session,
        kretaClient: widget.kretaClient,
        initialTodaysLessons: _data?.todaysLessons ?? const <Lesson>[],
        prefs: widget.prefs,
        onPrefsChanged: widget.onPrefsChanged,
        onImmersiveWeeklyModeChanged: (immersive) {
          if (mounted && _isImmersiveWeeklyMode != immersive) {
            setState(() => _isImmersiveWeeklyMode = immersive);
          }
        },
        isActiveTab: _selectedIndex == _timetableTabIndex,
        entranceEpoch: _tabSwitchEpoch,
      ),
      MoreScreen(
        session: _session,
        student: student,
        kretaClient: widget.kretaClient,
        dashboardData: _data,
        initialOmissions: _data?.omissions ?? const <Omission>[],
        initialMessages:
            _messagesOverride ?? _data?.messages ?? const <KretaMessage>[],
        prefs: widget.prefs,
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

    return IndexedStack(
      index: _selectedIndex,
      children: tabs,
    );
  }

  /// Minimalist Icon-Only Floating Dock with ultra-light liquid/frosted glass
  /// (`BackdropFilter` sigma 16, surface `Colors.white.withValues(alpha: 0.08)`
  /// in dark mode and `0.55` in light mode, crisp `1px` border
  /// `Colors.white.withValues(alpha: 0.20)`), explicit high-contrast icon
  /// colors, 220ms `Curves.easeOutCubic` sliding pill indicator, and 4 primary
  /// tabs: Főoldal, Jegyek, Órarend, Hiányzások.
  Widget _buildMinimalistFloatingDock(ThemeData theme, ColorScheme scheme) {
    final isDark = theme.brightness == Brightness.dark ||
        widget.prefs.themeStyle != AppThemeStyle.light;
    final dockColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.55);
    final borderColor = Colors.white.withValues(alpha: 0.20);
    final activeIconColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final inactiveIconColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF0F172A).withValues(alpha: 0.65);

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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: dockColor,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: borderColor,
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.22 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final totalWidth = constraints.maxWidth;
                    final slotWidth = totalWidth / tabs.length;
                    const pillWidth = 56.0;
                    const pillHeight = 42.0;
                    final pillLeft = (_selectedIndex * slotWidth) +
                        ((slotWidth - pillWidth) / 2);

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          left: pillLeft,
                          top: (62 - pillHeight) / 2,
                          width: pillWidth,
                          height: pillHeight,
                          child: Container(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(
                                alpha: isDark ? 0.28 : 0.20,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: scheme.primary.withValues(
                                  alpha: isDark ? 0.58 : 0.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: List.generate(tabs.length, (idx) {
                            final item = tabs[idx];
                            final isSelected = _selectedIndex == idx;
                            final iconColor = isSelected
                                ? activeIconColor
                                : inactiveIconColor;
                            return Expanded(
                              child: Semantics(
                                label: item.tooltip,
                                selected: isSelected,
                                button: true,
                                child: Tooltip(
                                  message: item.tooltip,
                                  child: TactileBounce(
                                    onTap: () => _selectBottomTab(idx),
                                    child: SizedBox(
                                      height: 62,
                                      child: Center(
                                        child: IconTheme(
                                          data: IconThemeData(
                                            color: iconColor,
                                            size: 25,
                                          ),
                                          child: AnimatedSwitcher(
                                            duration:
                                                const Duration(milliseconds: 180),
                                            child: Icon(
                                              isSelected
                                                  ? item.selectedIcon
                                                  : item.icon,
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
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
                ),
              ),
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

  String _formatDaySectionTitle(DateTime day, DateTime today) {
    if (day == today) return 'Ma';
    if (day == today.subtract(const Duration(days: 1))) return 'Tegnap';
    if (day == today.add(const Duration(days: 1))) return 'Holnap';
    final month = _shortMonthsHu[(day.month - 1).clamp(0, 11)];
    if (day.year != today.year) {
      return '${day.year}. $month ${day.day}.';
    }
    return '$month ${day.day}.';
  }

  List<({DateTime day, List<_ActivityItem> items})> _groupFeedItemsByDay(
    List<_ActivityItem> items,
  ) {
    final groups = <({DateTime day, List<_ActivityItem> items})>[];
    for (final item in items) {
      final day = DateUtils.dateOnly(item.sortDate.toLocal());
      if (groups.isEmpty || groups.last.day != day) {
        groups.add((day: day, items: <_ActivityItem>[item]));
      } else {
        groups.last.items.add(item);
      }
    }
    return groups;
  }

  Widget _buildHomeTab(ThemeData theme, ColorScheme scheme) {
    final lessons = _data?.todaysLessons ?? const <Lesson>[];
    final feedItems = _buildFilteredFeedItems();
    final dayGroups = _groupFeedItemsByDay(feedItems);
    final today = DateUtils.dateOnly(DateTime.now());

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 116),
        children: [
          if (_error != null) ...[
            _buildErrorCard(theme, _error!),
            const SizedBox(height: 16),
          ],
          if (widget.prefs.transitCardEnabled &&
              widget.prefs.transitConfigured &&
              _commuteEval != null) ...[
            _maybeHomeEntrance(
              MenetrendHomeCard(
                evaluation: _commuteEval,
                isLoading: _commuteLoading,
                prefs: widget.prefs,
                onOpenSettings: _openProfileAndSettingsModal,
                onRetry: _refreshCommute,
              ),
              0,
              key: const ValueKey('home-transit'),
            ),
            const SizedBox(height: 16),
          ],
          _maybeHomeEntrance(
            _buildNextLessonHeroCard(theme, scheme, lessons),
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
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: dayGroups.isEmpty
                ? _buildEmptyStateCard(
                    theme,
                    scheme,
                    icon: Icons.inbox_rounded,
                    message: uwu(
                      'Nincs megjeleníthető elem ebben a kategóriában.',
                    ),
                  )
                : Column(
                    key: ValueKey<String>('feed-${_feedFilter.name}'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int gIdx = 0; gIdx < dayGroups.length; gIdx++) ...[
                        if (gIdx > 0) const SizedBox(height: 22),
                        _buildDayGroupSection(
                          theme,
                          scheme,
                          dayGroups[gIdx].day,
                          dayGroups[gIdx].items,
                          today,
                          gIdx,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayGroupSection(
    ThemeData theme,
    ColorScheme scheme,
    DateTime day,
    List<_ActivityItem> items,
    DateTime today,
    int groupIndex,
  ) {
    final title = _formatDaySectionTitle(day, today);
    final weekday = _weekdayNamesHu[day.weekday.clamp(1, 7)];

    final section = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Row(
            children: [
              Text(
                uwu(title),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                weekday,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.52),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _buildActivityFeedTile(theme, scheme, items[i]),
        ],
      ],
    );
    return _maybeHomeEntrance(
      section,
      groupIndex + 2,
      key: ValueKey('day-${day.toIso8601String()}'),
    );
  }

  /// Builds the dynamic 'Következő óra' / Live Activity hero card using
  /// [NextLessonStatus.evaluate] with local DateTime comparisons.
  Widget _buildNextLessonHeroCard(
    ThemeData theme,
    ColorScheme scheme,
    List<Lesson> lessons,
  ) {
    final status = NextLessonStatus.evaluate(
      lessons,
      DateTime.now(),
      prefs: widget.prefs,
    );
    final currentOrNext = status.targetLesson;
    final upcoming = status.upcomingLesson;
    final isOngoing = status.phase == NextLessonPhase.ongoing;

    final progressText = status.phase == NextLessonPhase.completedForToday
        ? 'Ma már nincs több órád!'
        : 'Ma még ${status.remainingLessonsCount} / ${status.totalLessonsCount} óra van hátra';

    final heroTag =
        currentOrNext != null ? 'lesson_num_${currentOrNext.uid}' : null;

    final rawCurrentSubj = currentOrNext != null
        ? (currentOrNext.subject?.name ?? currentOrNext.name)
        : '';
    final currentSubjTitle = currentOrNext != null
        ? widget.prefs.resolveSubjectName(
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
                prefs: widget.prefs,
              )
          : () => _selectBottomTab(_timetableTabIndex),
      child: ChristmasSnowCap(
        enabled: widget.prefs.christmasModeEnabled,
        child: SoftGlassCard(
          prefs: widget.prefs,
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
                          Icon(
                            isOngoing
                                ? Icons.sensors_rounded
                                : Icons.schedule_rounded,
                            size: 15,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            uwu(
                              isOngoing
                                  ? 'Folyamatban lévő óra'
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
                    const Spacer(),
                    Flexible(
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
                        child: Text(
                          uwu(
                            isOngoing
                                ? '${status.remainingMinutes} perc van hátra'
                                : progressText,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isOngoing
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
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
                    Hero(
                      tag: heroTag!,
                      child: Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          width: 58,
                          height: 58,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 58,
                                height: 58,
                                child: CircularProgressIndicator(
                                  value: status.remainingFraction,
                                  strokeWidth: 4.5,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor:
                                      scheme.primary.withValues(alpha: 0.18),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    scheme.primary,
                                  ),
                                ),
                              ),
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  currentOrNext.lessonNumber != null
                                      ? '${currentOrNext.lessonNumber}.'
                                      : '•',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
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
                          Text(
                            currentOrNext.substituteTeacher != null &&
                                    currentOrNext.substituteTeacher!
                                        .trim()
                                        .isNotEmpty
                                ? 'Helyettes: ${widget.prefs.resolveTeacherName(currentOrNext.substituteTeacher)} • ${status.remainingMinutes} perc van hátra'
                                : '${currentOrNext.teacher != null ? '${widget.prefs.resolveTeacherName(currentOrNext.teacher)} • ' : ''}${status.remainingMinutes} perc van hátra',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
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
                    Hero(
                      tag: heroTag!,
                      child: Material(
                        type: MaterialType.transparency,
                        child: Container(
                          width: 52,
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: OledTheme.badgeRadius,
                          ),
                          child: Text(
                            currentOrNext.lessonNumber != null
                                ? '${currentOrNext.lessonNumber}.'
                                : '•',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w900,
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
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
                      Text(
                        status.countdownLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (currentOrNext.substituteTeacher != null &&
                          currentOrNext.substituteTeacher!.trim().isNotEmpty)
                        Flexible(
                          child: Text(
                            'Helyettes: ${widget.prefs.resolveTeacherName(currentOrNext.substituteTeacher)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFFFB300),
                              fontWeight: FontWeight.w800,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else if (currentOrNext.teacher != null)
                        Flexible(
                          child: Text(
                            widget.prefs
                                .resolveTeacherName(currentOrNext.teacher),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                            overflow: TextOverflow.ellipsis,
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
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Text(
            upcoming.lessonNumber != null ? '${upcoming.lessonNumber}.' : '•',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.onSurface,
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ActivityFeedFilter.values.map((filter) {
          final selected = _feedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TactileBounce(
              onTap: () => setState(() => _feedFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : theme.cardTheme.color,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: selected ? scheme.primary : theme.dividerColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      filter.icon,
                      size: 16,
                      color: selected
                          ? scheme.onPrimary
                          : scheme.onSurface.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      uwu(filter.label),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                        color: selected
                            ? scheme.onPrimary
                            : scheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<_ActivityItem> _buildFilteredFeedItems() {
    final grades = _data?.allGrades ?? const <Grade>[];
    final homeworks = _data?.homeworks ?? const <Homework>[];
    final tests = _data?.tests ?? const <Test>[];

    final items = <_ActivityItem>[];
    if (_feedFilter == ActivityFeedFilter.all ||
        _feedFilter == ActivityFeedFilter.grades) {
      items.addAll(grades.map(_ActivityItem.grade));
    }
    if (_feedFilter == ActivityFeedFilter.all ||
        _feedFilter == ActivityFeedFilter.homeworks) {
      items.addAll(homeworks.map(_ActivityItem.homework));
    }
    if (_feedFilter == ActivityFeedFilter.all ||
        _feedFilter == ActivityFeedFilter.tests) {
      items.addAll(tests.map(_ActivityItem.test));
    }

    items.sort((a, b) => b.sortDate.compareTo(a.sortDate));
    return items;
  }

  Widget _buildActivityFeedTile(
    ThemeData theme,
    ColorScheme scheme,
    _ActivityItem item,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showGradeInspectionModal(
          context,
          grade,
          prefs: widget.prefs,
          heroTag: heroTag,
        ),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: widget.prefs,
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
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(11),
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
                            _dateFormat.format(grade.recordDate.toLocal()),
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.56),
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
    final cleanText = homework.description
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();
    final heroTag = 'home_hw_${homework.uid}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TactileBounce(
        pressedScale: 0.97,
        onTap: () => showHomeworkInspectionModal(
          context,
          homework,
          prefs: widget.prefs,
          heroTag: heroTag,
        ),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: widget.prefs,
            padding: const EdgeInsets.all(14),
            borderRadius: BorderRadius.circular(16),
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
                        color: hwColor.withValues(alpha: 0.2),
                        borderRadius: OledTheme.badgeRadius,
                        border: Border.all(color: hwColor),
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
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
                              ),
                            ),
                          ),
                          Text(
                            'Határidő: ${_dateFormat.format(homework.dueDate.toLocal())}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: hwColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cleanText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.78),
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
              ],
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
          prefs: widget.prefs,
          heroTag: heroTag,
        ),
        child: ChristmasSnowCap(
          enabled: widget.prefs.christmasModeEnabled,
          child: SoftGlassCard(
            prefs: widget.prefs,
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
                            '$weekdayName ${_dateFormat.format(testLocal)}',
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
      prefs: widget.prefs,
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
