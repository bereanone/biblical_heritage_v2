import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_narration_button.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

class _Target implements ReaderAutoScrollTarget {
  @override
  bool get isAttached => true;
  @override
  bool scrollBy(double delta) => true;
}

void main() {
  MacReaderAutoScrollController controller({bool audio = false}) =>
      MacReaderAutoScrollController(
        scrollTarget: _Target(),
        driveFrames: false,
        narrationControlsPacing: true,
        preferences: MacAutoscrollPreferences(audioEnabled: audio),
      );

  Future<void> show(
    WidgetTester tester,
    MacReaderAutoScrollController c, {
    bool busy = false,
    VoidCallback? changed,
    VoidCallback? longPress,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReaderNarrationButton(
          controller: c,
          playLabel: 'Play Bible',
          busy: busy,
          onChanged: changed,
          onLongPress: longPress,
        ),
      ),
    ),
  );

  testWidgets('silent autoscroll never shows Pause or enables voice playback', (
    tester,
  ) async {
    final c = controller();
    addTearDown(c.dispose);
    c.setSignedStep(5);
    var changes = 0;
    var longPresses = 0;
    await show(
      tester,
      c,
      changed: () => changes++,
      longPress: () => longPresses++,
    );
    expect(find.text('Audio off'), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
    expect(button.onLongPress, isNull);
    await tester.tap(find.text('Audio off'));
    await tester.pump();
    expect(c.audioEnabled, isFalse);
    expect(c.signedStep, 5);
    expect(c.isScrolling, isTrue);
    expect(changes, 0);
    expect(longPresses, 0);
  });

  testWidgets(
    'stopping silent scroll leaves Audio Off and transport disabled',
    (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      c.setSignedStep(3);
      await show(tester, c);
      c.stopForManualInteraction();
      await tester.pump();
      await tester.tap(find.text('Audio off'));
      expect(c.audioEnabled, isFalse);
      expect(c.isScrolling, isFalse);
      expect(
        tester.widget<TextButton>(find.byType(TextButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'Audio On permits play and pause without changing its preference',
    (tester) async {
      final c = controller(audio: true);
      addTearDown(c.dispose);
      await show(tester, c);
      await tester.tap(find.text('Play Bible'));
      await tester.pump();
      expect(c.isScrolling, isTrue);
      expect(c.audioEnabled, isTrue);
      expect(find.text('Pause'), findsOneWidget);
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(c.isScrolling, isFalse);
      expect(c.audioEnabled, isTrue);
      expect(find.text('Play Bible'), findsOneWidget);
    },
  );

  testWidgets(
    'turning Audio Off disables even a previously captured play callback',
    (tester) async {
      final c = controller(audio: true);
      addTearDown(c.dispose);
      await show(tester, c);
      final stalePlay = tester
          .widget<TextButton>(find.byType(TextButton))
          .onPressed!;
      c.updatePreferences(const MacAutoscrollPreferences(audioEnabled: false));
      stalePlay();
      await tester.pump();
      expect(c.audioEnabled, isFalse);
      expect(c.isScrolling, isFalse);
      expect(find.text('Audio off'), findsOneWidget);
    },
  );

  testWidgets('busy narration transport cannot start playback', (tester) async {
    final c = controller(audio: true);
    addTearDown(c.dispose);
    await show(tester, c, busy: true);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Play Bible'));
    expect(c.isScrolling, isFalse);
    expect(c.audioEnabled, isTrue);
  });
}
