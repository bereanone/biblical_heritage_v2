part of 'library_book_reader_screen.dart';

List<InlineSpan> _buildEpubInlineSpans({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  String? highlightQuery,
  List<String> highlightTerms = const [],
}) {
  final innerHtml = _epubBlockInnerHtml(html);
  final semanticBaseStyle = _epubSemanticStyleFromHtml(html, baseStyle);
  if (innerHtml.trim().isEmpty) {
    return _buildHighlightedEpubTextSpans(
      fallbackText,
      baseStyle: semanticBaseStyle,
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
  final styleFrames = <_EpubInlineStyleFrame>[];
  var index = 0;

  TextStyle currentStyle() {
    if (styleFrames.isEmpty) return semanticBaseStyle;
    return styleFrames.last.style;
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
      for (
        var frameIndex = styleFrames.length - 1;
        frameIndex >= 0;
        frameIndex--
      ) {
        if (styleFrames[frameIndex].tagName == tagName) {
          styleFrames.removeAt(frameIndex);
          break;
        }
      }
      index = closeIndex + 1;
      continue;
    }

    if (tagName == 'br') {
      buffer.write('\n');
      index = closeIndex + 1;
      continue;
    }

    final updatedStyle = _epubSemanticStyleFromRawTag(
      rawTag: rawTag,
      currentStyle: currentStyle(),
    );
    if (updatedStyle != currentStyle() ||
        _epubTagCanCarrySemanticStyle(tagName)) {
      styleFrames.add(
        _EpubInlineStyleFrame(tagName: tagName, style: updatedStyle),
      );
    }

    index = closeIndex + 1;
  }

  flush();

  if (spans.isEmpty) {
    return _buildHighlightedEpubTextSpans(
      fallbackText,
      baseStyle: semanticBaseStyle,
      highlightQuery: highlightQuery,
      highlightTerms: highlightTerms,
    );
  }
  return spans;
}

TextStyle _epubSemanticStyleFromHtml(String html, TextStyle baseStyle) {
  final firstClose = html.indexOf('>');
  if (firstClose < 0 || html.isEmpty) return baseStyle;
  final firstTag = html.substring(1, firstClose).trim();
  return _epubSemanticStyleFromRawTag(
    rawTag: firstTag,
    currentStyle: baseStyle,
  );
}

TextStyle _epubSemanticStyleFromRawTag({
  required String rawTag,
  required TextStyle currentStyle,
}) {
  final tagName = _epubTagName(rawTag.toLowerCase());
  final attrs = _epubParseAttributes(rawTag);
  final lowerStyle = attrs['style']?.toLowerCase() ?? '';
  final lowerClass = attrs['class']?.toLowerCase() ?? '';

  var style = currentStyle;

  final shouldBold =
      tagName == 'strong' ||
      tagName == 'b' ||
      _styleSuggestsBold(lowerStyle) ||
      _classSuggestsBold(lowerClass);
  if (shouldBold) {
    style = style.copyWith(fontWeight: FontWeight.w700);
  }

  final shouldItalic =
      tagName == 'em' ||
      tagName == 'i' ||
      _styleSuggestsItalic(lowerStyle) ||
      _classSuggestsItalic(lowerClass);
  if (shouldItalic) {
    style = style.copyWith(fontStyle: FontStyle.italic);
  }

  final shouldUnderline =
      tagName == 'u' ||
      _styleSuggestsUnderline(lowerStyle) ||
      _classSuggestsUnderline(lowerClass);
  if (shouldUnderline) {
    style = style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null) style.decoration!,
        TextDecoration.underline,
      ]),
    );
  }

  final shouldSmallCaps =
      _styleSuggestsSmallCaps(lowerStyle) ||
      _classSuggestsSmallCaps(lowerClass);
  if (shouldSmallCaps) {
    style = style.copyWith(
      fontFeatures: [
        ...?style.fontFeatures,
        FontFeature.enable('smcp'),
        FontFeature.enable('c2sc'),
      ],
    );
  }

  if (tagName == 'sup' || _styleSuggestsSuperscript(lowerStyle)) {
    style = style.copyWith(fontSize: (style.fontSize ?? 16) * 0.84);
  }
  if (tagName == 'sub' || _styleSuggestsSubscript(lowerStyle)) {
    style = style.copyWith(fontSize: (style.fontSize ?? 16) * 0.84);
  }

  return style;
}

bool _epubTagCanCarrySemanticStyle(String tagName) {
  switch (tagName) {
    case 'strong':
    case 'b':
    case 'em':
    case 'i':
    case 'u':
    case 'sup':
    case 'sub':
    case 'span':
    case 'a':
    case 'font':
      return true;
    default:
      return false;
  }
}

Map<String, String> _epubParseAttributes(String rawTag) {
  final attrs = <String, String>{};
  final pattern = RegExp(
    r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))''',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in pattern.allMatches(rawTag)) {
    final key = match.group(1)?.trim().toLowerCase();
    if (key == null || key.isEmpty) continue;
    final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
    attrs[key] = value;
  }
  return attrs;
}

bool _styleSuggestsBold(String style) {
  return style.contains('font-weight:bold') ||
      style.contains('font-weight: bold') ||
      RegExp(r'font-weight\s*:\s*(?:[7-9]00|bold|bolder)').hasMatch(style);
}

bool _styleSuggestsItalic(String style) {
  return style.contains('font-style:italic') ||
      style.contains('font-style: italic') ||
      RegExp(r'font-style\s*:\s*(?:italic|oblique)').hasMatch(style);
}

bool _styleSuggestsUnderline(String style) {
  return style.contains('text-decoration:underline') ||
      style.contains('text-decoration: underline') ||
      style.contains('text-decoration-line:underline') ||
      style.contains('text-decoration-line: underline');
}

bool _styleSuggestsSmallCaps(String style) {
  return style.contains('font-variant:small-caps') ||
      style.contains('font-variant: small-caps') ||
      style.contains('font-variant-caps:small-caps') ||
      style.contains('font-variant-caps: small-caps');
}

bool _styleSuggestsSuperscript(String style) {
  return style.contains('vertical-align:super') ||
      style.contains('vertical-align: super');
}

bool _styleSuggestsSubscript(String style) {
  return style.contains('vertical-align:sub') ||
      style.contains('vertical-align: sub');
}

bool _classSuggestsBold(String classValue) {
  return _classTokens(
    classValue,
  ).any((token) => token == 'bold' || token == 'strong' || token == 'b');
}

bool _classSuggestsItalic(String classValue) {
  return _classTokens(classValue).any(
    (token) =>
        token == 'italic' ||
        token == 'italics' ||
        token == 'em' ||
        token == 'poem',
  );
}

bool _classSuggestsUnderline(String classValue) {
  return _classTokens(classValue).any(
    (token) => token == 'underline' || token == 'underlined' || token == 'u',
  );
}

bool _classSuggestsSmallCaps(String classValue) {
  return classValue.contains('small-caps') ||
      classValue.contains('smallcaps') ||
      _classTokens(classValue).any((token) => token == 'sc');
}

Iterable<String> _classTokens(String classValue) {
  return classValue
      .split(RegExp(r'[\s_]+'))
      .map((token) => token.trim().toLowerCase())
      .where((token) => token.isNotEmpty);
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

class _EpubInlineStyleFrame {
  const _EpubInlineStyleFrame({required this.tagName, required this.style});

  final String tagName;
  final TextStyle style;
}
