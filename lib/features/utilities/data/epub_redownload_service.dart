import 'dart:io';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../library/data/canonical_activation.dart';
import 'elibrary_download_service.dart';

enum EpubRedownloadOutcome {
  /// The EPUB was already present; nothing needed to be done.
  alreadyAvailable,

  /// No `library_items` row exists for the given id.
  itemNotFound,

  /// The redownload ran but the expected file still wasn't found afterward.
  downloadFailed,

  /// The file redownloaded but the rebuilt canonical generation failed
  /// validation; the redownloaded file is retained per policy.
  canonicalizeFailed,

  /// The file redownloaded, canonicalized, and validated successfully. The
  /// current storage policy has been reapplied (which may remove the file
  /// again immediately, matching ordinary post-import behavior).
  rebuilt,
}

class EpubRedownloadResult {
  const EpubRedownloadResult({required this.outcome, this.detail});
  final EpubRedownloadOutcome outcome;
  final String? detail;
}

/// Maps `library_items.collection_name` (as written by
/// [ELibraryFolderPolicy.managedEgwFolderDefinitions]) onto the matching
/// `installX` flag of [ELibraryDownloadService.runProductionSetup], so a
/// single removed book can be restored by re-running the same collection
/// download the book originally came from.
const Map<String, String> _collectionInstallFlags = <String, String>{
  'EGW Books': 'installBooks',
  'EGW Devotionals': 'installDevotionals',
  'EGW Commentaries': 'installCommentaries',
  'EGW Misc Collections': 'installMiscCollections',
  'EGW Pamphlets': 'installPamphlets',
  'EGW Periodicals': 'installPeriodicals',
  'EGW Manuscript Releases': 'installManuscriptReleases',
};

/// Restores a book's app-managed EPUB after the platform storage policy has
/// removed it (see [EpubStoragePolicyService]), rebuilds its canonical
/// representation, and reapplies the current storage policy. User data
/// (notes, highlights, bookmarks, reading position, recents) is untouched
/// throughout, since it is keyed off stable block IDs and `library_items.id`
/// rather than the EPUB file.
class EpubRedownloadService {
  EpubRedownloadService._();

  static final EpubRedownloadService instance = EpubRedownloadService._();

  Future<EpubRedownloadResult> ensureEpubAvailable({
    required String libraryItemId,
  }) async {
    final rowResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_items',
            where: 'id = ?',
            whereArgs: <Object?>[libraryItemId],
            limit: 1,
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    if (rowResult.value.isEmpty) {
      return const EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.itemNotFound,
      );
    }
    final item = rowResult.value.first;
    final storageState = (item['epub_storage_state']?.toString() ?? 'present')
        .toLowerCase();
    if (storageState != 'removed_after_index') {
      return const EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.alreadyAvailable,
      );
    }

    final collectionName = item['collection_name']?.toString() ?? '';
    final installFlag = _collectionInstallFlags[collectionName];
    if (installFlag == null) {
      return EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.downloadFailed,
        detail: 'Unrecognized collection "$collectionName".',
      );
    }

    await ELibraryDownloadService.instance.runProductionSetup(
      installBooks: installFlag == 'installBooks',
      installDevotionals: installFlag == 'installDevotionals',
      installCommentaries: installFlag == 'installCommentaries',
      installMiscCollections: installFlag == 'installMiscCollections',
      installPamphlets: installFlag == 'installPamphlets',
      installPeriodicals: installFlag == 'installPeriodicals',
      installManuscriptReleases: installFlag == 'installManuscriptReleases',
      installEpub: true,
    );

    final relativePath = item['relative_path']?.toString().trim() ?? '';
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (relativePath.isEmpty || rootPath == null || rootPath.isEmpty) {
      return const EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.downloadFailed,
        detail: 'Library Root Folder is not selected.',
      );
    }
    final resolvedPath = await LibraryRootService.instance.resolveRelativePath(
      relativePath: relativePath,
      rootPath: rootPath,
    );
    final source = File(resolvedPath);
    if (!await source.exists()) {
      return const EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.downloadFailed,
      );
    }

    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'library_items',
      <String, Object?>{'epub_storage_state': 'present', 'updated_at': now},
      where: 'id = ?',
      whereArgs: <Object?>[libraryItemId],
    );

    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: libraryItemId,
      source: source,
      applyStoragePolicy: true,
      rootPath: rootPath,
    );
    if (!outcome.isReady) {
      return EpubRedownloadResult(
        outcome: EpubRedownloadOutcome.canonicalizeFailed,
        detail: outcome.technicalDetail,
      );
    }
    return const EpubRedownloadResult(outcome: EpubRedownloadOutcome.rebuilt);
  }
}
