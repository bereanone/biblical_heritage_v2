import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import 'canonical_activation.dart';
import 'library_document_canonicalizer.dart';

class CanonicalEpubGenerationRepairReport {
  const CanonicalEpubGenerationRepairReport({
    required this.staleGenerationsScanned,
    required this.regenerated,
    required this.rejected,
    required this.skippedMissingFile,
    required this.staleStorageStatesRepaired,
  });

  /// Active canonical generations built by a canonicalizer version older
  /// than [LibraryDocumentCanonicalizer.version] — the only generations that
  /// could ever have skipped the structural EPUB gate, since every
  /// generation built by the current version already passed it.
  final int staleGenerationsScanned;

  /// Revalidated, passed, and rebuilt under the current canonicalizer
  /// version.
  final int regenerated;

  /// Revalidated and rejected as structurally invalid; their stale
  /// generation was removed and the item marked Needs Attention.
  final int rejected;

  /// Left untouched because the source EPUB could not be found on disk to
  /// revalidate against (never fabricated, never guessed).
  final int skippedMissingFile;

  /// `library_items` rows whose `epub_storage_state` claimed the EPUB was
  /// `present` when it was not actually found on disk.
  final int staleStorageStatesRepaired;
}

/// Repairs canonical library data left over from before
/// [LibraryDocumentCanonicalizer] gained its structural EPUB gate (shared
/// with [EpubDownloadValidator]).
///
/// Two independent problems are repaired here, both read-then-write against
/// whatever is actually on disk — nothing is ever fabricated or assumed:
///
///  1. A canonical generation built by an older canonicalizer version was
///     never checked structurally, so a placeholder/teaser EPUB (the exact
///     shape EGW's media CDN returns for some titles) could have been
///     accepted and indexed as if it were the real book. Revalidating it
///     through the normal [LibraryDocumentCanonicalizer.canonicalize] path
///     reuses every rule the gate already enforces (no duplicated
///     validation logic): a structurally sound file is simply rebuilt under
///     the current version, and a structurally invalid one has its stale
///     generation removed and the item marked Needs Attention — while the
///     `library_items` row itself (title, source_work_id, and everything
///     user-owned in the user database) is left completely untouched.
///  2. A `library_items` row can claim `epub_storage_state == 'present'`
///     while the file is actually missing (e.g. a failed/interrupted
///     download that never got the chance to mark itself). That stale flag
///     otherwise makes [EpubRedownloadService] believe nothing needs to be
///     fetched. It is corrected to `removed_after_index`, the state the
///     rest of the app already treats as "needs a redownload."
class CanonicalEpubGenerationRepairService {
  CanonicalEpubGenerationRepairService._();

  static final CanonicalEpubGenerationRepairService instance =
      CanonicalEpubGenerationRepairService._();

  Future<CanonicalEpubGenerationRepairReport> repair({
    required Database db,
    required String rootPath,
    bool allowVersionUpgrade = true,
  }) async {
    final staleGenerations = allowVersionUpgrade
        ? await db.query(
            'library_document_conversion',
            columns: const <String>['library_item_id'],
            where: 'status = ? AND canonicalizer_version != ?',
            whereArgs: <Object?>[
              'complete',
              LibraryDocumentCanonicalizer.version,
            ],
          )
        : const <Map<String, Object?>>[];

    var regenerated = 0;
    var rejected = 0;
    var skippedMissingFile = 0;
    for (final row in staleGenerations) {
      final itemId = row['library_item_id']?.toString().trim() ?? '';
      if (itemId.isEmpty) continue;
      final source = await _resolveSourceFile(
        db: db,
        itemId: itemId,
        rootPath: rootPath,
      );
      if (source == null) {
        skippedMissingFile += 1;
        continue;
      }
      final outcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: source,
      );
      if (outcome.isReady) {
        regenerated += 1;
      } else {
        rejected += 1;
      }
    }

    final staleStorageStatesRepaired = await _repairStaleStorageStates(
      db: db,
      rootPath: rootPath,
    );

    return CanonicalEpubGenerationRepairReport(
      staleGenerationsScanned: staleGenerations.length,
      regenerated: regenerated,
      rejected: rejected,
      skippedMissingFile: skippedMissingFile,
      staleStorageStatesRepaired: staleStorageStatesRepaired,
    );
  }

  Future<File?> _resolveSourceFile({
    required Database db,
    required String itemId,
    required String rootPath,
  }) async {
    final itemRows = await db.query(
      'library_items',
      columns: const <String>['relative_path', 'file_format'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: <Object?>[itemId],
      limit: 1,
    );
    if (itemRows.isEmpty) return null;
    final row = itemRows.first;
    if ((row['file_format']?.toString() ?? '').trim().toLowerCase() != 'epub') {
      return null;
    }
    final relativePath = row['relative_path']?.toString().trim() ?? '';
    if (relativePath.isEmpty) return null;
    return LibraryRootService.instance.resolveExistingAssetFile(
      relativePath: relativePath,
      rootPath: rootPath,
    );
  }

  Future<int> _repairStaleStorageStates({
    required Database db,
    required String rootPath,
  }) async {
    final rows = await db.query(
      'library_items',
      columns: const <String>['id', 'relative_path'],
      where: '''
        deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(epub_storage_state, 'present')) = 'present'
      ''',
    );
    var repaired = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in rows) {
      final itemId = row['id']?.toString().trim() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (itemId.isEmpty || relativePath.isEmpty) continue;
      final existingFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: relativePath,
            rootPath: rootPath,
          );
      if (existingFile != null) continue;
      await db.update(
        'library_items',
        <String, Object?>{
          'epub_storage_state': 'removed_after_index',
          'epub_removed_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[itemId],
      );
      repaired += 1;
    }
    return repaired;
  }
}
