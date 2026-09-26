import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/utilities/data/epub_internal_anchor_section_splitter.dart';

void main() {
  test(
    'out of order and repeated targets never duplicate or drop source bytes',
    () {
      const source =
          '<html><body><p>Preface.</p>'
          '<h2><span id="a"/>A</h2><p>First.</p>'
          '<h2><span id="b"/>B</h2><p>Last.</p></body></html>';
      final sections = EpubInternalAnchorSectionSplitter.splitByAnchors(
        rawHtml: source,
        wholeFileTitle: 'Book',
        targets: const [
          EpubAnchorTarget(title: 'B', anchor: 'b'),
          EpubAnchorTarget(title: 'A', anchor: 'a'),
          EpubAnchorTarget(title: 'B again', anchor: 'b'),
        ],
      );
      expect(sections.map((s) => s.html).join(), source);
      expect(sections.length, 3);
      expect(sections[1].html, startsWith('<h2>'));
      expect(sections[2].html, startsWith('<h2>'));
    },
  );
  test('a missing target retains the whole source', () {
    const source = '<p>Preface</p><h2 id="a">A</h2><p>Body</p>';
    final sections = EpubInternalAnchorSectionSplitter.splitByAnchors(
      rawHtml: source,
      wholeFileTitle: 'Book',
      targets: const [
        EpubAnchorTarget(title: 'A', anchor: 'a'),
        EpubAnchorTarget(title: 'Missing', anchor: 'missing'),
      ],
    );
    expect(sections.single.html, source);
  });
}
