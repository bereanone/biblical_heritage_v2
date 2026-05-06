class CommentaryResearchPassageData {
  const CommentaryResearchPassageData({
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.bookName,
    required this.rootPath,
    required this.commentaryFolderPath,
    required this.researchFolderPath,
    required this.commentary,
    required this.research,
    required this.indexReportPath,
  });

  final int bookId;
  final int chapter;
  final int verse;
  final String bookName;
  final String? rootPath;
  final String? commentaryFolderPath;
  final String? researchFolderPath;
  final CommentaryResearchSectionData commentary;
  final CommentaryResearchSectionData research;
  final String? indexReportPath;
}

class CommentaryResearchSectionData {
  const CommentaryResearchSectionData({
    required this.folderType,
    required this.title,
    required this.statusMessage,
    required this.files,
    required this.matches,
    required this.discoveredCount,
    required this.indexedCount,
    required this.matchCount,
  });

  final String folderType;
  final String title;
  final String statusMessage;
  final List<CommentaryResearchFileItem> files;
  final List<CommentaryResearchMatchItem> matches;
  final int discoveredCount;
  final int indexedCount;
  final int matchCount;
}

class CommentaryResearchFileItem {
  const CommentaryResearchFileItem({
    required this.id,
    required this.title,
    required this.fileName,
    required this.relativePath,
    required this.fileSize,
    required this.indexed,
  });

  final String id;
  final String title;
  final String fileName;
  final String relativePath;
  final int fileSize;
  final bool indexed;
}

class CommentaryResearchMatchItem {
  const CommentaryResearchMatchItem({
    required this.libraryItemId,
    required this.itemTitle,
    required this.fileName,
    required this.relativePath,
    required this.originalReferenceText,
    required this.bookId,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.confidence,
    required this.anchor,
    this.fullParagraph,
    required this.parserWarning,
    this.epubCfi,
    this.epubHref,
    this.anchorId,
    this.spineIndex,
    this.paragraphIndex,
    this.sourceUrl,
  });

  final String libraryItemId;
  final String itemTitle;
  final String fileName;
  final String relativePath;
  final String originalReferenceText;
  final int bookId;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final double confidence;
  final String? anchor;
  final String? fullParagraph;
  final String? parserWarning;
  final String? epubCfi;
  final String? epubHref;
  final String? anchorId;
  final int? spineIndex;
  final int? paragraphIndex;
  final String? sourceUrl;
}

class CommentaryResearchNavigationItem {
  const CommentaryResearchNavigationItem({
    required this.id,
    required this.libraryItemId,
    required this.parentId,
    required this.label,
    required this.href,
    required this.anchorId,
    required this.spineIndex,
    required this.sortOrder,
    required this.depth,
    required this.navType,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String libraryItemId;
  final String? parentId;
  final String label;
  final String? href;
  final String? anchorId;
  final int? spineIndex;
  final int? sortOrder;
  final int? depth;
  final String? navType;
  final String createdAt;
  final String updatedAt;
}

class CommentaryResearchEpubBookData {
  const CommentaryResearchEpubBookData({
    required this.libraryItemId,
    required this.title,
    required this.relativePath,
    required this.navigationItems,
    required this.currentHref,
    required this.currentAnchorId,
    required this.currentLabel,
    required this.currentText,
  });

  final String libraryItemId;
  final String title;
  final String relativePath;
  final List<CommentaryResearchNavigationItem> navigationItems;
  final String? currentHref;
  final String? currentAnchorId;
  final String currentLabel;
  final String currentText;
}
