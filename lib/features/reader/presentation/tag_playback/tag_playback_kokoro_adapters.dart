import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/audio/narration_diagnostics.dart';
import '../../../../core/audio/narration_media_session.dart';
import '../kokoro_mac_test_narrator.dart';
import 'tag_playback_models.dart';
import 'tag_playback_ports.dart';

/// Renders clips with the app's existing [KokoroMacTestNarrator], so notes
/// and verses go through the same pronunciation rules, voice and engine as
/// the Bible reader. The narrator's shared engine lease is what keeps a
/// second 325 MB model out of memory.
class KokoroTagClipRenderer implements TagClipRenderer {
  KokoroTagClipRenderer(this._narrator, {required this.speed});

  final KokoroMacTestNarrator _narrator;

  /// The reader's narration speech rate setting.
  final double speed;

  @override
  Future<String> render(TagSpeechClip clip) async {
    // Notes carry no block id, so no KJV verse patch can apply to them; the
    // user's own corrections and the engine lexicon still do.
    // Names exactly what is about to be spoken, so any audio that does not
    // match a debug-console line here did not come from this popup.
    debugPrint('Tag playback synthesizing: ${clip.text}');
    final started = DateTime.now();
    try {
      final file = await _narrator.renderClip(
        text: clip.text,
        speed: speed,
        blockId: clip.blockId,
      );
      // 24 kHz, 16-bit mono WAV: 48,000 bytes per second of speech.
      final seconds = (await file.length() - 44) / 48000;
      final took = DateTime.now().difference(started).inMilliseconds / 1000;
      NarrationDiagnostics.log(
        'render ${clip.text.length} chars -> ${seconds.toStringAsFixed(1)}s '
        'audio in ${took.toStringAsFixed(1)}s '
        '(${(took / seconds).toStringAsFixed(2)}x real time)',
      );
      return file.path;
    } catch (error) {
      NarrationDiagnostics.log('render FAILED: $error');
      rethrow;
    }
  }

  @override
  Future<void> discard(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      /* Already gone; temp files are also reclaimed by the OS. */
    }
  }
}

/// Plays clips on two alternating players, as the reader does (Darwin emits
/// completion before it releases the old item, so one player per clip would
/// let cleanup release the next clip). The idle player can preload the next
/// file so the hand-over needs no file open.
class AudioplayersTagClipPlayer implements TagClipPlayer {
  AudioplayersTagClipPlayer({required double speed})
    : _playbackRate = KokoroMacTestNarrator.playbackRateFor(speed) {
    for (var index = 0; index < _players.length; index++) {
      _subscriptions.add(
        _players[index].onPlayerComplete.listen((_) {
          if (index == _active && !_completions.isClosed) {
            _completions.add(null);
          }
        }),
      );
    }
  }

  final double _playbackRate;
  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  final List<StreamSubscription<void>> _subscriptions = [];
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  int _active = 0;
  String? _preloadedPath;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> prepareNext(String path) async {
    if (_preloadedPath == path) return;
    _preloadedPath = path;
    final idle = _players[1 - _active];
    await idle.setPlaybackRate(_playbackRate);
    await idle.setSource(DeviceFileSource(path));
  }

  /// How long a player gets to start before the attempt is a failure the
  /// controller can report, instead of an await that never returns.
  static const _startTimeout = Duration(seconds: 20);

  /// Runs [body] with the audio session asserted first (audioplayers lets it
  /// go whenever nothing is playing) and a deadline, logging any failure.
  Future<void> _start(String what, Future<void> Function() body) async {
    try {
      await NarrationMediaSession.instance.activateAudioSession('tag $what');
      await body().timeout(
        _startTimeout,
        onTimeout: () => throw TimeoutException(
          'audio did not start within ${_startTimeout.inSeconds} s',
        ),
      );
    } catch (error) {
      NarrationDiagnostics.log('tag audio $what FAILED: $error');
      rethrow;
    }
  }

  @override
  Future<void> play(String path) async {
    final preloaded = _preloadedPath == path;
    _preloadedPath = null;
    // Alternate players, and mark the new one active before starting so a very
    // short clip's completion is not dropped.
    _active = 1 - _active;
    final player = _players[_active];
    await _start('play', () async {
      await player.setPlaybackRate(_playbackRate);
      if (preloaded) {
        await player.resume();
      } else {
        await player.play(DeviceFileSource(path));
      }
    });
  }

  @override
  Future<void> pause() => _players[_active].pause();

  @override
  Future<void> resume() => _start('resume', _players[_active].resume);

  @override
  Future<void> stop() async {
    _preloadedPath = null;
    await Future.wait(_players.map((player) => player.stop()));
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _completions.close();
    for (final player in _players) {
      await player.dispose();
    }
  }
}
