import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/library/data/library_citation_links.dart';
import 'package:studybible2/features/library/presentation/library_narration_text.dart';
import 'package:studybible2/features/library/presentation/library_verse_popup.dart';

void main() {
  final bounds =
      jsonDecode(
            File('test/fixtures/bible_citation_bounds.json').readAsStringSync(),
          )
          as Map;
  final books = [
    for (final b in bounds['books'] as List)
      BookRecord(
        bookNumber: b['book_number'] as int,
        bookName: b['book_name'] as String,
        bookIndex: b['book_index'] as int,
      ),
  ];
  final verseCounts = <int, Map<int, int>>{
    for (final b in (bounds['verse_counts'] as Map).entries)
      int.parse(b.key as String): {
        for (final c in (b.value as Map).entries)
          int.parse(c.key as String): c.value as int,
      },
  };
  test(
    'every historical PP footnote citation links to complete real Bible targets',
    () {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/pp_historical_citation_notes.json',
                ).readAsStringSync(),
              )
              as Map;
      final unresolved = <String>[];
      var linked = 0;
      for (final note in fixture['notes'] as List) {
        final text = note['text'] as String;
        final nodes = linkLibraryCitations(
          [
            {'type': 'text', 'text': text},
          ],
          resolves: (book, locator) =>
              libraryCitationResolves(book, locator, books, verseCounts),
        );
        expect(nodes.map((n) => n['text']).join(), text);
        var offset = 0;
        final ranges = <(int, int)>[];
        for (final n in nodes) {
          final end = offset + (n['text'] as String).length;
          if (n['link'] != null) {
            ranges.add((offset, end));
            linked++;
          }
          offset = end;
        }
        for (final m in RegExp(r'\d\s*:\s*\d').allMatches(text)) {
          if (!ranges.any((r) => r.$1 <= m.start && m.start < r.$2)) {
            unresolved.add('${note['id']}: $text');
            break;
          }
        }
      }
      expect(unresolved, isEmpty, reason: unresolved.join('\n'));
      expect(linked, greaterThan(800));
    },
  );
  test('PP historical shorthand has full speech with matching ranges', () {
    const cases = {
      'Eze. 28:12-15':
          'Ezekiel chapter twenty-eight verses twelve through fifteen',
      'Neh. 9:6': 'Nehemiah chapter nine verse six',
      'Cant. 2:11-13, Rev. Ver.':
          'Song of Solomon chapter two verses eleven through thirteen, Revised Version.',
      'Ex. 1; 2:1-10.':
          'Exodus chapter one; Exodus chapter two verses one through ten.',
      '2 Sam. 2-4; 5:1-5.':
          'Second Samuel chapters two through four; Second Samuel chapter five verses one through five.',
      'Ps. 33:6-9': 'Psalms chapter thirty-three verses six through nine',
      'PP 33.1': '',
      'II Sam. 23:1-5':
          'Second Samuel chapter twenty-three verses one through five',
      'III John 5-8': 'Third John chapter one verses five through eight',
    };
    for (final c in cases.entries) {
      final actual = prepareLibraryNarrationText(c.key);
      expect(actual, c.value, reason: c.key);
      expect(prepareLibraryNarrationText(actual), actual);
    }
    final text = 'Ps. 122:1-6, Rev. Ver.; 121:1, 2 (margin); 125:1, 2.';
    final speech = prepareLibraryNarrationText(text);
    expect(
      speech,
      contains('Psalms chapter one hundred twenty-one verses one and two'),
    );
    expect(
      speech,
      contains('Psalms chapter one hundred twenty-five verses one and two'),
    );
    final nodes = linkLibraryCitations([
      {'type': 'text', 'text': text},
    ]);
    expect(
      nodes
          .where((n) => n['link'] != null)
          .map(
            (n) => Uri.decodeComponent(
              (n['link'] as String).substring('studybible-citation:'.length),
            ),
          ),
      ['Ps. 122:1-6', 'Ps. 121:1, 2', 'Ps. 125:1, 2'],
    );
  });
  test(
    'a comma before a historical numbered book does not expand the previous range',
    () {
      const text = 'Ps. 1:1, 2 Kgs. 2:1; 1 Chr. 3:1.';
      final targets = linkLibraryCitations([
        {'type': 'text', 'text': text},
      ]).where((n) => n['link'] != null).map((n) => n['text']);
      expect(targets, ['Ps. 1:1', '2 Kgs. 2:1', '1 Chr. 3:1']);
    },
  );
}
