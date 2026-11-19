/// Strips HTML markup and decodes HTML entities from transit API strings
/// (e.g. `<span class="MNR2007">&#368;</span>` -> `Ű`).
class HtmlSanitizer {
  HtmlSanitizer._();

  static final RegExp _tag = RegExp(r'<[^>]*>');
  static final RegExp _numericEntity = RegExp(r'&#(x[0-9a-fA-F]+|\d+);');
  static final RegExp _namedEntity = RegExp(r'&([a-zA-Z]+);');

  static const Map<String, String> _named = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'laquo': '«',
    'raquo': '»',
    'aacute': 'á',
    'eacute': 'é',
    'iacute': 'í',
    'oacute': 'ó',
    'uacute': 'ú',
    'ouml': 'ö',
    'uuml': 'ü',
    'Aacute': 'Á',
    'Eacute': 'É',
    'Iacute': 'Í',
    'Oacute': 'Ó',
    'Uacute': 'Ú',
    'Ouml': 'Ö',
    'Uuml': 'Ü',
    'odblac': 'ő',
    'udblac': 'ű',
    'Odblac': 'Ő',
    'Udblac': 'Ű',
  };

  /// Removes tags, decodes entities, and collapses whitespace.
  static String clean(String? input) {
    if (input == null || input.isEmpty) return '';
    var out = input.replaceAll(_tag, '');
    out = out.replaceAllMapped(_numericEntity, (m) {
      final raw = m.group(1)!;
      final code = raw.startsWith('x') || raw.startsWith('X')
          ? int.tryParse(raw.substring(1), radix: 16)
          : int.tryParse(raw);
      if (code == null || code <= 0 || code > 0x10FFFF) return m.group(0)!;
      return String.fromCharCode(code);
    });
    out = out.replaceAllMapped(_namedEntity, (m) => _named[m.group(1)] ?? m.group(0)!);
    // `&amp;` may have produced fresh entities (e.g. `&amp;#368;`): decode once more.
    if (out.contains('&#') || out.contains('&amp;')) {
      out = out.replaceAllMapped(_numericEntity, (m) {
        final raw = m.group(1)!;
        final code = raw.startsWith('x') || raw.startsWith('X')
            ? int.tryParse(raw.substring(1), radix: 16)
            : int.tryParse(raw);
        return code == null || code <= 0 || code > 0x10FFFF
            ? m.group(0)!
            : String.fromCharCode(code);
      });
    }
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
