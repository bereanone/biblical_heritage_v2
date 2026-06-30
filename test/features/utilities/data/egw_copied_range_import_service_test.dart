import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_install_status_service.dart';
import 'package:studybible2/features/utilities/data/pioneer_source_catalog.dart';
import 'package:studybible2/features/utilities/data/pioneer_text_import_service.dart';

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

int _firstIntValue(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return 0;
  final value = rows.first.values.first;
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

const String _darCopiedRangeFixture = '''
Chapter 1 — Daniel in Captivity
DAR 24
VERSE 1. In the third year of the reign of Jehoiakim king of Judah...
DAR 24.1
WITH a directness characteristic of the prophet...
DAR 24.2
Paragraph without a copied-range ref.
DAR 25
The vision continues into the next page.
DAR 25.1

Chapter 2 — The Great Image
DAR 32
DANIEL was carried into captivity with the princes of Judah.
DAR 32.1
Another paragraph for the second chapter.
DAR 32.2
DAR 33
The closing paragraph bridges to the final page.
DAR 33.1
Final paragraph in the copied range.
DAR 33.2
''';

PioneerSourceWork _darWork() {
  return PioneerSourceWork(
    id: 'daniel_and_the_revelation',
    authorId: 'uriah_smith',
    authorName: 'Uriah Smith',
    sourceFamily: 'Pioneer',
    title: 'Daniel and the Revelation',
    abbreviation: 'DAR',
    group: 'Pioneer Authors',
    subgroup: 'Prophecy',
    availability: PioneerSourceAvailability.available,
    verified: true,
    catalogImportable: true,
    sourceType: 'readerPage',
    sourceUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
    collectionUrl: 'https://www.aplib.org/resources/pioneers-ebooks/',
    captureUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
    readerUrl: 'https://egwwritings.org/read?panels=p1297.2&index=0',
    directFileUrl: null,
    directFileType: null,
    sourceLabel: 'EGW Writings',
    notes: null,
  );
}

PioneerSourceCatalog _darCatalog() {
  return PioneerSourceCatalog.fromJson({
    'authors': [
      {
        'author_id': 'uriah_smith',
        'author_name': 'Uriah Smith',
        'source_family': 'Pioneer',
        'sort_key': 'uriah smith',
        'works': [
          {
            'work_id': 'daniel_and_the_revelation',
            'title': 'Daniel and the Revelation',
            'abbreviation': 'DAR',
            'group': 'Pioneer Authors',
            'subgroup': 'Prophecy',
            'availability_status': 'available',
            'source_type': 'readerPage',
            'source_family': 'EGW Writings',
            'source_url': 'https://egwwritings.org/read?panels=p1297.2&index=0',
            'source_label': 'EGW Writings',
            'verified': true,
            'importable': true,
          },
        ],
      },
    ],
  });
}

Future<void> _seedStaleDarEpubRows({
  required Database db,
  required String deviceId,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  const itemId =
      'library_item_research_pioneer_uriah_smith_daniel_and_the_revelation';

  await db.insert('library_items', {
    'id': itemId,
    'title': 'Daniel and the Revelation',
    'author': 'Uriah Smith',
    'file_name': 'DAR.html',
    'relative_path': 'ePubs/Research/Pioneer Authors/uriah_smith/DAR.html',
    'file_hash': 'stale-epub-hash',
    'file_size': 2355,
    'modified_at': null,
    'mime_type': 'text/html',
    'file_format': 'html',
    'folder_type': 'research',
    'library_role': 'research',
    'collection_name': 'Adventist Pioneer Library',
    'source_site': 'ellenwhiteaudio.org',
    'source_url':
        'https://ellenwhiteaudio.org/ebooks/en/smith/Daniel%20and%20the%20Revelation.epub',
    'cover_path': null,
    'date_added': now,
    'last_opened': null,
    'source_type': 'epub',
    'indexed_at': now,
    'index_status': 'indexed',
    'index_error': null,
    'epub_href': null,
    'epub_cfi': null,
    'anchor_id': null,
    'spine_index': null,
    'paragraph_index': null,
    'is_missing': 0,
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'device_id': deviceId,
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('library_navigation_items', {
    'id': 'nav_stale_dar_1',
    'library_item_id': itemId,
    'parent_id': null,
    'label': 'Response of History to the Prophecy of Daniel',
    'href': 'nav.xhtml',
    'anchor_id': null,
    'spine_index': 1,
    'sort_order': 1,
    'depth': 0,
    'nav_type': 'toc',
    'content_kind': 'chapter',
    'is_front_matter': 0,
    'is_body_start': 1,
    'body_order': 1,
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'device_id': deviceId,
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('library_navigation_items', {
    'id': 'nav_stale_dar_2',
    'library_item_id': itemId,
    'parent_id': null,
    'label': 'Appendix',
    'href': 'appendix.xhtml',
    'anchor_id': null,
    'spine_index': 2,
    'sort_order': 2,
    'depth': 0,
    'nav_type': 'toc',
    'content_kind': 'chapter',
    'is_front_matter': 0,
    'is_body_start': 0,
    'body_order': 2,
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'device_id': deviceId,
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('library_text_blocks', {
    'library_item_id': itemId,
    'epub_href': 'nav.xhtml',
    'spine_index': 1,
    'paragraph_index': 1,
    'paragraph_on_section': 1,
    'section_title': 'Response of History to the Prophecy of Daniel',
    'plain_text': 'W ITH an old EPUB artifact.',
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('library_text_blocks', {
    'library_item_id': itemId,
    'epub_href': 'appendix.xhtml',
    'spine_index': 2,
    'paragraph_index': 1,
    'paragraph_on_section': 1,
    'section_title': 'Appendix',
    'plain_text': 'Characteristics of the Sacred Writings.',
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('elibrary_ref_index', {
    'library_item_id': itemId,
    'work_key': itemId,
    'edition_key': null,
    'edition_year': null,
    'book_title': 'Daniel and the Revelation',
    'book_abbrev': 'DAR',
    'href': 'nav.xhtml',
    'anchor_id': null,
    'paragraph_index': 1,
    'page_number': 1,
    'paragraph_on_page': 1,
    'ref_code': 'DAR 1.1',
    'stable_ref': 'DAR 1.1',
    'plain_text': 'W ITH an old EPUB artifact.',
    'text_hash': 'stale-ref-hash',
    'ref_source': 'epub',
    'created_at': now,
    'updated_at': now,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('library_links', {
    'id': 'link_stale_dar_1',
    'library_item_id': itemId,
    'book_id': 27,
    'chapter': 1,
    'verse_start': 1,
    'verse_end': 1,
    'link_type': 'stale',
    'anchor': 'stale-anchor',
    'original_reference_text': 'Daniel 1:1',
    'confidence': 0.1,
    'parser_warning': 'stale EPUB link',
    'epub_href': 'nav.xhtml',
    'epub_cfi': null,
    'anchor_id': null,
    'spine_index': 1,
    'paragraph_index': 1,
    'full_paragraph': 'W ITH an old EPUB artifact.',
    'created_by': 'test',
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
    'device_id': deviceId,
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  await db.insert('elibrary_markups', {
    'id': 1,
    'library_item_id': itemId,
    'epub_href': 'nav.xhtml',
    'start_block_index': 0,
    'start_char_offset': 0,
    'end_block_index': 0,
    'end_char_offset': 5,
    'start_token_index': null,
    'end_token_index': null,
    'ref_start': 'DAR 1.1',
    'ref_end': 'DAR 1.1',
    'compact_ref': 'DAR 1.1',
    'selected_text_snapshot': 'W ITH',
    'markup_type': 'highlight',
    'color': '#ff0000',
    'note_text': 'stale EPUB markup',
    'created_at': now,
    'updated_at': now,
    'deleted_at': null,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('dar_import_support_');
    documentsDir = await Directory.systemTemp.createTemp('dar_import_docs_');
    libraryRootDir = await Directory.systemTemp.createTemp('dar_import_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
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

  test('imports the copied DAR range into the test eLibrary database', () async {
    final work = _darWork();
    final service = PioneerTextImportService.instance;
    final db = await ELibraryDatabase.instance.database;

    final firstResult = await service.importFromCopiedRange(
      work: work,
      text: _darCopiedRangeFixture,
      sourceUrl: work.sourceUrl,
      sourceLabel: work.sourceLabel,
    );

    expect(firstResult.workResults, hasLength(1));
    final firstWorkResult = firstResult.workResults.single;
    expect(firstWorkResult.isImported, isTrue);
    expect(firstWorkResult.requiresManualVerification, isTrue);
    expect(firstWorkResult.libraryItemId, work.copiedRangeLibraryItemId);
    expect(
      firstWorkResult.detail,
      allOf(
        contains('First captured ref: DAR 24.1'),
        contains('Last captured ref: DAR 33.2'),
      ),
    );

    final itemRows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [firstWorkResult.libraryItemId],
    );
    expect(itemRows, hasLength(1));
    expect(itemRows.single['index_status'], 'partially_imported');

    final navCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_navigation_items WHERE library_item_id = ?',
        [firstWorkResult.libraryItemId],
      ),
    );
    final textCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_text_blocks WHERE library_item_id = ?',
        [firstWorkResult.libraryItemId],
      ),
    );
    final refCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM elibrary_ref_index WHERE library_item_id = ?',
        [firstWorkResult.libraryItemId],
      ),
    );

    expect(navCount, firstWorkResult.insertedNavigationItems);
    expect(textCount, firstWorkResult.insertedTextBlocks);
    expect(refCount, firstWorkResult.insertedTextBlocks);
    expect(
      await db.query(
        'elibrary_ref_index',
        where: 'library_item_id = ? AND ref_code = ?',
        whereArgs: [firstWorkResult.libraryItemId, 'DAR 24.1'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'elibrary_ref_index',
        where: 'library_item_id = ? AND ref_code = ?',
        whereArgs: [firstWorkResult.libraryItemId, 'DAR 33.2'],
      ),
      hasLength(1),
    );

    final latestItem = await LibraryCatalogService.instance.loadItemById(
      firstWorkResult.libraryItemId,
    );
    expect(latestItem, isNotNull);
    expect(latestItem!.id, firstWorkResult.libraryItemId);
    expect(latestItem.sourceType, 'egw_copied_range');
    expect(latestItem.sourceSite, 'egwwritings.org');
    expect(latestItem.sourceUrl, work.sourceUrl);
    expect(latestItem.fileFormat, 'html');
    expect(latestItem.relativePath, contains('copied_range'));
    expect(latestItem.relativePath, endsWith('DAR.copied-range.html'));

    final bogusFile = File(
      p.join(libraryRootDir.path, latestItem.relativePath),
    );
    await bogusFile.parent.create(recursive: true);
    await bogusFile.writeAsString(
      '<html><body>Characteristics of the Sacred Writings W ITH old EPUB text.</body></html>',
      flush: true,
    );

    final loadedSections = await CommentaryResearchLibraryService.instance
        .loadBookSections(
          filePath: bogusFile.path,
          libraryItemId: latestItem.id,
          includeFrontMatter: true,
        );
    expect(loadedSections, isNotEmpty);
    expect(loadedSections.first.title, 'Chapter 1 — Daniel in Captivity');
    expect(loadedSections.first.blocks.first.referenceCode, 'DAR 24.1');
    expect(
      loadedSections.first.blocks.first.text,
      startsWith('VERSE 1. In the third year'),
    );
    expect(
      loadedSections.first.blocks.map((block) => block.text).join(' '),
      isNot(contains('W ITH')),
    );

    final navigationItems = await LibraryCatalogService.instance
        .loadNavigationItems(latestItem.id);
    expect(navigationItems, hasLength(2));
    expect(
      navigationItems.map((item) => item.label).toList(growable: false),
      containsAll(<String>[
        'Chapter 1 — Daniel in Captivity',
        'Chapter 2 — The Great Image',
      ]),
    );

    final installStatuses = await PioneerInstallStatusService.instance
        .inspectCatalog(_darCatalog());
    expect(
      installStatuses['daniel_and_the_revelation']!.statusLabel,
      'Partially imported',
    );
    expect(
      installStatuses['daniel_and_the_revelation']!.isVerifiedInstalled,
      isFalse,
    );

    final secondResult = await service.importFromCopiedRange(
      work: work,
      text: _darCopiedRangeFixture,
      sourceUrl: work.sourceUrl,
      sourceLabel: work.sourceLabel,
    );
    expect(secondResult.workResults.single.isSkipped, isTrue);
    expect(
      _firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM elibrary_ref_index WHERE library_item_id = ?',
          [firstWorkResult.libraryItemId],
        ),
      ),
      refCount,
    );

    final mutated = _darCopiedRangeFixture.replaceFirst(
      'WITH a directness',
      'WITH a different directness',
    );
    final conflictResult = await service.importFromCopiedRange(
      work: work,
      text: mutated,
      sourceUrl: work.sourceUrl,
      sourceLabel: work.sourceLabel,
    );
    expect(
      conflictResult.workResults.single.requiresManualVerification,
      isTrue,
    );
    expect(conflictResult.workResults.single.manualVerificationHint, isNotNull);

    expect(
      File(p.join(libraryRootDir.path, 'Databases', 'user.db')).existsSync(),
      isFalse,
    );
  });

  test('overwrites stale EPUB DAR rows before importing copied-range text', () async {
    final work = _darWork();
    final service = PioneerTextImportService.instance;
    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();

    await _seedStaleDarEpubRows(db: db, deviceId: deviceId);

    final result = await service.importFromCopiedRange(
      work: work,
      text: _darCopiedRangeFixture,
      sourceUrl: work.sourceUrl,
      sourceLabel: work.sourceLabel,
    );

    expect(result.workResults, hasLength(1));
    final workResult = result.workResults.single;
    expect(workResult.isImported, isTrue);
    expect(workResult.libraryItemId, work.copiedRangeLibraryItemId);

    final itemRows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: [workResult.libraryItemId],
    );
    expect(itemRows, hasLength(1));
    expect(itemRows.single['source_type'], 'egw_copied_range');
    expect(itemRows.single['source_site'], 'egwwritings.org');
    expect(itemRows.single['source_url'], work.sourceUrl);
    expect(itemRows.single['relative_path'], contains('copied_range'));
    expect(itemRows.single['relative_path'], endsWith('DAR.copied-range.html'));
    expect(
      itemRows.single['relative_path'],
      isNot(contains('ePubs/Research/Pioneer Authors/uriah_smith/DAR.html')),
    );

    final navCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_navigation_items WHERE library_item_id = ?',
        [workResult.libraryItemId],
      ),
    );
    final textCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_text_blocks WHERE library_item_id = ?',
        [workResult.libraryItemId],
      ),
    );
    final refCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM elibrary_ref_index WHERE library_item_id = ?',
        [workResult.libraryItemId],
      ),
    );
    final linkCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_links WHERE library_item_id = ?',
        [workResult.libraryItemId],
      ),
    );
    final markupCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM elibrary_markups WHERE library_item_id = ?',
        [work.stableLibraryItemId],
      ),
    );
    final staleStableTextCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_text_blocks WHERE library_item_id = ?',
        [work.stableLibraryItemId],
      ),
    );
    final staleStableActiveItemCount = _firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM library_items WHERE id = ? AND deleted_at IS NULL',
        [work.stableLibraryItemId],
      ),
    );

    expect(navCount, workResult.insertedNavigationItems);
    expect(textCount, workResult.insertedTextBlocks);
    expect(refCount, workResult.insertedTextBlocks);
    expect(linkCount, 0);
    expect(staleStableTextCount, 0);
    expect(staleStableActiveItemCount, 0);
    expect(
      markupCount,
      1,
      reason:
          'Overwrite should preserve user markup rows unless they are known import-generated rows.',
    );

    final firstRefs = await db.query(
      'elibrary_ref_index',
      columns: const ['ref_code', 'plain_text'],
      where: 'library_item_id = ?',
      whereArgs: [workResult.libraryItemId],
      orderBy: 'paragraph_index ASC',
      limit: 2,
    );
    expect(firstRefs, hasLength(2));
    expect(firstRefs[0]['ref_code'], 'DAR 24.1');
    expect(
      firstRefs[0]['plain_text'],
      startsWith('VERSE 1. In the third year'),
    );
    expect(
      _firstIntValue(
        await db.rawQuery(
          '''
          SELECT COUNT(*) FROM elibrary_ref_index
          WHERE library_item_id = ? AND plain_text LIKE 'WITH a directness characteristic%'
          ''',
          [workResult.libraryItemId],
        ),
      ),
      greaterThan(0),
    );
    expect(
      _firstIntValue(
        await db.rawQuery(
          '''
          SELECT COUNT(*) FROM library_text_blocks
          WHERE library_item_id = ? AND plain_text LIKE '%W ITH%'
          ''',
          [workResult.libraryItemId],
        ),
      ),
      0,
    );
  });
}
