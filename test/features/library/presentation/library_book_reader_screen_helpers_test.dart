import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/presentation/library_book_reader_screen.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

LibraryCatalogItem _catalogItem({
  required String id,
  required String title,
  required String fileName,
  required String relativePath,
}) {
  return LibraryCatalogItem(
    id: id,
    title: title,
    author: null,
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
  String itemId,
  {
  required int paragraphIndex,
  required String anchor,
  required String fullParagraph,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'library_links',
    <String, Object?>{
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
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<Directory> _prepareIsolatedLibraryRoot() async {
  final sourceDbDir = Directory(
    '/Users/deanbowen/Development/StudyBible2/test/Databases',
  );
  final libraryRootDir = await Directory.systemTemp
      .createTemp('library_reader_refcodes_root_');
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

  group('section reference codes', () {
    late Directory supportDir;
    late Directory documentsDir;
    late Directory libraryRootDir;

    setUp(() async {
      supportDir = await Directory.systemTemp
          .createTemp('library_reader_refcodes_support_');
      documentsDir = await Directory.systemTemp
          .createTemp('library_reader_refcodes_documents_');
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

    test('falls back to user.db when eLibrary.db lacks section codes', () async {
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
    });
  });
}
