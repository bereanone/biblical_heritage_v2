import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/watch_playback_handoff.dart';
import 'package:studybible2/features/reader/presentation/bible_watch_remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Watch handoff waits for real pause acknowledgements and unregisters closed readers',
    () async {
      final first = Object(), second = Object();
      final gate = Completer<void>();
      final events = <String>[];
      WatchPlaybackHandoff.register(first, () async {
        events.add('pause requested');
        await gate.future;
        events.add('paused');
      });
      WatchPlaybackHandoff.register(second, () async {
        events.add('closed reader');
      });
      WatchPlaybackHandoff.unregister(second);
      var finished = false;
      final pending = WatchPlaybackHandoff.pauseReaders().then((_) {
        finished = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(finished, isFalse);
      expect(events, ['pause requested']);
      gate.complete();
      await pending;
      expect(events, ['pause requested', 'paused']);
      WatchPlaybackHandoff.unregister(first);
    },
  );
  test('remote mode switch confirms pause without waiting for shelf rebuild', () async {
    final owner = Object();
    final paused = Completer<void>();
    final catalog = Completer<void>();
    var refreshStarted = false;
    var acknowledged = false;
    WatchPlaybackHandoff.register(owner, () => paused.future);
    addTearDown(() => WatchPlaybackHandoff.unregister(owner));
    final handoff = WatchPlaybackHandoff.pauseForRemote(refresh: () {
      refreshStarted = true;
      return catalog.future;
    }).then((_) => acknowledged = true);
    await Future<void>.delayed(Duration.zero);
    expect(acknowledged, isFalse);
    expect(refreshStarted, isFalse);
    paused.complete();
    await handoff;
    expect(refreshStarted, isTrue);
    expect(acknowledged, isTrue);
    expect(catalog.isCompleted, isFalse);
    catalog.complete();
  });
  test(
    'identical frame-by-frame Bible states cause one Watch update; changes still publish',
    () async {
      const channel = MethodChannel('watch-update-test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final remote = BibleWatchRemote.forTesting(channel);
      await remote.attach((_) async {});
      Future<void> publish({int verse = 1}) => remote.publish(
        book: 45,
        chapter: 1,
        verse: verse,
        title: 'Romans 1:$verse',
        loop: 'off',
        lastLoop: 'chapter',
        playing: false,
        pending: false,
        loopTargetBook: 45,
        loopTargetChapter: 1,
        loopTargetVerse: 1,
      );
      await Future.wait(List.generate(100, (_) => publish()));
      expect(calls.where((c) => c.method == 'publishState').length, 1);
      await publish(verse: 2);
      expect(calls.where((c) => c.method == 'publishState').length, 2);
      await remote.detach();
    },
  );
}
