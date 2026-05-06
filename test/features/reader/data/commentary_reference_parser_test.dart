import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/reader/data/commentary_reference_parser.dart';

void main() {
  final books = <BookRecord>[
    const BookRecord(bookNumber: 43, bookName: 'John', bookIndex: 44),
    const BookRecord(bookNumber: 62, bookName: '1 John', bookIndex: 63),
  ];
  final lookup = BibleReferenceParser.buildBookLookup(books);
  final aliases = BibleReferenceParser.buildBookAliases(books);

  test('keeps John and 1 John distinct', () {
    final john = BibleReferenceParser.extractReferences(
      'John 1:1',
      lookup,
      aliases: aliases,
    );
    final oneJohn = BibleReferenceParser.extractReferences(
      '1 John 1:1',
      lookup,
      aliases: aliases,
    );

    expect(john, hasLength(1));
    expect(john.single.bookId, 43);
    expect(oneJohn, hasLength(1));
    expect(oneJohn.single.bookId, 62);
  });

  test('keeps numbered books from bleeding into one another', () {
    final combined = BibleReferenceParser.extractReferences(
      'John 1:1 and 1 John 1:1',
      lookup,
      aliases: aliases,
    );

    expect(combined, hasLength(2));
    expect(combined.map((reference) => reference.bookId), containsAll(<int>[43, 62]));
  });
}
