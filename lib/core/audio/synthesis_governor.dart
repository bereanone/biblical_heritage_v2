import 'dart:async';

/// Paces speech synthesis so a locked iPhone stays under iOS's background CPU
/// cap (`cpu_resource_fatal`: more than 80% averaged over 60 s kills the app).
///
/// Jobs run one at a time. While [isThrottled] is true, each job is followed
/// by idle time so synthesis is busy for at most [duty] of the wall clock;
/// otherwise jobs run back to back. Narration plays clips that were rendered
/// ahead while the screen was on, so the pause between clips costs nothing
/// audible until that lead is used up.
class SynthesisGovernor {
  SynthesisGovernor({
    required this.isThrottled,
    this.duty = 0.5,
    this.log,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : assert(duty > 0 && duty <= 1),
       _now = now ?? DateTime.now,
       _delay = delay ?? ((wait) => Future<void>.delayed(wait));

  final bool Function() isThrottled;

  /// Largest share of wall time synthesis may be busy while throttled.
  final double duty;
  final void Function(String message)? log;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  Future<void> _tail = Future<void>.value();
  DateTime _notBefore = DateTime.fromMillisecondsSinceEpoch(0);

  /// Runs [job] when it is its turn and, if throttled, when its share of the
  /// budget allows. Errors from [job] reach the caller; they never stall the
  /// queue behind it.
  Future<T> run<T>(Future<T> Function() job) {
    final done = Completer<T>();
    _tail = _tail.then((_) async {
      var waited = Duration.zero;
      final throttled = isThrottled();
      if (throttled) {
        waited = _notBefore.difference(_now());
        if (waited > Duration.zero) await _delay(waited);
      }
      final started = _now();
      try {
        done.complete(await job());
      } catch (error, stack) {
        done.completeError(error, stack);
      }
      final finished = _now();
      final busy = finished.difference(started);
      _notBefore = finished.add(busy * (1 / duty - 1));
      if (throttled) {
        log?.call(
          'synth throttled busy=${busy.inMilliseconds}ms '
          'waited=${waited > Duration.zero ? waited.inMilliseconds : 0}ms '
          'duty=$duty',
        );
      }
    });
    return done.future;
  }
}
