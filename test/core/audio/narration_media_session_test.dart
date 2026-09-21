import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/narration_media_session.dart';

import 'fake_narration_media_platform.dart';

class _Player {
  bool playing = true;
  final List<String> calls = [];

  NarrationTransport get transport => NarrationTransport(
    isPlaying: () => playing,
    play: () {
      calls.add('play');
      playing = true;
    },
    pause: () {
      calls.add('pause');
      playing = false;
    },
    next: () => calls.add('next'),
    previous: () => calls.add('previous'),
  );
}

void main() {
  late FakeNarrationMediaPlatform platform;
  late NarrationMediaSession session;

  setUp(() {
    platform = FakeNarrationMediaPlatform();
    session = fakeSession(platform);
  });

  group('lease lifecycle', () {
    test(
      'the OS session begins with the first lease and ends with the last',
      () {
        final a = session.start(_Player().transport);
        final b = session.start(_Player().transport);
        expect(platform.begins, 1);
        a.dispose();
        expect(platform.ends, 0);
        b.dispose();
        expect(platform.ends, 1);
      },
    );

    test('identical now-playing info is not re-sent', () {
      final lease = session.start(_Player().transport);
      const info = NarrationNowPlaying(title: 'John 3:16', playing: true);
      lease
        ..update(info)
        ..update(info);
      expect(platform.nowPlaying, hasLength(1));
      lease.update(
        const NarrationNowPlaying(title: 'John 3:17', playing: true),
      );
      expect(platform.lastNowPlaying?['title'], 'John 3:17');
      lease.dispose();
    });

    test('the newest lease owns the controls; the previous one gets them '
        'back, with its info, when it is disposed', () {
      final first = _Player();
      final second = _Player();
      final a = session.start(first.transport)
        ..update(const NarrationNowPlaying(title: 'A', playing: true));
      final b = session.start(second.transport)
        ..update(const NarrationNowPlaying(title: 'B', playing: true));

      session.debugDeliver('next');
      expect(second.calls, ['next']);
      expect(first.calls, isEmpty);

      b.dispose();
      expect(platform.lastNowPlaying?['title'], 'A');
      session.debugDeliver('next');
      expect(first.calls, ['next']);
      a.dispose();
    });

    test(
      'a lease that is not the owner does not overwrite the lock screen',
      () {
        final a = session.start(_Player().transport);
        final b = session.start(_Player().transport)
          ..update(const NarrationNowPlaying(title: 'B', playing: true));
        a.update(const NarrationNowPlaying(title: 'A', playing: true));
        expect(platform.lastNowPlaying?['title'], 'B');
        b.dispose();
        a.dispose();
      },
    );
  });

  group('lock screen buttons', () {
    test('play and pause only act when they would change something', () {
      final player = _Player()..playing = false;
      final lease = session.start(player.transport);
      session
        ..debugDeliver('pause')
        ..debugDeliver('play')
        ..debugDeliver('play');
      expect(player.calls, ['play']);
      session.debugDeliver('pause');
      expect(player.calls, ['play', 'pause']);
      lease.dispose();
    });

    test('toggle flips, next and previous pass straight through', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session
        ..debugDeliver('toggle')
        ..debugDeliver('toggle')
        ..debugDeliver('next')
        ..debugDeliver('previous');
      expect(player.calls, ['pause', 'play', 'next', 'previous']);
      lease.dispose();
    });

    test('events with no lease are ignored', () {
      expect(() => session.debugDeliver('play'), returnsNormally);
    });
  });

  group('interruptions', () {
    test('a call pauses playback and resumes it when the system says to', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session.debugDeliver('interruptionBegan');
      expect(player.playing, isFalse);
      session.debugDeliver('interruptionEnded', {'shouldResume': true});
      expect(player.calls, ['pause', 'play']);
      lease.dispose();
    });

    test('does not resume when the system says not to', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session
        ..debugDeliver('interruptionBegan')
        ..debugDeliver('interruptionEnded', {'shouldResume': false});
      expect(player.calls, ['pause']);
      lease.dispose();
    });

    test('does not start speech that the user had already paused', () {
      final player = _Player()..playing = false;
      final lease = session.start(player.transport);
      session
        ..debugDeliver('interruptionBegan')
        ..debugDeliver('interruptionEnded', {'shouldResume': true});
      expect(player.calls, isEmpty);
      lease.dispose();
    });

    test('a manual pause during the interruption cancels the auto-resume', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session
        ..debugDeliver('interruptionBegan')
        ..debugDeliver('pause')
        ..debugDeliver('interruptionEnded', {'shouldResume': true});
      expect(player.playing, isFalse);
      lease.dispose();
    });

    test('unplugging headphones pauses and never auto-resumes', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session
        ..debugDeliver('routeLost')
        ..debugDeliver('interruptionEnded', {'shouldResume': true});
      expect(player.calls, ['pause']);
      lease.dispose();
    });

    test('native diagnostics are log-only and never touch the transport', () {
      final player = _Player();
      final lease = session.start(player.transport);
      session
        ..debugDeliver('diagnostic', 'interruption began reason=none')
        ..debugDeliver('diagnostic', 'cpu 91% last 15s');
      expect(player.calls, isEmpty);
      expect(player.playing, isTrue);
      lease.dispose();
    });
  });

  group('background time', () {
    test('is held while synthesis is pending and released once', () {
      final release = session.holdBackgroundTime();
      expect(platform.isBuffering, isTrue);
      release();
      release();
      expect(platform.isBuffering, isFalse);
      expect(platform.buffering, [true, false]);
    });

    test('overlapping holds keep it until the last is released', () {
      final one = session.holdBackgroundTime();
      final two = session.holdBackgroundTime();
      one();
      expect(platform.isBuffering, isTrue);
      two();
      expect(platform.isBuffering, isFalse);
    });

    test('a lease that is buffering when it is disposed lets go', () {
      final lease = session.start(_Player().transport)..setBuffering(true);
      expect(platform.isBuffering, isTrue);
      lease.dispose();
      expect(platform.isBuffering, isFalse);
    });
  });

  test('backgrounded follows the lifecycle; inactive is still on screen', () {
    expect(session.backgrounded.value, isFalse);
    session.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(session.backgrounded.value, isFalse);
    session.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(session.backgrounded.value, isTrue);
    session.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(session.backgrounded.value, isTrue);
    session.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(session.backgrounded.value, isFalse);
  });
}
