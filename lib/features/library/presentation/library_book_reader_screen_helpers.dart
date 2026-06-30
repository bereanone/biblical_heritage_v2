part of 'library_book_reader_screen.dart';

String libraryReaderBookSubtitle(
  LibraryCatalogItem item, {
  String? sectionTitle,
}) {
  final author = item.displayAuthor.trim();
  if (author.isNotEmpty && author.toLowerCase() != 'unknown author') {
    return author;
  }

  final cleanSectionTitle = sectionTitle?.trim() ?? '';
  if (cleanSectionTitle.isNotEmpty) {
    return cleanSectionTitle;
  }

  final collectionName = item.collectionName?.trim() ?? '';
  if (collectionName.isNotEmpty && collectionName.toLowerCase() != 'user') {
    return collectionName;
  }

  return '';
}

String? libraryReaderContentsTargetKeyForNavigationItem({
  required LibraryCatalogNavigationItem navItem,
  required List<LibraryBookSection> sections,
}) {
  final sectionIndex = _librarySectionIndexForNavigationItem(
    sections: sections,
    navItem: navItem,
  );
  if (sectionIndex == null) return null;
  return libraryReaderSectionStartTargetKey(sections[sectionIndex].blocks);
}

bool libraryReaderNavigationItemTargetsSectionStart({
  required LibraryCatalogNavigationItem navItem,
  required List<LibraryBookSection> sections,
}) {
  final sectionIndex = _librarySectionIndexForNavigationItem(
    sections: sections,
    navItem: navItem,
  );
  if (sectionIndex == null) return false;

  final sectionStartTargetKey = libraryReaderSectionStartTargetKey(
    sections[sectionIndex].blocks,
  );
  if (sectionStartTargetKey == null) return false;

  return libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItem,
        sections: sections,
      ) ==
      sectionStartTargetKey;
}

String? libraryReaderSectionStartTargetKey(List<LibraryBookBlock> blocks) {
  for (var index = 0; index < blocks.length; index++) {
    final block = blocks[index];
    if (block.text.trim().isEmpty) continue;
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
  return null;
}

String _normalizeBlockKey(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

int? _librarySectionIndexForNavigationItem({
  required List<LibraryBookSection> sections,
  required LibraryCatalogNavigationItem navItem,
}) {
  if (sections.isEmpty) return null;
  final href = _cleanNavigationHref(navItem.href);
  if (href != null) {
    final normalizedHref = href.toLowerCase();
    for (var index = 0; index < sections.length; index++) {
      if (_hrefMatchesSection(sections[index].entryName, normalizedHref)) {
        return index;
      }
    }
  }

  if (navItem.spineIndex != null) {
    final index = navItem.spineIndex! - 1;
    if (index >= 0 && index < sections.length) return index;
  }

  return null;
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

bool _isReaderMetadataHelpLabel(String value) {
  return libraryIsMetadataSectionLabel(value);
}

bool _hrefMatchesSection(String sectionEntryName, String normalizedHref) {
  final normalizedSectionHref = p.normalize(sectionEntryName).toLowerCase();
  if (normalizedSectionHref == normalizedHref) return true;
  return p.basename(normalizedSectionHref) == p.basename(normalizedHref);
}

_PageMarker? _readerPageMarkerFromText(String? text) {
  final clean = text?.trim() ?? '';
  if (clean.isEmpty) return null;
  final match = RegExp(r'\[(\d{1,4})\]').firstMatch(clean);
  if (match == null) return null;
  final pageNumber = int.tryParse(match.group(1)!);
  if (pageNumber == null) return null;
  return _PageMarker(pageNumber);
}

String? _readerDisplayReferenceCodeForParagraph({
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

Future<Map<int, String>> loadReaderSectionReferenceCodes({
  required String libraryItemId,
  required LibraryBookSection section,
  required String? itemAbbreviation,
  required bool isDevotional,
}) async {
  if (isDevotional) {
    return const <int, String>{};
  }

  final normalizedHref = p.normalize(section.entryName).toLowerCase();
  final refIndexRowResult = await ELibraryReadResolver.instance
      .readWithFallback<List<Map<String, Object?>>>(
        read: (db) => db.rawQuery(
          '''
      SELECT paragraph_index, ref_code
      FROM elibrary_ref_index
      WHERE library_item_id = ?
        AND LOWER(REPLACE(REPLACE(COALESCE(href, ''), '\\', '/'), './', '')) = ?
      ORDER BY paragraph_index ASC
      ''',
          [libraryItemId, normalizedHref],
        ),
        hasData: (rows) => rows.isNotEmpty,
        fallbackDatabase: UserDatabase.instance.database,
      );
  final refIndexRows = refIndexRowResult.value;
  if (refIndexRows.isNotEmpty) {
    final resolvedFromRefIndex = <int, String>{};
    for (final row in refIndexRows) {
      final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
      final refCode = row['ref_code']?.toString().trim() ?? '';
      if (paragraphIndex == null || paragraphIndex <= 0 || refCode.isEmpty) {
        continue;
      }
      resolvedFromRefIndex[paragraphIndex] = refCode;
    }
    if (resolvedFromRefIndex.isNotEmpty) {
      return resolvedFromRefIndex;
    }
  }

  final rowResult = await ELibraryReadResolver.instance
      .readWithFallback<List<Map<String, Object?>>>(
        read: (db) => db.rawQuery(
          '''
      SELECT paragraph_index, anchor, full_paragraph, epub_href, anchor_id,
             spine_index, original_reference_text
      FROM library_links
      WHERE library_item_id = ?
        AND deleted_at IS NULL
        AND LOWER(REPLACE(REPLACE(COALESCE(epub_href, ''), '\\', '/'), './', '')) = ?
      ORDER BY paragraph_index ASC
      ''',
          [libraryItemId, normalizedHref],
        ),
        hasData: (rows) => rows.isNotEmpty,
        fallbackDatabase: UserDatabase.instance.database,
      );
  final rows = rowResult.value;

  final resolved = <int, String>{};
  int? currentPageNumber;
  int? pageParagraphIndex;

  for (final row in rows) {
    final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
    if (paragraphIndex == null || paragraphIndex <= 0) continue;

    final marker =
        _readerPageMarkerFromText(row['anchor']?.toString()) ??
        _readerPageMarkerFromText(row['full_paragraph']?.toString());
    if (marker != null) {
      currentPageNumber = marker.pageNumber;
      pageParagraphIndex = paragraphIndex;
    }

    final referenceCode = _readerDisplayReferenceCodeForParagraph(
      itemAbbreviation: itemAbbreviation,
      pageNumber: currentPageNumber,
      pageParagraphIndex: pageParagraphIndex,
      paragraphIndex: paragraphIndex,
    );
    if (referenceCode != null) {
      resolved[paragraphIndex] = referenceCode;
    }
  }

  return resolved;
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
    'overview',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'a word to the reader',
    'word to the reader',
    'further links',
    'further information',
    'end user license agreement',
    'publisher s preface',
    'author s preface',
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
    'overview',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'a word to the reader',
    'word to the reader',
    'further links',
    'further information',
    'end user license agreement',
    'publisher s preface',
    'author s preface',
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

String? libraryReaderDevotionalFallbackRefCode({
  required LibraryCatalogItem item,
  required String sectionTitle,
  required int? paragraphIndex,
}) {
  if (!item.isDevotional) return null;
  if (paragraphIndex == null || paragraphIndex <= 0) return null;

  final abbreviation = cleanDisplayRefCode(libraryReaderBookAbbreviation(item));
  if (abbreviation == null || abbreviation.isEmpty) return null;

  final labelInfo = parseDevotionalNavigationLabel(sectionTitle);
  if (labelInfo == null || labelInfo.isMonthHeading || labelInfo.day == null) {
    return null;
  }

  final monthName = _devotionalMonthDisplayName(labelInfo.monthIndex);
  if (monthName.isEmpty) return null;

  return '$abbreviation $monthName ${labelInfo.day}.$paragraphIndex';
}

String? libraryReaderDevotionalFallbackRefCodeForBlock({
  required LibraryCatalogItem item,
  required String sectionTitle,
  required LibraryBookBlock block,
  required int fallbackParagraphCount,
}) {
  if (!libraryReaderShouldCountDevotionalFallbackParagraph(
    item: item,
    sectionTitle: sectionTitle,
    block: block,
    fallbackParagraphCount: fallbackParagraphCount,
  )) {
    return null;
  }

  return libraryReaderDevotionalFallbackRefCode(
    item: item,
    sectionTitle: sectionTitle,
    paragraphIndex: fallbackParagraphCount + 1,
  );
}

bool libraryReaderShouldCountDevotionalFallbackParagraph({
  required LibraryCatalogItem item,
  required String sectionTitle,
  required LibraryBookBlock block,
  required int fallbackParagraphCount,
}) {
  return libraryReaderShouldCountDevotionalFallbackParagraphText(
    item: item,
    sectionTitle: sectionTitle,
    paragraphText: block.text,
    className: block.className,
    fallbackParagraphCount: fallbackParagraphCount,
  );
}

bool libraryReaderShouldCountDevotionalFallbackParagraphText({
  required LibraryCatalogItem item,
  required String sectionTitle,
  required String paragraphText,
  String? className,
  required int fallbackParagraphCount,
}) {
  if (!item.isDevotional) return true;
  if (fallbackParagraphCount > 0) return true;

  final isLeadStyle =
      _hasEpubClass(className, 'devotionaltext') ||
      _hasEpubClass(className, 'bibletext') ||
      _hasEpubClass(className, 'center');
  final normalizedParagraphText = _normalizeReaderLabel(paragraphText);
  if (normalizedParagraphText.isEmpty) {
    return false;
  }

  final sectionLabel = _normalizeReaderLabel(sectionTitle);
  final looksLikeSectionTitle =
      sectionLabel.isNotEmpty && normalizedParagraphText == sectionLabel;
  if (looksLikeSectionTitle) {
    return false;
  }

  if (_looksLikeBibleCitationSubtitle(paragraphText)) {
    return false;
  }

  if (isLeadStyle) {
    return false;
  }

  return true;
}

bool libraryReaderShouldHideDevotionalContentsEntry({
  required String label,
  String? href,
}) {
  final cleanedHref = _cleanNavigationHref(href);
  final hrefLabel = cleanedHref == null
      ? ''
      : p.basenameWithoutExtension(cleanedHref);
  return _isReaderFrontMatterLabel(label) ||
      _isReaderFrontMatterLabel(hrefLabel) ||
      _isReaderMetadataHelpLabel(label) ||
      _isReaderMetadataHelpLabel(hrefLabel);
}

bool _looksLikeBibleCitationSubtitle(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return false;

  final candidate = _trimSubtitleCitationCandidate(
    _devotionalBibleCitationCandidate(normalized),
  );
  if (candidate.isEmpty) return false;

  if (!RegExp(
    r"^(?:[1-3]\s*)?[A-Za-z][A-Za-z'.]*(?:\s+[A-Za-z][A-Za-z'.]*){0,4}\s+\d+\s*:\s*\d+(?:\s*,\s*[A-Z.]+)?\.?$",
    caseSensitive: false,
  ).hasMatch(candidate)) {
    return false;
  }

  final normalizedCandidate = _normalizeReaderLabel(candidate);
  final wordCount = normalizedCandidate
      .split(' ')
      .where((part) => part.isNotEmpty)
      .length;
  return wordCount <= 16 ||
      normalized.contains('—') ||
      normalized.contains('-');
}

String _devotionalBibleCitationCandidate(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';

  final dashMatches = normalized.split(RegExp(r'[—–-]'));
  final tail = dashMatches.isEmpty ? normalized : dashMatches.last.trim();
  if (tail.isNotEmpty) {
    return tail;
  }
  return normalized;
}

String _trimSubtitleCitationCandidate(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'^[\s"“”‘’\(\)\[\]\{\},;:!?]+'), '')
      .replaceAll(RegExp(r'[\s"“”‘’\(\)\[\]\{\},;:!?]+$'), '')
      .trim();
}

String _devotionalMonthDisplayName(int monthIndex) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (monthIndex < 1 || monthIndex > months.length) return '';
  return months[monthIndex - 1];
}

String? cleanDisplayRefCode(String? value) {
  return librarySafeUserFacingReferenceText(value);
}

String libraryCompactReferenceRangeLabel(String? startRef, String? endRef) {
  final start = cleanDisplayRefCode(startRef);
  final end = cleanDisplayRefCode(endRef);
  if (start == null || start.isEmpty) return end ?? '';
  if (end == null || end.isEmpty) return start;
  if (start == end) return start;

  final startTokens = start.split(RegExp(r'\s+'));
  final endTokens = end.split(RegExp(r'\s+'));
  if (startTokens.length == endTokens.length && startTokens.length >= 2) {
    var sharedPrefix = true;
    for (var index = 0; index < startTokens.length - 1; index++) {
      if (startTokens[index] != endTokens[index]) {
        sharedPrefix = false;
        break;
      }
    }
    if (sharedPrefix) {
      final startTail = startTokens.last;
      final endTail = endTokens.last;
      if (_referenceTailIsCompatible(startTail, endTail)) {
        return '$start - $endTail';
      }
    }
  }

  return '$start - $end';
}

bool _referenceTailIsCompatible(String startTail, String endTail) {
  if (startTail == endTail) return true;
  if (RegExp(r'^\d+$').hasMatch(startTail) &&
      RegExp(r'^\d+$').hasMatch(endTail)) {
    return true;
  }

  final startParts = startTail.split('.');
  final endParts = endTail.split('.');
  if (startParts.length < 2 || endParts.length < 2) return false;
  final startRoot = startParts.sublist(0, startParts.length - 1).join('.');
  final endRoot = endParts.sublist(0, endParts.length - 1).join('.');
  if (startRoot.isEmpty || startRoot != endRoot) return false;
  return RegExp(r'^[0-9]+$').hasMatch(startParts.last) &&
      RegExp(r'^[0-9]+$').hasMatch(endParts.last);
}

String? libraryReaderBookAbbreviation(LibraryCatalogItem item) {
  return libraryUserFacingBookAbbreviation(
    title: item.displayTitle,
    fileName: item.fileName,
    relativePath: item.relativePath,
  );
}

// Returns "RH July 21, 1851, par. 3" for a periodical article section.
// sectionTitle must look like "July 21, 1851"; paragraphIndex is 1-based
// within the current article XHTML (already so in the reader).
String? libraryReaderPeriodicalRefCode({
  required LibraryCatalogItem item,
  required String sectionTitle,
  required int? paragraphIndex,
}) {
  if (!item.isPeriodical) return null;
  if (paragraphIndex == null || paragraphIndex <= 0) return null;

  final abbreviation = cleanDisplayRefCode(libraryReaderBookAbbreviation(item));
  if (abbreviation == null || abbreviation.isEmpty) return null;

  final date = _periodicalArticleDate(sectionTitle);
  if (date == null) return null;

  return '$abbreviation $date, par. $paragraphIndex';
}

// Validates and normalises a section title that looks like "July 21, 1851".
String? _periodicalArticleDate(String sectionTitle) {
  final match = RegExp(
    r'^(January|February|March|April|May|June|July|August|'
    r'September|October|November|December)\s+(\d{1,2}),\s*(\d{4})$',
    caseSensitive: false,
  ).firstMatch(sectionTitle.trim());
  if (match == null) return null;

  final month = _capitalizeFirst(match.group(1)!);
  final day = match.group(2)!;
  final year = match.group(3)!;
  return '$month $day, $year';
}

String _capitalizeFirst(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1).toLowerCase();
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
