import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../data/highlights_repository.dart';
import 'viewer_range_selection.dart';

class ViewerMarkupSegment {
  const ViewerMarkupSegment({
    required this.text,
    required this.style,
    this.tokenIndex,
    this.strongs,
  });

  final String text;
  final TextStyle style;
  final int? tokenIndex;
  final Set<String>? strongs;
}

InlineSpan buildViewerMarkupSpan({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  required Color redLetterColor,
  bool startsInRedLetter = false,
  int? blockId,
  ViewerRangeSelection? rangeSelection,
  ValueChanged<int>? onTokenLongPress,
  List<VerseHighlightRecord> persistedHighlights =
      const <VerseHighlightRecord>[],
  Set<String> highlightedStrongs = const <String>{},
}) {
  final segments = parseViewerMarkupSegments(
    html: html,
    fallbackText: fallbackText,
    baseStyle: baseStyle,
    redLetterColor: redLetterColor,
    startsInRedLetter: startsInRedLetter,
  );
  final spans = <InlineSpan>[];
  final selectedColor =
      baseStyle.backgroundColor ??
      baseStyle.color?.withValues(alpha: 0.14) ??
      Colors.yellow.withValues(alpha: 0.28);
  for (final segment in segments) {
    final tokenIndex = segment.tokenIndex;
    final isSelected =
        blockId != null &&
        tokenIndex != null &&
        rangeSelection?.containsTokenPosition(blockId, tokenIndex) == true;
    final isPendingAnchor =
        blockId != null &&
        tokenIndex != null &&
        rangeSelection?.containsPendingTokenAnchor(blockId, tokenIndex) == true;
    final persisted = tokenIndex == null
        ? null
        : _tokenHighlightForIndex(persistedHighlights, tokenIndex);
    final isStrongsMatch =
        segment.strongs != null &&
        segment.strongs!.any(highlightedStrongs.contains);
    final style = _applyViewerSpanStyle(
      segment.style,
      backgroundColor: (isSelected || isPendingAnchor)
          ? selectedColor
          : persisted?.color,
      emphasizeWeight: isSelected || isPendingAnchor || isStrongsMatch,
      underline: isStrongsMatch,
    );
    final recognizer =
        blockId != null && tokenIndex != null && onTokenLongPress != null
        ? (LongPressGestureRecognizer()
            ..onLongPress = () => onTokenLongPress(tokenIndex))
        : null;
    spans.add(
      TextSpan(text: segment.text, style: style, recognizer: recognizer),
    );
  }
  if (spans.isEmpty) {
    return TextSpan(text: fallbackText, style: baseStyle);
  }
  return TextSpan(children: spans);
}

TextStyle _applyViewerSpanStyle(
  TextStyle style, {
  Color? backgroundColor,
  required bool emphasizeWeight,
  required bool underline,
}) {
  final decoration = underline
      ? TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.underline,
        ])
      : style.decoration;
  return style.copyWith(
    backgroundColor: backgroundColor ?? style.backgroundColor,
    fontWeight: emphasizeWeight ? FontWeight.w700 : style.fontWeight,
    decoration: decoration,
  );
}

VerseHighlightRecord? _tokenHighlightForIndex(
  List<VerseHighlightRecord> highlights,
  int tokenIndex,
) {
  for (final highlight in highlights) {
    final start = highlight.startToken;
    final end = highlight.endToken;
    if (start == null || end == null) continue;
    if (tokenIndex >= start && tokenIndex <= end) {
      return highlight;
    }
  }
  return null;
}

List<ViewerMarkupSegment> parseViewerMarkupSegments({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  required Color redLetterColor,
  bool startsInRedLetter = false,
}) {
  if (html.trim().isEmpty) {
    return <ViewerMarkupSegment>[
      ViewerMarkupSegment(text: fallbackText, style: baseStyle),
    ];
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

  final segments = <ViewerMarkupSegment>[];
  final buffer = StringBuffer();
  var index = 0;
  var italicDepth = 0;
  var redDepth = startsInRedLetter ? 1 : 0;
  var skipDepth = 0;
  var currentTokenIndex = 0;
  int? activeTokenIndex;
  Set<String>? activeStrongs;

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
    segments.add(
      ViewerMarkupSegment(
        text: _decodeEntities(buffer.toString()),
        style: currentStyle(),
        tokenIndex: activeTokenIndex,
        strongs: activeStrongs == null || activeStrongs.isEmpty
            ? null
            : Set<String>.of(activeStrongs),
      ),
    );
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
      } else if (tagName == 'w') {
        // Keep the last word token active so trailing punctuation stays attached
        // to the selected/exported token span instead of falling out of range.
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
      if (segments.isNotEmpty) {
        segments.add(ViewerMarkupSegment(text: '\n', style: currentStyle()));
      }
    } else if (tagName == 'w' && !selfClosing) {
      currentTokenIndex += 1;
      activeTokenIndex = currentTokenIndex;
      activeStrongs = _extractCanonicalStrongs(rawTag);
    }

    index = closeIndex + 1;
  }

  flush();
  return segments;
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

Set<String>? _extractCanonicalStrongs(String rawTag) {
  final lemmaMatch = RegExp(
    r'lemma="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(rawTag);
  final lemma = lemmaMatch?.group(1) ?? '';
  final strongs = <String>{};
  for (final match in RegExp(
    r'strong:([GH])0*(\d+)',
    caseSensitive: false,
  ).allMatches(lemma)) {
    final prefix = match.group(1)!.toUpperCase();
    final digits = match.group(2)!;
    strongs.add('$prefix${digits.padLeft(4, '0')}');
  }
  return strongs.isEmpty ? null : strongs;
}
