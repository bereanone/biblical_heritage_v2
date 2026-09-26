import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/database_pronunciation_cues.dart';
import 'package:studybible2/features/reader/presentation/bible_pronunciation_map.dart';

void main() {
  const text = 'live live';
  final known = {
    'sbpronliveverb': {'l ˈ ɪ v'},
  };
  Map<String, dynamic> payload() => {
    'schema_version': 1,
    'tokenizer_version': 'ascii-apostrophe-v1',
    'engine': 'sherpa-onnx-kokoro',
    'phoneme_format': 'kokoro-model-symbols',
    'text_sha256': sha256.convert(utf8.encode(text)).toString(),
    'words': List.generate(
      2,
      (i) => {
        'i': i,
        'word': 'live',
        'start_utf16': i * 5,
        'end_utf16': i * 5 + 4,
        'alias': 'sbpronliveverb',
        'phonemes': ['l ˈ ɪ v'],
        'review_status': 'reviewed',
      },
    ),
  };
  test('reviewed repeated occurrences receive separate patches', () {
    expect(
      databasePronunciationPatches(text, jsonEncode(payload()), known)?.length,
      2,
    );
  });
  test('malformed JSON and wrong types fall back safely', () {
    for (final raw in ['{', '[]', 'null', '42', '{"words":"bad"}']) {
      expect(databasePronunciationPatches(text, raw, known), isNull);
    }
  });
  test('stale text hash and tokenizer are rejected', () {
    expect(
      databasePronunciationPatches('live lives', jsonEncode(payload()), known),
      isNull,
    );
    final p = payload()..['tokenizer_version'] = 'different';
    expect(databasePronunciationPatches(text, jsonEncode(p), known), isNull);
  });
  test('incorrect indices and offsets are rejected', () {
    for (final key in ['i', 'start_utf16', 'end_utf16']) {
      final p = payload();
      (p['words'] as List)[0][key] = 99;
      expect(databasePronunciationPatches(text, jsonEncode(p), known), isNull);
    }
  });
  test('unreviewed candidates do not become speech overrides', () {
    final p = payload();
    for (final w in p['words']) {
      w.remove('review_status');
    }
    p['review_status'] = 'reviewed';
    expect(databasePronunciationPatches(text, jsonEncode(p), known), isNull);
  });
  test('unknown aliases and incompatible sounds are ignored', () {
    expect(
      databasePronunciationPatches(text, jsonEncode(payload()), {}),
      isNull,
    );
    expect(
      databasePronunciationPatches(text, jsonEncode(payload()), {
        'sbpronliveverb': {'wrong'},
      }),
      isNull,
    );
  });
  test('database cues preserve announcements and user corrections', () {
    final map = BiblePronunciationMap(
      '{"verses":{}}',
      'sbpronliveverb l ˈ ɪ v',
    );
    expect(
      map.prepare(
        'Chapter 1. $text',
        databaseText: text,
        databasePronunciation: jsonEncode(payload()),
        corrections: {},
      ),
      'Chapter 1. sbpronliveverb sbpronliveverb',
    );
    expect(
      map.prepare(
        text,
        databaseText: text,
        databasePronunciation: jsonEncode(payload()),
        corrections: {'live': 'my choice'},
      ),
      'my choice my choice',
    );
    expect(
      map.prepare(
        text,
        databaseText: text,
        databasePronunciation: jsonEncode(payload()),
        corrections: {},
        preferDictionary: false,
      ),
      text,
    );
  });
  test('unreviewed database entry preserves legacy context rule', () {
    final map = BiblePronunciationMap(
      jsonEncode({
        'verses': {
          '1': {
            'text': text,
            'patches': [
              {'start': 0, 'end': 4, 'word': 'live', 'alias': 'sbpronliveverb'},
            ],
          },
        },
      }),
      'sbpronliveverb l ˈ ɪ v',
    );
    final p = payload();
    for (final w in p['words']) {
      w.remove('review_status');
    }
    expect(
      map.prepare(
        text,
        blockId: 1,
        databaseText: text,
        databasePronunciation: jsonEncode(p),
        corrections: {},
      ),
      'sbpronliveverb live',
    );
  });
}
