import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/reader/data/commentary_research_filters.dart';
import 'package:studybible2/features/reader/data/commentary_research_models.dart';

void main() {
  CommentaryResearchMatchItem buildMatch({
    required String title,
    required String relativePath,
    required String anchor,
  }) {
    return CommentaryResearchMatchItem(
      libraryItemId: 'item',
      itemTitle: title,
      fileName: relativePath.split('/').last,
      relativePath: relativePath,
      originalReferenceText: 'John 1:1',
      bookId: 43,
      chapter: 1,
      verseStart: 1,
      verseEnd: 1,
      confidence: 1,
      anchor: anchor,
      parserWarning: null,
    );
  }

  test('commentary filter drops front matter matches', () {
    final matches = <CommentaryResearchMatchItem>[
      buildMatch(
        title: 'Preface',
        relativePath: 'ePubs/Commentaries/EGW_Commentaries/preface.xhtml',
        anchor: 'Preface and publication information',
      ),
      buildMatch(
        title: 'Genesis 1',
        relativePath: 'ePubs/Commentaries/EGW_Commentaries/ch1.xhtml',
        anchor:
            'In the beginning God created the heaven and the earth. This '
            'opening account establishes the Creator as the source of all '
            'life and order.',
      ),
    ];

    final filtered = CommentaryResearchFilters.filterCommentaryMatches(
      matches,
      1,
    );

    expect(filtered, hasLength(1));
    expect(filtered.single.itemTitle, 'Genesis 1');
  });

  test('identical research paragraph through canonical and legacy paths dedupes', () {
    final matches = <CommentaryResearchMatchItem>[
      buildMatch(
        title: 'Education',
        relativePath: 'ePubs/EGW/EGW_Books/en_Ed.epub',
        anchor:
            'A sufficiently complete identical research paragraph for testing. '
            'It contains enough meaningful body text to pass the normal research '
            'quality filters while retaining the same wording in both copies.',
      ),
      buildMatch(
        title: 'Education',
        relativePath: 'ePubs/Research/EGW_Books/en_Ed.epub',
        anchor:
            'A sufficiently complete identical research paragraph for testing. '
            'It contains enough meaningful body text to pass the normal research '
            'quality filters while retaining the same wording in both copies.',
      ),
    ];
    final result = CommentaryResearchFilters.prepareResearchMatches(
      matches,
      bookId: 43,
      chapter: 1,
      verse: 1,
    );
    expect(result, hasLength(1));
  });

  test('similar but genuinely different research paragraphs remain distinct', () {
    final matches = <CommentaryResearchMatchItem>[
      buildMatch(
        title: 'Education',
        relativePath: 'ePubs/EGW/EGW_Books/en_Ed.epub',
        anchor:
            'The first sufficiently complete research paragraph discusses one '
            'important subject in enough detail to pass the normal quality filters '
            'and concludes with wording unique to the first source location.',
      ),
      buildMatch(
        title: 'Education',
        relativePath: 'ePubs/Research/EGW_Books/en_Ed.epub',
        anchor:
            'The second sufficiently complete research paragraph discusses another '
            'important subject in enough detail to pass the normal quality filters '
            'and concludes with wording unique to the second source location.',
      ),
    ];
    final result = CommentaryResearchFilters.prepareResearchMatches(
      matches,
      bookId: 43,
      chapter: 1,
      verse: 1,
    );
    expect(result, hasLength(2));
  });
}
