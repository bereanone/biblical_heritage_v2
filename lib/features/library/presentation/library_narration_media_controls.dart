import 'dart:ui' show VoidCallback;

import '../../../core/audio/narration_media_session.dart';
import 'mac_reader_autoscroll_controller.dart';

/// Connects eLibrary book narration to the lock screen and Control Center,
/// the same way `BibleNarrationMediaControls` does for the Bible reader: Now
/// Playing shows the book, the system buttons drive narration, and
/// interruptions pause then resume it.
///
/// Book narration is "autoscroll in narration mode": playing means the
/// controller is scrolling, pausing means stopping it. Holding the media
/// lease is also what keeps iOS from suspending the app behind a locked
/// screen, so without it narration ends the moment the screen turns off.
///
/// The lease is taken when narration first starts and kept while it is paused
/// (so the lock screen can resume it) until narration mode is switched off or
/// the reader closes.
/// True when [autoscroll] is speaking book narration that the OS lets continue
/// behind a locked screen or another app. Reader lifecycle handlers must not
/// stop narration in that case, or it ends the moment the screen turns off.
bool librarySpeechSurvivesBackground(
  MacReaderAutoScrollController autoscroll, {
  NarrationMediaSession? session,
}) =>
    (session ?? NarrationMediaSession.instance).supported &&
    autoscroll.isNarrationMode &&
    autoscroll.isScrolling;

class LibraryNarrationMediaControls {
  LibraryNarrationMediaControls({
    required this.autoscroll,
    required this.title,
    required this.next,
    required this.previous,
    this.author,
    NarrationMediaSession? session,
  }) : _session = session ?? NarrationMediaSession.instance {
    autoscroll.addListener(_sync);
    _sync();
  }

  final MacReaderAutoScrollController autoscroll;
  final String title;
  final String? author;

  /// Skips to the next paragraph, and back to the start of the current one.
  final VoidCallback next;
  final VoidCallback previous;
  final NarrationMediaSession _session;
  NarrationMediaLease? _lease;

  bool get isNarrating => autoscroll.isNarrationMode && autoscroll.isScrolling;

  /// True when leaving the screen should not stop narration: the OS lets it
  /// continue behind a locked screen and it is actually speaking.
  bool get keepsSpeakingInBackground =>
      librarySpeechSurvivesBackground(autoscroll, session: _session);

  void _sync() {
    if (!autoscroll.isNarrationMode) {
      _release();
      return;
    }
    if (_lease == null && !isNarrating) return;
    final lease = _lease ??= _session.start(
      NarrationTransport(
        isPlaying: () => isNarrating,
        play: () => autoscroll.setSignedStep(1),
        pause: autoscroll.stopForManualInteraction,
        next: next,
        previous: previous,
      ),
    );
    lease.update(
      NarrationNowPlaying(title: title, subtitle: author, playing: isNarrating),
    );
  }

  void _release() {
    _lease?.dispose();
    _lease = null;
  }

  /// Must run before [autoscroll] is disposed.
  void dispose() {
    autoscroll.removeListener(_sync);
    _release();
  }
}
