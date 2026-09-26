import '../../../core/database/elibrary_database.dart';
import '../../../core/database/elibrary_read_resolver.dart';

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
  static const String underlineType = 'underline';
  static const String defaultHighlightColor = '#F7D87D';

  Future<Map<String, List<ElibraryMarkupRecord>>> loadMarkupsBySectionForItem(
    String libraryItemId,
  ) async {
    final rowResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'elibrary_markups',
            where: 'library_item_id = ? AND deleted_at IS NULL',
            whereArgs: [libraryItemId],
            orderBy: 'created_at ASC, id ASC',
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    final rows = rowResult.value;
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

  Future<Map<String, List<ElibraryMarkupRecord>>>
  loadHighlightsBySectionForItem(String libraryItemId) async {
    final bySection = await loadMarkupsBySectionForItem(libraryItemId);
    return {
      for (final entry in bySection.entries)
        if (entry.value.any((record) => record.isHighlight))
          entry.key: entry.value
              .where((record) => record.isHighlight)
              .toList(growable: false),
    };
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
    String markupType = highlightType,
  }) async {
    if (markupType != highlightType && markupType != underlineType) {
      throw ArgumentError.value(markupType, 'markupType');
    }
    final db = await ELibraryDatabase.instance.database;
    final now = _utcNow();
    return db.transaction((txn) async {
      const identity =
          'library_item_id = ? AND epub_href = ? AND markup_type = ? '
          'AND start_block_index = ? AND start_char_offset = ? '
          'AND end_block_index = ? AND end_char_offset = ? '
          'AND selected_text_snapshot = ? AND deleted_at IS NULL';
      final existing = await txn.query(
        'elibrary_markups',
        where: identity,
        whereArgs: [
          libraryItemId,
          epubHref,
          markupType,
          startBlockIndex,
          startCharOffset,
          endBlockIndex,
          endCharOffset,
          selectedTextSnapshot,
        ],
        orderBy: 'id',
        limit: 1,
      );
      final values = <String, Object?>{
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
        'markup_type': markupType,
        'color': color,
        'updated_at': now,
      };
      int id;
      if (existing.isNotEmpty) {
        // Recoloring is an update. Keep the note, creation time and stable ID.
        id = (existing.single['id'] as num).toInt();
        await txn.update(
          'elibrary_markups',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        id = await txn.insert('elibrary_markups', {
          ...values,
          'created_at': now,
          'deleted_at': null,
        });
      }
      final rows = await txn.query(
        'elibrary_markups',
        where: 'id = ?',
        whereArgs: [id],
      );
      return _recordFromRow(rows.single);
    });
  }

  Future<int> clearHighlightsOverlappingSelection({
    required String libraryItemId,
    required String epubHref,
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
    bool includeUnderlines = false,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final now = _utcNow();
    return db.update(
      'elibrary_markups',
      {'updated_at': now, 'deleted_at': now},
      where:
          'library_item_id = ? AND epub_href = ? AND markup_type IN (?, ?) AND deleted_at IS NULL AND NOT ('
          'end_block_index < ? OR '
          '(end_block_index = ? AND end_char_offset <= ?) OR '
          'start_block_index > ? OR '
          '(start_block_index = ? AND start_char_offset >= ?)'
          ')',
      whereArgs: [
        libraryItemId,
        epubHref,
        highlightType,
        includeUnderlines ? underlineType : highlightType,
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
