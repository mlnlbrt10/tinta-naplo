import 'package:flutter/services.dart';

import '../utils/platform_support.dart';
import '../widgets/christmas_snowfall_overlay.dart';
import 'token_storage_service.dart';

/// Lightweight platform channel service that switches the active Android
/// `<activity-alias>` launcher icon via `PackageManager.setComponentEnabledSetting`.
class DynamicIconService {
  static const MethodChannel _channel = MethodChannel(
    'hu.mlnlbrt.tintanaplo/dynamic_icon',
  );

  static String? _lastSyncedIconId;
  static String? _pendingIconId;
  static int _requestEpoch = 0;

  /// Resolves the active icon preset for [prefs] and updates the Android
  /// launcher `<activity-alias>` if running on Android.
  static Future<void> syncIconWithPrefs(UserProfilePrefs prefs) async {
    final preset = AppIconPresetInfo.resolve(prefs);
    await setAppIcon(preset.id);
  }

  /// Switches the active Android launcher icon to [iconId]
  /// (`default` / `icon_normal`, `classic`, `icon_oled`, `icon_christmas`,
  /// `icon_christmas_oled`, or `icon_fityma`).
  static Future<String?> setAppIcon(String iconId) async {
    if (!isAndroidPlatform) {
      _lastSyncedIconId = iconId;
      return null;
    }
    if (_lastSyncedIconId == iconId || _pendingIconId == iconId) {
      return null;
    }
    final epoch = ++_requestEpoch;
    _pendingIconId = iconId;
    try {
      final preset = AppIconPresetInfo.fromId(iconId);
      final isFityma =
          iconId == 'icon_fityma' || iconId == '.MainActivityFityma';
      final isClassic = iconId == 'classic' ||
          iconId == 'icon_classic' ||
          iconId == '.MainActivityClassic';
      final appliedAlias = await _channel.invokeMethod<String>(
        'setAppIcon',
        <String, dynamic>{
          'iconName': isFityma
              ? 'icon_fityma'
              : (isClassic ? 'classic' : preset.id),
          'alias': isFityma
              ? '.MainActivityFityma'
              : (isClassic ? '.MainActivityClassic' : preset.activityAlias),
        },
      );
      if (epoch == _requestEpoch) {
        _lastSyncedIconId = isFityma
            ? 'icon_fityma'
            : (isClassic ? 'classic' : preset.id);
        _pendingIconId = null;
      }
      return appliedAlias;
    } catch (_) {
      if (epoch == _requestEpoch) {
        _pendingIconId = null;
      }
      // Ignore MissingPluginException in widget tests or non-Android hosts.
      return null;
    }
  }

  /// Queries the currently enabled `<activity-alias>` from the Android PackageManager.
  static Future<String?> getActiveAlias() async {
    if (!isAndroidPlatform) {
      return null;
    }
    try {
      return await _channel.invokeMethod<String>('getAppIcon');
    } catch (_) {
      return null;
    }
  }
}
