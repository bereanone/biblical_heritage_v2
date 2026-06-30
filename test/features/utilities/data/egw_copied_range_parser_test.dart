import 'package:flutter_test/flutter_test.dart';

import 'package:studybible2/features/utilities/data/egw_copied_range_parser.dart';

const String _darCopiedRangeFixture = '''
Chapter 1 — Daniel in Captivity
DAR 24
VERSE 1. In the third year of the reign of Jehoiakim king of Judah...
DAR 24.1
WITH a directness characteristic of the prophet...
DAR 24.2
Paragraph without a copied-range ref.
DAR 25
The vision continues into the next page.
DAR 25.1

Chapter 2 — The Great Image
DAR 32
DANIEL was carried into captivity with the princes of Judah.
DAR 32.1
Another paragraph for the second chapter.
DAR 32.2
DAR 33
The closing paragraph bridges to the final page.
DAR 33.1
Final paragraph in the copied range.
DAR 33.2
''';

void main() {
  test('parses the DAR copied range fixture with chapter and ref order', () {
    final result = parseEgwCopiedRangeText(
      _darCopiedRangeFixture,
      workAbbreviation: 'DAR',
    );
    final document = result.document;
    final report = result.report;

    expect(document.workAbbreviation, 'DAR');
    expect(document.sections, isNotEmpty);
    expect(report.headingCount, greaterThan(0));
    expect(report.paragraphCount, greaterThan(0));
    expect(report.firstRef, isNotNull);
    expect(report.lastRef, isNotNull);
    expect(report.pageNumbersNonDecreasing, isTrue);
    expect(report.warnings, isNotEmpty);
    expect(document.sections.first.title, 'Chapter 1 — Daniel in Captivity');
    expect(
      document.sections.any(
        (section) => section.title == 'Chapter 2 — The Great Image',
      ),
      isTrue,
    );

    final chapterOne = document.sections.first;
    expect(chapterOne.paragraphs, isNotEmpty);
    expect(chapterOne.paragraphs.first.ref, 'DAR 24.1');
    expect(chapterOne.paragraphs.first.text, contains('VERSE 1'));
    expect(chapterOne.paragraphs.first.page, greaterThanOrEqualTo(24));

    final chapterOneSecond = chapterOne.paragraphs[1];
    expect(chapterOneSecond.ref, 'DAR 24.2');
    expect(chapterOneSecond.text, contains('WITH a directness'));
    expect(chapterOneSecond.page, greaterThanOrEqualTo(24));

    final pageTransitionParagraph = document.sections
        .expand((section) => section.paragraphs)
        .firstWhere((paragraph) => paragraph.ref == 'DAR 25.1');
    expect(pageTransitionParagraph.page, greaterThanOrEqualTo(24));
  });

  test('flags duplicate refs without removing the first paragraph', () {
    const text = '''
Chapter 1 — Daniel in Captivity
DAR 1
First paragraph.
DAR 1.1
Second paragraph.
DAR 1.1
Repeated paragraph.
''';

    final result = parseEgwCopiedRangeText(text, workAbbreviation: 'DAR');
    expect(result.report.duplicateRefs, contains('DAR 1.1'));
    expect(result.report.isValid, isFalse);
    final paragraph = result.document.sections.first.paragraphs.firstWhere(
      (item) => item.ref == 'DAR 1.1',
    );
    expect(paragraph.text, 'First paragraph.');
  });

  test('normalizes browser capture before copied range parsing', () {
    const capture = '''
writings
Search for books
TAMP The American Papacy
The American Papacy p.3
The American Papacy
By Alonzo Trevier Jones (1894)
The American Papacy.
SINCE the year 1856, a book entitled “Our Country” has been largely circulated, and it has excited a great deal of attention throughout the United States. The book was written for the American Home Missionary Society, its object being to present “facts and arguments showing the imperative need of home missionary work for the evangelization of the land.” In a startling as well as splendid array of facts, it presents the growth, the size, the resources, and the perils of our country.
TAMP 3.1
Among the perils to our country, the author rightly places Romanism, and by many excellent quotations proves that it is indeed a peril. We quote a passage or two:—
TAMP 3.2
“There are many who are disposed to attribute any fear of Roman Catholicism in the United States to bigotry or childishness. Such see nothing in the character and attitude of Romanism that is hostile to our free institutions, or find nothing portentous in its growth. Let us, then, first compare some of the fundamental principles of our Government with those of the Catholic Church.
TAMP 3.3
“The Constitution of the United States guarantees liberty of conscience. Nothing is clearer or more fundamental. Pope Pius IX. said that liberty of conscience was an error.”
TAMP 4.1
''';

    final normalized = const EgwBrowserCaptureNormalizer().normalize(
      capture,
      workAbbreviation: 'TAMP',
    );

    expect(normalized.workTitle, 'The American Papacy');
    expect(normalized.author, 'Alonzo Trevier Jones');
    expect(
      normalized.normalizedText,
      startsWith('Chapter 1 — The American Papacy\nTAMP 3\nSINCE'),
    );
    expect(normalized.normalizedText, contains('\nTAMP 4\n'));
    expect(normalized.normalizedText, isNot(contains('By Alonzo')));
    expect(normalized.normalizedText, isNot(contains('Search for books')));
    expect(
      normalized.normalizedText,
      isNot(contains('TAMP The American Papacy')),
    );
    expect(normalized.normalizedText, isNot(contains('The American Papacy.')));

    final parsed = parseEgwCopiedRangeText(
      normalized.normalizedText,
      workAbbreviation: 'TAMP',
    );
    final paragraphs = parsed.document.sections.single.paragraphs;

    expect(
      parsed.document.sections.single.title,
      'Chapter 1 — The American Papacy',
    );
    expect(parsed.report.firstRef, 'TAMP 3.1');
    expect(parsed.report.lastRef, 'TAMP 4.1');
    expect(parsed.report.duplicateRefs, isEmpty);
    expect(parsed.report.emptyParagraphRefs, isEmpty);
    expect(parsed.report.isValid, isTrue);
    expect(parsed.report.pageNumbers, <int>[3, 4]);
    expect(paragraphs.map((paragraph) => paragraph.ref), <String>[
      'TAMP 3.1',
      'TAMP 3.2',
      'TAMP 3.3',
      'TAMP 4.1',
    ]);
    expect(paragraphs.first.text, startsWith('SINCE the year 1856'));
    expect(paragraphs.first.text, isNot(contains('The American Papacy')));
    expect(paragraphs[0].page, 3);
    expect(paragraphs[1].page, 3);
    expect(paragraphs[3].page, 4);
    expect(paragraphs[1].text, startsWith('Among the perils'));
  });
}
