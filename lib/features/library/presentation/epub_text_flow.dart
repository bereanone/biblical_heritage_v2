/// Normalizes inline EPUB breaks without erasing structural boundaries.
///
/// EPUBs frequently preserve print-layout line wrapping as single `<br>`
/// elements. Ordinary prose treats those as spaces. Repeated breaks remain a
/// hard paragraph boundary, while explicitly structured verse/list/table/pre
/// content retains its line structure. A short `poem-*` quotation is treated
/// as print-wrapped prose only when most seams are grammatical continuations.
String normalizeEpubInlineTextFlow(String html) {
  if (!RegExp(r'<br\b', caseSensitive: false).hasMatch(html)) return html;

  final openingTag = RegExp(r'^\s*<[^>]+>').firstMatch(html)?.group(0) ?? '';
  final lowerOpeningTag = openingTag.toLowerCase();
  final classMatch = RegExp(
    r'''\bclass\s*=\s*(?:"([^"]*)"|'([^']*)')''',
    caseSensitive: false,
  ).firstMatch(openingTag);
  final classValue = classMatch?.group(1) ?? classMatch?.group(2) ?? '';
  final classTokens = classValue
      .toLowerCase()
      .split(RegExp(r'[\s_\-]+'))
      .where((token) => token.isNotEmpty)
      .toSet();
  final explicitlyStructured =
      RegExp(
        r'^\s*<(?:pre|table|thead|tbody|tfoot|tr|td|th|ul|ol|li)\b',
      ).hasMatch(lowerOpeningTag) ||
      classTokens.any(
        (token) =>
            token == 'list' ||
            token == 'table' ||
            token == 'stanza' ||
            token == 'verse',
      );
  final poemLike = classTokens.any(
    (token) => token == 'poem' || classValue.toLowerCase().contains('poem-'),
  );

  final preserveSingleBreaks =
      explicitlyStructured ||
      (poemLike && !_looksLikeShortPrintWrappedQuotation(html));
  final breakPattern = RegExp(r'(?:<br\s*/?>\s*)+', caseSensitive: false);
  const hardBreakSentinel = '\u0000epub-hard-break\u0000';
  var normalized = html.replaceAllMapped(breakPattern, (match) {
    final count = RegExp(
      r'<br\s*/?>',
      caseSensitive: false,
    ).allMatches(match.group(0)!).length;
    if (count >= 2) return hardBreakSentinel;
    return preserveSingleBreaks ? '\n' : ' ';
  });
  if (!preserveSingleBreaks) {
    normalized = normalized.replaceAll(RegExp(r'[\t\r\n ]+'), ' ');
  }
  return normalized.replaceAll(hardBreakSentinel, '\n\n');
}

bool _looksLikeShortPrintWrappedQuotation(String html) {
  final parts = html.split(RegExp(r'<br\s*/?>', caseSensitive: false));
  final breakCount = parts.length - 1;
  if (breakCount < 1 || breakCount > 5) return false;
  var softSeams = 0;
  for (var index = 0; index < breakCount; index++) {
    final left = _plainInlineText(parts[index]).trimRight();
    final right = _plainInlineText(parts[index + 1]).trimLeft();
    if (left.isEmpty || right.isEmpty) continue;
    final endsHard = RegExp(r'''[.!?;:]\s*[”’"']?$''').hasMatch(left);
    final firstLetter = RegExp(r'[A-Za-z]').firstMatch(right)?.group(0);
    final continuesLowercase =
        firstLetter != null && firstLetter == firstLetter.toLowerCase();
    if (!endsHard || continuesLowercase) softSeams += 1;
  }
  return softSeams / breakCount >= 0.6;
}

String _plainInlineText(String value) => value
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
