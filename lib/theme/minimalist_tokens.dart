import 'package:flutter/material.dart';

import '../services/token_storage_service.dart';

/// Centralized density tokens for Minimalist Mode (`Minimalista mód`).
/// Preserves the modern Liquid Glass design language and rounded corners while
/// tightening padding, margins, gaps, badge sizes, and typography into an
/// ultra-compact layout.
class MinimalistTokens {
  final bool enabled;

  const MinimalistTokens(this.enabled);

  factory MinimalistTokens.of(UserProfilePrefs? prefs) => MinimalistTokens(
        prefs?.minimalistModeEnabled ??
            UserProfilePrefs.activeMinimalistModeEnabled,
      );

  double get horizontalPagePadding => enabled ? 10.0 : 16.0;
  double get cardGap => enabled ? 4.0 : 8.0;
  double get sectionGap => enabled ? 10.0 : 20.0;
  double get radiusValue => 18.0;
  BorderRadius get cardRadius => BorderRadius.circular(18.0);
  BorderRadius get largeRadius => BorderRadius.circular(22.0);
  BorderRadius get badgeRadius => BorderRadius.circular(12.0);

  EdgeInsets get tilePadding => enabled
      ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
      : const EdgeInsets.symmetric(horizontal: 14, vertical: 11);

  EdgeInsets get cardPadding =>
      enabled ? const EdgeInsets.all(10) : const EdgeInsets.all(18);

  double get badgeSize => enabled ? 28.0 : 40.0;
  double get smallBadgeSize => enabled ? 24.0 : 34.0;
  double get iconSize => enabled ? 15.0 : 20.0;
  double get tabBarHeight => enabled ? 31.0 : 40.0;
  double get tabFontSize => enabled ? 11.0 : 12.5;
  double get borderWidth => 1.0;

  double font(double standard, [double? minimalist]) =>
      enabled ? (minimalist ?? (standard - 1.5)) : standard;
}
