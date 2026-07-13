import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_recent_items.dart';

LibraryCatalogItem _item({
  required String id,
  required String title,
  String? author,
  String? collectionName,
  DateTime? dateAdded,
  DateTime? lastOpened,
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: author,
    fileName: '$id.epub',
    fileHash: null,
    relativePath: 'Books/$id.epub',
    fileFormat: 'epub',
    folderType: null,
    libraryRole: null,
    collectionName: collectionName,
    sourceSite: null,
    sourceUrl: null,
    sourceType: null,
    coverPath: null,
    dateAdded: dateAdded,
    lastOpened: lastOpened,
    indexStatus: 'indexed',
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
  group('selectRecentLibraryItems', () {
    test('includes only items the user actually opened', () {
      final opened = _item(
        id: 'pioneer-1',
        title: 'Daniel and the Revelation',
        collectionName: 'Adventist Pioneer Library',
        dateAdded: DateTime.utc(2026, 6, 1),
        lastOpened: DateTime.utc(2026, 7, 1),
      );
      final onlyIndexed = _item(
        id: 'ms-1',
        title: 'Manuscript Releases Volume 1',
        collectionName: 'EGW Manuscripts',
        dateAdded: DateTime.utc(2026, 7, 7),
      );

      final recents = selectRecentLibraryItems([onlyIndexed, opened]);

      expect(recents.map((item) => item.id), ['pioneer-1']);
    });

    test('freshly indexed collection does not flood Recents via dateAdded', () {
      final now = DateTime.utc(2026, 7, 8);
      final manuscripts = List.generate(
        20,
        (i) => _item(
          id: 'ms-$i',
          title: 'Manuscript Releases Volume ${i + 1}',
          collectionName: 'EGW Manuscripts',
          dateAdded: now,
        ),
      );
      final pioneerBook = _item(
        id: 'pioneer-1',
        title: 'The Great Second Advent Movement',
        collectionName: 'Adventist Pioneer Library',
        dateAdded: DateTime.utc(2026, 5, 1),
        lastOpened: DateTime.utc(2026, 7, 6),
      );

      final recents = selectRecentLibraryItems([...manuscripts, pioneerBook]);

      expect(recents.map((item) => item.id), ['pioneer-1']);
    });

    test('refresh/index that only sets dateAdded yields empty Recents', () {
      final items = [
        _item(id: 'a', title: 'Book A', dateAdded: DateTime.utc(2026, 7, 8)),
        _item(id: 'b', title: 'Book B', dateAdded: DateTime.utc(2026, 7, 8)),
      ];

      expect(selectRecentLibraryItems(items), isEmpty);
    });

    test('opened Pioneer book stays recent alongside other collections', () {
      final pioneer = _item(
        id: 'pioneer-1',
        title: 'Life Incidents',
        collectionName: 'Adventist Pioneer Library',
        lastOpened: DateTime.utc(2026, 7, 5),
      );
      final manuscript = _item(
        id: 'ms-1',
        title: 'Manuscript Releases Volume 1',
        collectionName: 'EGW Manuscripts',
        lastOpened: DateTime.utc(2026, 7, 2),
      );
      final unopened = _item(
        id: 'ms-2',
        title: 'Manuscript Releases Volume 2',
        collectionName: 'EGW Manuscripts',
        dateAdded: DateTime.utc(2026, 7, 8),
      );

      final recents = selectRecentLibraryItems([manuscript, unopened, pioneer]);

      expect(recents.map((item) => item.id), ['pioneer-1', 'ms-1']);
    });

    test('returns the original item instances with metadata untouched', () {
      final opened = _item(
        id: 'pioneer-1',
        title: 'Daniel and the Revelation',
        lastOpened: DateTime.utc(2026, 7, 5),
      );

      final recents = selectRecentLibraryItems([opened]);

      expect(recents, hasLength(1));
      expect(identical(recents.single, opened), isTrue);
      expect(recents.single.coverPath, opened.coverPath);
    });

    test('orders by actual open time, most recent first', () {
      final first = _item(
        id: 'a',
        title: 'Alpha',
        dateAdded: DateTime.utc(2026, 7, 8),
        lastOpened: DateTime.utc(2026, 7, 1),
      );
      final second = _item(
        id: 'b',
        title: 'Beta',
        dateAdded: DateTime.utc(2026, 1, 1),
        lastOpened: DateTime.utc(2026, 7, 7),
      );
      final third = _item(
        id: 'c',
        title: 'Gamma',
        lastOpened: DateTime.utc(2026, 7, 4),
      );

      final recents = selectRecentLibraryItems([first, second, third]);

      expect(recents.map((item) => item.id), ['b', 'c', 'a']);
    });

    test('search query narrows Recents without adding unopened items', () {
      final opened = _item(
        id: 'pioneer-1',
        title: 'Daniel and the Revelation',
        author: 'Uriah Smith',
        lastOpened: DateTime.utc(2026, 7, 5),
      );
      final otherOpened = _item(
        id: 'egw-1',
        title: 'Steps to Christ',
        author: 'Ellen G. White',
        lastOpened: DateTime.utc(2026, 7, 6),
      );
      final unopenedMatch = _item(
        id: 'ms-1',
        title: 'Revelation Manuscripts',
        dateAdded: DateTime.utc(2026, 7, 8),
      );

      final recents = selectRecentLibraryItems([
        opened,
        otherOpened,
        unopenedMatch,
      ], searchQuery: 'Revelation');

      expect(recents.map((item) => item.id), ['pioneer-1']);
    });
  });
}
