// ignore_for_file: avoid_print
//
// Repairs two bugs found in the archive.org-backed Pioneer EPUB downloader
// (`pioneer_archive_org_install_service.dart`):
//
// 1. **Corrupted content for every `pioneer_archive_org_download` item.**
//    `_stageActivateAndPromote` activated each download against a *staging*
//    file named `.<title>.epub.<timestamp>.downloading`. Because
//    `LibraryDocumentCanonicalizer.canonicalize` decides whether to unzip a
//    source purely by its file extension, and the staging file's real
//    extension was `.downloading` (not `.epub`), every one of these books was
//    "canonicalized" as if it were plain text — storing the raw ZIP bytes as
//    a single garbage `library_document_blocks` row instead of real parsed
//    text/navigation. Fixed at the source in
//    `pioneer_archive_org_install_service.dart` (the staging name now keeps
//    a real `.epub` extension). This tool re-canonicalizes every affected
//    item's already-downloaded file at its *final* (correctly-named)
//    destination path, which was never affected by the staging bug.
//
// 2. **Duplicate `library_items` rows for one physical file.** A handful of
//    manifest entries are distinct archive.org editions that share the same
//    nominal title (e.g. Uriah Smith's "Daniel and The Revelation" has a
//    `DAR` and a `DAR1909` edition). Before the file-name collision fix
//    (also in `pioneer_archive_org_install_service.dart`), both sanitized to
//    the identical destination file name, so the second download silently
//    overwrote the first on disk while both still kept their own
//    `library_items` row — leaving one row's metadata pointing at a file
//    that is no longer the edition it claims to be. This tool finds
//    `library_items` rows (source_type `pioneer_archive_org_download` or
//    `pioneer_epub_import`) that share an identical normalized
//    `relative_path` and retires all but one, preferring whichever id
//    matches this app's stable identity conventions
//    (`pioneer_<author>_<code>` or the hardcoded `library_item_research_*`
//    legacy-bridge ids) over an ad hoc/UUID-derived id.
//
// This has to run under `flutter test` (not plain `dart run`) because the
// canonicalizer's import graph pulls in `package:flutter/services.dart`
// (via `pioneer_html_capture_folder_scanner.dart`), which the vanilla Dart
// SDK used by `dart run` cannot compile.
//
// Usage:
//   PIONEER_REPAIR_DB=<eLibrary.db> PIONEER_REPAIR_ROOT=<library root path> \
//     flutter test tool/pioneer_archive_org_repair/run_pioneer_archive_org_repair.dart
//
// Add PIONEER_REPAIR_APPLY=1 to actually write changes; without it, this is
// a dry run that only prints/writes the report. Add
// PIONEER_REPAIR_REPORT=<output.json> to also save the report to a file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';

const _pioneerSourceTypes = <String>[
  'pioneer_archive_org_download',
  'pioneer_epub_import',
];

// Every table that owns rows keyed by `library_item_id` for a generated
// canonical/legacy-nav/reference generation. Mirrors the table lists in
// `library_item_identity.dart` and `elibrary_catalog_duplicate_repair_service.dart`.
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
  'library_item_contributors',
  'elibrary_ref_index',
  'elibrary_markups',
];

String _normalizedPath(String value) =>
    p.posix.normalize(value.replaceAll('\\', '/')).toLowerCase();

/// Rows produced by this app's stable identity schemes (the archive.org
/// downloader's `pioneer_<author>_<code>` ids, or the hardcoded
/// `library_item_research_pioneer_*` legacy-bridge ids) are always preferred
/// over an ad hoc/UUID- or raw-path-derived id from an older importer
/// version, regardless of which row happens to have more content today —
/// keeping the non-canonical id risks a *third* duplicate the next time the
/// canonical id is looked up and found "missing."
bool _looksCanonical(String id) {
  if (id.startsWith('library_item_research_pioneer_')) return true;
  if (id.startsWith('pioneer_') && !id.startsWith('pioneer_epub_import')) {
    return true;
  }
  return false;
}

Future<bool> _tableExists(DatabaseExecutor db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    <Object?>[table],
  );
  return rows.isNotEmpty;
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pioneer archive.org duplicate + corruption repair', () async {
    final dbPath = Platform.environment['PIONEER_REPAIR_DB'];
    final rootPath = Platform.environment['PIONEER_REPAIR_ROOT'];
    if (dbPath == null || dbPath.trim().isEmpty) {
      // No-op under a plain `flutter test` sweep of this directory — this
      // tool only does something when explicitly invoked with its env vars.
      return;
    }
    if (rootPath == null || rootPath.trim().isEmpty) {
      fail('PIONEER_REPAIR_ROOT must be set alongside PIONEER_REPAIR_DB.');
    }
    final apply = Platform.environment['PIONEER_REPAIR_APPLY'] == '1';
    final reportPath = Platform.environment['PIONEER_REPAIR_REPORT'];

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(dbPath);

    final dedupePairs = <Map<String, Object?>>[];
    var rowsRetired = 0;

    // --- Step 1: retire duplicate rows for the same physical file. ---
    final placeholders = _pioneerSourceTypes.map((_) => '?').join(', ');
    final rows = await db.query(
      'library_items',
      columns: const <String>[
        'id',
        'title',
        'author',
        'source_type',
        'relative_path',
        'created_at',
      ],
      where: 'deleted_at IS NULL AND source_type IN ($placeholders)',
      whereArgs: _pioneerSourceTypes,
    );

    final byPath = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final path = _normalizedPath(row['relative_path']?.toString() ?? '');
      if (path.isEmpty) continue;
      byPath.putIfAbsent(path, () => []).add(row);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final group in byPath.values) {
        if (group.length < 2) continue;
        group.sort((a, b) {
          final aCanonical = _looksCanonical(a['id'] as String);
          final bCanonical = _looksCanonical(b['id'] as String);
          if (aCanonical != bCanonical) return aCanonical ? -1 : 1;
          return (a['created_at'] as String? ?? '').compareTo(
            b['created_at'] as String? ?? '',
          );
        });
        final keeper = group.first;
        final losers = group.skip(1).toList(growable: false);
        for (final loser in losers) {
          final loserId = loser['id'] as String;
          dedupePairs.add(<String, Object?>{
            'kept_id': keeper['id'],
            'retired_id': loserId,
            'title': loser['title'],
            'relative_path': loser['relative_path'],
          });
          if (!apply) continue;
          for (final table in _generatedItemTables) {
            if (!await _tableExists(txn, table)) continue;
            await txn.delete(
              table,
              where: 'library_item_id = ?',
              whereArgs: <Object?>[loserId],
            );
          }
          await txn.update(
            'library_items',
            <String, Object?>{
              'deleted_at': now,
              'updated_at': now,
              'index_status': 'duplicate_retired',
              'index_error': 'Superseded by canonical item ${keeper['id']}',
              'sync_status': 'pending',
            },
            where: 'id = ?',
            whereArgs: <Object?>[loserId],
          );
          rowsRetired += 1;
        }
      }
    });

    // --- Step 2: re-canonicalize every surviving archive.org download. ---
    final survivingArchiveOrgRows = await db.query(
      'library_items',
      columns: const <String>['id', 'relative_path', 'title'],
      where:
          "deleted_at IS NULL AND source_type = 'pioneer_archive_org_download'",
    );

    final recanonicalizeResults = <Map<String, Object?>>[];
    var recanonicalized = 0;
    var recanonicalizeFailed = 0;
    var missingFiles = 0;

    for (final row in survivingArchiveOrgRows) {
      final id = row['id'] as String;
      final relativePath = row['relative_path']?.toString() ?? '';
      final file = File(p.join(rootPath, relativePath));
      if (!await file.exists()) {
        missingFiles += 1;
        recanonicalizeResults.add(<String, Object?>{
          'id': id,
          'title': row['title'],
          'status': 'missing_file',
          'path': file.path,
        });
        // The corrupted generation's blockCount > 0 makes
        // `LibraryDocumentRepository.isComplete` report this item as
        // "already in library" forever, so a future "Update Verified
        // Pioneer Books" run would never re-download it even after the
        // extension bug fix. With no local file to re-canonicalize from,
        // clearing the corrupted generation and marking the row
        // needs-attention is the only way to make it self-heal on the next
        // real download.
        if (apply) {
          await db.transaction((txn) async {
            for (final table in _generatedItemTables) {
              if (!await _tableExists(txn, table)) continue;
              await txn.delete(
                table,
                where: 'library_item_id = ?',
                whereArgs: <Object?>[id],
              );
            }
            await txn.update(
              'library_items',
              <String, Object?>{
                'index_status': 'needs_attention',
                'index_error':
                    'Source file missing at $relativePath under the '
                    'current Library Root; re-run "Update Verified '
                    'Pioneer Books" to re-download it.',
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: <Object?>[id],
            );
          });
        }
        continue;
      }

      final beforeCount = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM library_document_blocks WHERE library_item_id = ?',
        <Object?>[id],
      );
      final before = (beforeCount.first['c'] as num?)?.toInt() ?? 0;

      if (!apply) {
        recanonicalizeResults.add(<String, Object?>{
          'id': id,
          'title': row['title'],
          'status': 'dry_run',
          'blocks_before': before,
        });
        continue;
      }

      try {
        final outcome = await CanonicalActivation.activate(
          db: db,
          libraryItemId: id,
          source: file,
          force: true,
        );
        final afterCount = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM library_document_blocks WHERE library_item_id = ?',
          <Object?>[id],
        );
        final after = (afterCount.first['c'] as num?)?.toInt() ?? 0;
        if (outcome.isReady) {
          recanonicalized += 1;
        } else {
          recanonicalizeFailed += 1;
        }
        recanonicalizeResults.add(<String, Object?>{
          'id': id,
          'title': row['title'],
          'status': outcome.isReady ? 'recanonicalized' : 'failed',
          'blocks_before': before,
          'blocks_after': after,
          if (!outcome.isReady) 'detail': outcome.technicalDetail,
        });
      } catch (error) {
        recanonicalizeFailed += 1;
        recanonicalizeResults.add(<String, Object?>{
          'id': id,
          'title': row['title'],
          'status': 'error',
          'blocks_before': before,
          'error': error.toString(),
        });
      }
    }

    final report = <String, Object?>{
      'apply': apply,
      'canonicalizer_version': LibraryDocumentCanonicalizer.version,
      'duplicate_groups_found': dedupePairs.length,
      'rows_retired': rowsRetired,
      'dedupe_pairs': dedupePairs,
      'archive_org_items_scanned': survivingArchiveOrgRows.length,
      'recanonicalized': recanonicalized,
      'recanonicalize_failed': recanonicalizeFailed,
      'missing_files': missingFiles,
      'recanonicalize_results': recanonicalizeResults,
    };

    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    if (reportPath != null && reportPath.trim().isNotEmpty) {
      await File(reportPath).writeAsString(encoded);
    }
    print(
      '${apply ? "APPLIED" : "DRY RUN"}: '
      '${dedupePairs.length} duplicate pair(s) found, $rowsRetired retired; '
      '${survivingArchiveOrgRows.length} archive.org item(s) scanned, '
      '$recanonicalized recanonicalized, $recanonicalizeFailed failed, '
      '$missingFiles missing on disk.',
    );
    if (reportPath != null && reportPath.trim().isNotEmpty) {
      print('Report written to $reportPath');
    }

    if (apply) {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      print('PRAGMA integrity_check: ${integrity.first.values.first}');
    }

    await db.close();
  });
}
