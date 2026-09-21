import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _contextPath = 'assets/audio/pronunciation/context-lexicon.txt';
const _kokoroDir = 'assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0';

Map<String, List<String>> _parse(String text) => {
  for (final line in text.split('\n'))
    if (line.trim().isNotEmpty)
      line.trim().split(RegExp(r'\s+')).first.toLowerCase(): line
          .trim()
          .split(RegExp(r'\s+'))
          .skip(1)
          .toList(),
};

void main() {
  final context = File(_contextPath).readAsStringSync();

  test(
    'liveth/livest are spoken with short i and the second-syllable schwa, '
    'overriding the bundled long-i entries',
    () {
      final ours = _parse(context);
      // Two syllables ("liv-eth"), not the one-syllable "livth".
      expect(ours['liveth'], ['l', 'ˈ', 'ɪ', 'v', 'ə', 'θ']);
      expect(ours['livest'], ['l', 'ˈ', 'ɪ', 'v', 'ə', 's', 't']);
      // The bundled lexicon has the adjective "live" vowel (long i); the engine
      // keeps the first entry it loads, so ours must load first.
      final bundled = _parse(
        File('$_kokoroDir/lexicon-us-en.txt').readAsStringSync(),
      );
      expect(bundled['liveth'], ['l', 'ˈ', 'I', 'v', 'θ']);
      expect(bundled['livest'], ['l', 'ˈ', 'I', 'v', 's', 't']);
      final worker = File(
        'lib/features/reader/presentation/kokoro_speech_worker.dart',
      ).readAsStringSync();
      expect(
        worker.indexOf('context-lexicon-v1.txt'),
        lessThan(worker.indexOf('lexicon-us-en.txt')),
      );
    },
  );

  test('"the" is reduced (ð ə), not spoken as "thee" (ð i)', () {
    // The bundled US lexicon gives "the" and "thee" identical phonemes, so
    // every "the" is heard as the archaic pronoun. The UK lexicon has ð ə.
    expect(_parse(context)['the'], ['ð', 'ə']);
    final bundled = _parse(
      File('$_kokoroDir/lexicon-us-en.txt').readAsStringSync(),
    );
    expect(bundled['the'], ['ð', 'i']);
    expect(bundled['thee'], ['ð', 'i']);
    // "thee" itself must stay the full vowel.
    expect(_parse(context).containsKey('thee'), isFalse);
  });

  test('every context entry is unique and uses only known model tokens', () {
    final tokens = File('$_kokoroDir/tokens.txt')
        .readAsLinesSync()
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.split(' ').first)
        .toSet();
    final words = <String>{};
    for (final line in context.split('\n').where((l) => l.trim().isNotEmpty)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      expect(words.add(parts.first.toLowerCase()), isTrue, reason: line);
      // The engine silently drops an entry with an unknown phoneme.
      for (final phoneme in parts.skip(1)) {
        expect(tokens, contains(phoneme), reason: line);
      }
    }
  });
}
