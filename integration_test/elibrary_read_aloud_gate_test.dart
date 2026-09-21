import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_speech_controls.dart';

/// Verifies the fix for library_book_reader_screen.dart's narration gate,
/// which previously only rendered LibrarySpeechControls
/// (the "Read aloud" affordance) on macOS. Opens a real, already-bundled
/// eLibrary item through the actual production screen and checks the
/// button is now present on this platform.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('eLibrary reader shows Read aloud on this platform', (
    tester,
  ) async {
    final items = await tester.runAsync(
      () => LibraryCatalogService.instance.loadItems(),
    );
    // ignore: avoid_print
    print('ELIBRARY_GATE_STAGE items_loaded count=${items?.length}');
    expect(items, isNotNull);
    expect(items, isNotEmpty, reason: 'no bundled eLibrary items to open');
    final item = items!.first;
    // ignore: avoid_print
    print('ELIBRARY_GATE_STAGE opening item=${item.id} title=${item.title}');

    await tester.pumpWidget(
      MaterialApp(home: LibraryBookReaderScreen(item: item)),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 2));
    }
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('ELIBRARY_GATE_STAGE reader_settled');
    // ignore: avoid_print
    print('ELIBRARY_GATE_DIAG defaultTargetPlatform=$defaultTargetPlatform');
    // ignore: avoid_print
    print(
      'ELIBRARY_GATE_DIAG titleTextFound=${find.textContaining(item.title).evaluate().isNotEmpty} '
      'errorTextFound=${find.textContaining('rror').evaluate().isNotEmpty} '
      'spinnerFound=${find.byType(CircularProgressIndicator).evaluate().isNotEmpty} '
      'contentsLabelFound=${find.text('Contents').evaluate().isNotEmpty} '
      'noSectionsMsgFound=${find.textContaining('does not expose readable sections').evaluate().isNotEmpty} '
      'pdfMsgFound=${find.textContaining('PDF reading is not wired').evaluate().isNotEmpty} '
      'isPdf=${item.mimeType} fileFormat=${item.fileFormat}',
    );

    // A persisted "narration already enabled" preference from an earlier
    // session would make LibrarySpeechControls render its play/pause row
    // instead of the "Read aloud" bootstrap text, so check for the widget
    // itself rather than one specific internal label.
    final controls = find.byType(LibrarySpeechControls);
    final readAloud = find.widgetWithText(TextButton, 'Read aloud');
    // ignore: avoid_print
    print(
      'ELIBRARY_GATE_RESULT controlsPresent=${controls.evaluate().isNotEmpty} '
      'readAloudVisible=${readAloud.evaluate().isNotEmpty} '
      'voiceRowVisible=${find.text('Voice').evaluate().isNotEmpty}',
    );
    expect(
      controls,
      findsOneWidget,
      reason:
          'LibrarySpeechControls still missing from the eLibrary reader on this platform',
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}
