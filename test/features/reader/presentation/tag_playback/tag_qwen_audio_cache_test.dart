import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_qwen_audio_cache.dart';

void main() {
  const verse = BibleVerseRecord(
    blockId: 123,
    bookNumber: 43,
    bookName: 'John',
    chapter: 11,
    verse: 14,
    text: 'Then said Jesus unto them plainly, Lazarus is dead.',
  );
  const clip = TagSpeechClip(
    text: 'Then said Jesus unto them plainly, Lazarus is dead.',
    kind: TagClipKind.verse,
    blockId: 123,
    reference: 'John 11, verse 14',
  );
  test('reference on and off both retain the exact Qwen verse identity', () {
    for (final enabled in [true, false]) {
      final resolved = clip.resolved(speakReference: enabled)!;
      expect(tagCanUseQwen(resolved, verse), isTrue);
      expect(resolved.sourceReference, enabled ? clip.reference : null);
      expect(resolved.text, enabled ? clip.text : clip.body);
    }
  });
  test(
    'edited verse and excerpt never play a different canonical recording',
    () {
      for (final body in [
        'Lazarus is dead.',
        'Then said Jesus unto them plainly, Lazarus is alive.',
      ]) {
        expect(
          tagCanUseQwen(
            TagSpeechClip(text: body, kind: TagClipKind.verse, blockId: 123),
            verse,
          ),
          isFalse,
        );
      }
    },
  );
  test(
    'notes, other verse identities and range references use exact-text fallback',
    () {
      expect(
        tagCanUseQwen(
          TagSpeechClip(text: verse.text, kind: TagClipKind.note, blockId: 123),
          verse,
        ),
        isFalse,
      );
      expect(
        tagCanUseQwen(
          TagSpeechClip(
            text: verse.text,
            kind: TagClipKind.verse,
            blockId: 456,
          ),
          verse,
        ),
        isFalse,
      );
      expect(
        tagCanUseQwen(
          TagSpeechClip(
            text: verse.text,
            kind: TagClipKind.verse,
            blockId: 123,
            reference: 'John 11, verses 14 to 15',
          ),
          verse,
        ),
        isFalse,
      );
    },
  );
  test('whitespace changes preserve a matching verse', () {
    expect(
      tagCanUseQwen(
        TagSpeechClip(
          text: '  ${verse.text.replaceAll(' ', '  ')}\n',
          kind: TagClipKind.verse,
          blockId: 123,
        ),
        verse,
      ),
      isTrue,
    );
  });
}
