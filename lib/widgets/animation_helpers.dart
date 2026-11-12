import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Underdamped liquid spring pill track (~400ms settling + velocity-driven
/// horizontal stretch / vertical squish) shared by the floating bottom
/// navigation bar and the Órarend weekday selector.
class LiquidSpringPillTrack extends StatefulWidget {
  final int itemCount;
  final int selectedIndex;
  final double height;
  final double? pillWidth;
  final double pillHeight;
  final PageController? pageController;
  final bool ignorePageController;
  final Clip clipBehavior;
  final BorderRadius? clipBorderRadius;
  final Widget Function(BuildContext context, double velocity) pillBuilder;
  final Widget Function(
    BuildContext context,
    int index,
    double activeProgress,
  ) itemBuilder;

  const LiquidSpringPillTrack({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.height,
    this.pillWidth,
    double? pillHeight,
    this.pageController,
    this.ignorePageController = false,
    this.clipBehavior = Clip.none,
    this.clipBorderRadius,
    required this.pillBuilder,
    required this.itemBuilder,
  }) : pillHeight = pillHeight ?? height;

  @override
  State<LiquidSpringPillTrack> createState() => _LiquidSpringPillTrackState();
}

class _LiquidSpringPillTrackState extends State<LiquidSpringPillTrack>
    with SingleTickerProviderStateMixin {
  static const SpringDescription _liquidSpring = SpringDescription(
    mass: 1.0,
    stiffness: 255.0,
    damping: 17.5,
  );

  late final AnimationController _pillAnim;
  ScrollPosition? _observedPosition;
  double? _lastPageSample;
  int _lastSampleUs = 0;
  double _dragVelocity = 0.0;
  bool _isFollowingPage = false;

  @override
  void initState() {
    super.initState();
    _pillAnim = AnimationController.unbounded(
      vsync: this,
      value: widget.selectedIndex.toDouble(),
    );
    widget.pageController?.addListener(_onPageControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScrollEndListener();
    });
  }

  @override
  void didUpdateWidget(covariant LiquidSpringPillTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController != widget.pageController) {
      oldWidget.pageController?.removeListener(_onPageControllerChanged);
      _detachScrollEndListener();
      widget.pageController?.addListener(_onPageControllerChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _attachScrollEndListener();
      });
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final pc = widget.pageController;
      final isUserSwiping = !widget.ignorePageController &&
          pc != null &&
          pc.hasClients &&
          pc.position.isScrollingNotifier.value;
      if (!isUserSwiping) {
        _launchSpringTo(widget.selectedIndex.toDouble());
      }
    }
  }

  void _attachScrollEndListener() {
    if (!mounted) return;
    final pc = widget.pageController;
    if (pc == null || !pc.hasClients) return;
    final pos = pc.position;
    if (_observedPosition == pos) return;
    _detachScrollEndListener();
    _observedPosition = pos;
    pos.isScrollingNotifier.addListener(_onScrollingStateChanged);
  }

  void _detachScrollEndListener() {
    _observedPosition?.isScrollingNotifier.removeListener(
      _onScrollingStateChanged,
    );
    _observedPosition = null;
  }

  void _onScrollingStateChanged() {
    final pos = _observedPosition;
    if (pos == null || pos.isScrollingNotifier.value) return;
    if (_isFollowingPage) {
      final leftoverVel = _dragVelocity.clamp(-8.0, 8.0);
      _isFollowingPage = false;
      _dragVelocity = 0.0;
      _lastPageSample = null;
      _lastSampleUs = 0;
      _launchSpringTo(
        widget.selectedIndex.toDouble(),
        initialVelocity: leftoverVel,
      );
    }
  }

  void _onPageControllerChanged() {
    _attachScrollEndListener();
    if (widget.ignorePageController) return;
    final pc = widget.pageController;
    if (pc == null || !pc.hasClients || !pc.position.haveDimensions) return;
    if (!pc.position.isScrollingNotifier.value) {
      return;
    }
    final page = pc.page;
    if (page == null) return;
    final clamped = page.clamp(0.0, (widget.itemCount - 1).toDouble());
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    if (_lastPageSample != null && _lastSampleUs > 0) {
      final dtSec = ((nowUs - _lastSampleUs) / 1000000.0).clamp(0.004, 0.05);
      final instVel = ((clamped - _lastPageSample!) / dtSec).clamp(-18.0, 18.0);
      _dragVelocity = (_dragVelocity * 0.55) + (instVel * 0.45);
    }
    _lastPageSample = clamped;
    _lastSampleUs = nowUs;
    _isFollowingPage = true;
    _pillAnim.value = clamped;
  }

  void _launchSpringTo(double target, {double? initialVelocity}) {
    _isFollowingPage = false;
    final currentPos = _pillAnim.value;
    final currentVel =
        initialVelocity ?? (_pillAnim.isAnimating ? _pillAnim.velocity : 0.0);
    _dragVelocity = 0.0;
    _lastPageSample = null;
    _lastSampleUs = 0;
    if ((currentPos - target).abs() < 0.001 && currentVel.abs() < 0.01) {
      _pillAnim.value = target;
      return;
    }
    final sim = SpringSimulation(
      _liquidSpring,
      currentPos,
      target,
      currentVel,
    );
    _pillAnim.animateWith(sim);
  }

  @override
  void dispose() {
    widget.pageController?.removeListener(_onPageControllerChanged);
    _detachScrollEndListener();
    _pillAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / widget.itemCount;
          final resolvedPillWidth = widget.pillWidth ?? slotWidth;
          final topOffset = (widget.height - widget.pillHeight) / 2;

          return AnimatedBuilder(
            animation: _pillAnim,
            builder: (context, _) {
              final pos = _pillAnim.value;
              final vel = _isFollowingPage
                  ? _dragVelocity
                  : (_pillAnim.isAnimating ? _pillAnim.velocity : 0.0);
              final stretchNorm = (vel.abs() / 12.0).clamp(0.0, 1.0);
              final scaleX = 1.0 + (stretchNorm * 0.28);
              final scaleY = 1.0 - (stretchNorm * 0.11);
              final left = (pos * slotWidth) +
                  ((slotWidth - resolvedPillWidth) / 2);

              final stack = Stack(
                alignment: Alignment.center,
                clipBehavior: widget.clipBehavior,
                children: [
                  Positioned(
                    left: left,
                    top: topOffset,
                    width: resolvedPillWidth,
                    height: widget.pillHeight,
                    child: IgnorePointer(
                      child: Transform.scale(
                        scaleX: scaleX,
                        scaleY: scaleY,
                        alignment: Alignment.center,
                        child: widget.pillBuilder(context, vel),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(widget.itemCount, (idx) {
                      final activeProgress = (1.0 - (pos - idx).abs())
                          .clamp(0.0, 1.0);
                      return Expanded(
                        child: widget.itemBuilder(context, idx, activeProgress),
                      );
                    }),
                  ),
                ],
              );

              if (widget.clipBorderRadius != null) {
                return ClipRRect(
                  borderRadius: widget.clipBorderRadius!,
                  child: stack,
                );
              }
              return stack;
            },
          );
        },
      ),
    );
  }
}

/// Custom 120Hz-ready Shared-Axis / Predictive-Back style page route transition
/// using `Curves.easeOutCubic` / `Curves.easeInOutCubic` (280ms forward, 240ms reverse).
class SmoothSharedAxisRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothSharedAxisRoute({
    required this.page,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final primaryCurved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInOutCubic,
            );
            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInOutCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.06, 0.0),
                end: Offset.zero,
              ).animate(primaryCurved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                  primaryCurved,
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                    primaryCurved,
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 0.97).animate(
                      secondaryCurved,
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}

/// Custom PageTransitionsBuilder so all standard routes use smooth shared-axis
/// slide + subtle scale fade transitions instead of abrupt platform cuts.
class SmoothSharedAxisTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothSharedAxisTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final primaryCurved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    final secondaryCurved = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.05, 0.0),
        end: Offset.zero,
      ).animate(primaryCurved),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(primaryCurved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(primaryCurved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 0.97).animate(secondaryCurved),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Tactile scale-bounce wrapper that shrinks to [pressedScale] (0.96) on tap
/// down and springs back to 1.0 on release with `HapticFeedback.lightImpact()`.
class TactileBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final bool enableHaptics;

  const TactileBounce({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.96,
    this.borderRadius,
    this.enableHaptics = true,
  });

  @override
  State<TactileBounce> createState() => _TactileBounceState();
}

class _TactileBounceState extends State<TactileBounce> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails _) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onTap == null) return;
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    if (_isPressed) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTap() {
    if (widget.onTap == null) return;
    if (widget.enableHaptics) {
      HapticFeedback.lightImpact();
    }
    widget.onTap!();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1.0,
        duration: Duration(milliseconds: _isPressed ? 105 : 190),
        curve: _isPressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

/// Smoothly animates floating-point or integer number rollups (grade averages,
/// ghost simulator projected averages, countdown minutes) using
/// [TweenAnimationBuilder] and `Curves.easeOutCubic`.
class AnimatedNumberText extends StatelessWidget {
  final double value;
  final int fractionDigits;
  final String prefix;
  final String suffix;
  final TextStyle? style;
  final Duration duration;

  const AnimatedNumberText({
    super.key,
    required this.value,
    this.fractionDigits = 2,
    this.prefix = '',
    this.suffix = '',
    this.style,
    this.duration = const Duration(milliseconds: 360),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, animatedVal, _) {
        final formatted = fractionDigits == 0
            ? animatedVal.round().toString()
            : animatedVal.toStringAsFixed(fractionDigits);
        return Text(
          '$prefix$formatted$suffix',
          style: style,
        );
      },
    );
  }
}

/// Lightweight, GPU-friendly one-shot entrance animation (`240ms`,
/// `Curves.easeOutCubic`, fade `0.0 -> 1.0` + `14px` upward translation with a
/// `35ms` stagger for initial visible items).
///
/// Runs at most once per initial load and never re-triggers during vertical
/// scrolling or tab switching. Once completed, renders [child] directly with
/// zero compositing overhead.
class StaggeredEntranceItem extends StatefulWidget {
  final Widget child;
  final int index;
  final bool enabled;
  final int stepMs;
  final int maxStaggerIndex;
  final double slideOffsetPx;
  final int durationMs;

  const StaggeredEntranceItem({
    super.key,
    required this.child,
    required this.index,
    this.enabled = true,
    this.stepMs = 35,
    this.maxStaggerIndex = 8,
    this.slideOffsetPx = 14.0,
    this.durationMs = 240,
  });

  @override
  State<StaggeredEntranceItem> createState() => _StaggeredEntranceItemState();
}

class _StaggeredEntranceItemState extends State<StaggeredEntranceItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _curved;
  bool _hasAnimated = false;
  bool _completed = true;

  @override
  void initState() {
    super.initState();
    if (widget.enabled && widget.index <= widget.maxStaggerIndex) {
      _startEntrance();
    }
  }

  @override
  void didUpdateWidget(covariant StaggeredEntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled &&
        !oldWidget.enabled &&
        !_hasAnimated &&
        widget.index <= widget.maxStaggerIndex) {
      _startEntrance();
    }
  }

  void _startEntrance() {
    _hasAnimated = true;
    _completed = false;
    final effectiveIdx = widget.index.clamp(0, widget.maxStaggerIndex);
    final delayMs = effectiveIdx * widget.stepMs;
    final totalMs = delayMs + widget.durationMs;

    _controller?.dispose();
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _controller = ctrl;
    final beginFraction =
        totalMs > 0 ? (delayMs / totalMs).clamp(0.0, 0.92) : 0.0;
    _curved = CurvedAnimation(
      parent: ctrl,
      curve: Interval(beginFraction, 1.0, curve: Curves.easeOutCubic),
    );
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _completed = true);
      }
    });
    ctrl.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_curved == null) {
      return widget.child;
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _curved!,
        child: widget.child,
        builder: (context, child) {
          final t = _completed ? 1.0 : _curved!.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0.0, (1.0 - t) * widget.slideOffsetPx),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Extension applying the 120fps one-shot staggered fade (`0.0 -> 1.0`) +
/// `14px` upward translation (`240ms`, `Curves.easeOutCubic`, `35ms` stagger).
extension StaggeredListEntrance on Widget {
  Widget staggeredEntrance(
    int index, {
    Key? animationKey,
    bool enabled = true,
    int stepMs = 35,
    int maxStaggerIndex = 8,
  }) {
    return StaggeredEntranceItem(
      key: animationKey,
      index: index,
      enabled: enabled,
      stepMs: stepMs,
      maxStaggerIndex: maxStaggerIndex,
      child: this,
    );
  }
}
