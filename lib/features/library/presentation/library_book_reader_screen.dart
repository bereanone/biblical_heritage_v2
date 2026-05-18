// ignore_for_file: unused_element, dead_code

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import '../data/library_citation_display_helper.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../../reader/presentation/reader_search_mode_picker.dart';
import '../../reader/presentation/viewer_search_dialog.dart';
import '../../search/search_highlight_helper.dart';
import '../data/library_catalog_service.dart';
import 'library_navigation_tree.dart';

part 'epub_inline_span_builder.dart';
part 'epub_body_block_parser.dart';
part 'library_contents_popup.dart';
part 'library_reader_bottom_bar.dart';
part 'library_book_reader_screen_helpers.dart';

const bool _libraryRefCodeDiagnosticsEnabled = false;

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
  });

  final LibraryCatalogItem item;
  final String? initialHref;
  final String? initialAnchorId;
  final int? initialSpineIndex;
  final int? initialParagraphIndex;
  final String? searchQuery;
  final List<String> highlightTerms;

  @override
  State<LibraryBookReaderScreen> createState() =>
      _LibraryBookReaderScreenState();
}

class _LibraryBookReaderScreenState extends State<LibraryBookReaderScreen> {
  final _service = CommentaryResearchLibraryService.instance;
  final ScrollController _bodyScrollController = ScrollController();
  final Map<String, GlobalKey> _bodyBlockKeys = <String, GlobalKey>{};
  String? _lastSearchTerm;
  bool _loading = true;
  bool _nightMode = false;
  bool _showRefCodes = false;
  bool _refCodesLoaded = false;
  double _fontScale = 1.0;
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

  @override
  void initState() {
    super.initState();
    final initialSearchTerm = widget.searchQuery?.trim() ?? '';
    _lastSearchTerm = initialSearchTerm.isNotEmpty ? initialSearchTerm : null;
    _load();
  }

  @override
  void dispose() {
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      final sections = widget.item.isPdf
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
      final devotionalMode =
          widget.item.isDevotional || isDevotionalNavigation(navigationItems);
      final initialIndex = widget.item.isPdf
          ? 0
          : _initialSectionIndex(
              sections: sections,
              navigationItems: navigationItems,
              devotionalMode: devotionalMode,
            );
      final initialNavigationIndex = widget.item.isPdf
          ? 0
          : _navigationIndexForSectionIndex(initialIndex) ?? 0;
      final paragraphReferenceCodeLoadResult =
          !widget.item.isPdf && savedShowRefCodes
          ? await _loadParagraphReferenceCodes(
              sections: sections,
              libraryItemId: widget.item.id,
              rootPath: rootPath,
            )
          : const _ParagraphReferenceCodeLoadResult(
              bySection: <String, Map<int, String>>{},
              byLocation: <String, String>{},
            );
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _navigationItems = navigationItems;
        _selectedIndex = initialIndex;
        _selectedNavigationIndex = initialNavigationIndex;
        _showRefCodes = savedShowRefCodes;
        _refCodesLoaded = savedShowRefCodes && !widget.item.isPdf;
        _refCodeByLocation = paragraphReferenceCodeLoadResult.byLocation;
        _paragraphReferenceCodesBySection =
            paragraphReferenceCodeLoadResult.bySection;
        _loading = false;
      });
      final targetKey = _initialScrollTargetKey();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTarget(targetKey);
      });
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
    );
    if (!mounted || selection == null) return;
    final selectedSearchTerm = selection.lastSearchTerm.trim();
    if (selectedSearchTerm.isNotEmpty) {
      _lastSearchTerm = selectedSearchTerm;
    }
  }

  void _close() {
    final navigator = Navigator.of(context);
    _saveCurrentLocation().whenComplete(() {
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        navigator.maybePop();
      }
    });
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
    final now = DateTime.now().toUtc().toIso8601String();
    final db = await UserDatabase.instance.database;
    await db.update(
      'library_items',
      {
        'last_opened': now,
        'epub_href': savedHref != null && savedHref.isNotEmpty
            ? savedHref
            : currentSection.entryName,
        'epub_cfi': null,
        'anchor_id': savedAnchorId != null && savedAnchorId.isNotEmpty
            ? savedAnchorId
            : null,
        'spine_index': currentSection.spineIndex,
        'paragraph_index': savedParagraphIndex ?? 1,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [widget.item.id],
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

  bool get _isDevotionalNavigationBook {
    return widget.item.isDevotional || isDevotionalNavigation(_navigationItems);
  }

  String get _currentSubtitle {
    final sectionTitle = _currentSection?.title.trim() ?? '';
    if (sectionTitle.isNotEmpty) {
      return sectionTitle;
    }

    final collectionName = widget.item.collectionName?.trim() ?? '';
    if (collectionName.isNotEmpty && collectionName.toLowerCase() != 'user') {
      return collectionName;
    }

    return '';
  }

  int _initialSectionIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required bool devotionalMode,
  }) {
    if (sections.isEmpty) return 0;

    final initialHref = _splitReaderHref(widget.initialHref).href;
    if (initialHref.isNotEmpty) {
      final initialIndex = _readableSectionIndexForHref(sections, initialHref);
      if (initialIndex != null) return initialIndex;
    }

    final initialSpineIndex = widget.initialSpineIndex;
    if (initialSpineIndex != null && initialSpineIndex > 0) {
      final initialIndex = _readableSectionIndexForSpineIndex(
        sections: sections,
        navigationItems: navigationItems,
        spineIndex: initialSpineIndex,
      );
      if (initialIndex != null) return initialIndex;
    }

    final savedHref = _splitReaderHref(widget.item.epubHref).href;
    if (savedHref.isNotEmpty) {
      final savedIndex = _readableSectionIndexForHref(sections, savedHref);
      if (savedIndex != null) return savedIndex;
    }

    if (devotionalMode) {
      final devotionalInitialHref = _devotionalInitialNavigationHref(
        navigationItems,
      );
      if (devotionalInitialHref != null) {
        final devotionalIndex = _sectionIndexForHref(
          sections,
          devotionalInitialHref,
        );
        if (devotionalIndex != null) return devotionalIndex;
      }
    }

    final firstRealContentHref = _firstRealContentNavigationHref(
      navigationItems,
    );
    if (firstRealContentHref != null) {
      final firstRealContentIndex = _sectionIndexForHref(
        sections,
        firstRealContentHref,
      );
      if (firstRealContentIndex != null &&
          _isRealContentSection(sections[firstRealContentIndex])) {
        return firstRealContentIndex;
      }
    }

    final firstContentIndex = _firstRealContentSectionIndex(sections);
    if (firstContentIndex != null) return firstContentIndex;

    final savedParagraph = widget.item.paragraphIndex;
    if (savedParagraph != null &&
        widget.item.spineIndex != null &&
        widget.item.spineIndex! > 0) {
      final navIndex = _navigationIndexForSavedState(
        sections: sections,
        navigationItems: navigationItems,
        spineIndex: widget.item.spineIndex!,
      );
      if (navIndex != null && _isRealContentSection(sections[navIndex])) {
        return navIndex;
      }
    }

    return 0;
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
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_isReaderChapterOneLabel(section.title) ||
          _isReaderChapterOneLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        return index;
      }
    }

    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_isReaderMetadataHelpLabel(section.title) ||
          _isReaderMetadataHelpLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        continue;
      }
      return index;
    }
    return null;
  }

  bool _isRealContentSection(LibraryBookSection section) {
    final entryLabel = p.basenameWithoutExtension(section.entryName);
    return !_isReaderMetadataHelpLabel(section.title) &&
        !_isReaderMetadataHelpLabel(entryLabel);
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
      final index = item.spineIndex! - 1;
      if (index >= 0 && index < _sections.length) return index;
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
      final index = item.spineIndex! - 1;
      if (index >= 0 && index < sections.length) return index;
    }

    return null;
  }

  String? _firstRealContentNavigationHref(
    List<LibraryCatalogNavigationItem> navigationItems,
  ) {
    if (navigationItems.isEmpty) return null;

    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (item.isBodyStart ||
          (item.contentKind?.trim().toLowerCase() == 'body' &&
              !item.isFrontMatter)) {
        return href;
      }
      if (_isReaderMetadataHelpLabel(item.label) ||
          _isReaderMetadataHelpLabel(p.basenameWithoutExtension(href)) ||
          item.isFrontMatter) {
        continue;
      }
      return href;
    }

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
    final sectionIndex = _sectionIndexForNavigationItem(navItem);
    final targetSection =
        sectionIndex != null &&
            sectionIndex >= 0 &&
            sectionIndex < _sections.length
        ? _sections[sectionIndex]
        : _currentSection;
    final targetKey =
        _navigationTargetKey(navItem) ??
        _fallbackTargetKeyForNavigationItem(navItem, section: targetSection);
    setState(() {
      if (navIndex >= 0) {
        _selectedNavigationIndex = navIndex;
      }
      if (sectionIndex != null) {
        _selectedIndex = sectionIndex;
      }
      _pendingBodyScrollTargetKey = targetKey;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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

    final targets = _headingTargetsForCurrentSection();
    if (targets.isEmpty) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = forward ? _selectedIndex + 1 : _selectedIndex - 1;
      final currentSectionTitle =
          _currentSection?.title ?? widget.item.displayTitle;
      if (fallbackIndex < 0 || fallbackIndex >= _sections.length) {
        debugPrint(
          '[LibraryBookReader] No subsection headings found in "$currentSectionTitle"; '
          'no ${forward ? 'next' : 'previous'} chapter fallback is available.',
        );
        return;
      }
      debugPrint(
        '[LibraryBookReader] No subsection headings found in "$currentSectionTitle"; '
        'falling back to ${forward ? 'next' : 'previous'} chapter.',
      );
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
      final currentSectionTitle =
          _currentSection?.title ?? widget.item.displayTitle;
      if (fallbackIndex < 0 || fallbackIndex >= _sections.length) {
        debugPrint(
          '[LibraryBookReader] No subsection headings found in "$currentSectionTitle"; '
          'no ${forward ? 'next' : 'previous'} chapter fallback is available.',
        );
        return;
      }
      debugPrint(
        '[LibraryBookReader] No subsection headings found in "$currentSectionTitle"; '
        'falling back to ${forward ? 'next' : 'previous'} chapter.',
      );
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

    final savedTargetKey = _savedLocationTargetKey();
    if (savedTargetKey != null) return savedTargetKey;

    final selectedNavigationItem = _selectedNavigationItem;
    if (selectedNavigationItem != null) {
      final targetKey = _navigationTargetKey(selectedNavigationItem);
      if (targetKey != null) return targetKey;
      final fallback = _fallbackTargetKeyForNavigationItem(
        selectedNavigationItem,
        section: _currentSection,
      );
      if (fallback != null) return fallback;
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
      final blockLabel = _normalizeReaderLabel(block.text);
      if (normalizedNavLabel.isNotEmpty && blockLabel == normalizedNavLabel) {
        return _blockTargetKey(block, index);
      }
      if (normalizedRawLabel.isNotEmpty && blockLabel == normalizedRawLabel) {
        return _blockTargetKey(block, index);
      }
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

  void _scrollToTarget(String? targetKey) {
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

  String _normalizeBlockKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
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

    void visit(LibraryCatalogNavigationItem item, int depth) {
      if (!visited.add(item.id)) return;
      final shouldDisplay = !_isMeaninglessNumericNavigationLabel(item);
      if (shouldDisplay) {
        result.add(
          _NavigationDisplayEntry(
            item: item,
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
      _fontScale = (_fontScale + 0.1).clamp(0.85, 1.6).toDouble();
    });
  }

  void _zoomOut() {
    setState(() {
      _fontScale = (_fontScale - 0.1).clamp(0.85, 1.6).toDouble();
    });
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
    if (_refCodesLoaded || widget.item.isPdf || _sections.isEmpty) {
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
      if (_libraryRefCodeDiagnosticsEnabled) {
        debugPrint(
          '[LibraryBookReader] ref index load '
          'showRefCodes=$_showRefCodes '
          'itemTitle=${widget.item.displayTitle} '
          'itemId=$libraryItemId '
          'bookAbbrev=${itemAbbreviation ?? '(none)'} '
          'resolved=${byLocation.length} '
          'source=elibrary_ref_index',
        );
      }
      return _ParagraphReferenceCodeLoadResult(
        bySection: _paragraphReferenceCodesBySectionFromLocation(byLocation),
        byLocation: byLocation,
      );
    }

    final db = await UserDatabase.instance.database;
    final result = <String, Map<int, String>>{};
    for (final section in sections) {
      final sectionKey = _sectionKey(section.entryName);
      final sectionCodes = await _loadSectionReferenceCodes(
        db: db,
        libraryItemId: libraryItemId,
        section: section,
        itemAbbreviation: itemAbbreviation,
        sectionTitle: section.title,
      );
      if (sectionCodes.isNotEmpty) {
        result[sectionKey] = sectionCodes;
      }
      if (_libraryRefCodeDiagnosticsEnabled) {
        debugPrint(
          '[LibraryBookReader] ref code scan '
          'showRefCodes=$_showRefCodes '
          'itemTitle=${widget.item.displayTitle} '
          'itemId=$libraryItemId '
          'bookAbbrev=${itemAbbreviation ?? '(none)'} '
          'section=${section.title.isEmpty ? section.entryName : section.title} '
          'entryName=${section.entryName} '
          'resolved=${sectionCodes.length} '
          'fields=paragraph_index,anchor,full_paragraph,spine_index,epub_href,'
          'anchor_id,original_reference_text',
        );
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
      if (_libraryRefCodeDiagnosticsEnabled) {
        debugPrint(
          '[LibraryBookReader] generated ref codes '
          'showRefCodes=$_showRefCodes '
          'itemTitle=${widget.item.displayTitle} '
          'itemId=$libraryItemId '
          'bookAbbrev=${itemAbbreviation ?? '(none)'} '
          'resolved=${generatedByLocation.length} '
          'source=epub_raw_html',
        );
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
    required Database db,
    required String libraryItemId,
    required LibraryBookSection section,
    required String? itemAbbreviation,
    required String sectionTitle,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT paragraph_index, anchor, full_paragraph, epub_href, anchor_id,
             spine_index, original_reference_text
      FROM library_links
      WHERE library_item_id = ?
        AND deleted_at IS NULL
        AND LOWER(REPLACE(REPLACE(COALESCE(epub_href, ''), '\\', '/'), './', '')) = ?
      ORDER BY paragraph_index ASC
      ''',
      [libraryItemId, _sectionKey(section.entryName)],
    );

    final resolved = <int, String>{};
    if (widget.item.isDevotional) {
      return const <int, String>{};
    }

    int? currentPageNumber;
    int? pageParagraphIndex;
    var markerCount = 0;

    for (final row in rows) {
      final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
      if (paragraphIndex == null || paragraphIndex <= 0) continue;

      final marker =
          _pageMarkerFromText(row['anchor']?.toString()) ??
          _pageMarkerFromText(row['full_paragraph']?.toString());
      if (marker != null) {
        currentPageNumber = marker.pageNumber;
        pageParagraphIndex = paragraphIndex;
        markerCount += 1;
      }

      final referenceCode = _displayReferenceCodeForParagraph(
        itemAbbreviation: itemAbbreviation,
        pageNumber: currentPageNumber,
        pageParagraphIndex: pageParagraphIndex,
        paragraphIndex: paragraphIndex,
      );
      if (referenceCode != null) {
        resolved[paragraphIndex] = referenceCode;
      }

      if (_libraryRefCodeDiagnosticsEnabled) {
        final rawStableRef = [
          row['epub_href']?.toString().trim() ?? '',
          row['anchor_id']?.toString().trim() ?? '',
        ].where((value) => value.isNotEmpty).join('#');
        debugPrint(
          '[LibraryBookReader] ref code row '
          'section=${section.title.isEmpty ? section.entryName : section.title} '
          'showRefCodes=$_showRefCodes '
          'paragraphIndex=$paragraphIndex '
          'href=${row['epub_href']?.toString() ?? '(none)'} '
          'anchorId=${row['anchor_id']?.toString() ?? '(none)'} '
          'spineIndex=${row['spine_index']?.toString() ?? '(none)'} '
          'sourceRef=${row['original_reference_text']?.toString() ?? '(none)'} '
          'rawStableRef=${rawStableRef.isEmpty ? '(none)' : rawStableRef} '
          'officialParagraphRefMetadata=${row['original_reference_text']?.toString().startsWith('GC ') == true || row['original_reference_text']?.toString().startsWith('DA ') == true || row['original_reference_text']?.toString().startsWith('RC ') == true || row['original_reference_text']?.toString().startsWith('HB ') == true || row['original_reference_text']?.toString().startsWith('TMK ') == true ? 'present' : 'missing'} '
          'finalCleanRefCode=${referenceCode ?? '(null)'}',
        );
      }
    }

    if (_libraryRefCodeDiagnosticsEnabled) {
      debugPrint(
        '[LibraryBookReader] ref code summary '
        'section=${section.title.isEmpty ? section.entryName : section.title} '
        'paragraphs=${resolved.length} '
        'markers=$markerCount '
        'bookAbbrev=${itemAbbreviation ?? '(none)'}',
      );
    }

    return resolved;
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
    final isGreatControversy = abbreviation == 'GC' || abbreviation == 'GC88';
    int? currentPageNumber;
    var paragraphNumberOnPage = 0;
    var generatedCount = 0;
    var content02Count = 0;
    var insideParagraphMarkerCount = 0;
    int? content02InitialPage;

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
            continue;
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
        generatedCount += 1;
        if (_sectionKey(section.entryName) == content02Href) {
          content02Count += 1;
          if (content02Samples.length < 5) {
            content02Samples.add(
              'paragraphIndex=$paragraphIndex ref=$generatedRefCode preview=${_paragraphPreview(block.text)}',
            );
          }
        }

        final preview = _paragraphPreview(block.text);
        if (_libraryRefCodeDiagnosticsEnabled && markerSamples.length < 20) {
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
          for (final marker in markers) {
            if (marker.isInsideParagraph) {
              insideParagraphMarkerCount += 1;
            }
          }
          final lastMarker = markers.last;
          currentPageNumber = lastMarker.pageNumber;
          paragraphNumberOnPage = 0;
        }
      }
    }

    if (_libraryRefCodeDiagnosticsEnabled && isGreatControversy) {
      debugPrint(
        '[LibraryBookReader] generated ref code summary '
        'itemTitle=${widget.item.displayTitle} '
        'itemId=$libraryItemId '
        'bookAbbrev=$abbreviation '
        'totalGeneratedRefs=$generatedCount '
        'content02GeneratedRefs=$content02Count '
        'content02InitialPage=${content02InitialPage?.toString() ?? '(none)'} '
        'pagebreakInsideParagraphCount=$insideParagraphMarkerCount',
      );
      for (var i = 0; i < markerSamples.length; i++) {
        debugPrint(
          '[LibraryBookReader] generated pagebreak marker ${i + 1} '
          '${markerSamples[i]}',
        );
      }
      for (var i = 0; i < content02Samples.length; i++) {
        debugPrint(
          '[LibraryBookReader] content02 generated ref ${i + 1} '
          '${content02Samples[i]}',
        );
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
        return _ContentsPopupSheet(
          itemTitle: widget.item.displayTitle,
          entries: entries,
          sections: _sections,
          selectedNavigationItemId: _selectedNavigationItem?.id,
          selectedNavigationIndex: _selectedNavigationIndex,
          selectedSectionIndex: _selectedIndex,
          isNightMode: _nightMode,
          isDevotionalNavigation: _isDevotionalNavigationBook,
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
    final sectionBlocks = currentSection?.blocks ?? const <LibraryBookBlock>[];
    final sectionReferenceCodes = currentSection == null
        ? const <int, String>{}
        : item.isDevotional
        ? const <int, String>{}
        : _paragraphReferenceCodesBySection[_sectionKey(
                currentSection.entryName,
              )] ??
              const <int, String>{};
    final shouldLogRefCodeDiagnostics =
        _libraryRefCodeDiagnosticsEnabled &&
        _showRefCodes &&
        widget.item.displayTitle.toLowerCase().contains('great controversy');
    final showSectionTitle = _shouldShowSectionTitle(
      sectionBlocks,
      currentSection?.title ?? '',
    );

    final bodyFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale;
    final titleFontSize =
        (theme.textTheme.headlineSmall?.fontSize ?? 24) * _fontScale;
    final sectionBlockWidgets = <Widget>[];
    if (sectionBlocks.isNotEmpty) {
      var paragraphIndex = 0;
      var devotionalFallbackParagraphCount = 0;
      for (var index = 0; index < sectionBlocks.length; index++) {
        final block = sectionBlocks[index];
        final isParagraph = block.kind == 'paragraph';
        if (isParagraph) {
          paragraphIndex += 1;
        }

        final referenceCode = isParagraph
            ? (item.isDevotional
                  ? libraryReaderDevotionalFallbackRefCodeForBlock(
                      item: item,
                      sectionTitle: currentSection?.title ?? '',
                      block: block,
                      fallbackParagraphCount: devotionalFallbackParagraphCount,
                    )
                  : item.isPeriodical
                  ? libraryReaderPeriodicalRefCode(
                      item: item,
                      sectionTitle: currentSection?.title ?? '',
                      paragraphIndex: paragraphIndex,
                    )
                  : _refCodeByLocation[_refCodeLocationKey(
                          libraryItemId: item.id,
                          href: currentSection?.entryName ?? '',
                          paragraphIndex: paragraphIndex,
                        )] ??
                        sectionReferenceCodes[paragraphIndex])
            : null;
        if (item.isDevotional && referenceCode != null) {
          devotionalFallbackParagraphCount += 1;
        }
        sectionBlockWidgets.add(
          _SectionBlockView(
            key: _keyForBlock(_blockTargetKey(block, index)),
            block: block,
            sectionTitle: currentSection?.title ?? '',
            sectionEntryName: currentSection?.entryName ?? '',
            paragraphIndex: isParagraph ? paragraphIndex : null,
            textColor: textColor,
            subduedColor: subduedColor,
            bodyFontSize: bodyFontSize,
            searchQuery: widget.searchQuery,
            highlightTerms: widget.highlightTerms,
            topPadding: index == 0 ? 0 : (block.isHeading ? 18 : 6),
            bottomPadding: block.isHeading ? 12 : 14,
            isNightMode: isNight,
            showRefCodes: _showRefCodes,
            referenceCode: referenceCode,
            diagnosticLoggingEnabled: shouldLogRefCodeDiagnostics,
          ),
        );
      }
    }

    return Scaffold(
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
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _close,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Bible'),
                      style: FilledButton.styleFrom(
                        foregroundColor: textColor,
                        backgroundColor: cardBackground,
                        side: BorderSide(color: cardBorder),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'eLibrary',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: _openSearch,
                      icon: const Icon(Icons.search),
                      label: const Text('Search'),
                      style: FilledButton.styleFrom(
                        foregroundColor: textColor,
                        backgroundColor: cardBackground,
                        side: BorderSide(color: cardBorder),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _close,
                      icon: const Icon(Icons.library_books_outlined),
                      label: const Text('Library'),
                      style: FilledButton.styleFrom(
                        foregroundColor: textColor,
                        backgroundColor: cardBackground,
                        side: BorderSide(color: cardBorder),
                      ),
                    ),
                  ],
                ),
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
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
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
                                  style: theme.textTheme.bodyLarge?.copyWith(
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
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: textColor,
                                  ),
                                ),
                              )
                            : SelectionArea(
                                child: SingleChildScrollView(
                                  controller: _bodyScrollController,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (showSectionTitle) ...[
                                        Text(
                                          currentSection?.title ??
                                              item.displayTitle,
                                          style: theme.textTheme.headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: textColor,
                                                fontSize: titleFontSize,
                                              ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      if (sectionBlocks.isEmpty)
                                        Text(
                                          'No readable text in this section.',
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    onPressed: _close,
                  ),
                  const SizedBox(width: 12),
                  _ToolbarPillButton(
                    isNightMode: isNight,
                    icon: isNight
                        ? Icons.wb_sunny_outlined
                        : Icons.nightlight_round,
                    label: isNight ? 'Day' : 'Night',
                    onPressed: () => setState(() => _nightMode = !_nightMode),
                  ),
                  const SizedBox(width: 12),
                  _ToolbarPillButton(
                    isNightMode: isNight,
                    icon: _showRefCodes
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    label: _showRefCodes ? 'Hide Ref Codes' : 'Show Ref Codes',
                    onPressed: _sections.isEmpty ? null : _toggleShowRefCodes,
                  ),
                  const SizedBox(width: 12),
                  _ZoomCluster(
                    isNightMode: isNight,
                    valueLabel: '${(_fontScale * 100).round()}%',
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
