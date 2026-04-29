import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/highlights_repository.dart';
import 'viewer_acrostic_block.dart';
import 'bible_explorer_range_interaction.dart';
import 'viewer_heading_block.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';
import 'viewer_render_models.dart';
import 'viewer_render_resolver.dart';
import 'viewer_verse_line.dart';

part 'viewer_body_helpers.dart';

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
    this.onSelectTokenLongPress,
    this.onTapSelectedRange = _noop,
    this.rangeSelection = const ViewerRangeSelection(),
    this.highlightRefreshTick = 0,
    this.navigationTick = 0,
  });

  final PassageData? passage;
  final int selectedBookNumber;
  final int selectedChapter;
  final int selectedVerse;
  final double fontScale;
  final ValueChanged<VerseLine> onSelectVerse;
  final ValueChanged<VerseLine> onSelectVerseNumber;
  final void Function(VerseLine line, int tokenIndex)? onSelectTokenLongPress;
  final VoidCallback onTapSelectedRange;
  final ViewerRangeSelection rangeSelection;
  final int highlightRefreshTick;
  final int navigationTick;

  static void _noop() {}
  static void _noopVerseSelection(VerseLine _) {}

  @override
  State<ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends State<ViewerBody> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, Map<int, List<String>>> _headingCache =
      <String, Map<int, List<String>>>{};
  final Map<String, Map<int, AcrosticRecord>> _acrosticCache =
      <String, Map<int, AcrosticRecord>>{};
  final Map<String, Map<String, VerseHighlightRecord>> _highlightCache =
      <String, Map<String, VerseHighlightRecord>>{};
  final Map<String, Map<String, List<VerseHighlightRecord>>>
  _tokenHighlightCache = <String, Map<String, List<VerseHighlightRecord>>>{};
  int? _lastScrolledBlockId;
  int _recenterToken = 0;

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
    if (oldWidget.navigationTick != widget.navigationTick) {
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
      _tokenHighlightCache.remove(headingCacheKey);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize:
          ((theme.textTheme.bodyLarge?.fontSize ?? 16) * widget.fontScale),
      height: 1.38,
    );

    if (widget.passage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final selectedLine = _findSelectedLine(widget.passage!.lines);
    final selectedBlockId = selectedLine?.blockId;

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
        .map(
          (line) => '${widget.passage!.bookName} ${line.chapter}:${line.verse}',
        )
        .toList(growable: false);
    final cachedHighlights = _highlightCache[headingCacheKey];
    final cachedTokenHighlights = _tokenHighlightCache[headingCacheKey];
    if (cachedHeadings == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final headings = await StudyBibleDatabase.instance
            .loadSectionHeadingsForBlockIds(blockIds);
        if (!mounted) return;
        setState(() {
          _headingCache[headingCacheKey] = headings;
        });
      });
    }
    if (cachedAcrostics == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final acrostics = await StudyBibleDatabase.instance
            .loadAcrosticsForBlockIds(blockIds);
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
        final tokenHighlights = await HighlightsRepository()
            .loadHighlightRangesForVerseRefs(verseRefs);
        if (!mounted) return;
        setState(() {
          _highlightCache[headingCacheKey] = highlights;
          _tokenHighlightCache[headingCacheKey] = tokenHighlights;
        });
      });
    }

    final renderItems = resolveViewerRenderItems(
      widget.passage!,
      headingsByBlockId: cachedHeadings ?? const <int, List<String>>{},
      acrosticsByBlockId: cachedAcrostics ?? const <int, AcrosticRecord>{},
    );
    final renderEntries = _buildRenderEntries(renderItems);
    final verseItemIndex = <int, int>{};
    for (var index = 0; index < renderEntries.length; index++) {
      final item = renderEntries[index].item;
      if (item case ViewerVerseItem(:final line)) {
        final blockId = line.blockId;
        if (blockId != null) {
          verseItemIndex[blockId] = index;
        }
      }
    }

    final initialScrollIndex = selectedBlockId != null && selectedBlockId > 0
        ? (verseItemIndex[selectedBlockId] ?? 0)
        : 0;

    if (selectedBlockId != null &&
        selectedBlockId > 0 &&
        _lastScrolledBlockId != selectedBlockId) {
      _scheduleCenterSelectedBlock(selectedBlockId, verseItemIndex);
    }
    return ScrollablePositionedList.builder(
      itemCount: renderEntries.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      initialScrollIndex: initialScrollIndex,
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
      itemBuilder: (context, index) {
        final entry = renderEntries[index];
        final item = entry.item;
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == renderEntries.length - 1
                ? 0
                : item is ViewerHeadingItem
                ? 2
                : item is ViewerAcrosticItem
                ? 4
                : 12,
          ),
          child: switch (item) {
            ViewerAcrosticItem(:final hebrew, :final transliteration) =>
              ViewerAcrosticBlock(
                hebrew: hebrew,
                transliteration: transliteration,
                fontScale: widget.fontScale,
              ),
            ViewerHeadingItem(:final text) => ViewerHeadingBlock(
              text: text,
              fontScale: widget.fontScale,
            ),
            ViewerVerseItem(:final line) => Builder(
              builder: (context) {
                final blockId = line.blockId ?? 0;
                final rangeSelected = shouldOpenRangeActionsOnTap(
                  widget.rangeSelection,
                  blockId,
                );
                final verseKey =
                    '${widget.passage!.bookName} ${line.chapter}:${line.verse}';
                final verseLine = ViewerVerseLine(
                  line: line,
                  style: bodyStyle,
                  isSelected: _matchesSelectedLine(line),
                  isRangeSelected: rangeSelected,
                  highlight:
                      (cachedHighlights ??
                      const <String, VerseHighlightRecord>{})[verseKey],
                  tokenHighlights:
                      (cachedTokenHighlights ??
                          const <
                            String,
                            List<VerseHighlightRecord>
                          >{})[verseKey] ??
                      const <VerseHighlightRecord>[],
                  showChapterNumber:
                      entry.previousVerseLine == null ||
                      entry.previousVerseLine!.bookNumber != line.bookNumber ||
                      entry.previousVerseLine!.chapter != line.chapter,
                  startsInRedLetter: entry.startsInRedLetter,
                  onTap: () => widget.onSelectVerse(line),
                  onVerseNumberLongPress: () =>
                      widget.onSelectVerseNumber(line),
                  rangeSelection: widget.rangeSelection,
                  onTokenLongPress: (tokenIndex) {
                    widget.onSelectTokenLongPress?.call(line, tokenIndex);
                  },
                );
                return verseLine;
              },
            ),
          },
        );
      },
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
}
