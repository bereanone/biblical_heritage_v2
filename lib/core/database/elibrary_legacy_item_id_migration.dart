import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../features/library/data/library_item_identity.dart';

const String kLegacyItemIdNormalizationMigrationKey =
    'normalize_legacy_pioneer_item_ids_20260815';

/// Legacy `library_items.id` values shipped in the bundled asset database
/// before [canonicalLibraryItemId]'s `library_item_...` prefix convention
/// existed. Both rows predate the Pioneer stable-ID scheme
/// (`library_item_research_pioneer_<authorId>_<workId>`) and were never
/// re-imported under it, so their bare IDs sort ahead of every properly
/// prefixed ID — including every EGW item — in a plain ID-ordered query.
/// That crowded EGW results out of the pre-scoring LIMIT window in
/// `LibraryCatalogService.searchContent`.
const Map<String, String> _legacyPioneerItemIdRenames = <String, String>{
  'DAR_US': 'library_item_research_pioneer_uriah_smith_DAR_US',
  'lessons_on_faith': 'library_item_research_pioneer_at_jones_lessons_on_faith',
};

class ELibraryLegacyItemIdMigrationService {
  ELibraryLegacyItemIdMigrationService._();

  static final ELibraryLegacyItemIdMigrationService instance =
      ELibraryLegacyItemIdMigrationService._();

  Future<void> run(Database db, {void Function(String message)? log}) async {
    final alreadyApplied = await _alreadyApplied(db);
    if (alreadyApplied) return;

    final renamed = <String>[];
    for (final entry in _legacyPioneerItemIdRenames.entries) {
      final before = await db.query(
        'library_items',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [entry.key],
        limit: 1,
      );
      if (before.isEmpty) continue;
      await migrateManagedLibraryItemId(
        db: db,
        oldId: entry.key,
        newId: entry.value,
      );
      renamed.add('${entry.key} -> ${entry.value}');
    }

    final message = renamed.isEmpty
        ? 'No legacy Pioneer item IDs found to normalize.'
        : 'Normalized legacy Pioneer item IDs: ${renamed.join(', ')}.';
    await db.insert('elibrary_schema_migrations', <String, Object?>{
      'migration_key': kLegacyItemIdNormalizationMigrationKey,
      'from_version': 1,
      'to_version': 1,
      'applied_at': _utcNow(),
      'status': 'completed',
      'details': message,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    log?.call(message);
  }

  Future<bool> _alreadyApplied(DatabaseExecutor db) async {
    final rows = await db.query(
      'elibrary_schema_migrations',
      columns: const ['migration_key'],
      where: 'migration_key = ? AND status = ?',
      whereArgs: [kLegacyItemIdNormalizationMigrationKey, 'completed'],
      limit: 1,
    );
    return rows.isNotEmpty;
  }
}

String _utcNow() {
  final now = DateTime.now().toUtc();
  final iso = now.toIso8601String();
  return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
}
