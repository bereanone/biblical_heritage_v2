import 'dart:async';
import 'dart:io';
import '../../../../core/audio/local_narration_policy.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/audio/narration_diagnostics.dart';
import '../../../../core/audio/narration_media_session.dart';
import '../kokoro_mac_test_narrator.dart';
import 'tag_playback_models.dart';
import 'tag_playback_ports.dart';
import 'tag_note_audio_cache.dart';
import 'tag_verse_audio_cache.dart';
import 'tag_qwen_audio_cache.dart';

/// Prefers existing Qwen recordings for exact Bible verses. Text without a
/// matching recording uses the shared local Kokoro engine.
class KokoroTagClipRenderer implements TagClipRenderer {
  KokoroTagClipRenderer(this._narrator, {required this.speed});

  final KokoroMacTestNarrator _narrator;

  /// The reader's narration speech rate setting.
  final double speed;

  @override
  Future<String> render(TagSpeechClip clip) async {
    final recorded = await TagQwenAudioCache.instance.renderIfAvailable(clip);
    if (recorded != null) return recorded;
    if (clip.kind == TagClipKind.note) {
      return TagNoteAudioCache.instance.renderOrGet(
        clip.text,
        speed: speed,
        narrator: _narrator,
      );
    }
    // Notes carry no block id, so no KJV verse patch can apply to them; the
    // user's own corrections and the engine lexicon still do.
    // Names exactly what is about to be spoken, so any audio that does not
    // match a debug-console line here did not come from this popup.
    debugPrint('Tag playback loading: ${clip.text}');
    final started = DateTime.now();
    try {
      final path = clip.kind == TagClipKind.verse
          ? await TagVerseAudioCache.instance.renderOrGet(
              clip,
              speed: speed,
              narrator: _narrator,
            )
          : (await _narrator.renderClip(
              text: clip.text,
              speed: speed,
              blockId: clip.blockId,
              allowGeneration: !LocalNarrationPolicy.savedPlaybackOnly,
            )).path;
      final file = File(path);
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
    if (TagQwenAudioCache.isCachedPath(path)) return;
    if (TagNoteAudioCache.instance.isCachedPath(path)) return;
    if (TagVerseAudioCache.instance.isCachedPath(path)) return;
    try {
      await File(path).delete();
    } catch (_) {
      /* Already gone; temp files are also reclaimed by the OS. */
    }
  }
}

/// Plays clips on two alternating players, as the reader does (Darwin emits
/// completion before it releases the old item). Speech files are rendered
/// ahead by the controller; the player opens each file only when it becomes
/// current. Preloading a source on an idle native player raced with the next
/// play call and could leave a clip selected but silent.
class AudioplayersTagClipPlayer implements TagClipPlayer {
  AudioplayersTagClipPlayer({required double speed})
    : _recordedRate = speed,
      _playbackRate = KokoroMacTestNarrator.playbackRateFor(speed) {
    for (var index = 0; index < _players.length; index++) {
      _subscriptions.add(
        _players[index].onPlayerComplete.listen((_) {
          if (index == _active && _playing && !_completions.isClosed) {
            _playing = false;
            ++_serial;
            _watchdog?.cancel();
            NarrationDiagnostics.log('tag audio completed');
            _completions.add(null);
          }
        }),
      );
    }
  }

  final double _recordedRate;
  final double _playbackRate;
  double _activeRate = 1;
  final List<AudioPlayer> _players = [AudioPlayer(), AudioPlayer()];
  final List<StreamSubscription<void>> _subscriptions = [];
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  final StreamController<Object> _failures =
      StreamController<Object>.broadcast();
  int _active = 0;
  int _serial = 0;
  bool _playing = false;
  bool _paused = false;
  String? _currentPath;
  Timer? _watchdog;

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<Object> get failures => _failures.stream;

  @override
  Future<void> prepareNext(String path) async {
    // The controller already synthesizes and retains the next WAV. Calling
    // setSource here could still be in flight when play() switches players.
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
    // Alternate players, and mark the new one active before starting so a very
    // short clip's completion is not dropped.
    _watchdog?.cancel();
    final serial = ++_serial;
    _active = 1 - _active;
    _playing = true;
    _paused = false;
    _currentPath = path;
    _activeRate =
        TagQwenAudioCache.isCachedPath(path) ||
            (LocalNarrationPolicy.savedPlaybackOnly &&
                TagNoteAudioCache.instance.isCachedPath(path))
        ? _recordedRate
        : _playbackRate;
    final player = _players[_active];
    try {
      await _start('play', () async {
        await player.setPlaybackRate(_activeRate);
        await player.play(DeviceFileSource(path));
      });
      if (_playing && serial == _serial) {
        NarrationDiagnostics.log('tag audio started: $path');
        unawaited(_armWatchdog(serial, path));
      }
    } catch (_) {
      if (serial == _serial) {
        _playing = false;
        ++_serial;
      }
      rethrow;
    }
  }

  @override
  Future<void> pause() {
    _paused = true;
    _watchdog?.cancel();
    return _players[_active].pause();
  }

  @override
  Future<void> resume() async {
    await _start('resume', _players[_active].resume);
    _paused = false;
    if (_playing) unawaited(_armWatchdog(_serial, _currentPath));
  }

  /// Native completion notifications can be lost during a file handoff. A
  /// generous deadline checks the actual playhead: completed audio advances,
  /// while a stopped playhead reports an error instead of hanging forever.
  Future<void> _armWatchdog(int serial, String? path) async {
    final player = _players[_active];
    Duration? duration;
    try {
      duration = await player.getDuration().timeout(const Duration(seconds: 3));
      if (duration == null && path != null) {
        final bytes = await File(path).length();
        duration = Duration(milliseconds: ((bytes - 44) / 48).round());
      }
      if (duration == null || duration <= Duration.zero) return;
      final position = await player.getCurrentPosition().timeout(
        const Duration(seconds: 3),
        onTimeout: () => Duration.zero,
      );
      if (!_playing || _paused || serial != _serial) return;
      final remainingMs =
          duration.inMilliseconds - (position?.inMilliseconds ?? 0);
      final delayMs = (remainingMs / _activeRate).ceil() + 8000;
      _watchdog?.cancel();
      _watchdog = Timer(
        Duration(milliseconds: delayMs.clamp(8000, 360000)),
        () {
          unawaited(_checkWatchdog(serial, duration!));
        },
      );
    } catch (error) {
      NarrationDiagnostics.log('tag audio watchdog unavailable: $error');
    }
  }

  Future<void> _checkWatchdog(int serial, Duration duration) async {
    if (!_playing || _paused || serial != _serial) return;
    try {
      final position = await _players[_active].getCurrentPosition().timeout(
        const Duration(seconds: 3),
      );
      if (!_playing || _paused || serial != _serial) return;
      if (position != null &&
          position >= duration - const Duration(milliseconds: 250)) {
        _playing = false;
        ++_serial;
        NarrationDiagnostics.log('tag audio completion recovered at end');
        _completions.add(null);
      } else {
        final error = TimeoutException(
          'audio stopped before the clip ended (${position?.inSeconds ?? 0}'
          '/${duration.inSeconds} s)',
        );
        _playing = false;
        ++_serial;
        NarrationDiagnostics.log('tag audio FAILED: $error');
        _failures.add(error);
      }
    } catch (error) {
      if (!_playing || serial != _serial) return;
      _playing = false;
      ++_serial;
      NarrationDiagnostics.log('tag audio FAILED: $error');
      _failures.add(error);
    }
  }

  @override
  Future<void> stop() async {
    _watchdog?.cancel();
    _playing = false;
    _paused = false;
    _currentPath = null;
    ++_serial;
    await Future.wait(_players.map((player) => player.stop()));
  }

  @override
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _completions.close();
    await _failures.close();
    for (final player in _players) {
      await player.dispose();
    }
  }
}
