// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/synthesis_job_probe.dart';

class _FakeDevice implements NarrationDeviceProbe {
  double cpu = 100;
  final requests = <bool>[];

  @override
  Future<DeviceSample?> sample({bool threads = false}) async {
    requests.add(threads);
    final reading = cpu;
    if (!threads) cpu += 30; // The mid-job thread sample is not a job edge.
    return DeviceSample(
      cpuSeconds: reading,
      state: 'thermal=1(fair) lpm=off battery=82%',
      threads: threads ? '[qos=default pri=31/31 cpu=90% run]' : null,
    );
  }
}

void main() {
  test('writes one render line with timings, CPU, state and threads', () {
    fakeAsync((async) {
      final lines = <String>[];
      final device = _FakeDevice();
      final clock = async.getClock(DateTime(2026, 9, 21));
      final probe = SynthesisJobProbe(
        engineId: 3,
        log: lines.add,
        device: device,
        context: () => 'lead=21.4s',
        now: clock.now,
      );
      final run = probe.begin(chars: 153);
      async.elapse(
        const Duration(seconds: 6),
      ); // past the mid-job thread sample
      final stats = run.finish(9.0);
      async.flushMicrotasks();

      expect(stats.ratio, closeTo(0.667, 0.01));
      expect(device.requests, [false, true, false]);
      expect(lines, hasLength(1));
      final line = lines.single;
      expect(line, contains('engine=#3'));
      expect(line, contains('job=1 FIRST-AFTER-START'));
      expect(
        line,
        contains('chars=153 audio=9.0s wall=6.0s (0.67x real time)'),
      );
      expect(line, contains('cpu=30.0s (5.00 cores, 3.33 cpu-s per audio-s)'));
      expect(line, contains('thermal=1(fair) lpm=off battery=82%'));
      expect(line, contains('lead=21.4s'));
      expect(line, contains('threads=[qos=default pri=31/31 cpu=90% run]'));
    });
  });

  test('only the first job on an engine is marked', () {
    fakeAsync((async) {
      final lines = <String>[];
      final probe = SynthesisJobProbe(engineId: 1, log: lines.add);
      probe.begin(chars: 10).finish(5);
      probe.begin(chars: 10).finish(5);
      async.flushMicrotasks();
      expect(lines[0], contains('FIRST-AFTER-START'));
      expect(lines[1], isNot(contains('FIRST-AFTER-START')));
      expect(lines[1], contains('job=2'));
    });
  });

  test('works with no device bridge', () {
    fakeAsync((async) {
      final lines = <String>[];
      final probe = SynthesisJobProbe(engineId: 1, log: lines.add);
      final stats = probe.begin(chars: 40).finish(4);
      async.flushMicrotasks();
      expect(stats.audioSeconds, 4);
      expect(lines.single, isNot(contains('cpu=')));
    });
  });

  test('a job abandoned mid-way writes nothing', () {
    fakeAsync((async) {
      final lines = <String>[];
      final device = _FakeDevice();
      final probe = SynthesisJobProbe(
        engineId: 1,
        log: lines.add,
        device: device,
      );
      probe.begin(chars: 40).abandon();
      async.elapse(const Duration(seconds: 10));
      expect(lines, isEmpty);
      expect(device.requests, [
        false,
      ], reason: 'no thread sample after abandon');
    });
  });
}
