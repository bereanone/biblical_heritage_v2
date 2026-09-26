import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/library_document_canonicalizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'older CIS retains protected prose and reading position on current import',
    () async {
      final root = Platform.environment['CIS_REIMPORT_ROOT'];
      if (root == null) return;
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(
        p.absolute(root, 'eLibrary.db'),
      );
      try {
        final id =
            (await db.rawQuery(
                  'SELECT DISTINCT library_item_id FROM library_document_blocks',
                )).single['library_item_id']
                as String;
        final before = await db.query(
          'library_document_blocks',
          where: 'library_item_id=?',
          whereArgs: [id],
        );
        final protected = before
            .where(
              (b) =>
                  (b['source_refcode'] as String? ?? '').isNotEmpty &&
                  b['block_type'] == 'paragraph',
            )
            .toList();
        expect(protected, isNotEmpty);
        for (final block in protected) {
          final text = block['plain_text'] as String;
          await db.insert('elibrary_markups', {
            'library_item_id': id,
            'epub_href': 'canonical:${block['id']}',
            'start_block_index': 0,
            'end_block_index': 0,
            'start_char_offset': 0,
            'end_char_offset': text.length,
            'selected_text_snapshot': text,
            'markup_type': 'highlight',
            'color': '#00FF00',
            'created_at': 'isolated-proof',
            'updated_at': 'isolated-proof',
          });
        }
        final saved = protected.firstWhere(
          (b) => b['source_refcode'] == 'CIS 125.1',
        );
        await db.update(
          'library_items',
          {'anchor_id': 'canonical:${saved['id']}'},
          where: 'id=?',
          whereArgs: [id],
        );
        final result = await const LibraryDocumentCanonicalizer().canonicalize(
          db: db,
          libraryItemId: id,
          source: File(
            p.absolute(
              'tool/Verification/cis_1914_restoration/output/CIS_reference_preview.epub',
            ),
          ),
          force: true,
        );
        final after = await db.query(
          'library_document_blocks',
          where: 'library_item_id=?',
          whereArgs: [id],
        );
        final byId = {for (final b in after) b['id']: b};
        final lost = before
            .where((b) => !byId.containsKey(b['id']))
            .map(
              (b) => {
                'id': b['id'],
                'text': b['plain_text'],
                'type': b['block_type'],
              },
            )
            .toList();
        final report = {
          'activated': result.activated,
          'failure': result.validationFailureReason,
          'before_blocks': before.length,
          'after_blocks': after.length,
          'protected_prose': protected.length,
          'unmatched_old_blocks': lost,
          'saved_reference': saved['source_refcode'],
          'live_library_modified': false,
        };
        await File(
          p.join(root, 'reimport_protection_report.json'),
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        expect(
          result.activated,
          isTrue,
          reason: result.validationFailureReason,
        );
        for (final old in protected) {
          expect(byId[old['id']]?['plain_text'], old['plain_text']);
          expect(byId[old['id']]?['source_refcode'], old['source_refcode']);
        }
        expect(
          (await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: [id],
          )).single['anchor_id'],
          'canonical:${saved['id']}',
        );
        print(
          'Reimport activated; preserved ${protected.length} protected prose blocks; ${lost.length} unmatched prior unprotected blocks.',
        );
      } finally {
        await db.close();
      }
    },
  );
}
