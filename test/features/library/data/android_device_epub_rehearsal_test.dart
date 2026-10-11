import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/canonical_activation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backup = Platform.environment['STUDYBIBLE_ANDROID_BACKUP_ROOT'];
  test(
    'device-library EPUB repair rehearsal preserves original backup',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = await Directory.systemTemp.createTemp(
        'android_epub_rehearsal_',
      );
      final sourceRoot = Directory(backup!);
      final copied = await File(
        p.join(sourceRoot.path, 'Databases', 'eLibrary.db'),
      ).copy(p.join(root.path, 'eLibrary.db'));
      final db = await openDatabase(copied.path);
      try {
        await ELibrarySchema.ensure(db);
        final rows = await db.rawQuery("""
        SELECT DISTINCT i.id,i.title,i.relative_path FROM library_items i
        JOIN library_document_blocks b ON b.library_item_id=i.id
        WHERE b.plain_text LIKE 'PK%' AND i.deleted_at IS NULL
        ORDER BY CASE WHEN i.relative_path LIKE '%Appeal on Immortality%' THEN 0 ELSE 1 END,
        i.id LIMIT 20
      """);
        expect(rows.length, 20);
        for (final row in rows) {
          final original = File(
            p.join(sourceRoot.path, row['relative_path'] as String),
          );
          final source = await original.copy(
            p.join(root.path, p.basename(original.path)),
          );
          if (original.path.contains('Appeal on Immortality')) {
            final old = await db.query(
              'library_document_blocks',
              where: 'library_item_id=?',
              whereArgs: [row['id']],
              limit: 1,
            );
            await db.update(
              'library_items',
              {'anchor_id': 'canonical:${old.first['id']}'},
              where: 'id=?',
              whereArgs: [row['id']],
            );
          }
          final outcome = await CanonicalActivation.activate(
            db: db,
            libraryItemId: row['id'] as String,
            source: source,
            force: true,
          );
          expect(
            outcome.isReady,
            isTrue,
            reason: '${row['title']}: ${outcome.technicalDetail}',
          );
          final blocks = await db.query(
            'library_document_blocks',
            where: 'library_item_id=?',
            whereArgs: [row['id']],
          );
          expect(blocks, isNotEmpty);
          expect(
            blocks.any(
              (b) => (b['plain_text'] as String).startsWith('PK\u0003\u0004'),
            ),
            isFalse,
          );
          final nav = await db.query(
            'library_document_navigation',
            where: 'library_item_id=?',
            whereArgs: [row['id']],
          );
          if (original.path.contains('Appeal on Immortality')) {
            final audit = await db.query(
              'library_legacy_zip_position_repairs',
              where: 'library_item_id=?',
              whereArgs: [row['id']],
            );
            expect(audit, hasLength(1));
          }
          print(
            'REPAIRED ${p.basename(original.path)} blocks=${blocks.length} contents=${nav.length}',
          );
        }
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
    skip: backup == null
        ? 'Set STUDYBIBLE_ANDROID_BACKUP_ROOT to a copied device library.'
        : false,
  );
}
