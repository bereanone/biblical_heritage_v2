import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/synthesis_thermal_gate.dart';
import 'package:studybible2/core/audio/synthesis_governor.dart';
import 'package:studybible2/core/audio/speech_engine.dart';

void main() {
  test(
    'thermal pause overrides catch-up; resumes after sustained cool period',
    () async {
      var now = DateTime(2026);
      var level = 2;
      final changes = <bool>[];
      final gate = SynthesisThermalGate(
        mobile: true,
        now: () => now,
        read: () async => {'level': level},
        delay: (duration) async {
          now = now.add(duration);
          if (now.difference(DateTime(2026)).inSeconds >= 10) level = 0;
        },
      );
      gate.waitingForTemperature.addListener(
        () => changes.add(gate.waitingForTemperature.value),
      );
      var jobs = 0;
      final governor = SynthesisGovernor(
        isThrottled: () => true,
        lead: () => Duration.zero,
        beforeJob: gate.beforeJob,
        afterJob: gate.afterJob,
        now: () => now,
      );
      await governor.run(() async {
        jobs++;
      });
      expect(jobs, 1);
      expect(
        now.difference(DateTime(2026)).inSeconds,
        greaterThanOrEqualTo(70),
      );
      expect(changes, [true, false]);
    },
  );
  test('warm, missing and NaN-like samples stay conservative', () {
    final gate = SynthesisThermalGate(mobile: true, read: () async => null);
    expect(gate.duty, .25);
    gate.update({'level': 1});
    expect(gate.duty, .2);
    gate.update({'level': double.nan});
    expect(gate.duty, .25);
    gate.update({'level': 0});
    expect(gate.duty, .5);
  });
  test('hot latch does not clear for missing sensors or intermittent cool', () {
    var now = DateTime(2026);
    final gate = SynthesisThermalGate(
      mobile: true,
      read: () async => null,
      now: () => now,
    );
    gate.update({'level': 2});
    gate.update({'level': 0});
    now = now.add(const Duration(seconds: 30));
    gate.update(null);
    now = now.add(const Duration(minutes: 5));
    expect(gate.paused, isTrue);
    gate.update({'level': 0});
    expect(gate.paused, isTrue);
  });
  test(
    'unknown sensor pacing cannot be bypassed by a starving listener',
    () async {
      var now = DateTime(2026);
      final gate = SynthesisThermalGate(
        mobile: true,
        now: () => now,
        read: () async => throw StateError('unsupported'),
        delay: (wait) async => now = now.add(wait),
      );
      final starts = <DateTime>[];
      final governor = SynthesisGovernor(
        isThrottled: () => true,
        lead: () => Duration.zero,
        beforeJob: gate.beforeJob,
        afterJob: gate.afterJob,
        now: () => now,
      );
      Future<void> job() async {
        starts.add(now);
        now = now.add(const Duration(seconds: 2));
      }

      await governor.run(job);
      await governor.run(job);
      expect(starts[1].difference(starts[0]), const Duration(seconds: 8));
    },
  );
  test(
    'Stop cancels a cooling job without synthesizing or wedging queue',
    () async {
      var cancelled = false;
      var jobs = 0;
      final gate = SynthesisThermalGate(
        mobile: true,
        read: () async => {'level': 2},
        delay: (_) async {
          cancelled = true;
        },
      );
      final governor = SynthesisGovernor(
        isThrottled: () => false,
        beforeJob: gate.beforeJob,
      );
      await expectLater(
        governor.run(() async {
          jobs++;
        }, cancelled: () => cancelled),
        throwsA(isA<SpeechSynthesisCancelled>()),
      );
      expect(jobs, 0);
      expect(gate.waitingForTemperature.value, isFalse);
    },
  );
  test('a long sample gap cannot count as a continuous cooldown', () {
    var now = DateTime(2026);
    final gate = SynthesisThermalGate(
      mobile: true,
      read: () async => null,
      now: () => now,
    );
    gate.update({'level': 2});
    gate.update({'level': 0});
    now = now.add(const Duration(minutes: 5));
    gate.update({'level': 0});
    expect(gate.paused, isTrue);
  });

  test(
    'concurrent callers await the same sensor read before inference',
    () async {
      final snapshot = Completer<Map<String, dynamic>?>();
      var reads = 0;
      var cancelled = false;
      final gate = SynthesisThermalGate(
        mobile: true,
        read: () {
          reads++;
          return snapshot.future;
        },
        delay: (_) async {
          cancelled = true;
        },
      );
      var finished = 0;
      final first = gate.beforeJob(() => cancelled).then((_) {
        finished++;
      });
      final second = gate.beforeJob(() => cancelled).then((_) {
        finished++;
      });
      final results = Future.wait([
        expectLater(first, throwsA(isA<SpeechSynthesisCancelled>())),
        expectLater(second, throwsA(isA<SpeechSynthesisCancelled>())),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(finished, 0);
      expect(reads, 1);
      snapshot.complete({'level': 2});
      await results;
      expect(finished, 0);
      expect(gate.waitingForTemperature.value, isFalse);
    },
  );

  test('desktop bypasses mobile sensing', () async {
    final gate = SynthesisThermalGate(
      mobile: false,
      read: () async => throw StateError('must not read'),
    );
    await gate.beforeJob();
    expect(gate.duty, 1);
  });
}
