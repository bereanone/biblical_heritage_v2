import 'library_xml_html_entities.dart';

/// Produces a safe, human-readable title for library UI.
///
/// Candidates must be supplied in authority order. Empty, code-like, or
/// punctuation-only candidates are skipped. This does not mutate source
/// metadata.
String normalizeBookDisplayTitle(
  String? catalogTitle, {
  Iterable<String?> fallbacks = const <String?>[],
  String fallbackLabel = 'Untitled',
}) {
  for (final candidate in <String?>[catalogTitle, ...fallbacks]) {
    final normalized = _normalizeDisplayText(candidate);
    if (normalized.isNotEmpty && !_isInternalCodeOnly(normalized)) {
      return normalized;
    }
  }
  return fallbackLabel;
}

/// Applies entity, tag, quote, punctuation, and whitespace cleanup suitable
/// for short contributor text shown in the UI.
String normalizeBookDisplayAuthor(
  String? author, {
  String fallbackLabel = 'Unknown author',
}) {
  final normalized = _normalizeDisplayText(author);
  if (normalized.isEmpty || _isInternalCodeOnly(normalized)) {
    return fallbackLabel;
  }
  return normalized;
}

String _normalizeDisplayText(String? value) {
  if (value == null || value.trim().isEmpty) return '';

  // Some imported EPUBs contain XML that was escaped twice. Decode at most
  // twice: enough to turn &amp;quot; into a quote without a fixed-point loop.
  var text = decodeXmlHtmlEntities(value);
  text = decodeXmlHtmlEntities(text);
  text = text.replaceAll(RegExp(r'<[^>]*>', dotAll: true), ' ');
  text = text
      .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
      .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  text = _collapseRepeatedFragments(text);
  text = text.replaceAllMapped(
    RegExp(r'\b([A-Z])\s*;\s*(?=[A-Z])'),
    (match) => '${match.group(1)}. ',
  );
  text = text.replaceAll(RegExp(r'(^|\s)[;,]+(?=\s|$)'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  text = _removeUnmatchedQuotes(text);
  text = text.replaceAll(RegExp(r'^[\s,;:]+|[\s,;:]+$'), '').trim();
  return text;
}

String _collapseRepeatedFragments(String value) {
  final quoted = RegExp(r'^\s*"([^"]+)"(?:\s+"?\1"?){1,}\s*$');
  final quotedMatch = quoted.firstMatch(value);
  if (quotedMatch != null) return quotedMatch.group(1)!.trim();

  final fragments = value
      .split(RegExp(r'\s*(?:\r?\n|\s{2,})\s*'))
      .map(_withoutOuterQuotes)
      .where((part) => part.isNotEmpty)
      .toList();
  if (fragments.length > 1 &&
      fragments.every(
        (part) => part.toLowerCase() == fragments.first.toLowerCase(),
      )) {
    return fragments.first;
  }

  // Handles whitespace-collapsed forms such as `"The Daily" "The Daily"
  // The Daily`, while leaving legitimate internal quotations untouched.
  final pieces = RegExp(r'"([^"]+)"|([^"]+)')
      .allMatches(value)
      .map((match) => (match.group(1) ?? match.group(2) ?? '').trim())
      .where((part) => part.isNotEmpty)
      .toList();
  if (pieces.length > 1 &&
      pieces.every(
        (part) => part.toLowerCase() == pieces.first.toLowerCase(),
      )) {
    return pieces.first;
  }
  return value;
}

String _withoutOuterQuotes(String value) {
  var result = value.trim();
  if (result.length >= 2 && result.startsWith('"') && result.endsWith('"')) {
    result = result.substring(1, result.length - 1).trim();
  }
  return result;
}

String _removeUnmatchedQuotes(String value) {
  var text = value;
  for (final quote in <String>['"', "'"]) {
    final count = quote.allMatches(text).length;
    if (count.isOdd) {
      if (text.startsWith(quote)) {
        text = text.substring(1).trimLeft();
      } else if (text.endsWith(quote)) {
        text = text.substring(0, text.length - 1).trimRight();
      }
    }
  }
  return _withoutOuterQuotes(text);
}

bool _isInternalCodeOnly(String value) {
  final compact = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  return compact.length <= 5 &&
      RegExp(r'^[A-Z0-9]+$').hasMatch(compact) &&
      !value.contains(RegExp(r'[a-z]'));
}
