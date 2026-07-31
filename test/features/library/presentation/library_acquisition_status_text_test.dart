import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/library/presentation/library_acquisition_status_text.dart';

LibraryAcquisitionOutcome _outcome({
  required LibraryAcquisitionPhase phase,
  bool retryable = false,
  bool storagePolicyCleanupFailed = false,
}) => LibraryAcquisitionOutcome(
  libraryItemId: 'item',
  phase: phase,
  userSummary:
      'raw internal summary text — should never be shown by these mappers',
  technicalDetail: 'Structurally invalid EPUB (missingOpf): raw detail',
  retryable: retryable,
  hasReadableCanonicalGeneration: phase == LibraryAcquisitionPhase.ready,
  sourceFilePresent: true,
  storagePolicyCleanupFailed: storagePolicyCleanupFailed,
);

void main() {
  group('15/16. libraryAcquisitionFriendlyText maps every relevant phase', () {
    test('sourceUnavailable', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.sourceUnavailable),
        ),
        'A readable edition is not currently available from the source.',
      );
    });

    test('failedDownload', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.failedDownload),
        ),
        'The download could not be completed. Try again.',
      );
    });

    test('failedValidation', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.failedValidation),
        ),
        'The selected book is not a readable EPUB.',
      );
    });

    test('failedImport', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.failedImport),
        ),
        'The book could not be prepared for reading. The source file was '
        'not altered.',
      );
    });

    test('retainedFromPriorGeneration', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.retainedFromPriorGeneration),
        ),
        'The update could not be completed, but your existing readable '
        'copy was preserved.',
      );
    });

    test('storage cleanup failure on an otherwise-ready outcome', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(
            phase: LibraryAcquisitionPhase.ready,
            storagePolicyCleanupFailed: true,
          ),
        ),
        'The book is ready to read, but its temporary source copy could '
        'not be removed.',
      );
    });

    test('ready with no cleanup issue', () {
      expect(
        libraryAcquisitionFriendlyText(
          _outcome(phase: LibraryAcquisitionPhase.ready),
        ),
        'Ready to read.',
      );
    });

    test(
      'never returns the raw userSummary or technicalDetail for a mapped phase',
      () {
        for (final phase in const [
          LibraryAcquisitionPhase.sourceUnavailable,
          LibraryAcquisitionPhase.failedDownload,
          LibraryAcquisitionPhase.failedValidation,
          LibraryAcquisitionPhase.failedImport,
          LibraryAcquisitionPhase.retainedFromPriorGeneration,
        ]) {
          final text = libraryAcquisitionFriendlyText(_outcome(phase: phase));
          expect(text, isNot(contains('raw internal summary')));
          expect(text, isNot(contains('missingOpf')));
        }
      },
    );
  });

  group('progress labels', () {
    test('downloading/validating/preparing use a verb + title', () {
      expect(
        libraryAcquisitionProgressLabel(
          phase: LibraryAcquisitionPhase.validating,
          title: 'The Desire of Ages',
        ),
        'Validating The Desire of Ages',
      );
      expect(
        libraryAcquisitionProgressLabel(
          phase: LibraryAcquisitionPhase.preparing,
          title: 'Child Guidance',
        ),
        'Preparing Child Guidance',
      );
    });

    test('ready phases collapse to "Ready to read"', () {
      expect(
        libraryAcquisitionProgressLabel(
          phase: LibraryAcquisitionPhase.ready,
          title: 'Anything',
        ),
        'Ready to read',
      );
    });

    test('count label formats "Downloading 12 of 147"', () {
      expect(
        libraryAcquisitionCountLabel(
          verb: 'Downloading',
          current: 12,
          total: 147,
        ),
        'Downloading 12 of 147',
      );
    });
  });

  group('batch summary', () {
    test('"145 books ready, 2 unavailable"', () {
      final outcomes = <LibraryAcquisitionOutcome>[
        for (var i = 0; i < 145; i++)
          _outcome(phase: LibraryAcquisitionPhase.ready),
        _outcome(phase: LibraryAcquisitionPhase.sourceUnavailable),
        _outcome(phase: LibraryAcquisitionPhase.failedValidation),
      ];
      final result = LibraryAcquisitionBatchResult(
        targets: const [],
        outcomes: outcomes,
      );
      expect(
        libraryAcquisitionBatchSummary(result),
        '145 books ready, 2 unavailable',
      );
    });

    test('singular book, no failures', () {
      final result = LibraryAcquisitionBatchResult(
        targets: const [],
        outcomes: [_outcome(phase: LibraryAcquisitionPhase.ready)],
      );
      expect(libraryAcquisitionBatchSummary(result), '1 book ready');
    });
  });
}
