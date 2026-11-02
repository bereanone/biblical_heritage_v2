import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_narration_text.dart';
void main() {
  test('dates and complete reference lists preserve source offsets and speech', () {
  const cases = {
    'Oct. 18, 1898': 'October eighteenth, eighteen ninety-eight',
    'Oct.18,1898': 'October eighteenth, eighteen ninety-eight',
    'Jan 3, 1899': 'January third, eighteen ninety-nine',
    'October 13, 1890': 'October thirteenth, eighteen ninety',
    'Aug. 21, 1900': 'August twenty-first, nineteen hundred',
    'Sept. 18, 1901': 'September eighteenth, nineteen oh one',
    'Feb. 29, 2000': 'February twenty-ninth, two thousand',
    'July 18, July 25, August 1, 1899':
      'July eighteenth, July twenty-fifth, August first, eighteen ninety-nine',
    'Mark5:1,2': 'Mark chapter five verses one and two',
    'Mark5:1,3-5': 'Mark chapter five verses one and three through five',
    'Mark5:1,4;6:4-8': 'Mark chapter five verses one and four and chapter six verses four through eight',
    'Mark 5:1; John 4:3–6': 'Mark chapter five verse one and John chapter four verses three through six',
    'Eph. 4:7': 'Ephesians chapter four verse seven',
    'Jude 20, 21': 'Jude chapter one verses twenty and twenty-one',
    'Habakkuk (2:4)': 'Habakkuk chapter two verse four',
    'Ps. 33:6-9': 'Psalms chapter thirty-three verses six through nine',
    'Luke 7:41, 42: “There was a certain creditor”':
      'Luke chapter seven verses forty-one and forty-two: “There was a certain creditor”',
    '1 Cor. 9:26, 27:': 'First Corinthians chapter nine verses twenty-six and twenty-seven:',
    'Gal. 5:3—signifies': 'Galatians chapter five verse three—signifies',
    'Verse 63.': 'verse sixty-three.',
    'verses 14-16:': 'verses fourteen through sixteen:',
    'chapter 22, para. 5': 'chapter twenty-two, para. 5',
    'Oct. 32, 1898': 'Oct. 32, 1898',
    'Feb. 29, 1900': 'Feb. 29, 1900',
    'Mark 5:6-3': 'Mark 5:6-3',
    'Ps. 33:6-': 'Ps. 33:6-',
    'John 3:16a': 'John 3:16a',
    'The ratio is 5:2.': 'The ratio is 5:2.',
    'May I read October notes?': 'May I read October notes?',
  };
  for (final entry in cases.entries) {
    final actual = prepareLibraryNarrationText(entry.key);
    if (actual != entry.value) throw StateError('${entry.key}\n$actual\n!= ${entry.value}');
    if (prepareLibraryNarrationText(actual) != actual) throw StateError('Not idempotent: $actual');
    var end = 0;
    for (final span in librarySpeechSpans(entry.key)) {
      if (span.start < end || span.end > entry.key.length) throw StateError('Invalid source offsets');
      end = span.end;
    }
  }
  const months = ['Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.', 'Jul.', 'Aug.', 'Sept.', 'Oct.', 'Nov.', 'Dec.'];
  for (final month in months) {
    final output = prepareLibraryNarrationText('$month 1, 1899');
    if (!output.endsWith('first, eighteen ninety-nine')) throw StateError(output);
  }
  print('${cases.length} regression cases and all 12 months passed');
  });
}
