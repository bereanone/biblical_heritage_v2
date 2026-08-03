import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/reader/data/cross_reference_repository.dart';

void main() {
  late Database database;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath);
    await database.execute('''
      CREATE TABLE cross_references (
        source_verse_id INTEGER NOT NULL,
        target_verse_id INTEGER NOT NULL,
        score INTEGER NOT NULL,
        source_reference TEXT,
        target_reference TEXT,
        PRIMARY KEY (source_verse_id, target_verse_id)
      )
    ''');
    await database.insert('cross_references', {
      'source_verse_id': 1,
      'target_verse_id': 3,
      'score': 4,
      'target_reference': 'Genesis 1:3',
    });
    await database.insert('cross_references', {
      'source_verse_id': 1,
      'target_verse_id': 2,
      'score': 20,
      'target_reference': 'Genesis 1:2',
    });
  });

  tearDown(() => database.close());

  test('retrieves a canonical verse ID sorted by score descending', () async {
    final repository = CrossReferenceRepository(database: database);
    final references = await repository.forVerse(1);
    expect(references.map((item) => item.targetVerseId), [2, 3]);
    expect(references.map((item) => item.score), [20, 4]);
  });
}
