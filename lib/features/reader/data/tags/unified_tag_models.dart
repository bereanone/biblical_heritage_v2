enum UnifiedTagStorageKind { hash, dollar, unified, unknownLegacy }

enum UnifiedTagSourceType {
  bible,
  bibleRange,
  eLibrary,
  note,
  image,
  media,
  heading,
  unknownLegacy,
}

enum UnifiedTagItemType {
  bibleVerse,
  bibleRange,
  eLibraryRange,
  note,
  image,
  media,
  heading,
  unknownLegacy,
}

class UnifiedTagReadSnapshot {
  const UnifiedTagReadSnapshot({required this.chains, required this.loadedAt});

  final List<UnifiedTagChain> chains;
  final DateTime loadedAt;

  Map<String, UnifiedTagChain> get chainsById {
    return {for (final chain in chains) chain.id: chain};
  }
}

class UnifiedTagChain {
  const UnifiedTagChain({
    required this.id,
    required this.name,
    required this.storageKind,
    required this.items,
    this.categoryId,
    this.categoryName,
    this.isDefault = false,
    this.legacyTable,
    this.legacyTagName,
    this.legacyTagId,
    this.legacyGroupId,
    this.legacyImportPackageId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.rawFields = const <String, Object?>{},
  });

  final String id;
  final String name;
  final UnifiedTagStorageKind storageKind;
  final String? categoryId;
  final String? categoryName;
  final bool isDefault;
  final String? legacyTable;
  final String? legacyTagName;
  final String? legacyTagId;
  final String? legacyGroupId;
  final String? legacyImportPackageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final Map<String, Object?> rawFields;
  final List<UnifiedTagChainItem> items;

  bool get isDeleted => deletedAt != null;
}

class UnifiedTagChainItem {
  const UnifiedTagChainItem({
    required this.id,
    required this.chainId,
    required this.storageKind,
    required this.sourceType,
    required this.itemType,
    required this.sortOrder,
    this.displayTitle,
    this.textSnapshot,
    this.noteText,
    this.htmlContent,
    this.media = const <UnifiedTagMedia>[],
    this.bibleAnchor,
    this.elibraryAnchor,
    this.layoutHint,
    this.legacyTable,
    this.legacyTagName,
    this.legacyTagId,
    this.legacyItemId,
    this.legacyGroupId,
    this.legacyImportPackageId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.rawFields = const <String, Object?>{},
  });

  final String id;
  final String chainId;
  final UnifiedTagStorageKind storageKind;
  final UnifiedTagSourceType sourceType;
  final UnifiedTagItemType itemType;
  final int sortOrder;
  final String? displayTitle;
  final String? textSnapshot;
  final String? noteText;
  final String? htmlContent;
  final List<UnifiedTagMedia> media;
  final UnifiedTagBibleAnchor? bibleAnchor;
  final UnifiedTagELibraryAnchor? elibraryAnchor;
  final UnifiedTagLayoutHint? layoutHint;
  final String? legacyTable;
  final String? legacyTagName;
  final String? legacyTagId;
  final String? legacyItemId;
  final String? legacyGroupId;
  final String? legacyImportPackageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final Map<String, Object?> rawFields;

  bool get isDeleted => deletedAt != null;
  bool get hasMedia => media.isNotEmpty;
}

class UnifiedTagMedia {
  const UnifiedTagMedia({
    required this.id,
    required this.itemId,
    required this.relativePath,
    required this.mediaType,
    required this.sortOrder,
    this.caption,
    this.fileHash,
    this.fileSize,
    this.width,
    this.height,
    this.legacyTable,
    this.legacyTagName,
    this.legacyTagId,
    this.legacyItemId,
    this.legacyImportPackageId,
    this.createdAt,
    this.updatedAt,
    this.deletedAt,
    this.rawFields = const <String, Object?>{},
  });

  final String id;
  final String itemId;
  final String relativePath;
  final String mediaType;
  final int sortOrder;
  final String? caption;
  final String? fileHash;
  final int? fileSize;
  final int? width;
  final int? height;
  final String? legacyTable;
  final String? legacyTagName;
  final String? legacyTagId;
  final String? legacyItemId;
  final String? legacyImportPackageId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final Map<String, Object?> rawFields;

  bool get isDeleted => deletedAt != null;
}

class UnifiedTagBibleAnchor {
  const UnifiedTagBibleAnchor({
    required this.bookNumber,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    this.tokenStart,
    this.tokenEnd,
    this.verseRef,
    this.referenceCode,
    this.rawFields = const <String, Object?>{},
  });

  final int bookNumber;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final int? tokenStart;
  final int? tokenEnd;
  final String? verseRef;
  final String? referenceCode;
  final Map<String, Object?> rawFields;

  bool get isRange => verseEnd > verseStart;
}

extension UnifiedTagBibleAnchorDisplay on UnifiedTagBibleAnchor {
  String displayReference(Map<int, String> bookNames) {
    final bookName = bookNames[bookNumber]?.trim() ?? '';
    final resolvedBookName = bookName.isNotEmpty
        ? bookName
        : 'Book $bookNumber';
    final verseLabel = verseEnd > verseStart
        ? '$verseStart-$verseEnd'
        : '$verseStart';
    return '$resolvedBookName $chapter:$verseLabel';
  }
}

class UnifiedTagELibraryAnchor {
  const UnifiedTagELibraryAnchor({
    required this.compactRef,
    this.sourceTitle,
    this.sourceTitleAcronym,
    this.sourceLocation,
    this.sourceReferenceText,
    this.sourceHref,
    this.sourceAnchorId,
    this.sourceSpineIndex,
    this.sourceParagraphIndex,
    this.sourceRelativePath,
    this.sourceLibraryItemId,
    this.selectedTextSnapshot,
    this.selectionStartBlockIndex,
    this.selectionStartCharOffset,
    this.selectionEndBlockIndex,
    this.selectionEndCharOffset,
    this.selectionStartTokenIndex,
    this.selectionEndTokenIndex,
    this.sourcePageNumber,
    this.sourceParagraphNumber,
    this.searchQuery,
    this.sourceParagraph,
    this.excerpt,
    this.stableRef,
    this.rawFields = const <String, Object?>{},
  });

  final String compactRef;
  final String? sourceTitle;
  final String? sourceTitleAcronym;
  final String? sourceLocation;
  final String? sourceReferenceText;
  final String? sourceHref;
  final String? sourceAnchorId;
  final int? sourceSpineIndex;
  final int? sourceParagraphIndex;
  final String? sourceRelativePath;
  final String? sourceLibraryItemId;
  final String? selectedTextSnapshot;
  final int? selectionStartBlockIndex;
  final int? selectionStartCharOffset;
  final int? selectionEndBlockIndex;
  final int? selectionEndCharOffset;
  final int? selectionStartTokenIndex;
  final int? selectionEndTokenIndex;
  final int? sourcePageNumber;
  final int? sourceParagraphNumber;
  final String? searchQuery;
  final String? sourceParagraph;
  final String? excerpt;
  final String? stableRef;
  final Map<String, Object?> rawFields;
}

class UnifiedTagLayoutHint {
  const UnifiedTagLayoutHint({
    this.layoutKey,
    this.presentationSlideNumber,
    this.presentationSlideRegion,
    this.zone,
    this.rowOrder,
    this.columnOrder,
    this.widthWeight,
    this.heightWeight,
    this.zOrder,
    this.rawFields = const <String, Object?>{},
  });

  final String? layoutKey;
  final int? presentationSlideNumber;
  final String? presentationSlideRegion;
  final String? zone;
  final int? rowOrder;
  final int? columnOrder;
  final double? widthWeight;
  final double? heightWeight;
  final int? zOrder;
  final Map<String, Object?> rawFields;
}
