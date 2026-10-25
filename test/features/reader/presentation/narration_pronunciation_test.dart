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
        ...defaultNarrationPronunciations,
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

  test(
    'saved custom rules receive defaults and override them case-insensitively',
    () {
      final rules = decodeNarrationPronunciations(
        '{" HAST ":"custom", "example":"spoken"}',
      );
      expect(
        prepareNarrationPronunciation('hast example Sodom', corrections: rules),
        'custom spoken Soddum',
      );
      expect(
        rules.keys.where((key) => key.toLowerCase() == 'hast'),
        hasLength(1),
      );
    },
  );

  test('intentional removals survive save and reload', () {
    final edited = {...defaultNarrationPronunciations, 'example': 'spoken'}
      ..remove('hast');
    final reloaded = decodeNarrationPronunciations(
      encodeNarrationPronunciations(edited),
    );
    expect(reloaded, edited);
    expect(
      decodeNarrationPronunciations(encodeNarrationPronunciations({})),
      isEmpty,
    );
  });

  test(
    'future defaults merge under versioned edits without reviving disabled defaults',
    () {
      final rules = decodeNarrationPronunciations(
        '{"version":2,"rules":{"example":"spoken"},"disabledDefaults":["hast"]}',
      );
      expect(rules['example'], 'spoken');
      expect(rules['Sodom'], defaultNarrationPronunciations['Sodom']);
      expect(rules.containsKey('hast'), isFalse);
    },
  );

  test(
    'deferred snapshots stay exact instead of acquiring new defaults',
    () async {
      final rules = await loadDeferredNarrationPronunciations(
        rules: defaultNarrationPronunciations,
        load: (_) async => '{"old":"fallback"}',
        save: (_, __) async {},
      );
      expect(rules, {'old': 'fallback'});
    },
  );
}
