import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:studybible2/core/audio/speech_engine.dart';
import 'package:studybible2/features/reader/presentation/kokoro_speech_worker.dart';

// Scripted stand-ins for the real synthesis isolate. They speak the same
// message protocol, so these tests exercise the worker's real liveness,
// deadline and exit handling without loading a model.

void _startup(
  List<Object> arguments,
  void Function(ReceivePort, SendPort) run,
) {
  final reply = arguments[0] as SendPort;
  final requests = ReceivePort();
  reply.send(requests.sendPort);
  run(requests, reply);
}

sherpa.GeneratedAudio _audio() =>
    sherpa.GeneratedAudio(samples: Float32List(8), sampleRate: 24000);

void _echoEntry(List<Object> arguments) =>
    _startup(arguments, (requests, reply) {
      requests.listen((dynamic message) {
        if (message == null) return requests.close();
        final request = message as List;
        if (request[0] == 'ping') return reply.send(['pong', request[1]]);
        reply.send([request[0], _audio()]);
      });
    });

/// Accepts work and never answers, like a native call that never returns.
void _hangEntry(List<Object> arguments) =>
    _startup(arguments, (requests, reply) {
      requests.listen((dynamic message) {
        if (message == null) requests.close();
      });
    });

/// Dies on the first synthesis request.
void _dieEntry(List<Object> arguments) =>
    _startup(arguments, (requests, reply) {
      requests.listen((dynamic message) {
        if (message is List && message[0] != 'ping') Isolate.exit();
      });
    });

/// Answers every synthesis request with an error.
void _errorEntry(List<Object> arguments) =>
    _startup(arguments, (requests, reply) {
      requests.listen((dynamic message) {
        if (message == null) return requests.close();
        final request = message as List;
        if (request[0] == 'ping') return reply.send(['pong', request[1]]);
        reply.send([request[0], 'Kokoro returned no audio']);
      });
    });

void main() {
  late List<String> log;
  setUp(() => log = []);

  Future<KokoroSpeechWorker> start(
    void Function(List<Object>) entry, {
    Duration limit = const Duration(milliseconds: 300),
  }) => KokoroSpeechWorker.start(
    'unused',
    entry: entry,
    requestTimeout: (_) => limit,
    log: log.add,
  );

  test('a live worker answers pings and synthesizes', () async {
    final worker = await start(_echoEntry);
    expect(await worker.ping(), isTrue);
    final audio = await worker.generate('hello', 1);
    expect(audio.sampleRate, 24000);
    expect(worker.isClosed, isFalse);

    worker.dispose();
    await worker.exited.timeout(const Duration(seconds: 5));
    expect(worker.isClosed, isTrue);
    expect(await worker.ping(), isFalse);
  });

  test('a synthesis that never returns times out instead of hanging', () async {
    final worker = await start(_hangEntry);

    await expectLater(
      worker.generate('hello', 1),
      throwsA(isA<SpeechEngineUnavailableException>()),
    );

    expect(worker.isClosed, isTrue, reason: 'a hung worker is discarded');
    expect(log.join('\n'), contains('engine synthesis hung'));
    await worker.exited.timeout(const Duration(seconds: 5));
  });

  test('a hung synthesis does not wedge the queue behind it', () async {
    final worker = await start(_hangEntry);

    final results = await Future.wait([
      worker.generate('first', 1).then<Object?>((_) => 'ok', onError: (e) => e),
      worker
          .generate('second', 1)
          .then<Object?>((_) => 'ok', onError: (e) => e),
    ]).timeout(const Duration(seconds: 5));

    expect(results[0], isA<SpeechEngineUnavailableException>());
    expect(results[1], isA<SpeechEngineUnavailableException>());
  });

  test('an isolate that dies is noticed and fails what was pending', () async {
    final worker = await start(_dieEntry, limit: const Duration(seconds: 5));

    await expectLater(
      worker.generate('hello', 1),
      throwsA(isA<SpeechEngineUnavailableException>()),
    );

    expect(worker.isClosed, isTrue);
    expect(await worker.ping(), isFalse);
    await worker.exited.timeout(const Duration(seconds: 5));
    expect(log.join('\n'), contains('exited unexpectedly'));
  });

  test(
    'an engine that stops answering pings is reported as not live',
    () async {
      final worker = await start(_hangEntry);
      expect(
        await worker.ping(timeout: const Duration(milliseconds: 150)),
        isFalse,
      );
      worker.dispose();
    },
  );

  test('a busy worker is not mistaken for a dead one', () async {
    final worker = await start(_hangEntry, limit: const Duration(seconds: 5));
    final pending = worker.generate('long clip', 1);
    pending.ignore();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      await worker.ping(timeout: const Duration(milliseconds: 100)),
      isTrue,
    );
    worker.dispose();
  });

  test(
    'a clip the engine cannot speak is an error, not a dead engine',
    () async {
      final worker = await start(_errorEntry);

      final error = await worker
          .generate('hello', 1)
          .then<Object?>((_) => null, onError: (Object e) => e);

      expect(error, isA<SpeechEngineException>());
      expect(error, isNot(isA<SpeechEngineUnavailableException>()));
      expect(worker.isClosed, isFalse);
      worker.dispose();
    },
  );
}
