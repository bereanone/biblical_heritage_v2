import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/lessons_reading_edition.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Database db;
  const old = LessonsReadingEdition.legacyItemId;
  const fresh = LessonsReadingEdition.itemId;
  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY,value TEXT)',
    );
  });
  tearDown(() => db.close());
  Future<void> shelf(List<String> ids) => db.insert('app_settings', {
    'key': 'elibrary_top_shelf_v1',
    'value': jsonEncode(ids),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<List<dynamic>> ids() async => jsonDecode(
    (await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: ['elibrary_top_shelf_v1'],
        )).single['value']
        as String,
  );
  test(
    'replaces shelf shortcut once, preserves study data and respects later removal',
    () async {
      await shelf(['first', old, 'last']);
      await db.insert('app_settings', {
        'key': 'personal',
        'value': 'unchanged',
      });
      await LessonsReadingEdition.offerOnExistingShelf(db, {
        'first',
        old,
        fresh,
        'last',
      });
      expect(await ids(), ['first', fresh, 'last']);
      await shelf(['first', old, 'last']);
      await LessonsReadingEdition.offerOnExistingShelf(db, {old, fresh});
      expect(await ids(), ['first', old, 'last']);
      expect(
        (await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: ['personal'],
        )).single['value'],
        'unchanged',
      );
    },
  );
  test(
    'waits for available edition and preserves ordering without duplicates',
    () async {
      await shelf([old, 'other']);
      await LessonsReadingEdition.offerOnExistingShelf(db, {old});
      expect(await ids(), [old, 'other']);
      expect(
        await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: [LessonsReadingEdition.shelfDeliveryKey],
        ),
        isEmpty,
      );
      await shelf(['other', fresh, old]);
      await LessonsReadingEdition.offerOnExistingShelf(db, {old, fresh});
      expect(await ids(), ['other', fresh]);
    },
  );
  test('cleans up the already delivered duplicate shelf without deleting books', () async {
    await shelf(['first', old, fresh, 'last']);
    await db.insert('app_settings', {'key': 'library.lof_reading_edition_shelf_v1', 'value': '1'});
    await LessonsReadingEdition.offerOnExistingShelf(db, {old, fresh});
    expect(await ids(), ['first', fresh, 'last']);
  });
  test('does not promote a deleted or unselected older copy', () async {
    await shelf(['other', old]);
    await LessonsReadingEdition.offerOnExistingShelf(db, {fresh});
    expect(await ids(), ['other', old]);
  });
  test(
    'keeps new users uncurated and leaves malformed preferences untouched',
    () async {
      await LessonsReadingEdition.offerOnExistingShelf(db, {fresh});
      expect(
        await db.query(
          'app_settings',
          where: 'key=?',
          whereArgs: ['elibrary_top_shelf_v1'],
        ),
        isEmpty,
      );
      await db.delete('app_settings');
      await db.insert('app_settings', {
        'key': 'elibrary_top_shelf_v1',
        'value': 'malformed',
      });
      await LessonsReadingEdition.offerOnExistingShelf(db, {old, fresh});
      expect((await db.query('app_settings')).single['value'], 'malformed');
    },
  );
}
