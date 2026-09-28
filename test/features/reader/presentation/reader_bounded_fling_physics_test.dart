import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/reader/presentation/reader_bounded_fling_physics.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_preferences.dart';

void main() {
  test('finger fling momentum is capped in both directions', () {
    const physics = ReaderBoundedFlingPhysics();
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 20000,
      pixels: 10000,
      viewportDimension: 800,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 3,
    );
    for (final sign in <double>[-1, 1]) {
      final capped = physics.createBallisticSimulation(
        metrics,
        sign * ReaderBoundedFlingPhysics.maximumFlingPixelsPerSecond,
      );
      final extreme = physics.createBallisticSimulation(metrics, sign * 20000);
      expect(capped, isNotNull);
      expect(extreme, isNotNull);
      expect(extreme!.dx(0), closeTo(capped!.dx(0), 0.01));
    }
  });

  test('iPhone Bible tilt cap bounds even a high saved sensitivity', () {
    const settings = ReaderTiltAutoScrollSettings(
      maximumSpeedPixelsPerSecond: 240,
      hardSafetyCapPixelsPerSecond: 240,
    );
    final forward = readerTiltSpeedForPreferences(
      1,
      settings,
      const ReaderTiltPreferences(speedMultiplier: 4),
    );
    final reverse = readerTiltSpeedForPreferences(
      -1,
      settings,
      const ReaderTiltPreferences(speedMultiplier: 4),
    );
    expect(forward, 240);
    expect(reverse, -240);
  });
}
