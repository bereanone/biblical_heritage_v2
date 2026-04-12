import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/highlights_repository.dart';
import 'bible_explorer_screen.dart';
import 'viewer_acrostic_block.dart';
import 'viewer_heading_block.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_render_models.dart';
import 'viewer_render_resolver.dart';
import 'viewer_verse_line.dart';

class ViewerBody extends StatefulWidget {
  const ViewerBody({
    super.key,
    required this.passage,
    required this.selectedBookNumber,
    required this.selectedChapter,
    required this.selectedVerse,
    required this.fontScale,
    required this.onSelectVerse,
    this.onSelectVerseNumber = _noopVerseSelection,
    this.onTapSelectedRange = _noop,
    this.selectedRangeStartBlockId,
    this.selectedRangeEndBlockId,
    this.highlightRefreshTick = 0,
  });

  final PassageData? passage;
  final int selectedBookNumber;
  final int selectedChapter;
  final int selectedVerse;
  final double fontScale;
  final ValueChanged<VerseLine> onSelectVerse;
  final ValueChanged<VerseLine> onSelectVerseNumber;
  final VoidCallback onTapSelectedRange;
  final int? selectedRangeStartBlockId;
  final int? selectedRangeEndBlockId;
  final int highlightRefreshTick;

  static void _noop() {}
  static void _noopVerseSelection(VerseLine _) {}

  @override
  State<ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends State<ViewerBody> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _verseKeys = <int, GlobalKey>{};
  final Map<String, Map<int, List<String>>> _headingCache =
      <String, Map<int, List<String>>>{};
  final Map<String, Map<int, AcrosticRecord>> _acrosticCache =
      <String, Map<int, AcrosticRecord>>{};
  final Map<String, Map<String, VerseHighlightRecord>> _highlightCache =
      <String, Map<String, VerseHighlightRecord>>{};
  int? _lastScrolledBlockId;

  @override
  void didUpdateWidget(covariant ViewerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVerse != widget.selectedVerse ||
        oldWidget.selectedChapter != widget.selectedChapter ||
        oldWidget.selectedBookNumber != widget.selectedBookNumber ||
        oldWidget.passage?.chapter != widget.passage?.chapter ||
        oldWidget.passage?.bookName != widget.passage?.bookName ||
        oldWidget.fontScale != widget.fontScale ||
        oldWidget.highlightRefreshTick != widget.highlightRefreshTick) {
      _lastScrolledBlockId = null;
    }
    if (oldWidget.highlightRefreshTick != widget.highlightRefreshTick &&
        widget.passage != null) {
      final blockIds = widget.passage!.lines
          .map((line) => line.blockId ?? 0)
          .where((id) => id > 0)
          .toList(growable: false);
      final headingCacheKey = blockIds.isEmpty
          ? '${widget.passage!.bookName}|${widget.passage!.chapter}'
          : '${blockIds.first}-${blockIds.last}';
      _highlightCache.remove(headingCacheKey);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: ((theme.textTheme.bodyLarge?.fontSize ?? 16) * widget.fontScale),
      height: 1.38,
    );

    if (widget.passage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedLine = _findSelectedLine(widget.passage!.lines);
    final selectedBlockId = selectedLine?.blockId;

    if (selectedBlockId != null && _lastScrolledBlockId != selectedBlockId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final targetContext = _verseKeys[selectedBlockId]?.currentContext;
        if (targetContext == null) return;
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          alignment: 0.42,
        );
        _lastScrolledBlockId = selectedBlockId;
      });
    }

    final blockIds = widget.passage!.lines
        .map((line) => line.blockId ?? 0)
        .where((id) => id > 0)
        .toList(growable: false);
    final headingCacheKey = blockIds.isEmpty
        ? '${widget.passage!.bookName}|${widget.passage!.chapter}'
        : '${blockIds.first}-${blockIds.last}';
    final cachedHeadings = _headingCache[headingCacheKey];
    final cachedAcrostics = _acrosticCache[headingCacheKey];
    final verseRefs = widget.passage!.lines
        .map((line) => '${widget.passage!.bookName} ${line.chapter}:${line.verse}')
        .toList(growable: false);
    final cachedHighlights = _highlightCache[headingCacheKey];
    if (cachedHeadings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final headings = await StudyBibleDatabase.instance
            .loadSectionHeadingsForBlockIds(
          blockIds,
        );
        if (!mounted) return;
        setState(() {
          _headingCache[headingCacheKey] = headings;
        });
      });
    }
    if (cachedAcrostics == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final acrostics = await StudyBibleDatabase.instance
            .loadAcrosticsForBlockIds(
          blockIds,
        );
        if (!mounted) return;
        setState(() {
          _acrosticCache[headingCacheKey] = acrostics;
        });
      });
    }
    if (cachedHighlights == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final highlights = await HighlightsRepository()
            .loadHighlightsForVerseRefs(verseRefs);
        if (!mounted) return;
        setState(() {
          _highlightCache[headingCacheKey] = highlights;
        });
      });
    }

    final renderItems = resolveViewerRenderItems(
      widget.passage!,
      headingsByBlockId: cachedHeadings ?? const <int, List<String>>{},
      acrosticsByBlockId: cachedAcrostics ?? const <int, AcrosticRecord>{},
    );
    final children = <Widget>[];
    var isInsideJesusSpeech = false;
    VerseLine? previousVerseLine;
    for (int index = 0; index < renderItems.length; index++) {
      final item = renderItems[index];
      if (item case ViewerAcrosticItem(:final hebrew, :final transliteration)) {
        children.add(
          ViewerAcrosticBlock(
            hebrew: hebrew,
            transliteration: transliteration,
            fontScale: widget.fontScale,
          ),
        );
      } else if (item case ViewerHeadingItem(:final text)) {
        children.add(
          ViewerHeadingBlock(
            text: text,
            fontScale: widget.fontScale,
          ),
        );
      } else if (item case ViewerVerseItem(:final line)) {
        final blockId = line.blockId ?? 0;
        final rangeSelected = _isBlockInsideSelectedRange(blockId);
        children.add(
          ViewerVerseLine(
            key: _verseKeys.putIfAbsent(line.blockId ?? line.verse, () => GlobalKey()),
            line: line,
            style: bodyStyle,
            isSelected: _matchesSelectedLine(line),
            isRangeSelected: rangeSelected,
            highlight: (cachedHighlights ?? const <String, VerseHighlightRecord>{})[
              '${widget.passage!.bookName} ${line.chapter}:${line.verse}'
            ],
            showChapterNumber:
                previousVerseLine == null ||
                previousVerseLine.bookNumber != line.bookNumber ||
                previousVerseLine.chapter != line.chapter,
            startsInRedLetter: isInsideJesusSpeech,
            onTap: () {
              if (rangeSelected) {
                widget.onTapSelectedRange();
              } else {
                widget.onSelectVerse(line);
              }
            },
            onLongPress: () => widget.onSelectVerseNumber(line),
          ),
        );
        previousVerseLine = line;
        isInsideJesusSpeech = computeViewerRedLetterContinuation(
          line.html,
          startsInRedLetter: isInsideJesusSpeech,
        );
      }
      if (index != renderItems.length - 1) {
        children.add(
          SizedBox(height: item is ViewerHeadingItem ? 2 : item is ViewerAcrosticItem ? 4 : 12),
        );
      }
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ],
    );
  }

  VerseLine? _findSelectedLine(List<VerseLine> lines) {
    for (final line in lines) {
      if (_matchesSelectedLine(line)) return line;
    }
    return null;
  }

  bool _matchesSelectedLine(VerseLine line) {
    return line.bookNumber == widget.selectedBookNumber &&
        line.chapter == widget.selectedChapter &&
        line.verse == widget.selectedVerse;
  }

  bool _isBlockInsideSelectedRange(int blockId) {
    final start = widget.selectedRangeStartBlockId;
    final end = widget.selectedRangeEndBlockId;
    if (start == null || end == null || blockId <= 0) return false;
    final low = start < end ? start : end;
    final high = start < end ? end : start;
    return blockId >= low && blockId <= high;
  }

}
