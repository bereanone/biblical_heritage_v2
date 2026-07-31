import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'library_document_models.dart';
import 'library_search_navigation_target.dart';
import 'library_section_heuristics.dart';

class LibraryDocumentRepository {
  const LibraryDocumentRepository(this.db);
  final Database db;

  Future<bool> isComplete(String libraryItemId) async {
    final rows = await db.query(
      'library_document_conversion',
      columns: const <String>['status'],
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    return rows.isNotEmpty &&
        rows.first['status'] == 'complete' &&
        await blockCount(libraryItemId) > 0;
  }

  Future<bool> isCurrentComplete(
    String libraryItemId, {
    required int canonicalizerVersion,
  }) async {
    final rows = await db.query(
      'library_document_conversion',
      columns: const <String>['status', 'canonicalizer_version'],
      where: 'library_item_id = ?',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    return rows.isNotEmpty &&
        rows.first['status'] == 'complete' &&
        rows.first['canonicalizer_version'] == canonicalizerVersion &&
        await blockCount(libraryItemId) > 0;
  }

  /// Updates only the catalog title/author for an already-imported item —
  /// never touches canonical content, `source_work_id`, or anything in the
  /// separate user database. `null` leaves a field unchanged.
  Future<void> updateCatalogMetadata(
    String libraryItemId, {
    String? title,
    String? author,
  }) async {
    final values = <String, Object?>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (title != null) 'title': title,
      if (author != null) 'author': author,
    };
    await db.update(
      'library_items',
      values,
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
    );
  }

  Future<int> blockCount(String libraryItemId) async => _firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM library_document_blocks WHERE library_item_id = ?',
      <Object?>[libraryItemId],
    ),
  );

  Future<List<LibraryDocumentBlock>> loadWindow(
    String libraryItemId, {
    required int centerOrder,
    int radius = 50,
  }) async {
    final first = (centerOrder - radius).clamp(0, 1 << 30);
    final last = centerOrder + radius;
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND display_order BETWEEN ? AND ?',
      whereArgs: <Object?>[libraryItemId, first, last],
      orderBy: 'display_order ASC',
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  Future<List<LibraryDocumentBlock>> loadHeadings(String libraryItemId) async {
    final rows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order ASC',
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  Future<List<LibraryDocumentBlock>> searchCurrentBook(
    String libraryItemId,
    String query,
  ) async {
    final term = query.trim();
    if (term.isEmpty) return const <LibraryDocumentBlock>[];
    final escaped = term
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final rows = await db.rawQuery(
      '''
      SELECT * FROM library_document_blocks
      WHERE library_item_id = ?
        AND plain_text LIKE ? ESCAPE '\\'
      ORDER BY display_order ASC
      ''',
      <Object?>[libraryItemId, '%$escaped%'],
    );
    return rows.map(LibraryDocumentBlock.fromRow).toList(growable: false);
  }

  Future<int?> displayOrderForBlock(
    String libraryItemId,
    String blockId,
  ) async {
    final rows = await db.query(
      'library_document_blocks',
      columns: const <String>['display_order'],
      where: 'library_item_id = ? AND id = ?',
      whereArgs: <Object?>[libraryItemId, blockId],
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['display_order'] as num).toInt();
  }

  /// Returns the first substantive canonical block while leaving all front
  /// matter in the document and Contents tree.
  Future<int?> openingDisplayOrder(
    String libraryItemId, {
    String? bookTitle,
  }) async {
    final headingRows = await db.query(
      'library_document_blocks',
      columns: const <String>['display_order', 'plain_text', 'source_href'],
      where: 'library_item_id = ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order ASC',
    );
    for (final heading in headingRows) {
      final label = heading['plain_text']?.toString() ?? '';
      final href = heading['source_href']?.toString() ?? '';
      if (libraryIsFrontMatterOpeningLabel(label) ||
          libraryIsFrontMatterOpeningLabel(href)) {
        continue;
      }
      final normalized = label
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      if (RegExp(
        r'^(?:chapter|article|sermon|part) (?:1|i|one)(?: |$)',
      ).hasMatch(normalized)) {
        return (heading['display_order'] as num?)?.toInt();
      }
    }

    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.title, s.source_href, MIN(b.display_order) AS first_order
      FROM library_document_sections s
      JOIN library_document_blocks b
        ON b.library_item_id = s.library_item_id AND b.section_id = s.id
      WHERE s.library_item_id = ?
      GROUP BY s.id, s.display_order
      ORDER BY s.display_order ASC
      ''',
      <Object?>[libraryItemId],
    );
    for (final row in rows) {
      final sectionId = row['id']?.toString() ?? '';
      final title = row['title']?.toString() ?? '';
      final href = row['source_href']?.toString() ?? '';
      if (libraryIsFrontMatterOpeningLabel(title) ||
          libraryIsFrontMatterOpeningLabel(href)) {
        continue;
      }
      final blockRows = await db.query(
        'library_document_blocks',
        columns: const <String>['display_order', 'block_type', 'plain_text'],
        where: 'library_item_id = ? AND section_id = ?',
        whereArgs: <Object?>[libraryItemId, sectionId],
        orderBy: 'display_order ASC',
      );
      final paragraphs = blockRows
          .map((block) => block['plain_text']?.toString() ?? '')
          .toList(growable: false);
      if (libraryIsMeaningfulReadingSection(
        title: title,
        href: href,
        paragraphs: paragraphs,
        bookTitle: bookTitle,
      )) {
        for (final block in blockRows) {
          if (block['block_type'] != LibraryDocumentBlockType.heading.name) {
            continue;
          }
          final heading = block['plain_text']?.toString() ?? '';
          if (!libraryIsFrontMatterOpeningLabel(heading)) {
            return (block['display_order'] as num?)?.toInt();
          }
        }
        return (row['first_order'] as num?)?.toInt();
      }
    }
    return null;
  }

  Future<bool> containsDisplayOrder(
    String libraryItemId,
    int displayOrder,
  ) async {
    final rows = await db.query(
      'library_document_blocks',
      columns: const <String>['id'],
      where: 'library_item_id = ? AND display_order = ?',
      whereArgs: <Object?>[libraryItemId, displayOrder],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int?> displayOrderForSearchTarget(
    LibrarySearchNavigationTarget target,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT b.display_order
      FROM library_block_source_map sm
      INNER JOIN library_document_blocks b
        ON b.library_item_id = sm.library_item_id
        AND b.id = sm.block_id
      WHERE sm.library_item_id = ?
        AND LOWER(COALESCE(sm.source_href, '')) = LOWER(?)
        AND sm.legacy_paragraph_index = ?
      LIMIT 1
      ''',
      <Object?>[
        target.libraryItemId,
        target.href,
        target.paragraphOnSection ?? target.paragraphIndex,
      ],
    );
    return rows.isEmpty ? null : (rows.first['display_order'] as num?)?.toInt();
  }

  Future<LibraryDocumentLocation?> resolveLocation(
    String libraryItemId,
    int displayOrder,
  ) async {
    final blocks = await db.rawQuery(
      '''
      SELECT b.*, s.title AS section_title
      FROM library_document_blocks b
      JOIN library_document_sections s ON s.id = b.section_id
      WHERE b.library_item_id = ? AND b.display_order = ? LIMIT 1
    ''',
      <Object?>[libraryItemId, displayOrder],
    );
    if (blocks.isEmpty) return null;
    final block = LibraryDocumentBlock.fromRow(blocks.first);
    final headingRows = await db.query(
      'library_document_blocks',
      where: 'library_item_id = ? AND display_order <= ? AND block_type = ?',
      whereArgs: <Object?>[
        libraryItemId,
        displayOrder,
        LibraryDocumentBlockType.heading.name,
      ],
      orderBy: 'display_order DESC',
    );
    final headings = headingRows.map(LibraryDocumentBlock.fromRow).toList();
    final primary = headings.where(
      (heading) => heading.isPrimaryChapterHeading,
    );
    final selectedHeading = primary.isNotEmpty
        ? primary.first
        : headings.firstOrNull;
    final secondary = headings.where(
      (heading) =>
          heading.headingRole == 'section' || heading.headingRole == 'minor',
    );
    return LibraryDocumentLocation(
      block: block,
      sectionTitle: blocks.first['section_title']?.toString(),
      heading: selectedHeading,
      renderedHeading: headings.firstOrNull,
      secondaryHeading: secondary.firstOrNull,
    );
  }
}

int _firstIntValue(List<Map<String, Object?>> rows) =>
    rows.isEmpty ? 0 : (rows.first.values.first as num?)?.toInt() ?? 0;
