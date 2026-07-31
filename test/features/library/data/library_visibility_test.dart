import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_item_availability.dart';
import 'package:studybible2/features/library/data/library_recent_items.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory rootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'library_visibility_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'library_visibility_documents_',
    );
    rootDir = await Directory.systemTemp.createTemp('library_visibility_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: rootDir.path);
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
    for (final dir in <Directory>[supportDir, documentsDir, rootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Future<void> seedItem({
    required String id,
    required String title,
    required String relativePath,
    String fileFormat = 'epub',
    String folderType = 'research',
    String collectionName = 'EGW_Books',
    String indexStatus = 'indexed',
    String? indexError,
    String? sourceWorkId,
    String? lastOpened,
    int navigationCount = 0,
    int readableBlockCount = 0,
  }) async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': title,
      'file_name': p.basename(relativePath),
      'relative_path': relativePath,
      'file_format': fileFormat,
      'folder_type': folderType,
      'library_role': 'research',
      'collection_name': collectionName,
      'source_type': 'official_download',
      'source_work_id': sourceWorkId,
      'index_status': indexStatus,
      'index_error': indexError,
      'last_opened': lastOpened,
      'date_added': now,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    for (var i = 0; i < navigationCount; i++) {
      await db.insert('library_navigation_items', <String, Object?>{
        'id': '${id}_nav_$i',
        'library_item_id': id,
        'label': 'Section $i',
        'sort_order': i,
        'depth': 0,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });
    }
    for (var i = 0; i < readableBlockCount; i++) {
      await db.insert('library_text_blocks', <String, Object?>{
        'library_item_id': id,
        'epub_href': 'chapter1.html',
        'paragraph_index': i,
        'paragraph_on_section': i,
        'plain_text': 'Some readable content for block $i.',
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  group('needs_attention placeholder EPUBs are hidden from normal library', () {
    test(
      'invalid COS placeholder is absent from loadItems() (Books/List)',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_cos_epub',
          title: 'Christ Our Saviour',
          relativePath: 'ePubs/EGW/EGW_Books/en_COS.epub',
          indexStatus: 'needs_attention',
          indexError:
              'Structurally invalid EPUB (missingOpf): container.xml '
              'references "OEBPS/content.opf" but no such entry exists.',
        );

        final items = await LibraryCatalogService.instance.loadItems();

        expect(items.where((i) => i.title == 'Christ Our Saviour'), isEmpty);
      },
    );

    test(
      'invalid IC placeholder is absent from loadItems() (Books/List)',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_ic_epub',
          title: 'The Impending Conflict',
          relativePath: 'ePubs/EGW/EGW_Books/en_IC.epub',
          indexStatus: 'needs_attention',
          indexError:
              'Structurally invalid EPUB (missingOpf): container.xml '
              'references "OEBPS/content.opf" but no such entry exists.',
        );

        final items = await LibraryCatalogService.instance.loadItems();

        expect(
          items.where((i) => i.title == 'The Impending Conflict'),
          isEmpty,
        );
      },
    );

    test(
      'invalid COS placeholder is absent from Recent even after being opened',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_cos_epub',
          title: 'Christ Our Saviour',
          relativePath: 'ePubs/EGW/EGW_Books/en_COS.epub',
          indexStatus: 'needs_attention',
          indexError: 'Referenced OPF package document is missing.',
          lastOpened: DateTime.now().toUtc().toIso8601String(),
        );

        final items = await LibraryCatalogService.instance.loadItems();
        final recent = selectRecentLibraryItems(items);

        expect(recent.where((i) => i.title == 'Christ Our Saviour'), isEmpty);
      },
    );

    test(
      'invalid IC placeholder is absent from Recent even after being opened',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_ic_epub',
          title: 'The Impending Conflict',
          relativePath: 'ePubs/EGW/EGW_Books/en_IC.epub',
          indexStatus: 'needs_attention',
          indexError: 'Referenced OPF package document is missing.',
          lastOpened: DateTime.now().toUtc().toIso8601String(),
        );

        final items = await LibraryCatalogService.instance.loadItems();
        final recent = selectRecentLibraryItems(items);

        expect(
          recent.where((i) => i.title == 'The Impending Conflict'),
          isEmpty,
        );
      },
    );

    test('a needs_attention item is excluded from search even if it retains '
        'stale text blocks from before it was flagged unreadable', () async {
      await seedItem(
        id: 'library_item_stale_blocks_needs_attention',
        title: 'Christ Our Saviour',
        relativePath: 'ePubs/EGW/EGW_Books/en_COS_stale.epub',
        indexStatus: 'needs_attention',
        indexError: 'Referenced OPF package document is missing.',
        readableBlockCount: 3,
      );

      final results = await LibraryCatalogService.instance.searchContent(
        query: 'readable content',
      );

      expect(
        results.where((r) => r.item.title == 'Christ Our Saviour'),
        isEmpty,
      );
    });

    test('sanity check: a valid indexed item with matching text blocks does '
        'appear in search (proves the query above is a real negative, not a '
        'no-op)', () async {
      await seedItem(
        id: 'library_item_valid_searchable_book',
        title: 'Steps to Christ',
        relativePath: 'ePubs/EGW/EGW_Books/en_SC_searchable.epub',
        indexStatus: 'indexed',
        readableBlockCount: 3,
      );

      final results = await LibraryCatalogService.instance.searchContent(
        query: 'readable content',
      );

      expect(
        results.where((r) => r.item.title == 'Steps to Christ'),
        isNotEmpty,
      );
    });

    test('missing EPUB with no retained canonical content is hidden', () async {
      await seedItem(
        id: 'library_item_research_epubs_egw_egw_misc_collections_en_shm_apx_epub',
        title: 'The Story of Our Health Message',
        relativePath: 'ePubs/EGW/EGW_Misc_Collections/en_SHM-apx.epub',
        indexStatus: 'needs_attention',
        indexError: 'No readable text content found after parsing.',
      );

      final items = await LibraryCatalogService.instance.loadItems();

      expect(
        items.where((i) => i.title == 'The Story of Our Health Message'),
        isEmpty,
      );
    });
  });

  group('duplicate COS/IC rows collapse to one Needs Attention entry', () {
    test(
      'two stale COS rows sharing a source_work_id collapse to one',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_research_egw_books_en_cos_epub',
          title: 'Christ Our Saviour',
          relativePath: 'ePubs/Research/EGW_Books/en_COS.epub',
          indexStatus: 'needs_attention',
          indexError: 'Referenced OPF package document is missing.',
          sourceWorkId: 'COS',
          lastOpened: DateTime.now().toUtc().toIso8601String(),
        );
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_cos_epub',
          title: 'Christ Our Saviour',
          relativePath: 'ePubs/EGW/EGW_Books/en_COS.epub',
          indexStatus: 'needs_attention',
          indexError: 'Referenced OPF package document is missing.',
          sourceWorkId: 'COS',
        );

        final needsAttention = await LibraryCatalogService.instance
            .listNeedsAttentionManagedItems();

        expect(
          needsAttention.where((i) => i.title == 'Christ Our Saviour').length,
          1,
        );
      },
    );

    test(
      'two stale IC rows sharing a source_work_id collapse to one',
      () async {
        await seedItem(
          id: 'library_item_research_epubs_research_egw_books_en_ic_epub',
          title: 'The Impending Conflict',
          relativePath: 'ePubs/Research/EGW_Books/en_IC.epub',
          indexStatus: 'needs_attention',
          indexError: 'Structurally invalid EPUB (missingOpf): placeholder.',
          sourceWorkId: 'IC',
          lastOpened: DateTime.now().toUtc().toIso8601String(),
        );
        await seedItem(
          id: 'library_item_research_epubs_egw_egw_books_en_ic_epub',
          title: 'The Impending Conflict',
          relativePath: 'ePubs/EGW/EGW_Books/en_IC.epub',
          indexStatus: 'needs_attention',
          indexError: 'Referenced OPF package document is missing.',
          sourceWorkId: 'IC',
        );

        final needsAttention = await LibraryCatalogService.instance
            .listNeedsAttentionManagedItems();

        expect(
          needsAttention
              .where((i) => i.title == 'The Impending Conflict')
              .length,
          1,
        );
      },
    );
  });

  group('valid items are unaffected', () {
    test('a valid canonical-generation book still appears', () async {
      await seedItem(
        id: 'library_item_valid_canonical_book',
        title: 'Steps to Christ',
        relativePath: 'ePubs/EGW/EGW_Books/en_SC.epub',
        indexStatus: 'indexed',
        navigationCount: 5,
        readableBlockCount: 40,
      );

      final items = await LibraryCatalogService.instance.loadItems();

      expect(items.where((i) => i.title == 'Steps to Christ').length, 1);
    });

    test(
      'a valid legacy EPUB fallback (metadata_only) still appears',
      () async {
        await seedItem(
          id: 'library_item_valid_metadata_only_book',
          title: 'The Great Controversy',
          relativePath: 'ePubs/EGW/EGW_Books/en_GC.epub',
          indexStatus: 'metadata_only',
        );

        final items = await LibraryCatalogService.instance.loadItems();

        expect(
          items.where((i) => i.title == 'The Great Controversy').length,
          1,
        );
      },
    );

    test('a valid CaptureClipper book still appears', () async {
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('library_items', <String, Object?>{
        'id': 'library_item_capture_clipper_book',
        'title': 'Captured Pioneer Work',
        'file_name': 'captured.html',
        'relative_path': 'Research/Pioneer/captured.html',
        'file_format': 'html',
        'folder_type': 'research',
        'library_role': 'research',
        'collection_name': 'Adventist Pioneer Library',
        'source_type': 'egw_html_capture',
        'index_status': 'indexed',
        'date_added': now,
        'created_at': now,
        'updated_at': now,
        'device_id': 'test-device',
      });

      final items = await LibraryCatalogService.instance.loadItems();

      expect(items.where((i) => i.title == 'Captured Pioneer Work').length, 1);
    });

    test(
      'a missing EPUB that still has a retained canonical generation stays visible',
      () async {
        await seedItem(
          id: 'library_item_missing_epub_with_canonical',
          title: 'Patriarchs and Prophets',
          relativePath: 'ePubs/EGW/EGW_Books/en_PP.epub',
          indexStatus: 'indexed',
          navigationCount: 10,
          readableBlockCount: 80,
        );

        final items = await LibraryCatalogService.instance.loadItems();

        expect(
          items.where((i) => i.title == 'Patriarchs and Prophets').length,
          1,
        );
      },
    );
  });

  group('soft-retiring a stale duplicate preserves user data', () {
    test('markups/links referencing a soft-retired row survive and the row '
        'disappears from every read query', () async {
      const staleId = 'library_item_research_epubs_egw_egw_books_en_cos_epub';
      await seedItem(
        id: staleId,
        title: 'Christ Our Saviour',
        relativePath: 'ePubs/EGW/EGW_Books/en_COS.epub',
        indexStatus: 'needs_attention',
        indexError: 'Referenced OPF package document is missing.',
      );
      final db = await ELibraryDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('elibrary_markups', <String, Object?>{
        'library_item_id': staleId,
        'epub_href': 'chapter1.html',
        'start_block_index': 0,
        'start_char_offset': 0,
        'end_block_index': 0,
        'end_char_offset': 5,
        'selected_text_snapshot': 'kept note',
        'markup_type': 'note',
        'color': '#FFFF00',
        'created_at': now,
        'updated_at': now,
      });

      // Simulate the narrowly-targeted soft-retirement the live repair
      // performs: mark the stale duplicate deleted without touching its
      // user-data rows.
      await db.update(
        'library_items',
        <String, Object?>{'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: <Object?>[staleId],
      );

      final items = await LibraryCatalogService.instance.loadItems();
      expect(items.where((i) => i.id == staleId), isEmpty);

      final markups = await db.query(
        'elibrary_markups',
        where: 'library_item_id = ?',
        whereArgs: <Object?>[staleId],
      );
      expect(markups, hasLength(1));
      expect(markups.single['selected_text_snapshot'], 'kept note');
    });
  });

  group('libraryItemIsNormallyReadable matches libraryItemAvailability', () {
    test('is false for needs_attention, true otherwise', () async {
      await seedItem(
        id: 'library_item_needs_attention_probe',
        title: 'Probe',
        relativePath: 'ePubs/EGW/EGW_Books/probe.epub',
        indexStatus: 'needs_attention',
        indexError: 'Referenced OPF package document is missing.',
      );
      final blocked = await LibraryCatalogService.instance.loadItemById(
        'library_item_needs_attention_probe',
      );
      expect(blocked, isNotNull);
      expect(libraryItemIsNormallyReadable(blocked!), isFalse);

      await seedItem(
        id: 'library_item_indexed_probe',
        title: 'Probe Two',
        relativePath: 'ePubs/EGW/EGW_Books/probe2.epub',
        indexStatus: 'indexed',
      );
      final allowed = await LibraryCatalogService.instance.loadItemById(
        'library_item_indexed_probe',
      );
      expect(allowed, isNotNull);
      expect(libraryItemIsNormallyReadable(allowed!), isTrue);
    });
  });
}
