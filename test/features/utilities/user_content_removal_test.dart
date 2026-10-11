import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/utilities/data/user_content_removal_service.dart';

void main() {
  sqfliteFfiInit();
  test('library cleanup preserves studies and reclaims SQLite pages', () async {
    final root = await Directory.systemTemp.createTemp('removal-test-');
    final db = await databaseFactoryFfi.openDatabase(
      p.join(root.path, 'user.db'),
    );
    try {
      await db.execute('CREATE TABLE library_text_blocks (body BLOB)');
      await db.execute(
        'CREATE TABLE library_items (id INTEGER, deleted_at TEXT, is_missing INTEGER)',
      );
      await db.execute('CREATE TABLE notes (body TEXT)');
      await db.execute('CREATE TABLE bible_verses (body TEXT)');
      await db.execute('CREATE TABLE app_migrations (version INTEGER)');
      await db.execute("INSERT INTO notes VALUES ('keep personal study')");
      await db.execute("INSERT INTO bible_verses VALUES ('keep Bible')");
      await db.execute('INSERT INTO app_migrations VALUES (43)');
      await db.execute('INSERT INTO library_items VALUES (1, NULL, 0)');
      await db.execute(
        'INSERT INTO library_text_blocks VALUES (zeroblob(16777216))',
      );
      final before = await File(db.path).length();
      await UserContentRemovalService.clearDatabase(
        db,
        UserContentRemovalScope.library,
      );
      expect(await db.rawQuery('SELECT * FROM library_text_blocks'), isEmpty);
      expect((await db.query('notes')).single['body'], 'keep personal study');
      expect((await db.query('library_items')).single['is_missing'], 1);
      expect(await File(db.path).length(), lessThan(before ~/ 10));
      await UserContentRemovalService.clearDatabase(
        db,
        UserContentRemovalScope.allUserData,
      );
      expect(await db.query('notes'), isEmpty);
      expect(await db.query('library_items'), isEmpty);
      expect((await db.query('bible_verses')).single['body'], 'keep Bible');
      expect((await db.query('app_migrations')).single['version'], 43);
      expect(
        (await db.rawQuery('PRAGMA quick_check')).single.values.single,
        'ok',
      );
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
  test('bundled Bible database cannot be cleared', () async {
    final root = await Directory.systemTemp.createTemp('protected-bible-');
    final db = await databaseFactoryFfi.openDatabase(
      p.join(root.path, 'bible_base.db'),
    );
    try {
      await expectLater(
        UserContentRemovalService.clearDatabase(
          db,
          UserContentRemovalScope.allUserData,
        ),
        throwsStateError,
      );
    } finally {
      await db.close();
      await root.delete(recursive: true);
    }
  });
  test(
    'outside files, symlinks and bundled databases are not eligible',
    () async {
      final root = await Directory.systemTemp.createTemp('file-isolation-');
      try {
        await Directory(p.join(root.path, 'ePubs')).create();
        final owned = File(p.join(root.path, 'ePubs', 'book.epub'));
        await owned.writeAsString('owned');
        final outside = File(p.join(root.path, 'original.epub'));
        await outside.writeAsString('source');
        await File(
          p.join(root.path, 'ePubs', 'bible_base.db'),
        ).writeAsString('Bible');
        await Link(
          p.join(root.path, 'ePubs', 'linked.epub'),
        ).create(outside.path);
        final files = await UserContentRemovalService.scanFiles(root.path, [
          'ePubs',
        ]);
        expect(files.keys, [owned.path]);
        expect(await outside.readAsString(), 'source');
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
