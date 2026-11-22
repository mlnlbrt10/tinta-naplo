import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/uwu_helper.dart';
import 'animation_helpers.dart';
import 'glass_card.dart';

/// Linear bounding-rect interpolation for Hero badge and avatar transitions,
/// avoiding Material's upward parabolic [MaterialRectArcTween] swing.
RectTween createLinearHeroRectTween(Rect? begin, Rect? end) =>
    RectTween(begin: begin, end: end);

/// Computes damped upward rubber-band offset (negative pixels) when dragging
/// a floating sheet upward past its resting position.
double computeSheetUpwardRubberBand(
  double rawNegativeDrag, {
  double maxUpwardPull = 22.0,
}) {
  if (rawNegativeDrag >= 0.0) return 0.0;
  final absUp = -rawNegativeDrag;
  return -(maxUpwardPull * (absUp / (absUp + 85.0)));
}

/// Computes subtle vertical stretch scale (`1.0 -> 1.03`) anchored at the
/// bottom during an upward over-drag of a floating sheet.
double computeSheetUpwardStretchScale(
  double visualOffset, {
  double maxUpwardPull = 22.0,
  double maxExtraScale = 0.03,
}) {
  if (visualOffset >= 0.0) return 1.0;
  final progress = (-visualOffset / maxUpwardPull).clamp(0.0, 1.0);
  return 1.0 + progress * maxExtraScale;
}

class _FloatingSheetScrollBehavior extends ScrollBehavior {
  const _FloatingSheetScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(
      parent: AlwaysScrollableScrollPhysics(),
    );
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Custom transparent [PageRoute] for all floating detail sheets.
///
/// Extends [PageRoute] (rather than [PopupRoute]) so Flutter's [HeroController]
/// runs smooth boomerang badge Hero transitions between list cards and the
/// floating popup header, paired with spring/impulse entry, boomerang reverse,
/// and interactive swipe-down-to-dismiss velocity physics.
class FloatingGlassSheetRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final Color _barrierColor;
  final bool _barrierDismissible;
  final String? _barrierLabel;
  final bool _useSafeArea;

  FloatingGlassSheetRoute({
    required this.builder,
    Color barrierColor = const Color(0x8A000000),
    bool barrierDismissible = true,
    String? barrierLabel,
    bool useSafeArea = true,
    super.settings,
  })  : _barrierColor = barrierColor,
        _barrierDismissible = barrierDismissible,
        _barrierLabel = barrierLabel,
        _useSafeArea = useSafeArea;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  Color? get barrierColor => _barrierColor;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget inner = _FloatingSheetDragDismissWrapper(
      onDismiss: () {
        if (isCurrent) {
          navigator?.maybePop();
        }
      },
      child: Material(
        type: MaterialType.transparency,
        child: builder(context),
      ),
    );
    // Keep Align inside buildPage so ModalRoute._subtreeKey spans the full
    // viewport and Hero measures the true bottom-sheet badge coordinates.
    Widget page = Align(
      alignment: Alignment.bottomCenter,
      child: inner,
    );
    if (_useSafeArea) {
      page = SafeArea(
        left: true,
        top: true,
        right: true,
        bottom: false,
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: page,
        ),
      );
    }
    return page;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final raw = animation.value.clamp(0.0, 1.0);
    final isReverse = animation.status == AnimationStatus.reverse;
    final curved = isReverse
        ? (1.0 - Curves.easeInCubic.transform(1.0 - raw))
        : Curves.easeOutCubic.transform(raw);
    final scale = 0.95 + 0.05 * curved;
    final dy = (1.0 - curved) * 28.0;
    final opacity = (isReverse
            ? Curves.easeIn.transform(raw)
            : Curves.easeOut.transform((raw * 1.6).clamp(0.0, 1.0)))
        .clamp(0.0, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
  }
}

class _FloatingSheetDragDismissWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;

  const _FloatingSheetDragDismissWrapper({
    required this.child,
    required this.onDismiss,
  });

  @override
  State<_FloatingSheetDragDismissWrapper> createState() =>
      _FloatingSheetDragDismissWrapperState();
}

class _FloatingSheetDragDismissWrapperState
    extends State<_FloatingSheetDragDismissWrapper>
    with SingleTickerProviderStateMixin {
  static const double _dismissDistanceThreshold = 100.0;
  static const double _dismissVelocityThreshold = 500.0;

  late final AnimationController _springBackCtrl;
  double _rawDragOffset = 0.0;
  double _visualOffset = 0.0;
  bool _dismissTriggered = false;
  bool _gestureDetectorOwnsDrag = false;
  bool _scrollDragActive = false;
  int? _activePointer;
  VelocityTracker? _velocityTracker;

  @override
  void initState() {
    super.initState();
    _springBackCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {
            _visualOffset = _springBackCtrl.value.clamp(-28.0, 600.0);
          });
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (mounted && _visualOffset.abs() < 0.05) {
            setState(() {
              _visualOffset = 0.0;
              _rawDragOffset = 0.0;
            });
          }
        }
      });
  }

  @override
  void dispose() {
    _springBackCtrl.dispose();
    super.dispose();
  }

  void _applyDragDelta(double deltaDy) {
    if (_dismissTriggered || deltaDy == 0.0) return;
    if (_springBackCtrl.isAnimating) {
      _springBackCtrl.stop();
    }
    _rawDragOffset = (_rawDragOffset + deltaDy).clamp(-450.0, 480.0);
    final nextVisual = _rawDragOffset >= 0.0
        ? _rawDragOffset.clamp(0.0, 480.0)
        : computeSheetUpwardRubberBand(_rawDragOffset);
    if ((nextVisual - _visualOffset).abs() > 0.1) {
      setState(() => _visualOffset = nextVisual);
    }
  }

  void _finishDrag(double velocityY) {
    if (_dismissTriggered) return;
    if (_rawDragOffset >= 0.0 &&
        (_visualOffset > _dismissDistanceThreshold ||
            (velocityY > _dismissVelocityThreshold && _visualOffset > 0.0))) {
      _dismissTriggered = true;
      HapticFeedback.selectionClick();
      widget.onDismiss();
      return;
    }
    _rawDragOffset = 0.0;
    if (_visualOffset.abs() > 0.1) {
      const spring = SpringDescription(
        mass: 1.0,
        stiffness: 420.0,
        damping: 28.0,
      );
      _springBackCtrl.animateWith(
        SpringSimulation(
          spring,
          _visualOffset,
          0.0,
          (velocityY / 1000.0).clamp(-3.0, 3.0),
        ),
      );
    } else if (_visualOffset != 0.0) {
      setState(() => _visualOffset = 0.0);
    }
  }

  void _onGestureDragStart(DragStartDetails details) {
    if (_dismissTriggered) return;
    _gestureDetectorOwnsDrag = true;
    _scrollDragActive = false;
    if (_springBackCtrl.isAnimating) {
      _springBackCtrl.stop();
    }
  }

  void _onGestureDragUpdate(DragUpdateDetails details) {
    _applyDragDelta(details.delta.dy);
  }

  void _onGestureDragEnd(DragEndDetails details) {
    _gestureDetectorOwnsDrag = false;
    _finishDrag(details.velocity.pixelsPerSecond.dy);
  }

  void _onGestureDragCancel() {
    _gestureDetectorOwnsDrag = false;
    if (!_dismissTriggered && _visualOffset.abs() > 0.1) {
      _finishDrag(0.0);
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_dismissTriggered) return;
    if (_activePointer == null) {
      _activePointer = event.pointer;
      _velocityTracker = VelocityTracker.withKind(event.kind);
      _scrollDragActive = false;
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _activePointer) {
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (event.pointer != _activePointer) return;
    final velocityY = _velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0.0;
    _activePointer = null;
    _velocityTracker = null;
    if (!_gestureDetectorOwnsDrag &&
        (_scrollDragActive || _visualOffset.abs() > 0.1)) {
      _scrollDragActive = false;
      _finishDrag(velocityY);
    } else {
      _scrollDragActive = false;
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_dismissTriggered ||
        _gestureDetectorOwnsDrag ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      if (notification.overscroll != 0.0) {
        _scrollDragActive = true;
        _applyDragDelta(-notification.overscroll);
      }
      return false;
    }

    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0.0;
      if (_scrollDragActive) {
        if (_rawDragOffset > 0.0 && delta > 0.0) {
          _applyDragDelta(-delta);
        } else if (_rawDragOffset < 0.0 && delta < 0.0) {
          _applyDragDelta(-delta);
        }
      } else {
        // Fallback when an inner scrollable uses BouncingScrollPhysics.
        if (notification.metrics.pixels < 0.0 && delta < 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta);
        } else if (notification.metrics.pixels >
                notification.metrics.maxScrollExtent &&
            delta > 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta);
        }
      }
      return false;
    }

    if (notification is ScrollEndNotification &&
        _scrollDragActive &&
        _activePointer == null) {
      _scrollDragActive = false;
      if (_visualOffset.abs() > 0.1) {
        _finishDrag(0.0);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveOffset = _visualOffset.abs() < 0.01 ? 0.0 : _visualOffset;
    final double translateY;
    final double scaleX;
    final double scaleY;

    if (effectiveOffset >= 0.0) {
      translateY = effectiveOffset;
      final uniformScale =
          (1.0 - (effectiveOffset / 1800.0)).clamp(0.92, 1.0);
      scaleX = uniformScale;
      scaleY = uniformScale;
    } else {
      translateY = effectiveOffset * 0.45;
      scaleX = 1.0;
      scaleY = computeSheetUpwardStretchScale(effectiveOffset);
    }

    Widget content = ScrollConfiguration(
      behavior: const _FloatingSheetScrollBehavior(),
      child: widget.child,
    );

    if (translateY != 0.0 || scaleX != 1.0 || scaleY != 1.0) {
      content = Transform.translate(
        offset: Offset(0, translateY),
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
          child: content,
        ),
      );
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUpOrCancel,
      onPointerCancel: _onPointerUpOrCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _onGestureDragStart,
          onVerticalDragUpdate: _onGestureDragUpdate,
          onVerticalDragEnd: _onGestureDragEnd,
          onVerticalDragCancel: _onGestureDragCancel,
          child: content,
        ),
      ),
    );
  }
}

/// Pushes a floating glass sheet using [FloatingGlassSheetRoute] with custom
/// spring physics, swipe-down dismiss, and full Hero badge boomerang support.
Future<T?> showFloatingGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
  bool useSafeArea = true,
  bool useRootNavigator = false,
  UserProfilePrefs? prefs,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    FloatingGlassSheetRoute<T>(
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor ??
          resolveSoftBlurBarrierColor(
            context,
            prefs: prefs,
            solidDarkAlpha: 0.54,
            solidLightAlpha: 0.42,
          ),
      useSafeArea: useSafeArea,
    ),
  );
}

/// Reusable Hero flight shuttle providing an elastic boomerang arc scale as
/// grade and lesson badges fly between list tiles and floating modal headers.
Widget buildBoomerangBadgeHeroShuttle(
  BuildContext flightContext,
  Animation<double> flightAnimation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  return AnimatedBuilder(
    animation: flightAnimation,
    builder: (context, child) {
      final t = flightAnimation.value.clamp(0.0, 1.0);
      final bounce = 1.0 + 0.08 * math.sin(math.pi * t);
      return Transform.scale(
        scale: bounce,
        child: child,
      );
    },
    child: Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: DefaultTextStyle.of(toHeroContext).style,
        child: toHeroContext.widget,
      ),
    ),
  );
}

/// Performance-safe modal bottom sheet container.
///
/// When Liquid Glass mode is enabled, renders a genuinely translucent surface
/// (`0.76 - 0.80` alpha) with a subtle `1px` edge highlight and a single flat
/// `BackdropFilter(sigmaX: 14, sigmaY: 14)` wrapped in [ClipRRect] and
/// [RepaintBoundary] so scrolling/sheet animations stay smooth at 60/120fps.
/// When Liquid Glass mode is disabled, renders a solid opaque Material 3
/// surface with zero [BackdropFilter] widgets.
class FrostedBottomSheetSurface extends StatelessWidget {
  final Widget child;
  final UserProfilePrefs? prefs;
  final double topRadius;
  final double blurSigma;
  final EdgeInsetsGeometry? padding;
  final bool showDragHandle;
  final bool includeSafeAreaBottom;

  const FrostedBottomSheetSurface({
    super.key,
    required this.child,
    this.prefs,
    this.topRadius = 26.0,
    this.blurSigma = 14.0,
    this.padding,
    this.showDragHandle = true,
    this.includeSafeAreaBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrefs =
        prefs ?? AppProvidersScope.maybeOf(context)?.settings.prefs;
    final liquidGlass = resolveLiquidGlassEnabled(effectivePrefs);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(topRadius);

    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDragHandle) ...[
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Flexible(
          fit: FlexFit.loose,
          child: child,
        ),
      ],
    );

    final Widget card;
    if (!liquidGlass) {
      final fill = isDark ? scheme.surfaceContainerHigh : Colors.white;
      final solidMaterial = Material(
        color: fill,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(
              color: isDark
                  ? scheme.outlineVariant.withValues(alpha: 0.28)
                  : Colors.black.withValues(alpha: 0.07),
              width: 1.0,
            ),
          ),
          child: inner,
        ),
      );
      card = !isDark
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: solidMaterial,
            )
          : solidMaterial;
    } else {
      final translucentFill = isDark
          ? (scheme.surface == Colors.black
              ? const Color(0xFF141820).withValues(alpha: 0.76)
              : scheme.surface.withValues(alpha: 0.76))
          : Colors.white.withValues(alpha: 0.84);

      final glassCard = ClipRRect(
        borderRadius: radius,
        child: RepaintBoundary(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: translucentFill,
                  borderRadius: radius,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: inner,
              ),
            ),
          ),
        ),
      );
      card = !isDark
          ? DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: glassCard,
            )
          : glassCard;
    }

    final Widget result = includeSafeAreaBottom
        ? SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: card,
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: card,
          );

    final route = ModalRoute.of(context);
    if (route is FloatingGlassSheetRoute) {
      return result;
    }
    final routeAnim = route?.animation;
    if (routeAnim == null) {
      return result;
    }

    return AnimatedBuilder(
      animation: routeAnim,
      builder: (context, child) {
        final raw = routeAnim.value.clamp(0.0, 1.0);
        if (raw >= 0.9999 && routeAnim.status == AnimationStatus.completed) {
          return child!;
        }
        final isReverse = routeAnim.status == AnimationStatus.reverse;
        final curved = isReverse
            ? (1.0 - Curves.easeInCubic.transform(1.0 - raw))
            : Curves.easeOutCubic.transform(raw);
        final scale = 0.95 + 0.05 * curved;
        final dy = (1.0 - curved) * 24.0;
        final opacity = (isReverse
                ? Curves.easeIn.transform(raw)
                : Curves.easeOut.transform((raw * 1.45).clamp(0.0, 1.0)))
            .clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
        );
      },
      child: result,
    );
  }
}

/// Displays a sleek bottom-anchored frosted glass (or solid Material 3)
/// inspection modal sheet with a unified circular translucent header badge,
/// single-column hairline-divided key-value rows, clean readable body text,
/// and [heroTag] support.
Future<void> showFrostedModal({
  required BuildContext context,
  String categoryLabel = '',
  required IconData categoryIcon,
  required Color accentColor,
  Color? badgeColor,
  Color? badgeTextColor,
  required String title,
  String? subtitle,
  String? subtitleTimeSpan,
  String? badgeText,
  BoxShape badgeShape = BoxShape.circle,
  String? heroTag,
  required List<FrostedDetailRow> rows,
  String? topicTitle,
  String? topicBody,
  Widget? extraBottomSection,
  ModalCloseButtonMode? closeMode,
  UserProfilePrefs? prefs,
}) {
  HapticFeedback.lightImpact();
  final effectiveCloseMode =
      closeMode ?? UserProfilePrefs.activeModalCloseMode;
  final resolvedSubtitle = (subtitle != null && subtitle.trim().isNotEmpty)
      ? subtitle.trim()
      : ((subtitleTimeSpan != null && subtitleTimeSpan.trim().isNotEmpty)
          ? subtitleTimeSpan.trim()
          : null);
  final visibleRows =
      rows.where((r) => r.value.trim().isNotEmpty).toList(growable: false);

  return showFloatingGlassSheet<void>(
    context: context,
    prefs: prefs,
    barrierColor: resolveSoftBlurBarrierColor(
      context,
      prefs: prefs,
      solidDarkAlpha: 0.54,
      solidLightAlpha: 0.42,
    ),
    builder: (sheetContext) {
      final activePrefs =
          prefs ?? AppProvidersScope.maybeOf(sheetContext)?.settings.prefs;
      final uwuEnabled = activePrefs?.uwuModeEnabled;
      final theme = Theme.of(sheetContext);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final hairlineColor =
          scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.07);

      final resolvedAccent = OledTheme.semanticForeground(
        accentColor,
        theme.brightness,
      );
      final effectiveBadgeBg = badgeColor ??
          OledTheme.semanticBadgeBg(accentColor, theme.brightness);
      final effectiveBadgeFg = badgeTextColor ?? resolvedAccent;
      final effectiveBadgeBorder =
          OledTheme.semanticBadgeBorder(effectiveBadgeFg, theme.brightness);

      Widget badgeOrIcon;
      if (badgeText != null && badgeText.trim().isNotEmpty) {
        final cleanBadge = badgeText.trim();
        final fontSize = cleanBadge.length >= 3 ? 14.5 : 20.5;
        badgeOrIcon = Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: effectiveBadgeBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: effectiveBadgeBorder,
              width: 1.2,
            ),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(
                  left: cleanBadge.endsWith('.') ? 1.5 : 0.0,
                ),
                child: Text(
                  cleanBadge,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(
                    color: effectiveBadgeFg,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        badgeOrIcon = Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: effectiveBadgeBg,
            shape: BoxShape.circle,
            border: Border.all(
              color: effectiveBadgeBorder,
              width: 1.2,
            ),
          ),
          child: Icon(
            categoryIcon,
            color: effectiveBadgeFg,
            size: 22,
          ),
        );
      }

      if (heroTag != null) {
        badgeOrIcon = Hero(
          tag: heroTag,
          createRectTween: createLinearHeroRectTween,
          flightShuttleBuilder: buildBoomerangBadgeHeroShuttle,
          child: badgeOrIcon,
        );
      }

      final hasTopicBody = topicBody != null && topicBody.trim().isNotEmpty;

      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.86,
          ),
          child: FrostedBottomSheetSurface(
            prefs: prefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      badgeOrIcon,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              uwuLabel(title, enabled: uwuEnabled),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 18.5,
                                height: 1.22,
                                letterSpacing: -0.3,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            if (resolvedSubtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                uwuLabel(resolvedSubtitle, enabled: uwuEnabled),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 13,
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.60),
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (effectiveCloseMode.showTopX) ...[
                        const SizedBox(width: 8),
                        TactileBounce(
                          onTap: () => Navigator.of(sheetContext).pop(),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.onSurface.withValues(
                                alpha: isDark ? 0.08 : 0.06,
                              ),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: scheme.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (visibleRows.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildKeyValueList(
                      theme: theme,
                      scheme: scheme,
                      rows: visibleRows,
                      hairlineColor: hairlineColor,
                      uwuEnabled: uwuEnabled,
                    ),
                  ],
                  if (hasTopicBody) ...[
                    if (visibleRows.isEmpty) ...[
                      const SizedBox(height: 16),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: hairlineColor,
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (topicTitle != null &&
                        topicTitle.trim().isNotEmpty) ...[
                      Text(
                        uwuLabel(topicTitle.trim(), enabled: uwuEnabled),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.56),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      uwu(topicBody.trim(), enabled: uwuEnabled),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 14,
                        color: scheme.onSurface.withValues(alpha: 0.90),
                        height: 1.48,
                      ),
                    ),
                  ],
                  if (extraBottomSection != null) ...[
                    if (visibleRows.isNotEmpty || hasTopicBody)
                      const SizedBox(height: 14)
                    else
                      const SizedBox(height: 16),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: hairlineColor,
                    ),
                    const SizedBox(height: 12),
                    extraBottomSection,
                  ],
                  if (effectiveCloseMode.showBottomButton) ...[
                    const SizedBox(height: 18),
                    TactileBounce(
                      onTap: () => Navigator.of(sheetContext).pop(),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          uwuLabel('Bezárás', enabled: uwuEnabled),
                          style: TextStyle(
                            color: OledTheme.contrastTextFor(
                              accentColor,
                            ),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class FrostedDetailRow {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const FrostedDetailRow({
    this.icon = Icons.circle,
    required this.label,
    required this.value,
    this.valueColor,
  });
}

Widget _buildKeyValueList({
  required ThemeData theme,
  required ColorScheme scheme,
  required List<FrostedDetailRow> rows,
  required Color hairlineColor,
  bool? uwuEnabled,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Divider(height: 1, thickness: 1, color: hairlineColor),
      for (int i = 0; i < rows.length; i++) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uwuLabel(rows[i].label, enabled: uwuEnabled),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurface.withValues(alpha: 0.56),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  uwuLabel(rows[i].value, enabled: uwuEnabled),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: rows[i].valueColor ?? scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: hairlineColor),
      ],
    ],
  );
}

/// Opens the redesigned, minimal inspection modal for a [Grade].
Future<void> showGradeInspectionModal(
  BuildContext context,
  Grade grade, {
  UserProfilePrefs? prefs,
  String? heroTag,
  String? impactDeltaText,
  Color? impactDeltaColor,
}) {
  final scopeSettings =
      context.getInheritedWidgetOfExactType<AppProvidersScope>()?.settings;
  final effectivePrefs = prefs ?? scopeSettings?.prefs;
  final isMinimalist = effectivePrefs?.minimalistModeEnabled ??
      UserProfilePrefs.activeMinimalistModeEnabled;
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final color = OledTheme.gradeColor(grade.numericValue, effectivePrefs);
  final badge = grade.numericValue?.toString() ??
      grade.shortStrValue ??
      (grade.strValue.isNotEmpty ? grade.strValue.substring(0, 1) : '?');
  final weightStr =
      (grade.weightPercentage != null && grade.weightPercentage! > 0)
          ? '${grade.weightPercentage}%'
          : '100%';

  final subjectDisplay = effectivePrefs != null
      ? effectivePrefs.resolveSubjectName(grade.subject.name, grade.subject.uid)
      : grade.subject.name;
  final teacherDisplay = effectivePrefs != null
      ? effectivePrefs.resolveTeacherName(grade.teacher).trim()
      : grade.teacher.trim();

  final cleanTopic = OledTheme.capitalizeFirst(grade.topic ?? '');
  final cleanMode = OledTheme.capitalizeFirst(grade.mode?.description ?? '');
  final cleanType = OledTheme.capitalizeFirst(
    grade.type.description.replaceFirst(
      RegExp(r'^Évközi jegy/értékelés\s*[•\-]\s*', caseSensitive: false),
      '',
    ),
  );
  final resolvedMode = cleanMode.isNotEmpty
      ? cleanMode
      : (cleanType.toLowerCase().contains('évközi') ? '' : cleanType);

  final cleanGradeWord = OledTheme.capitalizeFirst(
    grade.strValue.replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '').trim(),
  );

  final title = cleanTopic.isNotEmpty
      ? cleanTopic
      : (resolvedMode.isNotEmpty
          ? resolvedMode
          : (cleanGradeWord.isNotEmpty ? cleanGradeWord : subjectDisplay));

  final gradeAndWeight = cleanGradeWord.isNotEmpty
      ? '$cleanGradeWord ($weightStr)'
      : weightStr;
  final subtitle = [
    if (subjectDisplay.trim().isNotEmpty && subjectDisplay != title)
      subjectDisplay.trim(),
    gradeAndWeight,
  ].join(' • ');

  return showFrostedModal(
    context: context,
    categoryIcon: Icons.star_rounded,
    accentColor: color,
    title: title,
    subtitle: subtitle,
    badgeText: badge,
    badgeShape: BoxShape.circle,
    heroTag: heroTag,
    closeMode: effectivePrefs?.modalCloseMode,
    prefs: effectivePrefs,
    rows: [
      if (resolvedMode.isNotEmpty && resolvedMode != title)
        FrostedDetailRow(
          label: 'Típus',
          value: resolvedMode,
        ),
      if (!isMinimalist &&
          impactDeltaText != null &&
          impactDeltaText.trim().isNotEmpty)
        FrostedDetailRow(
          label: 'Átlagra hatás',
          value: impactDeltaText.trim(),
          valueColor: impactDeltaColor,
        ),
      if (teacherDisplay.isNotEmpty)
        FrostedDetailRow(
          label: 'Tanár',
          value: teacherDisplay,
        ),
      FrostedDetailRow(
        label: 'Dátum',
        value: dtFormat.format(grade.recordedAt.toLocal()),
      ),
    ],
  );
}

/// Opens the redesigned, minimal inspection modal for a [Homework] item.
Future<void> showHomeworkInspectionModal(
  BuildContext context,
  Homework homework, {
  UserProfilePrefs? prefs,
  String? heroTag,
  bool? isCompletedOverride,
}) {
  final scopeSettings =
      context.getInheritedWidgetOfExactType<AppProvidersScope>()?.settings;
  final effectivePrefs = prefs ?? scopeSettings?.prefs;
  final isCompleted = isCompletedOverride ??
      (scopeSettings?.isHomeworkCompleted(homework) ?? homework.isDone);
  final dtFormat = DateFormat('yyyy. MM. dd. HH:mm');
  final cleanedDesc = Homework.stripHtmlTags(homework.description).trim();

  final rawSubject = homework.subject.name.isNotEmpty
      ? homework.subject.name
      : homework.subjectName;
  final subjectDisplay = effectivePrefs != null
      ? effectivePrefs.resolveSubjectName(rawSubject, homework.subject.uid)
      : rawSubject;
  final teacherDisplay = effectivePrefs != null
      ? effectivePrefs.resolveTeacherName(homework.teacherName).trim()
      : homework.teacherName.trim();

  const hwAccent = Color(0xFF00BFA5);

  return showFrostedModal(
    context: context,
    categoryIcon: Icons.menu_book_rounded,
    accentColor: hwAccent,
    title: subjectDisplay,
    subtitle: isCompleted ? 'Házi feladat • Kész' : 'Házi feladat',
    heroTag: heroTag,
    closeMode: effectivePrefs?.modalCloseMode,
    prefs: effectivePrefs,
    rows: [
      FrostedDetailRow(
        label: 'Határidő',
        value: dtFormat.format(homework.dueDate.toLocal()),
      ),
      FrostedDetailRow(
        label: 'Státusz',
        value: isCompleted ? 'Megoldva (Kész)' : 'Aktív',
        valueColor: isCompleted ? hwAccent : null,
      ),
      if (teacherDisplay.isNotEmpty)
        FrostedDetailRow(
          label: 'Tanár',
          value: teacherDisplay,
        ),
    ],
    topicBody: cleanedDesc.isNotEmpty ? cleanedDesc : null,
  );
}

/// Opens the redesigned, minimal inspection modal for an announced [Test] / exam.
Future<void> showTestInspectionModal(
  BuildContext context,
  Test test, {
  UserProfilePrefs? prefs,
  String? heroTag,
}) {
  final scopeSettings =
      context.getInheritedWidgetOfExactType<AppProvidersScope>()?.settings;
  final effectivePrefs = prefs ?? scopeSettings?.prefs;
  final isMinimalist = effectivePrefs?.minimalistModeEnabled ??
      UserProfilePrefs.activeMinimalistModeEnabled;
  final dayFormat = DateFormat('yyyy. MM. dd.');
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
  final weekdayLabel = weekdayNames[testLocal.weekday.clamp(1, 7)];
  final rawSubject =
      test.subject.name.isNotEmpty ? test.subject.name : test.subjectName;
  final subjectDisplay = effectivePrefs != null
      ? effectivePrefs.resolveSubjectName(rawSubject, test.subject.uid)
      : rawSubject;
  final teacherDisplay = effectivePrefs != null
      ? effectivePrefs.resolveTeacherName(test.teacherName).trim()
      : test.teacherName.trim();
  final cleanTopic = OledTheme.capitalizeFirst(test.theme ?? '');
  final cleanMethod = OledTheme.capitalizeFirst(test.method.description);

  final title = cleanTopic.isNotEmpty
      ? cleanTopic
      : (cleanMethod.isNotEmpty ? cleanMethod : subjectDisplay);
  final lessonNum = test.lessonNumber;
  final subtitle = [
    if (subjectDisplay.trim().isNotEmpty && subjectDisplay != title)
      subjectDisplay.trim(),
    if (lessonNum > 0) '$lessonNum. óra',
  ].join(' • ');

  return showFrostedModal(
    context: context,
    categoryIcon: Icons.assignment_late_rounded,
    accentColor: const Color(0xFFFF7043),
    title: title,
    subtitle: subtitle,
    badgeText: lessonNum > 0 ? '$lessonNum.' : null,
    badgeShape: BoxShape.circle,
    heroTag: heroTag,
    closeMode: effectivePrefs?.modalCloseMode,
    prefs: effectivePrefs,
    rows: [
      FrostedDetailRow(
        label: 'Időpont',
        value: '$weekdayLabel, ${dayFormat.format(testLocal)}',
      ),
      if (cleanMethod.isNotEmpty && cleanMethod != title)
        FrostedDetailRow(
          label: 'Típus',
          value: cleanMethod,
        ),
      if (teacherDisplay.isNotEmpty)
        FrostedDetailRow(
          label: 'Tanár',
          value: teacherDisplay,
        ),
      if (!isMinimalist && test.reportDate.year > 2000)
        FrostedDetailRow(
          label: 'Bejelentve',
          value: dayFormat.format(test.reportDate.toLocal()),
        ),
    ],
  );
}

/// Opens the redesigned, minimal inspection modal for a timetable [Lesson]
/// with boomerang [heroTag] transition (`lesson_num_${lesson.uid}`).
Future<void> showLessonInspectionModal(
  BuildContext context,
  Lesson lesson, {
  String? heroTag,
  UserProfilePrefs? prefs,
  Homework? homework,
  bool? isHomeworkCompleted,
}) {
  final scopeSettings =
      context.getInheritedWidgetOfExactType<AppProvidersScope>()?.settings;
  final effectivePrefs = prefs ?? scopeSettings?.prefs;
  final isMinimalist = effectivePrefs?.minimalistModeEnabled ??
      UserProfilePrefs.activeMinimalistModeEnabled;
  final hwKey = homework != null
      ? SettingsProvider.homeworkCompletionKey(homework)
      : (lesson.homeworkUid?.trim() ?? '');
  final resolvedHwCompleted = isHomeworkCompleted ??
      (hwKey.isNotEmpty &&
          (scopeSettings?.isHomeworkKeyCompleted(hwKey) ?? false));
  final dayFormat = DateFormat('yyyy. MM. dd.');
  final timeFormat = DateFormat('HH:mm');
  final startLocal = lesson.start.toLocal();
  final endLocal = lesson.end.toLocal();
  final timeSpan =
      '${timeFormat.format(startLocal)} - ${timeFormat.format(endLocal)}';

  final isCancelled = lesson.state.name.toLowerCase() == 'elmaradt' ||
      lesson.state.name.toLowerCase().contains('elmarad') ||
      lesson.state.description.toLowerCase().contains('elmarad');
  final hasSub = lesson.substituteTeacher != null &&
      lesson.substituteTeacher!.trim().isNotEmpty;

  final scheme = Theme.of(context).colorScheme;
  final accent = isCancelled
      ? const Color(0xFFEF5350)
      : hasSub
          ? const Color(0xFFF59E0B)
          : scheme.primary;

  final rawSubject = lesson.subject?.name ?? lesson.name;
  final subjectDisplay = effectivePrefs != null
      ? effectivePrefs.resolveSubjectName(rawSubject, lesson.subject?.uid)
      : rawSubject;
  final teacherClean = (effectivePrefs != null && lesson.teacher != null
          ? effectivePrefs.resolveTeacherName(lesson.teacher)
          : (lesson.teacher ?? ''))
      .trim();
  final subTeacherClean =
      (effectivePrefs != null && lesson.substituteTeacher != null
              ? effectivePrefs.resolveTeacherName(lesson.substituteTeacher)
              : (lesson.substituteTeacher ?? ''))
          .trim();
  final roomClean = (lesson.roomName ?? '').trim();
  final themeClean = OledTheme.capitalizeFirst(lesson.theme ?? '');

  final effectiveTeacher = (hasSub && subTeacherClean.isNotEmpty)
      ? subTeacherClean
      : teacherClean;

  const hwTeal = Color(0xFF00BFA5);
  final hasHomeworkFlag = !isMinimalist &&
      (homework != null ||
          (lesson.homeworkUid != null && lesson.homeworkUid!.trim().isNotEmpty));

  Widget? homeworkSection;
  if (hasHomeworkFlag) {
    final hwDesc = homework != null
        ? Homework.stripHtmlTags(homework.description).trim()
        : '';
    homeworkSection = Builder(
      builder: (innerContext) {
        final theme = Theme.of(innerContext);
        final innerScheme = theme.colorScheme;
        return TactileBounce(
          onTap: homework != null
              ? () {
                  Navigator.of(innerContext).pop();
                  if (!context.mounted) return;
                  showHomeworkInspectionModal(
                    context,
                    homework,
                    prefs: effectivePrefs,
                  );
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 16,
                    color: hwTeal,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        uwuLabel(
                          resolvedHwCompleted
                              ? 'Házi feladat • Kész'
                              : 'Házi feladat',
                          enabled: effectivePrefs?.uwuModeEnabled,
                        ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: hwTeal,
                          fontWeight: FontWeight.w700,
                          decoration: resolvedHwCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (hwDesc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          uwu(
                            hwDesc,
                            enabled: effectivePrefs?.uwuModeEnabled,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: innerScheme.onSurface.withValues(alpha: 0.78),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (homework != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: innerScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  final subtitle = [
    timeSpan,
    if (roomClean.isNotEmpty) roomClean,
  ].join(' • ');

  return showFrostedModal(
    context: context,
    categoryIcon: Icons.schedule_rounded,
    accentColor: accent,
    badgeShape: BoxShape.circle,
    title: subjectDisplay,
    subtitle: subtitle,
    badgeText: lesson.lessonNumber != null ? '${lesson.lessonNumber}.' : '•',
    heroTag: heroTag ?? 'lesson_num_${lesson.uid}',
    closeMode: effectivePrefs?.modalCloseMode,
    prefs: effectivePrefs,
    rows: isMinimalist
        ? [
            FrostedDetailRow(
              label: 'Időpont',
              value: timeSpan,
            ),
            if (roomClean.isNotEmpty)
              FrostedDetailRow(
                label: 'Terem',
                value: roomClean,
              ),
            if (effectiveTeacher.isNotEmpty)
              FrostedDetailRow(
                label: 'Tanár',
                value: effectiveTeacher,
              ),
          ]
        : [
            if (themeClean.isNotEmpty)
              FrostedDetailRow(
                label: 'Téma',
                value: themeClean,
              ),
            FrostedDetailRow(
              label: 'Időpont',
              value: '${dayFormat.format(startLocal)} • $timeSpan',
            ),
            if (roomClean.isNotEmpty)
              FrostedDetailRow(
                label: 'Terem',
                value: roomClean,
              ),
            if (teacherClean.isNotEmpty)
              FrostedDetailRow(
                label: 'Tanár',
                value: teacherClean,
              ),
            if (hasSub && subTeacherClean.isNotEmpty)
              FrostedDetailRow(
                label: 'Helyettesítő',
                value: subTeacherClean,
              ),
            if (isCancelled || hasSub)
              FrostedDetailRow(
                label: 'Státusz',
                value: isCancelled ? 'Elmarad' : 'Helyettesítés',
                valueColor:
                    isCancelled ? const Color(0xFFEF5350) : const Color(0xFFF59E0B),
              ),
          ],
    extraBottomSection: isMinimalist ? null : homeworkSection,
  );
}
