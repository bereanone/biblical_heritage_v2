import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_loop_announcement_settings.dart';
import 'package:studybible2/features/reader/presentation/bundled_bible_audio_narrator.dart';

BundledChapter _chapter(int chapter) => BundledChapter(
  book: 45,
  chapter: chapter,
  asset: 'unused',
  audioSha256: 'unused',
  durationSeconds: 30,
  segmentStarts: const [],
  verseStarts: const [
    BundledVerseStart(verse: 1, seconds: 2),
    BundledVerseStart(verse: 2, seconds: 10),
    BundledVerseStart(verse: 3, seconds: 20),
  ],
);

void main() {
  test('all enabled announcements follow their own recorded boundaries', () {
    final first = _chapter(1).announcementEvents(
      const BibleLoopAnnouncementSettings(
        book: true,
        chapter: true,
        verse: true,
      ),
    );
    expect(first.map((event) => event.seconds), [0, 2, 10, 20]);
    expect(first.first.assets, [
      'assets/audio/qwen_loop_cues/book_45.m4a',
      'assets/audio/qwen_loop_cues/chapter_001.m4a',
    ]);
    expect(first[2].assets, ['assets/audio/qwen_loop_cues/verse_002.m4a']);

    final later = _chapter(6).announcementEvents(
      const BibleLoopAnnouncementSettings(
        book: true,
        chapter: true,
        verse: true,
      ),
    );
    expect(later.first.assets, ['assets/audio/qwen_loop_cues/chapter_006.m4a']);
  });

  test('verse labels can be on independently of chapter and book labels', () {
    final events = _chapter(
      6,
    ).announcementEvents(const BibleLoopAnnouncementSettings(verse: true));
    expect(events.map((event) => event.seconds), [2, 10, 20]);
    expect(events.last.assets.single, endsWith('verse_003.m4a'));
    expect(_chapter(6).rangeForVerse(2), (10.0, 20.0));
    expect(
      _chapter(6).announcementEvents(const BibleLoopAnnouncementSettings()),
      isEmpty,
    );
  });

  test('book repeat and verse announcements work across chapters and wrap', () {
    const settings = BibleLoopAnnouncementSettings(verse: true);
    final middle = _chapter(6).announcementEvents(settings);
    final last = _chapter(16).announcementEvents(settings);
    final first = _chapter(1).announcementEvents(settings);

    for (final events in [middle, last, first]) {
      expect(events.map((event) => event.seconds), [2, 10, 20]);
      expect(events.first.assets.single, endsWith('verse_001.m4a'));
      expect(events.last.assets.single, endsWith('verse_003.m4a'));
    }
    expect(bundledRepeatRange(_chapter(16)), isNull);
    expect(
      bundledBookShouldWrap(currentBook: 45, adjacentBook: 46, loopBook: 45),
      isTrue,
    );
    expect(
      bundledBookShouldWrap(currentBook: 45, adjacentBook: 45, loopBook: 45),
      isFalse,
    );
  });

  test('verse, chapter, and book repeat have distinct boundaries', () {
    final chapter = _chapter(6);
    expect(bundledRepeatRange(chapter, verse: 2), (10.0, 20.0));
    expect(bundledRepeatRange(chapter, repeatChapter: true), (0.0, 30.0));
    expect(bundledRepeatRange(chapter), isNull);
    expect(
      bundledBookShouldWrap(currentBook: 45, adjacentBook: 45, loopBook: 45),
      isFalse,
    );
    expect(
      bundledBookShouldWrap(currentBook: 45, adjacentBook: 46, loopBook: 45),
      isTrue,
    );
    expect(
      bundledBookShouldWrap(currentBook: 45, adjacentBook: null, loopBook: 45),
      isTrue,
    );
  });

  test(
    'a live nonempty verse schedule must be acknowledged by native audio',
    () async {
      final events = _chapter(
        6,
      ).announcementEvents(const BibleLoopAnnouncementSettings(verse: true));
      final payload = events
          .map(
            (event) => <String, Object>{
              'seconds': event.seconds,
              'paths': event.assets
                  .map((asset) => '/tmp/${asset.split('/').last}')
                  .toList(),
            },
          )
          .toList();
      List<Map<String, Object>>? received;
      await sendBundledAnnouncementEvents(payload, (sent) async {
        received = sent;
        return sent.length;
      });
      expect(received, hasLength(3));
      expect(received![1]['paths'], ['/tmp/verse_002.m4a']);
      await expectLater(
        sendBundledAnnouncementEvents(payload, (_) async => 0),
        throwsStateError,
      );
    },
  );
}
