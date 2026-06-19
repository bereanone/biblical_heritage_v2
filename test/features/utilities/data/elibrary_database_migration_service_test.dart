import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/bootstrap/library_root_service.dart';
import 'package:studybible2/core/bootstrap/local_settings_store.dart';
import 'package:studybible2/core/database/elibrary_database.dart';
import 'package:studybible2/core/database/user_database.dart';
import 'package:studybible2/features/utilities/data/elibrary_database_migration_service.dart';

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

Future<void> _seedLibraryItem(Database db, String id, String title) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'library_items',
    <String, Object?>{
      'id': id,
      'title': title,
      'file_name': '$id.epub',
      'relative_path': 'ePubs/EGW_Books/$id.epub',
      'file_hash': 'hash-$id',
      'file_size': 123,
      'modified_at': now,
      'mime_type': 'application/epub+zip',
      'file_format': 'epub',
      'folder_type': 'research',
      'library_role': 'research',
      'collection_name': 'EGW Books',
      'source_site': 'egwwritings.org',
      'source_url': 'https://example.invalid/$id',
      'cover_path': null,
      'date_added': now,
      'last_opened': null,
      'source_type': 'official_download',
      'indexed_at': now,
      'index_status': 'indexed',
      'index_error': null,
      'epub_href': null,
      'epub_cfi': null,
      'anchor_id': null,
      'spine_index': null,
      'paragraph_index': null,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': 'device-test',
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedLibraryLink(Database db, String itemId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'library_links',
    <String, Object?>{
      'id': 'link-$itemId',
      'library_item_id': itemId,
      'book_id': 1,
      'chapter': 1,
      'verse_start': 1,
      'verse_end': 1,
      'link_type': 'research',
      'anchor': 'anchor-1',
      'original_reference_text': 'John 1:1',
      'confidence': 1.0,
      'parser_warning': null,
      'epub_href': 'OEBPS/content01.xhtml',
      'epub_cfi': null,
      'anchor_id': 'anchor-1',
      'spine_index': 1,
      'paragraph_index': 1,
      'full_paragraph': 'In the beginning was the Word.',
      'created_by': 'test',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': 'device-test',
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedNavigationItem(Database db, String itemId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'library_navigation_items',
    <String, Object?>{
      'id': 'nav-$itemId',
      'library_item_id': itemId,
      'parent_id': null,
      'label': 'Chapter 1',
      'href': 'OEBPS/content01.xhtml',
      'anchor_id': null,
      'spine_index': 1,
      'sort_order': 1,
      'depth': 1,
      'nav_type': 'chapter',
      'content_kind': 'body',
      'is_front_matter': 0,
      'is_body_start': 1,
      'body_order': 1,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': 'device-test',
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedTextBlock(Database db, String itemId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'library_text_blocks',
    <String, Object?>{
      'id': 1,
      'library_item_id': itemId,
      'epub_href': 'OEBPS/content01.xhtml',
      'spine_index': 1,
      'paragraph_index': 1,
      'paragraph_on_section': 1,
      'section_title': 'Chapter 1',
      'plain_text': 'The church is God’s appointed agency.',
      'created_at': now,
      'updated_at': now,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedRefIndex(Database db, String itemId) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'elibrary_ref_index',
    <String, Object?>{
      'id': 1,
      'library_item_id': itemId,
      'work_key': 'AA',
      'edition_key': 'AA-1',
      'edition_year': 1911,
      'book_title': 'The Acts of the Apostles',
      'book_abbrev': 'AA',
      'href': 'OEBPS/content01.xhtml',
      'anchor_id': null,
      'paragraph_index': 1,
      'page_number': 1,
      'paragraph_on_page': 1,
      'ref_code': 'AA 1.1',
      'stable_ref': 'AA 1.1',
      'plain_text': 'The church is God’s appointed agency.',
      'text_hash': 'hash-1',
      'ref_source': 'legacy',
      'created_at': now,
      'updated_at': now,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedMarkup(Database db, String itemId, {required int id}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'elibrary_markups',
    <String, Object?>{
      'id': id,
      'library_item_id': itemId,
      'epub_href': 'OEBPS/content01.xhtml',
      'start_block_index': 1,
      'start_char_offset': 0,
      'end_block_index': 1,
      'end_char_offset': 10,
      'start_token_index': null,
      'end_token_index': null,
      'ref_start': 'AA 1.1',
      'ref_end': 'AA 1.1',
      'compact_ref': 'AA 1.1',
      'selected_text_snapshot': 'The church is God’s appointed agency.',
      'markup_type': 'highlight',
      'color': '#F7D87D',
      'note_text': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> _seedInstallEstimate({
  required Database db,
  required String collectionKey,
  required String format,
  required int fileCount,
}) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert(
    'elibrary_install_estimates',
    <String, Object?>{
      'collection_key': collectionKey,
      'format': format,
      'file_count': fileCount,
      'total_size_bytes': 123,
      'size_known': 1,
      'last_checked_utc': now,
      'source': 'test',
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<int> _countRows(Database db, String table) async {
  final rows = await db.rawQuery('SELECT COUNT(*) AS cnt FROM "$table"');
  return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory supportDir;
  late Directory documentsDir;
  late Directory libraryRootDir;
  const itemId = 'acts-legacy';

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('elibrary_db_migration_support_');
    documentsDir = await Directory.systemTemp.createTemp('elibrary_db_migration_documents_');
    libraryRootDir = await Directory.systemTemp.createTemp('elibrary_db_migration_root_');
    LibraryRootService.instance.invalidateCachedSelection();
    await _installPathProviderMocks(
      supportDir: supportDir,
      documentsDir: documentsDir,
    );
    await LibraryRootService.instance.setLibraryRoot(path: libraryRootDir.path);
    await LocalSettingsStore.instance.ensureDeviceId();
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

  test('dry run reports insert counts without writing', () async {
    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;

    await _seedLibraryItem(userDb, itemId, 'Source Title');
    await _seedLibraryLink(userDb, itemId);
    await _seedNavigationItem(userDb, itemId);
    await _seedTextBlock(userDb, itemId);
    await _seedRefIndex(userDb, itemId);
    await _seedMarkup(userDb, itemId, id: 1);
    await _seedInstallEstimate(
      db: userDb,
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 1,
    );

    final report = await ELibraryDatabaseMigrationService.instance
        .buildDryRunReport();

    expect(report.schemaCompatible, isTrue);
    expect(report.migrationNeeded, isTrue);
    expect(report.sourceRowCount, 7);
    expect(report.wouldInsertRowCount, 7);
    expect(report.insertedRowCount, 0);
    expect(report.tableReports, hasLength(7));
    expect(await _countRows(eLibraryDb, 'library_items'), 0);
    expect(await _countRows(eLibraryDb, 'library_links'), 0);
    expect(await _countRows(eLibraryDb, 'library_navigation_items'), 0);
    expect(await _countRows(eLibraryDb, 'library_text_blocks'), 0);
    expect(await _countRows(eLibraryDb, 'elibrary_ref_index'), 0);
    expect(await _countRows(eLibraryDb, 'elibrary_markups'), 0);
    expect(await _countRows(eLibraryDb, 'elibrary_install_estimates'), 0);
  });

  test('copy is idempotent and preserves existing eLibrary rows', () async {
    final userDb = await UserDatabase.instance.database;
    final eLibraryDb = await ELibraryDatabase.instance.database;

    await _seedLibraryItem(userDb, itemId, 'Source Title');
    await _seedLibraryLink(userDb, itemId);
    await _seedNavigationItem(userDb, itemId);
    await _seedTextBlock(userDb, itemId);
    await _seedRefIndex(userDb, itemId);
    await _seedMarkup(userDb, itemId, id: 1);
    await _seedInstallEstimate(
      db: userDb,
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 1,
    );

    await _seedLibraryItem(eLibraryDb, itemId, 'Destination Title');
    await _seedInstallEstimate(
      db: eLibraryDb,
      collectionKey: 'egw_books',
      format: 'epub',
      fileCount: 99,
    );

    final firstReport = await ELibraryDatabaseMigrationService.instance
        .copyLegacyData(createBackups: false);

    expect(firstReport.schemaCompatible, isTrue);
    expect(firstReport.migrationComplete, isTrue);
    expect(firstReport.wouldInsertRowCount, 5);
    expect(firstReport.insertedRowCount, 5);
    expect(firstReport.tableReports.firstWhere((r) => r.tableName == 'library_items').wouldInsertRowCount, 0);
    expect(firstReport.tableReports.firstWhere((r) => r.tableName == 'elibrary_install_estimates').wouldInsertRowCount, 0);

    expect(await _countRows(eLibraryDb, 'library_items'), 1);
    expect(await _countRows(eLibraryDb, 'library_links'), 1);
    expect(await _countRows(eLibraryDb, 'library_navigation_items'), 1);
    expect(await _countRows(eLibraryDb, 'library_text_blocks'), 1);
    expect(await _countRows(eLibraryDb, 'elibrary_ref_index'), 1);
    expect(await _countRows(eLibraryDb, 'elibrary_markups'), 1);
    expect(await _countRows(eLibraryDb, 'elibrary_install_estimates'), 1);

    final itemRows = await eLibraryDb.query(
      'library_items',
      columns: const ['title'],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    expect(itemRows.single['title'], 'Destination Title');

    final estimateRows = await eLibraryDb.query(
      'elibrary_install_estimates',
      columns: const ['file_count'],
      where: 'collection_key = ? AND format = ?',
      whereArgs: ['egw_books', 'epub'],
      limit: 1,
    );
    expect(estimateRows.single['file_count'], 99);

    final secondReport = await ELibraryDatabaseMigrationService.instance
        .copyLegacyData(createBackups: false);

    expect(secondReport.wouldInsertRowCount, 0);
    expect(secondReport.insertedRowCount, 0);
    expect(secondReport.migrationComplete, isTrue);
  });
}
