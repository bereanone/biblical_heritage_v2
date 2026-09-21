import 'dart:convert';
import 'package:studybible2/features/reader/presentation/narration_pronunciation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_pronunciation_map.dart';

void main() {
  test('speech keeps typographic possessives and contractions together', () {
    final map = BiblePronunciationMap('{"verses":{}}', 'people p');
    const source =
        'His people’s prayer; God’s love; don’t; peopleʼs; ‘prayer’.';
    expect(
      map.prepare(source, corrections: {}),
      "His people's prayer; God's love; don't; people's; ‘prayer’.",
    );
    expect(
      source,
      'His people’s prayer; God’s love; don’t; peopleʼs; ‘prayer’.',
    );
    expect(
      map.prepare('people’s prayer', corrections: {'people’s': 'our people’s'}),
      "our people's prayer",
    );
  });

  test(
    'church fallback migration retains rules and lets later edits win',
    () async {
      final store = <String, String>{
        'narration_deferred_pronunciations_v1': '{"God":"gawd"}',
      };
      const rules = {'Pergamos': 'old hint', 'custom': 'my choice'};
      Future<String?> load(String key) async => store[key];
      Future<void> save(String key, String value) async {
        store[key] = value;
      }

      final deferred = await loadDeferredNarrationPronunciations(
        rules: rules,
        load: load,
        save: save,
      );
      expect(deferred, {'God': 'gawd', 'Pergamos': 'old hint'});
      final map = BiblePronunciationMap('{"verses":{}}', 'pergamos p');
      expect(
        map.prepare(
          'Pergamos',
          corrections: rules,
          deferredCorrections: deferred,
        ),
        'Pergamos',
      );
      final again = await loadDeferredNarrationPronunciations(
        rules: {'Pergamos': 'new hint'},
        load: load,
        save: save,
      );
      expect(
        map.prepare(
          'Pergamos',
          corrections: {'Pergamos': 'new hint'},
          deferredCorrections: again,
        ),
        'new hint',
      );
      expect(rules['Pergamos'], 'old hint');
    },
  );

  BiblePronunciationMap makeMap() => BiblePronunciationMap(
    jsonEncode({
      'verses': {
        '1': {
          'text': 'God said, live for ever.',
          'patches': [
            {'start': 10, 'end': 14, 'word': 'live', 'alias': 'sbpronliveverb'},
          ],
        },
      },
    }),
    'god ɡ ˈ ɑ d\nlive l ˈ I v\n',
  );
  test('dictionary replaces deferred workarounds and context chooses verb', () {
    const rules = {'God': 'gawd', 'live': 'liv'};
    expect(
      makeMap().prepare(
        'God said, live for ever.',
        blockId: 1,
        corrections: rules,
        deferredCorrections: rules,
      ),
      'God said, sbpronliveverb for ever.',
    );
  });
  test('new correction takes priority over dictionary and context map', () {
    expect(
      makeMap().prepare(
        'God said, live for ever.',
        blockId: 1,
        corrections: {'God': 'newgod', 'live': 'newlive'},
        deferredCorrections: {'God': 'gawd', 'live': 'liv'},
      ),
      'newgod said, newlive for ever.',
    );
  });
  test('changed source never receives stored offsets', () {
    expect(
      makeMap().prepare('God said, live forever.', blockId: 1, corrections: {}),
      'God said, live forever.',
    );
  });
  test('chapter announcement preserves source matching', () {
    expect(
      makeMap().prepare(
        'Genesis 3. God said, live for ever.',
        blockId: 1,
        corrections: {},
      ),
      'Genesis 3. God said, sbpronliveverb for ever.',
    );
  });
  test('preview deliberately auditions the user spelling', () {
    const rules = {'God': 'gawd'};
    expect(
      makeMap().prepare(
        'God',
        corrections: rules,
        deferredCorrections: rules,
        preferDictionary: false,
      ),
      'gawd',
    );
  });
  test('unknown dictionary word keeps the saved fallback', () {
    const rules = {'Lamech': 'Lamek'};
    expect(
      makeMap().prepare(
        'Lamech',
        corrections: rules,
        deferredCorrections: rules,
      ),
      'Lamek',
    );
  });
}
