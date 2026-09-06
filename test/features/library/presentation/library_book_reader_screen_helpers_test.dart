import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_reader_opening.dart';
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
  String fileFormat = 'epub',
  String mimeType = 'application/epub+zip',
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: author,
    fileName: fileName,
    fileHash: null,
    relativePath: relativePath,
    fileFormat: fileFormat,
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
    mimeType: mimeType,
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
  final sourceDbDir = Directory('test/Databases');
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
  final booksRoot = p.basename(root.path) == 'Books'
      ? root
      : Directory(p.join(root.path, 'Books'));
  final folder = Directory(p.join(booksRoot.path, folderName));
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

  test('steady autoscroll remains desktop-only', () {
    expect(libraryReaderUsesSteadyAutoscroll(TargetPlatform.android), isFalse);
    expect(libraryReaderUsesSteadyAutoscroll(TargetPlatform.macOS), isTrue);
    expect(libraryReaderUsesSteadyAutoscroll(TargetPlatform.windows), isTrue);
    expect(libraryReaderUsesSteadyAutoscroll(TargetPlatform.linux), isTrue);
    expect(libraryReaderUsesSteadyAutoscroll(TargetPlatform.iOS), isFalse);
  });

  test('steady autoscroll remains disabled for PDF books', () {
    final textBook = _catalogItem(
      id: 'text-reader',
      title: 'Text Reader',
      fileName: 'text.epub',
      relativePath: 'text.epub',
    );
    final pdfBook = _catalogItem(
      id: 'pdf-reader',
      title: 'PDF Reader',
      fileName: 'document.pdf',
      relativePath: 'document.pdf',
      fileFormat: 'pdf',
      mimeType: 'application/pdf',
    );

    expect(
      libraryReaderSteadyAutoscrollEnabled(
        item: textBook,
        hasReadableSections: true,
      ),
      isTrue,
    );
    expect(
      libraryReaderSteadyAutoscrollEnabled(
        item: pdfBook,
        hasReadableSections: true,
      ),
      isFalse,
    );
    expect(
      libraryReaderSteadyAutoscrollEnabled(
        item: textBook,
        hasReadableSections: false,
      ),
      isFalse,
    );
  });

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

  test('TOC headings sharing one EPUB section resolve to their own blocks', () {
    final section = LibraryBookSection(
      entryName: 'OEBPS/early-writings.xhtml',
      title: 'Early Writings',
      paragraphs: const <String>['Preface text.', 'The vision text.'],
      blocks: const <LibraryBookBlock>[
        LibraryBookBlock(
          html: '<h1>Early Writings</h1>',
          text: 'Early Writings',
          kind: 'heading',
          bodyOrder: 1,
        ),
        LibraryBookBlock(
          html: '<h2>Preface</h2>',
          text: 'Preface',
          kind: 'heading',
          bodyOrder: 17,
        ),
        LibraryBookBlock(
          html: '<h2>My First Vision</h2>',
          text: 'My First Vision',
          kind: 'heading',
          bodyOrder: 42,
        ),
      ],
      spineIndex: 3,
    );
    final navItem = LibraryCatalogNavigationItem(
      id: 'first-vision',
      parentId: null,
      label: 'My First Vision',
      href: 'OEBPS/early-writings.xhtml',
      anchorId: null,
      spineIndex: 3,
      sortOrder: 8,
      depth: 0,
      navType: 'toc',
      contentKind: 'body_subsection',
      isFrontMatter: false,
      isBodyStart: false,
      // Deliberately from the TOC ordering domain, not the text-block domain.
      bodyOrder: 8,
    );

    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItem,
        sections: [section],
      ),
      'body:42',
    );
    expect(
      libraryReaderNavigationItemTargetsSectionStart(
        navItem: navItem,
        sections: [section],
      ),
      isFalse,
    );
  });

  test('subheadings split into sections with one href resolve by anchor', () {
    const sharedHref = 'OEBPS/content02.xhtml';
    const sections = <LibraryBookSection>[
      LibraryBookSection(
        entryName: sharedHref,
        title: 'Historical Prologue',
        paragraphs: <String>['Opening text.'],
        blocks: <LibraryBookBlock>[
          LibraryBookBlock(
            html: '<h2>Historical Prologue</h2>',
            text: 'Historical Prologue',
            kind: 'heading',
            anchorId: 'content02_heading_1_historical_prologue',
          ),
        ],
        spineIndex: 7,
      ),
      LibraryBookSection(
        entryName: sharedHref,
        title: 'The Great Advent Awakening',
        paragraphs: <String>['Awakening text.'],
        blocks: <LibraryBookBlock>[
          LibraryBookBlock(
            html: '<h4>The Great Advent Awakening</h4>',
            text: 'The Great Advent Awakening',
            kind: 'heading',
            anchorId: 'content02_heading_6_the_great_advent_awakening',
          ),
        ],
        spineIndex: 7,
      ),
      LibraryBookSection(
        entryName: sharedHref,
        title: 'Truths Confirmed by Vision',
        paragraphs: <String>['Confirmation text.'],
        blocks: <LibraryBookBlock>[
          LibraryBookBlock(
            html: '<h4>Truths Confirmed by Vision</h4>',
            text: 'Truths Confirmed by Vision',
            kind: 'heading',
            anchorId: 'content02_heading_40_truths_confirmed_by_vision',
          ),
        ],
        spineIndex: 7,
      ),
    ];
    const navItem = LibraryCatalogNavigationItem(
      id: 'truths-confirmed',
      parentId: 'historical-prologue',
      label: 'Truths Confirmed by Vision',
      href: sharedHref,
      anchorId: 'content02_heading_40_truths_confirmed_by_vision',
      spineIndex: 7,
      sortOrder: 3007,
      depth: 1,
      navType: 'body',
      contentKind: 'body_subsection',
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: 40,
    );

    expect(
      libraryReaderContentsTargetKeyForNavigationItem(
        navItem: navItem,
        sections: sections,
      ),
      'anchor:content02_heading_40_truths_confirmed_by_vision',
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

  test(
    'empty Preface contents entry is hidden while readable Preface stays',
    () {
      final emptyPreface = LibraryBookSection(
        entryName: 'preface.xhtml',
        title: 'PREFACE.',
        paragraphs: const <String>[],
        blocks: const <LibraryBookBlock>[],
        spineIndex: 1,
      );
      final readablePreface = LibraryBookSection(
        entryName: 'preface-readable.xhtml',
        title: 'PREFACE.',
        paragraphs: const <String>['This preface introduces the book.'],
        blocks: const <LibraryBookBlock>[
          LibraryBookBlock(
            html: '<p>This preface introduces the book.</p>',
            text: 'This preface introduces the book.',
            kind: 'paragraph',
            bodyOrder: 1,
          ),
        ],
        spineIndex: 1,
      );
      final prefaceNav = LibraryCatalogNavigationItem(
        id: 'preface',
        parentId: null,
        label: 'PREFACE.',
        href: 'preface.xhtml',
        anchorId: null,
        spineIndex: 1,
        sortOrder: 1,
        depth: 0,
        navType: 'toc',
        contentKind: 'preface',
        isFrontMatter: true,
        isBodyStart: false,
        bodyOrder: 1,
      );

      expect(
        libraryReaderShouldHideEmptyPrefaceContentsEntry(
          navItem: prefaceNav,
          sections: [emptyPreface],
        ),
        isTrue,
      );
      expect(
        libraryReaderShouldHideEmptyPrefaceContentsEntry(
          navItem: prefaceNav,
          sections: [readablePreface],
        ),
        isFalse,
      );
    },
  );

  test(
    'an empty leaf shell normalizes to the readable descendant in the same branch',
    () {
      final shell = LibraryCatalogNavigationItem(
        id: 'shell',
        parentId: null,
        label: 'OCTOBER 17, 1895.',
        href: 'shell.xhtml',
        anchorId: null,
        spineIndex: 1,
        sortOrder: 1,
        depth: 0,
        navType: 'toc',
        contentKind: null,
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 1,
      );
      final studies = LibraryCatalogNavigationItem(
        id: 'studies',
        parentId: 'shell',
        label: 'STUDIES IN ROMANS.',
        href: 'studies.xhtml',
        anchorId: null,
        spineIndex: 2,
        sortOrder: 2,
        depth: 1,
        navType: 'toc',
        contentKind: null,
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 2,
      );
      final readable = LibraryCatalogNavigationItem(
        id: 'october17_readable',
        parentId: 'studies',
        label: 'OCTOBER 17, 1895.',
        href: 'october17.xhtml',
        anchorId: null,
        spineIndex: 3,
        sortOrder: 3,
        depth: 2,
        navType: 'toc',
        contentKind: null,
        isFrontMatter: false,
        isBodyStart: false,
        bodyOrder: 3,
      );
      final sections = <LibraryBookSection>[
        const LibraryBookSection(
          entryName: 'shell.xhtml',
          title: 'OCTOBER 17, 1895.',
          paragraphs: <String>[],
          blocks: <LibraryBookBlock>[],
          spineIndex: 1,
        ),
        const LibraryBookSection(
          entryName: 'studies.xhtml',
          title: 'STUDIES IN ROMANS.',
          paragraphs: <String>[],
          blocks: <LibraryBookBlock>[],
          spineIndex: 2,
        ),
        const LibraryBookSection(
          entryName: 'october17.xhtml',
          title: 'OCTOBER 17, 1895.',
          paragraphs: <String>['Under this heading it is proposed to conduct'],
          blocks: <LibraryBookBlock>[
            LibraryBookBlock(
              html: '<p>Under this heading it is proposed to conduct</p>',
              text: 'Under this heading it is proposed to conduct',
              kind: 'paragraph',
            ),
          ],
          spineIndex: 3,
        ),
      ];
      final tree = buildLibraryNavigationTree([shell, studies, readable]);

      final normalized = libraryReaderVisibleContentsNavigationItem(
        navItem: shell,
        tree: tree,
        sections: sections,
      );
      expect(normalized?.id, readable.id);
      expect(normalized?.href, 'october17.xhtml');
    },
  );

  test('Chapter 1 structural navigation stays visible as its own identity', () {
    final chapter1 = LibraryCatalogNavigationItem(
      id: 'chapter1',
      parentId: null,
      label: 'CHAPTER 1.',
      href: 'chapter1.xhtml',
      anchorId: null,
      spineIndex: 1,
      sortOrder: 1,
      depth: 0,
      navType: 'toc',
      contentKind: 'chapter',
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: 1,
    );
    final studies = LibraryCatalogNavigationItem(
      id: 'studies',
      parentId: 'chapter1',
      label: 'STUDIES IN ROMANS.',
      href: 'studies.xhtml',
      anchorId: null,
      spineIndex: 2,
      sortOrder: 2,
      depth: 1,
      navType: 'toc',
      contentKind: null,
      isFrontMatter: false,
      isBodyStart: false,
      bodyOrder: 2,
    );
    final sections = <LibraryBookSection>[
      const LibraryBookSection(
        entryName: 'chapter1.xhtml',
        title: 'CHAPTER 1.',
        paragraphs: <String>[],
        blocks: <LibraryBookBlock>[],
        spineIndex: 1,
      ),
      const LibraryBookSection(
        entryName: 'studies.xhtml',
        title: 'STUDIES IN ROMANS.',
        paragraphs: <String>[],
        blocks: <LibraryBookBlock>[],
        spineIndex: 2,
      ),
    ];
    final tree = buildLibraryNavigationTree([chapter1, studies]);

    final normalized = libraryReaderVisibleContentsNavigationItem(
      navItem: chapter1,
      tree: tree,
      sections: sections,
    );
    expect(normalized?.id, chapter1.id);
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

  group('libraryReaderFirstReadableDescendant', () {
    // WOR-shaped hierarchy:
    // Waggoner on Romans
    //   Preface (heading-only, no descendant)
    //   Chapter 1 (heading-only)
    //     Studies in Romans (heading-only)
    //       October 17, 1895 (readable)
    //   Chapter 2 (readable, sibling of Chapter 1)
    LibraryBookSection headingOnlySection(
      String entryName,
      String title,
      int spineIndex,
    ) {
      return LibraryBookSection(
        entryName: entryName,
        title: title,
        paragraphs: const <String>[],
        blocks: const <LibraryBookBlock>[],
        spineIndex: spineIndex,
      );
    }

    LibraryBookSection readableSection(
      String entryName,
      String title,
      String bodyText,
      int spineIndex,
    ) {
      return LibraryBookSection(
        entryName: entryName,
        title: title,
        paragraphs: <String>[bodyText],
        blocks: <LibraryBookBlock>[
          LibraryBookBlock(
            html: '<p>$bodyText</p>',
            text: bodyText,
            kind: 'paragraph',
          ),
        ],
        spineIndex: spineIndex,
      );
    }

    LibraryCatalogNavigationItem navItem({
      required String id,
      String? parentId,
      required String label,
      required String href,
      required int sortOrder,
      int depth = 0,
    }) {
      return LibraryCatalogNavigationItem(
        id: id,
        parentId: parentId,
        label: label,
        href: href,
        anchorId: null,
        spineIndex: sortOrder,
        sortOrder: sortOrder,
        depth: depth,
        navType: 'toc',
        contentKind: null,
        isFrontMatter: label == 'PREFACE.',
        isBodyStart: false,
        bodyOrder: sortOrder,
      );
    }

    final preface = headingOnlySection('preface.html', 'PREFACE.', 1);
    final chapter1 = headingOnlySection('chapter1.html', 'CHAPTER 1.', 2);
    final studies = headingOnlySection('studies.html', 'STUDIES IN ROMANS.', 3);
    final october17 = readableSection(
      'october17.html',
      'OCTOBER 17, 1895.',
      'The Salutation opens the study of Romans.',
      4,
    );
    final chapter2 = readableSection(
      'chapter2.html',
      'CHAPTER 2.',
      'Chapter two body text.',
      5,
    );

    final sections = <LibraryBookSection>[
      preface,
      chapter1,
      studies,
      october17,
      chapter2,
    ];

    final navPreface = navItem(
      id: 'preface',
      label: 'PREFACE.',
      href: 'preface.html',
      sortOrder: 1,
    );
    final navChapter1 = navItem(
      id: 'chapter1',
      label: 'CHAPTER 1.',
      href: 'chapter1.html',
      sortOrder: 2,
    );
    final navStudies = navItem(
      id: 'studies',
      parentId: 'chapter1',
      label: 'STUDIES IN ROMANS.',
      href: 'studies.html',
      sortOrder: 3,
      depth: 1,
    );
    final navOctober17 = navItem(
      id: 'october17',
      parentId: 'studies',
      label: 'OCTOBER 17, 1895.',
      href: 'october17.html',
      sortOrder: 4,
      depth: 2,
    );
    final navChapter2 = navItem(
      id: 'chapter2',
      label: 'CHAPTER 2.',
      href: 'chapter2.html',
      sortOrder: 5,
    );

    final navigationItems = <LibraryCatalogNavigationItem>[
      navPreface,
      navChapter1,
      navStudies,
      navOctober17,
      navChapter2,
    ];

    final tree = buildLibraryNavigationTree(navigationItems);

    test('a heading-only Chapter node with a readable descendant resolves '
        'through the intervening structural heading to the first readable '
        'section', () {
      final chain = libraryReaderFirstReadableDescendant(
        navItem: navChapter1,
        tree: tree,
        sections: sections,
      );

      expect(chain, isNotNull);
      expect(chain!.headingSections.map((s) => s.entryName), <String>[
        'studies.html',
      ]);
      expect(chain.readableSection.entryName, 'october17.html');
      expect(chain.readableSection.blocks, isNotEmpty);
    });

    test('selecting Studies in Romans directly resolves the same October 17 '
        'descendant with no intervening headings', () {
      final chain = libraryReaderFirstReadableDescendant(
        navItem: navStudies,
        tree: tree,
        sections: sections,
      );

      expect(chain, isNotNull);
      expect(chain!.headingSections, isEmpty);
      expect(chain.readableSection.entryName, 'october17.html');
    });

    test('automatic readable-leaf transition preserves its structural heading '
        'path in document order', () {
      final headings = libraryReaderComposedHeadingSections(
        navItem: navOctober17,
        tree: tree,
        sections: sections,
      );

      expect(headings.map((section) => section.title), <String>[
        'CHAPTER 1.',
        'STUDIES IN ROMANS.',
        'OCTOBER 17, 1895.',
      ]);
    });

    test('automatic transition into Chapter 2 shows Chapter 2 before body', () {
      final chapter2Heading = headingOnlySection(
        'chapter2-heading.html',
        'CHAPTER 2.',
        20,
      );
      final chapter2Body = readableSection(
        'chapter2-body.html',
        'THE SEVEN CHURCHES',
        'Chapter two body text.',
        21,
      );
      final chapter2HeadingNav = navItem(
        id: 'chapter2-heading',
        label: 'CHAPTER 2.',
        href: 'chapter2-heading.html',
        sortOrder: 20,
      );
      final chapter2BodyNav = navItem(
        id: 'chapter2-body',
        parentId: 'chapter2-heading',
        label: 'THE SEVEN CHURCHES',
        href: 'chapter2-body.html',
        sortOrder: 21,
        depth: 1,
      );
      final chapter2Tree = buildLibraryNavigationTree([
        chapter2HeadingNav,
        chapter2BodyNav,
      ]);

      final headings = libraryReaderComposedHeadingSections(
        navItem: chapter2BodyNav,
        tree: chapter2Tree,
        sections: [chapter2Heading, chapter2Body],
      );
      expect(headings.map((section) => section.title), <String>[
        'CHAPTER 2.',
        'THE SEVEN CHURCHES',
      ]);
      expect(headings.last.paragraphs.single, 'Chapter two body text.');
    });

    test(
      'continuous scroll does not reprint a heading-only ancestor already '
      'shown by the immediately preceding readable unit '
      '(regression: "APPENDIX A" printing twice before its nested '
      '"OPEN LETTER" subsection)',
      () {
        final chapter2Heading = headingOnlySection(
          'chapter2-heading.html',
          'CHAPTER 2.',
          20,
        );
        final chapter2Body = readableSection(
          'chapter2-body.html',
          'THE SEVEN CHURCHES',
          'Chapter two body text.',
          21,
        );
        final chapter2HeadingNav = navItem(
          id: 'chapter2-heading',
          label: 'CHAPTER 2.',
          href: 'chapter2-heading.html',
          sortOrder: 20,
        );
        final chapter2BodyNav = navItem(
          id: 'chapter2-body',
          parentId: 'chapter2-heading',
          label: 'THE SEVEN CHURCHES',
          href: 'chapter2-body.html',
          sortOrder: 21,
          depth: 1,
        );
        final chapter2Tree = buildLibraryNavigationTree([
          chapter2HeadingNav,
          chapter2BodyNav,
        ]);
        final chapter2Sections = [chapter2Heading, chapter2Body];

        // Unit 1: the ancestor's own continuous-scroll unit — no preceding
        // unit shares any of its heading path, so nothing is stripped.
        final previousUnitHeadings = libraryReaderComposedHeadingSections(
          navItem: chapter2HeadingNav,
          tree: chapter2Tree,
          sections: chapter2Sections,
        );
        final firstUnit = libraryReaderContinuousUnitHeadings(
          composedHeadings: previousUnitHeadings,
          previousComposedHeadings: const <LibraryBookSection>[],
        );
        expect(firstUnit.map((section) => section.title), <String>[
          'CHAPTER 2.',
        ]);

        // Unit 2: the nested body's own composed path re-includes "CHAPTER
        // 2." as its ancestor. Since unit 1 already printed it, it must be
        // dropped here — only the newly-entered "THE SEVEN CHURCHES" heading
        // should remain.
        final currentUnitComposed = libraryReaderComposedHeadingSections(
          navItem: chapter2BodyNav,
          tree: chapter2Tree,
          sections: chapter2Sections,
        );
        final secondUnit = libraryReaderContinuousUnitHeadings(
          composedHeadings: currentUnitComposed,
          previousComposedHeadings: previousUnitHeadings,
        );
        expect(secondUnit.map((section) => section.title), <String>[
          'THE SEVEN CHURCHES',
        ]);
      },
    );

    test('structural heading and readable descendant are composed once', () {
      final chain = libraryReaderFirstReadableDescendant(
        navItem: navChapter1,
        tree: tree,
        sections: sections,
      );
      final headings = libraryReaderComposedHeadingSections(
        navItem: navChapter1,
        tree: tree,
        sections: sections,
        descendantChain: chain,
      );

      expect(headings.map((section) => section.entryName), <String>[
        'chapter1.html',
        'studies.html',
        'october17.html',
      ]);
      expect(
        headings.where((section) => section.entryName == 'october17.html'),
        hasLength(1),
      );
    });

    test('manual direct selection and automatic continuation have the same '
        'visible heading path', () {
      final manual = libraryReaderComposedHeadingSections(
        navItem: navOctober17,
        tree: tree,
        sections: sections,
      );
      final automatic = libraryReaderComposedHeadingSections(
        navItem: tree.items.firstWhere((item) => item.id == 'october17'),
        tree: tree,
        sections: sections,
      );
      expect(
        automatic.map((section) => section.entryName),
        manual.map((section) => section.entryName),
      );
    });

    test('genuinely distinct repeated headings remain distinct by href', () {
      final repeatedSections = <LibraryBookSection>[
        headingOnlySection('part-a.html', 'INTRODUCTION', 10),
        readableSection('part-b.html', 'INTRODUCTION', 'Second body', 11),
      ];
      final repeatedParent = navItem(
        id: 'part-a',
        label: 'INTRODUCTION',
        href: 'part-a.html',
        sortOrder: 10,
      );
      final repeatedChild = navItem(
        id: 'part-b',
        parentId: 'part-a',
        label: 'INTRODUCTION',
        href: 'part-b.html',
        sortOrder: 11,
        depth: 1,
      );
      final repeatedTree = buildLibraryNavigationTree([
        repeatedParent,
        repeatedChild,
      ]);

      final headings = libraryReaderComposedHeadingSections(
        navItem: repeatedChild,
        tree: repeatedTree,
        sections: repeatedSections,
      );
      expect(headings.map((section) => section.entryName), <String>[
        'part-a.html',
        'part-b.html',
      ]);
    });

    test('Preface with no readable subtree resolves to null and does not '
        'redirect to Chapter 1 or any other content', () {
      final chain = libraryReaderFirstReadableDescendant(
        navItem: navPreface,
        tree: tree,
        sections: sections,
      );

      expect(chain, isNull);
    });

    test('a heading-only node never borrows a sibling chapter\'s content when '
        'its own subtree has no readable descendant', () {
      // Studies in Romans' only child (October 17) is temporarily removed
      // from the section list so Chapter 1's subtree has no readable
      // section at all; Chapter 2 (a sibling, readable) must never be used.
      final sectionsWithoutOctober = <LibraryBookSection>[
        preface,
        chapter1,
        studies,
        chapter2,
      ];

      final chain = libraryReaderFirstReadableDescendant(
        navItem: navChapter1,
        tree: tree,
        sections: sectionsWithoutOctober,
      );

      expect(chain, isNull);
    });

    test(
      'a heading-only node never crosses into the next chapter\'s subtree',
      () {
        final chain = libraryReaderFirstReadableDescendant(
          navItem: navChapter1,
          tree: tree,
          sections: sections,
        );

        expect(chain, isNotNull);
        expect(chain!.readableSection.entryName, isNot('chapter2.html'));
        expect(
          chain.headingSections.map((s) => s.entryName),
          isNot(contains('chapter2.html')),
        );
      },
    );

    test('first open at Chapter 1 composes into a useful readable section '
        'rather than staying blank', () {
      final structuralSections = libraryReaderSectionsWithHeadingOnlyNavigation(
        sections: sections,
        navigationItems: navigationItems,
      );
      final item = LibraryCatalogItem.fromRow(const <String, Object?>{
        'id': 'wor-test',
        'title': 'Waggoner on Romans',
        'file_name': 'wor.epub',
        'relative_path': 'Books/wor.epub',
      });

      final initialIndex = libraryReaderInitialSectionIndex(
        item: item,
        sections: structuralSections,
        navigationItems: navigationItems,
        devotionalMode: false,
      );
      final selectedSection = structuralSections[initialIndex];
      expect(selectedSection.title, 'CHAPTER 1.');
      expect(selectedSection.blocks, isEmpty);

      final chain = libraryReaderFirstReadableDescendant(
        navItem: navChapter1,
        tree: tree,
        sections: structuralSections,
      );
      expect(chain, isNotNull);
      expect(chain!.readableSection.entryName, 'october17.html');
    });

    test(
      'first open preserves Chapter 1 anchor when title shares its spine',
      () {
        final item = LibraryCatalogItem.fromRow(const <String, Object?>{
          'id': 'american-papacy',
          'title': 'The American Papacy',
          'file_name': 'american-papacy.epub',
          'relative_path': 'ImportedPioneerEpubs/american-papacy.epub',
        });
        final sharedSection = LibraryBookSection(
          entryName: 'text/book.xhtml',
          title: 'The American Papacy',
          paragraphs: const ['The American Papacy', 'Chapter 1 body text.'],
          blocks: const [
            LibraryBookBlock(
              html: '<h1>The American Papacy</h1>',
              text: 'The American Papacy',
              kind: 'heading',
              anchorId: 'title',
            ),
            LibraryBookBlock(
              html: '<h2>Chapter 1</h2>',
              text: 'Chapter 1',
              kind: 'heading',
              anchorId: 'chapter-1',
            ),
          ],
          spineIndex: 1,
        );
        final navigation = <LibraryCatalogNavigationItem>[
          const LibraryCatalogNavigationItem(
            id: 'title',
            parentId: null,
            label: 'The American Papacy',
            href: 'text/book.xhtml',
            anchorId: 'title',
            spineIndex: 1,
            sortOrder: 1,
            depth: 0,
            navType: 'toc',
            contentKind: 'title',
            isFrontMatter: false,
            isBodyStart: false,
            bodyOrder: 1,
          ),
          const LibraryCatalogNavigationItem(
            id: 'chapter-1',
            parentId: null,
            label: 'Chapter 1',
            href: 'text/book.xhtml#chapter-1',
            anchorId: 'chapter-1',
            spineIndex: 1,
            sortOrder: 2,
            depth: 0,
            navType: 'toc',
            contentKind: 'chapter',
            isFrontMatter: false,
            isBodyStart: true,
            bodyOrder: 2,
          ),
        ];

        final initialSection = libraryReaderInitialSectionIndex(
          item: item,
          sections: [sharedSection],
          navigationItems: navigation,
          devotionalMode: false,
        );
        expect(initialSection, 0);
        expect(
          libraryReaderInitialNavigationIndex(
            item: item,
            sections: [sharedSection],
            navigationItems: navigation,
            initialSectionIndex: initialSection,
            hasExplicitInitialLocation: false,
          ),
          1,
        );

        final previouslyOpenedAtTitle =
            LibraryCatalogItem.fromRow(const <String, Object?>{
              'id': 'american-papacy-saved-title',
              'title': 'The American Papacy',
              'file_name': 'american-papacy.epub',
              'relative_path': 'ImportedPioneerEpubs/american-papacy.epub',
              'last_opened': '2026-08-04T00:00:00.000Z',
              'epub_href': 'text/book.xhtml#title',
              'spine_index': 1,
            });
        expect(
          libraryReaderSavedLocationTargetsFrontMatter(
            item: previouslyOpenedAtTitle,
            sections: [sharedSection],
            navigationItems: navigation,
          ),
          isTrue,
        );
        expect(
          libraryReaderInitialNavigationIndex(
            item: previouslyOpenedAtTitle,
            sections: [sharedSection],
            navigationItems: navigation,
            initialSectionIndex: 0,
            hasExplicitInitialLocation: false,
          ),
          1,
        );
      },
    );

    test('genuine saved progress on an already-readable section resumes '
        'exactly and never engages descendant composition', () {
      final item = LibraryCatalogItem.fromRow(const <String, Object?>{
        'id': 'wor-test-resume',
        'title': 'Waggoner on Romans',
        'file_name': 'wor.epub',
        'relative_path': 'Books/wor.epub',
        'last_opened': '2026-07-08T00:00:00.000Z',
        'epub_href': 'october17.html',
        'spine_index': 4,
        'paragraph_index': 1,
      });

      final resumedIndex = libraryReaderInitialSectionIndex(
        item: item,
        sections: sections,
        navigationItems: navigationItems,
        devotionalMode: false,
      );

      expect(sections[resumedIndex].entryName, 'october17.html');
      // The resumed section already has readable blocks, so the reader
      // never needs to resolve a descendant chain for it.
      expect(sections[resumedIndex].blocks, isNotEmpty);
    });

    test(
      'saved EGW front matter is ignored in favor of substantive content',
      () {
        final item = LibraryCatalogItem.fromRow(const <String, Object?>{
          'id': 'confrontation',
          'title': 'Confrontation',
          'file_name': 'con.epub',
          'relative_path': 'ePubs/EGW/EGW_Books/con.epub',
          'last_opened': '2026-08-04T00:00:00.000Z',
          'epub_href': 'information.xhtml',
          'spine_index': 1,
        });
        const frontMatter = LibraryBookSection(
          entryName: 'information.xhtml',
          title: 'Information about this Book',
          paragraphs: ['ISBN: 978-1-61253-711-5'],
          blocks: [
            LibraryBookBlock(
              html: '<p>ISBN: 978-1-61253-711-5</p>',
              text: 'ISBN: 978-1-61253-711-5',
              kind: 'paragraph',
            ),
          ],
          spineIndex: 1,
        );
        const firstChapter = LibraryBookSection(
          entryName: 'chapter1.xhtml',
          title: 'Confrontation in the Desert',
          paragraphs: ['Substantive chapter text.'],
          blocks: [
            LibraryBookBlock(
              html: '<p>Substantive chapter text.</p>',
              text: 'Substantive chapter text.',
              kind: 'paragraph',
            ),
          ],
          spineIndex: 2,
        );
        const navigation = <LibraryCatalogNavigationItem>[
          LibraryCatalogNavigationItem(
            id: 'information',
            parentId: null,
            label: 'Information about this Book',
            href: 'information.xhtml',
            anchorId: null,
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
            label: 'Confrontation in the Desert',
            href: 'chapter1.xhtml',
            anchorId: null,
            spineIndex: 2,
            sortOrder: 2,
            depth: 0,
            navType: 'toc',
            contentKind: 'chapter',
            isFrontMatter: false,
            isBodyStart: true,
            bodyOrder: 2,
          ),
        ];

        expect(
          libraryReaderInitialSectionIndex(
            item: item,
            sections: const [frontMatter, firstChapter],
            navigationItems: navigation,
            devotionalMode: false,
          ),
          1,
        );
      },
    );

    test('a readable leaf keeps its own body and a sibling leaf keeps its own '
        'body too', () {
      final debtor = readableSection(
        'debtor.html',
        'DEBTOR TO ALL.',
        'Debtor to All owns this paragraph.',
        4,
      );
      final questioning = readableSection(
        'questioning.html',
        'QUESTIONING THE TEXT.',
        'Questioning the Text owns its own paragraph.',
        5,
      );
      final leafSections = <LibraryBookSection>[
        preface,
        chapter1,
        studies,
        debtor,
        questioning,
      ];
      final leafDebtor = navItem(
        id: 'debtor',
        parentId: 'studies',
        label: 'DEBTOR TO ALL.',
        href: 'debtor.html',
        sortOrder: 4,
        depth: 2,
      );
      final leafQuestioning = navItem(
        id: 'questioning',
        parentId: 'studies',
        label: 'QUESTIONING THE TEXT.',
        href: 'questioning.html',
        sortOrder: 5,
        depth: 2,
      );
      final leafTree = buildLibraryNavigationTree([
        navPreface,
        navChapter1,
        navStudies,
        leafDebtor,
        leafQuestioning,
      ]);

      expect(
        libraryReaderFirstReadableDescendant(
          navItem: leafDebtor,
          tree: leafTree,
          sections: leafSections,
        ),
        isNull,
      );
      expect(
        libraryReaderFirstReadableDescendant(
          navItem: leafQuestioning,
          tree: leafTree,
          sections: leafSections,
        ),
        isNull,
      );
    });
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

        final importReport = await PioneerCapturedHtmlImportFolderService
            .instance
            .importConfiguredCloudFolder(
              selectedFolderPaths: [sourceFolder.path],
              archiveImportedFolders: false,
            );
        expect(importReport.importedCount, 1);
        final importedLibraryItemId = importReport.entries
            .singleWhere((entry) => entry.imported && entry.createdNew)
            .libraryItemId;

        final items = await LibraryCatalogService.instance.loadItems();
        importedItem = items.singleWhere(
          (item) => item.id == importedLibraryItemId,
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
            const MaterialApp(home: Scaffold(body: Text('Library Home'))),
          );
          await tester.pump();

          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => LibraryBookReaderScreen(
                item: importedItem,
                enableCanonicalReader: false,
              ),
            ),
          );
          await _pumpUntilFinder(
            tester,
            find.text('The Story of the Seer of Patmos'),
          );
          await _pumpTransient(tester);

          expect(find.text('Remove from Library'), findsNothing);
          expect(find.text('Repair Imported Book'), findsNothing);
          expect(find.text('Menu'), findsOneWidget);

          await tester.tap(find.text('Menu'));
          await _pumpTransient(tester);

          expect(find.text('Open eLibrary Setup'), findsOneWidget);
          expect(find.text('Maintenance'), findsOneWidget);
          expect(find.text('Remove Current Book from Library'), findsOneWidget);
          expect(find.text('Repair Current Imported Book'), findsOneWidget);
        },
      );

      testWidgets('reader body does not install per-word recognizers', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: LibraryBookReaderScreen(
              item: importedItem,
              enableCanonicalReader: false,
            ),
          ),
        );
        await _pumpUntilFinder(
          tester,
          find.text('The Story of the Seer of Patmos'),
        );

        var recognizerCount = 0;
        void visit(InlineSpan span) {
          if (span is! TextSpan) return;
          if (span.recognizer != null) recognizerCount += 1;
          for (final child in span.children ?? const <InlineSpan>[]) {
            visit(child);
          }
        }

        for (final richText in tester.widgetList<RichText>(
          find.byType(RichText),
        )) {
          visit(richText.text);
        }
        expect(recognizerCount, 0);
      });

      for (final width in [300.0, 390.0, 800.0]) {
        testWidgets(
          'eLibrary restores approved scrollable toolbar order at $width px',
          (tester) async {
            debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
            addTearDown(() {
              debugDefaultTargetPlatformOverride = null;
            });
            await tester.binding.setSurfaceSize(Size(width, 700));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            await tester.pumpWidget(
              MaterialApp(
                home: LibraryBookReaderScreen(
                  item: importedItem,
                  enableCanonicalReader: false,
                ),
              ),
            );
            await _pumpUntilFinder(
              tester,
              find.text('The Story of the Seer of Patmos'),
            );

            final safeArea = tester.getRect(
              find.byKey(const ValueKey('elibrary-toolbar-safe-area')),
            );
            final toolbar = tester.getRect(
              find.byKey(const ValueKey('elibrary-bottom-toolbar')),
            );
            final contents = tester.getRect(find.text('Contents'));
            final library = tester.getRect(find.text('Library').last);
            final theme = tester.getRect(find.byIcon(Icons.nightlight_round));
            final refs = tester.getRect(find.text('Show Ref Codes'));
            final font = tester.getRect(
              find.byKey(const ValueKey('elibrary-font-size-control')),
            );
            final tilt = tester.getRect(
              find.byKey(const ValueKey('elibrary-tilt-auto-scroll')),
            );

            expect(tilt.width, greaterThanOrEqualTo(44));
            expect(tilt.height, greaterThanOrEqualTo(44));
            // Autoscroll sits immediately after Contents (ahead of Library
            // and the theme toggle) since it's used far more often than
            // those on phones — see the reorder comment above the tilt
            // button in library_book_reader_screen.dart.
            expect(contents.left, lessThan(tilt.left));
            expect(tilt.left, lessThan(library.left));
            expect(library.left, lessThan(theme.left));
            expect(theme.left, lessThan(refs.left));
            expect(refs.left, lessThan(font.left));
            expect(contents.overlaps(tilt), isFalse);
            expect(toolbar.left, greaterThanOrEqualTo(safeArea.left));
            expect(toolbar.right, lessThanOrEqualTo(safeArea.right));

            final before = tilt;
            await tester.drag(
              find.byKey(const ValueKey('elibrary-secondary-toolbar-scroll')),
              const Offset(-260, 0),
            );
            await tester.pump(const Duration(milliseconds: 500));
            expect(
              tester.getRect(
                find.byKey(const ValueKey('elibrary-tilt-auto-scroll')),
              ),
              isNot(before),
            );
            debugDefaultTargetPlatformOverride = null;
            expect(tester.takeException(), isNull);
          },
        );
      }

      testWidgets(
        'Pioneer imported text exposes tilt-only autoscroll on Android phone',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() {
            debugDefaultTargetPlatformOverride = null;
          });
          await tester.binding.setSurfaceSize(const Size(390, 700));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          await tester.pumpWidget(
            MaterialApp(
              home: LibraryBookReaderScreen(
                item: importedItem,
                enableCanonicalReader: false,
              ),
            ),
          );
          await _pumpUntilFinder(
            tester,
            find.text('The Story of the Seer of Patmos'),
          );
          await _pumpTransient(tester);

          final autoscroll = find.byKey(const ValueKey('elibrary-auto-scroll'));
          expect(autoscroll, findsNothing);
          expect(find.byTooltip('Autoscroll'), findsNothing);
          expect(
            find.byKey(const ValueKey('elibrary-tilt-auto-scroll')),
            findsOneWidget,
          );

          debugDefaultTargetPlatformOverride = null;
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('macOS keyboard stays inactive while LibraryBookReaderScreen '
          'autoscroll is disabled', (tester) async {
        // LibraryBookReaderScreen._load() reads book content through
        // UserDatabase/AppSettingsService, which never resolves inside
        // this widget-test harness (a pre-existing gap: every other
        // testWidgets case in this file pumps the same screen and never
        // observes it finish either, they just don't assert on it). The
        // reader-level keyboard focus wiring and the MacReaderAutoScroll
        // controller are both created unconditionally in initState,
        // independent of that load, so the live keyboard path is fully
        // exercisable without waiting for it.
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
        });
        await tester.pumpWidget(
          MaterialApp(
            home: LibraryBookReaderScreen(
              item: importedItem,
              enableCanonicalReader: false,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final button = find.byKey(const ValueKey('mac-autoscroll-button'));
        expect(button, findsOneWidget);
        expect(find.byIcon(Icons.swap_vert), findsOneWidget);
        expect(
          find.byKey(const ValueKey('elibrary-auto-scroll')),
          findsNothing,
        );

        final statusFinder = find.byKey(
          const ValueKey('mac-autoscroll-status'),
        );
        expect(statusFinder, findsNothing);

        Future<void> press(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(key);
          await tester.sendKeyUpEvent(key);
          await tester.pump();
        }

        // The toolbar is disabled while this harness is still loading, so
        // keyboard autoscroll mode is off and arrows must not start it.
        await press(LogicalKeyboardKey.arrowDown);
        await press(LogicalKeyboardKey.arrowUp);
        expect(statusFinder, findsNothing);

        // The button toggle path and the settings-dialog long press are
        // covered directly against handleMacReaderAutoscrollKeyEvent in
        // mac_reader_autoscroll_controls_test.dart. This test's toolbar
        // button stays disabled here because _sections never finishes
        // loading in this widget-test harness (a separate, pre-existing
        // condition: no other testWidgets case in this file waits on
        // LibraryBookReaderScreen._load() either); that gate is unrelated
        // to the keyboard-focus defect this test targets.
        expect(tester.widget<IconButton>(button).onPressed, isNull);

        expect(tester.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

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

      testWidgets('remove from menu is DB-only and cancel does nothing', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: LibraryBookReaderScreen(
              item: importedItem,
              enableCanonicalReader: false,
            ),
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
          find.textContaining('This removes the imported database copy only.'),
        );

        expect(
          find.textContaining('This removes the imported database copy only.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Cancel'));
        await _pumpTransient(tester);
        expect(find.text('Menu'), findsOneWidget);
        expect(
          find.textContaining('This removes the imported database copy only.'),
          findsNothing,
        );
      });

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
            itemsAfterRemove.where((item) => item.id == importedItem.id),
            isEmpty,
          );
        },
      );

      test(
        'repair path fails gracefully when the source folder is missing',
        () async {
          await sourceFolder.delete(recursive: true);

          final report = await PioneerCapturedHtmlImportFolderService.instance
              .repairImportedCaptureClipperBook(libraryItemId: importedItem.id);

          expect(report, isNull);

          final itemsAfterRepair = await LibraryCatalogService.instance
              .loadItems();
          expect(
            itemsAfterRepair.where((item) => item.id == importedItem.id),
            isNotEmpty,
          );
        },
      );
    });
  });

  group('libraryReaderComposedHeadingSections – sibling headings sharing one '
      'physical file (SL27 shape)', () {
    // A.T. Jones' "The National Sunday Law" [SL27] stores every heading
    // (INTRODUCTION, ARGUMENT, "ARTICLE", APPENDIX A, ...) as anchors within
    // one shared OEBPS/content.xhtml, all as genuine top-level siblings with
    // no parent_id in the database. Each heading still gets its own
    // LibraryBookSection, keyed by the anchor-qualified entryName, exactly
    // like the text-block importer does.
    // Neither matching function can disambiguate these by href alone: the
    // fragment-preserving comparison in _navigationIndexForSectionIndex would
    // work, but libraryReaderComposedHeadingSections resolves sections via
    // _librarySectionIndexForNavigationItem, which strips the fragment via
    // _cleanNavigationHref before comparing — so, exactly as in production,
    // disambiguation here falls through to the per-heading spineIndex that
    // the text-block importer stamps on both the section and its nav item.
    LibraryBookSection headingSection(String anchorId, String title, int spineIndex) {
      return LibraryBookSection(
        entryName: 'OEBPS/content.xhtml#$anchorId',
        title: title,
        paragraphs: <String>['Body text for $title.'],
        blocks: const <LibraryBookBlock>[],
        spineIndex: spineIndex,
      );
    }

    LibraryCatalogNavigationItem siblingNavItem({
      required String id,
      required String label,
      required String anchorId,
      required int sortOrder,
    }) {
      return LibraryCatalogNavigationItem(
        id: id,
        parentId: null,
        label: label,
        href: 'OEBPS/content.xhtml#$anchorId',
        anchorId: anchorId,
        spineIndex: sortOrder,
        sortOrder: sortOrder,
        depth: 0,
        navType: 'toc',
        contentKind: null,
        isFrontMatter: false,
        isBodyStart: sortOrder == 1,
        bodyOrder: sortOrder,
      );
    }

    final introductionSection = headingSection(
      'heading-2-1',
      'INTRODUCTION',
      1,
    );
    final argumentSection = headingSection('heading-2-3', 'ARGUMENT', 3);
    final appendixASection = headingSection('heading-2-11', 'APPENDIX A', 11);

    final navIntroduction = siblingNavItem(
      id: 'introduction',
      label: 'INTRODUCTION',
      anchorId: 'heading-2-1',
      sortOrder: 1,
    );
    final navArgument = siblingNavItem(
      id: 'argument',
      label: 'ARGUMENT',
      anchorId: 'heading-2-3',
      sortOrder: 3,
    );
    final navAppendixA = siblingNavItem(
      id: 'appendix-a',
      label: 'APPENDIX A',
      anchorId: 'heading-2-11',
      sortOrder: 11,
    );

    final sections = <LibraryBookSection>[
      introductionSection,
      argumentSection,
      appendixASection,
    ];
    final navigationItems = <LibraryCatalogNavigationItem>[
      navIntroduction,
      navArgument,
      navAppendixA,
    ];
    final tree = buildLibraryNavigationTree(navigationItems);

    test(
      'scrolling into a later sibling replaces the heading trail instead of '
      'stacking the first sibling above it',
      () {
        final introductionHeadings = libraryReaderComposedHeadingSections(
          navItem: navIntroduction,
          tree: tree,
          sections: sections,
        );
        expect(introductionHeadings.map((s) => s.title), <String>[
          'INTRODUCTION',
        ]);

        final appendixHeadings = libraryReaderComposedHeadingSections(
          navItem: navAppendixA,
          tree: tree,
          sections: sections,
        );
        expect(appendixHeadings.map((s) => s.title), <String>['APPENDIX A']);
      },
    );

    test(
      'a middle sibling composes just its own heading, not the first '
      'sibling in the shared file',
      () {
        final argumentHeadings = libraryReaderComposedHeadingSections(
          navItem: navArgument,
          tree: tree,
          sections: sections,
        );
        expect(argumentHeadings.map((s) => s.title), <String>['ARGUMENT']);
      },
    );

    test(
      'a substantial "INTRODUCTION" chapter wrongly flagged front matter at '
      'import is not sunk to the bottom of the Contents list (regression: '
      'SL27\'s real Introduction sorting last, after APPENDIX B)',
      () {
        // Mirrors production: firstMeaningfulSectionIndex's front-matter-label
        // check treats "INTRODUCTION" as skippable-by-label for picking a
        // default open position, so import stamps is_front_matter=1 on it
        // even though — unlike a real cover or boilerplate title page — it
        // has substantial prose of its own, unlike the short placeholder
        // body introductionSection uses for the composed-heading tests above.
        final substantialIntroductionSection = LibraryBookSection(
          entryName: introductionSection.entryName,
          title: introductionSection.title,
          paragraphs: const <String>[
            'THIS pamphlet is a report of an argument made upon the national '
                'Sunday bill introduced by Senator Blair in the fiftieth '
                'Congress. It is not, however, exactly the argument that was '
                'made before the Senate Committee.',
          ],
          blocks: const <LibraryBookBlock>[],
          spineIndex: introductionSection.spineIndex,
        );
        final frontMatterFlaggedIntroduction = navIntroduction.copyWith(
          isFrontMatter: true,
        );

        final corrected = libraryReaderContentsDisplayNavigationItems(
          items: [frontMatterFlaggedIntroduction, navArgument, navAppendixA],
          sections: [
            substantialIntroductionSection,
            argumentSection,
            appendixASection,
          ],
          bookTitle: 'The National Sunday Law',
        );

        final correctedIntroduction = corrected.firstWhere(
          (item) => item.id == 'introduction',
        );
        expect(correctedIntroduction.isFrontMatter, isFalse);

        final tree = buildLibraryNavigationTree(corrected);
        expect(tree.items.map((item) => item.id), <String>[
          'introduction',
          'argument',
          'appendix-a',
        ]);
      },
    );

    test(
      'the default-open-position promotion also moves off a later section '
      'once the earlier one it was skipping past is corrected (regression: '
      'Introduction landing second, after the subtitle heading that was '
      'picked as the default open position, instead of first)',
      () {
        // Mirrors production exactly: INTRODUCTION (sort_order 1) is real
        // content wrongly flagged front matter by label; the book's own
        // verbose subtitle heading (sort_order 2) was picked instead as
        // isBodyStart because firstMeaningfulSectionIndex skipped past
        // INTRODUCTION by label without looking at its content.
        final substantialIntroductionSection = LibraryBookSection(
          entryName: introductionSection.entryName,
          title: introductionSection.title,
          paragraphs: const <String>[
            'THIS pamphlet is a report of an argument made upon the national '
                'Sunday bill introduced by Senator Blair in the fiftieth '
                'Congress. It is not, however, exactly the argument that was '
                'made before the Senate Committee.',
          ],
          blocks: const <LibraryBookBlock>[],
          spineIndex: introductionSection.spineIndex,
        );
        final frontMatterFlaggedIntroduction = navIntroduction.copyWith(
          isFrontMatter: true,
          isBodyStart: false,
        );
        final subtitleSection = LibraryBookSection(
          entryName: 'OEBPS/content.xhtml#heading-2-2',
          title: 'THE NATIONAL SUNDAY LAW ARGUMENT OF ALONZO T. JONES',
          paragraphs: const <String>['Senator Blair.—There are gentlemen...'],
          blocks: const <LibraryBookBlock>[],
          spineIndex: 2,
        );
        final navSubtitle = LibraryCatalogNavigationItem(
          id: 'subtitle',
          parentId: null,
          label: 'THE NATIONAL SUNDAY LAW ARGUMENT OF ALONZO T. JONES',
          href: 'OEBPS/content.xhtml#heading-2-2',
          anchorId: 'heading-2-2',
          spineIndex: 2,
          sortOrder: 2,
          depth: 0,
          navType: 'toc',
          contentKind: null,
          isFrontMatter: false,
          isBodyStart: true,
          bodyOrder: 2,
        );

        final corrected = libraryReaderContentsDisplayNavigationItems(
          items: [
            frontMatterFlaggedIntroduction,
            navSubtitle,
            navArgument,
            navAppendixA,
          ],
          sections: [
            substantialIntroductionSection,
            subtitleSection,
            argumentSection,
            appendixASection,
          ],
          bookTitle: 'The National Sunday Law',
        );

        final correctedIntroduction = corrected.firstWhere(
          (item) => item.id == 'introduction',
        );
        final correctedSubtitle = corrected.firstWhere(
          (item) => item.id == 'subtitle',
        );
        expect(correctedIntroduction.isFrontMatter, isFalse);
        expect(
          correctedIntroduction.isBodyStart,
          isTrue,
          reason:
              'the earliest non-front-matter item should keep the default '
              'open promotion',
        );
        expect(
          correctedSubtitle.isBodyStart,
          isFalse,
          reason:
              'a later section must not keep floating to the top once the '
              'earlier, genuinely substantial section is no longer treated '
              'as front matter',
        );

        final tree = buildLibraryNavigationTree(corrected);
        expect(tree.items.map((item) => item.id), <String>[
          'introduction',
          'subtitle',
          'argument',
          'appendix-a',
        ]);
      },
    );

    test(
      'a genuinely decorative front-matter item (no substantial content of '
      'its own) still sinks to the bottom of the Contents list',
      () {
        final coverSection = LibraryBookSection(
          entryName: 'OEBPS/content.xhtml#heading-2-0',
          title: 'Cover',
          paragraphs: const <String>[],
          blocks: const <LibraryBookBlock>[],
          spineIndex: 0,
        );
        final navCover = LibraryCatalogNavigationItem(
          id: 'cover',
          parentId: null,
          label: 'Cover',
          href: 'OEBPS/content.xhtml#heading-2-0',
          anchorId: 'heading-2-0',
          spineIndex: 0,
          sortOrder: 0,
          depth: 0,
          navType: 'toc',
          contentKind: null,
          isFrontMatter: true,
          isBodyStart: false,
          bodyOrder: 0,
        );

        final corrected = libraryReaderContentsDisplayNavigationItems(
          items: [navCover, navArgument, navAppendixA],
          sections: [coverSection, argumentSection, appendixASection],
          bookTitle: 'The National Sunday Law',
        );

        final correctedCover = corrected.firstWhere(
          (item) => item.id == 'cover',
        );
        expect(correctedCover.isFrontMatter, isTrue);

        final tree = buildLibraryNavigationTree(corrected);
        expect(tree.items.map((item) => item.id), <String>[
          'argument',
          'appendix-a',
          'cover',
        ]);
      },
    );
  });
}
