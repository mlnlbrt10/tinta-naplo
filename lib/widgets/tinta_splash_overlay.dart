import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Full-screen pure OLED `#000000` splash overlay displayed on frame 1 above
/// the root navigator.
///
/// Pixel-matches the native Android splash background (`#000000` + centered
/// ink icon) and keeps an organic 120fps breathing logo + ultra-thin (2px)
/// rounded progress bar active while session/cache restoration runs. Once
/// [isLoading] becomes `false`, dissolves seamlessly over 450ms
/// (`Curves.easeOutCubic`) with a subtle `1.0 -> 1.05` scale-up.
class TintaSplashOverlay extends StatefulWidget {
  final bool isLoading;
  final Color? accentColor;
  final VoidCallback? onDismissed;

  const TintaSplashOverlay({
    super.key,
    required this.isLoading,
    this.accentColor,
    this.onDismissed,
  });

  @override
  State<TintaSplashOverlay> createState() => _TintaSplashOverlayState();
}

class _TintaSplashOverlayState extends State<TintaSplashOverlay>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _exitDuration = Duration(milliseconds: 450);

  late final AnimationController _breathController;
  late final Animation<double> _breathCurve;
  late final AnimationController _progressController;
  late final AnimationController _exitController;
  late final Animation<double> _exitFade;
  late final Animation<double> _exitScale;

  bool _isExiting = false;
  bool _dismissNotified = false;
  bool _logoPrecached = false;
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _breathCurve = CurvedAnimation(
      parent: _breathController,
      curve: Curves.easeInOutSine,
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );

    _exitController = AnimationController(
      vsync: this,
      duration: _exitDuration,
    );
    final curvedExit = CurvedAnimation(
      parent: _exitController,
      curve: Curves.easeOutCubic,
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(curvedExit);
    _exitScale = Tween<double>(begin: 1.0, end: 1.04).animate(curvedExit);

    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_dismissNotified) {
        _dismissNotified = true;
        _breathController.stop();
        _progressController.stop();
        widget.onDismissed?.call();
      }
    });

    if (!widget.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _beginExit();
      });
    }
  }

  void _syncAmbientTickers() {
    if (!mounted) return;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final appActive =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    if (!_isExiting && tickerEnabled && appActive) {
      if (!_breathController.isAnimating) {
        _breathController.repeat(reverse: true);
      }
      if (!_progressController.isAnimating) {
        _progressController.repeat();
      }
    } else {
      if (_breathController.isAnimating) {
        _breathController.stop(canceled: false);
      }
      if (_isExiting && _progressController.isAnimating) {
        _progressController.stop(canceled: false);
      } else if (!tickerEnabled || !appActive) {
        _progressController.stop(canceled: false);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_logoPrecached) {
      _logoPrecached = true;
      precacheImage(const AssetImage('assets/images/tinta_icon.png'), context);
    }
    _syncAmbientTickers();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncAmbientTickers();
  }

  @override
  void didUpdateWidget(covariant TintaSplashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLoading && !_isExiting) {
      _beginExit();
    }
  }

  void _beginExit() {
    if (_isExiting) return;
    setState(() => _isExiting = true);
    _breathController.stop();
    _exitController.forward();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _breathController.dispose();
    _progressController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Theme.of(context).colorScheme.primary;
    final barColor = Color.lerp(Colors.white, accent, 0.32)!;

    return IgnorePointer(
      ignoring: !widget.isLoading || _isExiting,
      child: RepaintBoundary(
        child: FadeTransition(
          opacity: _exitFade,
          child: ScaleTransition(
            scale: _exitScale,
            child: ColoredBox(
              color: const Color(0xFF000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _breathCurve,
                      builder: (context, child) {
                        final t = _breathCurve.value;
                        final logoScale = lerpDouble(1.0, 1.045, t) ?? 1.0;
                        final glowAlpha = lerpDouble(0.05, 0.16, t) ?? 0.08;
                        return Transform.scale(
                          scale: logoScale,
                          child: SizedBox(
                            width: 192,
                            height: 192,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        barColor.withValues(alpha: glowAlpha),
                                        Colors.white
                                            .withValues(alpha: glowAlpha * 0.45),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.55, 1.0],
                                    ),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                                child!,
                              ],
                            ),
                          ),
                        );
                      },
                      child: RepaintBoundary(
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (rect) => const RadialGradient(
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.89, 0.99],
                          ).createShader(rect),
                          child: Image.asset(
                            'assets/images/tinta_icon.png',
                            width: 192,
                            height: 192,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      opacity: _isExiting ? 0.0 : 1.0,
                      child: _UltraThinSplashProgressBar(
                        controller: _progressController,
                        color: barColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UltraThinSplashProgressBar extends StatelessWidget {
  final AnimationController controller;
  final Color color;

  const _UltraThinSplashProgressBar({
    required this.controller,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const double trackWidth = 112.0;
    const double indicatorWidth = 42.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: trackWidth,
        height: 2.0,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
          ),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final raw = controller.value;
              final eased = Curves.easeInOutCubic.transform(raw);
              final left =
                  lerpDouble(-indicatorWidth, trackWidth, eased) ?? 0.0;
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    top: 0,
                    bottom: 0,
                    width: indicatorWidth,
                    child: child!,
                  ),
                ],
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.15),
                    color.withValues(alpha: 0.92),
                    color.withValues(alpha: 0.15),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
