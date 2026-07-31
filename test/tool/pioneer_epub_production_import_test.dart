// Explicit, opt-in production execution harness. A normal test run is a no-op.
// It never writes to the selected source folder.
import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_bulk_import_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_folder_inventory_service.dart';

const Set<String> _pilotFiles = <String>{
  'christ_and_his_righteousness.epub',
  'aplib_a_t_jones_the_signs_of_the_times_1896_1900_epub_fe41b09b.epub',
  'aplib_james_white_our_faith_and_hope_no_1_epub_8f12fa59.epub',
  'aplib_uriah_smith_the_marvel_of_nations_epub_789838f1.epub',
  'aplib_j_n_loughborough_conference_address_ottowa_illinois_epub_27b68f87.epub',
};

const Set<String> _legacyUpgradeTitles = <String>{
  'the cross and its shadow',
  'the story of the seer of patmos',
  'the consecrated way to christian perfection',
  'sanctification',
};

const Set<String> _duplicateAlternateFiles = <String>{
  'aplib_storrs_six_sermons_on_the_inquiry_is_there_immortality_in_sin_and_suffering_epub_df071727.epub',
  'aplib_uriah_smith_mortal_or_immortal_which_epub_efc33cec.epub',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('explicit Pioneer production pilot/import', () async {
    if (Platform.environment['RUN_PIONEER_PRODUCTION_IMPORT'] != '1') return;

    final sourcePath =
        (Platform.environment['PIONEER_EPUB_SOURCE_FOLDER'] ?? '').trim();
    final rootPath = (Platform.environment['PIONEER_LIBRARY_ROOT'] ?? '')
        .trim();
    final mode = (Platform.environment['PIONEER_IMPORT_MODE'] ?? 'pilot')
        .trim()
        .toLowerCase();
    final reportPath =
        (Platform.environment['PIONEER_PROGRESS_REPORT_PATH'] ?? '').trim();
    if (sourcePath.isEmpty || rootPath.isEmpty) {
      fail('PIONEER_EPUB_SOURCE_FOLDER and PIONEER_LIBRARY_ROOT are required.');
    }

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'getApplicationDocumentsDirectory':
              return rootPath;
            case 'getApplicationSupportDirectory':
            case 'getTemporaryDirectory':
            case 'getLibraryDirectory':
              return p.join(rootPath, '.studybible2_runtime');
          }
          return rootPath;
        });

    try {
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: rootPath);
      final inventory = await PioneerEpubFolderInventoryService.instance.survey(
        Directory(sourcePath),
        onProgress: (current, total, fileName) {
          if (current % 50 == 0 || current == total) {
            stdout.writeln('[pioneer-import] surveyed $current/$total');
          }
        },
      );

      final legacyEntries = inventory.entries
          .where(
            (entry) =>
                _legacyUpgradeTitles.contains(entry.title?.toLowerCase()),
          )
          .toList(growable: false);
      if (legacyEntries.length != 4 ||
          legacyEntries.any(
            (entry) => !entry.reusesLegacyLibraryItemIdentity,
          )) {
        fail(
          'The four legacy rows were not all resolved in the selected '
          'production database; refusing any import.',
        );
      }
      stdout.writeln(
        '[pioneer-import] verified legacy identities: '
        '${legacyEntries.map((entry) => '${entry.title}=${entry.libraryItemId}').join(', ')}',
      );

      final pilotEntries = inventory.entries
          .where(
            (entry) =>
                entry.isStructurallyValid &&
                _pilotFiles.contains(entry.fileName.toLowerCase()) &&
                !_legacyUpgradeTitles.contains(entry.title?.toLowerCase()),
          )
          .toList(growable: false);
      if (pilotEntries.length != _pilotFiles.length) {
        fail(
          'Expected ${_pilotFiles.length} pilot files, found '
          '${pilotEntries.length}: ${pilotEntries.map((e) => e.fileName)}',
        );
      }

      if (mode == 'full') {
        final incompletePilot = pilotEntries
            .where((entry) => !entry.isUnchanged)
            .toList(growable: false);
        if (incompletePilot.isNotEmpty) {
          fail(
            'The corrected pilot is not current for: '
            '${incompletePilot.map((entry) => entry.title).join(', ')}',
          );
        }
        for (final entry in pilotEntries) {
          _appendProgress(reportPath, <String, Object?>{
            'status': 'skipped_unchanged',
            'file': entry.fileName,
            'title': entry.title,
            'library_item_id': entry.libraryItemId,
          });
        }

        final legacySummary = await _importSequentially(
          inventory: inventory,
          entries: legacyEntries,
          label: 'legacy',
          reportPath: reportPath,
        );
        if (legacySummary.failed != 0 || legacySummary.ready != 4) {
          fail(
            'Legacy migration gate failed: ready=${legacySummary.ready}, '
            'failed=${legacySummary.failed}. Broad batch not started.',
          );
        }

        final excludedPaths = <String>{
          ...pilotEntries.map((entry) => entry.absolutePath),
          ...legacyEntries.map((entry) => entry.absolutePath),
        };
        final broadEntries = inventory.entries
            .where(
              (entry) =>
                  entry.isStructurallyValid &&
                  !excludedPaths.contains(entry.absolutePath) &&
                  !_duplicateAlternateFiles.contains(
                    entry.fileName.toLowerCase(),
                  ),
            )
            .toList(growable: false);
        for (final entry in inventory.entries.where(
          (entry) =>
              _duplicateAlternateFiles.contains(entry.fileName.toLowerCase()),
        )) {
          _appendProgress(reportPath, <String, Object?>{
            'status': 'skipped_duplicate_source',
            'file': entry.fileName,
            'title': entry.title,
            'reason': 'lexically later UUID-only alternate',
          });
        }
        for (final entry in inventory.invalid) {
          _appendProgress(reportPath, <String, Object?>{
            'status': 'skipped_invalid_existing_work',
            'file': entry.fileName,
            'title': entry.title,
            'reason': entry.rejectionReason,
          });
        }
        final broadSummary = await _importSequentially(
          inventory: inventory,
          entries: broadEntries,
          label: 'full',
          reportPath: reportPath,
        );
        stdout.writeln(
          '[pioneer-import:full] ready=${broadSummary.ready} '
          'unchanged=${broadSummary.unchanged} failed=${broadSummary.failed}',
        );
        return;
      }

      await _import(
        PioneerEpubFolderInventory(
          folderPath: inventory.folderPath,
          scannedAt: inventory.scannedAt,
          entries: pilotEntries,
          skippedNonEpubCount: inventory.skippedNonEpubCount,
        ),
        label: 'pilot',
      );
      if (mode == 'pilot') return;

      final pilotPaths = pilotEntries
          .map((entry) => entry.absolutePath)
          .toSet();
      final remainingEntries = inventory.entries
          .where(
            (entry) =>
                entry.isStructurallyValid &&
                !pilotPaths.contains(entry.absolutePath),
          )
          .toList(growable: false);
      await _import(
        PioneerEpubFolderInventory(
          folderPath: inventory.folderPath,
          scannedAt: inventory.scannedAt,
          entries: remainingEntries,
          skippedNonEpubCount: inventory.skippedNonEpubCount,
        ),
        label: 'remaining',
      );
    } finally {
      await UserDatabase.instance.close();
      await ELibraryDatabase.instance.close();
      LibraryRootService.instance.invalidateCachedSelection();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  }, timeout: Timeout.none);
}

class _SequentialImportSummary {
  const _SequentialImportSummary({
    required this.ready,
    required this.unchanged,
    required this.failed,
  });

  final int ready;
  final int unchanged;
  final int failed;
}

Future<_SequentialImportSummary> _importSequentially({
  required PioneerEpubFolderInventory inventory,
  required List<PioneerEpubInventoryEntry> entries,
  required String label,
  required String reportPath,
}) async {
  var ready = 0;
  var unchanged = 0;
  var failed = 0;
  final batchStopwatch = Stopwatch()..start();
  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final itemStopwatch = Stopwatch()..start();
    final title = entry.title ?? entry.fileName;
    stdout.writeln(
      '[pioneer-import:$label] Preparing ${index + 1} of ${entries.length}: '
      '$title',
    );
    if (entry.isUnchanged) {
      unchanged += 1;
      _appendProgress(reportPath, <String, Object?>{
        'status': 'skipped_unchanged',
        'file': entry.fileName,
        'title': entry.title,
        'library_item_id': entry.libraryItemId,
      });
      continue;
    }
    final singleInventory = PioneerEpubFolderInventory(
      folderPath: inventory.folderPath,
      scannedAt: inventory.scannedAt,
      entries: <PioneerEpubInventoryEntry>[entry],
      skippedNonEpubCount: 0,
    );
    try {
      final preparation = await PioneerEpubBulkImportService.instance.prepare(
        inventory: singleInventory,
      );
      if (preparation.preparationFailures.isNotEmpty ||
          preparation.targets.length != 1) {
        failed += 1;
        _appendProgress(reportPath, <String, Object?>{
          'status': 'failed',
          'phase': 'preparation',
          'file': entry.fileName,
          'title': entry.title,
          'library_item_id': entry.libraryItemId,
          'detail': preparation.preparationFailures
              .map((failure) => failure.technicalDetail)
              .join('; '),
        });
        continue;
      }
      final result = await LibraryAcquisitionBatchRunner.instance.activate(
        preparation.targets,
      );
      final outcome = result.outcomes.single;
      itemStopwatch.stop();
      if (outcome.isReady) {
        ready += 1;
        final elapsed = batchStopwatch.elapsed;
        final averageMs = elapsed.inMilliseconds / (index + 1);
        final remaining = entries.length - index - 1;
        stdout.writeln(
          '[pioneer-import:$label] ${entry.reusesLegacyLibraryItemIdentity ? 'Migrated legacy identity' : 'Imported'}: '
          '$title (${itemStopwatch.elapsed.inMilliseconds} ms, '
          'ETA ${(averageMs * remaining / 1000).round()} s)',
        );
        _appendProgress(reportPath, <String, Object?>{
          'status': entry.reusesLegacyLibraryItemIdentity
              ? 'migrated_legacy_identity'
              : 'imported',
          'file': entry.fileName,
          'title': entry.title,
          'library_item_id': entry.libraryItemId,
          'elapsed_ms': itemStopwatch.elapsedMilliseconds,
        });
      } else {
        failed += 1;
        _appendProgress(reportPath, <String, Object?>{
          'status': 'failed',
          'phase': outcome.phase.name,
          'file': entry.fileName,
          'title': entry.title,
          'library_item_id': entry.libraryItemId,
          'detail': outcome.technicalDetail,
          'elapsed_ms': itemStopwatch.elapsedMilliseconds,
        });
      }
    } catch (error, stackTrace) {
      itemStopwatch.stop();
      failed += 1;
      _appendProgress(reportPath, <String, Object?>{
        'status': 'failed',
        'phase': 'exception',
        'file': entry.fileName,
        'title': entry.title,
        'library_item_id': entry.libraryItemId,
        'detail': error.toString(),
        'stack': stackTrace.toString(),
        'elapsed_ms': itemStopwatch.elapsedMilliseconds,
      });
    }
  }
  return _SequentialImportSummary(
    ready: ready,
    unchanged: unchanged,
    failed: failed,
  );
}

void _appendProgress(String path, Map<String, Object?> event) {
  if (path.isEmpty) return;
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${jsonEncode(<String, Object?>{'recorded_at': DateTime.now().toUtc().toIso8601String(), ...event})}\n',
    mode: FileMode.append,
    flush: true,
  );
}

Future<void> _import(
  PioneerEpubFolderInventory inventory, {
  required String label,
}) async {
  final preparation = await PioneerEpubBulkImportService.instance.prepare(
    inventory: inventory,
    onProgress: (current, total, title) {
      stdout.writeln('[pioneer-import:$label] copy $current/$total $title');
    },
  );
  if (preparation.preparationFailures.isNotEmpty) {
    fail('$label preparation failures: ${preparation.preparationFailures}');
  }
  final result = await LibraryAcquisitionBatchRunner.instance.activate(
    preparation.targets,
    onProgress: (progress) {
      stdout.writeln(
        '[pioneer-import:$label] ${progress.current}/${progress.total} '
        '${progress.phase.name} ${progress.currentTitle}',
      );
    },
  );
  if (result.unavailableOutcomes.isNotEmpty) {
    fail('$label activation failures: ${result.unavailableOutcomes}');
  }
  stdout.writeln(
    '[pioneer-import:$label] ready=${result.readyCount} '
    'unchanged=${preparation.skippedUnchangedCount}',
  );
}
