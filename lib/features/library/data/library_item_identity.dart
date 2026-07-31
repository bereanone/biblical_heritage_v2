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

bool isUserImportedEpubRelativePath(String relativePath) {
  return ELibraryFolderPolicy.isUserImportedEpubFolderPath(relativePath);
}

bool isPioneerImportedEpubRelativePath(String relativePath) {
  return ELibraryFolderPolicy.isPioneerImportedEpubFolderPath(relativePath);
}

bool isManagedEgwCollectionName(String? collectionName) {
  final normalized = _normalizedText(collectionName ?? '');
  return normalized == 'egw books' ||
      normalized == 'egw devotionals' ||
      normalized == 'egw commentaries' ||
      normalized == 'egw misc collections' ||
      normalized == 'egw pamphlets' ||
      normalized == 'egw periodicals' ||
      normalized == 'egw manuscript releases';
}

/// Every table keyed by `library_item_id` whose rows belong to exactly one
/// library item. Shared by [migrateManagedLibraryItemId] (renaming a live
/// item) and [reassociateOrphanCanonicalGeneration] (grafting an orphaned
/// generation onto a live item) so both agree on the full dependent-row set.
const _itemOwnedTables = <String>[
  'library_document_conversion',
  'library_document_sections',
  'library_document_blocks',
  'library_block_source_map',
  'library_document_conversion_staging',
  'library_document_sections_staging',
  'library_document_blocks_staging',
  'library_block_source_map_staging',
  'library_navigation_items',
  'library_links',
  'library_text_blocks',
  'library_item_contributors',
  'elibrary_ref_index',
  'elibrary_markups',
];

/// Moves every dependent row owned by [fromId] in each of [_itemOwnedTables]
/// to [toId], refusing (and leaving every table untouched, since this always
/// runs inside the caller's transaction) if any table already owns rows for
/// [toId].
Future<void> _moveOwnedTableRows({
  required DatabaseExecutor txn,
  required String fromId,
  required String toId,
  required String refusalContext,
}) async {
  for (final table in _itemOwnedTables) {
    if (!await _tableExists(txn, table)) continue;
    final collision = await txn.query(
      table,
      columns: const <String>['library_item_id'],
      where: 'library_item_id = ?',
      whereArgs: <Object?>[toId],
      limit: 1,
    );
    if (collision.isNotEmpty) {
      throw StateError(
        'Refusing $refusalContext because $table already owns rows for '
        'target: $toId',
      );
    }
    await txn.update(
      table,
      <String, Object?>{'library_item_id': toId},
      where: 'library_item_id = ?',
      whereArgs: <Object?>[fromId],
    );
  }
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
    if (targetExists.isNotEmpty) {
      throw StateError(
        'Refusing library item ID migration because target already exists: '
        '$normalizedNew',
      );
    }

    await _moveOwnedTableRows(
      txn: txn,
      fromId: normalizedOld,
      toId: normalizedNew,
      refusalContext: 'library item ID migration',
    );

    await txn.update(
      'library_items',
      {'id': normalizedNew},
      where: 'id = ?',
      whereArgs: [normalizedOld],
    );
  });
}

/// Grafts an orphaned canonical generation — dependent-table rows left
/// behind under [orphanGenerationId] with no owning `library_items` row at
/// all — onto an existing, currently-visible library item at
/// [visibleItemId]. This is the inverse of [migrateManagedLibraryItemId]:
/// that function renames a *live* row (and its dependents) to a new,
/// not-yet-used ID; this function moves *ownerless* dependent rows onto an
/// ID that already has a live `library_items` row and refuses if
/// [orphanGenerationId] turns out to still have one of its own (in that
/// case [migrateManagedLibraryItemId] is the correct tool instead).
///
/// The `library_items` row at [visibleItemId] itself is never modified —
/// only the dependent canonical/reference/markup tables are reassociated.
Future<void> reassociateOrphanCanonicalGeneration({
  required Database db,
  required String orphanGenerationId,
  required String visibleItemId,
}) async {
  final normalizedOrphan = orphanGenerationId.trim();
  final normalizedVisible = visibleItemId.trim();
  if (normalizedOrphan.isEmpty || normalizedVisible.isEmpty) return;
  if (normalizedOrphan == normalizedVisible) return;

  final visibleRow = await db.query(
    'library_items',
    columns: const ['id'],
    where: 'id = ?',
    whereArgs: [normalizedVisible],
    limit: 1,
  );
  if (visibleRow.isEmpty) {
    throw StateError(
      'Refusing orphan generation reassociation because the visible item '
      'does not exist: $normalizedVisible',
    );
  }

  await db.transaction((txn) async {
    final orphanOwnsLiveItem = await txn.query(
      'library_items',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [normalizedOrphan],
      limit: 1,
    );
    if (orphanOwnsLiveItem.isNotEmpty) {
      throw StateError(
        'Refusing orphan generation reassociation because '
        '$normalizedOrphan is not an orphan — it still owns a live '
        'library_items row; use migrateManagedLibraryItemId instead.',
      );
    }

    await _moveOwnedTableRows(
      txn: txn,
      fromId: normalizedOrphan,
      toId: normalizedVisible,
      refusalContext: 'orphan generation reassociation',
    );
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
