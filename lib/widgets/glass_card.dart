import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';

/// Card container that optionally renders as a 120fps hardware-accelerated
/// semi-transparent frosted glass surface (`Kártyák soft blur & áttetszőség`)
/// without per-item `BackdropFilter` shader overhead inside scrolling lists.
class SoftGlassCard extends StatelessWidget {
  final UserProfilePrefs prefs;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;
  final BoxBorder? border;

  const SoftGlassCard({
    super.key,
    required this.prefs,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor =
        color ?? theme.cardTheme.color ?? theme.colorScheme.surface;
    final borderSide = border ?? Border.all(color: theme.dividerColor);

    if (!prefs.cardBlurEnabled) {
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: borderRadius,
            border: borderSide,
          ),
          child: child,
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    final userOpacity = (prefs.cardOpacity >= 0.85
            ? 0.44
            : (prefs.cardOpacity * 0.62))
        .clamp(0.35, 0.55);
    final glassBorder = border ??
        Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.36),
          width: 1.0,
        );
    final topSheen = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.06 : 0.18),
      surfaceColor,
    ).withValues(alpha: userOpacity);
    final bottomTint = surfaceColor.withValues(alpha: userOpacity);

    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: userOpacity),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [topSheen, bottomTint],
          ),
          borderRadius: borderRadius,
          border: glassBorder,
        ),
        child: child,
      ),
    );
  }
}
