import 'dart:async';

import 'package:flutter/foundation.dart';

import 'tag_playback_models.dart';
import 'tag_playback_ports.dart';
import 'tag_playback_settings.dart';

/// Position inside the playlist: entry index and clip index within it.
@immutable
class _Cursor {
  const _Cursor(this.entry, this.clip);
  final int entry;
  final int clip;

  @override
  bool operator ==(Object other) =>
      other is _Cursor && other.entry == entry && other.clip == clip;

  @override
  int get hashCode => Object.hash(entry, clip);
}

/// A clip on its way to audio. Slots are the prefetch buffer: the current
/// clip plus at most [TagPlaybackController.maxAhead] clips behind it.
class _Slot {
  _Slot(this.cursor, this.clip);

  final _Cursor cursor;
  final TagSpeechClip clip;
  final Completer<void> _settled = Completer<void>();

  bool started = false;
  bool cancelled = false;
  bool gateHeld = false;
  Timer? timeout;
  String? path;
  Object? error;

  bool get isSettled => _settled.isCompleted;
  void settle() {
    if (!_settled.isCompleted) _settled.complete();
  }
}

/// Plays a tag's entries as a gapless playlist: for each entry, its
/// reference and content clips and then (optionally) its note clips.
///
/// The controller owns the sequencing and the prefetch buffer only; synthesis
/// and audio output sit behind [TagClipRenderer] and [TagClipPlayer], which
/// makes the state machine testable without a model or an audio device.
class TagPlaybackController extends ChangeNotifier {
  TagPlaybackController({
    required this.items,
    required TagClipRenderer renderer,
    required TagClipPlayer player,
    bool includeNotes = true,
    bool loop = false,
    bool speakReference = true,
    this.onSettingsChanged,
    this.maxAhead = 2,
    this.backgroundMaxAhead = 5,
    this.maxConcurrentRenders = 2,
    this.renderTimeout = const Duration(seconds: 90),
    this.maxConsecutiveFailures = 3,
  }) : _renderer = renderer,
       _player = player,
       _includeNotes = includeNotes,
       _speakReference = speakReference,
       _loop = loop {
    _cursor = _firstAtOrAfter(0);
    _completions = _player.completions.listen((_) => _onClipCompleted());
  }

  final List<TagPlaybackItem> items;

  /// Called after the user changes a playback setting, so it can be remembered.
  final void Function(TagPlaybackSettings settings)? onSettingsChanged;

  /// Clips synthesized ahead of the one playing. Bounds disk/memory: at most
  /// `1 + maxAhead` audio files exist at once, however long the tag is.
  final int maxAhead;

  /// Lookahead while the app is backgrounded. Once iOS suspends a locked app,
  /// nothing can top the buffer up on demand, so the clips already rendered
  /// are what keeps speech continuous through a slow render. Costs about
  /// 50 KB of temp file per second of buffered speech (roughly 3 MB for five
  /// long clips), never more, however long the tag or whether it loops.
  final int backgroundMaxAhead;

  /// Synthesis jobs handed to the engine at once. The engine runs jobs in
  /// order and cannot abort one, so anything not yet handed over can still be
  /// cancelled for free (rapid skipping never queues stale work).
  final int maxConcurrentRenders;
  final Duration renderTimeout;
  final int maxConsecutiveFailures;

  final TagClipRenderer _renderer;
  final TagClipPlayer _player;
  late final StreamSubscription<void> _completions;

  bool _includeNotes;
  bool _speakReference;
  bool _loop;
  bool _backgrounded = false;
  bool _disposed = false;

  /// True once the user has pressed play and until stop/finish.
  bool _started = false;
  bool _playRequested = false;
  bool _audioStarted = false;
  bool _finished = false;
  int _epoch = 0;
  int _inFlight = 0;
  int _consecutiveFailures = 0;
  String? _error;

  _Cursor? _cursor;
  _Slot? _current;
  final List<_Slot> _ahead = [];
  String? _preloadedPath;

  bool get includeNotes => _includeNotes;
  bool get speakReference => _speakReference;
  bool get loop => _loop;

  int get _aheadTarget => _backgrounded ? backgroundMaxAhead : maxAhead;

  TagPlaybackSettings get settings => TagPlaybackSettings(
    speakReference: _speakReference,
    speakNotes: _includeNotes,
    loop: _loop,
  );
  int get entryCount => items.length;
  String? get errorMessage => _error;

  /// Entries that will actually be spoken in the current mode.
  int get speakableEntryCount =>
      items.where((item) => _clips(item).isNotEmpty).length;

  /// Index of the entry being (or about to be) spoken; 0 for an empty tag.
  int get currentIndex => _cursor?.entry ?? 0;

  TagPlaybackItem? get currentItem {
    final cursor = _cursor;
    return cursor == null ? null : items[cursor.entry];
  }

  bool get canPlay => _firstAtOrAfter(0) != null;

  TagPlaybackStatus get status {
    if (_error != null && !_started) return TagPlaybackStatus.error;
    if (_started) {
      if (!_playRequested) return TagPlaybackStatus.paused;
      return _audioStarted
          ? TagPlaybackStatus.playing
          : TagPlaybackStatus.loading;
    }
    return _finished ? TagPlaybackStatus.finished : TagPlaybackStatus.idle;
  }

  bool get isPlaying => status == TagPlaybackStatus.playing;

  /// Clips currently held (playing + buffered), including in-flight renders.
  @visibleForTesting
  int get bufferedClipCount => (_current == null ? 0 : 1) + _ahead.length;

  // ---------------------------------------------------------------- queries

  List<TagSpeechClip> _clips(TagPlaybackItem item) => item.clipsFor(
    includeNotes: _includeNotes,
    speakReference: _speakReference,
  );

  _Cursor? _firstAtOrAfter(int entry) {
    for (var i = entry; i < items.length; i++) {
      if (_clips(items[i]).isNotEmpty) return _Cursor(i, 0);
    }
    return null;
  }

  _Cursor? _lastAtOrBefore(int entry) {
    for (var i = entry; i >= 0; i--) {
      if (_clips(items[i]).isNotEmpty) return _Cursor(i, 0);
    }
    return null;
  }

  /// The clip that follows [cursor], wrapping to the top when looping.
  _Cursor? _after(_Cursor cursor) {
    if (cursor.entry < items.length &&
        cursor.clip + 1 < _clips(items[cursor.entry]).length) {
      return _Cursor(cursor.entry, cursor.clip + 1);
    }
    return _firstAtOrAfter(cursor.entry + 1) ??
        (_loop ? _firstAtOrAfter(0) : null);
  }

  // --------------------------------------------------------------- commands

  /// Starts from the top (or from the selected entry), or resumes if paused.
  void play() {
    if (_disposed) return;
    if (_started) {
      if (_playRequested) return;
      _playRequested = true;
      if (_audioStarted) {
        unawaited(_resumeAudio());
      } else {
        _drive();
      }
      _pump();
      _notify();
      return;
    }
    var start = _cursor;
    if (start == null || _finished) start = _firstAtOrAfter(0);
    if (start == null) return; // Empty tag: nothing to speak.
    _finished = false;
    _error = null;
    _consecutiveFailures = 0;
    _started = true;
    _playRequested = true;
    _cursor = start;
    _current = _newSlot(start);
    _pump();
    _drive();
    _notify();
  }

  /// A resume that fails (the player or audio session is gone after a long
  /// pause) ends the pass with a visible error rather than an unhandled one.
  Future<void> _resumeAudio() async {
    final epoch = _epoch;
    try {
      await _player.resume();
    } catch (error) {
      if (_disposed || epoch != _epoch) return;
      _fail('Speech stopped: could not resume ($error)');
    }
  }

  void pause() {
    if (_disposed || !_started || !_playRequested) return;
    _playRequested = false;
    if (_audioStarted) unawaited(_player.pause());
    _notify();
  }

  void togglePlayPause() => _playRequested && _started ? pause() : play();

  /// Stops, drops every buffered clip and returns to the first entry.
  void stop() {
    if (_disposed) return;
    _halt();
    _finished = false;
    _error = null;
    _cursor = _firstAtOrAfter(0);
    _notify();
  }

  /// Skips to the next entry. At the last entry: wraps when looping,
  /// otherwise ends the pass.
  void next() {
    final cursor = _cursor;
    if (_disposed || cursor == null) return;
    final target =
        _firstAtOrAfter(cursor.entry + 1) ??
        (_loop ? _firstAtOrAfter(0) : null);
    if (target == null) {
      if (_started) _finishPass();
      return;
    }
    _moveTo(target);
  }

  /// Skips to the previous entry. At the first entry: wraps to the last when
  /// looping, otherwise restarts the first entry.
  void previous() {
    final cursor = _cursor;
    if (_disposed || cursor == null) return;
    final target =
        _lastAtOrBefore(cursor.entry - 1) ??
        (_loop ? _lastAtOrBefore(items.length - 1) : _firstAtOrAfter(0));
    if (target != null) _moveTo(target);
  }

  /// Jumps to [index] (or the next speakable entry after it) and plays.
  void playFromEntry(int index) {
    if (_disposed) return;
    final target = _firstAtOrAfter(index.clamp(0, items.length));
    if (target == null) return;
    _moveTo(target);
    if (!_playRequested) play();
  }

  void setLoop(bool value) {
    if (_disposed || value == _loop) return;
    _loop = value;
    // Buffered clips may sit across (or lack) the wraparound: rebuild.
    _replanAfterSettingChange();
  }

  void setIncludeNotes(bool value) {
    if (_disposed || value == _includeNotes) return;
    _includeNotes = value;
    _replanAfterSettingChange();
  }

  void setSpeakReference(bool value) {
    if (_disposed || value == _speakReference) return;
    _speakReference = value;
    _replanAfterSettingChange();
  }

  /// The clip playing now finishes as-is; everything buffered behind it was
  /// planned under the old setting and is rebuilt (and its audio discarded), so
  /// the change takes effect from the next clip with no stale or empty audio.
  void _replanAfterSettingChange() {
    _resetAhead();
    if (!_started) _cursor = _normalized(_cursor);
    _pump();
    _notify();
    onSettingsChanged?.call(settings);
  }

  /// Backgrounded playback keeps going (iOS "audio" background mode) but
  /// buffers deeper. Returning to the foreground drops back to [maxAhead];
  /// clips already buffered beyond it are simply played out.
  void setBackgrounded(bool value) {
    if (_disposed || value == _backgrounded) return;
    _backgrounded = value;
    _pump();
  }

  /// For platforms where nothing keeps speaking in the background (macOS
  /// hidden window): pause rather than leave speech half-buffered. Resume is
  /// explicit.
  void pauseForBackground() => pause();

  @override
  void dispose() {
    if (_disposed) return;
    _halt();
    _disposed = true;
    unawaited(_completions.cancel());
    unawaited(_stopThenDisposePlayer());
    super.dispose();
  }

  Future<void> _stopThenDisposePlayer() async {
    try {
      await _player.stop();
    } catch (_) {
      /* Already tearing down. */
    }
    try {
      await _player.dispose();
    } catch (_) {
      /* Already tearing down. */
    }
  }

  // ------------------------------------------------------------ transitions

  _Cursor? _normalized(_Cursor? cursor) {
    if (cursor == null) return _firstAtOrAfter(0);
    if (cursor.entry < items.length && _clips(items[cursor.entry]).isNotEmpty) {
      return cursor;
    }
    return _firstAtOrAfter(cursor.entry) ?? _lastAtOrBefore(items.length - 1);
  }

  /// Cancels everything and clears run state (not the cursor).
  void _halt() {
    ++_epoch;
    _started = false;
    _playRequested = false;
    _audioStarted = false;
    _discardSlot(_current);
    _current = null;
    _resetAhead();
    _preloadedPath = null;
    unawaited(_player.stop());
  }

  void _finishPass() {
    _halt();
    _finished = true;
    _notify();
  }

  void _moveTo(_Cursor target) {
    if (!_started) {
      _cursor = target;
      _finished = false;
      _notify();
      return;
    }
    ++_epoch;
    _audioStarted = false;
    unawaited(_player.stop());
    _preloadedPath = null;
    _consecutiveFailures = 0;
    final old = _current;
    _current = null;
    // A prefetched clip that is exactly the target keeps its audio, and the
    // clips behind it are still a valid continuation, so nothing is wasted.
    final reuse = _ahead.indexWhere((s) => !s.cancelled && s.cursor == target);
    if (reuse >= 0) {
      for (final dropped in _ahead.sublist(0, reuse)) {
        _discardSlot(dropped);
      }
      _current = _ahead[reuse];
      _ahead.removeRange(0, reuse + 1);
    } else {
      _resetAhead();
      _current = _newSlot(target);
    }
    _discardSlot(old);
    _cursor = target;
    _pump();
    _drive();
    _notify();
  }

  void _onClipCompleted() {
    if (_disposed || !_audioStarted) return;
    _audioStarted = false;
    _consecutiveFailures = 0;
    _advance();
  }

  /// Moves past the current clip (played or failed) to whatever follows.
  void _advance() {
    final finished = _current;
    final cursor = _cursor;
    if (finished == null || cursor == null) return;
    final following = _ahead.isNotEmpty ? _ahead.removeAt(0) : null;
    final target = following?.cursor ?? _after(cursor);
    _discardSlot(finished);
    _current = null;
    if (target == null) {
      _discardSlot(following);
      _finishPass();
      return;
    }
    _current = following ?? _newSlot(target);
    _cursor = target;
    _pump();
    _drive();
    _notify();
  }

  void _fail(String message) {
    _halt();
    _error = message;
    _notify();
  }

  // ------------------------------------------------------- buffer + engine

  _Slot _newSlot(_Cursor cursor) =>
      _Slot(cursor, _clips(items[cursor.entry])[cursor.clip]);

  void _resetAhead() {
    for (final slot in _ahead) {
      _discardSlot(slot);
    }
    _ahead.clear();
  }

  void _discardSlot(_Slot? slot) {
    if (slot == null) return;
    slot.cancelled = true;
    // A job already handed to the engine keeps running and keeps its gate
    // until it really finishes (or times out), so stale work can never pile up
    // ahead of the clip the user is waiting for.
    if (!slot.gateHeld) slot.timeout?.cancel();
    final path = slot.path;
    slot.path = null;
    if (path != null) {
      if (_preloadedPath == path) _preloadedPath = null;
      unawaited(_renderer.discard(path));
    }
    slot.settle();
  }

  void _releaseGate(_Slot slot) {
    if (!slot.gateHeld) return;
    slot.gateHeld = false;
    --_inFlight;
  }

  /// Tops up the ahead-buffer and hands queued clips to the engine, nearest
  /// first, without exceeding [maxConcurrentRenders].
  void _pump() {
    if (_disposed || _current == null) return;
    if (_playRequested) {
      var tail = _ahead.isEmpty ? _cursor : _ahead.last.cursor;
      while (_ahead.length < _aheadTarget && tail != null) {
        final next = _after(tail);
        if (next == null) break;
        _ahead.add(_newSlot(next));
        tail = next;
      }
    }
    for (final slot in [_current!, ..._ahead]) {
      if (_inFlight >= maxConcurrentRenders) break;
      // Prefetching only runs while playing; a paused list needs just the
      // clip it will resume with.
      if (slot != _current && !_playRequested) break;
      if (!slot.started && !slot.cancelled) _startRender(slot);
    }
  }

  void _startRender(_Slot slot) {
    slot.started = true;
    slot.gateHeld = true;
    ++_inFlight;
    slot.timeout = Timer(renderTimeout, () {
      // A hung job must not hold the gate forever. If the engine finishes
      // later, that file is discarded on arrival.
      _releaseGate(slot);
      if (slot.isSettled || slot.cancelled || _disposed) return;
      slot.error = TimeoutException('Speech synthesis timed out');
      _slotSettled(slot);
    });
    Future<String>.sync(() => _renderer.render(slot.clip)).then(
      (path) {
        slot.timeout?.cancel();
        _releaseGate(slot);
        if (slot.cancelled || slot.isSettled || _disposed) {
          unawaited(_renderer.discard(path));
        } else {
          slot.path = path;
          _slotSettled(slot);
        }
        _pump();
      },
      onError: (Object error) {
        slot.timeout?.cancel();
        _releaseGate(slot);
        if (!slot.cancelled && !slot.isSettled && !_disposed) {
          slot.error = error;
          _slotSettled(slot);
        }
        _pump();
      },
    );
  }

  void _slotSettled(_Slot slot) {
    slot.settle();
    if (_disposed || slot.cancelled) return;
    if (slot == _current) {
      _drive();
    } else {
      _preloadNext();
    }
    _pump();
  }

  /// Tells the player which file follows the one now playing so the switch
  /// needs no file open at the boundary.
  void _preloadNext() {
    if (!_audioStarted || _ahead.isEmpty) return;
    final path = _ahead.first.path;
    if (path == null || path == _preloadedPath) return;
    _preloadedPath = path;
    unawaited(_player.prepareNext(path).catchError((Object _) {}));
  }

  /// Starts the current clip's audio once it is rendered. Idempotent.
  void _drive() {
    if (_disposed || !_playRequested || _audioStarted) return;
    final slot = _current;
    if (slot == null) return;
    if (!slot.isSettled) {
      _notify(); // Shows the buffering state.
      return;
    }
    if (slot.error != null) {
      _clipFailed(slot);
      return;
    }
    final path = slot.path;
    if (path == null) return;
    _audioStarted = true;
    final epoch = _epoch;
    unawaited(_startAudio(path, epoch));
    _preloadNext();
    _notify();
  }

  Future<void> _startAudio(String path, int epoch) async {
    try {
      await _player.play(path);
      if (_disposed || epoch != _epoch) return;
      // Pause pressed while the player was still opening the file.
      if (!_playRequested) await _player.pause();
    } catch (error) {
      if (_disposed || epoch != _epoch) return;
      _audioStarted = false;
      final slot = _current;
      if (slot != null) _clipFailed(slot, error: error);
    }
  }

  void _clipFailed(_Slot slot, {Object? error}) {
    _consecutiveFailures++;
    final cause = error ?? slot.error;
    if (_consecutiveFailures >= maxConsecutiveFailures) {
      _fail('Speech stopped: $cause');
      return;
    }
    // One bad clip should not end the playlist; move on.
    _advance();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}
