part of 'viewer_body.dart';

class _ViewerBodyBlockContext {
  const _ViewerBodyBlockContext({
    required this.previousVerseLine,
    required this.startsInRedLetter,
  });

  final VerseLine? previousVerseLine;
  final bool startsInRedLetter;
}

extension _ViewerBodyHelpers on _ViewerBodyState {
  bool _isVerseVisible(int blockId) {
    final targetIndex = _indexForBlockId(blockId);
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index != targetIndex) continue;
      return position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1;
    }
    return false;
  }

  bool _isVerseNearCenter(int blockId, {double tolerance = 0.16}) {
    final targetIndex = _indexForBlockId(blockId);
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return false;
    for (final position in positions) {
      if (position.index != targetIndex) continue;
      final center =
          (position.itemLeadingEdge + position.itemTrailingEdge) / 2;
      return (center - 0.5).abs() <= tolerance;
    }
    return false;
  }

  int _indexForBlockId(int blockId) {
    final clamped = blockId.clamp(1, widget.data.maxBlockId);
    return clamped - 1;
  }

  void _scheduleCenterSelectedBlock(int blockId) {
    final targetIndex = _indexForBlockId(blockId);
    final token = ++_recenterToken;
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 120),
      Duration(milliseconds: 280),
    ];

    void runAttempt(int attempt) {
      Future<void>.delayed(delays[attempt], () {
        if (!mounted || token != _recenterToken) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || token != _recenterToken) return;
          if (_userIsScrolling) return;
          if (!_itemScrollController.isAttached) {
            if (attempt + 1 < delays.length) {
              runAttempt(attempt + 1);
            }
            return;
          }
          final isVisible = _isVerseVisible(blockId);
          final isBibleStartBoundary = blockId == 1 && isVisible;
          final isBibleEndBoundary =
              blockId == widget.data.maxBlockId && isVisible;
          if (isBibleStartBoundary) {
            _lastScrolledBlockId = blockId;
            return;
          }
          if (isBibleEndBoundary) {
            _lastScrolledBlockId = blockId;
            return;
          }
          if (attempt > 0 && isVisible) {
            _lastScrolledBlockId = blockId;
            return;
          }
          final shouldCenter =
              !isVisible || !_isVerseNearCenter(blockId);
          if (shouldCenter) {
            _suppressUserScroll = true;
            try {
              await _itemScrollController.scrollTo(
                index: targetIndex,
                alignment: 0.5,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOut,
              );
            } finally {
              _suppressUserScroll = false;
            }
          }
          if (!mounted || token != _recenterToken) return;
          _lastScrolledBlockId = blockId;
          if (attempt + 1 < delays.length) {
            runAttempt(attempt + 1);
          }
        });
      });
    }

    runAttempt(0);
  }

  Map<int, _ViewerBodyBlockContext> _buildBlockContextMap(List<int> loadedIds) {
    final contextById = <int, _ViewerBodyBlockContext>{};
    VerseLine? previousVerseLine;
    var isInsideJesusSpeech = false;
    for (final blockId in loadedIds) {
      final line = widget.data.getBlock(blockId);
      if (line == null) continue;
      contextById[blockId] = _ViewerBodyBlockContext(
        previousVerseLine: previousVerseLine,
        startsInRedLetter: isInsideJesusSpeech,
      );
      previousVerseLine = line;
      isInsideJesusSpeech = computeViewerRedLetterContinuation(
        line.html,
        startsInRedLetter: isInsideJesusSpeech,
      );
    }
    return contextById;
  }
}
