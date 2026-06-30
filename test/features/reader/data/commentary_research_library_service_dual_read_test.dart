import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
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

Future<void> _seedLibraryItem({
  required Database db,
  required String deviceId,
  required String itemId,
  required String title,
  required List<String> paragraphs,
  String fileName = 'Acts.epub',
  String relativePath = 'ePubs/EGW_Books/Acts.epub',
  String fileFormat = 'epub',
  String folderType = 'research',
  String sourceType = 'official_download',
  String collectionName = 'EGW_Books',
  bool addRefIndexRows = false,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('library_items', <String, Object?>{
    'id': itemId,
    'title': title,
    'file_name': fileName,
    'relative_path': relativePath,
    'file_format': fileFormat,
    'folder_type': folderType,
    'library_role': 'user_added',
    'collection_name': collectionName,
    'source_type': sourceType,
    'index_status': 'indexed',
    'created_at': now,
    'updated_at': now,
    'device_id': deviceId,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  for (var i = 0; i < paragraphs.length; i++) {
    await db.insert('library_text_blocks', <String, Object?>{
      'library_item_id': itemId,
      'epub_href': 'OEBPS/content01.xhtml',
      'spine_index': 1,
      'paragraph_index': i + 1,
      'paragraph_on_section': i + 1,
      'section_title': 'Chapter 1',
      'plain_text': paragraphs[i],
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (!addRefIndexRows) continue;
    await db.insert('elibrary_ref_index', <String, Object?>{
      'library_item_id': itemId,
      'work_key': 'test-work',
      'edition_key': 'test-edition',
      'edition_year': 1900,
      'book_title': title,
      'book_abbrev': 'TEST',
      'href': 'section_1.xhtml',
      'anchor_id': null,
      'paragraph_index': i + 1,
      'page_number': i + 1,
      'paragraph_on_page': i + 1,
      'ref_code': 'TEST ${i + 1}',
      'stable_ref': 'TEST ${i + 1}',
      'plain_text': paragraphs[i],
      'text_hash': null,
      'ref_source': sourceType,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late String deviceId;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('dual_read_support_');
    documentsDir = await Directory.systemTemp.createTemp(
      'dual_read_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp('dual_read_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    deviceId = await LocalSettingsStore.instance.ensureDeviceId();
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

  test('falls back to user.db text blocks when eLibrary.db is empty', () async {
    final userDb = await UserDatabase.instance.database;
    await ELibraryDatabase.instance.database;
    const itemId = 'acts-user';
    const paragraphs = <String>[
      'The church is God’s appointed agency for the salvation of men.',
      'Many and wonderful are the promises recorded in the Scriptures [10] regarding the church.',
      '“Ye are My witnesses, saith the Lord...”',
    ];

    await _seedLibraryItem(
      db: userDb,
      deviceId: deviceId,
      itemId: itemId,
      title: 'The Acts of the Apostles',
      paragraphs: paragraphs,
    );

    final sections = await CommentaryResearchLibraryService.instance
        .loadBookSections(
          filePath: p.join(libraryRootDir.path, 'missing', 'Acts.epub'),
          libraryItemId: itemId,
          includeFrontMatter: true,
        );

    expect(sections, isNotEmpty);
    expect(sections.first.blocks.map((block) => block.text), paragraphs);
    expect(
      sections.first.blocks.map((block) => block.referenceCode),
      const <String?>['AA 9.1', 'AA 9.2', 'AA 10.1'],
    );
  });

  test('prefers eLibrary.db text blocks when rows exist there', () async {
    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;
    const itemId = 'acts-elibrary';
    const userParagraphs = <String>[
      'User fallback paragraph one.',
      'User fallback paragraph two.',
    ];
    const eLibraryParagraphs = <String>[
      'eLibrary primary paragraph one.',
      'eLibrary primary paragraph two [10] with a marker.',
    ];

    await _seedLibraryItem(
      db: userDb,
      deviceId: deviceId,
      itemId: itemId,
      title: 'The Acts of the Apostles',
      paragraphs: userParagraphs,
    );
    await _seedLibraryItem(
      db: eLibraryDb,
      deviceId: deviceId,
      itemId: itemId,
      title: 'The Acts of the Apostles',
      paragraphs: eLibraryParagraphs,
    );

    final sections = await CommentaryResearchLibraryService.instance
        .loadBookSections(
          filePath: p.join(libraryRootDir.path, 'missing', 'Acts.epub'),
          libraryItemId: itemId,
          includeFrontMatter: true,
        );

    expect(sections, isNotEmpty);
    expect(
      sections.first.blocks.map((block) => block.text),
      eLibraryParagraphs,
    );
    expect(sections.first.blocks.first.referenceCode, isNotNull);
  });

  test(
    'loads DB-backed commentary research content even when source folders are missing',
    () async {
      final eLibraryDb = await ELibraryDatabase.instance.database;
      const itemId = 'dar-us-html';
      const paragraphs = <String>[
        'Section one paragraph one.',
        'Section one paragraph two [10].',
        'Section two paragraph one.',
      ];

      await _seedLibraryItem(
        db: eLibraryDb,
        deviceId: deviceId,
        itemId: itemId,
        title: 'Daniel and the Revelation',
        paragraphs: paragraphs,
        fileName: 'capture.html',
        relativePath: 'assets/scans/DAR/capture.html',
        fileFormat: 'html',
        folderType: 'research',
        sourceType: 'egw_html_capture',
        collectionName: 'Research',
        addRefIndexRows: true,
      );

      final section = await CommentaryResearchLibraryService.instance
          .loadSection(
            bookId: 1,
            chapter: 1,
            verse: 1,
            bookName: 'Genesis',
            folderType: 'research',
            folderLabel: 'Research',
            candidatePaths: [
              p.join(libraryRootDir.path, 'ePubs', 'Research'),
              p.join(libraryRootDir.path, 'PDFs', 'Research'),
            ],
            chapterWideMatches: true,
          );

      expect(section.files, isNotEmpty);
      expect(section.statusMessage, isNot(contains('Open eLibrary Setup')));
      expect(section.statusMessage, contains('Research'));

      final passage = await CommentaryResearchLibraryService.instance
          .loadPassage(bookId: 1, chapter: 1, verse: 1, bookName: 'Genesis');

      expect(passage.research.files, isNotEmpty);
      expect(
        passage.research.statusMessage,
        isNot(contains('Open eLibrary Setup')),
      );
      expect(passage.research.statusMessage, contains('Research'));
    },
  );

  test(
    'falls back to missing-folder diagnostics when no DB-backed content exists',
    () async {
      final section = await CommentaryResearchLibraryService.instance
          .loadSection(
            bookId: 1,
            chapter: 1,
            verse: 1,
            bookName: 'Genesis',
            folderType: 'research',
            folderLabel: 'Research',
            candidatePaths: [
              p.join(libraryRootDir.path, 'ePubs', 'Research'),
              p.join(libraryRootDir.path, 'PDFs', 'Research'),
            ],
            chapterWideMatches: true,
          );

      expect(section.files, isEmpty);
      expect(section.matches, isEmpty);
      expect(section.statusMessage, contains('imported yet'));
    },
  );

  test(
    'shows a clean empty-state message when baseline commentary folders exist but contain no files',
    () async {
      for (final relative in const [
        'ePubs/EGW',
        'PDFs/EGW',
        'ePubs/Commentaries',
        'PDFs/Commentaries',
        'ePubs/Research',
        'PDFs/Research',
      ]) {
        await Directory(
          p.join(libraryRootDir.path, relative),
        ).create(recursive: true);
      }

      final passage = await CommentaryResearchLibraryService.instance
          .loadPassage(bookId: 1, chapter: 1, verse: 1, bookName: 'Genesis');

      expect(
        passage.commentary.statusMessage,
        'No commentary files have been imported yet.',
      );
      expect(
        passage.research.statusMessage,
        'No research files have been imported yet.',
      );
    },
  );
}
