import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../library/data/library_catalog_service.dart';
import '../../reader/data/commentary_research_library_service.dart';
import 'elibrary_folder_policy.dart';
import 'elibrary_local_install_size_service.dart';

enum ELibraryManagedDownloadFormat { epub, pdf }

class ELibraryManagedDownloadFileRecord {
  const ELibraryManagedDownloadFileRecord({
    required this.absolutePath,
    required this.relativePath,
    required this.collectionName,
    required this.format,
    required this.fileSize,
  });

  final String absolutePath;
  final String relativePath;
  final String collectionName;
  final ELibraryManagedDownloadFormat format;
  final int fileSize;
}

class ELibraryStorageSummary {
  const ELibraryStorageSummary({
    required this.epubCount,
    required this.epubSizeBytes,
    required this.pdfCount,
    required this.pdfSizeBytes,
  });

  final int epubCount;
  final int epubSizeBytes;
  final int pdfCount;
  final int pdfSizeBytes;

  int get totalCount => epubCount + pdfCount;

  int get totalSizeBytes => epubSizeBytes + pdfSizeBytes;
}

class ELibraryRemovalReport {
  const ELibraryRemovalReport({
    required this.removedCount,
    required this.epubRemovedCount,
    required this.pdfRemovedCount,
    required this.removedBytes,
    required this.removedPaths,
    required this.skippedPaths,
  });

  final int removedCount;
  final int epubRemovedCount;
  final int pdfRemovedCount;
  final int removedBytes;
  final List<String> removedPaths;
  final List<String> skippedPaths;
}

class ELibraryFileManagementService {
  ELibraryFileManagementService._();

  static final ELibraryFileManagementService instance =
      ELibraryFileManagementService._();

  Future<ELibraryStorageSummary> computeDownloadedStorageSummary({
    String? rootPath,
  }) async {
    final resolvedRootPath = await _resolveRootPath(rootPath);
    if (resolvedRootPath == null) {
      return const ELibraryStorageSummary(
        epubCount: 0,
        epubSizeBytes: 0,
        pdfCount: 0,
        pdfSizeBytes: 0,
      );
    }

    final records = await _scanManagedFiles(
      rootPath: resolvedRootPath,
      collectionNames: const <String>{},
      formats: const <ELibraryManagedDownloadFormat>{
        ELibraryManagedDownloadFormat.epub,
        ELibraryManagedDownloadFormat.pdf,
      },
    );
    var epubCount = 0;
    var epubSizeBytes = 0;
    var pdfCount = 0;
    var pdfSizeBytes = 0;
    for (final record in records) {
      switch (record.format) {
        case ELibraryManagedDownloadFormat.epub:
          epubCount += 1;
          epubSizeBytes += record.fileSize;
          break;
        case ELibraryManagedDownloadFormat.pdf:
          pdfCount += 1;
          pdfSizeBytes += record.fileSize;
          break;
      }
    }
    return ELibraryStorageSummary(
      epubCount: epubCount,
      epubSizeBytes: epubSizeBytes,
      pdfCount: pdfCount,
      pdfSizeBytes: pdfSizeBytes,
    );
  }

  Future<List<ELibraryManagedDownloadFileRecord>> buildFilteredRemovalQueue({
    required Set<String> collectionNames,
    required Set<ELibraryManagedDownloadFormat> formats,
    String? rootPath,
  }) async {
    final resolvedRootPath = await _resolveRootPath(rootPath);
    if (resolvedRootPath == null) {
      return const <ELibraryManagedDownloadFileRecord>[];
    }
    return _scanManagedFiles(
      rootPath: resolvedRootPath,
      collectionNames: collectionNames,
      formats: formats,
    );
  }

  Future<ELibraryRemovalReport> removeDownloadedFiles({
    required Set<String> collectionNames,
    required Set<ELibraryManagedDownloadFormat> formats,
    String? rootPath,
  }) async {
    final resolvedRootPath = await _resolveRootPath(rootPath);
    if (resolvedRootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final records = await _scanManagedFiles(
      rootPath: resolvedRootPath,
      collectionNames: collectionNames,
      formats: formats,
    );
    if (records.isEmpty) {
      return const ELibraryRemovalReport(
        removedCount: 0,
        epubRemovedCount: 0,
        pdfRemovedCount: 0,
        removedBytes: 0,
        removedPaths: <String>[],
        skippedPaths: <String>[],
      );
    }

    final removedPaths = <String>[];
    final skippedPaths = <String>[];
    var removedBytes = 0;
    var epubRemovedCount = 0;
    var pdfRemovedCount = 0;
    for (final record in records) {
      final file = File(record.absolutePath);
      if (!await file.exists()) {
        skippedPaths.add(record.relativePath);
        continue;
      }
      removedBytes += await file.length();
      await file.delete();
      removedPaths.add(record.relativePath);
      switch (record.format) {
        case ELibraryManagedDownloadFormat.epub:
          epubRemovedCount += 1;
          break;
        case ELibraryManagedDownloadFormat.pdf:
          pdfRemovedCount += 1;
          break;
      }
    }

    if (removedPaths.isEmpty) {
      return ELibraryRemovalReport(
        removedCount: 0,
        epubRemovedCount: 0,
        pdfRemovedCount: 0,
        removedBytes: 0,
        removedPaths: removedPaths,
        skippedPaths: skippedPaths,
      );
    }

    await _markLibraryItemsDeleted(removedRelativePaths: removedPaths);
    await LibraryCatalogService.instance.refreshManagedItemsFromDisk();
    await CommentaryResearchLibraryService.instance.indexLocalCatalogedEpubs();
    await ELibraryLocalInstallSizeService.instance
        .refreshInstalledCollectionSizes(rootPath: resolvedRootPath);

    return ELibraryRemovalReport(
      removedCount: removedPaths.length,
      epubRemovedCount: epubRemovedCount,
      pdfRemovedCount: pdfRemovedCount,
      removedBytes: removedBytes,
      removedPaths: removedPaths,
      skippedPaths: skippedPaths,
    );
  }

  Future<String?> _resolveRootPath(String? rootPath) async {
    final normalized = rootPath?.trim() ?? '';
    if (normalized.isNotEmpty) {
      return p.normalize(normalized);
    }

    final explicit = await LibraryRootService.instance
        .explicitLibraryRootPath();
    if (explicit != null && explicit.trim().isNotEmpty) {
      return p.normalize(explicit.trim());
    }
    return null;
  }

  Future<List<ELibraryManagedDownloadFileRecord>> _scanManagedFiles({
    required String rootPath,
    required Set<String> collectionNames,
    required Set<ELibraryManagedDownloadFormat> formats,
  }) async {
    final normalizedRoot = p.normalize(rootPath);
    final hasCollectionFilter = collectionNames.isNotEmpty;
    final hasFormatFilter = formats.isNotEmpty;
    final records = <ELibraryManagedDownloadFileRecord>[];
    final seen = <String>{};

    for (final folder in ELibraryFolderPolicy.allManagedEgwFolderDefinitions) {
      if (hasCollectionFilter &&
          !collectionNames.contains(folder.collectionName)) {
        continue;
      }
      final format = _formatForFolder(folder.relativeFolder);
      if (format == null) continue;
      if (hasFormatFilter && !formats.contains(format)) {
        continue;
      }

      final directory = Directory(
        p.join(normalizedRoot, folder.relativeFolder),
      );
      if (!await directory.exists()) continue;

      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.epub' && ext != '.pdf') continue;

        final absolutePath = p.normalize(entity.path);
        if (!_isPathWithinRoot(normalizedRoot, absolutePath)) {
          continue;
        }
        final normalizedRelative = p.relative(
          absolutePath,
          from: normalizedRoot,
        );
        if (!seen.add(normalizedRelative.toLowerCase())) continue;

        final stat = await entity.stat();
        records.add(
          ELibraryManagedDownloadFileRecord(
            absolutePath: absolutePath,
            relativePath: normalizedRelative,
            collectionName: folder.collectionName,
            format: ext == '.epub'
                ? ELibraryManagedDownloadFormat.epub
                : ELibraryManagedDownloadFormat.pdf,
            fileSize: stat.size,
          ),
        );
      }
    }

    return records;
  }

  Future<void> _markLibraryItemsDeleted({
    required List<String> removedRelativePaths,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final relativePath in removedRelativePaths) {
      final rowResult = await ELibraryReadResolver.instance.readWithFallback<
        List<Map<String, Object?>>
      >(
        read: (db) => db.query(
          'library_items',
          columns: const ['id'],
          where: 'LOWER(relative_path) = ?',
          whereArgs: [relativePath.toLowerCase()],
          limit: 1,
        ),
        hasData: (rows) => rows.isNotEmpty,
      );
      final rows = rowResult.value;
      if (rows.isEmpty) continue;
      final db = rowResult.database;
      final itemId = rows.first['id']?.toString().trim() ?? '';
      if (itemId.isEmpty) continue;
      await db.update(
        'library_items',
        {
          'deleted_at': now,
          'updated_at': now,
          'is_missing': 1,
          'sync_status': 'pending',
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
    }
  }

  bool _isPathWithinRoot(String rootPath, String absolutePath) {
    final normalizedRoot = p.normalize(rootPath);
    final normalizedPath = p.normalize(absolutePath);
    return p.isWithin(normalizedRoot, normalizedPath) ||
        normalizedRoot == normalizedPath;
  }

  ELibraryManagedDownloadFormat? _formatForFolder(String relativeFolder) {
    final normalized = relativeFolder.toLowerCase();
    if (normalized.startsWith('epubs/')) {
      return ELibraryManagedDownloadFormat.epub;
    }
    if (normalized.startsWith('pdfs/')) {
      return ELibraryManagedDownloadFormat.pdf;
    }
    return null;
  }
}
