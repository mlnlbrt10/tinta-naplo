import 'uwu_helper.dart';

/// Time-based Hungarian greeting and student name resolution utilities.
class GreetingUtils {
  /// Resolves the display name for the greeting:
  /// 1. Uses [customNickname] if non-empty.
  /// 2. Extracts the first/given name from [fullStudentName] if available
  ///    (in Hungarian "Vezetéknév Keresztnév" order, the given name is the second token).
  /// 3. Falls back to [defaultFirstName] ("Milán").
  static String resolveDisplayName({
    String? customNickname,
    String? fullStudentName,
    String defaultFirstName = 'Milán',
  }) {
    final trimmedNick = customNickname?.trim() ?? '';
    if (trimmedNick.isNotEmpty) {
      return trimmedNick;
    }

    final trimmedFull = fullStudentName?.trim() ?? '';
    if (trimmedFull.isNotEmpty) {
      final parts = trimmedFull
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty && !p.endsWith('.'))
          .toList();
      if (parts.length >= 2) {
        return parts[1];
      }
      if (parts.isNotEmpty) {
        return parts.first;
      }
    }

    return defaultFirstName;
  }

  /// Returns the dynamic Hungarian greeting based on [now]:
  /// * 04:00 – 07:59: `"Szép reggelt, <name>!"`
  /// * 08:00 – 17:59: `"Szép napot, <name>!"`
  /// * 18:00 – 21:59: `"Szép estét, <name>!"`
  /// * 22:00 – 03:59: `"Jó éjszakát, <name>!"`
  ///
  /// When [uwuMode] (or `UwuHelper.isEnabled`) is active, transforms greetings
  /// into cute UwU variants (e.g. `"szép nyapot, <name>! uwu"`, `"jó éccakát, <name>! :3"`).
  static String buildGreeting({
    required String name,
    DateTime? now,
    bool? uwuMode,
  }) {
    final isUwu = uwuMode ?? UwuHelper.isEnabled;
    final hour = (now ?? DateTime.now()).hour;

    if (isUwu) {
      final uwuName = UwuHelper.transform(name, enabled: true)
          .replaceAll(RegExp(r'\s+(uwu|:3|owo|>w<|nya~)$'), '');
      if (hour >= 4 && hour <= 7) {
        return 'Szép weggewt, $uwuName! nya~';
      } else if (hour >= 8 && hour <= 17) {
        return 'Szép nyapot, $uwuName! uwu';
      } else if (hour >= 18 && hour <= 21) {
        return 'Szép estét, $uwuName! >w<';
      } else {
        return 'Jó éccakát, $uwuName! :3';
      }
    }

    if (hour >= 4 && hour <= 7) {
      return 'Szép reggelt, $name!';
    } else if (hour >= 8 && hour <= 17) {
      return 'Szép napot, $name!';
    } else if (hour >= 18 && hour <= 21) {
      return 'Szép estét, $name!';
    } else {
      return 'Jó éjszakát, $name!';
    }
  }
}
