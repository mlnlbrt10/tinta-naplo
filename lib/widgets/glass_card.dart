import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';

/// Resolves whether Settings "Liquid Glass" is active and enables glassmorphic
/// `BackdropFilter` surfaces and fluid droplet slider physics.
bool resolveLiquidGlassEnabled([UserProfilePrefs? prefs]) {
  return prefs?.liquidGlassEnabled ?? UserProfilePrefs.activeLiquidGlassEnabled;
}

/// Backwards-compatible alias for [resolveLiquidGlassEnabled].
bool resolveSoftBlurEnabled([UserProfilePrefs? prefs]) =>
    resolveLiquidGlassEnabled(prefs);

double resolveSoftBlurBackdropSigma([UserProfilePrefs? prefs]) {
  final raw = prefs?.cardBlurSigma ?? UserProfilePrefs.activeSoftBlurSigma;
  return (12.0 + raw * 2.0).clamp(12.0, 20.0);
}

/// Returns a lighter scrim behind frosted glass modals and dialogs when Liquid
/// Glass is enabled so blurred underlying content shines cleanly through.
Color resolveSoftBlurBarrierColor(
  BuildContext context, {
  UserProfilePrefs? prefs,
  double solidDarkAlpha = 0.56,
  double solidLightAlpha = 0.34,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (resolveLiquidGlassEnabled(prefs)) {
    return Colors.black.withValues(alpha: isDark ? 0.30 : 0.20);
  }
  return Colors.black.withValues(
    alpha: isDark ? solidDarkAlpha : solidLightAlpha,
  );
}

/// Liquid frosted glass container matching the floating bottom tab bar's
/// `BackdropFilter` + translucent tint + 1px specular border when Settings
/// Liquid Glass is ON, falling back cleanly to a solid opaque Material 3
/// elevated surface without `BackdropFilter` when OFF.
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

  /// When true, renders a crisp high-contrast solid surface without
  /// `BackdropFilter` even when Liquid Glass is active, preventing double-blur
  /// stacking on expanded modal/detail sheets above already-blurred cards.
  final bool highContrastExpanded;

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
    this.highContrastExpanded = false,
    this.contentOpacityAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final effectivePrefs =
        prefs ?? AppProvidersScope.maybeOf(context)?.settings.prefs;
    final liquidGlassEnabled = resolveLiquidGlassEnabled(effectivePrefs);
    final resolvedSolidColor = highContrastExpanded && liquidGlassEnabled
        ? (solidColor ??
            (isDark
                ? const Color(0xF5141820)
                : Colors.white.withValues(alpha: 0.97)))
        : (solidColor ?? scheme.surfaceContainerHigh).withValues(alpha: 1.0);
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

    if (!liquidGlassEnabled || (highContrastExpanded && !isDockStyle)) {
      final resolvedBorder = border ??
          Border.all(
            color: liquidGlassEnabled
                ? Colors.white.withValues(alpha: isDark ? 0.14 : 0.24)
                : scheme.outlineVariant,
            width: 1.0,
          );
      final solidBox = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: resolvedSolidColor,
          borderRadius: borderRadius,
          border: resolvedBorder,
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

    final maxSigma = resolveSoftBlurBackdropSigma(effectivePrefs);

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

    final baseOuterShadows = (boxShadow == null || boxShadow!.isEmpty)
        ? null
        : boxShadow!
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

    Widget buildFrostedSurface(double factor, Widget innerChild) {
      final t = factor.clamp(0.0, 1.0);
      final animatedSigma = maxSigma * t;
      final animTopTint = t >= 0.999
          ? topTint
          : topTint.withValues(alpha: topTint.a * t);
      final animBottomTint = t >= 0.999
          ? bottomTint
          : bottomTint.withValues(alpha: bottomTint.a * t);
      final animBorder = t >= 0.999
          ? specularBorder
          : _scaleBoxBorderAlpha(specularBorder, t);

      final Widget glassContent;
      if (isDockStyle) {
        // Keep the BackdropFilter blur clipped inside the rounded dock capsule
        // while allowing child liquid bubbles to overscroll past left/right ends.
        glassContent = Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ClipRRect(
                  borderRadius: borderRadius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(
                      sigmaX: animatedSigma,
                      sigmaY: animatedSigma,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [animTopTint, animBottomTint],
                        ),
                        borderRadius: borderRadius,
                        border: animBorder,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: padding,
              child: innerChild,
            ),
          ],
        );
      } else {
        glassContent = ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: animatedSigma,
              sigmaY: animatedSigma,
            ),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [animTopTint, animBottomTint],
                ),
                borderRadius: borderRadius,
                border: animBorder,
              ),
              child: innerChild,
            ),
          ),
        );
      }

      if (baseOuterShadows == null) {
        return glassContent;
      }

      // Keep drop shadows strictly outside the translucent clip so they never
      // darken the glass interior beneath the blurred surface.
      final outerShadows = t >= 0.999
          ? baseOuterShadows
          : baseOuterShadows
              .map(
                (s) => BoxShadow(
                  color: s.color.withValues(alpha: s.color.a * t),
                  offset: s.offset,
                  blurRadius: s.blurRadius,
                  spreadRadius: s.spreadRadius,
                  blurStyle: BlurStyle.outer,
                ),
              )
              .toList(growable: false);

      return Container(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: outerShadows,
        ),
        child: glassContent,
      );
    }

    if (contentOpacityAnimation == null) {
      return RepaintBoundary(child: buildFrostedSurface(1.0, rawContent));
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: contentOpacityAnimation!,
        child: contentChild,
        builder: (context, animatedChild) {
          return buildFrostedSurface(
            contentOpacityAnimation!.value,
            animatedChild!,
          );
        },
      ),
    );
  }

  static BoxBorder _scaleBoxBorderAlpha(BoxBorder boxBorder, double factor) {
    if (boxBorder is Border) {
      BorderSide scaleSide(BorderSide side) {
        if (side == BorderSide.none) return BorderSide.none;
        return side.copyWith(
          color: side.color.withValues(alpha: side.color.a * factor),
        );
      }

      return Border(
        top: scaleSide(boxBorder.top),
        right: scaleSide(boxBorder.right),
        bottom: scaleSide(boxBorder.bottom),
        left: scaleSide(boxBorder.left),
      );
    }
    return boxBorder;
  }
}

class _SoftBlurDialogRoute<T> extends RawDialogRoute<T> {
  final Duration _reverseTransitionDuration;

  _SoftBlurDialogRoute({
    required super.pageBuilder,
    super.barrierDismissible = true,
    super.barrierColor,
    super.barrierLabel,
    super.transitionDuration = const Duration(milliseconds: 250),
    Duration reverseTransitionDuration = const Duration(milliseconds: 230),
    super.transitionBuilder,
  }) : _reverseTransitionDuration = reverseTransitionDuration;

  @override
  Duration get reverseTransitionDuration => _reverseTransitionDuration;
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
  bool useRootNavigator = true,
  required Widget Function(BuildContext dialogContext) builder,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _SoftBlurDialogRoute<T>(
      barrierDismissible: barrierDismissible,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: barrierColor ??
          resolveSoftBlurBarrierColor(
            context,
            prefs: prefs,
            solidDarkAlpha: 0.52,
            solidLightAlpha: 0.34,
          ),
      transitionDuration: const Duration(milliseconds: 250),
      reverseTransitionDuration: const Duration(milliseconds: 230),
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
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(scaleCurved),
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
                highContrastExpanded: true,
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
    ),
  );
}

/// Card container rendering a frosted `BackdropFilter(sigmaX: 14, sigmaY: 14)`
/// surface clipped to [borderRadius] for collapsed cards when Liquid Glass is
/// active, high-contrast solid fills when [isExpanded] is true (avoiding
/// double-blur stacking), and zero-blur Material surfaces when OFF.
class SoftGlassCard extends StatelessWidget {
  final UserProfilePrefs prefs;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Color? color;
  final BoxBorder? border;
  final Color? borderColor;
  final bool isExpanded;

  const SoftGlassCard({
    super.key,
    required this.prefs,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.color,
    this.border,
    this.borderColor,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final activePrefs =
        AppProvidersScope.maybeOf(context)?.settings.prefs ?? prefs;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activePreset = BackgroundPresetInfo.resolve(activePrefs);
    final hasStudioOrCustomBackdrop = activePrefs.hasAnimatedBackdrop ||
        activePrefs.hasCustomBackdrop ||
        activePreset.id != 'pure_oled';
    final contrast = AdaptiveContrastTokens.resolve(activePrefs);
    final resolvedBorderColor = borderColor ??
        (hasStudioOrCustomBackdrop
            ? contrast.cardBorder
            : scheme.outlineVariant);
    final borderSide =
        border ?? Border.all(color: resolvedBorderColor, width: 1.0);
    final Widget themedChild = hasStudioOrCustomBackdrop
        ? DefaultTextStyle.merge(
            style: TextStyle(color: contrast.primaryText),
            child: IconTheme.merge(
              data: IconThemeData(color: contrast.iconColor),
              child: child,
            ),
          )
        : child;
    final contentChild = Material(
      type: MaterialType.transparency,
      child: themedChild,
    );

    if (!activePrefs.liquidGlassEnabled) {
      final baseSolid = hasStudioOrCustomBackdrop
          ? (color ?? contrast.cardFill.withValues(alpha: 0.94))
          : (color ?? scheme.surfaceContainer).withValues(alpha: 1.0);
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: baseSolid,
            borderRadius: borderRadius,
            border: borderSide,
          ),
          child: contentChild,
        ),
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    final glassBorder = border ??
        Border.all(
          color: borderColor ??
              (hasStudioOrCustomBackdrop
                  ? contrast.cardBorder
                  : Colors.white.withValues(alpha: isDark ? 0.14 : 0.28)),
          width: 1.0,
        );

    if (isExpanded) {
      final expandedFill = hasStudioOrCustomBackdrop
          ? (color ?? contrast.cardFill.withValues(alpha: 0.95))
          : (color ?? scheme.surfaceContainerHigh).withValues(alpha: 0.96);
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: expandedFill,
            borderRadius: borderRadius,
            border: glassBorder,
          ),
          child: contentChild,
        ),
      );
    }

    final surfaceColor =
        color ?? theme.cardTheme.color ?? scheme.surface;
    final clearTint = hasStudioOrCustomBackdrop
        ? (color ??
            (contrast.isLightBackdrop
                ? Colors.white.withValues(alpha: 0.56)
                : const Color(0xFF141820).withValues(alpha: 0.54)))
        : (isDark
            ? Colors.black.withValues(
                alpha: (activePrefs.cardOpacity * 0.42).clamp(0.18, 0.48),
              )
            : surfaceColor.withValues(
                alpha: (activePrefs.cardOpacity * 0.48).clamp(0.24, 0.46),
              ));

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14.0, sigmaY: 14.0),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: clearTint,
              borderRadius: borderRadius,
              border: glassBorder,
            ),
            child: contentChild,
          ),
        ),
      ),
    );
  }
}
