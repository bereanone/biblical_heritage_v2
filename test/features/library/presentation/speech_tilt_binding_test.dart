import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/features/library/presentation/speech_tilt_binding.dart';
import 'package:studybible2/features/library/presentation/mac_reader_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_autoscroll_controller.dart';
import 'package:studybible2/features/library/presentation/reader_tilt_motion_source.dart';

void main() {
  testWidgets('audio uses buttons and chosen speed, never starts motion', (
    tester,
  ) async {
    final target = CallbackReaderAutoScrollTarget();
    final motion = FakeReaderTiltMotionSource();
    final tilt = ReaderTiltAutoScrollController(
      motionSource: motion,
      scrollTarget: target,
    );
    final speech = MacReaderAutoScrollController(
      scrollTarget: target,
      narrationControlsPacing: true,
      preferences: const MacAutoscrollPreferences(audioEnabled: true),
    );
    final rates = <double>[];
    final binding = SpeechTiltBinding(speech, tilt, rates.add);
    speech.setSignedStep(1);
    await tester.pump();
    expect(speech.isScrolling, isTrue);
    expect(tilt.isActive, isFalse);
    speech.setSpeechRate(1.25);
    expect(rates.last, 1.25);
    speech.stopForManualInteraction();
    speech.setSignedStep(1);
    expect(speech.speechRate, 1.25);
    expect(tilt.isActive, isFalse);
    speech.stopForManualInteraction();
    binding.dispose();
    speech.dispose();
    tilt.dispose();
    await tester.pump();
  });
  testWidgets('turning audio on stops existing silent tilt', (tester) async {
    final target = CallbackReaderAutoScrollTarget();
    final tilt = ReaderTiltAutoScrollController(
      motionSource: FakeReaderTiltMotionSource(),
      scrollTarget: target,
    );
    final speech = MacReaderAutoScrollController(
      scrollTarget: target,
      narrationControlsPacing: true,
    );
    final binding = SpeechTiltBinding(speech, tilt, (_) {});
    await tilt.activate();
    expect(tilt.isActive, isTrue);
    speech.updatePreferences(
      const MacAutoscrollPreferences(audioEnabled: true, speechRate: 1.2),
    );
    expect(tilt.isActive, isFalse);
    expect(speech.speechRate, 1.2);
    binding.dispose();
    speech.dispose();
    tilt.dispose();
    await tester.pump();
  });
}
