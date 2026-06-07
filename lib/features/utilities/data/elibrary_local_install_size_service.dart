import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import 'elibrary_folder_policy.dart';
import 'elibrary_install_estimate_repository.dart';

class ELibraryLocalInstallSizeService {
  ELibraryLocalInstallSizeService._();

  static final ELibraryLocalInstallSizeService instance =
      ELibraryLocalInstallSizeService._();

  Future<void> refreshInstalledCollectionSizes({String? rootPath}) async {
    final resolvedRootPath = await _resolveRootPath(rootPath);
    if (resolvedRootPath == null) return;

    final cachedEstimates = await ELibraryInstallEstimateRepository.instance
        .loadByCollectionAndFormat();
    if (cachedEstimates.isEmpty) return;

    final localSizes = await _scanInstalledCollectionSizes(
      rootPath: resolvedRootPath,
    );
    final checkedAt = DateTime.now().toUtc();
    final cacheWrites = <Future<void>>[];
    for (final collectionEntry in cachedEstimates.entries) {
      final collectionKey = collectionEntry.key;
      for (final formatEntry in collectionEntry.value.entries) {
        final existingRecord = formatEntry.value;
        final localRecord = localSizes[collectionKey]?[formatEntry.key];
        cacheWrites.add(
          ELibraryInstallEstimateRepository.instance.upsertCollectionCount(
            collectionKey: collectionKey,
            format: formatEntry.key,
            fileCount: existingRecord.fileCount,
            totalSizeBytes: localRecord?.totalSizeBytes,
            sizeKnown: localRecord != null,
            source: 'local_installed_scan',
            lastCheckedUtc: checkedAt,
          ),
        );
      }
    }
    await Future.wait(cacheWrites);
  }

  Future<Map<String, Map<String, _LocalCollectionSize>>>
  _scanInstalledCollectionSizes({String? rootPath}) async {
    final resolvedRootPath = await _resolveRootPath(rootPath);
    if (resolvedRootPath == null) {
      return const <String, Map<String, _LocalCollectionSize>>{};
    }

    final totals = <String, Map<String, _MutableLocalCollectionSize>>{};
    for (final folder in ELibraryFolderPolicy.allManagedEgwFolderDefinitions) {
      final directory = Directory(
        p.join(resolvedRootPath, folder.relativeFolder),
      );
      if (!await directory.exists()) continue;

      final format =
          p
                  .split(p.normalize(folder.relativeFolder))
                  .firstWhere(
                    (segment) =>
                        segment.toLowerCase() == 'epubs' ||
                        segment.toLowerCase() == 'pdfs',
                    orElse: () => '',
                  )
                  .toLowerCase() ==
              'epubs'
          ? 'epub'
          : 'pdf';

      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.epub' && ext != '.pdf') continue;

        final stat = await entity.stat();
        if (stat.size < 0) continue;
        final collectionTotals = totals.putIfAbsent(
          folder.collectionName,
          () => <String, _MutableLocalCollectionSize>{},
        );
        final formatTotals = collectionTotals.putIfAbsent(
          format,
          _MutableLocalCollectionSize.new,
        );
        formatTotals.fileCount += 1;
        formatTotals.totalSizeBytes += stat.size;
      }
    }

    return totals.map(
      (collectionKey, formatTotals) => MapEntry(
        collectionKey,
        formatTotals.map(
          (format, totals) => MapEntry(
            format,
            _LocalCollectionSize(
              fileCount: totals.fileCount,
              totalSizeBytes: totals.totalSizeBytes,
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _resolveRootPath(String? rootPath) async {
    final normalized = rootPath?.trim() ?? '';
    if (normalized.isNotEmpty) return normalized;

    final explicit = await LibraryRootService.instance
        .explicitLibraryRootPath();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    return null;
  }
}

class _LocalCollectionSize {
  const _LocalCollectionSize({
    required this.fileCount,
    required this.totalSizeBytes,
  });

  final int fileCount;
  final int totalSizeBytes;
}

class _MutableLocalCollectionSize {
  int fileCount = 0;
  int totalSizeBytes = 0;
}
