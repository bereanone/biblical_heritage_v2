import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ReaderDeviceOrientation {
  portrait,
  portraitUpsideDown,
  landscapeLeft,
  landscapeRight,
}

class ReaderTiltSample {
  const ReaderTiltSample({
    required this.pitchRadians,
    this.horizontalRadians = 0,
    required this.orientation,
  });

  final double pitchRadians;
  final double horizontalRadians;
  final ReaderDeviceOrientation orientation;
}

@visibleForTesting
ReaderTiltSample readerTiltSampleForAttitude({
  required double pitchRadians,
  required double rollRadians,
  required ReaderDeviceOrientation orientation,
}) {
  return switch (orientation) {
    ReaderDeviceOrientation.portrait => ReaderTiltSample(
      pitchRadians: pitchRadians,
      horizontalRadians: rollRadians,
      orientation: orientation,
    ),
    ReaderDeviceOrientation.portraitUpsideDown => ReaderTiltSample(
      pitchRadians: -pitchRadians,
      horizontalRadians: -rollRadians,
      orientation: orientation,
    ),
    ReaderDeviceOrientation.landscapeLeft => ReaderTiltSample(
      pitchRadians: rollRadians,
      horizontalRadians: -pitchRadians,
      orientation: orientation,
    ),
    ReaderDeviceOrientation.landscapeRight => ReaderTiltSample(
      pitchRadians: -rollRadians,
      horizontalRadians: pitchRadians,
      orientation: orientation,
    ),
  };
}

abstract interface class ReaderTiltMotionSource {
  bool get isSupported;
  Stream<ReaderTiltSample> start();
  Future<void> stop();
}

class PlatformReaderTiltMotionSource implements ReaderTiltMotionSource {
  static const _events = EventChannel('studybible/reader_tilt_motion');
  StreamSubscription<Object?>? _subscription;
  final StreamController<ReaderTiltSample> _samples =
      StreamController<ReaderTiltSample>.broadcast(sync: true);

  @override
  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Stream<ReaderTiltSample> start() {
    if (!isSupported) {
      return Stream<ReaderTiltSample>.error(
        UnsupportedError('Tilt motion is unavailable on this platform.'),
      );
    }
    _subscription ??= _events.receiveBroadcastStream().listen((event) {
      final map = Map<Object?, Object?>.from(event as Map);
      final attitudePitch = (map['attitudePitch'] as num?)?.toDouble();
      final attitudeRoll = (map['attitudeRoll'] as num?)?.toDouble();
      final orientationName = map['orientation'] as String?;
      if (attitudePitch == null ||
          attitudeRoll == null ||
          orientationName == null) {
        return;
      }
      final orientation = ReaderDeviceOrientation.values.firstWhere(
        (value) => value.name == orientationName,
        orElse: () => ReaderDeviceOrientation.portrait,
      );
      _samples.add(
        readerTiltSampleForAttitude(
          pitchRadians: attitudePitch,
          rollRadians: attitudeRoll,
          orientation: orientation,
        ),
      );
    }, onError: _samples.addError);
    return _samples.stream;
  }

  @override
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

/// Compatibility name for older call sites and tests.
@Deprecated('Use PlatformReaderTiltMotionSource')
class IosReaderTiltMotionSource extends PlatformReaderTiltMotionSource {}

class FakeReaderTiltMotionSource implements ReaderTiltMotionSource {
  FakeReaderTiltMotionSource({this.isSupported = true});

  @override
  final bool isSupported;
  final StreamController<ReaderTiltSample> _controller =
      StreamController<ReaderTiltSample>.broadcast(sync: true);
  int startCount = 0;
  int stopCount = 0;

  @override
  Stream<ReaderTiltSample> start() {
    startCount += 1;
    return _controller.stream;
  }

  void add(ReaderTiltSample sample) => _controller.add(sample);
  void addError(Object error) => _controller.addError(error);

  @override
  Future<void> stop() async => stopCount += 1;

  Future<void> dispose() => _controller.close();
}
