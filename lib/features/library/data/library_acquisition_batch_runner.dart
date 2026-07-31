import '../../../core/database/elibrary_database.dart';
import '../../../core/bootstrap/library_root_service.dart';
import 'canonical_activation.dart';
import 'library_acquisition_orchestrator.dart';
import 'library_document_canonicalizer.dart';
import 'library_document_repository.dart';

/// One item awaiting canonical preparation: an already-cataloged library
/// item whose source file is known to be on disk at [relativePath].
class LibraryAcquisitionBatchTarget {
  const LibraryAcquisitionBatchTarget({
    required this.libraryItemId,
    required this.relativePath,
    required this.title,
  });

  final String libraryItemId;
  final String relativePath;
  final String title;
}

/// One point-in-time progress update for a batch run, e.g. rendered as
/// "Preparing The Desire of Ages (12 of 147)".
class LibraryAcquisitionBatchProgress {
  const LibraryAcquisitionBatchProgress({
    required this.current,
    required this.total,
    required this.currentTitle,
    required this.phase,
  });

  final int current;
  final int total;
  final String currentTitle;
  final LibraryAcquisitionPhase phase;
}

class LibraryAcquisitionBatchResult {
  const LibraryAcquisitionBatchResult({
    required this.targets,
    required this.outcomes,
  });

  final List<LibraryAcquisitionBatchTarget> targets;
  final List<LibraryAcquisitionOutcome> outcomes;

  int get readyCount => outcomes.where((o) => o.isReady).length;

  List<LibraryAcquisitionOutcome> get unavailableOutcomes =>
      outcomes.where((o) => !o.isReady).toList(growable: false);

  /// Targets whose outcome did not end up ready, paired back with their
  /// title/relative path so "Retry Failed Books" can re-run just these.
  List<LibraryAcquisitionBatchTarget> get failedTargets {
    final failedIds = unavailableOutcomes.map((o) => o.libraryItemId).toSet();
    return targets
        .where((t) => failedIds.contains(t.libraryItemId))
        .toList(growable: false);
  }
}

/// Shared "activate a batch of already-downloaded managed EPUBs" runner.
/// This is the one place that loops [LibraryAcquisitionOrchestrator] over
/// many items with progress reporting, so no screen needs to reimplement
/// that loop itself. Every activation is atomic per item (see
/// [CanonicalActivation]), so stopping between items via [shouldContinue]
/// can never leave a partially-activated generation.
class LibraryAcquisitionBatchRunner {
  LibraryAcquisitionBatchRunner._();

  static final LibraryAcquisitionBatchRunner instance =
      LibraryAcquisitionBatchRunner._();

  /// Every managed official-download EPUB item that does not yet have a
  /// current-complete canonical generation. Safe to call repeatedly:
  /// [CanonicalActivation.activate] skips deterministically when a source
  /// is unchanged, so re-including an already-ready item just costs one
  /// cheap no-op pass rather than corrupting anything.
  Future<List<LibraryAcquisitionBatchTarget>>
  loadPendingOfficialDownloadItems() async {
    final db = await ELibraryDatabase.instance.database;
    final repository = LibraryDocumentRepository(db);
    final rows = await db.query(
      'library_items',
      columns: const <String>['id', 'relative_path', 'title'],
      where: '''
        deleted_at IS NULL
        AND COALESCE(is_missing, 0) = 0
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(source_type, '')) = 'official_download'
      ''',
    );
    final targets = <LibraryAcquisitionBatchTarget>[];
    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (id.isEmpty || relativePath.isEmpty) continue;
      final alreadyComplete = await repository.isCurrentComplete(
        id,
        canonicalizerVersion: LibraryDocumentCanonicalizer.version,
      );
      if (alreadyComplete) continue;
      final title = row['title']?.toString().trim() ?? '';
      targets.add(
        LibraryAcquisitionBatchTarget(
          libraryItemId: id,
          relativePath: relativePath,
          title: title.isEmpty ? id : title,
        ),
      );
    }
    return targets;
  }

  Future<LibraryAcquisitionBatchResult> activate(
    List<LibraryAcquisitionBatchTarget> targets, {
    void Function(LibraryAcquisitionBatchProgress progress)? onProgress,
    bool Function()? shouldContinue,
  }) async {
    await LibraryRootService.instance.requireLibraryAuthorization();
    final outcomes = <LibraryAcquisitionOutcome>[];
    for (var index = 0; index < targets.length; index++) {
      if (shouldContinue != null && !shouldContinue()) break;
      final target = targets[index];
      onProgress?.call(
        LibraryAcquisitionBatchProgress(
          current: index + 1,
          total: targets.length,
          currentTitle: target.title,
          phase: LibraryAcquisitionPhase.preparing,
        ),
      );
      final outcome = await LibraryAcquisitionOrchestrator.instance
          .prepareExistingEpub(
            libraryItemId: target.libraryItemId,
            relativePath: target.relativePath,
          );
      outcomes.add(outcome);
      onProgress?.call(
        LibraryAcquisitionBatchProgress(
          current: index + 1,
          total: targets.length,
          currentTitle: target.title,
          phase: outcome.phase,
        ),
      );
    }
    return LibraryAcquisitionBatchResult(
      targets: targets.take(outcomes.length).toList(growable: false),
      outcomes: outcomes,
    );
  }
}
