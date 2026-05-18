part of 'library_catalog_service.dart';

String _buildLibraryTextBlockLocationText({
  required LibraryCatalogItem item,
  String? refCode,
  required String? sectionTitle,
  required int? paragraphOnSection,
}) {
  // Priority A: use a verified EGW ref code (e.g. "GC 435.2") when available.
  final safeRefCode = librarySafeUserFacingReferenceText(refCode);
  if (safeRefCode != null) return safeRefCode;

  final cleanSection = sectionTitle?.trim() ?? '';
  final parNum = paragraphOnSection ?? 0;

  if (item.isPeriodical) {
    final abbreviation = libraryUserFacingBookAbbreviation(
      title: item.displayTitle,
      fileName: item.fileName,
      relativePath: item.relativePath,
    );
    if (abbreviation != null) {
      if (cleanSection.isNotEmpty && parNum > 0) {
        return '$abbreviation $cleanSection, par. $parNum';
      }
      if (cleanSection.isNotEmpty) return '$abbreviation $cleanSection';
      if (parNum > 0) return '$abbreviation par. $parNum';
      return abbreviation;
    }
  }

  if (cleanSection.isNotEmpty && parNum > 0) {
    // Truncate long section titles so the trailing ", par. N" is never clipped
    // by the single-line overflow in the search result list tile.
    final displaySection = cleanSection.length > 38
        ? '${cleanSection.substring(0, 37)}…'
        : cleanSection;
    return '$displaySection, par. $parNum';
  }
  if (cleanSection.isNotEmpty) return cleanSection;
  if (parNum > 0) return 'par. $parNum';
  return '';
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

int _scoreLibrarySearchResult({
  required LibraryCatalogItem item,
  required String? referenceText,
  required String? fullParagraph,
  required List<String> queryTerms,
}) {
  final title = _normalizedLibraryText(item.displayTitle);
  final author = _normalizedLibraryText(item.displayAuthor);
  final reference = _normalizedLibraryText(referenceText);
  final paragraph = _normalizedLibrarySearchText(fullParagraph ?? '');

  var bestScore = 6;
  for (final term in queryTerms) {
    final normalizedTerm = _normalizedLibrarySearchText(term);
    if (normalizedTerm.isEmpty) continue;
    var termScore = 5;
    if (paragraph.contains(normalizedTerm)) {
      termScore = 0;
    } else if (reference.contains(normalizedTerm)) {
      termScore = 1;
    } else if (title.contains(normalizedTerm)) {
      termScore = 2;
    } else if (author.contains(normalizedTerm)) {
      termScore = 3;
    }
    if (termScore < bestScore) {
      bestScore = termScore;
    }
  }
  return bestScore;
}
