import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_item_availability.dart';
import 'package:studybible2/features/library/presentation/library_unavailable_book_dialog.dart';

LibraryCatalogItem _catalogItem({String title = 'Christ Our Saviour'}) {
  return LibraryCatalogItem(
    id: 'item-1',
    title: title,
    author: null,
    fileName: 'item-1.epub',
    fileHash: null,
    relativePath: 'ePubs/EGW/EGW_Books/item-1.epub',
    fileFormat: 'epub',
    folderType: 'research',
    libraryRole: 'research',
    collectionName: 'EGW Books',
    sourceSite: 'egwwritings.org',
    sourceUrl: null,
    sourceType: 'official_download',
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: 'needs_attention',
    fileSize: 0,
    mimeType: 'application/epub+zip',
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

Future<void> _openDialog(
  WidgetTester tester, {
  required LibraryItemAvailability availability,
  required bool canRetry,
  required ValueChanged<LibraryUnavailableBookDialogAction> onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return ElevatedButton(
            onPressed: () async {
              final action = await showLibraryUnavailableBookDialog(
                context,
                item: _catalogItem(),
                availability: availability,
                canRetry: canRetry,
              );
              onResult(action);
            },
            child: const Text('Open'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'shows the placeholder explanation and a Retry Download button when '
    'retry is supported',
    (tester) async {
      LibraryUnavailableBookDialogAction? result;
      await _openDialog(
        tester,
        availability: const LibraryItemAvailability.unavailable(
          category: LibraryItemUnavailableCategory.sourceHasNoReadableEdition,
        ),
        canRetry: true,
        onResult: (action) => result = action,
      );

      expect(find.text('No Readable Copy Available'), findsOneWidget);
      expect(find.textContaining('Christ Our Saviour'), findsOneWidget);
      expect(find.text('Retry Download'), findsOneWidget);

      await tester.tap(find.text('Retry Download'));
      await tester.pumpAndSettle();
      expect(result, LibraryUnavailableBookDialogAction.retryDownload);
    },
  );

  testWidgets('hides Retry Download when retry is not supported', (
    tester,
  ) async {
    LibraryUnavailableBookDialogAction? result;
    await _openDialog(
      tester,
      availability: const LibraryItemAvailability.unavailable(
        category: LibraryItemUnavailableCategory.downloadFailedValidation,
      ),
      canRetry: false,
      onResult: (action) => result = action,
    );

    expect(find.text('Download Needs to Be Retried'), findsOneWidget);
    expect(find.text('Retry Download'), findsNothing);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result, LibraryUnavailableBookDialogAction.dismissed);
  });
}
