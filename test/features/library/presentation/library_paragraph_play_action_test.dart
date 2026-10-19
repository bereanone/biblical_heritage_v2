import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_selection_menu.dart';

void main() {
  testWidgets('Play from here closes Range Actions and returns playback action', (tester) async {
    LibrarySelectionRangeAction? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await showLibrarySelectionRangeActionsSheet(context,
        payload: const LibrarySelectionRangeActionsPayload(referenceLabel: 'Daniel chapter 1', previewText: 'This', enableClearMarkup: false), fontScale: 1); },
      child: const Text('Select paragraph'),
    )))));
    await tester.tap(find.text('Select paragraph'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play from here'));
    await tester.pumpAndSettle();
    expect(result, LibrarySelectionRangeAction.playFromHere);
    expect(find.text('Range Actions'), findsNothing);
  });
}
