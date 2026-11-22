/// Global UwU text transformers for Tinta Napló's Developer Mode Easter Eggs.
class UwuHelper {
  /// Synchronized with `UserProfilePrefs.uwuModeEnabled`.
  static bool isEnabled = false;

  /// Synchronized with `UserProfilePrefs.fitymaModeEnabled`.
  static bool isFitymaEnabled = false;

  /// Returns `"Fityma Napló"` when Easter-egg branding mode is enabled, or
  /// `"Tinta Napló"` otherwise.
  static String brandName([bool? fityma]) =>
      (fityma ?? isFitymaEnabled) ? 'Fityma Napló' : 'Tinta Napló';

  static const List<String> _suffixes = [
    'uwu',
    'owo',
    ':3',
    '>w<',
  ];

  static final RegExp _tokenSplitter = RegExp(r'(\s+)');
  static final RegExp _leadingTrailingPunct = RegExp(
    r'^([^A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]*)([A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]+)([^A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]*)$',
  );
  static final RegExp _upperAcronym = RegExp(r'^[A-ZÁÉÍÓÖŐÚÜŰ]{2,5}$');
  static final RegExp _nasalVowel = RegExp(r'([nN])([aeiouáéíóöőúüű])');
  static final RegExp _protectedSuffixGuard = RegExp(
    r'[\d\)\]]$|ft(/hó|-[A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]+)?$',
    caseSensitive: false,
  );
  static final RegExp _ftHyphenGuard = RegExp(r'^ft-', caseSensitive: false);

  static const Set<String> _protectedTokens = {
    'ft',
    'huf',
    'eur',
    'usd',
    'km',
    'cm',
    'mm',
    'db',
    'fszt',
    'em',
    'évf',
    'dr',
    'prof',
    'jan',
    'feb',
    'már',
    'ápr',
    'máj',
    'jún',
    'júl',
    'aug',
    'szept',
    'okt',
    'nov',
    'dec',
  };

  /// Convenience alias for [transform].
  static String apply(
    String input, {
    bool? enabled,
    bool allowSuffix = true,
  }) =>
      transform(input, enabled: enabled, allowSuffix: allowSuffix);

  /// Transforms [input] with dynamic, readable UwU phonetics when enabled,
  /// preserving numbers, timestamps, dates, percentages, room codes, currency,
  /// and acronyms.
  static String transform(
    String input, {
    bool? enabled,
    bool allowSuffix = true,
  }) {
    if (input.trim().isEmpty) {
      return input;
    }

    var source = input;
    if (isFitymaEnabled) {
      source = source
          .replaceAll('Tinta Napló', 'Fityma Napló')
          .replaceAll('Tinta Nyapló', 'Fityma Nyapló');
    }

    final active = enabled ?? isEnabled;
    if (!active) {
      return source;
    }

    // Preserve greetings and specific iconic phrases cleanly
    var out = source
        .replaceAll('Szép napot', 'Szép nyapot')
        .replaceAll('szép napot', 'szép nyapot')
        .replaceAll('Jó éjszakát', 'Jó éccakát')
        .replaceAll('jó éjszakát', 'jó éccakát')
        .replaceAll('Szép reggelt', 'Szép weggewt')
        .replaceAll('szép reggelt', 'szép weggewt');

    // Token-aware transformation so numbers, times, percentages, and URLs remain intact
    final buffer = StringBuffer();
    var searchStart = 0;
    for (final match in _tokenSplitter.allMatches(out)) {
      if (match.start > searchStart) {
        buffer.write(_transformWordToken(out.substring(searchStart, match.start)));
      }
      buffer.write(match.group(0));
      searchStart = match.end;
    }
    if (searchStart < out.length) {
      buffer.write(_transformWordToken(out.substring(searchStart)));
    }
    out = buffer.toString();

    if (!allowSuffix) {
      return out;
    }

    final trimmed = out.trimRight();
    final lower = trimmed.toLowerCase();
    for (final s in _suffixes) {
      if (lower.contains(s)) {
        return out;
      }
    }
    if (lower.endsWith('nya~')) {
      return out;
    }

    // Append a subtle kaomoji only on longer conversational sentences, dynamically
    if (trimmed.length >= 18 &&
        !trimmed.contains('\n') &&
        !trimmed.contains('->') &&
        !trimmed.endsWith(':') &&
        !trimmed.endsWith('%') &&
        !_protectedSuffixGuard.hasMatch(trimmed)) {
      final hash = _stableHash(source);
      if (trimmed.endsWith('!') ||
          trimmed.endsWith('?') ||
          trimmed.endsWith('.') ||
          hash % 3 == 0) {
        final suffix = source.startsWith('Szép napot')
            ? 'uwu'
            : _suffixes[hash % _suffixes.length];
        return '$out $suffix';
      }
    }
    return out;
  }

  static String _transformWordToken(String token) {
    if (token.length <= 2) return token;
    if (token.contains(RegExp(r'[0-9@/\\:%#=&]')) ||
        token.toLowerCase().startsWith('http')) {
      return token;
    }

    if (token.contains('-')) {
      if (_ftHyphenGuard.hasMatch(token)) {
        return token;
      }
      final parts = token.split('-');
      return parts.map(_transformWordToken).join('-');
    }

    final m = _leadingTrailingPunct.firstMatch(token);
    if (m == null) {
      return token;
    }
    final prefix = m.group(1)!;
    final core = m.group(2)!;
    final suffix = m.group(3)!;

    if (core.length <= 2 ||
        _upperAcronym.hasMatch(core) ||
        _protectedTokens.contains(core.toLowerCase())) {
      return token;
    }

    var transformed = core
        .replaceAll('th', 'd')
        .replaceAll('Th', 'D')
        .replaceAll('TH', 'D');

    // Fix nasal vowel expansions safely using replaceAllMapped (never literal '$1')
    transformed = transformed.replaceAllMapped(_nasalVowel, (match) {
      final n = match.group(1)!;
      final v = match.group(2)!;
      // Avoid double ny if already followed by y semantics or inside short roots
      return '${n}y$v';
    });
    // Collapse accidental 'nyy' -> 'ny'
    transformed = transformed
        .replaceAll('nyy', 'ny')
        .replaceAll('Nyy', 'Ny');

    // Selectively soften 'r'/'l' -> 'w' up to 2 swaps per word to keep Hungarian legible
    final chars = transformed.split('');
    var swaps = 0;
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (ch == 'r' || ch == 'l') {
        chars[i] = 'w';
        swaps++;
      } else if (ch == 'R' || ch == 'L') {
        chars[i] = 'W';
        swaps++;
      }
      if (swaps >= 2) break;
    }
    transformed = chars.join();

    return '$prefix$transformed$suffix';
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

/// Shorthand global helper for UwU text transformation.
String uwu(String text, {bool? enabled, bool allowSuffix = true}) =>
    UwuHelper.transform(text, enabled: enabled, allowSuffix: allowSuffix);

/// Shorthand UwU helper for compact UI labels, names, badges, and table rows
/// (transforms text without appending trailing kaomojis).
String uwuLabel(String text, {bool? enabled}) =>
    UwuHelper.transform(text, enabled: enabled, allowSuffix: false);
