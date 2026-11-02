import 'package:crypto/crypto.dart';
import 'package:studybible2/features/library/data/library_document_assets.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';
import 'package:studybible2/features/reader/data/commentary_research_library_service.dart';

Future<void> _installPathProviderMocks({
  required Directory supportDir,
  required Directory documentsDir,
}) async {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'getApplicationSupportDirectory':
            return supportDir.path;
          case 'getApplicationDocumentsDirectory':
            return documentsDir.path;
          case 'getTemporaryDirectory':
            return supportDir.path;
          case 'getLibraryDirectory':
            return supportDir.path;
        }
        return supportDir.path;
      });
}

void main() {
  // This fixture owns its complete catalog. Mobile provisioning adds shipped
  // books automatically and is verified in the dedicated delivery tests.
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.macOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory rootDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'catalog_storage_state_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'catalog_storage_state_documents_',
    );
    rootDir = await Directory.systemTemp.createTemp(
      'catalog_storage_state_root_',
    );
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: rootDir.path);
    // Own the fixture catalog even when the shipped seed gains new books.
    final db = await ELibraryDatabase.instance.database;
    await db.delete('library_items');
  });

  tearDown(() async {
    LibraryRootService.instance.invalidateCachedSelection();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await UserDatabase.instance.close();
    await ELibraryDatabase.instance.close();
    for (final dir in <Directory>[supportDir, documentsDir, rootDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  Future<String> seedRemovedAfterIndexItem() async {
    final db = await ELibraryDatabase.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    const itemId = 'removed_pilot_item';
    await db.insert('library_items', <String, Object?>{
      'id': itemId,
      'title': 'Canonically Indexed Pilot Book',
      'file_name': 'pilot.epub',
      'relative_path': p.join('ePubs', 'EGW', 'EGW_Books', 'pilot.epub'),
      'file_format': 'epub',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'EGW_Books',
      'source_type': 'official_download',
      'index_status': 'metadata_only',
      'epub_storage_state': 'removed_after_index',
      'epub_removed_at': now,
      'created_at': now,
      'updated_at': now,
      'device_id': 'test-device',
    });
    return itemId;
  }

  test(
    'hydration keeps explicit publisher artwork above an embedded fallback',
    () async {
      final id = await seedRemovedAfterIndexItem();
      final db = await ELibraryDatabase.instance.database;
      const cover = 'assets/icons/GoldLogo.png';
      await db.update(
        'library_items',
        {'cover_path': cover, 'author': 'Author'},
        where: 'id=?',
        whereArgs: [id],
      );
      final sourceHash = 'a' * 64;
      final bytes = await File(cover).readAsBytes();
      final asset = LibraryDocumentAsset('${sha256.convert(bytes)}.png', bytes);
      await db.insert('library_document_conversion', {
        'library_item_id': id,
        'canonicalizer_version': 1,
        'source_hash': sourceHash,
        'status': 'complete',
      });
      await LibraryDocumentAssets.store(
        db,
        itemId: id,
        sourceHash: sourceHash,
        assets: [asset],
        coverAssetName: asset.name,
      );
      final items = await LibraryCatalogService.instance.loadItems();
      expect(items.singleWhere((item) => item.id == id).coverPath, cover);
      expect(
        (await db.query(
          'library_items',
          where: 'id=?',
          whereArgs: [id],
        )).single['cover_path'],
        cover,
      );
    },
  );

  test(
    'retained EPUB with readable canonical text does not need legacy reindexing',
    () async {
      final id = await seedRemovedAfterIndexItem();
      final db = await ELibraryDatabase.instance.database;
      await db.update(
        'library_items',
        {'epub_storage_state': 'present', 'index_status': 'indexed'},
        where: 'id=?',
        whereArgs: [id],
      );
      await db.insert('library_document_sections', {
        'id': 'section',
        'library_item_id': id,
        'display_order': 0,
      });
      await db.insert('library_document_blocks', {
        'id': 'body',
        'library_item_id': id,
        'section_id': 'section',
        'display_order': 0,
        'block_type': 'paragraph',
        'plain_text': 'The included book is already ready to read and search.',
      });
      expect(
        await LibraryCatalogService.instance.countUnindexedManagedItems(),
        0,
      );
      expect(
        await LibraryCatalogService.instance.listUnindexedManagedItems(),
        isEmpty,
      );
      await db.delete('library_document_blocks');
      expect(
        await LibraryCatalogService.instance.countUnindexedManagedItems(),
        1,
      );
      expect(
        (await LibraryCatalogService.instance.listUnindexedManagedItems())
            .single
            .id,
        id,
      );
    },
  );

  test(
    'a canonically-indexed item with its EPUB removed is excluded from unindexed counts/lists',
    () async {
      await seedRemovedAfterIndexItem();

      final count = await LibraryCatalogService.instance
          .countUnindexedManagedItems();
      final list = await LibraryCatalogService.instance
          .listUnindexedManagedItems();

      expect(count, 0);
      expect(list, isEmpty);
    },
  );

  test(
    'the legacy indexer skips a canonically-indexed item with its EPUB removed instead of failing on it',
    () async {
      final itemId = await seedRemovedAfterIndexItem();

      final result = await CommentaryResearchLibraryService.instance
          .indexLocalCatalogedEpubs(rootPathOverride: rootDir.path);

      expect(result, (indexed: 0, skipped: 0, failed: 0));
      final db = await ELibraryDatabase.instance.database;
      final rows = await db.query(
        'library_items',
        columns: const <String>['index_status', 'index_error'],
        where: 'id = ?',
        whereArgs: <Object?>[itemId],
      );
      expect(rows.single['index_status'], 'metadata_only');
      expect(rows.single['index_error'], isNull);
    },
  );
}
