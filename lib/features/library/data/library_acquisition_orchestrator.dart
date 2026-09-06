import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_database.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../../utilities/data/elibrary_download_service.dart';
import '../../utilities/data/pioneer_book_package_import_service.dart';
import '../../utilities/data/pioneer_captured_html_import_folder_service.dart';
import '../../utilities/data/pioneer_study_collection_service.dart';
import '../../utilities/data/pioneer_text_import_service.dart'
    show PioneerExistingImportPolicy;
import 'canonical_activation.dart';
import 'library_item_availability.dart';
import 'library_item_retry_download_service.dart';

/// Single shared orchestration entry point for every way a book can be
/// acquired and made readable: an official EGW download, a Pioneer
/// `.studybook` package, a Pioneer/StudyCollection item, a CaptureClipper
/// capture folder, or a plain individual EPUB. Each typed operation below
/// runs the same conceptual pipeline —
///
///   discover/obtain source -> validate source -> resolve canonical identity
///   -> canonicalize into staging -> validate staged generation
///   -> atomically activate -> apply device storage policy
///   -> return a friendly, typed result
///
/// — by composing the existing, already-authoritative services
/// ([ELibraryDownloadService], [EpubDownloadValidator] (via the
/// canonicalizer's own structural gate), [CanonicalActivation] (wrapping
/// [LibraryDocumentCanonicalizer]/[LibraryDocumentImportValidator]/
/// [EpubStoragePolicyService]), [PioneerBookPackageImportService],
/// [PioneerCapturedHtmlImportFolderService], and
/// [PioneerStudyCollectionService]) rather than reimplementing any of them.
///
/// This is an orchestration-layer addition only: no screen currently calls
/// these methods. Existing screens keep using the existing services
/// directly (which now internally share [CanonicalActivation] with this
/// orchestrator), so current behavior is unchanged.
class LibraryAcquisitionOrchestrator {
  LibraryAcquisitionOrchestrator._();

  static final LibraryAcquisitionOrchestrator instance =
      LibraryAcquisitionOrchestrator._();

  // ---------------------------------------------------------------------
  // Official EGW download
  // ---------------------------------------------------------------------

  /// Downloads the official collection [collectionName] belongs to, then
  /// canonicalizes and activates whichever file lands at [relativePath] for
  /// [libraryItemId], applying the device storage policy on success. This is
  /// the same "download this book's collection, then rebuild" operation
  /// [LibraryItemRetryDownloadService] already performs for an unavailable
  /// item; a not-yet-downloaded item goes through the identical sequence.
  Future<LibraryAcquisitionOutcome> prepareOfficialDownload({
    required String libraryItemId,
    required String collectionName,
    required String relativePath,
  }) => _downloadCollectionAndActivate(
    libraryItemId: libraryItemId,
    collectionName: collectionName,
    relativePath: relativePath,
  );

  /// Retries a book already flagged unavailable. Identical operation to
  /// [prepareOfficialDownload]; kept as a separate typed name because the
  /// two call sites represent distinct user intents ("get this book" vs.
  /// "this book failed, try again").
  Future<LibraryAcquisitionOutcome> retryFailedItem({
    required String libraryItemId,
    required String collectionName,
    required String relativePath,
  }) => _downloadCollectionAndActivate(
    libraryItemId: libraryItemId,
    collectionName: collectionName,
    relativePath: relativePath,
  );

  Future<LibraryAcquisitionOutcome> _downloadCollectionAndActivate({
    required String libraryItemId,
    required String collectionName,
    required String relativePath,
  }) async {
    final installFlag = libraryManagedCollectionInstallFlags[collectionName];
    if (installFlag == null) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.failedDownload,
        userSummary: 'A readable edition is not currently available.',
        technicalDetail: 'Unrecognized collection "$collectionName".',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
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
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.failedDownload,
        userSummary: 'A readable edition is not currently available.',
        technicalDetail: 'Library Root Folder is not selected.',
        retryable: true,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    final source = await LibraryRootService.instance.resolveExistingAssetFile(
      relativePath: relativePath,
      rootPath: rootPath,
    );
    if (source == null) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.sourceUnavailable,
        userSummary: 'A readable edition is not currently available.',
        retryable: true,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }

    final db = await ELibraryDatabase.instance.database;
    return CanonicalActivation.activate(
      db: db,
      libraryItemId: libraryItemId,
      source: source,
      applyStoragePolicy: true,
      rootPath: rootPath,
    );
  }

  // ---------------------------------------------------------------------
  // Individual EPUB import ("Add an EPUB")
  // ---------------------------------------------------------------------

  /// Activates a single EPUB already sitting at [relativePath] under the
  /// Library Root (an individually-imported book, not necessarily an
  /// official download). [EpubStoragePolicyService] only ever removes a
  /// source it positively recognizes as an app-managed EGW download path,
  /// so applying the storage policy here is always safe for a plain
  /// individual EPUB import — it will simply retain the file.
  Future<LibraryAcquisitionOutcome> prepareExistingEpub({
    required String libraryItemId,
    required String relativePath,
  }) async {
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (rootPath == null || rootPath.isEmpty) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.sourceUnavailable,
        userSummary: 'A readable edition is not currently available.',
        technicalDetail: 'Library Root Folder is not selected.',
        retryable: true,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    final source = await LibraryRootService.instance.resolveExistingAssetFile(
      relativePath: relativePath,
      rootPath: rootPath,
    );
    if (source == null) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.sourceUnavailable,
        userSummary: 'A readable edition is not currently available.',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
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
    if (outcome.isReady) {
      // Every bulk EPUB import (Pioneer folder import, the combined
      // pioneerthin.zip install) funnels through this one method — this is
      // the single choke point where the navigation tree the canonicalizer
      // itself never builds (see library_document_canonicalizer.dart, which
      // only writes library_document_blocks/sections) gets filled in, so
      // future imports never again ship with an empty Contents/TOC.
      await CommentaryResearchLibraryService.instance.ensureNavigationIndexed(
        db: db,
        libraryItemId: libraryItemId,
        file: source,
      );
    }
    return outcome;
  }

  // ---------------------------------------------------------------------
  // Pioneer .studybook package import
  // ---------------------------------------------------------------------

  /// Imports a `.studybook`/`.zip` CaptureClipper package (unchanged
  /// extraction via [PioneerBookPackageImportService]), then explicitly
  /// scans the resulting managed folder so the contained HTML file(s) are
  /// cataloged and — via the same hook
  /// [PioneerCapturedHtmlImportFolderService] now calls after every
  /// successful capture import — have their canonical generation activated
  /// immediately, instead of leaving activation to whenever the reader next
  /// happens to open the book.
  Future<List<LibraryAcquisitionOutcome>> prepareStudyBook({
    required String packagePath,
    String? managedRootPath,
    bool setAsConfiguredFolder = true,
    String? expectedWorkId,
    String? expectedPackageId,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.overwriteExisting,
  }) async {
    final packageResult = await PioneerBookPackageImportService.instance
        .importPackage(
          packagePath,
          managedRootPath: managedRootPath,
          setAsConfiguredFolder: setAsConfiguredFolder,
          expectedWorkId: expectedWorkId,
          expectedPackageId: expectedPackageId,
        );

    final scanReport = await PioneerCapturedHtmlImportFolderService.instance
        .scanFolder(
          folderPath: packageResult.destinationFolderPath,
          importFiles: true,
          existingImportPolicy: existingImportPolicy,
        );

    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    final outcomes = <LibraryAcquisitionOutcome>[];
    for (final file in scanReport.files) {
      final itemId = file.libraryItemId?.trim() ?? '';
      if (itemId.isEmpty) continue;
      // The folder-service hook already activated this item as part of the
      // scan above; report its current state rather than re-canonicalizing.
      outcomes.add(
        await _describeExistingActivation(
          libraryItemId: itemId,
          rootPath: rootPath,
        ),
      );
    }
    return outcomes;
  }

  // ---------------------------------------------------------------------
  // Pioneer StudyCollection item import
  // ---------------------------------------------------------------------

  /// Imports one item (by work id) from a `.studycollection` archive,
  /// reusing [PioneerStudyCollectionService] for inventory/extraction and
  /// composing its `.studybook` branch with the same capture-folder scan
  /// used by [prepareStudyBook], so a StudyCollection-sourced Pioneer book
  /// is explicitly activated too rather than only via a later reader open.
  Future<LibraryAcquisitionOutcome?> prepareStudyCollectionItem({
    required String collectionPath,
    required String workId,
  }) async {
    // The studybook branch of importSelectedItems only extracts the
    // package; it never creates a library_items row itself (see
    // PioneerBookPackageImportService.importPackage). Injecting this
    // importer lets the extraction be immediately followed by the same
    // capture-folder scan+activation prepareStudyBook uses, and captures
    // the resulting library item id(s) directly from that scan rather than
    // trying to re-derive them with a second, import-less scan afterward
    // (which would not carry a libraryItemId at all).
    final capturedItemIds = <String>[];
    final service = PioneerStudyCollectionService(
      studybookImporter: (path, item) async {
        final result = await PioneerBookPackageImportService.instance
            .importPackage(
              path,
              expectedWorkId: item.workId,
              expectedPackageId: item.packageId.isEmpty ? null : item.packageId,
            );
        final scanReport = await PioneerCapturedHtmlImportFolderService.instance
            .scanFolder(
              folderPath: result.destinationFolderPath,
              importFiles: true,
              existingImportPolicy:
                  PioneerExistingImportPolicy.overwriteExisting,
            );
        capturedItemIds.addAll(
          scanReport.files
              .map((file) => file.libraryItemId?.trim() ?? '')
              .where((id) => id.isNotEmpty),
        );
        return result;
      },
    );
    final batch = await service.importSelectedItems(collectionPath, <String>[
      workId,
    ]);
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();

    if (batch.studybookResults.isNotEmpty && capturedItemIds.isNotEmpty) {
      return _describeExistingActivation(
        libraryItemId: capturedItemIds.first,
        rootPath: rootPath,
      );
    }
    for (final result in batch.epubResults) {
      if (!result.isImported) continue;
      // The legacy StudyCollection EPUB branch reports its import status
      // here without a second activation pass. Raw Pioneer-folder EPUBs
      // use the bulk-import path, which activates them explicitly.
      return LibraryAcquisitionOutcome(
        libraryItemId: result.libraryItemId,
        phase: LibraryAcquisitionPhase.ready,
        userSummary: 'Ready to read.',
        technicalDetail:
            'Imported via the legacy text-block pipeline; not yet eligible '
            'for canonical activation.',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: true,
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------
  // CaptureClipper capture-folder import
  // ---------------------------------------------------------------------

  /// Scans and imports every HTML capture in [folderPath], reusing
  /// [PioneerCapturedHtmlImportFolderService.scanFolder]. Each successfully
  /// imported file is now explicitly activated by that service's own
  /// import step (see its `_analyzeFile` hook), so the outcomes below
  /// reflect real activation rather than a promise fulfilled only when the
  /// reader is later opened.
  Future<List<LibraryAcquisitionOutcome>> prepareCaptureFolder({
    required String folderPath,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) async {
    final report = await PioneerCapturedHtmlImportFolderService.instance
        .scanFolder(
          folderPath: folderPath,
          importFiles: true,
          existingImportPolicy: existingImportPolicy,
        );
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    final outcomes = <LibraryAcquisitionOutcome>[];
    for (final file in report.files) {
      final itemId = file.libraryItemId?.trim() ?? '';
      if (itemId.isEmpty) continue;
      outcomes.add(
        await _describeExistingActivation(
          libraryItemId: itemId,
          rootPath: rootPath,
        ),
      );
    }
    return outcomes;
  }

  // ---------------------------------------------------------------------
  // Rebuild (maintenance repair of a single item's canonical generation)
  // ---------------------------------------------------------------------

  /// Re-canonicalizes a single item from whatever source file it currently
  /// resolves to, without applying the storage policy — the single-item
  /// equivalent of what [CanonicalEpubGenerationRepairService] does in
  /// batch for every stale generation. Never fabricates a source: if
  /// nothing is on disk, the existing generation (if any) is left exactly
  /// as-is.
  Future<LibraryAcquisitionOutcome> rebuildCanonicalCopy({
    required String libraryItemId,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      columns: const <String>['relative_path', 'file_format'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.failedImport,
        userSummary: 'A readable edition is not currently available.',
        technicalDetail: 'No library item found for id "$libraryItemId".',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    final relativePath = rows.first['relative_path']?.toString().trim() ?? '';
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
    if (relativePath.isEmpty || rootPath == null || rootPath.isEmpty) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.sourceUnavailable,
        userSummary: 'A readable edition is not currently available.',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    final source = await LibraryRootService.instance.resolveExistingAssetFile(
      relativePath: relativePath,
      rootPath: rootPath,
    );
    if (source == null) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.sourceUnavailable,
        userSummary: 'A readable edition is not currently available.',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    return CanonicalActivation.activate(
      db: db,
      libraryItemId: libraryItemId,
      source: source,
      applyStoragePolicy: false,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  /// Reports the current activation state of an item that was already
  /// activated by a prior explicit step in this same operation (e.g. the
  /// capture-folder import hook), without re-running canonicalize.
  Future<LibraryAcquisitionOutcome> _describeExistingActivation({
    required String libraryItemId,
    String? rootPath,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final rows = await db.query(
      'library_items',
      columns: const <String>['relative_path', 'index_status', 'index_error'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[libraryItemId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.failedImport,
        userSummary: 'A readable edition is not currently available.',
        retryable: false,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: false,
      );
    }
    final relativePath = rows.first['relative_path']?.toString().trim() ?? '';
    final sourceFilePresent =
        relativePath.isNotEmpty &&
        rootPath != null &&
        rootPath.isNotEmpty &&
        await LibraryRootService.instance.resolveExistingAssetFile(
              relativePath: relativePath,
              rootPath: rootPath,
            ) !=
            null;
    final indexStatus = (rows.first['index_status']?.toString() ?? '').trim();
    if (indexStatus == 'needs_attention') {
      final indexError = rows.first['index_error']?.toString();
      final category = categorizeUnavailableReason(indexError);
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.needsAttention,
        userSummary:
            category ==
                LibraryItemUnavailableCategory.sourceHasNoReadableEdition
            ? 'A readable edition is not currently available.'
            : 'The book could not be prepared; the source file was not '
                  'altered.',
        technicalDetail: indexError,
        retryable:
            category !=
            LibraryItemUnavailableCategory.sourceHasNoReadableEdition,
        hasReadableCanonicalGeneration: false,
        sourceFilePresent: sourceFilePresent,
      );
    }
    return LibraryAcquisitionOutcome(
      libraryItemId: libraryItemId,
      phase: LibraryAcquisitionPhase.ready,
      userSummary: 'Ready to read.',
      retryable: false,
      hasReadableCanonicalGeneration: true,
      sourceFilePresent: sourceFilePresent,
    );
  }
}
