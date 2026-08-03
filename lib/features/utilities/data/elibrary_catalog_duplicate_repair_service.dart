import 'dart:developer' as developer;

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String kLegacyEgwCatalogRepairKey =
    'repair_legacy_egw_catalog_duplicates_v1';

class ELibraryCatalogDuplicateRepairReport {
  const ELibraryCatalogDuplicateRepairReport({
    required this.duplicateLogicalBooksFound,
    required this.legacyCatalogRowsRetired,
    required this.userStateRowsMigrated,
    required this.indexRowsRemoved,
    required this.linkRowsRemoved,
    required this.ambiguousDuplicates,
    required this.pairs,
  });

  final int duplicateLogicalBooksFound;
  final int legacyCatalogRowsRetired;
  final int userStateRowsMigrated;
  final int indexRowsRemoved;
  final int linkRowsRemoved;
  final List<String> ambiguousDuplicates;
  final List<ELibraryCatalogDuplicatePair> pairs;

  bool get changed => legacyCatalogRowsRetired > 0;
}

class ELibraryCatalogDuplicatePair {
  const ELibraryCatalogDuplicatePair({
    required this.canonicalId,
    required this.legacyId,
    required this.canonicalPath,
    required this.legacyPath,
  });

  final String canonicalId;
  final String legacyId;
  final String canonicalPath;
  final String legacyPath;
}

class ELibraryCatalogDuplicateRepairService {
  ELibraryCatalogDuplicateRepairService._();

  static final instance = ELibraryCatalogDuplicateRepairService._();

  static bool isCanonicalEgwEpubPath(String value) {
    final path = _normalizedPath(value);
    return path.startsWith('epubs/egw/') && path.endsWith('.epub');
  }

  static bool isLegacyEgwEpubPath(String value) {
    final path = _normalizedPath(value);
    return path.startsWith('epubs/research/egw_') && path.endsWith('.epub');
  }

  /// A legacy candidate remains supported unless an active, verified
  /// canonical catalog equivalent is already present.
  Future<bool> shouldSkipLegacyCandidate({
    required DatabaseExecutor db,
    required String relativePath,
  }) async {
    if (!isLegacyEgwEpubPath(relativePath)) return false;
    final fileName = _normalizedFileName(relativePath);
    final legacyRows = await db.query(
      'library_items',
      where:
          'LOWER(file_name) = ? AND '
          "LOWER(REPLACE(relative_path, '\\', '/')) = ?",
      whereArgs: <Object?>[fileName, _normalizedPath(relativePath)],
    );
    final canonicalRows = await db.query(
      'library_items',
      where:
          'deleted_at IS NULL AND LOWER(file_name) = ? AND '
          "LOWER(REPLACE(relative_path, '\\', '/')) LIKE 'epubs/egw/%'",
      whereArgs: <Object?>[fileName],
    );
    return legacyRows.any(
      (legacy) =>
          canonicalRows.any((canonical) => _equivalent(canonical, legacy)),
    );
  }

  Future<ELibraryCatalogDuplicateRepairReport> repair({
    required Database db,
  }) async {
    final rows = await db.query(
      'library_items',
      columns: const <String>[
        'id',
        'title',
        'author',
        'file_name',
        'relative_path',
        'source_work_id',
        'source_package_id',
        'last_opened',
        'epub_href',
        'epub_cfi',
        'anchor_id',
        'spine_index',
        'paragraph_index',
      ],
      where: 'deleted_at IS NULL',
    );

    final canonicalByFile = <String, List<Map<String, Object?>>>{};
    final legacyRows = <Map<String, Object?>>[];
    for (final row in rows) {
      final path = row['relative_path']?.toString() ?? '';
      if (isCanonicalEgwEpubPath(path)) {
        canonicalByFile
            .putIfAbsent(_normalizedFileName(path), () => [])
            .add(row);
      } else if (isLegacyEgwEpubPath(path)) {
        legacyRows.add(row);
      }
    }

    final pairs = <ELibraryCatalogDuplicatePair>[];
    final ambiguous = <String>[];
    for (final legacy in legacyRows) {
      final legacyPath = legacy['relative_path']?.toString() ?? '';
      final candidates =
          canonicalByFile[_normalizedFileName(legacyPath)] ??
          const <Map<String, Object?>>[];
      final matches = candidates
          .where((canonical) => _equivalent(canonical, legacy))
          .toList(growable: false);
      if (matches.length == 1) {
        final canonical = matches.single;
        pairs.add(
          ELibraryCatalogDuplicatePair(
            canonicalId: canonical['id']!.toString(),
            legacyId: legacy['id']!.toString(),
            canonicalPath: canonical['relative_path']!.toString(),
            legacyPath: legacyPath,
          ),
        );
      } else if (candidates.isNotEmpty) {
        ambiguous.add(legacyPath);
      }
    }

    var retired = 0;
    var userStateMigrated = 0;
    var indexRowsRemoved = 0;
    var linkRowsRemoved = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final pair in pairs) {
        final legacy = (await txn.query(
          'library_items',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[pair.legacyId],
          limit: 1,
        ));
        final canonical = (await txn.query(
          'library_items',
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[pair.canonicalId],
          limit: 1,
        ));
        if (legacy.isEmpty ||
            canonical.isEmpty ||
            !_equivalent(canonical.single, legacy.single)) {
          continue;
        }

        final canonicalRow = canonical.single;
        final legacyRow = legacy.single;
        final updates = <String, Object?>{'updated_at': now};
        final canonicalLastOpened =
            canonicalRow['last_opened']?.toString().trim() ?? '';
        final legacyLastOpened =
            legacyRow['last_opened']?.toString().trim() ?? '';
        if (legacyLastOpened.compareTo(canonicalLastOpened) > 0) {
          updates['last_opened'] = legacyLastOpened;
          for (final column in const <String>[
            'epub_href',
            'epub_cfi',
            'anchor_id',
            'spine_index',
            'paragraph_index',
          ]) {
            updates[column] = legacyRow[column];
          }
        }
        await txn.update(
          'library_items',
          updates,
          where: 'id = ?',
          whereArgs: <Object?>[pair.canonicalId],
        );

        var migrated = 0;
        if (await _tableExists(txn, 'elibrary_markups')) {
          migrated += await txn.update(
            'elibrary_markups',
            <String, Object?>{'library_item_id': pair.canonicalId},
            where: 'library_item_id = ?',
            whereArgs: <Object?>[pair.legacyId],
          );
        }
        if (await _tableExists(txn, 'library_item_contributors')) {
          await txn.rawInsert(
            '''
            INSERT OR IGNORE INTO library_item_contributors
              (library_item_id, contributor_id, role, sort_order, is_primary, created_at)
            SELECT ?, contributor_id, role, sort_order, is_primary, created_at
            FROM library_item_contributors WHERE library_item_id = ?
            ''',
            <Object?>[pair.canonicalId, pair.legacyId],
          );
          await txn.delete(
            'library_item_contributors',
            where: 'library_item_id = ?',
            whereArgs: <Object?>[pair.legacyId],
          );
        }

        var removed = 0;
        var links = 0;
        for (final table in _generatedItemTables) {
          if (!await _tableExists(txn, table)) continue;
          final count = await txn.delete(
            table,
            where: 'library_item_id = ?',
            whereArgs: <Object?>[pair.legacyId],
          );
          removed += count;
          if (table == 'library_links') links += count;
        }
        await txn.update(
          'library_items',
          <String, Object?>{
            'deleted_at': now,
            'updated_at': now,
            'index_status': 'duplicate_retired',
            'index_error': 'Superseded by canonical item ${pair.canonicalId}',
            'sync_status': 'pending',
          },
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: <Object?>[pair.legacyId],
        );
        userStateMigrated += migrated;
        indexRowsRemoved += removed;
        linkRowsRemoved += links;
        retired += 1;
      }

      final existingMarker = await txn.query(
        'elibrary_schema_migrations',
        columns: const <String>['migration_key'],
        where: 'migration_key = ?',
        whereArgs: const <Object?>[kLegacyEgwCatalogRepairKey],
        limit: 1,
      );
      if (retired > 0 || existingMarker.isEmpty) {
        await txn.insert(
          'elibrary_schema_migrations',
          <String, Object?>{
            'migration_key': kLegacyEgwCatalogRepairKey,
            'from_version': 1,
            'to_version': 1,
            'applied_at': now,
            'status': 'completed',
            'details':
                'found=${pairs.length}; retired=$retired; '
                'user_state=$userStateMigrated; index_rows=$indexRowsRemoved; '
                'links=$linkRowsRemoved; '
                'ambiguous=${ambiguous.length}',
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    final report = ELibraryCatalogDuplicateRepairReport(
      duplicateLogicalBooksFound: pairs.length,
      legacyCatalogRowsRetired: retired,
      userStateRowsMigrated: userStateMigrated,
      indexRowsRemoved: indexRowsRemoved,
      linkRowsRemoved: linkRowsRemoved,
      ambiguousDuplicates: List.unmodifiable(ambiguous),
      pairs: List.unmodifiable(pairs),
    );
    developer.log(
      'Legacy EGW catalog repair: found=${report.duplicateLogicalBooksFound} '
      'retired=${report.legacyCatalogRowsRetired} '
      'userState=${report.userStateRowsMigrated} '
      'indexRows=${report.indexRowsRemoved} '
      'links=${report.linkRowsRemoved} '
      'ambiguous=${report.ambiguousDuplicates.length}.',
      name: 'ELibraryCatalogDuplicateRepair',
    );
    return report;
  }
}

const _generatedItemTables = <String>[
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
  'elibrary_ref_index',
];

bool _equivalent(Map<String, Object?> canonical, Map<String, Object?> legacy) {
  final canonicalWork = _normalizedText(canonical['source_work_id']);
  final legacyWork = _normalizedText(legacy['source_work_id']);
  if (canonicalWork.isNotEmpty && legacyWork.isNotEmpty) {
    return canonicalWork == legacyWork;
  }
  final canonicalPackage = _normalizedText(canonical['source_package_id']);
  final legacyPackage = _normalizedText(legacy['source_package_id']);
  if (canonicalPackage.isNotEmpty && legacyPackage.isNotEmpty) {
    return canonicalPackage == legacyPackage;
  }
  if (_normalizedFileName(canonical['file_name']?.toString() ?? '') !=
      _normalizedFileName(legacy['file_name']?.toString() ?? '')) {
    return false;
  }
  final canonicalTitle = _normalizedText(canonical['title']);
  final legacyTitle = _normalizedText(legacy['title']);
  final canonicalAuthor = _normalizedText(canonical['author']);
  final legacyAuthor = _normalizedText(legacy['author']);
  if (canonicalTitle.isNotEmpty &&
      legacyTitle.isNotEmpty &&
      canonicalTitle != legacyTitle) {
    return false;
  }
  if (canonicalAuthor.isNotEmpty &&
      legacyAuthor.isNotEmpty &&
      canonicalAuthor != legacyAuthor) {
    return false;
  }
  return true;
}

String _normalizedPath(String value) =>
    p.posix.normalize(value.replaceAll('\\', '/')).toLowerCase();

String _normalizedFileName(String value) =>
    p.posix.basename(value.replaceAll('\\', '/')).toLowerCase().trim();

String _normalizedText(Object? value) => (value?.toString() ?? '')
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    <Object?>[table],
  );
  return rows.isNotEmpty;
}
