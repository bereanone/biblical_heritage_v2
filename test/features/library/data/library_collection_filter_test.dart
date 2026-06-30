import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';

LibraryCatalogItem _item({
  required String title,
  required String collectionName,
  required String relativePath,
  String fileFormat = 'epub',
}) {
  return LibraryCatalogItem(
    id: '${title}_id',
    title: title,
    author: null,
    fileName: relativePath.split('/').last,
    fileHash: null,
    relativePath: relativePath,
    fileFormat: fileFormat,
    folderType: 'research',
    libraryRole: 'user_added',
    collectionName: collectionName,
    sourceSite: null,
    sourceUrl: null,
    sourceType: 'official_download',
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: 'indexed',
    fileSize: 0,
    mimeType: fileFormat == 'pdf' ? 'application/pdf' : 'application/epub+zip',
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

void main() {
  test('derives EGW collection labels from metadata and paths', () {
    final item = _item(
      title: 'The Story of Our Health Message',
      collectionName: 'EGW_Misc_Collections',
      relativePath: 'ePubs/Research/EGW_Misc_Collections/en_SHM-apx.epub',
    );

    expect(item.collectionGroupKey, 'egw_misc_collections');
    expect(item.collectionGroupLabel, 'EGW Misc Collections');
    expect(
      libraryItemMatchesCollectionFilter(item, 'egw_misc_collections'),
      isTrue,
    );
    expect(libraryItemMatchesCollectionFilter(item, 'egw_books'), isFalse);
  });

  test('builds installed collection filters in EGW order', () {
    final options = buildLibraryCollectionFilterOptions([
      _item(
        title: 'Christ Object Lessons',
        collectionName: 'EGW_Books',
        relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
      ),
      _item(
        title: 'Conflict and Courage',
        collectionName: 'EGW_Devotionals',
        relativePath: 'ePubs/Research/EGW_Devotionals/en_CC.epub',
      ),
      _item(
        title: 'The Story of Our Health Message',
        collectionName: 'EGW_Misc_Collections',
        relativePath: 'ePubs/Research/EGW_Misc_Collections/en_SHM-apx.epub',
      ),
    ]);

    expect(options.map((option) => option.label).toList(), <String>[
      'All Collections',
      'EGW Books',
      'EGW Devotionals',
      'EGW Misc Collections',
    ]);
  });

  test('classifies Pioneer rows as Adventist Pioneer Library', () {
    final item = _item(
      title: 'Home Here, and Home in Heaven; With Other Poems',
      collectionName: 'Pioneer Authors',
      relativePath: 'ePubs/Research/Pioneer Authors/annie_smith/HHAH.html',
    );

    expect(item.collectionGroupKey, 'adventist_pioneer_library');
    expect(item.collectionGroupLabel, 'Adventist Pioneer Library');
    expect(
      libraryItemMatchesCollectionFilter(item, 'adventist_pioneer_library'),
      isTrue,
    );
    expect(libraryItemMatchesCollectionFilter(item, 'egw_books'), isFalse);
  });

  test('includes Adventist Pioneer Library in collection options', () {
    final options = buildLibraryCollectionFilterOptions([
      _item(
        title: 'Home Here, and Home in Heaven; With Other Poems',
        collectionName: 'Pioneer Authors',
        relativePath: 'ePubs/Research/Pioneer Authors/annie_smith/HHAH.html',
      ),
      _item(
        title: 'Christ Object Lessons',
        collectionName: 'EGW_Books',
        relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
      ),
    ]);

    expect(options.map((option) => option.label).toList(), <String>[
      'All Collections',
      'EGW Books',
      'Adventist Pioneer Library',
    ]);
  });
}
