import 'package:path/path.dart' as p;

bool libraryIsMetadataSectionLabel(String value) {
  final normalized = _normalizeLibraryText(value);
  if (normalized.isEmpty) return false;

  const exactMatches = <String>{
    'cover',
    'title page',
    'titlepage',
    'table of contents',
    'contents',
    'toc',
    'nav',
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
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
}

/// Labels that mark introductory front matter (intro/preface/foreword/etc.).
///
/// These sections stay visible in navigation and remain readable; the label
/// check is only used to avoid defaulting to them when a book is opened with
/// no saved reading position.
bool libraryIsFrontMatterOpeningLabel(String value) {
  final normalized = _normalizeLibraryText(value);
  if (normalized.isEmpty) return false;
  if (libraryIsMetadataSectionLabel(normalized)) return true;

  const exactMatches = <String>{
    'intro',
    'introduction',
    'preface',
    'foreword',
    'front matter',
    'frontmatter',
    'a word to the reader',
    'word to the reader',
    'to the reader',
    'about this book',
    'information about this book',
    'book information',
    'about the author',
    'how to use this book',
    'a note to the reader',
    'note to the reader',
  };
  if (exactMatches.contains(normalized)) return true;

  const prefixes = <String>[
    'introduction ',
    'preface ',
    'foreword ',
    'front matter ',
    'authors preface',
    'author s preface',
    'publishers preface',
    'publisher s preface',
    'translators preface',
    'translator s preface',
    'information about this book ',
    'book information ',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  return false;
}

bool libraryIsMeaningfulReadingSection({
  required String title,
  required String href,
  required List<String> paragraphs,
  String? bookTitle,
}) {
  final trimmedParagraphs = paragraphs
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList(growable: false);
  if (trimmedParagraphs.isEmpty) return false;

  final normalizedTitle = _normalizeLibraryText(title);
  final normalizedHref = _normalizeLibraryText(
    p.basenameWithoutExtension(href),
  );
  final normalizedBookTitle = _normalizeLibraryText(bookTitle ?? '');
  final totalLength = trimmedParagraphs.fold<int>(
    0,
    (sum, paragraph) => sum + paragraph.length,
  );
  final bodyParagraphCount = trimmedParagraphs
      .where((paragraph) => !_looksLikeMetadataParagraph(paragraph))
      .length;
  final hasSubstantialParagraph = trimmedParagraphs.any(
    (paragraph) => paragraph.length >= 80,
  );

  final looksLikeMetadataLabel =
      libraryIsMetadataSectionLabel(normalizedTitle) ||
      libraryIsMetadataSectionLabel(normalizedHref);
  final titlePageBoilerplate =
      normalizedBookTitle.isNotEmpty &&
      normalizedTitle == normalizedBookTitle &&
      trimmedParagraphs.any((paragraph) {
        final normalized = _normalizeLibraryText(paragraph);
        return normalized.contains('copyright') ||
            normalized.contains('originally published') ||
            normalized.contains('publishing association') ||
            normalized.contains('published in the usa') ||
            normalized.startsWith('isbn') ||
            normalized.contains('www ');
      });

  if (titlePageBoilerplate) return false;

  if (looksLikeMetadataLabel) {
    if (bodyParagraphCount >= 2 && totalLength >= 180) {
      return true;
    }
    return false;
  }

  if (totalLength < 80) return false;
  if (bodyParagraphCount == 0 && totalLength < 200) return false;
  if (!hasSubstantialParagraph && bodyParagraphCount < 2 && totalLength < 160) {
    return false;
  }
  return true;
}

String libraryCleanVisibleMarginArtifacts(String value) {
  if (value.isEmpty) return value;

  // Only clean when the paragraph contains the obvious numbered artifact form.
  if (!RegExp(r'\b\d+\s+Margin\b', caseSensitive: false).hasMatch(value)) {
    return value;
  }

  final cleaned = value
      .replaceAll(RegExp(r'\b\d+\s+Margin\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\bMargin\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

bool _looksLikeMetadataParagraph(String paragraph) {
  final normalized = _normalizeLibraryText(paragraph);
  if (normalized.isEmpty) return true;

  if (RegExp(r'^\d+$').hasMatch(normalized)) return true;

  const exactMatches = <String>{
    'by',
    'copyright',
    'published at the advent review office',
    'published at the advent review and sabbath herald office',
    'published by',
    'printed by',
    'contents',
    'table of contents',
    'foreword',
    'preface',
    'introduction',
    'a word to the reader',
    'word to the reader',
    'questions for study',
    'footnotes',
    'appendix',
    'isbn',
  };
  if (exactMatches.contains(normalized)) return true;

  const prefixes = <String>[
    'by ',
    'copyright ',
    'published at ',
    'published by ',
    'printed by ',
    'contents ',
    'table of contents',
    'foreword ',
    'preface ',
    'introduction ',
    'a word to the reader',
    'word to the reader',
    'questions for study',
    'footnotes',
    'appendix ',
    'isbn',
  ];
  for (final prefix in prefixes) {
    if (normalized.startsWith(prefix)) return true;
  }

  if (normalized.contains('published at') ||
      normalized.contains('originally published') ||
      normalized.contains('original table of contents') ||
      normalized.contains('adventist pioneer library') ||
      normalized.contains('copyright') ||
      normalized.contains('frontispiece') ||
      normalized.contains('margin')) {
    return true;
  }

  if (normalized.length <= 24 &&
      RegExp(r'^[a-z0-9\s,.\-]+$').hasMatch(normalized)) {
    return true;
  }

  return false;
}

String _normalizeLibraryText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
