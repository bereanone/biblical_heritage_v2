import 'package:studybible2/core/audio/narration_media_session.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_media_binding.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';

import '../../../../core/audio/fake_narration_media_platform.dart';
import 'tag_playback_fakes.dart';

List<TagPlaybackItem> entries(int count) => [
  for (var i = 0; i < count; i++) fakeItem(i),
];

void main() {
  late FakeNarrationMediaPlatform platform;
  late Harness h;
  late TagPlaybackMediaBinding binding;

  setUp(() {
    platform = FakeNarrationMediaPlatform();
  });

  void open(Harness harness) {
    h = harness;
    binding = TagPlaybackMediaBinding(
      controller: h.controller,
      tag: '#grace',
      session: _session,
    );
  }

  tearDown(() {
    binding.dispose();
    h.controller.dispose();
  });

  group('now playing', () {
    setUp(() {
      _session = fakeSession(platform);
      open(Harness(entries(4)));
    });

    test('an idle popup leaves the lock screen alone', () {
      expect(platform.begins, 0);
      expect(platform.nowPlaying, isEmpty);
    });

    test('shows the current reference while playing', () async {
      h.controller.play();
      await h.settle();
      expect(platform.begins, 1);
      expect(platform.lastNowPlaying, containsPair('title', 'Ref 0'));
      expect(platform.lastNowPlaying, containsPair('playing', true));
      expect(platform.lastNowPlaying, containsPair('index', 1));
      expect(platform.lastNowPlaying, containsPair('count', 4));
      expect(
        platform.lastNowPlaying,
        containsPair('subtitle', 'Listen · #grace'),
      );
    });

    test('follows the playlist from clip to clip', () async {
      h.controller.play();
      await h.settle();
      await h.finishClip();
      expect(platform.lastNowPlaying, containsPair('title', 'Ref 1'));
    });

    test('shows paused, and stays available to resume', () async {
      h.controller.play();
      await h.settle();
      h.controller.pause();
      expect(platform.lastNowPlaying, containsPair('playing', false));
      expect(platform.ends, 0);
      h.controller.play();
      expect(platform.lastNowPlaying, containsPair('playing', true));
    });

    test('is cleared when the pass ends or is stopped', () async {
      h.controller.play();
      await h.settle();
      h.controller.stop();
      expect(platform.ends, 1);
    });
  });

  group('lock screen and Control Center buttons', () {
    setUp(() async {
      _session = fakeSession(platform);
      open(Harness(entries(4)));
      h.controller.play();
      await h.settle();
    });

    test('next and previous move through entries', () async {
      _session.debugDeliver('next');
      await h.settle();
      expect(h.controller.currentIndex, 1);
      expect(platform.lastNowPlaying, containsPair('title', 'Ref 1'));
      _session.debugDeliver('previous');
      await h.settle();
      expect(h.controller.currentIndex, 0);
    });

    test('pause then play', () async {
      _session.debugDeliver('pause');
      expect(h.controller.status, TagPlaybackStatus.paused);
      expect(h.player.paused, isTrue);
      _session.debugDeliver('play');
      expect(h.controller.isPlaying, isTrue);
    });

    test('toggle', () {
      _session.debugDeliver('toggle');
      expect(h.controller.status, TagPlaybackStatus.paused);
      _session.debugDeliver('toggle');
      expect(h.controller.isPlaying, isTrue);
    });
  });

  group('interruptions', () {
    setUp(() async {
      _session = fakeSession(platform);
      open(Harness(entries(4)));
      h.controller.play();
      await h.settle();
    });

    test('a phone call pauses, and playback resumes afterwards', () {
      _session.debugDeliver('interruptionBegan');
      expect(h.controller.status, TagPlaybackStatus.paused);
      _session.debugDeliver('interruptionEnded', {'shouldResume': true});
      expect(h.controller.isPlaying, isTrue);
    });

    test('stays paused when the system does not ask to resume', () {
      _session.debugDeliver('interruptionBegan');
      _session.debugDeliver('interruptionEnded', {'shouldResume': false});
      expect(h.controller.status, TagPlaybackStatus.paused);
    });
  });

  group('backgrounding', () {
    setUp(() {
      _session = fakeSession(platform);
    });

    test('keeps playing and buffers deeper, then returns to the cap', () async {
      open(Harness(entries(20)));
      h.controller.play();
      await h.settle();
      expect(h.renderer.requestedTexts, ['v0.0', 'v1.0', 'v2.0']);

      _session.didChangeAppLifecycleState(AppLifecycleState.paused);
      await h.settle();
      expect(h.controller.isPlaying, isTrue);
      expect(h.renderer.requestedTexts, [
        'v0.0', 'v1.0', 'v2.0', 'v3.0', 'v4.0', 'v5.0', //
      ]);

      _session.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await h.finishClip();
      // Already 4 ahead: nothing new is rendered until the window drains.
      expect(h.renderer.requestedTexts, hasLength(6));
    });

    test('a looping long tag stays bounded in the background', () async {
      open(Harness(entries(12), loop: true));
      _session.didChangeAppLifecycleState(AppLifecycleState.paused);
      h.controller.play();
      await h.settle();
      for (var i = 0; i < 60; i++) {
        await h.finishClip();
      }
      expect(h.controller.isPlaying, isTrue);
      expect(h.renderer.maxLive, lessThanOrEqualTo(6));
      expect(h.controller.bufferedClipCount, lessThanOrEqualTo(6));
    });

    test(
      'asks for background time only while a clip is still rendering',
      () async {
        open(Harness(entries(3), auto: false));
        h.controller.play();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.loading);
        expect(platform.isBuffering, isTrue);
        h.renderer.completeAll();
        await h.settle();
        expect(h.controller.status, TagPlaybackStatus.playing);
        expect(platform.isBuffering, isFalse);
      },
    );
  });
}

late NarrationMediaSession _session;
