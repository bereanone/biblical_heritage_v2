import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../core/audio/narration_diagnostics.dart';
import '../../../core/audio/narration_media_session.dart';
import '../../../core/audio/speech_engine.dart';
import 'bible_pronunciation_map.dart';
import 'kokoro_engine_host.dart';

/// App-owned offline Kokoro reader. Its model is staged once from bundled
/// assets into the app sandbox; neither Python nor an external drive is used.
class KokoroMacTestNarrator {
  static const _assetPrefix =
      'assets/audio/kokoro/sherpa/kokoro-multi-lang-v1_0/';

  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  final List<StreamSubscription<void>> _completionSubscriptions = [];
  int _playerIndex = 0;
  bool _holdsLease = false;
  Map<String, String> pronunciationCorrections = {};
  Map<String, String> deferredPronunciationCorrections = {};
  Future<BiblePronunciationMap>? _pronunciationMap;
  final Map<String, Future<File>> _prepared = {};
  int _fileId = 0;
  Future<SpeechEngine>? _engineInitialization;
  bool _disposed = false;
  String? _activeVerseKey;
  var _generation = 0;
  var _isPlaying = false;
  double _clipSpeed = 1;
  double? _liveRate;

  Future<void> setLiveRate(double speed) async {
    if (_disposed || !Platform.isIOS) return;
    _liveRate = speed;
    if (_isPlaying) {
      await _players[_playerIndex].setPlaybackRate(speed / _clipSpeed);
    }
  }

  KokoroMacTestNarrator({
    this.onPlaybackReady,
    this.onPlaybackComplete,
    this.onError,
  }) {
    for (var index = 0; index < _players.length; index++) {
      _completionSubscriptions.add(
        _players[index].onPlayerComplete.listen((_) {
          if (index == _playerIndex) _handlePlaybackComplete();
        }),
      );
    }
  }

  final ValueChanged<Duration>? onPlaybackReady;
  final VoidCallback? onPlaybackComplete;
  final ValueChanged<String>? onError;

  void _handlePlaybackComplete() {
    if (_disposed || !_isPlaying) return;
    unawaited(recordDiagnostic('complete $_activeVerseKey'));
    _isPlaying = false;
    _activeVerseKey = null;
    onPlaybackComplete?.call();
  }

  bool get isAvailable => true;

  Future<void> recordDiagnostic(String message) async =>
      NarrationDiagnostics.log(message);

  /// Starts the bundled engine while autoscroll is armed, before movement
  /// begins. This makes the first spoken verse ready when scrolling starts.
  Future<void> warmUp() async {
    try {
      await Future.wait<Object>([
        _ensureEngine(),
        _pronunciationMap ??= _loadPronunciationMap(),
      ]);
    } catch (error) {
      debugPrint('Native Kokoro warm-up failed: $error');
      NarrationDiagnostics.log('warm-up FAILED: $error');
    }
  }

  /// How long the audio player gets to open and start a clip before the
  /// attempt is reported as failed rather than left hanging.
  static const _audioStartTimeout = Duration(seconds: 20);

  /// A play request still unfinished after this long is written to the event
  /// log with the stage it is stuck in, so a hang is visible even though it
  /// never produces an error.
  static const _slowSpeakAfter = Duration(seconds: 20);

  Future<void> speak({
    required String verseKey,
    required String text,
    required double speed,
    String voice = 'am_michael',
    int? blockId,
    bool preferDictionary = true,
  }) async {
    if (_disposed ||
        text.trim().isEmpty ||
        _isPlaying ||
        _activeVerseKey == verseKey) {
      NarrationDiagnostics.log(
        'speak ignored key=$verseKey (disposed=$_disposed '
        'empty=${text.trim().isEmpty} playing=$_isPlaying '
        'active=$_activeVerseKey)',
      );
      return;
    }
    final generation = ++_generation;
    _activeVerseKey = verseKey;
    _isPlaying = true;
    // Nothing is audible until this clip is synthesized; on a locked iPhone
    // that silence would let iOS suspend the app before it finishes.
    final releaseBackgroundTime = NarrationMediaSession.instance
        .holdBackgroundTime();
    // Every failure below names the stage it happened in, and a stage that
    // never returns is reported by [_slowSpeakAfter], so the event log shows
    // exactly where a play request stopped.
    final clock = _StageClock('audio-session');
    final slow = Timer(
      _slowSpeakAfter,
      () => NarrationDiagnostics.log(
        'speak SLOW key=$verseKey stage=${clock.current} '
        'after ${_slowSpeakAfter.inSeconds} s',
      ),
    );
    NarrationDiagnostics.log('speak begin key=$verseKey');
    try {
      debugPrint('Native Kokoro speak $verseKey');
      if (voice != 'am_michael') throw ArgumentError.value(voice);
      // audioplayers deactivates the audio session whenever nothing is
      // playing, so a resume after a pause finds it inactive.
      await NarrationMediaSession.instance.activateAudioSession('speak');
      clock.enter('engine');
      await _ensureEngine();
      clock.enter('synthesize');
      final output = await prepare(
        text: text,
        speed: speed,
        blockId: blockId,
        preferDictionary: preferDictionary,
      );
      if (_disposed || generation != _generation) {
        NarrationDiagnostics.log(
          'speak superseded key=$verseKey stage=${clock.current}',
        );
        return;
      }
      // Synthesis can take seconds; assert the session again just before use.
      clock.enter('audio-session');
      await NarrationMediaSession.instance.activateAudioSession('before-play');
      // Darwin emits completion before releasing its old item. Alternate
      // players so that cleanup cannot release the next verse's new item.
      clock.enter('play');
      _playerIndex = (_playerIndex + 1) % _players.length;
      final player = _players[_playerIndex];
      _clipSpeed = Platform.isIOS ? 1 : speed;
      await _within(_audioStartTimeout, 'audio did not start', () async {
        await player.setPlaybackRate(Platform.isIOS ? (_liveRate ?? speed) : 1);
        await player.play(DeviceFileSource(output.path));
      });
      unawaited(recordDiagnostic('play $verseKey speed=$speed'));
      if (_disposed || generation != _generation) return;
      clock.enter('duration');
      final duration = await player.getDuration().timeout(
        _audioStartTimeout,
        onTimeout: () => null,
      );
      onPlaybackReady?.call(duration ?? Duration.zero);
      NarrationDiagnostics.log(
        'speak ok key=$verseKey stages: ${clock.summary()}',
      );
    } catch (error) {
      debugPrint('Native Kokoro failed: $error');
      NarrationDiagnostics.log(
        'speak FAILED key=$verseKey stage=${clock.current} '
        'after ${clock.elapsedMs} ms: $error',
      );
      if (_disposed || generation != _generation) return;
      _activeVerseKey = null;
      _isPlaying = false;
      // A start that timed out may still complete later; make sure it cannot
      // begin audio for a request that was already reported as failed.
      unawaited(_silencePlayers());
      onError?.call(_describeFailure(clock.current, error));
    } finally {
      slow.cancel();
      releaseBackgroundTime();
    }
  }

  static Future<void> _within(
    Duration limit,
    String what,
    Future<void> Function() body,
  ) => body().timeout(
    limit,
    onTimeout: () => throw _StageTimeout('$what within ${limit.inSeconds} s'),
  );

  static String _describeFailure(String stage, Object error) {
    final doing = switch (stage) {
      'audio-session' => 'preparing the audio session',
      'engine' => 'starting the speech engine',
      'synthesize' => 'synthesizing speech',
      'play' => 'starting playback',
      _ => 'playing',
    };
    return 'Narration failed while $doing ($error)';
  }

  Future<void> _silencePlayers() async {
    for (final player in _players) {
      try {
        await player.stop().timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Best effort; the failure itself is already logged. */
      }
    }
  }

  Future<SpeechEngine> _ensureEngine() {
    if (_disposed) return Future.error(StateError('Narrator is disposed'));
    return _engineInitialization ??= _initializeEngine();
  }

  Future<SpeechEngine> _initializeEngine() async {
    try {
      return await _createEngine();
    } finally {
      _engineInitialization = null;
    }
  }

  /// Leases the app-wide engine the first time, and on every later call asks
  /// the host to confirm it still answers (rebuilding it if not); see
  /// [KokoroEngineHost]. Never trusts a reference held from an earlier call.
  Future<SpeechEngine> _createEngine() async {
    final host = KokoroEngineHost.instance;
    if (_holdsLease) {
      final engine = await host.ensureLive();
      if (_disposed) throw StateError('Narrator is disposed');
      return engine;
    }
    final engine = await host.acquire();
    if (_disposed) {
      host.release();
      throw StateError('Narrator is disposed');
    }
    _holdsLease = true;
    return engine;
  }

  static BiblePronunciationMap _parsePronunciationMap(List<String> data) =>
      BiblePronunciationMap(data[0], '${data[1]}\n${data[2]}');

  Future<BiblePronunciationMap> _loadPronunciationMap() async {
    final data = await Future.wait([
      rootBundle.loadString('assets/audio/pronunciation/bible-map-v1.json'),
      rootBundle.loadString('${_assetPrefix}lexicon-us-en.txt'),
      rootBundle.loadString('assets/audio/pronunciation/context-lexicon.txt'),
    ]);
    return compute(_parsePronunciationMap, data);
  }

  /// Verses to keep synthesized ahead of the one being spoken. iPhones render
  /// deep while the screen is on: a locked app is CPU-capped (see
  /// [SynthesisGovernor]) and plays from this lead.
  static int prefetchAhead() => Platform.isIOS ? 12 : 1;

  /// Current clip plus [prefetchAhead], with spares.
  int get _preparedCapacity => Platform.isIOS ? 16 : 3;

  static Future<void> _deleteQuietly(Future<File> file) async {
    try {
      // Unlinking a file the player still has open is safe on iOS and macOS.
      await (await file).delete();
    } catch (_) {
      /* Already gone, or the clip never rendered. */
    }
  }

  /// Speed baked into synthesized audio: iPhone clips are always rendered at
  /// 1.0 and the rate is applied at playback; macOS renders at [speed].
  static double synthesisSpeedFor(double speed) => Platform.isIOS ? 1.0 : speed;

  /// Playback rate that pairs with [synthesisSpeedFor].
  static double playbackRateFor(double speed) => Platform.isIOS ? speed : 1.0;

  Future<String> _spokenText(
    String text, {
    int? blockId,
    bool preferDictionary = true,
  }) async {
    // Capture editor state before awaiting asset loading.
    final corrections = Map<String, String>.of(pronunciationCorrections);
    final deferred = Map<String, String>.of(deferredPronunciationCorrections);
    final map = await (_pronunciationMap ??= _loadPronunciationMap());
    return map.prepare(
      text,
      blockId: blockId,
      corrections: corrections,
      deferredCorrections: deferred,
      // The app-owned Mac and physical iOS engines support dictionary aliases.
      preferDictionary:
          preferDictionary && (Platform.isMacOS || Platform.isIOS),
    );
  }

  /// Synthesizes one clip through the same pronunciation pipeline as
  /// [prepare], but outside the reader's clip cache. The caller owns the
  /// returned file and must delete it.
  Future<File> renderClip({
    required String text,
    required double speed,
    int? blockId,
    bool preferDictionary = true,
  }) async {
    final spoken = await _spokenText(
      text,
      blockId: blockId,
      preferDictionary: preferDictionary,
    );
    return _generateClip(spoken, synthesisSpeedFor(speed));
  }

  Future<File> prepare({
    required String text,
    required double speed,
    int? blockId,
    bool preferDictionary = true,
  }) async {
    final spoken = await _spokenText(
      text,
      blockId: blockId,
      preferDictionary: preferDictionary,
    );
    // Manual rate changes reuse prepared iPhone audio through playback rate.
    final synthesisSpeed = synthesisSpeedFor(speed);
    final key = '$synthesisSpeed|$spoken';
    final existing = _prepared[key];
    if (existing != null) {
      try {
        final file = await existing;
        if (await file.exists()) return file;
        NarrationDiagnostics.log('clip file missing; rendering again');
      } catch (_) {
        // The earlier attempt failed (already logged); try once more.
      }
      if (identical(_prepared[key], existing)) _prepared.remove(key);
    }
    // Only current and upcoming clips are needed. The cache is deeper while
    // backgrounded (see [prefetchAhead]); an evicted clip has already played,
    // so its file goes too, or a long locked-screen session would fill the
    // temp directory at about 170 MB per hour of speech.
    if (_prepared.length >= _preparedCapacity) {
      unawaited(_deleteQuietly(_prepared.remove(_prepared.keys.first)!));
    }
    final result = _generateClip(spoken, synthesisSpeed);
    _prepared[key] = result;
    // A failed clip must not stay cached: replaying the same text would hand
    // back the same failure forever.
    unawaited(
      result.then<void>(
        (_) {},
        onError: (Object error) {
          NarrationDiagnostics.log('clip synthesis FAILED: $error');
          if (identical(_prepared[key], result)) _prepared.remove(key);
        },
      ),
    );
    return result;
  }

  Future<File> _generateClip(String text, double speed) async {
    // While something is audible iOS keeps the app running; otherwise this is
    // the silent stretch that needs borrowed background time.
    final releaseBackgroundTime = _isPlaying
        ? null
        : NarrationMediaSession.instance.holdBackgroundTime();
    try {
      final audio = await _synthesize(text, speed);
      final temporary = await getTemporaryDirectory();
      final output = File(
        '${temporary.path}/narration-${DateTime.now().microsecondsSinceEpoch}-${++_fileId}.wav',
      );
      try {
        await _writeWave(output, audio);
      } catch (error) {
        throw SpeechEngineException('Could not write the audio file: $error');
      }
      return output;
    } finally {
      releaseBackgroundTime?.call();
    }
  }

  /// Synthesizes on a confirmed-live engine. If the engine turns out to be
  /// dead or hung, asks the host for a fresh one and tries once more.
  Future<sherpa.GeneratedAudio> _synthesize(String text, double speed) async {
    for (var attempt = 1; ; attempt++) {
      final engine = await _ensureEngine();
      try {
        return await engine.generate(text, speed);
      } on SpeechEngineUnavailableException catch (error) {
        NarrationDiagnostics.log(
          'synthesis found the engine unavailable (attempt $attempt): $error',
        );
        if (_disposed || attempt >= 2) rethrow;
      }
    }
  }

  Future<void> stop() async {
    NarrationDiagnostics.log('narrator stop key=$_activeVerseKey');
    ++_generation;
    _activeVerseKey = null;
    _isPlaying = false;
    await Future.wait(_players.map((player) => player.stop()));
  }

  void dispose() {
    _disposed = true;
    ++_generation;
    if (_holdsLease) {
      _holdsLease = false;
      KokoroEngineHost.instance.release();
    }
    for (final clip in _prepared.values) {
      unawaited(_deleteQuietly(clip));
    }
    _prepared.clear();
    for (final subscription in _completionSubscriptions) {
      subscription.cancel();
    }
    for (final player in _players) {
      player.dispose();
    }
  }

  /// Writes the generated samples using Dart's sandbox-aware file API.
  /// The native helper cannot create a file in a macOS app container.
  Future<void> _writeWave(File output, sherpa.GeneratedAudio audio) async {
    const headerLength = 44;
    const bytesPerSample = 2;
    final samples = audio.samples;
    final dataLength = samples.length * bytesPerSample;
    final bytes = ByteData(headerLength + dataLength);

    void text(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        bytes.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    text(8, 'WAVEfmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, audio.sampleRate, Endian.little);
    bytes.setUint32(28, audio.sampleRate * bytesPerSample, Endian.little);
    bytes.setUint16(32, bytesPerSample, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, dataLength, Endian.little);
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index].clamp(-1.0, 1.0);
      bytes.setInt16(
        headerLength + index * bytesPerSample,
        (sample * 32767).round(),
        Endian.little,
      );
    }
    await output.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }
}

class _StageTimeout implements Exception {
  const _StageTimeout(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Times each stage of a play request for the event log.
class _StageClock {
  _StageClock(this.current);

  final Stopwatch _watch = Stopwatch()..start();
  final List<String> _done = [];
  String current;
  int _mark = 0;

  int get elapsedMs => _watch.elapsedMilliseconds;

  void enter(String stage) {
    _close();
    current = stage;
  }

  void _close() {
    final now = _watch.elapsedMilliseconds;
    _done.add('$current=${now - _mark}ms');
    _mark = now;
  }

  String summary() {
    _close();
    return _done.join(' ');
  }
}
