import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:studybible2/core/database/elibrary_schema.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('additive package-lineage migration preserves legacy rows', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''
      CREATE TABLE library_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT,
        file_name TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        file_hash TEXT,
        folder_type TEXT,
        collection_name TEXT,
        source_type TEXT,
        deleted_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        device_id TEXT NOT NULL
      )
    ''');
    await db.insert('library_items', <String, Object?>{
      'id': 'legacy-item',
      'title': 'Legacy Book',
      'file_name': 'legacy.html',
      'relative_path': 'legacy/legacy.html',
      'file_hash': 'legacy-hash',
      'created_at': '2026-01-01T00:00:00Z',
      'updated_at': '2026-01-01T00:00:00Z',
      'device_id': 'legacy-device',
    });

    await ELibrarySchema.ensure(db);

    final columns = await db.rawQuery('PRAGMA table_info(library_items)');
    final names = columns.map((row) => row['name']).toSet();
    expect(names, containsAll(<String>['source_work_id', 'source_package_id']));
    final rows = await db.query(
      'library_items',
      where: 'id = ?',
      whereArgs: ['legacy-item'],
    );
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Legacy Book');
    expect(rows.single['file_hash'], 'legacy-hash');
    expect(rows.single['source_work_id'], isNull);
    expect(rows.single['source_package_id'], isNull);
    expect(await ELibrarySchema.currentAppliedVersion(db), 2);
  });
}
