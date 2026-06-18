import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/elibrary_schema.dart';

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
}
