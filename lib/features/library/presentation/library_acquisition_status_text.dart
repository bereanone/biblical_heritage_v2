import '../data/canonical_activation.dart';
import '../data/library_acquisition_batch_runner.dart';

/// Maps a finished [LibraryAcquisitionOutcome] to the exact plain-language
/// copy the setup flows must show. Never returns a raw database field or
/// stack trace — that belongs only in [LibraryAcquisitionOutcome.technicalDetail],
/// surfaced through an explicit Advanced Details disclosure.
String libraryAcquisitionFriendlyText(LibraryAcquisitionOutcome outcome) {
  if (outcome.isReady) {
    if (outcome.storagePolicyCleanupFailed) {
      return 'The book is ready to read, but its temporary source copy '
          'could not be removed.';
    }
    return 'Ready to read.';
  }
  switch (outcome.phase) {
    case LibraryAcquisitionPhase.sourceUnavailable:
      return 'A readable edition is not currently available from the '
          'source.';
    case LibraryAcquisitionPhase.failedDownload:
      return 'The download could not be completed. Try again.';
    case LibraryAcquisitionPhase.failedValidation:
      return 'The selected book is not a readable EPUB.';
    case LibraryAcquisitionPhase.failedImport:
      return 'The book could not be prepared for reading. The source file '
          'was not altered.';
    case LibraryAcquisitionPhase.retainedFromPriorGeneration:
      return 'The update could not be completed, but your existing '
          'readable copy was preserved.';
    case LibraryAcquisitionPhase.needsAttention:
      return outcome.retryable
          ? 'The book could not be prepared for reading. The source file '
                'was not altered.'
          : 'A readable edition is not currently available from the '
                'source.';
    default:
      return outcome.userSummary;
  }
}

/// One-line label for a phase currently in progress (not yet a finished
/// outcome), e.g. "Validating The Desire of Ages" or "Preparing Child
/// Guidance". Falls back to the plain title for phases with no dedicated
/// verb.
String libraryAcquisitionProgressLabel({
  required LibraryAcquisitionPhase phase,
  required String title,
}) {
  switch (phase) {
    case LibraryAcquisitionPhase.downloading:
      return 'Downloading $title';
    case LibraryAcquisitionPhase.validating:
      return 'Validating $title';
    case LibraryAcquisitionPhase.preparing:
      return 'Preparing $title';
    case LibraryAcquisitionPhase.ready:
    case LibraryAcquisitionPhase.removedSourceAfterSuccessfulImport:
      return 'Ready to read';
    default:
      return title;
  }
}

/// "Downloading 12 of 147" — used while a bulk step has a known count but
/// no single current title worth naming yet.
String libraryAcquisitionCountLabel({
  required String verb,
  required int current,
  required int total,
}) => '$verb $current of $total';

/// "145 books ready, 2 unavailable" (or "12 books ready" when everything
/// succeeded) — the single shared batch-completion summary line.
String libraryAcquisitionBatchSummary(LibraryAcquisitionBatchResult result) {
  final ready = result.readyCount;
  final unavailable = result.unavailableOutcomes.length;
  final readyText = '$ready book${ready == 1 ? '' : 's'} ready';
  if (unavailable == 0) return readyText;
  return '$readyText, $unavailable unavailable';
}
