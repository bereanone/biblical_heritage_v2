// ignore_for_file: avoid_print
//
// Recovers `pioneer_epub_import` library items whose app-managed EPUB copy
// was removed by `EpubStoragePolicyService` and whose canonical generation
// is stale relative to `LibraryDocumentCanonicalizer.version`, by copying
// (never moving) each title's original source file from the legacy
// `Documents/ImportedPioneerEpubs` folder into the current Library Root's
// `ImportedPioneerEpubs` folder, then re-canonicalizing under the current
// version via the same `CanonicalActivation.activate` primitive every other
// acquisition path uses.
//
// Never touches the legacy folder: files are read-only there. Never applies
// the storage-deletion policy after activation, so the freshly-recovered
// copy stays present in the Library Root for verification. Verifies success
// per title via `LibraryDocumentRepository.isCurrentComplete`, not by
// assuming a lack of exception means success.
//
// Usage (must run under `flutter test`, not `dart run` — see
// tool/pioneer_archive_org_repair for why):
//   PIONEER_RECOVERY_DB=<eLibrary.db> \
//   PIONEER_RECOVERY_ROOT=<v2 library root path> \
//   PIONEER_RECOVERY_LEGACY=<legacy ImportedPioneerEpubs folder> \
//     flutter test tool/pioneer_legacy_recovery/run_pioneer_legacy_recovery.dart
//
// Add PIONEER_RECOVERY_APPLY=1 to actually copy files and write to the
// database; without it, this is a dry run that only reports what it would
// do. Add PIONEER_RECOVERY_LIMIT=<n> to cap how many candidate items are
// processed (used for the reviewed rehearsal batch). Add
// PIONEER_RECOVERY_IDS=<comma-separated library_item_id list> to target
// specific items instead of the full candidate query (also used for the
// rehearsal). Add PIONEER_RECOVERY_REPORT=<output.json> to save the report.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pioneer legacy-folder recovery', () async {
    final dbPath = Platform.environment['PIONEER_RECOVERY_DB'];
    final rootPath = Platform.environment['PIONEER_RECOVERY_ROOT'];
    final legacyPath = Platform.environment['PIONEER_RECOVERY_LEGACY'];
    if (dbPath == null || dbPath.trim().isEmpty) {
      // No-op under a plain `flutter test` sweep of this directory.
      return;
    }
    if (rootPath == null || rootPath.trim().isEmpty) {
      fail('PIONEER_RECOVERY_ROOT must be set alongside PIONEER_RECOVERY_DB.');
    }
    if (legacyPath == null || legacyPath.trim().isEmpty) {
      fail(
        'PIONEER_RECOVERY_LEGACY must be set alongside PIONEER_RECOVERY_DB.',
      );
    }
    final apply = Platform.environment['PIONEER_RECOVERY_APPLY'] == '1';
    final reportPath = Platform.environment['PIONEER_RECOVERY_REPORT'];
    final limitRaw = Platform.environment['PIONEER_RECOVERY_LIMIT'];
    final limit = limitRaw == null ? null : int.tryParse(limitRaw);
    final idsRaw = Platform.environment['PIONEER_RECOVERY_IDS'];
    final onlyIds = (idsRaw == null || idsRaw.trim().isEmpty)
        ? null
        : idsRaw
              .split(',')
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty)
              .toSet();

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openDatabase(dbPath);
    final repository = LibraryDocumentRepository(db);
    final currentVersion = LibraryDocumentCanonicalizer.version;

    // Candidate set: active pioneer_epub_import rows whose app-managed copy
    // was removed. `isCurrentComplete` is re-checked per row below (not
    // trusted from a join) since it also requires blockCount > 0.
    final candidates = await db.query(
      'library_items',
      columns: const <String>['id', 'title', 'relative_path'],
      where: '''
        deleted_at IS NULL
        AND source_type = 'pioneer_epub_import'
        AND LOWER(COALESCE(epub_storage_state, 'present')) = 'removed_after_index'
      ''',
      orderBy: 'id ASC',
    );

    final results = <Map<String, Object?>>[];
    var recovered = 0;
    var alreadyCurrent = 0;
    var failed = 0;
    var missingSource = 0;
    var skipped = 0;
    var processed = 0;

    for (final row in candidates) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      if (onlyIds != null && !onlyIds.contains(id)) continue;
      if (limit != null && processed >= limit) break;
      processed += 1;

      final title = row['title']?.toString() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (relativePath.isEmpty) {
        skipped += 1;
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': 'skipped_no_relative_path',
        });
        continue;
      }

      final alreadyGood = await repository.isCurrentComplete(
        id,
        canonicalizerVersion: currentVersion,
      );
      if (alreadyGood) {
        alreadyCurrent += 1;
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': 'already_current',
        });
        continue;
      }

      final fileName = p.basename(relativePath);
      final legacyFile = File(p.join(legacyPath, fileName));
      if (!await legacyFile.exists()) {
        missingSource += 1;
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': 'missing_legacy_source',
          'expected_legacy_path': legacyFile.path,
        });
        continue;
      }

      final sourceBytes = await legacyFile.readAsBytes();
      final sourceHash = sha256.convert(sourceBytes).toString();
      final destinationFile = File(p.join(rootPath, relativePath));

      if (!apply) {
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': 'dry_run_would_recover',
          'legacy_path': legacyFile.path,
          'destination_path': destinationFile.path,
          'legacy_sha256': sourceHash,
          'legacy_size_bytes': sourceBytes.length,
        });
        continue;
      }

      try {
        await destinationFile.parent.create(recursive: true);
        await destinationFile.writeAsBytes(sourceBytes, flush: true);
        final copiedHash = sha256
            .convert(await destinationFile.readAsBytes())
            .toString();
        if (copiedHash != sourceHash) {
          failed += 1;
          results.add(<String, Object?>{
            'id': id,
            'title': title,
            'status': 'copy_hash_mismatch',
            'legacy_sha256': sourceHash,
            'copied_sha256': copiedHash,
          });
          continue;
        }

        final beforeCount = await repository.blockCount(id);
        final outcome = await CanonicalActivation.activate(
          db: db,
          libraryItemId: id,
          source: destinationFile,
          force: true,
        );
        final afterCount = await repository.blockCount(id);
        final nowCurrent = await repository.isCurrentComplete(
          id,
          canonicalizerVersion: currentVersion,
        );

        if (nowCurrent) {
          final now = DateTime.now().toUtc().toIso8601String();
          await db.update(
            'library_items',
            <String, Object?>{
              'epub_storage_state': 'present',
              'epub_removed_at': null,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
          recovered += 1;
        } else {
          failed += 1;
        }

        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': nowCurrent ? 'recovered' : 'recanonicalize_not_current',
          'legacy_sha256': sourceHash,
          'blocks_before': beforeCount,
          'blocks_after': afterCount,
          'outcome_phase': outcome.phase.name,
          'is_current_complete_after': nowCurrent,
          if (!nowCurrent) 'outcome_detail': outcome.technicalDetail,
        });
      } catch (error) {
        failed += 1;
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'status': 'error',
          'error': error.toString(),
        });
      }
    }

    final report = <String, Object?>{
      'apply': apply,
      'canonicalizer_version': currentVersion,
      'candidates_scanned': candidates.length,
      'processed': processed,
      'recovered': recovered,
      'already_current': alreadyCurrent,
      'failed': failed,
      'missing_legacy_source': missingSource,
      'skipped': skipped,
      'results': results,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    if (reportPath != null && reportPath.trim().isNotEmpty) {
      await File(reportPath).writeAsString(encoded);
    }
    print(
      '${apply ? "APPLIED" : "DRY RUN"}: $processed processed, '
      '$recovered recovered, $alreadyCurrent already current, '
      '$failed failed, $missingSource missing legacy source, '
      '$skipped skipped.',
    );
    print(encoded);

    if (apply) {
      final integrity = await db.rawQuery('PRAGMA integrity_check');
      print('PRAGMA integrity_check: ${integrity.first.values.first}');
    }

    await db.close();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
