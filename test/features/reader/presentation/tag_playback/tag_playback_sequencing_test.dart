import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';

import 'tag_playback_fakes.dart';

void main() {
  group('ordering and notes', () {
    test(
      'speaks each entry verse first, then its note, in list order',
      () async {
        final h = Harness([
          fakeItem(0, notes: 1),
          fakeItem(1, notes: 1),
          fakeItem(2, notes: 1),
        ]);
        h.controller.play();
        await h.settle();
        await h.runToEnd();
        expect(h.player.playedTexts, [
          'v0.0', 'n0.0', 'v1.0', 'n1.0', 'v2.0', 'n2.0', //
        ]);
        expect(h.controller.status, TagPlaybackStatus.finished);
        h.controller.dispose();
      },
    );

    test('verses-only mode leaves notes out', () async {
      final h = Harness([
        fakeItem(0, notes: 2),
        fakeItem(1, notes: 1),
      ], includeNotes: false);
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, ['v0.0', 'v1.0']);
      h.controller.dispose();
    });

    test('notes default to on when the caller does not say', () {
      final h = Harness([fakeItem(0, notes: 1)]);
      expect(h.controller.includeNotes, isTrue);
      h.controller.dispose();
    });

    test('an entry without a note is skipped gracefully', () async {
      final h = Harness([
        fakeItem(0, notes: 1),
        fakeItem(1), // no note
        fakeItem(2, notes: 1),
      ]);
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, [
        'v0.0', 'n0.0', 'v1.0', 'v2.0', 'n2.0', //
      ]);
      h.controller.dispose();
    });

    test(
      'a note-only entry is spoken with notes and skipped without',
      () async {
        TagPlaybackItem noteOnly(int i) => TagPlaybackItem(
          entryId: i,
          label: 'Note',
          preview: '',
          noteClips: [TagSpeechClip(text: 'only$i', kind: TagClipKind.note)],
        );
        final items = [fakeItem(0), noteOnly(1), fakeItem(2)];

        final withNotes = Harness(items);
        withNotes.controller.play();
        await withNotes.settle();
        await withNotes.runToEnd();
        expect(withNotes.player.playedTexts, ['v0.0', 'only1', 'v2.0']);
        withNotes.controller.dispose();

        final versesOnly = Harness(items, includeNotes: false);
        versesOnly.controller.play();
        await versesOnly.settle();
        await versesOnly.runToEnd();
        expect(versesOnly.player.playedTexts, ['v0.0', 'v2.0']);
        // The skipped entry is never even synthesized.
        expect(versesOnly.renderer.requestedTexts, isNot(contains('only1')));
        versesOnly.controller.dispose();
      },
    );

    test('an entry of several clips plays them contiguously', () async {
      final h = Harness([fakeItem(0, verses: 2, notes: 2), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, [
        'v0.0', 'v0.1', 'n0.0', 'n0.1', 'v1.0', //
      ]);
      h.controller.dispose();
    });

    test('position tracks the entry being spoken', () async {
      final h = Harness([
        fakeItem(0, notes: 1, label: 'Gen 1:1'),
        fakeItem(1, label: 'John 3:16'),
      ]);
      expect(h.controller.entryCount, 2);
      expect(h.controller.currentIndex, 0);
      h.controller.play();
      await h.settle();
      expect(h.controller.currentItem!.label, 'Gen 1:1');
      await h.finishClip(); // verse -> note, still entry 0
      expect(h.controller.currentIndex, 0);
      await h.finishClip(); // note -> entry 1
      expect(h.controller.currentIndex, 1);
      expect(h.controller.currentItem!.label, 'John 3:16');
      h.controller.dispose();
    });
  });

  group('looping', () {
    test(
      'loop off: one pass, then stops and synthesizes nothing more',
      () async {
        final h = Harness([fakeItem(0), fakeItem(1)]);
        h.controller.play();
        await h.settle();
        await h.runToEnd();
        expect(h.controller.status, TagPlaybackStatus.finished);
        final renders = h.renderer.requested.length;
        await h.settle();
        expect(h.renderer.requested.length, renders);
        expect(h.player.playedTexts, ['v0.0', 'v1.0']);
        expect(
          h.renderer.live,
          isEmpty,
          reason: 'every audio file is cleaned up',
        );
        h.controller.dispose();
      },
    );

    test('loop on: restarts from the top and keeps going', () async {
      final h = Harness([fakeItem(0), fakeItem(1)], loop: true);
      h.controller.play();
      await h.settle();
      for (var i = 0; i < 5; i++) {
        await h.finishClip();
      }
      expect(h.player.playedTexts.take(6), [
        'v0.0', 'v1.0', 'v0.0', 'v1.0', 'v0.0', 'v1.0', //
      ]);
      expect(h.controller.isPlaying, isTrue);
      h.controller.dispose();
    });

    test('loop wraps entry positions back to the first', () async {
      final h = Harness([fakeItem(0), fakeItem(1)], loop: true);
      h.controller.play();
      await h.settle();
      await h.finishClip();
      expect(h.controller.currentIndex, 1);
      await h.finishClip();
      expect(h.controller.currentIndex, 0);
      h.controller.dispose();
    });

    test('play after a finished pass starts over from the top', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      h.controller.play();
      await h.settle();
      expect(h.controller.currentIndex, 0);
      expect(h.player.playedTexts.last, 'v0.0');
      h.controller.dispose();
    });
  });

  group('empty and single-entry tags', () {
    test('an empty tag cannot play and never touches the engine', () async {
      final h = Harness([]);
      expect(h.controller.canPlay, isFalse);
      h.controller.play();
      h.controller.next();
      h.controller.previous();
      h.controller.playFromEntry(0);
      h.controller.stop();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.idle);
      expect(h.renderer.requested, isEmpty);
      expect(h.player.played, isEmpty);
      h.controller.dispose();
    });

    test(
      'a tag where nothing is speakable behaves like an empty one',
      () async {
        final h = Harness([
          TagPlaybackItem(entryId: 0, label: 'Image', preview: ''),
        ]);
        h.controller.play();
        await h.settle();
        expect(h.controller.canPlay, isFalse);
        expect(h.renderer.requested, isEmpty);
        expect(h.controller.status, TagPlaybackStatus.idle);
        h.controller.dispose();
      },
    );

    test('single entry, loop off: plays once and finishes', () async {
      final h = Harness([fakeItem(0, notes: 1)]);
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, ['v0.0', 'n0.0']);
      expect(h.controller.status, TagPlaybackStatus.finished);
      h.controller.dispose();
    });

    test('single entry, loop on: repeats indefinitely', () async {
      final h = Harness([fakeItem(0)], loop: true);
      h.controller.play();
      await h.settle();
      for (var i = 0; i < 4; i++) {
        await h.finishClip();
      }
      expect(h.player.playedTexts.length, 5);
      expect(h.controller.isPlaying, isTrue);
      h.controller.dispose();
    });

    test('single entry: next ends the pass, previous restarts it', () async {
      final h = Harness([fakeItem(0)]);
      h.controller.play();
      await h.settle();
      h.controller.previous();
      await h.settle();
      expect(h.player.playedTexts, ['v0.0', 'v0.0']);
      expect(h.controller.currentIndex, 0);
      expect(h.controller.isPlaying, isTrue);
      h.controller.next();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.finished);
      h.controller.dispose();
    });
  });

  group('skipping', () {
    test('next and previous move one entry at a time', () async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      h.controller.play();
      await h.settle();
      h.controller.next();
      await h.settle();
      expect(h.controller.currentIndex, 1);
      expect(h.player.playedTexts.last, 'v1.0');
      h.controller.next();
      await h.settle();
      expect(h.controller.currentIndex, 2);
      h.controller.previous();
      await h.settle();
      expect(h.controller.currentIndex, 1);
      expect(h.player.playedTexts.last, 'v1.0');
      h.controller.dispose();
    });

    test('next skips over the rest of a multi-clip entry', () async {
      final h = Harness([fakeItem(0, notes: 3), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.next();
      await h.settle();
      expect(h.player.playedTexts, ['v0.0', 'v1.0']);
      h.controller.dispose();
    });

    test('next on the last entry with loop off ends the pass', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.next();
      await h.settle();
      h.controller.next();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.finished);
      expect(h.controller.currentIndex, 1);
      expect(h.player.current, isNull);
      h.controller.dispose();
    });

    test('next on the last entry with loop on wraps to the first', () async {
      final h = Harness([fakeItem(0), fakeItem(1)], loop: true);
      h.controller.play();
      await h.settle();
      h.controller.next();
      await h.settle();
      h.controller.next();
      await h.settle();
      expect(h.controller.currentIndex, 0);
      expect(h.player.playedTexts.last, 'v0.0');
      expect(h.controller.isPlaying, isTrue);
      h.controller.dispose();
    });

    test('previous on the first entry with loop off restarts it', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.previous();
      await h.settle();
      expect(h.controller.currentIndex, 0);
      expect(h.player.playedTexts, ['v0.0', 'v0.0']);
      h.controller.dispose();
    });

    test(
      'previous on the first entry with loop on wraps to the last',
      () async {
        final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)], loop: true);
        h.controller.play();
        await h.settle();
        h.controller.previous();
        await h.settle();
        expect(h.controller.currentIndex, 2);
        expect(h.player.playedTexts.last, 'v2.0');
        h.controller.dispose();
      },
    );

    test('skips pass over entries that have nothing to say', () async {
      final silent = TagPlaybackItem(entryId: 9, label: 'Image', preview: '');
      final h = Harness([fakeItem(0), silent, fakeItem(2)]);
      h.controller.play();
      await h.settle();
      h.controller.next();
      await h.settle();
      expect(h.controller.currentIndex, 2);
      h.controller.previous();
      await h.settle();
      expect(h.controller.currentIndex, 0);
      h.controller.dispose();
    });

    test('skipping while paused moves without starting audio', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.pause();
      h.controller.next();
      await h.settle();
      expect(h.controller.currentIndex, 1);
      expect(h.controller.status, TagPlaybackStatus.paused);
      expect(h.player.playedTexts, ['v0.0']);
      h.controller.play();
      await h.settle();
      expect(h.player.playedTexts, ['v0.0', 'v1.0']);
      h.controller.dispose();
    });

    test('navigating before playing sets where playback begins', () async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      h.controller.next();
      h.controller.next();
      expect(h.controller.status, TagPlaybackStatus.idle);
      expect(h.renderer.requested, isEmpty);
      h.controller.play();
      await h.settle();
      expect(h.player.playedTexts, ['v2.0']);
      h.controller.dispose();
    });

    test('tapping an entry plays from there', () async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      h.controller.playFromEntry(2);
      await h.settle();
      expect(h.player.playedTexts, ['v2.0']);
      expect(h.controller.currentIndex, 2);
      h.controller.dispose();
    });
  });

  group('transport', () {
    test(
      'pause holds the audio and play resumes without re-synthesis',
      () async {
        final h = Harness([fakeItem(0), fakeItem(1)]);
        h.controller.play();
        await h.settle();
        final renders = h.renderer.requested.length;
        h.controller.pause();
        await h.settle();
        expect(h.player.paused, isTrue);
        expect(h.controller.status, TagPlaybackStatus.paused);
        h.controller.play();
        await h.settle();
        expect(h.player.paused, isFalse);
        expect(h.player.resumeCount, 1);
        expect(h.renderer.requested.length, renders);
        expect(h.player.playedTexts, ['v0.0']);
        h.controller.dispose();
      },
    );

    test('a clip that ends while paused does not start the next one', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.pause();
      await h.finishClip();
      expect(h.player.playedTexts, ['v0.0']);
      expect(h.controller.currentIndex, 1);
      h.controller.play();
      await h.settle();
      expect(h.player.playedTexts, ['v0.0', 'v1.0']);
      h.controller.dispose();
    });

    test('pause requested before the audio starts is honoured', () async {
      final h = Harness([fakeItem(0)], auto: false);
      h.controller.play();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.loading);
      h.controller.pause();
      h.renderer.completeAll();
      await h.settle();
      expect(h.player.played, isEmpty);
      expect(h.controller.status, TagPlaybackStatus.paused);
      h.controller.play();
      await h.settle();
      expect(h.player.playedTexts, ['v0.0']);
      h.controller.dispose();
    });

    test('stop returns to the first entry and clears every buffer', () async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      h.controller.next();
      h.controller.play();
      await h.settle();
      h.controller.stop();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.idle);
      expect(h.controller.currentIndex, 0);
      expect(h.renderer.live, isEmpty);
      expect(h.player.current, isNull);
      expect(h.controller.bufferedClipCount, 0);
      h.controller.dispose();
    });

    test(
      'turning notes off mid-entry drops the note from what follows',
      () async {
        final h = Harness([fakeItem(0, notes: 1), fakeItem(1, notes: 1)]);
        h.controller.play();
        await h.settle(); // playing v0.0, note n0.0 already buffered
        h.controller.setIncludeNotes(false);
        await h.settle();
        await h.finishClip();
        await h.finishClip();
        expect(h.player.playedTexts, ['v0.0', 'v1.0']);
        expect(h.renderer.live, isEmpty);
        h.controller.dispose();
      },
    );

    test('turning notes on mid-entry adds the note before moving on', () async {
      final h = Harness([
        fakeItem(0, notes: 1),
        fakeItem(1, notes: 1),
      ], includeNotes: false);
      h.controller.play();
      await h.settle();
      h.controller.setIncludeNotes(true);
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, [
        'v0.0', 'n0.0', 'v1.0', 'n1.0', //
      ]);
      h.controller.dispose();
    });

    test('loop can be toggled while playing', () async {
      final h = Harness([fakeItem(0)]);
      h.controller.play();
      await h.settle();
      h.controller.setLoop(true);
      await h.finishClip();
      expect(h.controller.isPlaying, isTrue);
      expect(h.player.playedTexts.length, 2);
      h.controller.setLoop(false);
      await h.settle();
      await h.finishClip();
      expect(h.controller.status, TagPlaybackStatus.finished);
      h.controller.dispose();
    });

    test('pauseForBackground pauses', () async {
      final h = Harness([fakeItem(0), fakeItem(1)]);
      h.controller.play();
      await h.settle();
      h.controller.pauseForBackground();
      await h.settle();
      expect(h.player.paused, isTrue);
      expect(h.controller.status, TagPlaybackStatus.paused);
      h.controller.dispose();
    });
  });
}
