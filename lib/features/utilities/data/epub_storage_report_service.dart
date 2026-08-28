import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import 'epub_storage_policy_service.dart';

class EpubBookStorageReport {
  const EpubBookStorageReport({
    required this.libraryItemId,
    required this.canonicalTextSizeBytes,
    required this.assetSizeBytes,
    required this.epubSizeBytes,
    required this.epubPresent,
    required this.retentionPreference,
  });

  final String libraryItemId;
  final int canonicalTextSizeBytes;
  final int assetSizeBytes;
  final int epubSizeBytes;
  final bool epubPresent;
  final EpubRetentionPreference retentionPreference;

  int get totalOfflineSizeBytes =>
      canonicalTextSizeBytes + assetSizeBytes + epubSizeBytes;

  /// What would be freed if the app-managed EPUB were removed right now.
  /// Zero when it has already been removed.
  int get estimatedSavingsIfEpubRemovedBytes => epubPresent ? epubSizeBytes : 0;
}

/// Per-book storage reporting for the canonical EPUB import pipeline: how
/// much space the canonical database text/index takes, how much extracted
/// assets take, how much (if anything) the app-managed EPUB archive still
/// takes, and what the current retention choice would do about it.
class EpubStorageReportService {
  EpubStorageReportService._();

  static final EpubStorageReportService instance = EpubStorageReportService._();

  Future<EpubBookStorageReport> reportFor(String libraryItemId) async {
    final itemResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_items',
            where: 'id = ?',
            whereArgs: <Object?>[libraryItemId],
            limit: 1,
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    final item = itemResult.value.isEmpty ? null : itemResult.value.first;

    final blockSizeResult = await ELibraryReadResolver.instance
        .readWithFallback<int>(
          read: (db) async {
            final rows = await db.rawQuery(
              '''
              SELECT COALESCE(SUM(LENGTH(plain_text) + LENGTH(formatted_content)), 0) AS bytes
              FROM library_document_blocks
              WHERE library_item_id = ?
              ''',
              <Object?>[libraryItemId],
            );
            return (rows.first['bytes'] as num?)?.toInt() ?? 0;
          },
          hasData: (bytes) => bytes > 0,
        );

    var epubSizeBytes = 0;
    var epubPresent = false;
    var assetSizeBytes = 0;
    final relativePath = item?['relative_path']?.toString().trim() ?? '';
    if (relativePath.isNotEmpty) {
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath())
              ?.trim();
      if (rootPath != null && rootPath.isNotEmpty) {
        final epubFile = await LibraryRootService.instance
            .resolveExistingAssetFile(
              relativePath: relativePath,
              rootPath: rootPath,
            );
        if (epubFile != null) {
          epubPresent = true;
          epubSizeBytes = await epubFile.length();
        }
        // The epub itself may already be cleaned up after canonicalization
        // (leaving only the generated assets), so check for the assets
        // folder next to wherever the epub actually is (or would be).
        final assetDirectoryBase =
            epubFile?.parent.path ??
            p.dirname(
              await LibraryRootService.instance.resolveRelativePath(
                relativePath: relativePath,
                rootPath: rootPath,
              ),
            );
        final assetDirectory = Directory(
          p.join(assetDirectoryBase, '_canonical_assets', libraryItemId),
        );
        if (await assetDirectory.exists()) {
          await for (final entity in assetDirectory.list(recursive: true)) {
            if (entity is File) {
              assetSizeBytes += await entity.length();
            }
          }
        }
      }
    }

    final policyService = EpubStoragePolicyService.instance;
    final retentionPreference = await policyService.currentPreference();

    return EpubBookStorageReport(
      libraryItemId: libraryItemId,
      canonicalTextSizeBytes: blockSizeResult.value,
      assetSizeBytes: assetSizeBytes,
      epubSizeBytes: epubSizeBytes,
      epubPresent: epubPresent,
      retentionPreference: retentionPreference,
    );
  }
}
