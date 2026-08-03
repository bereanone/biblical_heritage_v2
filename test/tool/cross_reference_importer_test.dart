import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../tool/cross_reference_importer.dart';

void main() {
  late Directory temporaryDirectory;
  late String biblePath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('xref_test_');
    biblePath = p.join(temporaryDirectory.path, 'bible.db');
    final db = await openDatabase(biblePath);
    await db.execute(
      'CREATE TABLE books (book_number INTEGER, book_name TEXT)',
    );
    await db.execute(
      '''CREATE TABLE bible_blocks (
      id INTEGER, book_number INTEGER, chapter INTEGER, block_index INTEGER)''',
    );
    await db.insert('books', {'book_number': 1, 'book_name': 'Genesis'});
    await db.insert('books', {'book_number': 9, 'book_name': '1 Samuel'});
    await db.insert('books', {'book_number': 19, 'book_name': 'Psalms'});
    await db.insert('books', {'book_number': 43, 'book_name': 'John'});
    final verses = [
      [1, 1, 1, 1],
      [2, 1, 1, 2],
      [3, 1, 1, 3],
      [4, 1, 2, 1],
      [5, 9, 1, 1],
      [6, 19, 23, 1],
      [7, 43, 3, 16],
    ];
    for (final verse in verses) {
      await db.insert('bible_blocks', {
        'id': verse[0],
        'book_number': verse[1],
        'chapter': verse[2],
        'block_index': verse[3],
      });
    }
    await db.close();
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test('parses normal, numbered, alternate, and ranged references', () async {
    final importer = await CrossReferenceImporter.fromBibleDatabase(biblePath);
    expect(importer.parseReference('Gen.1.1').start.id, 1);
    expect(importer.parseReference('1Sam.1.1').start.id, 5);
    expect(importer.parseReference('I Samuel 1:1').start.id, 5);
    expect(importer.parseReference('Psalm 23:1').start.id, 6);
    expect(importer.parseReference('Jn 3:16').start.id, 7);
    expect(
      importer
          .expand(importer.parseReference('Gen.1.2-Gen.2.1'))
          .map((verse) => verse.id),
      [2, 3, 4],
    );
  });

  test('rejects invalid chapters and verses', () async {
    final importer = await CrossReferenceImporter.fromBibleDatabase(biblePath);
    expect(() => importer.parseReference('Gen.99.1'), throwsFormatException);
    expect(() => importer.parseReference('Gen.1.99'), throwsFormatException);
  });

  test(
    'deduplicates by maximum score and produces deterministic data',
    () async {
      final source = p.join(temporaryDirectory.path, 'source.txt');
      File(source).writeAsStringSync(
        'From Verse\tTo Verse\tVotes\t#www.openbible.info CC-BY 2026-08-03\n'
        'Gen.1.1\tGen.1.2-Gen.1.3\t5\n'
        'Gen.1.1\tGen.1.2\t12\n'
        'Gen.1.99\tGen.1.2\t7\n',
      );
      final importer = await CrossReferenceImporter.fromBibleDatabase(
        biblePath,
      );
      final first = p.join(temporaryDirectory.path, 'first.db');
      final second = p.join(temporaryDirectory.path, 'second.db');
      final metadata = {'download_date': '2026-08-03'};
      final summary = await importer.build(
        sourcePath: source,
        outputPath: first,
        metadata: metadata,
      );
      await importer.build(
        sourcePath: source,
        outputPath: second,
        metadata: metadata,
      );
      expect(summary.rawRows, 3);
      expect(summary.importedRows, 2);
      expect(summary.duplicatesRemoved, 1);
      expect(summary.rejectedRows, 1);
      final firstDb = await openDatabase(first, readOnly: true);
      final secondDb = await openDatabase(second, readOnly: true);
      final firstRows = await firstDb.query(
        'cross_references',
        orderBy: 'source_verse_id, target_verse_id',
      );
      final secondRows = await secondDb.query(
        'cross_references',
        orderBy: 'source_verse_id, target_verse_id',
      );
      expect(firstRows, secondRows);
      expect(firstRows.first['score'], 12);
      await firstDb.close();
      await secondDb.close();
      expect(File(first).readAsBytesSync(), File(second).readAsBytesSync());
    },
  );
}
