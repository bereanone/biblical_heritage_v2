import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_note_audio_cache.dart';

void main() {
  test('note recording key changes after text, voice, or pronunciation edits', () {
    String key({
      String text = 'Original note.',
      String pronunciation = '{}',
      String deferred = '{}',
      String voice = 'voice-v1',
      double bakedSpeed = 1,
    }) => tagNoteAudioKey(
      text: text,
      pronunciation: pronunciation,
      deferred: deferred,
      voiceRevision: voice,
      bakedSpeed: bakedSpeed,
    );

    final original = key();
    expect(key(), original);
    expect(key(text: 'Edited note.'), isNot(original));
    expect(key(pronunciation: '{"name":"new"}'), isNot(original));
    expect(key(deferred: '{"name":"new"}'), isNot(original));
    expect(key(voice: 'voice-v2'), isNot(original));
    expect(key(bakedSpeed: 1.2), isNot(original));
  });
}
