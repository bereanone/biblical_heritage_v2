part of 'library_book_reader_screen.dart';

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
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'overview',
    'further links',
    'further information',
    'end user license agreement',
    'a word to the reader',
    'word to the reader',
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
    'ellen g white',
    'ellen white',
  };
  if (exactMatches.contains(normalized)) return true;

  const prefixes = <String>[
    'cover ',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'toc',
    'nav',
    'about this book',
    'about book',
    'aboutbook',
    'about the author',
    'information about this book',
    'overview',
    'further links',
    'further information',
    'end user license agreement',
    'a word to the reader',
    'word to the reader',
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
    'ellen g white',
    'ellen white',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
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
  final cleaned = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return null;
  final lower = cleaned.toLowerCase();
  if (lower.startsWith('elibrary:') ||
      lower.startsWith('note:') ||
      lower.contains('::') ||
      lower.contains('oebps/') ||
      lower.contains('.xhtml') ||
      lower == 'book 0 0:0') {
    return null;
  }
  if (RegExp(
    r'^content\d+(?:\.xhtml)?$',
    caseSensitive: false,
  ).hasMatch(lower)) {
    return null;
  }
  return cleaned;
}

String? libraryReaderBookAbbreviation(LibraryCatalogItem item) {
  final fromDisplayTitle = _libraryReaderAbbreviationFromTitle(
    item.displayTitle,
  );
  if (fromDisplayTitle != null) return fromDisplayTitle;

  final fromFileName = _libraryReaderAbbreviationFromPathSegment(item.fileName);
  if (fromFileName != null) return fromFileName;

  final fromRelativePath = _libraryReaderAbbreviationFromPathSegment(
    item.relativePath,
  );
  if (fromRelativePath != null) return fromRelativePath;

  return null;
}

String? _libraryReaderAbbreviationFromTitle(String value) {
  final normalized = _normalizeLibraryReaderText(value);
  if (normalized.isEmpty) return null;

  const rules = <({String needle, String code})>[
    (needle: 'the great controversy', code: 'GC'),
    (needle: 'the great controversy 1888', code: 'GC88'),
    (needle: 'desire of ages', code: 'DA'),
    (needle: 'christ triumphant', code: 'CTr'),
    (needle: 'steps to christ', code: 'SC'),
    (needle: 'patriarchs and prophets', code: 'PP'),
    (needle: 'prophets and kings', code: 'PK'),
    (needle: 'acts of the apostles', code: 'AA'),
    (needle: 'early writings', code: 'EW'),
    (needle: 'gospel workers', code: 'GW'),
    (needle: 'life sketches', code: 'LS'),
    (needle: 'ministry of healing', code: 'MH'),
    (needle: 'christ s object lessons', code: 'COL'),
    (needle: 'education', code: 'Ed.'),
    (needle: 'thoughts from the mount of blessing', code: 'MB'),
    (needle: 'the faith i live by', code: 'FLB'),
    (needle: 'homeward bound', code: 'HB'),
    (needle: 'maranatha', code: 'Mar'),
    (needle: 'radiant religion', code: 'RRe'),
    (needle: 'reflecting christ', code: 'RC'),
    (needle: 'that i may know him', code: 'TMK'),
    (needle: 'testimonies for the church vol 1', code: '1T'),
    (needle: 'testimonies for the church vol 2', code: '2T'),
    (needle: 'testimonies for the church vol 3', code: '3T'),
    (needle: 'testimonies for the church vol 4', code: '4T'),
    (needle: 'testimonies for the church vol 5', code: '5T'),
    (needle: 'testimonies for the church vol 6', code: '6T'),
    (needle: 'testimonies for the church vol 7', code: '7T'),
    (needle: 'testimonies for the church vol 8', code: '8T'),
    (needle: 'testimonies for the church vol 9', code: '9T'),
    (needle: 'spiritual gifts vol 1', code: 'SG1'),
  ];

  for (final rule in rules) {
    if (normalized.contains(rule.needle)) {
      return rule.code;
    }
  }

  return null;
}

String? _libraryReaderAbbreviationFromPathSegment(String value) {
  final stem = p.basenameWithoutExtension(value).trim();
  if (stem.isEmpty) return null;

  final tokens = stem
      .split(RegExp(r'[_\-\s]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  for (final token in tokens.reversed) {
    final upper = token.toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,5}$').hasMatch(upper)) continue;
    if (RegExp(
      r'^(EPUB|HTML|XHTML|CONTENT\d+)$',
      caseSensitive: false,
    ).hasMatch(upper)) {
      continue;
    }
    if (RegExp(
      r'^(RESEARCH|DEVOTIONALS?|COMMENTARIES?)$',
      caseSensitive: false,
    ).hasMatch(upper)) {
      continue;
    }
    return upper;
  }
  return null;
}

String _normalizeLibraryReaderText(String? value) {
  return (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
