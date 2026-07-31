import 'library_catalog_service.dart';

/// Why a book flagged `index_status = 'needs_attention'` cannot currently be
/// opened. Backed entirely by the reason text
/// [LibraryDocumentCanonicalizer] already writes to `index_error` when its
/// structural EPUB gate (shared with `EpubDownloadValidator`) rejects a
/// source file — no new persisted state, just a friendlier read of what is
/// already there.
enum LibraryItemUnavailableCategory {
  /// The source never had a complete EPUB for this title — only a
  /// placeholder/teaser package (missing OPF/manifest/spine, or a spine
  /// with no extractable text). Retrying will only help if the source
  /// itself later publishes a real edition.
  sourceHasNoReadableEdition,

  /// The most recently downloaded file failed validation in a way that
  /// looks like a transient/corrupted transfer (not a zip, corrupt zip,
  /// wrong title, etc.) rather than a genuinely missing edition. Retrying
  /// the download is likely to fix it.
  downloadFailedValidation,

  /// Flagged Needs Attention, but `index_error` didn't match a known
  /// rejection reason (e.g. cleared/legacy text).
  unknown,
}

class LibraryItemAvailability {
  const LibraryItemAvailability.available()
    : isAvailable = true,
      category = null,
      detail = null;

  const LibraryItemAvailability.unavailable({
    required this.category,
    this.detail,
  }) : isAvailable = false;

  final bool isAvailable;
  final LibraryItemUnavailableCategory? category;
  final String? detail;
}

final RegExp _needsAttentionReasonPattern = RegExp(
  r'Structurally invalid EPUB \(([a-zA-Z]+)\)',
);

const Set<String> _placeholderReasonNames = <String>{
  'missingOpf',
  'missingManifest',
  'missingSpine',
  'noReadableContent',
};

/// Shared categorization for a raw canonicalization/index rejection reason,
/// reused by [libraryItemAvailability] (existing `library_items.index_error`
/// text) and by [CanonicalActivation] (a fresh
/// [LibraryDocumentCanonicalizationResult.validationFailureReason]) so both
/// read the same "is this a placeholder/no-real-edition source, or a
/// transient/corrupt download" distinction instead of each re-implementing
/// the pattern match. Returns null only when [errorText] is empty.
LibraryItemUnavailableCategory? categorizeUnavailableReason(String? errorText) {
  final text = errorText?.trim() ?? '';
  if (text.isEmpty) return null;
  final reasonName = _needsAttentionReasonPattern.firstMatch(text)?.group(1);
  if (reasonName == null) return LibraryItemUnavailableCategory.unknown;
  return _placeholderReasonNames.contains(reasonName)
      ? LibraryItemUnavailableCategory.sourceHasNoReadableEdition
      : LibraryItemUnavailableCategory.downloadFailedValidation;
}

/// Reads the existing library status model (`index_status`/`index_error` on
/// `library_items`) to decide whether [item] can be opened in the reader.
/// Only `needs_attention` is treated as unavailable — every other status
/// (`metadata_only`, `indexed`, `indexed_empty`) already opens fine today
/// because the reader parses the EPUB directly and only falls back to
/// indexed text blocks; those statuses just describe search-index state.
LibraryItemAvailability libraryItemAvailability(LibraryCatalogItem item) {
  final normalizedStatus = (item.indexStatus ?? '').trim().toLowerCase();
  if (normalizedStatus != 'needs_attention') {
    return const LibraryItemAvailability.available();
  }

  final errorText = item.indexError?.trim() ?? '';
  final category =
      categorizeUnavailableReason(errorText) ??
      LibraryItemUnavailableCategory.unknown;
  return LibraryItemAvailability.unavailable(
    category: category,
    detail: errorText.isEmpty ? null : errorText,
  );
}

/// The single authoritative readability check for [item] — consulted by the
/// Books shelf, List view, Recent, search, and every reader-navigation entry
/// point so a `needs_attention` item (structurally invalid/placeholder EPUB,
/// no readable source) is hidden and never opened consistently everywhere,
/// instead of only being caught by whichever screen happens to call
/// [libraryItemAvailability] directly.
bool libraryItemIsNormallyReadable(LibraryCatalogItem item) =>
    libraryItemAvailability(item).isAvailable;

/// Maps a managed item's `collection_name` (as written by
/// `ELibraryFolderPolicy.managedEgwFolderDefinitions`) onto the matching
/// `installX` flag of `ELibraryDownloadService.runProductionSetup`, so a
/// single unavailable book can be retried without re-running all of eLibrary
/// Setup.
const Map<String, String> libraryManagedCollectionInstallFlags =
    <String, String>{
      'EGW Books': 'installBooks',
      'EGW Devotionals': 'installDevotionals',
      'EGW Commentaries': 'installCommentaries',
      'EGW Misc Collections': 'installMiscCollections',
      'EGW Pamphlets': 'installPamphlets',
      'EGW Periodicals': 'installPeriodicals',
      'EGW Manuscript Releases': 'installManuscriptReleases',
    };

/// True when [item] came from the official eLibrary collection downloader
/// and its collection is one [LibraryItemRetryDownloadService] knows how to
/// re-run — i.e. offering "Retry Download" is actually meaningful.
bool libraryItemSupportsRetryDownload(LibraryCatalogItem item) {
  final sourceType = (item.sourceType ?? '').trim().toLowerCase();
  if (sourceType != 'official_download') return false;
  final collectionName = item.collectionName?.trim() ?? '';
  return libraryManagedCollectionInstallFlags.containsKey(collectionName);
}
