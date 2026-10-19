import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  final items = [
    LibrarySpeechItem(
      cursor: '120',
      nextCursor: '121',
      text: 'Prior paragraph',
    ),
    LibrarySpeechItem(cursor: '121', nextCursor: '122', text: 'Summary'),
    LibrarySpeechItem(cursor: '122', nextCursor: '123', text: 'The Tabernacle'),
    LibrarySpeechItem(
      cursor: '123',
      nextCursor: '124',
      text: 'Built by Moses in the wilderness',
    ),
    LibrarySpeechItem(cursor: '124', nextCursor: '125', text: 'Summary'),
  ];
  test('Summary and short subheadings map to their own recorded audio', () {
    expect(
      recordedCueItemIndex(
        const RecordedLibraryAudioCue(
          Duration.zero,
          'Summary',
          sourceCursor: '121',
        ),
        items,
      ),
      1,
    );
    expect(
      recordedCueItemIndex(
        const RecordedLibraryAudioCue(
          Duration.zero,
          'The Tabernacle',
          sourceCursor: '122',
        ),
        items,
      ),
      2,
    );
  });
  test(
    'stale source location is checked and repeated headings remain forward',
    () {
      expect(
        recordedCueItemIndex(
          const RecordedLibraryAudioCue(
            Duration.zero,
            'Summary',
            sourceCursor: '120',
          ),
          items,
        ),
        1,
      );
      expect(
        recordedCueItemIndex(
          const RecordedLibraryAudioCue(Duration.zero, 'Summary'),
          items,
          startIndex: 3,
        ),
        4,
      );
      expect(
        recordedCueItemIndex(
          const RecordedLibraryAudioCue(Duration.zero, 'Missing'),
          items,
        ),
        -1,
      );
    },
  );
}
