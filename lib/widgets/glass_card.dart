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
  final skin = prefs?.customSkinConfig ?? UserProfilePrefs.activeCustomSkin;
  if (skin.enabled && skin.glassBlur != null) {
    return skin.glassBlur!;
  }
  return 10.0;
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
    final skin = effectivePrefs?.customSkinConfig ?? UserProfilePrefs.activeCustomSkin;
    final liquidGlassEnabled = resolveLiquidGlassEnabled(effectivePrefs);
    final effectiveRadius = (skin.enabled &&
            skin.cardRadius != null &&
            borderRadius.topLeft.x >= 16.0)
        ? BorderRadius.circular(skin.cardRadius!)
        : borderRadius;
    final effectiveBorderWidth = skin.enabled ? (skin.borderWidth ?? 1.0) : 1.0;
    final effectiveSolidColor = skin.enabled && skin.surface != null
        ? skin.surface!.withValues(alpha: skin.cardOpacity ?? 1.0)
        : solidColor;
    final resolvedSolidColor = highContrastExpanded && liquidGlassEnabled
        ? (effectiveSolidColor ??
            (isDark
                ? const Color(0xF5141820)
                : Colors.white.withValues(alpha: 0.97)))
        : (effectiveSolidColor ?? scheme.surfaceContainerHigh).withValues(alpha: 1.0);
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
            color: (skin.enabled && skin.borderColor != null)
                ? skin.borderColor!
                : (liquidGlassEnabled
                    ? Colors.white.withValues(alpha: isDark ? 0.14 : 0.24)
                    : scheme.outlineVariant),
            width: effectiveBorderWidth,
          );
      final solidBox = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: resolvedSolidColor,
          borderRadius: effectiveRadius,
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
    } else if (skin.enabled && skin.surface != null) {
      final op = skin.cardOpacity ?? 0.85;
      topTint = skin.surface!.withValues(alpha: (0.45 * op).clamp(0.05, 0.9));
      bottomTint = skin.surface!.withValues(alpha: (0.28 * op).clamp(0.03, 0.85));
    } else {
      // Crystal-clear optical glass: near-zero dark tint with zero white haze
      // so the wallpaper or underlying UI shines cleanly through the blur.
      topTint = Colors.black.withValues(alpha: isDark ? 0.06 : 0.02);
      bottomTint = Colors.transparent;
    }

    final specularBorder = border ??
        Border.all(
          color: (skin.enabled && skin.borderColor != null)
              ? skin.borderColor!
              : Colors.white.withValues(alpha: isDark ? 0.14 : 0.24),
          width: effectiveBorderWidth,
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
                child: RepaintBoundary(
                  child: ClipRRect(
                    borderRadius: effectiveRadius,
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
                          borderRadius: effectiveRadius,
                          border: animBorder,
                        ),
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
        glassContent = RepaintBoundary(
          child: ClipRRect(
            borderRadius: effectiveRadius,
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
                  borderRadius: effectiveRadius,
                  border: animBorder,
                ),
                child: innerChild,
              ),
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
          borderRadius: effectiveRadius,
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

/// High-performance GPU-friendly Liquid Glass card surface using a multi-stop
/// translucent gradient, subtle top specular highlight, and [RepaintBoundary]
/// isolation (avoiding expensive per-item `BackdropFilter` offscreen `saveLayer`
/// passes inside scrollable lists for steady 120Hz scrolling).
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
    final skin = activePrefs.customSkinConfig;
    final effectiveRadius = (skin.enabled &&
            skin.cardRadius != null &&
            borderRadius.topLeft.x >= 16.0)
        ? BorderRadius.circular(skin.cardRadius!)
        : borderRadius;
    final effectiveBorderWidth = skin.enabled ? (skin.borderWidth ?? 1.0) : 1.0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activePreset = BackgroundPresetInfo.resolve(activePrefs);
    final hasStudioOrCustomBackdrop = activePrefs.hasAnimatedBackdrop ||
        activePrefs.hasCustomBackdrop ||
        activePreset.id != 'pure_oled';
    final contrast = AdaptiveContrastTokens.resolve(activePrefs);
    final resolvedBorderColor = borderColor ??
        (skin.enabled && skin.borderColor != null
            ? skin.borderColor!
            : (hasStudioOrCustomBackdrop
                ? contrast.cardBorder
                : scheme.outlineVariant));
    final borderSide = border ??
        Border.all(color: resolvedBorderColor, width: effectiveBorderWidth);
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
      final baseSolid = (skin.enabled && skin.surface != null)
          ? (color ?? skin.surface!).withValues(alpha: skin.cardOpacity ?? 1.0)
          : (hasStudioOrCustomBackdrop
              ? (color ?? contrast.cardFill.withValues(alpha: 0.94))
              : (color ?? scheme.surfaceContainer).withValues(alpha: 1.0));
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: baseSolid,
            borderRadius: effectiveRadius,
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
              (skin.enabled && skin.borderColor != null
                  ? skin.borderColor!
                  : (hasStudioOrCustomBackdrop
                      ? contrast.cardBorder
                      : Colors.white.withValues(alpha: isDark ? 0.14 : 0.34))),
          width: effectiveBorderWidth,
        );

    if (isExpanded) {
      final expandedFill = (skin.enabled && skin.surface != null)
          ? (color ?? skin.surface!).withValues(alpha: skin.cardOpacity ?? 0.95)
          : (hasStudioOrCustomBackdrop
              ? (color ?? contrast.cardFill.withValues(alpha: 0.95))
              : (color ?? scheme.surfaceContainerHigh).withValues(alpha: 0.96));
      return RepaintBoundary(
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: expandedFill,
            borderRadius: effectiveRadius,
            border: glassBorder,
          ),
          child: contentChild,
        ),
      );
    }

    final opacityScale = (skin.enabled && skin.cardOpacity != null)
        ? skin.cardOpacity!.clamp(0.15, 1.0)
        : activePrefs.cardOpacity.clamp(0.55, 0.95);
    final surfaceBase = color ??
        (skin.enabled && skin.surface != null
            ? skin.surface!
            : (isDark ? const Color(0xFF141820) : Colors.white));
    final Color topHighlightStop;
    final Color midBodyStop;
    final Color bottomDepthStop;
    if (color != null) {
      topHighlightStop = Color.alphaBlend(
        Colors.white.withValues(alpha: isDark ? 0.08 : 0.22),
        color!.withValues(alpha: (color!.a * opacityScale).clamp(0.28, 0.86)),
      );
      midBodyStop = color!.withValues(
        alpha: (color!.a * opacityScale * 0.88).clamp(0.22, 0.78),
      );
      bottomDepthStop = color!.withValues(
        alpha: (color!.a * opacityScale * 0.94).clamp(0.26, 0.84),
      );
    } else if (hasStudioOrCustomBackdrop) {
      if (contrast.isLightBackdrop) {
        topHighlightStop = Colors.white.withValues(alpha: 0.72 * opacityScale);
        midBodyStop = Colors.white.withValues(alpha: 0.54 * opacityScale);
        bottomDepthStop = const Color(0xFFF1F5F9).withValues(
          alpha: 0.62 * opacityScale,
        );
      } else {
        topHighlightStop = Colors.white.withValues(alpha: 0.13 * opacityScale);
        midBodyStop = const Color(0xFF141820).withValues(
          alpha: 0.56 * opacityScale,
        );
        bottomDepthStop = const Color(0xFF0C0F16).withValues(
          alpha: 0.68 * opacityScale,
        );
      }
    } else if (isDark) {
      topHighlightStop = Colors.white.withValues(alpha: 0.095 * opacityScale);
      midBodyStop = surfaceBase.withValues(alpha: 0.44 * opacityScale);
      bottomDepthStop = const Color(0xFF0A0D13).withValues(
        alpha: 0.56 * opacityScale,
      );
    } else {
      topHighlightStop = Colors.white.withValues(alpha: 0.82 * opacityScale);
      midBodyStop = scheme.surfaceContainerHigh.withValues(
        alpha: 0.56 * opacityScale,
      );
      bottomDepthStop = scheme.surfaceContainer.withValues(
        alpha: 0.66 * opacityScale,
      );
    }

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.35, 1.0],
              colors: [topHighlightStop, midBodyStop, bottomDepthStop],
            ),
            borderRadius: effectiveRadius,
            border: glassBorder,
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: effectiveRadius,
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: isDark ? 0.22 : 0.62),
                width: 0.85,
              ),
            ),
          ),
          child: contentChild,
        ),
      ),
    );
  }
}

/// Animated luminous ambient aura glow rendered around newly arrived ("first-seen")
/// grade cards and subject tiles before auto-dismissing once inspected.
class GradeFirstSeenGlow extends StatelessWidget {
  final bool isGlowing;
  final Color accentColor;
  final BorderRadius borderRadius;
  final Widget child;

  const GradeFirstSeenGlow({
    super.key,
    required this.isGlowing,
    required this.accentColor,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(
          color: isGlowing
              ? accentColor.withValues(alpha: isDark ? 0.45 : 0.38)
              : Colors.transparent,
          width: isGlowing ? 1.0 : 0.0,
        ),
        boxShadow: isGlowing
            ? [
                BoxShadow(
                  color: accentColor.withValues(alpha: isDark ? 0.44 : 0.35),
                  blurRadius: 18,
                  spreadRadius: 1.0,
                ),
                BoxShadow(
                  color: accentColor.withValues(alpha: isDark ? 0.36 : 0.26),
                  blurRadius: 26,
                  spreadRadius: 2.0,
                ),
              ]
            : const [],
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: borderRadius,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  opacity: isGlowing ? 1.0 : 0.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.centerLeft,
                        radius: 1.25,
                        colors: [
                          accentColor.withValues(alpha: isDark ? 0.18 : 0.11),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
