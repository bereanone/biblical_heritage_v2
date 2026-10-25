import 'package:flutter/foundation.dart';

/// Mobile playback consumes recordings; short note saves are the sole mobile
/// generation task. Book generation is available on Windows and Mac.
class LocalNarrationPolicy {
  static bool get savedPlaybackOnly =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  static bool get canGenerateBooks =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  // Bounds preparation of one saved note, including any spoken title. These
  // are work limits, not a guarantee of temperature or rendering duration.
  static const maxMobileNoteCharacters = 1600;
  static const maxNoteChunkCharacters = 320;

  static double noteSynthesisSpeed(double speed) =>
      savedPlaybackOnly ? 1 : speed;
}

class SavedAudioUnavailable implements Exception {
  const SavedAudioUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}
