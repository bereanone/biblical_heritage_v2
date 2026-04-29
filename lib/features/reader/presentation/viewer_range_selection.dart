class ViewerRangeSelection {
  const ViewerRangeSelection({
    this.startBlockId,
    this.endBlockId,
    this.startTokenIndex,
    this.endTokenIndex,
  });

  final int? startBlockId;
  final int? endBlockId;
  final int? startTokenIndex;
  final int? endTokenIndex;

  bool get hasSelection => startBlockId != null;

  bool get hasCompletedRange => startBlockId != null && endBlockId != null;

  bool get hasTokenSelection =>
      startTokenIndex != null || endTokenIndex != null;

  bool get isSingleToken =>
      hasCompletedRange &&
      startBlockId == endBlockId &&
      startTokenIndex != null &&
      endTokenIndex != null &&
      startTokenIndex == endTokenIndex;

  ViewerRangeSelection copyWith({
    int? startBlockId,
    bool clearStartBlockId = false,
    int? endBlockId,
    bool clearEndBlockId = false,
    int? startTokenIndex,
    bool clearStartTokenIndex = false,
    int? endTokenIndex,
    bool clearEndTokenIndex = false,
  }) {
    return ViewerRangeSelection(
      startBlockId: clearStartBlockId
          ? null
          : (startBlockId ?? this.startBlockId),
      endBlockId: clearEndBlockId ? null : (endBlockId ?? this.endBlockId),
      startTokenIndex: clearStartTokenIndex
          ? null
          : (startTokenIndex ?? this.startTokenIndex),
      endTokenIndex: clearEndTokenIndex
          ? null
          : (endTokenIndex ?? this.endTokenIndex),
    );
  }

  ViewerRangeSelection clear() {
    return const ViewerRangeSelection();
  }

  ViewerRangeSelection beginVerseRange(int blockId) {
    return ViewerRangeSelection(startBlockId: blockId, endBlockId: null);
  }

  ViewerRangeSelection completeVerseRange(int blockId) {
    return ViewerRangeSelection(
      startBlockId: startBlockId ?? blockId,
      endBlockId: blockId,
    );
  }

  ViewerRangeSelection beginTokenRange(int blockId, int tokenIndex) {
    return ViewerRangeSelection(
      startBlockId: blockId,
      startTokenIndex: tokenIndex,
    );
  }

  ViewerRangeSelection completeTokenRange(int blockId, int tokenIndex) {
    return ViewerRangeSelection(
      startBlockId: startBlockId ?? blockId,
      endBlockId: blockId,
      startTokenIndex: startTokenIndex ?? tokenIndex,
      endTokenIndex: tokenIndex,
    );
  }

  int? get lowerBlockId {
    final start = startBlockId;
    final end = endBlockId;
    if (start == null) return null;
    if (end == null) return start;
    if (start < end) return start;
    if (start > end) return end;
    final startToken = startTokenIndex ?? 1;
    final endToken = endTokenIndex ?? startToken;
    return startToken <= endToken ? start : end;
  }

  int? get upperBlockId {
    final start = startBlockId;
    final end = endBlockId;
    if (start == null) return null;
    if (end == null) return start;
    if (start > end) return start;
    if (start < end) return end;
    final startToken = startTokenIndex ?? 1;
    final endToken = endTokenIndex ?? startToken;
    return startToken >= endToken ? start : end;
  }

  int? get lowerTokenIndex {
    final start = startBlockId;
    final end = endBlockId ?? start;
    final startToken = startTokenIndex;
    final endToken = endTokenIndex ?? startToken;
    if (startToken == null) return null;
    if (start == null || end == null) return startToken;
    if (start < end) return startToken;
    if (start > end) return endToken;
    if (endToken == null) return startToken;
    return startToken <= endToken ? startToken : endToken;
  }

  int? get upperTokenIndex {
    final start = startBlockId;
    final end = endBlockId ?? start;
    final startToken = startTokenIndex;
    final endToken = endTokenIndex ?? startToken;
    if (startToken == null) return null;
    if (start == null || end == null) return startToken;
    if (start > end) return startToken;
    if (start < end) return endToken;
    if (endToken == null) return startToken;
    return startToken >= endToken ? startToken : endToken;
  }

  bool containsBlock(int blockId) {
    final low = lowerBlockId;
    final high = upperBlockId;
    if (low == null || high == null) return false;
    return blockId >= low && blockId <= high;
  }

  bool containsTokenPosition(int blockId, int tokenIndex) {
    if (!hasCompletedRange) return false;
    if (!hasTokenSelection) return containsBlock(blockId);
    final lowBlock = lowerBlockId;
    final highBlock = upperBlockId;
    final lowToken = lowerTokenIndex;
    final highToken = upperTokenIndex;
    if (lowBlock == null ||
        highBlock == null ||
        lowToken == null ||
        highToken == null) {
      return false;
    }
    if (blockId < lowBlock || blockId > highBlock) return false;
    if (blockId == lowBlock && tokenIndex < lowToken) return false;
    if (blockId == highBlock && tokenIndex > highToken) return false;
    return true;
  }

  bool containsPendingTokenAnchor(int blockId, int tokenIndex) {
    if (!hasSelection || hasCompletedRange) return false;
    final startBlock = startBlockId;
    final startToken = startTokenIndex;
    if (startBlock == null || startToken == null) return false;
    return blockId == startBlock && tokenIndex == startToken;
  }
}
