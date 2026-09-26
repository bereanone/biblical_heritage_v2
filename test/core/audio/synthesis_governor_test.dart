import 'package:flutter_test/flutter_test.dart';
import 'package:studybible2/core/audio/synthesis_governor.dart';

void main() {
  late DateTime clock;
  late bool throttled;
  late SynthesisGovernor governor;
  final logs = <String>[];

  Future<int> job(int id, int busyMs, List<String> starts) async {
    starts.add('$id@${clock.millisecondsSinceEpoch}');
    clock = clock.add(Duration(milliseconds: busyMs));
    return id;
  }

  setUp(() {
    clock = DateTime.fromMillisecondsSinceEpoch(1000000);
    throttled = true;
    logs.clear();
    governor = SynthesisGovernor(
      isThrottled: () => throttled,
      duty: 0.5,
      log: logs.add,
      now: () => clock,
      delay: (wait) async => clock = clock.add(wait),
    );
  });

  test('foreground jobs run back to back', () async {
    throttled = false;
    final starts = <String>[];
    final t0 = clock.millisecondsSinceEpoch;
    await governor.run(() => job(3, 5000, starts));
    await governor.run(() => job(4, 5000, starts));
    expect(starts, ['3@$t0', '4@${t0 + 5000}']);
    expect(logs, isEmpty);
  });

  test('throttled jobs leave idle time so busy share is the duty', () async {
    final starts = <String>[];
    final t0 = clock.millisecondsSinceEpoch;
    await governor.run(() => job(1, 4000, starts));
    await governor.run(() => job(2, 4000, starts));
    await governor.run(() => job(3, 4000, starts));
    // duty 0.5: each 4 s job is followed by 4 s idle.
    expect(starts, ['1@$t0', '2@${t0 + 8000}', '3@${t0 + 16000}']);
    final busy = 12000;
    final elapsed = clock.millisecondsSinceEpoch - t0;
    expect(busy / elapsed, closeTo(0.6, 0.01)); // last job has no trailing idle
    expect(logs.last, contains('waited=4000ms'));
  });

  test('queued jobs run in order, one at a time', () async {
    final starts = <String>[];
    final results = await Future.wait([
      governor.run(() => job(1, 1000, starts)),
      governor.run(() => job(2, 1000, starts)),
      governor.run(() => job(3, 1000, starts)),
    ]);
    expect(results, [1, 2, 3]);
    expect(starts.map((s) => s.split('@').first), ['1', '2', '3']);
  });

  test(
    'a failing job reports its error and does not stall the queue',
    () async {
      final failed = governor.run<int>(() => throw StateError('boom'));
      final after = governor.run(() => Future.value(7));
      await expectLater(failed, throwsStateError);
      expect(await after, 7);
    },
  );

  test('leaving the background stops pacing', () async {
    final starts = <String>[];
    final t0 = clock.millisecondsSinceEpoch;
    await governor.run(() => job(1, 4000, starts));
    throttled = false;
    await governor.run(() => job(2, 4000, starts));
    expect(starts, ['1@$t0', '2@${t0 + 4000}']);
  });

  group('lead-aware pacing', () {
    late Duration? lead;

    SynthesisGovernor leadAware() => SynthesisGovernor(
      isThrottled: () => throttled,
      duty: 0.5,
      lead: () => lead,
      log: logs.add,
      now: () => clock,
      delay: (wait) async => clock = clock.add(wait),
    );

    test('a healthy lead keeps the throttle', () async {
      lead = const Duration(seconds: 60);
      governor = leadAware();
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 4000, starts));
      await governor.run(() => job(2, 4000, starts));
      expect(starts, ['1@$t0', '2@${t0 + 8000}']);
      expect(logs.last, contains('waited=4000ms'));
      expect(logs.last, contains('lead=60.0s'));
    });

    test('a low lead runs flat out and owes no idle time', () async {
      lead = const Duration(seconds: 10);
      governor = leadAware();
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 4000, starts));
      await governor.run(() => job(2, 4000, starts));
      expect(starts, ['1@$t0', '2@${t0 + 4000}']);
      expect(logs.first, contains('synth catch-up begin lead=10.0s'));
      expect(
        logs.where((l) => l.startsWith('synth catch-up busy')),
        hasLength(2),
      );
    });

    test('an empty lead, a clip being awaited, is the same as low', () async {
      lead = Duration.zero;
      governor = leadAware();
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 4000, starts));
      await governor.run(() => job(2, 4000, starts));
      expect(starts.last, '2@${t0 + 4000}');
    });

    test(
      'catch-up holds until the lead is rebuilt, then pacing resumes',
      () async {
        lead = const Duration(seconds: 10);
        governor = leadAware();
        final starts = <String>[];
        final t0 = clock.millisecondsSinceEpoch;
        await governor.run(() => job(1, 4000, starts));
        lead = const Duration(seconds: 40); // above 30 s but below 45 s
        await governor.run(() => job(2, 4000, starts));
        expect(
          starts.last,
          '2@${t0 + 4000}',
          reason: 'hysteresis: still catching up',
        );
        lead = const Duration(seconds: 50);
        await governor.run(() => job(3, 4000, starts));
        expect(logs, contains('synth catch-up end lead=50.0s'));
        await governor.run(() => job(4, 4000, starts));
        // Job 3 ran paced and owes 4 s idle before job 4.
        expect(starts.last, '4@${t0 + 8000 + 4000 + 4000}');
      },
    );

    test('a lead that falls during an idle ends the idle early', () async {
      lead = const Duration(seconds: 60);
      var idles = 0;
      governor = SynthesisGovernor(
        isThrottled: () => throttled,
        duty: 0.5,
        lead: () => lead,
        log: logs.add,
        now: () => clock,
        delay: (wait) async {
          clock = clock.add(wait);
          if (++idles == 2) lead = const Duration(seconds: 5);
        },
      );
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 10000, starts)); // owes 10 s idle
      await governor.run(() => job(2, 1000, starts));
      // Two 1 s polls, then the lead collapsed and the job ran at once.
      expect(starts.last, '2@${t0 + 10000 + 2000}');
    });

    test('nobody listening keeps the throttle', () async {
      lead = null;
      governor = leadAware();
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 4000, starts));
      await governor.run(() => job(2, 4000, starts));
      expect(starts.last, '2@${t0 + 8000}');
    });

    test('the foreground is never paced whatever the lead', () async {
      throttled = false;
      lead = const Duration(seconds: 90);
      governor = leadAware();
      final starts = <String>[];
      final t0 = clock.millisecondsSinceEpoch;
      await governor.run(() => job(1, 4000, starts));
      await governor.run(() => job(2, 4000, starts));
      expect(starts.last, '2@${t0 + 4000}');
      expect(logs, isEmpty);
    });
  });
}
