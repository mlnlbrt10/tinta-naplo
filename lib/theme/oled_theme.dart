import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/token_storage_service.dart';
import '../utils/platform_support.dart';
import '../widgets/animation_helpers.dart';

/// Architectural studio and vector backdrop presets supported in Tinta Napló.
class BackgroundPresetInfo {
  final String id;
  final String label;
  final IconData icon;
  final List<Color> gradientColors;
  final bool isVectorContour;

  const BackgroundPresetInfo({
    required this.id,
    required this.label,
    required this.icon,
    required this.gradientColors,
    this.isVectorContour = false,
  });

  static const List<BackgroundPresetInfo> presets = [
    BackgroundPresetInfo(
      id: 'pure_oled',
      label: 'OLED Fekete (Pure Black)',
      icon: Icons.contrast_rounded,
      gradientColors: [Colors.black, Colors.black],
    ),
    BackgroundPresetInfo(
      id: 'nordic_slate',
      label: 'Nordic Slate',
      icon: Icons.layers_rounded,
      gradientColors: [Color(0xFF0F131A), Color(0xFF181F2A)],
    ),
    BackgroundPresetInfo(
      id: 'warm_alabaster',
      label: 'Warm Alabaster',
      icon: Icons.light_mode_outlined,
      gradientColors: [Color(0xFFF4F1EA), Color(0xFFE8E2D5)],
    ),
    BackgroundPresetInfo(
      id: 'topographic_contour',
      label: 'Topographic Contour',
      icon: Icons.terrain_rounded,
      gradientColors: [Color(0xFF0B0E14), Color(0xFF10151F)],
      isVectorContour: true,
    ),
    BackgroundPresetInfo(
      id: 'brushed_titanium',
      label: 'Brushed Titanium',
      icon: Icons.blur_linear_rounded,
      gradientColors: [Color(0xFF17191D), Color(0xFF242830)],
    ),
    BackgroundPresetInfo(
      id: 'monolith_mesh',
      label: 'Monolith Mesh',
      icon: Icons.grain_rounded,
      gradientColors: [
        Color(0xFF0D0F14),
        Color(0xFF241C18),
        Color(0xFF16202A),
      ],
    ),
    BackgroundPresetInfo(
      id: 'solarized_dusk',
      label: 'Solarized Dusk',
      icon: Icons.wb_twilight_rounded,
      gradientColors: [
        Color(0xFF3A2018),
        Color(0xFF241620),
        Color(0xFF14111D),
      ],
    ),
  ];

  static const List<BackgroundPresetInfo> _legacyAliases = [
    BackgroundPresetInfo(
      id: 'brand_navy',
      label: 'Mély Ciánkék',
      icon: Icons.water_drop_rounded,
      gradientColors: [Color(0xFF0B1E28), Color(0xFF0B1E28)],
    ),
    BackgroundPresetInfo(
      id: 'midnight_aurora',
      label: 'Éjszakai Aurora',
      icon: Icons.auto_awesome_rounded,
      gradientColors: [Color(0xFF071324), Color(0xFF000000), Color(0xFF091A18)],
    ),
    BackgroundPresetInfo(
      id: 'cyber_violet',
      label: 'Cyber Ibolya',
      icon: Icons.blur_on_rounded,
      gradientColors: [Color(0xFF190A26), Color(0xFF000000), Color(0xFF0B1528)],
    ),
    BackgroundPresetInfo(
      id: 'sunset_ember',
      label: 'Alkonyati Parázs',
      icon: Icons.wb_twilight_rounded,
      gradientColors: [Color(0xFF240E0B), Color(0xFF000000), Color(0xFF180B1E)],
    ),
    BackgroundPresetInfo(
      id: 'winter_frost',
      label: 'Téli Fagy',
      icon: Icons.ac_unit_rounded,
      gradientColors: [Color(0xFF0A1E29), Color(0xFF03080C), Color(0xFF0E2419)],
    ),
  ];

  double get perceptualLuminance {
    if (gradientColors.isEmpty) return 0.0;
    double sum = 0.0;
    for (final c in gradientColors) {
      sum += AdaptiveContrastTokens.computeColorLuminance(c);
    }
    return (sum / gradientColors.length).clamp(0.0, 1.0);
  }

  bool get isLightPreset => perceptualLuminance >= 0.45;

  static BackgroundPresetInfo resolve(UserProfilePrefs prefs) {
    if (prefs.christmasModeEnabled && prefs.backgroundPreset == 'pure_oled') {
      return _legacyAliases.firstWhere((p) => p.id == 'winter_frost');
    }
    for (final p in presets) {
      if (p.id == prefs.backgroundPreset) return p;
    }
    for (final p in _legacyAliases) {
      if (p.id == prefs.backgroundPreset) return p;
    }
    return presets.first;
  }
}

/// Automatic luminance-adaptive typography, icon, and frosted card tokens
/// ensuring >= 4.5:1 readability over any studio backdrop or user photo.
class AdaptiveContrastTokens {
  final double effectiveLuminance;
  final bool isLightBackdrop;
  final Color primaryText;
  final Color secondaryText;
  final Color iconColor;
  final Color cardFill;
  final Color cardBorder;

  const AdaptiveContrastTokens({
    required this.effectiveLuminance,
    required this.isLightBackdrop,
    required this.primaryText,
    required this.secondaryText,
    required this.iconColor,
    required this.cardFill,
    required this.cardBorder,
  });

  static double computeColorLuminance(Color c) =>
      (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b).clamp(0.0, 1.0);

  /// Computes average weighted perceptual luminance (`0.0..1.0`) from an image's
  /// bytes using a fast `32x32` decoded thumbnail via `dart:ui`.
  static Future<double> computeImageLuminance(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 32,
      targetHeight: 32,
    );
    ui.FrameInfo? frame;
    try {
      frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null || data.lengthInBytes < 4) return 0.15;
      final pixels = data.buffer.asUint8List();
      double sum = 0.0;
      int count = 0;
      for (int i = 0; i + 3 < pixels.length; i += 4) {
        final r = pixels[i] / 255.0;
        final g = pixels[i + 1] / 255.0;
        final b = pixels[i + 2] / 255.0;
        sum += (0.2126 * r + 0.7152 * g + 0.0722 * b);
        count++;
      }
      return count > 0 ? (sum / count).clamp(0.0, 1.0) : 0.15;
    } finally {
      frame?.image.dispose();
      codec.dispose();
    }
  }

  static double computeEffectiveLuminance(UserProfilePrefs prefs) {
    if (prefs.hasAnimatedBackdrop) {
      return prefs.animatedBackdropPreset.luminance;
    }
    if (prefs.hasCustomBackdrop) {
      return (prefs.customBackdropLuminance *
              (1.0 - prefs.customBackdropDim.clamp(0.0, 0.75)))
          .clamp(0.0, 1.0);
    }
    final preset = BackgroundPresetInfo.resolve(prefs);
    if (preset.id == 'pure_oled') {
      return prefs.themeStyle == AppThemeStyle.light ? 0.96 : 0.0;
    }
    return preset.perceptualLuminance;
  }

  static AdaptiveContrastTokens resolve(UserProfilePrefs prefs) {
    final lum = computeEffectiveLuminance(prefs);
    final isLight = lum >= 0.45;
    if (isLight) {
      return AdaptiveContrastTokens(
        effectiveLuminance: lum,
        isLightBackdrop: true,
        primaryText: const Color(0xFF101318),
        secondaryText: const Color(0xFF475467),
        iconColor: const Color(0xFF101318),
        cardFill: Colors.white.withValues(alpha: 0.78),
        cardBorder: Colors.black.withValues(alpha: 0.08),
      );
    }
    return AdaptiveContrastTokens(
      effectiveLuminance: lum,
      isLightBackdrop: false,
      primaryText: const Color(0xFFF5F7FA),
      secondaryText: const Color(0xFFB8C0CC),
      iconColor: const Color(0xFFF5F7FA),
      cardFill: const Color(0xFF141820).withValues(alpha: 0.72),
      cardBorder: Colors.white.withValues(alpha: 0.12),
    );
  }
}

/// Theme constants, multi-theme builder (OLED Pure Black, Standard Dark, Light),
/// Material 3 seed color presets, and grade badge colors.
class OledTheme {
  static const String defaultFontFamily = 'Inter';

  /// Capitalizes the first character of [text] (trimmed) if it is lowercase,
  /// preserving the rest of the string and full Hungarian diacritics.
  static String capitalizeFirst(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    final first = trimmed.substring(0, 1);
    final upperFirst = first.toUpperCase();
    if (first == upperFirst) return trimmed;
    return '$upperFirst${trimmed.substring(1)}';
  }

  static const Color pureBlack = Colors.black;
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF181818);
  static const Color borderSubtle = Color(0xFF262626);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color accentPrimary = Color(0xFF4DA3FF);
  static const Color uwuPastelPink = Color(0xFFFF94C2);
  static const Color uwuPastelLavender = Color(0xFFCE93D8);

  static const double cardRadiusVal = 24.0;
  static const double largeRadiusVal = 28.0;
  static const double badgeRadiusVal = 22.0;

  static final BorderRadius cardRadius = BorderRadius.circular(cardRadiusVal);
  static final BorderRadius largeRadius = BorderRadius.circular(largeRadiusVal);
  static final BorderRadius badgeRadius = BorderRadius.circular(badgeRadiusVal);

  /// Selectable 2D Material vector icons for the student profile avatar.
  static const List<IconData> avatarIcons = [
    Icons.person_rounded,
    Icons.school_rounded,
    Icons.bolt_rounded,
    Icons.code_rounded,
    Icons.rocket_launch_rounded,
    Icons.workspace_premium_rounded,
    Icons.music_note_rounded,
    Icons.sports_esports_rounded,
  ];

  /// Selectable accent/seed colors for M3 theme and profile avatar.
  static const List<Color> avatarColors = [
    Color(0xFF4DA3FF), // Electric Blue
    Color(0xFF2E7D32), // Emerald Green
    Color(0xFF9C27B0), // Amethyst Purple
    Color(0xFF00BFA5), // Cyber Teal
    Color(0xFFFF7043), // Coral Orange
    Color(0xFFEC407A), // Neon Rose
    Color(0xFFFFCA28), // Solar Amber
    Color(0xFF5C6BC0), // Indigo
  ];

  /// Returns high-contrast foreground color (`Colors.white` or deep slate)
  /// for text rendered on top of [background].
  static Color contrastTextFor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
          ? Colors.white
          : const Color(0xFF0F172A);

  /// Ensures inline text colored with [color] stays legible against a surface
  /// with [surfaceBrightness] (e.g. darkening bright pastel on light surfaces
  /// or lightening near-black on dark surfaces).
  static Color readableInlineColor(
    Color color,
    Brightness surfaceBrightness,
  ) {
    final lum = color.computeLuminance();
    if (surfaceBrightness == Brightness.light && lum > 0.42) {
      return Color.lerp(color, const Color(0xFF0F172A), 0.42)!;
    }
    if (surfaceBrightness == Brightness.dark && lum < 0.14) {
      return Color.lerp(color, Colors.white, 0.55)!;
    }
    return color;
  }

  /// Returns a deeper, richer saturation variant of [base] when rendered on
  /// Light Mode white cards so status/grade/exam badges stay crisp and legible.
  static Color semanticForeground(Color base, Brightness brightness) {
    if (brightness == Brightness.dark) return base;
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness((hsl.lightness * 0.72).clamp(0.24, 0.42))
        .withSaturation((hsl.saturation * 1.15).clamp(0.0, 1.0))
        .toColor();
  }

  static Color semanticBadgeBg(Color base, Brightness brightness) =>
      base.withValues(alpha: brightness == Brightness.dark ? 0.16 : 0.13);

  static Color semanticBadgeBorder(Color base, Brightness brightness) =>
      brightness == Brightness.dark
          ? base.withValues(alpha: 0.28)
          : semanticForeground(base, brightness).withValues(alpha: 0.26);

  /// Green foreground for excused (`Igazolt`) absences & late arrivals.
  static Color omissionExcusedColor(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFF10B981)
          : const Color(0xFF047857);

  /// Distinct orange foreground for unexcused / pending-excuse (`Igazolandó`) items.
  static Color omissionPendingOrangeColor(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFFF97316)
          : const Color(0xFFEA580C);

  /// Red foreground for finalized unexcused (`Igazolatlan`) items.
  static Color omissionUnexcusedRedColor(Brightness brightness) =>
      brightness == Brightness.dark
          ? const Color(0xFFEF4444)
          : const Color(0xFFDC2626);

  /// System status bar and navigation bar icon brightness matching [brightness].
  static SystemUiOverlayStyle systemOverlayStyleForBrightness(
    Brightness brightness,
  ) {
    if (brightness == Brightness.light) {
      return const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      );
    }
    return const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarContrastEnforced: false,
    );
  }

  /// Palette of selectable colors for customizing individual grade badges (1..5).
  static const List<Color> gradeColorPalette = [
    Color(0xFF2E7D32), // Classic Green (5)
    Color(0xFF00C853), // Vivid Mint
    Color(0xFF00897B), // Teal
    Color(0xFF1565C0), // Classic Blue (4)
    Color(0xFF4DA3FF), // Sky Blue
    Color(0xFF7B1FA2), // Royal Purple
    Color(0xFFF9A825), // Classic Amber (3)
    Color(0xFFFFB300), // Gold
    Color(0xFFEF6C00), // Classic Orange (2)
    Color(0xFFFF5722), // Deep Orange
    Color(0xFFC62828), // Classic Red (1)
    Color(0xFFE91E63), // Crimson Pink
  ];

  /// Default color-coded grade badge color:
  /// 5 = green, 4 = blue, 3 = amber, 2 = orange, 1 = red.
  static Color gradeColor(
    int? numericValue, [
    UserProfilePrefs? prefs,
  ]) {
    if (prefs != null) {
      return prefs.colorForGrade(numericValue);
    }
    switch (numericValue) {
      case 5:
        return const Color(0xFF2E7D32);
      case 4:
        return const Color(0xFF1565C0);
      case 3:
        return const Color(0xFFF9A825);
      case 2:
        return const Color(0xFFEF6C00);
      case 1:
        return const Color(0xFFC62828);
      default:
        return const Color(0xFF37474F);
    }
  }

  /// Color for a floating-point subject/overall average (1.00 - 5.00),
  /// honoring user rounding rules and custom grade colors when provided.
  static Color averageColor(
    double average, [
    UserProfilePrefs? prefs,
  ]) {
    if (prefs != null) {
      return prefs.colorForAverage(average);
    }
    if (average >= 4.5) return gradeColor(5);
    if (average >= 3.5) return gradeColor(4);
    if (average >= 2.5) return gradeColor(3);
    if (average >= 1.5) return gradeColor(2);
    if (average > 0) return gradeColor(1);
    return const Color(0xFF37474F);
  }

  /// Builds the app [ThemeData] for OLED Pure Black, Standard Dark, or Light mode,
  /// optionally incorporating Material You [dynamicScheme].
  static ThemeData buildTheme({
    UserProfilePrefs prefs = const UserProfilePrefs(),
    ColorScheme? dynamicScheme,
    Brightness? platformBrightness,
  }) {
    var effectivePrefs = prefs.effectiveForPlatform();
    if (isIOSPlatform && effectivePrefs.followSystemTheme) {
      final sysBrightness = platformBrightness ??
          ui.PlatformDispatcher.instance.platformBrightness;
      effectivePrefs = effectivePrefs.copyWith(
        themeStyle: sysBrightness == Brightness.light
            ? AppThemeStyle.light
            : AppThemeStyle.oledPureBlack,
      );
    }
    final activePreset = BackgroundPresetInfo.resolve(effectivePrefs);
    final hasAnimated = effectivePrefs.hasAnimatedBackdrop;
    final hasStudioOrCustomBackdrop =
        hasAnimated ||
        effectivePrefs.hasCustomBackdrop ||
        activePreset.id != 'pure_oled';
    final contrast = AdaptiveContrastTokens.resolve(effectivePrefs);
    final isLight = hasStudioOrCustomBackdrop
        ? contrast.isLightBackdrop
        : (effectivePrefs.themeStyle == AppThemeStyle.light);
    final isOled =
        !isLight && effectivePrefs.themeStyle == AppThemeStyle.oledPureBlack;
    final brightness = isLight ? Brightness.light : Brightness.dark;
    final skin = effectivePrefs.customSkinConfig;
    final seedColor = skin.enabled && skin.accent != null
        ? skin.accent!
        : (effectivePrefs.uwuModeEnabled
            ? uwuPastelPink
            : Color(effectivePrefs.seedColorValue));

    ColorScheme baseScheme;
    if (!effectivePrefs.uwuModeEnabled &&
        effectivePrefs.useDynamicColor &&
        dynamicScheme != null &&
        dynamicScheme.brightness == brightness) {
      baseScheme = dynamicScheme;
    } else {
      baseScheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      );
    }

    final Color scaffoldBg;
    final Color cardBg;
    final Color elevatedBg;
    final Color borderColor;

    final isNavy =
        !hasAnimated && isOled && effectivePrefs.backgroundPreset == 'brand_navy';
    if (hasStudioOrCustomBackdrop && !isNavy) {
      scaffoldBg = hasAnimated
          ? effectivePrefs.animatedBackdropPreset.baseColor
          : activePreset.gradientColors.first;
      cardBg = contrast.cardFill.withValues(alpha: 1.0);
      elevatedBg = isLight
          ? const Color(0xFFEAECE8)
          : const Color(0xFF1C212C);
      borderColor = contrast.cardBorder;
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        onSurface: contrast.primaryText,
        onSurfaceVariant: contrast.secondaryText,
        outlineVariant: contrast.cardBorder,
        primary: effectivePrefs.uwuModeEnabled
            ? (isLight ? const Color(0xFFD81B60) : uwuPastelPink)
            : baseScheme.primary,
        secondary: effectivePrefs.uwuModeEnabled
            ? uwuPastelLavender
            : baseScheme.secondary,
        surfaceContainerLowest: scaffoldBg,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    } else if (isOled) {
      scaffoldBg = isNavy ? const Color(0xFF0B1E28) : pureBlack;
      cardBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFF19121B)
          : (isNavy ? const Color(0xFF112A37) : surfaceDark);
      elevatedBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFF241928)
          : (isNavy ? const Color(0xFF173545) : surfaceElevated);
      borderColor = effectivePrefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.42)
          : borderSubtle;
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        onSurface: Colors.white,
        primary: effectivePrefs.uwuModeEnabled ? uwuPastelPink : baseScheme.primary,
        secondary:
            effectivePrefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        surfaceContainerLowest: scaffoldBg,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    } else if (!isLight) {
      // Standard Material 3 Dark
      scaffoldBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFF1A141F)
          : const Color(0xFF14161A);
      cardBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFF251C2C)
          : const Color(0xFF1E2128);
      elevatedBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFF31253B)
          : const Color(0xFF282C35);
      borderColor = effectivePrefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.45)
          : const Color(0xFF363B47);
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        primary: effectivePrefs.uwuModeEnabled ? uwuPastelPink : baseScheme.primary,
        secondary:
            effectivePrefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    } else {
      // Material 3 Light
      scaffoldBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFFFFF5FA)
          : const Color(0xFFF4F6F8);
      cardBg = Colors.white;
      elevatedBg = effectivePrefs.uwuModeEnabled
          ? const Color(0xFFFCE8F3)
          : const Color(0xFFEFF2F6);
      borderColor = effectivePrefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.45)
          : Colors.black.withValues(alpha: 0.06);
      const lightInk = Color(0xFF0F172A);
      const lightSlate = Color(0xFF64748B);
      final effectivePrimary =
          effectivePrefs.uwuModeEnabled ? const Color(0xFFD81B60) : baseScheme.primary;
      final lightSecondaryContainer = Color.alphaBlend(
        effectivePrimary.withValues(alpha: 0.14),
        Colors.white,
      );
      final lightOnSecondaryContainer = Color.lerp(
        effectivePrimary,
        lightInk,
        0.35,
      )!;
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        onSurface: lightInk,
        onSurfaceVariant: lightSlate,
        outlineVariant: borderColor,
        outline: Colors.black.withValues(alpha: 0.14),
        primary: effectivePrimary,
        secondary:
            effectivePrefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        secondaryContainer: lightSecondaryContainer,
        onSecondaryContainer: lightOnSecondaryContainer,
        surfaceContainerLowest: scaffoldBg,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: const Color(0xFFE5EAF0),
      );
    }

    final Color resolvedScaffoldBg =
        skin.enabled ? (skin.bg ?? scaffoldBg) : scaffoldBg;
    final Color resolvedCardBg = skin.enabled
        ? (skin.surface ?? cardBg).withValues(alpha: skin.cardOpacity ?? 1.0)
        : cardBg;
    final Color resolvedElevatedBg =
        skin.enabled ? (skin.surface ?? elevatedBg) : elevatedBg;
    final Color resolvedBorderColor =
        skin.enabled ? (skin.borderColor ?? borderColor) : borderColor;
    final bool isMinimalist = effectivePrefs.minimalistModeEnabled;
    final BorderRadius effectiveCardRadius =
        skin.enabled && skin.cardRadius != null
            ? BorderRadius.circular(skin.cardRadius!)
            : cardRadius;
    final double effectiveBorderWidth =
        skin.enabled ? (skin.borderWidth ?? 1.0) : 1.0;

    if (skin.enabled) {
      baseScheme = baseScheme.copyWith(
        surface: resolvedScaffoldBg,
        onSurface: skin.text ?? baseScheme.onSurface,
        primary: skin.accent ?? baseScheme.primary,
        secondary: skin.accent ?? baseScheme.secondary,
        outlineVariant: resolvedBorderColor,
        surfaceContainerLowest: resolvedScaffoldBg,
        surfaceContainerLow: resolvedCardBg,
        surfaceContainer: resolvedCardBg,
        surfaceContainerHigh: resolvedElevatedBg,
        surfaceContainerHighest: resolvedElevatedBg,
      );
    }

    final primaryAccent = baseScheme.primary;
    final onSurfaceText = baseScheme.onSurface;
    final mutedText = onSurfaceText.withValues(alpha: 0.68);

    final rawTheme = ThemeData(
      useMaterial3: true,
      visualDensity:
          isMinimalist ? VisualDensity.compact : VisualDensity.standard,
      brightness: brightness,
      fontFamily: defaultFontFamily,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: resolvedScaffoldBg,
      canvasColor: resolvedScaffoldBg,
      dividerColor: resolvedBorderColor,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: SmoothSharedAxisTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: resolvedScaffoldBg,
        foregroundColor: onSurfaceText,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: systemOverlayStyleForBrightness(brightness),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: defaultFontFamily,
          color: onSurfaceText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
      cardTheme: CardThemeData(
        color: resolvedCardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: effectiveCardRadius,
          side: BorderSide(
            color: resolvedBorderColor,
            width: effectiveBorderWidth,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: resolvedCardBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryAccent.withValues(alpha: 0.22),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: defaultFontFamily,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? primaryAccent : mutedText,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? primaryAccent : mutedText,
            size: 24,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: resolvedElevatedBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: resolvedBorderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: resolvedBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: primaryAccent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: resolvedCardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: largeRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: resolvedCardBg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );

    TextStyle refineTextStyle(TextStyle? style, {double? letterSpacing}) {
      return (style ?? const TextStyle()).copyWith(
        fontFamily: defaultFontFamily,
        letterSpacing: letterSpacing ?? style?.letterSpacing,
        fontFeatures: const [ui.FontFeature.tabularFigures()],
      );
    }

    final baseTextTheme = rawTheme.textTheme;
    final refinedTextTheme = TextTheme(
      displayLarge: refineTextStyle(
        baseTextTheme.displayLarge,
        letterSpacing: -0.4,
      ),
      displayMedium: refineTextStyle(
        baseTextTheme.displayMedium,
        letterSpacing: -0.4,
      ),
      displaySmall: refineTextStyle(
        baseTextTheme.displaySmall,
        letterSpacing: -0.35,
      ),
      headlineLarge: refineTextStyle(
        baseTextTheme.headlineLarge,
        letterSpacing: -0.35,
      ),
      headlineMedium: refineTextStyle(
        baseTextTheme.headlineMedium,
        letterSpacing: -0.35,
      ),
      headlineSmall: refineTextStyle(
        baseTextTheme.headlineSmall,
        letterSpacing: -0.3,
      ),
      titleLarge: refineTextStyle(
        baseTextTheme.titleLarge,
        letterSpacing: -0.3,
      ),
      titleMedium: refineTextStyle(
        baseTextTheme.titleMedium,
        letterSpacing: -0.25,
      ),
      titleSmall: refineTextStyle(
        baseTextTheme.titleSmall,
        letterSpacing: -0.2,
      ),
      bodyLarge: refineTextStyle(baseTextTheme.bodyLarge),
      bodyMedium: refineTextStyle(baseTextTheme.bodyMedium),
      bodySmall: refineTextStyle(baseTextTheme.bodySmall),
      labelLarge: refineTextStyle(baseTextTheme.labelLarge),
      labelMedium: refineTextStyle(baseTextTheme.labelMedium),
      labelSmall: refineTextStyle(baseTextTheme.labelSmall),
    );

    final baseTheme = rawTheme.copyWith(textTheme: refinedTextTheme);

    if (skin.enabled &&
        skin.fontScale != null &&
        (skin.fontScale! - 1.0).abs() > 0.01) {
      final scale = skin.fontScale!;
      final resolvedTypography = Typography.englishLike2021.merge(
        baseTheme.textTheme,
      );
      TextStyle? scaleStyle(TextStyle? style) => style?.fontSize != null
          ? style!.copyWith(fontSize: style.fontSize! * scale)
          : style;
      return baseTheme.copyWith(
        textTheme: TextTheme(
          displayLarge: scaleStyle(resolvedTypography.displayLarge),
          displayMedium: scaleStyle(resolvedTypography.displayMedium),
          displaySmall: scaleStyle(resolvedTypography.displaySmall),
          headlineLarge: scaleStyle(resolvedTypography.headlineLarge),
          headlineMedium: scaleStyle(resolvedTypography.headlineMedium),
          headlineSmall: scaleStyle(resolvedTypography.headlineSmall),
          titleLarge: scaleStyle(resolvedTypography.titleLarge),
          titleMedium: scaleStyle(resolvedTypography.titleMedium),
          titleSmall: scaleStyle(resolvedTypography.titleSmall),
          bodyLarge: scaleStyle(resolvedTypography.bodyLarge),
          bodyMedium: scaleStyle(resolvedTypography.bodyMedium),
          bodySmall: scaleStyle(resolvedTypography.bodySmall),
          labelLarge: scaleStyle(resolvedTypography.labelLarge),
          labelMedium: scaleStyle(resolvedTypography.labelMedium),
          labelSmall: scaleStyle(resolvedTypography.labelSmall),
        ),
      );
    }
    return baseTheme;
  }
}
