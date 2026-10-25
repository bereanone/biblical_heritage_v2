class ViewerRangeSelection {
  const ViewerRangeSelection({
    this.startBlockId,
    this.endBlockId,
    this.startTokenIndex,
    this.endTokenIndex,
    this.usesWordIndices = false,
  });

  final int? startBlockId;
  final int? endBlockId;
  final int? startTokenIndex;
  final int? endTokenIndex;
  final bool usesWordIndices;

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
      usesWordIndices: usesWordIndices,
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

  /// Extend in either direction without dropping any of the existing verses.
  ViewerRangeSelection extendVerseRange(int blockId) {
    final low = lowerBlockId ?? blockId;
    final high = upperBlockId ?? blockId;
    return ViewerRangeSelection(
      startBlockId: blockId < low ? blockId : low,
      endBlockId: blockId > high ? blockId : high,
    );
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

  ViewerRangeSelection beginTokenRange(
    int blockId,
    int tokenIndex, {
    bool wordIndices = false,
  }) {
    return ViewerRangeSelection(
      startBlockId: blockId,
      usesWordIndices: wordIndices,
      startTokenIndex: tokenIndex,
    );
  }

  ViewerRangeSelection completeTokenRange(int blockId, int tokenIndex) {
    return ViewerRangeSelection(
      startBlockId: startBlockId ?? blockId,
      usesWordIndices: usesWordIndices,
      endBlockId: blockId,
      startTokenIndex: startTokenIndex ?? tokenIndex,
      endTokenIndex: tokenIndex,
    );
  }

  /// Move one visible endpoint, clamping at its counterpart rather than
  /// flipping handles mid-drag. Source token IDs remain unchanged.
  ViewerRangeSelection moveEndpoint({
    required bool start,
    required int blockId,
    required int tokenIndex,
  }) {
    if (!hasCompletedRange || !hasTokenSelection) return this;
    var block = blockId;
    var token = tokenIndex;
    final fixedBlock = start ? upperBlockId! : lowerBlockId!;
    final fixedToken = (start ? upperTokenIndex : lowerTokenIndex)!;
    final comparison = block == fixedBlock
        ? token.compareTo(fixedToken)
        : block.compareTo(fixedBlock);
    if ((start && comparison > 0) || (!start && comparison < 0)) {
      block = fixedBlock;
      token = fixedToken;
    }
    return ViewerRangeSelection(
      usesWordIndices: usesWordIndices,
      startBlockId: start ? block : lowerBlockId,
      startTokenIndex: start ? token : lowerTokenIndex,
      endBlockId: start ? upperBlockId : block,
      endTokenIndex: start ? upperTokenIndex : token,
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
