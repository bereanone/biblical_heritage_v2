import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_autoscroll_frame_rate_boost.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

const _portrait = ReaderDeviceOrientation.portrait;

class FakeReaderAutoScrollFrameRateBoost
    implements ReaderAutoScrollFrameRateBoost {
  final List<bool> calls = [];

  @override
  Future<void> setActive(bool active) async {
    calls.add(active);
  }
}

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
  test('ordinary Android ticker gaps (30-90ms, unboosted refresh rate) pass '
      'through unmodified so distance stays proportional to elapsed time', () {
    for (final ms in [16, 35, 45, 60, 90]) {
      expect(
        readerSmoothAutoScrollFrameElapsed(Duration(milliseconds: ms)),
        Duration(milliseconds: ms),
        reason: 'a $ms ms gap must not be truncated',
      );
    }
  });

  test('a fixed speed advances proportionally correct distance across 35ms, '
      '45ms, 60ms, and 90ms frame gaps', () {
    const speedPixelsPerSecond = 320.0;
    for (final ms in [35, 45, 60, 90]) {
      final elapsed = readerSmoothAutoScrollFrameElapsed(
        Duration(milliseconds: ms),
      );
      final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final distance = speedPixelsPerSecond * seconds;
      expect(
        distance,
        closeTo(speedPixelsPerSecond * ms / 1000, 0.0001),
        reason: 'a $ms ms gap must cover its full proportional distance',
      );
    }
  });

  test('an extreme background/resume gap is still capped rather than replayed '
      'as one large jump', () {
    expect(
      readerSmoothAutoScrollFrameElapsed(const Duration(seconds: 30)),
      const Duration(milliseconds: 250),
    );
    expect(
      readerSmoothAutoScrollFrameElapsed(const Duration(milliseconds: 251)),
      const Duration(milliseconds: 250),
    );
    expect(
      readerSmoothAutoScrollFrameElapsed(const Duration(milliseconds: 250)),
      const Duration(milliseconds: 250),
    );
  });

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

  testWidgets(
    'requests the high frame-rate boost while a session is active and '
    'releases it on stop and on dispose',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final boost = FakeReaderAutoScrollFrameRateBoost();
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget(),
        settings: settings,
        frameRateBoost: boost,
      );

      await controller.activate();
      expect(boost.calls, [true]);

      await controller.stop(notify: false);
      expect(boost.calls, [true, false]);

      await controller.activate();
      expect(boost.calls, [true, false, true]);

      controller.dispose();
      expect(boost.calls, [true, false, true, false]);
      await source.dispose();
    },
  );

  testWidgets(
    'the constant-speed diagnostic driver also requests and releases the '
    'frame-rate boost',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final boost = FakeReaderAutoScrollFrameRateBoost();
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget(),
        settings: settings,
        frameRateBoost: boost,
      );

      // debugRunConstantSpeedDiagnostic stops any prior session first (a
      // no-op release since nothing was active yet), then requests the
      // boost for the diagnostic run itself.
      await controller.debugRunConstantSpeedDiagnostic(40);
      expect(boost.calls, [false, true]);

      controller.debugStopConstantSpeedDiagnostic();
      expect(boost.calls, [false, true, false]);

      controller.dispose();
      await source.dispose();
    },
  );

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

  testWidgets(
    'vertical chapter boundary preserves speed and latches one transition',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final target = CallbackReaderAutoScrollTarget()..attach((_) => false);
      final transitions = <ReaderChapterTiltDirection>[];
      var horizontalTransitions = 0;
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: target,
        settings: settings,
        preferences: const ReaderTiltPreferences(
          horizontalChapterTiltEnabled: true,
        ),
        canChangeChapter: (_) => true,
        onChapterChange: (_) => horizontalTransitions += 1,
        onVerticalBoundary: (direction) {
          transitions.add(direction);
          return true;
        },
      );
      addTearDown(() async {
        controller.dispose();
        await source.dispose();
      });

      await controller.activate();
      for (var i = 0; i < settings.calibrationSampleCount; i++) {
        source.add(sample(0));
      }
      source.add(sample(10));
      controller.tick();

      final speedAtBoundary = controller.speedPixelsPerSecond;
      expect(transitions, [ReaderChapterTiltDirection.next]);
      expect(speedAtBoundary, greaterThan(0));
      expect(controller.isActive, isTrue);
      expect(controller.verticalBoundaryTransitionInProgress, isTrue);

      source.add(sample(10, horizontalDegrees: 30));
      controller.tick();
      controller.tick();
      expect(transitions, hasLength(1));
      expect(horizontalTransitions, 0);
      expect(controller.speedPixelsPerSecond, closeTo(speedAtBoundary, 0.001));

      var appliedPixels = 0.0;
      target.attach((delta) {
        appliedPixels += delta;
        return true;
      });
      controller.completeVerticalBoundaryTransition();
      controller.tick();
      expect(appliedPixels, greaterThan(0));
      expect(controller.speedPixelsPerSecond, closeTo(speedAtBoundary, 0.001));
      controller.stopSynchronously();
      await tester.pump();
    },
  );

  testWidgets('upward vertical boundary requests the previous chapter', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final transitions = <ReaderChapterTiltDirection>[];
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget()..attach((_) => false),
      settings: settings,
      onVerticalBoundary: (direction) {
        transitions.add(direction);
        return true;
      },
    );
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await controller.activate();
    for (var i = 0; i < settings.calibrationSampleCount; i++) {
      source.add(sample(0));
    }
    source.add(sample(-10));
    controller.tick();

    expect(transitions, [ReaderChapterTiltDirection.previous]);
    expect(controller.speedPixelsPerSecond, lessThan(0));
    expect(controller.isActive, isTrue);
    controller.stopSynchronously();
    await tester.pump();
  });

  testWidgets('forward neutral reverse rocking never disables the session', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    var pixels = 0.0;
    var sawForward = false;
    var sawBackward = false;
    final target = CallbackReaderAutoScrollTarget()
      ..attach((delta) {
        pixels += delta;
        return true;
      });
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: target,
      settings: settings,
    );
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await controller.activate();
    for (var i = 0; i < settings.calibrationSampleCount; i++) {
      source.add(sample(0));
    }
    for (var cycle = 0; cycle < 20; cycle++) {
      source.add(sample(10));
      controller.tick();
      sawForward = sawForward || controller.speedPixelsPerSecond > 0;
      expect(controller.isActive, isTrue);
      source.add(sample(0));
      controller.tick();
      expect(controller.isActive, isTrue);
      source.add(sample(-10));
      controller.tick();
      sawBackward = sawBackward || controller.speedPixelsPerSecond < 0;
      expect(controller.isActive, isTrue);
    }

    expect(sawForward, isTrue);
    expect(sawBackward, isTrue);
    expect(pixels, closeTo(0, 0.001));
    expect(controller.diagnosticStopCalls, 0);
    expect(controller.hasFrameDriver, isTrue);
    expect(controller.diagnosticHasMotionSubscription, isTrue);
    controller.stopSynchronously();
    await tester.pump();
  });

  testWidgets('detach invalid extent and true book edge clamp without stop', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final target = CallbackReaderAutoScrollTarget();
    var boundaryRequests = 0;
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: target,
      settings: settings,
      onVerticalBoundary: (_) {
        boundaryRequests += 1;
        return false;
      },
    );
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await controller.activate();
    for (var i = 0; i < settings.calibrationSampleCount; i++) {
      source.add(sample(0));
    }
    source.add(sample(10));
    controller.tick();
    expect(controller.isActive, isTrue);
    expect(controller.diagnosticStopCalls, 0);

    target.attach((_) => false);
    source.add(sample(10));
    controller.tick();
    expect(boundaryRequests, 1);
    expect(controller.isActive, isTrue);
    expect(controller.speedPixelsPerSecond, 0);
    expect(controller.diagnosticStopCalls, 0);

    target.attach((_) => true);
    source.add(sample(-10));
    controller.tick();
    expect(controller.isActive, isTrue);
    expect(controller.speedPixelsPerSecond, lessThan(0));
    controller.stopSynchronously();
    await tester.pump();
  });

  testWidgets(
    'eLibrary fail-safe rocking clamps once and never changes section',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      final target = CallbackReaderAutoScrollTarget()..attach((_) => false);
      var boundaryCallbacks = 0;
      var sectionIndex = 2;
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: target,
        settings: settings,
        // eLibrary fail-safe intentionally provides no horizontal chapter
        // callbacks and treats the vertical callback as a clamp latch only.
        onVerticalBoundary: (_) {
          boundaryCallbacks += 1;
          return true;
        },
      );
      addTearDown(() async {
        controller.dispose();
        await source.dispose();
      });

      await controller.activate();
      for (var i = 0; i < settings.calibrationSampleCount; i++) {
        source.add(sample(0));
      }
      for (var cycle = 0; cycle < 20; cycle++) {
        source.add(sample(10, horizontalDegrees: 20));
        controller.tick();
        source.add(sample(0, horizontalDegrees: -20));
        controller.tick();
        source.add(sample(-10, horizontalDegrees: 20));
        controller.tick();
      }

      expect(boundaryCallbacks, 1);
      expect(sectionIndex, 2);
      expect(controller.isActive, isTrue);
      expect(controller.verticalBoundaryTransitionInProgress, isTrue);
      expect(controller.diagnosticStopCalls, 0);
      controller.stopSynchronously();
      await tester.pump();
    },
  );

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

  testWidgets('material vertical tilt cannot arm a horizontal chapter change', (
    tester,
  ) async {
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

    // A sideways component caused by ordinary forward tilt is ineligible.
    source.add(sample(10, horizontalDegrees: -17));
    controller.tick();
    expect(pixels, greaterThan(0));
    now = now.add(const Duration(milliseconds: 600));
    source.add(sample(10, horizontalDegrees: -17));

    expect(changes, isEmpty);
    controller.dispose();
    await source.dispose();
  });

  testWidgets('minor sideways movement during vertical scroll never fires', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    var now = DateTime.utc(2026, 1, 1);
    final changes = <ReaderChapterTiltDirection>[];
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget()..attach((_) => true),
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
    for (var step = 0; step < 5; step++) {
      source.add(sample(14, horizontalDegrees: 8));
      controller.tick();
      now = now.add(const Duration(milliseconds: 200));
    }
    expect(changes, isEmpty);
    controller.dispose();
    await source.dispose();
  });

  testWidgets('sensor samples only change target velocity', (tester) async {
    final source = FakeReaderTiltMotionSource();
    final deltas = <double>[];
    final target = CallbackReaderAutoScrollTarget()
      ..attach((delta) {
        deltas.add(delta);
        return true;
      });
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: target,
      settings: settings,
    );
    await controller.activate();
    for (var i = 0; i < settings.calibrationSampleCount; i++) {
      source.add(sample(0));
    }
    source.add(sample(12));
    source.add(sample(13));
    source.add(sample(14));
    expect(deltas, isEmpty);
    controller.tick();
    expect(deltas, hasLength(1));
    controller.dispose();
    await source.dispose();
  });

  testWidgets('activation owns exactly one frame driver', (tester) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: settings,
    );
    await controller.activate();
    expect(controller.hasFrameDriver, isTrue);
    await controller.activate();
    expect(source.startCount, 1);
    await controller.stop();
    expect(controller.hasFrameDriver, isFalse);
    controller.dispose();
    await source.dispose();
  });

  testWidgets(
    'elapsed integration is sensor-frequency independent and keeps fractions',
    (tester) async {
      Future<double> run({required int duplicateSamples}) async {
        final source = FakeReaderTiltMotionSource();
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
        );
        await controller.activate();
        for (var i = 0; i < settings.calibrationSampleCount; i++) {
          source.add(sample(0));
        }
        for (var i = 0; i < duplicateSamples; i++) {
          source.add(sample(10));
        }
        controller.tick(elapsed: const Duration(milliseconds: 7));
        controller.tick(elapsed: const Duration(milliseconds: 13));
        controller.tick(elapsed: const Duration(milliseconds: 80));
        controller.dispose();
        await source.dispose();
        return pixels;
      }

      final lowFrequency = await run(duplicateSamples: 1);
      final highFrequency = await run(duplicateSamples: 20);
      expect(lowFrequency, closeTo(highFrequency, 0.0001));
      final speed = readerTiltSpeedForPreferences(
        10 * math.pi / 180,
        settings,
        ReaderTiltPreferences.defaults,
      );
      expect(lowFrequency, closeTo(speed * 0.1, 0.0001));
      expect(lowFrequency, isNot(lowFrequency.roundToDouble()));
    },
  );

  testWidgets('velocity accelerates, decelerates, and stops exactly', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget()..attach((_) => true),
      settings: const ReaderTiltAutoScrollSettings(
        calibrationSampleCount: 3,
        sampleSmoothingFactor: 1,
        speedSmoothingFactor: 0.2,
        updateInterval: Duration(milliseconds: 16),
      ),
    );
    await controller.activate();
    for (var i = 0; i < 3; i++) {
      source.add(sample(0));
    }
    source.add(sample(12));
    controller.tick(elapsed: const Duration(milliseconds: 16));
    final first = controller.speedPixelsPerSecond;
    controller.tick(elapsed: const Duration(milliseconds: 16));
    expect(controller.speedPixelsPerSecond, greaterThan(first));
    source.add(sample(0));
    controller.tick(elapsed: const Duration(milliseconds: 16));
    expect(controller.speedPixelsPerSecond, lessThan(first * 2));
    for (var i = 0; i < 80; i++) {
      controller.tick(elapsed: const Duration(milliseconds: 16));
    }
    expect(controller.speedPixelsPerSecond, 0);
    controller.dispose();
    await source.dispose();
  });

  testWidgets(
    'synchronous stop invalidates the active session and queued input',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      var pixels = 0.0;
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget()
          ..attach((delta) {
            pixels += delta;
            return true;
          }),
        settings: settings,
      );
      addTearDown(() async {
        controller.dispose();
        await source.dispose();
      });

      await controller.activate();
      for (var i = 0; i < settings.calibrationSampleCount; i++) {
        source.add(sample(0));
      }
      source.add(sample(10));
      controller.tick();
      expect(pixels, greaterThan(0));
      final stoppedPixels = pixels;
      final generation = controller.diagnosticSessionGeneration;

      controller.stopSynchronously();

      expect(controller.isActive, isFalse);
      expect(controller.speedPixelsPerSecond, 0);
      expect(controller.hasFrameDriver, isFalse);
      expect(controller.diagnosticHasMotionSubscription, isFalse);
      expect(controller.diagnosticSessionGeneration, greaterThan(generation));
      source.add(sample(20));
      controller.tick();
      expect(pixels, stoppedPixels);
    },
  );

  testWidgets('five chapter callbacks retain one subscription and ticker', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    var chapter = 0;
    var pixels = 0.0;
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget()
        ..attach((delta) {
          pixels += delta;
          return true;
        }),
      settings: settings,
      canChangeChapter: (_) => true,
      onChapterChange: (_) => chapter += 1,
    );
    addTearDown(() async {
      controller.dispose();
      await source.dispose();
    });

    await controller.activate();
    for (var i = 0; i < settings.calibrationSampleCount; i++) {
      source.add(sample(0));
    }
    source.add(sample(10));
    controller.tick();
    final firstDelta = pixels;
    final initialListenerCount = controller.diagnosticListenerCount;
    final chapterDeltas = <double>[];
    for (var transition = 0; transition < 5; transition++) {
      source.add(sample(10, horizontalDegrees: 30));
      controller.tick();
      source.add(sample(10, horizontalDegrees: 0));
      final before = pixels;
      controller.tick();
      final delta = pixels - before;
      chapterDeltas.add(delta);
      expect(delta, closeTo(firstDelta, 0.001));
      expect(source.startCount, 1);
      expect(controller.hasFrameDriver, isTrue);
      expect(controller.diagnosticHasMotionSubscription, isTrue);
      expect(controller.diagnosticListenerCount, initialListenerCount);
    }
    expect(chapterDeltas, everyElement(closeTo(firstDelta, 0.001)));
    controller.stopSynchronously();
    await tester.pump();
  });

  testWidgets(
    'hundreds of visual frames request no persistence and retain resources',
    (tester) async {
      final source = FakeReaderTiltMotionSource();
      const persistenceRequests = 0;
      var pixels = 0.0;
      final controller = ReaderTiltAutoScrollController(
        motionSource: source,
        scrollTarget: CallbackReaderAutoScrollTarget()
          ..attach((delta) {
            pixels += delta;
            return true;
          }),
        settings: const ReaderTiltAutoScrollSettings(
          calibrationSampleCount: 1,
          sampleSmoothingFactor: 1,
          speedSmoothingFactor: 1,
        ),
      );
      addTearDown(() async {
        controller.dispose();
        await source.dispose();
      });

      await controller.activate();
      source.add(sample(0));
      source.add(sample(20));
      final listenerCount = controller.diagnosticListenerCount;
      double? firstChapterDelta;
      for (var chapter = 0; chapter < 6; chapter++) {
        final before = pixels;
        for (var frame = 0; frame < 120; frame++) {
          controller.tick(elapsed: const Duration(microseconds: 16667));
        }
        final chapterDelta = pixels - before;
        firstChapterDelta ??= chapterDelta;
        expect(chapterDelta, closeTo(firstChapterDelta, 0.001));
        expect(controller.diagnosticListenerCount, listenerCount);
        expect(controller.diagnosticHasMotionSubscription, isTrue);
        expect(controller.diagnosticHasFrameDriver, isTrue);
      }

      // Persistence has no callback in the frame driver or scroll target.
      expect(persistenceRequests, 0);
      expect(controller.diagnosticFrameTicks, 720);
      controller.stopSynchronously();
      await tester.pump();
    },
  );

  testWidgets('stop is synchronous while an unrelated save is pending', (
    tester,
  ) async {
    final source = FakeReaderTiltMotionSource();
    final pendingSave = Completer<void>();
    final controller = ReaderTiltAutoScrollController(
      motionSource: source,
      scrollTarget: CallbackReaderAutoScrollTarget(),
      settings: settings,
    );
    addTearDown(() async {
      if (!pendingSave.isCompleted) pendingSave.complete();
      controller.dispose();
      await source.dispose();
    });

    await controller.activate();
    final save = pendingSave.future;
    controller.stopSynchronously();

    expect(controller.isActive, isFalse);
    expect(controller.diagnosticHasFrameDriver, isFalse);
    expect(controller.diagnosticHasMotionSubscription, isFalse);
    expect(pendingSave.isCompleted, isFalse);
    pendingSave.complete();
    await save;
    await tester.pump();
  });

  testWidgets('eLibrary adapter preserves fractional and full-speed deltas', (
    tester,
  ) async {
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
    final target = ScrollControllerReaderAutoScrollTarget(scroll);
    expect(target.scrollBy(0.25), isTrue);
    expect(target.scrollBy(0.25), isTrue);
    expect(target.scrollBy(0.25), isTrue);
    expect(scroll.offset, closeTo(0.75, 0.0001));

    final before = scroll.offset;
    expect(target.scrollBy(40), isTrue);
    expect(scroll.offset - before, closeTo(40, 0.0001));
    scroll.dispose();
  });

  test('explicit shared curve scales 50, 100, and 200 percent correctly', () {
    const defaults = ReaderTiltAutoScrollSettings();
    final neutral = defaults.maximumTiltRadians * 0.05;
    final span = defaults.maximumTiltRadians - neutral;
    double angleFor(double normalized) => neutral + span * normalized;
    double speed(double normalized, double multiplier) =>
        readerTiltSpeedForPreferences(
          angleFor(normalized),
          defaults,
          ReaderTiltPreferences(speedMultiplier: multiplier),
        );

    for (final normalized in [0.25, 0.6, 1.0]) {
      final half = speed(normalized, 0.5);
      final normal = speed(normalized, 1);
      final doubleSpeed = speed(normalized, 2);
      expect(half, closeTo(normal * 0.5, 0.001));
      expect(doubleSpeed, closeTo(normal * 2, 0.001));
    }
    expect(speed(0.25, 1), closeTo(72, 0.001));
    expect(speed(0.6, 1), closeTo(293.76, 0.001));
    expect(speed(1, 1), closeTo(720, 0.001));
    expect(speed(1, 2), closeTo(1440, 0.001));
    expect(speed(1, 2) / 60, closeTo(24, 0.001));
    expect(
      readerTiltNormalizedMagnitude(
        angleFor(0.6),
        ReaderTiltAutoScrollSettings(deadZoneRadians: neutral),
      ),
      closeTo(0.6, 0.001),
    );
  });

  test('curve increases materially across the complete usable tilt range', () {
    const defaults = ReaderTiltAutoScrollSettings();
    final neutral = defaults.maximumTiltRadians * 0.05;
    final span = defaults.maximumTiltRadians - neutral;
    double speedAt(double normalized, {double multiplier = 1}) =>
        readerTiltSpeedForPreferences(
          neutral + span * normalized,
          defaults,
          ReaderTiltPreferences(speedMultiplier: multiplier),
        );

    final samples = [
      for (var tenth = 0; tenth <= 10; tenth++) speedAt(tenth / 10),
    ];
    expect(samples.first, 0);
    for (var index = 1; index < samples.length; index++) {
      expect(samples[index], greaterThan(samples[index - 1]));
    }
    for (var index = 8; index < samples.length; index++) {
      expect(samples[index] - samples[index - 1], greaterThan(40));
    }
    expect(samples.last, defaults.maximumSpeedPixelsPerSecond);
    expect(speedAt(0.999), lessThan(samples.last));
    for (final normalized in [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]) {
      expect(
        speedAt(normalized, multiplier: 2),
        closeTo(speedAt(normalized) * 2, 0.001),
      );
    }
  });

  testWidgets('Bible and eLibrary apply equal one-second displacement', (
    tester,
  ) async {
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
    const exact = ReaderTiltAutoScrollSettings(
      calibrationSampleCount: 1,
      sampleSmoothingFactor: 1,
      speedSmoothingFactor: 1,
    );
    final bibleSource = FakeReaderTiltMotionSource();
    final librarySource = FakeReaderTiltMotionSource();
    var biblePixels = 0.0;
    final bible = ReaderTiltAutoScrollController(
      motionSource: bibleSource,
      scrollTarget: CallbackReaderAutoScrollTarget()
        ..attach((delta) {
          biblePixels += delta;
          return true;
        }),
      settings: exact,
    );
    final library = ReaderTiltAutoScrollController(
      motionSource: librarySource,
      scrollTarget: ScrollControllerReaderAutoScrollTarget(scroll),
      settings: exact,
    );
    await bible.activate();
    await library.activate();
    bibleSource.add(sample(0));
    librarySource.add(sample(0));
    bibleSource.add(sample(28));
    librarySource.add(sample(28));
    for (var frame = 0; frame < 60; frame++) {
      const elapsed = Duration(microseconds: 16667);
      bible.tick(elapsed: elapsed);
      library.tick(elapsed: elapsed);
    }
    expect(biblePixels, closeTo(720, 0.1));
    expect(scroll.offset, closeTo(biblePixels, 0.001));
    bible.dispose();
    library.dispose();
    await bibleSource.dispose();
    await librarySource.dispose();
  });
}
