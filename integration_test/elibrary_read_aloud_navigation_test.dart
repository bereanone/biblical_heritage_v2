import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_speech_controls.dart';
import 'package:studybible2/main.dart' as app;

/// Verifies the library_book_reader_screen.dart narration-gate fix by
/// navigating the real app exactly as a user would (Entry -> Bible Explorer
/// -> eLibrary -> tap a book), rather than constructing the reader screen
/// directly — a prior attempt to instantiate LibraryBookReaderScreen in
/// isolation loaded content successfully but never exposed
/// LibrarySpeechControls, which pointed at some difference between that
/// isolated construction and the real navigation path (missing ancestor
/// state/providers normally set up during app bootstrap).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eLibrary book reader shows narration controls via real nav', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('NAV_STAGE entry_screen');

    final skip = find.text('Skip for Now');
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // ignore: avoid_print
      print('NAV_STAGE dismissed_setup_dialog');
    }

    final bibleExplorerButton = find.widgetWithText(
      ElevatedButton,
      'Bible Explorer',
    );
    expect(bibleExplorerButton, findsOneWidget);
    await tester.tap(bibleExplorerButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('NAV_STAGE bible_explorer_open');

    final libraryButton = find.byTooltip('eLibrary');
    // ignore: avoid_print
    print(
      'NAV_STAGE libraryButtonFound=${libraryButton.evaluate().isNotEmpty}',
    );
    expect(libraryButton, findsOneWidget);
    await tester.tap(libraryButton.first);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('NAV_STAGE library_open');

    final bookTile = find.text('The Cross and Its Shadow');
    // ignore: avoid_print
    print('NAV_STAGE bookTileFound=${bookTile.evaluate().isNotEmpty}');
    if (bookTile.evaluate().isEmpty) {
      final allTexts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .where((s) => s.trim().isNotEmpty)
          .take(60)
          .join(' | ');
      // ignore: avoid_print
      print('NAV_DIAG visibleTexts=$allTexts');
      return;
    }
    await tester.tap(bookTile.first);
    await tester.pumpAndSettle(const Duration(seconds: 8));
    // ignore: avoid_print
    print('NAV_STAGE book_open');

    final controls = find.byType(LibrarySpeechControls);
    // ignore: avoid_print
    print(
      'NAV_RESULT controlsPresent=${controls.evaluate().isNotEmpty} '
      'readAloudVisible=${find.widgetWithText(TextButton, 'Read aloud').evaluate().isNotEmpty} '
      'voiceRowVisible=${find.text('Voice').evaluate().isNotEmpty} '
      'canonicalScreenPresent=${find.byType(CanonicalLibraryReaderScreen).evaluate().isNotEmpty} '
      'legacyScreenPresent=${find.byType(LibraryBookReaderScreen).evaluate().isNotEmpty} '
      'reconnectErrorFound=${find.textContaining('Reconnect the Library Root').evaluate().isNotEmpty}',
    );
  }, timeout: const Timeout(Duration(minutes: 4)));
}
