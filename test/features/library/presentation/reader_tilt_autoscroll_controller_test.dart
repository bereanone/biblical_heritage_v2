import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

const _portrait = ReaderDeviceOrientation.portrait;

ReaderTiltSample sample(
  double degrees, {
  double horizontalDegrees = 0,
  ReaderDeviceOrientation orientation = _portrait,
}) => ReaderTiltSample(
  pitchRadians: degrees * math.pi / 180,
  horizontalRadians: horizontalDegrees * math.pi / 180,
  orientation: orientation,
);

void main() {
  const settings = ReaderTiltAutoScrollSettings(
    calibrationSampleCount: 5,
    sampleSmoothingFactor: 1,
    speedSmoothingFactor: 1,
    updateInterval: Duration(milliseconds: 100),
  );

  test('speed curve has dead zone, direction, progression, and cap', () {
    expect(readerTiltSpeedForAngle(2 * math.pi / 180, settings), 0);
    final slight = readerTiltSpeedForAngle(4 * math.pi / 180, settings);
    final greater = readerTiltSpeedForAngle(10 * math.pi / 180, settings);
    expect(slight, greaterThan(0));
    expect(greater, greaterThan(slight));
    expect(readerTiltSpeedForAngle(-10 * math.pi / 180, settings), -greater);
    expect(
      readerTiltSpeedForAngle(90 * math.pi / 180, settings),
      settings.maximumSpeedPixelsPerSecond,
    );
  });

  test('preferences reverse direction and scale neutral zone and speed', () {
    final angle = 8 * math.pi / 180;
    final normal = readerTiltSpeedForPreferences(
      angle,
      settings,
      ReaderTiltPreferences.defaults,
    );
    final reversed = readerTiltSpeedForPreferences(
      angle,
      settings,
      const ReaderTiltPreferences(reverseVerticalDirection: true),
    );
    expect(reversed, -normal);

    final moreSensitive = readerTiltSpeedForPreferences(
      1 * math.pi / 180,
      settings,
      const ReaderTiltPreferences(neutralZoneFraction: 0.02),
    );
    final lessSensitive = readerTiltSpeedForPreferences(
      1 * math.pi / 180,
      settings,
      const ReaderTiltPreferences(neutralZoneFraction: 0.10),
    );
    expect(moreSensitive, greaterThan(0));
    expect(lessSensitive, 0);

    final slower = readerTiltSpeedForPreferences(
      angle,
      settings,
      const ReaderTiltPreferences(speedMultiplier: 0.5),
    );
    final faster = readerTiltSpeedForPreferences(
      angle,
      settings,
      const ReaderTiltPreferences(speedMultiplier: 2),
    );
    expect(faster, closeTo(slower * 4, 0.001));
  });

  testWidgets('calibrates from several samples and recalibrates', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: settings,
    );
    await controller.activate();
    for (final degrees in [9.8, 10.2, 10.0, 9.9, 30.0]) {
      source.add(sample(degrees));
    }
    expect(controller.neutralPitchRadians, closeTo(10 * math.pi / 180, 0.001));

    controller.recalibrate();
    for (final degrees in [19.8, 20.2, 20.0, 19.9, 20.1]) {
      source.add(sample(degrees));
    }
    expect(controller.neutralPitchRadians, closeTo(20 * math.pi / 180, 0.001));
    controller.dispose();
    await source.dispose();
  });

  testWidgets('tilt drives attached scroll view and respects both boundaries', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final scroll = ScrollController();
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: scroll,
          itemCount: 100,
          itemBuilder: (_, index) =>
              SizedBox(height: 40, child: Text('$index')),
        ),
      ),
    );
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: ScrollControllerReaderAutoScrollTarget(scroll),
      settings: settings,
    );
    await controller.activate();
    for (var i = 0; i < 5; i++) {
      source.add(sample(0));
    }
    source.add(sample(10));
    controller.tick();
    expect(scroll.offset, greaterThan(0));
    final forwardSpeed = controller.speedPixelsPerSecond;

    source.add(sample(4));
    controller.tick();
    expect(controller.speedPixelsPerSecond, lessThan(forwardSpeed));

    source.add(sample(-10));
    final beforeBackward = scroll.offset;
    controller.tick();
    expect(scroll.offset, lessThan(beforeBackward));
    scroll.jumpTo(scroll.position.minScrollExtent);
    controller.tick();
    expect(scroll.offset, scroll.position.minScrollExtent);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    source.add(sample(17));
    controller.tick();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    controller.dispose();
    await source.dispose();
  });

  testWidgets('sample smoothing dampens a noisy jump', (tester) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: const ReaderTiltAutoScrollSettings(
        calibrationSampleCount: 3,
        sampleSmoothingFactor: 0.2,
        speedSmoothingFactor: 1,
        updateInterval: Duration(milliseconds: 100),
      ),
    );
    await controller.activate();
    for (var i = 0; i < 3; i++) {
      source.add(sample(0));
    }
    source.add(sample(17));
    controller.tick();
    expect(controller.speedPixelsPerSecond, lessThan(30));
    controller.dispose();
    await source.dispose();
  });

  testWidgets('manual interaction, popup, and background stop cleanly', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: settings,
    );
    await controller.activate();
    await controller.stopForManualInteraction();
    expect(controller.state, ReaderTiltAutoScrollState.paused);
    expect(source.stopCount, 1);

    await controller.activate();
    await controller.stop(); // Contents/dialog entry point.
    expect(controller.isActive, isFalse);
    await controller.activate();
    await controller.stop(); // App lifecycle entry point.
    expect(controller.isActive, isFalse);
    controller.dispose();
    await source.dispose();
  });

  testWidgets(
    'orientation change stops and activate never duplicates resources',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget(),
        settings: settings,
      );
      await controller.activate();
      await controller.activate();
      expect(source.startCount, 1);
      for (var i = 0; i < 5; i++) {
        source.add(sample(0));
      }
      source.add(sample(0, orientation: ReaderDeviceOrientation.landscapeLeft));
      await tester.pump();
      expect(controller.state, ReaderTiltAutoScrollState.paused);
      expect(source.stopCount, 1);
      controller.dispose();
      await source.dispose();
    },
  );

  testWidgets('unavailable and error states do not crash', (tester) async {
    final unavailable = FakeReaderTiltMotionSource(isSupported: false);
    final first = ReaderTiltAutoScrollController(
      motionSource: unavailable,
      scrollTarget: CallbackReaderAutoScrollTarget(),
    );
    await first.activate();
    expect(first.state, ReaderTiltAutoScrollState.unavailable);
    first.dispose();

    final failing = FakeReaderTiltMotionSource();
    final second = ReaderTiltAutoScrollController(
      motionSource: failing,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: settings,
    );
    await second.activate();
    failing.addError(StateError('sensor failed'));
    await tester.pump();
    expect(second.state, ReaderTiltAutoScrollState.error);
    second.dispose();
    await unavailable.dispose();
    await failing.dispose();
  });

  testWidgets(
    'enabled horizontal tilt triggers once and pauses vertical motion',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      var now = DateTime.utc(2026, 1, 1);
      final changes = <ReaderChapterTiltDirection>[];
      final target = CallbackReaderAutoScrollTarget()..attach((_) => true);
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: target,
        settings: settings,
        preferences: const ReaderTiltPreferences(
          horizontalChapterTiltEnabled: true,
        ),
        canChangeChapter: (_) => true,
        onChapterChange: changes.add,
        now: () => now,
      );
      await controller.activate();
      for (var i = 0; i < 5; i++) {
        source.add(sample(0));
      }
      source.add(sample(0, horizontalDegrees: 17));
      now = now.add(const Duration(milliseconds: 600));
      source.add(sample(0, horizontalDegrees: 17));
      expect(changes, [ReaderChapterTiltDirection.next]);
      source.add(sample(10, horizontalDegrees: 17));
      controller.tick();
      expect(controller.speedPixelsPerSecond, 0);
      source.add(sample(0));
      now = now.add(const Duration(seconds: 2));
      source.add(sample(0));
      source.add(sample(0, horizontalDegrees: 17));
      now = now.add(const Duration(milliseconds: 600));
      source.add(sample(0, horizontalDegrees: 17));
      expect(changes, [
        ReaderChapterTiltDirection.next,
        ReaderChapterTiltDirection.next,
      ]);
      controller.dispose();
      await source.dispose();
    },
  );

  testWidgets(
    'horizontal chapter tilt is off by default and orientation cancels pending',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      var now = DateTime.utc(2026, 1, 1);
      final changes = <ReaderChapterTiltDirection>[];
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget(),
        settings: settings,
        canChangeChapter: (_) => true,
        onChapterChange: changes.add,
        now: () => now,
      );
      await controller.activate();
      for (var i = 0; i < 5; i++) {
        source.add(sample(0));
      }
      source.add(sample(0, horizontalDegrees: 17));
      now = now.add(const Duration(seconds: 1));
      source.add(sample(0, horizontalDegrees: 17));
      expect(changes, isEmpty);

      controller.updatePreferences(
        const ReaderTiltPreferences(horizontalChapterTiltEnabled: true),
      );
      source.add(sample(0, horizontalDegrees: 17));
      source.add(
        sample(
          0,
          horizontalDegrees: 17,
          orientation: ReaderDeviceOrientation.landscapeLeft,
        ),
      );
      await tester.pump();
      expect(controller.state, ReaderTiltAutoScrollState.paused);
      expect(changes, isEmpty);
      controller.dispose();
      await source.dispose();
    },
  );

  testWidgets(
    'boundary-approved previous hold pins vertical motion at the top',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      var now = DateTime.utc(2026, 1, 1);
      final changes = <ReaderChapterTiltDirection>[];
      var pixels = 0.0;
      final target = CallbackReaderAutoScrollTarget()
        ..attach((delta) {
          pixels += delta;
          return true;
        });
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: target,
        settings: settings,
        preferences: const ReaderTiltPreferences(
          horizontalChapterTiltEnabled: true,
        ),
        canChangeChapter: (direction) =>
            direction == ReaderChapterTiltDirection.previous && pixels <= 48,
        onChapterChange: changes.add,
        now: () => now,
      );
      await controller.activate();
      for (var i = 0; i < 5; i++) {
        source.add(sample(0));
      }

      // The user's left tilt also contains enough forward pitch to scroll.
      source.add(sample(10, horizontalDegrees: -17));
      controller.tick();
      expect(pixels, 0);
      now = now.add(const Duration(milliseconds: 600));
      source.add(sample(10, horizontalDegrees: -17));

      expect(changes, [ReaderChapterTiltDirection.previous]);
      expect(pixels, 0);
      controller.dispose();
      await source.dispose();
    },
  );
}
