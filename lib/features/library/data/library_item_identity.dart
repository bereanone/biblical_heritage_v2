import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utilities/data/elibrary_folder_policy.dart';

String canonicalLibraryItemId({
  required String folderType,
  required String relativePath,
}) {
  return 'library_item_${_slug(folderType)}_${_slug(relativePath)}';
}

bool isManagedEgwRelativePath(String relativePath) {
  return ELibraryFolderPolicy.isManagedEgwFolderPath(relativePath);
}

bool isManagedEgwCollectionName(String? collectionName) {
  final normalized = _normalizedText(collectionName ?? '');
  return normalized == 'egw books' ||
      normalized == 'egw devotionals' ||
      normalized == 'egw commentaries';
}

Future<void> migrateManagedLibraryItemId({
  required Database db,
  required String oldId,
  required String newId,
}) async {
  final normalizedOld = oldId.trim();
  final normalizedNew = newId.trim();
  if (normalizedOld.isEmpty || normalizedNew.isEmpty) return;
  if (normalizedOld == normalizedNew) return;

  final existing = await db.query(
    'library_items',
    columns: const ['id'],
    where: 'id = ?',
    whereArgs: [normalizedOld],
    limit: 1,
  );
  if (existing.isEmpty) return;

  await db.transaction((txn) async {
    final targetExists = await txn.query(
      'library_items',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [normalizedNew],
      limit: 1,
    );

    await txn.update(
      'library_links',
      {'library_item_id': normalizedNew},
      where: 'library_item_id = ?',
      whereArgs: [normalizedOld],
    );
    await txn.update(
      'library_navigation_items',
      {'library_item_id': normalizedNew},
      where: 'library_item_id = ?',
      whereArgs: [normalizedOld],
    );

    if (await _tableExists(txn, 'elibrary_ref_index')) {
      await txn.update(
        'elibrary_ref_index',
        {'library_item_id': normalizedNew},
        where: 'library_item_id = ?',
        whereArgs: [normalizedOld],
      );
    }

    if (targetExists.isNotEmpty) {
      await txn.delete(
        'library_items',
        where: 'id = ?',
        whereArgs: [normalizedOld],
      );
    } else {
      await txn.update(
        'library_items',
        {'id': normalizedNew},
        where: 'id = ?',
        whereArgs: [normalizedOld],
      );
    }
  });
}

Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [tableName],
  );
  return rows.isNotEmpty;
}

String _normalizedText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _slug(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
