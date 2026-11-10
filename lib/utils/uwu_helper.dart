/// Global UwU / Kawaii phonetic text transformer for reKRETA's Developer Mode Easter Egg.
class UwuHelper {
  /// Synchronized with `UserProfilePrefs.uwuModeEnabled`.
  static bool isEnabled = false;

  static const List<String> _suffixes = [
    'uwu',
    ':3',
    'owo',
    '>w<',
    'nya~',
  ];

  /// Transforms [input] with cute UwU phonetic replacements when [enabled]
  /// (or [isEnabled]) is true; returns [input] unchanged otherwise.
  static String transform(String input, {bool? enabled}) {
    final active = enabled ?? isEnabled;
    if (!active || input.trim().isEmpty) {
      return input;
    }

    // Specific phrase overrides requested in spec
    String out = input
        .replaceAll('Szép napot', 'Szép nyapot')
        .replaceAll('szép napot', 'szép nyapot')
        .replaceAll('Jó éjszakát', 'Jó éccakát')
        .replaceAll('jó éjszakát', 'jó éccakát')
        .replaceAll('Szép reggelt', 'Szép weggewt')
        .replaceAll('Szép estét', 'Szép estét');

    // Phonetic replacements: 'r'/'l' -> 'w', 'th' -> 'd', 'na/no/ne' -> 'nya/nyo/nye'
    out = out
        .replaceAll('th', 'd')
        .replaceAll('Th', 'D')
        .replaceAll('TH', 'D')
        .replaceAll(RegExp(r'n([aeiouáéíóöőúüű])'), r'ny$1')
        .replaceAll(RegExp(r'N([aeiouáéíóöőúüű])'), r'Ny$1')
        .replaceAll('r', 'w')
        .replaceAll('l', 'w')
        .replaceAll('R', 'W')
        .replaceAll('L', 'W');

    // Avoid duplicating suffixes if already present
    final lower = out.toLowerCase();
    for (final s in _suffixes) {
      if (lower.endsWith(s)) {
        return out;
      }
    }

    // Deterministically append a cute suffix to longer phrases or titles
    if (input.length >= 6) {
      final suffix = _suffixes[input.hashCode.abs() % _suffixes.length];
      return '$out $suffix';
    }
    return out;
  }
}

/// Shorthand global helper for UwU text transformation.
String uwu(String text, {bool? enabled}) =>
    UwuHelper.transform(text, enabled: enabled);
