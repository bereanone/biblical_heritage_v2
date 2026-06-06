import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_citation_display_helper.dart';

void main() {
  test('rejects raw internal hrefs in user-facing ref text', () {
    expect(
      librarySafeUserFacingReferenceText('OEBPS/content02.xhtml#anchor'),
      isNull,
    );
  });

  test('rejects eLibrary internal locators in user-facing ref text', () {
    expect(
      librarySafeUserFacingReferenceText(
        'elibrary-range:library_item_research_epubs:115:5::OEBPS/content110.xhtml',
      ),
      isNull,
    );
    expect(
      librarySafeUserFacingReferenceText('library_item_research_epubs'),
      isNull,
    );
    expect(
      librarySafeUserFacingReferenceText('compactRef:library_item_research_epubs'),
      isNull,
    );
    expect(
      librarySafeUserFacingReferenceText('content110.xhtml'),
      isNull,
    );
  });

  test('prefers official devotional refs and falls back safely', () {
    expect(
      libraryUserFacingSearchLocationText(
        title: 'Homeward Bound',
        officialReferenceText: 'HB May 13.1',
        fileName: 'en_HB.epub',
        relativePath: 'ePubs/Research/EGW_Devotionals/en_HB.epub',
        pageCitation: '179.1',
        paragraphIndex: 1,
      ),
      'HB May 13.1',
    );

    expect(
      libraryUserFacingSearchLocationText(
        title: 'Homeward Bound',
        officialReferenceText: 'OEBPS/content02.xhtml',
        fileName: 'en_HB.epub',
        relativePath: 'ePubs/Research/EGW_Devotionals/en_HB.epub',
        pageCitation: '179.1',
        paragraphIndex: 1,
      ),
      'HB 179.1',
    );
  });

  test('maps Conflict and Courage to CC', () {
    expect(
      libraryUserFacingBookAbbreviation(
        title: 'Conflict and Courage',
        fileName: 'en_CC.epub',
        relativePath: 'ePubs/Research/EGW_Devotionals/en_CC.epub',
      ),
      'CC',
    );
  });

  test('hides internal eLibrary locator strings from display labels', () {
    final label = libraryUserFacingELibraryDisplayLabel(
      sourceTitle: 'library_item_research_epubs',
      sourceTitleAcronym: 'compactRef:library_item_research_epubs',
      sourceLocation:
          'elibrary-range:library_item_research_epubs:115:5::OEBPS/content110.xhtml',
      sourceReferenceText: 'library_item_research_epubs',
      fileName: 'content110.xhtml',
      relativePath: 'ePubs/Research/EGW_Devotionals/library_item_research_epubs.epub',
      pageCitation: '115.5',
      paragraphIndex: 5,
    );

    expect(label, isNot(contains('library_item_')));
    expect(label, isNot(contains('elibrary-range:')));
    expect(label, isNot(contains('OEBPS/')));
  });

  group('abbreviation from filename — language prefix stripping', () {
    test('strips en_ prefix: en_1SAT.epub -> 1SAT', () {
      expect(
        libraryUserFacingBookAbbreviation(
          title: 'Sermons and Talks, Vol. 1',
          fileName: 'en_1SAT.epub',
          relativePath: 'ePubs/Research/EGW_Misc_Collections/en_1SAT.epub',
        ),
        '1SAT',
      );
    });

    test('strips en_ prefix: en_1MR.epub -> 1MR', () {
      expect(
        libraryUserFacingBookAbbreviation(
          title: 'Manuscript Releases, Vol. 1',
          fileName: 'en_1MR.epub',
          relativePath: 'ePubs/Research/EGW_Manuscript_Releases/en_1MR.epub',
        ),
        '1MR',
      );
    });

    test('strips en_ prefix: en_RH.epub -> RH', () {
      expect(
        libraryUserFacingBookAbbreviation(
          title: 'The Review and Herald',
          fileName: 'en_RH.epub',
          relativePath: 'ePubs/Research/EGW_Periodicals/en_RH.epub',
        ),
        'RH',
      );
    });

    test('strips en_ prefix on 6-char code: en_SFEcho.epub -> SFECHO', () {
      expect(
        libraryUserFacingBookAbbreviation(
          title: 'Signs of the Far East',
          fileName: 'en_SFEcho.epub',
          relativePath: 'ePubs/Research/EGW_Periodicals/en_SFEcho.epub',
        ),
        'SFECHO',
      );
    });

    test('preserves hyphenated codes: en_SHM-apx.epub -> SHM-APX', () {
      expect(
        libraryUserFacingBookAbbreviation(
          title: 'Some Hyphenated Manual Appendix',
          fileName: 'en_SHM-apx.epub',
          relativePath: 'ePubs/Research/EGW_Misc_Collections/en_SHM-apx.epub',
        ),
        'SHM-APX',
      );
    });
  });
}
