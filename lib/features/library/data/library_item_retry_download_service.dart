import 'dart:io';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_database.dart';
import '../../utilities/data/elibrary_download_service.dart';
import 'canonical_activation.dart';
import 'library_item_availability.dart';

enum LibraryItemRetryDownloadOutcome {
  /// [libraryItemSupportsRetryDownload] would have returned false for this
  /// item's collection; nothing was attempted.
  collectionUnknown,

  /// The Library Root Folder isn't currently accessible.
  libraryRootUnavailable,

  /// The collection download ran but no file landed at this item's
  /// `relative_path` afterward.
  fileStillMissing,

  /// A file is present but [LibraryDocumentCanonicalizer] still rejected it
  /// — the source still has nothing readable for this title.
  stillUnavailable,

  /// The file redownloaded and canonicalized successfully.
  succeeded,
}

class LibraryItemRetryDownloadResult {
  const LibraryItemRetryDownloadResult({required this.outcome, this.detail});

  final LibraryItemRetryDownloadOutcome outcome;
  final String? detail;

  bool get succeeded => outcome == LibraryItemRetryDownloadOutcome.succeeded;
}

/// Retries a single book that [libraryItemAvailability] has flagged
/// unavailable (`index_status = 'needs_attention'`).
///
/// Re-runs the official collection download for just this item's collection
/// — [ELibraryDownloadService] already replaces an existing file that fails
/// its own validation, so this is the same repair path eLibrary Setup uses,
/// scoped to one book — then rebuilds the canonical generation from
/// whatever lands on disk. Never fabricates content: if the source still
/// has nothing usable, the item is left exactly where
/// [LibraryDocumentCanonicalizer] already puts it (Needs Attention; title,
/// cover, and `source_work_id` untouched).
class LibraryItemRetryDownloadService {
  LibraryItemRetryDownloadService._();

  static final LibraryItemRetryDownloadService instance =
      LibraryItemRetryDownloadService._();

  Future<LibraryItemRetryDownloadResult> retry({
    required String libraryItemId,
    required String collectionName,
    required String relativePath,
  }) async {
    final installFlag = libraryManagedCollectionInstallFlags[collectionName];
    if (installFlag == null) {
      return const LibraryItemRetryDownloadResult(
        outcome: LibraryItemRetryDownloadOutcome.collectionUnknown,
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

    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      return const LibraryItemRetryDownloadResult(
        outcome: LibraryItemRetryDownloadOutcome.libraryRootUnavailable,
      );
    }
    final resolvedPath = await LibraryRootService.instance.resolveRelativePath(
      relativePath: relativePath,
      rootPath: rootPath,
    );
    final source = File(resolvedPath);
    if (!await source.exists()) {
      return const LibraryItemRetryDownloadResult(
        outcome: LibraryItemRetryDownloadOutcome.fileStillMissing,
      );
    }

    final db = await ELibraryDatabase.instance.database;
    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: libraryItemId,
      source: source,
      applyStoragePolicy: true,
      rootPath: rootPath,
    );
    if (!outcome.isReady) {
      return LibraryItemRetryDownloadResult(
        outcome: LibraryItemRetryDownloadOutcome.stillUnavailable,
        detail: outcome.technicalDetail,
      );
    }
    return const LibraryItemRetryDownloadResult(
      outcome: LibraryItemRetryDownloadOutcome.succeeded,
    );
  }
}
