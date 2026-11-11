import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';

/// Card container that optionally renders as soft frosted glass
/// (`Kártyák soft blur & áttetszőség` setting): a lightweight
/// [BackdropFilter] with a tinted, translucent surface colour.
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
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: borderRadius,
          border: borderSide,
        ),
        child: child,
      );
    }

    final blurSigma = prefs.cardBlurSigma.clamp(2.0, 8.0);
    final cardOpacity = prefs.cardOpacity.clamp(0.60, 0.85);

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: cardOpacity),
            borderRadius: borderRadius,
            border: borderSide,
          ),
          child: child,
        ),
      ),
    );
  }
}
