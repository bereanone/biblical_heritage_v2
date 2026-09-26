import 'dart:async';

/// Paces speech synthesis so a locked iPhone stays under iOS's background CPU
/// cap (`cpu_resource_fatal`: more than 80% averaged over 60 s kills the app).
///
/// Jobs run one at a time. While [isThrottled] is true, each job is followed
/// by idle time so synthesis is busy for at most [duty] of the wall clock;
/// otherwise jobs run back to back.
///
/// Pacing alone is a losing trade for a long listen: at the measured 0.56x
/// real-time synthesis speed a 50% duty makes clips about 11% slower than
/// they play, so the clips rendered ahead in the foreground drain and the
/// listener hears silence. Pacing is therefore lead-aware. [lead] reports how
/// much synthesized speech is left before silence (null when nobody is
/// listening). Below [starveBelow] the governor stops idling and synthesizes
/// flat out; it paces again once the lead has been rebuilt to [refillTo]. The
/// gap between the two is hysteresis, so it does not flip on every clip.
class SynthesisGovernor {
  SynthesisGovernor({
    required this.isThrottled,
    this.duty = 0.5,
    this.lead,
    this.starveBelow = const Duration(seconds: 30),
    this.refillTo = const Duration(seconds: 45),
    this.pollEvery = const Duration(seconds: 1),
    this.log,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : assert(duty > 0 && duty <= 1),
       assert(refillTo >= starveBelow),
       _now = now ?? DateTime.now,
       _delay = delay ?? ((wait) => Future<void>.delayed(wait));

  final bool Function() isThrottled;

  /// Largest share of wall time synthesis may be busy while throttled.
  final double duty;

  /// Synthesized speech left before silence, or null when no one is listening
  /// (nothing can starve then, so pacing is safe). Without it the governor
  /// paces unconditionally.
  final Duration? Function()? lead;

  /// Below this lead, pacing is suspended. It must cover the worst wait for
  /// the next clip while paced: the idle share (up to one job) plus the job
  /// itself, about 10 s each at the slowest normal clip, plus half again.
  final Duration starveBelow;

  /// Pacing resumes when the lead is rebuilt to this.
  final Duration refillTo;

  /// How often a paced wait re-reads [lead], so a lead that falls while the
  /// governor is idling ends the idle early.
  final Duration pollEvery;

  final void Function(String message)? log;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  Future<void> _tail = Future<void>.value();
  DateTime _notBefore = DateTime.fromMillisecondsSinceEpoch(0);
  bool _catchUp = false;

  /// True when pacing applies to the job that is about to run.
  bool _paced() {
    if (!isThrottled()) {
      _catchUp = false;
      return false;
    }
    final reading = lead?.call();
    if (reading == null) {
      _catchUp = false;
      return true;
    }
    if (!_catchUp && reading < starveBelow) {
      _catchUp = true;
      log?.call('synth catch-up begin lead=${_seconds(reading)}');
    } else if (_catchUp && reading >= refillTo) {
      _catchUp = false;
      log?.call('synth catch-up end lead=${_seconds(reading)}');
    }
    return !_catchUp;
  }

  static String _seconds(Duration value) =>
      '${(value.inMilliseconds / 1000).toStringAsFixed(1)}s';

  /// Runs [job] when it is its turn and, if paced, when its share of the
  /// budget allows. Errors from [job] reach the caller; they never stall the
  /// queue behind it.
  Future<T> run<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      final waitStart = _now();
      var paced = _paced();
      while (paced) {
        final remaining = _notBefore.difference(_now());
        if (remaining <= Duration.zero) break;
        // Poll only when there is a lead to watch; otherwise one wait will do.
        await _delay(
          lead == null || remaining < pollEvery ? remaining : pollEvery,
        );
        paced = _paced();
      }
      final waited = _now().difference(waitStart);
      final started = _now();
      try {
        done.complete(await job());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
      final finished = _now();
      final busy = finished.difference(started);
      // Idle time is owed only for work done under the throttle, so a burst
      // that ran flat out to keep ahead of playback does not delay the next.
      _notBefore = paced ? finished.add(busy * (1 / duty - 1)) : finished;
      final reading = lead?.call();
      final leadNote = reading == null ? '' : ' lead=${_seconds(reading)}';
      if (paced) {
        log?.call(
          'synth throttled busy=${busy.inMilliseconds}ms '
          'waited=${waited > Duration.zero ? waited.inMilliseconds : 0}ms '
          'duty=$duty$leadNote',
        );
      } else if (_catchUp) {
        log?.call('synth catch-up busy=${busy.inMilliseconds}ms$leadNote');
      }
    });
    return done.future;
  }
}
