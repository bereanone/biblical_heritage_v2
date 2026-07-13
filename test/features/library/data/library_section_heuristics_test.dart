import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_section_heuristics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('treats title-page boilerplate as not meaningful reading', () {
    expect(
      libraryIsMeaningfulReadingSection(
        title: 'The Story of the Seer of Patmos',
        href: 'OPS/chapter-1.xhtml',
        paragraphs: const <String>[
          'BY STEPHEN N. HASKELL.',
          'SOUTHERN PUBLISHING ASSOCIATION',
        ],
        bookTitle: 'The Story of the Seer of Patmos',
      ),
      isFalse,
    );
  });

  test('treats DAR title-page boilerplate as not meaningful reading', () {
    expect(
      libraryIsMeaningfulReadingSection(
        title: 'Daniel and the Revelation',
        href: 'OEBPS/The_Daniel_and_Revelation_01t_(ebook).xhtml',
        paragraphs: const <String>[
          '© 2016 Adventist Pioneer Library',
          '37457 Jasper Lowell Rd',
          'Jasper, OR, 97438, USA',
          '+1 (877) 585-1111',
          'www.APLib.org',
          'Originally published in 1897 by the Review and Herald Publishing Company.',
          'The original Table of Contents contained brief descriptions of the contents of each chapter.',
          'Published in the USA',
          'July, 2016',
          'ISBN: 978-1-61455-045-7',
        ],
        bookTitle: 'Daniel and the Revelation',
      ),
      isFalse,
    );
  });

  test('treats substantive content as meaningful reading', () {
    expect(
      libraryIsMeaningfulReadingSection(
        title: 'CHAPTER I. THE SEER OF PATMOS',
        href: 'OPS/chapter-2.xhtml',
        paragraphs: const <String>[
          'The men whom God has chosen as a means of communication between heaven and earth, form a galaxy of noted characters.',
          'The gift of prophecy is called the "best gift," and the church is exhorted to covet that "best gift."',
        ],
        bookTitle: 'The Story of the Seer of Patmos',
      ),
      isTrue,
    );
  });

  test('cleans obvious Pioneer margin artifacts conservatively', () {
    expect(
      libraryCleanVisibleMarginArtifacts(
        'Israel was to send beams of 2 Margin light to the world.',
      ),
      'Israel was to send beams of light to the world.',
    );
    expect(
      libraryCleanVisibleMarginArtifacts('for at 1 Margin the time of the end'),
      'for at the time of the end',
    );
  });

  test('preserves legitimate margin prose when no artifact marker exists', () {
    expect(
      libraryCleanVisibleMarginArtifacts(
        'The margin of the page was intentionally wide for notes.',
      ),
      'The margin of the page was intentionally wide for notes.',
    );
  });

  test('flags intro/preface/foreword labels as front-matter openings', () {
    expect(libraryIsFrontMatterOpeningLabel('Introduction'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('Introduction.'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('Preface'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('Foreword'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel("Author's Preface"), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('A Word to the Reader'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('Table of Contents'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('intro'), isTrue);
    expect(libraryIsFrontMatterOpeningLabel('Chapter 1'), isFalse);
  });

  test('does not flag real chapter labels as front-matter openings', () {
    expect(
      libraryIsFrontMatterOpeningLabel('CHAPTER 1. THE EARTHLY SANCTUARY.'),
      isFalse,
    );
    expect(libraryIsFrontMatterOpeningLabel('Chapter I'), isFalse);
    expect(libraryIsFrontMatterOpeningLabel('The Great Controversy'), isFalse);
    expect(libraryIsFrontMatterOpeningLabel('An Appeal to Youth'), isFalse);
  });
}
