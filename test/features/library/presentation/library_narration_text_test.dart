import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_narration_text.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  test('citation lists and chapter continuations are spoken smoothly', () {
    const cases = {
      'Heb. 11:1': 'Hebrews chapter eleven verse one',
      'Phil. 4:4': 'Philippians chapter four verse four',
      'Gal. 2:20': 'Galatians chapter two verse twenty',
      'Col. 1:20': 'Colossians chapter one verse twenty',
      '1 Thess. 1:3': 'First Thessalonians chapter one verse three',
      '2 Sam. 22:33': 'Second Samuel chapter twenty-two verse thirty-three',
      'Eze. 36:26': 'Ezekiel chapter thirty-six verse twenty-six',
      'Habakkuk (2:4)': 'Habakkuk chapter two verse four',
      'Eph. 4:7': 'Ephesians chapter four verse seven',
      'Eph. 2:8,9': 'Ephesians chapter two verses eight and nine',
      'Mark 5:1,2': 'Mark chapter five verses one and two',
      'Jude 20, 21': 'Jude chapter one verses twenty and twenty-one',
      'Jude 1:20,21': 'Jude chapter one verses twenty and twenty-one',
      '3 John 2': 'Third John chapter one verse two',
      'Mark 5:1,3-5': 'Mark chapter five verses one and three through five',
      'Mark 5:1,4; 6:4-8':
          'Mark chapter five verses one and four and chapter six verses four through eight',
      '1 Cor. 1:2; 2:3,4':
          'First Corinthians chapter one verse two and chapter two verses three and four',
      'See John 3:16, 1 John 4:2.':
          'See John chapter three verse sixteen, First John chapter four verse two.',
      'Mark 5:1; John 4:3–6':
          'Mark chapter five verse one and John chapter four verses three through six',
    };
    for (final e in cases.entries) {
      expect(prepareLibraryNarrationText(e.key), e.value);
      expect(prepareLibraryNarrationText(e.value), e.value);
    }
  });
  test('pagination and book codes are silent; meaningful brackets survive', () {
    const source =
        'First [24] paragraph. SC 23.3\n\nSecond [editorial note] paragraph. WOR138.3';
    expect(
      prepareLibraryNarrationText(source),
      'First paragraph.\n\nSecond [editorial note] paragraph.',
    );
    expect(prepareLibraryNarrationText('[24] SC 23.3'), isEmpty);
    expect(source, contains('[24]'));
    for (final s in [
      'Mark 5:6-3',
      'John 3:16a',
      'John 0:1',
      'The ratio is 5:2.',
    ]) {
      expect(prepareLibraryNarrationText(s), s);
    }
  });
  test(
    'segmentation preserves source offsets and never bisects a citation',
    () async {
      const citation = 'Mark 5:1,4; 6:4-8';
      for (var offset = 285; offset < 325; offset++) {
        final source =
            '${'word ' * (offset ~/ 5)}$citation and more words. ${'word ' * 40}';
        final segmenter = LibrarySpeechSegmenter(
          (c) async => c == 'p'
              ? LibrarySpeechItem(cursor: 'p', nextCursor: 'end', text: source)
              : null,
        );
        var cursor = 'p';
        final parts = <LibrarySpeechItem>[];
        while (cursor != 'end') {
          final part = (await segmenter.load(cursor))!;
          parts.add(part);
          cursor = part.nextCursor;
        }
        expect(parts.map((p) => p.text).join(), source);
        expect(parts.where((p) => p.text.contains(citation)).length, 1);
        expect(
          parts.map((p) => p.spokenText).join(' '),
          contains(
            'Mark chapter five verses one and four and chapter six verses four through eight',
          ),
        );
      }
    },
  );
}
