// ignore_for_file: avoid_print
//
// Backfills `library_navigation_items` and `library_text_blocks` for Pioneer
// EPUB imports that were canonicalized (readable text landed in
// `library_document_blocks`/`library_document_sections`) but never got a
// navigation tree built at all, because the Pioneer import pipeline
// (`PioneerEpubBulkImportService` / `pioneer_archive_org_install_service.dart`
// via `CanonicalActivation.activate`) never called anything that writes
// `library_navigation_items` — that table is only ever populated by
// `CommentaryResearchLibraryService`'s EPUB indexer
// (`_storeNavigationMetadata`/`_storeLibraryTextBlocks`), which the Pioneer
// import pathway never invoked. Fixed at the source in
// `library_acquisition_orchestrator.dart` (`prepareExistingEpub`, used by
// every bulk EPUB import) and `pioneer_archive_org_install_service.dart`,
// both of which now call the new
// `CommentaryResearchLibraryService.ensureNavigationIndexed` right after a
// successful activation. This tool only backfills books that already exist
// with the old, broken (empty-navigation) generation.
//
// Selection criteria: any non-deleted, non-`duplicate_retired` EPUB item that
// has real canonical content (`library_document_blocks` rows) but zero
// `library_navigation_items` rows — the exact symptom of this bug, regardless
// of which Pioneer source_type produced it.
//
// This has to run under `flutter test` (not plain `dart run`) because the
// indexer's import graph pulls in `package:flutter/services.dart` and
// `package:path_provider`.
//
// Usage:
//   NAV_REPAIR_DB=<eLibrary.db> NAV_REPAIR_ROOT=<library root path> \
//     flutter test tool/nav_tree_repair/run_nav_tree_repair.dart
//
// Add NAV_REPAIR_APPLY=1 to actually write changes; without it, this is a
// dry run that only prints/writes the report. Add
// NAV_REPAIR_REPORT=<output.json> to also save the report to a file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

Future<void> _installPathProviderMocks(Directory supportDir) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => supportDir.path);
}

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'backfill navigation trees for broken Pioneer EPUB imports',
    () async {
      final dbPath = Platform.environment['NAV_REPAIR_DB'];
      final rootPath = Platform.environment['NAV_REPAIR_ROOT'];
      if (dbPath == null || dbPath.trim().isEmpty) {
        // No-op under a plain `flutter test` sweep of this directory — this
        // tool only does something when explicitly invoked with its env vars.
        return;
      }
      if (rootPath == null || rootPath.trim().isEmpty) {
        fail('NAV_REPAIR_ROOT must be set alongside NAV_REPAIR_DB.');
      }
      final apply = Platform.environment['NAV_REPAIR_APPLY'] == '1';
      final reportPath = Platform.environment['NAV_REPAIR_REPORT'];

      final supportDir = await Directory.systemTemp.createTemp(
        'nav_repair_support_',
      );
      await _installPathProviderMocks(supportDir);

      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final db = await openDatabase(dbPath);

      final rows = await db.rawQuery('''
      SELECT id, title, relative_path, source_type, folder_type
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(index_status, '')) != 'duplicate_retired'
        AND EXISTS (
          SELECT 1 FROM library_document_blocks
          WHERE library_item_id = library_items.id
        )
        AND NOT EXISTS (
          SELECT 1 FROM library_navigation_items
          WHERE library_item_id = library_items.id
        )
      ORDER BY id
    ''');

      var built = 0;
      var stillEmpty = 0;
      var missingFiles = 0;
      final results = <Map<String, Object?>>[];
      final bySourceType = <String, int>{};

      for (final row in rows) {
        final id = row['id'] as String;
        final title = row['title']?.toString() ?? '';
        final sourceType = row['source_type']?.toString() ?? '';
        final relativePath = row['relative_path']?.toString() ?? '';
        bySourceType[sourceType] = (bySourceType[sourceType] ?? 0) + 1;

        final file = File(p.join(rootPath, relativePath));
        if (!await file.exists()) {
          missingFiles += 1;
          results.add(<String, Object?>{
            'id': id,
            'title': title,
            'source_type': sourceType,
            'status': 'missing_file',
            'path': file.path,
          });
          continue;
        }

        if (!apply) {
          results.add(<String, Object?>{
            'id': id,
            'title': title,
            'source_type': sourceType,
            'status': 'dry_run',
          });
          continue;
        }

        await CommentaryResearchLibraryService.instance.ensureNavigationIndexed(
          db: db,
          libraryItemId: id,
          file: file,
        );
        final navCount = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM library_navigation_items WHERE library_item_id = ?',
          <Object?>[id],
        );
        final textBlockCount = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM library_text_blocks WHERE library_item_id = ?',
          <Object?>[id],
        );
        final navAfter = (navCount.first['c'] as num?)?.toInt() ?? 0;
        final textBlocksAfter =
            (textBlockCount.first['c'] as num?)?.toInt() ?? 0;
        if (navAfter > 0) {
          built += 1;
        } else {
          stillEmpty += 1;
        }
        results.add(<String, Object?>{
          'id': id,
          'title': title,
          'source_type': sourceType,
          'status': navAfter > 0 ? 'built' : 'failed',
          'nav_items_after': navAfter,
          'text_blocks_after': textBlocksAfter,
        });
      }

      final report = <String, Object?>{
        'apply': apply,
        'items_scanned': rows.length,
        'by_source_type': bySourceType,
        'built': built,
        'still_empty': stillEmpty,
        'missing_files': missingFiles,
        'results': results,
      };

      final encoded = const JsonEncoder.withIndent('  ').convert(report);
      if (reportPath != null && reportPath.trim().isNotEmpty) {
        await File(reportPath).writeAsString(encoded);
      }
      print(
        '${apply ? "APPLIED" : "DRY RUN"}: ${rows.length} broken item(s) found; '
        '$built built, $stillEmpty still empty after repair attempt, '
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
      if (supportDir.existsSync()) {
        await supportDir.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
