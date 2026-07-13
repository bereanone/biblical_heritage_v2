import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';

void main() {
  test('portrait uses roll for screen-horizontal tilt', () {
    final sample = readerTiltSampleForAttitude(
      pitchRadians: 0.2,
      rollRadians: 0.3,
      orientation: ReaderDeviceOrientation.portrait,
    );
    expect(sample.pitchRadians, 0.2);
    expect(sample.horizontalRadians, 0.3);
  });

  test('upside-down portrait reverses both screen axes', () {
    final sample = readerTiltSampleForAttitude(
      pitchRadians: 0.2,
      rollRadians: 0.3,
      orientation: ReaderDeviceOrientation.portraitUpsideDown,
    );
    expect(sample.pitchRadians, -0.2);
    expect(sample.horizontalRadians, -0.3);
  });

  test('landscape left maps pitch to screen-horizontal direction', () {
    final sample = readerTiltSampleForAttitude(
      pitchRadians: 0.2,
      rollRadians: 0.3,
      orientation: ReaderDeviceOrientation.landscapeLeft,
    );
    expect(sample.pitchRadians, 0.3);
    expect(sample.horizontalRadians, -0.2);
  });

  test('landscape right maps pitch with the opposite rotation', () {
    final sample = readerTiltSampleForAttitude(
      pitchRadians: 0.2,
      rollRadians: 0.3,
      orientation: ReaderDeviceOrientation.landscapeRight,
    );
    expect(sample.pitchRadians, -0.3);
    expect(sample.horizontalRadians, 0.2);
  });
}
