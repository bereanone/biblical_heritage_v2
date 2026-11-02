import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/lof_paragraph_correction.dart';
import 'package:studybible2/core/database/lof_reference_correction.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';
import 'package:studybible2/features/library/presentation/canonical_library_reader.dart';

void main() {
  const itemId = 'library_item_publisher_lof_complete_2017';
  sqfliteFfiInit();
  late Database db;
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ELibrarySchema.ensure(db);
    final source = await databaseFactoryFfi.openDatabase(
      File('assets/bundled_library/catalog.db').absolute.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      await db.insert(
        'library_items',
        (await source.query(
          'library_items',
          where: 'id = ?',
          whereArgs: [itemId],
        )).single,
      );
      for (final row in await source.query(
        'library_document_blocks',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      )) {
        await db.insert('library_document_blocks', row);
      }
    } finally {
      await source.close();
    }
    await db.transaction((txn) => LofParagraphCorrection.apply(txn, itemId));
    await db.execute(
      'CREATE TABLE preserved_notes(id TEXT, body TEXT, block_id TEXT)',
    );
    await db.insert('preserved_notes', {
      'id': 'note',
      'body': 'Keep this note',
      'block_id': LofParagraphCorrection.headId,
    });
  });
  tearDown(() => db.close());

  test(
    'real edition gets published codes across every body paragraph without changing narration or anchors',
    () async {
      final before = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      final notes = await db.query('preserved_notes');
      expect(
        await db.transaction(
          (txn) => LofReferenceCorrection.apply(txn, itemId),
        ),
        698,
      );
      final after = await db.query(
        'library_document_blocks',
        orderBy: 'display_order',
      );
      expect(after.length, before.length);
      for (var i = 0; i < after.length; i++) {
        final a = after[i], b = before[i];
        for (final field in [
          'id',
          'library_item_id',
          'section_id',
          'display_order',
          'block_type',
          'plain_text',
          'source_href',
          'source_anchor',
        ]) {
          expect(a[field], b[field], reason: '${a['display_order']}: $field');
        }
        final fa = jsonDecode(a['formatted_content'] as String) as Map;
        final fb = jsonDecode(b['formatted_content'] as String) as Map;
        expect(fa['nodes'], fb['nodes']);
        if (a['block_type'] == 'paragraph' &&
            (a['display_order'] as int) >= 49) {
          expect(
            a['source_refcode'],
            isNotEmpty,
            reason: 'body gap ${a['display_order']}',
          );
          expect(a['reference_witness'], startsWith('https://'));
        }
      }
      final psalm = LibraryDocumentBlock.fromRow(
        after.singleWhere((r) => r['display_order'] == 345),
      );
      expect(
        canonicalInlineReferenceCode(psalm, visible: true),
        'LOF_ATJ 53.3',
      );
      expect(canonicalInlineReferenceCode(psalm, visible: false), isNull);
      expect(
        after.singleWhere((r) => r['display_order'] == 83)['source_refcode'],
        'LOF_ATJ 15.1–15.2',
      );
      expect(
        after.singleWhere((r) => r['display_order'] == 305)['source_refcode'],
        'RH, March 14, 1899, p. 168',
      );
      expect(
        after.singleWhere((r) => r['display_order'] == 10)['source_refcode'],
        isNull,
      );
      expect(await db.query('preserved_notes'), notes);
      expect(
        await db.transaction(
          (txn) => LofReferenceCorrection.apply(txn, itemId),
        ),
        0,
      );
      expect(
        await db.query('library_document_blocks', orderBy: 'display_order'),
        after,
      );
    },
  );

  test(
    'wrong edition and revised paragraphs cannot receive a guessed code',
    () async {
      await db.update('library_items', {'file_hash': 'another-edition'});
      expect(await LofReferenceCorrection.apply(db, itemId), 0);
      await db.update('library_items', {
        'file_hash': LofParagraphCorrection.sourceHash,
      });
      await db.update(
        'library_document_blocks',
        {'plain_text': 'User revised this paragraph'},
        where: 'display_order = ?',
        whereArgs: [345],
      );
      expect(
        await db.transaction(
          (txn) => LofReferenceCorrection.apply(txn, itemId),
        ),
        697,
      );
      final row = (await db.query(
        'library_document_blocks',
        where: 'display_order = ?',
        whereArgs: [345],
      )).single;
      expect(row['source_refcode'], isNull);
    },
  );
}
