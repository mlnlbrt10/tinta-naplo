import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';

/// Resolves whether Settings "Soft Blur" (`Kártyák soft blur & áttetszőség`)
/// is active and returns its normalized sigma for `BackdropFilter` surfaces.
bool resolveSoftBlurEnabled([UserProfilePrefs? prefs]) {
  return prefs?.cardBlurEnabled ?? UserProfilePrefs.activeSoftBlurEnabled;
}

double resolveSoftBlurBackdropSigma([UserProfilePrefs? prefs]) {
  final raw = prefs?.cardBlurSigma ?? UserProfilePrefs.activeSoftBlurSigma;
  return (12.0 + raw * 2.0).clamp(12.0, 20.0);
}

/// Returns a lighter scrim behind frosted glass modals and dialogs when Soft
/// Blur is enabled so blurred underlying content shines cleanly through.
Color resolveSoftBlurBarrierColor(
  BuildContext context, {
  UserProfilePrefs? prefs,
  double solidDarkAlpha = 0.56,
  double solidLightAlpha = 0.34,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (resolveSoftBlurEnabled(prefs)) {
    return Colors.black.withValues(alpha: isDark ? 0.30 : 0.20);
  }
  return Colors.black.withValues(
    alpha: isDark ? solidDarkAlpha : solidLightAlpha,
  );
}

/// Liquid frosted glass container matching the floating bottom tab bar's
/// `BackdropFilter` + translucent tint + 1px specular border when Settings
/// Soft Blur is ON, falling back cleanly to a solid/opaque elevated surface
/// without `BackdropFilter` when Soft Blur is OFF.
class LiquidGlassSurface extends StatelessWidget {
  final UserProfilePrefs? prefs;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? solidColor;
  final Color? glassTintColor;
  final BoxBorder? border;
  final List<BoxShadow>? boxShadow;
  final bool isDockStyle;

  /// Optional animation that fades the interior content (and, in solid mode,
  /// the surface) WITHOUT wrapping `BackdropFilter` in an ancestor `Opacity`
  /// layer, ensuring frosted blur is active from frame 0 of route transitions.
  final Animation<double>? contentOpacityAnimation;

  const LiquidGlassSurface({
    super.key,
    this.prefs,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.solidColor,
    this.glassTintColor,
    this.border,
    this.boxShadow,
    this.isDockStyle = false,
    this.contentOpacityAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final softBlurEnabled = resolveSoftBlurEnabled(prefs);
    final resolvedSolidColor = solidColor ??
        theme.cardTheme.color ??
        (isDark ? const Color(0xFF161922) : Colors.white);
    final rawContent = Material(
      type: MaterialType.transparency,
      child: child,
    );
    final contentChild = contentOpacityAnimation != null
        ? FadeTransition(
            opacity: contentOpacityAnimation!,
            child: rawContent,
          )
        : rawContent;

    if (!softBlurEnabled) {
      final solidBox = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: resolvedSolidColor,
          borderRadius: borderRadius,
          border: border ?? Border.all(color: theme.dividerColor, width: 1.0),
          boxShadow: boxShadow,
        ),
        child: rawContent,
      );
      return RepaintBoundary(
        child: contentOpacityAnimation != null
            ? FadeTransition(
                opacity: contentOpacityAnimation!,
                child: solidBox,
              )
            : solidBox,
      );
    }

    final sigma = resolveSoftBlurBackdropSigma(prefs);

    late final Color topTint;
    late final Color bottomTint;
    if (glassTintColor != null) {
      topTint = glassTintColor!;
      bottomTint = glassTintColor!.withValues(
        alpha: (glassTintColor!.a * 0.55).clamp(0.0, 1.0),
      );
    } else {
      // Crystal-clear optical glass: near-zero dark tint with zero white haze
      // so the wallpaper or underlying UI shines cleanly through the blur.
      topTint = Colors.black.withValues(alpha: isDark ? 0.06 : 0.02);
      bottomTint = Colors.transparent;
    }

    final specularBorder = border ??
        Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.24),
          width: 1.0,
        );

    final glassContent = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [topTint, bottomTint],
            ),
            borderRadius: borderRadius,
            border: specularBorder,
          ),
          child: contentChild,
        ),
      ),
    );

    if (boxShadow == null || boxShadow!.isEmpty) {
      return RepaintBoundary(child: glassContent);
    }

    // Keep drop shadows strictly outside the translucent clip so they never
    // darken the glass interior beneath the blurred surface.
    final outerShadows = boxShadow!
        .map(
          (s) => BoxShadow(
            color: s.color,
            offset: s.offset,
            blurRadius: s.blurRadius,
            spreadRadius: s.spreadRadius,
            blurStyle: BlurStyle.outer,
          ),
        )
        .toList(growable: false);

    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: outerShadows,
        ),
        child: glassContent,
      ),
    );
  }
}

/// Dialog wrapper styled identically to [LiquidGlassSurface] when Settings Soft
/// Blur is active, or solid elevated surface when OFF.
Future<T?> showSoftBlurDialog<T>({
  required BuildContext context,
  UserProfilePrefs? prefs,
  bool barrierDismissible = true,
  Color? barrierColor,
  double maxWidth = 420,
  BorderRadius borderRadius = const BorderRadius.all(Radius.circular(28)),
  EdgeInsetsGeometry contentPadding = const EdgeInsets.fromLTRB(24, 22, 24, 20),
  required Widget Function(BuildContext dialogContext) builder,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ??
        resolveSoftBlurBarrierColor(
          context,
          prefs: prefs,
          solidDarkAlpha: 0.52,
          solidLightAlpha: 0.34,
        ),
    transitionDuration: const Duration(milliseconds: 260),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        child,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final fadeCurved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final scaleCurved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInOutCubic,
      );
      return ScaleTransition(
        scale: Tween<double>(begin: 0.90, end: 1.0).animate(scaleCurved),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: LiquidGlassSurface(
              prefs: prefs,
              borderRadius: borderRadius,
              padding: contentPadding,
              contentOpacityAnimation: fadeCurved,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
              child: builder(dialogContext),
            ),
          ),
        ),
      );
    },
  );
}

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
    final contentChild = Material(
      type: MaterialType.transparency,
      child: child,
    );

    if (!prefs.cardBlurEnabled) {
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: borderRadius,
            border: borderSide,
          ),
          child: contentChild,
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    final clearTint = isDark
        ? Colors.black.withValues(alpha: 0.18)
        : surfaceColor.withValues(
            alpha: (prefs.cardOpacity * 0.45).clamp(0.20, 0.36),
          );
    final glassBorder = border ??
        Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.28),
          width: 1.0,
        );

    return RepaintBoundary(
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: clearTint,
          borderRadius: borderRadius,
          border: glassBorder,
        ),
        child: contentChild,
      ),
    );
  }
}
