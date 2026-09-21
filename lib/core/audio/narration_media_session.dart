import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'narration_diagnostics.dart';

/// What the lock screen and Control Center show for spoken narration.
@immutable
class NarrationNowPlaying {
  const NarrationNowPlaying({
    required this.title,
    required this.playing,
    this.subtitle,
    this.album,
    this.index,
    this.count,
  });

  /// The current reference, e.g. "John 3:16".
  final String title;
  final bool playing;
  final String? subtitle;
  final String? album;

  /// 1-based position in a playlist and its length, when there is one.
  final int? index;
  final int? count;

  Map<String, Object?> toMap() => {
    'title': title,
    'playing': playing,
    'subtitle': subtitle,
    'album': album,
    'index': index,
    'count': count,
  };

  @override
  bool operator ==(Object other) =>
      other is NarrationNowPlaying &&
      other.title == title &&
      other.playing == playing &&
      other.subtitle == subtitle &&
      other.album == album &&
      other.index == index &&
      other.count == count;

  @override
  int get hashCode =>
      Object.hash(title, playing, subtitle, album, index, count);
}

/// The controls an owner hands the system: the lock screen buttons and
/// interruption handling drive these and nothing else.
class NarrationTransport {
  const NarrationTransport({
    required this.isPlaying,
    required this.play,
    required this.pause,
    required this.next,
    required this.previous,
  });

  /// True from the moment playback is requested, including while the next
  /// clip is still being synthesized.
  final bool Function() isPlaying;
  final VoidCallback play;
  final VoidCallback pause;
  final VoidCallback next;
  final VoidCallback previous;
}

/// Native half of the session (iOS `NarrationMediaBridge`).
abstract class NarrationMediaPlatform {
  /// Receives system events: `command` (`play`, `pause`, `toggle`, `next`,
  /// `previous`), `interruptionBegan`, `interruptionEnded`, `routeLost`.
  void listen(void Function(String event, Object? argument) handler);
  Future<void> begin();
  Future<void> end();
  Future<void> updateNowPlaying(Map<String, Object?> info);
  Future<void> setBuffering(bool buffering);

  /// Re-asserts the playback audio session. audioplayers deactivates it
  /// whenever nothing is playing, so a resume after a pause finds it inactive.
  /// Returns false, having logged why, if iOS refused.
  Future<bool> activate();
}

class MethodChannelNarrationMediaPlatform implements NarrationMediaPlatform {
  MethodChannelNarrationMediaPlatform([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('studybible/narration_media');

  final MethodChannel _channel;

  @override
  void listen(void Function(String event, Object? argument) handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'command') {
        handler(call.arguments as String, null);
      } else {
        handler(call.method, call.arguments);
      }
    });
  }

  // Lock screen glue must never be able to break speech itself.
  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('Narration media $method failed: $error');
    } on MissingPluginException {
      /* Not running on a platform with the bridge. */
    }
  }

  @override
  Future<void> begin() => _invoke('begin');

  @override
  Future<void> end() => _invoke('end');

  @override
  Future<void> updateNowPlaying(Map<String, Object?> info) =>
      _invoke('updateNowPlaying', info);

  @override
  Future<void> setBuffering(bool buffering) =>
      _invoke('setBuffering', buffering);

  @override
  Future<bool> activate() async {
    try {
      return await _channel.invokeMethod<bool>('activate') ?? false;
    } on PlatformException catch (error) {
      NarrationDiagnostics.log('session activate PlatformException: $error');
      return false;
    } on MissingPluginException {
      return true; // No bridge on this platform: nothing to activate.
    }
  }
}

class _NoopNarrationMediaPlatform implements NarrationMediaPlatform {
  @override
  void listen(void Function(String event, Object? argument) handler) {}
  @override
  Future<void> begin() async {}
  @override
  Future<void> end() async {}
  @override
  Future<void> updateNowPlaying(Map<String, Object?> info) async {}
  @override
  Future<void> setBuffering(bool buffering) async {}
  @override
  Future<bool> activate() async => true;
}

/// One app-wide owner of the system's now-playing slot. The Bible reader and
/// the tag popup each take a [NarrationMediaLease]; the newest lease receives
/// the lock screen buttons and interruptions, and giving it up hands them
/// back to the previous one. Off iOS every call is a no-op.
class NarrationMediaSession with WidgetsBindingObserver {
  NarrationMediaSession({
    NarrationMediaPlatform? platform,
    bool? supported,
    bool observeLifecycle = true,
  }) : supported = supported ?? Platform.isIOS,
       _platform = platform ?? _defaultPlatform(supported ?? Platform.isIOS) {
    _platform.listen(_onEvent);
    if (this.supported && observeLifecycle) {
      WidgetsFlutterBinding.ensureInitialized().addObserver(this);
    }
  }

  static NarrationMediaPlatform _defaultPlatform(bool supported) => supported
      ? MethodChannelNarrationMediaPlatform()
      : _NoopNarrationMediaPlatform();

  static final NarrationMediaSession instance = NarrationMediaSession();

  /// True where the OS lets narration continue behind a locked screen.
  final bool supported;
  final NarrationMediaPlatform _platform;
  final List<NarrationMediaLease> _leases = [];

  /// True while the app is not on screen (locked or in another app). Playback
  /// buffers further ahead then, because synthesis can no longer be topped up
  /// on demand once iOS suspends the app.
  final ValueNotifier<bool> backgrounded = ValueNotifier(false);

  NarrationMediaLease? get _owner => _leases.isEmpty ? null : _leases.last;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NarrationDiagnostics.log('app lifecycle ${state.name}');
    // inactive (Control Center, an incoming call banner) is still on screen.
    backgrounded.value =
        state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
  }

  /// Takes the lock screen controls for [transport]. Call
  /// [NarrationMediaLease.dispose] when playback ends for good.
  NarrationMediaLease start(NarrationTransport transport) {
    final lease = NarrationMediaLease._(this, transport);
    NarrationDiagnostics.log('media session start (leases ${_leases.length})');
    if (_leases.isEmpty) unawaited(_platform.begin());
    _leases.add(lease);
    return lease;
  }

  void _release(NarrationMediaLease lease) {
    final wasOwner = identical(_owner, lease);
    NarrationDiagnostics.log('media session release');
    _leases.remove(lease);
    _syncBuffering();
    if (_leases.isEmpty) {
      unawaited(_platform.end());
    } else if (wasOwner) {
      _owner!._publish();
    }
  }

  /// Makes sure the audio session is active before speech is synthesized or
  /// played. Every attempt that fails is written to the event log with the
  /// [reason] it was made for; native detail (error code, category, route)
  /// follows as a `native activate` line. Returns whether iOS accepted it.
  /// Playback is still attempted on failure, so the stage that actually
  /// breaks is the one the log names.
  Future<bool> activateAudioSession(String reason) async {
    if (!supported) return true;
    final watch = Stopwatch()..start();
    var ok = false;
    try {
      ok = await _platform.activate().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      NarrationDiagnostics.log(
        'session activate ($reason) TIMED OUT after 5 s',
      );
      return false;
    } catch (error) {
      NarrationDiagnostics.log('session activate ($reason) FAILED: $error');
      return false;
    }
    if (!ok) {
      NarrationDiagnostics.log(
        'session activate ($reason) FAILED after ${watch.elapsedMilliseconds} ms',
      );
    }
    return ok;
  }

  int _holds = 0;

  /// Asks iOS for background time (about 30 s) while the returned callback has
  /// not been called. Use it around work that must finish before the next
  /// word can be spoken, such as synthesizing the next clip. Idempotent.
  VoidCallback holdBackgroundTime() {
    var released = false;
    _holds++;
    _syncBuffering();
    return () {
      if (released) return;
      released = true;
      _holds--;
      _syncBuffering();
    };
  }

  void _syncBuffering() => unawaited(
    _platform.setBuffering(_holds > 0 || _leases.any((l) => l._buffering)),
  );

  void _onEvent(String event, Object? argument) {
    // Native observations for the event log only; they never drive playback.
    if (event == 'diagnostic') {
      NarrationDiagnostics.log('native $argument');
      return;
    }
    NarrationDiagnostics.log(
      'system $event${argument == null ? '' : ' $argument'}'
      '${_owner == null ? ' (no owner, ignored)' : ''}',
    );
    _owner?._handle(event, argument);
  }

  @visibleForTesting
  void debugDeliver(String event, [Object? argument]) =>
      _onEvent(event, argument);
}

class NarrationMediaLease {
  NarrationMediaLease._(this._session, this._transport);

  final NarrationMediaSession _session;
  final NarrationTransport _transport;
  NarrationNowPlaying? _info;
  bool _buffering = false;
  bool _resumeAfterInterruption = false;
  bool _disposed = false;

  bool get _isOwner => identical(_session._owner, this);

  /// Publishes the current reference and play state to the lock screen.
  void update(NarrationNowPlaying info) {
    if (_disposed || info == _info) return;
    _info = info;
    if (_isOwner) _publish();
  }

  void _publish() {
    final info = _info;
    if (info != null) {
      unawaited(_session._platform.updateNowPlaying(info.toMap()));
    }
  }

  /// Marks that nothing is audible because the next clip is still being
  /// synthesized. iOS is asked for background time to finish it.
  void setBuffering(bool buffering) {
    if (_disposed || buffering == _buffering) return;
    _buffering = buffering;
    _session._syncBuffering();
  }

  void _handle(String event, Object? argument) {
    final transport = _transport;
    switch (event) {
      case 'play':
        _resumeAfterInterruption = false;
        if (!transport.isPlaying()) transport.play();
      case 'pause':
        _resumeAfterInterruption = false;
        if (transport.isPlaying()) transport.pause();
      case 'toggle':
        _resumeAfterInterruption = false;
        transport.isPlaying() ? transport.pause() : transport.play();
      case 'next':
        transport.next();
      case 'previous':
        transport.previous();
      case 'interruptionBegan':
        // A call, Siri or another app took the speaker. Pause now and pick
        // up again only if we were the one that was playing.
        if (transport.isPlaying()) {
          _resumeAfterInterruption = true;
          transport.pause();
        }
      case 'interruptionEnded':
        final resume =
            _resumeAfterInterruption &&
            argument is Map &&
            argument['shouldResume'] == true;
        _resumeAfterInterruption = false;
        if (resume && !transport.isPlaying()) transport.play();
      case 'routeLost':
        // Headphones unplugged: stay paused until the user asks.
        _resumeAfterInterruption = false;
        if (transport.isPlaying()) transport.pause();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _buffering = false;
    _session._release(this);
  }
}
