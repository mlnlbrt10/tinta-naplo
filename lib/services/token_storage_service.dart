import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/kreta_auth_config.dart';
import '../theme/custom_skin_config.dart';
import '../utils/uwu_helper.dart';

/// Supported visual theme styles in Tinta Napló.
enum AppThemeStyle {
  oledPureBlack,
  standardDark,
  light,
}

/// Physical-optics Liquid Glass rendering & spring physics presets selectable
/// in Developer Options (`Fejlesztői beállítások`).
enum LiquidGlassMode {
  classicFrost(
    label: 'Classic Frost',
    subtitle: 'Alapértelmezett matt üveg',
    description:
        'Kiegyensúlyozott matt üvegfelület, élénk alulcsillapított rugófizika és lágy felső peremfény.',
    stiffnessX: 360.0,
    dampingX: 24.5,
    stiffnessY: 360.0,
    dampingY: 24.5,
    stretchMultiplier: 1.0,
  ),
  hydroMercury(
    label: 'Hydro Mercury',
    subtitle: 'Folyékony Higany',
    description:
        'Nagy felületi feszültségű higanycsepp fizika, élénk nyújtás és fémes peremtükröződés.',
    stiffnessX: 410.0,
    dampingX: 19.5,
    stiffnessY: 380.0,
    dampingY: 21.0,
    stretchMultiplier: 1.05,
  ),
  opticalPrism(
    label: 'Optical Prism',
    subtitle: 'Optikai Prizma',
    description:
        'Kristálytiszta üveg finom meleg-borostyán és jégkék kromatikus élszóródással.',
    stiffnessX: 360.0,
    dampingX: 24.0,
    stiffnessY: 360.0,
    dampingY: 24.0,
    stretchMultiplier: 1.02,
  ),
  smokedObsidian(
    label: 'Smoked Obsidian',
    subtitle: 'Füstölt Obszidián',
    description:
        'ND füstölt stúdióüveg kritikusan csillapított viszkózus csúszással és 1px csiszolt éllel.',
    stiffnessX: 340.0,
    dampingX: 36.9,
    stiffnessY: 340.0,
    dampingY: 36.9,
    stretchMultiplier: 0.25,
  ),
  rippleGel(
    label: 'Ripple Gel',
    subtitle: 'Hidrogél',
    description:
        'Puha rugalmas zselé összenyomódás érintéspontból sugárzó koncentrikus fényhullámmal.',
    stiffnessX: 330.0,
    dampingX: 21.5,
    stiffnessY: 330.0,
    dampingY: 21.5,
    stretchMultiplier: 1.04,
  );

  final String label;
  final String subtitle;
  final String description;
  final double stiffnessX;
  final double dampingX;
  final double stiffnessY;
  final double dampingY;
  final double stretchMultiplier;

  const LiquidGlassMode({
    required this.label,
    required this.subtitle,
    required this.description,
    required this.stiffnessX,
    required this.dampingX,
    required this.stiffnessY,
    required this.dampingY,
    required this.stretchMultiplier,
  });

  static LiquidGlassMode fromName(String? name) {
    return LiquidGlassMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => LiquidGlassMode.classicFrost,
    );
  }
}

/// Experimental GPU-friendly animated backdrop scenes selectable in
/// Developer Options (`Fejlesztői beállítások`).
enum AnimatedBackdropPreset {
  off(
    label: 'Off',
    subtitle: 'Statikus stúdió háttér',
    baseColor: Colors.black,
    luminance: 0.0,
  ),
  gyroLiquidHorizon(
    label: 'Gyro Liquid Horizon',
    subtitle: 'Giroszkóp + érintés parallaxis [Ultra]',
    baseColor: Color(0xFF0A0D12),
    luminance: 0.012,
  ),
  causticWater(
    label: 'Caustic Water',
    subtitle: 'Fénytöréses víz',
    baseColor: Color(0xFF0B1319),
    luminance: 0.016,
  ),
  ferrofluidDrift(
    label: 'Ferrofluid Drift',
    subtitle: 'Ferrofluid',
    baseColor: Color(0xFF0E1014),
    luminance: 0.014,
  ),
  sunbeamDust(
    label: 'Sunbeam Dust',
    subtitle: 'Napsugár',
    baseColor: Color(0xFF121110),
    luminance: 0.018,
  ),
  topographicPulse(
    label: 'Topographic Pulse',
    subtitle: 'Élő szintvonalak',
    baseColor: Color(0xFF0B0E14),
    luminance: 0.010,
  ),
  analogFilmLight(
    label: 'Analog Film Light',
    subtitle: 'Analóg fényjáték',
    baseColor: Color(0xFF110F0E),
    luminance: 0.015,
  );

  final String label;
  final String subtitle;
  final Color baseColor;
  final double luminance;

  const AnimatedBackdropPreset({
    required this.label,
    required this.subtitle,
    required this.baseColor,
    required this.luminance,
  });

  static AnimatedBackdropPreset fromName(String? name) {
    return AnimatedBackdropPreset.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AnimatedBackdropPreset.off,
    );
  }
}

/// Configurable close button display modes for inspection & detail modals.
enum ModalCloseButtonMode {
  onlyX,
  onlyBottom,
  both,
  neither;

  String get label {
    switch (this) {
      case ModalCloseButtonMode.onlyX:
        return "Csak 'X' gomb";
      case ModalCloseButtonMode.onlyBottom:
        return 'Csak alsó bezárás gomb';
      case ModalCloseButtonMode.both:
        return 'Mindkettő';
      case ModalCloseButtonMode.neither:
        return 'Egyik se';
    }
  }

  bool get showTopX =>
      this == ModalCloseButtonMode.onlyX || this == ModalCloseButtonMode.both;

  bool get showBottomButton =>
      this == ModalCloseButtonMode.onlyBottom ||
      this == ModalCloseButtonMode.both;
}

/// Configurable grade rounding thresholds (minimum average required for each grade).
class GradeRoundingConfig {
  final double threshold5;
  final double threshold4;
  final double threshold3;
  final double threshold2;

  const GradeRoundingConfig({
    this.threshold5 = 4.50,
    this.threshold4 = 3.50,
    this.threshold3 = 2.50,
    this.threshold2 = 1.50,
  });

  /// Evaluates the rounded integer grade (1..5) for a given [average].
  int evaluateRoundedGrade(double average) {
    if (average >= threshold5) return 5;
    if (average >= threshold4) return 4;
    if (average >= threshold3) return 3;
    if (average >= threshold2) return 2;
    return 1;
  }

  /// Returns the threshold required for [targetGrade] (2..5).
  double thresholdForGrade(int targetGrade) {
    switch (targetGrade) {
      case 5:
        return threshold5;
      case 4:
        return threshold4;
      case 3:
        return threshold3;
      case 2:
        return threshold2;
      default:
        return 1.0;
    }
  }

  GradeRoundingConfig copyWith({
    double? threshold5,
    double? threshold4,
    double? threshold3,
    double? threshold2,
  }) {
    return GradeRoundingConfig(
      threshold5: threshold5 ?? this.threshold5,
      threshold4: threshold4 ?? this.threshold4,
      threshold3: threshold3 ?? this.threshold3,
      threshold2: threshold2 ?? this.threshold2,
    );
  }

  Map<String, double> toJson() => {
        '5': threshold5,
        '4': threshold4,
        '3': threshold3,
        '2': threshold2,
      };

  factory GradeRoundingConfig.fromJson(Map<String, dynamic> json) {
    return GradeRoundingConfig(
      threshold5: (json['5'] as num?)?.toDouble() ?? 4.50,
      threshold4: (json['4'] as num?)?.toDouble() ?? 3.50,
      threshold3: (json['3'] as num?)?.toDouble() ?? 2.50,
      threshold2: (json['2'] as num?)?.toDouble() ?? 1.50,
    );
  }
}

/// User customization & personalization preferences persisted in secure storage.
/// Survives logout/relogin and supports full JSON export/import.
class UserProfilePrefs {
  static ModalCloseButtonMode activeModalCloseMode = ModalCloseButtonMode.both;
  static bool activeLiquidGlassEnabled = false;
  static bool get activeSoftBlurEnabled => activeLiquidGlassEnabled;
  static LiquidGlassMode activeLiquidGlassMode = LiquidGlassMode.classicFrost;
  static double activeSoftBlurSigma = 4.0;
  static bool activeMinimalistModeEnabled = false;
  static bool activeDemoModeEnabled = false;
  static bool activeFitymaModeEnabled = false;
  static CustomSkinConfig activeCustomSkin = const CustomSkinConfig();

  static void syncActiveGlobals(UserProfilePrefs prefs) {
    activeModalCloseMode = prefs.modalCloseMode;
    activeLiquidGlassEnabled = prefs.liquidGlassEnabled;
    activeLiquidGlassMode = prefs.liquidGlassMode;
    activeSoftBlurSigma = prefs.cardBlurSigma;
    activeMinimalistModeEnabled = prefs.minimalistModeEnabled;
    activeDemoModeEnabled = prefs.demoModeEnabled;
    activeFitymaModeEnabled = prefs.fitymaModeEnabled;
    activeCustomSkin = prefs.customSkinConfig;
    UwuHelper.isFitymaEnabled = prefs.fitymaModeEnabled;
  }

  static bool _parseBool(dynamic value) => value == true || value == 'true';

  final String? nickname;
  final int avatarIconIndex;
  final int avatarColorIndex;
  final String? customPhotoPath;
  final AppThemeStyle themeStyle;
  final bool useDynamicColor;
  final int seedColorValue;
  final bool showWeekends;
  final bool showCancelledLessons;
  final Map<int, int> customGradeColors;
  final GradeRoundingConfig roundingConfig;
  final bool developerModeUnlocked;
  final bool uwuModeEnabled;
  final bool tsundereModeEnabled;
  final bool christmasModeEnabled;
  final String appIconPreset;
  final String backgroundPreset;
  final ModalCloseButtonMode modalCloseMode;
  final String transitHomeStation;
  final String transitSchoolStation;
  final bool transitAllowCoach;
  final bool transitAllowTrain;
  final bool transitAllowLocalBus;
  final double walkingSpeedKmh;
  final int walkingDurationMinutes;
  final int transitAlertBufferMinutes;
  final bool transitNotificationsEnabled;
  final bool transitCardEnabled;
  final int walkHomeToBusMinutes;
  final int walkHomeToTrainMinutes;
  final int walkSchoolToBusMinutes;
  final int walkSchoolToTrainMinutes;
  final bool calcAllow200Weight;
  final bool liquidGlassEnabled;
  bool get cardBlurEnabled => liquidGlassEnabled;
  final LiquidGlassMode liquidGlassMode;
  final String? customBackdropPath;
  final double customBackdropDim;
  final double customBackdropLuminance;
  final AnimatedBackdropPreset animatedBackdropPreset;
  final double cardOpacity;
  final double cardBlurSigma;

  bool get hasCustomBackdrop =>
      customBackdropPath != null && customBackdropPath!.trim().isNotEmpty;

  bool get hasAnimatedBackdrop =>
      animatedBackdropPreset != AnimatedBackdropPreset.off;
  final String favoriteRoute1stPeriod;
  final String favoriteRoute2ndPeriod;
  final Map<String, GradeRoundingConfig> subjectRoundingOverrides;
  final Map<String, int> subjectCustomColors;
  final Map<String, String> subjectCustomNames;
  final Map<String, String> teacherCustomNames;

  /// Forward-compatible bag for v1.0.0 settings (timetable filters, scholarship
  /// mode, exact commute addresses, per-day commute plans). Persisted as JSON.
  final Map<String, dynamic> extras;

  static const Map<int, int> defaultGradeColors = {
    5: 0xFF2E7D32, // Green
    4: 0xFF1565C0, // Blue
    3: 0xFFF9A825, // Amber
    2: 0xFFEF6C00, // Orange
    1: 0xFFC62828, // Red
  };

  const UserProfilePrefs({
    this.nickname,
    this.avatarIconIndex = 0,
    this.avatarColorIndex = 0,
    this.customPhotoPath,
    this.themeStyle = AppThemeStyle.oledPureBlack,
    this.useDynamicColor = false,
    this.seedColorValue = 0xFF4DA3FF,
    this.showWeekends = false,
    this.showCancelledLessons = true,
    this.customGradeColors = defaultGradeColors,
    this.roundingConfig = const GradeRoundingConfig(),
    this.developerModeUnlocked = false,
    this.uwuModeEnabled = false,
    this.tsundereModeEnabled = false,
    this.christmasModeEnabled = false,
    this.appIconPreset = 'default',
    this.backgroundPreset = 'pure_oled',
    this.modalCloseMode = ModalCloseButtonMode.both,
    this.transitHomeStation = '',
    this.transitSchoolStation = '',
    this.transitAllowCoach = true,
    this.transitAllowTrain = true,
    this.transitAllowLocalBus = true,
    this.walkingSpeedKmh = 4.5,
    this.walkingDurationMinutes = 10,
    this.transitAlertBufferMinutes = 5,
    this.transitNotificationsEnabled = true,
    this.transitCardEnabled = false,
    this.walkHomeToBusMinutes = 8,
    this.walkHomeToTrainMinutes = 12,
    this.walkSchoolToBusMinutes = 5,
    this.walkSchoolToTrainMinutes = 15,
    this.calcAllow200Weight = false,
    bool? liquidGlassEnabled,
    @Deprecated('Use liquidGlassEnabled instead') bool? cardBlurEnabled,
    this.liquidGlassMode = LiquidGlassMode.classicFrost,
    this.customBackdropPath,
    this.customBackdropDim = 0.35,
    this.customBackdropLuminance = 0.15,
    this.animatedBackdropPreset = AnimatedBackdropPreset.off,
    this.cardOpacity = 0.9,
    this.cardBlurSigma = 4.0,
    this.favoriteRoute1stPeriod = '',
    this.favoriteRoute2ndPeriod = '',
    this.subjectRoundingOverrides = const {},
    this.subjectCustomColors = const {},
    this.subjectCustomNames = const {},
    this.teacherCustomNames = const {},
    this.extras = const {},
  }) : liquidGlassEnabled = liquidGlassEnabled ?? cardBlurEnabled ?? false;

  // ---- v1.0.0 typed accessors over [extras] --------------------------------
  /// "Elmaradó órák elrejtése" (falls back to the legacy single filter).
  bool get hideCancelledLessons =>
      (extras['hideCancelledLessons'] as bool?) ?? !showCancelledLessons;

  /// "Lyukas / szabad órák elrejtése" (falls back to the legacy single filter).
  bool get hideFreeLessons =>
      (extras['hideFreeLessons'] as bool?) ?? !showCancelledLessons;

  /// Developer Options: "Minimalista mód" (stripped-down expanded cards/modals).
  bool get minimalistModeEnabled => extras['minimalistModeEnabled'] == true;

  UserProfilePrefs withMinimalistMode(bool enabled) =>
      withExtra('minimalistModeEnabled', enabled);

  /// Developer Options: Isolated "Demó mód" (Kovács Bence showcase dataset).
  bool get demoModeEnabled => extras['demoModeEnabled'] == true;

  UserProfilePrefs withDemoMode(bool enabled) =>
      withExtra('demoModeEnabled', enabled);

  /// Developer Options: Live Activity / Samsung Now Bar ongoing lesson notification.
  bool get liveActivityEnabled => extras['liveActivityEnabled'] == true;

  UserProfilePrefs withLiveActivityEnabled(bool enabled) =>
      withExtra('liveActivityEnabled', enabled);

  /// Developer Options: Easter-egg "Fityma Napló" branding & cartoon mascot mode.
  bool get fitymaModeEnabled => extras['fitymaModeEnabled'] == true;

  UserProfilePrefs withFitymaMode(bool enabled) =>
      withExtra('fitymaModeEnabled', enabled);

  /// Developer Options: CSS-style Custom Skin Engine toggle & raw CSS variables.
  bool get customSkinEnabled => extras['customSkinEnabled'] == true;

  String get customSkinCss {
    final raw = extras['customSkinCss'];
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return CustomSkinConfig.defaultTemplateCss;
  }

  CustomSkinConfig get customSkinConfig =>
      CustomSkinConfig.parse(customSkinCss, enabled: customSkinEnabled);

  UserProfilePrefs withCustomSkin({bool? enabled, String? css}) {
    final updatedExtras = Map<String, dynamic>.from(extras);
    if (enabled != null) {
      updatedExtras['customSkinEnabled'] = enabled;
    }
    if (css != null) {
      updatedExtras['customSkinCss'] = css;
    }
    return copyWith(extras: updatedExtras);
  }

  /// `true` => "Ágazati alapoktatás (9–10. évf.)", `false` => "Szakirányú oktatás".
  bool get scholarshipBasicEducation => extras['scholarshipBasic'] == true;

  /// `technikum` or `szakkepzo`.
  String get scholarshipSchoolType =>
      extras['scholarshipSchoolType'] == 'szakkepzo' ? 'szakkepzo' : 'technikum';

  /// Configured scholarship target tier index (0-based into ScholarshipTier.tiers), if any.
  int? get scholarshipTargetTierIdx {
    final raw = extras['scholarshipTargetTierIdx'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return null;
  }

  /// Configured explicit scholarship target average, if saved.
  double? get scholarshipTargetAverage {
    final raw = extras['scholarshipTargetAverage'];
    if (raw is num) return raw.toDouble();
    return null;
  }

  /// Optional custom ARGB color override for timetable period numbers/badges
  /// (`1.`, `2.`, ...). `null` restores the theme's default period styling.
  int? get timetablePeriodColorValue {
    final raw = extras['timetablePeriodColorValue'];
    return raw is num ? raw.toInt() : null;
  }

  Color? get timetablePeriodColor {
    final v = timetablePeriodColorValue;
    return v == null ? null : Color(v);
  }

  UserProfilePrefs withTimetablePeriodColor(int? argb) {
    final nextExtras = Map<String, dynamic>.from(extras);
    if (argb == null) {
      nextExtras.remove('timetablePeriodColorValue');
    } else {
      nextExtras['timetablePeriodColorValue'] = argb;
    }
    return copyWith(extras: nextExtras);
  }

  String get homeAddress => (extras['homeAddress'] as String?)?.trim() ?? '';
  double? get homeAddressLat => (extras['homeAddressLat'] as num?)?.toDouble();
  double? get homeAddressLon => (extras['homeAddressLon'] as num?)?.toDouble();

  String get schoolAddress => (extras['schoolAddress'] as String?)?.trim() ?? '';
  double? get schoolAddressLat =>
      (extras['schoolAddressLat'] as num?)?.toDouble();
  double? get schoolAddressLon =>
      (extras['schoolAddressLon'] as num?)?.toDouble();

  String get homeBusStop => transitHomeStation.trim();
  String get homeTrainStation =>
      (extras['homeTrainStation'] as String?)?.trim() ?? '';

  String get schoolBusStop => transitSchoolStation.trim();
  String get schoolTrainStation =>
      (extras['schoolTrainStation'] as String?)?.trim() ?? '';

  String get primaryHomeStop => homeBusStop.isNotEmpty
      ? homeBusStop
      : (homeTrainStation.isNotEmpty ? homeTrainStation : homeAddress);

  String get primarySchoolStop => schoolBusStop.isNotEmpty
      ? schoolBusStop
      : (schoolTrainStation.isNotEmpty ? schoolTrainStation : schoolAddress);

  /// Per-weekday commute plan (1 = Hétfő … 5 = Péntek).
  /// Supports bidirectional keys:
  /// - Morning (`Odafele`): `morningLine`, `morningUseLocalBus` (falls back to `line` / `useLocalBus`)
  /// - Afternoon (`Hazafele`): `afternoonLine`, `afternoonUseLocalBus` (falls back to `line` / `useLocalBus`)
  Map<String, dynamic> commutePlanForWeekday(int weekday) {
    final raw = extras['commuteDays'];
    if (raw is Map && raw['$weekday'] is Map) {
      return Map<String, dynamic>.from(raw['$weekday'] as Map);
    }
    return const {};
  }

  UserProfilePrefs withExtra(String key, Object? value) {
    final next = Map<String, dynamic>.from(extras);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return copyWith(extras: next);
  }

  UserProfilePrefs withExtras(Map<String, Object?> updates) {
    final next = Map<String, dynamic>.from(extras);
    updates.forEach((key, value) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    });
    return copyWith(extras: next);
  }

  UserProfilePrefs withCommutePlan(int weekday, Map<String, dynamic> plan) {
    final days = <String, dynamic>{};
    final raw = extras['commuteDays'];
    if (raw is Map) {
      raw.forEach((k, v) => days[k.toString()] = v);
    }
    days['$weekday'] = plan;
    return withExtra('commuteDays', days);
  }

  /// True when both the home and school stops/addresses have been configured.
  bool get transitConfigured =>
      (homeBusStop.isNotEmpty ||
          homeTrainStation.isNotEmpty ||
          homeAddress.isNotEmpty) &&
      (schoolBusStop.isNotEmpty ||
          schoolTrainStation.isNotEmpty ||
          schoolAddress.isNotEmpty);

  Color colorForGrade(int? numericValue) {
    if (numericValue == null) return const Color(0xFF37474F);
    final argb =
        customGradeColors[numericValue] ?? defaultGradeColors[numericValue];
    return argb != null ? Color(argb) : const Color(0xFF37474F);
  }

  Color colorForAverage(double average) {
    final rounded = roundingConfig.evaluateRoundedGrade(average);
    return colorForGrade(rounded);
  }

  /// Resolves the rounding configuration for a specific subject key (`uid` or `name`),
  /// falling back to the global [roundingConfig].
  GradeRoundingConfig roundingForSubject(String subjectKey, [String? altKey]) {
    if (subjectRoundingOverrides.containsKey(subjectKey)) {
      return subjectRoundingOverrides[subjectKey]!;
    }
    if (altKey != null && subjectRoundingOverrides.containsKey(altKey)) {
      return subjectRoundingOverrides[altKey]!;
    }
    return roundingConfig;
  }

  /// Evaluates the rounded standing grade (1..5) for a subject using any per-subject override.
  int evaluateSubjectRoundedGrade(
    double average,
    String subjectKey, [
    String? altKey,
  ]) {
    return roundingForSubject(subjectKey, altKey).evaluateRoundedGrade(average);
  }

  /// Returns a custom accent color for a subject if set, or null.
  Color? customColorForSubject(String subjectKey, [String? altKey]) {
    final argb = subjectCustomColors[subjectKey] ??
        (altKey != null ? subjectCustomColors[altKey] : null);
    return argb != null ? Color(argb) : null;
  }

  /// Returns the display name for a subject, honoring local custom renames.
  String resolveSubjectName(String originalName, [String? subjectUid]) {
    if (subjectUid != null && subjectUid.isNotEmpty) {
      final byUid = subjectCustomNames[subjectUid]?.trim();
      if (byUid != null && byUid.isNotEmpty) return byUid;
    }
    final byName = subjectCustomNames[originalName]?.trim();
    if (byName != null && byName.isNotEmpty) return byName;
    return originalName;
  }

  /// Returns the display name for a teacher, honoring local custom renames.
  String resolveTeacherName(String? originalTeacher) {
    if (originalTeacher == null || originalTeacher.trim().isEmpty) {
      return '';
    }
    final trimmed = originalTeacher.trim();
    final custom = teacherCustomNames[trimmed]?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return trimmed;
  }

  UserProfilePrefs copyWith({
    String? nickname,
    bool clearNickname = false,
    int? avatarIconIndex,
    int? avatarColorIndex,
    String? customPhotoPath,
    bool clearCustomPhoto = false,
    AppThemeStyle? themeStyle,
    bool? useDynamicColor,
    int? seedColorValue,
    bool? showWeekends,
    bool? showCancelledLessons,
    Map<int, int>? customGradeColors,
    GradeRoundingConfig? roundingConfig,
    bool? developerModeUnlocked,
    bool? uwuModeEnabled,
    bool? tsundereModeEnabled,
    bool? christmasModeEnabled,
    String? appIconPreset,
    String? backgroundPreset,
    ModalCloseButtonMode? modalCloseMode,
    String? transitHomeStation,
    String? transitSchoolStation,
    bool? transitAllowCoach,
    bool? transitAllowTrain,
    bool? transitAllowLocalBus,
    double? walkingSpeedKmh,
    int? walkingDurationMinutes,
    int? transitAlertBufferMinutes,
    bool? transitNotificationsEnabled,
    bool? transitCardEnabled,
    int? walkHomeToBusMinutes,
    int? walkHomeToTrainMinutes,
    int? walkSchoolToBusMinutes,
    int? walkSchoolToTrainMinutes,
    bool? calcAllow200Weight,
    bool? liquidGlassEnabled,
    @Deprecated('Use liquidGlassEnabled instead') bool? cardBlurEnabled,
    LiquidGlassMode? liquidGlassMode,
    String? customBackdropPath,
    bool clearCustomBackdropPath = false,
    double? customBackdropDim,
    double? customBackdropLuminance,
    AnimatedBackdropPreset? animatedBackdropPreset,
    double? cardOpacity,
    double? cardBlurSigma,
    String? favoriteRoute1stPeriod,
    String? favoriteRoute2ndPeriod,
    Map<String, GradeRoundingConfig>? subjectRoundingOverrides,
    Map<String, int>? subjectCustomColors,
    Map<String, String>? subjectCustomNames,
    Map<String, String>? teacherCustomNames,
    Map<String, dynamic>? extras,
  }) {
    return UserProfilePrefs(
      nickname: clearNickname ? null : (nickname ?? this.nickname),
      avatarIconIndex: avatarIconIndex ?? this.avatarIconIndex,
      avatarColorIndex: avatarColorIndex ?? this.avatarColorIndex,
      customPhotoPath:
          clearCustomPhoto ? null : (customPhotoPath ?? this.customPhotoPath),
      themeStyle: themeStyle ?? this.themeStyle,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      seedColorValue: seedColorValue ?? this.seedColorValue,
      showWeekends: showWeekends ?? this.showWeekends,
      showCancelledLessons: showCancelledLessons ?? this.showCancelledLessons,
      customGradeColors: customGradeColors ?? this.customGradeColors,
      roundingConfig: roundingConfig ?? this.roundingConfig,
      developerModeUnlocked:
          developerModeUnlocked ?? this.developerModeUnlocked,
      uwuModeEnabled: uwuModeEnabled ?? this.uwuModeEnabled,
      tsundereModeEnabled: tsundereModeEnabled ?? this.tsundereModeEnabled,
      christmasModeEnabled: christmasModeEnabled ?? this.christmasModeEnabled,
      appIconPreset: appIconPreset ?? this.appIconPreset,
      backgroundPreset: backgroundPreset ?? this.backgroundPreset,
      modalCloseMode: modalCloseMode ?? this.modalCloseMode,
      transitHomeStation: transitHomeStation ?? this.transitHomeStation,
      transitSchoolStation: transitSchoolStation ?? this.transitSchoolStation,
      transitAllowCoach: transitAllowCoach ?? this.transitAllowCoach,
      transitAllowTrain: transitAllowTrain ?? this.transitAllowTrain,
      transitAllowLocalBus: transitAllowLocalBus ?? this.transitAllowLocalBus,
      walkingSpeedKmh: walkingSpeedKmh ?? this.walkingSpeedKmh,
      walkingDurationMinutes:
          walkingDurationMinutes ?? this.walkingDurationMinutes,
      transitAlertBufferMinutes:
          transitAlertBufferMinutes ?? this.transitAlertBufferMinutes,
      transitNotificationsEnabled:
          transitNotificationsEnabled ?? this.transitNotificationsEnabled,
      transitCardEnabled: transitCardEnabled ?? this.transitCardEnabled,
      walkHomeToBusMinutes: walkHomeToBusMinutes ?? this.walkHomeToBusMinutes,
      walkHomeToTrainMinutes: walkHomeToTrainMinutes ?? this.walkHomeToTrainMinutes,
      walkSchoolToBusMinutes: walkSchoolToBusMinutes ?? this.walkSchoolToBusMinutes,
      walkSchoolToTrainMinutes: walkSchoolToTrainMinutes ?? this.walkSchoolToTrainMinutes,
      calcAllow200Weight: calcAllow200Weight ?? this.calcAllow200Weight,
      liquidGlassEnabled:
          liquidGlassEnabled ?? cardBlurEnabled ?? this.liquidGlassEnabled,
      liquidGlassMode: liquidGlassMode ?? this.liquidGlassMode,
      customBackdropPath: clearCustomBackdropPath
          ? null
          : (customBackdropPath ?? this.customBackdropPath),
      customBackdropDim:
          (customBackdropDim ?? this.customBackdropDim).clamp(0.0, 0.75),
      customBackdropLuminance:
          (customBackdropLuminance ?? this.customBackdropLuminance)
              .clamp(0.0, 1.0),
      animatedBackdropPreset:
          animatedBackdropPreset ?? this.animatedBackdropPreset,
      cardOpacity: cardOpacity ?? this.cardOpacity,
      cardBlurSigma: cardBlurSigma ?? this.cardBlurSigma,
      favoriteRoute1stPeriod:
          favoriteRoute1stPeriod ?? this.favoriteRoute1stPeriod,
      favoriteRoute2ndPeriod:
          favoriteRoute2ndPeriod ?? this.favoriteRoute2ndPeriod,
      subjectRoundingOverrides:
          subjectRoundingOverrides ?? this.subjectRoundingOverrides,
      subjectCustomColors: subjectCustomColors ?? this.subjectCustomColors,
      subjectCustomNames: subjectCustomNames ?? this.subjectCustomNames,
      teacherCustomNames: teacherCustomNames ?? this.teacherCustomNames,
      extras: extras ?? this.extras,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 3,
      'nickname': nickname,
      'avatarIconIndex': avatarIconIndex,
      'avatarColorIndex': avatarColorIndex,
      'customPhotoPath': customPhotoPath,
      'themeStyle': themeStyle.name,
      'useDynamicColor': useDynamicColor,
      'seedColorValue': seedColorValue,
      'showWeekends': showWeekends,
      'showCancelledLessons': showCancelledLessons,
      'customGradeColors':
          customGradeColors.map((k, v) => MapEntry(k.toString(), v)),
      'roundingConfig': roundingConfig.toJson(),
      'developerModeUnlocked': developerModeUnlocked,
      'uwuModeEnabled': uwuModeEnabled,
      'tsundereModeEnabled': tsundereModeEnabled,
      'christmasModeEnabled': christmasModeEnabled,
      'appIconPreset': appIconPreset,
      'backgroundPreset': backgroundPreset,
      'modalCloseMode': modalCloseMode.name,
      'transitHomeStation': transitHomeStation,
      'transitSchoolStation': transitSchoolStation,
      'transitAllowCoach': transitAllowCoach,
      'transitAllowTrain': transitAllowTrain,
      'transitAllowLocalBus': transitAllowLocalBus,
      'walkingSpeedKmh': walkingSpeedKmh,
      'walkingDurationMinutes': walkingDurationMinutes,
      'transitAlertBufferMinutes': transitAlertBufferMinutes,
      'transitNotificationsEnabled': transitNotificationsEnabled,
      'transitCardEnabled': transitCardEnabled,
      'walkHomeToBusMinutes': walkHomeToBusMinutes,
      'walkHomeToTrainMinutes': walkHomeToTrainMinutes,
      'walkSchoolToBusMinutes': walkSchoolToBusMinutes,
      'walkSchoolToTrainMinutes': walkSchoolToTrainMinutes,
      'calcAllow200Weight': calcAllow200Weight,
      'liquidGlassEnabled': liquidGlassEnabled,
      'liquidGlassMode': liquidGlassMode.name,
      'customBackdropPath': customBackdropPath,
      'customBackdropDim': customBackdropDim,
      'customBackdropLuminance': customBackdropLuminance,
      'animatedBackdropPreset': animatedBackdropPreset.name,
      'cardOpacity': cardOpacity,
      'cardBlurSigma': cardBlurSigma,
      'favoriteRoute1stPeriod': favoriteRoute1stPeriod,
      'favoriteRoute2ndPeriod': favoriteRoute2ndPeriod,
      'subjectRoundingOverrides':
          subjectRoundingOverrides.map((k, v) => MapEntry(k, v.toJson())),
      'subjectCustomColors': subjectCustomColors,
      'subjectCustomNames': subjectCustomNames,
      'teacherCustomNames': teacherCustomNames,
      'extras': extras,
    };
  }

  String toExportJsonString() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  factory UserProfilePrefs.fromJson(Map<String, dynamic> json) {
    final rawNick = (json['nickname'] as String?)?.trim();
    final photoPath = (json['customPhotoPath'] as String?)?.trim();
    final themeName = json['themeStyle'] as String?;
    final themeStyle = AppThemeStyle.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => AppThemeStyle.oledPureBlack,
    );
    final modalCloseName = json['modalCloseMode'] as String?;
    final modalCloseMode = ModalCloseButtonMode.values.firstWhere(
      (e) => e.name == modalCloseName,
      orElse: () => ModalCloseButtonMode.both,
    );

    final gradeColors = Map<int, int>.from(defaultGradeColors);
    final rawGradeColors = json['customGradeColors'];
    if (rawGradeColors is Map) {
      for (final entry in rawGradeColors.entries) {
        final k = int.tryParse(entry.key.toString());
        final v = entry.value;
        if (k != null && v is num) {
          gradeColors[k] = v.toInt();
        }
      }
    }

    GradeRoundingConfig rounding = const GradeRoundingConfig();
    if (json['roundingConfig'] is Map<String, dynamic>) {
      rounding = GradeRoundingConfig.fromJson(
        json['roundingConfig'] as Map<String, dynamic>,
      );
    } else if (json['roundingConfig'] is Map) {
      rounding = GradeRoundingConfig.fromJson(
        Map<String, dynamic>.from(json['roundingConfig'] as Map),
      );
    }

    final subjRounding = <String, GradeRoundingConfig>{};
    if (json['subjectRoundingOverrides'] is Map) {
      for (final entry in (json['subjectRoundingOverrides'] as Map).entries) {
        if (entry.value is Map) {
          subjRounding[entry.key.toString()] = GradeRoundingConfig.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }

    final subjColors = <String, int>{};
    if (json['subjectCustomColors'] is Map) {
      for (final entry in (json['subjectCustomColors'] as Map).entries) {
        if (entry.value is num) {
          subjColors[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    final subjNames = <String, String>{};
    if (json['subjectCustomNames'] is Map) {
      for (final entry in (json['subjectCustomNames'] as Map).entries) {
        final v = entry.value?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          subjNames[entry.key.toString()] = v;
        }
      }
    }

    final teacherNames = <String, String>{};
    if (json['teacherCustomNames'] is Map) {
      for (final entry in (json['teacherCustomNames'] as Map).entries) {
        final v = entry.value?.toString().trim() ?? '';
        if (v.isNotEmpty) {
          teacherNames[entry.key.toString()] = v;
        }
      }
    }

    return UserProfilePrefs(
      nickname: (rawNick != null && rawNick.isNotEmpty) ? rawNick : null,
      avatarIconIndex: (json['avatarIconIndex'] as num?)?.toInt() ?? 0,
      avatarColorIndex: (json['avatarColorIndex'] as num?)?.toInt() ?? 0,
      customPhotoPath:
          (photoPath != null && photoPath.isNotEmpty) ? photoPath : null,
      themeStyle: themeStyle,
      useDynamicColor: json['useDynamicColor'] == true,
      seedColorValue: (json['seedColorValue'] as num?)?.toInt() ?? 0xFF4DA3FF,
      showWeekends: json['showWeekends'] == true,
      showCancelledLessons: json['showCancelledLessons'] != false,
      customGradeColors: gradeColors,
      roundingConfig: rounding,
      developerModeUnlocked: json['developerModeUnlocked'] == true,
      uwuModeEnabled: json['uwuModeEnabled'] == true,
      tsundereModeEnabled: json['tsundereModeEnabled'] == true,
      christmasModeEnabled: json['christmasModeEnabled'] == true,
      appIconPreset: (json['appIconPreset'] as String?) ?? 'default',
      backgroundPreset: (json['backgroundPreset'] as String?) ?? 'pure_oled',
      modalCloseMode: modalCloseMode,
      transitHomeStation:
          (json['transitHomeStation'] as String?)?.trim().isNotEmpty == true
              ? (json['transitHomeStation'] as String).trim()
              : '',
      transitSchoolStation:
          (json['transitSchoolStation'] as String?)?.trim().isNotEmpty == true
              ? (json['transitSchoolStation'] as String).trim()
              : '',
      transitAllowCoach: json['transitAllowCoach'] != false,
      transitAllowTrain: json['transitAllowTrain'] != false,
      transitAllowLocalBus: json['transitAllowLocalBus'] != false,
      walkingSpeedKmh: (json['walkingSpeedKmh'] as num?)?.toDouble() ?? 4.5,
      walkingDurationMinutes:
          (json['walkingDurationMinutes'] as num?)?.toInt() ?? 10,
      transitAlertBufferMinutes:
          (json['transitAlertBufferMinutes'] as num?)?.toInt() ?? 5,
      transitNotificationsEnabled: json['transitNotificationsEnabled'] != false,
      transitCardEnabled: json['transitCardEnabled'] == true,
      walkHomeToBusMinutes: (json['walkHomeToBusMinutes'] as num?)?.toInt().clamp(0, 60) ?? 8,
      walkHomeToTrainMinutes: (json['walkHomeToTrainMinutes'] as num?)?.toInt().clamp(0, 60) ?? 12,
      walkSchoolToBusMinutes: (json['walkSchoolToBusMinutes'] as num?)?.toInt().clamp(0, 60) ?? 5,
      walkSchoolToTrainMinutes: (json['walkSchoolToTrainMinutes'] as num?)?.toInt().clamp(0, 60) ?? 15,
      calcAllow200Weight: json['calcAllow200Weight'] == true,
      liquidGlassEnabled: _parseBool(
        json['liquidGlassEnabled'] ??
            json['cardBlurEnabled'] ??
            json['softBlur'],
      ),
      liquidGlassMode: LiquidGlassMode.fromName(json['liquidGlassMode'] as String?),
      customBackdropPath:
          (json['customBackdropPath'] as String?)?.trim().isNotEmpty == true
              ? (json['customBackdropPath'] as String).trim()
              : null,
      customBackdropDim:
          ((json['customBackdropDim'] as num?)?.toDouble() ?? 0.35)
              .clamp(0.0, 0.75),
      customBackdropLuminance:
          ((json['customBackdropLuminance'] as num?)?.toDouble() ?? 0.15)
              .clamp(0.0, 1.0),
      animatedBackdropPreset: AnimatedBackdropPreset.fromName(
        json['animatedBackdropPreset'] as String?,
      ),
      cardOpacity: ((json['cardOpacity'] as num?)?.toDouble() ?? 0.9).clamp(0.6, 1.0),
      cardBlurSigma: ((json['cardBlurSigma'] as num?)?.toDouble() ?? 4.0).clamp(2.0, 8.0),
      favoriteRoute1stPeriod:
          (json['favoriteRoute1stPeriod'] as String?) ?? '',
      favoriteRoute2ndPeriod:
          (json['favoriteRoute2ndPeriod'] as String?) ?? '',
      subjectRoundingOverrides: subjRounding,
      subjectCustomColors: subjColors,
      subjectCustomNames: subjNames,
      teacherCustomNames: teacherNames,
      extras: json['extras'] is Map
          ? Map<String, dynamic>.from(json['extras'] as Map)
          : const {},
    );
  }

  factory UserProfilePrefs.fromExportJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Érvénytelen JSON beállításfájl.');
    }
    return UserProfilePrefs.fromJson(Map<String, dynamic>.from(decoded));
  }
}

/// Represents an authenticated E-Kréta session persisted in secure storage.
class StoredSession {
  final String accessToken;
  final String refreshToken;
  final String idToken;
  final String instituteCode;
  final String? userName;
  final DateTime expiresAt;

  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.idToken,
    required this.instituteCode,
    this.userName,
    required this.expiresAt,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 2)));

  /// Creates a [StoredSession] from a [TokenGrantResponse] and extracts
  /// `kreta:institute_code` and `kreta:user_name` from the JWT claims.
  factory StoredSession.fromTokenGrant(
    TokenGrantResponse grant, {
    String? fallbackInstituteCode,
    String? fallbackIdToken,
    String? fallbackUserName,
  }) {
    final effectiveIdToken = grant.idToken.trim().isNotEmpty
        ? grant.idToken.trim()
        : (fallbackIdToken?.trim() ?? '');
    final accessClaims = KretaAuthConfig.decodeJwtPayload(grant.accessToken);
    final claims = <String, dynamic>{
      ...KretaAuthConfig.decodeJwtPayload(effectiveIdToken),
      ...accessClaims,
    };

    final claimIss =
        (claims['kreta:institute_code'] ?? claims['institute_code'])
            ?.toString()
            .trim();
    final resolvedIss = (claimIss != null && claimIss.isNotEmpty)
        ? claimIss
        : (fallbackInstituteCode?.trim() ?? '');

    if (resolvedIss.isEmpty) {
      throw const FormatException(
        'Could not determine institution code (kreta:institute_code) from JWT token.',
      );
    }

    final claimUser =
        (claims['kreta:user_name'] ?? claims['sub'])?.toString().trim();
    final resolvedUser = (claimUser != null && claimUser.isNotEmpty)
        ? claimUser
        : (fallbackUserName?.trim().isNotEmpty == true
            ? fallbackUserName!.trim()
            : null);

    final fallbackDuration =
        Duration(seconds: grant.expiresIn > 0 ? grant.expiresIn : 1800);
    DateTime expiresAt = DateTime.now().add(fallbackDuration);
    final accessExpClaim = accessClaims['exp'];
    if (accessExpClaim is num) {
      final parsedExp =
          DateTime.fromMillisecondsSinceEpoch(accessExpClaim.toInt() * 1000);
      if (parsedExp.isAfter(DateTime.now())) {
        expiresAt = parsedExp;
      }
    }

    return StoredSession(
      accessToken: grant.accessToken,
      refreshToken: refreshTokenOrEmpty(grant.refreshToken),
      idToken: effectiveIdToken,
      instituteCode: resolvedIss,
      userName: resolvedUser,
      expiresAt: expiresAt,
    );
  }

  static String refreshTokenOrEmpty(String token) => token;
}

/// Permanent, retry-verified `invalid_grant` response returned by the KRÉTA
/// OAuth2 token endpoint after cross-checking local & external token stores
/// and retrying once to rule out concurrent rotation or transient glitches.
class VerifiedInvalidGrantException extends InvalidGrantException {
  final int httpStatusCode;
  final String responseBody;
  final String caller;

  const VerifiedInvalidGrantException({
    required this.httpStatusCode,
    required this.responseBody,
    this.caller = 'TokenStorageService.refreshToken',
  }) : super();

  @override
  String toString() =>
      'VerifiedInvalidGrantException(caller: $caller, httpStatus: $httpStatusCode, body: $responseBody)';
}

/// Diagnostic snapshot persisted under SharedPreferences key
/// `'last_logout_reason'` whenever a session is cleared or redirected to
/// `LoginScreen`.
class LogoutDiagnosticEntry {
  final DateTime timestamp;
  final String caller;
  final String reason;
  final int? httpStatusCode;
  final String? errorBody;

  const LogoutDiagnosticEntry({
    required this.timestamp,
    required this.caller,
    required this.reason,
    this.httpStatusCode,
    this.errorBody,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'caller': caller,
        'reason': reason,
        if (httpStatusCode != null) 'httpStatusCode': httpStatusCode,
        if (errorBody != null && errorBody!.isNotEmpty) 'errorBody': errorBody,
      };

  factory LogoutDiagnosticEntry.fromJson(Map<String, dynamic> json) {
    return LogoutDiagnosticEntry(
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      caller: json['caller']?.toString() ?? 'unknown',
      reason: json['reason']?.toString() ?? 'Ismeretlen ok',
      httpStatusCode: json['httpStatusCode'] is num
          ? (json['httpStatusCode'] as num).toInt()
          : int.tryParse(json['httpStatusCode']?.toString() ?? ''),
      errorBody: json['errorBody']?.toString(),
    );
  }

  String toDiagnosticSummary() {
    final buf = StringBuffer()
      ..writeln('Időpont: ${timestamp.toLocal().toIso8601String()}')
      ..writeln('Hívó: $caller')
      ..writeln('Ok: $reason');
    if (httpStatusCode != null) {
      buf.writeln('HTTP státusz: $httpStatusCode');
    }
    if (errorBody != null && errorBody!.trim().isNotEmpty) {
      buf.writeln('Válasz / hiba: ${errorBody!.trim()}');
    }
    return buf.toString().trim();
  }
}

/// Manages encrypted persistence of OAuth2 tokens and user profile preferences
/// via [FlutterSecureStorage].
class TokenStorageService {
  static const _keyAccessToken = 'kreta_access_token';
  static const _keyRefreshToken = 'kreta_refresh_token';
  static const _keyIdToken = 'kreta_id_token';
  static const _keyInstituteCode = 'kreta_institute_code';
  static const _keyUserName = 'kreta_user_name';
  static const _keyExpiresAt = 'kreta_expires_at';

  static const _keyCustomNickname = 'kreta_custom_nickname';
  static const _keyAvatarIconIndex = 'kreta_avatar_icon_idx';
  static const _keyAvatarColorIndex = 'kreta_avatar_color_idx';
  static const _keyCustomPhotoPath = 'kreta_custom_photo_path';
  static const _keyThemeStyle = 'kreta_theme_style';
  static const _keyUseDynamicColor = 'kreta_use_dynamic_color';
  static const _keySeedColorValue = 'kreta_seed_color_val';
  static const _keyShowWeekends = 'kreta_show_weekends';
  static const _keyShowCancelledLessons = 'kreta_show_cancelled_lessons';
  static const _keyCustomGradeColors = 'kreta_custom_grade_colors';
  static const _keyRoundingConfig = 'kreta_rounding_config';
  static const _keyDeveloperModeUnlocked = 'kreta_dev_mode_unlocked';
  static const _keyUwuModeEnabled = 'kreta_uwu_mode_enabled';
  static const _keyTsundereModeEnabled = 'kreta_tsundere_mode_enabled';
  static const _keyChristmasModeEnabled = 'kreta_christmas_mode_enabled';
  static const _keyAppIconPreset = 'kreta_app_icon_preset';
  static const _keyBackgroundPreset = 'kreta_background_preset';
  static const _keyModalCloseMode = 'kreta_modal_close_mode';
  static const _keyTransitHomeStation = 'kreta_transit_home_station';
  static const _keyTransitSchoolStation = 'kreta_transit_school_station';
  static const _keyTransitAllowCoach = 'kreta_transit_allow_coach';
  static const _keyTransitAllowTrain = 'kreta_transit_allow_train';
  static const _keyTransitAllowLocalBus = 'kreta_transit_allow_local_bus';
  static const _keyWalkingSpeedKmh = 'kreta_walking_speed_kmh';
  static const _keyWalkingDurationMinutes = 'kreta_walking_duration_min';
  static const _keyTransitAlertBufferMinutes = 'kreta_transit_alert_buffer_min';
  static const _keyTransitNotificationsEnabled = 'kreta_transit_notifs_enabled';
  static const _keyTransitCardEnabled = 'kreta_transit_card_enabled';
  static const _keyWalkHomeToBusMinutes = 'kreta_walk_home_bus';
  static const _keyWalkHomeToTrainMinutes = 'kreta_walk_home_train';
  static const _keyWalkSchoolToBusMinutes = 'kreta_walk_school_bus';
  static const _keyWalkSchoolToTrainMinutes = 'kreta_walk_school_train';
  static const _keyCalcAllow200Weight = 'kreta_calc_allow_200';
  static const _keyLiquidGlassEnabled = 'kreta_liquid_glass_enabled';
  static const _keyCardBlurEnabled = 'kreta_card_blur_enabled';
  static const _keyLiquidGlassMode = 'kreta_liquid_glass_mode';
  static const _keyCustomBackdropPath = 'kreta_custom_backdrop_path';
  static const _keyCustomBackdropDim = 'kreta_custom_backdrop_dim';
  static const _keyCustomBackdropLuminance = 'kreta_custom_backdrop_luminance';
  static const _keyAnimatedBackdropPreset = 'kreta_animated_backdrop_preset';
  static const _keyCardOpacity = 'kreta_card_opacity';
  static const _keyCardBlurSigma = 'kreta_card_blur_sigma';
  static const _keyFavoriteRoute1stPeriod = 'kreta_fav_route_1st';
  static const _keyFavoriteRoute2ndPeriod = 'kreta_fav_route_2nd';
  static const _keySubjectRoundingOverrides = 'kreta_subj_rounding_overrides';
  static const _keySubjectCustomColors = 'kreta_subj_custom_colors';
  static const _keySubjectCustomNames = 'kreta_subj_custom_names';
  static const _keyTeacherCustomNames = 'kreta_teacher_custom_names';
  static const _keyExtras = 'kreta_extras_json';
  static const _keyReadMessageIds = 'kreta_read_message_ids';
  static const _keyDashboardCachePrefix = 'kreta_dashboard_cache_v1_';
  static const String sharedPrefsProfileKey = 'tinta_profile_prefs_v1';
  static const String _keySharedPrefsSessionBackup = 'kreta_session_backup_v2';
  static const String lastLogoutReasonKey = 'last_logout_reason';
  static const String _keyHasEverLoggedIn = 'tinta_has_ever_logged_in_v1';

  static Completer<bool>? _refreshCompleter;
  static StoredSession? _lastRefreshedSession;
  static StoredSession? get latestSession => _lastRefreshedSession;
  static final ValueNotifier<StoredSession?> sessionNotifier =
      ValueNotifier<StoredSession?>(null);

  /// Optional external fallback loader (registered on Android by
  /// `WearSyncService`) to recover rotated tokens cached natively in
  /// `WearSessionBridge` when KeyStore or Dart storage lags behind.
  static Future<StoredSession?> Function()? externalSessionFallbackLoader;

  /// Delay before retrying a suspected `invalid_grant` once to rule out
  /// concurrent rotation or transient IdP races.
  static Duration invalidGrantRetryDelay = const Duration(milliseconds: 400);

  /// Last transient storage exception encountered during [loadSession], if any.
  static String? lastStorageReadError;

  static DateTime? _lastLogoutRecordedAt;

  static String? _sanitizeDiagnosticBody(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final scrubbed = trimmed
        .replaceAll(
          RegExp(
            r'(access_token|refresh_token|id_token)"?\s*[:=]\s*"?[^",\s\}]+',
            caseSensitive: false,
          ),
          r'$1=[REDACTED]',
        )
        .replaceAll(
          RegExp(r'Bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false),
          'Bearer [REDACTED]',
        );
    return scrubbed.length > 500
        ? '${scrubbed.substring(0, 500)}…'
        : scrubbed;
  }

  /// Persists a timestamped `last_logout_reason` entry in [SharedPreferences]
  /// so Developer Options can display the exact root cause of any logout.
  static Future<void> recordLogoutReason({
    required String caller,
    required String reason,
    int? httpStatusCode,
    String? errorBody,
  }) async {
    _lastLogoutRecordedAt = DateTime.now();
    final entry = LogoutDiagnosticEntry(
      timestamp: DateTime.now(),
      caller: caller,
      reason: reason,
      httpStatusCode: httpStatusCode,
      errorBody: _sanitizeDiagnosticBody(errorBody),
    );
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(lastLogoutReasonKey, jsonEncode(entry.toJson()));
    } catch (_) {
      // Ignore in unmocked unit tests.
    }
  }

  static Future<LogoutDiagnosticEntry?> loadLastLogoutReason() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(lastLogoutReasonKey);
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return LogoutDiagnosticEntry.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
      return LogoutDiagnosticEntry(
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        caller: 'legacy',
        reason: raw,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearLastLogoutReason() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(lastLogoutReasonKey);
    } catch (_) {}
  }

  static Future<bool> hadPreviousLogin() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getBool(_keyHasEverLoggedIn) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setPreviousLoginMarker(bool loggedIn) async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (loggedIn) {
        await sp.setBool(_keyHasEverLoggedIn, true);
      } else {
        await sp.remove(_keyHasEverLoggedIn);
      }
    } catch (_) {}
  }

  /// Picks the valid [StoredSession] with non-empty credentials and the latest
  /// [StoredSession.expiresAt].
  static StoredSession? pickNewestSession(Iterable<StoredSession?> candidates) {
    StoredSession? best;
    for (final c in candidates) {
      if (c == null ||
          c.accessToken.trim().isEmpty ||
          c.refreshToken.trim().isEmpty ||
          c.instituteCode.trim().isEmpty) {
        continue;
      }
      if (best == null || c.expiresAt.isAfter(best.expiresAt)) {
        best = c;
      }
    }
    return best;
  }

  final FlutterSecureStorage _storage;

  const TokenStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> _saveSessionBackupToSharedPrefs(StoredSession session) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        _keySharedPrefsSessionBackup,
        jsonEncode({
          'accessToken': session.accessToken,
          'refreshToken': session.refreshToken,
          'idToken': session.idToken,
          'instituteCode': session.instituteCode,
          'userName': session.userName ?? '',
          'expiresAt': session.expiresAt.toIso8601String(),
        }),
      );
    } catch (_) {
      // Ignore in unmocked unit tests or platform failures.
    }
  }

  Future<StoredSession?> _loadSessionBackupFromSharedPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_keySharedPrefsSessionBackup);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final accessToken = decoded['accessToken']?.toString() ?? '';
      final refreshToken = decoded['refreshToken']?.toString() ?? '';
      final instituteCode = decoded['instituteCode']?.toString() ?? '';
      if (accessToken.isEmpty || refreshToken.isEmpty || instituteCode.isEmpty) {
        return null;
      }
      final userName = decoded['userName']?.toString();
      final expiresAt = DateTime.tryParse(
            decoded['expiresAt']?.toString() ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return StoredSession(
        accessToken: accessToken,
        refreshToken: refreshToken,
        idToken: decoded['idToken']?.toString() ?? '',
        instituteCode: instituteCode,
        userName: (userName != null && userName.isNotEmpty) ? userName : null,
        expiresAt: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(StoredSession session) async {
    _lastRefreshedSession = session;
    sessionNotifier.value = session;
    await _saveSessionBackupToSharedPrefs(session);
    await setPreviousLoginMarker(true);
    // Write sequentially to avoid Android EncryptedSharedPreferences concurrency races.
    final entries = <MapEntry<String, String>>[
      MapEntry(_keyAccessToken, session.accessToken),
      MapEntry(_keyRefreshToken, session.refreshToken),
      MapEntry(_keyIdToken, session.idToken),
      MapEntry(_keyInstituteCode, session.instituteCode),
      MapEntry(_keyUserName, session.userName ?? ''),
      MapEntry(_keyExpiresAt, session.expiresAt.toIso8601String()),
    ];
    for (final entry in entries) {
      try {
        await _storage.write(key: entry.key, value: entry.value);
      } catch (_) {}
    }
  }

  StoredSession? _parseSessionFromMap(Map<String, String?> values) {
    final accessToken = values[_keyAccessToken];
    final refreshToken = values[_keyRefreshToken];
    final instituteCode = values[_keyInstituteCode];

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty ||
        instituteCode == null ||
        instituteCode.isEmpty) {
      return null;
    }

    final expiresRaw = values[_keyExpiresAt];
    final expiresAt =
        (expiresRaw != null ? DateTime.tryParse(expiresRaw) : null) ??
            DateTime.fromMillisecondsSinceEpoch(0);
    final userName = values[_keyUserName];
    return StoredSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      idToken: values[_keyIdToken] ?? '',
      instituteCode: instituteCode,
      userName: (userName != null && userName.isNotEmpty) ? userName : null,
      expiresAt: expiresAt,
    );
  }

  Future<StoredSession?> _readSessionFromSecureStorageResilient() async {
    lastStorageReadError = null;
    try {
      final values = await _storage.readAll();
      return _parseSessionFromMap(values);
    } catch (e) {
      lastStorageReadError = e.toString();
      // Never wipe credentials on transient Android KeyStore / EncryptedSharedPreferences
      // exceptions. Wait briefly and read only the 6 auth keys individually so an
      // unrelated corrupted preference entry cannot mask valid tokens.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      try {
        final map = <String, String?>{};
        for (final key in const [
          _keyAccessToken,
          _keyRefreshToken,
          _keyIdToken,
          _keyInstituteCode,
          _keyUserName,
          _keyExpiresAt,
        ]) {
          try {
            map[key] = await _storage.read(key: key);
          } catch (keyErr) {
            lastStorageReadError = keyErr.toString();
          }
        }
        return _parseSessionFromMap(map);
      } catch (retryErr) {
        lastStorageReadError = retryErr.toString();
        return null;
      }
    }
  }

  Future<StoredSession?> loadSession() async {
    final fromSecure = await _readSessionFromSecureStorageResilient();
    final fromBackup = await _loadSessionBackupFromSharedPrefs();
    StoredSession? fromExternal;
    final extLoader = externalSessionFallbackLoader;
    if (extLoader != null) {
      try {
        fromExternal =
            await Future<StoredSession?>.value(extLoader()).timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (_) {
        fromExternal = null;
      }
    }

    final chosen = pickNewestSession([
      fromSecure,
      _lastRefreshedSession,
      fromBackup,
      fromExternal,
    ]);
    if (chosen != null) {
      _lastRefreshedSession = chosen;
      final needsBackupBackfill = fromBackup == null ||
          chosen.refreshToken != fromBackup.refreshToken ||
          chosen.accessToken != fromBackup.accessToken ||
          chosen.expiresAt.isAfter(fromBackup.expiresAt);
      if (needsBackupBackfill) {
        await _saveSessionBackupToSharedPrefs(chosen);
      }
      await setPreviousLoginMarker(true);
    }
    return chosen;
  }

  static bool _isExplicitInvalidGrantResponse(http.Response response) {
    if (response.statusCode != 400 && response.statusCode != 401) {
      return false;
    }
    String? errorCode;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        errorCode = decoded['error']?.toString().toLowerCase().trim();
      }
    } catch (_) {}
    final bodyLower = response.body.toLowerCase();
    return errorCode == 'invalid_grant' || bodyLower.contains('invalid_grant');
  }

  /// Transparently refreshes the OAuth2 access & refresh tokens using a strict
  /// single-flight lock (`_refreshCompleter`) so concurrent callers never race
  /// KRÉTA's single-use refresh token rotation. Transient network / 429 / 5xx /
  /// KeyStore failures raise regular exceptions rather than [InvalidGrantException].
  /// Only a retry-verified permanent `invalid_grant` from the auth server throws
  /// [VerifiedInvalidGrantException].
  Future<StoredSession> refreshToken({
    StoredSession? session,
    http.Client? httpClient,
    String clientId = KretaAuthConfig.clientIdIos,
  }) async {
    final existingCompleter = _refreshCompleter;
    if (existingCompleter != null) {
      final succeeded = await existingCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
      StoredSession? storedAfterWait;
      try {
        storedAfterWait = await loadSession();
      } catch (_) {}
      final latest = pickNewestSession([
        storedAfterWait,
        _lastRefreshedSession,
        session,
      ]);
      if (succeeded && latest != null) {
        return latest;
      }
      if (latest != null && !latest.isExpired) {
        return latest;
      }
      throw Exception('Concurrent token refresh did not succeed.');
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      StoredSession? stored;
      try {
        stored = await loadSession();
      } catch (_) {
        stored = null;
      }

      final active = pickNewestSession([
        stored,
        _lastRefreshedSession,
        session,
      ]);

      // If another caller already rotated and persisted a non-expired session with a
      // newer refresh/access token while we waited, return it cleanly.
      if (active != null &&
          session != null &&
          (active.accessToken != session.accessToken ||
              active.refreshToken != session.refreshToken) &&
          !active.isExpired) {
        _lastRefreshedSession = active;
        sessionNotifier.value = active;
        if (!completer.isCompleted) {
          completer.complete(true);
        }
        return active;
      }

      // Never treat a transient local storage read miss as a server invalid_grant.
      if (active == null || active.refreshToken.trim().isEmpty) {
        throw Exception(
          'Refresh token unavailable locally (storageError: ${lastStorageReadError ?? 'none'}).',
        );
      }

      final client = httpClient ?? http.Client();

      Future<http.Response> postRefresh(
        String instituteCode,
        String refreshTokenStr,
      ) {
        return client
            .post(
              Uri.parse(KretaAuthConfig.tokenEndpoint),
              headers: const {
                'Content-Type':
                    'application/x-www-form-urlencoded; charset=UTF-8',
                'Accept': '*/*',
                'User-Agent': KretaAuthConfig.userAgent,
              },
              body: {
                'institute_code': instituteCode,
                'refresh_token': refreshTokenStr,
                'grant_type': 'refresh_token',
                'client_id': clientId,
              },
            )
            .timeout(const Duration(seconds: 12));
      }

      var effectiveActive = active;
      var response = await postRefresh(
        effectiveActive.instituteCode,
        effectiveActive.refreshToken,
      );

      if (response.statusCode == 400 || response.statusCode == 401) {
        // 1. Check if another caller, background isolate, or Wear OS watch already
        // rotated and saved a newer refresh_token in the meantime.
        final latestCheck = await loadSession();
        if (latestCheck != null &&
            latestCheck.refreshToken != effectiveActive.refreshToken) {
          if (!latestCheck.isExpired) {
            _lastRefreshedSession = latestCheck;
            sessionNotifier.value = latestCheck;
            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return latestCheck;
          }
          effectiveActive = latestCheck;
          response = await postRefresh(
            effectiveActive.instituteCode,
            effectiveActive.refreshToken,
          );
        }
      }

      if (_isExplicitInvalidGrantResponse(response)) {
        // 2. Wait briefly to let any in-flight Watch/background sync settle, re-check
        // storage, and retry once before confirming permanent invalid_grant.
        if (invalidGrantRetryDelay > Duration.zero) {
          await Future<void>.delayed(invalidGrantRetryDelay);
        }
        final settledCheck = await loadSession();
        if (settledCheck != null &&
            settledCheck.refreshToken != effectiveActive.refreshToken) {
          if (!settledCheck.isExpired) {
            _lastRefreshedSession = settledCheck;
            sessionNotifier.value = settledCheck;
            if (!completer.isCompleted) {
              completer.complete(true);
            }
            return settledCheck;
          }
          effectiveActive = settledCheck;
        }
        response = await postRefresh(
          effectiveActive.instituteCode,
          effectiveActive.refreshToken,
        );
      }

      if (response.statusCode == 400 || response.statusCode == 401) {
        if (_isExplicitInvalidGrantResponse(response)) {
          throw VerifiedInvalidGrantException(
            httpStatusCode: response.statusCode,
            responseBody: response.body,
            caller: 'TokenStorageService.refreshToken',
          );
        }
        throw Exception(
          'Token refresh rejected transiently (HTTP ${response.statusCode}): ${response.body}',
        );
      }
      if (response.statusCode != 200) {
        throw Exception(
          'Transient token refresh failed (HTTP ${response.statusCode}): ${response.body}',
        );
      }

      final jsonMap =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final rawGrant = TokenGrantResponse.fromJson(jsonMap);
      final effectiveGrant = rawGrant.refreshToken.trim().isEmpty
          ? TokenGrantResponse(
              idToken: rawGrant.idToken,
              accessToken: rawGrant.accessToken,
              expiresIn: rawGrant.expiresIn,
              tokenType: rawGrant.tokenType,
              refreshToken: effectiveActive.refreshToken,
              scope: rawGrant.scope,
            )
          : rawGrant;
      final refreshed = StoredSession.fromTokenGrant(
        effectiveGrant,
        fallbackInstituteCode: effectiveActive.instituteCode,
        fallbackIdToken: effectiveActive.idToken,
        fallbackUserName: effectiveActive.userName,
      );
      await saveSession(refreshed);
      if (!completer.isCompleted) {
        completer.complete(true);
      }
      return refreshed;
    } finally {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      if (identical(_refreshCompleter, completer)) {
        _refreshCompleter = null;
      }
    }
  }

  /// Clears only the authentication tokens while preserving all user
  /// preferences, colors, nicknames, subject renames, rounding configs, and
  /// the diagnostic `last_logout_reason` record.
  Future<void> clearSession({
    String caller = 'TokenStorageService.clearSession',
    String reason = 'Munkamenet törölve',
    int? httpStatusCode,
    String? errorBody,
    bool isUserInitiated = false,
  }) async {
    final recentlyRecorded = _lastLogoutRecordedAt != null &&
        DateTime.now().difference(_lastLogoutRecordedAt!).inSeconds < 2;
    if (!recentlyRecorded) {
      await recordLogoutReason(
        caller: caller,
        reason: reason,
        httpStatusCode: httpStatusCode,
        errorBody: errorBody,
      );
    }
    if (isUserInitiated) {
      await setPreviousLoginMarker(false);
    }
    _lastRefreshedSession = null;
    sessionNotifier.value = null;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_keySharedPrefsSessionBackup);
    } catch (_) {}
    final keys = [
      _keyAccessToken,
      _keyRefreshToken,
      _keyIdToken,
      _keyInstituteCode,
      _keyUserName,
      _keyExpiresAt,
    ];
    for (final k in keys) {
      try {
        await _storage.delete(key: k);
      } catch (_) {}
    }
  }

  static Future<SharedPreferences?> _safeSharedPrefs() async {
    try {
      return await SharedPreferences.getInstance()
          .then<SharedPreferences?>((sp) => sp)
          .timeout(
            const Duration(milliseconds: 800),
            onTimeout: () => null,
          );
    } catch (_) {
      // Ignore in headless unit tests where platform channels are unmocked.
      return null;
    }
  }

  /// Persists [prefs] immediately into [SharedPreferences] so UI rebuilds and
  /// restarts see updates synchronously without awaiting slow secure-storage I/O.
  static Future<void> saveProfilePrefsToSharedPrefs(
    UserProfilePrefs prefs,
  ) async {
    try {
      final sp = await _safeSharedPrefs();
      if (sp == null) return;
      await sp.setString(sharedPrefsProfileKey, jsonEncode(prefs.toJson()));
    } catch (_) {
      // Ignore in headless unit tests where platform channels are unmocked.
    }
  }

  /// Loads persisted [UserProfilePrefs] from [SharedPreferences] if present.
  static Future<UserProfilePrefs?> loadProfilePrefsFromSharedPrefs() async {
    try {
      final sp = await _safeSharedPrefs();
      if (sp == null) return null;
      final raw = sp.getString(sharedPrefsProfileKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final loaded = UserProfilePrefs.fromJson(decoded);
        UserProfilePrefs.syncActiveGlobals(loaded);
        return loaded;
      }
      if (decoded is Map) {
        final loaded = UserProfilePrefs.fromJson(
          Map<String, dynamic>.from(decoded),
        );
        UserProfilePrefs.syncActiveGlobals(loaded);
        return loaded;
      }
    } catch (_) {}
    return null;
  }

  Future<UserProfilePrefs> loadProfilePrefs() async {
    final fromShared = await loadProfilePrefsFromSharedPrefs();
    if (fromShared != null) {
      return fromShared;
    }

    Map<String, String> values = const <String, String>{};
    try {
      values = await _storage.readAll();
    } catch (_) {
      values = const <String, String>{};
    }
    final rawNick = values[_keyCustomNickname]?.trim();
    final iconIdx = int.tryParse(values[_keyAvatarIconIndex] ?? '') ?? 0;
    final colorIdx = int.tryParse(values[_keyAvatarColorIndex] ?? '') ?? 0;
    final photoPath = values[_keyCustomPhotoPath]?.trim();

    final themeName = values[_keyThemeStyle];
    final themeStyle = AppThemeStyle.values.firstWhere(
      (e) => e.name == themeName,
      orElse: () => AppThemeStyle.oledPureBlack,
    );

    final useDynamic = values[_keyUseDynamicColor] == 'true';
    final seedColor =
        int.tryParse(values[_keySeedColorValue] ?? '') ?? 0xFF4DA3FF;
    final showWeekends = values[_keyShowWeekends] == 'true';
    final showCancelledRaw = values[_keyShowCancelledLessons];
    final showCancelledLessons =
        showCancelledRaw == null ? true : (showCancelledRaw == 'true');
    final devUnlocked = values[_keyDeveloperModeUnlocked] == 'true';
    final uwuEnabled = values[_keyUwuModeEnabled] == 'true';
    final tsundereEnabled = values[_keyTsundereModeEnabled] == 'true';
    final christmasEnabled = values[_keyChristmasModeEnabled] == 'true';
    final appIconPreset = values[_keyAppIconPreset] ?? 'default';
    final backgroundPreset = values[_keyBackgroundPreset] ?? 'pure_oled';
    final modalCloseName = values[_keyModalCloseMode];
    final modalCloseMode = ModalCloseButtonMode.values.firstWhere(
      (e) => e.name == modalCloseName,
      orElse: () => ModalCloseButtonMode.both,
    );
    final transitHomeStation =
        values[_keyTransitHomeStation]?.trim().isNotEmpty == true
            ? values[_keyTransitHomeStation]!.trim()
            : '';
    final transitSchoolStation =
        values[_keyTransitSchoolStation]?.trim().isNotEmpty == true
            ? values[_keyTransitSchoolStation]!.trim()
            : '';
    final transitAllowCoach =
        values[_keyTransitAllowCoach] == null || values[_keyTransitAllowCoach] == 'true';
    final transitAllowTrain =
        values[_keyTransitAllowTrain] == null || values[_keyTransitAllowTrain] == 'true';
    final transitAllowLocalBus =
        values[_keyTransitAllowLocalBus] == null || values[_keyTransitAllowLocalBus] == 'true';
    final walkingSpeedKmh =
        double.tryParse(values[_keyWalkingSpeedKmh] ?? '') ?? 4.5;
    final walkingDurationMinutes =
        int.tryParse(values[_keyWalkingDurationMinutes] ?? '') ?? 10;
    final transitAlertBufferMinutes =
        int.tryParse(values[_keyTransitAlertBufferMinutes] ?? '') ?? 5;
    final transitNotificationsEnabled =
        values[_keyTransitNotificationsEnabled] == null ||
            values[_keyTransitNotificationsEnabled] == 'true';
    final favoriteRoute1stPeriod =
        values[_keyFavoriteRoute1stPeriod] ?? '';
    final favoriteRoute2ndPeriod =
        values[_keyFavoriteRoute2ndPeriod] ?? '';

    UwuHelper.isEnabled = uwuEnabled;
    UwuHelper.isTsundereEnabled = tsundereEnabled;
    UserProfilePrefs.activeModalCloseMode = modalCloseMode;

    final Map<int, int> gradeColors = Map<int, int>.from(
      UserProfilePrefs.defaultGradeColors,
    );
    final rawGradeColors = values[_keyCustomGradeColors];
    if (rawGradeColors != null && rawGradeColors.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawGradeColors) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final k = int.tryParse(entry.key);
          final v = entry.value;
          if (k != null && v is int) {
            gradeColors[k] = v;
          }
        }
      } catch (_) {}
    }

    GradeRoundingConfig rounding = const GradeRoundingConfig();
    final rawRounding = values[_keyRoundingConfig];
    if (rawRounding != null && rawRounding.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawRounding) as Map<String, dynamic>;
        rounding = GradeRoundingConfig.fromJson(decoded);
      } catch (_) {}
    }

    final Map<String, GradeRoundingConfig> subjRounding = {};
    final rawSubjRounding = values[_keySubjectRoundingOverrides];
    if (rawSubjRounding != null && rawSubjRounding.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSubjRounding) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            subjRounding[entry.key] = GradeRoundingConfig.fromJson(
              entry.value as Map<String, dynamic>,
            );
          } else if (entry.value is Map) {
            subjRounding[entry.key] = GradeRoundingConfig.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
          }
        }
      } catch (_) {}
    }

    final Map<String, int> subjColors = {};
    final rawSubjColors = values[_keySubjectCustomColors];
    if (rawSubjColors != null && rawSubjColors.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSubjColors) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is num) {
            subjColors[entry.key] = (entry.value as num).toInt();
          }
        }
      } catch (_) {}
    }

    final Map<String, String> subjNames = {};
    final rawSubjNames = values[_keySubjectCustomNames];
    if (rawSubjNames != null && rawSubjNames.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSubjNames) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final v = entry.value?.toString().trim() ?? '';
          if (v.isNotEmpty) subjNames[entry.key] = v;
        }
      } catch (_) {}
    }

    final Map<String, String> teacherNames = {};
    final rawTeacherNames = values[_keyTeacherCustomNames];
    if (rawTeacherNames != null && rawTeacherNames.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTeacherNames) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final v = entry.value?.toString().trim() ?? '';
          if (v.isNotEmpty) teacherNames[entry.key] = v;
        }
      } catch (_) {}
    }

    final loaded = UserProfilePrefs(
      nickname: (rawNick != null && rawNick.isNotEmpty) ? rawNick : null,
      avatarIconIndex: iconIdx,
      avatarColorIndex: colorIdx,
      customPhotoPath:
          (photoPath != null && photoPath.isNotEmpty) ? photoPath : null,
      themeStyle: themeStyle,
      useDynamicColor: useDynamic,
      seedColorValue: seedColor,
      showWeekends: showWeekends,
      showCancelledLessons: showCancelledLessons,
      customGradeColors: gradeColors,
      roundingConfig: rounding,
      developerModeUnlocked: devUnlocked,
      uwuModeEnabled: uwuEnabled,
      tsundereModeEnabled: tsundereEnabled,
      christmasModeEnabled: christmasEnabled,
      appIconPreset: appIconPreset,
      backgroundPreset: backgroundPreset,
      modalCloseMode: modalCloseMode,
      transitHomeStation: transitHomeStation,
      transitSchoolStation: transitSchoolStation,
      transitAllowCoach: transitAllowCoach,
      transitAllowTrain: transitAllowTrain,
      transitAllowLocalBus: transitAllowLocalBus,
      walkingSpeedKmh: walkingSpeedKmh,
      walkingDurationMinutes: walkingDurationMinutes,
      transitAlertBufferMinutes: transitAlertBufferMinutes,
      transitNotificationsEnabled: transitNotificationsEnabled,
      transitCardEnabled: values[_keyTransitCardEnabled] == 'true',
      walkHomeToBusMinutes: (int.tryParse(values[_keyWalkHomeToBusMinutes] ?? '') ?? 8).clamp(0, 60),
      walkHomeToTrainMinutes: (int.tryParse(values[_keyWalkHomeToTrainMinutes] ?? '') ?? 12).clamp(0, 60),
      walkSchoolToBusMinutes: (int.tryParse(values[_keyWalkSchoolToBusMinutes] ?? '') ?? 5).clamp(0, 60),
      walkSchoolToTrainMinutes: (int.tryParse(values[_keyWalkSchoolToTrainMinutes] ?? '') ?? 15).clamp(0, 60),
      calcAllow200Weight: values[_keyCalcAllow200Weight] == 'true',
      liquidGlassEnabled:
          (values[_keyLiquidGlassEnabled] ?? values[_keyCardBlurEnabled]) ==
              'true',
      liquidGlassMode:
          LiquidGlassMode.fromName(values[_keyLiquidGlassMode]),
      customBackdropPath:
          (values[_keyCustomBackdropPath]?.trim().isNotEmpty ?? false)
              ? values[_keyCustomBackdropPath]!.trim()
              : null,
      customBackdropDim:
          (double.tryParse(values[_keyCustomBackdropDim] ?? '') ?? 0.35)
              .clamp(0.0, 0.75),
      customBackdropLuminance:
          (double.tryParse(values[_keyCustomBackdropLuminance] ?? '') ?? 0.15)
              .clamp(0.0, 1.0),
      animatedBackdropPreset: AnimatedBackdropPreset.fromName(
        values[_keyAnimatedBackdropPreset],
      ),
      cardOpacity:
          (double.tryParse(values[_keyCardOpacity] ?? '') ?? 0.9).clamp(0.6, 1.0),
      cardBlurSigma:
          (double.tryParse(values[_keyCardBlurSigma] ?? '') ?? 4.0).clamp(2.0, 8.0),
      favoriteRoute1stPeriod: favoriteRoute1stPeriod,
      favoriteRoute2ndPeriod: favoriteRoute2ndPeriod,
      subjectRoundingOverrides: subjRounding,
      subjectCustomColors: subjColors,
      subjectCustomNames: subjNames,
      teacherCustomNames: teacherNames,
      extras: _decodeExtras(values[_keyExtras]),
    );
    UserProfilePrefs.syncActiveGlobals(loaded);
    if (values.isNotEmpty) {
      await saveProfilePrefsToSharedPrefs(loaded);
    }
    return loaded;
  }

  static Map<String, dynamic> _decodeExtras(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return const {};
  }

  Future<void> saveProfilePrefs(UserProfilePrefs prefs) async {
    UwuHelper.isEnabled = prefs.uwuModeEnabled;
    UwuHelper.isTsundereEnabled = prefs.tsundereModeEnabled;
    UserProfilePrefs.syncActiveGlobals(prefs);
    await saveProfilePrefsToSharedPrefs(prefs);

    final trimmedNick = prefs.nickname?.trim() ?? '';
    final trimmedPhoto = prefs.customPhotoPath?.trim() ?? '';
    final serializedColors = jsonEncode(
      prefs.customGradeColors.map((k, v) => MapEntry(k.toString(), v)),
    );
    final serializedRounding = jsonEncode(prefs.roundingConfig.toJson());
    final serializedSubjRounding = jsonEncode(
      prefs.subjectRoundingOverrides.map((k, v) => MapEntry(k, v.toJson())),
    );
    final serializedSubjColors = jsonEncode(prefs.subjectCustomColors);
    final serializedSubjNames = jsonEncode(prefs.subjectCustomNames);
    final serializedTeacherNames = jsonEncode(prefs.teacherCustomNames);

    try {
      // Serialize writes sequentially behind the secure-storage lock instead of
      // firing ~48 parallel writes into Android EncryptedSharedPreferences,
      // preventing KeyStore/XML races with auth tokens.
      final writeOps = <MapEntry<String, String?>>[
        MapEntry(_keyExtras, jsonEncode(prefs.extras)),
        MapEntry(_keyCustomNickname, trimmedNick.isEmpty ? null : trimmedNick),
        MapEntry(_keyAvatarIconIndex, prefs.avatarIconIndex.toString()),
        MapEntry(_keyAvatarColorIndex, prefs.avatarColorIndex.toString()),
        MapEntry(_keyCustomPhotoPath, trimmedPhoto.isEmpty ? null : trimmedPhoto),
        MapEntry(_keyThemeStyle, prefs.themeStyle.name),
        MapEntry(_keyUseDynamicColor, prefs.useDynamicColor.toString()),
        MapEntry(_keySeedColorValue, prefs.seedColorValue.toString()),
        MapEntry(_keyShowWeekends, prefs.showWeekends.toString()),
        MapEntry(_keyShowCancelledLessons, prefs.showCancelledLessons.toString()),
        MapEntry(_keyCustomGradeColors, serializedColors),
        MapEntry(_keyRoundingConfig, serializedRounding),
        MapEntry(
          _keyDeveloperModeUnlocked,
          prefs.developerModeUnlocked.toString(),
        ),
        MapEntry(_keyUwuModeEnabled, prefs.uwuModeEnabled.toString()),
        MapEntry(_keyTsundereModeEnabled, prefs.tsundereModeEnabled.toString()),
        MapEntry(_keyChristmasModeEnabled, prefs.christmasModeEnabled.toString()),
        MapEntry(_keyAppIconPreset, prefs.appIconPreset),
        MapEntry(_keyBackgroundPreset, prefs.backgroundPreset),
        MapEntry(_keyModalCloseMode, prefs.modalCloseMode.name),
        MapEntry(_keyTransitHomeStation, prefs.transitHomeStation.trim()),
        MapEntry(_keyTransitSchoolStation, prefs.transitSchoolStation.trim()),
        MapEntry(_keyTransitAllowCoach, prefs.transitAllowCoach.toString()),
        MapEntry(_keyTransitAllowTrain, prefs.transitAllowTrain.toString()),
        MapEntry(
          _keyTransitAllowLocalBus,
          prefs.transitAllowLocalBus.toString(),
        ),
        MapEntry(_keyWalkingSpeedKmh, prefs.walkingSpeedKmh.toString()),
        MapEntry(
          _keyWalkingDurationMinutes,
          prefs.walkingDurationMinutes.toString(),
        ),
        MapEntry(
          _keyTransitAlertBufferMinutes,
          prefs.transitAlertBufferMinutes.toString(),
        ),
        MapEntry(
          _keyTransitNotificationsEnabled,
          prefs.transitNotificationsEnabled.toString(),
        ),
        MapEntry(
          _keyWalkHomeToBusMinutes,
          prefs.walkHomeToBusMinutes.toString(),
        ),
        MapEntry(
          _keyWalkHomeToTrainMinutes,
          prefs.walkHomeToTrainMinutes.toString(),
        ),
        MapEntry(
          _keyWalkSchoolToBusMinutes,
          prefs.walkSchoolToBusMinutes.toString(),
        ),
        MapEntry(
          _keyWalkSchoolToTrainMinutes,
          prefs.walkSchoolToTrainMinutes.toString(),
        ),
        MapEntry(_keyCalcAllow200Weight, prefs.calcAllow200Weight.toString()),
        MapEntry(_keyTransitCardEnabled, prefs.transitCardEnabled.toString()),
        MapEntry(_keyLiquidGlassEnabled, prefs.liquidGlassEnabled.toString()),
        MapEntry(_keyLiquidGlassMode, prefs.liquidGlassMode.name),
        MapEntry(
          _keyCustomBackdropPath,
          (prefs.customBackdropPath == null ||
                  prefs.customBackdropPath!.trim().isEmpty)
              ? null
              : prefs.customBackdropPath!.trim(),
        ),
        MapEntry(_keyCustomBackdropDim, prefs.customBackdropDim.toString()),
        MapEntry(
          _keyCustomBackdropLuminance,
          prefs.customBackdropLuminance.toString(),
        ),
        MapEntry(_keyAnimatedBackdropPreset, prefs.animatedBackdropPreset.name),
        MapEntry(_keyCardOpacity, prefs.cardOpacity.toString()),
        MapEntry(_keyCardBlurSigma, prefs.cardBlurSigma.toString()),
        MapEntry(_keyFavoriteRoute1stPeriod, prefs.favoriteRoute1stPeriod.trim()),
        MapEntry(_keyFavoriteRoute2ndPeriod, prefs.favoriteRoute2ndPeriod.trim()),
        MapEntry(_keySubjectRoundingOverrides, serializedSubjRounding),
        MapEntry(_keySubjectCustomColors, serializedSubjColors),
        MapEntry(_keySubjectCustomNames, serializedSubjNames),
        MapEntry(_keyTeacherCustomNames, serializedTeacherNames),
      ];
      for (final op in writeOps) {
        try {
          if (op.value == null) {
            await _storage.delete(key: op.key);
          } else {
            await _storage.write(key: op.key, value: op.value!);
          }
        } catch (_) {}
      }
    } catch (_) {
      // SharedPreferences mirror above has already succeeded.
    }
  }

  /// Builds a stable per-account key used to scope locally cached read message IDs.
  static String accountKeyForSession(StoredSession? session) {
    if (session == null) return 'default';
    final inst = session.instituteCode.trim();
    final user = (session.userName ?? 'default').trim();
    return '${inst.isEmpty ? 'default' : inst}|${user.isEmpty ? 'default' : user}';
  }

  /// Loads locally persisted read message keys for [accountKey].
  Future<Set<String>> loadReadMessageIds({String? accountKey}) async {
    final key = (accountKey == null || accountKey.trim().isEmpty)
        ? 'default'
        : accountKey.trim();
    try {
      final raw = await _storage.read(key: _keyReadMessageIds);
      if (raw == null || raw.isEmpty) return <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final bucket = decoded[key];
        if (bucket is List) {
          return bucket
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toSet();
        }
      }
    } catch (_) {}
    return <String>{};
  }

  /// Persists [messageKeys] as read locally for [accountKey] so system messages
  /// and offline views stay marked read across app restarts.
  Future<void> markMessagesReadLocally(
    Iterable<String> messageKeys, {
    String? accountKey,
  }) async {
    final cleanKeys = messageKeys
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (cleanKeys.isEmpty) return;

    final acct = (accountKey == null || accountKey.trim().isEmpty)
        ? 'default'
        : accountKey.trim();
    try {
      final map = <String, List<String>>{};
      final raw = await _storage.read(key: _keyReadMessageIds);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.value is List) {
              map[entry.key.toString()] = (entry.value as List)
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
          }
        }
      }
      final existing = map[acct] ?? <String>[];
      final merged = <String>{...existing, ...cleanKeys}.toList();
      const maxStoredIds = 2500;
      map[acct] = merged.length > maxStoredIds
          ? merged.sublist(merged.length - maxStoredIds)
          : merged;
      await _storage.write(
        key: _keyReadMessageIds,
        value: jsonEncode(map),
      );
    } catch (_) {}
  }

  /// Persists serialized dashboard cache JSON scoped per account.
  Future<void> saveDashboardCacheJson(
    String accountKey,
    String jsonPayload,
  ) async {
    try {
      await _storage.write(
        key: '$_keyDashboardCachePrefix$accountKey',
        value: jsonPayload,
      );
    } catch (_) {}
  }

  /// Loads cached dashboard JSON scoped per account, or `null` if unavailable.
  Future<String?> loadDashboardCacheJson(String accountKey) async {
    try {
      return await _storage.read(key: '$_keyDashboardCachePrefix$accountKey');
    } catch (_) {
      return null;
    }
  }

  /// Removes cached dashboard JSON for [accountKey].
  Future<void> clearDashboardCache(String accountKey) async {
    try {
      await _storage.delete(key: '$_keyDashboardCachePrefix$accountKey');
    } catch (_) {}
  }
}
