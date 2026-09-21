import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/bible_pronunciation_map.dart';
import 'package:studybible2/features/reader/presentation/narration_pronunciation.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_controller.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_panel.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_planner.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_settings.dart';
import 'package:studybible2/features/reader/presentation/tag_quick_apply_helper.dart';

import 'tag_playback_fakes.dart';

HashTagEntry entry(
  int id, {
  int book = 43,
  int chapter = 3,
  int verse = 16,
  int? verseEnd,
  String verseText = 'For God so loved the world.',
  String? noteText,
}) => HashTagEntry(
  id: id,
  bookNumber: book,
  chapter: chapter,
  verse: verse,
  verseEnd: verseEnd ?? verse,
  verseRef: '$book:$chapter:$verse',
  verseText: verseText,
  createdAt: id,
  sortOrder: id,
  noteText: noteText,
);

TagPlaybackPlanner planner() => TagPlaybackPlanner(
  bookNames: const {43: 'John'},
  resolveBlockId: (b, c, v) async => b * 100000 + c * 1000 + v,
);

/// A store that remembers in memory, standing in for the settings table.
class MemoryStore {
  final Map<String, String> values = {};
  AppTagPlaybackSettingsStore get store => AppTagPlaybackSettingsStore(
    load: (key) async => values[key],
    save: (key, value) async => values[key] = value,
  );
}

void main() {
  group('settings store', () {
    test('defaults: reference on, notes on, loop off', () async {
      final loaded = await MemoryStore().store.load();
      expect(loaded.speakReference, isTrue);
      expect(loaded.speakNotes, isTrue);
      expect(loaded.loop, isFalse);
    });

    test('every toggle survives a save and a fresh load', () async {
      final memory = MemoryStore();
      await memory.store.save(
        const TagPlaybackSettings(
          speakReference: false,
          speakNotes: false,
          loop: true,
        ),
      );
      final loaded = await memory.store.load();
      expect(loaded.speakReference, isFalse);
      expect(loaded.speakNotes, isFalse);
      expect(loaded.loop, isTrue);
    });

    test('an unreadable or garbled store falls back to the defaults', () async {
      final broken = AppTagPlaybackSettingsStore(
        load: (_) async => throw StateError('db closed'),
        save: (_, _) async => throw StateError('db closed'),
      );
      expect(await broken.load(), const TagPlaybackSettings());
      await broken.save(const TagPlaybackSettings()); // Must not throw.
      final garbled = AppTagPlaybackSettingsStore(load: (_) async => 'maybe');
      expect(await garbled.load(), const TagPlaybackSettings());
    });

    test('changing a setting on the controller reports it for saving', () {
      final seen = <TagPlaybackSettings>[];
      final h = Harness([fakeItem(0, notes: 1)]);
      final controller = TagPlaybackController(
        items: h.controller.items,
        renderer: h.renderer,
        player: h.player,
        onSettingsChanged: seen.add,
      );
      controller.setSpeakReference(false);
      controller.setIncludeNotes(false);
      controller.setLoop(true);
      controller.setLoop(true); // Unchanged: nothing to save.
      expect(seen, [
        const TagPlaybackSettings(speakReference: false),
        const TagPlaybackSettings(speakReference: false, speakNotes: false),
        const TagPlaybackSettings(
          speakReference: false,
          speakNotes: false,
          loop: true,
        ),
      ]);
      controller.dispose();
      h.controller.dispose();
    });
  });

  group('reference off', () {
    test(
      'the reference is a separate part of the clip, not baked in',
      () async {
        final item = (await planner().plan([entry(1)])).single;
        final clip = item.contentClips.single;
        expect(clip.reference, 'John 3, verse 16');
        expect(clip.body, 'For God so loved the world.');
        expect(clip.text, 'John 3, verse 16. For God so loved the world.');
        expect(clip.blockId, 4303016);
      },
    );

    test('speaks exactly the verse text, keeping its verse id', () async {
      final item = (await planner().plan([entry(1)])).single;
      final clips = item.clipsFor(includeNotes: true, speakReference: false);
      expect(clips.map((c) => c.text), ['For God so loved the world.']);
      expect(clips.single.blockId, 4303016);
      expect(clips.single.reference, isNull);
    });

    test(
      'a range keeps one clip per verse and drops only the lead-in',
      () async {
        final item = (await planner().plan([
          entry(
            1,
            verse: 16,
            verseEnd: 17,
            verseText: 'For God so loved the world.\nFor God sent not his Son.',
          ),
        ])).single;
        expect(item.clipsFor(includeNotes: false).map((c) => c.text), [
          'John 3, verses 16 to 17. For God so loved the world.',
          'For God sent not his Son.',
        ]);
        expect(
          item
              .clipsFor(includeNotes: false, speakReference: false)
              .map((c) => c.text),
          ['For God so loved the world.', 'For God sent not his Son.'],
        );
      },
    );

    test('a verse with no text leaves no empty clip, just its note', () async {
      final item = (await planner().plan([
        entry(1, verseText: '', noteText: 'A thought on this.'),
      ])).single;
      // Reference on: it says where the note belongs.
      expect(item.clipsFor(includeNotes: true).map((c) => c.text), [
        'John 3, verse 16.',
        'A thought on this.',
      ]);
      // Reference off: no "." or blank clip is left behind.
      final off = item.clipsFor(includeNotes: true, speakReference: false);
      expect(off.map((c) => c.text), ['A thought on this.']);
      expect(off.every((c) => c.text.trim().isNotEmpty), isTrue);
      // Reference off and notes off: nothing at all.
      expect(
        item.clipsFor(includeNotes: false, speakReference: false),
        isEmpty,
      );
    });

    test('the verse still receives its KJV patches without the reference', () {
      final json = File(
        'assets/audio/pronunciation/bible-map-v1.json',
      ).readAsStringSync();
      final lexicon = File(
        'assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0/lexicon-us-en.txt',
      ).readAsStringSync();
      final map = BiblePronunciationMap(json, lexicon);
      final verses =
          (jsonDecode(json) as Map<String, dynamic>)['verses']
              as Map<String, dynamic>;
      final conflict = RegExp(
        'live for ?ever|hast|sodom|gomorrah',
        caseSensitive: false,
      );
      final verse = verses.entries.firstWhere(
        (e) =>
            (e.value['patches'] as List<dynamic>).isNotEmpty &&
            !conflict.hasMatch(e.value['text'] as String),
      );
      final clip = TagSpeechClip(
        text: verse.value['text'] as String,
        kind: TagClipKind.verse,
        blockId: int.parse(verse.key),
        reference: 'John 3, verse 16',
      );
      String spoken(bool speakReference) => map.prepare(
        clip.resolved(speakReference: speakReference)!.text,
        blockId: clip.blockId,
        corrections: Map<String, String>.of(defaultNarrationPronunciations),
      );
      expect(spoken(true), contains('sbpron'));
      expect(spoken(false), contains('sbpron'));
      expect(spoken(false), isNot(startsWith('John')));
    });

    test('playback never synthesizes the reference or an empty clip', () async {
      final items = await planner().plan([
        entry(1, noteText: 'First note.'),
        entry(2, verse: 17, verseText: 'Second verse.'),
      ]);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
        speakReference: false,
      );
      controller.play();
      await h.settle();
      for (var i = 0; i < 10 && controller.isPlaying; i++) {
        h.player.finishCurrent();
        await h.settle();
      }
      expect(h.renderer.requestedTexts, [
        'For God so loved the world.',
        'First note.',
        'Second verse.',
      ]);
      expect(
        h.renderer.requestedTexts.any((t) => t.contains('verse 1')),
        isFalse,
      );
      expect(
        h.renderer.requestedTexts.every((t) => t.trim().isNotEmpty),
        isTrue,
      );
      controller.dispose();
      h.controller.dispose();
    });

    test('turning it off mid-playback re-plans the buffered clips', () async {
      final items = await planner().plan([
        entry(1),
        entry(2, verse: 17, verseText: 'Second verse.'),
        entry(3, verse: 18, verseText: 'Third verse.'),
      ]);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
      );
      controller.play();
      await h.settle();
      expect(h.player.playedTexts, [
        'John 3, verse 16. For God so loved the world.',
      ]);
      controller.setSpeakReference(false);
      await h.settle();
      // The clip already playing finishes untouched; the rest is re-rendered
      // without a reference, and the stale prefetched audio is discarded.
      h.player.finishCurrent();
      await h.settle();
      expect(h.player.playedTexts.last, 'Second verse.');
      h.player.finishCurrent();
      await h.settle();
      expect(h.player.playedTexts.last, 'Third verse.');
      expect(h.renderer.discarded, isNotEmpty);
      controller.dispose();
      h.controller.dispose();
    });
  });

  group('notes off', () {
    test('speaks the reference and verse but never the note', () async {
      final items = await planner().plan([
        entry(1, noteText: 'My private thought.'),
      ]);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
        includeNotes: false,
      );
      controller.play();
      await h.settle();
      for (var i = 0; i < 10 && controller.isPlaying; i++) {
        h.player.finishCurrent();
        await h.settle();
      }
      expect(h.renderer.requestedTexts, [
        'John 3, verse 16. For God so loved the world.',
      ]);
      controller.dispose();
      h.controller.dispose();
    });

    test('reference off and notes off together speak only the verse', () async {
      final items = await planner().plan([
        entry(1, noteText: 'My private thought.'),
      ]);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
        includeNotes: false,
        speakReference: false,
      );
      controller.play();
      await h.settle();
      expect(h.renderer.requestedTexts, ['For God so loved the world.']);
      controller.dispose();
      h.controller.dispose();
    });
  });

  group('empty tag', () {
    test('plans nothing, renders nothing and plays nothing', () async {
      final items = await planner().plan(const []);
      expect(items, isEmpty);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
      );
      expect(controller.canPlay, isFalse);
      controller.play();
      controller.next();
      controller.playFromEntry(0);
      controller.setLoop(true);
      controller.play();
      await h.settle();
      expect(h.renderer.requested, isEmpty);
      expect(h.player.played, isEmpty);
      expect(controller.status, TagPlaybackStatus.idle);
      controller.dispose();
      h.controller.dispose();
    });

    test('an entry with no text, no note and no title is silent', () async {
      final items = await planner().plan([
        entry(2, book: 0, chapter: 0, verse: 0, verseText: ''),
      ]);
      final h = Harness(items);
      final controller = TagPlaybackController(
        items: items,
        renderer: h.renderer,
        player: h.player,
        loop: true,
      );
      expect(controller.canPlay, isFalse);
      controller.play();
      await h.settle();
      expect(h.renderer.requested, isEmpty);
      expect(h.player.played, isEmpty);
      controller.dispose();
      h.controller.dispose();
    });

    test('a verse with no text or note is announced, or silent with the '
        'reference off', () async {
      final items = await planner().plan([entry(1, verseText: '')]);
      final on = Harness(items);
      expect(on.controller.canPlay, isTrue);
      on.controller.play();
      await on.settle();
      expect(on.renderer.requestedTexts, ['John 3, verse 16.']);
      on.controller.dispose();

      final off = Harness(items);
      off.controller.setSpeakReference(false);
      expect(off.controller.canPlay, isFalse);
      off.controller.dispose();
    });
  });

  group('settings panel', () {
    Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 500, height: 800, child: child)),
    );

    testWidgets('the gear opens reference and notes switches, loop stays out', (
      tester,
    ) async {
      final h = Harness([fakeItem(0, notes: 1)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(
        find.byKey(const Key('tag_playback_settings_panel')),
        findsNothing,
      );
      // Loop keeps its place in the transport; there is no second notes chip.
      expect(find.byKey(const Key('tag_playback_loop')), findsOneWidget);
      expect(find.byKey(const Key('tag_playback_notes')), findsNothing);

      await tester.tap(find.byKey(const Key('tag_playback_settings')));
      await tester.pump();
      expect(
        find.byKey(const Key('tag_playback_settings_panel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tag_playback_loop')), findsOneWidget);
      expect(find.text('Speak reference'), findsOneWidget);
      expect(find.text('Speak notes'), findsOneWidget);
      expect(h.controller.speakReference, isTrue);
      expect(h.controller.includeNotes, isTrue);

      await tester.tap(find.byKey(const Key('tag_playback_setting_reference')));
      await tester.tap(find.byKey(const Key('tag_playback_setting_notes')));
      await tester.pump();
      expect(h.controller.speakReference, isFalse);
      expect(h.controller.includeNotes, isFalse);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('an empty tag shows the empty state with the settings usable', (
      tester,
    ) async {
      final h = Harness(const []);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(find.byKey(const Key('tag_playback_empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await tester.pump();
      expect(h.renderer.requested, isEmpty);
      expect(h.player.played, isEmpty);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });
  });
}
