import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';

const bool _debugELibraryRootMigrationLogs = false;

class ELibraryRootMigrationPreview {
  const ELibraryRootMigrationPreview({
    required this.sourceRootPath,
    required this.destinationRootPath,
    required this.scannedFolders,
    required this.destinationFoldersCreated,
    required this.epubCount,
    required this.epubSizeBytes,
    required this.pdfCount,
    required this.pdfSizeBytes,
    required this.otherManagedCount,
    required this.otherManagedSizeBytes,
  });

  final String sourceRootPath;
  final String destinationRootPath;
  final List<String> scannedFolders;
  final List<String> destinationFoldersCreated;
  final int epubCount;
  final int epubSizeBytes;
  final int pdfCount;
  final int pdfSizeBytes;
  final int otherManagedCount;
  final int otherManagedSizeBytes;

  int get totalCount => epubCount + pdfCount + otherManagedCount;
  int get totalSizeBytes =>
      epubSizeBytes + pdfSizeBytes + otherManagedSizeBytes;
}

class ELibraryRootMigrationReport {
  const ELibraryRootMigrationReport({
    required this.sourceRootPath,
    required this.destinationRootPath,
    required this.scannedFolders,
    required this.destinationFoldersCreated,
    required this.movedCount,
    required this.skippedCount,
    required this.conflictCount,
    required this.failedCount,
    required this.movedBytes,
    required this.movedRelativePaths,
    required this.skippedRelativePaths,
    required this.conflictRelativePaths,
    required this.failedRelativePaths,
  });

  final String sourceRootPath;
  final String destinationRootPath;
  final List<String> scannedFolders;
  final List<String> destinationFoldersCreated;
  final int movedCount;
  final int skippedCount;
  final int conflictCount;
  final int failedCount;
  final int movedBytes;
  final List<String> movedRelativePaths;
  final List<String> skippedRelativePaths;
  final List<String> conflictRelativePaths;
  final List<String> failedRelativePaths;

  bool get completedSuccessfully => failedCount == 0 && conflictCount == 0;
}

class ELibraryRootMigrationService {
  ELibraryRootMigrationService._();

  static final ELibraryRootMigrationService instance =
      ELibraryRootMigrationService._();

  static const _managedSourceFolders = <String>[
    'ePubs',
    'PDFs',
    'Images',
    'Index',
    'Indexes',
    'Commentaries',
    'Research',
    'eLibrary_Downloads',
    'TEST_Downloads',
  ];

  Future<ELibraryRootMigrationPreview> previewMigration({
    required String sourceRootPath,
    required String destinationRootPath,
  }) async {
    final source = p.normalize(sourceRootPath.trim());
    final destination = p.normalize(destinationRootPath.trim());
    final scannedFolders = <String>[];
    final destinationFolders = <String>[];
    var epubCount = 0;
    var epubSizeBytes = 0;
    var pdfCount = 0;
    var pdfSizeBytes = 0;
    var otherCount = 0;
    var otherSizeBytes = 0;

    for (final folder in _managedSourceFolders) {
      final sourceDir = Directory(p.join(source, folder));
      if (!await sourceDir.exists()) continue;
      scannedFolders.add(p.relative(sourceDir.path, from: source));
      destinationFolders.add(
        p.relative(p.join(destination, folder), from: destination),
      );
      await for (final entity in sourceDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.size < 0) continue;
        switch (p.extension(entity.path).toLowerCase()) {
          case '.epub':
            epubCount += 1;
            epubSizeBytes += stat.size;
            break;
          case '.pdf':
            pdfCount += 1;
            pdfSizeBytes += stat.size;
            break;
          default:
            otherCount += 1;
            otherSizeBytes += stat.size;
            break;
        }
      }
    }

    return ELibraryRootMigrationPreview(
      sourceRootPath: source,
      destinationRootPath: destination,
      scannedFolders: scannedFolders,
      destinationFoldersCreated: destinationFolders,
      epubCount: epubCount,
      epubSizeBytes: epubSizeBytes,
      pdfCount: pdfCount,
      pdfSizeBytes: pdfSizeBytes,
      otherManagedCount: otherCount,
      otherManagedSizeBytes: otherSizeBytes,
    );
  }

  Future<ELibraryRootMigrationReport> migrateManagedFiles({
    required String sourceRootPath,
    required String destinationRootPath,
    bool Function()? isCancelled,
  }) async {
    final source = p.normalize(sourceRootPath.trim());
    final destination = p.normalize(destinationRootPath.trim());
    await LibraryRootService.instance.ensureStructure(destination);

    final sourceFiles = await _discoverManagedFiles(source);
    final scannedFolders = _managedSourceFolders
        .where((folder) => Directory(p.join(source, folder)).existsSync())
        .toList(growable: false);
    final destinationFolders = _managedSourceFolders
        .map(
          (folder) =>
              p.relative(p.join(destination, folder), from: destination),
        )
        .toList(growable: false);

    var movedCount = 0;
    var skippedCount = 0;
    var conflictCount = 0;
    var failedCount = 0;
    var movedBytes = 0;
    final movedRelativePaths = <String>[];
    final skippedRelativePaths = <String>[];
    final conflictRelativePaths = <String>[];
    final failedRelativePaths = <String>[];

    for (final sourceFile in sourceFiles) {
      if (isCancelled?.call() ?? false) {
        break;
      }

      final sourcePath = p.normalize(sourceFile.path);
      final relativePath = p.relative(sourcePath, from: source);
      if (relativePath.startsWith('..')) {
        continue;
      }

      final destinationPath = p.join(destination, relativePath);
      final destinationFile = File(destinationPath);
      try {
        final sourceStat = await sourceFile.stat();
        if (await destinationFile.exists()) {
          final destinationStat = await destinationFile.stat();
          final identical =
              destinationStat.size == sourceStat.size &&
              await _sha256ForFile(sourceFile) ==
                  await _sha256ForFile(destinationFile);
          if (identical) {
            skippedCount += 1;
            skippedRelativePaths.add(relativePath);
            await sourceFile.delete();
            if (_debugELibraryRootMigrationLogs) {
              debugPrint(
                '[ELibraryRootMigration] skipped identical $relativePath',
              );
            }
            continue;
          }

          conflictCount += 1;
          conflictRelativePaths.add(relativePath);
          if (_debugELibraryRootMigrationLogs) {
            debugPrint(
              '[ELibraryRootMigration] conflict $relativePath -> $destinationPath',
            );
          }
          continue;
        }

        await _copyVerified(sourceFile, destinationFile, sourceStat.size);
        final copiedStat = await destinationFile.stat();
        if (copiedStat.size != sourceStat.size) {
          failedCount += 1;
          failedRelativePaths.add(relativePath);
          continue;
        }
        await sourceFile.delete();
        movedCount += 1;
        movedBytes += sourceStat.size;
        movedRelativePaths.add(relativePath);
        if (_debugELibraryRootMigrationLogs) {
          debugPrint('[ELibraryRootMigration] moved $relativePath');
        }
      } catch (error) {
        failedCount += 1;
        failedRelativePaths.add(relativePath);
        if (_debugELibraryRootMigrationLogs) {
          debugPrint('[ELibraryRootMigration] failed $relativePath: $error');
        }
      }
    }

    return ELibraryRootMigrationReport(
      sourceRootPath: source,
      destinationRootPath: destination,
      scannedFolders: scannedFolders,
      destinationFoldersCreated: destinationFolders,
      movedCount: movedCount,
      skippedCount: skippedCount,
      conflictCount: conflictCount,
      failedCount: failedCount,
      movedBytes: movedBytes,
      movedRelativePaths: movedRelativePaths,
      skippedRelativePaths: skippedRelativePaths,
      conflictRelativePaths: conflictRelativePaths,
      failedRelativePaths: failedRelativePaths,
    );
  }

  Future<List<File>> _discoverManagedFiles(String rootPath) async {
    final discovered = <File>[];
    final seen = <String>{};
    for (final folder in _managedSourceFolders) {
      final directory = Directory(p.join(rootPath, folder));
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final normalized = p.normalize(entity.path);
        if (!seen.add(normalized.toLowerCase())) continue;
        if (!_isWithinRoot(rootPath, normalized)) continue;
        discovered.add(entity);
      }
    }
    return discovered;
  }

  Future<void> _copyVerified(
    File sourceFile,
    File destinationFile,
    int sourceSize,
  ) async {
    await destinationFile.parent.create(recursive: true);
    final tempFile = File('${destinationFile.path}.copying');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await sourceFile.copy(tempFile.path);
    final copiedStat = await tempFile.stat();
    if (copiedStat.size != sourceSize) {
      await tempFile.delete();
      throw StateError('Copy verification failed for ${sourceFile.path}');
    }
    final sourceHash = await _sha256ForFile(sourceFile);
    final copiedHash = await _sha256ForFile(tempFile);
    if (copiedHash != sourceHash) {
      await tempFile.delete();
      throw StateError('Copy verification failed for ${sourceFile.path}');
    }
    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }
    await tempFile.rename(destinationFile.path);
  }

  Future<String> _sha256ForFile(File file) async {
    return (await sha256.bind(file.openRead()).first).toString();
  }

  bool _isWithinRoot(String rootPath, String absolutePath) {
    final normalizedRoot = p.normalize(rootPath);
    final normalizedPath = p.normalize(absolutePath);
    return p.isWithin(normalizedRoot, normalizedPath) ||
        normalizedRoot == normalizedPath;
  }
}
