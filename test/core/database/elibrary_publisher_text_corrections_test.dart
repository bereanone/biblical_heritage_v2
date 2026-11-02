import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_publisher_text_corrections.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  const before = ELibraryPublisherTextCorrections.wor10214Before;
  const after = ELibraryPublisherTextCorrections.wor10214After;
  const source =
      '49474b9b27e5fc4828aac88f07753acaf9b1930ef2efa3ea9bc5132ba9a70b83';
  test(
    'direct EPUB corrects only the approved source, location and paragraph',
    () {
      const html = '<p data-refcode="WOR 102.14">$before</p>';
      String apply(String hash, String href, String body) =>
          ELibraryPublisherTextCorrections.correctedEpubHtml(
            sourceHash: hash,
            href: href,
            html: body,
          );
      expect(
        apply(source, 'OEBPS/content26.xhtml', html),
        '<p data-refcode="WOR 102.14">$after</p>',
      );
      expect(apply('unknown', 'OEBPS/content26.xhtml', html), html);
      expect(apply(source, 'OEBPS/content27.xhtml', html), html);
      expect(
        apply(
          source,
          'OEBPS/content26.xhtml',
          html.replaceAll('102.14', '102.15'),
        ),
        html.replaceAll('102.14', '102.15'),
      );
      final corrected = apply(source, 'OEBPS/content26.xhtml', html);
      expect(apply(source, 'OEBPS/content26.xhtml', corrected), corrected);
    },
  );
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE library_items (id TEXT PRIMARY KEY, file_hash TEXT, anchor_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE library_document_blocks (id TEXT PRIMARY KEY, library_item_id TEXT, source_refcode TEXT, plain_text TEXT, formatted_content TEXT, block_type TEXT, content_hash TEXT, display_order INTEGER)',
    );
    await db.execute(
      'CREATE TABLE library_text_blocks (library_item_id TEXT, plain_text TEXT)',
    );
    await db.execute(
      'CREATE TABLE elibrary_ref_index (library_item_id TEXT, plain_text TEXT)',
    );
    await db.execute('CREATE TABLE library_markups (note_text TEXT)');
    await db.insert('library_items', {
      'id': 'wor',
      'file_hash': source,
      'anchor_id': 'canonical:stable',
    });
    await db.insert('library_document_blocks', {
      'id': 'stable',
      'library_item_id': 'wor',
      'source_refcode': 'WOR 102.14',
      'plain_text': before,
      'formatted_content': jsonEncode({
        'nodes': [
          {'text': before},
        ],
      }),
      'block_type': 'paragraph',
      'content_hash': 'old',
      'display_order': 1024,
    });
    for (final table in ['library_text_blocks', 'elibrary_ref_index']) {
      await db.insert(table, {'library_item_id': 'wor', 'plain_text': before});
    }
    await db.insert('library_markups', {'note_text': before});
  });
  tearDown(() => db.close());
  test(
    'patches verified paragraph and search copies, preserves anchors and notes, repeats safely',
    () async {
      final itemBefore = await db.query('library_items');
      expect(await ELibraryPublisherTextCorrections.apply(db), 1);
      final row = (await db.query('library_document_blocks')).single;
      expect(row['plain_text'], after);
      expect(row['formatted_content'].toString(), contains('up from the dead'));
      expect(row['id'], 'stable');
      expect(row['display_order'], 1024);
      expect(row['source_refcode'], 'WOR 102.14');
      expect(await db.query('library_items'), itemBefore);
      expect((await db.query('library_markups')).single['note_text'], before);
      expect(
        (await db.query('library_text_blocks')).single['plain_text'],
        after,
      );
      expect(
        (await db.query('elibrary_ref_index')).single['plain_text'],
        after,
      );
      expect(await ELibraryPublisherTextCorrections.apply(db), 0);
      final audit = (await db.query('library_publisher_text_repairs')).single;
      expect(
        (jsonDecode(audit['previous_row_json'] as String) as Map)['plain_text'],
        before,
      );
      // A later reimport of the preserved source must receive the same correction.
      await db.update('library_document_blocks', {
        'plain_text': before,
        'formatted_content': jsonEncode({
          'nodes': [
            {'text': before},
          ],
        }),
      });
      expect(
        await ELibraryPublisherTextCorrections.apply(db, itemId: 'wor'),
        1,
      );
      expect((await db.query('library_publisher_text_repairs')).length, 1);
    },
  );
  test('unknown source is never corrected', () async {
    await db.update('library_items', {'file_hash': 'unverified'});
    expect(await ELibraryPublisherTextCorrections.apply(db), 0);
    expect(
      (await db.query('library_document_blocks')).single['plain_text'],
      before,
    );
  });
  test('user-altered paragraph is never overwritten', () async {
    await db.update('library_document_blocks', {'plain_text': 'User revision'});
    expect(await ELibraryPublisherTextCorrections.apply(db), 0);
    expect(
      (await db.query('library_document_blocks')).single['plain_text'],
      'User revision',
    );
  });
}
