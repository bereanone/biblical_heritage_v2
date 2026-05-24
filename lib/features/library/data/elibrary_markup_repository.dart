import '../../../core/database/user_database.dart';

class ElibraryMarkupRecord {
  const ElibraryMarkupRecord({
    required this.id,
    required this.libraryItemId,
    required this.epubHref,
    required this.startBlockIndex,
    required this.startCharOffset,
    required this.endBlockIndex,
    required this.endCharOffset,
    required this.selectedTextSnapshot,
    required this.markupType,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.startTokenIndex,
    this.endTokenIndex,
    this.refStart,
    this.refEnd,
    this.compactRef,
    this.noteText,
    this.deletedAt,
  });

  final int id;
  final String libraryItemId;
  final String epubHref;
  final int startBlockIndex;
  final int startCharOffset;
  final int endBlockIndex;
  final int endCharOffset;
  final int? startTokenIndex;
  final int? endTokenIndex;
  final String? refStart;
  final String? refEnd;
  final String? compactRef;
  final String selectedTextSnapshot;
  final String markupType;
  final String color;
  final String? noteText;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;

  bool get isHighlight => markupType == ElibraryMarkupRepository.highlightType;
}

class ElibraryMarkupRepository {
  static const String highlightType = 'highlight';
  static const String defaultHighlightColor = '#F7D87D';

  Future<Map<String, List<ElibraryMarkupRecord>>>
  loadHighlightsBySectionForItem(String libraryItemId) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'elibrary_markups',
      where: 'library_item_id = ? AND deleted_at IS NULL AND markup_type = ?',
      whereArgs: [libraryItemId, highlightType],
      orderBy: 'created_at ASC, id ASC',
    );
    final result = <String, List<ElibraryMarkupRecord>>{};
    for (final row in rows) {
      final record = _recordFromRow(row);
      if (record == null) continue;
      result
          .putIfAbsent(record.epubHref, () => <ElibraryMarkupRecord>[])
          .add(record);
    }
    return result;
  }

  Future<ElibraryMarkupRecord?> saveHighlight({
    required String libraryItemId,
    required String epubHref,
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
    int? startTokenIndex,
    int? endTokenIndex,
    required String refStart,
    required String refEnd,
    required String compactRef,
    required String selectedTextSnapshot,
    String color = defaultHighlightColor,
  }) async {
    final db = await UserDatabase.instance.database;
    final now = _utcNow();
    await db.delete(
      'elibrary_markups',
      where:
          'library_item_id = ? AND epub_href = ? AND markup_type = ? AND start_block_index = ? AND start_char_offset = ? AND end_block_index = ? AND end_char_offset = ? AND deleted_at IS NULL',
      whereArgs: [
        libraryItemId,
        epubHref,
        highlightType,
        startBlockIndex,
        startCharOffset,
        endBlockIndex,
        endCharOffset,
      ],
    );
    final id = await db.insert('elibrary_markups', {
      'library_item_id': libraryItemId,
      'epub_href': epubHref,
      'start_block_index': startBlockIndex,
      'start_char_offset': startCharOffset,
      'end_block_index': endBlockIndex,
      'end_char_offset': endCharOffset,
      'start_token_index': startTokenIndex,
      'end_token_index': endTokenIndex,
      'ref_start': refStart,
      'ref_end': refEnd,
      'compact_ref': compactRef,
      'selected_text_snapshot': selectedTextSnapshot,
      'markup_type': highlightType,
      'color': color,
      'note_text': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    });
    return ElibraryMarkupRecord(
      id: id.toInt(),
      libraryItemId: libraryItemId,
      epubHref: epubHref,
      startBlockIndex: startBlockIndex,
      startCharOffset: startCharOffset,
      endBlockIndex: endBlockIndex,
      endCharOffset: endCharOffset,
      startTokenIndex: startTokenIndex,
      endTokenIndex: endTokenIndex,
      refStart: refStart,
      refEnd: refEnd,
      compactRef: compactRef,
      selectedTextSnapshot: selectedTextSnapshot,
      markupType: highlightType,
      color: color,
      noteText: null,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
  }

  Future<int> clearHighlightsOverlappingSelection({
    required String libraryItemId,
    required String epubHref,
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
  }) async {
    final db = await UserDatabase.instance.database;
    final now = _utcNow();
    return db.update(
      'elibrary_markups',
      {
        'updated_at': now,
        'deleted_at': now,
      },
      where:
          'library_item_id = ? AND epub_href = ? AND markup_type = ? AND deleted_at IS NULL AND NOT ('
          'end_block_index < ? OR '
          '(end_block_index = ? AND end_char_offset <= ?) OR '
          'start_block_index > ? OR '
          '(start_block_index = ? AND start_char_offset >= ?)'
          ')',
      whereArgs: [
        libraryItemId,
        epubHref,
        highlightType,
        startBlockIndex,
        startBlockIndex,
        startCharOffset,
        endBlockIndex,
        endBlockIndex,
        endCharOffset,
      ],
    );
  }

  ElibraryMarkupRecord? _recordFromRow(Map<String, Object?> row) {
    final idValue = row['id'];
    final libraryItemId = row['library_item_id']?.toString() ?? '';
    final epubHref = row['epub_href']?.toString() ?? '';
    final selectedTextSnapshot =
        row['selected_text_snapshot']?.toString() ?? '';
    final markupType = row['markup_type']?.toString() ?? '';
    final color = row['color']?.toString() ?? '';
    if (idValue == null ||
        libraryItemId.isEmpty ||
        epubHref.isEmpty ||
        selectedTextSnapshot.isEmpty ||
        markupType.isEmpty ||
        color.isEmpty) {
      return null;
    }
    return ElibraryMarkupRecord(
      id: (idValue as num).toInt(),
      libraryItemId: libraryItemId,
      epubHref: epubHref,
      startBlockIndex: (row['start_block_index'] as num?)?.toInt() ?? 0,
      startCharOffset: (row['start_char_offset'] as num?)?.toInt() ?? 0,
      endBlockIndex: (row['end_block_index'] as num?)?.toInt() ?? 0,
      endCharOffset: (row['end_char_offset'] as num?)?.toInt() ?? 0,
      startTokenIndex: (row['start_token_index'] as num?)?.toInt(),
      endTokenIndex: (row['end_token_index'] as num?)?.toInt(),
      refStart: row['ref_start']?.toString(),
      refEnd: row['ref_end']?.toString(),
      compactRef: row['compact_ref']?.toString(),
      selectedTextSnapshot: selectedTextSnapshot,
      markupType: markupType,
      color: color,
      noteText: row['note_text']?.toString(),
      createdAt: row['created_at']?.toString() ?? '',
      updatedAt: row['updated_at']?.toString() ?? '',
      deletedAt: row['deleted_at']?.toString(),
    );
  }

  String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }
}
