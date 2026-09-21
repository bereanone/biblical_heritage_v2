import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/library_speech_scroll_follower.dart';
import 'package:studybible2/features/library/presentation/library_speech_queue.dart';

void main() {
  group('librarySpeechFollowDelta', () {
    test('leaves a slice inside the comfort band alone', () {
      expect(
        librarySpeechFollowDelta(sliceTop: 100, viewportHeight: 1000),
        isNull,
      );
      expect(
        librarySpeechFollowDelta(sliceTop: 500, viewportHeight: 1000),
        isNull,
      );
    });

    test('scrolls a slice that drifted past mid-screen back to the anchor', () {
      // Slice top at 800 of 1000; anchor is 200, so scroll 600 forward.
      expect(
        librarySpeechFollowDelta(sliceTop: 800, viewportHeight: 1000),
        600,
      );
    });

    test('scrolls back for a slice above the viewport', () {
      expect(
        librarySpeechFollowDelta(sliceTop: -300, viewportHeight: 1000),
        -500,
      );
    });

    test('progress is clamped and tolerates unknown length', () {
      expect(librarySpeechProgress(0, null), 0);
      expect(librarySpeechProgress(50, 200), .25);
      expect(librarySpeechProgress(500, 200), 1);
    });
  });

  test('segmenter reports the whole paragraph length on every slice', () async {
    final text = List.filled(60, 'The beast rose up out of the sea.').join(' ');
    final segmenter = LibrarySpeechSegmenter(
      (cursor) async =>
          LibrarySpeechItem(cursor: '0', nextCursor: '1', text: text),
    );
    final first = (await segmenter.load('0'))!;
    final second = (await segmenter.load(first.nextCursor))!;
    expect(first.sourceLength, text.length);
    expect(second.sourceLength, text.length);
    expect(second.startOffset, greaterThan(0));
  });

  testWidgets(
    'followSpeechInBlock scrolls a tall paragraph only once the voice '
    'passes mid-screen',
    (tester) async {
      final controller = ScrollController();
      final paragraphKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: ListView(
                controller: controller,
                children: [
                  SizedBox(key: paragraphKey, height: 3000),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      );
      Future<bool> follow(double progress) async {
        final result = tester.runAsync(
          () => followSpeechInBlock(
            blockContext: paragraphKey.currentContext!,
            progress: progress,
          ),
        );
        await tester.pumpAndSettle();
        return (await result)!;
      }

      // Start of the paragraph is at the top, inside the band: no movement.
      expect(await follow(0), isFalse);
      expect(controller.offset, 0);
      // 10% in is 300px down, still inside the top half of a 600px viewport.
      expect(await follow(.1), isFalse);
      expect(controller.offset, 0);
      // 40% in is 1200px down, far past mid-screen: scrolled so it sits at 20%.
      expect(await follow(.4), isTrue);
      expect(controller.offset, closeTo(1200 - 600 * librarySpeechAnchor, 1));
    },
  );
}
