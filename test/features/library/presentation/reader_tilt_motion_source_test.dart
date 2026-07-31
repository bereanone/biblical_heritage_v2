import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';

// The iOS bridge (ios/Runner/AppDelegate.swift ReaderTiltMotionBridge) and the
// Android bridge (android/.../MainActivity.kt) both publish on this channel
// name using the identical attitudePitch/attitudeRoll/orientation keys. These
// tests exercise the real EventChannel decode path in
// PlatformReaderTiltMotionSource (not FakeReaderTiltMotionSource), so a future
// change that alters either native payload's shape — the kind of change made
// while wiring up Android support — fails here instead of silently breaking
// tilt on a real device.
const _motionChannel = MethodChannel('studybible/reader_tilt_motion');
const _motionCodec = StandardMethodCodec();

void _emitMotionEvent(Map<String, Object?> payload) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _motionChannel.name,
        _motionCodec.encodeSuccessEnvelope(payload),
        (ByteData? _) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_motionChannel, null);
  });

  test('platform source supports Android and iOS mobile sensors', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(PlatformReaderTiltMotionSource().isSupported, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(PlatformReaderTiltMotionSource().isSupported, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(PlatformReaderTiltMotionSource().isSupported, isFalse);
  });

  test('decodes the exact iOS native payload into a tilt sample', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_motionChannel, (call) async => null);

    final source = PlatformReaderTiltMotionSource();
    final samples = <ReaderTiltSample>[];
    final subscription = source.start().listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      await source.stop();
    });
    await Future<void>.delayed(Duration.zero);

    _emitMotionEvent({
      'attitudePitch': 0.35,
      'attitudeRoll': -0.12,
      'orientation': 'portrait',
    });
    await Future<void>.delayed(Duration.zero);

    expect(samples, hasLength(1));
    expect(samples.single.pitchRadians, 0.35);
    expect(samples.single.horizontalRadians, -0.12);
    expect(samples.single.orientation, ReaderDeviceOrientation.portrait);
  });

  test('decodes the exact Android native payload into a tilt sample', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_motionChannel, (call) async => null);

    final source = PlatformReaderTiltMotionSource();
    final samples = <ReaderTiltSample>[];
    final subscription = source.start().listen(samples.add);
    addTearDown(() async {
      await subscription.cancel();
      await source.stop();
    });
    await Future<void>.delayed(Duration.zero);

    // Shaped like MainActivity.kt's onSensorChanged: SensorManager.getOrientation
    // radians carried through the same attitudePitch/attitudeRoll keys as iOS.
    _emitMotionEvent({
      'attitudePitch': -0.41,
      'attitudeRoll': 0.08,
      'orientation': 'landscapeLeft',
    });
    await Future<void>.delayed(Duration.zero);

    expect(samples, hasLength(1));
    expect(samples.single.orientation, ReaderDeviceOrientation.landscapeLeft);
    // landscapeLeft maps pitch->horizontal and roll->pitch (see
    // readerTiltSampleForAttitude), identically for both platforms.
    expect(samples.single.pitchRadians, 0.08);
    expect(samples.single.horizontalRadians, 0.41);
  });

  test(
    'a malformed payload missing a key is dropped, not crashed on',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_motionChannel, (call) async => null);

      final source = PlatformReaderTiltMotionSource();
      final samples = <ReaderTiltSample>[];
      final subscription = source.start().listen(samples.add);
      addTearDown(() async {
        await subscription.cancel();
        await source.stop();
      });
      await Future<void>.delayed(Duration.zero);

      _emitMotionEvent({'attitudePitch': 0.1, 'attitudeRoll': 0.1});
      await Future<void>.delayed(Duration.zero);

      expect(samples, isEmpty);
    },
  );

  test(
    'start() called twice registers only one channel subscription',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final methodCounts = <String, int>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_motionChannel, (call) async {
            methodCounts[call.method] = (methodCounts[call.method] ?? 0) + 1;
            return null;
          });

      final source = PlatformReaderTiltMotionSource();
      final subscriptionA = source.start().listen((_) {});
      final subscriptionB = source.start().listen((_) {});
      addTearDown(() async {
        await subscriptionA.cancel();
        await subscriptionB.cancel();
        await source.stop();
      });
      await Future<void>.delayed(Duration.zero);

      expect(methodCounts['listen'], 1);
    },
  );

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
