import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

Future<void> _copyDatabaseBundle({
  required Directory sourceDir,
  required Directory destinationDir,
}) async {
  await destinationDir.create(recursive: true);
  for (final name in const [
    'eLibrary.db',
    'eLibrary.db-wal',
    'eLibrary.db-shm',
    'user.db',
    'user.db-wal',
    'user.db-shm',
  ]) {
    final sourceFile = File(p.join(sourceDir.path, name));
    if (!await sourceFile.exists()) continue;
    await sourceFile.copy(p.join(destinationDir.path, name));
  }
}

Future<Map<String, FileStat>> _snapshotUserDatabaseFiles(
  Directory databaseDir,
) async {
  final snapshot = <String, FileStat>{};
  for (final name in const ['user.db', 'user.db-wal', 'user.db-shm']) {
    final file = File(p.join(databaseDir.path, name));
    if (await file.exists()) {
      snapshot[name] = file.statSync();
    }
  }
  return snapshot;
}

void _expectUserDatabaseFilesUnchanged(
  Map<String, FileStat> before,
  Directory databaseDir,
) {
  for (final entry in before.entries) {
    final file = File(p.join(databaseDir.path, entry.key));
    expect(
      file.existsSync(),
      isTrue,
      reason: '${entry.key} should still exist',
    );
    final after = file.statSync();
    expect(after.size, entry.value.size, reason: '${entry.key} size changed');
    expect(
      after.modified,
      entry.value.modified,
      reason: '${entry.key} modified timestamp changed',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory databaseDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'library_catalog_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'library_catalog_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'library_catalog_root_',
    );
    databaseDir = Directory(p.join(libraryRootDir.path, 'Databases'));

    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await _copyDatabaseBundle(
      sourceDir: Directory(p.join(Directory.current.path, 'test', 'Databases')),
      destinationDir: databaseDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  test(
    'catalog item exposes generated asset thumbnail and keeps fallback null',
    () {
      final withCover = LibraryCatalogItem.fromRow(const <String, Object?>{
        'id': 'library_item_research_pioneer_at_jones_lessons_on_faith',
        'title': 'Lessons on Faith',
        'file_name': 'capture.html',
        'relative_path': 'assets/scans/LOF_ATJ/capture.html',
        'source_type': 'egw_html_capture',
        'cover_path': 'assets/library_covers/thumbs/LOF_ATJ.png',
        'navigation_count': 22,
      });
      expect(withCover.coverPath, 'assets/library_covers/thumbs/LOF_ATJ.png');

      final missingFileCover =
          LibraryCatalogItem.fromRow(const <String, Object?>{
            'id': 'missing_cover',
            'title': 'Missing Cover',
            'file_name': 'capture.html',
            'relative_path': 'TextCaptures/missing.html',
            'cover_path': '/definitely/missing/cover.png',
            'navigation_count': 0,
          });
      expect(missingFileCover.coverPath, isNull);
    },
  );

  test('classifies Pioneer rows and exposes the new collection filter', () async {
    final items = await LibraryCatalogService.instance.loadItems();
    final pioneerItems = items
        .where((item) => item.collectionGroupKey == 'adventist_pioneer_library')
        .toList(growable: false);

    expect(pioneerItems.length, greaterThanOrEqualTo(3));
    expect(
      pioneerItems.map((item) => item.displayTitle).toSet(),
      containsAll(<String>[
        'Home Here, and Home in Heaven; With Other Poems',
        'Christ Our Righteousness',
        'Herald of the Bridegroom',
      ]),
    );
    expect(
      pioneerItems.map((item) => item.displayAuthor).toSet(),
      containsAll(<String>['Annie Smith', 'A. G. Daniells', 'Apollos Hale']),
    );

    final darItems = pioneerItems
        .where(
          (item) =>
              item.displayTitle == 'Daniel and the Revelation' &&
              item.displayAuthor == 'Uriah Smith',
        )
        .toList(growable: false);
    expect(darItems, hasLength(1));
    final dar = darItems.single;
    expect(
      dar.id,
      'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation_egw_copied_range',
    );
    expect(dar.displayAuthor, 'Uriah Smith');
    expect(dar.fileFormat, 'html');
    expect(dar.isEpub, isTrue);
    expect(dar.collectionName, 'Adventist Pioneer Library');
    expect(dar.sourceType, 'egw_copied_range');
    expect(dar.sourceSite, 'egwwritings.org');
    expect(dar.relativePath, contains('copied_range'));
    expect(
      libraryCatalogSearchTextForItem(dar),
      contains(compactLibrarySearchText('Daniel')),
    );

    final options = buildLibraryCollectionFilterOptions(items);
    expect(
      options.map((option) => option.label).toList(),
      contains('Adventist Pioneer Library'),
    );

    expect(
      libraryItemMatchesCollectionFilter(
        pioneerItems.first,
        'adventist_pioneer_library',
      ),
      isTrue,
    );
    expect(
      libraryItemMatchesCollectionFilter(pioneerItems.first, 'all'),
      isTrue,
    );

    final egwCollectionOptions = buildLibraryCollectionFilterOptions(
      items.where((item) => item.collectionGroupKey.startsWith('egw_')),
    );
    expect(
      egwCollectionOptions.map((option) => option.label).toList(),
      isNot(contains('Adventist Pioneer Library')),
    );
  });

  test(
    'searches and opens Pioneer text blocks without touching user.db',
    () async {
      final beforeUserDb = await _snapshotUserDatabaseFiles(databaseDir);

      final items = await LibraryCatalogService.instance.loadItems();
      final annie = items.firstWhere(
        (item) =>
            item.displayTitle ==
            'Home Here, and Home in Heaven; With Other Poems',
      );
      expect(annie.displayAuthor, 'Annie Smith');
      expect(annie.coverPath, isNull);

      const searchPhrase = 'BY ANNIE R. SMITH ROCHESTER';
      final results = await LibraryCatalogService.instance.searchContent(
        query: searchPhrase,
        collectionFilter: 'adventist_pioneer_library',
      );
      expect(results, isNotEmpty);

      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: searchPhrase,
          collectionFilter: 'adventist_pioneer_library',
        ),
        greaterThanOrEqualTo(1),
      );
      expect(
        await LibraryCatalogService.instance.countIndexedSearchableItems(
          collectionFilter: 'adventist_pioneer_library',
        ),
        greaterThanOrEqualTo(3),
      );
      expect(
        await LibraryCatalogService.instance.countCatalogItemsInScope(
          collectionFilter: 'adventist_pioneer_library',
        ),
        greaterThanOrEqualTo(3),
      );

      final egwResults = await LibraryCatalogService.instance.searchContent(
        query: searchPhrase,
        collectionFilter: 'egw_books',
      );
      expect(egwResults.where((result) => result.item.id == annie.id), isEmpty);

      final annieResults = results
          .where((result) => result.item.id == annie.id)
          .toList(growable: false);
      expect(annieResults, isNotEmpty);
      expect(annieResults.first.item.displayAuthor, 'Annie Smith');
      expect(annieResults.first.snippet, contains(searchPhrase));

      final sections = await CommentaryResearchLibraryService.instance
          .loadBookSections(
            filePath: p.join(libraryRootDir.path, annie.relativePath),
            libraryItemId: annie.id,
          );
      expect(sections, isNotEmpty);
      expect(
        sections.expand((section) => section.paragraphs).join(' '),
        contains('I thanked my God'),
      );

      final navigationItems = await LibraryCatalogService.instance
          .loadNavigationItems(annie.id);
      expect(navigationItems, isNotEmpty);

      _expectUserDatabaseFilesUnchanged(beforeUserDb, databaseDir);
    },
  );
}
