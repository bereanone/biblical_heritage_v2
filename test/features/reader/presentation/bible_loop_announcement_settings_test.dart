import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Qwen loop cue assets include the chapter-six recording', () async {
    const cueRoot = String.fromEnvironment(
      'TEST_QWEN_CUE_ROOT',
      defaultValue: 'assets/audio/qwen_loop_cues',
    );
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                '$cueRoot/manifest.json',
              ),
            )
            as Map<String, dynamic>;
    final cues = manifest['cues'] as List<dynamic>;
    expect(cues, hasLength(392));
    final chapterSix = (cues.cast<Map<String, dynamic>>()).singleWhere(
      (cue) => cue['name'] == 'chapter_006',
    );
    expect(chapterSix['text'], 'Chapter six.');
    final bytes = await rootBundle.load(
      '$cueRoot/chapter_006.m4a',
    );
    expect(
      sha256
          .convert(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          )
          .toString(),
      chapterSix['audio_sha256'],
    );
  });

  test('book and chapter default on, verse off, and switches are independent', () {
    const defaults = BibleLoopAnnouncementSettings();
    expect(defaults.book, isTrue);
    expect(defaults.chapter, isTrue);
    expect(defaults.verse, isFalse);

    final chapterOnly = defaults.withValue(BibleLoopUnit.book, false);
    expect(chapterOnly.book, isFalse);
    expect(chapterOnly.chapter, isTrue);
    expect(chapterOnly.verse, isFalse);
    expect(
      chapterOnly.cueFor(
        BibleLoopUnit.chapter,
        bookName: 'Romans',
        chapterNumber: 6,
        verseNumber: 17,
      ),
      'Chapter six',
    );
    expect(
      chapterOnly.cueAssetFor(
        BibleLoopUnit.chapter,
        bookNumber: 45,
        chapterNumber: 6,
        verseNumber: 17,
      ),
      'assets/audio/qwen_loop_cues/chapter_006.m4a',
    );
    expect(
      chapterOnly.cueAssetFor(
        BibleLoopUnit.verse,
        bookNumber: 45,
        chapterNumber: 6,
        verseNumber: 17,
      ),
      isNull,
    );
    expect(
      chapterOnly.cueFor(
        BibleLoopUnit.verse,
        bookName: 'Romans',
        chapterNumber: 6,
        verseNumber: 17,
      ),
      isNull,
    );
  });

  test('book and verse cues say only their selected reference', () {
    const settings = BibleLoopAnnouncementSettings(book: true, verse: true);
    expect(
      settings.cueFor(
        BibleLoopUnit.book,
        bookName: 'Romans',
        chapterNumber: 6,
        verseNumber: 17,
      ),
      'Romans',
    );
    expect(
      settings.cueFor(
        BibleLoopUnit.verse,
        bookName: 'Romans',
        chapterNumber: 6,
        verseNumber: 17,
      ),
      'Verse seventeen',
    );
    expect(
      settings.cueFor(
        BibleLoopUnit.verse,
        bookName: 'Psalms',
        chapterNumber: 119,
        verseNumber: 176,
      ),
      'Verse one hundred seventy six',
    );
  });

  test('each switch persists without changing the others', () async {
    final saved = <String, String>{};
    final store = BibleLoopAnnouncementSettingsStore(
      loadValue: (key) async => saved[key],
      saveValue: (key, value) async {
        saved[key] = value;
      },
    );
    expect((await store.load()).book, isTrue);
    expect((await store.load()).chapter, isTrue);
    expect((await store.load()).verse, isFalse);
    await store.save(BibleLoopUnit.book, false);
    expect((await store.load()).book, isFalse);
    expect((await store.load()).chapter, isTrue);
    await store.save(BibleLoopUnit.verse, true);
    expect((await store.load()).verse, isTrue);
    await store.save(BibleLoopUnit.verse, false);
    await store.save(BibleLoopUnit.chapter, true);
    await store.save(BibleLoopUnit.book, true);
    await store.save(BibleLoopUnit.chapter, false);
    final reloaded = await store.load();
    expect(reloaded.book, isTrue);
    expect(reloaded.chapter, isFalse);
    expect(reloaded.verse, isFalse);
  });
}
