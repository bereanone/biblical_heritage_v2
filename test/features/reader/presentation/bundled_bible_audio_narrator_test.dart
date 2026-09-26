import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bundled_bible_audio_narrator.dart';

void main() {
  test('recorded chapter uses actual verse onsets for lookup', () {
    final chapter = BundledChapter.fromJson({
      'book': 58,
      'chapter': 4,
      'asset': 'assets/audio/qwen_bible/58_Heb_004.m4a',
      'audioSha256': 'test',
      'durationSeconds': 122.48,
      'segmentStarts': [
        {'seconds': 0, 'firstVerse': 1},
        {'seconds': 44.24, 'firstVerse': 7},
      ],
      'verseStarts': [
        {'seconds': 0.54, 'verse': 1},
        {'seconds': 7.703, 'verse': 2},
        {'seconds': 16.247, 'verse': 3},
      ],
    });

    expect(chapter.secondsForVerse(2), 7.703);
    expect(chapter.secondsForVerse(4), isNull);
    expect(chapter.verseForPosition(7.702), 1);
    expect(chapter.verseForPosition(7.703), 2);
    expect(chapter.verseForPosition(16.3), 3);
    expect(chapter.rangeForVerse(2), (7.703, 16.247));
    expect(chapter.rangeForVerse(3), (16.247, 122.48));
    expect(chapter.rangeForVerse(4), isNull);
  });
}
