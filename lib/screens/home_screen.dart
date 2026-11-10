import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../services/kreta_client.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/greeting_utils.dart';
import '../widgets/expandable_profile_card.dart';
import '../widgets/frosted_inspection_modal.dart';
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
}

/// Main authenticated shell for reKRETA with:
/// 1. Dynamic time-based Hungarian greeting in the top AppBar (without refresh button).
/// 2. 'Következő óra' (Next Lesson) live hero card with countdown & daily progress.
/// 3. Unified Activity Feed ([Összes, Jegyek, Házik, Számonkérések]) with frosted-glass modals.
/// 4. 4-tab Material 3 Bottom NavigationBar (Főoldal, Jegyek, Órarend, Több).
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
  ActivityFeedFilter _feedFilter = ActivityFeedFilter.all;

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
    _countdownTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && _selectedIndex == 0) {
        setState(() {});
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final student = _data?.student;

    final resolvedName = GreetingUtils.resolveDisplayName(
      customNickname: widget.prefs.nickname,
      fullStudentName: student?.name,
      defaultFirstName: 'Milán',
    );
    final greetingText = GreetingUtils.buildGreeting(name: resolvedName);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greetingText,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: scheme.onSurface,
              ),
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
      ),
      body: _isLoading && _data == null
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildHomeTab(theme, scheme),
                GradesScreen(
                  allGrades: _data?.allGrades ?? const <Grade>[],
                  prefs: widget.prefs,
                  onPrefsChanged: widget.onPrefsChanged,
                  onRefresh: _loadDashboard,
                ),
                TimetableScreen(
                  session: _session,
                  kretaClient: widget.kretaClient,
                  initialTodaysLessons:
                      _data?.todaysLessons ?? const <Lesson>[],
                  prefs: widget.prefs,
                  onPrefsChanged: widget.onPrefsChanged,
                  isActiveTab: _selectedIndex == 2,
                ),
                MoreScreen(
                  session: _session,
                  student: student,
                  prefs: widget.prefs,
                  onPrefsChanged: widget.onPrefsChanged,
                  onLogout: widget.onLogout,
                ),
              ],
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Főoldal',
            ),
            NavigationDestination(
              icon: Icon(Icons.assignment_rounded),
              selectedIcon: Icon(Icons.star_rounded),
              label: 'Jegyek',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_today_rounded),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Órarend',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_rounded),
              selectedIcon: Icon(Icons.menu_rounded),
              label: 'Több',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab(ThemeData theme, ColorScheme scheme) {
    final student = _data?.student;
    final lessons = _data?.todaysLessons ?? const <Lesson>[];
    final feedItems = _buildFilteredFeedItems();

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          ExpandableProfileCard(
            student: student,
            session: _session,
            prefs: widget.prefs,
            onPrefsChanged: widget.onPrefsChanged,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _buildErrorCard(theme, _error!),
          ],
          const SizedBox(height: 18),
          _buildNextLessonHeroCard(theme, scheme, lessons),
          const SizedBox(height: 24),
          _buildActivityFeedHeader(theme, scheme),
          const SizedBox(height: 12),
          _buildFilterChipBar(theme, scheme),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: feedItems.isEmpty
                ? _buildEmptyStateCard(
                    theme,
                    scheme,
                    icon: Icons.inbox_rounded,
                    message: 'Nincs megjeleníthető elem ebben a kategóriában.',
                  )
                : Column(
                    key: ValueKey<ActivityFeedFilter>(_feedFilter),
                    children: feedItems
                        .map((item) => _buildActivityFeedTile(theme, scheme, item))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  /// Builds the dynamic 'Következő óra' (Next Lesson) hero card with real-time
  /// countdown and daily lesson progress.
  Widget _buildNextLessonHeroCard(
    ThemeData theme,
    ColorScheme scheme,
    List<Lesson> lessons,
  ) {
    final now = DateTime.now();
    final activeLessons = lessons
        .where((l) => !l.state.name.toLowerCase().contains('elmarad'))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    final totalCount = activeLessons.length;
    final remainingLessons =
        activeLessons.where((l) => l.end.isAfter(now)).toList();
    final remainingCount = remainingLessons.length;

    Lesson? currentOrNext;
    bool isOngoing = false;
    for (final l in activeLessons) {
      if (!now.isBefore(l.start) && now.isBefore(l.end)) {
        currentOrNext = l;
        isOngoing = true;
        break;
      }
      if (l.start.isAfter(now)) {
        currentOrNext = l;
        isOngoing = false;
        break;
      }
    }

    final progressText = (totalCount == 0 || remainingCount == 0)
        ? 'Mára vége az óráknak!'
        : 'Ma még $remainingCount / $totalCount óra van hátra';

    String countdownLabel = '';
    if (currentOrNext != null) {
      if (isOngoing) {
        final minsLeft =
            currentOrNext.end.difference(now).inMinutes.clamp(1, 999);
        countdownLabel = 'Folyamatban • még $minsLeft perc';
      } else {
        final diffMins =
            currentOrNext.start.difference(now).inMinutes.clamp(1, 9999);
        if (diffMins >= 60) {
          final h = diffMins ~/ 60;
          final m = diffMins % 60;
          countdownLabel = 'Kezdésig: $h óra $m perc';
        } else {
          countdownLabel = 'Kezdésig: $diffMins perc';
        }
      }
    }

    return InkWell(
      borderRadius: OledTheme.largeRadius,
      onTap: currentOrNext != null
          ? () => showLessonInspectionModal(context, currentOrNext!)
          : () => setState(() => _selectedIndex = 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
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
                        isOngoing ? 'Jelenlegi óra' : 'Következő óra',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
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
                    progressText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (currentOrNext == null)
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
                          'Mára vége az óráknak!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          totalCount > 0
                              ? 'Mind a(z) $totalCount mai tanóra lezajlott. Koppints a teljes órarendért!'
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
                  Container(
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
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentOrNext.subject?.name ?? currentOrNext.name,
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
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${_timeFormat.format(currentOrNext.start)} – ${_timeFormat.format(currentOrNext.end)}',
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
                                    style: theme.textTheme.bodySmall?.copyWith(
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
                      countdownLabel,
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
                          'Helyettes: ${currentOrNext.substituteTeacher}',
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
                          currentOrNext.teacher!,
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
    );
  }

  Widget _buildActivityFeedHeader(ThemeData theme, ColorScheme scheme) {
    return Row(
      children: [
        Icon(Icons.dynamic_feed_rounded, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Aktivitási hírfolyam',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ),
        Text(
          'Koppints a részletekért',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.54),
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
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => setState(() => _feedFilter = filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
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
                      filter.label,
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

  Widget _buildGradeFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Grade grade,
  ) {
    final badgeColor = OledTheme.gradeColor(grade.numericValue, widget.prefs);
    final badgeText = grade.numericValue?.toString() ??
        grade.shortStrValue ??
        (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');

    final subtitleParts = <String>[
      if (grade.topic != null && grade.topic!.trim().isNotEmpty) grade.topic!,
      if (grade.mode?.description.isNotEmpty == true) grade.mode!.description,
      if (grade.weightPercentage != null) '${grade.weightPercentage}%',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: OledTheme.cardRadius,
        onTap: () => showGradeInspectionModal(
          context,
          grade,
          prefs: widget.prefs,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: OledTheme.badgeRadius,
                ),
                child: Text(
                  badgeText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
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
                            grade.subject.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          _dateFormat.format(grade.recordDate),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${grade.strValue} • ${grade.type.description}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitleParts.join(' • '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      grade.teacher,
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
    );
  }

  Widget _buildHomeworkFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Homework homework,
  ) {
    const hwColor = Color(0xFF00BFA5);
    final subjectTitle = homework.subject.name.isNotEmpty
        ? homework.subject.name
        : homework.subjectName;
    final cleanText = homework.description
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: OledTheme.cardRadius,
        onTap: () => showHomeworkInspectionModal(context, homework),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hwColor.withValues(alpha: 0.2),
                  borderRadius: OledTheme.badgeRadius,
                  border: Border.all(color: hwColor),
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  color: hwColor,
                  size: 24,
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
                            subjectTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          'Határidő: ${_dateFormat.format(homework.dueDate)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hwColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cleanText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.78),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      homework.teacherName,
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
    );
  }

  Widget _buildTestFeedCard(
    ThemeData theme,
    ColorScheme scheme,
    Test test,
  ) {
    const testColor = Color(0xFFFF7043);
    final subjectTitle =
        test.subject.name.isNotEmpty ? test.subject.name : test.subjectName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: OledTheme.cardRadius,
        onTap: () => showTestInspectionModal(context, test),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.cardTheme.color,
            borderRadius: OledTheme.cardRadius,
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: testColor.withValues(alpha: 0.2),
                  borderRadius: OledTheme.badgeRadius,
                  border: Border.all(color: testColor),
                ),
                child: const Icon(
                  Icons.assignment_late_rounded,
                  color: testColor,
                  size: 24,
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
                            subjectTitle,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          _dateFormat.format(test.date),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: testColor,
                            fontWeight: FontWeight.w700,
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
                      test.teacherName,
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
