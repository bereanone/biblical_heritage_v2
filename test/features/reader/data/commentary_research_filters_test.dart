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
}
