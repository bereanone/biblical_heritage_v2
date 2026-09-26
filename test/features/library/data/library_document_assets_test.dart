import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/features/library/data/library_document_assets.dart';
import 'package:studybible2/features/library/data/library_document_models.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  late Directory root;
  final revision = sha256.convert(utf8.encode('source revision')).toString();
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  final asset = LibraryDocumentAsset('${sha256.convert(bytes)}.png', bytes);
  Map<String, Object?> block(String item) => {
    'id': '$item-image',
    'library_item_id': item,
    'section_id': '$item-section',
    'display_order': 0,
    'block_type': 'image',
    'plain_text': 'Original illustration',
    'formatted_content': LibraryFormattedContent(
      nodes: [
        {'type': 'image', 'source': asset.name, 'rotation_degrees': 90},
      ],
    ).toJson(),
  };
  Future<void> seed(String item, {String? hash}) async {
    await db.insert('library_document_conversion', {
      'library_item_id': item,
      'source_hash': hash ?? revision,
      'status': 'complete',
      'canonicalizer_version': 34,
    });
    await db.insert('library_document_blocks', block(item));
  }

  Future<void> store(String item) => db.transaction(
    (txn) => LibraryDocumentAssets.store(
      txn,
      itemId: item,
      sourceHash: revision,
      assets: [asset],
      coverAssetName: asset.name,
    ),
  );
  Future<Directory?> restore(String item) =>
      LibraryDocumentAssets.restore(db: db, itemId: item, libraryRoot: root);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('embedded_library_');
    db = await openDatabase(p.join(root.path, 'eLibrary.db'));
    await ELibrarySchema.ensure(db);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'database alone restores exact images, cover, and unchanged block metadata',
    () async {
      await seed('smith');
      await store('smith');
      final before = await db.query('library_document_blocks');
      final first = (await restore('smith'))!;
      expect(await File(p.join(first.path, asset.name)).readAsBytes(), bytes);
      await first.delete(recursive: true);
      final second = (await restore('smith'))!;
      expect(await File(p.join(second.path, asset.name)).readAsBytes(), bytes);
      final covers = await LibraryDocumentAssets.restoreCovers(
        db: db,
        itemIds: {'smith'},
        libraryRoot: root,
      );
      expect(covers['smith'], p.join(second.path, asset.name));
      expect(await db.query('library_document_blocks'), before);
      expect(
        (await db.query('library_document_assets')).single['review_status'],
        'unreviewed',
      );
      await store('smith');
      expect(await db.query('library_asset_blobs'), hasLength(1));
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'active source identity prevents stale images and same-title author mixing',
    () async {
      await seed('smith');
      await store('smith');
      await seed('another-author');
      expect(await restore('another-author'), isNull);
      await db.update(
        'library_document_conversion',
        {
          'source_hash': sha256
              .convert(utf8.encode('different edition'))
              .toString(),
        },
        where: 'library_item_id=?',
        whereArgs: ['smith'],
      );
      expect(await restore('smith'), isNull);
      expect(
        await LibraryDocumentAssets.restoreCovers(
          db: db,
          itemIds: {'smith'},
          libraryRoot: root,
        ),
        isEmpty,
      );
    },
  );

  test(
    'corrupt database image is rejected before a cache is created',
    () async {
      await seed('smith');
      await store('smith');
      await db.update('library_asset_blobs', {
        'data': Uint8List.fromList([1, 2]),
        'byte_length': 2,
      });
      await expectLater(restore('smith'), throwsFormatException);
      expect(
        await Directory(p.join(root.path, '_database_assets')).exists(),
        isFalse,
      );
    },
  );

  test(
    'a missing image mapping cannot masquerade as a complete image set',
    () async {
      await seed('smith');
      await store('smith');
      await db.delete('library_document_assets');
      await expectLater(restore('smith'), throwsStateError);
      expect(
        await Directory(p.join(root.path, '_database_assets')).exists(),
        isFalse,
      );
    },
  );

  test('conflicting cache files and symlinks are not overwritten', () async {
    await seed('smith');
    await store('smith');
    final dir = (await restore('smith'))!;
    final file = File(p.join(dir.path, asset.name));
    await file.writeAsString('keep this file');
    await expectLater(restore('smith'), throwsFormatException);
    expect(await file.readAsString(), 'keep this file');
    await file.delete();
    final outside = File(p.join(root.path, 'outside.png'));
    await outside.writeAsBytes(bytes);
    await Link(file.path).create(outside.path);
    await expectLater(restore('smith'), throwsA(isA<FileSystemException>()));
    expect(await outside.readAsBytes(), bytes);
  });

  test('same revision cannot replace its immutable asset set', () async {
    await seed('smith');
    await store('smith');
    await expectLater(
      db.transaction(
        (txn) => LibraryDocumentAssets.store(
          txn,
          itemId: 'smith',
          sourceHash: revision,
          assets: [],
        ),
      ),
      throwsStateError,
    );
    expect(await db.query('library_document_assets'), hasLength(1));
    expect(await restore('smith'), isNotNull);
  });

  test(
    'collection reads only referenced hash-verified regular files',
    () async {
      final extraction = Directory(p.join(root.path, 'extraction'));
      await extraction.create();
      await File(p.join(extraction.path, asset.name)).writeAsBytes(bytes);
      await File(
        p.join(extraction.path, 'unrelated-modern-cover.png'),
      ).writeAsString('omit');
      final collected = await LibraryDocumentAssets.collect(
        blocks: [block('smith')],
        directory: extraction,
      );
      expect(collected.map((a) => a.name), [asset.name]);
      await File(
        p.join(extraction.path, asset.name),
      ).writeAsString('wrong bytes');
      await expectLater(
        LibraryDocumentAssets.collect(
          blocks: [block('smith')],
          directory: extraction,
        ),
        throwsFormatException,
      );
    },
  );
}
