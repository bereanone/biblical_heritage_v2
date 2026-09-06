import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/library/data/library_catalog_service.dart';

LibraryCatalogItem _item({required String title, String? relativePath}) {
  return LibraryCatalogItem(
    id: 'test-id',
    title: title,
    author: null,
    fileName: 'book.epub',
    fileHash: null,
    relativePath: relativePath ?? 'ePubs/book.epub',
    fileFormat: 'epub',
    folderType: null,
    libraryRole: null,
    collectionName: null,
    sourceSite: null,
    sourceUrl: null,
    sourceType: null,
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: null,
    fileSize: null,
    mimeType: null,
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

void main() {
  group('LibraryCatalogItem.displayTitle strips catalog edition-code suffixes', () {
    test('strips a trailing [SL27]-style code', () {
      final item = _item(title: 'The National Sunday Law [SL27]');
      expect(item.displayTitle, 'The National Sunday Law');
      expect(item.title, 'The National Sunday Law [SL27]',
          reason: 'stored title must never be mutated by display formatting');
    });

    test('strips other known edition codes ([SL18], [RLL], [FP187])', () {
      expect(_item(title: 'The National Sunday Law [SL18]').displayTitle,
          'The National Sunday Law');
      expect(_item(title: 'The National Sunday Law [RLL]').displayTitle,
          'The National Sunday Law');
      expect(_item(title: 'Fundamental Principles [FP187]').displayTitle,
          'Fundamental Principles');
    });

    test('leaves titles with no bracket suffix untouched', () {
      expect(_item(title: 'The Great Controversy').displayTitle,
          'The Great Controversy');
    });

    test(
      'does not strip a bracket suffix containing lowercase letters or '
      'spaces, such as a Manuscript Releases volume range',
      () {
        // Manuscript Releases titles are hydrated to forms like
        // "Manuscript Releases, vol. 1 [Nos. 19-96]" (see
        // library_catalog_service_official_title_test.dart, which asserts
        // this survives end-to-end). The edition-code regex only matches
        // all-caps/digit codes with no spaces, so this bracket must survive
        // even when it is the raw stored title.
        final item = _item(title: 'Manuscript Releases, vol. 1 [Nos. 19-96]');
        expect(item.displayTitle, contains('[nos. 19 96]'));
      },
    );
  });
}
