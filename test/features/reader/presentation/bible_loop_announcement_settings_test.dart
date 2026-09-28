import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Qwen loop cue assets include the chapter-six recording', () async {
    final manifest =
        jsonDecode(
              await rootBundle.loadString(
                'assets/audio/qwen_loop_cues/manifest.json',
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
      'assets/audio/qwen_loop_cues/chapter_006.m4a',
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

  test('announcements are off by default and independent', () {
    const defaults = BibleLoopAnnouncementSettings();
    expect(defaults.book, isFalse);
    expect(defaults.chapter, isFalse);
    expect(defaults.verse, isFalse);

    final chapterOnly = defaults.withValue(BibleLoopUnit.chapter, true);
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
    expect((await store.load()).chapter, isFalse);
    await store.save(BibleLoopUnit.chapter, true);
    await store.save(BibleLoopUnit.book, true);
    await store.save(BibleLoopUnit.chapter, false);
    final reloaded = await store.load();
    expect(reloaded.book, isTrue);
    expect(reloaded.chapter, isFalse);
    expect(reloaded.verse, isFalse);
  });
}
