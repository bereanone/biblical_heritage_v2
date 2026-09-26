import 'package:flutter/foundation.dart';

/// What one finished synthesis job cost. [wall] is time inside the engine,
/// not time spent waiting behind the governor.
@immutable
class SynthesisJobStats {
  const SynthesisJobStats({
    required this.engineId,
    required this.engineJob,
    required this.chars,
    required this.audioSeconds,
    required this.wall,
  });

  /// Which engine (isolate) ran it, counting from 1 since the app started.
  final int engineId;

  /// This job's position on that engine, counting from 1.
  final int engineJob;
  final int chars;
  final double audioSeconds;
  final Duration wall;

  /// Wall seconds per audio second. Under 1.0 synthesis outruns playback;
  /// the measured norm on an iPhone 15 Plus is about 0.56.
  double get ratio =>
      audioSeconds <= 0 ? 0 : wall.inMilliseconds / 1000 / audioSeconds;
}

/// Notices when synthesis has become pathologically slow and asks for one
/// engine rebuild, then reports whether the fresh engine is fast. That tells
/// an engine-specific slowdown (memory, a degraded isolate) from a
/// device-wide one (thermal, iOS demoting the process), which no amount of
/// rebuilding can fix.
///
/// Slow means [slowRatio] or worse for [slowJobsToAct] jobs in a row. At
/// 1.5 synthesis is well over twice its norm and cannot keep pace with
/// playback even with no pacing at all. Three in a row rules out one long
/// verse. Clips under [minAudioSeconds] are ignored: fixed per-call overhead
/// dominates them.
///
/// It never rebuilds in a loop: after one rebuild it stays quiet until
/// [healthyJobsToRearm] consecutive jobs come in under [healthyRatio].
class SynthesisHealthMonitor {
  SynthesisHealthMonitor({
    this.slowRatio = 1.5,
    this.slowJobsToAct = 3,
    this.minAudioSeconds = 2.0,
    this.healthyRatio = 1.0,
    this.healthyJobsToRearm = 3,
    this.verdictJobs = 3,
    required void Function(String message) log,
  }) : _log = log;

  final double slowRatio;
  final int slowJobsToAct;
  final double minAudioSeconds;
  final double healthyRatio;
  final int healthyJobsToRearm;
  final int verdictJobs;
  final void Function(String message) _log;

  /// Set by the engine host: replaces the engine. Called at most once per
  /// slowdown.
  void Function(String reason)? onRebuild;

  final List<double> _slow = [];
  int _healthy = 0;
  bool _rebuilt = false;
  bool _saidNoRetry = false;
  int? _rebuiltFrom;
  double _ratioBefore = 0;
  final List<double> _fresh = [];

  void record(SynthesisJobStats job) {
    if (job.audioSeconds < minAudioSeconds) return;
    // A straggler from the engine already condemned says nothing new.
    if (job.engineId == _rebuiltFrom) return;
    final ratio = job.ratio;
    if (_rebuiltFrom != null) {
      _fresh.add(ratio);
      if (_fresh.length >= verdictJobs) _verdict(job.engineId);
    }
    if (ratio >= slowRatio) {
      _slow.add(ratio);
      _healthy = 0;
      if (_slow.length >= slowJobsToAct) _actOn(job);
      return;
    }
    _slow.clear();
    if (ratio >= healthyRatio) {
      _healthy = 0;
      return;
    }
    if (++_healthy >= healthyJobsToRearm && (_rebuilt || _saidNoRetry)) {
      _log('synth health: recovered; a further slowdown may rebuild again');
      _rebuilt = false;
      _saidNoRetry = false;
    }
  }

  void _actOn(SynthesisJobStats job) {
    final mean = _slow.reduce((a, b) => a + b) / _slow.length;
    final summary =
        '${_slow.length} jobs in a row at ${mean.toStringAsFixed(2)}x real '
        'time (norm 0.56x) on engine #${job.engineId}';
    _slow.clear();
    if (_rebuilt) {
      if (!_saidNoRetry) {
        _saidNoRetry = true;
        _log(
          'synth health: still slow after a rebuild ($summary); not '
          'rebuilding again until it recovers',
        );
      }
      return;
    }
    _rebuilt = true;
    _rebuiltFrom = job.engineId;
    _ratioBefore = mean;
    _fresh.clear();
    _log(
      'synth health: PATHOLOGICALLY SLOW, $summary; rebuilding the engine '
      'once',
    );
    onRebuild?.call(summary);
  }

  void _verdict(int freshEngine) {
    _fresh.sort();
    final median = _fresh[_fresh.length ~/ 2];
    final fast = median < slowRatio;
    _log(
      'synth health: VERDICT fresh engine #$freshEngine median '
      '${median.toStringAsFixed(2)}x over ${_fresh.length} jobs vs '
      '${_ratioBefore.toStringAsFixed(2)}x before: '
      '${fast ? 'FAST, the slowdown was engine-specific (memory, isolate state)' : 'SLOW, the slowdown is device-wide (thermal, QoS or OS throttling), not the engine'}',
    );
    _rebuiltFrom = null;
    _fresh.clear();
  }
}
