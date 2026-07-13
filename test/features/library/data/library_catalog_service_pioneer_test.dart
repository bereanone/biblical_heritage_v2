import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_navigation_tree.dart';
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

  test('WOR editions have normalized display metadata and distinct labels', () {
    LibraryCatalogItem item(String id, String title, String author) =>
        LibraryCatalogItem.fromRow(<String, Object?>{
          'id': id,
          'title': title,
          'author': author,
          'file_name': 'capture.html',
          'relative_path': 'TextCaptures/WOR/capture.html',
        });

    final capture = item(
      'library_item_research_pioneer_e_j_waggoner_WOR',
      'Waggoner on Romans',
      'E. J. Waggoner',
    );
    final official = item(
      'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW',
      'WOR',
      'Ellet Joseph Waggoner',
    );

    expect(capture.displayTitle, 'Waggoner on Romans');
    expect(official.displayTitle, 'Waggoner on Romans');
    expect(capture.displayAuthor, 'E. J. Waggoner');
    expect(official.displayAuthor, 'E. J. Waggoner');
    expect(capture.editionLabel, 'CaptureClipper edition');
    expect(official.editionLabel, 'Official EPUB edition');
    expect(capture.id, isNot(official.id));
  });

  test(
    'canonical selection keeps only the objectively stronger WOR edition',
    () {
      LibraryCatalogItem edition({
        required String id,
        required String workId,
        required int textLength,
        required int blocks,
        required int navigation,
      }) => LibraryCatalogItem.fromRow(<String, Object?>{
        'id': id,
        'title': 'WOR',
        'author': 'E. J. Waggoner',
        'file_name': '$id.html',
        'relative_path': 'captures/$id.html',
        'source_work_id': workId,
        'index_status': 'indexed',
        'extracted_text_length': textLength,
        'readable_block_count': blocks,
        'navigation_count': navigation,
        'navigation_max_depth': 3,
      });
      final capture = edition(
        id: 'library_item_research_pioneer_e_j_waggoner_WOR',
        workId: 'WOR',
        textLength: 600000,
        blocks: 1400,
        navigation: 338,
      );
      final official = edition(
        id: 'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW',
        workId: 'WOR_EJW',
        textLength: 620000,
        blocks: 1420,
        navigation: 340,
      );

      final visible = selectPreferredLibraryEditions([capture, official]);
      expect(visible, hasLength(1));
      expect(visible.single.id, official.id);
      expect(canonicalLibraryWorkId(capture), 'WOR');
      expect(canonicalLibraryWorkId(official), 'WOR');
    },
  );

  test('items without stable work identity are never grouped by title', () {
    LibraryCatalogItem item(String id) =>
        LibraryCatalogItem.fromRow(<String, Object?>{
          'id': id,
          'title': 'Shared title',
          'author': 'Shared author',
          'file_name': '$id.epub',
          'relative_path': 'epubs/$id.epub',
        });
    expect(
      selectPreferredLibraryEditions([item('a'), item('b')]),
      hasLength(2),
    );
  });

  test('explicit catalog aliases group only confirmed identical editions', () {
    LibraryCatalogItem item(String id) =>
        LibraryCatalogItem.fromRow(<String, Object?>{
          'id': id,
          'title': 'source title',
          'file_name': '$id.html',
          'relative_path': 'library/$id.html',
        });

    expect(
      canonicalLibraryWorkId(
        item('library_item_research_pioneer_s_n_haskell_SSP_SNH'),
      ),
      'SSP',
    );
    expect(
      canonicalLibraryWorkId(
        item('library_item_research_pioneer_stephen_nelson_haskell_SSP'),
      ),
      'SSP',
    );
    expect(
      canonicalLibraryWorkId(
        item('library_item_research_epubs_egw_egw_pamphlets_en_spta02b_epub'),
      ),
      'EGW:PAMPHLET:SPTA02B',
    );
    expect(
      canonicalLibraryWorkId(
        item('library_item_research_epubs_egw_egw_pamphlets_en_ph133_epub'),
      ),
      'EGW:PAMPHLET:SPTA02B',
    );
  });

  test(
    'preferred edition diagnostics prefer official EPUB when quality is tied',
    () {
      LibraryCatalogItem edition({
        required String id,
        required String sourceType,
        required String sourceWorkId,
      }) {
        return LibraryCatalogItem.fromRow(<String, Object?>{
          'id': id,
          'title': 'Waggoner on Romans',
          'author': 'E. J. Waggoner',
          'file_name': '$id.epub',
          'relative_path': 'epubs/$id.epub',
          'source_type': sourceType,
          'source_work_id': sourceWorkId,
          'index_status': 'indexed',
          'extracted_text_length': 5000,
          'readable_block_count': 20,
          'navigation_count': 12,
          'navigation_max_depth': 4,
        });
      }

      final capture = edition(
        id: 'library_item_research_pioneer_e_j_waggoner_WOR',
        sourceType: 'egw_html_capture',
        sourceWorkId: 'WOR',
      );
      final official = edition(
        id: 'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW',
        sourceType: 'official_download',
        sourceWorkId: 'WOR_EJW',
      );

      final decision = describePreferredLibraryEdition([capture, official]);
      expect(decision.preferredEdition.id, official.id);
      expect(decision.workId, 'WOR');
      expect(decision.reason, contains('preferred source tier'));
      expect(selectPreferredLibraryEditions([capture, official]), hasLength(1));
    },
  );

  test(
    'healthier CaptureClipper edition wins when the EPUB is structurally weak',
    () {
      LibraryCatalogItem edition({
        required String id,
        required String sourceType,
        required String sourceWorkId,
        required int textLength,
        required int blocks,
        required int navigation,
        required String? indexError,
      }) {
        return LibraryCatalogItem.fromRow(<String, Object?>{
          'id': id,
          'title': 'Waggoner on Romans',
          'author': 'E. J. Waggoner',
          'file_name': '$id.epub',
          'relative_path': 'epubs/$id.epub',
          'source_type': sourceType,
          'source_work_id': sourceWorkId,
          'index_status': indexError == null ? 'indexed' : 'needs_attention',
          'index_error': indexError,
          'extracted_text_length': textLength,
          'readable_block_count': blocks,
          'navigation_count': navigation,
          'navigation_max_depth': 3,
        });
      }

      final capture = edition(
        id: 'library_item_research_pioneer_e_j_waggoner_WOR',
        sourceType: 'egw_html_capture',
        sourceWorkId: 'WOR',
        textLength: 650000,
        blocks: 1450,
        navigation: 340,
        indexError: null,
      );
      final brokenOfficial = edition(
        id: 'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW',
        sourceType: 'official_download',
        sourceWorkId: 'WOR_EJW',
        textLength: 12000,
        blocks: 9,
        navigation: 4,
        indexError: 'missing spine items',
      );

      final decision = describePreferredLibraryEdition([
        capture,
        brokenOfficial,
      ]);
      expect(decision.preferredEdition.id, capture.id);
      expect(decision.reason, contains('higher quality score'));
      expect(
        selectPreferredLibraryEditions([capture, brokenOfficial]),
        hasLength(1),
      );
    },
  );

  test('package-backed HTML capture wins an equivalent legacy capture', () {
    LibraryCatalogItem capture(String id, String? packageId) {
      return LibraryCatalogItem.fromRow(<String, Object?>{
        'id': id,
        'title': 'Waggoner on Romans',
        'author': 'E. J. Waggoner',
        'file_name': 'capture.html',
        'relative_path': 'TextCaptures/$id/capture.html',
        'source_type': 'egw_html_capture',
        'source_work_id': id == 'current' ? 'WOR' : 'WOR_EJW',
        'source_package_id': packageId,
        'index_status': 'indexed',
        'extracted_text_length': 604443,
        'readable_block_count': 1400,
        'navigation_count': 338,
      });
    }

    final current = capture('current', 'captureclipper:WOR');
    final legacy = capture('legacy', null);
    final decision = describePreferredLibraryEdition([legacy, current]);

    expect(decision.preferredEdition, same(current));
    expect(decision.reason, contains('deterministic package-id tie-break'));
  });

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

  test(
    'repairs a missing Pioneer capture cover from local folder metadata',
    () async {
      final captureDir = Directory(
        p.join(libraryRootDir.path, 'assets', 'scans', 'LOF_ATJ'),
      );
      await captureDir.create(recursive: true);
      await File(
        p.join(captureDir.path, 'capture.html'),
      ).writeAsString('<html><body><p>cover repair fixture</p></body></html>');
      await File(
        p.join(captureDir.path, 'metadata.json'),
      ).writeAsString('{"cover_image":"cover.jpg"}');
      await File(p.join(captureDir.path, 'cover.jpg')).writeAsString('cover');

      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        {'cover_path': null},
        where: 'id = ?',
        whereArgs: ['lessons_on_faith'],
      );

      final items = await LibraryCatalogService.instance.loadItems();
      final lessons = items.firstWhere((item) => item.id == 'lessons_on_faith');
      final expectedCoverPath = p.join(
        libraryRootDir.path,
        'Graphics',
        'eLibraryCovers',
        'library_item_077a15a4815016460c22_faith.jpg',
      );
      expect(lessons.coverPath, expectedCoverPath);
      expect(File(expectedCoverPath).existsSync(), isTrue);

      final repairedRow = await db.query(
        'library_items',
        columns: const ['cover_path'],
        where: 'id = ?',
        whereArgs: ['lessons_on_faith'],
      );
      expect(repairedRow.single['cover_path'], expectedCoverPath);
    },
  );

  test(
    'repairs a stale non-EPUB cover path from the eLibraryCovers mirror',
    () async {
      // Simulates an iOS container move: the cached cover file survives
      // under the current root, but the stored absolute path is dead.
      final coverDir = Directory(
        p.join(libraryRootDir.path, 'Graphics', 'eLibraryCovers'),
      );
      await coverDir.create(recursive: true);
      final mirrorCoverPath = p.join(coverDir.path, 'lessons_on_faith.png');
      await File(mirrorCoverPath).writeAsString('cover bytes');

      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        {
          'cover_path':
              '/var/mobile/Containers/Data/Application/DEAD-UUID/Documents/'
              'BiblicalHeritage/v2/Graphics/eLibraryCovers/lessons_on_faith.png',
        },
        where: 'id = ?',
        whereArgs: ['lessons_on_faith'],
      );

      final items = await LibraryCatalogService.instance.loadItems();
      final lessons = items.firstWhere((item) => item.id == 'lessons_on_faith');
      expect(lessons.coverPath, mirrorCoverPath);

      final repairedRow = await db.query(
        'library_items',
        columns: const ['cover_path'],
        where: 'id = ?',
        whereArgs: ['lessons_on_faith'],
      );
      expect(repairedRow.single['cover_path'], mirrorCoverPath);
    },
  );

  test(
    'classifies Pioneer rows and exposes the new collection filter',
    () async {
      final items = await LibraryCatalogService.instance.loadItems();
      final pioneerItems = items
          .where(
            (item) => item.collectionGroupKey == 'adventist_pioneer_library',
          )
          .toList(growable: false);

      expect(pioneerItems.length, greaterThanOrEqualTo(2));
      expect(
        pioneerItems.map((item) => item.displayTitle).toSet(),
        containsAll(<String>['Daniel and the Revelation', 'Lessons on Faith']),
      );
      expect(
        pioneerItems.map((item) => item.displayAuthor).toSet(),
        containsAll(<String>['Uriah Smith', 'A. T. Jones']),
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
      expect(dar.id, 'DAR_US');
      expect(dar.displayAuthor, 'Uriah Smith');
      expect(dar.fileFormat, 'html');
      expect(dar.isEpub, isTrue);
      expect(dar.collectionName, 'Pioneer Authors');
      expect(dar.sourceType, 'egw_html_capture');
      expect(dar.sourceSite, 'egwwritings.org');
      expect(dar.relativePath, 'assets/scans/DAR/capture.html');
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
    },
  );

  test('real WOR navigation rows map to their own readable sections and keep '
      'empty Preface hidden', () async {
    final productionRoot = await Directory.systemTemp.createTemp(
      'library_catalog_wor_root_',
    );
    final productionDatabases = Directory(
      p.join(productionRoot.path, 'Databases'),
    );
    await _copyDatabaseBundle(
      sourceDir: Directory(
        p.join(Directory.current.path, 'assets', 'databases'),
      ),
      destinationDir: productionDatabases,
    );
    final previousRoot = libraryRootDir.path;
    try {
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(
        path: productionRoot.path,
      );

      final wor =
          await LibraryCatalogService.instance.loadItemById(
            'library_item_research_pioneer_e_j_waggoner_WOR',
          ) ??
          await LibraryCatalogService.instance.loadItemById(
            'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW',
          );
      if (wor == null) {
        return;
      }
      final worItem = wor;
      final sections = await CommentaryResearchLibraryService.instance
          .loadBookSections(
            filePath: p.join(productionRoot.path, worItem.relativePath),
            libraryItemId: worItem.id,
          );
      final navigationItems = await LibraryCatalogService.instance
          .loadNavigationItems(worItem.id);
      final tree = buildLibraryNavigationTree(navigationItems);

      final prefaceMatches = navigationItems
          .where((item) => item.label.trim().toUpperCase() == 'PREFACE.')
          .toList(growable: false);
      if (prefaceMatches.isNotEmpty) {
        expect(
          libraryReaderShouldHideEmptyPrefaceContentsEntry(
            navItem: prefaceMatches.first,
            sections: sections,
          ),
          isTrue,
        );
      }

      final chapter1 = navigationItems.firstWhere(
        (item) => item.label.trim().toUpperCase() == 'CHAPTER 1.',
      );
      expect(
        libraryReaderFirstReadableDescendant(
          navItem: chapter1,
          tree: tree,
          sections: sections,
        )?.readableSection.entryName,
        'captured/wor/chapter_05_october_17_1895.html',
      );

      final checks = <({String href, LibraryCatalogNavigationItem nav})>[
        (
          href: 'captured/wor/chapter_05_october_17_1895.html',
          nav: navigationItems.firstWhere(
            (item) =>
                item.label.trim().toUpperCase() == 'OCTOBER 17, 1895.' &&
                item.href?.contains('chapter_05_october_17_1895') == true,
          ),
        ),
        (
          href: 'captured/wor/chapter_06_the_salutation_romans_1_1_17.html',
          nav: navigationItems.firstWhere(
            (item) =>
                item.label.trim().toUpperCase() ==
                    'THE SALUTATION—ROMANS 1:1-17.' &&
                item.href?.contains(
                      'chapter_06_the_salutation_romans_1_1_17',
                    ) ==
                    true,
          ),
        ),
        (
          href: 'captured/wor/chapter_07_questioning_the_text.html',
          nav: navigationItems.firstWhere(
            (item) =>
                item.label.trim().toUpperCase() == 'QUESTIONING THE TEXT.' &&
                item.href?.contains('chapter_07_questioning_the_text') == true,
          ),
        ),
        (
          href: 'captured/wor/chapter_08_october_17_1895.html',
          nav: navigationItems.firstWhere(
            (item) =>
                item.label.trim().toUpperCase() == 'OCTOBER 17, 1895.' &&
                item.href?.contains('chapter_08_october_17_1895') == true,
          ),
        ),
        (
          href: 'captured/wor/chapter_11_debtor_to_all.html',
          nav: navigationItems.firstWhere(
            (item) => item.label.trim().toUpperCase() == 'DEBTOR TO ALL.',
          ),
        ),
        (
          href: 'captured/wor/chapter_12_october_24_1895.html',
          nav: navigationItems.firstWhere(
            (item) =>
                item.label.trim().toUpperCase() == 'OCTOBER 24, 1895.' &&
                item.href?.contains('chapter_12_october_24_1895') == true,
          ),
        ),
      ];

      for (final check in checks) {
        final index = sections.indexWhere(
          (section) =>
              p.basename(section.entryName).toLowerCase() ==
              p.basename(check.href).toLowerCase(),
        );
        if (index < 0) {
          continue;
        }
        expect(sections[index].blocks, isNotEmpty);
        expect(
          libraryReaderContentsTargetKeyForNavigationItem(
            navItem: check.nav,
            sections: sections,
          ),
          isNotNull,
        );
        expect(
          libraryReaderNavigationItemTargetsSectionStart(
            navItem: check.nav,
            sections: sections,
          ),
          isTrue,
        );
      }

      expect(
        sections
            .firstWhere(
              (section) =>
                  p.basename(section.entryName).toLowerCase() ==
                  'chapter_05_october_17_1895.html',
            )
            .blocks
            .first
            .text,
        startsWith('Under this heading it is proposed to conduct'),
      );
      expect(
        sections
            .firstWhere(
              (section) =>
                  p.basename(section.entryName).toLowerCase() ==
                  'chapter_11_debtor_to_all.html',
            )
            .blocks
            .first
            .text,
        startsWith('I am debtor both to the Greeks, and to the barbarians'),
      );
      expect(
        sections
            .firstWhere(
              (section) =>
                  p.basename(section.entryName).toLowerCase() ==
                  'chapter_12_october_24_1895.html',
            )
            .blocks
            .first
            .text,
        startsWith('The first seven verses of the first chapter of Romans'),
      );
    } finally {
      LibraryRootService.instance.invalidateCachedSelection();
      await LibraryRootService.instance.setLibraryRoot(path: previousRoot);
      await productionRoot.delete(recursive: true);
    }
  });

  test(
    'searches and opens Pioneer text blocks without touching user.db',
    () async {
      final beforeUserDb = await _snapshotUserDatabaseFiles(databaseDir);

      final items = await LibraryCatalogService.instance.loadItems();
      final lessons = items.firstWhere(
        (item) =>
            item.displayTitle == 'Lessons on Faith' &&
            item.displayAuthor == 'A. T. Jones',
      );
      expect(lessons.coverPath, 'assets/library_covers/thumbs/LOF_ATJ.png');

      const searchPhrase = 'Without faith it is impossible to please him.';
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
        greaterThanOrEqualTo(2),
      );
      expect(
        await LibraryCatalogService.instance.countCatalogItemsInScope(
          collectionFilter: 'adventist_pioneer_library',
        ),
        greaterThanOrEqualTo(2),
      );

      final egwResults = await LibraryCatalogService.instance.searchContent(
        query: searchPhrase,
        collectionFilter: 'egw_books',
      );
      expect(
        egwResults.where((result) => result.item.id == lessons.id),
        isEmpty,
      );

      final lessonsResults = results
          .where((result) => result.item.id == lessons.id)
          .toList(growable: false);
      expect(lessonsResults, isNotEmpty);
      expect(lessonsResults.first.item.displayAuthor, 'A. T. Jones');
      expect(
        lessonsResults.first.snippet.toLowerCase(),
        contains('without faith it is impossible to please him'),
      );

      final sections = await CommentaryResearchLibraryService.instance
          .loadBookSections(
            filePath: p.join(libraryRootDir.path, lessons.relativePath),
            libraryItemId: lessons.id,
          );
      expect(sections, isNotEmpty);
      expect(
        sections.expand((section) => section.paragraphs).join(' '),
        contains('without faith it is impossible to please him'),
      );

      final navigationItems = await LibraryCatalogService.instance
          .loadNavigationItems(lessons.id);
      expect(navigationItems, isNotEmpty);

      _expectUserDatabaseFilesUnchanged(beforeUserDb, databaseDir);
    },
  );
}
