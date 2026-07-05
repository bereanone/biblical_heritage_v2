import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/elibrary_sdp_cleanup.dart';

Future<({Database db, Directory dir})> _openTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('elibrary_schema_');
  final dbPath = p.join(tempDir.path, 'eLibrary.db');
  final db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: (db, _) async {
      await ELibrarySchema.ensure(db);
    },
  );
  return (db: db, dir: tempDir);
}

Future<({Database db, Directory dir})> _openCleanupTestDatabase() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  final tempDir = await Directory.systemTemp.createTemp('elibrary_cleanup_');
  final dbPath = p.join(tempDir.path, 'eLibrary.db');
  final db = await openDatabase(dbPath, version: 1);
  await db.execute('''
    CREATE TABLE IF NOT EXISTS elibrary_schema_migrations (
      migration_key TEXT PRIMARY KEY,
      from_version INTEGER,
      to_version INTEGER NOT NULL,
      applied_at TEXT NOT NULL,
      status TEXT NOT NULL,
      details TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS library_items (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT,
      collection_name TEXT,
      source_type TEXT,
      relative_path TEXT,
      deleted_at TEXT,
      created_at TEXT,
      updated_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS library_navigation_items (
      id TEXT PRIMARY KEY,
      library_item_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS library_text_blocks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      library_item_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS elibrary_ref_index (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      library_item_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS library_links (
      id TEXT PRIMARY KEY,
      library_item_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS library_item_contributors (
      library_item_id TEXT NOT NULL,
      contributor_id TEXT NOT NULL,
      PRIMARY KEY (library_item_id, contributor_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS elibrary_markups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      library_item_id TEXT NOT NULL
    )
  ''');
  return (db: db, dir: tempDir);
}

Future<void> _seedBogusSdpItem(Database db) async {
  final now = DateTime.now().toUtc().toIso8601String();
  await db.insert('library_items', <String, Object?>{
    'id': 'library_item_research_pioneer_uriah_smith_DAR_US',
    'title': 'SDP',
    'author': 'Uriah Smith',
    'collection_name': 'Adventist Pioneer Library',
    'source_type': 'egw_html_capture',
    'relative_path':
        'TextCaptures/Research/Pioneer Authors/uriah smith/DAR/capture.html',
    'deleted_at': null,
    'created_at': now,
    'updated_at': now,
  });
  await db.insert('library_navigation_items', <String, Object?>{
    'id': 'nav-sdp',
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
  });
  await db.insert('library_text_blocks', <String, Object?>{
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
  });
  await db.insert('elibrary_ref_index', <String, Object?>{
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
  });
  await db.insert('library_links', <String, Object?>{
    'id': 'link-sdp',
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
  });
  await db.insert('library_item_contributors', <String, Object?>{
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
    'contributor_id': 'uriah-smith',
  });
  await db.insert('elibrary_markups', <String, Object?>{
    'library_item_id': 'library_item_research_pioneer_uriah_smith_DAR_US',
  });
}

Future<int> _countRows(
  Database db,
  String tableName, {
  String? where,
  List<Object?> whereArgs = const [],
}) async {
  final sql = StringBuffer('SELECT COUNT(*) AS cnt FROM "$tableName"');
  if (where != null && where.trim().isNotEmpty) {
    sql.write(' WHERE $where');
  }
  final rows = await db.rawQuery(sql.toString(), whereArgs);
  return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bootstraps the current eLibrary tables and indexes', () async {
    final setup = await _openTestDatabase();
    final db = setup.db;
    final tempDir = setup.dir;
    addTearDown(() async {
      await db.close();
      await deleteDatabase(p.join(tempDir.path, 'eLibrary.db'));
      await tempDir.delete(recursive: true);
    });

    final tableRows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
    ''');
    final tableNames = tableRows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();

    expect(
      tableNames,
      containsAll(<String>[
        'elibrary_schema_migrations',
        'elibrary_install_estimates',
        'library_items',
        'library_links',
        'library_navigation_items',
        'library_text_blocks',
        'elibrary_ref_index',
        'elibrary_markups',
      ]),
    );

    final indexRows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
    ''');
    final indexNames = indexRows
        .map((row) => row['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet();

    expect(
      indexNames,
      containsAll(<String>[
        'idx_library_links_lookup',
        'idx_library_items_folder_path',
        'idx_library_navigation_items_lookup',
        'idx_library_text_blocks_item',
        'idx_library_text_blocks_item_spine',
        'idx_library_text_blocks_item_href',
        'idx_elibrary_ref_index_lookup',
        'idx_elibrary_markups_item_href',
        'idx_elibrary_markups_item_type',
      ]),
    );

    expect(await ELibrarySchema.currentAppliedVersion(db), 1);
    expect(await ELibrarySchema.schemaStatus(db), 'ready (version 1)');
  });

  test(
    'removes the bogus SDP catalog item and its dependent rows exactly once',
    () async {
      final setup = await _openCleanupTestDatabase();
      final db = setup.db;
      final tempDir = setup.dir;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(p.join(tempDir.path, 'eLibrary.db'));
        await tempDir.delete(recursive: true);
      });

      await _seedBogusSdpItem(db);

      final removedMessages = <String>[];
      final firstReport = await ELibraryBogusSdpCleanupService.instance.run(
        db,
        log: removedMessages.add,
      );

      expect(firstReport.removed, isTrue);
      expect(
        firstReport.matchedItemId,
        'library_item_research_pioneer_uriah_smith_DAR_US',
      );
      expect(firstReport.matchedTitle, 'SDP');
      expect(firstReport.matchedAuthor, 'Uriah Smith');
      expect(firstReport.matchedCollectionName, 'Adventist Pioneer Library');
      expect(
        removedMessages.single,
        contains('Removed bogus SDP catalog item'),
      );
      expect(
        await _countRows(
          db,
          'library_items',
          where: 'id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_navigation_items',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_text_blocks',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'elibrary_ref_index',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_links',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'library_item_contributors',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );
      expect(
        await _countRows(
          db,
          'elibrary_markups',
          where: 'library_item_id = ?',
          whereArgs: const ['library_item_research_pioneer_uriah_smith_DAR_US'],
        ),
        0,
      );

      final secondReport = await ELibraryBogusSdpCleanupService.instance.run(
        db,
      );
      expect(secondReport.removed, isFalse);
      expect(secondReport.alreadyApplied, isTrue);
    },
  );

  test(
    'records a no-op cleanup when the bogus SDP catalog item is absent',
    () async {
      final setup = await _openCleanupTestDatabase();
      final db = setup.db;
      final tempDir = setup.dir;
      addTearDown(() async {
        await db.close();
        await deleteDatabase(p.join(tempDir.path, 'eLibrary.db'));
        await tempDir.delete(recursive: true);
      });

      final messages = <String>[];
      final report = await ELibraryBogusSdpCleanupService.instance.run(
        db,
        log: messages.add,
      );

      expect(report.removed, isFalse);
      expect(report.alreadyApplied, isFalse);
      expect(report.matchedItemId, isNull);
      expect(messages.single, contains('No matching bogus SDP catalog item'));
      expect(
        await _countRows(
          db,
          'elibrary_schema_migrations',
          where: 'migration_key = ?',
          whereArgs: const [kBogusSdpCleanupMigrationKey],
        ),
        1,
      );
    },
  );
}
