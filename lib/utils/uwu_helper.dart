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
    'Nem mintha érdekelne a házi feladatod, b-baka!',
    'Megint hármas? Nem mintha figyeltem volna...',
    'Csak véletlenül töltöttem be az órarendedet, ne bízd el magad!',
    'H-hmph! Ne bámulj így a jegyeidre, b-baka!',
    'Nem miattad frissítettem ám az adatokat... csak unatkoztam!',
  ];

  /// Returns a sassy Tsundere comment for a grade or alert.
  static String tsundereCommentForGrade(int? grade) {
    switch (grade) {
      case 5:
        return 'Ötös?! N-nem mintha büszke lennék rád vagy ilyesmi, b-baka!';
      case 4:
        return 'Négyes? Pff, tudnál te ennél jobbat is... nem mintha érdekelne!';
      case 3:
        return 'Megint hármas? Nem mintha figyeltem volna...';
      case 2:
        return 'Kettes?! H-hé, tanulj már egy kicsit... nem mintha aggódnék érted, b-baka!';
      case 1:
        return 'Egyes?! B-baka! Azonnal ülj le tanulni, de nem azért mondom, mert érdekel!';
      default:
        return 'Nem mintha érdekelne a házi feladatod, b-baka!';
    }
  }

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
      return '$input (nem mintha érdekelne, b-baka!)';
    }
    if (input.contains('Nincs megjeleníthető elem')) {
      return 'Nincs itt semmi! Nem mintha neked kerestem volna, b-baka!';
    }
    if (input.contains('Mára vége az óráknak')) {
      return 'Mára vége az óráknak! Ne hidd, hogy hiányozni fogsz, b-baka!';
    }
    if (input.contains('A legfrissebb verziót használod')) {
      return 'Már a legújabb verzión vagy, b-baka! Minek nyomkodod?!';
    }
    if (input.contains('Aktivitási hírfolyam')) {
      return 'Aktivitási hírfolyam (Hmph!)';
    }
    return input;
  }
}

/// Shorthand global helper for UwU / Tsundere text transformation.
String uwu(String text, {bool? enabled, bool? tsundere}) =>
    UwuHelper.transform(text, enabled: enabled, tsundere: tsundere);
