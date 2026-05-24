part of 'library_book_reader_screen.dart';

class LibraryRangeSelectionAnchor {
  const LibraryRangeSelectionAnchor({
    required this.blockIndex,
    required this.tokenIndex,
  });

  final int blockIndex;
  final int tokenIndex;
}

class LibraryRangeSelection {
  const LibraryRangeSelection({this.start, this.end});

  final LibraryRangeSelectionAnchor? start;
  final LibraryRangeSelectionAnchor? end;

  bool get hasSelection => start != null;

  bool get hasCompletedRange => start != null && end != null;

  bool get isPendingRange => hasSelection && !hasCompletedRange;

  LibraryRangeSelection clear() => const LibraryRangeSelection();

  LibraryRangeSelection beginAt(int blockIndex, int tokenIndex) {
    return LibraryRangeSelection(
      start: LibraryRangeSelectionAnchor(
        blockIndex: blockIndex,
        tokenIndex: tokenIndex,
      ),
    );
  }

  LibraryRangeSelection completeAt(int blockIndex, int tokenIndex) {
    return LibraryRangeSelection(
      start:
          start ??
          LibraryRangeSelectionAnchor(
            blockIndex: blockIndex,
            tokenIndex: tokenIndex,
          ),
      end: LibraryRangeSelectionAnchor(
        blockIndex: blockIndex,
        tokenIndex: tokenIndex,
      ),
    );
  }

  LibraryRangeSelectionAnchor? get lowerAnchor {
    final startAnchor = start;
    final endAnchor = end;
    if (startAnchor == null) return null;
    if (endAnchor == null) return startAnchor;
    final comparison = _compareAnchors(startAnchor, endAnchor);
    return comparison <= 0 ? startAnchor : endAnchor;
  }

  LibraryRangeSelectionAnchor? get upperAnchor {
    final startAnchor = start;
    final endAnchor = end;
    if (startAnchor == null) return null;
    if (endAnchor == null) return startAnchor;
    final comparison = _compareAnchors(startAnchor, endAnchor);
    return comparison <= 0 ? endAnchor : startAnchor;
  }

  bool containsBlock(int blockIndex) {
    final low = lowerAnchor;
    final high = upperAnchor;
    if (low == null || high == null) return false;
    return blockIndex >= low.blockIndex && blockIndex <= high.blockIndex;
  }

  bool containsTokenPosition(int blockIndex, int tokenIndex) {
    if (!hasCompletedRange) return false;
    final low = lowerAnchor;
    final high = upperAnchor;
    if (low == null || high == null) return false;
    if (blockIndex < low.blockIndex || blockIndex > high.blockIndex) {
      return false;
    }
    if (blockIndex == low.blockIndex && tokenIndex < low.tokenIndex) {
      return false;
    }
    if (blockIndex == high.blockIndex && tokenIndex > high.tokenIndex) {
      return false;
    }
    return true;
  }

  bool containsPendingTokenAnchor(int blockIndex, int tokenIndex) {
    if (!isPendingRange) return false;
    final startAnchor = start;
    if (startAnchor == null) return false;
    return startAnchor.blockIndex == blockIndex &&
        startAnchor.tokenIndex == tokenIndex;
  }
}

class _LibraryTextRun {
  const _LibraryTextRun({
    required this.text,
    required this.style,
    this.tokenIndex,
    this.startOffset,
    this.endOffset,
  });

  final String text;
  final TextStyle style;
  final int? tokenIndex;
  final int? startOffset;
  final int? endOffset;
}

List<InlineSpan> buildLibraryInteractiveEpubSpans({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  required HighlightRenderSpec selectionHighlightSpec,
  required bool isNightMode,
  required int blockIndex,
  required LibraryRangeSelection rangeSelection,
  required ValueChanged<int> onWordLongPress,
  required ValueChanged<int> onWordTap,
  required ValueChanged<int> onWordLongPressMove,
  required ValueChanged<LongPressMoveUpdateDetails>? onWordLongPressMoveDetails,
  required List<ElibraryMarkupRecord> persistedHighlights,
  String? highlightQuery,
  List<String> highlightTerms = const [],
  bool enableWordLongPressRecognizers = false,
  String? geometryScopeId,
  String? geometryContentKey,
  List<TextRangeLayoutSeed>? geometrySeeds,
}) {
  final baseSpans = _buildEpubInlineSpans(
    html: html,
    fallbackText: fallbackText,
    baseStyle: baseStyle,
    highlightQuery: highlightQuery,
    highlightTerms: highlightTerms,
  );
  final flattenedRuns = _flattenInlineTextRuns(baseSpans, baseStyle);
  final spans = <InlineSpan>[];
  var tokenIndex = 0;
  var textOffset = 0;

  for (final run in flattenedRuns) {
    if (run.text.isEmpty) continue;
    final parts = _splitWhitespaceAwarePartsWithOffsets(run.text);
    for (final part in parts) {
      if (part.text.isEmpty) continue;
      final isWhitespace = part.text.trim().isEmpty;
      final partStartOffset = textOffset;
      final partEndOffset = partStartOffset + part.text.length;
      final persistedHighlight = _persistedLibraryMarkupForToken(
        blockIndex: blockIndex,
        tokenStartOffset: partStartOffset,
        tokenEndOffset: partEndOffset,
        persistedHighlights: persistedHighlights,
      );
      final currentTokenIndex = isWhitespace ? tokenIndex : ++tokenIndex;
      final nextTokenIndex = currentTokenIndex + 1;
      final isSelected = isWhitespace
          ? rangeSelection.hasCompletedRange &&
                rangeSelection.containsTokenPosition(
                  blockIndex,
                  currentTokenIndex,
                ) &&
                rangeSelection.containsTokenPosition(blockIndex, nextTokenIndex)
          : rangeSelection.containsTokenPosition(blockIndex, currentTokenIndex);
      final isPendingAnchor =
          !isWhitespace &&
          rangeSelection.containsPendingTokenAnchor(
            blockIndex,
            currentTokenIndex,
          );
      final persistedStyle = persistedHighlight == null
          ? null
          : resolveHighlightRender(
              _persistedLibraryMarkupColor(persistedHighlight.color),
              isNightMode,
              layerType: HighlightLayerType.savedRange,
            );
      final appliedHighlightSpec = (isSelected || isPendingAnchor)
          ? selectionHighlightSpec
          : persistedStyle;
      final tokenStyle = run.style.copyWith(
        backgroundColor:
            appliedHighlightSpec?.backgroundColor ?? run.style.backgroundColor,
        color: appliedHighlightSpec == null
            ? run.style.color
            : _foregroundColorForHighlightedSpan(
                segmentStyle: run.style,
                baseStyle: baseStyle,
                highlightTextColor: appliedHighlightSpec.textColor,
              ),
        fontWeight: (isSelected || isPendingAnchor)
            ? FontWeight.w700
            : run.style.fontWeight,
      );
      GestureLongPressMoveUpdateCallback? moveUpdateCallback;
      if (onWordLongPressMoveDetails != null) {
        moveUpdateCallback = (details) {
          onWordLongPressMoveDetails(details);
        };
      } else {
        moveUpdateCallback = (_) {
          onWordLongPressMove(currentTokenIndex);
        };
      }
      final recognizer = enableWordLongPressRecognizers &&
              isSelected &&
              rangeSelection.hasCompletedRange
          ? (TapGestureRecognizer()..onTap = () => onWordTap(currentTokenIndex))
          : (enableWordLongPressRecognizers && !isWhitespace
              ? (LongPressGestureRecognizer()
                  ..onLongPress = () {
                    onWordLongPress(currentTokenIndex);
                  }
                  ..onLongPressMoveUpdate = moveUpdateCallback)
              : null);
      if (geometrySeeds != null &&
          geometryScopeId != null &&
          !isWhitespace) {
        geometrySeeds.add(
          TextRangeLayoutSeed(
            anchor: TextRangeAnchor.elibrary(
              scopeId: geometryScopeId,
              paragraphBlockIndex: blockIndex,
              tokenIndex: currentTokenIndex,
              characterOffset: partStartOffset,
              contentKey: geometryContentKey,
            ),
            startOffset: partStartOffset,
            endOffset: partEndOffset,
            lineIndex: blockIndex,
          ),
        );
      }
      if (isWhitespace) {
        spans.add(
          TextSpan(text: part.text, style: tokenStyle, recognizer: recognizer),
        );
        textOffset = partEndOffset;
        continue;
      }
      spans.add(
        TextSpan(text: part.text, style: tokenStyle, recognizer: recognizer),
      );
      textOffset = partEndOffset;
    }
  }

  if (spans.isEmpty) {
    return <InlineSpan>[TextSpan(text: fallbackText, style: baseStyle)];
  }
  return spans;
}

int? hitTestLibraryInteractiveEpubTokenIndex({
  required String html,
  required String fallbackText,
  required TextStyle baseStyle,
  required double maxWidth,
  required Offset localPosition,
  required TextDirection textDirection,
  required TextAlign textAlign,
  String? highlightQuery,
  List<String> highlightTerms = const [],
}) {
  final baseSpans = _buildEpubInlineSpans(
    html: html,
    fallbackText: fallbackText,
    baseStyle: baseStyle,
    highlightQuery: highlightQuery,
    highlightTerms: highlightTerms,
  );
  final flattenedRuns = _flattenInlineTextRuns(baseSpans, baseStyle);
  final spans = <InlineSpan>[
    for (final run in flattenedRuns) TextSpan(text: run.text, style: run.style),
  ];
  if (spans.isEmpty) return null;

  final painter = TextPainter(
    text: TextSpan(children: spans),
    textDirection: textDirection,
    textAlign: textAlign,
  )..layout(maxWidth: maxWidth);

  final textOffset = painter.getPositionForOffset(localPosition).offset;
  var tokenIndex = 0;
  var cursor = 0;
  final tokenRanges = <({int tokenIndex, int start, int end})>[];

  for (final run in flattenedRuns) {
    if (run.text.isEmpty) continue;
    final parts = _splitWhitespaceAwarePartsWithOffsets(run.text);
    for (final part in parts) {
      if (part.text.isEmpty) continue;
      final isWhitespace = part.text.trim().isEmpty;
      final currentTokenIndex = isWhitespace ? tokenIndex : ++tokenIndex;
      if (!isWhitespace) {
        tokenRanges.add((
          tokenIndex: currentTokenIndex,
          start: cursor,
          end: cursor + part.text.length,
        ));
      }
      cursor += part.text.length;
    }
  }

  if (tokenRanges.isEmpty) return null;

  var nearestTokenIndex = tokenRanges.first.tokenIndex;
  var nearestDistance = double.infinity;
  for (final range in tokenRanges) {
    if (textOffset >= range.start && textOffset <= range.end) {
      return range.tokenIndex;
    }
    final center = (range.start + range.end) / 2.0;
    final distance = (textOffset - center).abs();
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestTokenIndex = range.tokenIndex;
    }
  }

  return nearestTokenIndex;
}

String buildLibrarySelectionText({
  required List<LibraryBookBlock> blocks,
  required LibraryRangeSelection selection,
}) {
  if (!selection.hasCompletedRange) return '';
  final low = selection.lowerAnchor;
  final high = selection.upperAnchor;
  if (low == null || high == null) return '';

  final buffer = StringBuffer();
  for (
    var blockIndex = low.blockIndex;
    blockIndex <= high.blockIndex;
    blockIndex++
  ) {
    if (blockIndex < 0 || blockIndex >= blocks.length) continue;
    final block = blocks[blockIndex];
    final runs = _splitLibraryTextRuns(block.text);
    final startToken = blockIndex == low.blockIndex ? low.tokenIndex : 1;
    final endToken = blockIndex == high.blockIndex
        ? high.tokenIndex
        : _libraryWordCount(runs);
    final selectedText = _extractLibrarySelectionText(
      runs,
      startToken: startToken,
      endToken: endToken,
    );
    if (selectedText.trim().isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(selectedText.trimRight());
  }

  return buffer.toString().trimRight();
}

int _compareAnchors(
  LibraryRangeSelectionAnchor left,
  LibraryRangeSelectionAnchor right,
) {
  final blockCompare = left.blockIndex.compareTo(right.blockIndex);
  if (blockCompare != 0) return blockCompare;
  return left.tokenIndex.compareTo(right.tokenIndex);
}

List<_LibraryTextRun> _flattenInlineTextRuns(
  List<InlineSpan> spans,
  TextStyle inheritedStyle,
) {
  final runs = <_LibraryTextRun>[];
  for (final span in spans) {
    runs.addAll(_flattenInlineTextSpan(span, inheritedStyle));
  }
  return runs;
}

List<_LibraryTextRun> _flattenInlineTextSpan(
  InlineSpan span,
  TextStyle inheritedStyle,
) {
  if (span is! TextSpan) return const [];
  final mergedStyle = inheritedStyle.merge(span.style);
  final children = span.children;
  if (children != null && children.isNotEmpty) {
    return _flattenInlineTextRuns(children, mergedStyle);
  }
  final text = span.text;
  if (text == null || text.isEmpty) return const [];
  return <_LibraryTextRun>[
    _LibraryTextRun(text: text, style: mergedStyle, tokenIndex: null),
  ];
}

List<({String text, int startOffset, int endOffset})>
_splitWhitespaceAwarePartsWithOffsets(String text) {
  if (text.isEmpty) return const [];
  final parts = <({String text, int startOffset, int endOffset})>[];
  final matches = RegExp(r'\s+|\S+').allMatches(text);
  for (final match in matches) {
    final part = match.group(0);
    if (part != null && part.isNotEmpty) {
      parts.add((text: part, startOffset: match.start, endOffset: match.end));
    }
  }
  return parts;
}

List<_LibraryTextRun> _splitLibraryTextRuns(String text) {
  final runs = <_LibraryTextRun>[];
  var tokenIndex = 0;
  for (final part in _splitWhitespaceAwarePartsWithOffsets(text)) {
    if (part.text.trim().isEmpty) {
      runs.add(_LibraryTextRun(text: part.text, style: const TextStyle()));
      continue;
    }
    tokenIndex += 1;
    runs.add(
      _LibraryTextRun(
        text: part.text,
        style: const TextStyle(),
        tokenIndex: tokenIndex,
        startOffset: part.startOffset,
        endOffset: part.endOffset,
      ),
    );
  }
  return runs;
}

int _libraryWordCount(List<_LibraryTextRun> runs) {
  return runs.where((run) => run.tokenIndex != null).length;
}

String _extractLibrarySelectionText(
  List<_LibraryTextRun> runs, {
  required int startToken,
  required int endToken,
}) {
  final buffer = StringBuffer();
  var started = false;
  var finished = false;
  for (final run in runs) {
    final tokenIndex = run.tokenIndex;
    if (tokenIndex == null) {
      if (started && !finished) {
        buffer.write(run.text);
      }
      continue;
    }
    if (tokenIndex < startToken || tokenIndex > endToken) {
      continue;
    }
    started = true;
    buffer.write(run.text);
    if (tokenIndex == endToken) {
      finished = true;
    }
  }
  return buffer.toString().trimRight();
}

ElibraryMarkupRecord? _persistedLibraryMarkupForToken({
  required int blockIndex,
  required int tokenStartOffset,
  required int tokenEndOffset,
  required List<ElibraryMarkupRecord> persistedHighlights,
}) {
  for (var index = persistedHighlights.length - 1; index >= 0; index--) {
    final highlight = persistedHighlights[index];
    if (!highlight.isHighlight) continue;
    if (blockIndex < highlight.startBlockIndex ||
        blockIndex > highlight.endBlockIndex) {
      continue;
    }
    if (blockIndex == highlight.startBlockIndex &&
        tokenEndOffset <= highlight.startCharOffset) {
      continue;
    }
    if (blockIndex == highlight.endBlockIndex &&
        tokenStartOffset >= highlight.endCharOffset) {
      continue;
    }
    return highlight;
  }
  return null;
}

Color _persistedLibraryMarkupColor(String colorHex) {
  final normalized = colorHex.trim().replaceFirst('#', '');
  try {
    if (normalized.length == 6) {
      return Color(0xFF000000 | int.parse(normalized, radix: 16));
    }
    if (normalized.length == 8) {
      return Color(int.parse(normalized, radix: 16));
    }
  } catch (_) {
    // Fall through to the default color.
  }
  return const Color(0xFFF7D87D);
}

Color? _foregroundColorForHighlightedSpan({
  required TextStyle segmentStyle,
  required TextStyle baseStyle,
  required Color highlightTextColor,
}) {
  final explicitColor = segmentStyle.color;
  final baseColor = baseStyle.color;
  if (explicitColor != null && explicitColor != baseColor) {
    return explicitColor;
  }
  return highlightTextColor;
}
