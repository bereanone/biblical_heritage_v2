import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/utilities/data/downloaded_lessons_presentation.dart';

void main() {
  late Database library;
  late Database settings;
  setUp(() async {
    sqfliteFfiInit();
    library = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    settings = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await library.execute(
      'CREATE TABLE library_items(id TEXT PRIMARY KEY, cover_path TEXT, deleted_at TEXT)',
    );
    await settings.execute(
      'CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT)',
    );
    await library.insert('library_items', {
      'id': 'lof',
      'cover_path': 'old.png',
    });
    await library.insert('library_items', {
      'id': 'wor',
      'cover_path': 'wor.png',
    });
    await settings.insert('app_settings', {
      'key': DownloadedLessonsPresentation.shelfKey,
      'value': '["daniel","cross"]',
    });
  });
  tearDown(() async {
    await library.close();
    await settings.close();
  });
  Future<bool> apply(String title, {String id = 'lof', bool success = true}) =>
      DownloadedLessonsPresentation.apply(
        libraryDb: library,
        settingsDb: settings,
        itemId: id,
        title: title,
        downloadSucceeded: success,
      );
  Future<List<dynamic>> shelf() async => jsonDecode(
    (await settings.query('app_settings')).single['value']! as String,
  );
  test(
    'successful download applies cover and appends once without moving other books',
    () async {
      expect(await apply('Lessons on Faith'), isTrue);
      expect(await apply('Lessons on Faith'), isTrue);
      expect(await shelf(), ['daniel', 'cross', 'lof']);
      expect(
        (await library.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['lof'],
        )).single['cover_path'],
        DownloadedLessonsPresentation.coverPath,
      );
      expect(
        (await library.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['wor'],
        )).single['cover_path'],
        'wor.png',
      );
    },
  );
  test(
    'failed download and Waggoner never promote or override covers',
    () async {
      expect(await apply('Lessons on Faith', success: false), isFalse);
      expect(await apply('Waggoner on Romans', id: 'wor'), isFalse);
      expect(await shelf(), ['daniel', 'cross']);
      expect(
        (await library.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['lof'],
        )).single['cover_path'],
        'old.png',
      );
    },
  );
  test('missing or removed item cannot be promoted', () async {
    expect(await apply('Lessons on Faith', id: 'missing'), isFalse);
    await library.update(
      'library_items',
      {'deleted_at': 'removed'},
      where: 'id=?',
      whereArgs: ['lof'],
    );
    expect(await apply('Lessons on Faith'), isFalse);
    expect(await shelf(), ['daniel', 'cross']);
  });
}
