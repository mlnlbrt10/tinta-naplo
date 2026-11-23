import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_providers.dart';
import '../services/school_year_schedule_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import '../widgets/animation_helpers.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import '../widgets/frosted_inspection_modal.dart';
import '../widgets/glass_card.dart';
import '../widgets/tinta_toast.dart';

enum _ScheduleFilter {
  all('Összes', 'all'),
  school('Iskolai programok', 'school'),
  national('Szünetek / Munkanapok', 'national');

  final String label;
  final String keySuffix;
  const _ScheduleFilter(this.label, this.keySuffix);

  bool matches(SchoolYearEvent e) => switch (this) {
        _ScheduleFilter.all => true,
        _ScheduleFilter.school => e.isSchoolSpecific,
        _ScheduleFilter.national => !e.isSchoolSpecific ||
            e.type == SchoolYearEventType.schoolBreak ||
            e.type == SchoolYearEventType.nationalHoliday ||
            e.type == SchoolYearEventType.workingSaturday,
      };
}

/// Clean "Tanév rendje" viewer accessible from the Profile sheet showing school
/// breaks, national holidays, working Saturdays, countdowns, manual refresh,
/// school website URL override, and custom day entries.
class SchoolYearScheduleScreen extends StatefulWidget {
  final Student? student;
  final String instituteCode;
  final UserProfilePrefs prefs;
  final SchoolYearScheduleService? scheduleService;
  final DateTime Function()? clock;

  const SchoolYearScheduleScreen({
    super.key,
    required this.student,
    required this.instituteCode,
    required this.prefs,
    this.scheduleService,
    this.clock,
  });

  @override
  State<SchoolYearScheduleScreen> createState() =>
      _SchoolYearScheduleScreenState();
}

class _SchoolYearScheduleScreenState extends State<SchoolYearScheduleScreen> {
  SchoolYearScheduleService get _service =>
      widget.scheduleService ?? SchoolYearScheduleService.instance;

  final DateFormat _dateFormat = DateFormat('yyyy. MM. dd.');
  final DateFormat _shortFormat = DateFormat('MM. dd.');
  final DateFormat _syncFormat = DateFormat('yyyy. MM. dd. HH:mm');

  SchoolYearSchedule? _schedule;
  String? _customUrl;
  String? _pinnedCountdownEventId;
  Set<SchoolYearEventCategory> _hiddenCategories = <SchoolYearEventCategory>{};
  bool _loading = true;
  bool _refreshing = false;
  _ScheduleFilter _selectedFilter = _ScheduleFilter.all;
  late final PageController _filterPageController =
      PageController(initialPage: 0);

  @override
  void dispose() {
    _filterPageController.dispose();
    super.dispose();
  }

  void _selectFilter(_ScheduleFilter next, {bool animatePage = true}) {
    if (_selectedFilter != next) {
      setState(() => _selectedFilter = next);
    }
    if (animatePage && _filterPageController.hasClients) {
      final target = _ScheduleFilter.values.indexOf(next).clamp(
            0,
            _ScheduleFilter.values.length - 1,
          );
      final cur = _filterPageController.page?.round() ?? target;
      if (cur != target) {
        _filterPageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_initialLoad());
  }

  Future<void> _initialLoad() async {
    final cached = await _service.loadCachedOrFallback(
      student: widget.student,
      instituteCode: widget.instituteCode,
      nowOverride: _now(),
    );
    final customUrl =
        await _service.loadCustomUrlOverride(widget.instituteCode);
    final hidden =
        await _service.loadHiddenCategories(widget.instituteCode);
    final pinned =
        await _service.loadPinnedCountdownEventId(widget.instituteCode);
    if (!mounted) return;
    setState(() {
      _schedule = cached;
      _customUrl = customUrl;
      _hiddenCategories = hidden;
      _pinnedCountdownEventId = pinned;
      _loading = false;
    });

    // Silently refresh from school website / national calendar if stale.
    unawaited(_refreshSchedule(forceRefresh: false, showFeedback: false));
  }

  Future<void> _toggleCategory(SchoolYearEventCategory category) async {
    HapticFeedback.selectionClick();
    final next = Set<SchoolYearEventCategory>.from(_hiddenCategories);
    if (next.contains(category)) {
      next.remove(category);
    } else {
      next.add(category);
    }
    setState(() => _hiddenCategories = next);
    await _service.saveHiddenCategories(widget.instituteCode, next);
  }

  Future<void> _setPinnedCountdownEvent(String? eventId) async {
    HapticFeedback.selectionClick();
    setState(() => _pinnedCountdownEventId = eventId);
    await _service.savePinnedCountdownEventId(widget.instituteCode, eventId);
  }

  Future<void> _openCountdownTargetPickerSheet(
    SchoolYearSchedule schedule,
    DateTime now,
    UserProfilePrefs prefs,
  ) async {
    HapticFeedback.lightImpact();
    final d = DateUtils.dateOnly(now.toLocal());
    final upcoming = schedule.events.where((e) => !e.isPastOn(d)).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final autoClosest = _service.resolveCountdownEvent(
      schedule,
      now,
      pinnedEventId: null,
      hiddenCategories: _hiddenCategories,
    );

    final picked = await showFloatingGlassSheet<String?>(
      context: context,
      prefs: prefs,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        final scheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final closeMode = prefs.modalCloseMode;
        final uwuOn = prefs.uwuModeEnabled;
        final isAuto = _pinnedCountdownEventId == null;

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 520,
            maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.82,
          ),
          child: FrostedBottomSheetSurface(
            key: const ValueKey<String>('school-year-countdown-target-sheet'),
            prefs: prefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.push_pin_rounded,
                        size: 18,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwuLabel('Visszaszámlálás célpontja', enabled: uwuOn),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (closeMode.showTopX) ...[
                      const SizedBox(width: 8),
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(sheetCtx).pop(),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    physics: const FloatingSheetScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    children: [
                      TactileBounce(
                        key: const ValueKey<String>('countdown-target-auto'),
                        pressedScale: 0.98,
                        onTap: () => Navigator.of(sheetCtx).pop('auto'),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isAuto
                                ? scheme.primary
                                    .withValues(alpha: isDark ? 0.18 : 0.12)
                                : scheme.onSurface.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isAuto
                                  ? scheme.primary
                                  : scheme.outlineVariant.withValues(alpha: 0.4),
                              width: isAuto ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.auto_awesome_rounded,
                                size: 18,
                                color: isAuto
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      uwuLabel(
                                        'Automatikus (legközelebbi)',
                                        enabled: uwuOn,
                                      ),
                                      style:
                                          theme.textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (autoClosest != null)
                                      Text(
                                        uwuLabel(
                                          'Most: ${autoClosest.title}',
                                          enabled: uwuOn,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isAuto)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 18,
                                  color: scheme.primary,
                                ),
                            ],
                          ),
                        ),
                      ),
                      for (final ev in upcoming)
                        TactileBounce(
                          key: ValueKey<String>('countdown-target-${ev.id}'),
                          pressedScale: 0.98,
                          onTap: () => Navigator.of(sheetCtx).pop(ev.id),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: _pinnedCountdownEventId == ev.id
                                  ? ev.category.color
                                      .withValues(alpha: isDark ? 0.18 : 0.12)
                                  : scheme.onSurface.withValues(alpha: 0.035),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _pinnedCountdownEventId == ev.id
                                    ? ev.category.color
                                    : scheme.outlineVariant
                                        .withValues(alpha: 0.32),
                                width:
                                    _pinnedCountdownEventId == ev.id ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: ev.category.color
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    ev.category.icon,
                                    size: 15,
                                    color: OledTheme.semanticForeground(
                                      ev.category.color,
                                      theme.brightness,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        uwuLabel(ev.title, enabled: uwuOn),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '${_formatCompactRange(ev)} • ${ev.category.shortLabel}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          fontSize: 11,
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.62),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  ev.isOngoingOn(now)
                                      ? '${ev.daysRemaining(now)}n'
                                      : (ev.daysUntil(now) == 0
                                          ? 'Ma'
                                          : '${ev.daysUntil(now)}n'),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: OledTheme.semanticForeground(
                                      ev.category.color,
                                      theme.brightness,
                                    ),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                if (_pinnedCountdownEventId == ev.id) ...[
                                  const SizedBox(width: 6),
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: ev.category.color,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 10),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(sheetCtx).pop(),
                    uwuEnabled: uwuOn,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    await _setPinnedCountdownEvent(picked == 'auto' ? null : picked);
  }

  String _formatCompactRange(SchoolYearEvent event) {
    final s = _shortFormat.format(event.startDate.toLocal());
    if (DateUtils.dateOnly(event.startDate) ==
        DateUtils.dateOnly(event.endDate)) {
      return s;
    }
    final e = _shortFormat.format(event.endDate.toLocal());
    return '$s – $e';
  }

  Future<void> _refreshSchedule({
    bool forceRefresh = true,
    bool showFeedback = true,
  }) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final fresh = await _service.fetchSchedule(
        student: widget.student,
        instituteCode: widget.instituteCode,
        customUrlOverride: _customUrl,
        forceRefresh: forceRefresh,
        nowOverride: _now(),
      );
      if (!mounted) return;
      setState(() {
        _schedule = fresh;
        _refreshing = false;
      });
      if (showFeedback) {
        TintaToast.success(
          context,
          uwu('Tanév rendje frissítve (${fresh.sourceLabel})'),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return;
    HapticFeedback.selectionClick();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      TintaToast.info(context, uwu('A hivatkozás nem nyitható meg: $rawUrl'));
    }
  }

  Future<void> _openCustomUrlDialog() async {
    HapticFeedback.selectionClick();
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final result = await showFloatingGlassSheet<String?>(
      context: context,
      builder: (_) => _CustomUrlSheetContent(
        initialUrl: _customUrl ?? '',
        hasOverride: _customUrl != null && _customUrl!.isNotEmpty,
        prefs: activePrefs,
      ),
    );
    if (result == null || !mounted) return;
    await _service.saveCustomUrlOverride(widget.instituteCode, result);
    setState(() => _customUrl = result.isEmpty ? null : result);
    await _refreshSchedule(forceRefresh: true, showFeedback: true);
  }

  Future<void> _openAddCustomEventDialog() async {
    HapticFeedback.selectionClick();
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final saved = await showFloatingGlassSheet<SchoolYearEvent?>(
      context: context,
      builder: (_) => _CustomEventSheetContent(
        initialStartDate: DateUtils.dateOnly(_now().add(const Duration(days: 1))),
        shortFormat: _shortFormat,
        prefs: activePrefs,
      ),
    );
    if (saved == null || !mounted) return;
    await _service.addCustomEvent(widget.instituteCode, saved);
    final updated = await _service.loadCachedOrFallback(
      student: widget.student,
      instituteCode: widget.instituteCode,
      nowOverride: _now(),
    );
    if (!mounted) return;
    setState(() => _schedule = updated);
    TintaToast.success(context, uwu('Saját esemény mentve'));
  }

  Future<void> _deleteCustomEvent(SchoolYearEvent event) async {
    HapticFeedback.lightImpact();
    await _service.removeCustomEvent(widget.instituteCode, event.id);
    final updated = await _service.loadCachedOrFallback(
      student: widget.student,
      instituteCode: widget.instituteCode,
      nowOverride: _now(),
    );
    if (!mounted) return;
    setState(() => _schedule = updated);
    TintaToast.info(context, uwu('Egyéni esemény törölve'));
  }

  String _formatRange(SchoolYearEvent event) {
    final s = _dateFormat.format(event.startDate.toLocal());
    if (DateUtils.dateOnly(event.startDate) ==
        DateUtils.dateOnly(event.endDate)) {
      return s;
    }
    final e = _dateFormat.format(event.endDate.toLocal());
    return '$s – $e (${event.durationDays} nap)';
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? widget.prefs;
    final uwuOn = activePrefs.uwuModeEnabled;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = _now();

    final schedule = _schedule;
    final countdownEvent = schedule != null
        ? _service.resolveCountdownEvent(
            schedule,
            now,
            pinnedEventId: _pinnedCountdownEventId,
            hiddenCategories: _hiddenCategories,
          )
        : null;
    final resolvedPdfUrl = schedule?.pdfUrl ??
        ((schedule?.sourceUrl ?? '').toLowerCase().endsWith('.pdf')
            ? schedule?.sourceUrl
            : null);
    final availableCategories = schedule == null
        ? const <SchoolYearEventCategory>[]
        : SchoolYearEventCategory.values
            .where((cat) => schedule.events.any((e) => e.category == cat))
            .toList();

    return AdaptiveBackgroundScaffold(
      prefs: activePrefs,
      appBar: buildAdaptiveTransparentAppBar(
        context,
        title: uwu('Tanév rendje', enabled: uwuOn),
        actions: [
          IconButton(
            key: const ValueKey<String>('school-year-refresh-btn'),
            tooltip: uwu('Frissítés', enabled: uwuOn),
            onPressed: _refreshing
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _refreshSchedule(forceRefresh: true, showFeedback: true);
                  },
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading || schedule == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              notificationPredicate: nestedScrollRefreshNotificationPredicate,
              onRefresh: () =>
                  _refreshSchedule(forceRefresh: true, showFeedback: true),
              child: ElasticOverscrollStretchWrapper(
                child: NestedScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  headerSliverBuilder: (context, _) => [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        adaptiveAppBarTopPadding(context),
                        16,
                        10,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeroCard(
                              theme: theme,
                              scheme: scheme,
                              prefs: activePrefs,
                              schedule: schedule,
                              countdownEvent: countdownEvent,
                              isPinned: _pinnedCountdownEventId != null &&
                                  countdownEvent?.id == _pinnedCountdownEventId,
                              now: now,
                            ),
                            const SizedBox(height: 10),
                            if (resolvedPdfUrl != null &&
                                resolvedPdfUrl.isNotEmpty) ...[
                              SoftGlassCard(
                                prefs: activePrefs,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                borderRadius: OledTheme.cardRadius,
                                border: Border.all(
                                  color: scheme.primary.withValues(alpha: 0.35),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.picture_as_pdf_rounded,
                                      color: scheme.primary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        uwuLabel(
                                          'Hivatalos iskolai PDF dokumentum elérhető',
                                          enabled: uwuOn,
                                        ),
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton.tonalIcon(
                                      key: const ValueKey<String>(
                                        'school-year-open-pdf-btn',
                                      ),
                                      onPressed: () =>
                                          _openExternalUrl(resolvedPdfUrl),
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        uwuLabel(
                                          'Forrás / PDF',
                                          enabled: uwuOn,
                                        ),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey<String>(
                                    'school-year-url-btn',
                                  ),
                                  onPressed: _openCustomUrlDialog,
                                  icon:
                                      const Icon(Icons.link_rounded, size: 16),
                                  label: Text(
                                    uwuLabel(
                                      _customUrl != null
                                          ? 'Egyéni URL'
                                          : 'Iskola honlap',
                                      enabled: uwuOn,
                                    ),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  key: const ValueKey<String>(
                                    'school-year-add-event-btn',
                                  ),
                                  onPressed: _openAddCustomEventDialog,
                                  icon:
                                      const Icon(Icons.add_rounded, size: 17),
                                  label: Text(
                                    uwuLabel('Saját nap', enabled: uwuOn),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final filter
                                      in _ScheduleFilter.values) ...[
                                    ChoiceChip(
                                      key: ValueKey<String>(
                                        'school-year-filter-${filter.keySuffix}',
                                      ),
                                      label: Text(
                                        uwuLabel(filter.label, enabled: uwuOn),
                                      ),
                                      selected: _selectedFilter == filter,
                                      onSelected: (_) => _selectFilter(filter),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                ],
                              ),
                            ),
                            if (availableCategories.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildCategoryToggleStrip(
                                theme: theme,
                                scheme: scheme,
                                categories: availableCategories,
                                uwuOn: uwuOn,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  body: HorizontalSubTabSwipeDetector(
                    key: const ValueKey<String>('school-year-subtab-swipe'),
                    currentIndex: _ScheduleFilter.values
                        .indexOf(_selectedFilter)
                        .clamp(0, _ScheduleFilter.values.length - 1),
                    itemCount: _ScheduleFilter.values.length,
                    pageController: _filterPageController,
                    onIndexChanged: (idx) => _selectFilter(
                      _ScheduleFilter.values[idx],
                      animatePage: false,
                    ),
                    pageBuilder: (pageCtx, pageIdx) {
                      final pageFilter = _ScheduleFilter.values[pageIdx];
                      final pageFiltered = schedule.events
                          .where(
                            (e) =>
                                pageFilter.matches(e) &&
                                !_hiddenCategories.contains(e.category),
                          )
                          .toList();
                      final pageUpcoming =
                          pageFiltered.where((e) => !e.isPastOn(now)).toList();
                      final pagePast =
                          pageFiltered.where((e) => e.isPastOn(now)).toList();
                      return ListView(
                        key: PageStorageKey<String>(
                          'school-year-page-${pageFilter.keySuffix}',
                        ),
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
                        children: [
                          if (pageUpcoming.isEmpty && pagePast.isEmpty) ...[
                            SoftGlassCard(
                              prefs: activePrefs,
                              padding: const EdgeInsets.all(14),
                              borderRadius: OledTheme.cardRadius,
                              child: Text(
                                uwuLabel(
                                  _hiddenCategories.isNotEmpty
                                      ? 'Minden kategória rejtve van ebben a nézetben. Kapcsold vissza a fenti kategóriákat!'
                                      : (pageFilter == _ScheduleFilter.school
                                          ? 'Még nem található egyedi iskolai program. Add meg az iskola honlapjának vagy PDF-jének linkjét alább!'
                                          : 'Nincs megjeleníthető esemény ebben a szűrőben.'),
                                  enabled: uwuOn,
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.72),
                                ),
                              ),
                            ),
                          ],
                          if (pageUpcoming.isNotEmpty) ...[
                            Text(
                              uwuLabel('Közelgő események', enabled: uwuOn),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final event in pageUpcoming)
                              _buildEventCard(
                                theme: theme,
                                scheme: scheme,
                                prefs: activePrefs,
                                event: event,
                                now: now,
                                isPast: false,
                              ),
                          ],
                          if (pagePast.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text(
                              uwuLabel('Korábbi események', enabled: uwuOn),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (final event in pagePast)
                              _buildEventCard(
                                theme: theme,
                                scheme: scheme,
                                prefs: activePrefs,
                                event: event,
                                now: now,
                                isPast: true,
                              ),
                          ],
                          const SizedBox(height: 14),
                          _buildBottomSourceCard(
                            theme: theme,
                            scheme: scheme,
                            prefs: activePrefs,
                            schedule: schedule,
                            resolvedPdfUrl: resolvedPdfUrl,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildBottomSourceCard({
    required ThemeData theme,
    required ColorScheme scheme,
    required UserProfilePrefs prefs,
    required SchoolYearSchedule schedule,
    required String? resolvedPdfUrl,
  }) {
    final uwuOn = prefs.uwuModeEnabled;
    final displayUrl = _customUrl ??
        schedule.sourceUrl ??
        schedule.pdfUrl ??
        schedule.icsUrl;
    return SoftGlassCard(
      key: const ValueKey<String>('school-year-source-card'),
      prefs: prefs,
      padding: const EdgeInsets.all(14),
      borderRadius: OledTheme.cardRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.language_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  uwuLabel('Forrás és Iskolai Honlap', enabled: uwuOn),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                schedule.sourceLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            displayUrl != null && displayUrl.isNotEmpty
                ? displayUrl
                : uwuLabel(
                    'Országos tanév rendje (nem található automatikus iskolai URL)',
                    enabled: uwuOn,
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            uwuLabel(
              'Utolsó szinkron: ${_syncFormat.format(schedule.fetchedAt.toLocal())}',
              enabled: uwuOn,
            ),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              color: scheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey<String>('school-year-bottom-url-btn'),
                onPressed: _openCustomUrlDialog,
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: Text(
                  uwuLabel('URL megadása / módosítása', enabled: uwuOn),
                ),
              ),
              if (displayUrl != null && displayUrl.isNotEmpty)
                FilledButton.tonalIcon(
                  onPressed: () =>
                      _openExternalUrl(resolvedPdfUrl ?? displayUrl),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text(
                    uwuLabel('Forrás / PDF megnyitása', enabled: uwuOn),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryToggleStrip({
    required ThemeData theme,
    required ColorScheme scheme,
    required List<SchoolYearEventCategory> categories,
    required bool uwuOn,
  }) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, idx) {
          final cat = categories[idx];
          final visible = !_hiddenCategories.contains(cat);
          final catColor = OledTheme.semanticForeground(
            cat.color,
            theme.brightness,
          );
          return TactileBounce(
            key: ValueKey<String>('school-year-cat-toggle-${cat.name}'),
            pressedScale: 0.96,
            onTap: () => _toggleCategory(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: visible
                    ? catColor.withValues(alpha: 0.14)
                    : scheme.onSurface.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: visible
                      ? catColor.withValues(alpha: 0.45)
                      : scheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 13,
                    color: visible
                        ? catColor
                        : scheme.onSurface.withValues(alpha: 0.38),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    uwuLabel(cat.label, enabled: uwuOn),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: visible ? FontWeight.w800 : FontWeight.w600,
                      decoration:
                          visible ? null : TextDecoration.lineThrough,
                      color: visible
                          ? catColor
                          : scheme.onSurface.withValues(alpha: 0.42),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroCard({
    required ThemeData theme,
    required ColorScheme scheme,
    required UserProfilePrefs prefs,
    required SchoolYearSchedule schedule,
    required SchoolYearEvent? countdownEvent,
    required bool isPinned,
    required DateTime now,
  }) {
    final uwuOn = prefs.uwuModeEnabled;
    final focusEvent = countdownEvent;
    final focusColor = OledTheme.semanticForeground(
      focusEvent?.category.color ?? scheme.primary,
      theme.brightness,
    );
    final progress = schedule.schoolYearProgress(now);
    final progressPct = (progress * 100).round();

    String headline = '${schedule.schoolYearLabel}-es tanév';
    String countdownBadge = '$progressPct%';
    String subtitle = schedule.schoolName ?? schedule.sourceLabel;

    if (focusEvent != null) {
      headline = focusEvent.title;
      if (focusEvent.isOngoingOn(now)) {
        countdownBadge = 'Még ${focusEvent.daysRemaining(now)} nap';
      } else {
        final until = focusEvent.daysUntil(now);
        countdownBadge = until == 0 ? 'Ma' : '$until nap múlva';
      }
      subtitle = _formatRange(focusEvent);
    }

    return SoftGlassCard(
      prefs: prefs,
      padding: const EdgeInsets.all(16),
      borderRadius: OledTheme.largeRadius,
      border: Border.all(
        color: focusColor.withValues(alpha: 0.45),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    uwuLabel(
                      '${schedule.schoolYearLabel} • ${schedule.sourceLabel}',
                      enabled: uwuOn,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: focusColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  countdownBadge,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: focusColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            uwuLabel(headline, enabled: uwuOn),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            uwuLabel(subtitle, enabled: uwuOn),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TactileBounce(
                key: const ValueKey<String>('school-year-countdown-target-btn'),
                pressedScale: 0.96,
                onTap: () =>
                    _openCountdownTargetPickerSheet(schedule, now, prefs),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: focusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: focusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPinned
                            ? Icons.push_pin_rounded
                            : Icons.auto_awesome_rounded,
                        size: 13,
                        color: focusColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        uwuLabel(
                          isPinned
                              ? 'Kitűzött célpont • Váltás'
                              : 'Automatikus (legközelebbi)',
                          enabled: uwuOn,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: focusColor,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 15,
                        color: focusColor,
                      ),
                    ],
                  ),
                ),
              ),
              if (schedule.schoolEventsCount > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    uwuLabel(
                      '${schedule.schoolEventsCount} iskolai program',
                      enabled: uwuOn,
                    ),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF06B6D4),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                uwuLabel('Tanév haladása', enabled: uwuOn),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$progressPct%',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard({
    required ThemeData theme,
    required ColorScheme scheme,
    required UserProfilePrefs prefs,
    required SchoolYearEvent event,
    required DateTime now,
    required bool isPast,
  }) {
    final uwuOn = prefs.uwuModeEnabled;
    final cat = event.category;
    final tint = OledTheme.semanticForeground(cat.color, theme.brightness);
    final ongoing = event.isOngoingOn(now);
    final daysUntil = event.daysUntil(now);
    final isPinned = _pinnedCountdownEventId == event.id;
    final statusPill = ongoing
        ? 'Még ${event.daysRemaining(now)} nap'
        : (isPast
            ? 'Elmúlt'
            : (daysUntil == 0 ? 'Ma' : '$daysUntil nap'));

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: isPast ? 0.58 : 1.0,
        child: SoftGlassCard(
          prefs: prefs,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (ongoing || isPinned)
                ? tint.withValues(alpha: 0.72)
                : theme.dividerColor,
            width: (ongoing || isPinned) ? 1.3 : 0.9,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  cat.icon,
                  color: tint,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            uwuLabel(event.title, enabled: uwuOn),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${_formatCompactRange(event)} • ${cat.shortLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: scheme.onSurface.withValues(alpha: 0.66),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (event.effectiveSource == SchoolYearEventSource.school ||
                            event.isCustom) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: tint.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              uwuLabel(
                                event.effectiveSource ==
                                        SchoolYearEventSource.school
                                    ? 'Iskolai program'
                                    : 'Saját',
                                enabled: uwuOn,
                              ),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: tint,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusPill,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: tint,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (!isPast) ...[
                const SizedBox(width: 4),
                InkWell(
                  key: ValueKey<String>('school-year-pin-${event.id}'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _setPinnedCountdownEvent(
                    isPinned ? null : event.id,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 15,
                      color: isPinned
                          ? tint
                          : scheme.onSurface.withValues(alpha: 0.36),
                    ),
                  ),
                ),
              ],
              if (event.isCustom) ...[
                const SizedBox(width: 2),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => _deleteCustomEvent(event),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomUrlSheetContent extends StatefulWidget {
  final String initialUrl;
  final bool hasOverride;
  final UserProfilePrefs prefs;

  const _CustomUrlSheetContent({
    required this.initialUrl,
    required this.hasOverride,
    required this.prefs,
  });

  @override
  State<_CustomUrlSheetContent> createState() => _CustomUrlSheetContentState();
}

class _CustomUrlSheetContentState extends State<_CustomUrlSheetContent> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialUrl);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final closeMode = widget.prefs.modalCloseMode;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: (MediaQuery.sizeOf(context).height - bottomInset) * 0.86,
        ),
        child: FrostedBottomSheetSurface(
          topRadius: 26,
          prefs: widget.prefs,
          showDragHandle: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: SingleChildScrollView(
            physics: const FloatingSheetScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.link_rounded,
                        size: 19,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        uwu('Iskolai honlap URL'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (closeMode.showTopX)
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(context).pop(null),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  uwu(
                    'Illeszd be az iskola weboldalának, .ics naptárának vagy közvetlenül a Tanév rendje oldalának / PDF-jének linkjét:',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey<String>('school-year-custom-url-input'),
                  controller: _ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    hintText: 'https://iskola.hu/tanev-rendje',
                    prefixIcon: const Icon(Icons.language_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.hasOverride)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(''),
                        child: Text(uwu('Alapértelmezett')),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: Text(uwu('Mégse')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const ValueKey<String>('school-year-save-url-btn'),
                      onPressed: () =>
                          Navigator.of(context).pop(_ctrl.text.trim()),
                      child: Text(uwu('Mentés')),
                    ),
                  ],
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 12),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(context).pop(null),
                    uwuEnabled: widget.prefs.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomEventSheetContent extends StatefulWidget {
  final DateTime initialStartDate;
  final DateFormat shortFormat;
  final UserProfilePrefs prefs;

  const _CustomEventSheetContent({
    required this.initialStartDate,
    required this.shortFormat,
    required this.prefs,
  });

  @override
  State<_CustomEventSheetContent> createState() =>
      _CustomEventSheetContentState();
}

class _CustomEventSheetContentState extends State<_CustomEventSheetContent> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  SchoolYearEventType _selectedType = SchoolYearEventType.specialDay;
  late DateTime _startDate = widget.initialStartDate;
  late DateTime _endDate = widget.initialStartDate;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closeMode = widget.prefs.modalCloseMode;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: (MediaQuery.sizeOf(context).height - bottomInset) * 0.88,
        ),
        child: FrostedBottomSheetSurface(
          topRadius: 26,
          prefs: widget.prefs,
          showDragHandle: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: SingleChildScrollView(
            physics: const FloatingSheetScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        uwu('Saját esemény hozzáadása'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (closeMode.showTopX)
                      PopupTopCloseButton(
                        onTap: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: uwu('Megnevezés (pl. Diáknap)'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<SchoolYearEventType>(
                  initialValue: _selectedType,
                  decoration: InputDecoration(
                    labelText: uwu('Típus'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: SchoolYearEventType.values
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(t.label),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedType = v);
                    }
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTintaDatePickerSheet(
                            context: context,
                            prefs: widget.prefs,
                            initialDate: _startDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2032),
                          );
                          if (picked != null && mounted) {
                            setState(() {
                              _startDate = picked;
                              if (_endDate.isBefore(_startDate)) {
                                _endDate = _startDate;
                              }
                            });
                          }
                        },
                        child: Text(
                          'Kezdet: ${widget.shortFormat.format(_startDate)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final picked = await showTintaDatePickerSheet(
                            context: context,
                            prefs: widget.prefs,
                            initialDate: _endDate,
                            firstDate: _startDate,
                            lastDate: DateTime(2032),
                          );
                          if (picked != null && mounted) {
                            setState(() => _endDate = picked);
                          }
                        },
                        child:
                            Text('Vége: ${widget.shortFormat.format(_endDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: uwu('Megjegyzés (opcionális)'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(uwu('Mégse')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final title = _titleCtrl.text.trim();
                        if (title.isEmpty) return;
                        Navigator.of(context).pop(
                          SchoolYearEvent(
                            id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                            title: title,
                            startDate: _startDate,
                            endDate: _endDate,
                            type: _selectedType,
                            description: _descCtrl.text.trim().isEmpty
                                ? null
                                : _descCtrl.text.trim(),
                            isCustom: true,
                            source: SchoolYearEventSource.custom,
                          ),
                        );
                      },
                      child: Text(uwu('Hozzáadás')),
                    ),
                  ],
                ),
                if (closeMode.showBottomButton) ...[
                  const SizedBox(height: 12),
                  PopupBottomCloseButton(
                    onTap: () => Navigator.of(context).pop(),
                    uwuEnabled: widget.prefs.uwuModeEnabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
