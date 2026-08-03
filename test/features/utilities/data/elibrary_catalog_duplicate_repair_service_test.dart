import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/utilities/data/elibrary_catalog_duplicate_repair_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    temp = await Directory.systemTemp.createTemp('egw_duplicate_repair_');
    db = await openDatabase(p.join(temp.path, 'test.db'));
    await ELibrarySchema.ensure(db);
  });

  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });

  Future<void> item({
    required String id,
    required String path,
    required String title,
    String author = 'Ellen G. White',
    String? workId,
    String? lastOpened,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_items', <String, Object?>{
      'id': id,
      'title': title,
      'author': author,
      'file_name': p.basename(path),
      'relative_path': path,
      'source_work_id': workId,
      'file_format': 'epub',
      'folder_type': 'research',
      'last_opened': lastOpened,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test',
    });
  }

  Future<void> link(String id, String itemId, String text) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('library_links', <String, Object?>{
      'id': id,
      'library_item_id': itemId,
      'book_id': 1,
      'chapter': 1,
      'verse_start': 5,
      'verse_end': 5,
      'link_type': 'research',
      'anchor': text,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test',
    });
  }

  test('canonical duplicate is retained and legacy index is retired', () async {
    await item(
      id: 'canonical',
      path: 'ePubs/EGW/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
    );
    await item(
      id: 'legacy',
      path: 'ePubs/Research/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
    );
    await link('canonical-link', 'canonical', 'The same paragraph.');
    await link('legacy-link', 'legacy', 'The same paragraph.');

    final report = await ELibraryCatalogDuplicateRepairService.instance.repair(
      db: db,
    );

    expect(report.duplicateLogicalBooksFound, 1);
    expect(report.legacyCatalogRowsRetired, 1);
    expect(
      await db.query(
        'library_items',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: <Object?>['canonical'],
      ),
      hasLength(1),
    );
    expect(
      await db.query(
        'library_items',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: <Object?>['legacy'],
      ),
      isEmpty,
    );
    expect(await db.query('library_links'), hasLength(1));
  });

  test('legacy-only and canonical-only books are unchanged', () async {
    await item(
      id: 'legacy-only',
      path: 'ePubs/Research/EGW_Books/en_AA.epub',
      title: 'Acts of the Apostles',
      workId: 'AA',
    );
    await item(
      id: 'canonical-only',
      path: 'ePubs/EGW/EGW_Books/en_DA.epub',
      title: 'The Desire of Ages',
      workId: 'DA',
    );
    final report = await ELibraryCatalogDuplicateRepairService.instance.repair(
      db: db,
    );
    expect(report.legacyCatalogRowsRetired, 0);
    expect(
      await db.query('library_items', where: 'deleted_at IS NULL'),
      hasLength(2),
    );
  });

  test(
    'same filename with conflicting stable work IDs is not merged',
    () async {
      await item(
        id: 'canonical',
        path: 'ePubs/EGW/EGW_Books/book.epub',
        title: 'First Work',
        workId: 'FIRST',
      );
      await item(
        id: 'legacy',
        path: 'ePubs/Research/EGW_Books/book.epub',
        title: 'Second Work',
        workId: 'SECOND',
      );
      final report = await ELibraryCatalogDuplicateRepairService.instance
          .repair(db: db);
      expect(report.legacyCatalogRowsRetired, 0);
      expect(report.ambiguousDuplicates, hasLength(1));
    },
  );

  test('legacy user markup and latest reading position migrate', () async {
    await item(
      id: 'canonical',
      path: 'ePubs/EGW/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
      lastOpened: '2026-01-01T00:00:00Z',
    );
    await item(
      id: 'legacy',
      path: 'ePubs/Research/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
      lastOpened: '2026-02-01T00:00:00Z',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('elibrary_markups', <String, Object?>{
      'library_item_id': 'legacy',
      'epub_href': 'chapter.xhtml',
      'start_block_index': 0,
      'start_char_offset': 0,
      'end_block_index': 0,
      'end_char_offset': 4,
      'selected_text_snapshot': 'Text',
      'markup_type': 'highlight',
      'color': 'yellow',
      'note_text': 'Preserve me',
      'created_at': now,
      'updated_at': now,
    });

    final report = await ELibraryCatalogDuplicateRepairService.instance.repair(
      db: db,
    );
    expect(report.userStateRowsMigrated, 1);
    final markup = (await db.query('elibrary_markups')).single;
    expect(markup['library_item_id'], 'canonical');
    expect(markup['note_text'], 'Preserve me');
    final canonical = (await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: <Object?>['canonical'],
    )).single;
    expect(canonical['last_opened'], '2026-02-01T00:00:00Z');
  });

  test('repair is idempotent', () async {
    await item(
      id: 'canonical',
      path: 'ePubs/EGW/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
    );
    await item(
      id: 'legacy',
      path: 'ePubs/Research/EGW_Books/en_Ed.epub',
      title: 'Education',
      workId: 'ED',
    );
    expect(
      (await ELibraryCatalogDuplicateRepairService.instance.repair(
        db: db,
      )).legacyCatalogRowsRetired,
      1,
    );
    final second = await ELibraryCatalogDuplicateRepairService.instance.repair(
      db: db,
    );
    expect(second.legacyCatalogRowsRetired, 0);
    expect(second.indexRowsRemoved, 0);
    expect(second.userStateRowsMigrated, 0);
  });
}
