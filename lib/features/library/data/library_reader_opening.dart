import 'package:path/path.dart' as p;

import '../../reader/data/commentary_research_library_service.dart';
import 'library_catalog_service.dart';
import 'library_section_heuristics.dart';
import '../presentation/library_navigation_tree.dart';

/// Finds the next readable section without treating structural or empty
/// entries as chapter boundaries of their own.
int? libraryReaderAdjacentReadableSectionIndex({
  required int currentIndex,
  required int sectionCount,
  required bool forward,
  required bool Function(int index) isReadable,
}) {
  final step = forward ? 1 : -1;
  for (
    var index = currentIndex + step;
    index >= 0 && index < sectionCount;
    index += step
  ) {
    if (isReadable(index)) return index;
  }
  return null;
}

/// Preserves structural TOC nodes whose source contains a heading but no body.
/// No descendant text is copied into these sections.
List<LibraryBookSection> libraryReaderSectionsWithHeadingOnlyNavigation({
  required List<LibraryBookSection> sections,
  required List<LibraryCatalogNavigationItem> navigationItems,
}) {
  final result = <LibraryBookSection>[...sections];
  for (final item in navigationItems) {
    final href = _cleanNavigationHref(item.href);
    if (href == null || item.spineIndex == null) continue;
    final alreadyPresent = result.any(
      (section) => _hrefMatchesSection(section.entryName, href.toLowerCase()),
    );
    if (alreadyPresent) continue;
    result.add(
      LibraryBookSection(
        entryName: href,
        title: item.label,
        paragraphs: const <String>[],
        blocks: const <LibraryBookBlock>[],
        spineIndex: item.spineIndex,
      ),
    );
  }
  result.sort((left, right) {
    final spine = (left.spineIndex ?? 1 << 30).compareTo(
      right.spineIndex ?? 1 << 30,
    );
    if (spine != 0) return spine;
    return left.entryName.compareTo(right.entryName);
  });
  return List<LibraryBookSection>.unmodifiable(result);
}

/// Returns the section index the reader should open on.
///
/// The precedence matches the production reader:
/// 1. explicit initial href
/// 2. explicit initial spine index
/// 3. devotional navigation target for devotionals
/// 4. saved reading state when the item has been opened before
/// 5. first non-front-matter reading section
/// 6. saved spine/paragraph fallback
/// 7. first section
int libraryReaderInitialSectionIndex({
  required LibraryCatalogItem item,
  required List<LibraryBookSection> sections,
  required List<LibraryCatalogNavigationItem> navigationItems,
  required bool devotionalMode,
  String? initialHref,
  int? initialSpineIndex,
  DateTime? now,
}) {
  if (sections.isEmpty) return 0;

  final explicitInitialHref = _splitReaderHref(initialHref).href;
  if (explicitInitialHref.isNotEmpty) {
    final initialIndex = _sectionIndexForHref(sections, explicitInitialHref);
    if (initialIndex != null) return initialIndex;
  }

  if (initialSpineIndex != null && initialSpineIndex > 0) {
    final initialIndex = _sectionIndexForSpineIndex(
      sections: sections,
      navigationItems: navigationItems,
      spineIndex: initialSpineIndex,
    );
    if (initialIndex != null) return initialIndex;
  }

  if (devotionalMode) {
    final devotionalInitialHref = _devotionalInitialNavigationHref(
      navigationItems,
      now: now,
    );
    if (devotionalInitialHref != null) {
      final devotionalIndex = _sectionIndexForHref(
        sections,
        devotionalInitialHref,
      );
      if (devotionalIndex != null) return devotionalIndex;
    }
  }

  if (!devotionalMode && !item.isPeriodical && item.lastOpened != null) {
    final savedHref = _splitReaderHref(item.epubHref).href;
    if (savedHref.isNotEmpty) {
      final savedIndex = _sectionIndexForHref(sections, savedHref);
      if (savedIndex != null &&
          _hasReadableSavedSectionContent(sections[savedIndex]) &&
          (!_isEgwReaderItem(item) ||
              !_savedSectionIsFrontMatter(
                item: item,
                sections: sections,
                navigationItems: navigationItems,
                sectionIndex: savedIndex,
                savedLocation: item.epubHref,
              ))) {
        return savedIndex;
      }
    }
    final savedSpine = item.spineIndex;
    if (savedSpine != null && savedSpine > 0) {
      final savedIndex = _sectionIndexForSpineIndex(
        sections: sections,
        navigationItems: navigationItems,
        spineIndex: savedSpine,
      );
      if (savedIndex != null &&
          _hasReadableSavedSectionContent(sections[savedIndex]) &&
          (!_isEgwReaderItem(item) ||
              !_savedSectionIsFrontMatter(
                item: item,
                sections: sections,
                navigationItems: navigationItems,
                sectionIndex: savedIndex,
              ))) {
        return savedIndex;
      }
    }
  }

  if (!devotionalMode && !item.isPeriodical) {
    int? chapterOneIndex;
    for (final nav in navigationItems) {
      final index = _sectionIndexForNavigationItemInSections(sections, nav);
      if (index == null) continue;
      final normalizedLabel = nav.label
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      if (_isChapterOneLabel(normalizedLabel)) {
        chapterOneIndex ??= index;
      }
    }
    // A heading-only Chapter 1 is still the honest structural context for a
    // first open when Preface has no body. It must not be assigned to Preface.
    if (chapterOneIndex != null) return chapterOneIndex;
  }

  final firstRealContentHref = _firstRealContentNavigationHref(navigationItems);
  if (firstRealContentHref != null) {
    final firstRealContentIndex = _sectionIndexForHref(
      sections,
      firstRealContentHref,
    );
    // The navigation row has already passed the explicit front-matter and
    // metadata filters. Trust that database classification even when the
    // first chapter is intentionally short — except for the unambiguous
    // case of a section with zero real body paragraphs (e.g. an Index/
    // back-matter page that is nothing but bare print-page markers like
    // "150", "151", "152", …). Nav classification alone doesn't catch that
    // because such a section can still be labeled/typed as non-front-matter.
    if (firstRealContentIndex != null &&
        !librarySectionHasNoBodyParagraphs(
          sections[firstRealContentIndex].paragraphs,
        )) {
      return firstRealContentIndex;
    }
  }

  final firstContentIndex = _firstRealContentSectionIndex(
    sections,
    bookTitle: item.displayTitle,
  );
  if (firstContentIndex != null) return firstContentIndex;

  if (!devotionalMode) {
    final savedParagraph = item.paragraphIndex;
    if (savedParagraph != null &&
        item.spineIndex != null &&
        item.spineIndex! > 0) {
      final navIndex = _navigationIndexForSavedState(
        sections: sections,
        navigationItems: navigationItems,
        spineIndex: item.spineIndex!,
      );
      if (navIndex != null && _isRealContentSection(sections[navIndex], item)) {
        return navIndex;
      }
    }
  }

  return 0;
}

bool _isChapterOneLabel(String normalizedLabel) {
  return RegExp(r'^chapter (?:1|i|one)(?: |$)').hasMatch(normalizedLabel);
}

/// Keeps a first chapter's anchor/navigation identity when its heading shares
/// an XHTML spine with a title page. Resolving only the section index loses
/// that anchor and leaves the reader at the title until the user taps TOC.
int? libraryReaderInitialNavigationIndex({
  required LibraryCatalogItem item,
  required List<LibraryBookSection> sections,
  required List<LibraryCatalogNavigationItem> navigationItems,
  required int initialSectionIndex,
  required bool hasExplicitInitialLocation,
}) {
  if (hasExplicitInitialLocation) return null;
  for (var index = 0; index < navigationItems.length; index++) {
    final nav = navigationItems[index];
    final label = nav.label
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    if (!_isChapterOneLabel(label)) continue;
    final sectionIndex = _sectionIndexForNavigationItemInSections(
      sections,
      nav,
    );
    if (sectionIndex == initialSectionIndex) return index;
  }
  return null;
}

bool _hasReadableSavedSectionContent(LibraryBookSection section) {
  if (section.blocks.isNotEmpty) return true;
  if (!section.paragraphs.any((paragraph) => paragraph.trim().isNotEmpty)) {
    return false;
  }
  // A saved position that resolves to a section with only bare page-number/
  // metadata paragraphs (e.g. an Index page) is not readable content, even
  // though it technically has non-empty "paragraphs" — see
  // librarySectionHasNoBodyParagraphs.
  return !librarySectionHasNoBodyParagraphs(section.paragraphs);
}

bool _isEgwReaderItem(LibraryCatalogItem item) {
  final path = item.relativePath.replaceAll('\\', '/').toLowerCase();
  final collection = item.collectionName?.trim().toLowerCase() ?? '';
  return path.contains('/egw/') ||
      path.contains('/egw_') ||
      collection.startsWith('egw ') ||
      item.sourceSite?.trim().toLowerCase() == 'egwwritings.org';
}

bool libraryReaderSavedLocationTargetsFrontMatter({
  required LibraryCatalogItem item,
  required List<LibraryBookSection> sections,
  required List<LibraryCatalogNavigationItem> navigationItems,
}) {
  final savedHref = _splitReaderHref(item.epubHref).href;
  final savedIndex = savedHref.isNotEmpty
      ? _sectionIndexForHref(sections, savedHref)
      : item.spineIndex == null
      ? null
      : _sectionIndexForSpineIndex(
          sections: sections,
          navigationItems: navigationItems,
          spineIndex: item.spineIndex!,
        );
  if (savedIndex == null) return false;
  return _savedSectionIsFrontMatter(
    item: item,
    sections: sections,
    navigationItems: navigationItems,
    sectionIndex: savedIndex,
    savedLocation: item.epubHref,
  );
}

bool _savedSectionIsFrontMatter({
  required LibraryCatalogItem item,
  required List<LibraryBookSection> sections,
  required List<LibraryCatalogNavigationItem> navigationItems,
  required int sectionIndex,
  String? savedLocation,
}) {
  if (sectionIndex < 0 || sectionIndex >= sections.length) return true;
  final section = sections[sectionIndex];
  if (libraryIsFrontMatterOpeningLabel(section.title) ||
      libraryIsFrontMatterOpeningLabel(section.entryName)) {
    return true;
  }
  final savedAnchor = _splitReaderHref(savedLocation).anchor;
  for (final nav in navigationItems) {
    if (_sectionIndexForNavigationItemInSections(sections, nav) !=
        sectionIndex) {
      continue;
    }
    if (savedAnchor != null &&
        savedAnchor.isNotEmpty &&
        nav.anchorId?.trim().toLowerCase() != savedAnchor.toLowerCase()) {
      continue;
    }
    final contentKind = nav.contentKind?.trim().toLowerCase();
    if (nav.isFrontMatter ||
        const {
          'title',
          'cover',
          'copyright',
          'toc',
          'front_matter',
        }.contains(contentKind) ||
        libraryIsFrontMatterOpeningLabel(nav.label)) {
      return true;
    }
  }
  return false;
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

int? _firstRealContentSectionIndex(
  List<LibraryBookSection> sections, {
  required String bookTitle,
}) {
  int? firstMeaningfulIndex;
  for (var index = 0; index < sections.length; index++) {
    final section = sections[index];
    if (!libraryIsMeaningfulReadingSection(
      title: section.title,
      href: section.entryName,
      paragraphs: section.paragraphs,
      bookTitle: bookTitle,
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

bool _isRealContentSection(
  LibraryBookSection section,
  LibraryCatalogItem item,
) {
  return libraryIsMeaningfulReadingSection(
    title: section.title,
    href: section.entryName,
    paragraphs: section.paragraphs,
    bookTitle: item.displayTitle,
  );
}

String? _firstRealContentNavigationHref(
  List<LibraryCatalogNavigationItem> navigationItems,
) {
  if (navigationItems.isEmpty) return null;

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
  List<LibraryCatalogNavigationItem> navigationItems, {
  DateTime? now,
}) {
  if (navigationItems.isEmpty) return null;

  final tree = buildLibraryNavigationTree(
    navigationItems,
    devotionalMode: true,
  );
  final roots = tree.childrenByParent[null] ?? const [];
  if (roots.isEmpty) return null;

  final today = now ?? DateTime.now();
  final currentMonth = _devotionalMonthName(today.month);
  final currentDay = today.day;

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
    if (labelInfo.day == day) return child;
  }
  return null;
}

String? _cleanNavigationHref(String? href) {
  final trimmed = href?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final base = trimmed.split('#').first.split('?').first.trim();
  return base.isEmpty ? null : base;
}

bool _hrefMatchesSection(String sectionHref, String href) {
  final normalizedSectionHref = p.normalize(sectionHref).toLowerCase();
  final normalizedHref = p.normalize(href).toLowerCase();
  if (normalizedSectionHref == normalizedHref) return true;
  if (normalizedSectionHref.endsWith('/$normalizedHref')) return true;
  if (_hrefBase(normalizedSectionHref) == _hrefBase(normalizedHref)) {
    return true;
  }
  return false;
}

String _hrefBase(String href) {
  final trimmed = href.trim().toLowerCase();
  if (trimmed.isEmpty) return '';
  return p.basenameWithoutExtension(trimmed);
}

bool _isReaderMetadataHelpLabel(String value) {
  final normalized = _normalizeReaderLabel(value);
  if (normalized.isEmpty) return false;

  const prefixes = <String>[
    'cover',
    'title page',
    'contents',
    'table of contents',
    'toc',
    'foreword',
    'preface',
    'introduction',
    'copyright',
    'publisher note',
    'publisher',
    'editor note',
    'editorial note',
    'editorial',
    'publication information',
    'source credits',
    'acknowledgments',
    'acknowledgements',
    'index',
    'bibliography',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
}

String _normalizeReaderLabel(String value) {
  final normalized = value.toLowerCase();
  final stripped = normalized
      .replaceAll(RegExp(r'[_/\\]+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9\s]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return stripped;
}

({String href, String? anchor}) _splitReaderHref(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) {
    return (href: '', anchor: null);
  }
  final hashIndex = trimmed.indexOf('#');
  if (hashIndex < 0) {
    return (href: trimmed, anchor: null);
  }
  final href = trimmed.substring(0, hashIndex).trim();
  final anchor = trimmed.substring(hashIndex + 1).trim();
  return (href: href, anchor: anchor.isEmpty ? null : anchor);
}

String _devotionalMonthName(int month) {
  switch (month) {
    case 1:
      return 'january';
    case 2:
      return 'february';
    case 3:
      return 'march';
    case 4:
      return 'april';
    case 5:
      return 'may';
    case 6:
      return 'june';
    case 7:
      return 'july';
    case 8:
      return 'august';
    case 9:
      return 'september';
    case 10:
      return 'october';
    case 11:
      return 'november';
    case 12:
      return 'december';
    default:
      return 'january';
  }
}
