import 'dart:async';
import 'mac_reader_autoscroll_controller.dart';
import 'reader_tilt_autoscroll_controller.dart';

/// Keeps audio independent of phone motion; silent mode retains tilt scrolling.
class SpeechTiltBinding {
  SpeechTiltBinding(this.speech, this.tilt, this.onRate) {
    speech.addListener(_changed);
    _changed();
  }
  final MacReaderAutoScrollController speech;
  final ReaderTiltAutoScrollController tilt;
  final void Function(double) onRate;
  void _changed() {
    onRate(speech.speechRate);
    if (speech.isScrolling && tilt.isActive) {
      unawaited(tilt.stop());
    }
  }

  void dispose() {
    speech.removeListener(_changed);
  }
}

/// The motion button always means silent scrolling, regardless of the saved
/// Read aloud preference. Playback remains on the separate Play control.
Future<void> toggleSilentReaderTilt({
  required ReaderTiltAutoScrollController tilt,
  MacReaderAutoScrollController? speech,
}) async {
  if (tilt.isActive) {
    await tilt.stop();
    return;
  }
  speech?.stopForManualInteraction();
  await tilt.activate();
}
