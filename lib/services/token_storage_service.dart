import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kreta_api/kreta_api.dart';

import '../core/kreta_auth_config.dart';

/// Supported visual theme styles in reKRETA.
enum AppThemeStyle {
  oledPureBlack,
  standardDark,
  light,
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
class UserProfilePrefs {
  final String? nickname;
  final int avatarIconIndex;
  final int avatarColorIndex;
  final String? customPhotoPath;
  final AppThemeStyle themeStyle;
  final bool useDynamicColor;
  final int seedColorValue;
  final bool showWeekends;
  final Map<int, int> customGradeColors;
  final GradeRoundingConfig roundingConfig;

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
    this.customGradeColors = defaultGradeColors,
    this.roundingConfig = const GradeRoundingConfig(),
  });

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
    Map<int, int>? customGradeColors,
    GradeRoundingConfig? roundingConfig,
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
      customGradeColors: customGradeColors ?? this.customGradeColors,
      roundingConfig: roundingConfig ?? this.roundingConfig,
    );
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
  static const _keyCustomGradeColors = 'kreta_custom_grade_colors';
  static const _keyRoundingConfig = 'kreta_rounding_config';

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

    Map<int, int> gradeColors = Map<int, int>.from(
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

    return UserProfilePrefs(
      nickname: (rawNick != null && rawNick.isNotEmpty) ? rawNick : null,
      avatarIconIndex: iconIdx,
      avatarColorIndex: colorIdx,
      customPhotoPath:
          (photoPath != null && photoPath.isNotEmpty) ? photoPath : null,
      themeStyle: themeStyle,
      useDynamicColor: useDynamic,
      seedColorValue: seedColor,
      showWeekends: showWeekends,
      customGradeColors: gradeColors,
      roundingConfig: rounding,
    );
  }

  Future<void> saveProfilePrefs(UserProfilePrefs prefs) async {
    final trimmedNick = prefs.nickname?.trim() ?? '';
    final trimmedPhoto = prefs.customPhotoPath?.trim() ?? '';
    final serializedColors = jsonEncode(
      prefs.customGradeColors.map((k, v) => MapEntry(k.toString(), v)),
    );
    final serializedRounding = jsonEncode(prefs.roundingConfig.toJson());

    await Future.wait([
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
      _storage.write(key: _keyCustomGradeColors, value: serializedColors),
      _storage.write(key: _keyRoundingConfig, value: serializedRounding),
    ]);
  }
}
