import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:studybible2/features/library/data/library_captured_reference_alignment.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_entry_speech.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

import '../../reader/presentation/tag_playback/tag_playback_planner_test.dart'
    show entry;

Future<Database> _db({
  String sourceType = 'pioneer_captured_html',
  List<(String text, String code)> refs = const [],
}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute(
    'CREATE TABLE library_items (id TEXT PRIMARY KEY, source_type TEXT)',
  );
  await db.execute('''
    CREATE TABLE elibrary_ref_index (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      library_item_id TEXT NOT NULL,
      plain_text TEXT,
      ref_code TEXT
    )
  ''');
  await db.insert('library_items', {'id': 'item', 'source_type': sourceType});
  for (final (text, code) in refs) {
    await db.insert('elibrary_ref_index', {
      'library_item_id': 'item',
      'plain_text': text,
      'ref_code': code,
    });
  }
  return db;
}

void main() {
  group('CapturedReferenceAlignment', () {
    test('hands each index code to the paragraph with the same text', () async {
      final db = await _db(
        refs: [('First paragraph.', 'CS 1.1'), ('Second  one.', 'CS 2.1')],
      );
      final alignment = (await CapturedReferenceAlignment.load(db, 'item'))!;

      expect(alignment.nextCodeFor('First paragraph.'), 'CS 1.1');
      // Whitespace differences between the two parses do not break a match.
      expect(alignment.nextCodeFor('Second one.'), 'CS 2.1');
      await db.close();
    });

    test(
      'leaves a paragraph unlabeled rather than guess a neighbour',
      () async {
        final db = await _db(
          refs: [('One.', 'CS 1.1'), ('Two.', 'CS 1.2'), ('Three.', 'CS 1.3')],
        );
        final alignment = (await CapturedReferenceAlignment.load(db, 'item'))!;

        expect(alignment.nextCodeFor('One.'), 'CS 1.1');
        expect(alignment.nextCodeFor('Text the index never saw.'), isNull);
        // The cursor did not move on the miss, so the next real paragraph
        // still lines up.
        expect(alignment.nextCodeFor('Two.'), 'CS 1.2');
        await db.close();
      },
    );

    test('resyncs across a paragraph the index dropped', () async {
      final db = await _db(refs: [('One.', 'CS 1.1'), ('Three.', 'CS 1.3')]);
      final alignment = (await CapturedReferenceAlignment.load(db, 'item'))!;

      expect(alignment.nextCodeFor('One.'), 'CS 1.1');
      expect(alignment.nextCodeFor('Two.'), isNull);
      expect(alignment.nextCodeFor('Three.'), 'CS 1.3');
      await db.close();
    });

    test('does not attach a repeated line from far ahead', () async {
      final db = await _db(
        refs: [
          for (var i = 1; i <= 8; i++) ('Filler $i.', 'CS 1.$i'),
          ('Amen.', 'CS 1.9'),
        ],
      );
      final alignment = (await CapturedReferenceAlignment.load(db, 'item'))!;

      expect(alignment.nextCodeFor('Amen.'), isNull);
      await db.close();
    });

    test('applies only to captured sources with synthesized codes', () async {
      final epub = await _db(
        sourceType: 'pioneer_epub_import',
        refs: [('One.', 'CS 1.1')],
      );
      expect(await CapturedReferenceAlignment.load(epub, 'item'), isNull);
      await epub.close();

      final empty = await _db();
      expect(await CapturedReferenceAlignment.load(empty, 'item'), isNull);
      await empty.close();
    });
  });

  group('tag TTS for a synthesized capture reference', () {
    HashTagEntry savedFrom(String location) => entry(
      1,
      book: 0,
      chapter: 0,
      verse: 0,
      noteText: 'Second paragraph.',
      noteFormatJson: jsonEncode({
        'kind': 'elibrary_note',
        'source_title': 'Captured Sermon',
        'source_title_acronym': 'CS',
        'source_location': location,
        'source_reference_text': location,
        'excerpt': 'Second paragraph.',
      }),
    );

    test('speaks work title, page and paragraph, never the raw code', () {
      final source = ELibraryPassageSource.tryParse(savedFrom('CS 2.1'))!;

      expect(source.spokenReference, 'Captured Sermon, page 2, paragraph 1');
      expect(source.spokenReference, isNot(contains('CS 2.1')));
    });
  });
}
