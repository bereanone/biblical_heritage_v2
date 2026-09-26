import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:studybible2/core/audio/speech_engine.dart';
import 'package:studybible2/core/audio/synthesis_health.dart';
import 'package:studybible2/features/reader/presentation/kokoro_engine_host.dart';

/// Stands in for a loaded model so the host's lifecycle rules can be tested
/// without a 325 MB download.
class FakeEngine implements SpeechEngine {
  FakeEngine(this.id, {this.exitsOnDispose = true});

  final int id;
  final bool exitsOnDispose;
  bool closed = false;
  bool disposed = false;
  bool answersPing = true;
  final Completer<void> _exit = Completer<void>();

  void finishExiting() {
    if (!_exit.isCompleted) _exit.complete();
  }

  @override
  bool get isClosed => closed;

  @override
  Future<void> get exited => _exit.future;

  @override
  Future<sherpa.GeneratedAudio> generate(String text, double speed) async =>
      sherpa.GeneratedAudio(samples: Float32List(4), sampleRate: 24000);

  @override
  Future<bool> ping({Duration timeout = const Duration(seconds: 2)}) async =>
      !closed && answersPing;

  @override
  void dispose() {
    closed = true;
    disposed = true;
    if (exitsOnDispose) finishExiting();
  }
}

void main() {
  late List<FakeEngine> started;
  late List<String> log;
  late Future<SpeechEngine> Function() starter;

  KokoroEngineHost makeHost({Duration? idleRelease}) =>
      KokoroEngineHost.forTesting(
        starter: () => starter(),
        idleRelease: idleRelease,
        log: log.add,
      );

  setUp(() {
    started = [];
    log = [];
    starter = () async {
      final engine = FakeEngine(started.length + 1);
      started.add(engine);
      return engine;
    };
  });

  test(
    'play after the last lease was released starts a fresh engine',
    () async {
      final host = makeHost();

      final first = await host.acquire();
      expect(host.leaseCount, 1);
      host.release();
      expect(host.leaseCount, 0);
      expect(host.hasEngine, isFalse);
      expect((first as FakeEngine).disposed, isTrue);

      // The narrator the user presses play on leases again from cold.
      final second = await host.acquire();
      expect(second, isNot(same(first)));
      expect(started, hasLength(2));
      expect(await second.ping(), isTrue);
      expect(host.leaseCount, 1);
    },
  );

  test(
    'a narrator that holds a lease gets a fresh engine if its own died',
    () async {
      final host = makeHost();
      final first = await host.acquire() as FakeEngine;

      first.closed = true; // The isolate died while the app was idle.
      final again = await host.ensureLive();

      expect(again, isNot(same(first)));
      expect(started, hasLength(2));
      expect(host.leaseCount, 1, reason: 'replacing an engine keeps the lease');
      expect(log.join('\n'), contains('engine found closed; replacing'));
    },
  );

  test(
    'an engine that does not answer a ping is replaced, not trusted',
    () async {
      final host = makeHost();
      final first = await host.acquire() as FakeEngine;

      first.answersPing = false;
      final again = await host.ensureLive();

      expect(again, isNot(same(first)));
      expect(first.disposed, isTrue);
      expect(log.join('\n'), contains('did not answer a ping'));
    },
  );

  test('a healthy engine is reused, not restarted', () async {
    final host = makeHost();
    final first = await host.acquire();
    expect(await host.ensureLive(), same(first));
    expect(started, hasLength(1));
  });

  test('concurrent first leases share one start', () async {
    final host = makeHost();
    final engines = await Future.wait([host.acquire(), host.acquire()]);
    expect(engines[0], same(engines[1]));
    expect(started, hasLength(1));
    expect(host.leaseCount, 2);
  });

  test(
    'a start that fails leaves no lease and is retried by the next play',
    () async {
      final host = makeHost();
      var attempts = 0;
      starter = () async {
        attempts++;
        if (attempts == 1)
          throw const SpeechEngineException('load-model broke');
        final engine = FakeEngine(attempts);
        started.add(engine);
        return engine;
      };

      await expectLater(host.acquire(), throwsA(isA<SpeechEngineException>()));
      expect(host.leaseCount, 0);
      expect(log.join('\n'), contains('engine start FAILED'));

      final engine = await host.acquire();
      expect(await engine.ping(), isTrue);
      expect(host.leaseCount, 1);
    },
  );

  test('the next engine waits for the old isolate to free its model', () async {
    final host = makeHost();
    starter = () async {
      final engine = FakeEngine(started.length + 1, exitsOnDispose: false);
      started.add(engine);
      return engine;
    };
    final first = await host.acquire() as FakeEngine;
    host.release();

    var secondReady = false;
    final second = host.acquire().then((engine) {
      secondReady = true;
      return engine;
    });
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(started, hasLength(1), reason: 'old model still resident');
    expect(secondReady, isFalse);

    first.finishExiting();
    await second;
    expect(started, hasLength(2));
  });

  test('a stuck old isolate delays the restart but cannot block it', () async {
    final host = makeHost();
    starter = () async {
      final engine = FakeEngine(started.length + 1, exitsOnDispose: false);
      started.add(engine);
      return engine;
    };
    await host.acquire();
    host.release();

    await host.acquire(); // exitWait is 500 ms in tests.

    expect(started, hasLength(2));
    expect(log.join('\n'), contains('still running'));
  });

  group('idle release', () {
    test(
      'is off by default: the engine is freed when the last lease goes',
      () async {
        final host = makeHost();
        expect(host.idleRelease, isNull);
        final engine = await host.acquire() as FakeEngine;
        host.release();
        expect(engine.disposed, isTrue);
      },
    );

    test(
      'when set, keeps the engine through a short pause and reuses it',
      () async {
        final host = makeHost(idleRelease: const Duration(milliseconds: 150));
        final engine = await host.acquire() as FakeEngine;
        host.release();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(engine.disposed, isFalse);

        final again = await host.acquire();
        expect(again, same(engine));
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(engine.disposed, isFalse, reason: 'the new lease cancels it');
      },
    );

    test('when set, frees the engine after the idle time', () async {
      final host = makeHost(idleRelease: const Duration(milliseconds: 60));
      final engine = await host.acquire() as FakeEngine;
      host.release();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(engine.disposed, isTrue);
      expect(host.hasEngine, isFalse);

      final restarted = await host.acquire();
      expect(restarted, isNot(same(engine)));
    });
  });

  test(
    'pathologically slow synthesis replaces the engine once and warms the new '
    'one',
    () async {
      final health = SynthesisHealthMonitor(log: log.add);
      final host = KokoroEngineHost.forTesting(
        starter: () => starter(),
        health: health,
        log: log.add,
      );
      final first = await host.acquire() as FakeEngine;

      SynthesisJobStats slow(int engine) => SynthesisJobStats(
        engineId: engine,
        engineJob: 1,
        chars: 100,
        audioSeconds: 6,
        wall: const Duration(seconds: 18),
      );
      for (var i = 0; i < 3; i++) {
        health.record(slow(1));
      }
      await pumpEventQueue();

      expect(first.disposed, isTrue);
      expect(
        started,
        hasLength(2),
        reason: 'the new engine is started at once',
      );
      expect(host.hasEngine, isTrue);
      expect(host.leaseCount, 1, reason: 'the lease survives the replacement');
      expect(log.join('\n'), contains('engine replacing after slow synthesis'));

      // Still slow on the new engine: no second rebuild.
      for (var i = 0; i < 6; i++) {
        health.record(slow(2));
      }
      await pumpEventQueue();
      expect(started, hasLength(2));
    },
  );
}
