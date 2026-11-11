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
  final String headline;
  final String countdownLabel;
  final int remainingLessonsCount;
  final int totalLessonsCount;

  const NextLessonStatus({
    required this.phase,
    required this.targetLesson,
    required this.headline,
    required this.countdownLabel,
    required this.remainingLessonsCount,
    required this.totalLessonsCount,
  });

  /// Evaluates the 'Következő óra' card state machine comparing local
  /// `KezdetIdopont` (`lesson.start.toLocal()`) and `VegIdopont` (`lesson.end.toLocal()`)
  /// against [now].
  static NextLessonStatus evaluate(
    List<Lesson> lessons,
    DateTime now, {
    UserProfilePrefs? prefs,
  }) {
    final localNow = now.toLocal();
    final activeLessons = lessons
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

    // 1. Check if currently between start and end of any lesson
    for (final lesson in activeLessons) {
      final startLocal = lesson.start.toLocal();
      final endLocal = lesson.end.toLocal();
      if (!localNow.isBefore(startLocal) && localNow.isBefore(endLocal)) {
        final rawSubj = lesson.subject?.name ?? lesson.name;
        final subjName = prefs != null
            ? prefs.resolveSubjectName(rawSubj, lesson.subject?.uid)
            : rawSubj;
        final minsLeft = endLocal.difference(localNow).inMinutes.clamp(1, 999);
        return NextLessonStatus(
          phase: NextLessonPhase.ongoing,
          targetLesson: lesson,
          headline: 'Folyamatban lévő óra: $subjName',
          countdownLabel: 'Még $minsLeft perc',
          remainingLessonsCount: remainingCount,
          totalLessonsCount: totalCount,
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
  int _tabSwitchEpoch = 0;
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

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.prefs != widget.prefs && _data != null) {
      final eval = MenetrendService.evaluateSmartCommute(
        todaysLessons: _data!.todaysLessons,
        prefs: widget.prefs,
      );
      MenetrendService.syncNotificationsForEvaluation(
        evaluation: eval,
        prefs: widget.prefs,
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
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
      setState(() {
        _session = result.activeSession;
        _data = result;
        _isLoading = false;
        _error = null;
      });
      final eval = MenetrendService.evaluateSmartCommute(
        todaysLessons: result.todaysLessons,
        prefs: widget.prefs,
      );
      MenetrendService.syncNotificationsForEvaluation(
        evaluation: eval,
        prefs: widget.prefs,
      );
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

  void _selectBottomTab(int idx) {
    if (_selectedIndex == idx) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedIndex == 2 && idx != 2) {
        _isImmersiveWeeklyMode = false;
      }
      _selectedIndex = idx;
      _tabSwitchEpoch++;
    });
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
        _isImmersiveWeeklyMode && _selectedIndex == 2;

    final resolvedName = GreetingUtils.resolveDisplayName(
      customNickname: widget.prefs.nickname,
      fullStudentName: student?.name,
      defaultFirstName: 'Milán',
    );
    final greetingText = GreetingUtils.buildGreeting(
      name: resolvedName,
      uwuMode: widget.prefs.uwuModeEnabled,
      tsundereMode: widget.prefs.tsundereModeEnabled,
    );

    return PopScope(
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectedIndex != 0) {
          _selectBottomTab(0);
        }
      },
      child: Scaffold(
        extendBody: !hideChromeForLandscapeTimetable,
        appBar: hideChromeForLandscapeTimetable
            ? null
            : AppBar(
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
                  ProfileTopBarAvatar(
                    prefs: widget.prefs,
                    onTap: _openProfileAndSettingsModal,
                  ),
                ],
              ),
        body: ChristmasAndBackgroundOverlay(
          prefs: widget.prefs,
          child: _isLoading && _data == null
              ? const Center(child: CircularProgressIndicator())
              : AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final slide = Tween<Offset>(
                      begin: const Offset(0.0, 0.025),
                      end: Offset.zero,
                    ).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: slide,
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(_selectedIndex),
                    child: _buildActiveTabBody(theme, scheme, student),
                  ),
                ),
        ),
        bottomNavigationBar: hideChromeForLandscapeTimetable
            ? null
            : _buildMinimalistFloatingDock(theme, scheme),
      ),
    );
  }

  Widget _buildActiveTabBody(
    ThemeData theme,
    ColorScheme scheme,
    Student? student,
  ) {
    switch (_selectedIndex) {
      case 0:
        return _buildHomeTab(theme, scheme);
      case 1:
        return GradesScreen(
          allGrades: _data?.allGrades ?? const <Grade>[],
          prefs: widget.prefs,
          onPrefsChanged: widget.onPrefsChanged,
          onRefresh: _loadDashboard,
          entranceEpoch: _tabSwitchEpoch,
        );
      case 2:
        return TimetableScreen(
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
          isActiveTab: _selectedIndex == 2,
          entranceEpoch: _tabSwitchEpoch,
        );
      case 3:
      default:
        return MoreScreen(
          session: _session,
          student: student,
          kretaClient: widget.kretaClient,
          dashboardData: _data,
          initialOmissions: _data?.omissions ?? const <Omission>[],
          initialMessages: _data?.messages ?? const <KretaMessage>[],
          prefs: widget.prefs,
          onPrefsChanged: widget.onPrefsChanged,
          onLogout: widget.onLogout,
        );
    }
  }

  /// Minimalist Icon-Only Floating Dock with fluid sliding pill indicator
  /// (`Curves.easeOutCubic`), no text labels, star icon for Jegyek, uniform
  /// calendar icon (`Icons.calendar_month_outlined` / `Icons.calendar_month_rounded`),
  /// and 4th tab 'Továbbiak' (`Icons.grid_view_rounded`).
  Widget _buildMinimalistFloatingDock(ThemeData theme, ColorScheme scheme) {
    final isDark = theme.brightness == Brightness.dark;
    final dockColor = isDark
        ? const Color(0xFF121212).withValues(alpha: 0.90)
        : scheme.surface.withValues(alpha: 0.92);
    final borderColor = isDark
        ? (widget.prefs.uwuModeEnabled
            ? OledTheme.uwuPastelPink.withValues(alpha: 0.45)
            : const Color(0xFF262626))
        : theme.dividerColor;

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
        icon: Icons.grid_view_rounded,
        selectedIcon: Icons.grid_view_rounded,
        tooltip: 'Továbbiak',
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4.5, sigmaY: 4.5),
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: dockColor,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: borderColor,
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.14),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
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
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        left: pillLeft,
                        top: (62 - pillHeight) / 2,
                        width: pillWidth,
                        height: pillHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.48),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: List.generate(tabs.length, (idx) {
                          final item = tabs[idx];
                          final isSelected = _selectedIndex == idx;
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
                                      child: AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 180),
                                        child: Icon(
                                          isSelected
                                              ? item.selectedIcon
                                              : item.icon,
                                          key: ValueKey<String>(
                                            'dock-$idx-$isSelected',
                                          ),
                                          size: 25,
                                          color: isSelected
                                              ? scheme.primary
                                              : scheme.onSurface
                                                  .withValues(alpha: 0.65),
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
    );
  }

  Widget _buildHomeTab(ThemeData theme, ColorScheme scheme) {
    final lessons = _data?.todaysLessons ?? const <Lesson>[];
    final feedItems = _buildFilteredFeedItems();
    final commuteEval = MenetrendService.evaluateSmartCommute(
      todaysLessons: lessons,
      prefs: widget.prefs,
    );

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
        children: [
          if (_error != null) ...[
            _buildErrorCard(theme, _error!),
            const SizedBox(height: 14),
          ],
          MenetrendHeroCard(
            evaluation: commuteEval,
            prefs: widget.prefs,
          ).staggeredEntrance(
            0,
            animationKey: ValueKey('home-transit-$_tabSwitchEpoch'),
          ),
          const SizedBox(height: 14),
          _buildNextLessonHeroCard(theme, scheme, lessons).staggeredEntrance(
            1,
            animationKey: ValueKey('home-next-$_tabSwitchEpoch'),
          ),
          const SizedBox(height: 22),
          _buildActivityFeedHeader(theme, scheme).staggeredEntrance(
            2,
            animationKey: ValueKey('home-hdr-$_tabSwitchEpoch'),
          ),
          const SizedBox(height: 10),
          _buildFilterChipBar(theme, scheme).staggeredEntrance(
            3,
            animationKey: ValueKey('home-chips-$_tabSwitchEpoch'),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SizeTransition(
                  sizeFactor: animation,
                  child: child,
                ),
              );
            },
            child: feedItems.isEmpty
                ? _buildEmptyStateCard(
                    theme,
                    scheme,
                    icon: Icons.inbox_rounded,
                    message: uwu(
                      'Nincs megjeleníthető elem ebben a kategóriában.',
                    ),
                  )
                : Column(
                    key: ValueKey<String>(
                      'feed-${_feedFilter.name}-$_tabSwitchEpoch',
                    ),
                    children: List.generate(feedItems.length, (idx) {
                      final item = feedItems[idx];
                      return _buildActivityFeedTile(theme, scheme, item)
                          .staggeredEntrance(
                        idx + 2,
                        animationKey: ValueKey(
                          'item-${item.uniqueKey}-${_feedFilter.name}-$_tabSwitchEpoch',
                        ),
                      );
                    }),
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds the dynamic 'Következő óra' (Next Lesson) hero card using
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
    final isOngoing = status.phase == NextLessonPhase.ongoing;

    final progressText = status.phase == NextLessonPhase.completedForToday
        ? 'Mára vége az óráknak!'
        : 'Ma még ${status.remainingLessonsCount} / ${status.totalLessonsCount} óra van hátra';

    final heroTag =
        currentOrNext != null ? 'lesson_num_${currentOrNext.uid}' : null;

    return TactileBounce(
      pressedScale: 0.97,
      onTap: currentOrNext != null
          ? () => showLessonInspectionModal(
                context,
                currentOrNext,
                heroTag: heroTag,
                prefs: widget.prefs,
              )
          : () => _selectBottomTab(2),
      child: ChristmasSnowCap(
        enabled: widget.prefs.christmasModeEnabled,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.largeRadius,
            border: Border.all(
              color: currentOrNext != null
                  ? scheme.primary.withValues(alpha: 0.65)
                  : theme.dividerColor,
              width: currentOrNext != null ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                              ? Icons.play_circle_fill_rounded
                              : Icons.schedule_rounded,
                          size: 15,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          uwu(isOngoing ? 'Folyamatban lévő óra' : 'Következő óra'),
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
                        color: scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Text(
                        uwu(progressText),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                            uwu('Mára vége az óráknak!'),
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
              else ...[
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

  Widget _buildActivityFeedHeader(ThemeData theme, ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.dynamic_feed_rounded, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            uwu('Aktivitási hírfolyam'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: theme.dividerColor),
            ),
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
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: OledTheme.cardRadius,
              border: Border.all(color: theme.dividerColor),
            ),
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
    final teacherDisplay = widget.prefs.resolveTeacherName(test.teacherName);
    final heroTag = 'home_test_${test.uid}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: OledTheme.cardRadius,
              border: Border.all(color: theme.dividerColor),
            ),
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
                        color: testColor.withValues(alpha: 0.2),
                        borderRadius: OledTheme.badgeRadius,
                        border: Border.all(color: testColor),
                      ),
                      child: const Icon(
                        Icons.assignment_late_rounded,
                        color: testColor,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(width: 8),
                          Text(
                            '$weekdayName\n${_dateFormat.format(testLocal)}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: testColor,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${test.method.description} (${test.lessonNumber}. óra)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: testColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (test.theme != null &&
                          test.theme!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Téma: ${test.theme}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.78),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: OledTheme.cardRadius,
        border: Border.all(color: theme.dividerColor),
      ),
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
