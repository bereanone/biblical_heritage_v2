import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/bundled_library_content.dart';

class FileAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = await File(key).readAsBytes();
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  test(
    'real bundled artifact installs seven complete books and preserves an existing import',
    () async {
      final temp = await Directory.systemTemp.createTemp('actual-bundle-');
      final db = await openDatabase(
        inMemoryDatabasePath,
        singleInstance: false,
      );
      try {
        await db.execute('PRAGMA foreign_keys=ON');
        await ELibrarySchema.ensure(db);
        final personal = {
          'id': 'personal',
          'title': 'My existing import',
          'file_name': 'personal.epub',
          'relative_path': 'personal.epub',
          'created_at': 'user-date',
          'updated_at': 'user-date',
          'device_id': 'user-device',
        };
        await db.insert('library_items', personal);
        final before = (await db.query('library_items')).single;
        final manifest =
            jsonDecode(
                  await File(
                    BundledLibraryContent.manifestAsset,
                  ).readAsString(),
                )
                as Map;
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: temp.path,
            assets: FileAssets(),
          ),
          7,
        );
        expect(
          await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: ['personal'],
          ),
          [before],
        );
        expect(
          (manifest['books'] as List).map((book) => book['id']),
          contains(
            'library_item_research_pioneer_bible_readings_home_circle_1914',
          ),
        );
        for (final book in manifest['books'] as List) {
          final id = book['id'];
          final item = (await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: [id],
          )).single;
          final legacy = await db.query(
            'library_text_blocks',
            where: 'library_item_id=?',
            whereArgs: [id],
          );
          final canonical = await db.query(
            'library_document_blocks',
            where: 'library_item_id=?',
            whereArgs: [id],
          );
          expect(
            legacy.isNotEmpty || canonical.isNotEmpty,
            isTrue,
            reason: item['title'].toString(),
          );
          final cover = item['cover_path'] as String;
          expect(
            cover.startsWith('assets/') || await File(cover).exists(),
            isTrue,
            reason: cover,
          );
          if ((item['relative_path'] as String).startsWith(
            'Research/ManagedBundles/',
          )) {
            expect(
              await File(
                p.join(temp.path, item['relative_path'] as String),
              ).exists(),
              isTrue,
            );
          }
        }
        for (final blob in await db.query('library_asset_blobs')) {
          expect(
            sha256.convert(blob['data'] as List<int>).toString(),
            blob['sha256'],
          );
        }
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: temp.path,
            assets: FileAssets(),
          ),
          0,
        );
        expect((await db.query('library_items')).length, 8);
      } finally {
        await db.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
