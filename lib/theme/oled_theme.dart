import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';
import '../widgets/animation_helpers.dart';

/// Theme constants, multi-theme builder (OLED Pure Black, Standard Dark, Light),
/// Material 3 seed color presets, and grade badge colors.
class OledTheme {
  static const Color pureBlack = Colors.black;
  static const Color surfaceDark = Color(0xFF121212);
  static const Color surfaceElevated = Color(0xFF181818);
  static const Color borderSubtle = Color(0xFF262626);
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
  }) {
    final isLight = prefs.themeStyle == AppThemeStyle.light;
    final isOled = prefs.themeStyle == AppThemeStyle.oledPureBlack;
    final brightness = isLight ? Brightness.light : Brightness.dark;
    final seedColor =
        prefs.uwuModeEnabled ? uwuPastelPink : Color(prefs.seedColorValue);

    ColorScheme baseScheme;
    if (!prefs.uwuModeEnabled &&
        prefs.useDynamicColor &&
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

    if (isOled) {
      scaffoldBg = pureBlack;
      cardBg = prefs.uwuModeEnabled ? const Color(0xFF19121B) : surfaceDark;
      elevatedBg =
          prefs.uwuModeEnabled ? const Color(0xFF241928) : surfaceElevated;
      borderColor = prefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.42)
          : borderSubtle;
      baseScheme = baseScheme.copyWith(
        surface: pureBlack,
        onSurface: Colors.white,
        primary: prefs.uwuModeEnabled ? uwuPastelPink : baseScheme.primary,
        secondary:
            prefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        surfaceContainerLowest: pureBlack,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    } else if (!isLight) {
      // Standard Material 3 Dark
      scaffoldBg =
          prefs.uwuModeEnabled ? const Color(0xFF1A141F) : const Color(0xFF14161A);
      cardBg =
          prefs.uwuModeEnabled ? const Color(0xFF251C2C) : const Color(0xFF1E2128);
      elevatedBg =
          prefs.uwuModeEnabled ? const Color(0xFF31253B) : const Color(0xFF282C35);
      borderColor = prefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.45)
          : const Color(0xFF363B47);
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        primary: prefs.uwuModeEnabled ? uwuPastelPink : baseScheme.primary,
        secondary:
            prefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    } else {
      // Material 3 Light
      scaffoldBg =
          prefs.uwuModeEnabled ? const Color(0xFFFFF5FA) : const Color(0xFFF6F8FC);
      cardBg = Colors.white;
      elevatedBg =
          prefs.uwuModeEnabled ? const Color(0xFFFCE8F3) : const Color(0xFFEEF2F8);
      borderColor = prefs.uwuModeEnabled
          ? uwuPastelPink.withValues(alpha: 0.55)
          : const Color(0xFFDCE2EC);
      baseScheme = baseScheme.copyWith(
        surface: scaffoldBg,
        primary:
            prefs.uwuModeEnabled ? const Color(0xFFD81B60) : baseScheme.primary,
        secondary:
            prefs.uwuModeEnabled ? uwuPastelLavender : baseScheme.secondary,
        surfaceContainerLow: cardBg,
        surfaceContainer: cardBg,
        surfaceContainerHigh: elevatedBg,
        surfaceContainerHighest: elevatedBg,
      );
    }

    final primaryAccent = baseScheme.primary;
    final onSurfaceText = baseScheme.onSurface;
    final mutedText = onSurfaceText.withValues(alpha: 0.68);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: scaffoldBg,
      canvasColor: scaffoldBg,
      dividerColor: borderColor,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.iOS: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.linux: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.macOS: SmoothSharedAxisTransitionsBuilder(),
          TargetPlatform.windows: SmoothSharedAxisTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: onSurfaceText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryAccent.withValues(alpha: 0.22),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
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
        fillColor: elevatedBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: primaryAccent, width: 1.5),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: largeRadius),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
    );
  }
}
