import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/highlights_repository.dart';
import 'viewer_acrostic_block.dart';
import 'bible_explorer_range_interaction.dart';
import 'viewer_data_controller.dart';
import 'viewer_heading_block.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';
import 'viewer_verse_line.dart';
import 'text_range_geometry.dart';

part 'viewer_body_helpers.dart';

const bool _enableTextRangeGeometry = false;

class ViewerBody extends StatefulWidget {
  const ViewerBody({
    super.key,
    required this.anchorBlockId,
    required this.data,
    required this.bookNamesByNumber,
    required this.selectedBlockId,
    required this.fontScale,
    required this.onVisibleIdChanged,
    this.onSelectionVisibilityChanged,
    required this.onSelectVerse,
    this.onSelectVerseNumber = _noopVerseSelection,
    this.onSelectTokenLongPress,
    this.onSelectTokenLongPressMove,
    this.onTapSelectedRange = _noop,
    this.rangeSelection = const ViewerRangeSelection(),
    this.highlightRefreshTick = 0,
    this.navigationTick = 0,
  });

  final int anchorBlockId;
  final ViewerDataController data;
  final Map<int, String> bookNamesByNumber;
  final int? selectedBlockId;
  final double fontScale;
  final ValueChanged<int> onVisibleIdChanged;
  final ValueChanged<bool>? onSelectionVisibilityChanged;
  final ValueChanged<VerseLine> onSelectVerse;
  final ValueChanged<VerseLine> onSelectVerseNumber;
  final void Function(VerseLine line, int tokenIndex)? onSelectTokenLongPress;
  final void Function(VerseLine line, int tokenIndex)?
  onSelectTokenLongPressMove;
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
  final TextRangeGeometryRegistry _geometryRegistry =
      TextRangeGeometryRegistry();
  final Map<String, Map<int, List<String>>> _headingCache =
      <String, Map<int, List<String>>>{};
  final Map<String, Map<int, AcrosticRecord>> _acrosticCache =
      <String, Map<int, AcrosticRecord>>{};
  final Map<String, Map<String, VerseHighlightRecord>> _highlightCache =
      <String, Map<String, VerseHighlightRecord>>{};
  final Map<String, Map<String, List<VerseHighlightRecord>>>
  _tokenHighlightCache = <String, Map<String, List<VerseHighlightRecord>>>{};

  Timer? _scrollDebounce;
  Timer? _geometryDebounce;
  int? _lastScrolledBlockId;
  int _recenterToken = 0;
  final int _geometryTick = 0;
  bool _suppressUserScroll = false;
  bool _userIsScrolling = false;
  bool _selectionVisible = false;

  String get _geometryScopeId => 'viewer:${widget.anchorBlockId}';

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant ViewerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedBlockId != widget.selectedBlockId ||
        oldWidget.anchorBlockId != widget.anchorBlockId ||
        oldWidget.fontScale != widget.fontScale ||
        oldWidget.navigationTick != widget.navigationTick) {
      _lastScrolledBlockId = null;
    }
    if (oldWidget.highlightRefreshTick != widget.highlightRefreshTick) {
      final loadedIds = widget.data.loadedBlockIds;
      if (loadedIds.isNotEmpty) {
        final cacheKey = '${loadedIds.first}-${loadedIds.last}';
        _highlightCache.remove(cacheKey);
        _tokenHighlightCache.remove(cacheKey);
      }
    }
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _geometryDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 150), () {
      final positions = _itemPositionsListener.itemPositions.value;
      if (positions.isEmpty) return;

      var minIndex = 1 << 30;
      var maxIndex = -1;
      for (final position in positions) {
        if (position.index < minIndex) minIndex = position.index;
        if (position.index > maxIndex) maxIndex = position.index;
      }
      if (maxIndex < 0) return;

      final centerIndex = (minIndex + maxIndex) ~/ 2;
      final centerId = centerIndex + 1;
      final selectedBlockId = widget.selectedBlockId;
      if (selectedBlockId != null) {
        final isVisible = _isVerseVisible(selectedBlockId);
        if (_selectionVisible != isVisible) {
          _selectionVisible = isVisible;
          widget.onSelectionVisibilityChanged?.call(isVisible);
        }
      } else if (_selectionVisible) {
        _selectionVisible = false;
        widget.onSelectionVisibilityChanged?.call(false);
      }
      widget.onVisibleIdChanged(centerId);
      widget.data.ensureWindow(centerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize:
          ((theme.textTheme.bodyLarge?.fontSize ?? 16) * widget.fontScale),
      height: 1.38,
    );
    final geometryScopeId = _geometryScopeId;

    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final loadedIds = widget.data.loadedBlockIds;
        if (loadedIds.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final cacheKey = '${loadedIds.first}-${loadedIds.last}';
        final cachedHeadings = _headingCache[cacheKey];
        final cachedAcrostics = _acrosticCache[cacheKey];
        final cachedHighlights = _highlightCache[cacheKey];
        final cachedTokenHighlights = _tokenHighlightCache[cacheKey];
        final blockContextById = _buildBlockContextMap(loadedIds);

        if (cachedHeadings == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final headings = await StudyBibleDatabase.instance
                .loadSectionHeadingsForBlockIds(loadedIds);
            if (!mounted) return;
            setState(() {
              _headingCache[cacheKey] = headings;
            });
          });
        }
        if (cachedAcrostics == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final acrostics = await StudyBibleDatabase.instance
                .loadAcrosticsForBlockIds(loadedIds);
            if (!mounted) return;
            setState(() {
              _acrosticCache[cacheKey] = acrostics;
            });
          });
        }
        if (cachedHighlights == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final verseRefs = loadedIds
                .map((id) => widget.data.getBlock(id))
                .whereType<VerseLine>()
                .map((line) {
                  final bookName =
                      widget.bookNamesByNumber[line.bookNumber] ??
                      'Book ${line.bookNumber}';
                  return '$bookName ${line.chapter}:${line.verse}';
                })
                .toList(growable: false);
            final highlights = await HighlightsRepository()
                .loadHighlightsForVerseRefs(verseRefs);
            final tokenHighlights = await HighlightsRepository()
                .loadHighlightRangesForVerseRefs(verseRefs);
            if (!mounted) return;
            setState(() {
              _highlightCache[cacheKey] = highlights;
              _tokenHighlightCache[cacheKey] = tokenHighlights;
            });
          });
        }

        final selectedBlockId = widget.selectedBlockId;
        if (selectedBlockId != null &&
            selectedBlockId > 0 &&
            _lastScrolledBlockId != selectedBlockId) {
          _scheduleCenterSelectedBlock(selectedBlockId);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final currentSelectedBlockId = widget.selectedBlockId;
          final isVisible = currentSelectedBlockId != null
              ? _isVerseVisible(currentSelectedBlockId)
              : false;
          if (_selectionVisible != isVisible) {
            _selectionVisible = isVisible;
            widget.onSelectionVisibilityChanged?.call(isVisible);
          }
        });

        return NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (_suppressUserScroll) return false;
            final isScrolling = notification.direction != ScrollDirection.idle;
            if (_userIsScrolling != isScrolling) {
              _userIsScrolling = isScrolling;
              if (!isScrolling && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() {});
                });
              }
            }
            return false;
          },
          child: ScrollablePositionedList.builder(
            itemCount: widget.data.maxBlockId,
            itemScrollController: _itemScrollController,
            itemPositionsListener: _itemPositionsListener,
            initialScrollIndex: _indexForBlockId(widget.anchorBlockId),
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            itemBuilder: (context, index) {
              final blockId = index + 1;
              final line = widget.data.getBlock(blockId);
              if (line == null) {
                return SizedBox(height: 44 * widget.fontScale);
              }

              final blockContext = blockContextById[blockId];
              final previousVerseLine = blockContext?.previousVerseLine;
              final bookName =
                  widget.bookNamesByNumber[line.bookNumber] ??
                  'Book ${line.bookNumber}';
              final verseKey = '$bookName ${line.chapter}:${line.verse}';
              final rangeSelected = shouldOpenRangeActionsOnTap(
                widget.rangeSelection,
                blockId,
              );
              final headings =
                  (cachedHeadings ?? const <int, List<String>>{})[blockId] ??
                  const <String>[];
              final acrostic =
                  (cachedAcrostics ?? const <int, AcrosticRecord>{})[blockId];
              final showChapterNumber =
                  previousVerseLine == null ||
                  previousVerseLine.bookNumber != line.bookNumber ||
                  previousVerseLine.chapter != line.chapter;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (acrostic != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ViewerAcrosticBlock(
                          hebrew: acrostic.hebrew,
                          transliteration: acrostic.transliteration,
                          fontScale: widget.fontScale,
                        ),
                      ),
                    for (final heading in headings)
                      if (heading.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: ViewerHeadingBlock(
                            text: heading,
                            fontScale: widget.fontScale,
                          ),
                        ),
                    ViewerVerseLine(
                      line: line,
                      style: bodyStyle,
                      isSelected: selectedBlockId == blockId,
                      isRangeSelected: rangeSelected,
                      geometryRegistry: _enableTextRangeGeometry
                          ? _geometryRegistry
                          : null,
                      geometryScopeId: _enableTextRangeGeometry
                          ? geometryScopeId
                          : null,
                      geometryRevision: _enableTextRangeGeometry
                          ? _geometryTick
                          : 0,
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
                      showChapterNumber: showChapterNumber,
                      startsInRedLetter:
                          blockContext?.startsInRedLetter ?? false,
                      onTap: () => widget.onSelectVerse(line),
                      onVerseNumberLongPress: () =>
                          widget.onSelectVerseNumber(line),
                      rangeSelection: widget.rangeSelection,
                      onTokenLongPress: (tokenIndex) {
                        widget.onSelectTokenLongPress?.call(line, tokenIndex);
                      },
                      onTokenLongPressMove: (tokenIndex) {
                        widget.onSelectTokenLongPressMove?.call(line, tokenIndex);
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

}
