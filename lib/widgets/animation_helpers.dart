import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

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

/// Extension applying `flutter_animate` staggered fade + slideY entrance
/// (`.fadeIn(duration: 250.ms).slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic)`).
extension StaggeredListEntrance on Widget {
  Widget staggeredEntrance(
    int index, {
    Key? animationKey,
    int stepMs = 35,
    int maxStaggerIndex = 12,
  }) {
    final effectiveIdx = index.clamp(0, maxStaggerIndex);
    final delay = Duration(milliseconds: effectiveIdx * stepMs);

    return animate(key: animationKey, delay: delay)
        .fadeIn(
          duration: 250.ms,
          curve: Curves.easeOutCubic,
        )
        .slideY(
          begin: 0.1,
          end: 0.0,
          duration: 250.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
