import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';

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

Future<void> _copyDatabaseBundle({
  required Directory sourceDir,
  required Directory destinationDir,
}) async {
  await destinationDir.create(recursive: true);
  for (final name in const [
    'eLibrary.db',
    'eLibrary.db-wal',
    'eLibrary.db-shm',
    'user.db',
    'user.db-wal',
    'user.db-shm',
  ]) {
    final sourceFile = File(p.join(sourceDir.path, name));
    if (!await sourceFile.exists()) continue;
    await sourceFile.copy(p.join(destinationDir.path, name));
  }
}

Future<void> _setLibraryItemTitle({
  required String itemId,
  required String title,
}) async {
  final db = await ELibraryDatabase.instance.database;
  await db.update(
    'library_items',
    <String, Object?>{
      'title': title,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    where: 'id = ?',
    whereArgs: [itemId],
  );
}

Future<void> _seedOfficialDownloadItem({
  required String id,
  required String code,
}) async {
  final db = await ELibraryDatabase.instance.database;
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('library_items', <String, Object?>{
    'id': id,
    'title': code,
    'author': 'Ellen G. White',
    'file_name': 'en_$code.epub',
    'relative_path': 'ePubs/Research/EGW_Books/en_$code.epub',
    'file_format': 'epub',
    'folder_type': 'research',
    'library_role': 'research',
    'collection_name': 'EGW Books',
    'source_type': 'official_download',
    'index_status': 'indexed',
    'is_missing': 0,
    'created_at': now,
    'updated_at': now,
    'device_id': 'official-title-test',
    'revision': 1,
    'sync_status': 'pending',
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  late Directory databaseDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp(
      'library_catalog_titles_support_',
    );
    documentsDir = await Directory.systemTemp.createTemp(
      'library_catalog_titles_documents_',
    );
    libraryRootDir = await Directory.systemTemp.createTemp(
      'library_catalog_titles_root_',
    );
    databaseDir = Directory(p.join(libraryRootDir.path, 'Databases'));

    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await _copyDatabaseBundle(
      sourceDir: Directory(
        p.join(Directory.current.path, 'assets', 'databases'),
      ),
      destinationDir: databaseDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await _seedOfficialDownloadItem(
      id: 'library_item_research_epubs_egw_egw_books_en_cos_epub',
      code: 'cos',
    );
    await _seedOfficialDownloadItem(
      id: 'library_item_research_epubs_egw_egw_books_en_ic_epub',
      code: 'ic',
    );
    await _seedOfficialDownloadItem(
      id: 'library_item_research_epubs_egw_egw_manuscript_releases_en_1mr_epub',
      code: '1mr',
    );
    await _seedOfficialDownloadItem(
      id: 'library_item_research_epubs_egw_egw_manuscript_releases_en_10mr_epub',
      code: '10mr',
    );
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
    if (supportDir.existsSync()) {
      await supportDir.delete(recursive: true);
    }
    if (documentsDir.existsSync()) {
      await documentsDir.delete(recursive: true);
    }
    if (libraryRootDir.existsSync()) {
      await libraryRootDir.delete(recursive: true);
    }
  });

  test(
    'official EGW title metadata repairs filename fallback titles',
    () async {
      final cos = await LibraryCatalogService.instance.loadItemById(
        'library_item_research_epubs_egw_egw_books_en_cos_epub',
      );
      final ic = await LibraryCatalogService.instance.loadItemById(
        'library_item_research_epubs_egw_egw_books_en_ic_epub',
      );

      expect(cos?.displayTitle, 'Christ Our Saviour');
      expect(ic?.displayTitle, 'The Impending Conflict');

      final db = await ELibraryDatabase.instance.database;
      final cosRow = await db.query(
        'library_items',
        columns: const ['title'],
        where: 'id = ?',
        whereArgs: ['library_item_research_epubs_egw_egw_books_en_cos_epub'],
        limit: 1,
      );
      final icRow = await db.query(
        'library_items',
        columns: const ['title'],
        where: 'id = ?',
        whereArgs: ['library_item_research_epubs_egw_egw_books_en_ic_epub'],
        limit: 1,
      );

      expect(cosRow.single['title'], 'Christ Our Saviour');
      expect(icRow.single['title'], 'The Impending Conflict');
    },
  );

  test(
    'official Manuscript Releases volume titles hydrate from abbreviated codes',
    () async {
      const volumeOneId =
          'library_item_research_epubs_egw_egw_manuscript_releases_en_1mr_epub';
      const volumeTenId =
          'library_item_research_epubs_egw_egw_manuscript_releases_en_10mr_epub';

      await _setLibraryItemTitle(itemId: volumeOneId, title: '1MR');
      await _setLibraryItemTitle(itemId: volumeTenId, title: '10MR');

      final volumeOne = await LibraryCatalogService.instance.loadItemById(
        volumeOneId,
      );
      final volumeTen = await LibraryCatalogService.instance.loadItemById(
        volumeTenId,
      );

      expect(
        volumeOne?.displayTitle,
        'Manuscript Releases, vol. 1 [Nos. 19-96]',
      );
      expect(
        volumeTen?.displayTitle,
        'Manuscript Releases, vol. 10 [Nos. 771-850]',
      );
    },
  );
}
