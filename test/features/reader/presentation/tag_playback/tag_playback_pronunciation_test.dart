import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_pronunciation_map.dart';
import 'package:studybible2/features/reader/presentation/narration_pronunciation.dart';

/// Guards the decision to run tag notes through the same pronunciation
/// pipeline as scripture, with no block id: the KJV verse patches cannot
/// reach modern prose, and the shared corrections do not misfire on it.
void main() {
  late BiblePronunciationMap map;
  late Map<String, dynamic> verses;
  final defaults = Map<String, String>.of(defaultNarrationPronunciations);

  setUpAll(() {
    final json = File(
      'assets/audio/pronunciation/bible-map-v1.json',
    ).readAsStringSync();
    final lexicon = File(
      'assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0/lexicon-us-en.txt',
    ).readAsStringSync();
    map = BiblePronunciationMap(json, lexicon);
    verses =
        (jsonDecode(json) as Map<String, dynamic>)['verses']
            as Map<String, dynamic>;
  });

  /// A patched verse none of the default user corrections overlap (those win
  /// over a patch by design, e.g. "live for ever" in Genesis 3:22).
  MapEntry<String, dynamic> firstPatchedVerse() {
    final conflict = RegExp(
      'live for ?ever|hast|sodom|gomorrah',
      caseSensitive: false,
    );
    return verses.entries.firstWhere(
      (e) =>
          (e.value['patches'] as List<dynamic>).isNotEmpty &&
          !conflict.hasMatch(e.value['text'] as String),
    );
  }

  String prepare(String text, {int? blockId}) =>
      map.prepare(text, blockId: blockId, corrections: defaults);

  test(
    'a verse clip with a spoken reference still receives its KJV patches',
    () {
      final verse = firstPatchedVerse();
      final original = verse.value['text'] as String;
      final spoken = prepare(
        'John 3, verse 16. $original',
        blockId: int.parse(verse.key),
      );
      expect(spoken, contains('sbpron'));
      expect(spoken, startsWith('John 3, verse 16.'));
    },
  );

  test('the same words as a note (no block id) receive no verse patches', () {
    final verse = firstPatchedVerse();
    final original = verse.value['text'] as String;
    expect(prepare(original), isNot(contains('sbpron')));
  });

  test(
    'a note that quotes a patched verse and is given a stale id is left alone',
    () {
      final verse = firstPatchedVerse();
      // Text differs from the stored verse, so offsets are never applied.
      final edited =
          'Paraphrase: ${(verse.value['text'] as String).toUpperCase()}';
      expect(
        prepare(edited, blockId: int.parse(verse.key)),
        isNot(contains('sbpron')),
      );
    },
  );

  test('modern prose passes through the shared corrections unchanged', () {
    const note =
        'We live in hope and lived by faith. He will live forever, and '
        'everyone should live for everyone else. Read it again; lead well.';
    final spoken = prepare(note);
    expect(spoken, isNot(contains('sbpron')));
    expect(spoken, contains('We live in hope and lived by faith.'));
    expect(spoken, contains('everyone should live for everyone else'));
    expect(spoken, contains('Read it again; lead well.'));
  });

  test('the corrections that do apply to notes are the intended ones', () {
    // "live forever" is a verb phrase in scripture and in modern prose alike.
    expect(prepare('They live forever.'), 'They liv forever.');
    expect(prepare('Sodom and Gomorrah.'), 'Soddum and go-morrah.');
    // Whole words only.
    expect(prepare('They live for everyone.'), 'They live for everyone.');
    expect(prepare('The shastas bloom.'), 'The shastas bloom.');
  });

  test('typographic apostrophes in notes are normalized for the engine', () {
    expect(prepare('God’s grace; don’t doubt.'), "God's grace; don't doubt.");
  });
}
