import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'scanned page contents resolves exact files, never missing fragments or other books',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await ELibrarySchema.ensure(db);
      for (final spec in [
        ('first', 'book', 'epub/page_1.html', 0),
        ('second', 'book', 'epub/page_1.html', 1),
        ('next', 'book', 'epub/page_2.html', 2),
        ('other', 'other-book', 'epub/page_3.html', 0),
      ]) {
        await db.insert('library_document_blocks', {
          'id': spec.$1,
          'library_item_id': spec.$2,
          'section_id': 'section',
          'display_order': spec.$4,
          'block_type': 'paragraph',
          'plain_text': spec.$1,
          'source_href': spec.$3,
          'formatted_content': jsonEncode({'version': 1, 'nodes': <Object>[]}),
        });
      }
      for (final spec in [
        ('one', 'epub/page_1.html', ''),
        ('two', 'epub/page_2.html', ''),
        ('broken', 'epub/page_1.html', 'missing'),
        ('outside', 'epub/page_3.html', ''),
        ('wrong-path', 'other/page_1.html', ''),
      ]) {
        await db.insert('library_navigation_items', {
          'id': spec.$1,
          'library_item_id': 'book',
          'label': spec.$1,
          'href': spec.$2,
          'anchor_id': spec.$3,
          'sort_order': spec.$1 == 'one' ? 0 : 1,
          'depth': 0,
          'device_id': 'test',
          'created_at': '2026-10-18',
          'updated_at': '2026-10-18',
        });
      }
      final before = await db.query('library_document_blocks');
      final result = await LibraryDocumentRepository(
        db,
      ).loadCanonicalNavigationDestinations('book');
      expect(result.map((e) => e.block.id), ['first', 'next']);
      expect(await db.query('library_document_blocks'), before);
    },
  );
}
