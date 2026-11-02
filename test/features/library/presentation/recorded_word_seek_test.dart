import 'dart:convert';
import 'dart:io';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';

void main() {
  const cue = RecordedLibraryAudioCue(
    Duration(seconds: 12),
    'word again word',
    phrases: [
      RecordedLibraryAudioCue(
        Duration.zero,
        'word',
        sourceOffset: 0,
        sourceEndOffset: 4,
      ),
      RecordedLibraryAudioCue(
        Duration(seconds: 1),
        'again',
        sourceOffset: 5,
        sourceEndOffset: 10,
      ),
      RecordedLibraryAudioCue(
        Duration(seconds: 2),
        'word',
        sourceOffset: 11,
        sourceEndOffset: 15,
      ),
    ],
  );
  test(
    'paragraph starts at its verified cue and repeated word uses its source coordinate',
    () {
      expect(recordedWordSeekPosition(cue, 0), const Duration(seconds: 12));
      expect(
        recordedWordSeekPosition(cue, 11),
        const Duration(milliseconds: 13920),
      );
      expect(
        recordedWordSeekPosition(cue, 13),
        const Duration(milliseconds: 13920),
      );
    },
  );
  test('unmapped selection backs up to the nearest source-timed word', () {
    expect(
      recordedWordSeekPosition(cue, 100),
      const Duration(milliseconds: 13920),
    );
    expect(
      recordedWordSeekPosition(cue, 10),
      const Duration(milliseconds: 12920),
    );
    expect(
      recordedWordSeekPosition(
        const RecordedLibraryAudioCue(Duration(seconds: 5), 'word'),
        2,
      ),
      isNull,
    );
  });
  test(
    'package parser retains source word coordinates, even for a one-word cue',
    () async {
      final root = await Directory.systemTemp.createTemp('word-timing-parser-');
      addTearDown(() => root.delete(recursive: true));
      final folder = await Directory('${root.path}/book').create();
      await File('${folder.path}/chapter.mp3').writeAsBytes([1]);
      await File('${folder.path}/audio-manifest.json').writeAsString(
        jsonEncode({
          'title': 'Word Timing',
          'total_chapters': 1,
          'tracks': [
            {
              'chapter': 1,
              'title': 'Words',
              'file': 'chapter.mp3',
              'cues': [
                {
                  'start_ms': 5000,
                  'end_ms': 6000,
                  'text': 'again',
                  'source_cursor': '1',
                  'phrases': [
                    {
                      'start_ms': 100,
                      'text': 'again',
                      'source_start_offset': 0,
                      'source_end_offset': 5,
                    },
                  ],
                },
              ],
            },
          ],
        }),
      );
      final package = await RecordedLibraryAudioPackage.findIn(
        root,
        'Word Timing',
      );
      final phrase = package!.tracks.single.cues.single.phrases.single;
      expect(phrase.sourceOffset, 0);
      expect(phrase.sourceEndOffset, 5);
      expect(phrase.start, const Duration(milliseconds: 100));
    },
  );
  test('bad metadata digest cannot hide exact source-owned recording', () {
    const items = [
      LibrarySpeechItem(
        cursor: '346',
        nextCursor: '347',
        text: 'Evolution, even that which recognizes a Creator, holds.',
      ),
    ];
    expect(
      recordedCueItemIndex(
        const RecordedLibraryAudioCue(
          Duration.zero,
          'Evolution, even that which recognizes a Creator, holds.',
          sourceCursor: '346',
          textDigest: 'bad-metadata',
        ),
        items,
      ),
      0,
    );
    expect(
      recordedCueItemIndex(
        const RecordedLibraryAudioCue(
          Duration.zero,
          'Unrelated content.',
          sourceCursor: '346',
          textDigest: 'bad-metadata',
        ),
        items,
      ),
      -1,
    );
  });
}
