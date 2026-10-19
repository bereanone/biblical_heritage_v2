import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/recorded_library_audio_controls.dart';
import 'package:studybible2/features/library/presentation/library_speech_scroll_follower.dart';

void main() {
  test(
    'chapter heading is shown at opening but not on a mid-chapter resume',
    () {
      expect(recordedChapterOpening(0, Duration.zero), isTrue);
      expect(recordedChapterOpening(0, const Duration(seconds: 2)), isTrue);
      expect(recordedChapterOpening(0, const Duration(seconds: 3)), isFalse);
      expect(recordedChapterOpening(0, const Duration(minutes: 1)), isFalse);
      expect(recordedChapterOpening(1, Duration.zero), isFalse);
    },
  );
  test(
    'paragraph-only cues advance within a long paragraph and reset on seek',
    () {
      int offset(int seconds) => recordedParagraphFollowOffset(
        position: Duration(seconds: seconds),
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 110),
        textLength: 1001,
      );
      expect(offset(10), 0);
      expect(offset(35), 250);
      expect(offset(60), 500);
      expect(offset(10), 0);
      expect(offset(120), 1000);
      expect(offset(0), 0);
    },
  );
  test('final paragraph uses track end and tolerates unavailable duration', () {
    expect(
      recordedParagraphFollowOffset(
        position: const Duration(seconds: 90),
        start: const Duration(seconds: 60),
        end: const Duration(seconds: 120),
        textLength: 601,
      ),
      300,
    );
    expect(
      recordedParagraphFollowOffset(
        position: const Duration(seconds: 90),
        start: const Duration(seconds: 60),
        end: Duration.zero,
        textLength: 601,
      ),
      0,
    );
  });
  testWidgets(
    'word press interrupts narration animation and can extend a range',
    (tester) async {
      final controller = ScrollController();
      var selected = false;
      var dragged = false;
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Listener(
              onPointerDown: (_) => controller.jumpTo(controller.offset),
              child: ListView(
                controller: controller,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => tapped = true,
                    onLongPressStart: (_) => selected = true,
                    onLongPressMoveUpdate: (_) => dragged = true,
                    child: const SizedBox(
                      height: 600,
                      child: Text('And it is added that Daniel continued'),
                    ),
                  ),
                  const SizedBox(height: 3000),
                ],
              ),
            ),
          ),
        ),
      );
      final animation = animateSpeechFollow(
        controller.position,
        300,
        duration: const Duration(seconds: 2),
      );
      await tester.pump(const Duration(milliseconds: 100));
      final gesture = await tester.startGesture(const Offset(40, 120));
      await tester.pump(const Duration(milliseconds: 600));
      expect(selected, isTrue);
      final stoppedAt = controller.offset;
      await gesture.moveBy(const Offset(120, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(dragged, isTrue);
      expect(controller.offset, stoppedAt);
      await gesture.up();
      await tester.pumpAndSettle();
      await animation;
      await tester.tapAt(const Offset(40, 120));
      expect(tapped, isTrue);
    },
  );

  testWidgets(
    'phone-sized viewport keeps beginning and later points of a tall paragraph visible',
    (tester) async {
      tester.view.physicalSize = const Size(360, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ScrollController();
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              padding: EdgeInsets.zero,
              controller: controller,
              children: [
                const SizedBox(height: 500),
                SizedBox(key: key, height: 3000),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      );
      Future<void> follow(double progress) async {
        final future = followSpeechInBlock(
          blockContext: key.currentContext!,
          progress: progress,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await future;
      }

      await follow(0);
      final top = tester.getTopLeft(find.byKey(key)).dy;
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThan(420 * .5));
      await follow(.4);
      final spokenPoint = tester.getTopLeft(find.byKey(key)).dy + 3000 * .4;
      expect(spokenPoint, closeTo(420 * .35, 2));
      final previous = controller.offset;
      await follow(.41);
      expect(controller.offset - previous, closeTo(30, 2));
    },
  );
}
