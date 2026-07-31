import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_item_availability.dart';

LibraryCatalogItem _catalogItem({
  String id = 'item-1',
  String title = 'Christ Our Saviour',
  String? indexStatus = 'indexed',
  String? indexError,
  String? sourceType = 'official_download',
  String? collectionName = 'EGW Books',
  String fileFormat = 'epub',
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: null,
    fileName: '$id.epub',
    fileHash: null,
    relativePath: 'ePubs/EGW/EGW_Books/$id.epub',
    fileFormat: fileFormat,
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
  group('libraryItemAvailability', () {
    test('indexed items are available', () {
      final item = _catalogItem(indexStatus: 'indexed');
      final availability = libraryItemAvailability(item);
      expect(availability.isAvailable, isTrue);
      expect(availability.category, isNull);
    });

    test('metadata_only and indexed_empty items are still available', () {
      for (final status in <String>[
        'metadata_only',
        'indexed_empty',
        'pending',
      ]) {
        final item = _catalogItem(indexStatus: status);
        expect(
          libraryItemAvailability(item).isAvailable,
          isTrue,
          reason: 'index_status "$status" should still open in the reader',
        );
      }
    });

    test('needs_attention with a placeholder rejection reason is unavailable '
        'with sourceHasNoReadableEdition', () {
      final item = _catalogItem(
        indexStatus: 'needs_attention',
        indexError:
            'Structurally invalid EPUB (missingOpf): container.xml '
            'references "OEBPS/content.opf" but no such entry exists.',
      );
      final availability = libraryItemAvailability(item);
      expect(availability.isAvailable, isFalse);
      expect(
        availability.category,
        LibraryItemUnavailableCategory.sourceHasNoReadableEdition,
      );
    });

    test('needs_attention with a corruption-style rejection reason is '
        'unavailable with downloadFailedValidation', () {
      final item = _catalogItem(
        indexStatus: 'needs_attention',
        indexError:
            'Structurally invalid EPUB (corruptZip): Zip could not be '
            'decoded (truncated/corrupt download).',
      );
      final availability = libraryItemAvailability(item);
      expect(availability.isAvailable, isFalse);
      expect(
        availability.category,
        LibraryItemUnavailableCategory.downloadFailedValidation,
      );
    });

    test(
      'needs_attention with an unparseable reason falls back to unknown',
      () {
        final item = _catalogItem(
          indexStatus: 'needs_attention',
          indexError: 'Legacy failure text.',
        );
        final availability = libraryItemAvailability(item);
        expect(availability.isAvailable, isFalse);
        expect(availability.category, LibraryItemUnavailableCategory.unknown);
      },
    );
  });

  group('libraryItemSupportsRetryDownload', () {
    test('true for an official download from a known managed collection', () {
      final item = _catalogItem(
        sourceType: 'official_download',
        collectionName: 'EGW Books',
      );
      expect(libraryItemSupportsRetryDownload(item), isTrue);
    });

    test('false for a non-official-download source type', () {
      final item = _catalogItem(
        sourceType: 'egw_text_capture',
        collectionName: 'EGW Books',
      );
      expect(libraryItemSupportsRetryDownload(item), isFalse);
    });

    test('false for an unrecognized collection name', () {
      final item = _catalogItem(
        sourceType: 'official_download',
        collectionName: 'Some Unmapped Collection',
      );
      expect(libraryItemSupportsRetryDownload(item), isFalse);
    });
  });
}
