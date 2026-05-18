import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../library/data/library_epub_metadata.dart';
import 'elibrary_folder_policy.dart';

const bool _debugELibraryCleanupLogs = false;

class ELibraryDuplicateCleanupService {
  ELibraryDuplicateCleanupService._();

  static final ELibraryDuplicateCleanupService instance =
      ELibraryDuplicateCleanupService._();

  Future<ELibraryDuplicateCleanupReport> quarantineDuplicates({
    void Function(ELibraryDuplicateCleanupProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final scannedRoots = <String>[
      p.join(rootPath, 'ePubs'),
      p.join(rootPath, 'PDFs'),
      p.join(rootPath, 'Commentaries'),
      p.join(rootPath, 'Research'),
      p.join(rootPath, 'TEST_Downloads'),
    ];
    final reportRoot = Directory(p.join(rootPath, 'download_reports'));
    await reportRoot.create(recursive: true);
    final quarantineRoot = Directory(
      ELibraryFolderPolicy.quarantineRoot(rootPath),
    );
    await quarantineRoot.create(recursive: true);

    final report = _MutableELibraryDuplicateCleanupReport(
      startedAt: startedAt,
      sourcePathsScanned: scannedRoots,
      quarantineRoot: quarantineRoot.path,
    );

    final discovered = <File>[];
    final seen = <String>{};
    for (final sourceRoot in scannedRoots) {
      final directory = Directory(sourceRoot);
      if (!await directory.exists()) continue;
      await _collectCandidateFiles(directory, discovered, seen);
    }
    report.filesFound = discovered.length;

    final groups = <String, List<File>>{};
    for (final file in discovered) {
      final editionKey = ELibraryFolderPolicy.editionKeyForFileName(
        p.basename(file.path),
      );
      if (editionKey.isEmpty) continue;
      groups.putIfAbsent(editionKey, () => <File>[]).add(file);
    }
    report.groupsFound = groups.length;

    onProgress?.call(
      ELibraryDuplicateCleanupProgress(
        currentPath: 'Scanning duplicate candidates...',
        processedCount: 0,
        filesFound: report.filesFound,
        groupsFound: groups.length,
        quarantinedCount: report.filesQuarantined,
        preservedCount: report.filesPreserved,
        conflictedCount: report.filesConflicted,
        elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
      ),
    );

    try {
      for (final entry in groups.entries) {
        if (isCancelled?.call() ?? false) break;
        final editionKey = entry.key;
        final files = entry.value;
        if (files.length < 2) {
          continue;
        }

        final canonicalFiles = files
            .where((file) => _isCanonicalManagedPath(file.path))
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));

        if (canonicalFiles.isEmpty) {
          report.groupsWithoutCanonical += 1;
          for (final file in files) {
            report.entries.add(
              ELibraryDuplicateCleanupEntry(
                editionKey: editionKey,
                sourceRelativePath: _relativePath(rootPath, file.path),
                canonicalRelativePath: null,
                fileSize: await file.length(),
                sha256: await _sha256ForFile(file),
                epubTitle: await _epubTitleForFile(file),
                abbreviation: ELibraryFolderPolicy.detectedAbbreviation(
                  p.basename(file.path),
                ),
                identicalToCanonical: false,
                differentEdition: false,
                actionTaken: 'preserved_no_canonical',
                reason:
                    'No canonical managed copy was found, so this candidate was only reported.',
              ),
            );
          }
          continue;
        }

        final canonicalFile = canonicalFiles.first;
        final canonicalHash = await _sha256ForFile(canonicalFile);
        final canonicalRelative = _relativePath(rootPath, canonicalFile.path);

        for (final file in files) {
          if (file.path == canonicalFile.path) {
            report.entries.add(
              ELibraryDuplicateCleanupEntry(
                editionKey: editionKey,
                sourceRelativePath: _relativePath(rootPath, file.path),
                canonicalRelativePath: canonicalRelative,
                fileSize: await file.length(),
                sha256: canonicalHash,
                epubTitle: await _epubTitleForFile(file),
                abbreviation: ELibraryFolderPolicy.detectedAbbreviation(
                  p.basename(file.path),
                ),
                identicalToCanonical: true,
                differentEdition: false,
                actionTaken: 'kept_canonical',
                reason: 'This is the managed copy that will remain active.',
              ),
            );
            report.filesPreserved += 1;
            continue;
          }

          final sourceSize = await file.length();
          final sourceHash = await _sha256ForFile(file);
          final identical = sourceSize == (await canonicalFile.length()) &&
              sourceHash == canonicalHash;
          final quarantinePath = _uniqueQuarantinePath(
            rootPath: rootPath,
            sourcePath: file.path,
            suffix: identical ? 'duplicate' : 'conflict',
          );
          await _copyVerified(file, File(quarantinePath), sourceSize, sourceHash);
          await file.delete();
          report.filesQuarantined += 1;
          if (identical) {
            report.filesIdentical += 1;
          } else {
            report.filesConflicted += 1;
          }
          report.entries.add(
            ELibraryDuplicateCleanupEntry(
              editionKey: editionKey,
              sourceRelativePath: _relativePath(rootPath, file.path),
              canonicalRelativePath: canonicalRelative,
              fileSize: sourceSize,
              sha256: sourceHash,
              epubTitle: await _epubTitleForFile(file),
              abbreviation: ELibraryFolderPolicy.detectedAbbreviation(
                p.basename(file.path),
              ),
              identicalToCanonical: identical,
              differentEdition: false,
              actionTaken: identical
                  ? 'quarantined_duplicate'
                  : 'quarantined_conflict',
              reason: identical
                  ? 'Byte-identical duplicate of the canonical managed file.'
                  : 'Same edition key but different bytes, so the file was quarantined for review.',
            ),
          );
        }

        onProgress?.call(
          ELibraryDuplicateCleanupProgress(
            currentPath: canonicalRelative,
            processedCount: report.entries.length,
            filesFound: report.filesFound,
            groupsFound: groups.length,
            quarantinedCount: report.filesQuarantined,
            preservedCount: report.filesPreserved,
            conflictedCount: report.filesConflicted,
            elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
          ),
        );
      }
    } catch (error) {
      report.failures.add(error.toString());
      if (_debugELibraryCleanupLogs) {
        debugPrint('[ELibraryDuplicateCleanup] failed: $error');
      }
    }

    report.completedAt = DateTime.now().toUtc();
    report.elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
    final reportFilePath = p.join(
      reportRoot.path,
      'egw_duplicate_cleanup_${_timestamp(report.completedAt!)}.json',
    );
    final completed = report.toReport(reportFilePath);
    await File(reportFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(completed.toJson()),
    );
    return completed;
  }

  Future<void> _collectCandidateFiles(
    Directory directory,
    List<File> discovered,
    Set<String> seen,
  ) async {
    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is Directory) {
        if (ELibraryFolderPolicy.isQuarantinePath(entity.path)) continue;
        if (_shouldSkipDirectory(entity.path)) continue;
        await _collectCandidateFiles(entity, discovered, seen);
        continue;
      }
      if (entity is! File) continue;
      if (ELibraryFolderPolicy.isQuarantinePath(entity.path)) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.epub')) continue;
      final normalized = p.normalize(entity.path);
      if (!seen.add(normalized)) continue;
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

  bool _isCanonicalManagedPath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    for (final canonical in const [
      'epubs/commentaries/egw_commentaries',
      'epubs/research/egw_books',
      'epubs/research/egw_devotionals',
      'pdfs/commentaries/egw_commentaries',
      'pdfs/research/egw_books',
      'pdfs/research/egw_devotionals',
    ]) {
      if (normalized.contains(canonical)) return true;
    }
    return false;
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

  Future<String> _sha256ForFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<String?> _epubTitleForFile(File file) async {
    try {
      final metadata = await readLibraryEpubMetadata(file);
      final title = metadata?.title?.trim();
      if (title != null && title.isNotEmpty) {
        return title;
      }
    } catch (_) {
      // Fall through.
    }
    return null;
  }

  Future<String?> _writableLibraryRootPath() async {
    final accessible = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    if (accessible != null && accessible.trim().isNotEmpty) return accessible;
    final selection = await LibraryRootService.instance.loadSelection();
    if (selection.path == null || !selection.exists) return null;
    return selection.path;
  }

  String _relativePath(String rootPath, String path) {
    final normalizedRoot = p.normalize(rootPath.trim());
    final normalizedPath = p.normalize(path.trim());
    if (!p.isWithin(normalizedRoot, normalizedPath) &&
        normalizedRoot != normalizedPath) {
      return p.basename(normalizedPath);
    }
    return p.relative(normalizedPath, from: normalizedRoot);
  }

  String _uniqueQuarantinePath({
    required String rootPath,
    required String sourcePath,
    required String suffix,
  }) {
    final candidate = ELibraryFolderPolicy.quarantinePathFor(
      rootPath,
      sourcePath,
      suffix: suffix,
    );
    final directory = p.dirname(candidate);
    final base = p.basenameWithoutExtension(candidate);
    final extension = p.extension(candidate);
    var result = candidate;
    var counter = 1;
    while (File(result).existsSync()) {
      result = p.join(directory, '${base}_$counter$extension');
      counter += 1;
    }
    return result;
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

class ELibraryDuplicateCleanupReport {
  const ELibraryDuplicateCleanupReport({
    required this.startedAt,
    required this.completedAt,
    required this.elapsedSeconds,
    required this.filesFound,
    required this.groupsFound,
    required this.filesQuarantined,
    required this.filesIdentical,
    required this.filesConflicted,
    required this.filesPreserved,
    required this.groupsWithoutCanonical,
    required this.sourcePathsScanned,
    required this.quarantineRoot,
    required this.entries,
    required this.failures,
    required this.reportFilePath,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final double elapsedSeconds;
  final int filesFound;
  final int groupsFound;
  final int filesQuarantined;
  final int filesIdentical;
  final int filesConflicted;
  final int filesPreserved;
  final int groupsWithoutCanonical;
  final List<String> sourcePathsScanned;
  final String quarantineRoot;
  final List<ELibraryDuplicateCleanupEntry> entries;
  final List<String> failures;
  final String reportFilePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'started_at': startedAt.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
    'elapsed_seconds': elapsedSeconds,
    'files_found': filesFound,
    'groups_found': groupsFound,
    'files_quarantined': filesQuarantined,
    'files_identical': filesIdentical,
    'files_conflicted': filesConflicted,
    'files_preserved': filesPreserved,
    'groups_without_canonical': groupsWithoutCanonical,
    'source_paths_scanned': sourcePathsScanned,
    'quarantine_root': quarantineRoot,
    'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    'failures': failures,
    'report_file_path': reportFilePath,
  };
}

class ELibraryDuplicateCleanupEntry {
  const ELibraryDuplicateCleanupEntry({
    required this.editionKey,
    required this.sourceRelativePath,
    required this.canonicalRelativePath,
    required this.fileSize,
    required this.sha256,
    required this.epubTitle,
    required this.abbreviation,
    required this.identicalToCanonical,
    required this.differentEdition,
    required this.actionTaken,
    required this.reason,
  });

  final String editionKey;
  final String sourceRelativePath;
  final String? canonicalRelativePath;
  final int fileSize;
  final String sha256;
  final String? epubTitle;
  final String abbreviation;
  final bool identicalToCanonical;
  final bool differentEdition;
  final String actionTaken;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'edition_key': editionKey,
    'source_relative_path': sourceRelativePath,
    'canonical_relative_path': canonicalRelativePath,
    'file_size': fileSize,
    'sha256': sha256,
    'epub_title': epubTitle,
    'abbreviation': abbreviation,
    'identical_to_canonical': identicalToCanonical,
    'different_edition': differentEdition,
    'action_taken': actionTaken,
    'reason': reason,
  };
}

class ELibraryDuplicateCleanupProgress {
  const ELibraryDuplicateCleanupProgress({
    required this.currentPath,
    required this.processedCount,
    required this.filesFound,
    required this.groupsFound,
    required this.quarantinedCount,
    required this.preservedCount,
    required this.conflictedCount,
    required this.elapsedSeconds,
  });

  final String currentPath;
  final int processedCount;
  final int filesFound;
  final int groupsFound;
  final int quarantinedCount;
  final int preservedCount;
  final int conflictedCount;
  final double elapsedSeconds;
}

class _MutableELibraryDuplicateCleanupReport {
  _MutableELibraryDuplicateCleanupReport({
    required this.startedAt,
    required this.sourcePathsScanned,
    required this.quarantineRoot,
  });

  final DateTime startedAt;
  DateTime? completedAt;
  double elapsedSeconds = 0;
  int filesFound = 0;
  int groupsFound = 0;
  int filesQuarantined = 0;
  int filesIdentical = 0;
  int filesConflicted = 0;
  int filesPreserved = 0;
  int groupsWithoutCanonical = 0;
  final List<String> sourcePathsScanned;
  final String quarantineRoot;
  final List<ELibraryDuplicateCleanupEntry> entries =
      <ELibraryDuplicateCleanupEntry>[];
  final List<String> failures = <String>[];

  ELibraryDuplicateCleanupReport toReport(String reportFilePath) {
    final done = completedAt ?? DateTime.now().toUtc();
    return ELibraryDuplicateCleanupReport(
      startedAt: startedAt,
      completedAt: done,
      elapsedSeconds: elapsedSeconds,
      filesFound: filesFound,
      groupsFound: groupsFound,
      filesQuarantined: filesQuarantined,
      filesIdentical: filesIdentical,
      filesConflicted: filesConflicted,
      filesPreserved: filesPreserved,
      groupsWithoutCanonical: groupsWithoutCanonical,
      sourcePathsScanned: List<String>.unmodifiable(sourcePathsScanned),
      quarantineRoot: quarantineRoot,
      entries: List<ELibraryDuplicateCleanupEntry>.unmodifiable(entries),
      failures: List<String>.unmodifiable(failures),
      reportFilePath: reportFilePath,
    );
  }
}
