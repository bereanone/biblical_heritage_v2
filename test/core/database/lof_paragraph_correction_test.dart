import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_publisher_text_corrections.dart';
import 'package:studybible2/core/database/lof_paragraph_correction.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE library_items (id TEXT PRIMARY KEY, file_hash TEXT, anchor_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE library_document_blocks (id TEXT PRIMARY KEY, library_item_id TEXT, display_order INTEGER, block_type TEXT, plain_text TEXT, formatted_content TEXT, content_hash TEXT)',
    );
    await db.execute(
      'CREATE TABLE elibrary_markups (id INTEGER PRIMARY KEY, library_item_id TEXT, epub_href TEXT, start_char_offset INTEGER, end_char_offset INTEGER, start_token_index INTEGER, end_token_index INTEGER, note_text TEXT, selected_text_snapshot TEXT)',
    );
    await db.insert('library_items', {
      'id': 'lof',
      'file_hash': LofParagraphCorrection.sourceHash,
      'anchor_id': 'canonical:${LofParagraphCorrection.tailId}',
    });
    for (var i = 0; i < 2; i++) {
      final text = i == 0
          ? LofParagraphCorrection.headBefore
          : LofParagraphCorrection.tailBefore;
      await db.insert('library_document_blocks', {
        'id': i == 0
            ? LofParagraphCorrection.headId
            : LofParagraphCorrection.tailId,
        'library_item_id': 'lof',
        'display_order': 345 + i,
        'block_type': 'paragraph',
        'plain_text': text,
        'formatted_content': jsonEncode({
          'version': 1,
          'metadata': {},
          'nodes': [
            {'type': 'text', 'text': text},
          ],
        }),
        'content_hash': 'original-$i',
      });
    }
    await db.insert('elibrary_markups', {
      'id': 1,
      'library_item_id': 'lof',
      'epub_href': 'canonical:${LofParagraphCorrection.tailId}',
      'start_char_offset': 3,
      'end_char_offset': 7,
      'start_token_index': 1,
      'end_token_index': 1,
      'note_text': 'Keep my note',
      'selected_text_snapshot': 'Upon',
    });
  });
  tearDown(() => db.close());
  test(
    'source-confirmed join retains IDs, orders, source speech and note selection',
    () async {
      final itemBefore = await db.query('library_items');
      expect(await ELibraryPublisherTextCorrections.apply(db), 2);
      final rows = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(rows.length, 2);
      expect(rows[0]['id'], LofParagraphCorrection.headId);
      expect(rows[1]['id'], LofParagraphCorrection.tailId);
      expect(
        rows[0]['plain_text'],
        (LofParagraphCorrection.headBefore + LofParagraphCorrection.tailBefore)
            .replaceFirst('Evolution even', 'Evolution, even'),
      );
      final head = jsonDecode(rows[0]['formatted_content'] as String) as Map;
      final tail = jsonDecode(rows[1]['formatted_content'] as String) as Map;
      expect(
        (head['nodes'] as List).map((e) => e['text']).join(),
        rows[0]['plain_text'],
      );
      expect(
        head['metadata']['publisher_original_text'],
        LofParagraphCorrection.headBefore,
      );
      expect(tail['metadata']['publisher_joined_head_order'], 345);
      expect(tail['metadata']['content_role'], 'superseded_source_fragment');
      final note = (await db.query('elibrary_markups')).single;
      expect(note['note_text'], 'Keep my note');
      expect(note['selected_text_snapshot'], 'Upon');
      final text = rows[0]['plain_text'] as String;
      expect(
        text.substring(
          note['start_char_offset'] as int,
          note['end_char_offset'] as int,
        ),
        'Upon',
      );
      expect(await db.query('library_items'), itemBefore);
      expect(await ELibraryPublisherTextCorrections.apply(db), 0);
      expect((await db.query('library_publisher_text_repairs')).length, 5);
    },
  );
  test('unrecognized edition is left intact', () async {
    await db.update('library_items', {'file_hash': 'unrecognized'});
    expect(await ELibraryPublisherTextCorrections.apply(db), 0);
    expect(
      (await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      )).first['plain_text'],
      LofParagraphCorrection.headBefore,
    );
  });
  test('user-revised text is left intact', () async {
    await db.update(
      'library_document_blocks',
      {'plain_text': 'User revision'},
      where: 'id=?',
      whereArgs: [LofParagraphCorrection.tailId],
    );
    expect(await ELibraryPublisherTextCorrections.apply(db), 0);
  });
}
