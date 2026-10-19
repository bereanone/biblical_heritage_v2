import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'file-only contents skips epigraphs; explicit fragments retain authored targets',
    () async {
      final db = await openDatabase(inMemoryDatabasePath);
      await ELibrarySchema.ensure(db);
      for (final row in [
        {
          'id': 'intro',
          'display_order': 0,
          'block_type': 'paragraph',
          'plain_text': 'A Compilation from the Writings of Ellen G. White',
        },
        {
          'id': 'heading',
          'display_order': 4,
          'block_type': 'heading',
          'plain_text': 'The Sanctuary Truth',
        },
      ]) {
        await db.insert('library_document_blocks', {
          ...row,
          'library_item_id': 'cihs',
          'section_id': 'section',
          'source_href': 'oebps/content00.xhtml',
          'formatted_content': jsonEncode({'version': 1, 'nodes': <Object>[]}),
        });
      }
      for (final anchor in ['', 'authored-intro']) {
        await db.insert('library_document_navigation', {
          'id': anchor.isEmpty ? 'file' : 'fragment',
          'library_item_id': 'cihs',
          'label': 'The Sanctuary Truth',
          'depth': 0,
          'display_order': anchor.isEmpty ? 0 : 1,
          'source_href': 'oebps/content00.xhtml',
          'source_anchor': anchor,
          'target_block_id': 'intro',
        });
      }
      final destinations = await LibraryDocumentRepository(
        db,
      ).loadCanonicalNavigationDestinations('cihs');
      expect(destinations.first.block.id, 'heading');
      expect(destinations.last.block.id, 'intro');
      expect(
        (await db.query(
          'library_document_navigation',
        )).every((r) => r['target_block_id'] == 'intro'),
        isTrue,
      );
      await db.close();
    },
  );
}
