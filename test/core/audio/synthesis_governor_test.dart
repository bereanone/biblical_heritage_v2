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
}
