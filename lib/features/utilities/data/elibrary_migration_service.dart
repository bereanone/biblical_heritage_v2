import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_author_resolver.dart';
import '../../library/data/library_epub_metadata.dart';

class LegacyELibraryMigrationService {
  LegacyELibraryMigrationService._();

  static final LegacyELibraryMigrationService instance =
      LegacyELibraryMigrationService._();

  Future<LegacyELibraryMigrationReport> migrate({
    void Function(LegacyELibraryMigrationProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    await LibraryRootService.instance.ensureStructure(rootPath);

    final scannedRoots = <String>[
      p.join(rootPath, 'ePubs'),
      p.join(rootPath, 'PDFs'),
      p.join(rootPath, 'Commentaries'),
      p.join(rootPath, 'Research'),
      p.join(rootPath, 'TEST_Downloads'),
    ];

    final reportRoot = Directory(p.join(rootPath, 'legacy_migration_reports'));
    await reportRoot.create(recursive: true);

    final report = _MutableLegacyELibraryMigrationReport(
      startedAt: startedAt,
      sourcePathsScanned: scannedRoots,
      destinationPathsCreated: <String>[
        p.join(rootPath, 'ePubs', 'Commentaries', 'EGW_Commentaries'),
        p.join(rootPath, 'ePubs', 'Commentaries', 'User'),
        p.join(rootPath, 'ePubs', 'Research', 'EGW_Books'),
        p.join(rootPath, 'ePubs', 'Research', 'EGW_Devotionals'),
        p.join(rootPath, 'ePubs', 'Research', 'User'),
        p.join(rootPath, 'PDFs', 'Commentaries', 'EGW_Commentaries'),
        p.join(rootPath, 'PDFs', 'Commentaries', 'User'),
        p.join(rootPath, 'PDFs', 'Research', 'EGW_Books'),
        p.join(rootPath, 'PDFs', 'Research', 'EGW_Devotionals'),
        p.join(rootPath, 'PDFs', 'Research', 'User'),
      ],
    );

    final discovered = <File>[];
    final seen = <String>{};
    for (final sourceRoot in scannedRoots) {
      final directory = Directory(sourceRoot);
      if (!await directory.exists()) continue;
      await _collectLegacyFiles(directory, discovered, seen);
    }

    report.filesFound = discovered.length;
    onProgress?.call(
      LegacyELibraryMigrationProgress(
        currentPath: 'Scanning legacy folders...',
        processedCount: 0,
        filesFound: report.filesFound,
        copiedCount: report.filesCopied,
        skippedDuplicateCount: report.filesSkippedDuplicate,
        renamedCount: report.filesRenamedDueToConflict,
        unclassifiedCount: report.filesUnclassified,
        failedCount: report.failures.length,
        elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
      ),
    );

    try {
      for (var index = 0; index < discovered.length; index++) {
        if (isCancelled?.call() ?? false) break;
        final sourceFile = discovered[index];
        final sourceRelative = p.relative(sourceFile.path, from: rootPath);
        final classification = _classify(sourceRelative);
        if (classification == null) {
          report.filesUnclassified += 1;
          report.entries.add(
            LegacyELibraryMigrationEntry(
              oldRelativePath: sourceRelative,
              newRelativePath: null,
              size: await sourceFile.length(),
              sha256: await _sha256ForFile(sourceFile),
              actionTaken: 'skipped',
              reason: 'Unclassified EPUB/PDF source path.',
            ),
          );
          continue;
        }

        final destinationRelative = classification.destinationRelativePath(
          p.basename(sourceFile.path),
        );
        final destinationPath = p.join(rootPath, destinationRelative);
        final destinationFile = File(destinationPath);
        final sourceSize = await sourceFile.length();
        final sourceHash = await _sha256ForFile(sourceFile);
        String finalDestinationPath = destinationPath;
        String actionTaken = 'copied';
        String reason = classification.reason;

        if (await destinationFile.exists()) {
          final destinationSize = await destinationFile.length();
          final destinationHash = destinationSize == sourceSize
              ? await _sha256ForFile(destinationFile)
              : null;
          if (destinationSize == sourceSize &&
              destinationHash != null &&
              destinationHash == sourceHash) {
            report.filesSkippedDuplicate += 1;
            report.entries.add(
              LegacyELibraryMigrationEntry(
                oldRelativePath: sourceRelative,
                newRelativePath: destinationRelative,
                size: sourceSize,
                sha256: sourceHash,
                actionTaken: 'skipped_duplicate',
                reason: 'Destination already has the same file.',
              ),
            );
            continue;
          }

          final renamedPath = _safeConflictPath(destinationPath);
          final renamedFile = File(renamedPath);
          await _copyVerified(sourceFile, renamedFile, sourceSize, sourceHash);
          await _registerMigratedMetadata(
            relativePath: p.relative(renamedPath, from: rootPath),
            file: renamedFile,
            classification: classification,
            sourceRelativePath: sourceRelative,
            sha256: sourceHash,
          );
          report.filesRenamedDueToConflict += 1;
          finalDestinationPath = renamedPath;
          actionTaken = 'copied_renamed';
          reason =
              'Destination existed with different content, so a safe suffix was used.';
        } else {
          await _copyVerified(
            sourceFile,
            destinationFile,
            sourceSize,
            sourceHash,
          );
          await _registerMigratedMetadata(
            relativePath: p.relative(destinationPath, from: rootPath),
            file: destinationFile,
            classification: classification,
            sourceRelativePath: sourceRelative,
            sha256: sourceHash,
          );
        }

        report.filesCopied += 1;
        report.entries.add(
          LegacyELibraryMigrationEntry(
            oldRelativePath: sourceRelative,
            newRelativePath: p.relative(finalDestinationPath, from: rootPath),
            size: sourceSize,
            sha256: sourceHash,
            actionTaken: actionTaken,
            reason: reason,
          ),
        );

        onProgress?.call(
          LegacyELibraryMigrationProgress(
            currentPath: sourceRelative,
            processedCount: index + 1,
            filesFound: report.filesFound,
            copiedCount: report.filesCopied,
            skippedDuplicateCount: report.filesSkippedDuplicate,
            renamedCount: report.filesRenamedDueToConflict,
            unclassifiedCount: report.filesUnclassified,
            failedCount: report.failures.length,
            elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
          ),
        );
      }
    } catch (error) {
      report.failures.add(error.toString());
      debugPrint('[ELibraryMigration] failed: $error');
    }

    report.completedAt = DateTime.now().toUtc();
    report.elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
    if (report.filesFound == 0 &&
        report.entries.isEmpty &&
        report.failures.isEmpty) {
      return report.toReport('');
    }
    final reportFilePath = p.join(
      reportRoot.path,
      'elibrary_folder_migration_${_timestamp(report.completedAt!)}.json',
    );
    final completed = report.toReport(reportFilePath);
    await File(reportFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(completed.toJson()),
    );
    return completed;
  }

  Future<void> _collectLegacyFiles(
    Directory directory,
    List<File> discovered,
    Set<String> seen,
  ) async {
    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is Directory) {
        if (_shouldSkipDirectory(entity.path)) continue;
        await _collectLegacyFiles(entity, discovered, seen);
        continue;
      }
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.epub') && !lower.endsWith('.pdf')) continue;
      final normalized = p.normalize(entity.path);
      if (!seen.add(normalized)) continue;
      if (_isCanonicalPath(normalized)) continue;
      if (_shouldSkipDirectory(p.dirname(normalized))) continue;
      discovered.add(entity);
    }
  }

  bool _shouldSkipDirectory(String path) {
    final normalized = p.normalize(path).toLowerCase();
    for (final segment in const [
      'index',
      'download_reports',
      'legacy_migration_reports',
      'backups',
      'legacybackup',
    ]) {
      if (normalized.contains('/$segment') ||
          normalized.endsWith('/$segment')) {
        return true;
      }
    }
    return false;
  }

  bool _isCanonicalPath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    for (final canonical in const [
      'epubs/commentaries/egw_commentaries',
      'epubs/commentaries/user',
      'epubs/research/egw_books',
      'epubs/research/egw_devotionals',
      'epubs/research/user',
      'pdfs/commentaries/egw_commentaries',
      'pdfs/commentaries/user',
      'pdfs/research/egw_books',
      'pdfs/research/egw_devotionals',
      'pdfs/research/user',
    ]) {
      if (normalized.contains(canonical)) return true;
    }
    return false;
  }

  _LegacyClassification? _classify(String relativePath) {
    final normalized = p.normalize(relativePath).toLowerCase();
    final parts = p.split(normalized);
    if (parts.isEmpty) return null;

    final isPdf = normalized.endsWith('.pdf');
    final fileRoot = isPdf ? 'pdfs' : 'epubs';

    if (parts.first == 'test_downloads') {
      if (normalized.contains('$fileRoot/egw_books')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Books', fileName),
          reason: 'Legacy TEST_Downloads EGW Books path.',
          libraryRole: 'research',
          collectionName: 'EGW Books',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      if (normalized.contains('$fileRoot/egw_devotionals')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Devotionals', fileName),
          reason: 'Legacy TEST_Downloads EGW Devotionals path.',
          libraryRole: 'research',
          collectionName: 'EGW Devotionals',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      if (normalized.contains('$fileRoot/commentaries')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Commentaries', 'EGW_Commentaries', fileName),
          reason: 'Legacy TEST_Downloads commentaries path.',
          libraryRole: 'commentary',
          collectionName: 'EGW Commentaries',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      return _LegacyClassification(
        destinationRelativePath: (fileName) =>
            p.join(fileRoot, 'Research', 'User', fileName),
        reason: 'Legacy TEST_Downloads path without a clearer collection.',
        libraryRole: 'research',
        collectionName: 'User',
        sourceType: 'user_added',
        sourceSite: null,
      );
    }

    if (parts.first == 'commentaries') {
      return _LegacyClassification(
        destinationRelativePath: (fileName) =>
            p.join(fileRoot, 'Commentaries', 'EGW_Commentaries', fileName),
        reason: 'Legacy Commentary folder.',
        libraryRole: 'commentary',
        collectionName: 'EGW Commentaries',
        sourceType: 'official_download',
        sourceSite: 'egwwritings.org',
      );
    }

    if (parts.first == 'research') {
      if (normalized.contains('egw_books')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Books', fileName),
          reason: 'Legacy Research EGW Books folder.',
          libraryRole: 'research',
          collectionName: 'EGW Books',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      if (normalized.contains('egw_devotionals')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Devotionals', fileName),
          reason: 'Legacy Research EGW Devotionals folder.',
          libraryRole: 'research',
          collectionName: 'EGW Devotionals',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      return _LegacyClassification(
        destinationRelativePath: (fileName) =>
            p.join(fileRoot, 'Research', 'User', fileName),
        reason: 'Legacy Research folder without clearer collection.',
        libraryRole: 'research',
        collectionName: 'User',
        sourceType: 'user_added',
        sourceSite: null,
      );
    }

    if (parts.first == 'epubs' || parts.first == 'pdfs') {
      if (normalized.contains('egw_books')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Books', fileName),
          reason: 'Legacy ePub/PDF EGW Books folder.',
          libraryRole: 'research',
          collectionName: 'EGW Books',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      if (normalized.contains('egw_devotionals')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Research', 'EGW_Devotionals', fileName),
          reason: 'Legacy ePub/PDF EGW Devotionals folder.',
          libraryRole: 'research',
          collectionName: 'EGW Devotionals',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      if (normalized.contains('commentaries')) {
        return _LegacyClassification(
          destinationRelativePath: (fileName) =>
              p.join(fileRoot, 'Commentaries', 'EGW_Commentaries', fileName),
          reason: 'Legacy ePub/PDF commentaries folder.',
          libraryRole: 'commentary',
          collectionName: 'EGW Commentaries',
          sourceType: 'official_download',
          sourceSite: 'egwwritings.org',
        );
      }
      return _LegacyClassification(
        destinationRelativePath: (fileName) =>
            p.join(fileRoot, 'Research', 'User', fileName),
        reason: 'Legacy ePub/PDF folder without a clearer collection.',
        libraryRole: 'research',
        collectionName: 'User',
        sourceType: 'user_added',
        sourceSite: null,
      );
    }

    return null;
  }

  Future<void> _copyVerified(
    File sourceFile,
    File destinationFile,
    int sourceSize,
    String sourceHash,
  ) async {
    await destinationFile.parent.create(recursive: true);
    final tempFile = File('${destinationFile.path}.copying');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await sourceFile.copy(tempFile.path);
    final copiedSize = await tempFile.length();
    final copiedHash = await _sha256ForFile(tempFile);
    if (copiedSize != sourceSize || copiedHash != sourceHash) {
      await tempFile.delete();
      throw StateError('Copy verification failed for ${sourceFile.path}');
    }
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }
    await tempFile.rename(destinationFile.path);
  }

  Future<void> _registerMigratedMetadata({
    required String relativePath,
    required File file,
    required _LegacyClassification classification,
    required String sourceRelativePath,
    required String sha256,
  }) async {
    final stat = await file.stat();
    final db = await UserDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final now = DateTime.now().toUtc().toIso8601String();
    final isEpub = p.extension(file.path).toLowerCase() == '.epub';
    final author = await _resolveMigratedAuthor(
      file: file,
      classification: classification,
      relativePath: relativePath,
      isEpub: isEpub,
    );
    final title = await _resolveMigratedTitle(file: file, isEpub: isEpub);
    final newItemId = _itemId(classification.libraryRole, relativePath);
    final existingRows = await db.query(
      'library_items',
      columns: const ['id'],
      where: 'relative_path = ?',
      whereArgs: [sourceRelativePath],
    );
    for (final row in existingRows) {
      final oldId = row['id']?.toString() ?? '';
      if (oldId.isEmpty || oldId == newItemId) continue;
      await db.update(
        'library_links',
        {'library_item_id': newItemId, 'updated_at': now},
        where: 'library_item_id = ?',
        whereArgs: [oldId],
      );
      await db.delete('library_items', where: 'id = ?', whereArgs: [oldId]);
    }
    await db.insert('library_items', {
      'id': newItemId,
      'title': title,
      'author': author,
      'file_name': p.basename(file.path),
      'relative_path': relativePath,
      'file_hash': '${stat.size}:${stat.modified.millisecondsSinceEpoch}',
      'file_size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
      'mime_type': isEpub ? 'application/epub+zip' : 'application/pdf',
      'file_format': isEpub ? 'epub' : 'pdf',
      'folder_type': classification.libraryRole,
      'library_role': classification.libraryRole,
      'collection_name': classification.collectionName,
      'source_site': classification.sourceSite,
      'source_url': null,
      'date_added': now,
      'last_opened': null,
      'source_type': classification.sourceType,
      'indexed_at': isEpub ? null : now,
      'index_status': isEpub ? 'pending' : 'metadata_only',
      'index_error': null,
      'epub_href': null,
      'epub_cfi': null,
      'anchor_id': null,
      'spine_index': null,
      'paragraph_index': null,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
      'device_id': deviceId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint(
      '[ELibraryMigration] registered $sourceRelativePath -> $relativePath sha256=$sha256',
    );
  }

  Future<String?> _resolveMigratedAuthor({
    required File file,
    required _LegacyClassification classification,
    required String relativePath,
    required bool isEpub,
  }) async {
    if (!isEpub) {
      return resolveLibraryAuthor(
        author: null,
        collectionName: classification.collectionName,
        sourceSite: classification.sourceSite,
        relativePath: relativePath,
      );
    }

    return resolveLibraryAuthorFromEpub(
      file,
      collectionName: classification.collectionName,
      sourceSite: classification.sourceSite,
      relativePath: relativePath,
    );
  }

  Future<String> _resolveMigratedTitle({
    required File file,
    required bool isEpub,
  }) async {
    if (!isEpub) {
      return p.basenameWithoutExtension(file.path);
    }

    final metadata = await readLibraryEpubMetadata(file);
    final title = metadata?.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }

    return p.basenameWithoutExtension(file.path).replaceAll('_', ' ').trim();
  }

  String _itemId(String folderType, String relativePath) {
    return 'library_item_${_slug(folderType)}_${_slug(relativePath)}';
  }

  String _slug(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _safeConflictPath(String destinationPath) {
    final directory = p.dirname(destinationPath);
    final name = p.basenameWithoutExtension(destinationPath);
    final extension = p.extension(destinationPath);
    final timestamp = _timestamp(DateTime.now().toUtc());
    var candidate = p.join(directory, '${name}__legacy_$timestamp$extension');
    var counter = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(
        directory,
        '${name}__legacy_${timestamp}_$counter$extension',
      );
      counter += 1;
    }
    return candidate;
  }

  Future<String?> _writableLibraryRootPath() async {
    final accessible = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    if (accessible != null && accessible.trim().isNotEmpty) return accessible;
    final selection = await LibraryRootService.instance.loadSelection();
    if (selection.path == null || !selection.exists) return null;
    return selection.path;
  }

  Future<String> _sha256ForFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

class LegacyELibraryMigrationReport {
  const LegacyELibraryMigrationReport({
    required this.startedAt,
    required this.completedAt,
    required this.elapsedSeconds,
    required this.filesFound,
    required this.filesCopied,
    required this.filesSkippedDuplicate,
    required this.filesRenamedDueToConflict,
    required this.filesUnclassified,
    required this.failures,
    required this.sourcePathsScanned,
    required this.destinationPathsCreated,
    required this.entries,
    required this.reportFilePath,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final double elapsedSeconds;
  final int filesFound;
  final int filesCopied;
  final int filesSkippedDuplicate;
  final int filesRenamedDueToConflict;
  final int filesUnclassified;
  final List<String> failures;
  final List<String> sourcePathsScanned;
  final List<String> destinationPathsCreated;
  final List<LegacyELibraryMigrationEntry> entries;
  final String reportFilePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'started_at': startedAt.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
    'elapsed_seconds': elapsedSeconds,
    'files_found': filesFound,
    'files_moved_or_copied': filesCopied,
    'skipped_duplicates': filesSkippedDuplicate,
    'renamed_conflicts': filesRenamedDueToConflict,
    'files_unclassified': filesUnclassified,
    'failures': failures,
    'source_paths_scanned': sourcePathsScanned,
    'destination_paths_created': destinationPathsCreated,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'report_file_path': reportFilePath,
  };
}

class LegacyELibraryMigrationEntry {
  const LegacyELibraryMigrationEntry({
    required this.oldRelativePath,
    required this.newRelativePath,
    required this.size,
    required this.sha256,
    required this.actionTaken,
    required this.reason,
  });

  final String oldRelativePath;
  final String? newRelativePath;
  final int size;
  final String sha256;
  final String actionTaken;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'old_relative_path': oldRelativePath,
    'new_relative_path': newRelativePath,
    'size': size,
    'sha256': sha256,
    'action_taken': actionTaken,
    'reason': reason,
  };
}

class LegacyELibraryMigrationProgress {
  const LegacyELibraryMigrationProgress({
    required this.currentPath,
    required this.processedCount,
    required this.filesFound,
    required this.copiedCount,
    required this.skippedDuplicateCount,
    required this.renamedCount,
    required this.unclassifiedCount,
    required this.failedCount,
    required this.elapsedSeconds,
  });

  final String currentPath;
  final int processedCount;
  final int filesFound;
  final int copiedCount;
  final int skippedDuplicateCount;
  final int renamedCount;
  final int unclassifiedCount;
  final int failedCount;
  final double elapsedSeconds;
}

class _MutableLegacyELibraryMigrationReport {
  _MutableLegacyELibraryMigrationReport({
    required this.startedAt,
    required this.sourcePathsScanned,
    required this.destinationPathsCreated,
  });

  final DateTime startedAt;
  DateTime? completedAt;
  double elapsedSeconds = 0;
  int filesFound = 0;
  int filesCopied = 0;
  int filesSkippedDuplicate = 0;
  int filesRenamedDueToConflict = 0;
  int filesUnclassified = 0;
  final List<String> failures = <String>[];
  final List<String> sourcePathsScanned;
  final List<String> destinationPathsCreated;
  final List<LegacyELibraryMigrationEntry> entries =
      <LegacyELibraryMigrationEntry>[];

  LegacyELibraryMigrationReport toReport(String reportFilePath) {
    final done = completedAt ?? DateTime.now().toUtc();
    return LegacyELibraryMigrationReport(
      startedAt: startedAt,
      completedAt: done,
      elapsedSeconds: elapsedSeconds,
      filesFound: filesFound,
      filesCopied: filesCopied,
      filesSkippedDuplicate: filesSkippedDuplicate,
      filesRenamedDueToConflict: filesRenamedDueToConflict,
      filesUnclassified: filesUnclassified,
      failures: List<String>.unmodifiable(failures),
      sourcePathsScanned: List<String>.unmodifiable(sourcePathsScanned),
      destinationPathsCreated: List<String>.unmodifiable(
        destinationPathsCreated,
      ),
      entries: List<LegacyELibraryMigrationEntry>.unmodifiable(entries),
      reportFilePath: reportFilePath,
    );
  }
}

class _LegacyClassification {
  const _LegacyClassification({
    required this.destinationRelativePath,
    required this.reason,
    required this.libraryRole,
    required this.collectionName,
    required this.sourceType,
    required this.sourceSite,
  });

  final String Function(String fileName) destinationRelativePath;
  final String reason;
  final String libraryRole;
  final String? collectionName;
  final String sourceType;
  final String? sourceSite;
}
