/// Decodes the fixed set of XML/HTML entities this codebase's EPUB (OPF and
/// XHTML) sources ever contain: the five predefined XML entities, `&nbsp;`,
/// decimal numeric references (`&#NNN;`), and hex numeric references
/// (`&#xNNNN;`/`&#XNNNN;`).
///
/// Single-pass over the original string (`replaceAllMapped`, never a
/// fixed-point loop), so `&amp;amp;` decodes to the string `&amp;` and never
/// all the way down to `&` — matching how XML/HTML entity decoding is
/// specified to work. Unknown or malformed entities are left unchanged.
String decodeXmlHtmlEntities(String value) {
  final pattern = RegExp(r'&(#[xX][0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');
  return value.replaceAllMapped(pattern, (match) {
    final body = match.group(1)!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final codePoint = int.tryParse(body.substring(2), radix: 16);
      return codePoint == null ? match.group(0)! : _safeChar(codePoint);
    }
    if (body.startsWith('#')) {
      final codePoint = int.tryParse(body.substring(1));
      return codePoint == null ? match.group(0)! : _safeChar(codePoint);
    }
    switch (body) {
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'nbsp':
        // ASCII space (U+0020), deliberately not U+00A0 non-breaking space,
        // to match every existing whitespace-collapsing call site's
        // expectation of an ordinary space.
        return String.fromCharCode(0x20);
      default:
        return match.group(0)!;
    }
  });
}

String _safeChar(int codePoint) {
  if (codePoint <= 0 || codePoint > 0x10FFFF) return '';
  try {
    return String.fromCharCode(codePoint);
  } catch (_) {
    return '';
  }
}
