import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_panel.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_settings.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

import 'tag_playback_fakes.dart';
import 'tag_playback_planner_test.dart' show entry, planner;

/// What is spoken for [item] under the given switches.
List<String> spoken(
  TagPlaybackItem item, {
  bool notes = true,
  bool reference = true,
}) => [
  for (final c in item.clipsFor(includeNotes: notes, speakReference: reference))
    c.text,
];

const _quote = 'Faith is the hand that grasps the promise.';

String _eLibraryJson({
  String title = 'Steps to Christ',
  String acronym = 'SC',
  String location = 'SC 12.3',
  String referenceText = '',
  int? page = 12,
  int? paragraph = 3,
  String excerpt = _quote,
}) => jsonEncode({
  'kind': 'elibrary_note',
  'source_title': title,
  'source_title_acronym': acronym,
  'source_location': location,
  'source_reference_text': referenceText,
  'source_page_number': page,
  'source_paragraph_number': paragraph,
  'excerpt': excerpt,
  'stable_ref': 'elibrary:item:1:2',
});

/// A saved eLibrary quote: no Bible anchor, the quote stored as the note text
/// (which is how a freshly saved passage looks) unless [noteText] is given.
HashTagEntry eLibraryEntry({
  String? json,
  String? noteText = _quote,
  String? userTitle,
}) => entry(
  1,
  book: 0,
  chapter: 0,
  verse: 0,
  verseText: '',
  verseRef: 'elibrary:item:1:2',
  noteText: noteText,
  userTitle: userTitle,
  noteFormatJson: json ?? _eLibraryJson(),
);

HashTagEntry noteOnlyEntry({
  String? userTitle,
  String? referenceCode,
  String? noteText = 'Pray daily.',
}) => entry(
  1,
  book: 0,
  chapter: 0,
  verse: 0,
  verseText: '',
  verseRef: 'note:1',
  userTitle: userTitle,
  referenceCode: referenceCode,
  noteText: noteText,
);

Future<TagPlaybackItem> plan(HashTagEntry e) async =>
    (await planner().plan([e])).single;

void main() {
  group('scripture entries', () {
    test('reference on: reference and verse, then the note', () async {
      final item = await plan(entry(1, noteText: 'A note.'));
      expect(spoken(item), [
        'John 3, verse 16. For God so loved the world.',
        'A note.',
      ]);
    });

    test('reference off: the verse and the note, no identifier', () async {
      final item = await plan(entry(1, noteText: 'A note.'));
      expect(spoken(item, reference: false), [
        'For God so loved the world.',
        'A note.',
      ]);
    });

    test('notes off leaves the reference decision alone', () async {
      final item = await plan(entry(1, noteText: 'A note.'));
      expect(spoken(item, notes: false), [
        'John 3, verse 16. For God so loved the world.',
      ]);
      expect(spoken(item, notes: false, reference: false), [
        'For God so loved the world.',
      ]);
    });

    test('a verse with no text is still announced, then its note', () async {
      final item = await plan(entry(1, verseText: '', noteText: 'A note.'));
      expect(spoken(item), ['John 3, verse 16.', 'A note.']);
      expect(spoken(item, reference: false), ['A note.']);
      expect(spoken(item, notes: false), ['John 3, verse 16.']);
    });
  });

  group('eLibrary passages', () {
    test('are told apart from notes by their stored metadata', () async {
      final item = await plan(eLibraryEntry());
      expect(item.contentClips.single.kind, TagClipKind.passage);
    });

    test('reference on: work and location, then the quote', () async {
      final item = await plan(eLibraryEntry());
      expect(spoken(item), ['Steps to Christ, page 12, paragraph 3. $_quote']);
    });

    test('reference off: the quote alone', () async {
      final item = await plan(eLibraryEntry());
      expect(spoken(item, reference: false), [_quote]);
    });

    test('a note equal to the quote is not read a second time', () async {
      final item = await plan(eLibraryEntry());
      expect(item.hasNote, isFalse);
    });

    test('the user\'s own note follows the quote, when notes are on', () async {
      final item = await plan(eLibraryEntry(noteText: 'My reflection.'));
      expect(spoken(item), [
        'Steps to Christ, page 12, paragraph 3. $_quote',
        'My reflection.',
      ]);
      expect(spoken(item, reference: false), [_quote, 'My reflection.']);
      // The quote is the entry's content, so it is not switched off with notes.
      expect(spoken(item, notes: false, reference: false), [_quote]);
    });

    test(
      'a long quote is split into clips, the reference on the first',
      () async {
        final long = List.filled(
          30,
          'A sentence that runs on a while.',
        ).join(' ');
        final item = await plan(
          eLibraryEntry(
            json: _eLibraryJson(excerpt: long),
            noteText: long,
          ),
        );
        final on = spoken(item);
        expect(on.length, greaterThan(1));
        expect(on.first, startsWith('Steps to Christ, page 12, paragraph 3. '));
        expect(on.skip(1).any((t) => t.contains('Steps to Christ')), isFalse);
      },
    );

    test('a location of ¶ shorthand is spoken as words', () async {
      final item = await plan(
        eLibraryEntry(
          json: _eLibraryJson(
            title: 'Ministry of Healing',
            acronym: 'MH',
            location: 'MH ¶4',
            page: null,
            paragraph: null,
          ),
        ),
      );
      expect(
        spoken(item).first,
        startsWith('Ministry of Healing, paragraph 4.'),
      );
    });

    test('a work with no known location is announced by title alone', () async {
      final item = await plan(
        eLibraryEntry(
          json: _eLibraryJson(location: '', page: null, paragraph: null),
        ),
      );
      expect(spoken(item).first, 'Steps to Christ. $_quote');
    });

    test('an acronym is not cut out of the middle of a word', () async {
      final item = await plan(
        eLibraryEntry(
          json: _eLibraryJson(location: 'Schemes of Men', page: null),
        ),
      );
      expect(
        spoken(item).first,
        startsWith('Steps to Christ, Schemes of Men.'),
      );
    });

    test(
      'an unknown source falls back to the user\'s title, then to none',
      () async {
        final unknown = _eLibraryJson(
          title: '',
          acronym: '',
          location: '',
          page: null,
          paragraph: null,
        );
        final titled = await plan(
          eLibraryEntry(json: unknown, userTitle: 'Faith quote'),
        );
        expect(spoken(titled), ['Faith quote. $_quote']);
        final bare = await plan(eLibraryEntry(json: unknown));
        expect(spoken(bare), [_quote]);
      },
    );
  });

  group('note-only entries', () {
    test('titled, reference on: the title, then the note', () async {
      final item = await plan(noteOnlyEntry(userTitle: 'Reminder'));
      expect(spoken(item), ['Reminder.', 'Pray daily.']);
    });

    test('titled, reference off: the note alone', () async {
      final item = await plan(noteOnlyEntry(userTitle: 'Reminder'));
      expect(spoken(item, reference: false), ['Pray daily.']);
    });

    test(
      'is not skipped when notes are off: its title is still said',
      () async {
        final item = await plan(noteOnlyEntry(userTitle: 'Reminder'));
        expect(spoken(item, notes: false), ['Reminder.']);
        expect(item.clipsFor(includeNotes: false), isNotEmpty);
      },
    );

    test('with no title, the reference code identifies it', () async {
      final item = await plan(noteOnlyEntry(referenceCode: 'Study 4'));
      expect(spoken(item), ['Study 4.', 'Pray daily.']);
      expect(spoken(item, reference: false), ['Pray daily.']);
    });

    test('with no title or code it is simply read', () async {
      final item = await plan(noteOnlyEntry());
      expect(spoken(item), ['Pray daily.']);
      expect(spoken(item, reference: false), ['Pray daily.']);
    });

    test('with nothing at all to say it is silent, not an error', () async {
      final item = await plan(noteOnlyEntry(noteText: null));
      expect(spoken(item), isEmpty);
    });

    test('dollar-tag slide html is read as the note', () async {
      final item = await plan(
        entry(
          1,
          book: 0,
          chapter: 0,
          verse: 0,
          verseText: '',
          verseRef: 'slide:1',
          userTitle: 'Slide',
          contentHtml: '<p>Line one<br/>Line two</p>',
        ),
      );
      expect(spoken(item), ['Slide.', 'Line one', 'Line two']);
    });
  });

  group('the word "Note" is never spoken', () {
    test('by any entry type under any combination of switches', () async {
      final entries = [
        entry(1, noteText: 'A thought.'),
        entry(1, verseText: '', noteText: 'A thought.'),
        eLibraryEntry(noteText: 'A thought.'),
        eLibraryEntry(),
        noteOnlyEntry(userTitle: 'Reminder', noteText: 'A thought.'),
        noteOnlyEntry(noteText: 'A thought.'),
      ];
      for (final e in entries) {
        final item = await plan(e);
        for (final notes in [true, false]) {
          for (final reference in [true, false]) {
            for (final line in spoken(
              item,
              notes: notes,
              reference: reference,
            )) {
              expect(
                line,
                isNot(matches(RegExp(r'\bnote\b', caseSensitive: false))),
              );
            }
          }
        }
      }
    });

    test('an untitled note is never given a spoken label', () async {
      final item = await plan(noteOnlyEntry());
      expect(item.contentClips, isEmpty);
    });
  });

  group('playback', () {
    test('a note-only entry is announced and read, not skipped', () async {
      final items = await planner().plan([
        noteOnlyEntry(userTitle: 'Reminder'),
        entry(2, noteText: 'A note.'),
      ]);
      final h = Harness(items);
      h.controller.play();
      await h.settle();
      expect(h.renderer.requestedTexts.take(2), ['Reminder.', 'Pray daily.']);
      expect(h.controller.speakableEntryCount, 2);
      h.controller.dispose();
    });

    test(
      'switching the reference off mid-playback drops every identifier',
      () async {
        final items = await planner().plan([
          eLibraryEntry(),
          noteOnlyEntry(userTitle: 'Reminder'),
          entry(3, noteText: 'A note.'),
        ]);
        final h = Harness(items);
        h.controller.setSpeakReference(false);
        h.controller.play();
        await h.settle();
        final said = h.renderer.requestedTexts;
        expect(said, contains(_quote));
        expect(said, contains('Pray daily.'));
        expect(said, contains('For God so loved the world.'));
        expect(said.where((t) => t.contains('Steps to Christ')), isEmpty);
        expect(said.where((t) => t.contains('Reminder')), isEmpty);
        expect(said.where((t) => t.contains('John 3')), isEmpty);
        h.controller.dispose();
      },
    );

    test('an entry with only an identifier is silent once it is off', () async {
      final items = await planner().plan([
        noteOnlyEntry(userTitle: 'Reminder', noteText: null),
      ]);
      final h = Harness(items);
      expect(h.controller.canPlay, isTrue);
      h.controller.setSpeakReference(false);
      expect(h.controller.canPlay, isFalse);
      h.controller.dispose();
    });
  });

  group('settings', () {
    test('are the reference, notes and loop switches only', () async {
      final values = <String, String>{};
      final store = AppTagPlaybackSettingsStore(
        load: (key) async => values[key],
        save: (key, value) async => values[key] = value,
      );
      await store.save(const TagPlaybackSettings());
      expect(values.keys.toSet(), {
        AppTagPlaybackSettingsStore.speakReferenceKey,
        AppTagPlaybackSettingsStore.speakNotesKey,
        AppTagPlaybackSettingsStore.loopKey,
      });
    });

    test('a leftover stored "announce note" value is ignored', () async {
      final store = AppTagPlaybackSettingsStore(
        load: (key) async => key == 'tag_playback.announce_note' ? '1' : null,
        save: (_, _) async {},
      );
      expect(await store.load(), const TagPlaybackSettings());
    });
  });

  group('settings panel', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 500, height: 900, child: child)),
    );

    testWidgets('groups entry introductions and notes, with no Note label', (
      tester,
    ) async {
      final h = Harness([fakeItem(0, notes: 1)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      await tester.tap(find.byKey(const Key('tag_playback_settings')));
      await tester.pump();
      expect(find.text('Entry introductions'), findsOneWidget);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Bible text'), findsNothing);
      expect(find.textContaining('Begin with'), findsNothing);
      expect(
        find.byKey(const Key('tag_playback_setting_announce_note')),
        findsNothing,
      );
      expect(find.byType(SwitchListTile), findsNWidgets(2));
      expect(find.text('Speak reference'), findsOneWidget);
      expect(find.text('Speak notes'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('the reference switch drives the controller', (tester) async {
      final h = Harness([fakeItem(0, notes: 1)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      await tester.tap(find.byKey(const Key('tag_playback_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tag_playback_setting_reference')));
      await tester.pump();
      expect(h.controller.speakReference, isFalse);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });
  });
}
