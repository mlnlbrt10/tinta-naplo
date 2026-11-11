import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/oled_theme.dart';
import '../services/menetrend_service.dart';
import '../services/token_storage_service.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';

/// Home wrapper for the MenetrendGO card. Handles unconfigured, loading and
/// "no route found" states; real data is rendered by [MenetrendHeroCard].
class MenetrendHomeCard extends StatelessWidget {
  final CommuteEvaluation? evaluation;
  final bool isLoading;
  final UserProfilePrefs prefs;
  final VoidCallback onOpenSettings;
  final VoidCallback onRetry;

  const MenetrendHomeCard({
    super.key,
    required this.evaluation,
    required this.isLoading,
    required this.prefs,
    required this.onOpenSettings,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final eval = evaluation;
    if (prefs.transitConfigured && eval != null) {
      return MenetrendHeroCard(evaluation: eval, prefs: prefs);
    }
    final scheme = Theme.of(context).colorScheme;
    final String text;
    final IconData icon;
    VoidCallback onTap = onOpenSettings;
    if (!prefs.transitConfigured) {
      text = 'Koppints a menetrendi beállításokhoz';
      icon = Icons.settings_rounded;
    } else if (isLoading) {
      text = 'Menetrend betöltése...';
      icon = Icons.directions_transit_rounded;
      onTap = () {};
    } else {
      text = 'Nem található járat. Koppints az újrapróbálkozáshoz.';
      icon = Icons.refresh_rounded;
      onTap = onRetry;
    }
    return TactileBounce(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: OledTheme.surfaceDark,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                uwu(text),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isLoading && prefs.transitConfigured)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
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
    final trip = evaluation.recommendedTrip;
    final primary = Theme.of(context).colorScheme.primary;
    final isDelayed = trip.delayMinutes > 0 || trip.isCancelled;
    final delayColor = trip.isCancelled
        ? const Color(0xFFEF5350)
        : (trip.delayMinutes >= 5
            ? const Color(0xFFFFB300)
            : const Color(0xFF66BB6A));

    final modeBadgeText = evaluation.isMorningMode
        ? 'REGGELI INGÁZÁS • ISKOLÁBA'
        : 'DÉLUTÁNI HAZAÚT • OTTHONBA';

    final countdownBadgeText = 'Indulásig: ${evaluation.minutesUntilDeparture} perc';
    final walkStartFormatted =
        DateFormat('HH:mm').format(evaluation.latestWalkStartTime);

    return TactileBounce(
      onTap: () => showMenetrendDetailsModal(
        context,
        evaluation: evaluation,
        prefs: prefs,
      ),
      child: Hero(
        tag: 'menetrend_hero_card',
        flightShuttleBuilder: (
          flightContext,
          animation,
          flightDirection,
          fromHeroContext,
          toHeroContext,
        ) {
          return Material(
            type: MaterialType.transparency,
            child: toHeroContext.widget,
          );
        },
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  OledTheme.surfaceDark,
                  primary.withValues(alpha: 0.14),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: primary.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _iconForMode(trip.mode),
                            size: 14,
                            color: primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            UwuHelper.apply(modeBadgeText),
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: delayColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: delayColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        trip.isCancelled
                            ? 'KIMARAD'
                            : (isDelayed
                                ? '+${trip.delayMinutes} perc'
                                : countdownBadgeText),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: delayColor,
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
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD54F),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (trip.legs.length <= 1) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          trip.routeShortName,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${trip.departureStation} → ${trip.arrivalStation}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            evaluation.isMorningMode
                                ? 'Séta indulás: $walkStartFormatted (${evaluation.effectiveWalkMinutes} p séta)${trip.platformCode != null ? " • ${trip.platformCode}" : ""}'
                                : '$countdownBadgeText${trip.platformCode != null ? " • ${trip.platformCode}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: OledTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          trip.effectiveDepartureTimeFormatted,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Érk: ${trip.effectiveArrivalTimeFormatted}',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: OledTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (trip.legs.length > 1) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        for (var i = 0; i < trip.legs.length; i++) ...[
                          Container(
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
                                  _iconForMode(trip.legs[i].mode),
                                  size: 13,
                                  color: primary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${i + 1}. szakasz: ${trip.legs[i].routeShortName} '
                                  '(${trip.legs[i].mode == MenetrendTransportMode.rail ? "vonat" : "busz"})',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (i < trip.legs.length - 1) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: OledTheme.textSecondary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFFFB300)
                                      .withValues(alpha: 0.38),
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
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 5),
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                size: 13,
                                color: OledTheme.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
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

Future<void> showMenetrendDetailsModal(
  BuildContext context, {
  required CommuteEvaluation evaluation,
  required UserProfilePrefs prefs,
}) async {
  await Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
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
    final primary = Theme.of(context).colorScheme.primary;
    final closeMode = widget.prefs.modalCloseMode;
    final trip = _selectedTrip;
    final walkLeave = trip.effectiveDeparture
        .subtract(Duration(minutes: trip.walkToStationMinutes));
    final schoolArrive = trip.effectiveArrival
        .add(Duration(minutes: trip.walkToDestinationMinutes));

    final curved = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                child: const ColoredBox(color: Colors.transparent),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
              child: FadeTransition(
                opacity: widget.animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
                  child: Hero(
                    tag: 'menetrend_hero_card',
                    child: Material(
                      color: const Color(0xF0121212),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: primary.withValues(alpha: 0.4),
                          width: 1.2,
                        ),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 460,
                          maxHeight: 640,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: primary.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      trip.mode == MenetrendTransportMode.rail
                                          ? Icons.train_rounded
                                          : Icons.directions_bus_filled_rounded,
                                      color: primary,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${trip.routeShortName} • ${trip.mode.displayName}',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          trip.routeLongName,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: OledTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (closeMode.showTopX)
                                    IconButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: OledTheme.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              // Alternative departures selector
                              if (widget.evaluation.alternatives.length > 1) ...[
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: widget.evaluation.alternatives
                                        .map((alt) {
                                      final isSel = alt.scheduledDeparture ==
                                              trip.scheduledDeparture &&
                                          alt.routeShortName ==
                                              trip.routeShortName;
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: ChoiceChip(
                                          label: Text(
                                            '${alt.routeShortName} (${alt.departureTimeFormatted})',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: isSel
                                                  ? Colors.black
                                                  : Colors.white,
                                            ),
                                          ),
                                          selected: isSel,
                                          selectedColor: primary,
                                          backgroundColor:
                                              OledTheme.surfaceElevated,
                                          onSelected: (_) {
                                            setState(() => _selectedTrip = alt);
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              // Delay & platform status banner
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: OledTheme.surfaceElevated,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: OledTheme.borderSubtle),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      trip.delayMinutes > 0
                                          ? Icons.warning_amber_rounded
                                          : Icons.verified_rounded,
                                      size: 18,
                                      color: trip.delayMinutes > 0
                                          ? const Color(0xFFFFB300)
                                          : const Color(0xFF66BB6A),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        trip.delayMinutes > 0
                                            ? 'Élő késés: +${trip.delayMinutes} perc • Indulás: ${trip.effectiveDepartureTimeFormatted}'
                                            : 'Menetrend szerint pontos (${trip.travelDurationMinutes} perc menetidő)',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (trip.platformCode != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: primary.withValues(alpha: 0.16),
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
                              _buildTimelineStep(
                                icon: Icons.directions_walk_rounded,
                                time: DateFormat('HH:mm').format(walkLeave),
                                title: 'Gyaloglás az állomásra',
                                subtitle:
                                    '${trip.walkToStationMinutes} perc séta (${widget.prefs.walkingSpeedKmh.toStringAsFixed(1)} km/h tempó)',
                                accentColor: OledTheme.textSecondary,
                              ),
                              if (trip.legs.length > 1)
                                ..._buildLegSteps(trip, primary)
                              else ...[
                              _buildTimelineStep(
                                icon: trip.mode == MenetrendTransportMode.rail
                                    ? Icons.train_rounded
                                    : Icons.directions_bus_rounded,
                                time: trip.effectiveDepartureTimeFormatted,
                                title: 'Felszállás: ${trip.departureStation}',
                                subtitle:
                                    '${trip.routeShortName}${trip.platformCode != null ? " • ${trip.platformCode}" : ""}',
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
                                      color: Colors.white
                                          .withValues(alpha: 0.03),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: OledTheme.borderSubtle,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Köztes megállók (${trip.intermediateStops.length}):',
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: OledTheme.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ...trip.intermediateStops.map(
                                          (stop) => Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.circle,
                                                  size: 6,
                                                  color:
                                                      OledTheme.textSecondary,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    stop.name,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                ),
                                                if (stop.platformCode != null)
                                                  Text(
                                                    '${stop.platformCode!} • ',
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                      color: OledTheme
                                                          .textSecondary,
                                                    ),
                                                  ),
                                                if (stop.timeLabel != null)
                                                  Text(
                                                    stop.timeLabel!,
                                                    style: const TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: OledTheme
                                                          .textSecondary,
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
                                icon: Icons.location_on_rounded,
                                time: trip.effectiveArrivalTimeFormatted,
                                title: 'Érkezés: ${trip.arrivalStation}',
                                subtitle: trip.arrivalPlatformCode ??
                                    (trip.mode == MenetrendTransportMode.rail
                                        ? 'Érkező vágány'
                                        : 'Megálló'),
                                accentColor: const Color(0xFF66BB6A),
                              ),
                              _buildTimelineStep(
                                icon: widget.evaluation.isMorningMode
                                    ? Icons.school_rounded
                                    : Icons.home_rounded,
                                time: DateFormat('HH:mm').format(schoolArrive),
                                title: widget.evaluation.isMorningMode
                                    ? 'Séta az iskoláig'
                                    : 'Séta hazáig',
                                subtitle:
                                    '${trip.walkToDestinationMinutes} perc séta a célállomásig',
                                accentColor: OledTheme.textSecondary,
                                isLast: true,
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      MenetrendService.openInMenetrendGo(
                                    trip: trip,
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
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
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
  List<Widget> _buildLegSteps(MenetrendTripOption trip, Color primary) {
    final fmt = DateFormat('HH:mm');
    final out = <Widget>[];
    for (var i = 0; i < trip.legs.length; i++) {
      final leg = trip.legs[i];
      final rail = leg.mode == MenetrendTransportMode.rail;
      out.add(
        _buildTimelineStep(
          icon: rail ? Icons.train_rounded : Icons.directions_bus_rounded,
          time: fmt.format(leg.departure),
          title: '${i + 1}. szakasz: ${leg.routeShortName} • ${leg.fromName}',
          subtitle:
              '→ ${leg.toName} (${fmt.format(leg.arrival)})'
              '${rail && leg.platformCode != null ? ' • ${leg.platformCode}' : ''}',
          accentColor: primary,
        ),
      );
      if (i < trip.legs.length - 1) {
        final wait = trip.legs[i + 1].departure.difference(leg.arrival).inMinutes;
        out.add(
          _buildTimelineStep(
            icon: Icons.transfer_within_a_station_rounded,
            time: fmt.format(leg.arrival),
            title: 'Átszállás: ${leg.toName}',
            subtitle: '$wait perc várakozás',
            accentColor: const Color(0xFFFFB300),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildTimelineStep({
    required IconData icon,
    required String time,
    required String title,
    required String subtitle,
    required Color accentColor,
    bool isLast = false,
  }) {
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
                  color: OledTheme.borderSubtle,
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
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
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
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: OledTheme.textSecondary,
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
