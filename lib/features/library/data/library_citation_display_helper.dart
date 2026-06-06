import 'package:path/path.dart' as p;

String? librarySafeUserFacingReferenceText(String? value) {
  final cleaned = (value ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return null;
  final lower = cleaned.toLowerCase();
  if (_looksLikeInternalLocator(lower) ||
      lower.startsWith('note:') ||
      lower == 'book 0 0:0') {
    return null;
  }
  return cleaned;
}

String? libraryUserFacingBookAbbreviation({
  required String title,
  String? fileName,
  String? relativePath,
}) {
  final fromTitle = _looksLikeInternalLocator(title)
      ? null
      : _libraryAbbreviationFromTitle(title);
  if (fromTitle != null) return fromTitle;

  final fromFileName = _looksLikeInternalLocator(fileName)
      ? null
      : _libraryAbbreviationFromPathSegment(fileName);
  if (fromFileName != null) return fromFileName;

  final fromRelativePath = _looksLikeInternalLocator(relativePath)
      ? null
      : _libraryAbbreviationFromPathSegment(relativePath);
  if (fromRelativePath != null) return fromRelativePath;

  return null;
}

String libraryUserFacingSearchLocationText({
  required String title,
  String? officialReferenceText,
  String? fileName,
  String? relativePath,
  String? pageCitation,
  int? chapterNumber,
  int? paragraphIndex,
}) {
  final safeReference = librarySafeUserFacingReferenceText(
    officialReferenceText,
  );
  if (safeReference != null) return safeReference;

  final abbreviation = libraryUserFacingBookAbbreviation(
    title: title,
    fileName: fileName,
    relativePath: relativePath,
  );
  final cleanTitle = title.trim();
  final cleanPageCitation = pageCitation?.trim() ?? '';

  if (abbreviation != null) {
    if (cleanPageCitation.isNotEmpty) {
      return '$abbreviation $cleanPageCitation';
    }
    if (paragraphIndex != null && paragraphIndex > 0) {
      return '$abbreviation ¶$paragraphIndex';
    }
    if (chapterNumber != null && chapterNumber > 0) {
      return '$abbreviation ch. $chapterNumber';
    }
    return abbreviation;
  }

  if (cleanTitle.isNotEmpty) {
    if (cleanPageCitation.isNotEmpty) {
      return '$cleanTitle $cleanPageCitation';
    }
    if (paragraphIndex != null && paragraphIndex > 0) {
      return '$cleanTitle ¶$paragraphIndex';
    }
    if (chapterNumber != null && chapterNumber > 0) {
      return '$cleanTitle ch. $chapterNumber';
    }
    return cleanTitle;
  }

  if (cleanPageCitation.isNotEmpty) {
    return cleanPageCitation;
  }
  if (paragraphIndex != null && paragraphIndex > 0) {
    return '¶$paragraphIndex';
  }
  if (chapterNumber != null && chapterNumber > 0) {
    return 'ch. $chapterNumber';
  }
  return '';
}

String libraryUserFacingELibraryCitationText({
  required String sourceTitle,
  String? sourceTitleAcronym,
  String? sourceLocation,
  String? sourceReferenceText,
  String? fileName,
  String? relativePath,
  String? pageCitation,
  int? paragraphIndex,
}) {
  final safeReference = librarySafeUserFacingReferenceText(sourceReferenceText);
  if (safeReference != null) return safeReference;

  final safeLocation = librarySafeUserFacingReferenceText(sourceLocation);
  if (safeLocation != null) return safeLocation;

  final abbreviation =
      _libraryAbbreviationFromText(sourceTitleAcronym) ??
      libraryUserFacingBookAbbreviation(
        title: sourceTitle,
        fileName: fileName,
        relativePath: relativePath,
      );

  final cleanPageCitation = pageCitation?.trim() ?? '';
  if (abbreviation != null && cleanPageCitation.isNotEmpty) {
    return '$abbreviation $cleanPageCitation';
  }
  if (abbreviation != null && paragraphIndex != null && paragraphIndex > 0) {
    return '$abbreviation ¶$paragraphIndex';
  }
  if (cleanPageCitation.isNotEmpty) return cleanPageCitation;
  if (paragraphIndex != null && paragraphIndex > 0) return '¶$paragraphIndex';

  return '';
}

String libraryUserFacingELibraryDisplayLabel({
  required String sourceTitle,
  String? sourceTitleAcronym,
  String? sourceLocation,
  String? sourceReferenceText,
  String? fileName,
  String? relativePath,
  String? pageCitation,
  int? paragraphIndex,
}) {
  final cleanTitle = librarySafeUserFacingReferenceText(sourceTitle) ?? '';
  final citation = libraryUserFacingELibraryCitationText(
    sourceTitle: sourceTitle,
    sourceTitleAcronym: sourceTitleAcronym,
    sourceLocation: sourceLocation,
    sourceReferenceText: sourceReferenceText,
    fileName: fileName,
    relativePath: relativePath,
    pageCitation: pageCitation,
    paragraphIndex: paragraphIndex,
  );

  if (cleanTitle.isNotEmpty && citation.isNotEmpty) {
    final lowerTitle = cleanTitle.toLowerCase();
    final lowerCitation = citation.toLowerCase();
    if (lowerCitation == lowerTitle ||
        lowerCitation.startsWith('$lowerTitle — ') ||
        lowerCitation.startsWith('$lowerTitle ')) {
      return citation;
    }
    return '$cleanTitle — $citation';
  }
  if (citation.isNotEmpty) return citation;
  if (cleanTitle.isNotEmpty) return cleanTitle;

  final abbreviation =
      _libraryAbbreviationFromText(sourceTitleAcronym) ??
      libraryUserFacingBookAbbreviation(
        title: sourceTitle,
        fileName: fileName,
        relativePath: relativePath,
      );
  if (abbreviation != null) return abbreviation;

  return 'eLibrary Quote';
}

String? _libraryAbbreviationFromTitle(String value) {
  final normalized = _normalizeLibraryText(value);
  if (normalized.isEmpty) return null;

  const rules = <({String needle, String code})>[
    (needle: 'the great controversy 1888', code: 'GC88'),
    (needle: 'the great controversy', code: 'GC'),
    (needle: 'desire of ages', code: 'DA'),
    (needle: 'christ triumphant', code: 'CTr'),
    (needle: 'conflict and courage', code: 'CC'),
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
    (needle: 'our high calling', code: 'OHC'),
    (needle: 'in heavenly places', code: 'HP'),
    (needle: 'lift him up', code: 'LHU'),
    (needle: 'my life today', code: 'ML'),
    (needle: 'sons and daughters of god', code: 'SD'),
    (needle: 'this day with god', code: 'TDG'),
    (needle: 'reflecting christ', code: 'RC'),
    (needle: 'god s amazing grace', code: 'AG'),
    (needle: 'ye shall receive power', code: 'YRP'),
    (needle: 'from the heart', code: 'FH'),
    (needle: 'to be like jesus', code: 'BLJ'),
    (needle: 'with god at dawn', code: 'WGD'),
    (needle: 'our father cares', code: 'OFC'),
    (needle: 'maranatha', code: 'Mar'),
    (needle: 'radiant religion', code: 'RRe'),
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

String? _libraryAbbreviationFromPathSegment(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) return null;
  var stem = p.basenameWithoutExtension(input).trim();
  if (stem.isEmpty) return null;

  // Strip leading lowercase language prefix (e.g. "en_", "es_", "fr_") so it
  // never leaks into the generated code.
  stem = stem.replaceFirst(RegExp(r'^[a-z]{2,3}_'), '');
  if (stem.isEmpty) return null;

  // Split on underscores and whitespace only — hyphens are preserved so that
  // compound codes like "SHM-APX" survive as a single token.
  final tokens = stem
      .split(RegExp(r'[_\s]+'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  for (final token in tokens.reversed) {
    final upper = token.toUpperCase();
    final isSimple = RegExp(r'^[A-Z0-9]{2,8}$').hasMatch(upper);
    final isHyphenated = RegExp(
      r'^[A-Z0-9]{2,8}(?:-[A-Z0-9]{2,8})+$',
    ).hasMatch(upper);
    if (!isSimple && !isHyphenated) continue;
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

String? _libraryAbbreviationFromText(String? value) {
  final cleaned = librarySafeUserFacingReferenceText(value);
  if (cleaned == null) return null;
  final normalized = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized.isEmpty ? null : normalized;
}

bool _looksLikeInternalLocator(String? value) {
  final cleaned = (value ?? '').trim();
  if (cleaned.isEmpty) return false;
  final lower = cleaned.toLowerCase();
  if (lower.startsWith('elibrary-range:') ||
      lower.startsWith('elibrary:') ||
      lower.contains('library_item_') ||
      lower.contains('compactref') ||
      lower.contains('oebps/') ||
      RegExp(r'content\d+(?:\.xhtml)?', caseSensitive: false).hasMatch(lower) ||
      lower.contains('.xhtml')) {
    return true;
  }
  if (RegExp(
    r'(?<!\w)\d+:\d+:\d+(?:-\d+)?(?::\d+)?(?!\w)',
  ).hasMatch(lower)) {
    return true;
  }
  return false;
}

String _normalizeLibraryText(String? value) {
  return (value ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
