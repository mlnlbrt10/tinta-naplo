import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kreta_api/kreta_api.dart';

import '../providers/app_providers.dart';
import '../services/kreta_client.dart';
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
  return -(maxUpwardPull * (absUp / (absUp + 95.0)));
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

/// Computes smoothly damped downward offset when dragging a floating sheet
/// downward so it exhibits natural resistance instead of flying 1:1 or hitting
/// a hard clamp wall.
double computeSheetDownwardDampedOffset(double rawPositiveDrag) {
  if (rawPositiveDrag <= 0.0) return 0.0;
  const double maxPull = 540.0;
  return maxPull * (rawPositiveDrag / (rawPositiveDrag + 640.0));
}

/// Scroll physics for floating bottom sheets/popups:
/// - On scrollable popups (`maxScrollExtent > 0.5`, e.g. Ösztöndíj kalkulátor),
///   enables symmetrical top AND bottom [BouncingScrollPhysics] elastic
///   overscroll bounce/stretch so scrolling feels equally fluid at both ends.
/// - On non-scrollable sheets (`maxScrollExtent <= 0.5`), clamps at both top
///   and bottom so dragging anywhere on the card drives whole-sheet swipe/stretch.
class FloatingSheetScrollPhysics extends BouncingScrollPhysics {
  const FloatingSheetScrollPhysics({super.parent});

  @override
  FloatingSheetScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FloatingSheetScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final isScrollable = position.maxScrollExtent > position.minScrollExtent + 0.5;
    if (isScrollable) {
      return super.applyBoundaryConditions(position, value);
    }
    if (value < position.pixels &&
        position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }
    if (value < position.minScrollExtent &&
        position.minScrollExtent < position.pixels) {
      return value - position.minScrollExtent;
    }
    if (position.maxScrollExtent <= position.pixels &&
        position.pixels < value) {
      return value - position.pixels;
    }
    if (position.pixels < position.maxScrollExtent &&
        position.maxScrollExtent < value) {
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final isScrollable = position.maxScrollExtent > position.minScrollExtent + 0.5;
    if (isScrollable) {
      return super.createBallisticSimulation(position, velocity);
    }
    if (velocity.abs() > 0.0) {
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}

class _FloatingSheetScrollBehavior extends ScrollBehavior {
  const _FloatingSheetScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const FloatingSheetScrollPhysics(
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
      onDismiss: () async {
        if (isCurrent && navigator != null) {
          return navigator!.maybePop();
        }
        return false;
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
  final Future<bool> Function() onDismiss;

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
  static const double _dismissDistanceThreshold = 92.0;
  static const double _dismissVelocityThreshold = 520.0;
  static const double _deliberateTopDismissOverscrollPx = 36.0;

  late final AnimationController _springBackCtrl;
  double _rawDragOffset = 0.0;
  double _visualOffset = 0.0;
  double _topScrollOverscrollPx = 0.0;
  double _bottomScrollOverscrollPx = 0.0;
  bool _scrollStartedAtTop = false;
  bool _scrollableDismissUnlocked = false;
  bool _dismissTriggered = false;
  bool _gestureDetectorOwnsDrag = false;
  bool _scrollDragActive = false;
  final Set<int> _activePointers = <int>{};
  int? _trackingPointer;
  VelocityTracker? _velocityTracker;

  @override
  void initState() {
    super.initState();
    _springBackCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) {
          setState(() {
            _visualOffset = _springBackCtrl.value.clamp(-36.0, 620.0);
          });
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          if (mounted && _visualOffset.abs() < 0.15) {
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

  void _applyDragDelta(
    double deltaDy, {
    bool allowUpwardFromScroll = false,
  }) {
    if (_dismissTriggered || deltaDy == 0.0) return;
    if (_springBackCtrl.isAnimating) {
      _springBackCtrl.stop();
    }
    final nextRaw = (_rawDragOffset + deltaDy).clamp(-600.0, 2400.0);
    // If releasing a pull-down inside a mid-scrolled sheet, clamp at 0 so the
    // inner list scrolls first unless we're explicitly at the bottom/card edge.
    if (_scrollDragActive &&
        _rawDragOffset > 0.0 &&
        nextRaw < 0.0 &&
        !allowUpwardFromScroll) {
      _rawDragOffset = 0.0;
    } else {
      _rawDragOffset = nextRaw;
    }
    final nextVisual = _rawDragOffset >= 0.0
        ? computeSheetDownwardDampedOffset(_rawDragOffset)
        : computeSheetUpwardRubberBand(_rawDragOffset);
    if ((nextVisual - _visualOffset).abs() > 0.05 ||
        (_rawDragOffset == 0.0 && _visualOffset != 0.0)) {
      setState(() => _visualOffset = _rawDragOffset == 0.0 ? 0.0 : nextVisual);
    }
    if (_scrollDragActive && _rawDragOffset == 0.0) {
      _scrollDragActive = false;
    }
  }

  void _springBackToRest(double velocityY) {
    _rawDragOffset = 0.0;
    _scrollDragActive = false;
    _gestureDetectorOwnsDrag = false;
    _scrollStartedAtTop = false;
    _scrollableDismissUnlocked = false;
    _topScrollOverscrollPx = 0.0;
    _bottomScrollOverscrollPx = 0.0;
    if (!mounted) return;
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
    } else if (_visualOffset != 0.0 ||
        _topScrollOverscrollPx != 0.0 ||
        _bottomScrollOverscrollPx != 0.0) {
      setState(() {
        _visualOffset = 0.0;
        _topScrollOverscrollPx = 0.0;
        _bottomScrollOverscrollPx = 0.0;
      });
    }
  }

  void _finishDrag(double velocityY) {
    if (_dismissTriggered) return;
    if (_rawDragOffset >= 0.0 &&
        (_visualOffset > _dismissDistanceThreshold ||
            (velocityY > _dismissVelocityThreshold && _visualOffset > 20.0))) {
      _dismissTriggered = true;
      HapticFeedback.selectionClick();
      widget.onDismiss().then((didDismiss) {
        if (!didDismiss && mounted) {
          _dismissTriggered = false;
          _springBackToRest(0.0);
        }
      });
      return;
    }
    _springBackToRest(velocityY);
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
    _activePointers.add(event.pointer);
    if (_activePointers.length == 1 || _trackingPointer == null) {
      _trackingPointer = event.pointer;
      _velocityTracker = VelocityTracker.withKind(event.kind);
      _scrollDragActive = false;
    }
    if (event.pointer == _trackingPointer) {
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer == _trackingPointer) {
      _velocityTracker?.addPosition(event.timeStamp, event.position);
    }
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _activePointers.remove(event.pointer);
    final velocityY = event.pointer == _trackingPointer
        ? (_velocityTracker?.getVelocity().pixelsPerSecond.dy ?? 0.0)
        : 0.0;
    if (_activePointers.isNotEmpty) {
      if (event.pointer == _trackingPointer) {
        _trackingPointer = _activePointers.first;
      }
      return;
    }
    _trackingPointer = null;
    _velocityTracker = null;
    if (!_gestureDetectorOwnsDrag &&
        (_scrollDragActive || _visualOffset.abs() > 0.1)) {
      _scrollDragActive = false;
      _finishDrag(velocityY);
    } else {
      _scrollDragActive = false;
      // Failsafe: if the GestureDetector claimed drag start but lost arena or
      // failed to fire onEnd/onCancel, ensure the sheet never stays stuck.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _dismissTriggered ||
            _activePointers.isNotEmpty ||
            _springBackCtrl.isAnimating) {
          return;
        }
        if (_visualOffset.abs() > 0.1) {
          _gestureDetectorOwnsDrag = false;
          _scrollDragActive = false;
          _finishDrag(velocityY);
        }
      });
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_dismissTriggered ||
        _gestureDetectorOwnsDrag ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final metrics = notification.metrics;
    final isScrollable = metrics.maxScrollExtent > metrics.minScrollExtent + 0.5;

    if (notification is ScrollStartNotification) {
      _scrollStartedAtTop = notification.dragDetails != null &&
          metrics.pixels <= metrics.minScrollExtent + 1.0;
      _scrollableDismissUnlocked = false;
      return false;
    }

    if (notification is OverscrollNotification &&
        notification.dragDetails != null) {
      if (!isScrollable) {
        if (notification.overscroll < 0.0 && metrics.pixels <= 0.5) {
          // Non-scrollable popup: pulling downward drives swipe-to-dismiss.
          _scrollDragActive = true;
          _applyDragDelta(-notification.overscroll);
        } else if (notification.overscroll > 0.0 &&
            metrics.pixels >= metrics.maxScrollExtent - 0.5) {
          _scrollDragActive = true;
          _applyDragDelta(
            -notification.overscroll,
            allowUpwardFromScroll: true,
          );
        }
      }
      return false;
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (isScrollable) {
        final topOver =
            (metrics.minScrollExtent - metrics.pixels).clamp(0.0, 220.0);
        final bottomOver =
            (metrics.pixels - metrics.maxScrollExtent).clamp(0.0, 220.0);

        if ((topOver - _topScrollOverscrollPx).abs() > 0.4 ||
            (bottomOver - _bottomScrollOverscrollPx).abs() > 0.4 ||
            (topOver == 0.0 && _topScrollOverscrollPx != 0.0) ||
            (bottomOver == 0.0 && _bottomScrollOverscrollPx != 0.0)) {
          setState(() {
            _topScrollOverscrollPx = topOver;
            _bottomScrollOverscrollPx = bottomOver;
          });
        }

        // Bottom overscroll subtle upward rubber-band stretch
        if (bottomOver > 0.5 && notification.dragDetails != null && delta > 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta * 0.4, allowUpwardFromScroll: true);
        } else if (_scrollableDismissUnlocked &&
            notification.dragDetails != null &&
            delta != 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta);
        } else if (_scrollStartedAtTop &&
            notification.dragDetails != null &&
            topOver >= _deliberateTopDismissOverscrollPx &&
            delta < 0.0) {
          // User started at offset 0 and deliberately pulled down past threshold
          _scrollableDismissUnlocked = true;
          _scrollDragActive = true;
          _applyDragDelta(-delta);
        } else if (bottomOver <= 0.5 && _rawDragOffset < 0.0) {
          _applyDragDelta(-delta, allowUpwardFromScroll: true);
        }
        return false;
      }

      final atBottomOverscroll =
          metrics.pixels > metrics.maxScrollExtent + 0.5;
      if (notification.dragDetails != null) {
        if (_scrollDragActive) {
          if ((_rawDragOffset != 0.0 || atBottomOverscroll) && delta != 0.0) {
            _applyDragDelta(
              atBottomOverscroll ? -delta * 0.4 : -delta,
              allowUpwardFromScroll: atBottomOverscroll || _rawDragOffset <= 0.0,
            );
          }
        } else if (metrics.pixels < -0.5 && delta < 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta);
        } else if (atBottomOverscroll && delta > 0.0) {
          _scrollDragActive = true;
          _applyDragDelta(-delta * 0.4, allowUpwardFromScroll: true);
        }
      }
      return false;
    }

    if (notification is ScrollEndNotification) {
      final hadActive = _scrollDragActive || _visualOffset.abs() > 0.1;
      final canDismiss = !isScrollable || _scrollableDismissUnlocked;
      _scrollDragActive = false;
      _scrollStartedAtTop = false;
      _scrollableDismissUnlocked = false;
      if (_topScrollOverscrollPx != 0.0 || _bottomScrollOverscrollPx != 0.0) {
        setState(() {
          _topScrollOverscrollPx = 0.0;
          _bottomScrollOverscrollPx = 0.0;
        });
      }
      if (hadActive && !_gestureDetectorOwnsDrag) {
        if (canDismiss) {
          final endVelocity = notification.dragDetails?.primaryVelocity ??
              _velocityTracker?.getVelocity().pixelsPerSecond.dy ??
              0.0;
          _finishDrag(endVelocity);
        } else {
          _springBackToRest(0.0);
        }
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
    final Alignment stretchAlignment;

    if (effectiveOffset > 0.0) {
      translateY = effectiveOffset;
      final uniformScale =
          (1.0 - (effectiveOffset / 1800.0)).clamp(0.92, 1.0);
      scaleX = uniformScale;
      scaleY = uniformScale;
      stretchAlignment = Alignment.bottomCenter;
    } else if (effectiveOffset < 0.0) {
      translateY = effectiveOffset * 0.45;
      scaleX = 1.0;
      scaleY = computeSheetUpwardStretchScale(effectiveOffset);
      stretchAlignment = Alignment.bottomCenter;
    } else if (_topScrollOverscrollPx > 0.5) {
      final clamped = _topScrollOverscrollPx.clamp(0.0, 140.0);
      translateY = clamped * 0.14;
      scaleX = 1.0;
      scaleY = 1.0 + ((clamped / (clamped + 180.0)) * 0.045);
      stretchAlignment = Alignment.topCenter;
    } else if (_bottomScrollOverscrollPx > 0.5) {
      final clamped = _bottomScrollOverscrollPx.clamp(0.0, 140.0);
      translateY = -clamped * 0.14;
      scaleX = 1.0;
      scaleY = 1.0 + ((clamped / (clamped + 180.0)) * 0.045);
      stretchAlignment = Alignment.bottomCenter;
    } else {
      translateY = 0.0;
      scaleX = 1.0;
      scaleY = 1.0;
      stretchAlignment = Alignment.bottomCenter;
    }

    // Keep Transform nodes unconditionally mounted in the tree so transitioning
    // between 0 and non-zero drag offsets never unmounts/resets inner Scrollables.
    final Widget content = Transform.translate(
      offset: Offset(0, translateY),
      child: Transform(
        alignment: stretchAlignment,
        transform: Matrix4.diagonal3Values(scaleX, scaleY, 1.0),
        child: ScrollConfiguration(
          behavior: const _FloatingSheetScrollBehavior(),
          child: widget.child,
        ),
      ),
    );

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

/// Shared top-right circular close (`X`) button for all popups and modals.
/// Uses an exact centered glyph inside a `SizedBox` so there is zero offset.
class PopupTopCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final double size;
  final double iconSize;

  const PopupTopCloseButton({
    super.key,
    required this.onTap,
    this.size = 32,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return TactileBounce(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.onSurface.withValues(alpha: isDark ? 0.09 : 0.07),
          ),
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: iconSize,
              color: scheme.onSurface.withValues(alpha: 0.78),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared bottom close action button for popups and modals when
/// [ModalCloseButtonMode.showBottomButton] is enabled.
class PopupBottomCloseButton extends StatelessWidget {
  final VoidCallback onTap;
  final Color? accentColor;
  final String label;
  final bool? uwuEnabled;

  const PopupBottomCloseButton({
    super.key,
    required this.onTap,
    this.accentColor,
    this.label = 'Bezárás',
    this.uwuEnabled,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = accentColor ?? scheme.primary;
    return TactileBounce(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          uwuLabel(label, enabled: uwuEnabled),
          style: TextStyle(
            color: OledTheme.contrastTextFor(fill),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
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
  final effectiveCloseMode = closeMode ??
      prefs?.modalCloseMode ??
      AppProvidersScope.maybeOf(context)?.settings.prefs.modalCloseMode ??
      UserProfilePrefs.activeModalCloseMode;
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
                        PopupTopCloseButton(
                          onTap: () => Navigator.of(sheetContext).pop(),
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
                    PopupBottomCloseButton(
                      onTap: () => Navigator.of(sheetContext).pop(),
                      accentColor: accentColor,
                      uwuEnabled: uwuEnabled,
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
  Omission? omission,
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

  final brightness = Theme.of(context).brightness;
  final scheme = Theme.of(context).colorScheme;
  final accent = isCancelled
      ? const Color(0xFFEF5350)
      : hasSub
          ? const Color(0xFFF59E0B)
          : scheme.primary;

  final omissionIsLate = omission != null && OmissionsSummary.isTardiness(omission);
  final omissionStatusLabel = omission == null
      ? ''
      : switch (omission.state) {
          OmissionState.excused => 'Igazolt',
          OmissionState.unexcused => 'Igazolatlan',
          OmissionState.pending || OmissionState.unknown => 'Igazolandó',
        };
  final omissionStatusColor = omission == null
      ? scheme.primary
      : switch (omission.state) {
          OmissionState.excused => OledTheme.omissionExcusedColor(brightness),
          OmissionState.unexcused => OledTheme.omissionUnexcusedRedColor(brightness),
          OmissionState.pending ||
          OmissionState.unknown =>
            OledTheme.omissionPendingOrangeColor(brightness),
        };
  final omissionRowValue = omission == null
      ? ''
      : (omissionIsLate
          ? '${omission.lateForMin ?? 0} perc • $omissionStatusLabel'
          : omissionStatusLabel);

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
            if (omission != null)
              FrostedDetailRow(
                label: omissionIsLate ? 'Késés' : 'Hiányzás',
                value: omissionRowValue,
                valueColor: omissionStatusColor,
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
            if (omission != null)
              FrostedDetailRow(
                label: omissionIsLate ? 'Késés' : 'Hiányzás',
                value: omissionRowValue,
                valueColor: omissionStatusColor,
              ),
          ],
    extraBottomSection: isMinimalist ? null : homeworkSection,
  );
}

/// Shared modern floating Liquid Glass calendar date picker popup.
Future<DateTime?> showTintaDatePickerSheet({
  required BuildContext context,
  UserProfilePrefs? prefs,
  required DateTime initialDate,
  DateTime? today,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  final effectivePrefs = prefs ??
      AppProvidersScope.maybeOf(context)?.settings.prefs ??
      const UserProfilePrefs();
  final effectiveToday = today ?? DateUtils.dateOnly(DateTime.now());
  return showFloatingGlassSheet<DateTime>(
    context: context,
    prefs: effectivePrefs,
    builder: (sheetCtx) {
      final bottomInset = MediaQuery.viewInsetsOf(sheetCtx).bottom;
      return AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: (MediaQuery.sizeOf(sheetCtx).height - bottomInset) * 0.86,
          ),
          child: FrostedBottomSheetSurface(
            prefs: effectivePrefs,
            showDragHandle: true,
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: SingleChildScrollView(
              physics: const FloatingSheetScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              child: _TintaDatePickerContent(
                initialDate: initialDate,
                today: effectiveToday,
                firstDate: firstDate,
                lastDate: lastDate,
                prefs: effectivePrefs,
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _TintaDatePickerContent extends StatefulWidget {
  final DateTime initialDate;
  final DateTime today;
  final DateTime firstDate;
  final DateTime lastDate;
  final UserProfilePrefs prefs;

  const _TintaDatePickerContent({
    required this.initialDate,
    required this.today,
    required this.firstDate,
    required this.lastDate,
    required this.prefs,
  });

  @override
  State<_TintaDatePickerContent> createState() =>
      _TintaDatePickerContentState();
}

class _TintaDatePickerContentState extends State<_TintaDatePickerContent> {
  static const List<String> _monthNames = [
    'január',
    'február',
    'március',
    'április',
    'május',
    'június',
    'július',
    'augusztus',
    'szeptember',
    'október',
    'november',
    'december',
  ];

  static const List<String> _weekdays = [
    'H',
    'K',
    'Sze',
    'Cs',
    'P',
    'Szo',
    'V',
  ];

  late DateTime _visibleMonth;
  int _monthDirection = 1;

  @override
  void initState() {
    super.initState();
    _visibleMonth = DateTime(widget.initialDate.year, widget.initialDate.month);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get _canGoPrev {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    return !prev.isBefore(minMonth);
  }

  bool get _canGoNext {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    return !next.isAfter(maxMonth);
  }

  void _stepMonth(int delta) {
    final target = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    final minMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final maxMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (target.isBefore(minMonth) || target.isAfter(maxMonth)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _monthDirection = delta;
      _visibleMonth = target;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final closeMode = widget.prefs.modalCloseMode;
    final selected = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    final selectedMonday = DateTime(
      selected.year,
      selected.month,
      selected.day - (selected.weekday - 1),
    );
    final selectedSunday = DateTime(
      selectedMonday.year,
      selectedMonday.month,
      selectedMonday.day + 6,
    );

    final firstOfMonth = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final leadingDays = firstOfMonth.weekday - 1;
    final daysInMonth =
        DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final rowCount = ((leadingDays + daysInMonth + 6) ~/ 7);
    final gridStart = DateTime(
      firstOfMonth.year,
      firstOfMonth.month,
      1 - leadingDays,
    );

    final monthLabel =
        '${_visibleMonth.year}. ${_monthNames[_visibleMonth.month - 1]}';
    final isViewingToday = _sameDay(selected, widget.today);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildNavBtn(
              scheme: scheme,
              isDark: isDark,
              icon: Icons.chevron_left_rounded,
              tooltip: 'Előző hónap',
              enabled: _canGoPrev,
              onTap: () => _stepMonth(-1),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 210),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) {
                    final offset = Tween<Offset>(
                      begin: Offset(_monthDirection >= 0 ? 0.12 : -0.12, 0),
                      end: Offset.zero,
                    ).animate(anim);
                    return FadeTransition(
                      opacity: anim,
                      child: SlideTransition(position: offset, child: child),
                    );
                  },
                  child: FittedBox(
                    key: ValueKey<String>(monthLabel),
                    fit: BoxFit.scaleDown,
                    child: Text(
                      uwu(monthLabel, enabled: widget.prefs.uwuModeEnabled),
                      maxLines: 1,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _buildNavBtn(
              scheme: scheme,
              isDark: isDark,
              icon: Icons.chevron_right_rounded,
              tooltip: 'Következő hónap',
              enabled: _canGoNext,
              onTap: () => _stepMonth(1),
            ),
            const SizedBox(width: 6),
            TactileBounce(
              pressedScale: 0.94,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).pop(widget.today);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(
                    alpha: isViewingToday ? 0.10 : 0.18,
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.primary.withValues(
                      alpha: isViewingToday ? 0.35 : 0.65,
                    ),
                  ),
                ),
                child: Text(
                  'Ma',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
            if (closeMode.showTopX) ...[
              const SizedBox(width: 6),
              PopupTopCloseButton(
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: List.generate(7, (col) {
            final isWeekend = col >= 5;
            return Expanded(
              child: Center(
                child: Text(
                  _weekdays[col],
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface.withValues(
                      alpha: isWeekend ? 0.42 : 0.66,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Column(
            key: ValueKey<String>(
              'grid-${_visibleMonth.year}-${_visibleMonth.month}',
            ),
            mainAxisSize: MainAxisSize.min,
            children: List.generate(rowCount, (row) {
              final rowStart = DateTime(
                gridStart.year,
                gridStart.month,
                gridStart.day + (row * 7),
              );
              final rowEnd = DateTime(
                rowStart.year,
                rowStart.month,
                rowStart.day + 6,
              );
              final isSelectedWeekRow = !rowEnd.isBefore(selectedMonday) &&
                  !rowStart.isAfter(selectedSunday);

              final weekRow = Row(
                children: List.generate(7, (col) {
                  final day = DateTime(
                    rowStart.year,
                    rowStart.month,
                    rowStart.day + col,
                  );
                  final inMonth = day.month == _visibleMonth.month &&
                      day.year == _visibleMonth.year;
                  final inBounds = !day.isBefore(widget.firstDate) &&
                      !day.isAfter(widget.lastDate);
                  final isSelected = _sameDay(day, selected);
                  final isToday = _sameDay(day, widget.today);
                  final isWeekend = col >= 5;

                  return Expanded(
                    child: _buildDayCell(
                      scheme: scheme,
                      isDark: isDark,
                      day: day,
                      inMonth: inMonth,
                      inBounds: inBounds,
                      isSelected: isSelected,
                      isToday: isToday,
                      isWeekend: isWeekend,
                    ),
                  );
                }),
              );

              return Container(
                margin: const EdgeInsets.symmetric(vertical: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: isSelectedWeekRow
                    ? BoxDecoration(
                        color: scheme.primary.withValues(
                          alpha: isDark ? 0.14 : 0.10,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.25),
                          width: 1.0,
                        ),
                      )
                    : null,
                child: weekRow,
              );
            }),
          ),
        ),
        if (closeMode.showBottomButton) ...[
          const SizedBox(height: 14),
          PopupBottomCloseButton(
            onTap: () => Navigator.of(context).pop(),
            label: 'Mégse',
            uwuEnabled: widget.prefs.uwuModeEnabled,
          ),
        ],
      ],
    );
  }

  Widget _buildNavBtn({
    required ColorScheme scheme,
    required bool isDark,
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: TactileBounce(
        pressedScale: 0.92,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }

  Widget _buildDayCell({
    required ColorScheme scheme,
    required bool isDark,
    required DateTime day,
    required bool inMonth,
    required bool inBounds,
    required bool isSelected,
    required bool isToday,
    required bool isWeekend,
  }) {
    final textColor = !inBounds
        ? scheme.onSurface.withValues(alpha: 0.18)
        : isSelected
            ? scheme.onPrimary
            : isToday
                ? scheme.primary
                : inMonth
                    ? scheme.onSurface.withValues(alpha: isWeekend ? 0.65 : 1.0)
                    : scheme.onSurface.withValues(alpha: 0.28);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: inBounds
          ? () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop(day);
            }
          : null,
      child: SizedBox(
        height: 36,
        child: Center(
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? scheme.primary
                  : (isToday
                      ? scheme.primary.withValues(alpha: isDark ? 0.14 : 0.10)
                      : Colors.transparent),
              border: !isSelected && isToday
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected || isToday
                    ? FontWeight.w900
                    : (inMonth ? FontWeight.w700 : FontWeight.w500),
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Owns local modal disposables ([TextEditingController], [ValueNotifier],
/// etc.) so they are only disposed after the enclosing route's exit animation
/// finishes and unmounts the sheet widget tree.
class SheetDisposableScope extends StatefulWidget {
  final List<ChangeNotifier> disposables;
  final WidgetBuilder builder;

  const SheetDisposableScope({
    super.key,
    required this.disposables,
    required this.builder,
  });

  @override
  State<SheetDisposableScope> createState() => _SheetDisposableScopeState();
}

class _SheetDisposableScopeState extends State<SheetDisposableScope> {
  @override
  void dispose() {
    for (final d in widget.disposables) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
