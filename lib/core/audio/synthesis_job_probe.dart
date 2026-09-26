import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'synthesis_health.dart';

/// One reading of the device and process, taken by the iOS side
/// (`NarrationTelemetry.swift`). Every field is best effort.
class DeviceSample {
  const DeviceSample({this.cpuSeconds, this.state, this.threads});

  /// Process CPU time (user + system, all threads) from `getrusage`.
  final double? cpuSeconds;

  /// Thermal state, Low Power Mode, battery, charging, RSS and physical
  /// footprint, already formatted for the log.
  final String? state;

  /// The busiest threads with the QoS class each requested and the priority
  /// the scheduler is actually giving it. Only when asked for.
  final String? threads;

  static DeviceSample? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return DeviceSample(
      cpuSeconds: (raw['cpu'] as num?)?.toDouble(),
      state: raw['state'] as String?,
      threads: raw['threads'] as String?,
    );
  }
}

abstract interface class NarrationDeviceProbe {
  Future<DeviceSample?> sample({bool threads = false});
}

class MethodChannelDeviceProbe implements NarrationDeviceProbe {
  MethodChannelDeviceProbe([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('studybible/narration_probe');

  final MethodChannel _channel;

  @override
  Future<DeviceSample?> sample({bool threads = false}) async {
    try {
      return DeviceSample.fromMap(
        await _channel
            .invokeMethod<Object>('sample', {'threads': threads})
            .timeout(const Duration(seconds: 2)),
      );
    } catch (_) {
      return null; // No bridge here, or the main thread was too busy to answer.
    }
  }
}

/// Measures each synthesis job and writes one `render job` line for it:
/// characters, audio seconds, wall seconds, CPU seconds from `getrusage`, the
/// device state, the listener's lead, and the QoS class and scheduler
/// priority of the busiest threads sampled mid-job.
///
/// The first job on every engine carries `FIRST-AFTER-START`, so a fresh
/// engine's speed is easy to find. CPU is process-wide and a job's end sample
/// arrives a few milliseconds late, so per-job CPU is approximate; it is the
/// CPU seconds per audio second that matters.
class SynthesisJobProbe {
  SynthesisJobProbe({
    required this.engineId,
    required void Function(String message) log,
    NarrationDeviceProbe? device,
    this.context,
    this.threadSampleAfter = const Duration(seconds: 2),
    DateTime Function()? now,
  }) : _log = log,
       _device = device ?? (Platform.isIOS ? MethodChannelDeviceProbe() : null),
       _now = now ?? DateTime.now,
       _born = (now ?? DateTime.now)();

  final int engineId;

  /// Extra text for each line, e.g. the current lead.
  final String Function()? context;

  /// Threads are sampled this far into a job, once they are all busy.
  final Duration threadSampleAfter;

  final void Function(String message) _log;
  final NarrationDeviceProbe? _device;
  final DateTime Function() _now;
  final DateTime _born;
  int _jobs = 0;

  SynthesisJobRun begin({required int chars}) {
    _jobs++;
    return SynthesisJobRun._(this, _jobs, chars);
  }

  String _age() {
    final age = _now().difference(_born);
    return age.inHours > 0
        ? '${age.inHours}h${(age.inMinutes % 60).toString().padLeft(2, '0')}m'
        : '${age.inMinutes}m${(age.inSeconds % 60).toString().padLeft(2, '0')}s';
  }
}

class SynthesisJobRun {
  SynthesisJobRun._(this._probe, this._job, this._chars)
    : _startedAt = _probe._now(),
      _start = _probe._device?.sample() {
    if (_probe._device != null) {
      _threadTimer = Timer(
        _probe.threadSampleAfter,
        () => _threads = _probe._device.sample(threads: true),
      );
    }
  }

  final SynthesisJobProbe _probe;
  final int _job;
  final int _chars;
  final DateTime _startedAt;
  final Future<DeviceSample?>? _start;
  Timer? _threadTimer;
  Future<DeviceSample?>? _threads;

  /// The job ended without audio (failed, timed out or was closed).
  void abandon() => _threadTimer?.cancel();

  /// The job produced [audioSeconds] of speech. Returns its stats at once and
  /// writes the log line when the device readings arrive.
  SynthesisJobStats finish(double audioSeconds) {
    _threadTimer?.cancel();
    final stats = SynthesisJobStats(
      engineId: _probe.engineId,
      engineJob: _job,
      chars: _chars,
      audioSeconds: audioSeconds,
      wall: _probe._now().difference(_startedAt),
    );
    final end = _probe._device?.sample();
    unawaited(_report(stats, end));
    return stats;
  }

  Future<void> _report(
    SynthesisJobStats stats,
    Future<DeviceSample?>? endSample,
  ) async {
    try {
      final start = await _start;
      final end = await endSample;
      final threads = await _threads;
      final seconds = stats.wall.inMilliseconds / 1000;
      final cpu = (start?.cpuSeconds != null && end?.cpuSeconds != null)
          ? end!.cpuSeconds! - start!.cpuSeconds!
          : null;
      final parts = <String>[
        'render job engine=#${stats.engineId} age=${_probe._age()} '
            'job=${stats.engineJob}'
            '${stats.engineJob == 1 ? ' FIRST-AFTER-START' : ''}',
        'chars=${stats.chars}',
        'audio=${stats.audioSeconds.toStringAsFixed(1)}s',
        'wall=${seconds.toStringAsFixed(1)}s '
            '(${stats.ratio.toStringAsFixed(2)}x real time)',
        if (cpu != null)
          'cpu=${cpu.toStringAsFixed(1)}s '
              '(${(seconds > 0 ? cpu / seconds : 0).toStringAsFixed(2)} cores, '
              '${(stats.audioSeconds > 0 ? cpu / stats.audioSeconds : 0).toStringAsFixed(2)} cpu-s per audio-s)',
        if (end?.state != null) end!.state!,
        if (_probe.context != null) _probe.context!(),
        if (threads?.threads != null) 'threads=${threads!.threads}',
      ];
      _probe._log(parts.join(' '));
    } catch (_) {
      /* Diagnostics must never disturb speech. */
    }
  }
}
