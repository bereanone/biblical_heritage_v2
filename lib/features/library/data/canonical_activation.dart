import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utilities/data/epub_storage_policy_service.dart';
import 'library_document_canonicalizer.dart';
import 'library_document_repository.dart';
import 'library_item_availability.dart';

/// Human-oriented phase for a single library item's acquisition/preparation
/// lifecycle. Deliberately independent of any raw `library_items.index_status`
/// or `library_document_conversion.status` string — those remain internal.
enum LibraryAcquisitionPhase {
  availableToDownload,
  downloading,
  validating,
  preparing,
  ready,
  needsAttention,
  sourceUnavailable,
  failedDownload,
  failedValidation,
  failedImport,

  /// A replacement candidate was attempted (download, repair, or rebuild)
  /// but did not activate; the previously-active canonical generation (and
  /// therefore the book's readability) was left completely untouched.
  retainedFromPriorGeneration,

  /// A canonical generation just activated successfully and the device
  /// storage policy then removed the app-managed source copy (the canonical
  /// database copy is unaffected and the book remains readable).
  removedSourceAfterSuccessfulImport,
}

/// Typed, human-oriented outcome of a single acquisition/preparation step.
/// [technicalDetail] is the only place raw validator/database text ever
/// surfaces — normal UI must read [userSummary] instead, reserving
/// [technicalDetail] for an explicit Advanced Details view or logging.
class LibraryAcquisitionOutcome {
  const LibraryAcquisitionOutcome({
    required this.libraryItemId,
    required this.phase,
    required this.userSummary,
    this.technicalDetail,
    required this.retryable,
    required this.hasReadableCanonicalGeneration,
    required this.sourceFilePresent,
    this.storagePolicyRemovedManagedCopyOnly = false,
    this.storagePolicyCleanupFailed = false,
    this.progressCurrent,
    this.progressTotal,
  });

  final String libraryItemId;
  final LibraryAcquisitionPhase phase;

  /// Friendly, user-facing summary (e.g. "Ready to read.",
  /// "A readable edition is not currently available."). Never a raw
  /// database status string.
  final String userSummary;

  /// Raw detail (validator reason, exception text, storage-policy reason)
  /// intended for an Advanced Details disclosure or logging only.
  final String? technicalDetail;

  final bool retryable;
  final bool hasReadableCanonicalGeneration;
  final bool sourceFilePresent;

  /// True only when a successful activation was immediately followed by the
  /// device storage policy removing the app-managed source copy (never the
  /// canonical database copy, and never a CaptureClipper/user-provided
  /// source, which the policy never touches).
  final bool storagePolicyRemovedManagedCopyOnly;

  /// True when activation succeeded (the book is readable) but the device
  /// storage policy decided to remove the source and the removal attempt
  /// itself threw (e.g. a locked/in-use file). The canonical generation is
  /// unaffected either way — this only ever describes a failed cleanup of
  /// an already-redundant source copy, never a failure to read the book.
  final bool storagePolicyCleanupFailed;

  final int? progressCurrent;
  final int? progressTotal;

  bool get isReady =>
      phase == LibraryAcquisitionPhase.ready ||
      phase == LibraryAcquisitionPhase.removedSourceAfterSuccessfulImport;
}

/// The single shared "finish preparing this book" primitive: canonicalize
/// into staging, confirm activation, and optionally apply the device EPUB
/// storage policy. Every production entry point that used to call
/// [LibraryDocumentCanonicalizer] directly (the reader's lazy preparation,
/// redownload, single-item retry, and stale-generation repair) now funnels
/// through here instead, so the same activation + storage-policy sequence is
/// defined exactly once. Never duplicates [LibraryDocumentCanonicalizer],
/// [LibraryDocumentImportValidator], or [EpubStoragePolicyService] logic —
/// it only sequences and reports on them.
class CanonicalActivation {
  const CanonicalActivation._();

  static Future<LibraryAcquisitionOutcome> activate({
    required Database db,
    required String libraryItemId,
    required File source,
    bool applyStoragePolicy = false,
    String? rootPath,
    bool force = false,
  }) async {
    final repository = LibraryDocumentRepository(db);
    final LibraryDocumentCanonicalizationResult result;
    try {
      result = await const LibraryDocumentCanonicalizer().canonicalize(
        db: db,
        libraryItemId: libraryItemId,
        source: source,
        force: force,
      );
    } catch (error) {
      final hasReadable = await repository.isComplete(libraryItemId);
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: LibraryAcquisitionPhase.failedImport,
        userSummary: hasReadable
            ? 'The book could not be updated; your existing readable copy '
                  'was kept.'
            : 'The book could not be prepared; the source file was not '
                  'altered.',
        technicalDetail: error.toString(),
        retryable: true,
        hasReadableCanonicalGeneration: hasReadable,
        sourceFilePresent: await source.exists(),
      );
    }

    final isCurrentComplete = await repository.isCurrentComplete(
      libraryItemId,
      canonicalizerVersion: LibraryDocumentCanonicalizer.version,
    );

    if (result.activated && isCurrentComplete) {
      EpubStoragePolicyDecision? storageDecision;
      var cleanupFailed = false;
      String? cleanupError;
      if (applyStoragePolicy) {
        try {
          storageDecision = await EpubStoragePolicyService.instance
              .applyPolicyAfterValidatedImport(
                libraryItemId: libraryItemId,
                epubFile: source,
                rootPath: rootPath,
              );
        } catch (error) {
          cleanupFailed = true;
          cleanupError = error.toString();
        }
      }
      final removed = storageDecision?.shouldRemoveEpub ?? false;
      return LibraryAcquisitionOutcome(
        libraryItemId: libraryItemId,
        phase: removed
            ? LibraryAcquisitionPhase.removedSourceAfterSuccessfulImport
            : LibraryAcquisitionPhase.ready,
        userSummary: removed
            ? 'Ready to read. Removed from this device to save space; still '
                  'available from your library.'
            : cleanupFailed
            ? 'Ready to read. Its temporary source copy could not be removed.'
            : 'Ready to read.',
        technicalDetail: result.skipped
            ? 'Canonical generation already current; rebuild skipped.'
            : cleanupFailed
            ? cleanupError
            : storageDecision?.reason,
        retryable: false,
        hasReadableCanonicalGeneration: true,
        sourceFilePresent: await source.exists(),
        storagePolicyRemovedManagedCopyOnly: removed,
        storagePolicyCleanupFailed: cleanupFailed,
      );
    }

    final category = categorizeUnavailableReason(
      result.validationFailureReason,
    );
    final hasReadable = await repository.isComplete(libraryItemId);
    final phase = hasReadable
        ? LibraryAcquisitionPhase.retainedFromPriorGeneration
        : category == LibraryItemUnavailableCategory.sourceHasNoReadableEdition
        ? LibraryAcquisitionPhase.sourceUnavailable
        : LibraryAcquisitionPhase.failedValidation;
    return LibraryAcquisitionOutcome(
      libraryItemId: libraryItemId,
      phase: phase,
      userSummary: switch (phase) {
        LibraryAcquisitionPhase.retainedFromPriorGeneration =>
          'The book could not be updated; your existing readable copy was '
              'kept.',
        LibraryAcquisitionPhase.sourceUnavailable =>
          'A readable edition is not currently available.',
        _ =>
          'The book could not be prepared; the source file was not '
              'altered.',
      },
      technicalDetail: result.validationFailureReason,
      retryable:
          category != LibraryItemUnavailableCategory.sourceHasNoReadableEdition,
      hasReadableCanonicalGeneration: hasReadable,
      sourceFilePresent: await source.exists(),
    );
  }
}
