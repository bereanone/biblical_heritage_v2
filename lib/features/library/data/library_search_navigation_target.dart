class LibrarySearchNavigationTarget {
  const LibrarySearchNavigationTarget({
    required this.libraryItemId,
    required this.textBlockId,
    required this.href,
    required this.paragraphIndex,
    this.spineIndex,
    this.sectionTitle,
    this.paragraphOnSection,
    this.stableSourceReference,
    this.pageNumber,
    this.paragraphOnPage,
    this.query,
    this.matchedText,
    this.sourceWorkId,
    this.sourcePackageId,
  });

  final String libraryItemId;
  final int textBlockId;
  final String href;
  final int paragraphIndex;
  final int? spineIndex;
  final String? sectionTitle;
  final int? paragraphOnSection;
  final String? stableSourceReference;
  final int? pageNumber;
  final int? paragraphOnPage;
  final String? query;
  final String? matchedText;
  final String? sourceWorkId;
  final String? sourcePackageId;

  LibrarySearchNavigationTarget withQuery(String query) =>
      LibrarySearchNavigationTarget(
        libraryItemId: libraryItemId,
        textBlockId: textBlockId,
        href: href,
        paragraphIndex: paragraphIndex,
        spineIndex: spineIndex,
        sectionTitle: sectionTitle,
        paragraphOnSection: paragraphOnSection,
        stableSourceReference: stableSourceReference,
        pageNumber: pageNumber,
        paragraphOnPage: paragraphOnPage,
        query: query,
        matchedText: matchedText,
        sourceWorkId: sourceWorkId,
        sourcePackageId: sourcePackageId,
      );

  String get diagnosticSummary =>
      'work=$libraryItemId sourceWork=${sourceWorkId ?? "(none)"} '
      'sourcePackage=${sourcePackageId ?? "(none)"} '
      'section=${sectionTitle ?? href} block=$textBlockId '
      'paragraphIndex=$paragraphIndex page=${pageNumber ?? "(none)"} '
      'paragraph=${paragraphOnPage ?? paragraphOnSection ?? "(none)"} '
      'query=${query ?? "(none)"}';
}
