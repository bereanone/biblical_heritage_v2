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
