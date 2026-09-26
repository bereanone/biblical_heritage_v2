import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/data/library_citation_links.dart';

void main() {
  test('FP1872 comma before a numbered book does not add a spurious verse', () {
    const text = 'Psalm 119:105, 2 Peter 2:19; Revelation 1:1-3.';
    final nodes = linkLibraryCitations([{'type': 'text', 'text': text}]);
    expect(nodes.map((n) => n['text']).join(), text);
    expect(nodes.where((n) => n['link'] != null).map((n) =>
      Uri.decodeComponent((n['link'] as String).substring('studybible-citation:'.length))),
      ['Psalm 119:105', '2 Peter 2:19', 'Revelation 1:1-3']);
  });
  test('a reference split by emphasis keeps one target and all styles', () {
    final nodes = linkLibraryCitations([
      {'type': 'text', 'text': 'Read (John '},
      {
        'type': 'text',
        'text': '3:16',
        'marks': ['italic'],
        'relative_font_scale': .85,
      },
      {'type': 'text', 'text': ',18) now.'},
    ]);
    expect(nodes.map((n) => n['text']).join(), 'Read (John 3:16,18) now.');
    final linked = nodes.where((n) => n['link'] != null).toList();
    expect(linked.length, 3);
    expect(linked.map((n) => n['link']).toSet(), {
      'studybible-citation:${Uri.encodeComponent('John 3:16,18')}',
    });
    expect(linked[1]['marks'], ['italic']);
    expect(linked[1]['relative_font_scale'], .85);
  });
  test(
    'links ordinary references while preserving every character and style',
    () {
      const text = 'See Ex.17:6; 18:2 and I Cor. 10:4. John 3:16,18–20.';
      final nodes = linkLibraryCitations([
        {
          'type': 'text',
          'text': text,
          'marks': ['italic'],
        },
      ]);
      expect(nodes.map((n) => n['text']).join(), text);
      expect(
        nodes.every((n) => (n['marks'] as List).single == 'italic'),
        isTrue,
      );
      expect(
        nodes
            .where((n) => n['link'] != null)
            .map(
              (n) => Uri.decodeComponent(
                (n['link'] as String).split(':').skip(1).join(':'),
              ),
            ),
        ['Ex. 17:6; 18:2', 'I Cor. 10:4', 'John 3:16,18–20'],
      );
    },
  );
  test(
    'does not replace existing links or guess incomplete cross-chapter ranges',
    () {
      final linked = {'type': 'text', 'text': 'John 3:16', 'link': '#original'};
      final nodes = linkLibraryCitations([
        linked,
        {
          'type': 'text',
          'text': 'Chapter 18; Unknown 3:16; John 3:16-4:2;',
        },
      ]);
      expect(nodes.first, same(linked));
      expect(nodes.skip(1).any((n) => n['link'] != null), isFalse);
    },
  );
  test('chapter references and single-chapter verse lists retain printed text', () {
    const text = 'See Leviticus 16; Hebrews 8, and onward. Obadiah 15, 16.';
    final nodes = linkLibraryCitations([{'type': 'text', 'text': text}]);
    expect(nodes.map((n) => n['text']).join(), text);
    expect(nodes.where((n) => n['link'] != null).map((n) => n['text']),
      ['Leviticus 16', 'Hebrews 8', 'Obadiah 15, 16']);
  });
  test('leaves line breaks and split-format references untouched', () {
    final nodes = <Map<String, Object?>>[
      {'type': 'text', 'text': 'John '},
      {'type': 'line_break'},
      {'type': 'text', 'text': '3:16'},
    ];
    expect(linkLibraryCitations(nodes), nodes);
  });
}
