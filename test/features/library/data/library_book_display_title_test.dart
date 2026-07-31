import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_book_display_title.dart';

void main() {
  group('normalizeBookDisplayTitle', () {
    test('decodes quoted entity title and removes outer quotes', () {
      expect(normalizeBookDisplayTitle('&quot;The Daily&quot;'), 'The Daily');
      expect(normalizeBookDisplayTitle('&#34;The Daily&#34;'), 'The Daily');
    });

    test('collapses repeated identical fragments', () {
      expect(
        normalizeBookDisplayTitle('"The Daily"\n"The Daily"\nThe Daily'),
        'The Daily',
      );
    });

    test('decodes apostrophe, ampersand, and Unicode entities', () {
      expect(
        normalizeBookDisplayTitle(
          'The Lord&apos;s Day &amp; &#x201C;Rest&#x201D;',
        ),
        'The Lord\'s Day & "Rest"',
      );
    });

    test(
      'removes unmatched quotes but preserves legitimate internal quotes',
      () {
        expect(
          normalizeBookDisplayTitle('"Unfinished Title'),
          'Unfinished Title',
        );
        expect(
          normalizeBookDisplayTitle(
            'The "Abiding Sabbath" and the "Lord\'s Day"',
          ),
          'The "Abiding Sabbath" and the "Lord\'s Day"',
        );
      },
    );

    test('strips HTML and leaves clean titles unchanged', () {
      expect(
        normalizeBookDisplayTitle('<em>What Think Ye of Christ?</em>'),
        'What Think Ye of Christ?',
      );
      expect(
        normalizeBookDisplayTitle('Christian\'s Demand for War'),
        'Christian\'s Demand for War',
      );
    });

    test('skips internal codes when a usable fallback exists', () {
      expect(
        normalizeBookDisplayTitle('AW', fallbacks: const ['Adventist World']),
        'Adventist World',
      );
    });
  });
}
