import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controls.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

void main() {
  testWidgets('long press opens shared settings and tap still toggles', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var preferences = ReaderTiltPreferences.defaults;
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ReaderTiltAutoScrollIconButton(
              controller: controller,
              onPressed: controller.activate,
              onLongPress: () => showReaderTiltSettingsSheet(
                context,
                preferences: preferences,
                includeChapterTilt: true,
                onChanged: (value) => preferences = value,
                onRecalibrate: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    expect(controller.state, ReaderTiltAutoScrollState.calibrating);
    await controller.stop();
    final hold = await tester.startGesture(
      tester.getCenter(find.byIcon(Icons.swap_vert_rounded)),
    );
    await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
    await hold.up();
    await tester.pumpAndSettle();
    expect(find.text('Tilt Auto-scroll Settings'), findsOneWidget);
    expect(find.byKey(const ValueKey('autoscroll-mode')), findsNothing);
    expect(find.text('Steady'), findsNothing);
    expect(find.text('Tilt Sideways to Change Chapter'), findsOneWidget);
    expect(find.text('Set Current Angle as Neutral'), findsOneWidget);
    expect(find.byKey(const ValueKey('tilt-maximum-speed')), findsNothing);
    expect(find.byKey(const ValueKey('tilt-sensor-smoothing')), findsNothing);
    expect(find.textContaining('Sensor smoothing'), findsNothing);
    expect(find.text('Restore Defaults'), findsOneWidget);
  });

  testWidgets('shared button requires a deliberate 900ms stationary hold', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var taps = 0;
    var settings = 0;
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTiltAutoScrollIconButton(
          controller: controller,
          onPressed: () => taps += 1,
          onLongPress: () => settings += 1,
        ),
      ),
    );
    final center = tester.getCenter(find.byTooltip('Tilt Auto-scroll'));

    Future<void> pressFor(Duration duration) async {
      final gesture = await tester.startGesture(center);
      await tester.pump(duration);
      await gesture.up();
      await tester.pump();
    }

    await pressFor(const Duration(milliseconds: 300));
    await pressFor(const Duration(milliseconds: 700));
    expect(taps, 2);
    expect(settings, 0);

    await pressFor(ReaderTiltAutoScrollIconButton.longPressDuration);
    expect(settings, 1);
    expect(taps, 2);

    await pressFor(const Duration(milliseconds: 899));
    expect(settings, 1);
    expect(taps, 3);

    final moved = await tester.startGesture(center);
    await moved.moveBy(const Offset(40, 0));
    await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
    await moved.up();
    await tester.pump();
    expect(settings, 1);
    expect(taps, 3);
  });

  testWidgets(
    'active pointer down stops synchronously and cannot open settings',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget(),
      );
      var taps = 0;
      var settings = 0;
      addTearDown(() async {
        controller.dispose();
        await source.dispose();
      });
      await controller.activate();

      await tester.pumpWidget(
        MaterialApp(
          home: ReaderTiltAutoScrollIconButton(
            controller: controller,
            onPressed: () => taps += 1,
            onLongPress: () => settings += 1,
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Tilt Auto-scroll')),
      );
      expect(controller.isActive, isFalse);
      expect(controller.hasFrameDriver, isFalse);
      await tester.pump(ReaderTiltAutoScrollIconButton.longPressDuration);
      await gesture.up();
      await tester.pump();
      expect(taps, 0);
      expect(settings, 0);
    },
  );

  testWidgets('chapter generation cancels a pending deliberate hold', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var settings = 0;
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    Widget app(int generation) => MaterialApp(
      home: ReaderTiltAutoScrollIconButton(
        controller: controller,
        interactionGeneration: generation,
        onPressed: () {},
        onLongPress: () => settings += 1,
      ),
    );
    await tester.pumpWidget(app(0));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byTooltip('Tilt Auto-scroll')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(app(1));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pump();
    expect(settings, 0);
  });

  testWidgets('five chapter rebuilds retain constant controller listeners', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    Widget app(int generation) => MaterialApp(
      home: Column(
        children: [
          ReaderTiltAutoScrollIconButton(
            controller: controller,
            interactionGeneration: generation,
            onPressed: controller.activate,
          ),
          ReaderTiltAutoScrollActiveIndicator(controller: controller),
        ],
      ),
    );

    await tester.pumpWidget(app(0));
    final initialListeners = controller.diagnosticListenerCount;
    expect(initialListeners, 2);
    for (var chapter = 1; chapter <= 5; chapter++) {
      await tester.pumpWidget(app(chapter));
      expect(controller.diagnosticListenerCount, initialListeners);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.diagnosticListenerCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose cancels a pending hold timer without a late callback', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    var settings = 0;
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderTiltAutoScrollIconButton(
          controller: controller,
          onPressed: () {},
          onLongPress: () => settings += 1,
        ),
      ),
    );
    await tester.startGesture(
      tester.getCenter(find.byTooltip('Tilt Auto-scroll')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
    expect(settings, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bible settings omit chapter tilt and restore defaults', (
    tester,
  ) async {
    var preferences = const ReaderTiltPreferences(
      reverseVerticalDirection: true,
      neutralZoneFraction: 0.10,
      speedMultiplier: 2,
      horizontalChapterTiltEnabled: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showReaderTiltSettingsSheet(
                context,
                preferences: preferences,
                includeChapterTilt: false,
                onChanged: (value) => preferences = value,
                onRecalibrate: () {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Tilt Sideways to Change Chapter'), findsNothing);
    await tester.ensureVisible(find.text('Restore Defaults'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Defaults'));
    expect(preferences.reverseVerticalDirection, isFalse);
    expect(preferences.neutralZoneFraction, 0.05);
    expect(preferences.speedMultiplier, 1.0);
    expect(preferences.horizontalChapterTiltEnabled, isTrue);
  });
}
