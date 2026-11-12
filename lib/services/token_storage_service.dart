import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:kreta_api/kreta_api.dart';

import '../core/kreta_auth_config.dart';
import '../utils/uwu_helper.dart';

/// Supported visual theme styles in Tinta Napló.
enum AppThemeStyle {
  oledPureBlack,
  standardDark,
  light,
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
  static bool activeSoftBlurEnabled = false;
  static double activeSoftBlurSigma = 4.0;

  static void syncActiveGlobals(UserProfilePrefs prefs) {
    activeModalCloseMode = prefs.modalCloseMode;
    activeSoftBlurEnabled = prefs.cardBlurEnabled;
    activeSoftBlurSigma = prefs.cardBlurSigma;
  }

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
  final bool cardBlurEnabled;
  final double cardOpacity;
  final double cardBlurSigma;
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
    this.cardBlurEnabled = false,
    this.cardOpacity = 0.9,
    this.cardBlurSigma = 4.0,
    this.favoriteRoute1stPeriod = '',
    this.favoriteRoute2ndPeriod = '',
    this.subjectRoundingOverrides = const {},
    this.subjectCustomColors = const {},
    this.subjectCustomNames = const {},
    this.teacherCustomNames = const {},
    this.extras = const {},
  });

  // ---- v1.0.0 typed accessors over [extras] --------------------------------
  /// "Elmaradó órák elrejtése" (falls back to the legacy single filter).
  bool get hideCancelledLessons =>
      (extras['hideCancelledLessons'] as bool?) ?? !showCancelledLessons;

  /// "Lyukas / szabad órák elrejtése" (falls back to the legacy single filter).
  bool get hideFreeLessons =>
      (extras['hideFreeLessons'] as bool?) ?? !showCancelledLessons;

  /// `true` => "Ágazati alapoktatás (9–10. évf.)", `false` => "Szakirányú oktatás".
  bool get scholarshipBasicEducation => extras['scholarshipBasic'] == true;

  /// `technikum` or `szakkepzo`.
  String get scholarshipSchoolType =>
      extras['scholarshipSchoolType'] == 'szakkepzo' ? 'szakkepzo' : 'technikum';

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
    bool? cardBlurEnabled,
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
      cardBlurEnabled: cardBlurEnabled ?? this.cardBlurEnabled,
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
      'cardBlurEnabled': cardBlurEnabled,
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
      cardBlurEnabled: json['cardBlurEnabled'] == true,
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
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  /// Creates a [StoredSession] from a [TokenGrantResponse] and extracts
  /// `kreta:institute_code` and `kreta:user_name` from the JWT claims.
  factory StoredSession.fromTokenGrant(
    TokenGrantResponse grant, {
    String? fallbackInstituteCode,
  }) {
    final claims = <String, dynamic>{
      ...KretaAuthConfig.decodeJwtPayload(grant.idToken),
      ...KretaAuthConfig.decodeJwtPayload(grant.accessToken),
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

    DateTime expiresAt = DateTime.now().add(Duration(seconds: grant.expiresIn));
    final expClaim = claims['exp'];
    if (expClaim is int) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expClaim * 1000);
    }

    return StoredSession(
      accessToken: grant.accessToken,
      refreshToken: refreshTokenOrEmpty(grant.refreshToken),
      idToken: grant.idToken,
      instituteCode: resolvedIss,
      userName: claimUser,
      expiresAt: expiresAt,
    );
  }

  static String refreshTokenOrEmpty(String token) => token;
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
  static const _keyCardBlurEnabled = 'kreta_card_blur_enabled';
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

  final FlutterSecureStorage _storage;

  const TokenStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  Future<void> saveSession(StoredSession session) async {
    await Future.wait([
      _storage.write(key: _keyAccessToken, value: session.accessToken),
      _storage.write(key: _keyRefreshToken, value: session.refreshToken),
      _storage.write(key: _keyIdToken, value: session.idToken),
      _storage.write(key: _keyInstituteCode, value: session.instituteCode),
      _storage.write(key: _keyUserName, value: session.userName ?? ''),
      _storage.write(
        key: _keyExpiresAt,
        value: session.expiresAt.toIso8601String(),
      ),
    ]);
  }

  Future<StoredSession?> loadSession() async {
    final values = await _storage.readAll();
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

  /// Transparently refreshes the OAuth2 access & refresh tokens in the background,
  /// updates the stored session in [FlutterSecureStorage], and returns the new [StoredSession].
  Future<StoredSession> refreshToken({
    StoredSession? session,
    http.Client? httpClient,
    String clientId = KretaAuthConfig.clientIdIos,
  }) async {
    final active = session ?? await loadSession();
    if (active == null || active.refreshToken.isEmpty) {
      throw const TokenExpiredException();
    }

    final client = httpClient ?? http.Client();
    final response = await client.post(
      Uri.parse(KretaAuthConfig.tokenEndpoint),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Accept': '*/*',
        'User-Agent': KretaAuthConfig.userAgent,
      },
      body: {
        'institute_code': active.instituteCode,
        'refresh_token': active.refreshToken,
        'grant_type': 'refresh_token',
        'client_id': clientId,
      },
    );

    if (response.statusCode == 400) {
      throw const TokenExpiredException();
    }
    if (response.statusCode == 401) {
      throw const InvalidGrantException();
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Token refresh failed (HTTP ${response.statusCode}): ${response.body}',
      );
    }

    final jsonMap =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final grant = TokenGrantResponse.fromJson(jsonMap);
    final refreshed = StoredSession.fromTokenGrant(
      grant,
      fallbackInstituteCode: active.instituteCode,
    );
    await saveSession(refreshed);
    return refreshed;
  }

  /// Clears only the authentication tokens while preserving all user
  /// preferences, colors, nicknames, subject renames, and rounding configs.
  Future<void> clearSession() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyIdToken),
      _storage.delete(key: _keyInstituteCode),
      _storage.delete(key: _keyUserName),
      _storage.delete(key: _keyExpiresAt),
    ]);
  }

  Future<UserProfilePrefs> loadProfilePrefs() async {
    final values = await _storage.readAll();
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
      cardBlurEnabled: values[_keyCardBlurEnabled] == 'true',
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

    await Future.wait([
      _storage.write(key: _keyExtras, value: jsonEncode(prefs.extras)),
      if (trimmedNick.isEmpty)
        _storage.delete(key: _keyCustomNickname)
      else
        _storage.write(key: _keyCustomNickname, value: trimmedNick),
      _storage.write(
        key: _keyAvatarIconIndex,
        value: prefs.avatarIconIndex.toString(),
      ),
      _storage.write(
        key: _keyAvatarColorIndex,
        value: prefs.avatarColorIndex.toString(),
      ),
      if (trimmedPhoto.isEmpty)
        _storage.delete(key: _keyCustomPhotoPath)
      else
        _storage.write(key: _keyCustomPhotoPath, value: trimmedPhoto),
      _storage.write(key: _keyThemeStyle, value: prefs.themeStyle.name),
      _storage.write(
        key: _keyUseDynamicColor,
        value: prefs.useDynamicColor.toString(),
      ),
      _storage.write(
        key: _keySeedColorValue,
        value: prefs.seedColorValue.toString(),
      ),
      _storage.write(
        key: _keyShowWeekends,
        value: prefs.showWeekends.toString(),
      ),
      _storage.write(
        key: _keyShowCancelledLessons,
        value: prefs.showCancelledLessons.toString(),
      ),
      _storage.write(key: _keyCustomGradeColors, value: serializedColors),
      _storage.write(key: _keyRoundingConfig, value: serializedRounding),
      _storage.write(
        key: _keyDeveloperModeUnlocked,
        value: prefs.developerModeUnlocked.toString(),
      ),
      _storage.write(
        key: _keyUwuModeEnabled,
        value: prefs.uwuModeEnabled.toString(),
      ),
      _storage.write(
        key: _keyTsundereModeEnabled,
        value: prefs.tsundereModeEnabled.toString(),
      ),
      _storage.write(
        key: _keyChristmasModeEnabled,
        value: prefs.christmasModeEnabled.toString(),
      ),
      _storage.write(
        key: _keyAppIconPreset,
        value: prefs.appIconPreset,
      ),
      _storage.write(
        key: _keyBackgroundPreset,
        value: prefs.backgroundPreset,
      ),
      _storage.write(
        key: _keyModalCloseMode,
        value: prefs.modalCloseMode.name,
      ),
      _storage.write(
        key: _keyTransitHomeStation,
        value: prefs.transitHomeStation.trim(),
      ),
      _storage.write(
        key: _keyTransitSchoolStation,
        value: prefs.transitSchoolStation.trim(),
      ),
      _storage.write(
        key: _keyTransitAllowCoach,
        value: prefs.transitAllowCoach.toString(),
      ),
      _storage.write(
        key: _keyTransitAllowTrain,
        value: prefs.transitAllowTrain.toString(),
      ),
      _storage.write(
        key: _keyTransitAllowLocalBus,
        value: prefs.transitAllowLocalBus.toString(),
      ),
      _storage.write(
        key: _keyWalkingSpeedKmh,
        value: prefs.walkingSpeedKmh.toString(),
      ),
      _storage.write(
        key: _keyWalkingDurationMinutes,
        value: prefs.walkingDurationMinutes.toString(),
      ),
      _storage.write(
        key: _keyTransitAlertBufferMinutes,
        value: prefs.transitAlertBufferMinutes.toString(),
      ),
      _storage.write(
        key: _keyTransitNotificationsEnabled,
        value: prefs.transitNotificationsEnabled.toString(),
      ),
      _storage.write(key: _keyWalkHomeToBusMinutes, value: prefs.walkHomeToBusMinutes.toString()),
      _storage.write(key: _keyWalkHomeToTrainMinutes, value: prefs.walkHomeToTrainMinutes.toString()),
      _storage.write(key: _keyWalkSchoolToBusMinutes, value: prefs.walkSchoolToBusMinutes.toString()),
      _storage.write(key: _keyWalkSchoolToTrainMinutes, value: prefs.walkSchoolToTrainMinutes.toString()),
      _storage.write(key: _keyCalcAllow200Weight, value: prefs.calcAllow200Weight.toString()),
      _storage.write(
        key: _keyTransitCardEnabled,
        value: prefs.transitCardEnabled.toString(),
      ),
      _storage.write(
        key: _keyCardBlurEnabled,
        value: prefs.cardBlurEnabled.toString(),
      ),
      _storage.write(
        key: _keyCardOpacity,
        value: prefs.cardOpacity.toString(),
      ),
      _storage.write(
        key: _keyCardBlurSigma,
        value: prefs.cardBlurSigma.toString(),
      ),
      _storage.write(
        key: _keyFavoriteRoute1stPeriod,
        value: prefs.favoriteRoute1stPeriod.trim(),
      ),
      _storage.write(
        key: _keyFavoriteRoute2ndPeriod,
        value: prefs.favoriteRoute2ndPeriod.trim(),
      ),
      _storage.write(
        key: _keySubjectRoundingOverrides,
        value: serializedSubjRounding,
      ),
      _storage.write(
        key: _keySubjectCustomColors,
        value: serializedSubjColors,
      ),
      _storage.write(
        key: _keySubjectCustomNames,
        value: serializedSubjNames,
      ),
      _storage.write(
        key: _keyTeacherCustomNames,
        value: serializedTeacherNames,
      ),
    ]);
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
