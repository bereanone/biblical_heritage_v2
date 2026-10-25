import 'dart:convert';
import 'package:studybible2/core/theme/app_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory sandbox;
  late Database db;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const stamp = '2026-09-09T00:00:00Z';

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    sandbox = await Directory.systemTemp.createTemp('library_search_reading_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => sandbox.path);
    await LibraryRootService.instance.setLibraryRoot(path: sandbox.path);
    final path = p.join(sandbox.path, 'Databases', 'eLibrary.db');
    await Directory(p.dirname(path)).create(recursive: true);
    final seed = await openDatabase(path);
    await ELibrarySchema.ensure(seed);
    await seed.close();
    db = await ELibraryDatabase.instance.database;
  });
  tearDown(() async {
    await ELibraryDatabase.instance.close();
    await UserDatabase.instance.close();
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await sandbox.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> item(
    String id, {
    String status = 'indexed',
    bool deleted = false,
  }) async {
    await db.insert('library_items', {
      'id': id,
      'title': 'Book $id',
      'author': 'A. T. Jones',
      'file_name': '$id.epub',
      'relative_path': '$id.epub',
      'file_format': 'epub',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'Pioneer Authors',
      'source_type': 'pioneer_epub_import',
      'index_status': status,
      'created_at': stamp,
      'updated_at': stamp,
      'device_id': 'test',
      if (deleted) 'deleted_at': stamp,
    });
  }

  Future<void> canonical(
    String id,
    String text, {
    String status = 'complete',
  }) async {
    await db.insert('library_document_conversion', {
      'library_item_id': id,
      'canonicalizer_version': 16,
      'status': status,
    });
    await db.insert('library_document_sections', {
      'id': '$id-section',
      'library_item_id': id,
      'display_order': 0,
      'title': 'First chapter',
      'source_href': 'chapter.xhtml',
    });
    await db.insert('library_document_blocks', {
      'id': '$id-block',
      'library_item_id': id,
      'section_id': '$id-section',
      'display_order': 7,
      'block_type': 'paragraph',
      'plain_text': text,
      'source_href': 'chapter.xhtml',
      'content_hash': 'original-hash',
      'source_refcode': 'TEST 3.2',
    });
  }

  Future<void> legacy(String id, String text) async {
    await db.insert('library_text_blocks', {
      'library_item_id': id,
      'epub_href': 'chapter.xhtml',
      'paragraph_index': 1,
      'paragraph_on_section': 1,
      'plain_text': text,
      'created_at': stamp,
      'updated_at': stamp,
    });
  }

  test(
    'incidental substrings cannot crowd an exact word out of the candidate window',
    () async {
      await item('a-incidental');
      await canonical('a-incidental', 'The evening passed quietly.');
      final batch = db.batch();
      for (var i = 0; i < 1700; i++) {
        batch.insert('library_document_blocks', {
          'id': 'incidental-$i',
          'library_item_id': 'a-incidental',
          'section_id': 'a-incidental-section',
          'display_order': i + 8,
          'block_type': 'paragraph',
          'plain_text': 'This convenient arrangement belongs to the evening.',
          'source_href': 'chapter.xhtml',
          'content_hash': 'incidental-$i',
        });
      }
      await batch.commit(noResult: true);
      await item('z-exact');
      await canonical(
        'z-exact',
        'Veni, vidi, vici, the occasion when written, 238.',
      );
      final hits = await LibraryCatalogService.instance.searchContent(
        query: 'Veni',
        limit: 1,
      );
      expect(hits, hasLength(1));
      expect(hits.single.item.id, 'z-exact');
      expect(hits.single.target?.canonicalBlockId, 'z-exact-block');
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'Veni',
        ),
        1,
      );
      final filtered = await LibraryCatalogService.instance.searchContent(
        query: 'Veni',
        limit: 1,
        collectionFilter: 'pioneer_authors',
      );
      expect(filtered.map((h) => h.item.id), ['z-exact']);
    },
  );

  test(
    'candidate filtering preserves phrase punctuation, line breaks and citation numbers',
    () async {
      await item('phrase');
      await canonical(
        'phrase',
        'Righteousness—by\nfaith appears beside 66:23.',
      );
      for (final query in ['"righteousness by faith"', '66:23']) {
        final hits = await LibraryCatalogService.instance.searchContent(
          query: query,
        );
        expect(hits, hasLength(1), reason: query);
        expect(hits.single.target?.canonicalBlockId, 'phrase-block');
        expect(
          await LibraryCatalogService.instance.countSearchContentResults(
            query: query,
          ),
          1,
        );
      }
    },
  );

  test(
    'canonical search never inherits a citation from a different legacy paragraph',
    () async {
      await item('citation-safety');
      await canonical('citation-safety', 'A needlequartz canonical passage.');
      await db.update('library_document_blocks', {'source_refcode': null});
      await db.insert('elibrary_ref_index', {
        'library_item_id': 'citation-safety',
        'href': 'chapter.xhtml',
        'paragraph_index': 7,
        'ref_code': 'WRONG 99.9',
        'stable_ref': 'WRONG 99.9',
        'page_number': 99,
        'paragraph_on_page': 9,
        'book_abbrev': 'WRONG',
        'ref_source': 'legacy_fixture',
      });
      final hits = await LibraryCatalogService.instance.searchContent(
        query: 'needlequartz',
      );
      expect(hits, hasLength(1));
      expect(hits.single.locationText, isNot(contains('WRONG')));
    },
  );

  test(
    'canonical-only books are searchable and resolve by exact block identity',
    () async {
      await item('canonical-only');
      await canonical(
        'canonical-only',
        'The needlequartz passage is readable.',
      );
      final results = await LibraryCatalogService.instance.searchContent(
        query: 'needlequartz',
      );
      expect(results, hasLength(1));
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'needlequartz',
        ),
        1,
      );
      expect(
        await LibraryCatalogService.instance.countIndexedSearchableItems(),
        1,
      );
      final target = results.single.target!.withQuery('needlequartz');
      expect(target.canonicalBlockId, 'canonical-only-block');
      expect(target.canonicalContentHash, 'original-hash');
      expect(results.single.item.displayAuthor, 'A. T. Jones');
      expect(results.single.locationText, contains('TEST 3.2'));
      expect(
        await LibraryDocumentRepository(db).displayOrderForSearchTarget(target),
        7,
      );
      // A stale result must not silently land on changed text at the same ID.
      await db.update('library_document_blocks', {
        'content_hash': 'changed-hash',
      });
      expect(
        await LibraryDocumentRepository(db).displayOrderForSearchTarget(target),
        isNull,
      );
    },
  );

  test(
    'search follows accepted reading content without duplicate legacy hits',
    () async {
      await item('both');
      await canonical('both', 'A needlequartz accepted passage.');
      await legacy('both', 'A needlequartz obsoletelegacy passage.');
      await item('legacy-only');
      await legacy('legacy-only', 'Another needlequartz passage.');
      await item('failed-conversion');
      await canonical(
        'failed-conversion',
        'Unaccepted needlequartz text.',
        status: 'failed',
      );
      await legacy('failed-conversion', 'Prior needlequartz readable text.');
      final results = await LibraryCatalogService.instance.searchContent(
        query: 'needlequartz',
      );
      expect(results, hasLength(3));
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'needlequartz',
        ),
        3,
      );
      expect(
        await LibraryCatalogService.instance.countIndexedSearchableItems(),
        3,
      );
      expect(
        results.where((r) => r.item.id == 'both').single.fullParagraph,
        'A needlequartz accepted passage.',
      );
      expect(
        results
            .where((r) => r.item.id == 'failed-conversion')
            .single
            .target!
            .canonicalBlockId,
        isNull,
      );
      expect(
        await LibraryCatalogService.instance.searchContent(
          query: 'obsoletelegacy',
        ),
        isEmpty,
      );
      expect(
        await LibraryCatalogService.instance.searchContent(
          query: 'needlequartz',
          collectionFilter: 'egw_books',
        ),
        isEmpty,
      );
    },
  );

  test(
    'results and counts both exclude retired and needs-attention content',
    () async {
      await item('retired', deleted: true);
      await canonical('retired', 'needlequartz retired');
      await item('unreadable', status: 'needs_attention');
      await legacy('unreadable', 'needlequartz stale');
      await item('valid');
      await canonical('valid', 'needlequartz valid');
      expect(
        await LibraryCatalogService.instance.searchContent(
          query: 'needlequartz',
        ),
        hasLength(1),
      );
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'needlequartz',
        ),
        1,
      );
      expect(
        await LibraryCatalogService.instance.countIndexedSearchableItems(),
        1,
      );
    },
  );

  test(
    'title and author matches open a book without inventing a paragraph hit',
    () async {
      for (final field in ['title', 'author']) {
        final id = '$field-only';
        await item(id);
        await canonical(id, 'A paragraph about hope.');
        await db.update(
          'library_items',
          {field: 'Second Coming'},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
      final hits = await LibraryCatalogService.instance.searchContent(
        query: 'Second Coming',
      );
      expect(hits.map((hit) => hit.item.id).toSet(), {
        'title-only',
        'author-only',
      });
      expect(
        hits.every((hit) => hit.target == null && hit.fullParagraph == null),
        isTrue,
      );
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'Second Coming',
        ),
        2,
      );
      final quoted = await LibraryCatalogService.instance.searchContent(
        query: '"Second Coming"',
      );
      expect(quoted.map((hit) => hit.item.id).toSet(), {
        'title-only',
        'author-only',
      });
    },
  );

  test(
    'catalog matches do not duplicate real passage hits or leak another collection',
    () async {
      await item('matching');
      await canonical('matching', 'The Second Coming gives hope.');
      await db.update(
        'library_items',
        {'title': 'Second Coming'},
        where: 'id = ?',
        whereArgs: ['matching'],
      );
      final hits = await LibraryCatalogService.instance.searchContent(
        query: 'Second Coming',
      );
      expect(hits, hasLength(1));
      expect(hits.single.target, isNotNull);
      expect(
        await LibraryCatalogService.instance.countSearchContentResults(
          query: 'Second Coming',
        ),
        1,
      );
      expect(
        await LibraryCatalogService.instance.searchContent(
          query: 'Second Coming',
          collectionFilter: 'egw_books',
        ),
        isEmpty,
      );
    },
  );

  test(
    'Top Shelf limits text and catalog matches, counts, and a changed shelf',
    () async {
      for (final id in [
        'shelf-body',
        'other-body',
        'shelf-title',
        'other-title',
      ]) {
        await item(id);
        await canonical(
          id,
          id.endsWith('body')
              ? 'The Second Coming gives hope.'
              : 'A paragraph about hope.',
        );
        if (id.endsWith('title')) {
          await db.update(
            'library_items',
            {'title': 'Second Coming'},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      final service = LibraryCatalogService.instance;
      await AppSettingsService.instance.saveRawSetting(
        'elibrary_top_shelf_v1',
        jsonEncode(['shelf-body', 'shelf-title']),
      );
      final hits = await service.searchContent(
        query: 'Second Coming',
        collectionFilter: 'top_shelf',
      );
      expect(hits.map((hit) => hit.item.id).toSet(), {
        'shelf-body',
        'shelf-title',
      });
      expect(
        await service.countSearchContentResults(
          query: 'Second Coming',
          collectionFilter: 'top_shelf',
        ),
        2,
      );
      expect(
        await service.countIndexedSearchableItems(
          collectionFilter: 'top_shelf',
        ),
        2,
      );
      expect(
        await service.countCatalogItemsInScope(collectionFilter: 'top_shelf'),
        2,
      );
      await AppSettingsService.instance.saveRawSetting(
        'elibrary_top_shelf_v1',
        jsonEncode(['other-title']),
      );
      expect(
        (await service.searchContent(
          query: 'Second Coming',
          collectionFilter: 'top_shelf',
        )).single.item.id,
        'other-title',
      );
      expect(
        await service.countSearchContentResults(
          query: 'Second Coming',
          collectionFilter: 'all',
        ),
        4,
      );
    },
  );

  test(
    'empty and malformed Top Shelf never broaden to the whole library',
    () async {
      await item('match');
      await canonical('match', 'The Second Coming gives hope.');
      for (final raw in ['[]', '{broken', '{}', '[null, 4]']) {
        await AppSettingsService.instance.saveRawSetting(
          'elibrary_top_shelf_v1',
          raw,
        );
        expect(
          await LibraryCatalogService.instance.searchContent(
            query: 'Second Coming',
            collectionFilter: 'top_shelf',
          ),
          isEmpty,
        );
        expect(
          await LibraryCatalogService.instance.countSearchContentResults(
            query: 'Second Coming',
            collectionFilter: 'top_shelf',
          ),
          0,
        );
      }
    },
  );

  test(
    'metadata-only catalog entries are discoverable but retired and unreadable entries are not',
    () async {
      await item('catalog-only', status: 'metadata_only');
      await item('retired-catalog', deleted: true);
      await item('unreadable-catalog', status: 'needs_attention');
      final hits = await LibraryCatalogService.instance.searchContent(
        query: 'Jones',
      );
      expect(hits.map((hit) => hit.item.id), ['catalog-only']);
      expect(hits.single.target, isNull);
    },
  );
}
