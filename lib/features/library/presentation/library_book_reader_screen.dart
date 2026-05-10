import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../data/library_catalog_service.dart';
import 'library_navigation_tree.dart';

part 'epub_inline_span_builder.dart';
part 'epub_body_block_parser.dart';
part 'library_contents_popup.dart';
part 'library_reader_bottom_bar.dart';

class LibraryBookReaderScreen extends StatefulWidget {
  const LibraryBookReaderScreen({
    super.key,
    required this.item,
    this.initialHref,
    this.initialAnchorId,
    this.initialSpineIndex,
    this.initialParagraphIndex,
  });

  final LibraryCatalogItem item;
  final String? initialHref;
  final String? initialAnchorId;
  final int? initialSpineIndex;
  final int? initialParagraphIndex;

  @override
  State<LibraryBookReaderScreen> createState() =>
      _LibraryBookReaderScreenState();
}

class _LibraryBookReaderScreenState extends State<LibraryBookReaderScreen> {
  final _service = CommentaryResearchLibraryService.instance;
  final ScrollController _bodyScrollController = ScrollController();
  final Map<String, GlobalKey> _bodyBlockKeys = <String, GlobalKey>{};
  bool _loading = true;
  bool _nightMode = false;
  double _fontScale = 1.0;
  String? _error;
  List<LibraryBookSection> _sections = const [];
  List<LibraryCatalogNavigationItem> _navigationItems = const [];
  int _selectedIndex = 0;
  int _selectedNavigationIndex = 0;
  int? _selectedHeadingTargetIndex;
  String? _pendingBodyScrollTargetKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bodyScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.exists
        ? selection.path?.trim() ?? ''
        : (await LibraryRootService.instance.accessibleLibraryRootPath())
                  ?.trim() ??
              '';

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
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _navigationItems = navigationItems;
        _selectedIndex = initialIndex;
        _selectedNavigationIndex = initialNavigationIndex;
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
      final initialIndex = _sectionIndexForHref(sections, initialHref);
      if (initialIndex != null) return initialIndex;
    }

    final initialSpineIndex = widget.initialSpineIndex;
    if (initialSpineIndex != null && initialSpineIndex > 0) {
      final initialIndex = _sectionIndexForSpineIndex(
        sections: sections,
        navigationItems: navigationItems,
        spineIndex: initialSpineIndex,
      );
      if (initialIndex != null) return initialIndex;
    }

    final savedHref = _splitReaderHref(widget.item.epubHref).href;
    if (savedHref.isNotEmpty) {
      final savedIndex = _sectionIndexForHref(sections, savedHref);
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
      if (navIndex != null) return navIndex;
    }

    return 0;
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
      if (_isReaderFrontMatterLabel(section.title) ||
          _isReaderFrontMatterLabel(
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
    return !_isReaderFrontMatterLabel(section.title) &&
        !_isReaderFrontMatterLabel(entryLabel);
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
      if (_isReaderFrontMatterLabel(item.label) ||
          _isReaderFrontMatterLabel(p.basenameWithoutExtension(href)) ||
          item.isFrontMatter) {
        continue;
      }
      return href;
    }

    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (_isReaderFrontMatterLabel(item.label) ||
          _isReaderFrontMatterLabel(p.basenameWithoutExtension(href)) ||
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
    final showSectionTitle = _shouldShowSectionTitle(
      sectionBlocks,
      currentSection?.title ?? '',
    );

    final bodyFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale;
    final titleFontSize =
        (theme.textTheme.headlineSmall?.fontSize ?? 24) * _fontScale;

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
                            : SingleChildScrollView(
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
                                      for (
                                        var index = 0;
                                        index < sectionBlocks.length;
                                        index++
                                      ) ...[
                                        _SectionBlockView(
                                          key: _keyForBlock(
                                            _blockTargetKey(
                                              sectionBlocks[index],
                                              index,
                                            ),
                                          ),
                                          block: sectionBlocks[index],
                                          textColor: textColor,
                                          bodyFontSize: bodyFontSize,
                                          topPadding: index == 0
                                              ? 0
                                              : (sectionBlocks[index].isHeading
                                                    ? 18
                                                    : 6),
                                          bottomPadding:
                                              sectionBlocks[index].isHeading
                                              ? 12
                                              : 14,
                                          isNightMode: isNight,
                                        ),
                                      ],
                                  ],
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

String _normalizeReaderLabel(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _shouldShowSectionTitle(
  List<LibraryBookBlock> blocks,
  String sectionTitle,
) {
  final normalizedSectionTitle = _normalizeReaderLabel(sectionTitle);
  if (normalizedSectionTitle.isEmpty || blocks.isEmpty) {
    return true;
  }

  for (final block in blocks) {
    if (block.isHeading &&
        _normalizeReaderLabel(block.text) == normalizedSectionTitle) {
      return false;
    }
  }

  return true;
}

bool _hasEpubClass(String? className, String target) {
  if (className == null || className.trim().isEmpty) return false;
  final tokens = className
      .toLowerCase()
      .split(RegExp(r'[\s_-]+'))
      .where((token) => token.isNotEmpty);
  return tokens.contains(target.toLowerCase());
}

double _headingFontScale(int? level) {
  switch (level) {
    case 1:
      return 1.32;
    case 2:
      return 1.24;
    case 3:
      return 1.18;
    case 4:
      return 1.12;
    case 5:
      return 1.08;
    case 6:
      return 1.04;
    default:
      return 1.12;
  }
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

String? _cleanNavigationHref(String? href) {
  final value = href?.trim() ?? '';
  if (value.isEmpty) return null;
  final clean = value.split('#').first.split('?').first.trim();
  if (clean.isEmpty) return null;
  return p.normalize(clean);
}

bool _hrefMatchesSection(String sectionEntryName, String normalizedHref) {
  final normalizedSectionHref = p.normalize(sectionEntryName).toLowerCase();
  if (normalizedSectionHref == normalizedHref) return true;
  return p.basename(normalizedSectionHref) == p.basename(normalizedHref);
}

bool _isReaderFrontMatterLabel(String value) {
  final normalized = _normalizeReaderLabel(value);
  if (normalized.isEmpty) return false;

  const exactMatches = <String>{
    'cover',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'toc',
    'nav',
    'preface',
    'foreword',
    'introduction',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'copyright',
    'publisher note',
    'publisher',
    'editor note',
    'editorial note',
    'editorial',
    'publication information',
    'source credits',
    'dedication',
    'acknowledgments',
    'acknowledgements',
    'index',
    'bibliography',
    'appendix',
  };
  if (exactMatches.contains(normalized)) return true;

  const prefixes = <String>[
    'cover ',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'preface',
    'foreword',
    'introduction',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'copyright',
    'publisher note',
    'publisher',
    'editor note',
    'editorial note',
    'editorial',
    'publication information',
    'source credits',
    'dedication',
    'acknowledgments',
    'acknowledgements',
    'index',
    'bibliography',
    'appendix',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
}

Color _readerBackgroundColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.scaffoldBackgroundColor;
  return const Color(0xFF0B0D11);
}

Color _readerSurfaceColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.colorScheme.surface;
  return const Color(0xFF12151B);
}

Color _readerSurfaceHighColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.colorScheme.surfaceContainerHigh;
  return const Color(0xFF151922);
}

Color _readerBorderColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.colorScheme.outlineVariant;
  return const Color(0xFF3A404A);
}

Color _readerTextColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.colorScheme.onSurface;
  return const Color(0xFFF7F1E5);
}

Color _readerSubduedColor(ThemeData theme, bool isNight) {
  if (!isNight) return theme.colorScheme.onSurfaceVariant;
  return const Color(0xFFC8BFAF);
}

Color _readerSelectedColor(ThemeData theme, bool isNight) {
  final base = _readerSurfaceHighColor(theme, isNight);
  return Color.alphaBlend(
    theme.colorScheme.primary.withValues(alpha: 0.16),
    base,
  );
}
