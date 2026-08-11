import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/study_bible_database.dart';
import '../data/bible_markup_repository.dart';
import '../data/highlights_repository.dart';
import 'viewer_acrostic_block.dart';
import 'bible_explorer_range_interaction.dart';
import 'bible_visible_location_controller.dart';
import 'viewer_data_controller.dart';
import 'viewer_heading_block.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';
import 'viewer_verse_line.dart';
import 'text_range_geometry.dart';
import '../../library/presentation/reader_tilt_autoscroll_controller.dart';
import '../../library/presentation/mac_reader_autoscroll_controller.dart';
import 'reader_autoscroll_diagnostics.dart';

part 'viewer_body_helpers.dart';

const bool _enableTextRangeGeometry = false;
const int viewerMaximumAutomaticBlockLeap = 100;

bool viewerAutomaticBlockTransitionIsSafe({
  required int previousBlockId,
  required int candidateBlockId,
  int maximumLeap = viewerMaximumAutomaticBlockLeap,
}) => (candidateBlockId - previousBlockId).abs() <= maximumLeap;

enum ViewerAutoScrollWindowAction {
  scroll,
  extendForward,
  extendBackward,
  stopAtStart,
  stopAtEnd,
}

ViewerAutoScrollWindowAction viewerAutoScrollWindowAction({
  required double delta,
  required int firstVisibleBlockId,
  required int lastVisibleBlockId,
  required int firstLoadedBlockId,
  required int lastLoadedBlockId,
  required int maxBlockId,
  int guardBlocks = 4,
}) {
  if (delta > 0 && lastVisibleBlockId >= lastLoadedBlockId - guardBlocks) {
    return lastLoadedBlockId >= maxBlockId
        ? ViewerAutoScrollWindowAction.scroll
        : ViewerAutoScrollWindowAction.extendForward;
  }
  if (delta < 0 && firstVisibleBlockId <= firstLoadedBlockId + guardBlocks) {
    return firstLoadedBlockId <= ViewerDataController.minId
        ? ViewerAutoScrollWindowAction.scroll
        : ViewerAutoScrollWindowAction.extendBackward;
  }
  return ViewerAutoScrollWindowAction.scroll;
}

int viewerBodyItemCountForLoadedWindow(int? lastLoadedBlockId) =>
    lastLoadedBlockId ?? 0;

bool viewerVisibleLocationCallbackIsCurrent({
  required int scheduledGeneration,
  required int currentGeneration,
}) => scheduledGeneration == currentGeneration;

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
    this.onOpenCrossReferences,
    this.onSelectVerseNumber = _noopVerseSelection,
    this.onSelectTokenLongPress,
    this.onSelectTokenLongPressMove,
    this.onSelectVerseNumberLongPressMove,
    this.onTapSelectedRange = _noop,
    this.rangeSelection = const ViewerRangeSelection(),
    this.highlightRefreshTick = 0,
    this.navigationTick = 0,
    this.autoScrollTarget,
    this.onManualScroll,
  });

  final int anchorBlockId;
  final ViewerDataController data;
  final Map<int, String> bookNamesByNumber;
  final int? selectedBlockId;
  final double fontScale;
  final ValueChanged<int> onVisibleIdChanged;
  final ValueChanged<bool>? onSelectionVisibilityChanged;
  final ValueChanged<VerseLine> onSelectVerse;
  final ValueChanged<VerseLine>? onOpenCrossReferences;
  final ValueChanged<VerseLine> onSelectVerseNumber;
  final void Function(VerseLine line, int tokenIndex)? onSelectTokenLongPress;
  final void Function(VerseLine line, int tokenIndex)?
  onSelectTokenLongPressMove;
  final ValueChanged<VerseLine>? onSelectVerseNumberLongPressMove;
  final VoidCallback onTapSelectedRange;
  final ViewerRangeSelection rangeSelection;
  final int highlightRefreshTick;
  final int navigationTick;
  final CallbackReaderAutoScrollTarget? autoScrollTarget;
  final VoidCallback? onManualScroll;

  static void _noop() {}
  static void _noopVerseSelection(VerseLine _) {}

  @override
  State<ViewerBody> createState() => _ViewerBodyState();
}

class _ViewerBodyState extends State<ViewerBody> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ScrollOffsetController _scrollOffsetController =
      ScrollOffsetController();
  final GlobalKey _visibleListKey = GlobalKey(
    debugLabel: 'bible-visible-scroll-list',
  );
  ScrollPosition? _pixelScrollPosition;
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
  final Map<String, Set<String>> _verseMarkupCache = <String, Set<String>>{};
  // Keyed like the caches above, so a rebuild triggered by something other
  // than an actual change to the loaded window (e.g. a parent-level
  // setState during fast autoscroll) reuses the prior result instead of
  // re-walking every loaded block's HTML for red-letter continuation on
  // every single rebuild — real cost previously measured on-device at
  // several ms per call, recurring every ~30-90ms.
  final Map<String, Map<int, _ViewerBodyBlockContext>> _blockContextCache =
      <String, Map<int, _ViewerBodyBlockContext>>{};

  // Guards the four cache-fill fetches below against being kicked off again
  // on every rebuild while a fetch for the same cache key is already in
  // flight. Without this, a rebuild cadence faster than a slow fetch (e.g.
  // BibleMarkupRepository.loadMarkedVerseKeys on a large autoscroll-expanded
  // window, which issues one sequential SQL query per chapter spanned)
  // queues an unbounded pile of duplicate fetches, starving the UI thread
  // and stalling autoscroll entirely until they drain.
  final Set<String> _headingFetchInFlight = <String>{};
  final Set<String> _acrosticFetchInFlight = <String>{};
  final Set<String> _highlightFetchInFlight = <String>{};
  final Set<String> _verseMarkupFetchInFlight = <String>{};

  final Map<int, GlobalKey> _verseKeys = {};
  Timer? _scrollDebounce;
  Timer? _geometryDebounce;
  int? _lastScrolledBlockId;
  int _recenterToken = 0;
  final int _geometryTick = 0;
  bool _suppressUserScroll = false;
  bool _userIsScrolling = false;
  bool _selectionVisible = false;
  DateTime? _lastVisibleLocationEmission;
  BibleVisibleLocation? _lastEmittedVisibleLocation;
  int? _pendingVisibleBlockId;
  int _visibleLocationGeneration = 0;
  bool _automaticPixelScrollActive = false;
  bool _restoringSafeAutomaticPosition = false;
  Timer? _automaticPixelScrollIdleTimer;
  DateTime? _lastAutomaticPixelScroll;

  static const _visibleLocationInterval = Duration(milliseconds: 120);

  void _captureVisiblePixelPosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void inspect(Element element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (position.hasPixels) _pixelScrollPosition = position;
          return;
        }
        element.visitChildElements(inspect);
      }

      (_visibleListKey.currentContext as Element?)?.visitChildElements(inspect);
    });
  }

  String get _geometryScopeId => 'viewer:${widget.anchorBlockId}';

  Map<int, _ViewerBodyBlockContext> _computeAndCacheBlockContextMap(
    String cacheKey,
    List<int> loadedIds,
  ) {
    final stopwatch = readerAutoScrollDiagnostics.isCapturing
        ? (Stopwatch()..start())
        : null;
    final computed = _buildBlockContextMap(loadedIds);
    _blockContextCache[cacheKey] = computed;
    if (stopwatch != null) {
      readerAutoScrollDiagnostics.recordEvent(
        'block_context_map n=${loadedIds.length} '
        'us=${stopwatch.elapsedMicroseconds}',
      );
    }
    return computed;
  }

  @override
  void initState() {
    super.initState();
    _itemPositionsListener.itemPositions.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.autoScrollTarget?.attach(_scrollByPixels);
    });
    _captureVisiblePixelPosition();
  }

  bool _scrollByPixels(double delta) {
    final position = _pixelScrollPosition;
    if (!mounted || position == null || !position.hasPixels) return false;
    switch (_loadedWindowActionBeforeAutoScroll(delta)) {
      case ViewerAutoScrollWindowAction.extendForward:
      case ViewerAutoScrollWindowAction.extendBackward:
        return true;
      case ViewerAutoScrollWindowAction.stopAtStart:
      case ViewerAutoScrollWindowAction.stopAtEnd:
        return false;
      case ViewerAutoScrollWindowAction.scroll:
        break;
    }
    _automaticPixelScrollActive = true;
    widget.data.beginAutoScroll();
    _lastAutomaticPixelScroll = DateTime.now();
    _scheduleAutomaticPixelScrollIdleCheck();
    final safeDelta = delta
        .clamp(
          -macAutoscrollMaximumFrameDeltaPixels,
          macAutoscrollMaximumFrameDeltaPixels,
        )
        .toDouble();
    final target = (position.pixels + safeDelta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() <= 0.01) return false;
    final before = position.pixels;
    position.jumpTo(target);
    if (readerAutoScrollDiagnostics.isCapturing) {
      readerAutoScrollDiagnostics.record(
        requestedDeltaLogical: delta,
        pixelsBeforeLogical: before,
        pixelsAfterLogical: position.pixels,
        devicePixelRatio: View.of(context).devicePixelRatio,
      );
    }
    return (position.pixels - before).abs() > 0.01;
  }

  void _scheduleAutomaticPixelScrollIdleCheck() {
    if (_automaticPixelScrollIdleTimer != null) return;
    _automaticPixelScrollIdleTimer = Timer(
      const Duration(milliseconds: 350),
      () {
        _automaticPixelScrollIdleTimer = null;
        final last = _lastAutomaticPixelScroll;
        if (last != null &&
            DateTime.now().difference(last) <
                const Duration(milliseconds: 300)) {
          _scheduleAutomaticPixelScrollIdleCheck();
          return;
        }
        _automaticPixelScrollActive = false;
        widget.data.endAutoScroll(
          _lastEmittedVisibleLocation?.blockId ?? widget.anchorBlockId,
        );
      },
    );
  }

  ViewerAutoScrollWindowAction _loadedWindowActionBeforeAutoScroll(
    double delta,
  ) {
    if (delta == 0) return ViewerAutoScrollWindowAction.scroll;
    final positions = _itemPositionsListener.itemPositions.value;
    final firstLoaded = widget.data.firstBlockId;
    final lastLoaded = widget.data.lastBlockId;
    if (positions.isEmpty || firstLoaded == null || lastLoaded == null) {
      return ViewerAutoScrollWindowAction.scroll;
    }
    var firstVisible = widget.data.maxBlockId;
    var lastVisible = 1;
    for (final position in positions) {
      final blockId = position.index + 1;
      if (blockId < firstVisible) firstVisible = blockId;
      if (blockId > lastVisible) lastVisible = blockId;
    }
    final action = viewerAutoScrollWindowAction(
      delta: delta,
      firstVisibleBlockId: firstVisible,
      lastVisibleBlockId: lastVisible,
      firstLoadedBlockId: firstLoaded,
      lastLoadedBlockId: lastLoaded,
      maxBlockId: widget.data.maxBlockId,
      // Window-extend fetches measured 400-700ms on-device even after
      // fixing the duplicate-fetch pileup; a fast rapid-scan burst can
      // still outrun a 40-block buffer before that fetch resolves. 100
      // gives it more headroom to finish in the background before the
      // scroll clamp is reached.
      guardBlocks: 100,
    );
    switch (action) {
      case ViewerAutoScrollWindowAction.scroll:
        return action;
      case ViewerAutoScrollWindowAction.stopAtStart:
      case ViewerAutoScrollWindowAction.stopAtEnd:
        return action;
      case ViewerAutoScrollWindowAction.extendForward:
        if (readerAutoScrollDiagnostics.isCapturing) {
          readerAutoScrollDiagnostics.recordEvent(
            'extend_forward_start firstVisible=$firstVisible '
            'lastLoaded=$lastLoaded',
          );
        }
        unawaited(
          widget.data.ensureAutoScrollWindow(firstVisible, direction: 1).then((
            _,
          ) {
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent('extend_forward_done');
            }
          }),
        );
        // There are still 40 loaded blocks ahead, so do not introduce a
        // deliberate stopped frame while the asynchronous prefetch runs.
        return ViewerAutoScrollWindowAction.scroll;
      case ViewerAutoScrollWindowAction.extendBackward:
        if (readerAutoScrollDiagnostics.isCapturing) {
          readerAutoScrollDiagnostics.recordEvent(
            'extend_backward_start lastVisible=$lastVisible '
            'firstLoaded=$firstLoaded',
          );
        }
        unawaited(
          widget.data.ensureAutoScrollWindow(lastVisible, direction: -1).then((
            _,
          ) {
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent('extend_backward_done');
            }
          }),
        );
        return ViewerAutoScrollWindowAction.scroll;
    }
  }

  @override
  void didUpdateWidget(covariant ViewerBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedBlockId != widget.selectedBlockId ||
        oldWidget.anchorBlockId != widget.anchorBlockId ||
        oldWidget.fontScale != widget.fontScale ||
        oldWidget.navigationTick != widget.navigationTick) {
      _lastScrolledBlockId = null;
      _userIsScrolling = false;
    }
    if (oldWidget.anchorBlockId != widget.anchorBlockId ||
        oldWidget.data != widget.data) {
      _automaticPixelScrollActive = false;
      _visibleLocationGeneration += 1;
      _scrollDebounce?.cancel();
      _scrollDebounce = null;
      _pendingVisibleBlockId = null;
      _lastEmittedVisibleLocation = null;
      _lastVisibleLocationEmission = null;
    }
    if (oldWidget.highlightRefreshTick != widget.highlightRefreshTick) {
      final loadedIds = widget.data.loadedBlockIds;
      if (loadedIds.isNotEmpty) {
        final cacheKey = '${loadedIds.first}-${loadedIds.last}';
        _highlightCache.remove(cacheKey);
        _tokenHighlightCache.remove(cacheKey);
        _verseMarkupCache.remove(cacheKey);
      }
    }
  }

  @override
  void dispose() {
    widget.autoScrollTarget?.detach();
    _automaticPixelScrollIdleTimer?.cancel();
    _scrollDebounce?.cancel();
    _geometryDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onScroll);
    super.dispose();
  }

  GlobalKey _keyForBlock(int blockId) =>
      _verseKeys.putIfAbsent(blockId, GlobalKey.new);

  int? _blockIdAtGlobalPosition(Offset globalPosition) {
    int? nearest;
    var nearestDist = double.infinity;
    for (final entry in _verseKeys.entries) {
      final ro = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (ro == null || !ro.attached) continue;
      final local = ro.globalToLocal(globalPosition);
      final size = ro.size;
      if (local.dy >= 0 && local.dy <= size.height) return entry.key;
      final dist = local.dy < 0 ? -local.dy : local.dy - size.height;
      if (dist < nearestDist) {
        nearestDist = dist;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  void _handleCrossVerseDrag(LongPressMoveUpdateDetails details) {
    final onMove = widget.onSelectTokenLongPressMove;
    if (onMove == null) return;
    final blockId = _blockIdAtGlobalPosition(details.globalPosition);
    if (blockId == null) return;
    final targetLine = widget.data.getBlock(blockId);
    if (targetLine == null) return;
    final ro =
        _verseKeys[blockId]?.currentContext?.findRenderObject() as RenderBox?;
    if (ro == null || !ro.attached) return;
    final localPos = ro.globalToLocal(details.globalPosition);
    final theme = Theme.of(context);
    final bodyStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) * widget.fontScale,
      height: 1.38,
    );
    final brightness = theme.brightness;
    final redLetterColor = brightness == Brightness.dark
        ? const Color(0xFFFF3B30)
        : const Color(0xFFC62828);
    // Approximate gutter width; the text hit-test clamps via nearest-token fallback.
    final gutterWidth = (48.0 * widget.fontScale).clamp(0.0, ro.size.width);
    final textWidth = (ro.size.width - gutterWidth).clamp(1.0, double.infinity);
    final textLocalPos = Offset(
      (localPos.dx - gutterWidth).clamp(0.0, textWidth),
      localPos.dy.clamp(0.0, ro.size.height),
    );
    final tokenIndex = hitTestViewerMarkupTokenIndex(
      html: targetLine.html,
      fallbackText: targetLine.text,
      baseStyle: bodyStyle,
      redLetterColor: redLetterColor,
      localPosition: textLocalPos,
      maxWidth: textWidth,
      textDirection: Directionality.of(context),
      textAlign: TextAlign.start,
    );
    if (tokenIndex == null) return;
    onMove(targetLine, tokenIndex);
  }

  void _handleVerseGutterDrag(LongPressMoveUpdateDetails details) {
    final onMove = widget.onSelectVerseNumberLongPressMove;
    if (onMove == null) return;
    final blockId = _blockIdAtGlobalPosition(details.globalPosition);
    if (blockId == null) return;
    final targetLine = widget.data.getBlock(blockId);
    if (targetLine == null) return;
    onMove(targetLine);
  }

  void _onScroll() {
    final positions =
        _itemPositionsListener.itemPositions.value
            .where(
              (position) =>
                  position.itemTrailingEdge > 0.05 &&
                  position.itemLeadingEdge < 1,
            )
            .toList(growable: false)
          ..sort(
            (left, right) =>
                left.itemLeadingEdge.compareTo(right.itemLeadingEdge),
          );
    if (positions.isEmpty) return;
    final centeredBlockId = centeredBibleVerseBlockId(
      positions.map((position) {
        final blockId = position.index + 1;
        final line = widget.data.getBlock(blockId);
        return BibleViewportCandidate(
          blockId: blockId,
          leadingEdge: position.itemLeadingEdge,
          trailingEdge: position.itemTrailingEdge,
          isVerse:
              line != null && line.verse > 0 && line.text.trim().isNotEmpty,
        );
      }),
    );
    if (centeredBlockId == null) return;
    final previous = _lastEmittedVisibleLocation;
    if (_automaticPixelScrollActive &&
        previous != null &&
        !viewerAutomaticBlockTransitionIsSafe(
          previousBlockId: previous.blockId,
          candidateBlockId: centeredBlockId,
        )) {
      _restoreLastSafeAutomaticPosition(previous.blockId);
      return;
    }
    _queueVisibleBlockEmission(centeredBlockId);
  }

  void _restoreLastSafeAutomaticPosition(int blockId) {
    if (_restoringSafeAutomaticPosition || !_itemScrollController.isAttached) {
      return;
    }
    _restoringSafeAutomaticPosition = true;
    _automaticPixelScrollActive = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollController.isAttached) return;
      _itemScrollController.jumpTo(
        index: _indexForBlockId(blockId),
        alignment: 0.35,
      );
      _restoringSafeAutomaticPosition = false;
    });
  }

  void _queueVisibleBlockEmission(int blockId) {
    final line = widget.data.getBlock(blockId);
    if (line == null) return;
    final location = BibleVisibleLocation(
      blockId: blockId,
      bookNumber: line.bookNumber,
      chapter: line.chapter,
      verse: line.verse,
    );
    if (location == _lastEmittedVisibleLocation) return;

    final now = DateTime.now();
    final lastEmission = _lastVisibleLocationEmission;
    final immediate = location.crossesChapterOrBook(
      _lastEmittedVisibleLocation,
    );
    if (immediate ||
        lastEmission == null ||
        now.difference(lastEmission) >= _visibleLocationInterval) {
      _emitVisibleBlock(blockId, location, now);
      return;
    }

    _pendingVisibleBlockId = blockId;
    if (_scrollDebounce != null) return;
    final generation = _visibleLocationGeneration;
    final remaining = _visibleLocationInterval - now.difference(lastEmission);
    _scrollDebounce = Timer(remaining, () {
      _scrollDebounce = null;
      if (!mounted ||
          !viewerVisibleLocationCallbackIsCurrent(
            scheduledGeneration: generation,
            currentGeneration: _visibleLocationGeneration,
          )) {
        return;
      }
      final pending = _pendingVisibleBlockId;
      _pendingVisibleBlockId = null;
      if (pending == null) return;
      final pendingLine = widget.data.getBlock(pending);
      if (pendingLine == null) return;
      _emitVisibleBlock(
        pending,
        BibleVisibleLocation(
          blockId: pending,
          bookNumber: pendingLine.bookNumber,
          chapter: pendingLine.chapter,
          verse: pendingLine.verse,
        ),
        DateTime.now(),
      );
    });
  }

  void _emitVisibleBlock(
    int blockId,
    BibleVisibleLocation location,
    DateTime now,
  ) {
    _pendingVisibleBlockId = null;
    _lastEmittedVisibleLocation = location;
    _lastVisibleLocationEmission = now;
    final selectedBlockId = widget.selectedBlockId;
    final selectedIsVisible = selectedBlockId != null
        ? _isVerseVisible(selectedBlockId)
        : false;
    if (_selectionVisible != selectedIsVisible) {
      _selectionVisible = selectedIsVisible;
      widget.onSelectionVisibilityChanged?.call(selectedIsVisible);
    }
    widget.onVisibleIdChanged(blockId);
    // While autoscroll is driving the scroll, ensureAutoScrollWindow (see
    // _loadedWindowActionBeforeAutoScroll) already keeps the loaded window
    // ahead of the scroll direction with its own extend-guard timing and a
    // wider radius. This call's smaller default radius is redundant then,
    // and — measured on-device — it shares the same _isLoading gate as the
    // autoscroll extend, so its ~500ms fetch periodically blocks the real
    // extend from starting, producing a visible stall roughly every time it
    // fires. Manual scrolling still needs it to keep the window centered.
    if (!_automaticPixelScrollActive) {
      unawaited(widget.data.ensureWindow(blockId));
    }
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
        final cachedVerseMarkups = _verseMarkupCache[cacheKey];
        if (readerAutoScrollDiagnostics.isCapturing) {
          readerAutoScrollDiagnostics.recordEvent(
            'build_enter n=${loadedIds.length} key=$cacheKey '
            'headingMiss=${cachedHeadings == null} '
            'acrosticMiss=${cachedAcrostics == null} '
            'highlightMiss=${cachedHighlights == null} '
            'markupMiss=${cachedVerseMarkups == null}',
          );
        }
        final blockContextById =
            _blockContextCache[cacheKey] ??
            _computeAndCacheBlockContextMap(cacheKey, loadedIds);
        final loadedLines = loadedIds
            .map((id) => widget.data.getBlock(id))
            .whereType<VerseLine>()
            .toList(growable: false);

        if (cachedHeadings == null && _headingFetchInFlight.add(cacheKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final headings = await StudyBibleDatabase.instance
                .loadSectionHeadingsForBlockIds(loadedIds);
            _headingFetchInFlight.remove(cacheKey);
            if (!mounted) return;
            setState(() {
              _headingCache[cacheKey] = headings;
            });
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent(
                'heading_cache_setState key=$cacheKey',
              );
            }
          });
        }
        if (cachedAcrostics == null && _acrosticFetchInFlight.add(cacheKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final acrostics = await StudyBibleDatabase.instance
                .loadAcrosticsForBlockIds(loadedIds);
            _acrosticFetchInFlight.remove(cacheKey);
            if (!mounted) return;
            setState(() {
              _acrosticCache[cacheKey] = acrostics;
            });
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent(
                'acrostic_cache_setState key=$cacheKey',
              );
            }
          });
        }
        if (cachedHighlights == null && _highlightFetchInFlight.add(cacheKey)) {
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
            _highlightFetchInFlight.remove(cacheKey);
            if (!mounted) return;
            setState(() {
              _highlightCache[cacheKey] = highlights;
              _tokenHighlightCache[cacheKey] = tokenHighlights;
            });
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent(
                'highlight_cache_setState key=$cacheKey',
              );
            }
          });
        }
        if (cachedVerseMarkups == null &&
            _verseMarkupFetchInFlight.add(cacheKey)) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final markedVerseKeys = await BibleMarkupRepository()
                .loadMarkedVerseKeys(
                  lines: loadedLines,
                  bookNamesByNumber: widget.bookNamesByNumber,
                );
            _verseMarkupFetchInFlight.remove(cacheKey);
            if (!mounted) return;
            setState(() {
              _verseMarkupCache[cacheKey] = markedVerseKeys;
            });
            if (readerAutoScrollDiagnostics.isCapturing) {
              readerAutoScrollDiagnostics.recordEvent(
                'markup_cache_setState key=$cacheKey',
              );
            }
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

        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final notificationContext = notification.context;
            if (notificationContext != null) {
              _pixelScrollPosition = Scrollable.maybeOf(
                notificationContext,
              )?.position;
            }
            final manualStart = readerScrollNotificationIsManual(notification);
            if (manualStart && !_suppressUserScroll) {
              _automaticPixelScrollActive = false;
              widget.onManualScroll?.call();
            }
            final isScrolling = notification is ScrollStartNotification
                ? true
                : notification is ScrollEndNotification
                ? false
                : _userIsScrolling;
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
            key: _visibleListKey,
            // Never expose unloaded forward IDs as scrollable blank rows. The
            // item count grows only after ensureWindow has populated them.
            itemCount: viewerBodyItemCountForLoadedWindow(
              widget.data.lastBlockId,
            ),
            itemScrollController: _itemScrollController,
            scrollOffsetController: _scrollOffsetController,
            itemPositionsListener: _itemPositionsListener,
            initialScrollIndex: _indexForBlockId(widget.anchorBlockId),
            initialAlignment: 0.5,
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
            itemBuilder: (context, index) {
              // Make the visible pixel position available before the first
              // user scroll notification. Mac autoscroll can therefore begin
              // from a freshly opened reader instead of reporting a boundary.
              _pixelScrollPosition ??= Scrollable.maybeOf(context)?.position;
              if (_pixelScrollPosition == null ||
                  !_pixelScrollPosition!.hasPixels) {
                _captureVisiblePixelPosition();
              }
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
              final numericVerseKey =
                  '${line.bookNumber}:${line.chapter}:${line.verse}';
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
              return KeyedSubtree(
                key: _keyForBlock(blockId),
                child: Padding(
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
                        hasUserMarkup: (cachedVerseMarkups ?? const <String>{})
                            .contains(numericVerseKey),
                        showChapterNumber: showChapterNumber,
                        startsInRedLetter:
                            blockContext?.startsInRedLetter ?? false,
                        onTap: () => widget.onSelectVerse(line),
                        onVerseNumberTap: widget.onOpenCrossReferences == null
                            ? null
                            : () => widget.onOpenCrossReferences!(line),
                        onVerseNumberLongPress: () =>
                            widget.onSelectVerseNumber(line),
                        onVerseNumberLongPressMoveDetails:
                            widget.onSelectVerseNumberLongPressMove != null
                            ? _handleVerseGutterDrag
                            : null,
                        rangeSelection: widget.rangeSelection,
                        onTokenLongPress: (tokenIndex) {
                          widget.onSelectTokenLongPress?.call(line, tokenIndex);
                        },
                        onTokenLongPressMoveDetails:
                            widget.onSelectTokenLongPressMove != null
                            ? _handleCrossVerseDrag
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
