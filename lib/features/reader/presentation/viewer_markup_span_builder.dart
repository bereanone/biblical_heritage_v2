import 'package:flutter/material.dart';

InlineSpan buildViewerMarkupSpan({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  required Color redLetterColor,
  bool startsInRedLetter = false,
}) {
  if (html.trim().isEmpty) {
    return TextSpan(text: fallbackText, style: baseStyle);
  }

  final normalized = html
      .replaceAll(RegExp(r'<transChange[^>]*>'), '<i>')
      .replaceAll(RegExp(r'</transChange>'), '</i>')
      .replaceAll(RegExp(r'<span[^>]*class="wj"[^>]*>'), '<wj>')
      .replaceAll(RegExp(r'</span>\s*(?=<wj>)'), '</wj>')
      .replaceAll(RegExp(r'<milestone[^>]*type="x-p"[^>]*/>'), ' ')
      .replaceAll(RegExp(r'<milestone[^>]*type="x-p"[^>]*>'), ' ')
      .replaceAll(RegExp(r'</milestone>'), '')
      .replaceAll('<br>', '\n')
      .replaceAll('<br/>', '\n')
      .replaceAll('<br />', '\n');

  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var index = 0;
  var italicDepth = 0;
  var redDepth = startsInRedLetter ? 1 : 0;
  var skipDepth = 0;

  TextStyle currentStyle() {
    var style = baseStyle;
    if (italicDepth > 0) {
      style = style.merge(const TextStyle(fontStyle: FontStyle.italic));
    }
    if (redDepth > 0) {
      style = style.copyWith(color: redLetterColor);
    }
    return style;
  }

  void flush() {
    if (buffer.isEmpty || skipDepth > 0) {
      buffer.clear();
      return;
    }
    spans.add(TextSpan(text: _decodeEntities(buffer.toString()), style: currentStyle()));
    buffer.clear();
  }

  while (index < normalized.length) {
    final char = normalized[index];
    if (char != '<') {
      if (skipDepth == 0) {
        buffer.write(char);
      }
      index++;
      continue;
    }

    final closeIndex = normalized.indexOf('>', index);
    if (closeIndex == -1) {
      if (skipDepth == 0) {
        buffer.write(normalized.substring(index));
      }
      break;
    }

    final rawTag = normalized.substring(index + 1, closeIndex).trim();
    final lowerTag = rawTag.toLowerCase();
    final isClosing = lowerTag.startsWith('/');
    final tagName = _tagName(lowerTag);

    flush();

    if (isClosing) {
      if (tagName == 'i' || tagName == 'em') {
        italicDepth = italicDepth > 0 ? italicDepth - 1 : 0;
      } else if (tagName == 'q' || tagName == 'wj') {
        redDepth = redDepth > 0 ? redDepth - 1 : 0;
      } else if (tagName == 'note') {
        skipDepth = skipDepth > 0 ? skipDepth - 1 : 0;
      }
      index = closeIndex + 1;
      continue;
    }

    final selfClosing = lowerTag.endsWith('/');
    if (tagName == 'i' || tagName == 'em') {
      if (!selfClosing) {
        italicDepth++;
      }
    } else if (tagName == 'q') {
      if (_isJesusQuote(rawTag) && !selfClosing) {
        redDepth++;
      }
    } else if (tagName == 'wj') {
      if (!selfClosing) {
        redDepth++;
      }
    } else if (tagName == 'note') {
      if (!selfClosing) {
        skipDepth++;
      }
    } else if (tagName == 'p') {
      if (spans.isNotEmpty) {
        spans.add(TextSpan(text: '\n'));
      }
    }

    index = closeIndex + 1;
  }

  flush();

  if (spans.isEmpty) {
    return TextSpan(text: fallbackText, style: baseStyle);
  }
  return TextSpan(children: spans);
}

bool computeViewerRedLetterContinuation(
  String html, {
  bool startsInRedLetter = false,
}) {
  if (html.trim().isEmpty) return startsInRedLetter;

  var redDepth = startsInRedLetter ? 1 : 0;
  var index = 0;
  while (index < html.length) {
    if (html[index] != '<') {
      index++;
      continue;
    }

    final closeIndex = html.indexOf('>', index);
    if (closeIndex == -1) break;

    final rawTag = html.substring(index + 1, closeIndex).trim();
    final lowerTag = rawTag.toLowerCase();
    final isClosing = lowerTag.startsWith('/');
    final tagName = _tagName(lowerTag);
    final selfClosing = lowerTag.endsWith('/');

    if (isClosing) {
      if (tagName == 'q' || tagName == 'wj') {
        redDepth = redDepth > 0 ? redDepth - 1 : 0;
      }
    } else if (!selfClosing) {
      if (tagName == 'q' && _isJesusQuote(rawTag)) {
        redDepth++;
      } else if (tagName == 'wj') {
        redDepth++;
      }
    }

    index = closeIndex + 1;
  }

  return redDepth > 0;
}

String _tagName(String tag) {
  final cleaned = tag.startsWith('/') ? tag.substring(1) : tag;
  final match = RegExp(r'^([a-z0-9_-]+)').firstMatch(cleaned);
  return match?.group(1) ?? '';
}

bool _isJesusQuote(String rawTag) {
  return RegExp(r'who\s*=\s*"Jesus"', caseSensitive: false).hasMatch(rawTag) ||
      RegExp(r"who\s*=\s*'Jesus'", caseSensitive: false).hasMatch(rawTag);
}

String _decodeEntities(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}
