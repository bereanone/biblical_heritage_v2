import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// One loaded text-to-speech engine (for Kokoro, a model in a background
/// isolate). It exists so the code that decides *when* an engine is alive
/// can be tested without loading a 325 MB model.
abstract interface class SpeechEngine {
  /// True once the engine can no longer synthesize: it was disposed, its
  /// isolate exited, or it was discarded after failing to answer.
  bool get isClosed;

  /// Throws [SpeechEngineUnavailableException] when the engine is gone or
  /// hung (the caller may retry on a fresh engine) and
  /// [SpeechEngineException] when the engine ran but could not speak this
  /// text (retrying would repeat the failure).
  Future<sherpa.GeneratedAudio> generate(String text, double speed);

  /// True if the engine answers within [timeout]. An engine that is busy
  /// synthesizing counts as answering; a hung synthesis is caught by
  /// [generate]'s own timeout.
  Future<bool> ping({Duration timeout = const Duration(seconds: 2)});

  /// Completes when the engine's isolate has gone and its model is freed.
  Future<void> get exited;

  void dispose();
}

/// The engine ran but could not speak this text.
class SpeechEngineException implements Exception {
  const SpeechEngineException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The engine is dead, closed or hung, not the text's fault. Retrying on a
/// fresh engine is reasonable.
class SpeechEngineUnavailableException extends SpeechEngineException {
  const SpeechEngineUnavailableException(super.message);
}

/// Optional cancellation while a job is queued or cooling; native inference
/// already in flight finishes its bounded chunk and can still be saved.
abstract interface class CancellableSpeechEngine {
  Future<sherpa.GeneratedAudio> generateCancellable(
    String text,
    double speed,
    bool Function() cancelled,
  );
}

class SpeechSynthesisCancelled implements Exception {
  const SpeechSynthesisCancelled();
}
