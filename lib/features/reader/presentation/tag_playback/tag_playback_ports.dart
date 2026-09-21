import 'tag_playback_models.dart';

/// Turns a clip into an audio file. Synthesis cannot be aborted once started,
/// so the controller treats a cancelled render as "discard the file when it
/// eventually arrives".
abstract class TagClipRenderer {
  /// Returns the path of a freshly written audio file. The controller owns it
  /// and hands it back to [discard] when done.
  Future<String> render(TagSpeechClip clip);

  /// Deletes a file returned by [render]. Must not throw.
  Future<void> discard(String path);
}

/// Plays rendered clips one after another.
abstract class TagClipPlayer {
  /// Fires once when the clip started by [play] finishes on its own.
  Stream<void> get completions;

  /// Hint that [path] will be played next, so the switch can be gapless.
  Future<void> prepareNext(String path);

  Future<void> play(String path);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}
