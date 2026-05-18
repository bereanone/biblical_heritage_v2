enum TagMode { quick, studyList }

enum TagItemKind { verseReference, selectedText, noteOnly }

enum TagAnchorKind { verseReference, selectedText, noteOnly }

class TagSyncMetadata {
  const TagSyncMetadata({
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.deviceId,
    this.revision = 1,
    this.syncStatus = 'pending',
    this.lastSyncedAt,
    this.changeId,
  });

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;
  final int revision;
  final String syncStatus;
  final DateTime? lastSyncedAt;
  final String? changeId;

  bool get isDeleted => deletedAt != null;
}

class TagImportSource {
  const TagImportSource({
    required this.legacyTable,
    this.legacyRowId,
    this.legacyTag,
    this.legacyCategory,
    this.legacyImportPackageId,
    this.deviceId,
    this.sourceDeviceName,
    this.importedAt,
  });

  final String legacyTable;
  final String? legacyRowId;
  final String? legacyTag;
  final String? legacyCategory;
  final String? legacyImportPackageId;
  final String? deviceId;
  final String? sourceDeviceName;
  final DateTime? importedAt;
}

class TagAnchor {
  const TagAnchor._({
    required this.kind,
    this.bookNumber,
    this.chapter,
    this.verseStart,
    this.verseEnd,
    this.tokenStart,
    this.tokenEnd,
    this.verseRef,
    this.selectedText,
  });

  const TagAnchor.verseReference({
    required int bookNumber,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    int? tokenStart,
    int? tokenEnd,
    String? verseRef,
  }) : this._(
         kind: TagAnchorKind.verseReference,
         bookNumber: bookNumber,
         chapter: chapter,
         verseStart: verseStart,
         verseEnd: verseEnd ?? verseStart,
         tokenStart: tokenStart,
         tokenEnd: tokenEnd,
         verseRef: verseRef,
       );

  const TagAnchor.selectedText({
    required int bookNumber,
    required int chapter,
    required int verseStart,
    int? verseEnd,
    int? tokenStart,
    int? tokenEnd,
    String? verseRef,
    String? selectedText,
  }) : this._(
         kind: TagAnchorKind.selectedText,
         bookNumber: bookNumber,
         chapter: chapter,
         verseStart: verseStart,
         verseEnd: verseEnd ?? verseStart,
         tokenStart: tokenStart,
         tokenEnd: tokenEnd,
         verseRef: verseRef,
         selectedText: selectedText,
       );

  const TagAnchor.noteOnly({
    this.verseRef,
    this.selectedText,
  }) : kind = TagAnchorKind.noteOnly,
       bookNumber = null,
       chapter = null,
       verseStart = null,
       verseEnd = null,
       tokenStart = null,
       tokenEnd = null;

  final TagAnchorKind kind;
  final int? bookNumber;
  final int? chapter;
  final int? verseStart;
  final int? verseEnd;
  final int? tokenStart;
  final int? tokenEnd;
  final String? verseRef;
  final String? selectedText;

  bool get isNoteOnly => kind == TagAnchorKind.noteOnly;
}

class TagItemMedia {
  const TagItemMedia({
    required this.id,
    required this.itemId,
    required this.mediaType,
    required this.relativePath,
    required this.sortOrder,
    this.caption,
    this.fileHash,
    this.fileSize,
    this.sync,
    this.source,
  });

  final String id;
  final String itemId;
  final String mediaType;
  final String relativePath;
  final String? caption;
  final String? fileHash;
  final int? fileSize;
  final int sortOrder;
  final TagSyncMetadata? sync;
  final TagImportSource? source;
}

class TagItem {
  const TagItem({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.anchor,
    required this.sortOrder,
    this.noteText,
    this.sync,
    this.source,
  });

  final String id;
  final String groupId;
  final TagItemKind kind;
  final TagAnchor anchor;
  final String? noteText;
  final int sortOrder;
  final TagSyncMetadata? sync;
  final TagImportSource? source;

  bool get isDeleted => sync?.isDeleted == true;
}

class TagGroup {
  const TagGroup({
    required this.id,
    required this.mode,
    required this.name,
    required this.sortOrder,
    this.parentGroupId,
    this.description,
    this.isCategoryGroup = false,
    this.isDefault = false,
    this.sync,
    this.source,
  });

  final String id;
  final TagMode mode;
  final String name;
  final String? description;
  final String? parentGroupId;
  final int sortOrder;
  final bool isCategoryGroup;
  final bool isDefault;
  final TagSyncMetadata? sync;
  final TagImportSource? source;

  bool get isDeleted => sync?.isDeleted == true;
}
