import 'dart:ui' show Color;

/// Persistent CSS-variable skin configuration edited inside
/// `Fejlesztői beállítások` -> `"Egyéni CSS Skin"`.
class CustomSkinConfig {
  static const String defaultTemplateCss = '''
:root {
  --bg: #000000;
  --surface: #0c0e14;
  --accent: #38bdf8;
  --text: #f8fafc;
  --card-radius: 20px;
  --border-color: rgba(255,255,255,0.12);
  --border-width: 1px;
  --glass-blur: 18;
  --card-opacity: 0.85;
  --font-scale: 1.0;
}''';

  final bool enabled;
  final String rawCss;
  final Color? bg;
  final Color? surface;
  final Color? accent;
  final Color? text;
  final double? cardRadius;
  final Color? borderColor;
  final double? borderWidth;
  final double? glassBlur;
  final double? cardOpacity;
  final double? fontScale;

  const CustomSkinConfig({
    this.enabled = false,
    this.rawCss = defaultTemplateCss,
    this.bg,
    this.surface,
    this.accent,
    this.text,
    this.cardRadius,
    this.borderColor,
    this.borderWidth,
    this.glassBlur,
    this.cardOpacity,
    this.fontScale,
  });

  /// Parses `:root { --var: value; }` syntax into typed skin overrides.
  factory CustomSkinConfig.parse(
    String rawCss, {
    bool enabled = false,
  }) {
    final cleaned = rawCss.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final vars = <String, String>{};
    final reg = RegExp(r'--([a-zA-Z0-9_-]+)\s*:\s*([^;\}]+)');
    for (final match in reg.allMatches(cleaned)) {
      final name = match.group(1)?.toLowerCase().trim();
      final val = match.group(2)?.trim();
      if (name != null && name.isNotEmpty && val != null && val.isNotEmpty) {
        vars[name] = val;
      }
    }

    return CustomSkinConfig(
      enabled: enabled,
      rawCss: rawCss,
      bg: _parseCssColor(vars['bg']),
      surface: _parseCssColor(vars['surface']),
      accent: _parseCssColor(vars['accent']),
      text: _parseCssColor(vars['text']),
      cardRadius: _parseCssNumber(vars['card-radius'])?.clamp(0.0, 48.0),
      borderColor: _parseCssColor(vars['border-color']),
      borderWidth: _parseCssNumber(vars['border-width'])?.clamp(0.0, 6.0),
      glassBlur: _parseCssNumber(vars['glass-blur'])?.clamp(0.0, 40.0),
      cardOpacity: _parseCssNumber(vars['card-opacity'])?.clamp(0.05, 1.0),
      fontScale: _parseCssNumber(vars['font-scale'])?.clamp(0.75, 1.35),
    );
  }

  static double? _parseCssNumber(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final stripped = raw
        .toLowerCase()
        .replaceAll('px', '')
        .replaceAll('rem', '')
        .replaceAll('%', '')
        .trim();
    return double.tryParse(stripped);
  }

  static Color? _parseCssColor(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim().toLowerCase();

    if (trimmed.startsWith('#')) {
      final hex = trimmed.substring(1);
      if (hex.length == 3) {
        final expanded = '${hex[0]}${hex[0]}${hex[1]}${hex[1]}${hex[2]}${hex[2]}';
        final val = int.tryParse('ff$expanded', radix: 16);
        return val != null ? Color(val) : null;
      }
      if (hex.length == 6) {
        final val = int.tryParse('ff$hex', radix: 16);
        return val != null ? Color(val) : null;
      }
      if (hex.length == 8) {
        final val = int.tryParse(hex, radix: 16);
        return val != null ? Color(val) : null;
      }
      return null;
    }

    final rgbMatch = RegExp(
      r'^rgba?\(\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})\s*,\s*([0-9]{1,3})(?:\s*,\s*([0-9]*\.?[0-9]+))?\s*\)$',
    ).firstMatch(trimmed);
    if (rgbMatch != null) {
      final r = int.tryParse(rgbMatch.group(1)!)?.clamp(0, 255);
      final g = int.tryParse(rgbMatch.group(2)!)?.clamp(0, 255);
      final b = int.tryParse(rgbMatch.group(3)!)?.clamp(0, 255);
      if (r == null || g == null || b == null) return null;
      final aRaw = rgbMatch.group(4);
      final a = aRaw != null
          ? (double.tryParse(aRaw)?.clamp(0.0, 1.0) ?? 1.0)
          : 1.0;
      return Color.fromRGBO(r, g, b, a);
    }

    return null;
  }
}
