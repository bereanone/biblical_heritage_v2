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
import 'package:studybible2/features/library/data/library_reading_copy_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory sandbox;
  late Database db;
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  const stamp = '2026-09-09T00:00:00Z';

  setUp(() async {
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
  });

  Future<void> item(
    String id, {
    String status = 'indexed',
    bool deleted = false,
  }) async {
    await db.insert('library_items', {
      'id': id,
      'title': 'Same title',
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
      'source_hash': 'hash-$id',
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

  Future<List<LibraryReadingCopyReview>> prepareReview() async {
    await item('preferred');
    await canonical('preferred', 'needlequartz verified text');
    await item('old-ocr');
    await canonical('old-ocr', 'needlequartz obsoleteword OCR');
    await item('partial');
    await legacy('partial', 'needlequartz partial capture');
    await item('unrelated');
    await canonical('unrelated', 'needlequartz different author work');
    await db.update(
      'library_items',
      {'author': 'E. J. Waggoner'},
      where: 'id=?',
      whereArgs: ['unrelated'],
    );
    final preferredFingerprint =
        (await LibraryReadingCopyReview.sourceFingerprint(db, 'preferred'))!;
    return [
      for (final id in ['preferred', 'old-ocr', 'partial'])
        LibraryReadingCopyReview(
          itemId: id,
          fingerprint: (await LibraryReadingCopyReview.sourceFingerprint(
            db,
            id,
          ))!,
          preferredItemId: 'preferred',
          preferredFingerprint: preferredFingerprint,
          label: id == 'preferred'
              ? '1897 · Source-checked copy'
              : 'Retained $id',
          reason: 'Reviewed explicit identities and matching source text.',
        ),
    ];
  }

  test(
    'one reviewed reading copy on shelf and in search; all source rows retained',
    () async {
      final reviews = await prepareReview();
      final before = await db.query('library_items');
      await LibraryReadingCopyReview.record(db, reviews);
      final service = LibraryCatalogService.instance;
      final visible = await service.loadItems(hydrateMetadata: false);
      expect(visible.map((i) => i.id).toSet(), {'preferred', 'unrelated'});
      final preferred = visible.singleWhere((i) => i.id == 'preferred');
      expect(preferred.editionLabel, '1897 · Source-checked copy');
      expect(
        preferred.copyWith(spineIndex: 7).editionLabel,
        preferred.editionLabel,
      );
      expect(
        await service.loadItems(
          includeAlternateEditions: true,
          hydrateMetadata: false,
        ),
        hasLength(4),
      );
      final hits = await service.searchContent(query: 'needlequartz');
      expect(hits.map((h) => h.item.id).toSet(), {'preferred', 'unrelated'});
      expect(await service.countSearchContentResults(query: 'needlequartz'), 2);
      expect(await service.countIndexedSearchableItems(), 2);
      expect(await service.countCatalogItemsInScope(), 2);
      expect(await service.searchContent(query: 'obsoleteword'), isEmpty);
      expect(await db.query('library_items'), before);
      expect(await db.query('library_reading_copy_reviews'), hasLength(3));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test('missing or changed preferred source restores alternatives', () async {
    final reviews = await prepareReview();
    await LibraryReadingCopyReview.record(db, reviews);
    await db.update(
      'library_document_conversion',
      {'source_hash': 'changed'},
      where: 'library_item_id=?',
      whereArgs: ['preferred'],
    );
    expect(await LibraryReadingCopyReview.loadActive(db), isEmpty);
    expect(
      await LibraryCatalogService.instance.loadItems(hydrateMetadata: false),
      hasLength(4),
    );
    await db.update(
      'library_document_conversion',
      {'source_hash': 'hash-preferred'},
      where: 'library_item_id=?',
      whereArgs: ['preferred'],
    );
    await db.update(
      'library_items',
      {'deleted_at': stamp},
      where: 'id=?',
      whereArgs: ['preferred'],
    );
    expect(await LibraryReadingCopyReview.loadActive(db), isEmpty);
    expect(
      await LibraryCatalogService.instance.loadItems(hydrateMetadata: false),
      hasLength(3),
    );
  });

  test(
    'a changed legacy capture reappears for review without invalidating other choices',
    () async {
      await LibraryReadingCopyReview.record(db, await prepareReview());
      await db.update('library_text_blocks', {
        'plain_text': 'new complete capture',
      });
      final active = await LibraryReadingCopyReview.loadActive(db);
      expect(active.keys.toSet(), {'preferred', 'old-ocr'});
      expect(
        (await LibraryCatalogService.instance.loadItems(
          hydrateMetadata: false,
        )).map((i) => i.id).toSet(),
        {'preferred', 'partial', 'unrelated'},
      );
    },
  );

  test('a stale reviewed source rejects the whole transaction', () async {
    final reviews = await prepareReview();
    await db.update(
      'library_document_conversion',
      {'source_hash': 'changed'},
      where: 'library_item_id=?',
      whereArgs: ['old-ocr'],
    );
    await expectLater(
      LibraryReadingCopyReview.record(db, reviews),
      throwsStateError,
    );
    expect(await db.query('library_reading_copy_reviews'), isEmpty);
  });

  test(
    'approval history is retained when a later choice is recorded',
    () async {
      final reviews = await prepareReview();
      await LibraryReadingCopyReview.record(db, reviews);
      await LibraryReadingCopyReview.record(db, reviews);
      expect(await db.query('library_reading_copy_reviews'), hasLength(6));
      expect(await LibraryReadingCopyReview.loadActive(db), hasLength(3));
    },
  );
}
