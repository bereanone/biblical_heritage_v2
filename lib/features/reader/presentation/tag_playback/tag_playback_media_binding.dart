import '../../../../core/audio/narration_diagnostics.dart';
import '../../../../core/audio/narration_media_session.dart';
import 'tag_playback_controller.dart';
import 'tag_playback_models.dart';

/// Connects a tag playlist to the lock screen and Control Center: shows the
/// current reference, drives play/pause/next/previous from the system buttons,
/// pauses and resumes around interruptions, and buffers deeper while the app
/// is backgrounded.
///
/// Owns the media lease only while a pass is under way (loading, playing or
/// paused), so an idle or finished popup leaves the lock screen alone.
class TagPlaybackMediaBinding {
  TagPlaybackMediaBinding({
    required this.controller,
    required this.tag,
    NarrationMediaSession? session,
  }) : _session = session ?? NarrationMediaSession.instance {
    controller.addListener(_sync);
    _session.backgrounded.addListener(_syncBackgrounded);
    _syncBackgrounded();
    _sync();
  }

  final TagPlaybackController controller;
  final String tag;
  final NarrationMediaSession _session;
  NarrationMediaLease? _lease;

  bool get _wantsPlayback =>
      controller.status == TagPlaybackStatus.playing ||
      controller.status == TagPlaybackStatus.loading;

  void _syncBackgrounded() =>
      controller.setBackgrounded(_session.backgrounded.value);

  String? _lastLogged;

  void _sync() {
    final status = controller.status;
    final state =
        '${status.name} entry ${controller.currentIndex + 1}/'
        '${controller.entryCount} loop=${controller.loop}'
        '${controller.errorMessage == null ? '' : ' error=${controller.errorMessage}'}';
    if (state != _lastLogged) {
      _lastLogged = state;
      NarrationDiagnostics.log('tag $state');
    }
    final underway =
        status == TagPlaybackStatus.loading ||
        status == TagPlaybackStatus.playing ||
        status == TagPlaybackStatus.paused;
    if (!underway) {
      _lease?.dispose();
      _lease = null;
      return;
    }
    final lease = _lease ??= _session.start(
      NarrationTransport(
        isPlaying: () => _wantsPlayback,
        play: controller.play,
        pause: controller.pause,
        next: controller.next,
        previous: controller.previous,
      ),
    );
    lease.update(
      NarrationNowPlaying(
        title: controller.currentItem?.label ?? tag,
        subtitle: 'Listen · $tag',
        playing: status != TagPlaybackStatus.paused,
        index: controller.entryCount == 0 ? null : controller.currentIndex + 1,
        count: controller.entryCount == 0 ? null : controller.entryCount,
      ),
    );
    // Nothing is audible while the next clip renders; ask iOS for the time to
    // finish it if the screen is locked.
    lease.setBuffering(status == TagPlaybackStatus.loading);
  }

  /// Must run before the controller is disposed.
  void dispose() {
    controller.removeListener(_sync);
    _session.backgrounded.removeListener(_syncBackgrounded);
    _lease?.dispose();
    _lease = null;
  }
}
