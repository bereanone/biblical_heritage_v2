import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/presentation/library_indexing_prompt_dialogs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LibraryIndexingPromptGate', () {
    test('prompts when pending count is greater than zero', () {
      final gate = LibraryIndexingPromptGate();
      expect(gate.shouldPrompt(456), isTrue);
    });

    test('does not prompt when pending count is zero', () {
      final gate = LibraryIndexingPromptGate();
      expect(gate.shouldPrompt(0), isFalse);
    });

    test('does not prompt again once already shown this session', () {
      final gate = LibraryIndexingPromptGate();
      expect(gate.shouldPrompt(456), isTrue);
      expect(gate.shouldPrompt(456), isFalse);
      expect(gate.shouldPrompt(10), isFalse);
    });
  });

  group('showLibraryIndexingPromptDialog', () {
    testWidgets('shows the pending count and returns indexNow', (tester) async {
      LibraryIndexingPromptAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showLibraryIndexingPromptDialog(
                    context,
                    pendingCount: 456,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Finish Setting Up Your Library'), findsOneWidget);
      expect(
        find.textContaining('456 downloaded books still need indexing'),
        findsOneWidget,
      );
      expect(find.textContaining("today's devotional entry"), findsOneWidget);

      await tester.tap(find.text('Index Now'));
      await tester.pumpAndSettle();

      expect(result, LibraryIndexingPromptAction.indexNow);
    });

    testWidgets('returns later when dismissed with Later', (tester) async {
      LibraryIndexingPromptAction? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () async {
                  result = await showLibraryIndexingPromptDialog(
                    context,
                    pendingCount: 1,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('1 downloaded book still needs indexing'),
        findsOneWidget,
      );

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(result, LibraryIndexingPromptAction.later);
    });
  });

  group('LibraryIndexingPendingCard', () {
    testWidgets('renders nothing when pending count is zero', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryIndexingPendingCard(
              pendingCount: 0,
              busy: false,
              onIndexNow: () {},
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsNothing);
      expect(find.text('Index Now'), findsNothing);
    });

    testWidgets('shows the pending count and an Index Now button', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryIndexingPendingCard(
              pendingCount: 456,
              busy: false,
              onIndexNow: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('456 books need indexing'), findsOneWidget);
      expect(find.text('Index Now'), findsOneWidget);

      await tester.tap(find.text('Index Now'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('disables the button and relabels it while busy', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryIndexingPendingCard(
              pendingCount: 456,
              busy: true,
              onIndexNow: () {},
            ),
          ),
        ),
      );

      expect(find.text('Indexing…'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Indexing…'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('uses singular wording for exactly one book', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryIndexingPendingCard(
              pendingCount: 1,
              busy: false,
              onIndexNow: () {},
            ),
          ),
        ),
      );

      expect(find.text('1 book needs indexing'), findsOneWidget);
    });
  });

  group('LibraryNeedsAttentionCard', () {
    List<LibraryNeedsAttentionEntry> entries() {
      return const [
        LibraryNeedsAttentionEntry(
          title: 'Christ Our Saviour',
          fileName: 'en_COS.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'The Impending Conflict',
          fileName: 'en_IC.epub',
          reason: 'No readable text content found after parsing.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Third Book',
          fileName: 'third.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Fourth Book',
          fileName: 'fourth.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Fifth Book',
          fileName: 'fifth.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Sixth Book',
          fileName: 'sixth.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Seventh Book',
          fileName: 'seventh.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
        LibraryNeedsAttentionEntry(
          title: 'Eighth Book',
          fileName: 'eighth.epub',
          reason: 'Missing OEBPS/content.opf entry.',
        ),
      ];
    }

    testWidgets('shows a compact friendly summary by default', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LibraryNeedsAttentionCard(items: entries())),
        ),
      );

      expect(find.text('8 unreadable books set aside'), findsOneWidget);
      expect(
        find.text('Hidden from the library; original files were preserved.'),
        findsOneWidget,
      );
      expect(find.text('Christ Our Saviour'), findsNothing);
      expect(find.text('The Impending Conflict'), findsNothing);
      expect(find.text('Third Book'), findsNothing);
      expect(find.text('Review'), findsOneWidget);
      expect(find.textContaining('OPF'), findsNothing);
      expect(find.textContaining('Filename:'), findsNothing);
    });

    testWidgets('reveals set-aside details in the Review dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LibraryNeedsAttentionCard(items: entries())),
        ),
      );

      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(find.text('8 unreadable books set aside'), findsNWidgets(2));
      expect(find.textContaining('Filename: en_COS.epub'), findsOneWidget);
      expect(find.textContaining('Filename: en_IC.epub'), findsOneWidget);
      expect(
        find.text('Reason: The downloaded book file is incomplete.'),
        findsNWidgets(7),
      );
      expect(
        find.text('Reason: No readable book content was found.'),
        findsOneWidget,
      );
    });
  });
}
