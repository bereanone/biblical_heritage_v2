import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/library/presentation/library_navigation_tree.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_captured_html_import_folder_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

LibraryCatalogItem _catalogItem({
  required String id,
  required String title,
  String? author,
  required String fileName,
  required String relativePath,
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: author,
    fileName: fileName,
    fileHash: null,
    relativePath: relativePath,
    fileFormat: 'epub',
    folderType: 'research',
    libraryRole: 'user_added',
    collectionName: 'EGW_Devotionals',
    sourceSite: null,
    sourceUrl: null,
    sourceType: 'official_download',
    coverPath: null,
    dateAdded: null,
    lastOpened: null,
    indexStatus: 'indexed',
    fileSize: 0,
    mimeType: 'application/epub+zip',
    spineIndex: null,
    anchorId: null,
    epubHref: null,
    paragraphIndex: null,
    navigationCount: 0,
  );
}

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

Future<void> _seedLibraryLink(
  Database db,
  String itemId, {
  required int paragraphIndex,
  required String anchor,
  required String fullParagraph,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('library_links', <String, Object?>{
    'id': 'link-$itemId-$paragraphIndex',
    'library_item_id': itemId,
    'book_id': 1,
    'chapter': 1,
    'verse_start': paragraphIndex,
    'verse_end': paragraphIndex,
    'link_type': 'research',
    'anchor': anchor,
    'original_reference_text': 'Acts 9:$paragraphIndex',
    'confidence': 1.0,
    'parser_warning': null,
    'epub_href': 'OEBPS/content01.xhtml',
    'epub_cfi': null,
    'anchor_id': 'anchor-$paragraphIndex',
    'spine_index': 1,
    'paragraph_index': paragraphIndex,
    'full_paragraph': fullParagraph,
    'created_by': 'test',
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'device_id': 'device-test',
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Directory> _prepareIsolatedLibraryRoot() async {
  final sourceDbDir = Directory(
    '/Users/deanbowen/Development/StudyBible2/test/Databases',
  );
  final libraryRootDir = await Directory.systemTemp.createTemp(
    'library_reader_refcodes_root_',
  );
  final dbDir = Directory(p.join(libraryRootDir.path, 'Databases'));
  await dbDir.create(recursive: true);
  for (final fileName in const ['user.db', 'eLibrary.db']) {
    final sourceFile = File(p.join(sourceDbDir.path, fileName));
    if (await sourceFile.exists()) {
      await sourceFile.copy(p.join(dbDir.path, fileName));
    }
  }
  return libraryRootDir;
}

Future<Directory> _createCaptureFolder({
  required Directory root,
  required String folderName,
  required String title,
  required String abbreviation,
  required String workId,
  required String authorName,
  required String bodyHtml,
}) async {
  final folder = Directory(p.join(root.path, folderName));
  await folder.create(recursive: true);
  await File(p.join(folder.path, 'metadata.json')).writeAsString('''
{
  "title": "$title",
  "abbreviation": "$abbreviation",
  "work_id": "$workId",
  "source_type": "pioneer_captured_html",
  "source_site": "user_capture",
  "contributors": [
    {
      "name": "$authorName",
      "role": "author",
      "sort_order": 1,
      "primary": true
    }
  ]
}
''');
  await File(p.join(folder.path, 'capture.html')).writeAsString(bodyHtml);
  return folder;
}

Future<void> _pumpUntilFinder(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 30,
  Duration step = const Duration(milliseconds: 200),
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(step);
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpTransient(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('maps Christ Triumphant to the expected ref abbreviation', () {
    final item = _catalogItem(
      id: 'ct',
      title: 'Christ Triumphant',
      fileName: 'en_CTr.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CTr.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'CTr');
  });

  test('maps Conflict and Courage to the expected ref abbreviation', () {
    final item = _catalogItem(
      id: 'cc',
      title: 'Conflict and Courage',
      fileName: 'en_CC.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CC.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'CC');
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'A Clear View of God, May 13',
        paragraphIndex: 1,
      ),
      'CC May 13.1',
    );
  });

  test('keeps Christ’s Object Lessons mapped to COL', () {
    final item = _catalogItem(
      id: 'col',
      title: 'Christ’s Object Lessons',
      fileName: 'en_COL.epub',
      relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'COL');
  });

  test('maps Maranatha to Mar for devotional fallbacks', () {
    final item = _catalogItem(
      id: 'mar',
      title: 'Maranatha',
      fileName: 'en_Mar.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_Mar.epub',
    );

    expect(libraryReaderBookAbbreviation(item), 'Mar');
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Turmoil in the Cities, May 13',
        paragraphIndex: 1,
      ),
      'Mar May 13.1',
    );
  });

  test('prefers the real author in the reader subtitle', () {
    final item = _catalogItem(
      id: 'annie',
      title: 'Home Here, and Home in Heaven; With Other Poems',
      author: 'Annie Smith',
      fileName: 'HHAH.html',
      relativePath: 'ePubs/Research/Pioneer Authors/annie_smith/HHAH.html',
    );

    expect(libraryReaderBookSubtitle(item), 'Annie Smith');
  });

  test('suppresses Chapter 0 from reader section titles', () {
    expect(
      libraryReaderDisplaySectionTitle('Chapter 0 — Section 1 — The Sanctuary'),
      'Section 1 — The Sanctuary',
    );
    expect(
      libraryReaderDisplaySectionTitle('Chapter 0 — The Sanctuary'),
      'The Sanctuary',
    );
  });

  test('does not apply devotional fallback to non-devotional books', () {
    final item = _catalogItem(
      id: 'col',
      title: 'Christ’s Object Lessons',
      fileName: 'en_COL.epub',
      relativePath: 'ePubs/Research/EGW_Books/en_COL.epub',
    ).copyWith(collectionName: 'EGW_Books', libraryRole: 'user_added');

    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Teaching in Parables, May 13',
        paragraphIndex: 1,
      ),
      isNull,
    );
  });

  test('generates Acts-style ref codes from DB text blocks', () {
    final codes = generateLibraryTextBlockReferenceCodes(
      itemAbbreviation: 'AA',
      plainTexts: const <String>[
        'The church is God’s appointed agency for the salvation of men.',
        'Many and wonderful are the promises recorded in the Scriptures [10] regarding the church.',
        '“Ye are My witnesses, saith the Lord...”',
      ],
    );

    expect(codes, const <String?>['AA 9.1', 'AA 9.2', 'AA 10.1']);

    final block = LibraryBookBlock(
      html:
          '<p>The church is God’s appointed agency for the salvation of men.</p>',
      text: 'The church is God’s appointed agency for the salvation of men.',
      kind: 'paragraph',
      referenceCode: codes.first,
    );
    expect(block.referenceCode, 'AA 9.1');
  });

  test('skips devotional scripture subtitles for fallback numbering', () {
    final item = _catalogItem(
      id: 'ct',
      title: 'Christ Triumphant',
      fileName: 'en_CTr.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_CTr.epub',
    );

    final scriptureSubtitle = LibraryBookBlock(
      html:
          '<p class="bibletext center">Choose you this day whom ye will serve; ... Joshua 24:15.</p>',
      text: 'Choose you this day whom ye will serve; ... Joshua 24:15.',
      kind: 'paragraph',
      className: 'bibletext center',
      bodyOrder: 2,
    );
    final firstBodyParagraph = LibraryBookBlock(
      html: '<p>If those who are still on the stage of action...</p>',
      text: 'If those who are still on the stage of action...',
      kind: 'paragraph',
      bodyOrder: 3,
    );

    expect(
      libraryReaderShouldCountDevotionalFallbackParagraph(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        block: scriptureSubtitle,
        fallbackParagraphCount: 0,
      ),
      isFalse,
    );
    expect(
      libraryReaderShouldCountDevotionalFallbackParagraph(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        block: firstBodyParagraph,
        fallbackParagraphCount: 0,
      ),
      isTrue,
    );
    expect(
      libraryReaderDevotionalFallbackRefCode(
        item: item,
        sectionTitle: 'Never Forget God’s Leading In The Past, May 13',
        paragraphIndex: 1,
      ),
      'CTr May 13.1',
    );
  });

  test('skips Homeward Bound bible subtitles with a trailing dash citation', () {
    final item = _catalogItem(
      id: 'hb',
      title: 'Homeward Bound',
      fileName: 'en_HB.epub',
      relativePath: 'ePubs/Research/EGW_Devotionals/en_HB.epub',
    );

    const subtitle =
        'Nor did their own arm save them; but it was Your right hand, Your arm, and the light of Your countenance, because You favored them.—Psalm 44:3.';
    final subtitleBlock = LibraryBookBlock(
      html: '<p class="bibletext center">$subtitle</p>',
      text: subtitle,
      kind: 'paragraph',
      className: 'bibletext center',
      bodyOrder: 2,
    );
    final bodyBlock = LibraryBookBlock(
      html: '<p>Prayer moves the arm of omnipotence.</p>',
      text: 'Prayer moves the arm of omnipotence.',
      kind: 'paragraph',
      bodyOrder: 3,
    );

    expect(
      libraryReaderShouldCountDevotionalFallbackParagraphText(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        paragraphText: subtitle,
        className: subtitleBlock.className,
        fallbackParagraphCount: 0,
      ),
      isFalse,
    );
    expect(
      libraryReaderShouldCountDevotionalFallbackParagraphText(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        paragraphText: bodyBlock.text,
        className: bodyBlock.className,
        fallbackParagraphCount: 0,
      ),
      isTrue,
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: subtitleBlock,
        fallbackParagraphCount: 0,
      ),
      isNull,
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: bodyBlock,
        fallbackParagraphCount: 0,
      ),
      'HB May 13.1',
    );
    expect(
      libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: 'Prayer Moves the Arm of Omnipotence, May 13',
        block: LibraryBookBlock(
          html: '<p>While the world is progressing...</p>',
          text: 'While the world is progressing...',
          kind: 'paragraph',
        ),
        fallbackParagraphCount: 1,
      ),
      'HB May 13.2',
    );
  });

  test('hides obvious devotional front matter entries from contents', () {
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'Information about this Book',
        href: 'oebps/aboutbook.xhtml',
      ),
      isTrue,
    );
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'A Word to the Reader',
        href: 'oebps/content00.xhtml',
      ),
      isTrue,
    );
    expect(
      libraryReaderShouldHideDevotionalContentsEntry(
        label: 'Like Parent, Like Child, May 13',
        href: 'oebps/content139.xhtml',
      ),
      isFalse,
    );
  });

  test('Contents Chapter I opens the first text block of Chapter I', () {
    final section = LibraryBookSection(
      entryName: 'OPS/chapter-5.xhtml',
      title: 'CHAPTER I',
      paragraphs: const <String>[
        'Although Daniel lived twenty-five hundred years ago, he is a latter-day prophet.',
        'True, it was once a sealed book.',
        'The text continues.',
      ],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html: '<p>Although Daniel lived twenty-five hundred years ago...</p>',
          text: 'Although Daniel lived twenty-five hundred years ago...',
          kind: 'paragraph',
          bodyOrder: 1,
        ),
        LibraryBookBlock(
          html: '<p>True, it was once a sealed book.</p>',
          text: 'True, it was once a sealed book.',
          kind: 'paragraph',
          bodyOrder: 2,
        ),
      ],
      spineIndex: 5,
    );
    final navItem = LibraryCatalogNavigationItem(
      id: 'chapter-i',
      parentId: null,
      label: 'CHAPTER I',
      href: 'OPS/chapter-5.xhtml',
      anchorId: null,
      spineIndex: 5,
      sortOrder: 5,
      depth: 0,
      navType: 'toc',
      contentKind: 'chapter',
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: 5,
    );

    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItem,
        sections: [section],
      ),
      'body:1',
    );
    expect(
      libraryReaderNavigationItemTargetsSectionStart(
        navItem: navItem,
        sections: [section],
      ),
      isTrue,
    );
  });

  test('Contents Chapter II also resolves to the start of Chapter II', () {
    final chapterOne = LibraryBookSection(
      entryName: 'OPS/chapter-5.xhtml',
      title: 'CHAPTER I',
      paragraphs: const <String>['Chapter one paragraph.'],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html: '<p>Chapter one paragraph.</p>',
          text: 'Chapter one paragraph.',
          kind: 'paragraph',
          bodyOrder: 1,
        ),
      ],
      spineIndex: 5,
    );
    final chapterTwo = LibraryBookSection(
      entryName: 'OPS/chapter-6.xhtml',
      title: 'CHAPTER II',
      paragraphs: const <String>[
        'Chapter two paragraph one.',
        'Chapter two paragraph two.',
      ],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html: '<p>Chapter two paragraph one.</p>',
          text: 'Chapter two paragraph one.',
          kind: 'paragraph',
          bodyOrder: 1,
        ),
        LibraryBookBlock(
          html: '<p>Chapter two paragraph two.</p>',
          text: 'Chapter two paragraph two.',
          kind: 'paragraph',
          bodyOrder: 2,
        ),
      ],
      spineIndex: 6,
    );
    final navItem = LibraryCatalogNavigationItem(
      id: 'chapter-ii',
      parentId: null,
      label: 'CHAPTER II',
      href: 'OPS/chapter-6.xhtml',
      anchorId: null,
      spineIndex: 6,
      sortOrder: 6,
      depth: 0,
      navType: 'toc',
      contentKind: 'chapter',
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: 6,
    );

    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItem,
        sections: [chapterOne, chapterTwo],
      ),
      'body:1',
    );
    expect(
      libraryReaderNavigationItemTargetsSectionStart(
        navItem: navItem,
        sections: [chapterOne, chapterTwo],
      ),
      isTrue,
    );
  });

  test('SSP-style chapter navigation targets the real section starts', () {
    final preface = LibraryBookSection(
      entryName: 'ssp.xhtml',
      title: 'AUTHORS PREFACE.',
      paragraphs: const <String>['These pages introduce the book.'],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html: '<b class="calibre1">AUTHORS PREFACE.</b>',
          text: 'AUTHORS PREFACE.',
          kind: 'heading',
          anchorId: 'preface-start',
        ),
      ],
      spineIndex: 1,
    );
    final chapterOne = LibraryBookSection(
      entryName: 'ssp.xhtml#chapter-1',
      title: 'CHAPTER 1. THE SEER OF PATMOS.',
      paragraphs: const <String>[
        'SSP 1.1 First paragraph.',
        'SSP 1.2 Second paragraph.',
      ],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html:
              '<b id="calibre_toc_1" class="calibre1">CHAPTER 1. THE SEER OF PATMOS.</b>',
          text: 'CHAPTER 1. THE SEER OF PATMOS.',
          kind: 'heading',
          anchorId: 'chapter-1-start',
        ),
      ],
      spineIndex: 2,
    );
    final chapterTwo = LibraryBookSection(
      entryName: 'ssp.xhtml#chapter-2',
      title: 'CHAPTER 2. THE CHRIST OF THE APOCALYPSE.',
      paragraphs: const <String>['SSP 2.1 Third paragraph.'],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html:
              '<b id="calibre_toc_2" class="calibre1">CHAPTER 2. THE CHRIST OF THE APOCALYPSE.</b>',
          text: 'CHAPTER 2. THE CHRIST OF THE APOCALYPSE.',
          kind: 'heading',
          anchorId: 'chapter-2-start',
        ),
      ],
      spineIndex: 3,
    );

    final navItems = <LibraryCatalogNavigationItem>[
      LibraryCatalogNavigationItem(
        id: 'preface',
        parentId: null,
        label: 'AUTHORS PREFACE.',
        href: 'ssp.xhtml',
        anchorId: 'preface-start',
        spineIndex: 1,
        sortOrder: 1,
        depth: 0,
        navType: 'toc',
        contentKind: 'front_matter',
        isFrontMatter: true,
        isBodyStart: false,
        bodyOrder: 1,
      ),
      LibraryCatalogNavigationItem(
        id: 'chapter-1',
        parentId: null,
        label: 'CHAPTER 1. THE SEER OF PATMOS.',
        href: null,
        anchorId: 'chapter-1-start',
        spineIndex: 2,
        sortOrder: 2,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: false,
        isBodyStart: true,
        bodyOrder: 2,
      ),
      LibraryCatalogNavigationItem(
        id: 'chapter-2',
        parentId: null,
        label: 'CHAPTER 2. THE CHRIST OF THE APOCALYPSE.',
        href: null,
        anchorId: 'chapter-2-start',
        spineIndex: 3,
        sortOrder: 3,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 3,
      ),
    ];

    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItems[0],
        sections: [preface, chapterOne, chapterTwo],
      ),
      'anchor:preface_start',
    );
    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItems[1],
        sections: [preface, chapterOne, chapterTwo],
      ),
      'anchor:chapter_1_start',
    );
    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItems[2],
        sections: [preface, chapterOne, chapterTwo],
      ),
      'anchor:chapter_2_start',
    );
    expect(
      libraryReaderNavigationItemTargetsSectionStart(
        navItem: navItems[1],
        sections: [preface, chapterOne, chapterTwo],
      ),
      isTrue,
    );
    expect(
      libraryReaderNavigationItemTargetsSectionStart(
        navItem: navItems[2],
        sections: [preface, chapterOne, chapterTwo],
      ),
      isTrue,
    );
  });

  test('Contents and heading navigation keep the same cleaned ordering', () {
    final items = <LibraryCatalogNavigationItem>[
      LibraryCatalogNavigationItem(
        id: 'title',
        parentId: null,
        label: 'The Story of Daniel the Prophet',
        href: 'OPS/chapter-1.xhtml',
        anchorId: null,
        spineIndex: 1,
        sortOrder: 1,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: true,
        isBodyStart: true,
        bodyOrder: 1,
      ),
      LibraryCatalogNavigationItem(
        id: 'chapter1',
        parentId: null,
        label: 'CHAPTER I',
        href: 'OPS/chapter-5.xhtml',
        anchorId: null,
        spineIndex: 5,
        sortOrder: 5,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 5,
      ),
      LibraryCatalogNavigationItem(
        id: 'chapter2',
        parentId: null,
        label: 'CHAPTER II',
        href: 'OPS/chapter-6.xhtml',
        anchorId: null,
        spineIndex: 6,
        sortOrder: 6,
        depth: 0,
        navType: 'toc',
        contentKind: 'chapter',
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 1,
      ),
    ];

    final tree = buildLibraryNavigationTree(items);
    expect(tree.items.map((item) => item.id), [
      'title',
      'chapter1',
      'chapter2',
    ]);
  });

  group('section reference codes', () {
    late Directory supportDir;
    late Directory documentsDir;
    late Directory libraryRootDir;

    setUp(() async {
      supportDir = await Directory.systemTemp.createTemp(
        'library_reader_refcodes_support_',
      );
      documentsDir = await Directory.systemTemp.createTemp(
        'library_reader_refcodes_documents_',
      );
      libraryRootDir = await _prepareIsolatedLibraryRoot();
      await _installPathProviderMocks(
        supportDir: supportDir,
        documentsDir: documentsDir,
      );
      LibraryRootService.instance.invalidateCachedSelection();
      await LocalSettingsStore.instance.saveLibraryRoot(
        path: libraryRootDir.path,
        source: 'userSelected',
      );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      LibraryRootService.instance.invalidateCachedSelection();
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

    test('loads section reference codes from eLibrary.db first', () async {
      final userDb = await UserDatabase.instance.database;
      final eLibraryDb = await ELibraryDatabase.instance.database;

      await _seedLibraryLink(
        userDb,
        'acts-item',
        paragraphIndex: 1,
        anchor: '[8]',
        fullParagraph: 'Fallback page marker [8] for user.db',
      );
      await _seedLibraryLink(
        userDb,
        'acts-item',
        paragraphIndex: 2,
        anchor: '',
        fullParagraph: 'Fallback second paragraph for user.db',
      );

      await _seedLibraryLink(
        eLibraryDb,
        'acts-item',
        paragraphIndex: 1,
        anchor: '[9]',
        fullParagraph: 'Primary page marker [9] for eLibrary.db',
      );
      await _seedLibraryLink(
        eLibraryDb,
        'acts-item',
        paragraphIndex: 2,
        anchor: '',
        fullParagraph: 'Primary second paragraph for eLibrary.db',
      );

      final section = LibraryBookSection(
        entryName: 'OEBPS/content01.xhtml',
        title: 'Acts 9',
        paragraphs: const <String>[],
        blocks: const <LibraryBookBlock>[],
        spineIndex: 1,
      );

      final codes = await loadReaderSectionReferenceCodes(
        libraryItemId: 'acts-item',
        section: section,
        itemAbbreviation: 'AA',
        isDevotional: false,
      );

      expect(codes, const <int, String>{1: 'AA 9.1', 2: 'AA 9.2'});
    });

    test(
      'falls back to user.db when eLibrary.db lacks section codes',
      () async {
        final userDb = await UserDatabase.instance.database;

        await _seedLibraryLink(
          userDb,
          'acts-item-fallback',
          paragraphIndex: 1,
          anchor: '[7]',
          fullParagraph: 'Fallback page marker [7] for user.db',
        );
        await _seedLibraryLink(
          userDb,
          'acts-item-fallback',
          paragraphIndex: 2,
          anchor: '',
          fullParagraph: 'Fallback second paragraph for user.db',
        );

        final section = LibraryBookSection(
          entryName: 'OEBPS/content01.xhtml',
          title: 'Acts 9',
          paragraphs: const <String>[],
          blocks: const <LibraryBookBlock>[],
          spineIndex: 1,
        );

        final codes = await loadReaderSectionReferenceCodes(
          libraryItemId: 'acts-item-fallback',
          section: section,
          itemAbbreviation: 'AA',
          isDevotional: false,
        );

        expect(codes, const <int, String>{1: 'AA 7.1', 2: 'AA 7.2'});
      },
    );

    group('reader maintenance menu', () {
      late Directory supportDir;
      late Directory documentsDir;
      late Directory libraryRootDir;
      late Directory captureRootDir;
      late Directory sourceFolder;
      late LibraryCatalogItem importedItem;

      setUp(() async {
        supportDir = await Directory.systemTemp.createTemp(
          'reader_menu_support_',
        );
        documentsDir = await Directory.systemTemp.createTemp(
          'reader_menu_docs_',
        );
        libraryRootDir = await Directory.systemTemp.createTemp(
          'reader_menu_root_',
        );
        captureRootDir = await Directory.systemTemp.createTemp(
          'reader_menu_capture_',
        );

        LibraryRootService.instance.invalidateCachedSelection();
        await _installPathProviderMocks(
          supportDir: supportDir,
          documentsDir: documentsDir,
        );
        await LibraryRootService.instance.setLibraryRoot(
          path: libraryRootDir.path,
        );
        await LocalSettingsStore.instance.ensureDeviceId();

        sourceFolder = await _createCaptureFolder(
          root: captureRootDir,
          folderName: 'SSP',
          title: 'SSP',
          abbreviation: 'SSP',
          workId: 'the_story_of_the_seer_of_patmos',
          authorName: 'S. N. Haskell',
          bodyHtml: '''
<!doctype html>
<html>
  <head>
    <title>SSP</title>
    <meta name="author" content="S. N. Haskell" />
  </head>
  <body>
    <h1>The Story of the Seer of Patmos</h1>
    <h2>CHAPTER 1. THE SEER OF PATMOS.</h2>
    <div class="clip clip-text">
      <p>SSP 1.1 First paragraph. SSP 1.2 Second paragraph.</p>
    </div>
    <h2>CHAPTER 2. THE CHRIST OF THE APOCALYPSE.</h2>
    <div class="clip clip-text">
      <p>SSP 2.1 Third paragraph. SSP 2.2 Fourth paragraph.</p>
    </div>
  </body>
</html>
''',
        );

        await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
          path: captureRootDir.path,
        );

        final importReport = await PioneerCapturedHtmlImportFolderService.instance
            .importConfiguredCloudFolder(
              selectedFolderPaths: [sourceFolder.path],
              archiveImportedFolders: false,
            );
        expect(importReport.importedCount, 1);

        final items = await LibraryCatalogService.instance.loadItems();
        importedItem = items.singleWhere(
          (item) => item.displayTitle == 'The Story of the Seer of Patmos',
        );
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
        if (captureRootDir.existsSync()) {
          await captureRootDir.delete(recursive: true);
        }
      });

      testWidgets(
        'reader page hides inline maintenance buttons and exposes them in the menu',
        (tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(body: Text('Library Home')),
            ),
          );
          await tester.pump();

          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => LibraryBookReaderScreen(item: importedItem),
            ),
          );
          await _pumpUntilFinder(
            tester,
            find.text('The Story of the Seer of Patmos'),
          );

          expect(find.text('Remove from Library'), findsNothing);
          expect(find.text('Repair Imported Book'), findsNothing);
          expect(find.text('Menu'), findsOneWidget);

          await tester.tap(find.text('Menu'));
          await _pumpTransient(tester);

          expect(find.text('Open eLibrary Setup'), findsOneWidget);
          expect(find.text('Maintenance'), findsOneWidget);
          expect(
            find.text('Remove Current Book from Library'),
            findsOneWidget,
          );
          expect(
            find.text('Repair Current Imported Book'),
            findsOneWidget,
          );
        },
      );

      test('maintenance eligibility skips non-imported books', () {
        final normalBook = _catalogItem(
          id: 'normal',
          title: 'Some Other Book',
          author: 'Jane Doe',
          fileName: 'en_norm.epub',
          relativePath: 'ePubs/Research/EGW_Books/en_norm.epub',
        );

        expect(libraryReaderCanManageImportedBook(importedItem), isTrue);
        expect(libraryReaderCanManageImportedBook(normalBook), isFalse);
      });

      testWidgets(
        'remove from menu is DB-only and cancel does nothing',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              home: LibraryBookReaderScreen(item: importedItem),
            ),
          );
          await _pumpUntilFinder(
            tester,
            find.text('The Story of the Seer of Patmos'),
          );

          await tester.tap(find.text('Menu'));
          await _pumpTransient(tester);
          await tester.tap(find.text('Remove Current Book from Library'));
          await _pumpUntilFinder(
            tester,
            find.textContaining(
              'This removes the imported database copy only.',
            ),
          );

          expect(
            find.textContaining(
              'This removes the imported database copy only.',
            ),
            findsOneWidget,
          );

          await tester.tap(find.text('Cancel'));
          await _pumpTransient(tester);
          expect(find.text('Menu'), findsOneWidget);
          expect(
            find.textContaining(
              'This removes the imported database copy only.',
            ),
            findsNothing,
          );
        },
      );

      test(
        'remove path deletes only the database copy and keeps the source folder',
        () async {
          final removed = await PioneerTextImportService.instance
              .removeImportedLibraryItem(importedItem.id);
          expect(removed, isTrue);
          expect(sourceFolder.existsSync(), isTrue);

          final itemsAfterRemove = await LibraryCatalogService.instance
              .loadItems();
          expect(
            itemsAfterRemove
                .where(
                  (item) =>
                      item.displayTitle == 'The Story of the Seer of Patmos',
                ),
            isEmpty,
          );
        },
      );

      test(
        'repair path fails gracefully when the source folder is missing',
        () async {
          await sourceFolder.delete(recursive: true);

          final report = await PioneerCapturedHtmlImportFolderService.instance
              .repairImportedCaptureClipperBook(
                libraryItemId: importedItem.id,
              );

          expect(report, isNull);

          final itemsAfterRepair = await LibraryCatalogService.instance
              .loadItems();
          expect(
            itemsAfterRepair
                .where(
                  (item) =>
                      item.displayTitle == 'The Story of the Seer of Patmos',
                ),
            isNotEmpty,
          );
        },
      );
    });
  });
}
