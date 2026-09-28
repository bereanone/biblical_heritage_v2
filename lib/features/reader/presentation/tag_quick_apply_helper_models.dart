part of 'tag_quick_apply_helper.dart';

const recentImportCategory = 'Recent Import';

class HashTagTarget {
  const HashTagTarget({
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.verseRef,
    this.verseEnd,
    this.tokenNumber,
  });

  final int bookNumber;
  final int chapter;
  final int verse;
  final String verseRef;
  final int? verseEnd;
  final int? tokenNumber;
}

class HashTagSummary {
  const HashTagSummary({required this.tag, required this.count, this.category});

  final String tag;
  final int count;
  final String? category;

  String get displayLabel {
    final categoryLabel = category?.trim() ?? '';
    if (categoryLabel.isEmpty) return tag;
    return '$tag · $categoryLabel';
  }

  String get identityKey {
    return tag.trim().toLowerCase();
  }
}

String buildTemporaryImportTagName(
  String normalizedTag, {
  int suffixIndex = 1,
}) {
  final cleaned = normalizedTag.trim();
  if (cleaned.isEmpty) return '';
  final stemMatch = RegExp(r'^(.*?)(?:-import(?:-\d+)?)?$').firstMatch(cleaned);
  final stem = (stemMatch?.group(1) ?? cleaned).trim();
  if (stem.isEmpty) return '';
  if (suffixIndex <= 1) {
    return '$stem-import';
  }
  return '$stem-import-$suffixIndex';
}

class HashTagEntry {
  const HashTagEntry({
    required this.id,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.verseEnd,
    required this.verseRef,
    required this.verseText,
    required this.createdAt,
    required this.sortOrder,
    this.isNormalized = false,
    this.presentationSlideNumber,
    this.presentationSlideRegion,
    this.userTitle,
    this.referenceCode,
    this.displayTextOverride,
    this.titleFormatJson,
    this.displayTextFormatJson,
    this.contentHtml,
    this.noteText,
    this.noteFormatJson,
    this.shareId,
    List<String>? mediaRefs,
  }) : mediaRefs = mediaRefs ?? const <String>[];

  final int id;
  final int bookNumber;
  final int chapter;
  final int verse;
  final int verseEnd;
  final String verseRef;
  final String verseText;
  final int createdAt;
  final int sortOrder;
  final bool isNormalized;
  final int? presentationSlideNumber;
  final PresentationItemPlacement? presentationSlideRegion;
  final String? userTitle;
  final String? referenceCode;
  final String? displayTextOverride;
  final String? titleFormatJson;
  final String? displayTextFormatJson;
  final String? contentHtml;
  final String? noteText;
  final String? noteFormatJson;
  final String? shareId;
  final List<String> mediaRefs;

  // Presentation-only labels: keep verseText unchanged for narration matching.
  String get numberedVerseText => formatBibleRangeForDisplay(
    verseText,
    verseStart: verse,
    verseEnd: verseEnd,
  );

  bool get hasMedia => mediaRefs.isNotEmpty;
}

enum HashTagEntrySortMode { slideOrder, verseOrder }

enum SharedListImportMode { separate, merge }

class SharedListImportPreview {
  const SharedListImportPreview({
    required this.tag,
    required this.itemCount,
    required this.hasExistingList,
  });

  final String tag;
  final int itemCount;
  final bool hasExistingList;
}

class HashTagQuickApplyResult {
  const HashTagQuickApplyResult({
    required this.tag,
    required this.inserted,
    required this.skipped,
  });

  final String? tag;
  final int inserted;
  final int skipped;
}

class HashTagResolvedTag {
  const HashTagResolvedTag({
    required this.tag,
    required this.createdDefaultTag,
  });

  final String tag;
  final bool createdDefaultTag;
}

class HashTagCategoryMergeResult {
  const HashTagCategoryMergeResult({
    required this.tag,
    required this.sourceCategory,
    required this.targetCategory,
    required this.sourceCount,
    required this.targetCount,
    required this.addedCount,
    required this.skippedCount,
    required this.sourceRemoved,
    required this.dryRun,
  });

  final String tag;
  final String? sourceCategory;
  final String targetCategory;
  final int sourceCount;
  final int targetCount;
  final int addedCount;
  final int skippedCount;
  final bool sourceRemoved;
  final bool dryRun;

  int get finalTargetCount => targetCount + addedCount;
}

class HashTagSearchQuickApplyResult {
  const HashTagSearchQuickApplyResult({
    required this.tag,
    required this.inserted,
    required this.skipped,
    required this.createdDefaultTag,
  });

  final String? tag;
  final int inserted;
  final int skipped;
  final bool createdDefaultTag;
}

class HashTagImportResult {
  const HashTagImportResult({
    required this.tag,
    required this.parsedCount,
    required this.insertedCount,
    required this.updatedExistingCount,
    required this.skippedExistingCount,
    required this.failedCount,
    required this.failures,
    this.bibleImportedCount = 0,
    this.eLibraryImportedCount = 0,
    this.noteImportedCount = 0,
    this.unsupportedCount = 0,
    this.warnings = const <String>[],
  });

  final String tag;
  final int parsedCount;
  final int insertedCount;
  final int updatedExistingCount;
  final int skippedExistingCount;
  final int failedCount;
  final List<HashTagImportFailure> failures;
  final int bibleImportedCount;
  final int eLibraryImportedCount;
  final int noteImportedCount;
  final int unsupportedCount;
  final List<String> warnings;

  int get importedCount => insertedCount;
}

class HashTagImportFailure {
  const HashTagImportFailure({
    required this.lineNumber,
    required this.reason,
    required this.line,
  });

  final int lineNumber;
  final String reason;
  final String line;
}

class HashTagTrashedEntry {
  const HashTagTrashedEntry({
    required this.numericId,
    required this.stableId,
    required this.isNormalized,
    required this.tagName,
    this.category,
    required this.reference,
    required this.previewText,
    this.trashedAt,
    this.trashedReason,
  });

  final int numericId;
  final String stableId;
  final bool isNormalized;
  final String tagName;
  final String? category;
  final String reference;
  final String previewText;
  final String? trashedAt;
  final String? trashedReason;

  String get tagContext {
    final cat = category?.trim() ?? '';
    return cat.isEmpty ? tagName : '$tagName · $cat';
  }
}

class _ParsedSharedList {
  const _ParsedSharedList({required this.tag, required this.slides});

  final String tag;
  final List<_ParsedSharedSlide> slides;
}

class _ParsedSharedSlide {
  const _ParsedSharedSlide({
    required this.target,
    required this.contentText,
    required this.noteRef,
    this.elibraryMetadata,
    this.studyBibleMetadata,
  });

  final HashTagTarget? target;
  final String contentText;
  final String noteRef;
  final Map<String, Object?>? elibraryMetadata;
  final Map<String, Object?>? studyBibleMetadata;
}

/// Formats canonical one-line-per-verse text without guessing missing boundaries.
String formatBibleRangeForDisplay(
  String text, {
  required int verseStart,
  required int verseEnd,
}) {
  final trimmed = text.trim();
  if (verseStart <= 0 || verseEnd <= verseStart) return trimmed;
  final verses = trimmed.split('\n').map((line) => line.trim()).toList();
  if (verses.length != verseEnd - verseStart + 1 ||
      verses.any((line) => line.isEmpty))
    return trimmed;
  return List.generate(
    verses.length,
    (index) => '${verseStart + index} ${verses[index]}',
  ).join('\n');
}
