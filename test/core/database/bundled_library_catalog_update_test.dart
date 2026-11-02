import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/core/database/elibrary_schema.dart';
import 'package:studybible2/core/database/bundled_library_catalog_update.dart';

Future<Database> fresh() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA foreign_keys=ON');
  await ELibrarySchema.ensure(db);
  return db;
}

Future<void> book(
  Database db,
  String id,
  String title, {
  String? deleted,
}) async {
  await db.insert('library_items', {
    'id': id,
    'title': title,
    'file_name': '$id.html',
    'relative_path': '$id.html',
    'created_at': 'original',
    'updated_at': 'original',
    'device_id': 'test',
    'last_opened': 'reading-position',
    'deleted_at': deleted,
  });
  await db.insert('library_text_blocks', {
    'library_item_id': id,
    'epub_href': 'body',
    'paragraph_index': 0,
    'plain_text': title,
    'created_at': 'original',
    'updated_at': 'original',
  });
}

void main() {
  sqfliteFfiInit();
  late Database source, destination;
  setUp(() async {
    source = await fresh();
    destination = await fresh();
  });
  tearDown(() async {
    await source.close();
    await destination.close();
  });
  Future<int> update({
    String revision = 'v2',
    Set<String> ids = const {'bundled'},
  }) => BundledLibraryCatalogUpdate.apply(
    destination: destination,
    source: source,
    managedItemIds: ids,
    revision: revision,
  );

  test(
    'fresh install receives managed content and repeated update is idempotent',
    () async {
      await book(source, 'bundled', 'New book');
      expect(await update(), 1);
      expect(await update(), 0);
      expect(
        (await destination.query('library_items')).single['title'],
        'New book',
      );
      expect((await destination.query('library_text_blocks')).length, 1);
    },
  );
  test(
    'in-place update preserves annotations and unrelated user content',
    () async {
      await book(source, 'bundled', 'New text');
      await book(destination, 'bundled', 'Old text');
      await book(destination, 'user-owned', 'Personal import');
      await destination.execute(
        'CREATE TABLE test_notes (id TEXT PRIMARY KEY, '
        'item TEXT REFERENCES library_items(id) ON DELETE CASCADE, text TEXT)',
      );
      await destination.insert('test_notes', {
        'id': 'note',
        'item': 'bundled',
        'text': 'Keep my annotation',
      });
      final unrelated = await destination.query(
        'library_items',
        where: 'id=?',
        whereArgs: ['user-owned'],
      );
      expect(await update(), 1);
      expect(
        (await destination.query('test_notes')).single['text'],
        'Keep my annotation',
      );
      expect(
        await destination.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['user-owned'],
        ),
        unrelated,
      );
      expect(
        (await destination.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['bundled'],
        )).single['last_opened'],
        'reading-position',
      );
      expect(
        (await destination.query(
          'library_text_blocks',
          where: 'library_item_id=?',
          whereArgs: ['bundled'],
        )).single['plain_text'],
        'New text',
      );
      expect(await destination.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
  test(
    'book-specific revision leaves the other installed book untouched',
    () async {
      await book(source, 'bundled', 'Corrected BRHC');
      await book(source, 'second', 'Donor copy must not replace this');
      await book(destination, 'bundled', 'Older BRHC');
      await book(destination, 'second', 'Current other book');
      await destination.execute(
        'CREATE TABLE bundled_library_updates ('
        'library_item_id TEXT PRIMARY KEY, revision TEXT NOT NULL)',
      );
      for (final id in ['bundled', 'second']) {
        await destination.insert('bundled_library_updates', {
          'library_item_id': id,
          'revision': 'v1',
        });
      }
      final before = await destination.query(
        'library_items',
        where: 'id=?',
        whereArgs: ['second'],
      );
      expect(
        await BundledLibraryCatalogUpdate.apply(
          destination: destination,
          source: source,
          managedItemIds: {'bundled', 'second'},
          revision: 'v1',
          itemRevisions: {'bundled': 'corrected-brhc'},
        ),
        1,
      );
      expect(
        await destination.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['second'],
        ),
        before,
      );
    },
  );
  test(
    'reading anchor follows its block when chapter artwork changes row order',
    () async {
      await book(source, 'bundled', 'New text');
      await book(destination, 'bundled', 'Old text');
      await destination.update(
        'library_items',
        {
          'anchor_id': 'canonical:saved-block',
          'paragraph_index': 428,
          'epub_href': 'old-chapter',
        },
        where: 'id=?',
        whereArgs: ['bundled'],
      );
      await source.insert('library_document_blocks', {
        'id': 'saved-block',
        'library_item_id': 'bundled',
        'section_id': 'section',
        'display_order': 437,
        'block_type': 'heading',
        'plain_text': 'Chapter 1. The Scriptures',
        'source_href': 'epub/text/ch004.xhtml',
      });
      expect(await update(), 1);
      final row = (await destination.query('library_items')).single;
      expect(row['anchor_id'], 'canonical:saved-block');
      expect(row['paragraph_index'], 437);
      expect(row['epub_href'], 'epub/text/ch004.xhtml');
    },
  );
  test('content update does not resurrect a user-trashed book', () async {
    await book(source, 'bundled', 'New text');
    await book(destination, 'bundled', 'Old text', deleted: 'user-trash-time');
    expect(await update(), 0);
    expect(
      (await destination.query('library_items')).single['deleted_at'],
      'user-trash-time',
    );
    expect(
      (await destination.query('library_text_blocks')).single['plain_text'],
      'Old text',
    );
  });
  test('incomplete bundle leaves installed content untouched', () async {
    await book(source, 'bundled', 'New text');
    await book(destination, 'bundled', 'Old text');
    await expectLater(
      update(ids: {'bundled', 'missing'}),
      throwsFormatException,
    );
    expect(
      (await destination.query('library_items')).single['title'],
      'Old text',
    );
  });
  test(
    'failure halfway through multiple books rolls the entire update back',
    () async {
      await book(source, 'bundled', 'New text');
      await book(source, 'second', 'Second');
      await book(destination, 'bundled', 'Old text');
      await book(destination, 'user-owned', 'Personal');
      final nav = {
        'id': 'collision',
        'library_item_id': 'second',
        'label': 'Contents',
        'created_at': 'original',
        'updated_at': 'original',
        'device_id': 'test',
      };
      await source.insert('library_navigation_items', nav);
      await destination.insert('library_navigation_items', {
        ...nav,
        'library_item_id': 'user-owned',
      });
      await expectLater(
        update(ids: {'bundled', 'second'}),
        throwsA(isA<DatabaseException>()),
      );
      expect(
        (await destination.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['bundled'],
        )).single['title'],
        'Old text',
      );
      expect(
        await destination.query(
          'library_items',
          where: 'id=?',
          whereArgs: ['second'],
        ),
        isEmpty,
      );
      final tables = await destination.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='bundled_library_updates'",
      );
      if (tables.isNotEmpty)
        expect(await destination.query('bundled_library_updates'), isEmpty);
    },
  );
}
