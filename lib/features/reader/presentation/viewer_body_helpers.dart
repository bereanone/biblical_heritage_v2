part of 'viewer_body.dart';

class _ViewerBodyRenderEntry {
  const _ViewerBodyRenderEntry({
    required this.item,
    required this.previousVerseLine,
    required this.startsInRedLetter,
  });

  final ViewerRenderItem item;
  final VerseLine? previousVerseLine;
  final bool startsInRedLetter;
}

extension _ViewerBodyHelpers on _ViewerBodyState {
  bool _isVerseVisible(Map<int, int> verseItemIndex, int blockId) {
    final targetIndex = verseItemIndex[blockId];
    if (targetIndex == null) return false;
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index != targetIndex) continue;
      return position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1;
    }
    return false;
  }

  void _scheduleCenterSelectedBlock(int blockId, Map<int, int> verseItemIndex) {
    final targetIndex = verseItemIndex[blockId];
    if (targetIndex == null) return;
    final int token = ++_recenterToken;
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 120),
      Duration(milliseconds: 280),
    ];

    void runAttempt(int attempt) {
      final delay = delays[attempt];
      Future<void>.delayed(delay, () {
        if (!mounted || token != _recenterToken) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || token != _recenterToken) return;
          if (!_itemScrollController.isAttached) {
            if (attempt + 1 < delays.length) {
              runAttempt(attempt + 1);
            }
            return;
          }
          final shouldCenter =
              attempt == 0 || !_isVerseVisible(verseItemIndex, blockId);
          if (shouldCenter) {
            await _itemScrollController.scrollTo(
              index: targetIndex,
              alignment: 0.5,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
            );
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

  List<_ViewerBodyRenderEntry> _buildRenderEntries(
    List<ViewerRenderItem> renderItems,
  ) {
    final entries = <_ViewerBodyRenderEntry>[];
    VerseLine? previousVerseLine;
    var isInsideJesusSpeech = false;
    for (final item in renderItems) {
      entries.add(
        _ViewerBodyRenderEntry(
          item: item,
          previousVerseLine: previousVerseLine,
          startsInRedLetter: isInsideJesusSpeech,
        ),
      );
      if (item case ViewerVerseItem(:final line)) {
        previousVerseLine = line;
        isInsideJesusSpeech = computeViewerRedLetterContinuation(
          line.html,
          startsInRedLetter: isInsideJesusSpeech,
        );
      }
    }
    return entries;
  }
}
