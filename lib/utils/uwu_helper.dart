/// Global UwU and Tsundere text transformers for reKRETA's Developer Mode Easter Eggs.
class UwuHelper {
  /// Synchronized with `UserProfilePrefs.uwuModeEnabled`.
  static bool isEnabled = false;

  /// Synchronized with `UserProfilePrefs.tsundereModeEnabled`.
  static bool isTsundereEnabled = false;

  static const List<String> _suffixes = [
    'uwu',
    ':3',
    'owo',
    '>w<',
    'nya~',
  ];

  static const List<String> tsundereAlerts = [
    'N-nem mintha érdekelne a házi feladatod, b-baka~!',
    'M-megint egy hármas? Nem mintha figyeltem volna rád, h-hülye...~',
    'N-nehogy azt hidd, hogy miattad töltöttem be az órarendedet, b-baka~!',
    'H-hmph~! N-ne bámulj így a jegyeidre, b-baka~!',
    'A-ahh~... nem miattad frissítettem ám az adatokat, csak unatkoztam~!',
  ];

  /// Returns an expressive Tsundere comment for a grade or alert.
  static String tsundereCommentForGrade(int? grade) {
    switch (grade) {
      case 5:
        return 'Ö-ötös?! N-nehogy azt hidd, hogy büszke vagyok rád vagy ilyesmi, b-baka~!';
      case 4:
        return 'N-négyes~? Pff, tudnál te ennél jobbat is... n-nem mintha érdekelne, b-baka~!';
      case 3:
        return 'M-megint egy hármas? Nem mintha figyeltem volna rád, h-hülye...~';
      case 2:
        return 'K-kettes?! H-hé, tanulj már egy kicsit... n-nem mintha aggódnék érted, b-baka~!';
      case 1:
        return 'E-egyes?! B-baka~! A-azonnal ülj le tanulni, de n-nehogy azt hidd, hogy érdekel~!';
      default:
        return 'N-nem mintha érdekelne a házi feladatod, b-baka~!';
    }
  }

  /// Convenience alias for [transform].
  static String apply(
    String input, {
    bool? enabled,
    bool? tsundere,
  }) =>
      transform(input, enabled: enabled, tsundere: tsundere);

  /// Transforms [input] with cute UwU phonetic replacements or Tsundere sassy
  /// overrides when enabled.
  static String transform(
    String input, {
    bool? enabled,
    bool? tsundere,
  }) {
    if (input.trim().isEmpty) {
      return input;
    }

    final tsundereActive = tsundere ?? isTsundereEnabled;
    if (tsundereActive && enabled != true) {
      return _transformTsundere(input);
    }

    final active = enabled ?? isEnabled;
    if (!active) {
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

  static String _transformTsundere(String input) {
    if (input.contains('Házik') || input.contains('Házi feladat')) {
      return '$input (n-nem mintha érdekelne, b-baka~!)';
    }
    if (input.contains('Nincs megjeleníthető elem')) {
      return 'N-nincs itt semmi~! N-nehogy azt hidd, hogy neked kerestem, b-baka~!';
    }
    if (input.contains('Mára vége az óráknak')) {
      return 'M-mára vége az óráknak~! N-nehogy azt hidd, hogy hiányozni fogsz, b-baka~!';
    }
    if (input.contains('A legfrissebb verziót használod')) {
      return 'M-már a legújabb verzión vagy, b-baka~! M-minek nyomkodod~?!';
    }
    if (input.contains('Aktivitási hírfolyam')) {
      return 'A-aktivitási hírfolyam (H-hmph~!)';
    }
    if (input.contains('Következő óra')) {
      return 'K-következő óra (N-ne késs el, b-baka~!)';
    }
    if (input.contains('Tanulmányi átlag')) {
      return 'T-tanulmányi átlag (H-hmph~)';
    }
    // Add subtle stutter & trailing tilde to longer sentences when Tsundere mode is active
    if (input.length > 14 && !input.endsWith('~') && !input.endsWith('~!')) {
      final firstChar = input[0];
      if (RegExp(r'[A-ZÁÉÍÓÖŐÚÜŰ]').hasMatch(firstChar)) {
        return '$firstChar-${input.toLowerCase()[0]}${input.substring(1)}~';
      }
    }
    return input;
  }
}

/// Shorthand global helper for UwU / Tsundere text transformation.
String uwu(String text, {bool? enabled, bool? tsundere}) =>
    UwuHelper.transform(text, enabled: enabled, tsundere: tsundere);
