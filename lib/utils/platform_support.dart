import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Returns `true` when running on Android (or when running headless Flutter
/// widget/unit tests on a desktop host whose [defaultTargetPlatform] is
/// [TargetPlatform.android]). Returns `false` on iOS and Web.
bool get isAndroidPlatform {
  if (kIsWeb) return false;
  if (Platform.isAndroid) return true;
  if (Platform.isIOS) return false;
  return defaultTargetPlatform == TargetPlatform.android;
}

/// Returns `true` when running on iOS (or when a Flutter test explicitly sets
/// `debugDefaultTargetPlatformOverride = TargetPlatform.iOS`).
bool get isIOSPlatform {
  if (kIsWeb) return false;
  if (Platform.isIOS) return true;
  if (Platform.isAndroid) return false;
  return defaultTargetPlatform == TargetPlatform.iOS;
}
