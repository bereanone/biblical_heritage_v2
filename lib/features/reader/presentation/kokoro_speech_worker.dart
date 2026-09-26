import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../core/audio/narration_diagnostics.dart';
import '../../../core/audio/speech_engine.dart';
import '../../../core/audio/synthesis_governor.dart';
import '../../../core/audio/synthesis_health.dart';
import '../../../core/audio/synthesis_job_probe.dart';

/// A single native engine owned by a background isolate. The reader stays
/// responsive while the next verse is synthesized.
///
/// The worker knows when its isolate is gone (`onExit`), never waits on a
/// synthesis forever (each request has a deadline), and can be pinged. A
/// worker that dies or hangs closes itself and fails everything pending with
/// [SpeechEngineUnavailableException] so callers can rebuild it.
class KokoroSpeechWorker implements SpeechEngine {
  KokoroSpeechWorker._(
    this._port,
    this._messages,
    this._governor,
    this._requestTimeout,
    this._log,
    this._probe,
    this._onJob,
  );

  final SendPort _port;
  final ReceivePort _messages;
  final SynthesisGovernor _governor;
  final Duration Function(String text) _requestTimeout;
  final void Function(String message) _log;
  final SynthesisJobProbe _probe;
  final void Function(SynthesisJobStats job)? _onJob;
  final Map<int, Completer<sherpa.GeneratedAudio>> _pending = {};
  final Map<int, Completer<void>> _pings = {};
  final Completer<void> _exited = Completer<void>();
  int _nextId = 0;
  bool _closed = false;

  /// Synthesis speed is at most about real time (0.78x measured on an
  /// iPhone), and speech runs about 15 characters a second, so this is
  /// several times what any clip needs. Only time spent inside the isolate
  /// counts; waiting behind the [SynthesisGovernor] does not.
  static Duration defaultRequestTimeout(String text) =>
      Duration(seconds: 15, milliseconds: 120 * text.length);

  /// Numbers engines from 1 since the app started, so the log can say which
  /// one ran a job and how old it was.
  static int _engines = 0;

  static Future<KokoroSpeechWorker> start(
    String root, {
    SynthesisGovernor? governor,
    Duration Function(String text) requestTimeout = defaultRequestTimeout,
    Duration startTimeout = const Duration(seconds: 90),
    void Function(String message) log = NarrationDiagnostics.log,
    void Function(SynthesisJobStats job)? onJob,
    String Function()? jobContext,
    NarrationDeviceProbe? device,
    @visibleForTesting void Function(List<Object>) entry = _run,
  }) async {
    final messages = ReceivePort();
    final exitPort = ReceivePort();
    final errorPort = ReceivePort();
    final ready = Completer<KokoroSpeechWorker>();
    KokoroSpeechWorker? worker;

    void closePorts() {
      messages.close();
      exitPort.close();
      errorPort.close();
    }

    messages.listen((dynamic response) {
      if (response is SendPort) {
        worker = KokoroSpeechWorker._(
          response,
          messages,
          governor ?? SynthesisGovernor(isThrottled: () => false),
          requestTimeout,
          log,
          SynthesisJobProbe(
            engineId: ++_engines,
            log: log,
            device: device,
            context: jobContext,
          ),
          onJob,
        );
        ready.complete(worker);
      } else if (response is List && response.first == 'initError') {
        if (!ready.isCompleted) {
          ready.completeError(
            SpeechEngineException(
              'Speech engine failed to load: ${response[1]}',
            ),
          );
        }
        messages.close();
      } else if (response is List) {
        worker?._onReply(response);
      }
    });
    errorPort.listen((dynamic error) => log('engine isolate error: $error'));
    exitPort.listen((dynamic _) {
      final live = worker;
      if (live != null) {
        live._onExit();
      } else if (!ready.isCompleted) {
        ready.completeError(
          const SpeechEngineUnavailableException(
            'Speech engine exited while starting',
          ),
        );
      }
      closePorts();
    });

    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        entry,
        [messages.sendPort, root],
        onExit: exitPort.sendPort,
        onError: errorPort.sendPort,
      );
      return await ready.future.timeout(
        startTimeout,
        onTimeout: () => throw SpeechEngineUnavailableException(
          'Speech engine did not start within ${startTimeout.inSeconds} s',
        ),
      );
    } catch (_) {
      isolate?.kill(priority: Isolate.immediate);
      closePorts();
      rethrow;
    }
  }

  void _onReply(List<dynamic> response) {
    if (response.first == 'pong') {
      _pings.remove(response[1])?.complete();
      return;
    }
    final pending = _pending.remove(response[0]);
    if (response[1] is sherpa.GeneratedAudio) {
      pending?.complete(response[1] as sherpa.GeneratedAudio);
    } else {
      pending?.completeError(SpeechEngineException(response[1].toString()));
    }
  }

  void _onExit() {
    if (!_closed) {
      _log('engine isolate exited unexpectedly');
      _closed = true;
      _failPending('Speech engine stopped unexpectedly');
      _messages.close();
    }
    if (!_exited.isCompleted) _exited.complete();
  }

  void _failPending(String reason) {
    for (final pending in _pending.values) {
      pending.completeError(SpeechEngineUnavailableException(reason));
    }
    _pending.clear();
    _pings.clear();
  }

  @override
  bool get isClosed => _closed;

  @override
  Future<void> get exited => _exited.future;

  /// Every clip for every narration path is synthesized here, so this is
  /// where a backgrounded app is paced (see [SynthesisGovernor]).
  @override
  Future<sherpa.GeneratedAudio> generate(String text, double speed) =>
      _governor.run(() => _measured(text, speed));

  /// One governed job, timed and logged; see [SynthesisJobProbe].
  Future<sherpa.GeneratedAudio> _measured(String text, double speed) async {
    final run = _probe.begin(chars: text.length);
    try {
      final audio = await _generate(text, speed);
      final stats = run.finish(audio.samples.length / audio.sampleRate);
      _onJob?.call(stats);
      return audio;
    } catch (_) {
      run.abandon();
      rethrow;
    }
  }

  Future<sherpa.GeneratedAudio> _generate(String text, double speed) {
    if (_closed) {
      return Future.error(
        const SpeechEngineUnavailableException('Speech worker closed'),
      );
    }
    final id = ++_nextId;
    final result = Completer<sherpa.GeneratedAudio>();
    _pending[id] = result;
    _port.send([id, text, speed]);
    final limit = _requestTimeout(text);
    return result.future.timeout(
      limit,
      onTimeout: () {
        _pending.remove(id);
        _log(
          'engine synthesis hung: no answer in ${limit.inSeconds} s for '
          '${text.length} chars; discarding worker',
        );
        // The isolate may be stuck in native code. Ask it to free itself as
        // soon as it returns; callers rebuild the engine rather than wait.
        dispose();
        throw SpeechEngineUnavailableException(
          'Speech synthesis did not finish within ${limit.inSeconds} s',
        );
      },
    );
  }

  @override
  Future<bool> ping({Duration timeout = const Duration(seconds: 2)}) async {
    if (_closed) return false;
    if (_pending.isNotEmpty) return true; // Busy; generate has a deadline.
    final id = ++_nextId;
    final answered = Completer<void>();
    _pings[id] = answered;
    _port.send(['ping', id]);
    try {
      await answered.future.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    } finally {
      _pings.remove(id);
    }
  }

  @override
  void dispose() {
    if (_closed) return;
    _closed = true;
    _port.send(null); // Free after any in-flight native generation returns.
    _failPending('Speech worker closed');
    _messages.close();
  }

  static void _run(List<Object> arguments) {
    final reply = arguments[0] as SendPort;
    final root = arguments[1] as String;
    sherpa.OfflineTts engine;
    try {
      sherpa.initBindings();
      engine = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            kokoro: sherpa.OfflineTtsKokoroModelConfig(
              model: '$root/model.onnx',
              voices: '$root/voices.bin',
              tokens: '$root/tokens.txt',
              dataDir: '$root/espeak-ng-data',
              lexicon: '$root/context-lexicon-v1.txt,$root/lexicon-us-en.txt',
              // Both app-owned Apple packages include dictionary-mode.patch.
              // Keep the model voice available for unknown-word fallback.
              lang: (Platform.isMacOS || Platform.isIOS) ? 'lexicon' : '',
            ),
            numThreads: 2,
            debug: false,
          ),
        ),
      );
    } catch (error) {
      reply.send(['initError', error.toString()]);
      return;
    }
    final requests = ReceivePort();
    reply.send(requests.sendPort);
    requests.listen((dynamic message) {
      if (message == null) {
        engine.free();
        requests.close();
        return;
      }
      final request = message as List;
      if (request[0] == 'ping') {
        reply.send(['pong', request[1]]);
        return;
      }
      try {
        final audio = engine.generate(
          text: request[1] as String,
          sid: 16,
          speed: request[2] as double,
        );
        if (audio.samples.isEmpty || audio.sampleRate <= 0) {
          throw StateError('Kokoro returned no audio');
        }
        reply.send([request[0], audio]);
      } catch (error) {
        reply.send([request[0], error.toString()]);
      }
    });
  }
}
