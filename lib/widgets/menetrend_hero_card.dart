import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/html_sanitizer.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'edge_fade_horizontal_scroll.dart';
import 'frosted_inspection_modal.dart';
import 'glass_card.dart';

/// Home wrapper for the MenetrendGO card. Outside morning/afternoon commute
/// windows or when zero catchable departures remain, renders [SizedBox.shrink]
/// so it takes zero space on Főoldal.
class MenetrendHomeCard extends StatelessWidget {
  final CommuteEvaluation? evaluation;
  final bool isLoading;
  final UserProfilePrefs prefs;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;
  final List<Lesson>? todaysLessons;
  final DateTime? now;

  const MenetrendHomeCard({
    super.key,
    required this.evaluation,
    required this.isLoading,
    required this.prefs,
    required this.onOpenSettings,
    required this.onRetry,
    this.todaysLessons,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    final activePrefs = scope?.settings.prefs ?? prefs;
    final rawEval = scope?.commute.evaluation ?? evaluation;
    if (!activePrefs.transitCardEnabled ||
        !activePrefs.transitConfigured ||
        rawEval == null) {
      return const SizedBox.shrink();
    }
    final resolvedLessons = todaysLessons ??
        (scope != null && scope.commute.hasLessons
            ? scope.commute.todaysLessons
            : null);
    final effectiveEval = MenetrendService.filterVisibleEvaluation(
      evaluation: rawEval,
      todaysLessons: resolvedLessons,
      prefs: activePrefs,
      now: now ?? rawEval.now,
    );
    if (effectiveEval == null) {
      return const SizedBox.shrink();
    }
    return RepaintBoundary(
      child: MenetrendHeroCard(evaluation: effectiveEval, prefs: activePrefs),
    );
  }
}

Widget _buildMenetrendHeroShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final fromRender = fromHeroContext.findRenderObject() as RenderBox?;
  final toRender = toHeroContext.findRenderObject() as RenderBox?;
  final fromSize = (fromRender != null && fromRender.hasSize)
      ? fromRender.size
      : (flightDirection == HeroFlightDirection.push
          ? const Size(210, 26)
          : const Size(48, 48));
  final toSize = (toRender != null && toRender.hasSize)
      ? toRender.size
      : (flightDirection == HeroFlightDirection.push
          ? const Size(48, 48)
          : const Size(210, 26));

  final fromHero = fromHeroContext.widget as Hero;
  final toHero = toHeroContext.widget as Hero;
  final isPush = flightDirection == HeroFlightDirection.push;

  final progress = CurvedAnimation(
    parent: animation,
    curve: Curves.easeInOutCubic,
  );
  final fromOpacity = isPush ? ReverseAnimation(progress) : progress;
  final toOpacity = isPush ? progress : ReverseAnimation(progress);

  // Scale both hero snapshots strictly inside bounded SizedBoxes via FittedBox
  // so exit/pop transitions never compress inner Row children below min width.
  return Material(
    type: MaterialType.transparency,
    child: Stack(
      fit: StackFit.expand,
      alignment: Alignment.centerLeft,
      children: [
        FadeTransition(
          opacity: fromOpacity,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            child: SizedBox.fromSize(
              size: fromSize,
              child: fromHero.child,
            ),
          ),
        ),
        FadeTransition(
          opacity: toOpacity,
          child: FittedBox(
            fit: BoxFit.contain,
            alignment: Alignment.centerLeft,
            child: SizedBox.fromSize(
              size: toSize,
              child: toHero.child,
            ),
          ),
        ),
      ],
    ),
  );
}

class _TransitStatusInfo {
  final Color color;
  final String label;

  const _TransitStatusInfo({
    required this.color,
    required this.label,
  });

  factory _TransitStatusInfo.fromTrip(MenetrendTripOption trip) {
    if (trip.isCancelled) {
      return const _TransitStatusInfo(
        color: Color(0xFFEF4444),
        label: 'Kimarad',
      );
    }
    if (trip.delayMinutes >= 10) {
      return _TransitStatusInfo(
        color: const Color(0xFFEF4444),
        label: '+${trip.delayMinutes}p késés',
      );
    }
    if (trip.delayMinutes > 0) {
      return _TransitStatusInfo(
        color: const Color(0xFFF59E0B),
        label: '+${trip.delayMinutes}p késés',
      );
    }
    return const _TransitStatusInfo(
      color: Color(0xFF22C55E),
      label: 'Időben',
    );
  }
}

class MenetrendHeroCard extends StatelessWidget {
  final CommuteEvaluation evaluation;
  final UserProfilePrefs prefs;

  const MenetrendHeroCard({
    super.key,
    required this.evaluation,
    required this.prefs,
  });

  IconData _iconForMode(MenetrendTransportMode mode) {
    switch (mode) {
      case MenetrendTransportMode.rail:
        return Icons.train_rounded;
      case MenetrendTransportMode.coach:
        return Icons.directions_bus_filled_rounded;
      case MenetrendTransportMode.localBus:
        return Icons.directions_bus_rounded;
      case MenetrendTransportMode.walk:
        return Icons.directions_walk_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? prefs;
    final trip = evaluation.recommendedTrip;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final secondaryText =
        isDark ? OledTheme.textSecondary : onSurface.withValues(alpha: 0.72);
    final bool isDelayed = trip.delayMinutes > 0 && !trip.isCancelled;
    final statusInfo = _TransitStatusInfo.fromTrip(trip);
    final statusColor = statusInfo.color;

    final Color? arrivalTimeColor = trip.isCancelled
        ? const Color(0xFFEF4444)
        : (trip.delayMinutes >= 10
            ? const Color(0xFFEF4444)
            : (trip.delayMinutes > 0 ? const Color(0xFFF59E0B) : null));
    final displayedArrivalTime = isDelayed
        ? trip.effectiveDestinationArrivalTimeFormatted
        : trip.destinationArrivalTimeFormatted;

    final walkStartFormatted =
        DateFormat('HH:mm').format(evaluation.latestWalkStartTime);
    final safeLine = trip.safeRouteShortName;

    final walkSubtitle = uwuLabel(
      evaluation.effectiveWalkMinutes > 0
          ? 'Indulás: $walkStartFormatted (${evaluation.effectiveWalkMinutes}p séta)'
          : 'Indulásig: ${evaluation.minutesUntilDeparture}p',
      enabled: activePrefs.uwuModeEnabled,
    );

    final cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'MENETRENDGO',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                              color: onSurface.withValues(alpha: 0.50),
                            ),
                          ),
                          TextSpan(
                            text: '  •  ',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: onSurface.withValues(alpha: 0.35),
                            ),
                          ),
                          TextSpan(
                            text: uwuLabel(
                              statusInfo.label,
                              enabled: activePrefs.uwuModeEnabled,
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: statusColor.withValues(alpha: 0.92),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TactileBounce(
                    pressedScale: 0.92,
                    onTap: () => MenetrendService.openInMenetrendGo(
                      trip: trip,
                      evaluation: evaluation,
                      prefs: activePrefs,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.open_in_new_rounded,
                        size: 16,
                        color: onSurface.withValues(alpha: 0.54),
                      ),
                    ),
                  ),
                ],
              ),
              if (trip.isFavorite) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3.5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    uwuLabel(
                      trip.favoriteBadgeText,
                      enabled: activePrefs.uwuModeEnabled,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFFD54F),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  final maxBadgeW =
                      (constraints.maxWidth * 0.30).clamp(64.0, 116.0);
                  final maxTimesW =
                      (constraints.maxWidth * 0.44).clamp(76.0, 168.0);
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (trip.legs.length <= 1) ...[
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxBadgeW),
                          child: Hero(
                            tag: 'menetrend_hero_card',
                            createRectTween: createLinearHeroRectTween,
                            flightShuttleBuilder: _buildMenetrendHeroShuttle,
                            child: Material(
                              type: MaterialType.transparency,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    safeLine,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w900,
                                      color: primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ] else ...[
                        Hero(
                          tag: 'menetrend_hero_card',
                          createRectTween: createLinearHeroRectTween,
                          flightShuttleBuilder: _buildMenetrendHeroShuttle,
                          child: Material(
                            type: MaterialType.transparency,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: primary.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                _iconForMode(trip.mode),
                                size: 18,
                                color: primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              uwuLabel(
                                HtmlSanitizer.clean(
                                  '${trip.departureStation} → ${trip.arrivalStation}',
                                ),
                                enabled: activePrefs.uwuModeEnabled,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              walkSubtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: secondaryText,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxTimesW),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                trip.departureTimeFormatted,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: onSurface,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              Text(
                                uwuLabel(
                                  'Érk.: $displayedArrivalTime',
                                  enabled: activePrefs.uwuModeEnabled,
                                ),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: arrivalTimeColor != null
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: arrivalTimeColor ?? secondaryText,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                              if (isDelayed)
                                Text(
                                  uwuLabel(
                                    'Becsült ind.: ${trip.effectiveDepartureTimeFormatted}',
                                    enabled: activePrefs.uwuModeEnabled,
                                  ),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        if (trip.legs.length > 1) ...[
          const SizedBox(height: 10),
          EdgeFadeHorizontalScroll(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (var i = 0; i < trip.legs.length; i++) ...[
                () {
                  final leg = trip.legs[i];
                  final cleanLegName = MenetrendService.sanitizeTransitLineName(
                    rawShortName: leg.routeShortName,
                    rawTripShortName: leg.tripShortName,
                    mode: leg.mode,
                  );
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: primary.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _iconForMode(leg.mode),
                          size: 13,
                          color: primary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          uwuLabel(
                            '${i + 1}. szakasz: $cleanLegName '
                            '(${leg.mode == MenetrendTransportMode.rail ? "vonat" : "busz"})',
                            enabled: activePrefs.uwuModeEnabled,
                          ),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  );
                }(),
                if (i < trip.legs.length - 1) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: secondaryText,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color:
                            const Color(0xFFFFB300).withValues(alpha: 0.38),
                      ),
                    ),
                    child: Text(
                      uwuLabel(
                        'Átszállás ${trip.legs[i + 1].departure.difference(trip.legs[i].arrival).inMinutes} p',
                        enabled: activePrefs.uwuModeEnabled,
                      ),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFB300),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: secondaryText,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ],
    );

    return TactileBounce(
      onTap: () => showMenetrendDetailsModal(
        context,
        evaluation: evaluation,
        prefs: activePrefs,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SoftGlassCard(
          prefs: activePrefs,
          padding: const EdgeInsets.symmetric(vertical: 14),
          borderRadius: OledTheme.largeRadius,
          borderColor: primary.withValues(alpha: 0.35),
          child: cardContent,
        ),
      ),
    );
  }
}

Future<void> showMenetrendDetailsModal(
  BuildContext context, {
  required CommuteEvaluation evaluation,
  required UserProfilePrefs prefs,
}) async {
  await showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(
      context,
      prefs: prefs,
      solidDarkAlpha: 0.72,
      solidLightAlpha: 0.48,
    ),
    builder: (ctx) {
      return _MenetrendDetailsModalSheet(
        evaluation: evaluation,
        prefs: prefs,
      );
    },
  );
}

class _MenetrendDetailsModalSheet extends StatefulWidget {
  final CommuteEvaluation evaluation;
  final UserProfilePrefs prefs;

  const _MenetrendDetailsModalSheet({
    required this.evaluation,
    required this.prefs,
  });

  @override
  State<_MenetrendDetailsModalSheet> createState() =>
      _MenetrendDetailsModalSheetState();
}

class _MenetrendDetailsModalSheetState
    extends State<_MenetrendDetailsModalSheet> {
  late MenetrendTripOption _selectedTrip;
  bool _stopsExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedTrip = widget.evaluation.recommendedTrip;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppProvidersScope.maybeOf(context);
    final activePrefs = scope?.settings.prefs ?? widget.prefs;
    final activeEval = scope?.commute.evaluation ?? widget.evaluation;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final secondaryText = onSurface.withValues(alpha: 0.58);
    final surfaceElevated =
        isDark ? OledTheme.surfaceElevated : theme.colorScheme.surfaceContainerHigh;
    final hairlineColor =
        onSurface.withValues(alpha: isDark ? 0.08 : 0.07);

    final closeMode = activePrefs.modalCloseMode;
    final firstLessonStart = activeEval.isMorningMode
        ? activeEval.targetLesson?.start.toLocal()
        : null;
    final visibleAlternatives = activeEval.alternatives
        .map(
          (alt) => alt.recalculateForPrefs(
            activePrefs,
            isMorning: activeEval.isMorningMode,
          ),
        )
        .where(
          (alt) =>
              firstLessonStart == null ||
              MenetrendService.arrivesOnTimeForFirstLesson(
                alt,
                firstLessonStart,
              ),
        )
        .toList();
    final candidateTrip = _selectedTrip.recalculateForPrefs(
      activePrefs,
      isMorning: activeEval.isMorningMode,
    );
    final trip = (firstLessonStart == null ||
            MenetrendService.arrivesOnTimeForFirstLesson(
              candidateTrip,
              firstLessonStart,
            ) ||
            visibleAlternatives.isEmpty)
        ? candidateTrip
        : visibleAlternatives.last;
    final safeLine = trip.safeRouteShortName;
    final statusInfo = _TransitStatusInfo.fromTrip(trip);
    final isDelayed = trip.delayMinutes > 0 && !trip.isCancelled;

    final walkLeave = trip.scheduledDeparture
        .subtract(Duration(minutes: trip.walkToStationMinutes));
    final destinationArrive = trip.scheduledDestinationArrival;
    final arrivalTimeStr = isDelayed
        ? trip.effectiveArrivalTimeFormatted
        : trip.arrivalTimeFormatted;

    final arrivalPlatform = trip.arrivalPlatformCode?.trim() ?? '';
    final arrivalSubtitle = arrivalPlatform.isNotEmpty
        ? 'Leszállás • $arrivalPlatform'
        : 'Leszállás';

    final boardingPlatform = trip.platformCode?.trim() ?? '';
    final boardingSubtitle = boardingPlatform.isNotEmpty
        ? 'Felszállás • $safeLine • $boardingPlatform'
        : 'Felszállás • $safeLine';

    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: FrostedBottomSheetSurface(
          prefs: activePrefs,
          showDragHandle: true,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                                    Hero(
                                      tag: 'menetrend_hero_card',
                                      createRectTween: createLinearHeroRectTween,
                                      flightShuttleBuilder:
                                          _buildMenetrendHeroShuttle,
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: Container(
                                          width: 48,
                                          height: 48,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: primary.withValues(
                                              alpha: 0.16,
                                            ),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: primary.withValues(
                                                alpha: 0.28,
                                              ),
                                              width: 1.2,
                                            ),
                                          ),
                                          child: Icon(
                                            trip.mode ==
                                                    MenetrendTransportMode.rail
                                                ? Icons.train_rounded
                                                : Icons
                                                    .directions_bus_filled_rounded,
                                            color: primary,
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            uwuLabel(
                                              '$safeLine • ${trip.mode.displayName}',
                                              enabled:
                                                  activePrefs.uwuModeEnabled,
                                            ),
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                              fontSize: 18.5,
                                              height: 1.22,
                                              letterSpacing: -0.3,
                                              fontWeight: FontWeight.w800,
                                              color: onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text.rich(
                                            TextSpan(
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: secondaryText,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: uwuLabel(
                                                    statusInfo.label,
                                                    enabled: activePrefs
                                                        .uwuModeEnabled,
                                                  ),
                                                  style: TextStyle(
                                                    color: statusInfo.color
                                                        .withValues(alpha: 0.92),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                TextSpan(
                                                  text: uwuLabel(
                                                    ' • ${trip.travelDurationMinutes}p menetidő',
                                                    enabled: activePrefs
                                                        .uwuModeEnabled,
                                                  ),
                                                ),
                                                if (isDelayed)
                                                  TextSpan(
                                                    text: uwuLabel(
                                                      ' • Becsült ind.: ${trip.effectiveDepartureTimeFormatted}',
                                                      enabled: activePrefs
                                                          .uwuModeEnabled,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (closeMode.showTopX) ...[
                                      const SizedBox(width: 8),
                                      TactileBounce(
                                        onTap: () =>
                                            Navigator.of(context).pop(),
                                        child: Container(
                                          width: 32,
                                          height: 32,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: onSurface.withValues(
                                              alpha: isDark ? 0.08 : 0.06,
                                            ),
                                          ),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                            color: onSurface.withValues(
                                              alpha: 0.72,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (visibleAlternatives.length > 1) ...[
                                const SizedBox(height: 12),
                                EdgeFadeHorizontalScroll(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                  ),
                                  spacing: 8,
                                  children: visibleAlternatives.map((alt) {
                                    final safeAlt = alt.safeRouteShortName;
                                    final isSel = alt.scheduledDeparture ==
                                            trip.scheduledDeparture &&
                                        safeAlt == safeLine;
                                    return ChoiceChip(
                                      label: Text(
                                        '$safeAlt (${alt.departureTimeFormatted})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isSel
                                              ? theme.colorScheme.onPrimary
                                              : onSurface,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      selected: isSel,
                                      selectedColor: primary,
                                      backgroundColor: surfaceElevated,
                                      onSelected: (_) {
                                        setState(() {
                                          _selectedTrip = alt;
                                          _stopsExpanded = false;
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: hairlineColor,
                                    ),
                                    const SizedBox(height: 16),
                                    if (trip.walkToStationMinutes > 0)
                                      _buildTimelineStep(
                                        context: context,
                                        icon: Icons.directions_walk_rounded,
                                        time: DateFormat('HH:mm')
                                            .format(walkLeave),
                                        title: uwuLabel(
                                          'Séta az állomásra',
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        subtitle: uwuLabel(
                                          '${trip.walkToStationMinutes}p séta',
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        accentColor: secondaryText,
                                      ),
                                    if (trip.legs.length > 1)
                                      ..._buildLegSteps(context, trip, primary)
                                    else ...[
                                      _buildTimelineStep(
                                        context: context,
                                        icon: trip.mode ==
                                                MenetrendTransportMode.rail
                                            ? Icons.train_rounded
                                            : Icons.directions_bus_rounded,
                                        time: trip.departureTimeFormatted,
                                        title: uwuLabel(
                                          HtmlSanitizer.clean(
                                            trip.departureStation,
                                          ),
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        subtitle: uwuLabel(
                                          boardingSubtitle,
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        accentColor: primary,
                                      ),
                                      if (trip.intermediateStops.isNotEmpty)
                                        _buildIntermediateStopsInlineRow(
                                          context: context,
                                          stops: trip.intermediateStops,
                                          onSurface: onSurface,
                                          secondaryText: secondaryText,
                                          isDark: isDark,
                                        ),
                                    ],
                                    _buildTimelineStep(
                                      context: context,
                                      icon: Icons.location_on_rounded,
                                      time: arrivalTimeStr,
                                      timeColor: trip.isCancelled
                                          ? const Color(0xFFEF4444)
                                          : (trip.delayMinutes >= 10
                                              ? const Color(0xFFEF4444)
                                              : (trip.delayMinutes > 0
                                                  ? const Color(0xFFF59E0B)
                                                  : null)),
                                      title: uwuLabel(
                                        HtmlSanitizer.clean(
                                          trip.arrivalStation,
                                        ),
                                        enabled: activePrefs.uwuModeEnabled,
                                      ),
                                      subtitle: uwuLabel(
                                        arrivalSubtitle,
                                        enabled: activePrefs.uwuModeEnabled,
                                      ),
                                      accentColor: const Color(0xFF22C55E),
                                      isLast: trip.walkToDestinationMinutes <= 0,
                                    ),
                                    if (trip.walkToDestinationMinutes > 0)
                                      _buildTimelineStep(
                                        context: context,
                                        icon: activeEval.isMorningMode
                                            ? Icons.school_rounded
                                            : Icons.home_rounded,
                                        time: DateFormat('HH:mm')
                                            .format(destinationArrive),
                                        title: uwuLabel(
                                          activeEval.isMorningMode
                                              ? 'Iskola'
                                              : 'Otthon',
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        subtitle: uwuLabel(
                                          '${trip.walkToDestinationMinutes}p séta',
                                          enabled: activePrefs.uwuModeEnabled,
                                        ),
                                        accentColor: secondaryText,
                                        isLast: true,
                                      ),
                                    const SizedBox(height: 18),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 47,
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            MenetrendService.openInMenetrendGo(
                                          trip: trip,
                                          evaluation: activeEval,
                                          prefs: activePrefs,
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 17,
                                        ),
                                        label: Text(
                                          uwuLabel(
                                            'Megnyitás MenetrendGO-ban',
                                            enabled: activePrefs.uwuModeEnabled,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          foregroundColor:
                                              theme.colorScheme.onPrimary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (closeMode.showBottomButton) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: TextButton(
                                          onPressed: () =>
                                              Navigator.of(context).pop(),
                                          child: Text(
                                            uwuLabel(
                                              'Bezárás',
                                              enabled:
                                                  activePrefs.uwuModeEnabled,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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

  Widget _buildIntermediateStopsInlineRow({
    required BuildContext context,
    required List<MenetrendStop> stops,
    required Color onSurface,
    required Color secondaryText,
    required bool isDark,
  }) {
    final connectorColor =
        onSurface.withValues(alpha: isDark ? 0.14 : 0.12);
    final isSingle = stops.length == 1;
    final headerText = uwuLabel(
      isSingle
          ? '1 köztes megálló: ${HtmlSanitizer.clean(stops.first.name)}'
          : '${stops.length} köztes megálló',
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Center(
              child: Container(
                width: 1.5,
                color: connectorColor,
              ),
            ),
          ),
          const SizedBox(width: 56),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSingle)
                    Text(
                      headerText,
                      style: TextStyle(
                        fontSize: 12,
                        color: secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else ...[
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          setState(() => _stopsExpanded = !_stopsExpanded),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            headerText,
                            style: TextStyle(
                              fontSize: 12,
                              color: secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _stopsExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 16,
                            color: secondaryText,
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: _stopsExpanded
                          ? Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final stop in stops)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              uwuLabel(
                                                HtmlSanitizer.clean(stop.name),
                                              ),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: onSurface.withValues(
                                                  alpha: 0.78,
                                                ),
                                              ),
                                            ),
                                          ),
                                          if (stop.timeLabel != null)
                                            Text(
                                              stop.timeLabel!,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: secondaryText,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures(),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Explicit sequential segments for transfer trips:
  /// [Leg 1] -> [Átszállás wait] -> [Leg 2] ...
  List<Widget> _buildLegSteps(
    BuildContext context,
    MenetrendTripOption trip,
    Color primary,
  ) {
    final fmt = DateFormat('HH:mm');
    final out = <Widget>[];
    for (var i = 0; i < trip.legs.length; i++) {
      final leg = trip.legs[i];
      final rail = leg.mode == MenetrendTransportMode.rail;
      final cleanLegName = MenetrendService.sanitizeTransitLineName(
        rawShortName: leg.routeShortName,
        rawTripShortName: leg.tripShortName,
        mode: leg.mode,
      );
      final platform =
          (rail && leg.platformCode != null && leg.platformCode!.trim().isNotEmpty)
              ? ' • ${leg.platformCode!.trim()}'
              : '';
      out.add(
        _buildTimelineStep(
          context: context,
          icon: rail ? Icons.train_rounded : Icons.directions_bus_rounded,
          time: fmt.format(leg.departure),
          title: uwuLabel(HtmlSanitizer.clean(leg.fromName)),
          subtitle: uwuLabel(
            'Felszállás • $cleanLegName → ${HtmlSanitizer.clean(leg.toName)} (${fmt.format(leg.arrival)})$platform',
          ),
          accentColor: primary,
        ),
      );
      if (i < trip.legs.length - 1) {
        final wait =
            trip.legs[i + 1].departure.difference(leg.arrival).inMinutes;
        out.add(
          _buildTimelineStep(
            context: context,
            icon: Icons.transfer_within_a_station_rounded,
            time: fmt.format(leg.arrival),
            title: uwuLabel(HtmlSanitizer.clean(leg.toName)),
            subtitle: uwuLabel('Átszállás • ${wait}p várakozás'),
            accentColor: const Color(0xFFF59E0B),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildTimelineStep({
    required BuildContext context,
    required IconData icon,
    required String time,
    Color? timeColor,
    required String title,
    required String subtitle,
    required Color accentColor,
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = theme.colorScheme.onSurface;
    final secondaryText = onSurface.withValues(alpha: 0.58);
    final connectorColor =
        onSurface.withValues(alpha: isDark ? 0.14 : 0.12);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              if (!isLast)
                Container(
                  width: 1.5,
                  height: 22,
                  color: connectorColor,
                ),
            ],
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: timeColor ?? onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: secondaryText,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
