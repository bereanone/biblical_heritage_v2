import 'package:studybible2/features/library/data/library_document_repository.dart';
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
    'real bundled artifact installs eight complete books and preserves an existing import',
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
          8,
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
        final brhcOrder = await LibraryDocumentRepository(db)
            .openingDisplayOrder(
              'library_item_research_pioneer_bible_readings_home_circle_1914',
            );
        expect(brhcOrder, isNotNull);
        final brhcStart = await LibraryDocumentRepository(db).resolveLocation(
          'library_item_research_pioneer_bible_readings_home_circle_1914',
          brhcOrder!,
        );
        expect(brhcStart!.block.sourceAnchor, 'chapter-001');
        expect(brhcStart.block.plainText, 'Chapter 1. The Scriptures');
        final navigation = await LibraryDocumentRepository(db)
            .loadCanonicalNavigationDestinations(
              'library_item_research_pioneer_bible_readings_home_circle_1914',
            );
        final chapters = navigation.where((entry) => entry.depth == 1).toList();
        expect(chapters.length, 201);
        for (var i = 0; i < chapters.length; i++) {
          expect(chapters[i].label, startsWith('${i + 1}. '));
          expect(chapters[i].parentId, isNotNull);
          expect(chapters[i].block.plainText, startsWith('Chapter ${i + 1}. '));
        }
        expect(
          navigation
              .where((entry) => entry.label.startsWith('Section '))
              .length,
          18,
        );
        expect(
          (await db.query(
            'library_document_assets',
            where: 'library_item_id=?',
            whereArgs: [
              'library_item_research_pioneer_bible_readings_home_circle_1914',
            ],
          )).length,
          303,
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: temp.path,
            assets: FileAssets(),
          ),
          0,
        );
        // Simulate iOS moving the app data container after an update. The
        // original BRHC artwork must win over an EPUB's embedded flyer, even
        // when this bundle revision was already installed.
        final managedCovers = (manifest['books'] as List)
            .where((book) => book['cover_path'] != null)
            .toList();
        for (final book in managedCovers) {
          await db.update(
            'library_items',
            {
              'cover_path':
                  '/var/mobile/Containers/Data/Application/OLD/Graphics/${book['id']}.png',
            },
            where: 'id=?',
            whereArgs: [book['id']],
          );
        }
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: temp.path,
            assets: FileAssets(),
          ),
          0,
        );
        for (final book in managedCovers) {
          final row = (await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: [book['id']],
          )).single;
          expect(row['cover_path'], book['cover_path']);
          expect(
            await File(p.join(temp.path, row['cover_path'] as String)).exists(),
            isTrue,
          );
        }
        final brhc = managedCovers.firstWhere(
          (book) => book['title'].toString().startsWith('Bible Readings'),
        );
        final customCover = File(p.join(temp.path, 'my-cover.png'));
        await customCover.writeAsString('Keep my explicit artwork');
        await db.update(
          'library_items',
          {'cover_path': customCover.path},
          where: 'id=?',
          whereArgs: [brhc['id']],
        );
        expect(
          await BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: temp.path,
            assets: FileAssets(),
          ),
          0,
        );
        expect(
          (await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: [brhc['id']],
          )).single['cover_path'],
          customCover.path,
        );
        expect(
          await db.query(
            'library_items',
            where: 'id=?',
            whereArgs: ['personal'],
          ),
          [before],
        );
        expect((await db.query('library_items')).length, 9);
      } finally {
        await db.close();
        await temp.delete(recursive: true);
      }
    },
    // This exercises the full shipped catalog and hashes its original artwork.
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
