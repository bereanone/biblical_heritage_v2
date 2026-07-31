import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/data/canonical_activation.dart';
import 'package:studybible2/features/library/data/library_acquisition_batch_runner.dart';
import 'package:studybible2/features/library/presentation/library_acquisition_progress_view.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    '15. in-progress state renders a phase label and a progress indicator',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          const LibraryAcquisitionProgressView(
            progress: LibraryAcquisitionBatchProgress(
              current: 12,
              total: 147,
              currentTitle: 'The Desire of Ages',
              phase: LibraryAcquisitionPhase.validating,
            ),
          ),
        ),
      );

      expect(
        find.text('Validating The Desire of Ages (12 of 147)'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('cancel button only appears when onCancel is supplied', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      _wrap(
        LibraryAcquisitionProgressView(
          progress: const LibraryAcquisitionBatchProgress(
            current: 1,
            total: 3,
            currentTitle: 'Book A',
            phase: LibraryAcquisitionPhase.preparing,
          ),
          onCancel: () => cancelled = true,
        ),
      ),
    );

    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancelled, isTrue);
  });

  testWidgets(
    '16. Advanced Details is collapsed by default and reveals technicalDetail '
    'only when expanded',
    (tester) async {
      final result = LibraryAcquisitionBatchResult(
        targets: const [],
        outcomes: [
          const LibraryAcquisitionOutcome(
            libraryItemId: 'broken-book',
            phase: LibraryAcquisitionPhase.sourceUnavailable,
            userSummary: 'unused',
            technicalDetail:
                'Structurally invalid EPUB (missingOpf): raw diagnostic text',
            retryable: false,
            hasReadableCanonicalGeneration: false,
            sourceFilePresent: false,
          ),
        ],
      );

      await tester.pumpWidget(
        _wrap(LibraryAcquisitionProgressView(result: result)),
      );

      expect(find.textContaining('unavailable'), findsOneWidget);
      // Friendly text shown (as a bulleted line), raw technical text
      // hidden by default.
      expect(
        find.textContaining(
          'A readable edition is not currently available from the source.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('missingOpf'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, 'Advanced Details'));
      await tester.pumpAndSettle();

      expect(find.textContaining('missingOpf'), findsOneWidget);
    },
  );

  testWidgets(
    'Retry Failed Books only appears when there is a failure and a callback',
    (tester) async {
      final result = LibraryAcquisitionBatchResult(
        targets: const [],
        outcomes: [
          const LibraryAcquisitionOutcome(
            libraryItemId: 'a',
            phase: LibraryAcquisitionPhase.ready,
            userSummary: 'Ready to read.',
            retryable: false,
            hasReadableCanonicalGeneration: true,
            sourceFilePresent: true,
          ),
          const LibraryAcquisitionOutcome(
            libraryItemId: 'b',
            phase: LibraryAcquisitionPhase.failedValidation,
            userSummary: 'unused',
            retryable: true,
            hasReadableCanonicalGeneration: false,
            sourceFilePresent: true,
          ),
        ],
      );

      var retried = false;
      await tester.pumpWidget(
        _wrap(
          LibraryAcquisitionProgressView(
            result: result,
            onRetryFailed: () => retried = true,
          ),
        ),
      );

      expect(find.text('1 book ready, 1 unavailable'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Retry Failed Books'));
      expect(retried, isTrue);
    },
  );
}
