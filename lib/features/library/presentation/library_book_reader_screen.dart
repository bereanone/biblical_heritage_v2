// ignore_for_file: unused_element, dead_code

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../../core/database/user_database.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/theme_preferences.dart';
import '../data/elibrary_markup_repository.dart';
import '../data/library_citation_display_helper.dart';
import '../data/library_reader_opening.dart';
import '../data/library_reader_state_writer.dart';
import '../data/library_section_heuristics.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../../reader/presentation/highlight_render.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';
import '../../reader/presentation/tag_screen_launcher.dart';
import '../../reader/presentation/tag_dialog_styles.dart';
import '../../reader/presentation/reader_search_mode_picker.dart';
import '../../reader/presentation/viewer_search_dialog.dart';
import '../../reader/presentation/viewer_passage_models.dart';
import '../../reader/presentation/viewer_range_selection.dart';
import '../../search/search_highlight_helper.dart';
import '../data/library_catalog_service.dart';
import 'elibrary_highlight_color_picker.dart';
import 'library_font_scale.dart';
import 'library_navigation_tree.dart';
import '../../reader/presentation/text_range_geometry.dart';
import '../../utilities/data/pioneer_captured_html_import_folder_service.dart';
import '../../utilities/data/pioneer_text_import_service.dart';
import '../../utilities/presentation/elibrary_setup_screen.dart';

part 'epub_inline_span_builder.dart';
part 'epub_body_block_parser.dart';
part 'library_contents_popup.dart';
part 'library_reader_bottom_bar.dart';
part 'library_book_reader_range_selection.dart';
part 'library_book_reader_selection_menu.dart';
part 'library_book_reader_screen_helpers.dart';

const bool _enableTextRangeGeometry = false;

enum _ReaderBookMenuAction {
  openELibrarySetup,
  removeCurrentBook,
  repairCurrentImportedBook,
}

class LibraryBookReaderScreen extends StatefulWidget {
  const LibraryBookReaderScreen({
    super.key,
    required this.item,
    this.initialHref,
    this.initialAnchorId,
    this.initialSpineIndex,
    this.initialParagraphIndex,
    this.searchQuery,
    this.highlightTerms = const [],
    this.searchSession,
    this.onReturnToBible,
    this.themeMode,
    this.onThemeChanged,
  });

  final LibraryCatalogItem item;
  final String? initialHref;
  final String? initialAnchorId;
  final int? initialSpineIndex;
  final int? initialParagraphIndex;
  final String? searchQuery;
  final List<String> highlightTerms;
  final LibraryCatalogSearchSession? searchSession;
  final VoidCallback? onReturnToBible;
  final AppThemeMode? themeMode;
  final ValueChanged<AppThemeMode>? onThemeChanged;

  @override
  State<LibraryBookReaderScreen> createState() =>
      _LibraryBookReaderScreenState();
}

class _LibraryBookReaderScreenState extends State<LibraryBookReaderScreen> {
  final _service = CommentaryResearchLibraryService.instance;
  final ScrollController _bodyScrollController = ScrollController();
  final Map<String, GlobalKey> _bodyBlockKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _bodyTextKeys = <String, GlobalKey>{};
  final TextRangeGeometryRegistry _geometryRegistry =
      TextRangeGeometryRegistry();
  String? _lastSearchTerm;
  LibraryRangeSelection _rangeSelection = const LibraryRangeSelection();
  bool _librarySelectionActionsOpen = false;
  bool _loading = true;
  bool _nightMode = false;
  bool _showRefCodes = false;
  bool _refCodesLoaded = false;
  double _fontScale = 1.3;
  double _zoomScale = 1.0;
  final int _geometryTick = 0;
  String? _error;
  List<LibraryBookSection> _sections = const [];
  List<LibraryCatalogNavigationItem> _navigationItems = const [];
  int _selectedIndex = 0;
  int _selectedNavigationIndex = 0;
  int? _selectedHeadingTargetIndex;
  String? _pendingBodyScrollTargetKey;
  Map<String, String> _refCodeByLocation = <String, String>{};
  Map<String, Map<int, String>> _paragraphReferenceCodesBySection =
      <String, Map<int, String>>{};
  Map<String, List<ElibraryMarkupRecord>> _elibraryMarkupsByHref =
      <String, List<ElibraryMarkupRecord>>{};

  String get _geometryScopeId {
    final section = _sections.isEmpty
        ? null
        : _sections[_selectedIndex.clamp(0, _sections.length - 1)];
    return 'elibrary:${widget.item.id}:${section?.entryName ?? '(none)'}';
  }

  @override
  void initState() {
    super.initState();
    _nightMode = widget.themeMode == AppThemeMode.night;
    final initialSearchTerm = widget.searchQuery?.trim() ?? '';
    _lastSearchTerm = initialSearchTerm.isNotEmpty ? initialSearchTerm : null;
    _bodyScrollController.addListener(_onBodyScroll);
    _load();
  }

  @override
  void dispose() {
    _geometryDebounce?.cancel();
    _bodyScrollController.removeListener(_onBodyScroll);
    _bodyScrollController.dispose();
    super.dispose();
  }

  Timer? _geometryDebounce;

  void _onBodyScroll() {}

  Future<void> _load() async {
    final savedFontScale = await AppSettingsService.instance
        .loadViewerFontScale();
    final savedZoomScale = await AppSettingsService.instance
        .loadElibraryZoomScale();
    final savedShowRefCodes = await LocalSettingsStore.instance
        .loadLibraryReaderShowRefCodes();
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())
            ?.trim() ??
        (selection.exists ? selection.path?.trim() ?? '' : '');

    if (rootPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Reconnect the Library Root to open this book.';
        _loading = false;
      });
      return;
    }

    final filePath = p.join(rootPath, widget.item.relativePath);
    try {
      final loadedSections = widget.item.isPdf
          ? const <LibraryBookSection>[]
          : await _service.loadBookSections(
              filePath: filePath,
              libraryItemId: widget.item.id,
              includeFrontMatter: true,
            );
      final navigationItems = widget.item.isPdf
          ? const <LibraryCatalogNavigationItem>[]
          : await LibraryCatalogService.instance.loadNavigationItems(
              widget.item.id,
            );
      final sections = widget.item.isPdf
          ? loadedSections
          : libraryReaderSectionsWithHeadingOnlyNavigation(
              sections: loadedSections,
              navigationItems: navigationItems,
            );
      final devotionalMode =
          widget.item.isDevotional || isDevotionalNavigation(navigationItems);
      final navigationTree = widget.item.isPdf
          ? const LibraryNavigationTreeResult(
              items: <LibraryCatalogNavigationItem>[],
              childrenByParent: <String?, List<LibraryCatalogNavigationItem>>{},
            )
          : buildLibraryNavigationTree(
              navigationItems,
              devotionalMode: devotionalMode,
              periodicalMode: widget.item.isPeriodical,
            );
      final initialIndex = widget.item.isPdf
          ? 0
          : libraryReaderInitialSectionIndex(
              item: widget.item,
              sections: sections,
              navigationItems: navigationItems,
              devotionalMode: devotionalMode,
              initialHref: widget.initialHref,
              initialSpineIndex: widget.initialSpineIndex,
            );
      var initialNavigationIndex = widget.item.isPdf
          ? 0
          : _navigationIndexForSectionIndex(initialIndex) ?? 0;
      var resolvedInitialIndex = initialIndex;
      if (navigationItems.isNotEmpty) {
        final selectedNavItem =
            navigationItems[initialNavigationIndex.clamp(
              0,
              navigationItems.length - 1,
            )];
        final normalizedNavItem = libraryReaderVisibleContentsNavigationItem(
          navItem: selectedNavItem,
          tree: navigationTree,
          sections: sections,
        );
        if (normalizedNavItem != null &&
            normalizedNavItem.id != selectedNavItem.id) {
          final normalizedNavIndex = navigationItems.indexWhere(
            (nav) => nav.id == normalizedNavItem.id,
          );
          final normalizedSectionIndex =
              _sectionIndexForNavigationItemInSections(
                sections,
                normalizedNavItem,
              ) ??
              resolvedInitialIndex;
          if (normalizedNavIndex >= 0) {
            initialNavigationIndex = normalizedNavIndex;
            resolvedInitialIndex = normalizedSectionIndex;
          }
        }
      }
      // Periodicals generate ref codes inline (libraryReaderPeriodicalRefCode)
      // and books load codes in the background after first paint; skipping
      // the DB scan here avoids ~1,900 serial async queries on RH open.
      final paragraphReferenceCodeLoadResult =
          const _ParagraphReferenceCodeLoadResult(
            bySection: <String, Map<int, String>>{},
            byLocation: <String, String>{},
          );
      final elibraryMarkupsByHref = await _loadElibraryMarkups(widget.item.id);
      if (!mounted) return;
      setState(() {
        _fontScale = savedFontScale;
        _zoomScale = savedZoomScale;
        _sections = sections;
        _navigationItems = navigationItems;
        _selectedIndex = resolvedInitialIndex;
        _selectedNavigationIndex = initialNavigationIndex;
        _showRefCodes = savedShowRefCodes;
        // Codes are loaded lazily; the maps above are still empty here.
        _refCodesLoaded = false;
        _refCodeByLocation = paragraphReferenceCodeLoadResult.byLocation;
        _paragraphReferenceCodesBySection =
            paragraphReferenceCodeLoadResult.bySection;
        _elibraryMarkupsByHref = elibraryMarkupsByHref;
        _loading = false;
      });
      final targetKey = _initialScrollTargetKey();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTarget(targetKey);
      });
      unawaited(
        LibraryReaderStateWriter.instance.stampLastOpened(widget.item.id),
      );
      if (savedShowRefCodes) {
        unawaited(_ensureParagraphReferenceCodesLoaded());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open this book: $error';
        _loading = false;
      });
    }
  }

  Future<void> _openSearch() async {
    final selection = await showViewerSearchDialog(
      context,
      fontScale: _fontScale,
      lastSearchTerm: _lastSearchTerm,
      initialMode: ReaderSearchMode.elibrary,
      onReturnToBible: widget.onReturnToBible,
    );
    if (!mounted || selection == null) return;
    final selectedSearchTerm = selection.lastSearchTerm.trim();
    if (selectedSearchTerm.isNotEmpty) {
      _lastSearchTerm = selectedSearchTerm;
    }
  }

  bool get _hasSearchSession {
    final session = widget.searchSession;
    return session != null && session.results.isNotEmpty;
  }

  Future<void> _navigateSearchHit(int delta) async {
    final session = widget.searchSession;
    if (session == null || session.results.isEmpty) return;
    final nextIndex = session.currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= session.results.length) return;
    final nextSession = session.copyWithIndex(nextIndex);
    final nextResult = nextSession.currentResult;
    await _saveCurrentLocation();
    await AppSettingsService.instance.saveLastElibrarySearchSessionJson(
      LibraryCatalogSearchSessionSnapshot.fromSession(
        nextSession,
      ).toJsonString(),
    );
    await AppSettingsService.instance.saveLastElibrarySearch(nextSession.query);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: nextResult.item,
          initialHref: nextResult.item.epubHref,
          initialAnchorId: nextResult.item.anchorId,
          initialSpineIndex: nextResult.item.spineIndex,
          initialParagraphIndex: nextResult.item.paragraphIndex,
          searchQuery: nextSession.query,
          highlightTerms: extractLibrarySearchHighlightTerms(nextSession.query),
          searchSession: nextSession,
          onReturnToBible: widget.onReturnToBible,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  void _beginLibraryRangeSelection(int blockIndex, int tokenIndex) {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.beginAt(blockIndex, tokenIndex);
    });
  }

  void _completeLibraryRangeSelection(int blockIndex, int tokenIndex) {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.completeAt(blockIndex, tokenIndex);
    });
  }

  void _clearLibraryRangeSelection() {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.clear();
    });
  }

  void _handleLibraryWordLongPress({
    required int blockIndex,
    required int tokenIndex,
  }) {
    if (_rangeSelection.isPendingRange) {
      _completeLibraryRangeSelection(blockIndex, tokenIndex);
      return;
    }
    _beginLibraryRangeSelection(blockIndex, tokenIndex);
  }

  void _handleLibraryWordLongPressMove({
    required int blockIndex,
    required int tokenIndex,
  }) {
    if (!_rangeSelection.hasSelection) {
      _beginLibraryRangeSelection(blockIndex, tokenIndex);
      return;
    }
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.completeAt(blockIndex, tokenIndex);
    });
  }

  String? _referenceCodeForSectionBlock({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required LibraryBookBlock block,
    required int blockIndex,
    required int paragraphIndex,
    required int devotionalFallbackParagraphCount,
    required Map<int, String> sectionReferenceCodes,
  }) {
    if (block.kind != 'paragraph') return null;
    final sectionTitle = libraryReaderDisplaySectionTitle(section?.title ?? '');
    if (item.isDevotional) {
      return libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: sectionTitle,
        block: block,
        fallbackParagraphCount: devotionalFallbackParagraphCount,
      );
    }
    if (item.isPeriodical) {
      return libraryReaderPeriodicalRefCode(
        item: item,
        sectionTitle: sectionTitle,
        paragraphIndex: paragraphIndex,
      );
    }

    return _refCodeByLocation[_refCodeLocationKey(
          libraryItemId: item.id,
          href: section?.entryName ?? '',
          paragraphIndex: paragraphIndex,
        )] ??
        sectionReferenceCodes[paragraphIndex];
  }

  String _buildLibrarySelectionReferenceLabel({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    return _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    ).compactRef;
  }

  ({String refStart, String refEnd, String compactRef})
  _buildLibrarySelectionReferenceEndpoints({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    final low = _rangeSelection.lowerAnchor;
    final high = _rangeSelection.upperAnchor;
    if (low == null || high == null) {
      final fallback = _buildEpubSelectionFallbackReference(
        item: item,
        section: section,
      );
      return (refStart: fallback, refEnd: fallback, compactRef: fallback);
    }

    final sectionReferenceCodes = section == null
        ? const <int, String>{}
        : item.isDevotional
        ? const <int, String>{}
        : _paragraphReferenceCodesBySection[_sectionKey(section.entryName)] ??
              const <int, String>{};

    final refs = <String>[];
    var paragraphIndex = 0;
    var devotionalFallbackParagraphCount = 0;
    for (var index = 0; index < sectionBlocks.length; index++) {
      final block = sectionBlocks[index];
      final isParagraph = block.kind == 'paragraph';
      if (isParagraph) {
        paragraphIndex += 1;
      }

      final referenceCode = _referenceCodeForSectionBlock(
        item: item,
        section: section,
        block: block,
        blockIndex: index,
        paragraphIndex: paragraphIndex,
        devotionalFallbackParagraphCount: devotionalFallbackParagraphCount,
        sectionReferenceCodes: sectionReferenceCodes,
      );
      if (item.isDevotional && referenceCode != null) {
        devotionalFallbackParagraphCount += 1;
      }

      if (index < low.blockIndex || index > high.blockIndex) continue;
      if (referenceCode == null) continue;
      final ref = cleanDisplayRefCode(referenceCode);
      if (ref != null && ref.trim().isNotEmpty) {
        refs.add(ref);
      }
    }

    if (refs.isEmpty) {
      final fallback = _buildEpubSelectionFallbackReference(
        item: item,
        section: section,
      );
      return (refStart: fallback, refEnd: fallback, compactRef: fallback);
    }
    final refStart = refs.first;
    final refEnd = refs.last;
    final compactRef = refs.length == 1
        ? refStart
        : libraryCompactReferenceRangeLabel(refStart, refEnd);
    return (refStart: refStart, refEnd: refEnd, compactRef: compactRef);
  }

  String _buildEpubSelectionFallbackReference({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
  }) {
    final title = item.displayTitle.trim();
    final sectionTitle = libraryReaderDisplaySectionTitle(section?.title ?? '');

    if (title.isNotEmpty && sectionTitle.isNotEmpty) {
      return '$title, $sectionTitle';
    }
    if (title.isNotEmpty) {
      return title;
    }
    if (sectionTitle.isNotEmpty) {
      return sectionTitle;
    }
    return 'eLibrary';
  }

  Future<void> _showLibrarySelectionActionsMenu({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    if (_librarySelectionActionsOpen) return;
    final selectedText = buildLibrarySelectionText(
      blocks: sectionBlocks,
      selection: _rangeSelection,
    );
    if (selectedText.trim().isEmpty) return;

    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    _librarySelectionActionsOpen = true;
    final action = await showLibrarySelectionRangeActionsSheet(
      context,
      payload: LibrarySelectionRangeActionsPayload(
        referenceLabel: referenceLabel,
        previewText: selectedText,
        enableClearMarkup: _hasElibraryMarkupOverlapForSelection(
          section: section,
          sectionBlocks: sectionBlocks,
        ),
      ),
      fontScale: _fontScale,
    );
    _librarySelectionActionsOpen = false;
    if (!mounted || action == null) return;

    switch (action) {
      case LibrarySelectionRangeAction.copyNoCitation:
        await _copyLibrarySelectionToClipboard(selectedText);
        return;
      case LibrarySelectionRangeAction.copyWithCitation:
        await _copyLibrarySelectionWithReferenceToClipboard(
          selectedText: selectedText,
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.copyWithMarkup:
        await _copyLibrarySelectionWithMarkupToClipboard(selectedText);
        return;
      case LibrarySelectionRangeAction.copyWithMarkupAndCitation:
        await _copyLibrarySelectionWithMarkupAndReferenceToClipboard(
          selectedText: selectedText,
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.highlight:
        final chosenColor = await showElibraryHighlightColorPicker(context);
        if (!mounted || chosenColor == null) return;
        await AppSettingsService.instance.saveDefaultElibraryHighlightColorHex(
          chosenColor,
        );
        await _saveElibraryHighlightForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
          referenceLabel: referenceLabel,
          selectedText: selectedText,
          colorHex: chosenColor,
        );
        return;
      case LibrarySelectionRangeAction.addHashTag:
        await _addElibraryHashTagForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
          selectedText: selectedText,
        );
        return;
      case LibrarySelectionRangeAction.clearMarkup:
        await _clearElibraryMarkupForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.resetRange:
        _clearLibraryRangeSelection();
        return;
    }
  }

  Future<void> _copyLibrarySelectionToClipboard(String selectedText) async {
    await _copyLibrarySelectionPayloadToClipboard(selectedText: selectedText);
  }

  Future<void> _copyLibrarySelectionWithReferenceToClipboard({
    required String selectedText,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    await _copyLibrarySelectionPayloadToClipboard(
      selectedText: selectedText,
      referenceLabel: referenceLabel,
    );
  }

  Future<void> _copyLibrarySelectionWithMarkupToClipboard(
    String selectedText,
  ) async {
    // Rich clipboard export is not available yet, so markup copies intentionally
    // fall back to plain text until a safe rich path exists.
    await _copyLibrarySelectionPayloadToClipboard(selectedText: selectedText);
  }

  Future<void> _copyLibrarySelectionWithMarkupAndReferenceToClipboard({
    required String selectedText,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    // Rich clipboard export is not available yet, so markup copies intentionally
    // fall back to plain text until a safe rich path exists.
    await _copyLibrarySelectionPayloadToClipboard(
      selectedText: selectedText,
      referenceLabel: referenceLabel,
    );
  }

  Future<void> _copyLibrarySelectionPayloadToClipboard({
    required String selectedText,
    String? referenceLabel,
  }) async {
    final trimmedText = selectedText.trimRight();
    final payload = referenceLabel == null
        ? trimmedText
        : trimmedText.isEmpty
        ? referenceLabel
        : '$trimmedText\n— $referenceLabel';
    if (payload.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: payload));
  }

  Future<Map<String, List<ElibraryMarkupRecord>>> _loadElibraryMarkups(
    String libraryItemId,
  ) async {
    try {
      return await ElibraryMarkupRepository().loadMarkupsBySectionForItem(
        libraryItemId,
      );
    } catch (error) {
      debugPrint('[LibraryBookReader] Failed to load eLibrary markups: $error');
      return const <String, List<ElibraryMarkupRecord>>{};
    }
  }

  ({
    int startBlockIndex,
    int startCharOffset,
    int endBlockIndex,
    int endCharOffset,
  })?
  _librarySelectionCharRange({required List<LibraryBookBlock> sectionBlocks}) {
    final low = _rangeSelection.lowerAnchor;
    final high = _rangeSelection.upperAnchor;
    if (low == null || high == null) return null;
    if (low.blockIndex < 0 ||
        high.blockIndex < low.blockIndex ||
        high.blockIndex >= sectionBlocks.length) {
      return null;
    }

    final startBlock = sectionBlocks[low.blockIndex];
    final endBlock = sectionBlocks[high.blockIndex];
    final startSpan = _libraryTokenSpanForIndex(
      startBlock.text,
      low.tokenIndex,
    );
    final endSpan = _libraryTokenSpanForIndex(endBlock.text, high.tokenIndex);
    if (startSpan == null || endSpan == null) return null;

    return (
      startBlockIndex: low.blockIndex,
      startCharOffset: startSpan.startOffset,
      endBlockIndex: high.blockIndex,
      endCharOffset: endSpan.endOffset,
    );
  }

  int? _libraryParagraphIndexForBlockIndex(
    List<LibraryBookBlock> sectionBlocks,
    int blockIndex,
  ) {
    if (blockIndex < 0 || blockIndex >= sectionBlocks.length) return null;
    var paragraphIndex = 0;
    for (var index = 0; index <= blockIndex; index++) {
      if (sectionBlocks[index].kind == 'paragraph') {
        paragraphIndex += 1;
      }
    }
    return paragraphIndex > 0 ? paragraphIndex : null;
  }

  bool _elibraryMarkupOverlapsSelection(
    ElibraryMarkupRecord record, {
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
  }) {
    if (record.deletedAt != null || !record.isHighlight) return false;
    if (record.endBlockIndex < startBlockIndex) return false;
    if (record.endBlockIndex == startBlockIndex &&
        record.endCharOffset <= startCharOffset) {
      return false;
    }
    if (record.startBlockIndex > endBlockIndex) return false;
    if (record.startBlockIndex == endBlockIndex &&
        record.startCharOffset >= endCharOffset) {
      return false;
    }
    return true;
  }

  bool _hasElibraryMarkupOverlapForSelection({
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    if (section == null) return false;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return false;
    final highlights =
        _elibraryMarkupsByHref[section.entryName] ??
        const <ElibraryMarkupRecord>[];
    for (final record in highlights) {
      if (_elibraryMarkupOverlapsSelection(
        record,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveElibraryHighlightForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String referenceLabel,
    required String selectedText,
    required String colorHex,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final endpoints = _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );

    try {
      final saved = await ElibraryMarkupRepository().saveHighlight(
        libraryItemId: item.id,
        epubHref: section.entryName,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        startTokenIndex: _rangeSelection.lowerAnchor?.tokenIndex,
        endTokenIndex: _rangeSelection.upperAnchor?.tokenIndex,
        refStart: endpoints.refStart,
        refEnd: endpoints.refEnd,
        compactRef: referenceLabel,
        selectedTextSnapshot: selectedText,
        color: colorHex,
      );
      if (saved == null) {
        throw StateError('Unable to save eLibrary highlight.');
      }
      if (!mounted) return;
      setState(() {
        final sectionKey = section.entryName;
        final existing = List<ElibraryMarkupRecord>.of(
          _elibraryMarkupsByHref[sectionKey] ?? const <ElibraryMarkupRecord>[],
        );
        existing.removeWhere((record) {
          return record.markupType == ElibraryMarkupRepository.highlightType &&
              record.startBlockIndex == saved.startBlockIndex &&
              record.startCharOffset == saved.startCharOffset &&
              record.endBlockIndex == saved.endBlockIndex &&
              record.endCharOffset == saved.endCharOffset;
        });
        existing.add(saved);
        existing.sort((left, right) {
          final blockCompare = left.startBlockIndex.compareTo(
            right.startBlockIndex,
          );
          if (blockCompare != 0) return blockCompare;
          final charCompare = left.startCharOffset.compareTo(
            right.startCharOffset,
          );
          if (charCompare != 0) return charCompare;
          return left.id.compareTo(right.id);
        });
        _elibraryMarkupsByHref = <String, List<ElibraryMarkupRecord>>{
          ..._elibraryMarkupsByHref,
          sectionKey: existing,
        };
        _rangeSelection = _rangeSelection.clear();
      });
    } catch (error) {
      debugPrint(
        '[LibraryBookReader] Failed to save eLibrary highlight: $error',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save highlight for $referenceLabel.'),
        ),
      );
    }
  }

  Future<void> _clearElibraryMarkupForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final existing =
        _elibraryMarkupsByHref[section.entryName] ??
        const <ElibraryMarkupRecord>[];
    final overlapping = existing
        .where((record) {
          return _elibraryMarkupOverlapsSelection(
            record,
            startBlockIndex: selectionRange.startBlockIndex,
            startCharOffset: selectionRange.startCharOffset,
            endBlockIndex: selectionRange.endBlockIndex,
            endCharOffset: selectionRange.endCharOffset,
          );
        })
        .toList(growable: false);
    if (overlapping.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved eLibrary markup overlaps this selection.'),
        ),
      );
      return;
    }

    final cleared = await ElibraryMarkupRepository()
        .clearHighlightsOverlappingSelection(
          libraryItemId: item.id,
          epubHref: section.entryName,
          startBlockIndex: selectionRange.startBlockIndex,
          startCharOffset: selectionRange.startCharOffset,
          endBlockIndex: selectionRange.endBlockIndex,
          endCharOffset: selectionRange.endCharOffset,
        );
    if (!mounted) return;
    if (cleared <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved eLibrary markup overlaps this selection.'),
        ),
      );
      return;
    }

    setState(() {
      final sectionKey = section.entryName;
      final updated =
          List<ElibraryMarkupRecord>.of(
            _elibraryMarkupsByHref[sectionKey] ??
                const <ElibraryMarkupRecord>[],
          )..removeWhere((record) {
            return _elibraryMarkupOverlapsSelection(
              record,
              startBlockIndex: selectionRange.startBlockIndex,
              startCharOffset: selectionRange.startCharOffset,
              endBlockIndex: selectionRange.endBlockIndex,
              endCharOffset: selectionRange.endCharOffset,
            );
          });
      _elibraryMarkupsByHref = <String, List<ElibraryMarkupRecord>>{
        ..._elibraryMarkupsByHref,
        sectionKey: updated,
      };
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Markup cleared for selected eLibrary range.'),
      ),
    );
  }

  Future<void> _addElibraryHashTagForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String selectedText,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final endpoints = _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    final passage = PassageData(
      bookNumber: null,
      bookName: item.displayTitle,
      chapter: 0,
      lines: const <VerseLine>[],
    );

    final repository = HashTagRepository();
    final defaultTag = repository.normalizeTagName(
      await repository.loadDefaultTag() ?? '',
    );
    if (!mounted) return;
    if (defaultTag.isNotEmpty) {
      final result = await _applyElibraryHashTagSelectionToTag(
        repository: repository,
        item: item,
        section: section,
        sectionBlocks: sectionBlocks,
        selectedText: selectedText,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        compactRef: endpoints.compactRef,
        tag: defaultTag,
      );
      if (!mounted) return;
      if (result.tag != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tagged selected range with ${result.tag}'
              '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
            ),
          ),
        );
        return;
      }
    }

    await showHashTagScreen(
      Navigator.of(context),
      passage: passage,
      selection: const ViewerRangeSelection(),
      selectionTargets: const <HashTagTarget>[],
      fontScale: _fontScale,
      selectionLabelOverride: endpoints.compactRef,
      onApplySelectionOverride: (tag) => _applyElibraryHashTagSelectionToTag(
        repository: repository,
        item: item,
        section: section,
        sectionBlocks: sectionBlocks,
        selectedText: selectedText,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        compactRef: endpoints.compactRef,
        tag: tag,
      ),
    );
  }

  Future<HashTagQuickApplyResult> _applyElibraryHashTagSelectionToTag({
    required HashTagRepository repository,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String selectedText,
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
    required String compactRef,
    required String tag,
  }) async {
    if (section == null) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }
    final result = await repository.quickApplyELibrarySearchResult(
      bookTitle: item.displayTitle,
      locationText: compactRef,
      paragraphText: selectedText,
      stableRef:
          'elibrary-range:${item.id}:${section.entryName}:$startBlockIndex:$startCharOffset:$endBlockIndex:$endCharOffset',
      referenceText: compactRef,
      sourceHref: section.entryName,
      sourceAnchorId: item.anchorId,
      sourceSpineIndex: section.spineIndex,
      sourceParagraphIndex: _libraryParagraphIndexForBlockIndex(
        sectionBlocks,
        startBlockIndex,
      ),
      sourceRelativePath: item.relativePath,
      sourceLibraryItemId: item.id,
      selectedTextSnapshot: selectedText,
      selectionStartBlockIndex: startBlockIndex,
      selectionStartCharOffset: startCharOffset,
      selectionEndBlockIndex: endBlockIndex,
      selectionEndCharOffset: endCharOffset,
      selectionStartTokenIndex: _rangeSelection.lowerAnchor?.tokenIndex,
      selectionEndTokenIndex: _rangeSelection.upperAnchor?.tokenIndex,
      tag: tag,
    );
    return HashTagQuickApplyResult(
      tag: result.tag,
      inserted: result.inserted,
      skipped: result.skipped,
    );
  }

  ({int startOffset, int endOffset})? _libraryTokenSpanForIndex(
    String text,
    int tokenIndex,
  ) {
    final runs = _splitLibraryTextRuns(text);
    for (final run in runs) {
      if (run.tokenIndex != tokenIndex) continue;
      final startOffset = run.startOffset;
      final endOffset = run.endOffset;
      if (startOffset == null || endOffset == null) return null;
      return (startOffset: startOffset, endOffset: endOffset);
    }
    return null;
  }

  Future<void> _backToBible() async {
    final returnToBible = widget.onReturnToBible;
    final navigator = Navigator.of(context);
    await _saveCurrentLocation();
    if (!mounted) return;
    if (returnToBible != null) {
      returnToBible();
      return;
    }
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.maybePop();
    }
  }

  Future<void> _closeToLibrary() async {
    final navigator = Navigator.of(context);
    await _saveCurrentLocation();
    if (!mounted) return;
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.maybePop();
    }
  }

  bool get _canDropImportedBook {
    return libraryReaderCanManageImportedBook(widget.item);
  }

  Future<void> _dropImportedBook() async {
    if (!_canDropImportedBook) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Current Book from Library?'),
        content: Text(
          'This removes the imported database copy only. It does not delete '
          'or modify the original CaptureClipper source files.\n\n'
          'Book: "${widget.item.displayTitle}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final removed = await PioneerTextImportService.instance
        .removeImportedLibraryItem(widget.item.id);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That book could not be removed from the library.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${widget.item.displayTitle}" from eLibrary.'),
      ),
    );
    await _closeToLibrary();
  }

  Future<void> _repairImportedBook() async {
    if (!_canDropImportedBook) return;

    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repair Current Imported Book?'),
        content: Text(
          'This removes the imported database copy and reimports it from the '
          'configured CaptureClipper source folder.\n\n'
          'The original source files are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final report = await PioneerCapturedHtmlImportFolderService.instance
        .repairImportedCaptureClipperBook(libraryItemId: widget.item.id);
    if (!mounted) return;
    if (report == null || report.entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not find the original CaptureClipper source for this book.',
          ),
        ),
      );
      return;
    }

    final repaired = report.entries.firstWhere(
      (entry) => entry.libraryItemId == widget.item.id,
      orElse: () => report.entries.first,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Repaired "${repaired.title}" from its CaptureClipper source.',
        ),
      ),
    );
    await _load();
  }

  Future<void> _openELibrarySetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ELibrarySetupScreen()),
    );
  }

  Widget _buildReaderActionsMenu({
    required ThemeData theme,
    required Color textColor,
    required Color cardBackground,
    required Color cardBorder,
  }) {
    return PopupMenuButton<_ReaderBookMenuAction>(
      tooltip: 'Library actions',
      onSelected: (action) {
        switch (action) {
          case _ReaderBookMenuAction.openELibrarySetup:
            unawaited(_openELibrarySetup());
            return;
          case _ReaderBookMenuAction.removeCurrentBook:
            unawaited(_dropImportedBook());
            return;
          case _ReaderBookMenuAction.repairCurrentImportedBook:
            unawaited(_repairImportedBook());
            return;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<_ReaderBookMenuAction>>[
          const PopupMenuItem<_ReaderBookMenuAction>(
            value: _ReaderBookMenuAction.openELibrarySetup,
            child: Text('Open eLibrary Setup'),
          ),
        ];
        if (_canDropImportedBook) {
          items.addAll(const [
            PopupMenuItem<_ReaderBookMenuAction>(
              enabled: false,
              child: Text('Maintenance'),
            ),
            PopupMenuItem<_ReaderBookMenuAction>(
              value: _ReaderBookMenuAction.removeCurrentBook,
              child: Text('Remove Current Book from Library'),
            ),
            PopupMenuItem<_ReaderBookMenuAction>(
              value: _ReaderBookMenuAction.repairCurrentImportedBook,
              child: Text('Repair Current Imported Book'),
            ),
          ]);
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.more_horiz,
              size: 18,
              color: textColor.withValues(alpha: 0.82),
            ),
            const SizedBox(width: 6),
            Text(
              'Menu',
              style: libraryControlTextStyle(
                context,
                theme.textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: textColor.withValues(alpha: 0.82),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrentLocation() async {
    if (_sections.isEmpty ||
        _selectedIndex < 0 ||
        _selectedIndex >= _sections.length) {
      return;
    }

    final currentSection = _sections[_selectedIndex];
    final currentNavigationItem = _selectedNavigationItem;
    final savedHref = currentNavigationItem?.href?.trim();
    final savedAnchorId = currentNavigationItem?.parentId != null
        ? currentNavigationItem?.anchorId?.trim()
        : null;
    final savedParagraphIndex = currentNavigationItem?.parentId != null
        ? currentNavigationItem?.bodyOrder
        : null;
    await LibraryReaderStateWriter.instance.saveCurrentLocation(
      libraryItemId: widget.item.id,
      currentSectionEntryName: currentSection.entryName,
      currentSectionSpineIndex: currentSection.spineIndex,
      savedHref: savedHref,
      savedAnchorId: savedAnchorId,
      savedParagraphIndex: savedParagraphIndex,
    );
  }

  void _selectSection(int index) {
    if (index < 0 || index >= _sections.length) return;
    final navIndex = _navigationIndexForSectionIndex(index);
    setState(() {
      _selectedIndex = index;
      if (navIndex != null) {
        _selectedNavigationIndex = navIndex;
      }
      _selectedHeadingTargetIndex = null;
      _pendingBodyScrollTargetKey = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToTarget(null);
      }
    });
  }

  LibraryBookSection? get _currentSection {
    if (_sections.isEmpty) return null;
    final index = _selectedIndex.clamp(0, _sections.length - 1);
    return _sections[index];
  }

  LibraryCatalogNavigationItem? get _selectedNavigationItem {
    final navigationItems = _orderedNavigationItems;
    if (_selectedNavigationIndex < 0 ||
        _selectedNavigationIndex >= navigationItems.length) {
      return null;
    }
    return navigationItems[_selectedNavigationIndex];
  }

  /// Resolves the first readable descendant within the currently selected
  /// TOC node's own subtree, for composing a useful display when that node
  /// is heading-only. Returns null when the node has readable content of
  /// its own, or no readable descendant exists in its subtree.
  LibraryReaderDescendantChain? get _currentSectionReadableDescendantChain {
    if (_navigationItems.isEmpty) return null;
    final navItem = _selectedNavigationItem;
    if (navItem == null) return null;
    final tree = buildLibraryNavigationTree(
      _navigationItems,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    return libraryReaderFirstReadableDescendant(
      navItem: navItem,
      tree: tree,
      sections: _sections,
    );
  }

  bool get _isDevotionalNavigationBook {
    return widget.item.isDevotional || isDevotionalNavigation(_navigationItems);
  }

  String get _currentSubtitle {
    return libraryReaderBookSubtitle(
      widget.item,
      sectionTitle: libraryReaderDisplaySectionTitle(
        _currentSection?.title ?? '',
      ),
    );
  }

  int _initialSectionIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required bool devotionalMode,
  }) {
    return libraryReaderInitialSectionIndex(
      item: widget.item,
      sections: sections,
      navigationItems: navigationItems,
      devotionalMode: devotionalMode,
      initialHref: widget.initialHref,
      initialSpineIndex: widget.initialSpineIndex,
    );
  }

  int? _readableSectionIndexForHref(
    List<LibraryBookSection> sections,
    String href,
  ) {
    final sectionIndex = _sectionIndexForHref(sections, href);
    if (sectionIndex == null) return null;
    return _isRealContentSection(sections[sectionIndex]) ? sectionIndex : null;
  }

  int? _sectionIndexForSpineIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    if (navigationItems.isNotEmpty) {
      for (var i = 0; i < navigationItems.length; i++) {
        final nav = navigationItems[i];
        if (nav.spineIndex == spineIndex) {
          final sectionIndex = _sectionIndexForNavigationItemInSections(
            sections,
            nav,
          );
          if (sectionIndex != null) return sectionIndex;
        }
      }
    }

    if (spineIndex > 0 && spineIndex <= sections.length) {
      return spineIndex - 1;
    }

    return null;
  }

  int? _navigationIndexForSavedState({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    if (navigationItems.isEmpty) return null;
    for (var i = 0; i < navigationItems.length; i++) {
      final nav = navigationItems[i];
      if (nav.spineIndex == spineIndex) {
        final sectionIndex = _sectionIndexForNavigationItemInSections(
          sections,
          nav,
        );
        if (sectionIndex != null) return sectionIndex;
      }
    }
    if (spineIndex > 0 && spineIndex <= sections.length) {
      return spineIndex - 1;
    }
    return null;
  }

  int? _readableSectionIndexForSpineIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    final sectionIndex = _sectionIndexForSpineIndex(
      sections: sections,
      navigationItems: navigationItems,
      spineIndex: spineIndex,
    );
    if (sectionIndex == null) return null;
    return _isRealContentSection(sections[sectionIndex]) ? sectionIndex : null;
  }

  int? _sectionIndexForHref(List<LibraryBookSection> sections, String href) {
    final normalizedHref = p.normalize(href).toLowerCase();
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_hrefMatchesSection(section.entryName, normalizedHref)) {
        return index;
      }
    }
    return null;
  }

  int? _firstRealContentSectionIndex(List<LibraryBookSection> sections) {
    int? firstMeaningfulIndex;
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (!libraryIsMeaningfulReadingSection(
        title: section.title,
        href: section.entryName,
        paragraphs: section.paragraphs,
        bookTitle: widget.item.displayTitle,
      )) {
        continue;
      }
      firstMeaningfulIndex ??= index;
      if (libraryIsFrontMatterOpeningLabel(section.title) ||
          libraryIsFrontMatterOpeningLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        continue;
      }
      return index;
    }
    if (firstMeaningfulIndex != null) return firstMeaningfulIndex;
    return sections.isEmpty ? null : 0;
  }

  bool _isRealContentSection(LibraryBookSection section) {
    return libraryIsMeaningfulReadingSection(
      title: section.title,
      href: section.entryName,
      paragraphs: section.paragraphs,
      bookTitle: widget.item.displayTitle,
    );
  }

  bool _isReaderChapterOneLabel(String value) {
    final normalized = _normalizeReaderLabel(value);
    if (normalized.isEmpty) return false;

    const prefixes = <String>[
      'chapter 1',
      'chapter i',
      'chapter one',
      '1 ',
      '1.',
      '1)',
      'i ',
      'i.',
      'i)',
    ];
    for (final prefix in prefixes) {
      if (normalized == prefix.trim() || normalized.startsWith(prefix)) {
        return true;
      }
    }

    return false;
  }

  List<LibraryCatalogNavigationItem> get _orderedNavigationItems {
    if (_navigationItems.isEmpty) return const [];

    final tree = buildLibraryNavigationTree(
      _navigationItems,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    return tree.items;
  }

  int? _navigationIndexForSectionIndex(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return null;
    final section = _sections[sectionIndex];
    final sectionHref = p.normalize(section.entryName).toLowerCase();
    final sectionSpineIndex = section.spineIndex;
    final navigationItems = _orderedNavigationItems;
    for (var index = 0; index < navigationItems.length; index++) {
      final nav = navigationItems[index];
      final navHref = _cleanNavigationHref(nav.href);
      if (navHref != null && _hrefMatchesSection(navHref, sectionHref)) {
        return index;
      }
      if (sectionSpineIndex != null && nav.spineIndex == sectionSpineIndex) {
        return index;
      }
    }
    return null;
  }

  int? _sectionIndexForNavigationItem(LibraryCatalogNavigationItem item) {
    if (_sections.isEmpty) return null;
    final href = _cleanNavigationHref(item.href);
    if (href != null) {
      final normalizedHref = href.toLowerCase();
      for (var index = 0; index < _sections.length; index++) {
        if (_hrefMatchesSection(_sections[index].entryName, normalizedHref)) {
          return index;
        }
      }
    }

    if (item.spineIndex != null) {
      for (var index = 0; index < _sections.length; index++) {
        if (_sections[index].spineIndex == item.spineIndex) return index;
      }
    }

    return null;
  }

  int? _sectionIndexForNavigationItemInSections(
    List<LibraryBookSection> sections,
    LibraryCatalogNavigationItem item,
  ) {
    if (sections.isEmpty) return null;
    final href = _cleanNavigationHref(item.href);
    if (href != null) {
      final normalizedHref = href.toLowerCase();
      for (var index = 0; index < sections.length; index++) {
        if (_hrefMatchesSection(sections[index].entryName, normalizedHref)) {
          return index;
        }
      }
    }

    if (item.spineIndex != null) {
      for (var index = 0; index < sections.length; index++) {
        if (sections[index].spineIndex == item.spineIndex) return index;
      }
    }

    return null;
  }

  String? _firstRealContentNavigationHref(
    List<LibraryCatalogNavigationItem> navigationItems,
  ) {
    if (navigationItems.isEmpty) return null;

    // Imports can mark an intro/preface as the body start when it carries
    // enough text, so a body-start flag alone is not trusted; the label must
    // not look like front matter either.
    bool looksLikeFrontMatter(LibraryCatalogNavigationItem item, String href) {
      return item.isFrontMatter ||
          libraryIsFrontMatterOpeningLabel(item.label) ||
          libraryIsFrontMatterOpeningLabel(p.basenameWithoutExtension(href));
    }

    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (looksLikeFrontMatter(item, href)) continue;
      return href;
    }

    // Every navigation item looks like front matter; fall back to the first
    // one that is at least not pure metadata (cover/TOC/copyright).
    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (_isReaderMetadataHelpLabel(item.label) ||
          _isReaderMetadataHelpLabel(p.basenameWithoutExtension(href)) ||
          item.isFrontMatter) {
        continue;
      }
      return href;
    }

    return null;
  }

  String? _devotionalInitialNavigationHref(
    List<LibraryCatalogNavigationItem> navigationItems,
  ) {
    if (navigationItems.isEmpty) return null;

    final tree = buildLibraryNavigationTree(
      navigationItems,
      devotionalMode: true,
    );
    final roots = tree.childrenByParent[null] ?? const [];
    if (roots.isEmpty) return null;

    final now = DateTime.now();
    final currentMonth = _devotionalMonthName(now.month);
    final currentDay = now.day;

    final todayTarget = _devotionalNavigationHrefForMonthAndDay(
      roots: roots,
      tree: tree,
      monthName: currentMonth,
      day: currentDay,
    );
    if (todayTarget != null) return todayTarget;

    final currentMonthTarget = _devotionalNavigationHrefForMonth(
      roots: roots,
      tree: tree,
      monthName: currentMonth,
    );
    if (currentMonthTarget != null) return currentMonthTarget;

    final januaryTarget = _devotionalNavigationHrefForMonth(
      roots: roots,
      tree: tree,
      monthName: 'january',
    );
    if (januaryTarget != null) return januaryTarget;

    return _firstRealContentNavigationHref(navigationItems);
  }

  String? _devotionalNavigationHrefForMonthAndDay({
    required List<LibraryCatalogNavigationItem> roots,
    required LibraryNavigationTreeResult tree,
    required String monthName,
    required int day,
  }) {
    final monthRoot = _devotionalMonthRoot(roots, monthName);
    if (monthRoot == null) return null;

    final children = tree.childrenByParent[monthRoot.id] ?? const [];
    final dayMatch = _devotionalDayChild(children, monthName, day);
    if (dayMatch != null) return _cleanNavigationHref(dayMatch.href);

    return null;
  }

  String? _devotionalNavigationHrefForMonth({
    required List<LibraryCatalogNavigationItem> roots,
    required LibraryNavigationTreeResult tree,
    required String monthName,
  }) {
    final monthRoot = _devotionalMonthRoot(roots, monthName);
    if (monthRoot == null) return null;

    final children = tree.childrenByParent[monthRoot.id] ?? const [];
    final firstChild = children.firstWhere(
      (child) => _cleanNavigationHref(child.href) != null,
      orElse: () => monthRoot,
    );
    final firstChildHref = _cleanNavigationHref(firstChild.href);
    if (firstChildHref != null) return firstChildHref;

    return _cleanNavigationHref(monthRoot.href);
  }

  LibraryCatalogNavigationItem? _devotionalMonthRoot(
    List<LibraryCatalogNavigationItem> roots,
    String monthName,
  ) {
    for (final root in roots) {
      final labelInfo = parseDevotionalNavigationLabel(root.label);
      if (labelInfo != null &&
          labelInfo.isMonthHeading &&
          _devotionalMonthName(labelInfo.monthIndex) == monthName) {
        return root;
      }
    }
    return null;
  }

  LibraryCatalogNavigationItem? _devotionalDayChild(
    List<LibraryCatalogNavigationItem> children,
    String monthName,
    int day,
  ) {
    for (final child in children) {
      final labelInfo = parseDevotionalNavigationLabel(child.label);
      if (labelInfo == null || labelInfo.isMonthHeading) continue;
      if (_devotionalMonthName(labelInfo.monthIndex) != monthName) continue;
      if (labelInfo.day == day) return child;
    }
    return null;
  }

  String _devotionalMonthName(int monthIndex) {
    const months = <String>[
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    if (monthIndex < 1 || monthIndex > months.length) return '';
    return months[monthIndex - 1];
  }

  void _selectNavigationItem(LibraryCatalogNavigationItem navItem) {
    final navigationItems = _orderedNavigationItems;
    final navIndex = navigationItems.indexWhere((nav) => nav.id == navItem.id);
    final tree = buildLibraryNavigationTree(
      navigationItems,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    final normalizedNavItem = libraryReaderVisibleContentsNavigationItem(
      navItem: navItem,
      tree: tree,
      sections: _sections,
    );
    final effectiveNavItem = normalizedNavItem ?? navItem;
    final effectiveNavIndex = normalizedNavItem == null
        ? navIndex
        : navigationItems.indexWhere((nav) => nav.id == normalizedNavItem.id);
    final effectiveSectionIndex = _sectionIndexForNavigationItem(
      effectiveNavItem,
    );
    final targetSection =
        effectiveSectionIndex != null &&
            effectiveSectionIndex >= 0 &&
            effectiveSectionIndex < _sections.length
        ? _sections[effectiveSectionIndex]
        : _currentSection;
    final targetKey =
        libraryReaderContentsTargetKeyForNavigationItem(
          navItem: effectiveNavItem,
          sections: _sections,
        ) ??
        _fallbackTargetKeyForNavigationItem(
          effectiveNavItem,
          section: targetSection,
        );
    final shouldJumpToSectionStart =
        libraryReaderNavigationItemTargetsSectionStart(
          navItem: effectiveNavItem,
          sections: _sections,
        );
    setState(() {
      if (effectiveNavIndex >= 0) {
        _selectedNavigationIndex = effectiveNavIndex;
      }
      if (effectiveSectionIndex != null) {
        _selectedIndex = effectiveSectionIndex;
      }
      _pendingBodyScrollTargetKey = targetKey;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        if (shouldJumpToSectionStart && effectiveSectionIndex != null) {
          _selectSection(effectiveSectionIndex);
          return;
        }
        _scrollToTarget(targetKey);
      }
    });
  }

  double _pageScrollStep() {
    if (_bodyScrollController.hasClients) {
      final viewportHeight = _bodyScrollController.position.viewportDimension;
      if (viewportHeight > 0) {
        return viewportHeight * 0.9;
      }
    }
    return MediaQuery.sizeOf(context).height * 0.9;
  }

  double? _scrollOffsetForContext(BuildContext targetContext) {
    if (!_bodyScrollController.hasClients) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject == null) return null;
    final viewport = RenderAbstractViewport.of(renderObject);
    return viewport.getOffsetToReveal(renderObject, 0.0).offset;
  }

  List<_ReaderHeadingTarget> _headingTargetsForCurrentSection() {
    final currentSection = _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) {
      return const [];
    }

    final targets = <_ReaderHeadingTarget>[];
    final currentSectionHref = p
        .normalize(currentSection.entryName)
        .toLowerCase();
    final currentSectionSpineIndex = currentSection.spineIndex;

    final navigationTargets = _orderedNavigationItems
        .where((navItem) {
          final contentKind = navItem.contentKind?.trim().toLowerCase();
          if (contentKind != 'body_subsection') return false;
          final navHref = _cleanNavigationHref(navItem.href);
          if (navHref != null &&
              _hrefMatchesSection(navHref, currentSectionHref)) {
            return true;
          }
          return currentSectionSpineIndex != null &&
              navItem.spineIndex == currentSectionSpineIndex;
        })
        .toList(growable: false);

    for (final navItem in navigationTargets) {
      final targetKey = _navigationTargetKey(navItem);
      if (targetKey == null) continue;
      final targetContext = _bodyBlockKeys[targetKey]?.currentContext;
      if (targetContext == null) continue;

      final targetOffset = _scrollOffsetForContext(targetContext);
      if (targetOffset == null) continue;

      targets.add(_ReaderHeadingTarget(key: targetKey, offset: targetOffset));
    }

    if (targets.isEmpty) {
      final normalizedSectionTitle = _normalizeReaderLabel(
        currentSection.title,
      );
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (!block.isHeading) continue;

        if (normalizedSectionTitle.isNotEmpty &&
            _normalizeReaderLabel(block.text) == normalizedSectionTitle) {
          continue;
        }

        final targetKey = _blockTargetKey(block, index);
        final targetContext = _bodyBlockKeys[targetKey]?.currentContext;
        if (targetContext == null) continue;

        final targetOffset = _scrollOffsetForContext(targetContext);
        if (targetOffset == null) continue;

        targets.add(_ReaderHeadingTarget(key: targetKey, offset: targetOffset));
      }
    }

    targets.sort((left, right) => left.offset.compareTo(right.offset));
    return targets;
  }

  void _scrollToAdjacentHeading({required bool forward}) {
    if (_sections.isEmpty) return;
    if (!_bodyScrollController.hasClients) return;

    // Periodicals have one article per spine section; jump directly to the
    // adjacent section instead of hunting for sub-headings within the page.
    if (widget.item.isPeriodical) {
      _selectSection(forward ? _selectedIndex + 1 : _selectedIndex - 1);
      return;
    }

    final targets = _headingTargetsForCurrentSection();
    if (targets.isEmpty) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = forward ? _selectedIndex + 1 : _selectedIndex - 1;
      if (fallbackIndex < 0 || fallbackIndex >= _sections.length) {
        return;
      }
      _selectSection(fallbackIndex);
      return;
    }

    final currentOffset = _bodyScrollController.offset;
    const epsilon = 1.0;

    _ReaderHeadingTarget? target;
    var targetIndex = _selectedHeadingTargetIndex;
    if (targetIndex != null &&
        (targetIndex < 0 || targetIndex >= targets.length)) {
      targetIndex = null;
    }

    if (targetIndex != null) {
      final candidateIndex = forward ? targetIndex + 1 : targetIndex - 1;
      if (candidateIndex >= 0 && candidateIndex < targets.length) {
        targetIndex = candidateIndex;
        target = targets[targetIndex];
      } else {
        targetIndex = null;
      }
    }

    if (target == null) {
      if (forward) {
        for (var index = 0; index < targets.length; index++) {
          final candidate = targets[index];
          if (candidate.offset > currentOffset + epsilon) {
            target = candidate;
            targetIndex = index;
            break;
          }
        }
      } else {
        for (var index = targets.length - 1; index >= 0; index--) {
          final candidate = targets[index];
          if (candidate.offset < currentOffset - epsilon) {
            target = candidate;
            targetIndex = index;
            break;
          }
        }
      }
    }

    if (target == null) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = forward ? _selectedIndex + 1 : _selectedIndex - 1;
      if (fallbackIndex < 0 || fallbackIndex >= _sections.length) {
        return;
      }
      _selectSection(fallbackIndex);
      return;
    }

    final targetContext = _bodyBlockKeys[target.key]?.currentContext;
    if (targetContext == null) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = forward ? _selectedIndex + 1 : _selectedIndex - 1;
      if (fallbackIndex < 0 || fallbackIndex >= _sections.length) return;
      _selectSection(fallbackIndex);
      return;
    }

    _selectedHeadingTargetIndex = targetIndex;

    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  String? _initialScrollTargetKey() {
    if (_hasExplicitInitialSourceLocation) {
      return _explicitInitialScrollTargetKey();
    }

    final savedTargetKey = _isDevotionalNavigationBook
        ? null
        : _savedLocationTargetKey();
    if (savedTargetKey != null) return savedTargetKey;

    final headingTargets = _headingTargetsForCurrentSection();
    if (headingTargets.isNotEmpty) {
      return headingTargets.first.key;
    }

    return null;
  }

  bool get _hasExplicitInitialSourceLocation {
    return (widget.initialHref?.trim().isNotEmpty ?? false) ||
        (widget.initialAnchorId?.trim().isNotEmpty ?? false) ||
        (widget.initialSpineIndex != null && widget.initialSpineIndex! > 0) ||
        (widget.initialParagraphIndex != null &&
            widget.initialParagraphIndex! > 0);
  }

  String? _explicitInitialScrollTargetKey() {
    final currentSection = _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final initialHrefParts = _splitReaderHref(widget.initialHref);
    final initialAnchorId =
        widget.initialAnchorId?.trim() ?? initialHrefParts.anchor ?? '';
    if (initialAnchorId.isNotEmpty) {
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (block.anchorId?.trim() == initialAnchorId) {
          return _blockTargetKey(block, index);
        }
      }
    }

    final initialParagraphIndex = widget.initialParagraphIndex;
    if (initialParagraphIndex != null && initialParagraphIndex > 0) {
      var paragraphCounter = 0;
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (block.kind != 'paragraph') continue;
        paragraphCounter += 1;
        if (paragraphCounter == initialParagraphIndex) {
          return _blockTargetKey(block, index);
        }
      }
    }

    return null;
  }

  String? _savedLocationTargetKey() {
    final currentSection = _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final savedAnchorId = widget.item.anchorId?.trim() ?? '';
    final savedBodyOrder = widget.item.paragraphIndex;
    if (savedAnchorId.isEmpty && savedBodyOrder == null) return null;

    for (var index = 0; index < currentSection.blocks.length; index++) {
      final block = currentSection.blocks[index];
      if (savedAnchorId.isNotEmpty && block.anchorId?.trim() == savedAnchorId) {
        return _blockTargetKey(block, index);
      }
      if (savedBodyOrder != null && block.bodyOrder == savedBodyOrder) {
        return _blockTargetKey(block, index);
      }
    }

    return null;
  }

  String? _fallbackTargetKeyForNavigationItem(
    LibraryCatalogNavigationItem navItem, {
    LibraryBookSection? section,
  }) {
    final currentSection = section ?? _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final normalizedNavLabel = _normalizeReaderLabel(
      navigationDisplayLabel(
        navItem,
        devotionalMode: _isDevotionalNavigationBook,
      ),
    );
    final normalizedRawLabel = _normalizeReaderLabel(navItem.label);
    final isChapterOneNavigation =
        _isReaderChapterOneLabel(navItem.label) ||
        _isReaderChapterOneLabel(normalizedNavLabel) ||
        _isReaderChapterOneLabel(normalizedRawLabel);

    for (var index = 0; index < currentSection.blocks.length; index++) {
      final block = currentSection.blocks[index];
      if (!block.isHeading) continue;
    }

    if (isChapterOneNavigation) {
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (!block.isHeading) continue;
        if (_isReaderChapterOneLabel(block.text)) {
          return _blockTargetKey(block, index);
        }
      }
    }

    return null;
  }

  void _scrollToTarget(String? targetKey, {int attempt = 0}) {
    if (!_bodyScrollController.hasClients) return;
    final resolvedTargetKey = targetKey ?? _pendingBodyScrollTargetKey;
    final targetContext = resolvedTargetKey == null
        ? null
        : _bodyBlockKeys[resolvedTargetKey]?.currentContext;
    if (targetContext != null) {
      _selectedHeadingTargetIndex = null;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
      _pendingBodyScrollTargetKey = null;
      return;
    }

    if (resolvedTargetKey != null && attempt < 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTarget(resolvedTargetKey, attempt: attempt + 1);
      });
      return;
    }

    _pendingBodyScrollTargetKey = null;
    _selectedHeadingTargetIndex = null;
    _bodyScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  void _scrollPageUp() {
    if (!_bodyScrollController.hasClients) return;
    _selectedHeadingTargetIndex = null;
    final target = (_bodyScrollController.offset - _pageScrollStep()).clamp(
      0.0,
      _bodyScrollController.position.maxScrollExtent,
    );
    if ((target - _bodyScrollController.offset).abs() < 0.5) return;
    _bodyScrollController.jumpTo(target);
  }

  void _scrollPageDown() {
    if (!_bodyScrollController.hasClients) return;
    _selectedHeadingTargetIndex = null;
    final target = (_bodyScrollController.offset + _pageScrollStep()).clamp(
      0.0,
      _bodyScrollController.position.maxScrollExtent,
    );
    if ((target - _bodyScrollController.offset).abs() < 0.5) return;
    _bodyScrollController.jumpTo(target);
  }

  String? _navigationTargetKey(LibraryCatalogNavigationItem navItem) {
    final anchorId = navItem.anchorId?.trim();
    if (anchorId != null && anchorId.isNotEmpty) {
      return 'anchor:${_normalizeBlockKey(anchorId)}';
    }
    final bodyOrder = navItem.bodyOrder;
    if (bodyOrder != null) {
      return 'body:$bodyOrder';
    }
    return null;
  }

  String _blockTargetKey(LibraryBookBlock block, int index) {
    final anchorId = block.anchorId?.trim();
    if (anchorId != null && anchorId.isNotEmpty) {
      return 'anchor:${_normalizeBlockKey(anchorId)}';
    }
    final bodyOrder = block.bodyOrder;
    if (bodyOrder != null) {
      return 'body:$bodyOrder';
    }
    return 'block:$index';
  }

  GlobalKey _keyForBlock(String key) {
    return _bodyBlockKeys.putIfAbsent(key, GlobalKey.new);
  }

  GlobalKey _textKeyForBlock(String key) {
    return _bodyTextKeys.putIfAbsent(key, GlobalKey.new);
  }

  ({int blockIndex, int tokenIndex})? _resolveLibraryDragTokenHit({
    required Offset globalPosition,
    required List<LibraryBookBlock> sectionBlocks,
    required int preferredBlockIndex,
    required double bodyFontSize,
    required Color textColor,
    required bool isNightMode,
    required String? highlightQuery,
    required List<String> highlightTerms,
    required TextDirection textDirection,
  }) {
    ({int blockIndex, int tokenIndex})? bestHit;
    var bestDistance = double.infinity;
    final theme = Theme.of(context);

    for (var index = 0; index < sectionBlocks.length; index++) {
      final block = sectionBlocks[index];
      final key = _bodyTextKeys[_blockTargetKey(block, index)];
      final context = key?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      final distance = _distanceSquaredToRect(globalPosition, rect);
      if (distance > bestDistance) continue;

      final isHeading = block.isHeading;
      final className = block.className ?? '';
      final isChapterTitle =
          isHeading && _hasEpubClass(className, 'chapterhead');
      final isSectionTitle =
          isHeading && _hasEpubClass(className, 'sectionhead');
      final isDevotionalLead =
          _hasEpubClass(className, 'devotionaltext') ||
          _hasEpubClass(className, 'bibletext') ||
          _hasEpubClass(className, 'center');
      final fontSize = isChapterTitle
          ? bodyFontSize * 1.95
          : isHeading
          ? bodyFontSize * _headingFontScale(block.headingLevel)
          : isDevotionalLead
          ? bodyFontSize * 1.02
          : bodyFontSize;
      final textAlign = isChapterTitle || isSectionTitle || isDevotionalLead
          ? TextAlign.center
          : TextAlign.start;
      final style =
          (isChapterTitle
                  ? theme.textTheme.headlineSmall
                  : isHeading
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyLarge)
              ?.copyWith(
                color: textColor,
                fontWeight: isChapterTitle || isSectionTitle || isDevotionalLead
                    ? FontWeight.w800
                    : isHeading
                    ? FontWeight.w700
                    : FontWeight.w400,
                fontSize: fontSize,
                height: isChapterTitle
                    ? 1.12
                    : isHeading
                    ? 1.35
                    : isDevotionalLead
                    ? 1.45
                    : block.isBlockquote
                    ? 1.7
                    : 1.6,
                fontStyle: block.isBlockquote ? FontStyle.italic : null,
              );
      final resolvedStyle =
          style ??
          theme.textTheme.bodyLarge?.copyWith(color: textColor) ??
          TextStyle(color: textColor, fontSize: bodyFontSize, height: 1.6);

      final localPosition = renderObject.globalToLocal(globalPosition);
      final tokenIndex = hitTestLibraryInteractiveEpubTokenIndex(
        html: block.html,
        fallbackText: block.text,
        baseStyle: resolvedStyle,
        maxWidth: renderObject.size.width,
        localPosition: localPosition,
        textDirection: textDirection,
        textAlign: textAlign,
        highlightQuery: highlightQuery,
        highlightTerms: highlightTerms,
      );
      if (tokenIndex == null || tokenIndex <= 0) continue;
      bestDistance = distance;
      bestHit = (blockIndex: index, tokenIndex: tokenIndex);
    }

    return bestHit;
  }

  String _normalizeBlockKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  double _distanceSquaredToRect(Offset point, Rect rect) {
    final clampedX = point.dx < rect.left
        ? rect.left
        : point.dx > rect.right
        ? rect.right
        : point.dx;
    final clampedY = point.dy < rect.top
        ? rect.top
        : point.dy > rect.bottom
        ? rect.bottom
        : point.dy;
    final dx = point.dx - clampedX;
    final dy = point.dy - clampedY;
    return dx * dx + dy * dy;
  }

  ({String href, String? anchor}) _splitReaderHref(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return (href: '', anchor: null);
    }
    final parts = trimmed.split('#');
    final href = parts.first.trim();
    final anchor = parts.length > 1 ? parts.skip(1).join('#').trim() : '';
    return (href: href, anchor: anchor.isEmpty ? null : anchor);
  }

  List<_NavigationDisplayEntry> get _navigationDisplayEntries {
    final items = _orderedNavigationItems;
    if (items.isEmpty) return const [];
    final tree = buildLibraryNavigationTree(
      items,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    final childrenByParent = tree.childrenByParent;
    final roots = childrenByParent[null] ?? const [];
    if (roots.isEmpty) {
      return [
        for (var i = 0; i < items.length; i++)
          _NavigationDisplayEntry(item: items[i], depth: 0, displayIndex: i),
      ];
    }

    final result = <_NavigationDisplayEntry>[];
    final visited = <String>{};
    final visibleTargetIds = <String>{};

    void visit(LibraryCatalogNavigationItem item, int depth) {
      if (!visited.add(item.id)) return;
      final visibleItem = libraryReaderVisibleContentsNavigationItem(
        navItem: item,
        tree: tree,
        sections: _sections,
      );
      final shouldDisplay =
          visibleItem != null && !_isMeaninglessNumericNavigationLabel(item);
      if (shouldDisplay) {
        if (!visibleTargetIds.add(visibleItem.id)) {
          return;
        }
        result.add(
          _NavigationDisplayEntry(
            item: visibleItem,
            depth: depth,
            displayIndex: result.length,
          ),
        );
      }
      for (final child in childrenByParent[item.id] ?? const []) {
        visit(child, shouldDisplay ? depth + 1 : depth);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    for (final item in tree.items) {
      if (visited.contains(item.id)) continue;
      visit(item, 0);
    }

    return result;
  }

  bool _isMeaninglessNumericNavigationLabel(LibraryCatalogNavigationItem item) {
    final label = item.label.trim();
    if (label.isEmpty) return false;
    if (!RegExp(r'^\d+$').hasMatch(label)) return false;
    return !RegExp(r'^chapter\s+\d+$', caseSensitive: false).hasMatch(label);
  }

  void _zoomIn() {
    setState(() {
      _zoomScale = (_zoomScale + 0.1).clamp(0.85, 1.6).toDouble();
    });
    unawaited(AppSettingsService.instance.saveElibraryZoomScale(_zoomScale));
  }

  void _zoomOut() {
    setState(() {
      _zoomScale = (_zoomScale - 0.1).clamp(0.85, 1.6).toDouble();
    });
    unawaited(AppSettingsService.instance.saveElibraryZoomScale(_zoomScale));
  }

  Future<void> _toggleShowRefCodes() async {
    final nextValue = !_showRefCodes;
    setState(() {
      _showRefCodes = nextValue;
    });
    await LocalSettingsStore.instance.saveLibraryReaderShowRefCodes(nextValue);
    if (nextValue) {
      await _ensureParagraphReferenceCodesLoaded();
    }
  }

  Future<void> _ensureParagraphReferenceCodesLoaded() async {
    if (_refCodesLoaded ||
        widget.item.isPdf ||
        widget.item.isPeriodical ||
        _sections.isEmpty) {
      return;
    }
    final paragraphReferenceCodeLoadResult = await _loadParagraphReferenceCodes(
      sections: _sections,
      libraryItemId: widget.item.id,
      rootPath:
          (await LibraryRootService.instance.accessibleLibraryRootPath())
              ?.trim() ??
          (await LibraryRootService.instance.loadSelection()).path?.trim() ??
          '',
    );
    if (!mounted) return;
    setState(() {
      _refCodeByLocation = paragraphReferenceCodeLoadResult.byLocation;
      _paragraphReferenceCodesBySection =
          paragraphReferenceCodeLoadResult.bySection;
      _refCodesLoaded = true;
    });
  }

  Future<_ParagraphReferenceCodeLoadResult> _loadParagraphReferenceCodes({
    required List<LibraryBookSection> sections,
    required String libraryItemId,
    required String rootPath,
  }) async {
    final itemAbbreviation = libraryReaderBookAbbreviation(widget.item);
    final isManagedGreatControversy =
        itemAbbreviation == 'GC' || itemAbbreviation == 'GC88';
    if (isManagedGreatControversy) {
      final db = await UserDatabase.instance.database;
      await _service.ensureManagedEgwReferenceIndex(
        db: db,
        rootPath: rootPath,
        libraryItemId: libraryItemId,
        relativePath: widget.item.relativePath,
        bookTitle: widget.item.displayTitle,
        bookAbbrev: itemAbbreviation ?? 'GC',
        workKey: 'great_controversy',
        editionKey: itemAbbreviation ?? 'GC',
        editionYear: itemAbbreviation == 'GC88' ? 1888 : 1911,
        refresh: false,
      );
      final byLocation = await _service.loadManagedEgwReferenceCodesForItem(
        db: db,
        libraryItemId: libraryItemId,
      );
      return _ParagraphReferenceCodeLoadResult(
        bySection: _paragraphReferenceCodesBySectionFromLocation(byLocation),
        byLocation: byLocation,
      );
    }

    final result = <String, Map<int, String>>{};
    for (final section in sections) {
      final sectionKey = _sectionKey(section.entryName);
      final sectionCodes = await _loadSectionReferenceCodes(
        libraryItemId: libraryItemId,
        section: section,
        itemAbbreviation: itemAbbreviation,
        isDevotional: widget.item.isDevotional,
      );
      if (sectionCodes.isNotEmpty) {
        result[sectionKey] = sectionCodes;
      }
    }

    final generatedByLocation =
        widget.item.isDevotional ||
            itemAbbreviation == null ||
            itemAbbreviation.trim().isEmpty
        ? const <String, String>{}
        : _buildGeneratedParagraphReferenceCodes(
            sections: sections,
            libraryItemId: libraryItemId,
            itemAbbreviation: itemAbbreviation,
          );
    if (generatedByLocation.isNotEmpty) {
      final generatedBySection = _paragraphReferenceCodesBySectionFromLocation(
        generatedByLocation,
      );
      final mergedBySection = <String, Map<int, String>>{};
      for (final entry in result.entries) {
        mergedBySection[entry.key] = Map<int, String>.from(entry.value);
      }
      for (final entry in generatedBySection.entries) {
        mergedBySection
            .putIfAbsent(entry.key, () => <int, String>{})
            .addAll(entry.value);
      }
      return _ParagraphReferenceCodeLoadResult(
        bySection: mergedBySection,
        byLocation: generatedByLocation,
      );
    }

    return _ParagraphReferenceCodeLoadResult(
      bySection: result,
      byLocation: const <String, String>{},
    );
  }

  Future<Map<int, String>> _loadSectionReferenceCodes({
    required String libraryItemId,
    required LibraryBookSection section,
    required String? itemAbbreviation,
    required bool isDevotional,
  }) async {
    return loadReaderSectionReferenceCodes(
      libraryItemId: libraryItemId,
      section: section,
      itemAbbreviation: itemAbbreviation,
      isDevotional: isDevotional,
    );
  }

  String? _displayReferenceCodeForParagraph({
    required String? itemAbbreviation,
    required int? pageNumber,
    required int? pageParagraphIndex,
    required int paragraphIndex,
  }) {
    final abbreviation = cleanDisplayRefCode(itemAbbreviation);
    if (abbreviation == null || abbreviation.isEmpty) {
      return null;
    }
    if (abbreviation == 'GC' || abbreviation == 'GC88') {
      return null;
    }

    if (pageNumber != null &&
        pageParagraphIndex != null &&
        pageNumber > 0 &&
        pageParagraphIndex > 0) {
      final paragraphNumber = paragraphIndex - pageParagraphIndex + 1;
      if (paragraphNumber <= 0) return null;
      return cleanDisplayRefCode('$abbreviation $pageNumber.$paragraphNumber');
    }
    return null;
  }

  Map<String, String> _buildGeneratedParagraphReferenceCodes({
    required List<LibraryBookSection> sections,
    required String libraryItemId,
    required String? itemAbbreviation,
  }) {
    final abbreviation = cleanDisplayRefCode(itemAbbreviation);
    if (abbreviation == null || abbreviation.isEmpty) {
      return const <String, String>{};
    }

    final generatedByLocation = <String, String>{};
    final markerSamples = <String>[];
    final content02Samples = <String>[];
    final content02Href = _sectionKey('OEBPS/content02.xhtml');
    int? currentPageNumber;
    var paragraphNumberOnPage = 0;
    int? content02InitialPage;

    // Pre-scan to find the first pagebreak marker anywhere in the book.
    // Sections with no markers that precede the first marker (e.g. content00 in
    // EGW pamphlets) belong to the page before [N], so paragraphs there can
    // receive ref codes instead of being silently skipped.
    int? bookInitialPageNumber;
    for (final preScanSection in sections) {
      final firstMarker = _firstPageBreakMarkerOccurrence(
        preScanSection.blocks
            .where((b) => b.kind == 'paragraph')
            .toList(growable: false),
      );
      if (firstMarker != null) {
        bookInitialPageNumber = firstMarker.isInsideParagraph
            ? (firstMarker.pageNumber > 1 ? firstMarker.pageNumber - 1 : 1)
            : firstMarker.pageNumber;
        break;
      }
    }

    for (final section in sections) {
      final paragraphBlocks = section.blocks
          .where((block) => block.kind == 'paragraph')
          .toList(growable: false);
      if (paragraphBlocks.isEmpty) {
        continue;
      }

      final firstMarkerInSection = _firstPageBreakMarkerOccurrence(
        paragraphBlocks,
      );
      if (currentPageNumber == null && firstMarkerInSection != null) {
        currentPageNumber = firstMarkerInSection.isInsideParagraph
            ? (firstMarkerInSection.pageNumber > 1
                  ? firstMarkerInSection.pageNumber - 1
                  : 1)
            : firstMarkerInSection.pageNumber;
        if (_sectionKey(section.entryName) == content02Href) {
          content02InitialPage = currentPageNumber;
        }
      }

      var paragraphIndex = 0;
      for (final block in section.blocks) {
        if (block.kind != 'paragraph') {
          continue;
        }
        paragraphIndex += 1;
        final markers = _extractPageBreakMarkers(block.html);
        if (markers.isEmpty) {
          if (currentPageNumber == null) {
            if (bookInitialPageNumber == null) continue;
            currentPageNumber = bookInitialPageNumber;
          }
        } else {
          final firstMarkerBeforeText = markers.firstWhere(
            (marker) => !marker.isInsideParagraph,
            orElse: () => markers.first,
          );
          if (firstMarkerBeforeText.isInsideParagraph &&
              currentPageNumber == null) {
            currentPageNumber = firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
            if (_sectionKey(section.entryName) == content02Href) {
              content02InitialPage ??= currentPageNumber;
            }
          } else if (firstMarkerBeforeText.isInsideParagraph) {
            currentPageNumber ??= firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
          } else {
            currentPageNumber = firstMarkerBeforeText.pageNumber;
          }
        }

        final locationKey = _refCodeLocationKey(
          libraryItemId: libraryItemId,
          href: section.entryName,
          paragraphIndex: paragraphIndex,
        );
        paragraphNumberOnPage += 1;
        final generatedRefCode =
            '$abbreviation $currentPageNumber.$paragraphNumberOnPage';
        generatedByLocation[locationKey] = generatedRefCode;
        if (_sectionKey(section.entryName) == content02Href) {
          if (content02Samples.length < 5) {
            content02Samples.add(
              'paragraphIndex=$paragraphIndex ref=$generatedRefCode preview=${_paragraphPreview(block.text)}',
            );
          }
        }

        final preview = _paragraphPreview(block.text);
        if (markerSamples.length < 20) {
          final markerPreview = markers.isEmpty
              ? '(none)'
              : markers.first.preview;
          markerSamples.add(
            'href=${section.entryName} paragraphIndex=$paragraphIndex '
            'page=$currentPageNumber ref=$generatedRefCode '
            'markerPreview=$markerPreview preview=$preview',
          );
        }

        if (markers.isNotEmpty) {
          final lastMarker = markers.last;
          currentPageNumber = lastMarker.pageNumber;
          paragraphNumberOnPage = 0;
        }
      }
    }

    return generatedByLocation;
  }

  Map<String, Map<int, String>> _paragraphReferenceCodesBySectionFromLocation(
    Map<String, String> byLocation,
  ) {
    final result = <String, Map<int, String>>{};
    for (final entry in byLocation.entries) {
      final parts = entry.key.split('|');
      if (parts.length < 3) continue;
      final href = parts[1];
      final paragraphIndex = int.tryParse(parts[2]);
      if (paragraphIndex == null || paragraphIndex <= 0) continue;
      final sectionKey = _sectionKey(href);
      result.putIfAbsent(sectionKey, () => <int, String>{})[paragraphIndex] =
          entry.value;
    }
    return result;
  }

  _GeneratedPageBreakMarkerOccurrence? _firstPageBreakMarkerOccurrence(
    List<LibraryBookBlock> blocks,
  ) {
    for (final block in blocks) {
      final markers = _extractPageBreakMarkers(block.html);
      if (markers.isNotEmpty) {
        return markers.first;
      }
    }
    return null;
  }

  List<_GeneratedPageBreakMarkerOccurrence> _extractPageBreakMarkers(
    String html,
  ) {
    final markers = <_GeneratedPageBreakMarkerOccurrence>[];
    final spanPattern = RegExp(
      r'<span\b([^>]*)>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in spanPattern.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final lowerAttrs = attrs.toLowerCase();
      if (!lowerAttrs.contains('pagebreak')) {
        continue;
      }
      final titleMatch = RegExp(
        r'''title\s*=\s*["'](\d{1,4})["']''',
        caseSensitive: false,
      ).firstMatch(attrs);
      int? pageNumber;
      if (titleMatch != null) {
        pageNumber = int.tryParse(titleMatch.group(1)!);
      } else {
        final inner = (match.group(2) ?? '').trim();
        final innerMatch = RegExp(r'^\[(\d{1,4})\]$').firstMatch(inner);
        if (innerMatch != null) {
          pageNumber = int.tryParse(innerMatch.group(1)!);
        }
      }
      if (pageNumber == null) continue;
      final textBefore = _stripHtmlForRefCode(html.substring(0, match.start));
      final isInsideParagraph = textBefore.trim().isNotEmpty;
      final preview = _pageBreakPreview(match.group(0) ?? '');
      markers.add(
        _GeneratedPageBreakMarkerOccurrence(
          pageNumber: pageNumber,
          isInsideParagraph: isInsideParagraph,
          preview: preview,
        ),
      );
    }
    return markers;
  }

  String _paragraphPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  String _pageBreakPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  String _stripHtmlForRefCode(String value) {
    final stripped = value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped;
  }

  String _refCodeLocationKey({
    required String libraryItemId,
    required String href,
    required int paragraphIndex,
  }) {
    return '$libraryItemId|${_sectionKey(href)}|$paragraphIndex';
  }

  _PageMarker? _pageMarkerFromText(String? text) {
    final clean = text?.trim() ?? '';
    if (clean.isEmpty) return null;
    final match = RegExp(r'\[(\d{1,4})\]').firstMatch(clean);
    if (match == null) return null;
    final pageNumber = int.tryParse(match.group(1)!);
    if (pageNumber == null) return null;
    return _PageMarker(pageNumber);
  }

  String _sectionKey(String value) {
    return p.normalize(value).toLowerCase();
  }

  Future<void> _openContentsPopup() async {
    final entries = _navigationDisplayEntries;
    if (entries.isEmpty && _sections.isEmpty) return;

    final selected = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return LibraryFontScaleScope(
          scale: _fontScale,
          child: _ContentsPopupSheet(
            itemTitle: widget.item.displayTitle,
            itemSubtitle: '',
            entries: entries,
            sections: _sections,
            currentSectionEntryName: _currentSection?.entryName,
            currentSectionTitle: libraryReaderDisplaySectionTitle(
              _currentSection?.title ?? '',
            ),
            currentSectionSpineIndex: _currentSection?.spineIndex,
            selectedNavigationItemId: _selectedNavigationItem?.id,
            selectedNavigationIndex: _selectedNavigationIndex,
            selectedSectionIndex: _selectedIndex,
            isNightMode: _nightMode,
            isDevotionalNavigation: _isDevotionalNavigationBook,
            isPeriodical: widget.item.isPeriodical,
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    if (selected is LibraryCatalogNavigationItem) {
      _selectNavigationItem(selected);
    } else if (selected is int) {
      _selectSection(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNight = theme.brightness == Brightness.dark || _nightMode;
    final background = _readerBackgroundColor(theme, isNight);
    final summaryBackground = _readerSurfaceHighColor(theme, isNight);
    final cardBackground = _readerSurfaceColor(theme, isNight);
    final cardBorder = _readerBorderColor(theme, isNight);
    final textColor = _readerTextColor(theme, isNight);
    final subduedColor = _readerSubduedColor(theme, isNight);
    final item = widget.item;
    final currentSection = _sections.isEmpty
        ? null
        : _sections[_selectedIndex.clamp(0, _sections.length - 1)];
    // A heading-only structural node (e.g. Chapter 1) keeps its own heading
    // as section context but renders the first readable descendant's own
    // heading and body, following only explicit child links. The selected
    // TOC identity stays the structural node; only the displayed content
    // (ref codes, markups, tap/highlight targets) is sourced from the
    // readable descendant.
    final descendantChain =
        (currentSection != null && currentSection.blocks.isEmpty)
        ? _currentSectionReadableDescendantChain
        : null;
    final contentSection = descendantChain?.readableSection ?? currentSection;
    final headingSections = <LibraryBookSection>[];
    if (currentSection != null) {
      headingSections.add(currentSection);
    }
    if (descendantChain != null) {
      headingSections.addAll(descendantChain.headingSections);
      headingSections.add(descendantChain.readableSection);
    }
    final uniqueHeadingSections = <LibraryBookSection>[];
    final seenHeadingSectionKeys = <String>{};
    for (final section in headingSections) {
      final key = section.entryName.trim().toLowerCase();
      if (!seenHeadingSectionKeys.add(key)) continue;
      uniqueHeadingSections.add(section);
    }
    final sectionBlocks = contentSection?.blocks ?? const <LibraryBookBlock>[];
    final sectionReferenceCodes = contentSection == null
        ? const <int, String>{}
        : item.isDevotional
        ? const <int, String>{}
        : _paragraphReferenceCodesBySection[_sectionKey(
                contentSection.entryName,
              )] ??
              const <int, String>{};
    final showSectionTitle = _shouldShowSectionTitle(
      sectionBlocks,
      libraryReaderDisplaySectionTitle(currentSection?.title ?? ''),
    );
    final sectionMarkups = contentSection == null
        ? const <ElibraryMarkupRecord>[]
        : _elibraryMarkupsByHref[contentSection.entryName] ??
              const <ElibraryMarkupRecord>[];
    final sectionHasUserMarkup = sectionMarkups.isNotEmpty;
    final geometryScopeId = _geometryScopeId;

    final bodyFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale * _zoomScale;
    final titleFontSize =
        (theme.textTheme.headlineSmall?.fontSize ?? 24) *
        _fontScale *
        _zoomScale;
    final sectionBlockWidgets = <Widget>[];
    final selectionHighlightSpec = resolveHighlightRender(
      theme.colorScheme.primary,
      isNight,
      layerType: HighlightLayerType.temporarySelection,
    );
    if (sectionBlocks.isNotEmpty) {
      var paragraphIndex = 0;
      var devotionalFallbackParagraphCount = 0;
      for (var index = 0; index < sectionBlocks.length; index++) {
        final block = sectionBlocks[index];
        final blockIndex = index;
        final isParagraph = block.kind == 'paragraph';
        if (isParagraph) {
          paragraphIndex += 1;
        }

        final referenceCode = isParagraph
            ? (item.isDevotional
                  ? libraryReaderDevotionalFallbackRefCodeForBlock(
                      item: item,
                      sectionTitle: libraryReaderDisplaySectionTitle(
                        contentSection?.title ?? '',
                      ),
                      block: block,
                      fallbackParagraphCount: devotionalFallbackParagraphCount,
                    )
                  : item.isPeriodical
                  ? libraryReaderPeriodicalRefCode(
                      item: item,
                      sectionTitle: libraryReaderDisplaySectionTitle(
                        contentSection?.title ?? '',
                      ),
                      paragraphIndex: paragraphIndex,
                    )
                  : _refCodeByLocation[_refCodeLocationKey(
                          libraryItemId: item.id,
                          href: contentSection?.entryName ?? '',
                          paragraphIndex: paragraphIndex,
                        )] ??
                        sectionReferenceCodes[paragraphIndex] ??
                        block.referenceCode)
            : null;
        if (item.isDevotional && referenceCode != null) {
          devotionalFallbackParagraphCount += 1;
        }
        final blockKey = _keyForBlock(_blockTargetKey(block, blockIndex));
        final textKey = _textKeyForBlock(_blockTargetKey(block, blockIndex));
        sectionBlockWidgets.add(
          _SectionBlockView(
            key: blockKey,
            block: block,
            blockIndex: blockIndex,
            geometryRegistry: _geometryRegistry,
            geometryScopeId: geometryScopeId,
            geometryRevision: _enableTextRangeGeometry ? _geometryTick : 0,
            sectionTitle: libraryReaderDisplaySectionTitle(
              contentSection?.title ?? '',
            ),
            sectionEntryName: contentSection?.entryName ?? '',
            paragraphIndex: isParagraph ? paragraphIndex : null,
            textColor: textColor,
            subduedColor: subduedColor,
            bodyFontSize: bodyFontSize,
            searchQuery: widget.searchQuery,
            highlightTerms: widget.highlightTerms,
            topPadding: blockIndex == 0 ? 0 : (block.isHeading ? 18 : 6),
            bottomPadding: block.isHeading ? 12 : 14,
            isNightMode: isNight,
            showRefCodes: _showRefCodes,
            referenceCode: referenceCode,
            hasUserMarkup: sectionHasUserMarkup,
            selectionHighlightSpec: selectionHighlightSpec,
            rangeSelection: _rangeSelection,
            persistedHighlights: sectionMarkups,
            onBlockTap:
                _rangeSelection.hasCompletedRange &&
                    _rangeSelection.containsBlock(blockIndex)
                ? () => _showLibrarySelectionActionsMenu(
                    item: item,
                    section: contentSection,
                    sectionBlocks: sectionBlocks,
                  )
                : null,
            onWordLongPress: (tokenIndex) {
              _handleLibraryWordLongPress(
                blockIndex: blockIndex,
                tokenIndex: tokenIndex,
              );
            },
            onWordLongPressMove: (tokenIndex) {
              _handleLibraryWordLongPressMove(
                blockIndex: blockIndex,
                tokenIndex: tokenIndex,
              );
            },
            onWordLongPressMoveDetails: (details) {
              final hit = _resolveLibraryDragTokenHit(
                globalPosition: details.globalPosition,
                sectionBlocks: sectionBlocks,
                preferredBlockIndex: blockIndex,
                bodyFontSize: bodyFontSize,
                textColor: textColor,
                isNightMode: isNight,
                highlightQuery: widget.searchQuery,
                highlightTerms: widget.highlightTerms,
                textDirection: Directionality.of(context),
              );
              if (hit == null) return;
              _handleLibraryWordLongPressMove(
                blockIndex: hit.blockIndex,
                tokenIndex: hit.tokenIndex,
              );
            },
            textKey: textKey,
            onWordTap: (tokenIndex) {
              if (_rangeSelection.hasCompletedRange &&
                  _rangeSelection.containsTokenPosition(
                    blockIndex,
                    tokenIndex,
                  )) {
                _showLibrarySelectionActionsMenu(
                  item: item,
                  section: contentSection,
                  sectionBlocks: sectionBlocks,
                );
                return;
              }
              if (_rangeSelection.hasCompletedRange) {
                _clearLibraryRangeSelection();
              }
            },
            diagnosticLoggingEnabled: false,
          ),
        );
      }
    }

    return LibraryFontScaleScope(
      scale: _fontScale,
      child: Scaffold(
        backgroundColor: background,
        body: PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) {
              _saveCurrentLocation();
            }
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (MediaQuery.sizeOf(context).width < 900) ...[
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _backToBible,
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            'Back to Bible',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'eLibrary',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryScaledTextStyle(
                              theme.textTheme.headlineMedium,
                              libraryTitleScale(_fontScale),
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search),
                          label: Text(
                            'Search',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        if (_hasSearchSession)
                          _SearchHitNavigator(
                            label: widget.searchSession!.counterLabel,
                            canGoPrevious: widget.searchSession!.hasPrevious,
                            canGoNext: widget.searchSession!.hasNext,
                            onPrevious: () => _navigateSearchHit(-1),
                            onNext: () => _navigateSearchHit(1),
                            textColor: textColor,
                            backgroundColor: cardBackground,
                            borderColor: cardBorder,
                          ),
                        FilledButton.tonalIcon(
                          onPressed: _closeToLibrary,
                          icon: const Icon(Icons.library_books_outlined),
                          label: Text(
                            'Library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        _buildReaderActionsMenu(
                          theme: theme,
                          textColor: textColor,
                          cardBackground: cardBackground,
                          cardBorder: cardBorder,
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _backToBible,
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                            'Back to Bible',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'eLibrary',
                          style: libraryScaledTextStyle(
                            theme.textTheme.headlineMedium,
                            libraryTitleScale(_fontScale),
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        FilledButton.tonalIcon(
                          onPressed: _openSearch,
                          icon: const Icon(Icons.search),
                          label: Text(
                            'Search',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        if (_hasSearchSession) ...[
                          const SizedBox(width: 10),
                          _SearchHitNavigator(
                            label: widget.searchSession!.counterLabel,
                            canGoPrevious: widget.searchSession!.hasPrevious,
                            canGoNext: widget.searchSession!.hasNext,
                            onPrevious: () => _navigateSearchHit(-1),
                            onNext: () => _navigateSearchHit(1),
                            textColor: textColor,
                            backgroundColor: cardBackground,
                            borderColor: cardBorder,
                          ),
                        ],
                        const SizedBox(width: 12),
                        FilledButton.tonalIcon(
                          onPressed: _closeToLibrary,
                          icon: const Icon(Icons.library_books_outlined),
                          label: Text(
                            'Library',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryControlTextStyle(
                              context,
                              theme.textTheme.labelLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            foregroundColor: textColor,
                            backgroundColor: cardBackground,
                            side: BorderSide(color: cardBorder),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildReaderActionsMenu(
                          theme: theme,
                          textColor: textColor,
                          cardBackground: cardBackground,
                          cardBorder: cardBorder,
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Material(
                    color: summaryBackground,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.displayTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: libraryTitleTextStyle(
                              context,
                              theme.textTheme.titleLarge,
                              fontWeight: FontWeight.w800,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentSubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: libraryBodyTextStyle(
                              context,
                              theme.textTheme.bodyMedium,
                              color: subduedColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Material(
                      color: cardBackground,
                      borderRadius: BorderRadius.circular(26),
                      borderOnForeground: true,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _error != null
                              ? Center(
                                  child: Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: libraryBodyTextStyle(
                                      context,
                                      theme.textTheme.bodyLarge,
                                      color: textColor,
                                    ),
                                  ),
                                )
                              : _sections.isEmpty
                              ? Center(
                                  child: Text(
                                    item.isPdf
                                        ? 'PDF reading is not wired yet.'
                                        : 'This book does not expose readable sections yet.',
                                    textAlign: TextAlign.center,
                                    style: libraryBodyTextStyle(
                                      context,
                                      theme.textTheme.bodyLarge,
                                      color: textColor,
                                    ),
                                  ),
                                )
                              : GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _rangeSelection.hasCompletedRange
                                      ? _clearLibraryRangeSelection
                                      : null,
                                  child: SingleChildScrollView(
                                    controller: _bodyScrollController,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (showSectionTitle) ...[
                                          Text(
                                            () {
                                              final sectionTitle =
                                                  libraryReaderDisplaySectionTitle(
                                                    currentSection?.title ?? '',
                                                  );
                                              return sectionTitle.isNotEmpty
                                                  ? sectionTitle
                                                  : item.displayTitle;
                                            }(),
                                            style: libraryScaledTextStyle(
                                              theme.textTheme.headlineSmall,
                                              _fontScale * _zoomScale,
                                              fontWeight: FontWeight.w800,
                                              color: textColor,
                                              fontSize: titleFontSize,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                        if (descendantChain != null) ...[
                                          for (final headingSection
                                              in uniqueHeadingSections
                                                  .skip(
                                                    currentSection == null
                                                        ? 0
                                                        : 1,
                                                  )
                                                  .take(
                                                    uniqueHeadingSections
                                                        .length,
                                                  )) ...[
                                            if (libraryReaderDisplaySectionTitle(
                                              headingSection.title,
                                            ).isNotEmpty) ...[
                                              Text(
                                                libraryReaderDisplaySectionTitle(
                                                  headingSection.title,
                                                ),
                                                style: libraryScaledTextStyle(
                                                  theme.textTheme.headlineSmall,
                                                  _fontScale * _zoomScale,
                                                  fontWeight: FontWeight.w800,
                                                  color: textColor,
                                                  fontSize: titleFontSize,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                          ],
                                          if (libraryReaderDisplaySectionTitle(
                                                descendantChain
                                                    .readableSection
                                                    .title,
                                              ).isNotEmpty &&
                                              (uniqueHeadingSections.isEmpty ||
                                                  uniqueHeadingSections
                                                          .last
                                                          .entryName
                                                          .trim()
                                                          .toLowerCase() !=
                                                      descendantChain
                                                          .readableSection
                                                          .entryName
                                                          .trim()
                                                          .toLowerCase())) ...[
                                            Text(
                                              libraryReaderDisplaySectionTitle(
                                                descendantChain
                                                    .readableSection
                                                    .title,
                                              ),
                                              style: libraryScaledTextStyle(
                                                theme.textTheme.headlineSmall,
                                                _fontScale * _zoomScale,
                                                fontWeight: FontWeight.w800,
                                                color: textColor,
                                                fontSize: titleFontSize,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],
                                        ],
                                        if (sectionBlocks.isEmpty)
                                          Text(
                                            'No readable text in this section.',
                                            style: libraryScaledTextStyle(
                                              theme.textTheme.bodyLarge,
                                              _fontScale * _zoomScale,
                                              color: textColor,
                                              fontSize: bodyFontSize,
                                              height: 1.6,
                                            ),
                                          )
                                        else
                                          ...sectionBlockWidgets,
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _readerSurfaceHighColor(theme, isNight),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cardBorder),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolbarPillButton(
                      isNightMode: isNight,
                      icon: Icons.list_alt_outlined,
                      label: 'Contents',
                      onPressed: _sections.isEmpty ? null : _openContentsPopup,
                    ),
                    const SizedBox(width: 12),
                    _ToolbarPillButton(
                      isNightMode: isNight,
                      icon: Icons.library_books_outlined,
                      label: 'Library',
                      onPressed: _closeToLibrary,
                    ),
                    const SizedBox(width: 12),
                    _ToolbarPillButton(
                      isNightMode: isNight,
                      icon: isNight
                          ? Icons.wb_sunny_outlined
                          : Icons.nightlight_round,
                      label: isNight ? 'Day' : 'Night',
                      onPressed: () {
                        final next = isNight
                            ? AppThemeMode.sepia
                            : AppThemeMode.night;
                        setState(() => _nightMode = next == AppThemeMode.night);
                        final onThemeChanged = widget.onThemeChanged;
                        if (onThemeChanged != null) {
                          onThemeChanged(next);
                        } else {
                          ThemePreferences.instance.saveThemeMode(next);
                        }
                      },
                    ),
                    const SizedBox(width: 12),
                    _ToolbarPillButton(
                      isNightMode: isNight,
                      icon: _showRefCodes
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      label: _showRefCodes
                          ? 'Hide Ref Codes'
                          : 'Show Ref Codes',
                      onPressed: _sections.isEmpty ? null : _toggleShowRefCodes,
                    ),
                    const SizedBox(width: 12),
                    _ZoomCluster(
                      isNightMode: isNight,
                      valueLabel: '${(_zoomScale * 100).round()}%',
                      onZoomOut: _zoomOut,
                      onZoomIn: _zoomIn,
                    ),
                    const SizedBox(width: 12),
                    _NavCluster(
                      isNightMode: isNight,
                      canGoFirst: _sections.isNotEmpty,
                      canGoPrevious: _sections.isNotEmpty,
                      canGoNext: _sections.isNotEmpty,
                      canGoLast: _sections.isNotEmpty,
                      onGoFirst: () => _scrollToAdjacentHeading(forward: false),
                      onGoPrevious: _scrollPageUp,
                      onGoNext: _scrollPageDown,
                      onGoLast: () => _scrollToAdjacentHeading(forward: true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageMarker {
  const _PageMarker(this.pageNumber);

  final int pageNumber;
}

class _ParagraphReferenceCodeLoadResult {
  const _ParagraphReferenceCodeLoadResult({
    required this.bySection,
    required this.byLocation,
  });

  final Map<String, Map<int, String>> bySection;
  final Map<String, String> byLocation;
}

class _GeneratedPageBreakMarkerOccurrence {
  const _GeneratedPageBreakMarkerOccurrence({
    required this.pageNumber,
    required this.isInsideParagraph,
    required this.preview,
  });

  final int pageNumber;
  final bool isInsideParagraph;
  final String preview;
}

class _SearchHitNavigator extends StatelessWidget {
  const _SearchHitNavigator({
    required this.label,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = libraryControlTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontWeight: FontWeight.w800,
      color: textColor,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Previous hit',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label, style: labelStyle),
            ),
            IconButton(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Next hit',
            ),
          ],
        ),
      ),
    );
  }
}
