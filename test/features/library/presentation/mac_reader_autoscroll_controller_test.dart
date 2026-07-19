import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';

class _Target implements ReaderAutoScrollTarget {
  bool attached = true;
  bool acceptsScroll = true;
  final List<double> deltas = <double>[];
  double offset = 0;

  @override
  bool get isAttached => attached;

  @override
  bool scrollBy(double delta) {
    deltas.add(delta);
    if (acceptsScroll) offset += delta;
    return acceptsScroll;
  }
}

void main() {
  test('signed speed uses reading and scan bands symmetrically', () {
    final target = _Target();
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    expect(controller.signedStep, 0);
    for (final expected in <int>[1, 2, 3, 5, 15, 30, 60]) {
      controller.increaseStep();
      expect(controller.signedStep, expected);
    }
    controller.increaseStep();
    expect(controller.signedStep, 60);
    for (final expected in <int>[
      30,
      15,
      5,
      3,
      2,
      1,
      0,
      -1,
      -2,
      -3,
      -5,
      -15,
      -30,
      -60,
    ]) {
      controller.decreaseStep();
      expect(controller.signedStep, expected);
    }
    controller.decreaseStep();
    expect(controller.signedStep, -60);
  });

  test('requested rate is base speed times signed step at 10x and 20x', () {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(baseSpeed: 60),
      driveFrames: false,
    );
    addTearDown(controller.dispose);
    controller.setSignedStep(10);
    expect(controller.pixelsPerSecond, 600);
    controller.setSignedStep(20);
    expect(controller.pixelsPerSecond, 1200);
    controller.setSignedStep(-20);
    expect(controller.pixelsPerSecond, -1200);

    controller.updatePreferences(
      const MacAutoscrollPreferences(baseSpeed: 18, maximumStep: 20),
    );
    controller.setSignedStep(20);
    expect(controller.pixelsPerSecond, 360);

    controller.updatePreferences(
      const MacAutoscrollPreferences(baseSpeed: 18, maximumStep: 10),
    );
    controller.setSignedStep(20);
    expect(controller.signedStep, 10);
    expect(controller.pixelsPerSecond, 180);
  });

  test('tick changes only continuous pixel delta on the same target', () {
    final target = _Target();
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(2);
    expect(controller.statusLabel, 'Autoscroll ↓ 2×');
    controller.tick(const Duration(milliseconds: 500));
    controller.setSignedStep(-3);
    expect(controller.statusLabel, 'Autoscroll ↑ 3×');
    controller.tick(const Duration(milliseconds: 500));

    expect(identical(controller.scrollTarget, target), isTrue);
    expect(target.deltas, <double>[18, -27]);
  });

  test('18 px/sec fractional frame deltas accumulate without truncation', () {
    final target = _Target();
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(1);
    for (var frame = 0; frame < 60; frame++) {
      controller.tick(const Duration(microseconds: 16667));
    }

    expect(target.deltas.every((delta) => delta > 0 && delta < 1), isTrue);
    expect(target.offset, closeTo(18, .01));
  });

  test('click toggle stops and resumes the last signed speed', () {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(-3);
    controller.toggle();
    expect(controller.signedStep, 0);
    expect(controller.statusLabel, 'Autoscroll Stopped');
    expect(controller.lastNonzeroStep, -3);
    controller.toggle();
    expect(controller.signedStep, -3);
  });

  test('manual scrolling while already stopped emits no stopped status', () {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    final revision = controller.statusRevision;
    controller.stopForManualInteraction();

    expect(controller.signedStep, 0);
    expect(controller.statusRevision, revision);
  });

  test('click followed by frames changes actual target offset', () {
    final target = _Target();
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.toggle();
    expect(controller.signedStep, 1);
    controller.tick(const Duration(seconds: 3));
    expect(target.offset, closeTo(54, .001));
    controller.setSignedStep(10);
    controller.tick(const Duration(seconds: 3));
    expect(target.offset, closeTo(594, .001));
    controller.toggle();
    final stoppedOffset = target.offset;
    controller.tick(const Duration(seconds: 3));
    expect(target.offset, stoppedOffset);
  });

  test('startup target rejection does not immediately stop autoscroll', () {
    final target = _Target()..acceptsScroll = false;
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(1);
    for (var frame = 0; frame < 8; frame++) {
      controller.tick(const Duration(milliseconds: 16));
    }
    expect(controller.signedStep, 1);
    expect(controller.statusLabel, 'Autoscroll ↓ 1×');
    expect(target.deltas, hasLength(8));

    target.acceptsScroll = true;
    controller.tick(const Duration(seconds: 1));
    expect(target.offset, 18);

    target.acceptsScroll = false;
    for (var frame = 0; frame < 8; frame++) {
      controller.tick(const Duration(milliseconds: 16));
    }
    expect(controller.signedStep, 0);
    expect(controller.hasFrameDriver, isFalse);
  });

  test('invalid constructor resume step is normalized and never zero', () {
    final zeroController = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(lastNonzeroStep: 0),
      driveFrames: false,
    );
    addTearDown(zeroController.dispose);
    zeroController.toggle();
    expect(zeroController.signedStep, 1);

    final clampedController = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(
        lastNonzeroStep: -99,
        maximumStep: 4,
      ),
      driveFrames: false,
    );
    addTearDown(clampedController.dispose);
    clampedController.toggle();
    expect(clampedController.signedStep, -4);
  });

  test('stored preferences are bounded and retain signed direction', () {
    expect(
      MacAutoscrollPreferences.fromStoredValues(
        baseSpeed: '24',
        lastNonzeroStep: '-4',
        maximumStep: '4',
      ),
      isA<MacAutoscrollPreferences>()
          .having((value) => value.baseSpeed, 'base speed', 24)
          .having((value) => value.lastNonzeroStep, 'last step', -4)
          .having((value) => value.maximumStep, 'maximum', 4),
    );
    final invalid = MacAutoscrollPreferences.fromStoredValues(
      baseSpeed: 'bad',
      lastNonzeroStep: '0',
      maximumStep: '99',
    );
    expect(invalid.baseSpeed, defaultMacAutoscrollBaseSpeed);
    expect(invalid.lastNonzeroStep, 1);
    expect(invalid.maximumStep, 60);
    final phase7 = MacAutoscrollPreferences.fromStoredValues(
      baseSpeed: '18',
      lastNonzeroStep: '5',
      maximumStep: '5',
    );
    expect(phase7.maximumStep, 5);
    expect(phase7.lastNonzeroStep, 5);

    final phase9 = MacAutoscrollPreferences.fromStoredValues(
      maximumStep: '10',
      lastNonzeroStep: '10',
    );
    expect(phase9.maximumStep, 10);
    expect(phase9.lastNonzeroStep, 10);
  });

  test('20x status and target identity remain stable across reversal', () {
    final target = _Target();
    final controller = MacReaderAutoScrollController(
      scrollTarget: target,
      preferences: const MacAutoscrollPreferences(baseSpeed: 60),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(20);
    expect(controller.statusLabel, 'Autoscroll ↓ 20×');
    controller.tick(const Duration(milliseconds: 100));
    controller.setSignedStep(-20);
    expect(controller.statusLabel, 'Autoscroll ↑ 20×');
    controller.tick(const Duration(milliseconds: 100));

    expect(identical(controller.scrollTarget, target), isTrue);
    expect(target.deltas, <double>[120, -120]);
    expect(target.offset, 0);
  });

  test('saved lower maximum remains a hard cap in accelerated bands', () {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(maximumStep: 10),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    for (var press = 0; press < 10; press++) {
      controller.increaseStep();
    }
    expect(controller.signedStep, 10);
    controller.decreaseStep();
    expect(controller.signedStep, 5);
  });

  test('60x requests the full configured scan rate', () {
    final controller = MacReaderAutoScrollController(
      scrollTarget: _Target(),
      preferences: const MacAutoscrollPreferences(baseSpeed: 60),
      driveFrames: false,
    );
    addTearDown(controller.dispose);

    controller.setSignedStep(60);
    expect(controller.pixelsPerSecond, 3600);
    expect(controller.statusLabel, 'Autoscroll ↓ 60×');
  });
}
