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
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.color,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = color ?? theme.cardTheme.color ?? theme.colorScheme.surface;
    final borderSide = border ?? Border.all(color: theme.dividerColor);

    if (!prefs.cardBlurEnabled) {
      return Container(
        padding: padding,
        decoration: BoxDecoration(
          color: base,
          borderRadius: borderRadius,
          border: borderSide,
        ),
        child: child,
      );
    }

    final sigma = prefs.cardBlurSigma.clamp(2.0, 8.0);
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: base.withValues(alpha: prefs.cardOpacity.clamp(0.6, 1.0)),
            borderRadius: borderRadius,
            border: borderSide,
          ),
          child: child,
        ),
      ),
    );
  }
}
