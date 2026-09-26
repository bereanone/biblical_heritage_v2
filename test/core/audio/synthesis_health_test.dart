import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/synthesis_health.dart';

void main() {
  late List<String> logs;
  late List<String> rebuilds;
  late SynthesisHealthMonitor monitor;

  SynthesisJobStats job(int engine, double ratio, {double audio = 6}) =>
      SynthesisJobStats(
        engineId: engine,
        engineJob: 1,
        chars: 100,
        audioSeconds: audio,
        wall: Duration(milliseconds: (audio * ratio * 1000).round()),
      );

  setUp(() {
    logs = [];
    rebuilds = [];
    monitor = SynthesisHealthMonitor(log: logs.add)..onRebuild = rebuilds.add;
  });

  test('normal speed never acts', () {
    for (var i = 0; i < 20; i++) {
      monitor.record(job(1, 0.56));
    }
    expect(rebuilds, isEmpty);
    expect(logs, isEmpty);
  });

  test('two slow jobs are not enough, and one good job resets the count', () {
    monitor.record(job(1, 3));
    monitor.record(job(1, 3));
    monitor.record(job(1, 0.6));
    monitor.record(job(1, 3));
    monitor.record(job(1, 3));
    expect(rebuilds, isEmpty);
  });

  test('three slow jobs in a row rebuild the engine once', () {
    for (var i = 0; i < 3; i++) {
      monitor.record(job(1, 3.1));
    }
    expect(rebuilds, hasLength(1));
    expect(rebuilds.single, contains('engine #1'));
    expect(logs.single, contains('PATHOLOGICALLY SLOW'));
  });

  test('short clips are ignored', () {
    for (var i = 0; i < 10; i++) {
      monitor.record(job(1, 9, audio: 1));
    }
    expect(rebuilds, isEmpty);
  });

  test('a fast fresh engine means the slowdown was engine-specific', () {
    for (var i = 0; i < 3; i++) {
      monitor.record(job(1, 3));
    }
    for (var i = 0; i < 3; i++) {
      monitor.record(job(2, 0.6));
    }
    final verdict = logs.singleWhere((l) => l.contains('VERDICT'));
    expect(verdict, contains('FAST'));
    expect(verdict, contains('engine-specific'));
  });

  test('a slow fresh engine means device-wide, and never rebuilds again', () {
    for (var i = 0; i < 3; i++) {
      monitor.record(job(1, 3));
    }
    for (var i = 0; i < 12; i++) {
      monitor.record(job(2, 3));
    }
    expect(rebuilds, hasLength(1));
    expect(logs.where((l) => l.contains('VERDICT')).single, contains('SLOW'));
    expect(
      logs.where((l) => l.contains('VERDICT')).single,
      contains('device-wide'),
    );
    expect(logs.where((l) => l.contains('not rebuilding again')), hasLength(1));
  });

  test('stragglers from the condemned engine are ignored', () {
    for (var i = 0; i < 3; i++) {
      monitor.record(job(1, 3));
    }
    for (var i = 0; i < 6; i++) {
      monitor.record(job(1, 3));
    }
    expect(rebuilds, hasLength(1));
  });

  test('after a real recovery a later slowdown may rebuild again', () {
    for (var i = 0; i < 3; i++) {
      monitor.record(job(1, 3));
    }
    for (var i = 0; i < 6; i++) {
      monitor.record(job(2, 0.5));
    }
    expect(logs.any((l) => l.contains('recovered')), isTrue);
    for (var i = 0; i < 3; i++) {
      monitor.record(job(2, 3));
    }
    expect(rebuilds, hasLength(2));
  });
}
