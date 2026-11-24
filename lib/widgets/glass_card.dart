import 'dart:ui';

import 'package:flutter/material.dart';

import '../providers/app_providers.dart';
import '../services/token_storage_service.dart';
import '../theme/oled_theme.dart';
import '../utils/platform_support.dart';
import 'real_liquid_glass_surface.dart';

/// Backwards-compatible alias for [SoftGlassCard].
typedef GlassCard = SoftGlassCard;

/// Resolves whether Settings "Liquid Glass" is active and enables glassmorphic
/// `BackdropFilter` surfaces and fluid droplet slider physics.
bool resolveLiquidGlassEnabled([UserProfilePrefs? prefs]) {
  if (isIOSPlatform) return true;
  if (prefs != null) {
    final effective = prefs.effectiveForPlatform();
    return effective.liquidGlassEnabled || effective.realLiquidGlassEnabled;
  }
  return UserProfilePrefs.activeLiquidGlassEnabled ||
      UserProfilePrefs.activeRealLiquidGlassEnabled;
}

/// Resolves whether the experimental Android GLSL optical shader "Real Liquid
/// Glass" rendering mode is active. Strictly `false` on iOS so iOS retains its
/// locked native Liquid Glass setup.
bool resolveRealLiquidGlassEnabled([UserProfilePrefs? prefs]) {
  if (isIOSPlatform) return false;
  if (prefs != null) {
    return prefs.effectiveForPlatform().realLiquidGlassEnabled;
  }
  return UserProfilePrefs.activeRealLiquidGlassEnabled;
}

/// Backwards-compatible alias for [resolveLiquidGlassEnabled].
bool resolveSoftBlurEnabled([UserProfilePrefs? prefs]) =>
    resolveLiquidGlassEnabled(prefs);

double resolveSoftBlurBackdropSigma([UserProfilePrefs? prefs]) {
  if (isIOSPlatform) return 10.0;
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
  double glassDarkAlpha = 0.30,
  double glassLightAlpha = 0.20,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (resolveLiquidGlassEnabled(prefs)) {
    return Colors.black.withValues(
      alpha: isDark ? glassDarkAlpha : glassLightAlpha,
    );
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
    final realLiquidGlassEnabled = resolveRealLiquidGlassEnabled(effectivePrefs);
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
        : (effectiveSolidColor ??
                (!isDark && isDockStyle
                    ? Colors.white
                    : scheme.surfaceContainerHigh))
            .withValues(alpha: 1.0);
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

    if (realLiquidGlassEnabled) {
      return RealLiquidGlassSurface(
        prefs: effectivePrefs,
        borderRadius: effectiveRadius,
        padding: padding,
        tintColor: glassTintColor ??
            (highContrastExpanded ? effectiveSolidColor : null) ??
            (skin.enabled && skin.surface != null ? skin.surface : null),
        border: border,
        boxShadow: boxShadow,
        isDockStyle: isDockStyle,
        compactOptics: isDockStyle,
        highContrast: highContrastExpanded && !isDockStyle,
        contentOpacityAnimation: contentOpacityAnimation,
        child: rawContent,
      );
    }

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
    } else if (isDark) {
      // Crystal-clear optical glass on dark: near-zero dark tint so the
      // wallpaper or underlying UI shines cleanly through the blur.
      topTint = Colors.black.withValues(alpha: 0.06);
      bottomTint = Colors.transparent;
    } else {
      topTint = Colors.white.withValues(alpha: isDockStyle ? 0.88 : 0.84);
      bottomTint =
          const Color(0xFFF8FAFC).withValues(alpha: isDockStyle ? 0.80 : 0.78);
    }

    final specularBorder = border ??
        Border.all(
          color: (skin.enabled && skin.borderColor != null)
              ? skin.borderColor!
              : (isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.07)),
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
      transitionDuration: const Duration(milliseconds: 295),
      reverseTransitionDuration: const Duration(milliseconds: 240),
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
          reverseCurve: Curves.easeInBack,
        );
        final bottomInset = MediaQuery.viewInsetsOf(dialogContext).bottom;
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(bottom: bottomInset),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(scaleCurved),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.03),
                end: Offset.zero,
              ).animate(fadeCurved),
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight:
                        (MediaQuery.sizeOf(dialogContext).height - bottomInset) *
                            0.88,
                  ),
                  child: LiquidGlassSurface(
                    prefs: prefs,
                    borderRadius: borderRadius,
                    padding: contentPadding,
                    highContrastExpanded: true,
                    contentOpacityAnimation: fadeCurved,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.34 : 0.14),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    child: builder(dialogContext),
                  ),
                ),
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
    final BorderRadius effectiveRadius;
    if (skin.enabled &&
        skin.cardRadius != null &&
        borderRadius.topLeft.x >= 16.0) {
      effectiveRadius = BorderRadius.circular(skin.cardRadius!);
    } else {
      effectiveRadius = borderRadius;
    }
    final effectiveBorderWidth = skin.enabled ? (skin.borderWidth ?? 1.0) : 1.0;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
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

    if (resolveRealLiquidGlassEnabled(activePrefs) && !isExpanded) {
      final opacityScale = (skin.enabled && skin.cardOpacity != null)
          ? skin.cardOpacity!.clamp(0.0, 1.0)
          : activePrefs.cardOpacity.clamp(0.0, 1.0);
      final Color? resolvedTint = color ??
          (skin.enabled && skin.surface != null
              ? skin.surface!
              : (hasStudioOrCustomBackdrop ? contrast.cardFill : null));
      return RealLiquidGlassSurface(
        prefs: activePrefs,
        borderRadius: effectiveRadius,
        padding: padding,
        tintColor: resolvedTint,
        border: border ??
            (skin.enabled && skin.borderColor != null
                ? Border.all(
                    color: skin.borderColor!,
                    width: effectiveBorderWidth,
                  )
                : null),
        opacityScale: opacityScale,
        boxShadow: !isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
        child: contentChild,
      );
    }

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
            boxShadow: !isDark
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: contentChild,
        ),
      );
    }

    final glassBorder = border ??
        Border.all(
          color: borderColor ??
              (skin.enabled && skin.borderColor != null
                  ? skin.borderColor!
                  : (hasStudioOrCustomBackdrop
                      ? contrast.cardBorder
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06)))),
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
        ? skin.cardOpacity!.clamp(0.0, 1.0)
        : activePrefs.cardOpacity.clamp(0.0, 1.0);
    final surfaceBase = color ??
        (skin.enabled && skin.surface != null
            ? skin.surface!
            : (isDark ? const Color(0xFF141820) : Colors.white));
    final subtleTintAlpha = isDark
        ? (0.14 + opacityScale * 0.70).clamp(0.14, 0.86)
        : (0.18 + opacityScale * 0.72).clamp(0.18, 0.92);

    final Widget readabilityProtectedContent = opacityScale < 0.35
        ? DefaultTextStyle.merge(
            style: TextStyle(
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.14),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: contentChild,
          )
        : contentChild;

    final Color topHighlightStop;
    final Color midBodyStop;
    final Color bottomDepthStop;
    if (color != null) {
      topHighlightStop = Color.alphaBlend(
        Colors.white.withValues(alpha: isDark ? 0.03 : 0.12),
        color!.withValues(alpha: (color!.a * subtleTintAlpha).clamp(0.16, 0.88)),
      );
      midBodyStop = color!.withValues(
        alpha: (color!.a * subtleTintAlpha * 0.90).clamp(0.14, 0.82),
      );
      bottomDepthStop = color!.withValues(
        alpha: (color!.a * subtleTintAlpha * 0.96).clamp(0.16, 0.86),
      );
    } else if (hasStudioOrCustomBackdrop) {
      if (contrast.isLightBackdrop) {
        topHighlightStop = Colors.white.withValues(
          alpha: (0.16 + 0.56 * opacityScale).clamp(0.16, 0.76),
        );
        midBodyStop = Colors.white.withValues(
          alpha: (0.14 + 0.44 * opacityScale).clamp(0.14, 0.64),
        );
        bottomDepthStop = const Color(0xFFF1F5F9).withValues(
          alpha: (0.16 + 0.50 * opacityScale).clamp(0.16, 0.70),
        );
      } else {
        topHighlightStop = const Color(0xFF141923).withValues(
          alpha: (0.18 + 0.56 * opacityScale).clamp(0.18, 0.76),
        );
        midBodyStop = const Color(0xFF10141C).withValues(
          alpha: (0.20 + 0.58 * opacityScale).clamp(0.20, 0.80),
        );
        bottomDepthStop = const Color(0xFF0A0D13).withValues(
          alpha: (0.24 + 0.62 * opacityScale).clamp(0.24, 0.88),
        );
      }
    } else if (isDark) {
      topHighlightStop = Color.alphaBlend(
        Colors.white.withValues(alpha: 0.025),
        surfaceBase.withValues(
          alpha: (0.16 + opacityScale * 0.54).clamp(0.16, 0.72),
        ),
      );
      midBodyStop = surfaceBase.withValues(
        alpha: (0.18 + opacityScale * 0.56).clamp(0.18, 0.76),
      );
      bottomDepthStop = const Color(0xFF090C11).withValues(
        alpha: (0.22 + opacityScale * 0.62).clamp(0.22, 0.86),
      );
    } else {
      topHighlightStop = Colors.white.withValues(
        alpha: (0.80 + 0.10 * opacityScale).clamp(0.80, 0.90),
      );
      midBodyStop = Colors.white.withValues(
        alpha: (0.76 + 0.12 * opacityScale).clamp(0.76, 0.88),
      );
      bottomDepthStop = const Color(0xFFF8FAFC).withValues(
        alpha: (0.78 + 0.10 * opacityScale).clamp(0.78, 0.88),
      );
    }

    final glassCard = ClipRRect(
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
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.65),
              width: 0.85,
            ),
          ),
        ),
        child: readabilityProtectedContent,
      ),
    );

    if (!isDark) {
      return RepaintBoundary(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: effectiveRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: glassCard,
        ),
      );
    }

    return RepaintBoundary(child: glassCard);
  }
}

/// Subtle highlighted edge indicator rendered on newly arrived ("first-seen")
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
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: borderRadius,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                opacity: isGlowing ? 1.0 : 0.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: accentColor.withValues(alpha: isDark ? 0.65 : 0.55),
                      width: 1.35,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        accentColor.withValues(alpha: isDark ? 0.16 : 0.10),
                        accentColor.withValues(alpha: isDark ? 0.04 : 0.02),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 7, left: 7),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
