import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../widgets/christmas_snowfall_overlay.dart';
import 'token_storage_service.dart';

/// Lightweight platform channel service that switches the active Android
/// `<activity-alias>` launcher icon via `PackageManager.setComponentEnabledSetting`.
class DynamicIconService {
  static const MethodChannel _channel = MethodChannel(
    'hu.rekreta.rekreta_app/dynamic_icon',
  );

  static String? _lastSyncedIconId;

  /// Resolves the active icon preset for [prefs] and updates the Android
  /// launcher `<activity-alias>` if running on Android.
  static Future<void> syncIconWithPrefs(UserProfilePrefs prefs) async {
    final preset = AppIconPresetInfo.resolve(prefs);
    await setAppIcon(preset.id);
  }

  /// Switches the active Android launcher icon to [iconId]
  /// (`icon_normal`, `icon_oled`, `icon_christmas`, or `icon_christmas_oled`).
  static Future<String?> setAppIcon(String iconId) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _lastSyncedIconId = iconId;
      return null;
    }
    if (_lastSyncedIconId == iconId) {
      return null;
    }
    try {
      final preset = AppIconPresetInfo.fromId(iconId);
      final appliedAlias = await _channel.invokeMethod<String>(
        'setAppIcon',
        <String, dynamic>{
          'iconName': preset.id,
          'alias': preset.activityAlias,
        },
      );
      _lastSyncedIconId = preset.id;
      return appliedAlias;
    } catch (_) {
      // Ignore MissingPluginException in widget tests or non-Android hosts.
      return null;
    }
  }

  /// Queries the currently enabled `<activity-alias>` from the Android PackageManager.
  static Future<String?> getActiveAlias() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('getAppIcon');
    } catch (_) {
      return null;
    }
  }
}
