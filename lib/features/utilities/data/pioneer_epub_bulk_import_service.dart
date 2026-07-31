import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import '../../library/data/canonical_activation.dart';
import '../../library/data/library_acquisition_batch_runner.dart';
import 'elibrary_folder_policy.dart';
import 'pioneer_epub_folder_inventory_service.dart';

/// Result of copying/registering one folder's worth of Pioneer EPUBs into
/// the canonical database, immediately before the shared
/// [LibraryAcquisitionBatchRunner] activates them. Kept separate from
/// activation because "copy the byte-for-byte source into a managed
/// location and write its `library_items` row" and "canonicalize/activate
/// it" are different failure domains: a copy failure never touches the
/// canonicalizer, and an activation failure never re-copies anything.
class PioneerEpubImportPreparation {
  const PioneerEpubImportPreparation({
    required this.targets,
    required this.preparationFailures,
    required this.skippedUnchangedCount,
    required this.skippedInvalidCount,
  });

  /// Successfully copied/registered items, ready for
  /// [LibraryAcquisitionBatchRunner.activate].
  final List<LibraryAcquisitionBatchTarget> targets;

  /// Items whose copy/registration itself failed (e.g. disk full, a
  /// permission error) before canonicalization was ever attempted. Reported
  /// through the same typed outcome shape as an activation failure so the
  /// shared progress/result UI can show them together.
  final List<LibraryAcquisitionOutcome> preparationFailures;

  final int skippedUnchangedCount;
  final int skippedInvalidCount;
}

/// Copies every valid, not-yet-current EPUB found by
/// [PioneerEpubFolderInventoryService] into the app-managed
/// `ImportedPioneerEpubs` folder and registers/updates its `library_items`
/// row, then hands the resulting targets to the same
/// [LibraryAcquisitionBatchRunner] the EGW download flow uses for
/// canonicalization/activation — one book at a time, one transaction per
/// book, continuing past isolated failures. The external source folder and
/// its files are only ever opened for reading; nothing there is renamed,
/// moved, modified, or deleted.
class PioneerEpubBulkImportService {
  PioneerEpubBulkImportService._();

  static final PioneerEpubBulkImportService instance =
      PioneerEpubBulkImportService._();

  Future<PioneerEpubImportPreparation> prepare({
    required PioneerEpubFolderInventory inventory,
    void Function(int current, int total, String title)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      throw StateError('Library Root Folder is not selected.');
    }
    final destinationDir = Directory(
      p.join(rootPath, ELibraryFolderPolicy.pioneerImportedEpubsRelativeFolder),
    );
    await destinationDir.create(recursive: true);

    final needsImport = inventory.needsImport;
    final targets = <LibraryAcquisitionBatchTarget>[];
    final failures = <LibraryAcquisitionOutcome>[];
    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();

    for (var index = 0; index < needsImport.length; index++) {
      if (shouldContinue != null && !shouldContinue()) break;
      final entry = needsImport[index];
      final title = (entry.title?.trim().isNotEmpty ?? false)
          ? entry.title!.trim()
          : p.basenameWithoutExtension(entry.fileName);
      onProgress?.call(index + 1, needsImport.length, title);
      try {
        final relativePath = await _copyAndRegister(
          entry: entry,
          destinationDir: destinationDir,
          db: db,
          deviceId: deviceId,
          title: title,
        );
        targets.add(
          LibraryAcquisitionBatchTarget(
            libraryItemId: entry.libraryItemId,
            relativePath: relativePath,
            title: title,
          ),
        );
      } catch (error) {
        failures.add(
          LibraryAcquisitionOutcome(
            libraryItemId: entry.libraryItemId,
            phase: LibraryAcquisitionPhase.failedImport,
            userSummary:
                'The book could not be prepared for reading. The source '
                'file was not altered.',
            technicalDetail: error.toString(),
            retryable: true,
            hasReadableCanonicalGeneration: false,
            sourceFilePresent: true,
          ),
        );
      }
    }

    return PioneerEpubImportPreparation(
      targets: targets,
      preparationFailures: failures,
      skippedUnchangedCount: inventory.unchangedCount,
      skippedInvalidCount: inventory.invalidCount,
    );
  }

  /// Copies [entry]'s source bytes (never moving/renaming/deleting the
  /// original) into [destinationDir] and creates/updates its `library_items`
  /// row. Returns the relative path (under the Library Root) the canonical
  /// activation step should use.
  Future<String> _copyAndRegister({
    required PioneerEpubInventoryEntry entry,
    required Directory destinationDir,
    required Database db,
    required String deviceId,
    required String title,
  }) async {
    final sanitizedBase = p
        .basenameWithoutExtension(entry.fileName)
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    final fileName =
        '${sanitizedBase.isEmpty ? 'book' : sanitizedBase}_'
        '${entry.sha256.substring(0, 10)}.epub';
    final destination = File(p.join(destinationDir.path, fileName));
    if (!await destination.exists()) {
      // Copy (never move) the byte-for-byte source; the external original
      // is left completely untouched at entry.absolutePath.
      await File(entry.absolutePath).copy(destination.path);
    }
    final relativePath = p.join(
      ELibraryFolderPolicy.pioneerImportedEpubsRelativeFolder,
      fileName,
    );

    final stat = await destination.stat();
    final now = DateTime.now().toUtc().toIso8601String();
    final existingRows = await db.query(
      'library_items',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[entry.libraryItemId],
      limit: 1,
    );
    final sharedPayload = <String, Object?>{
      'title': title,
      'author': entry.author,
      'file_name': fileName,
      'relative_path': relativePath,
      'file_hash': '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
      'file_size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
      'mime_type': 'application/epub+zip',
      'file_format': 'epub',
      'folder_type': 'pioneer_epub_import',
      'library_role': 'pioneer_epub_import',
      'collection_name': 'Pioneer Library',
      'source_type': 'pioneer_epub_import',
      'pioneer_source_relative_path': entry.sourceRelativePath,
      'pioneer_source_fingerprint': entry.sha256,
      'updated_at': now,
      'deleted_at': null,
    };
    if (existingRows.isEmpty) {
      await db.insert('library_items', <String, Object?>{
        'id': entry.libraryItemId,
        ...sharedPayload,
        'source_site': null,
        'source_url': null,
        'cover_path': null,
        'date_added': now,
        'last_opened': null,
        'index_status': 'metadata_only',
        'index_error': null,
        'epub_href': null,
        'epub_cfi': null,
        'anchor_id': null,
        'spine_index': null,
        'paragraph_index': null,
        'is_missing': 0,
        'created_at': now,
        'device_id': deviceId,
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
    } else {
      await db.update(
        'library_items',
        sharedPayload,
        where: 'id = ?',
        whereArgs: <Object?>[entry.libraryItemId],
      );
    }
    return relativePath;
  }
}
