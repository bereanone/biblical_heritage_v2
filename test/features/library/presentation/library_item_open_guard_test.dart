import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_item_open_guard.dart';

LibraryCatalogItem _catalogItem({
  String id = 'library_item_research_epubs_egw_egw_books_en_ic_epub',
  String title = 'The Impending Conflict',
  String? indexStatus = 'needs_attention',
  String? indexError =
      'Structurally invalid EPUB (missingOpf): container.xml references '
      '"OEBPS/content.opf" but no such entry exists.',
  String? sourceType = 'official_download',
  String? collectionName = 'EGW Books',
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: null,
    fileName: '$id.epub',
    fileHash: null,
    relativePath: 'ePubs/EGW/EGW_Books/$id.epub',
    fileFormat: 'epub',
    folderType: 'research',
    libraryRole: 'research',
    collectionName: collectionName,
    sourceSite: 'egwwritings.org',
    sourceUrl: null,
    sourceType: sourceType,
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: indexStatus,
    indexError: indexError,
    fileSize: 0,
    mimeType: 'application/epub+zip',
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

void main() {
  testWidgets(
    'a known-invalid EPUB is refused: the guard returns false and shows the '
    'unavailable dialog instead of letting the caller navigate',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final item = _catalogItem();
      bool? openable;
      unawaited(
        ensureLibraryItemOpenable(capturedContext, item).then((value) {
          openable = value;
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('No Readable Copy Available'), findsOneWidget);
      expect(
        find.textContaining('Table of Contents'),
        findsNothing,
        reason:
            'the guard must intercept before any placeholder book content '
            'can render',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(openable, isFalse);
    },
  );

  testWidgets(
    'a readable item is approved: the guard returns true without showing '
    'any dialog',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final item = _catalogItem(indexStatus: 'indexed', indexError: null);
      final openable = await ensureLibraryItemOpenable(capturedContext, item);
      await tester.pumpAndSettle();

      expect(openable, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    '32. an unavailable official-download item offers "Retry Download" '
    'through this same guard used by search/tag/commentary launch paths — '
    'not just the main shelf',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final item = _catalogItem(
        indexStatus: 'needs_attention',
        indexError:
            'Structurally invalid EPUB (corruptZip): truncated download.',
      );
      unawaited(ensureLibraryItemOpenable(capturedContext, item));
      await tester.pumpAndSettle();

      expect(
        find.text('Retry Download'),
        findsOneWidget,
        reason:
            'libraryItemSupportsRetryDownload(item) is true for this '
            'official_download/EGW Books item, so every launch path — not '
            'just the main shelf — must offer the same retry option.',
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'an item whose collection is not one the retry service knows how to '
    're-run never offers "Retry Download", from any launch path',
    (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      // A Pioneer EPUB import (not an official EGW download) has no
      // "re-download the collection" operation to retry.
      final item = _catalogItem(sourceType: 'pioneer_epub_import');
      unawaited(ensureLibraryItemOpenable(capturedContext, item));
      await tester.pumpAndSettle();

      expect(find.text('Retry Download'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );
}
