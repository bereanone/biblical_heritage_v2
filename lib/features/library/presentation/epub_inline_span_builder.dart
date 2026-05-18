part of 'library_book_reader_screen.dart';

List<InlineSpan> _buildEpubInlineSpans({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  String? highlightQuery,
  List<String> highlightTerms = const [],
}) {
  final innerHtml = _epubBlockInnerHtml(html);
  if (innerHtml.trim().isEmpty) {
    return _buildHighlightedEpubTextSpans(
      fallbackText,
      baseStyle: baseStyle,
      highlightQuery: highlightQuery,
      highlightTerms: highlightTerms,
    );
  }

  final normalized = innerHtml
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div\s*>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</blockquote\s*>', caseSensitive: false), '\n\n');

  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var index = 0;
  var boldDepth = 0;
  var italicDepth = 0;
  var underlineDepth = 0;
  var superscriptDepth = 0;
  var subscriptDepth = 0;

  TextStyle currentStyle() {
    var style = baseStyle;
    if (boldDepth > 0) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (italicDepth > 0) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (underlineDepth > 0) {
      style = style.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.underline,
        ]),
      );
    }
    if (superscriptDepth > 0 || subscriptDepth > 0) {
      style = style.copyWith(fontSize: (style.fontSize ?? 16) * 0.84);
    }
    return style;
  }

  void flush() {
    if (buffer.isEmpty) return;
    final text = _decodeEpubHtmlEntities(buffer.toString());
    if (text.isNotEmpty) {
      spans.addAll(
        _buildHighlightedEpubTextSpans(
          text,
          baseStyle: currentStyle(),
          highlightQuery: highlightQuery,
          highlightTerms: highlightTerms,
        ),
      );
    }
    buffer.clear();
  }

  while (index < normalized.length) {
    final char = normalized[index];
    if (char != '<') {
      buffer.write(char);
      index += 1;
      continue;
    }

    final closeIndex = normalized.indexOf('>', index);
    if (closeIndex == -1) {
      buffer.write(normalized.substring(index));
      break;
    }

    final rawTag = normalized.substring(index + 1, closeIndex).trim();
    final lowerTag = rawTag.toLowerCase();
    final isClosing = lowerTag.startsWith('/');
    final tagName = _epubTagName(lowerTag);

    flush();

    if (isClosing) {
      switch (tagName) {
        case 'strong':
        case 'b':
          boldDepth = boldDepth > 0 ? boldDepth - 1 : 0;
          break;
        case 'em':
        case 'i':
          italicDepth = italicDepth > 0 ? italicDepth - 1 : 0;
          break;
        case 'u':
          underlineDepth = underlineDepth > 0 ? underlineDepth - 1 : 0;
          break;
        case 'sup':
          superscriptDepth = superscriptDepth > 0 ? superscriptDepth - 1 : 0;
          break;
        case 'sub':
          subscriptDepth = subscriptDepth > 0 ? subscriptDepth - 1 : 0;
          break;
      }
      index = closeIndex + 1;
      continue;
    }

    switch (tagName) {
      case 'strong':
      case 'b':
        boldDepth += 1;
        break;
      case 'em':
      case 'i':
        italicDepth += 1;
        break;
      case 'u':
        underlineDepth += 1;
        break;
      case 'sup':
        superscriptDepth += 1;
        break;
      case 'sub':
        subscriptDepth += 1;
        break;
      case 'br':
        buffer.write('\n');
        break;
    }

    index = closeIndex + 1;
  }

  flush();

  if (spans.isEmpty) {
    return _buildHighlightedEpubTextSpans(
      fallbackText,
      baseStyle: baseStyle,
      highlightQuery: highlightQuery,
      highlightTerms: highlightTerms,
    );
  }
  return spans;
}

String _epubBlockInnerHtml(String html) {
  final firstClose = html.indexOf('>');
  if (firstClose < 0) return html;
  final lastOpen = html.lastIndexOf('<');
  if (lastOpen <= firstClose) return html.substring(firstClose + 1);
  return html.substring(firstClose + 1, lastOpen);
}

String _decodeEpubHtmlEntities(String input) {
  return input
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
        final code = int.tryParse(m.group(1)!, radix: 16);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      })
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
        final code = int.tryParse(m.group(1)!);
        return code != null ? String.fromCharCode(code) : m.group(0)!;
      })
      .replaceAll(RegExp(r'\r\n?'), '\n');
}

List<InlineSpan> _buildHighlightedEpubTextSpans(
  String text, {
  required TextStyle baseStyle,
  String? highlightQuery,
  required List<String> highlightTerms,
}) {
  final candidates =
      highlightTerms
          .map((term) => term.trim())
          .where((term) => term.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort((left, right) => right.length.compareTo(left.length));

  if (candidates.isEmpty || text.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: baseStyle)];
  }
  return buildHighlightedSearchSpans(text, candidates, baseStyle: baseStyle);
}

String _epubTagName(String lowerTag) {
  final name = lowerTag.startsWith('/') ? lowerTag.substring(1) : lowerTag;
  final match = RegExp(r'^([a-z0-9]+)').firstMatch(name);
  return match?.group(1) ?? '';
}
