import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'speech_engine.dart';
import 'narration_diagnostics.dart';

/// Policy values are conservative workload limits, not temperature promises.
/// Unknown sensors remain paced. A hot latch requires positive cool readings.
class SynthesisThermalGate {
  SynthesisThermalGate({
    required this.read,
    required this.mobile,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.cooldown = const Duration(seconds: 60),
    this.freshFor = const Duration(seconds: 15),
    this.log,
  }) : _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  static const _methods = MethodChannel('studybible/narration_thermal');
  static const _events = EventChannel('studybible/narration_thermal_events');
  static final instance = SynthesisThermalGate(
    mobile: Platform.isIOS || Platform.isAndroid,
    read: () async =>
        await _methods.invokeMapMethod<String, dynamic>('snapshot'),
    log: NarrationDiagnostics.log,
  );
  final ValueNotifier<bool> waitingForTemperature = ValueNotifier(false);
  final bool mobile;
  final Future<Map<String, dynamic>?> Function() read;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final Duration cooldown;
  final Duration freshFor;
  final void Function(String)? log;
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;
  int _temperatureWaiters = 0;
  DateTime? _sampled;
  DateTime? _coolSince;
  DateTime? _lastRead;
  Future<void>? _refreshing;
  bool _hot = false;
  int? _level;
  DateTime? _notBefore;

  void start() {
    if (_started || !mobile) return;
    _started = true;
    _subscription = _events.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) update(Map<String, dynamic>.from(event));
      },
      onError: (Object error) {
        update(null);
      },
    );
  }

  /// Normalized levels: 0 cool, 1 warm, 2 pause (iOS serious,
  /// Android moderate or predicted headroom >= .85).
  void update(Map<String, dynamic>? sample) {
    final raw = sample?['level'];
    final level = raw is int && raw >= 0 && raw <= 2 ? raw : null;
    if (_sampled != null && _now().difference(_sampled!) > freshFor) {
      _coolSince = null;
    }
    final old = _level;
    _level = level;
    _sampled = _now();
    if (level == 2) {
      _hot = true;
      _coolSince = null;
    } else if (_hot && level == 0) {
      _coolSince ??= _now();
    } else {
      _coolSince = null;
    }
    if (old != level) log?.call('synth thermal level=$level hot=$_hot');
  }

  double get duty {
    if (!mobile) return 1;
    if (_sampled == null || _now().difference(_sampled!) > freshFor) return .25;
    return _level == 0
        ? .5
        : _level == 1
        ? .2
        : .25;
  }

  bool get paused {
    if (!_hot) return false;
    if (_level == 0 &&
        _coolSince != null &&
        _sampled != null &&
        _now().difference(_sampled!) <= freshFor &&
        _now().difference(_coolSince!) >= cooldown) {
      _hot = false;
      log?.call('synth thermal cooldown complete');
      return false;
    }
    return true;
  }

  Future<void> _refresh() async {
    final current = _refreshing;
    if (current != null) return current;
    if (_lastRead != null &&
        _now().difference(_lastRead!) < const Duration(seconds: 5)) {
      return;
    }
    _lastRead = _now();
    final pending = _readSnapshot();
    _refreshing = pending;
    try {
      await pending;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _readSnapshot() async {
    try {
      update(await read().timeout(const Duration(seconds: 2)));
    } catch (_) {
      update(null);
    }
  }

  /// Separate from playback and lead catch-up: neither can bypass this gate.
  Future<void> beforeJob([bool Function()? cancelled]) async {
    if (!mobile) return;
    await _refresh();
    var announced = false;
    try {
      while (true) {
        if (cancelled?.call() ?? false) throw const SpeechSynthesisCancelled();
        final wait = _notBefore?.difference(_now()) ?? Duration.zero;
        if (paused && !announced) {
          announced = true;
          _temperatureWaiters++;
          waitingForTemperature.value = true;
        }
        if (!paused && wait <= Duration.zero) return;
        await _delay(const Duration(seconds: 2));
        await _refresh();
      }
    } finally {
      if (announced) {
        _temperatureWaiters--;
        waitingForTemperature.value = _temperatureWaiters > 0;
      }
    }
  }

  void afterJob(Duration busy) {
    if (!mobile) return;
    // At least 1 s idle, even for short chunks; warm/unknown never catch up.
    final idle = busy * (1 / duty - 1);
    _notBefore = _now().add(
      idle < const Duration(seconds: 1) ? const Duration(seconds: 1) : idle,
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
