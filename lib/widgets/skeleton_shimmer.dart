import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import 'glass_card.dart';

/// Shared dark-glass skeleton shimmer placeholder matching the exact `Főoldal`
/// hero lesson card, filter chip bar, and circular-badge activity feed cards.
class HomeSkeletonFeed extends StatefulWidget {
  final UserProfilePrefs prefs;

  const HomeSkeletonFeed({
    super.key,
    required this.prefs,
  });

  @override
  State<HomeSkeletonFeed> createState() => _HomeSkeletonFeedState();
}

class _HomeSkeletonFeedState extends State<HomeSkeletonFeed>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _shimmerController;
  AppLifecycleState? _lifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    WidgetsBinding.instance.addObserver(this);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
  }

  void _syncTicker() {
    if (!mounted) return;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final appActive =
        _lifecycleState == null || _lifecycleState == AppLifecycleState.resumed;
    final shouldAnimate = tickerEnabled && routeIsCurrent && appActive;
    if (shouldAnimate && !_shimmerController.isAnimating) {
      _shimmerController.repeat();
    } else if (!shouldAnimate && _shimmerController.isAnimating) {
      _shimmerController.stop(canceled: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _syncTicker();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark ||
        widget.prefs.themeStyle != AppThemeStyle.light;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          final sweep = Curves.easeInOutSine.transform(_shimmerController.value);
          return ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 116),
            children: [
              // Next lesson hero skeleton matching SoftGlassCard(padding: 20)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SoftGlassCard(
                  prefs: widget.prefs,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _bone(
                            width: 52,
                            height: 52,
                            borderRadius: OledTheme.badgeRadius,
                            isDark: isDark,
                            sweep: sweep,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _bone(
                                  width: 168,
                                  height: 18,
                                  isDark: isDark,
                                  sweep: sweep,
                                ),
                                const SizedBox(height: 8),
                                _bone(
                                  width: 122,
                                  height: 13,
                                  isDark: isDark,
                                  sweep: sweep,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _bone(
                        width: double.infinity,
                        height: 36,
                        borderRadius: BorderRadius.circular(22),
                        isDark: isDark,
                        sweep: sweep,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Filter chip bar skeleton matching ActivityFeedFilter strip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _bone(
                      width: 74,
                      height: 36,
                      borderRadius: BorderRadius.circular(22),
                      isDark: isDark,
                      sweep: sweep,
                    ),
                    const SizedBox(width: 8),
                    _bone(
                      width: 76,
                      height: 36,
                      borderRadius: BorderRadius.circular(22),
                      isDark: isDark,
                      sweep: sweep,
                    ),
                    const SizedBox(width: 8),
                    _bone(
                      width: 72,
                      height: 36,
                      borderRadius: BorderRadius.circular(22),
                      isDark: isDark,
                      sweep: sweep,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _bone(
                        width: double.infinity,
                        height: 36,
                        borderRadius: BorderRadius.circular(22),
                        isDark: isDark,
                        sweep: sweep,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                      child: Row(
                        children: [
                          _bone(
                            width: 44,
                            height: 15,
                            isDark: isDark,
                            sweep: sweep,
                          ),
                          const SizedBox(width: 8),
                          _bone(
                            width: 58,
                            height: 12,
                            isDark: isDark,
                            sweep: sweep,
                          ),
                          const Spacer(),
                          _bone(
                            width: 24,
                            height: 20,
                            borderRadius: BorderRadius.circular(999),
                            isDark: isDark,
                            sweep: sweep,
                          ),
                        ],
                      ),
                    ),
                    for (int i = 0; i < 4; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SoftGlassCard(
                          prefs: widget.prefs,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 10,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          child: Row(
                            children: [
                              _bone(
                                width: 38,
                                height: 38,
                                isCircle: true,
                                isDark: isDark,
                                sweep: sweep,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _bone(
                                          width: i.isEven ? 132 : 108,
                                          height: 13.5,
                                          isDark: isDark,
                                          sweep: sweep,
                                        ),
                                        const Spacer(),
                                        _bone(
                                          width: 42,
                                          height: 11,
                                          isDark: isDark,
                                          sweep: sweep,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    _bone(
                                      width: i.isEven ? 186 : 154,
                                      height: 12,
                                      isDark: isDark,
                                      sweep: sweep,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bone({
    required double width,
    required double height,
    required bool isDark,
    required double sweep,
    BorderRadius? borderRadius,
    bool isCircle = false,
  }) {
    final baseColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.12);
    final beginX = -1.4 + sweep * 2.8;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : (borderRadius ?? BorderRadius.circular(8)),
        gradient: LinearGradient(
          begin: Alignment(beginX - 0.6, -0.2),
          end: Alignment(beginX + 0.6, 0.2),
          colors: [baseColor, highlightColor, baseColor],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}
