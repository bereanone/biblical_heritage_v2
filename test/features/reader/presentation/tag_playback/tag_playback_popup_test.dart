import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_models.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_panel.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_popup.dart';
import 'package:studybible2/features/reader/presentation/tag_playback/tag_playback_session.dart';

import 'tag_playback_fakes.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 500, height: 800, child: child)),
);

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

String textOf(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(Key(key))).data!;

Color? rowColor(WidgetTester tester, int index) {
  final box = tester.widget<Container>(
    find.byKey(Key('tag_playback_row_$index')),
  );
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  group('panel', () {
    testWidgets('shows which entry of how many, and the reference', (
      tester,
    ) async {
      final h = Harness([
        fakeItem(0, label: 'Genesis 1:1'),
        fakeItem(1, label: 'John 3:16', notes: 1),
        fakeItem(2, label: 'Psalm 23:1'),
      ]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(textOf(tester, 'tag_playback_position'), 'Entry 1 of 3');
      expect(textOf(tester, 'tag_playback_reference'), 'Genesis 1:1');
      expect(textOf(tester, 'tag_playback_status'), 'Ready');

      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);
      expect(textOf(tester, 'tag_playback_status'), 'Playing');

      h.player.finishCurrent();
      await settle(tester);
      expect(textOf(tester, 'tag_playback_position'), 'Entry 2 of 3');
      expect(textOf(tester, 'tag_playback_reference'), 'John 3:16');
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('highlights the current entry in the list', (tester) async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(rowColor(tester, 0), isNotNull);
      expect(rowColor(tester, 1), isNull);

      h.controller.play();
      await settle(tester);
      h.controller.next();
      await settle(tester);
      expect(rowColor(tester, 0), isNull);
      expect(rowColor(tester, 1), isNotNull);
      expect(rowColor(tester, 2), isNull);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('scrolls a long list to keep the current entry visible', (
      tester,
    ) async {
      final h = Harness([for (var i = 0; i < 60; i++) fakeItem(i)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      h.controller.playFromEntry(50);
      await settle(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tag_playback_row_50')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('transport buttons drive the controller', (tester) async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));

      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);
      expect(h.controller.isPlaying, isTrue);

      await tester.tap(find.byKey(const Key('tag_playback_next')));
      await settle(tester);
      expect(h.controller.currentIndex, 1);

      await tester.tap(find.byKey(const Key('tag_playback_previous')));
      await settle(tester);
      expect(h.controller.currentIndex, 0);

      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);
      expect(h.controller.status, TagPlaybackStatus.paused);
      expect(h.player.paused, isTrue);

      await tester.tap(find.byKey(const Key('tag_playback_stop')));
      await settle(tester);
      expect(h.controller.status, TagPlaybackStatus.idle);
      expect(textOf(tester, 'tag_playback_position'), 'Entry 1 of 3');
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('loop defaults off and notes default on; both toggle', (
      tester,
    ) async {
      final h = Harness([fakeItem(0, notes: 1)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(h.controller.loop, isFalse);
      expect(h.controller.includeNotes, isTrue);
      await tester.tap(find.byKey(const Key('tag_playback_loop')));
      await tester.tap(find.byKey(const Key('tag_playback_settings')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tag_playback_setting_notes')));
      await tester.pump();
      expect(h.controller.loop, isTrue);
      expect(h.controller.includeNotes, isFalse);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('tapping a row plays from that entry', (tester) async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      await tester.tap(find.byKey(const Key('tag_playback_row_2')));
      await settle(tester);
      expect(h.player.playedTexts, ['v2.0']);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('an empty tag says so and disables the controls', (
      tester,
    ) async {
      final h = Harness([]);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(find.byKey(const Key('tag_playback_empty')), findsOneWidget);
      final play = tester.widget<IconButton>(
        find.byKey(const Key('tag_playback_play_pause')),
      );
      expect(play.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('notes-off with only notes leaves nothing to read', (
      tester,
    ) async {
      final h = Harness([
        TagPlaybackItem(
          entryId: 0,
          label: 'Note',
          preview: 'x',
          noteClips: const [TagSpeechClip(text: 'x', kind: TagClipKind.note)],
        ),
      ], includeNotes: false);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      expect(find.byKey(const Key('tag_playback_nothing')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });

    testWidgets('a failed synthesis is reported, not silent', (tester) async {
      final h = Harness([fakeItem(0), fakeItem(1), fakeItem(2), fakeItem(3)]);
      h.renderer.failing.addAll(['v0.0', 'v1.0', 'v2.0']);
      await tester.pumpWidget(host(TagPlaybackPanel(controller: h.controller)));
      h.controller.play();
      await settle(tester);
      expect(textOf(tester, 'tag_playback_status'), contains('Speech stopped'));
      await tester.pumpWidget(const SizedBox());
      h.controller.dispose();
    });
  });

  group('dialog lifecycle', () {
    late Harness h;
    late bool sessionDisposed;

    Future<TagPlaybackSession> open() async {
      return TagPlaybackSession(
        tag: '#faith',
        controller: h.controller,
        onDispose: () async => sessionDisposed = true,
      );
    }

    Future<void> show(
      WidgetTester tester, {
      Future<TagPlaybackSession> Function()? opener,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Dialog(
                  child: SizedBox(
                    width: 500,
                    height: 700,
                    child: TagPlaybackDialog(
                      tag: '#faith',
                      open: opener ?? open,
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
    }

    setUp(() {
      h = Harness([fakeItem(0), fakeItem(1), fakeItem(2)]);
      sessionDisposed = false;
    });

    testWidgets('closing the popup stops playback and cancels synthesis', (
      tester,
    ) async {
      await show(tester);
      expect(find.text('Listen · #faith'), findsOneWidget);
      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);
      expect(h.controller.isPlaying, isTrue);

      await tester.tap(find.byKey(const Key('tag_playback_close')));
      await tester.pumpAndSettle();
      expect(find.byType(TagPlaybackDialog), findsNothing);
      expect(sessionDisposed, isTrue);
      expect(h.player.current, isNull, reason: 'speech stopped');
      expect(h.player.disposed, isTrue);
      final requests = h.renderer.requested.length;
      await settle(tester);
      expect(h.renderer.requested.length, requests);
      expect(h.renderer.live, isEmpty);
    });

    testWidgets('tapping outside dismisses and stops just the same', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(TagPlaybackDialog), findsNothing);
      expect(sessionDisposed, isTrue);
      expect(h.player.current, isNull);
    });

    testWidgets(
      'dismissing while the tag is still loading disposes it on arrival',
      (tester) async {
        final gate = Completer<TagPlaybackSession>();
        await show(tester, opener: () => gate.future);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(find.byType(TagPlaybackDialog), findsNothing);
        gate.complete(await open());
        await settle(tester);
        expect(sessionDisposed, isTrue);
        expect(h.player.played, isEmpty);
      },
    );

    testWidgets('a tag that cannot be loaded shows an error, not a spinner', (
      tester,
    ) async {
      await show(
        tester,
        opener: () async => throw StateError('db unavailable'),
      );
      expect(find.textContaining('Could not load'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('backgrounding pauses; window focus loss does not', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.byKey(const Key('tag_playback_play_pause')));
      await settle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await settle(tester);
      expect(h.controller.isPlaying, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await settle(tester);
      expect(h.controller.status, TagPlaybackStatus.paused);
      expect(h.player.paused, isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
      expect(
        h.controller.status,
        TagPlaybackStatus.paused,
        reason: 'returning to the app does not restart speech by itself',
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
    });
  });
}
