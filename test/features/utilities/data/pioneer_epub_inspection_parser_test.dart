import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/pioneer_epub_inspection_parser.dart';

Uint8List _epubWithAuthoredText() {
  const container =
      '<container><rootfiles><rootfile full-path="OEBPS/book.opf"/></rootfiles></container>';
  const opf =
      '<package><manifest><item id="two" href="two.xhtml"/><item id="one" href="one.xhtml"/></manifest><spine><itemref idref="one"/><itemref idref="two"/></spine></package>';
  const one =
      '<html><body><h1>ARGUMET</h1><p>Original spelling remains.</p></body></html>';
  const two =
      '<html><body><h2>SECOND HEADING</h2><p>Authored text remains verbatim.</p></body></html>';
  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip')))
    ..addFile(
      ArchiveFile(
        'META-INF/container.xml',
        container.length,
        utf8.encode(container),
      ),
    )
    ..addFile(ArchiveFile('OEBPS/book.opf', opf.length, utf8.encode(opf)))
    ..addFile(ArchiveFile('OEBPS/one.xhtml', one.length, utf8.encode(one)))
    ..addFile(ArchiveFile('OEBPS/two.xhtml', two.length, utf8.encode(two)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('reports invalid bytes without attempting a write', () {
    final report = PioneerEpubArchiveInspection.inspect(
      Uint8List.fromList([1, 2, 3]),
    );

    expect(report.isValidZip, isFalse);
    expect(report.archive, isNull);
    expect(report.selectedContentFiles, isEmpty);
  });

  test('uses authored spine order and preserves archive entry bytes', () {
    final bytes = _epubWithAuthoredText();
    final report = PioneerEpubArchiveInspection.inspect(bytes);

    expect(report.isValidZip, isTrue);
    expect(report.hasMimeType, isTrue);
    expect(report.opfPath, 'OEBPS/book.opf');
    expect(report.selectedContentFiles, ['OEBPS/one.xhtml', 'OEBPS/two.xhtml']);

    final first = report.archive!.findFile('OEBPS/one.xhtml')!;
    final authored = utf8.decode(first.content as List<int>);
    expect(
      authored,
      '<html><body><h1>ARGUMET</h1><p>Original spelling remains.</p></body></html>',
    );
  });

  test('reads nested authored NCX navigation in deterministic order', () {
    const ncx = '''<ncx><navMap>
<navPoint><navLabel><text>CHAPTER I: ARGUMET</text></navLabel><content src="text/one.xhtml#first"/>
  <navPoint><navLabel><text>Odd &amp; Unfixed</text></navLabel><content src="text/one.xhtml#child"/></navPoint>
</navPoint>
<navPoint><navLabel><text>Chapter II</text></navLabel><content src="text/two.xhtml#second"/></navPoint>
</navMap></ncx>''';
    final archive = Archive()
      ..addFile(ArchiveFile('OEBPS/toc.ncx', ncx.length, utf8.encode(ncx)));

    final targets = PioneerEpubNavigationParser.parse(
      archive: archive,
      fallbackTitle: 'Fallback',
    );

    expect(targets.map((target) => target.title), [
      'CHAPTER I: ARGUMET',
      'Odd & Unfixed',
      'Chapter II',
    ]);
    expect(targets.map((target) => target.path), [
      'OEBPS/text/one.xhtml',
      'OEBPS/text/one.xhtml',
      'OEBPS/text/two.xhtml',
    ]);
    expect(targets.map((target) => target.anchor), [
      'first',
      'child',
      'second',
    ]);
    expect(targets.map((target) => target.depth), [0, 1, 0]);
  });

  test(
    'ignores a sibling <pageList> so printed-page targets are never '
    'mistaken for chapter navigation',
    () {
      // A real published EPUB's NCX can carry a <pageList> alongside
      // <navMap> -- printed-page-number targets (e.g. "iv", "v", "vi")
      // mapped onto anchors inside ordinary chapter files. It uses the
      // exact same <navLabel><text>...</text></navLabel><content src=.../>
      // shape as <navMap>'s own <navPoint> entries, so several page
      // numbers landing inside one chapter file must not be counted as if
      // that file legitimately held several distinct chapters/sections.
      const ncx = '''<ncx><navMap>
<navPoint><navLabel><text>Chapter One</text></navLabel><content src="content01.xhtml"/></navPoint>
<navPoint><navLabel><text>Chapter Two</text></navLabel><content src="content02.xhtml"/></navPoint>
</navMap>
<pageList>
<pageTarget><navLabel><text>iv</text></navLabel><content src="content01.xhtml#piv"/></pageTarget>
<pageTarget><navLabel><text>v</text></navLabel><content src="content01.xhtml#pv"/></pageTarget>
<pageTarget><navLabel><text>vi</text></navLabel><content src="content01.xhtml#pvi"/></pageTarget>
</pageList></ncx>''';
      final archive = Archive()
        ..addFile(ArchiveFile('OEBPS/toc.ncx', ncx.length, utf8.encode(ncx)));

      final targets = PioneerEpubNavigationParser.parse(
        archive: archive,
        fallbackTitle: 'Fallback',
      );

      expect(targets.map((target) => target.title), [
        'Chapter One',
        'Chapter Two',
      ]);
      expect(targets.map((target) => target.anchor), ['', '']);
    },
  );

  test('extracts the authored body and preserves unusual heading text', () {
    const html = '''<html><head><title>Ignored</title></head><body>
      <h1>ARGUMET: “Odd”—punctuation!</h1><p>One&nbsp;&amp; two&#39;s.</p>
    </body></html>''';

    final body = PioneerEpubHtmlBodyParser.extractBody(html);

    expect(body, contains('ARGUMET: “Odd”—punctuation!'));
    expect(
      PioneerEpubHtmlBodyParser.plainText(body!),
      'ARGUMET: “Odd”—punctuation! One & two\'s.',
    );
  });

  test('groups classified blocks without filtering authored sections', () {
    final sections = PioneerEpubSectionParser.sectionize(
      fallbackTitle: 'Work',
      baseHref: 'OEBPS/book.xhtml',
      startingSpineIndex: 1,
      blocks: const [
        PioneerEpubContentBlock(kind: 'heading', text: 'ARGUMET'),
        PioneerEpubContentBlock(kind: 'paragraph', text: 'Unusual text!'),
        PioneerEpubContentBlock(kind: 'heading', text: 'CHAPTER II'),
        PioneerEpubContentBlock(kind: 'paragraph', text: 'Second.'),
      ],
    );
    expect(sections.map((section) => section.title), ['ARGUMET', 'CHAPTER II']);
    expect(sections.map((section) => section.href), [
      'OEBPS/book.xhtml',
      'OEBPS/book.xhtml#section-2',
    ]);
    expect(sections[0].paragraphs, ['Unusual text!']);
  });

  test('normalizes only comparison values without changing authored text', () {
    expect(
      PioneerEpubFilteringNormalization.collapseWhitespace(' \r\n ARGUMET\t  '),
      'ARGUMET',
    );
    expect(
      PioneerEpubFilteringNormalization.comparisonKey('“ARGUMET” &amp;  TWO'),
      'argumet amp two',
    );
    expect(
      PioneerEpubFilteringNormalization.collapseWhitespace(' \n\t '),
      isEmpty,
    );
  });
}
