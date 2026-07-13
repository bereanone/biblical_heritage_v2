import '../../../core/database/elibrary_database.dart';
import '../../../core/database/user_database.dart';

/// Persists reader state changes to the catalog databases.
class LibraryReaderStateWriter {
  LibraryReaderStateWriter._();

  static final LibraryReaderStateWriter instance = LibraryReaderStateWriter._();

  Future<void> stampLastOpened(String libraryItemId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _updateLibraryItemRow(libraryItemId, <String, Object?>{
      'last_opened': now,
      'updated_at': now,
    });
  }

  Future<void> saveCurrentLocation({
    required String libraryItemId,
    required String currentSectionEntryName,
    required int? currentSectionSpineIndex,
    required String? savedHref,
    required String? savedAnchorId,
    required int? savedParagraphIndex,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _updateLibraryItemRow(libraryItemId, <String, Object?>{
      'last_opened': now,
      'epub_href': savedHref != null && savedHref.isNotEmpty
          ? savedHref
          : currentSectionEntryName,
      'epub_cfi': null,
      'anchor_id': savedAnchorId != null && savedAnchorId.isNotEmpty
          ? savedAnchorId
          : null,
      'spine_index': currentSectionSpineIndex,
      'paragraph_index': savedParagraphIndex ?? 1,
      'updated_at': now,
    });
  }

  Future<void> _updateLibraryItemRow(
    String libraryItemId,
    Map<String, Object?> values,
  ) async {
    for (final databaseFuture in [
      ELibraryDatabase.instance.database,
      UserDatabase.instance.database,
    ]) {
      try {
        final db = await databaseFuture;
        await db.update(
          'library_items',
          values,
          where: 'id = ?',
          whereArgs: [libraryItemId],
        );
      } catch (_) {
        // Best effort: update whichever catalog database is available.
      }
    }
  }
}
