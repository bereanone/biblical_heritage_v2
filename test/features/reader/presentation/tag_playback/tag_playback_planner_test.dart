import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/database/study_bible_database.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_qwen_audio_cache.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_planner.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

HashTagEntry entry(
  int id, {
  int book = 43,
  int chapter = 3,
  int verse = 16,
  int? verseEnd,
  String verseText = 'For God so loved the world.',
  String? noteText,
  String? contentHtml,
  String? displayTextOverride,
  String? userTitle,
  String? referenceCode,
  String? noteFormatJson,
  String? verseRef,
  List<String> mediaRefs = const [],
}) => HashTagEntry(
  id: id,
  bookNumber: book,
  chapter: chapter,
  verse: verse,
  verseEnd: verseEnd ?? verse,
  verseRef: verseRef ?? '$book:$chapter:$verse',
  verseText: verseText,
  createdAt: id,
  sortOrder: id,
  noteText: noteText,
  contentHtml: contentHtml,
  displayTextOverride: displayTextOverride,
  userTitle: userTitle,
  referenceCode: referenceCode,
  noteFormatJson: noteFormatJson,
  mediaRefs: mediaRefs,
);

TagPlaybackPlanner planner({BlockIdResolver? resolve}) => TagPlaybackPlanner(
  bookNames: const {
    1: 'Genesis',
    19: 'Psalms',
    43: 'John',
    62: '1 John',
    22: 'Song of Solomon',
  },
  resolveBlockId: resolve ?? (b, c, v) async => b * 100000 + c * 1000 + v,
);

List<String> texts(List<TagSpeechClip> clips) => [
  for (final c in clips) c.text,
];

void main() {
  group('spoken references', () {
    test('reads chapter and verse in words, not as digits with a colon', () {
      expect(
        spokenBibleReference(
          bookName: 'John',
          chapter: 3,
          verseStart: 16,
          verseEnd: 16,
        ),
        'John 3, verse 16',
      );
    });

    test('spells out numbered books and singular Psalm', () {
      String ref(String book) => spokenBibleReference(
        bookName: book,
        chapter: 1,
        verseStart: 8,
        verseEnd: 9,
      );
      expect(ref('1 John'), 'First John 1, verses 8 to 9');
      expect(ref('2 Kings'), 'Second Kings 1, verses 8 to 9');
      expect(ref('3 John'), 'Third John 1, verses 8 to 9');
      expect(ref('Psalms'), 'Psalm 1, verses 8 to 9');
      expect(ref('Song of Solomon'), 'Song of Solomon 1, verses 8 to 9');
    });
  });

  group('planning one entry', () {
    test('speaks the reference, then the verse, then the note', () async {
      final items = await planner().plan([
        entry(1, noteText: 'This is the gospel in one line.'),
      ]);
      final item = items.single;
      expect(texts(item.contentClips), [
        'John 3, verse 16. For God so loved the world.',
      ]);
      expect(
        [for (final c in item.noteClips) c.body],
        ['This is the gospel in one line.'],
      );
      expect(item.clipsFor(includeNotes: true).map((c) => c.kind), [
        TagClipKind.verse,
        TagClipKind.note,
      ]);
      expect(item.label, 'John 3:16');
    });

    test('verses-only omits the note', () async {
      final item = (await planner().plan([
        entry(1, noteText: 'A note.'),
      ])).single;
      expect(texts(item.clipsFor(includeNotes: false)), [
        'John 3, verse 16. For God so loved the world.',
      ]);
    });

    test('an entry with no note has no note clips', () async {
      final item = (await planner().plan([entry(1)])).single;
      expect(item.hasNote, isFalse);
      expect(
        item.clipsFor(includeNotes: true),
        item.clipsFor(includeNotes: false),
      );
      final blank = (await planner().plan([
        entry(2, noteText: '  \n '),
      ])).single;
      expect(blank.hasNote, isFalse);
    });

    test('attached images produce no speech and no placeholder', () async {
      final item = (await planner().plan([
        entry(1, mediaRefs: const ['media/one.png', 'media/two.png']),
      ])).single;
      final spoken = texts(item.clipsFor(includeNotes: true)).join(' ');
      expect(spoken.toLowerCase(), isNot(contains('image')));
      expect(spoken.toLowerCase(), isNot(contains('attached')));
      expect(item.clipsFor(includeNotes: true), hasLength(1));
    });

    test('an image-only entry with no text is silent', () async {
      final item = (await planner().plan([
        entry(
          1,
          book: 0,
          chapter: 0,
          verse: 0,
          verseText: '',
          mediaRefs: const ['media/one.png'],
        ),
      ])).single;
      expect(item.clipsFor(includeNotes: true), isEmpty);
    });

    test(
      'the verse clip carries the block id so KJV patches can apply',
      () async {
        final asked = <List<int>>[];
        final item = (await planner(
          resolve: (b, c, v) async {
            asked.add([b, c, v]);
            return 4242;
          },
        ).plan([entry(1)])).single;
        expect(asked, [
          [43, 3, 16],
        ]);
        expect(item.contentClips.single.blockId, 4242);
      },
    );

    test('notes never carry a block id', () async {
      final item = (await planner().plan([
        entry(1, noteText: 'Modern prose.'),
      ])).single;
      expect(item.noteClips.every((c) => c.blockId == null), isTrue);
    });

    test('a failing block-id lookup only loses the patches', () async {
      final item = (await planner(
        resolve: (b, c, v) async => throw StateError('db closed'),
      ).plan([entry(1)])).single;
      expect(item.contentClips, hasLength(1));
      expect(item.contentClips.single.blockId, isNull);
    });

    test(
      'a verse range becomes one clip per verse, each with its own block id',
      () async {
        final item = (await planner().plan([
          entry(
            1,
            verse: 16,
            verseEnd: 18,
            verseText: 'Sixteen text.\nSeventeen text.\nEighteen text.',
          ),
        ])).single;
        expect(texts(item.contentClips), [
          'John 3, verse 16. Sixteen text.',
          'Seventeen text.',
          'Eighteen text.',
        ]);
        expect(item.contentClips.map((c) => c.blockId), [
          43 * 100000 + 3016,
          43 * 100000 + 3017,
          43 * 100000 + 3018,
        ]);
        expect(item.label, 'John 3:16-18');
        for (var index = 0; index < item.contentClips.length; index++) {
          final clip = item.contentClips[index];
          final verse = BibleVerseRecord(
            blockId: clip.blockId!, bookNumber: 43, bookName: 'John',
            chapter: 3, verse: 16 + index, text: clip.body,
          );
          for (final announcements in [true, false]) {
            expect(tagCanUseQwen(clip.resolved(speakReference: announcements)!, verse), isTrue,
              reason: 'Every verse, including the first, keeps the recorded voice');
          }
        }

      },
    );

    test(
      'a range whose lines do not match falls back to one clip without patches',
      () async {
        final item = (await planner().plan([
          entry(1, verse: 16, verseEnd: 18, verseText: 'Only one line.'),
        ])).single;
        expect(texts(item.contentClips), [
          'John 3, verses 16 to 18. Only one line.',
        ]);
        expect(item.contentClips.single.blockId, isNull);
      },
    );

    test('edited display text is what gets spoken', () async {
      final item = (await planner().plan([
        entry(1, displayTextOverride: 'My paraphrase.'),
      ])).single;
      expect(texts(item.contentClips), ['John 3, verse 16. My paraphrase.']);
    });

    test('note-only items speak their title and text; with notes off only the '
        'title remains', () async {
      final item = (await planner().plan([
        entry(
          1,
          book: 0,
          chapter: 0,
          verse: 0,
          verseText: '',
          userTitle: 'Reminder',
          noteText: 'Pray daily.',
        ),
      ])).single;
      expect(item.label, 'Reminder');
      expect(texts(item.clipsFor(includeNotes: true)), [
        'Reminder.',
        'Pray daily.',
      ]);
      expect(texts(item.clipsFor(includeNotes: false)), ['Reminder.']);
    });

    test('dollar-tag html notes are read as plain text', () async {
      final item = (await planner().plan([
        entry(1, contentHtml: '<p>First&nbsp;line<br/>Second &amp; last</p>'),
      ])).single;
      expect(
        [for (final c in item.noteClips) c.body],
        ['First line', 'Second & last'],
      );
    });

    test(
      'a note on a verse with missing text still says where it belongs',
      () async {
        final item = (await planner().plan([
          entry(1, verseText: '', noteText: 'Orphan note.'),
        ])).single;
        expect(texts(item.contentClips), ['John 3, verse 16.']);
        expect(texts(item.clipsFor(includeNotes: true)), [
          'John 3, verse 16.',
          'Orphan note.',
        ]);
        expect(texts(item.clipsFor(includeNotes: false)), [
          'John 3, verse 16.',
        ]);
      },
    );
  });

  group('plan order', () {
    test('keeps the entries in the order given', () async {
      final items = await planner().plan([
        entry(5, book: 43, chapter: 1, verse: 1),
        entry(2, book: 1, chapter: 1, verse: 1),
        entry(9, book: 19, chapter: 23, verse: 1),
      ]);
      expect(items.map((i) => i.entryId), [5, 2, 9]);
      expect(items.map((i) => i.label), [
        'John 1:1',
        'Genesis 1:1',
        'Psalms 23:1',
      ]);
    });

    test('yields an item for every entry, even silent ones', () async {
      final items = await planner().plan([
        entry(1),
        entry(2, book: 0, chapter: 0, verse: 0, verseText: ''),
        entry(3),
      ]);
      expect(items, hasLength(3));
      expect(items[1].clipsFor(includeNotes: true), isEmpty);
    });

    test('an empty tag plans nothing', () async {
      expect(await planner().plan(const []), isEmpty);
    });
  });

  group('splitIntoSpeechChunks', () {
    test('keeps a short note as one clip', () {
      expect(splitIntoSpeechChunks('One. Two. Three.'), ['One. Two. Three.']);
    });

    test('packs whole sentences up to the limit', () {
      final chunks = splitIntoSpeechChunks(
        'Aaaa aaaa. Bbbb bbbb. Cccc cccc. Dddd dddd.',
        maxChars: 24,
      );
      expect(chunks, ['Aaaa aaaa. Bbbb bbbb.', 'Cccc cccc. Dddd dddd.']);
      expect(chunks.every((c) => c.length <= 24), isTrue);
    });

    test('never splits inside a sentence, even a long one', () {
      final long = 'word ' * 100;
      final chunks = splitIntoSpeechChunks(
        '${long.trim()}. Short.',
        maxChars: 50,
      );
      expect(chunks.length, 2);
      expect(chunks.last, 'Short.');
    });

    test('starts a new clip at every paragraph break', () {
      expect(splitIntoSpeechChunks('First para.\n\nSecond para.'), [
        'First para.',
        'Second para.',
      ]);
    });

    test('ignores blank text', () {
      expect(splitIntoSpeechChunks('  \n\n '), isEmpty);
    });
  });
}
