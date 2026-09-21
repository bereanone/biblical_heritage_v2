import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/audio/narration_diagnostics.dart';
import '../../../core/audio/narration_media_session.dart';
import '../../../core/audio/speech_engine.dart';
import '../../../core/audio/synthesis_governor.dart';
import 'kokoro_speech_worker.dart';

typedef SpeechEngineStarter = Future<SpeechEngine> Function();

/// Owns the single app-wide Kokoro engine (a 325 MB model in a background
/// isolate). Every [KokoroMacTestNarrator] leases it instead of loading a
/// private copy, so the Bible reader, eLibrary reader and tag playback can be
/// open together without duplicating the model in memory. The engine starts on
/// first lease and is freed when the last lease is released (or, when
/// [idleRelease] is set, that long afterwards).
///
/// A lease is a promise that the engine may be wanted, not proof that it is
/// alive. [ensureLive] is what callers use before speaking: it rebuilds an
/// engine that is closed or does not answer, so play works from any state.
class KokoroEngineHost {
  KokoroEngineHost._(
    this._starter, {
    this.idleRelease,
    this.pingTimeout = const Duration(seconds: 2),
    this.exitWait = const Duration(seconds: 10),
    void Function(String message)? log,
  }) : _log = log ?? NarrationDiagnostics.log;

  @visibleForTesting
  factory KokoroEngineHost.forTesting({
    required SpeechEngineStarter starter,
    Duration? idleRelease,
    Duration pingTimeout = const Duration(milliseconds: 200),
    Duration exitWait = const Duration(milliseconds: 500),
    void Function(String message)? log,
  }) => KokoroEngineHost._(
    starter,
    idleRelease: idleRelease,
    pingTimeout: pingTimeout,
    exitWait: exitWait,
    log: log ?? (_) {},
  );

  static final KokoroEngineHost instance = KokoroEngineHost._(_startKokoro);

  static const _assetPrefix =
      'assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0/';
  static const _stagedMarker = '.staged-complete';

  /// How long the engine stays loaded after the last lease is released.
  /// Null (the default) frees it immediately. Idle release is deliberately
  /// off: reloading the model inside the short wake window of a lock-screen
  /// play would make resuming after a long pause worse, not better. Revisit
  /// with the RSS and cold-start figures from the engine log.
  Duration? idleRelease;

  final SpeechEngineStarter _starter;
  final Duration pingTimeout;
  final Duration exitWait;
  final void Function(String message) _log;

  SpeechEngine? _worker;
  Future<SpeechEngine>? _starting;
  Future<void>? _pendingExit;
  Timer? _idleTimer;
  int _leases = 0;

  /// Number of narrators currently holding the engine (for diagnostics/tests).
  int get leaseCount => _leases;

  @visibleForTesting
  bool get hasEngine => _worker != null;

  /// Counts a lease immediately, then resolves once the engine is running.
  /// Every successful [acquire] must be paired with one [release], including
  /// when the caller was disposed while the engine was still starting.
  Future<SpeechEngine> acquire() async {
    _leases++;
    _idleTimer?.cancel();
    _idleTimer = null;
    _log('engine acquire (leases $_leases)');
    try {
      return await ensureLive();
    } catch (_) {
      _leases--;
      rethrow;
    }
  }

  /// A running engine that has just been confirmed to answer, starting or
  /// replacing one if needed. Does not change the lease count, so a narrator
  /// that already holds a lease calls this before every play.
  Future<SpeechEngine> ensureLive() async {
    for (;;) {
      final current = _worker;
      if (current == null) return _startShared();
      if (current.isClosed) {
        _log('engine found closed; replacing');
        _discard(current);
        continue;
      }
      if (await current.ping(timeout: pingTimeout)) {
        if (identical(_worker, current) && !current.isClosed) return current;
        continue;
      }
      _log(
        'engine did not answer a ping within ${pingTimeout.inMilliseconds} ms; '
        'replacing',
      );
      _discard(current);
    }
  }

  void release() {
    if (_leases == 0) return;
    if (--_leases > 0) return;
    final wait = idleRelease;
    if (wait == null) {
      _log('engine last lease released; freeing the model');
      _discardCurrent();
      return;
    }
    _log('engine last lease released; freeing in ${wait.inSeconds} s if idle');
    _idleTimer?.cancel();
    _idleTimer = Timer(wait, () {
      _idleTimer = null;
      if (_leases > 0) return;
      _log('engine idle for ${wait.inSeconds} s; freeing the model');
      _discardCurrent();
    });
  }

  void _discardCurrent() {
    final worker = _worker;
    if (worker != null) _discard(worker);
  }

  /// Disposes [engine] and remembers when its isolate is gone, so the next
  /// start never has two models resident at once.
  void _discard(SpeechEngine engine) {
    if (identical(_worker, engine)) _worker = null;
    engine.dispose();
    _pendingExit = engine.exited;
    _log('engine freed (rss ${_rssMb()} MB)');
  }

  Future<SpeechEngine> _startShared() =>
      _starting ??= _start().whenComplete(() => _starting = null);

  Future<SpeechEngine> _start() async {
    final watch = Stopwatch()..start();
    _log('engine start begin (leases $_leases, rss ${_rssMb()} MB)');
    try {
      final exiting = _pendingExit;
      if (exiting != null) {
        await exiting.timeout(
          exitWait,
          onTimeout: () => _log(
            'engine previous isolate still running after '
            '${exitWait.inMilliseconds} ms; starting anyway',
          ),
        );
        if (identical(_pendingExit, exiting)) _pendingExit = null;
      }
      final engine = await _starter();
      _worker = engine;
      _log(
        'engine started in ${watch.elapsedMilliseconds} ms '
        '(rss ${_rssMb()} MB)',
      );
      return engine;
    } catch (error) {
      _log('engine start FAILED after ${watch.elapsedMilliseconds} ms: $error');
      rethrow;
    }
  }

  static int _rssMb() {
    try {
      return ProcessInfo.currentRss ~/ (1024 * 1024);
    } catch (_) {
      return -1;
    }
  }

  static Future<SpeechEngine> _startKokoro() async {
    final root = await _stage('stage-assets', _stageAssets);
    await _stage('write-lexicon', () async {
      final contextLexicon = File('${root.path}/context-lexicon-v1.txt');
      await contextLexicon.writeAsString(
        await rootBundle.loadString(
          'assets/audio/pronunciation/context-lexicon.txt',
        ),
      );
    });
    // The caller that triggered startup still holds its lease until this
    // resolves, so the engine cannot be released while it is starting.
    return _stage(
      'load-model',
      () => KokoroSpeechWorker.start(
        root.path,
        // A locked iPhone is killed above ~80% CPU, and synthesis runs two
        // threads flat out. Pace it while backgrounded; clips rendered ahead
        // in the foreground cover the difference.
        governor: SynthesisGovernor(
          isThrottled: () => NarrationMediaSession.instance.backgrounded.value,
          log: NarrationDiagnostics.log,
        ),
      ),
    );
  }

  /// Runs one startup step, logging which one failed and why.
  static Future<T> _stage<T>(String name, Future<T> Function() body) async {
    final watch = Stopwatch()..start();
    try {
      final result = await body();
      NarrationDiagnostics.log(
        'engine $name ok in ${watch.elapsedMilliseconds} ms',
      );
      return result;
    } on SpeechEngineException catch (error) {
      NarrationDiagnostics.log('engine $name FAILED: $error');
      rethrow;
    } catch (error) {
      NarrationDiagnostics.log('engine $name FAILED: $error');
      throw SpeechEngineException(
        'Speech engine could not start ($name): $error',
      );
    }
  }

  static Future<Directory> _stageAssets() async {
    final support = await getApplicationSupportDirectory();
    final target = Directory('${support.path}/kokoro-multi-lang-v1_0-v2');
    final marker = File('${target.path}/$_stagedMarker');
    if (await marker.exists()) return target;
    // Older installs staged without a marker; accept them only if every file
    // the engine opens is present, so a copy interrupted part way is redone.
    if (await _hasEngineFiles(target)) {
      await marker.writeAsString('legacy');
      return target;
    }
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    var staged = 0;
    for (final asset in manifest.listAssets().where(
      (key) => key.startsWith(_assetPrefix),
    )) {
      final relative = asset.substring(_assetPrefix.length);
      final file = File('${target.path}/$relative');
      await file.parent.create(recursive: true);
      final bytes = await rootBundle.load(asset);
      await file.writeAsBytes(bytes.buffer.asUint8List());
      staged++;
    }
    NarrationDiagnostics.log('engine staged $staged asset files');
    await marker.writeAsString('complete');
    return target;
  }

  static Future<bool> _hasEngineFiles(Directory target) async {
    for (final name in const [
      'model.onnx',
      'voices.bin',
      'tokens.txt',
      'lexicon-us-en.txt',
      'espeak-ng-data/phontab',
    ]) {
      if (!await File('${target.path}/$name').exists()) return false;
    }
    return true;
  }
}
