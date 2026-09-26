import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';

import 'tag_playback_fakes.dart';

List<TagPlaybackItem> entries(int count, {int notes = 0}) => [
  for (var i = 0; i < count; i++) fakeItem(i, notes: notes),
];

void main() {
  group('prefetch', () {
    test('synthesizes ahead of playback but only up to the cap', () async {
      final h = Harness(entries(10));
      h.controller.play();
      await h.settle();
      // Playing v0; v1 and v2 are buffered; v3 is not requested yet.
      expect(h.player.playedTexts, ['v0.0']);
      expect(h.renderer.requestedTexts, ['v0.0', 'v1.0', 'v2.0']);
      await h.finishClip();
      // The window slides by exactly one clip.
      expect(h.renderer.requestedTexts, ['v0.0', 'v1.0', 'v2.0', 'v3.0']);
      h.controller.dispose();
    });

    test('a smaller cap buffers less', () async {
      final h = Harness(entries(10), maxAhead: 1);
      h.controller.play();
      await h.settle();
      expect(h.renderer.requestedTexts, ['v0.0', 'v1.0']);
      h.controller.dispose();
    });

    test(
      'prefetch runs across entry boundaries into the next entry\'s note',
      () async {
        final h = Harness([fakeItem(0, notes: 1), fakeItem(1, notes: 1)]);
        h.controller.play();
        await h.settle();
        expect(h.renderer.requestedTexts, ['v0.0', 'n0.0', 'v1.0']);
        h.controller.dispose();
      },
    );

    test('files on disk never exceed the playing clip plus the cap', () async {
      final h = Harness(entries(30, notes: 1));
      h.controller.play();
      await h.settle();
      await h.runToEnd(limit: 200);
      expect(h.player.played.length, 60);
      expect(h.renderer.maxLive, lessThanOrEqualTo(3));
      expect(h.renderer.live, isEmpty);
      h.controller.dispose();
    });

    test('files stay bounded through many loops of a long tag', () async {
      final h = Harness(entries(12), loop: true);
      h.controller.play();
      await h.settle();
      for (var i = 0; i < 60; i++) {
        await h.finishClip();
      }
      expect(h.controller.isPlaying, isTrue);
      expect(h.renderer.maxLive, lessThanOrEqualTo(3));
      expect(h.controller.bufferedClipCount, lessThanOrEqualTo(3));
      h.controller.dispose();
    });

    test(
      'is gapless when the next clip is ready: it starts without waiting',
      () async {
        final h = Harness(entries(3));
        h.controller.play();
        await h.settle();
        final requestsBefore = h.renderer.requested.length;
        h.player.finishCurrent();
        // One microtask turn, no synthesis wait.
        await Future<void>.delayed(Duration.zero);
        expect(h.player.playedTexts, ['v0.0', 'v1.0']);
        expect(h.controller.status, TagPlaybackStatus.playing);
        expect(
          h.renderer.requested.length,
          greaterThanOrEqualTo(requestsBefore),
        );
        h.controller.dispose();
      },
    );

    test(
      'hands the player the next file to preload while one is playing',
      () async {
        final h = Harness(entries(3));
        h.controller.play();
        await h.settle();
        expect(h.player.preloaded.map(FakePlayer.textOf), ['v1.0']);
        await h.finishClip();
        expect(h.player.preloaded.map(FakePlayer.textOf), ['v1.0', 'v2.0']);
        h.controller.dispose();
      },
    );

    test(
      'shows loading, then resumes, when synthesis is slower than speech',
      () async {
        final h = Harness(entries(2), auto: false);
        h.controller.play();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.loading);
        h.renderer.complete(h.renderer.pendingPaths.first); // v0 only
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.playing);
        // v1 still pending when v0 ends.
        h.player.finishCurrent();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.loading);
        expect(h.player.playedTexts, ['v0.0']);
        h.renderer.completeAll();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.playing);
        expect(h.player.playedTexts, ['v0.0', 'v1.0']);
        h.controller.dispose();
      },
    );

    test(
      'paused playback prefetches nothing beyond the clip it resumes with',
      () async {
        final h = Harness(entries(10), auto: false);
        h.controller.play();
        await h.settle();
        h.renderer.completeAll();
        await h.settle();
        h.controller.pause();
        h.controller.next(); // now paused on entry 1
        await h.settle();
        final requested = h.renderer.requestedTexts;
        h.renderer.completeAll();
        await h.settle();
        // Only the clip being resumed with is rendered while paused.
        expect(
          h.renderer.requestedTexts.where((t) => !requested.contains(t)),
          isEmpty,
        );
        expect(h.renderer.requestedTexts.contains('v9.0'), isFalse);
        h.controller.dispose();
      },
    );
  });

  group('skip, previous and wraparound rebuild the buffer', () {
    test('previous throws away the forward buffer and re-renders', () async {
      final h = Harness(entries(6));
      h.controller.play();
      await h.settle();
      await h.finishClip();
      await h.finishClip(); // playing v2, buffered v3 v4
      final bufferedBefore = h.renderer.live.toList();
      h.controller.previous(); // back to v1
      await h.settle();
      expect(h.player.playedTexts.last, 'v1.0');
      for (final path in bufferedBefore) {
        expect(
          h.renderer.discarded,
          contains(path),
          reason: 'stale audio for ${FakePlayer.textOf(path)} was discarded',
        );
      }
      // Buffer is refilled from the new position.
      expect(h.renderer.requestedTexts.reversed.take(2).toList(), [
        'v3.0', 'v2.0', //
      ]);
      h.controller.dispose();
    });

    test(
      'next reuses a prefetched clip instead of synthesizing it twice',
      () async {
        final h = Harness(entries(8));
        h.controller.play();
        await h.settle(); // playing v0, buffered v1 v2
        h.controller.next();
        await h.settle();
        expect(h.player.playedTexts, ['v0.0', 'v1.0']);
        expect(
          h.renderer.requestedTexts.where((t) => t == 'v1.0').length,
          1,
          reason: 'v1 was already buffered',
        );
        expect(h.renderer.requestedTexts.where((t) => t == 'v2.0').length, 1);
        // The clip that was playing is released.
        expect(h.renderer.discarded.map(FakePlayer.textOf), contains('v0.0'));
        h.controller.dispose();
      },
    );

    test('a long jump discards the whole buffer and starts fresh', () async {
      final h = Harness(entries(10));
      h.controller.play();
      await h.settle();
      final old = h.renderer.live.toList();
      h.controller.playFromEntry(7);
      await h.settle();
      expect(h.player.playedTexts.last, 'v7.0');
      expect(h.renderer.discarded, containsAll(old));
      expect(h.renderer.requestedTexts, containsAll(['v7.0', 'v8.0', 'v9.0']));
      expect(h.renderer.live.map(FakePlayer.textOf).toSet(), {
        'v7.0', 'v8.0', 'v9.0', //
      });
      h.controller.dispose();
    });

    test(
      'wraparound is gapless: the first clip is prefetched before the last ends',
      () async {
        final h = Harness(entries(3), loop: true);
        h.controller.play();
        await h.settle();
        await h.finishClip(); // v1, buffered v2 and (wrapped) v0
        await h.finishClip(); // v2
        // The window behind v2 is the wrapped v0 and v1, requested while v2 plays.
        expect(h.renderer.requestedTexts.reversed.take(2).toList(), [
          'v1.0',
          'v0.0',
        ]);
        final requests = h.renderer.requested.length;
        h.player.finishCurrent();
        await Future<void>.delayed(Duration.zero);
        expect(h.player.playedTexts.last, 'v0.0');
        expect(h.renderer.requested.length, greaterThanOrEqualTo(requests));
        h.controller.dispose();
      },
    );

    test('turning loop off drops the audio buffered across the wrap', () async {
      final h = Harness(entries(3), loop: true);
      h.controller.play();
      await h.settle();
      await h.finishClip();
      await h.finishClip(); // playing v2 with wrapped v0/v1 buffered
      final wrapped = h.renderer.live.toList()
        ..removeWhere((p) => FakePlayer.textOf(p) == 'v2.0');
      expect(wrapped, isNotEmpty);
      h.controller.setLoop(false);
      await h.settle();
      expect(h.renderer.discarded, containsAll(wrapped));
      await h.finishClip();
      expect(h.controller.status, TagPlaybackStatus.finished);
      expect(h.player.playedTexts.last, 'v2.0');
      expect(h.renderer.live, isEmpty);
      h.controller.dispose();
    });

    test('turning loop on at the last entry buffers the wrap', () async {
      final h = Harness(entries(2));
      h.controller.play();
      await h.settle();
      await h.finishClip(); // playing v1, nothing to buffer
      expect(h.renderer.requestedTexts, ['v0.0', 'v1.0']);
      h.controller.setLoop(true);
      await h.settle();
      // The wrapped v0 (and the v1 after it) are buffered behind the last clip.
      expect(h.renderer.requestedTexts.sublist(2), ['v0.0', 'v1.0']);
      await h.finishClip();
      expect(h.player.playedTexts, ['v0.0', 'v1.0', 'v0.0']);
      h.controller.dispose();
    });

    test('changing the notes toggle re-plans the buffer', () async {
      final h = Harness(entries(4, notes: 1));
      h.controller.play();
      await h.settle(); // v0, buffered n0 v1
      final old = h.renderer.live.toList();
      h.controller.setIncludeNotes(false);
      await h.settle();
      expect(
        h.renderer.discarded.map(FakePlayer.textOf),
        containsAll(old.map(FakePlayer.textOf).where((t) => t != 'v0.0')),
      );
      expect(h.renderer.requestedTexts.reversed.take(2).toList(), [
        'v2.0', 'v1.0', //
      ]);
      h.controller.dispose();
    });
  });

  group('cancellation', () {
    test(
      'rapid skipping never queues more engine jobs than the gate allows',
      () async {
        final h = Harness(entries(40), auto: false);
        h.controller.play();
        await h.settle();
        for (var i = 0; i < 25; i++) {
          h.controller.next();
        }
        await h.settle();
        expect(h.renderer.maxInFlight, lessThanOrEqualTo(2));
        // Finish the engine's jobs in order until playback catches up.
        for (var i = 0; i < 60 && h.renderer.pendingPaths.isNotEmpty; i++) {
          h.renderer.complete(h.renderer.pendingPaths.first);
          await h.settle();
        }
        expect(h.controller.currentIndex, 25);
        expect(h.player.playedTexts.last, 'v25.0');
        expect(h.renderer.maxInFlight, lessThanOrEqualTo(2));
        // Everything stale was thrown away; only the window remains.
        expect(h.renderer.live.length, lessThanOrEqualTo(3));
        h.controller.dispose();
      },
    );

    test(
      'a render finishing after it was skipped is discarded on arrival',
      () async {
        final h = Harness(entries(6), auto: false);
        h.controller.play();
        await h.settle();
        final stale = h.renderer.pendingPaths.first; // v0 in flight
        h.controller.playFromEntry(4);
        await h.settle();
        expect(h.renderer.discarded, isNot(contains(stale)));
        h.renderer.complete(stale);
        await h.settle();
        expect(h.renderer.discarded, contains(stale));
        expect(h.renderer.live, isNot(contains(stale)));
        expect(h.player.playedTexts, isNot(contains('v0.0')));
        h.controller.dispose();
      },
    );

    test(
      'dismissing stops audio, discards files and ignores late renders',
      () async {
        final h = Harness(entries(6), auto: false);
        h.controller.play();
        await h.settle();
        h.renderer.complete(h.renderer.pendingPaths.first);
        await h.settle();
        expect(h.player.playedTexts, ['v0.0']);
        final inFlight = h.renderer.pendingPaths;
        expect(inFlight, isNotEmpty);
        h.controller.dispose();
        await h.settle();
        expect(h.player.stopCount, greaterThan(0));
        expect(h.player.disposed, isTrue);
        // The engine cannot abort; when it finishes, the output is thrown away.
        final requests = h.renderer.requested.length;
        h.renderer.completeAll();
        await h.settle();
        expect(h.renderer.live, isEmpty);
        expect(
          h.renderer.discarded.length,
          greaterThanOrEqualTo(inFlight.length),
        );
        expect(
          h.renderer.requested.length,
          requests,
          reason: 'no new synthesis is started after dismissal',
        );
      },
    );

    test(
      'dismissing while still preparing the first clip leaves nothing running',
      () async {
        final h = Harness(entries(4), auto: false);
        h.controller.play();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.loading);
        h.controller.dispose();
        final requests = h.renderer.requested.length;
        h.renderer.completeAll();
        await h.settle();
        expect(h.player.played, isEmpty, reason: 'no speech after dismissal');
        expect(h.renderer.live, isEmpty);
        expect(h.renderer.requested.length, requests);
      },
    );

    test('a late player completion after dismissal is ignored', () async {
      final h = Harness(entries(3));
      h.controller.play();
      await h.settle();
      h.controller.dispose();
      final played = h.player.played.length;
      // The stream is closed by dispose; a stray event must not restart audio.
      await h.settle();
      expect(h.player.played.length, played);
    });

    test('dispose is idempotent and silences notifications', () async {
      final h = Harness(entries(2));
      var notifications = 0;
      h.controller.addListener(() => notifications++);
      h.controller.play();
      await h.settle();
      h.controller.dispose();
      final after = notifications;
      h.controller.dispose();
      h.controller.pause();
      h.controller.next();
      await h.settle();
      expect(notifications, after);
    });
  });

  group('failures', () {
    test('a clip that fails to synthesize stops at its reference', () async {
      final h = Harness(entries(4));
      h.renderer.failing.add('v1.0');
      h.controller.play();
      await h.settle();
      await h.runToEnd();
      expect(h.player.playedTexts, ['v0.0']);
      expect(h.controller.status, TagPlaybackStatus.error);
      expect(h.controller.errorMessage, contains('Ref 1'));
      h.controller.dispose();
    });

    test('repeated failures stop playback with an error', () async {
      final h = Harness(entries(6));
      h.renderer.failing.addAll(['v0.0', 'v1.0', 'v2.0']);
      h.controller.play();
      await h.settle();
      expect(h.controller.status, TagPlaybackStatus.error);
      expect(h.controller.errorMessage, contains('Speech stopped'));
      expect(h.player.played, isEmpty);
      // Nothing is left running or on disk.
      await h.settle();
      expect(h.renderer.live, isEmpty);
      h.controller.dispose();
    });

    test(
      'a hung render stops at its reference and is discarded if it lands',
      () async {
        final h = Harness(
          entries(3),
          auto: false,
          renderTimeout: const Duration(milliseconds: 40),
        );
        h.controller.play();
        await h.settle();
        final hung = h.renderer.pendingPaths.first;
        // v1 and v2 render fine; v0 hangs.
        for (final path in h.renderer.pendingPaths.skip(1).toList()) {
          h.renderer.complete(path);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(h.player.playedTexts, isEmpty);
        expect(h.controller.status, TagPlaybackStatus.error);
        h.renderer.complete(hung);
        await h.settle();
        expect(h.renderer.discarded, contains(hung));
        h.controller.dispose();
      },
    );
  });
}
