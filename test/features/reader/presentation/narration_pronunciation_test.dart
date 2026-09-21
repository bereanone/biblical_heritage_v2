import 'package:flutter_test/flutter_test.dart';
import '../../../../lib/features/reader/presentation/narration_pronunciation.dart';

void main() {
  test('verb live correction is limited to the reported phrases', () {
    expect(
      prepareNarrationPronunciation(
        'live for ever; live forever; a live broadcast',
      ),
      'liv for ever; liv forever; a live broadcast',
    );
  });

  test('custom corrections override defaults once without cascading', () {
    expect(
      prepareNarrationPronunciation(
        'Sodom and hast!',
        corrections: {'Sodom': 'hast', 'hast': 'hasst'},
      ),
      'hast and hasst!',
    );
    expect(
      prepareNarrationPronunciation('hast haste', corrections: {}),
      'hast haste',
    );
  });
  test(
    'saved empty dictionary stays empty and malformed data recovers defaults',
    () {
      expect(decodeNarrationPronunciations('{}'), isEmpty);
      expect(
        decodeNarrationPronunciations('broken'),
        defaultNarrationPronunciations,
      );
      expect(decodeNarrationPronunciations('{"word":"spoken"}'), {
        'word': 'spoken',
      });
    },
  );

  test('Gomorrah uses middle stress without changing nearby names', () {
    expect(
      prepareNarrationPronunciation(
        "Sodom and Gomorrah; GOMORRAH, Gomorrah’s.",
      ),
      "Soddum and go-morrah; go-morrah, go-morrah’s.",
    );
    expect(
      prepareNarrationPronunciation('Gomorrahs Gomorrahite'),
      'Gomorrahs Gomorrahite',
    );
  });
  test('Sodom correction handles case, punctuation and possessives', () {
    expect(
      prepareNarrationPronunciation("Sodom, SODOM; sodom's, Sodom’s."),
      "Soddum, Soddum; Soddum's, Soddum’s.",
    );
  });
  test('does not alter other words or the source string', () {
    const source = 'Sodom and the Sodomites. Thou hast made haste.';
    expect(
      prepareNarrationPronunciation(source),
      'Soddum and the Sodomites. Thou hasst made haste.',
    );
    expect(source, 'Sodom and the Sodomites. Thou hast made haste.');
  });
}
