import 'package:flutter/foundation.dart' show VoidCallback;

/// How much speech a narrator has already synthesized and not yet spoken: the
/// only thing standing between the listener and silence while synthesis is
/// slow or paced. Measured in listening seconds, so a clip synthesized at 1.0
/// and played at 1.4x counts for 1/1.4 of its audio length.
class ClipLead {
  ClipLead({required double Function() playbackRate, DateTime Function()? now})
    : _rate = playbackRate,
      _now = now ?? DateTime.now;

  final double Function() _rate;
  final DateTime Function() _now;

  final Map<String, double> _ready = {};
  double _playingSeconds = 0;
  DateTime? _playingSince;

  /// Clips that are synthesized and waiting their turn.
  int get readyClips => _ready.length;

  /// A finished clip that has not started playing yet.
  void ready(String clip, double audioSeconds) => _ready[clip] = audioSeconds;

  /// The clip left the cache without playing (evicted, or its file is gone).
  void forget(String clip) => _ready.remove(clip);

  /// [clip] began playing: it stops being lead and becomes the current clip.
  void started(String clip) {
    _playingSeconds = _ready.remove(clip) ?? 0;
    _playingSince = _now();
  }

  /// Nothing is playing any more (finished, paused, stopped).
  void stopped() {
    _playingSeconds = 0;
    _playingSince = null;
  }

  /// Listening time until the last synthesized clip runs out: what is left of
  /// the current clip plus every ready clip.
  Duration get duration {
    final rate = _rate() <= 0 ? 1.0 : _rate();
    var seconds = _ready.values.fold<double>(0, (sum, s) => sum + s) / rate;
    final since = _playingSince;
    if (since != null) {
      final elapsed = _now().difference(since).inMicroseconds / 1e6;
      final remaining = _playingSeconds / rate - elapsed;
      if (remaining > 0) seconds += remaining;
    }
    return Duration(microseconds: (seconds * 1e6).round());
  }

  /// For the event log, e.g. `3 clips 21.4s`.
  String describe() =>
      '$readyClips clips ${(duration.inMilliseconds / 1000).toStringAsFixed(1)}s';
}

/// The app-wide view of lead, for the synthesis governor. Each narrator that
/// is being listened to registers a reading; the governor watches the
/// smallest, because the listener who is closest to silence is the one to
/// protect.
class NarrationLeadRegistry {
  NarrationLeadRegistry();

  static final NarrationLeadRegistry instance = NarrationLeadRegistry();

  final List<Duration? Function()> _providers = [];

  /// Adds a reading and returns the callback that removes it. A reading is
  /// null while its narrator is not playing, so an idle narrator never holds
  /// the governor open.
  VoidCallback register(Duration? Function() reading) {
    _providers.add(reading);
    return () => _providers.remove(reading);
  }

  /// The smallest lead among narrators that are playing, or null when no one
  /// is listening (nothing can starve, so pacing is safe).
  Duration? lead() {
    Duration? smallest;
    for (final reading in _providers) {
      final value = reading();
      if (value == null) continue;
      if (smallest == null || value < smallest) smallest = value;
    }
    return smallest;
  }
}
