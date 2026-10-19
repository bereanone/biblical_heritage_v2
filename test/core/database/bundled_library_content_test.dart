import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/bundled_library_content.dart';

class MemoryAssets extends CachingAssetBundle {
  MemoryAssets(this.files);
  final Map<String, List<int>> files;
  final loads = <String>[];
  @override
  Future<ByteData> load(String key) async {
    loads.add(key);
    final bytes = files[key];
    if (bytes == null) throw StateError('Missing test asset');
    final buffer = Uint8List.fromList([9, 9, ...bytes, 8]);
    return ByteData.view(buffer.buffer, 2, bytes.length);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory temp;
  late Database db;
  late List<int> catalog;
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  const relative = 'Research/ManagedBundles/v1/book.bin';
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bundle-test-');
    final source = await openDatabase(p.join(temp.path, 'source.db'));
    await ELibrarySchema.ensure(source);
    await source.insert('library_items', {
      'id': 'book',
      'title': 'Included book',
      'file_name': 'book.bin',
      'relative_path': relative,
      'created_at': 't',
      'updated_at': 't',
      'device_id': 'bundle',
    });
    await source.insert('library_text_blocks', {
      'library_item_id': 'book',
      'epub_href': 'body',
      'paragraph_index': 0,
      'plain_text': 'Complete text',
      'created_at': 't',
      'updated_at': 't',
    });
    await source.close();
    catalog = await File(p.join(temp.path, 'source.db')).readAsBytes();
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await ELibrarySchema.ensure(db);
  });
  tearDown(() async {
    await db.close();
    await temp.delete(recursive: true);
  });
  MemoryAssets assets({
    String destination = relative,
    bool corruptResource = false,
    bool corruptCatalog = false,
  }) {
    final manifest = {
      'revision': 'v1',
      'books': [
        {'id': 'book'},
      ],
      'catalog_asset': 'catalog',
      'catalog_sha256': sha256.convert(catalog).toString(),
      'resources': [
        {
          'asset': 'resource',
          'destination': destination,
          'bytes': bytes.length,
          'sha256': sha256.convert(bytes).toString(),
        },
      ],
    };
    return MemoryAssets({
      BundledLibraryContent.manifestAsset: utf8.encode(jsonEncode(manifest)),
      'catalog': corruptCatalog ? [0] : catalog,
      'resource': corruptResource ? [0] : bytes,
    });
  }

  test(
    'installs verified files and catalog; current revision repairs a missing file',
    () async {
      final root = p.join(temp.path, 'library');
      final first = assets();
      expect(
        await BundledLibraryContent.ensure(
          destination: db,
          libraryRoot: root,
          assets: first,
        ),
        1,
      );
      final file = File(p.join(root, relative));
      expect(await file.readAsBytes(), bytes);
      expect(
        (await db.query('library_items')).single['title'],
        'Included book',
      );
      await file.delete();
      final repeat = assets();
      expect(
        await BundledLibraryContent.ensure(
          destination: db,
          libraryRoot: root,
          assets: repeat,
        ),
        0,
      );
      expect(await file.readAsBytes(), bytes);
      expect(repeat.loads, isNot(contains('catalog')));
    },
  );
  test('corrupt resource never updates the catalog', () async {
    await expectLater(
      BundledLibraryContent.ensure(
        destination: db,
        libraryRoot: p.join(temp.path, 'library'),
        assets: assets(corruptResource: true),
      ),
      throwsFormatException,
    );
    expect(await db.query('library_items'), isEmpty);
  });
  test(
    'bundle cannot write outside the managed subtree or touch user database',
    () async {
      final user = File(p.join(temp.path, 'library/Databases/user.db'));
      await user.parent.create(recursive: true);
      await user.writeAsString('private-user-data');
      for (final path in [
        'Databases/user.db',
        'Research/ManagedBundles/../../Databases/user.db',
      ]) {
        await expectLater(
          BundledLibraryContent.ensure(
            destination: db,
            libraryRoot: p.join(temp.path, 'library'),
            assets: assets(destination: path),
          ),
          throwsFormatException,
        );
      }
      expect(await user.readAsString(), 'private-user-data');
      expect(await db.query('library_items'), isEmpty);
    },
  );
  test('catalog checksum failure leaves database unchanged', () async {
    await expectLater(
      BundledLibraryContent.ensure(
        destination: db,
        libraryRoot: p.join(temp.path, 'library'),
        assets: assets(corruptCatalog: true),
      ),
      throwsFormatException,
    );
    expect(await db.query('library_items'), isEmpty);
  });
}
