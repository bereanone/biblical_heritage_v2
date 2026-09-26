import '../data/library_catalog_service.dart';
import '../data/library_document_models.dart';
import '../data/library_document_repository.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';

String canonicalSelectionReference(
  LibraryCatalogItem item,
  LibraryDocumentBlock block,
) {
  final reference = block.visibleReference?.trim() ?? '';
  return reference.isEmpty ? item.displayTitle : reference;
}

Future<HashTagQuickApplyResult> saveCanonicalSelectionToTag({
  required LibraryDocumentRepository repository,
  required HashTagRepository tags,
  required LibraryCatalogItem item,
  required LibraryDocumentBlock block,
  required int start,
  required int end,
  required String tag,
}) async {
  if (block.libraryItemId != item.id ||
      start < 0 ||
      end > block.plainText.length ||
      end <= start) {
    throw const FormatException('Invalid selected range');
  }
  // Use the authored source mapping, never the canonical display order as a
  // legacy paragraph number. The selected excerpt and reference remain stored
  // even if its source later becomes unavailable.
  final sources = await repository.db.query(
    'library_block_source_map',
    where: 'library_item_id = ? AND block_id = ?',
    whereArgs: [item.id, block.id],
  );
  final source = sources.isEmpty ? null : sources.single;
  final text = block.plainText.substring(start, end);
  final reference = canonicalSelectionReference(item, block);
  final result = await tags.quickApplyELibrarySearchResult(
    bookTitle: item.displayTitle,
    locationText: reference,
    paragraphText: text,
    stableRef:
        'elibrary-canonical-range:${item.id}:${block.id}:${block.contentHash}:$start:$end',
    referenceText: reference,
    sourceHref: source?['source_href']?.toString() ?? block.sourceHref,
    sourceAnchorId: source?['source_anchor']?.toString() ?? block.sourceAnchor,
    sourceParagraphIndex: (source?['legacy_paragraph_index'] as num?)?.toInt(),
    sourceRelativePath: item.relativePath,
    sourceLibraryItemId: item.id,
    selectedTextSnapshot: text,
    selectionStartCharOffset: start,
    selectionEndCharOffset: end,
    tag: tag,
  );
  return HashTagQuickApplyResult(
    tag: result.tag,
    inserted: result.inserted,
    skipped: result.skipped,
  );
}
