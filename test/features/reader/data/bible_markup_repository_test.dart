import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/data/bible_markup_repository.dart';
import 'package:studybible2/features/reader/presentation/viewer_passage_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late BibleMarkupRepository repository;
  final lines = [
    for (var verse = 1; verse <= 12; verse++)
      VerseLine(
        blockId: verse,
        bookNumber: 45,
        chapter: 3,
        verse: verse,
        html: '',
        text: '',
      ),
  ];
  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    repository = BibleMarkupRepository(database: db);
    for (final table in ['hash_tags', 'dollar_tags', 'at_tags']) {
      await db.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY, tag TEXT, book_number INTEGER, chapter_number INTEGER, verse_number INTEGER, deleted_at_utc TEXT, trashed_at_utc TEXT)',
      );
    }
    for (final table in ['tag_items', 'bookmarks', 'notes']) {
      await db.execute(
        'CREATE TABLE $table (id INTEGER PRIMARY KEY, tag_group_id TEXT, book_id INTEGER, chapter INTEGER, verse_start INTEGER, verse_end INTEGER, deleted_at TEXT, trashed_at TEXT)',
      );
    }
    await db.execute(
      'CREATE TABLE tag_groups (id TEXT, name TEXT, tag_kind TEXT, deleted_at TEXT, trashed_at TEXT)',
    );
    await db.execute('CREATE TABLE highlights (verse_ref TEXT)');
  });
  tearDown(() => db.close());
  Future<BibleVerseMarkup> load() => repository.loadVerseMarkup(
    lines: lines,
    bookNamesByNumber: {45: 'Romans'},
  );
  test(
    'legacy and range tags underline every verse, other markings do not',
    () async {
      for (final entry in {
        'hash_tags': 1,
        'dollar_tags': 5,
        'at_tags': 6,
      }.entries) {
        await db.insert(entry.key, {
          'book_number': 45,
          'chapter_number': 3,
          'verse_number': entry.value,
        });
      }
      await db.insert('tag_items', {
        'book_id': 45,
        'chapter': 3,
        'verse_start': 2,
        'verse_end': 4,
      });
      await db.insert('notes', {
        'book_id': 45,
        'chapter': 3,
        'verse_start': 7,
        'verse_end': 7,
      });
      await db.insert('bookmarks', {
        'book_id': 45,
        'chapter': 3,
        'verse_start': 8,
        'verse_end': 8,
      });
      await db.insert('highlights', {'verse_ref': 'Romans 3:9'});
      final result = await load();
      expect(result.taggedVerseKeys, {for (var v = 1; v <= 6; v++) '45:3:$v'});
      expect(result.markedVerseKeys, {for (var v = 1; v <= 9; v++) '45:3:$v'});
      await db.delete('hash_tags');
      expect((await load()).taggedVerseKeys.contains('45:3:1'), isFalse);
    },
  );
  test(
    'membership finds overlapping ranges, deduplicates and excludes removed tags',
    () async {
      await db.insert('hash_tags', {
        'tag': '#Sabbath',
        'book_number': 45,
        'chapter_number': 3,
        'verse_number': 3,
      });
      await db.insert('dollar_tags', {
        'tag': 'Sabbath',
        'book_number': 45,
        'chapter_number': 3,
        'verse_number': 4,
      });
      await db.insert('hash_tags', {
        'tag': 'Deleted',
        'book_number': 45,
        'chapter_number': 3,
        'verse_number': 3,
        'deleted_at_utc': 'now',
      });
      await db.insert('hash_tags', {
        'tag': 'Trash',
        'book_number': 45,
        'chapter_number': 3,
        'verse_number': 3,
        'trashed_at_utc': 'now',
      });
      await db.insert('tag_groups', {
        'id': 'g',
        'name': 'Faith',
        'tag_kind': 'hash',
      });
      await db.insert('tag_items', {
        'tag_group_id': 'g',
        'book_id': 45,
        'chapter': 3,
        'verse_start': 2,
        'verse_end': 6,
      });
      expect(await repository.loadTagNamesForVerses(lines.sublist(2, 4)), [
        'Faith',
        'Sabbath',
      ]);
      await db.update('tag_groups', {'deleted_at': 'now'});
      expect(await repository.loadTagNamesForVerses(lines.sublist(2, 4)), [
        'Sabbath',
      ]);
      expect(await repository.loadTagNamesForVerses([lines.last]), isEmpty);
    },
  );
}
