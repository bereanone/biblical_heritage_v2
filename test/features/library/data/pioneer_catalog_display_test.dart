import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_catalog_service.dart';

LibraryCatalogItem item(String id, String title, String path) =>
    LibraryCatalogItem.fromRow({
      'id': id,
      'title': title,
      'relative_path': path,
      'file_name': path.split('/').last,
      'file_format': 'epub',
    });

void main() {
  test('a genuine collection title is retained', () {
    expect(
      item(
        'collection',
        'Adventist Pioneer Authors',
        'collection.epub',
      ).displayTitle,
      'Adventist Pioneer Authors',
    );
  });
  test(
    'generic collection title displays actual filename without mutating metadata',
    () {
      final book = item(
        'old',
        'Adventist Pioneer Authors - James White',
        'ImportedPioneerEpubs/Appeal on Immortality.epub',
      );
      expect(book.displayTitle, 'Appeal on Immortality');
      expect(book.title, 'Adventist Pioneer Authors - James White');
    },
  );
  test(
    'exact file aliases collapse to properly named record regardless of order',
    () {
      final old = item(
        'old',
        'Adventist Pioneer Authors - James White',
        'Pioneer/Appeal.epub',
      );
      final named = item(
        'named',
        'Appeal on Immortality',
        'Pioneer/Appeal.epub',
      );
      for (final source in [
        [old, named],
        [named, old],
      ]) {
        expect(selectDistinctLibraryFiles(source).single.id, 'named');
        expect(
          source.length,
          2,
          reason: 'saved alias IDs must remain available',
        );
      }
    },
  );
  test(
    'different books, editions, case-sensitive paths and missing paths remain separate',
    () {
      final books = [
        item('a', 'Appeal', 'A/Appeal.epub'),
        item('b', 'Appeal', 'B/Appeal.epub'),
        item('c', 'Appeal', 'A/appeal.epub'),
        item('d', 'No file', ''),
        item('e', 'No file', ''),
      ];
      expect(selectDistinctLibraryFiles(books).length, 5);
    },
  );
}
