import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_reader_opening.dart';
import 'package:studybible2/features/library/data/library_reader_state_writer.dart';
import 'package:studybible2/features/library/data/library_section_heuristics.dart';
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

LibraryCatalogItem _bookItem({
  required String id,
  required String title,
  String? epubHref,
  DateTime? lastOpened,
  int? spineIndex,
  int? paragraphIndex,
  String collectionName = 'Adventist Pioneer Library',
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: 'Stephen Nelson Haskell',
    fileName: '$id.epub',
    fileHash: null,
    relativePath: 'Books/$id.epub',
    fileFormat: 'epub',
    folderType: 'research',
    libraryRole: null,
    collectionName: collectionName,
    sourceSite: null,
    sourceUrl: null,
    sourceType: null,
    coverPath: null,
    dateAdded: DateTime.utc(2026, 7, 1),
    lastOpened: lastOpened,
    indexStatus: 'indexed',
    fileSize: null,
    mimeType: null,
    spineIndex: spineIndex,
    anchorId: null,
    epubHref: epubHref,
    paragraphIndex: paragraphIndex,
    navigationCount: 0,
  );
}

LibraryBookSection _section({
  required String entryName,
  required String title,
  required List<String> paragraphs,
  int? spineIndex,
}) {
  return LibraryBookSection(
    entryName: entryName,
    title: title,
    paragraphs: paragraphs,
    blocks: const <LibraryBookBlock>[],
    spineIndex: spineIndex,
  );
}

LibraryCatalogNavigationItem _navItem({
  required String id,
  required String label,
  required String href,
  required int sortOrder,
  bool isFrontMatter = false,
}) {
  return LibraryCatalogNavigationItem(
    id: id,
    parentId: null,
    label: label,
    href: href,
    anchorId: null,
    spineIndex: null,
    sortOrder: sortOrder,
    depth: 0,
    navType: 'toc',
    contentKind: null,
    isFrontMatter: isFrontMatter,
    isBodyStart: false,
    bodyOrder: null,
  );
}

Future<void> _insertLibraryItem(Database db, String itemId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('library_items', <String, Object?>{
    'id': itemId,
    'title': 'Test Book',
    'file_name': '$itemId.epub',
    'relative_path': 'Books/$itemId.epub',
    'created_at': now,
    'updated_at': now,
    'device_id': 'device_test',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('libraryReaderInitialSectionIndex', () {
    test(
      'ignores a saved href that became a heading-only shell after repair',
      () {
        final item = _bookItem(
          id: 'wor',
          title: 'Waggoner on Romans',
          lastOpened: DateTime.utc(2026, 7, 12),
          epubHref: 'divine-arithmetic.html',
        );
        final sections = <LibraryBookSection>[
          const LibraryBookSection(
            entryName: 'divine-arithmetic.html',
            title: 'DIVINE ARITHMETIC.',
            paragraphs: <String>[],
            blocks: <LibraryBookBlock>[],
            spineIndex: 1,
          ),
          LibraryBookSection(
            entryName: 'chapter-1.html',
            title: 'Chapter 1',
            paragraphs: const <String>[
              'This is the readable repaired body text for the first chapter '
                  'and it contains enough substantive content to be selected.',
            ],
            blocks: const <LibraryBookBlock>[],
            spineIndex: 2,
          ),
        ];
        final navigationItems = <LibraryCatalogNavigationItem>[
          _navItem(
            id: 'divine-arithmetic',
            label: 'DIVINE ARITHMETIC.',
            href: 'divine-arithmetic.html',
            sortOrder: 1,
          ),
          _navItem(
            id: 'chapter-1',
            label: 'Chapter 1',
            href: 'chapter-1.html',
            sortOrder: 2,
          ),
        ];

        expect(
          libraryReaderInitialSectionIndex(
            item: item,
            sections: sections,
            navigationItems: navigationItems,
            devotionalMode: false,
          ),
          1,
        );
      },
    );

    final sections = [
      _section(
        entryName: 'OPS/introduction.xhtml',
        title: 'Introduction',
        paragraphs: [
          'This introduction explains the purpose of the book and gives the reader the background needed to follow the chapters that come after it.',
          'It is still real reading material, but it is clearly introductory front matter rather than the first chapter of the work.',
        ],
        spineIndex: 1,
      ),
      _section(
        entryName: 'OPS/chapter1.xhtml',
        title: 'CHAPTER I. THE SEER OF PATMOS.',
        paragraphs: [
          'The Revelation opens with a blessing on the reader and a vision of the Son of man among the candlesticks.',
          'This is the first substantive chapter of the book.',
        ],
        spineIndex: 2,
      ),
    ];

    final navigationItems = <LibraryCatalogNavigationItem>[];

    test(
      'first open of a Pioneer book skips front matter, lands on Chapter 1',
      () {
        final item = _bookItem(
          id: 'reader-opening',
          title: 'The Story of the Seer of Patmos',
        );

        expect(
          libraryIsMeaningfulReadingSection(
            title: sections.first.title,
            href: sections.first.entryName,
            paragraphs: sections.first.paragraphs,
            bookTitle: item.displayTitle,
          ),
          isTrue,
        );

        expect(
          libraryReaderInitialSectionIndex(
            item: item,
            sections: sections,
            navigationItems: navigationItems,
            devotionalMode: false,
          ),
          1,
        );
      },
    );

    test(
      'saved location is restored for a previously opened ordinary book',
      () {
        final item = _bookItem(
          id: 'reader-opening',
          title: 'The Story of the Seer of Patmos',
          lastOpened: DateTime.utc(2026, 7, 8),
          epubHref: sections.first.entryName,
          spineIndex: 1,
          paragraphIndex: 1,
        );

        expect(
          libraryReaderInitialSectionIndex(
            item: item,
            sections: sections,
            navigationItems: navigationItems,
            devotionalMode: false,
          ),
          0,
        );
      },
    );

    test(
      'heading-only Preface stays separate and first open selects Chapter 1',
      () {
        final loaded = <LibraryBookSection>[
          _section(
            entryName: 'captured/wor/chapter_05_october.html',
            title: 'OCTOBER 17, 1895.',
            paragraphs: const ['First readable article body.'],
            spineIndex: 5,
          ),
        ];
        LibraryCatalogNavigationItem nav(
          String id,
          String label,
          String href,
          int spine,
        ) => LibraryCatalogNavigationItem(
          id: id,
          parentId: null,
          label: label,
          href: href,
          anchorId: null,
          spineIndex: spine,
          sortOrder: spine,
          depth: 1,
          navType: 'toc',
          contentKind: label == 'PREFACE.' ? 'preface' : 'chapter',
          isFrontMatter: label == 'PREFACE.',
          isBodyStart: false,
          bodyOrder: spine,
        );
        final navigation = [
          nav('preface', 'PREFACE.', 'captured/wor/preface.html', 2),
          nav('chapter1', 'CHAPTER 1.', 'captured/wor/chapter_1.html', 3),
          nav('october', 'OCTOBER 17, 1895.', loaded.single.entryName, 5),
        ];
        final structural = libraryReaderSectionsWithHeadingOnlyNavigation(
          sections: loaded,
          navigationItems: navigation,
        );

        expect(structural[0].title, 'PREFACE.');
        expect(structural[0].blocks, isEmpty);
        expect(structural[1].title, 'CHAPTER 1.');
        expect(structural[1].blocks, isEmpty);
        expect(
          libraryReaderInitialSectionIndex(
            item: _bookItem(id: 'wor', title: 'Waggoner on Romans'),
            sections: structural,
            navigationItems: navigation,
            devotionalMode: false,
          ),
          1,
        );
      },
    );

    test('first open of a non-devotional EGW book skips Introduction and '
        'selects Chapter 1', () {
      final item = _bookItem(
        id: 'egw-book',
        title: 'Steps to Christ',
        collectionName: 'EGW Books',
      );

      expect(item.isDevotional, isFalse);
      expect(
        libraryReaderInitialSectionIndex(
          item: item,
          sections: sections,
          navigationItems: navigationItems,
          devotionalMode: false,
        ),
        1,
      );
    });

    test('safe fallback stays on first readable section when no Chapter 1 or '
        'body marker exists', () {
      final frontMatterOnlySections = [
        _section(
          entryName: 'OPS/preface.xhtml',
          title: 'Preface',
          paragraphs: [
            'The preface carries enough real text to count as a readable section for the opening heuristics used by the reader.',
            'There is no chapter or other body content anywhere in this book.',
          ],
          spineIndex: 1,
        ),
        _section(
          entryName: 'OPS/introduction.xhtml',
          title: 'Introduction',
          paragraphs: [
            'The introduction is also readable front matter, and it is the only other section available in this stripped-down book.',
            'No chapter marker exists after it.',
          ],
          spineIndex: 2,
        ),
      ];

      expect(
        libraryReaderInitialSectionIndex(
          item: _bookItem(id: 'front-matter-only', title: 'Fragments'),
          sections: frontMatterOnlySections,
          navigationItems: navigationItems,
          devotionalMode: false,
        ),
        0,
      );
    });
  });

  group('libraryReaderInitialSectionIndex devotional', () {
    // Mirrors the real EGW devotional shape: front matter roots plus month
    // heading roots whose day entries carry the "…, Month D" label suffix.
    final devotionalSections = [
      _section(
        entryName: 'OEBPS/aboutbook.xhtml',
        title: 'Information about this Book',
        paragraphs: [
          'This eBook is provided by the Ellen G. White Estate and includes information about the book itself rather than devotional readings.',
          'It is metadata style front matter for the devotional volume.',
        ],
        spineIndex: 1,
      ),
      _section(
        entryName: 'OEBPS/content00.xhtml',
        title: 'Foreword',
        paragraphs: [
          'The foreword introduces the devotional and explains how the daily readings were compiled from the writings of the author.',
          'It is not a dated devotional entry.',
        ],
        spineIndex: 2,
      ),
      _section(
        entryName: 'OEBPS/content33.xhtml',
        title: 'February—God Loves Us',
        paragraphs: [
          'The February month heading page introduces the theme for the month of February with a short devotional overview of the topic.',
          'Daily readings for February follow this page.',
        ],
        spineIndex: 3,
      ),
      _section(
        entryName: 'OEBPS/content34.xhtml',
        title: 'Loved of God, February 1',
        paragraphs: [
          'The reading for the first of February with a full devotional text drawn from the writings selected for that calendar day.',
          'It closes with a short prayer for the day.',
        ],
        spineIndex: 4,
      ),
      _section(
        entryName: 'OEBPS/content73.xhtml',
        title: 'March—Walking With God',
        paragraphs: [
          'The March month heading page introduces the theme for the month of March with a short devotional overview of the topic.',
          'Daily readings for March follow this page.',
        ],
        spineIndex: 5,
      ),
      _section(
        entryName: 'OEBPS/content74.xhtml',
        title: 'Trust in Him, March 14',
        paragraphs: [
          'The reading for the fourteenth of March with a full devotional text drawn from the writings selected for that calendar day.',
          'It closes with a short prayer for the day.',
        ],
        spineIndex: 6,
      ),
      _section(
        entryName: 'OEBPS/content75.xhtml',
        title: 'Peace in Believing, March 15',
        paragraphs: [
          'The reading for the fifteenth of March with a full devotional text drawn from the writings selected for that calendar day.',
          'It closes with a short prayer for the day.',
        ],
        spineIndex: 7,
      ),
      _section(
        entryName: 'OEBPS/content76.xhtml',
        title: 'Strength for Today, March 16',
        paragraphs: [
          'The reading for the sixteenth of March with a full devotional text drawn from the writings selected for that calendar day.',
          'It closes with a short prayer for the day.',
        ],
        spineIndex: 8,
      ),
    ];

    final devotionalNavigation = <LibraryCatalogNavigationItem>[
      _navItem(
        id: 'n0',
        label: 'Information about this Book',
        href: 'oebps/aboutbook.xhtml',
        sortOrder: 0,
        isFrontMatter: true,
      ),
      _navItem(
        id: 'n1',
        label: 'Foreword',
        href: 'oebps/content00.xhtml',
        sortOrder: 1,
        isFrontMatter: true,
      ),
      _navItem(
        id: 'n2',
        label: 'February—God Loves Us',
        href: 'oebps/content33.xhtml',
        sortOrder: 2,
      ),
      _navItem(
        id: 'n3',
        label: 'Loved of God, February 1',
        href: 'oebps/content34.xhtml',
        sortOrder: 3,
      ),
      _navItem(
        id: 'n4',
        label: 'March—Walking With God',
        href: 'oebps/content73.xhtml',
        sortOrder: 4,
      ),
      _navItem(
        id: 'n5',
        label: 'Trust in Him, March 14',
        href: 'oebps/content74.xhtml',
        sortOrder: 5,
      ),
      _navItem(
        id: 'n6',
        label: 'Peace in Believing, March 15',
        href: 'oebps/content75.xhtml',
        sortOrder: 6,
      ),
      _navItem(
        id: 'n7',
        label: 'Strength for Today, March 16',
        href: 'oebps/content76.xhtml',
        sortOrder: 7,
      ),
    ];

    final fixedToday = DateTime(2026, 3, 15);

    LibraryCatalogItem devotionalItem({
      String? epubHref,
      DateTime? lastOpened,
      int? spineIndex,
      int? paragraphIndex,
    }) {
      return _bookItem(
        id: 'devotional',
        title: 'Sons and Daughters of God',
        collectionName: 'EGW_Devotionals',
        epubHref: epubHref,
        lastOpened: lastOpened,
        spineIndex: spineIndex,
        paragraphIndex: paragraphIndex,
      );
    }

    test('first open selects the entry for the current month and day', () {
      final item = devotionalItem();
      expect(item.isDevotional, isTrue);

      final index = libraryReaderInitialSectionIndex(
        item: item,
        sections: devotionalSections,
        navigationItems: devotionalNavigation,
        devotionalMode: true,
        now: fixedToday,
      );

      expect(devotionalSections[index].entryName, 'OEBPS/content75.xhtml');
    });

    test(
      'previously opened devotional with a saved href still opens today',
      () {
        final item = devotionalItem(
          lastOpened: DateTime.utc(2026, 2, 1),
          epubHref: 'OEBPS/content34.xhtml',
        );

        final index = libraryReaderInitialSectionIndex(
          item: item,
          sections: devotionalSections,
          navigationItems: devotionalNavigation,
          devotionalMode: true,
          now: fixedToday,
        );

        expect(devotionalSections[index].entryName, 'OEBPS/content75.xhtml');
      },
    );

    test(
      'previously opened devotional with saved spine and paragraph still opens today',
      () {
        final item = devotionalItem(
          lastOpened: DateTime.utc(2026, 2, 1),
          epubHref: null,
          spineIndex: 4,
          paragraphIndex: 2,
        );

        final index = libraryReaderInitialSectionIndex(
          item: item,
          sections: devotionalSections,
          navigationItems: devotionalNavigation,
          devotionalMode: true,
          now: fixedToday,
        );

        expect(devotionalSections[index].entryName, 'OEBPS/content75.xhtml');
      },
    );

    test('explicit initial href wins over the current-date default', () {
      final index = libraryReaderInitialSectionIndex(
        item: devotionalItem(),
        sections: devotionalSections,
        navigationItems: devotionalNavigation,
        devotionalMode: true,
        initialHref: 'OEBPS/content76.xhtml',
        now: fixedToday,
      );

      expect(devotionalSections[index].entryName, 'OEBPS/content76.xhtml');
    });

    test('explicit initial spine wins over the current-date default', () {
      final index = libraryReaderInitialSectionIndex(
        item: devotionalItem(),
        sections: devotionalSections,
        navigationItems: devotionalNavigation,
        devotionalMode: true,
        initialSpineIndex: 8,
        now: fixedToday,
      );

      expect(devotionalSections[index].entryName, 'OEBPS/content76.xhtml');
    });

    test('falls back to the month heading when today has no entry', () {
      final index = libraryReaderInitialSectionIndex(
        item: devotionalItem(),
        sections: devotionalSections,
        navigationItems: devotionalNavigation,
        devotionalMode: true,
        now: DateTime(2026, 3, 31),
      );

      // No March 31 entry exists; the first reading of March is used.
      expect(devotionalSections[index].entryName, 'OEBPS/content74.xhtml');
    });
  });

  group('LibraryReaderStateWriter', () {
    late Directory supportDir;
    late Directory documentsDir;
    late Directory libraryRootDir;

    setUp(() async {
      supportDir = await Directory.systemTemp.createTemp(
        'reader_opening_support_',
      );
      documentsDir = await Directory.systemTemp.createTemp(
        'reader_opening_docs_',
      );
      libraryRootDir = await Directory.systemTemp.createTemp(
        'reader_opening_root_',
      );

      LibraryRootService.instance.invalidateCachedSelection();
      await _installPathProviderMocks(
        supportDir: supportDir,
        documentsDir: documentsDir,
      );
      await LibraryRootService.instance.setLibraryRoot(
        path: libraryRootDir.path,
      );
      await LibraryRootService.instance.loadSelection();
      await LibraryRootService.instance.accessibleLibraryRootPath();
      await LocalSettingsStore.instance.ensureDeviceId();
      await UserDatabase.instance.database;
      await ELibraryDatabase.instance.database;
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
      for (final dir in [supportDir, documentsDir, libraryRootDir]) {
        if (dir.existsSync()) {
          await dir.delete(recursive: true);
        }
      }
    });

    test('opening a book writes last_opened', () async {
      const itemId = 'reader-state-writer';
      final elibraryDb = await ELibraryDatabase.instance.database;
      final userDb = await UserDatabase.instance.database;
      await _insertLibraryItem(elibraryDb, itemId);
      await _insertLibraryItem(userDb, itemId);

      await LibraryReaderStateWriter.instance.stampLastOpened(itemId);

      final elibraryRows = await elibraryDb.query(
        'library_items',
        columns: const ['last_opened', 'updated_at'],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      final userRows = await userDb.query(
        'library_items',
        columns: const ['last_opened', 'updated_at'],
        where: 'id = ?',
        whereArgs: [itemId],
        limit: 1,
      );

      expect(elibraryRows, hasLength(1));
      expect(userRows, hasLength(1));
      expect(elibraryRows.single['last_opened'], isNotNull);
      expect(userRows.single['last_opened'], isNotNull);
      expect(elibraryRows.single['updated_at'], isNotNull);
      expect(userRows.single['updated_at'], isNotNull);
    });
  });
}
