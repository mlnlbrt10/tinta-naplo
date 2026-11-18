import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../theme/oled_theme.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../utils/html_sanitizer.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'edge_fade_horizontal_scroll.dart';
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
          : const Size(42, 42));
  final toSize = (toRender != null && toRender.hasSize)
      ? toRender.size
      : (flightDirection == HeroFlightDirection.push
          ? const Size(42, 42)
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
    final activePrefs = AppProvidersScope.maybeOf(context)?.settings.prefs ?? prefs;
    final trip = evaluation.recommendedTrip;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final secondaryText =
        isDark ? OledTheme.textSecondary : onSurface.withValues(alpha: 0.72);
    final bool isDelayed = trip.delayMinutes > 0 && !trip.isCancelled;
    final Color statusColor;
    final String statusBadgeText;
    final IconData statusIcon;
    if (trip.isCancelled) {
      statusColor = const Color(0xFFEF4444);
      statusBadgeText = 'Kimarad';
      statusIcon = Icons.cancel_rounded;
    } else if (trip.delayMinutes >= 10) {
      statusColor = const Color(0xFFEF4444);
      statusBadgeText = '+${trip.delayMinutes} perc késés';
      statusIcon = Icons.schedule_rounded;
    } else if (trip.delayMinutes > 0) {
      statusColor = const Color(0xFFF59E0B);
      statusBadgeText = '+${trip.delayMinutes} perc késés';
      statusIcon = Icons.schedule_rounded;
    } else {
      statusColor = const Color(0xFF22C55E);
      statusBadgeText = 'Időben';
      statusIcon = Icons.check_circle_rounded;
    }

    final Color? arrivalTimeColor = trip.isCancelled
        ? const Color(0xFFEF4444)
        : (trip.delayMinutes >= 10
            ? const Color(0xFFEF4444)
            : (trip.delayMinutes > 0 ? const Color(0xFFF59E0B) : null));
    final displayedArrivalTime = isDelayed
        ? trip.effectiveDestinationArrivalTimeFormatted
        : trip.destinationArrivalTimeFormatted;

    final countdownBadgeText =
        'Indulásig: ${evaluation.minutesUntilDeparture} perc';
    final walkStartFormatted =
        DateFormat('HH:mm').format(evaluation.latestWalkStartTime);
    final safeLine = trip.safeRouteShortName;

    final walkSubtitle = evaluation.effectiveWalkMinutes > 0
        ? 'Séta ind.: $walkStartFormatted (${evaluation.effectiveWalkMinutes} p séta)'
            '${trip.walkToDestinationMinutes > 0 ? " • Cél séta: ${trip.walkToDestinationMinutes} p" : ""}'
            '${trip.platformCode != null ? " • ${trip.platformCode}" : ""}'
        : (trip.walkToDestinationMinutes > 0
            ? 'Cél séta: ${trip.walkToDestinationMinutes} perc${trip.platformCode != null ? " • ${trip.platformCode}" : ""}'
            : '$countdownBadgeText${trip.platformCode != null ? " • ${trip.platformCode}" : ""}');

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
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4.5,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                statusIcon,
                                size: 13.5,
                                color: statusColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                UwuHelper.apply(statusBadgeText),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TactileBounce(
                    pressedScale: 0.95,
                    onTap: () => MenetrendService.openInMenetrendGo(
                      trip: trip,
                      evaluation: evaluation,
                      prefs: activePrefs,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4.5,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: primary.withValues(alpha: 0.42),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'MenetrendGO',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 13.5,
                            color: primary,
                          ),
                        ],
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
                    trip.favoriteBadgeText,
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
                              HtmlSanitizer.clean(
                                '${trip.departureStation} → ${trip.arrivalStation}',
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
                                ),
                              ),
                              Text(
                                'Érk: $displayedArrivalTime',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: arrivalTimeColor != null
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: arrivalTimeColor ?? secondaryText,
                                ),
                              ),
                              if (isDelayed)
                                Text(
                                  'Becsült ind.: ${trip.effectiveDepartureTimeFormatted}',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
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
                          '${i + 1}. szakasz: $cleanLegName '
                          '(${leg.mode == MenetrendTransportMode.rail ? "vonat" : "busz"})',
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
                      'Átszállás ${trip.legs[i + 1].departure.difference(trip.legs[i].arrival).inMinutes} p',
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
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: 'Bezárás',
      barrierColor: resolveSoftBlurBarrierColor(
        context,
        prefs: prefs,
        solidDarkAlpha: 0.72,
        solidLightAlpha: 0.48,
      ),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 230),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return _MenetrendDetailsModalSheet(
          evaluation: evaluation,
          prefs: prefs,
          animation: animation,
        );
      },
    ),
  );
}

class _MenetrendDetailsModalSheet extends StatefulWidget {
  final CommuteEvaluation evaluation;
  final UserProfilePrefs prefs;
  final Animation<double> animation;

  const _MenetrendDetailsModalSheet({
    required this.evaluation,
    required this.prefs,
    required this.animation,
  });

  @override
  State<_MenetrendDetailsModalSheet> createState() =>
      _MenetrendDetailsModalSheetState();
}

class _MenetrendDetailsModalSheetState
    extends State<_MenetrendDetailsModalSheet> {
  late MenetrendTripOption _selectedTrip;

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
    final secondaryText =
        isDark ? OledTheme.textSecondary : onSurface.withValues(alpha: 0.72);
    final surfaceElevated =
        isDark ? OledTheme.surfaceElevated : theme.colorScheme.surfaceContainerHigh;
    final borderSubtle =
        isDark ? OledTheme.borderSubtle : onSurface.withValues(alpha: 0.14);

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
    final safeLongLine = MenetrendService.sanitizeRouteLongName(trip.routeLongName);
    final headerSubtitle =
        safeLongLine.isNotEmpty && safeLongLine != safeLine
            ? safeLongLine
            : 'MenetrendGO valós idejű útvonal';

    // Use OFFICIAL scheduled departure/arrival so delayed transit catches-ups
    // never leave the user late at the station, and show true destination arrival.
    final walkLeave = trip.scheduledDeparture
        .subtract(Duration(minutes: trip.walkToStationMinutes));
    final destinationArrive = trip.scheduledDestinationArrival;
    final fallbackDestLabel = activeEval.isMorningMode
        ? activePrefs.schoolAddress
        : activePrefs.homeAddress;
    final destLabel = (trip.destinationLabel != null &&
            trip.destinationLabel!.trim().isNotEmpty &&
            trip.destinationLabel!.trim() != trip.arrivalStation.trim())
        ? trip.destinationLabel!.trim()
        : (fallbackDestLabel.trim().isNotEmpty &&
                fallbackDestLabel.trim() != trip.arrivalStation.trim()
            ? fallbackDestLabel.trim()
            : '');

    final String statusBannerText;
    if (trip.isCancelled) {
      statusBannerText =
          'Járat kimarad • Menetrend szerinti ind.: ${trip.departureTimeFormatted}';
    } else if (trip.delayMinutes > 0) {
      statusBannerText =
          'Élő késés: +${trip.delayMinutes} perc • Becsült ind.: ${trip.effectiveDepartureTimeFormatted}';
    } else {
      statusBannerText =
          'Menetrend szerint pontos (${trip.travelDurationMinutes} perc menetidő)';
    }

    final fadeCurved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final scaleCurved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (ModalRoute.of(context)?.isCurrent ?? true) {
                  Navigator.of(context).pop();
                }
              },
              child: const ColoredBox(color: Colors.transparent),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                  scaleCurved,
                ),
                child: RepaintBoundary(
                  child: Material(
                    type: MaterialType.transparency,
                    child: LiquidGlassSurface(
                      prefs: activePrefs,
                      highContrastExpanded: true,
                      solidColor: resolveLiquidGlassEnabled(activePrefs)
                          ? (isDark
                              ? const Color(0xF0121212)
                              : theme.colorScheme.surface.withValues(alpha: 0.96))
                          : null,
                      borderRadius: BorderRadius.circular(24),
                      contentOpacityAnimation: fadeCurved,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 460,
                          maxHeight: 640,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 18, 0, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  children: [
                                    Hero(
                                      tag: 'menetrend_hero_card',
                                      flightShuttleBuilder:
                                          _buildMenetrendHeroShuttle,
                                      child: Material(
                                        type: MaterialType.transparency,
                                        child: Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: primary.withValues(
                                              alpha: 0.16,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(14),
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
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$safeLine • ${trip.mode.displayName}',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                              color: onSurface,
                                            ),
                                          ),
                                          Text(
                                            headerSubtitle,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: secondaryText,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (closeMode.showTopX)
                                      IconButton(
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: Icon(
                                          Icons.close_rounded,
                                          color: secondaryText,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Alternative departures selector
                              if (visibleAlternatives.length > 1) ...[
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
                                        ),
                                      ),
                                      selected: isSel,
                                      selectedColor: primary,
                                      backgroundColor: surfaceElevated,
                                      onSelected: (_) {
                                        setState(() => _selectedTrip = alt);
                                      },
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 12),
                              ],
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Delay & platform status banner
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: surfaceElevated,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: borderSubtle),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            trip.isCancelled
                                                ? Icons.cancel_rounded
                                                : (trip.delayMinutes > 0
                                                    ? Icons
                                                        .warning_amber_rounded
                                                    : Icons.verified_rounded),
                                            size: 18,
                                            color: trip.isCancelled
                                                ? const Color(0xFFEF5350)
                                                : (trip.delayMinutes > 0
                                                    ? const Color(0xFFFFB300)
                                                    : const Color(0xFF66BB6A)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              statusBannerText,
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: onSurface,
                                              ),
                                            ),
                                          ),
                                          if (trip.platformCode != null)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 3,
                                              ),
                                              decoration: BoxDecoration(
                                                color: primary.withValues(
                                                  alpha: 0.16,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                trip.platformCode!,
                                                style: TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: primary,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // Step-by-step Trip Breakdown
                                    if (trip.walkToStationMinutes > 0)
                                      _buildTimelineStep(
                                        context: context,
                                        icon: Icons.directions_walk_rounded,
                                        time:
                                            DateFormat('HH:mm').format(walkLeave),
                                        title: 'Gyaloglás az állomásra',
                                        subtitle:
                                            '${trip.walkToStationMinutes} perc séta (${MenetrendService.walkingSpeedLabel(activePrefs.walkingSpeedKmh)})',
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
                                        title:
                                            'Felszállás: ${HtmlSanitizer.clean(trip.departureStation)}',
                                        subtitle:
                                            'Menetrend szerinti indulás: ${trip.departureTimeFormatted} • $safeLine${trip.platformCode != null ? " • ${trip.platformCode}" : ""}',
                                        accentColor: primary,
                                      ),
                                      if (trip.intermediateStops.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 22,
                                            top: 4,
                                            bottom: 8,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: onSurface.withValues(
                                                alpha: isDark ? 0.03 : 0.04,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border:
                                                  Border.all(color: borderSubtle),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Köztes megállók (${trip.intermediateStops.length}):',
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: secondaryText,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                ...trip.intermediateStops.map(
                                                  (stop) => Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      vertical: 2,
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons.circle,
                                                          size: 6,
                                                          color: secondaryText,
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            HtmlSanitizer.clean(
                                                              stop.name,
                                                            ),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: onSurface,
                                                            ),
                                                          ),
                                                        ),
                                                        if (stop.platformCode !=
                                                            null)
                                                          Text(
                                                            '${stop.platformCode!} • ',
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              color:
                                                                  secondaryText,
                                                            ),
                                                          ),
                                                        if (stop.timeLabel !=
                                                            null)
                                                          Text(
                                                            stop.timeLabel!,
                                                            style: TextStyle(
                                                              fontSize: 11.5,
                                                              fontWeight:
                                                                  FontWeight.w700,
                                                              color:
                                                                  secondaryText,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                    _buildTimelineStep(
                                      context: context,
                                      icon: Icons.location_on_rounded,
                                      time: (trip.delayMinutes > 0 &&
                                              !trip.isCancelled)
                                          ? trip.effectiveArrivalTimeFormatted
                                          : trip.arrivalTimeFormatted,
                                      timeColor: trip.isCancelled
                                          ? const Color(0xFFEF4444)
                                          : (trip.delayMinutes >= 10
                                              ? const Color(0xFFEF4444)
                                              : (trip.delayMinutes > 0
                                                  ? const Color(0xFFF59E0B)
                                                  : null)),
                                      title:
                                          'Leszállás: ${HtmlSanitizer.clean(trip.arrivalStation)}',
                                      subtitle: trip.arrivalPlatformCode ??
                                          (trip.mode ==
                                                  MenetrendTransportMode.rail
                                              ? 'Érkező vágány • jármű érkezése: ${(trip.delayMinutes > 0 && !trip.isCancelled) ? trip.effectiveArrivalTimeFormatted : trip.arrivalTimeFormatted}'
                                              : 'Leszálló megálló • jármű érkezése: ${(trip.delayMinutes > 0 && !trip.isCancelled) ? trip.effectiveArrivalTimeFormatted : trip.arrivalTimeFormatted}'),
                                      accentColor: const Color(0xFF66BB6A),
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
                                        title: activeEval.isMorningMode
                                            ? 'Séta az iskoláig'
                                            : 'Séta hazáig',
                                        subtitle:
                                            '${trip.walkToDestinationMinutes} perc séta${destLabel.isNotEmpty ? " • $destLabel" : " a célállomásig"}',
                                        accentColor: secondaryText,
                                        isLast: true,
                                      ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            MenetrendService.openInMenetrendGo(
                                          trip: trip,
                                          evaluation: activeEval,
                                          prefs: activePrefs,
                                        ),
                                        icon: const Icon(
                                          Icons.open_in_new_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Részletek a MenetrendGO-ban',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: primary,
                                          foregroundColor:
                                              theme.colorScheme.onPrimary,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 13,
                                          ),
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
                                          child: const Text('Bezárás'),
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
                  ),
                ),
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
      out.add(
        _buildTimelineStep(
          context: context,
          icon: rail ? Icons.train_rounded : Icons.directions_bus_rounded,
          time: fmt.format(leg.departure),
          title:
              '${i + 1}. szakasz: $cleanLegName • ${HtmlSanitizer.clean(leg.fromName)}',
          subtitle:
              'Menetrend szerinti ind.: ${fmt.format(leg.departure)} → ${HtmlSanitizer.clean(leg.toName)} (${fmt.format(leg.arrival)})'
              '${rail && leg.platformCode != null ? ' • ${leg.platformCode}' : ''}',
          accentColor: primary,
        ),
      );
      if (i < trip.legs.length - 1) {
        final wait = trip.legs[i + 1].departure.difference(leg.arrival).inMinutes;
        out.add(
          _buildTimelineStep(
            context: context,
            icon: Icons.transfer_within_a_station_rounded,
            time: fmt.format(leg.arrival),
            title: 'Átszállás: ${HtmlSanitizer.clean(leg.toName)}',
            subtitle: '$wait perc várakozás',
            accentColor: const Color(0xFFFFB300),
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
    final secondaryText =
        isDark ? OledTheme.textSecondary : onSurface.withValues(alpha: 0.72);
    final borderSubtle =
        isDark ? OledTheme.borderSubtle : onSurface.withValues(alpha: 0.16);

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
                  color: accentColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 22,
                  color: borderSubtle,
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
                      fontSize: 11.5,
                      color: secondaryText,
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
