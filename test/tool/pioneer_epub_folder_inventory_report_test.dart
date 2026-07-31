// Read-only Pioneer EPUB folder inventory tool, mirroring the existing
// opt-in `test/tool/epub_canonical_overnight_batch_test.dart` convention:
// does nothing under a normal `flutter test` run, and only scans the real
// folder (never writes to a production database, never modifies/moves/
// deletes a single source file) when explicitly invoked with
// RUN_PIONEER_EPUB_INVENTORY=1, e.g.:
//
//   RUN_PIONEER_EPUB_INVENTORY=1 \
//   PIONEER_EPUB_INVENTORY_FOLDER="/path/to/Pioneers" \
//   flutter test test/tool/pioneer_epub_folder_inventory_report_test.dart --timeout=none
//
// Uses a throwaway, empty eLibrary database for the "already imported"
// comparison (never the real production eLibrary.db), so every run reports
// a fresh-install baseline ("N books ready to import") rather than risking
// any interaction with real library state. This is intentional: the Phase 3
// "Real-Library Execution Policy" requires a read-only inventory pass to be
// reviewed *before* any production-database write is attempted.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('read-only Pioneer EPUB folder inventory', () async {
    if (Platform.environment['RUN_PIONEER_EPUB_INVENTORY'] != '1') {
      return;
    }

    final folderPath =
        (Platform.environment['PIONEER_EPUB_INVENTORY_FOLDER'] ?? '').trim();
    if (folderPath.isEmpty) {
      stdout.writeln(
        '[pioneer-inventory] PIONEER_EPUB_INVENTORY_FOLDER not set; skipping.',
      );
      return;
    }
    final folder = Directory(p.normalize(folderPath));
    if (!await folder.exists()) {
      stdout.writeln('[pioneer-inventory] folder does not exist: $folderPath');
      return;
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final scratchSupport = await Directory.systemTemp.createTemp(
      'pioneer_inventory_support_',
    );
    final scratchDocuments = await Directory.systemTemp.createTemp(
      'pioneer_inventory_docs_',
    );
    final scratchRoot = await Directory.systemTemp.createTemp(
      'pioneer_inventory_root_',
    );

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getApplicationSupportDirectory':
              return scratchSupport.path;
            case 'getApplicationDocumentsDirectory':
              return scratchDocuments.path;
            case 'getTemporaryDirectory':
              return scratchSupport.path;
            case 'getLibraryDirectory':
              return scratchSupport.path;
          }
          return scratchSupport.path;
        });

    try {
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: scratchRoot.path);

      stdout.writeln('[pioneer-inventory] scanning: ${folder.path}');
      final stopwatch = Stopwatch()..start();
      final inventory = await PioneerEpubFolderInventoryService.instance.survey(
        folder,
        onProgress: (current, total, fileName) {
          if (current % 25 == 0 || current == total) {
            stdout.writeln(
              '[pioneer-inventory] checked $current of $total ($fileName)',
            );
          }
        },
      );
      stopwatch.stop();

      final reportRoot =
          (Platform.environment['PIONEER_EPUB_INVENTORY_REPORT_DIR'] ?? '')
              .trim()
              .isEmpty
          ? Directory.current.path
          : p.normalize(
              Platform.environment['PIONEER_EPUB_INVENTORY_REPORT_DIR']!.trim(),
            );
      final timestamp = _timestamp(DateTime.now().toUtc());
      final jsonPath = p.join(
        reportRoot,
        'PIONEER_EPUB_INVENTORY_REPORT_$timestamp.json',
      );

      final duplicateGroups = inventory.probableDuplicateGroups;
      final report = <String, Object?>{
        'source_folder': inventory.folderPath,
        'scanned_at': inventory.scannedAt.toIso8601String(),
        'elapsed_seconds': stopwatch.elapsedMilliseconds / 1000.0,
        'total_epub_files_found': inventory.totalFound,
        'skipped_non_epub_files': inventory.skippedNonEpubCount,
        'structurally_valid': inventory.validCount,
        'structurally_invalid': inventory.invalidCount,
        'already_prepared_unchanged': inventory.unchangedCount,
        'ready_to_import': inventory.needsImportCount,
        'missing_cover_count': inventory.missingCoverCount,
        'probable_duplicate_groups': duplicateGroups.length,
        'estimated_new_source_bytes': inventory.estimatedNewSourceBytes,
        'invalid_files': inventory.invalid
            .map(
              (e) => <String, Object?>{
                'source_relative_path': e.sourceRelativePath,
                'reason': e.rejectionReason,
              },
            )
            .toList(growable: false),
        'duplicate_groups': duplicateGroups.entries
            .map(
              (entry) => <String, Object?>{
                'key': entry.key,
                'files': entry.value
                    .map((e) => e.sourceRelativePath)
                    .toList(growable: false),
              },
            )
            .toList(growable: false),
      };

      await File(jsonPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );

      stdout.writeln('[pioneer-inventory] === SUMMARY ===');
      stdout.writeln('  total EPUB files found:      ${inventory.totalFound}');
      stdout.writeln(
        '  skipped (non-.epub):          ${inventory.skippedNonEpubCount}',
      );
      stdout.writeln('  structurally valid:           ${inventory.validCount}');
      stdout.writeln(
        '  structurally invalid:         ${inventory.invalidCount}',
      );
      stdout.writeln(
        '  already prepared/unchanged:   ${inventory.unchangedCount}',
      );
      stdout.writeln(
        '  ready to import:              ${inventory.needsImportCount}',
      );
      stdout.writeln(
        '  missing cover:                ${inventory.missingCoverCount}',
      );
      stdout.writeln(
        '  probable duplicate groups:    ${duplicateGroups.length}',
      );
      stdout.writeln(
        '  elapsed seconds:               ${(stopwatch.elapsedMilliseconds / 1000.0).toStringAsFixed(1)}',
      );
      stdout.writeln('[pioneer-inventory] report written to: $jsonPath');
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await UserDatabase.instance.close();
      await ELibraryDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      for (final dir in [scratchSupport, scratchDocuments, scratchRoot]) {
        if (dir.existsSync()) await dir.delete(recursive: true);
      }
    }
  });
}

String _timestamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}_'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}
