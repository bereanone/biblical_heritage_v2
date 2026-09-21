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
    if (speech.audioEnabled && tilt.isActive) {
      unawaited(tilt.stop());
    }
  }

  void dispose() {
    speech.removeListener(_changed);
  }
}
