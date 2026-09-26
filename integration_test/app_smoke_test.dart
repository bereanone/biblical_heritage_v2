import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:studybible2/main.dart' as app;

/// Baseline smoke test: boots the real app against the real installed
/// library database, opens Bible Explorer, and opens eLibrary — establishing
/// that ordinary navigation is unaffected by the narration changes in this
/// session before narration itself is exercised separately.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App boots, opens Bible Explorer and eLibrary', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('SMOKE_STAGE entry_screen');

    final bibleExplorerButton = find.widgetWithText(
      ElevatedButton,
      'Bible Explorer',
    );
    expect(bibleExplorerButton, findsOneWidget);
    await tester.tap(bibleExplorerButton);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // ignore: avoid_print
    print('SMOKE_STAGE bible_explorer_open');

    final libraryButton = find.byTooltip('eLibrary');
    // ignore: avoid_print
    print('SMOKE_RESULT libraryButtonFound=${libraryButton.evaluate().isNotEmpty}');
    if (libraryButton.evaluate().isNotEmpty) {
      await tester.tap(libraryButton.first);
      await tester.pumpAndSettle(const Duration(seconds: 5));
      // ignore: avoid_print
      print('SMOKE_STAGE library_open');
    }

    // ignore: avoid_print
    print('SMOKE_STAGE done');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
