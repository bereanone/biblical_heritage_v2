/// A small, self-contained, pure-Dart re-implementation of the block-level
/// paragraph extraction used by the app's live EPUB reader
/// (`commentary_research_library_service_epub_parsing.dart`), for use by
/// standalone `dart run` tooling that can't import that file directly (it's
/// Flutter-bound transitively via `debugPrint`, which pulls in `dart:ui` —
/// unavailable outside a running Flutter engine).
///
/// This intentionally mirrors the same tag-stack / block-tag regex approach
/// as the real parser closely enough to produce equivalent "does this
/// section have substantial real content" judgments, without needing
/// heading/anchor detection — front-matter classification only cares about
/// paragraph text and length, not structure.
library;

final RegExp _bodyPattern = RegExp(
  r'<body\b[^>]*>(.*?)</body>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _blockPattern = RegExp(
  r'<(/?)(h[1-6]|p|div|blockquote)\b[^>]*>',
  caseSensitive: false,
  dotAll: true,
);
final RegExp _nestedBlockPattern = RegExp(
  r'<(/?)(h[1-6]|p|div)\b',
  caseSensitive: false,
);
final RegExp _tagPattern = RegExp(r'<[^>]*>');
final RegExp _whitespacePattern = RegExp(r'\s+');
final RegExp _numericEntityPattern = RegExp(r'&#(\d+);');

class _BlockFrame {
  _BlockFrame({required this.tag, required this.contentStart});
  final String tag;
  final int contentStart;
}

/// Extracts plain-text paragraph strings from a raw EPUB chapter's XHTML.
List<String> extractParagraphsFromXhtml(String raw) {
  final bodyMatch = _bodyPattern.firstMatch(raw);
  final source = bodyMatch?.group(1) ?? raw;
  final stack = <_BlockFrame>[];
  final paragraphs = <String>[];

  for (final match in _blockPattern.allMatches(source)) {
    final isClosing = (match.group(1) ?? '').isNotEmpty;
    final tag = (match.group(2) ?? '').toLowerCase();
    if (!isClosing) {
      if ((match.group(0) ?? '').endsWith('/>')) continue;
      stack.add(_BlockFrame(tag: tag, contentStart: match.end));
      continue;
    }
    final openIndex = stack.lastIndexWhere((frame) => frame.tag == tag);
    if (openIndex < 0) continue;
    final frame = stack.removeAt(openIndex);
    final innerHtml = source.substring(frame.contentStart, match.start);
    // A container <div> that wraps other block tags isn't itself a
    // paragraph — its contents are already captured individually.
    if (tag == 'div' && _nestedBlockPattern.hasMatch(innerHtml)) continue;
    final text = _stripHtml(innerHtml);
    if (text.isNotEmpty) paragraphs.add(text);
  }
  return paragraphs;
}

String _stripHtml(String html) {
  final noTags = html.replaceAll(_tagPattern, ' ');
  return _decodeEntities(noTags).replaceAll(_whitespacePattern, ' ').trim();
}

String _decodeEntities(String value) {
  var result = value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', '’')
      .replaceAll('&lsquo;', '‘')
      .replaceAll('&rdquo;', '”')
      .replaceAll('&ldquo;', '“')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
  result = result.replaceAllMapped(_numericEntityPattern, (match) {
    final code = int.tryParse(match.group(1) ?? '');
    return code == null ? match.group(0)! : String.fromCharCode(code);
  });
  return result;
}
