import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'library_document_models.dart';

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
