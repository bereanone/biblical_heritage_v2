import '../../../core/audio/narration_media_session.dart';
import '../../library/presentation/mac_reader_autoscroll_controller.dart';
import 'bible_visible_location_controller.dart';

/// Connects the Bible reader's narration to the lock screen and Control
/// Center, the same way [TagPlaybackMediaBinding] does for the tag popup:
/// Now Playing shows the verse being read, the system buttons drive
/// narration, and interruptions pause then resume it.
///
/// Reader narration is "autoscroll in narration mode": playing means the
/// controller is scrolling, pausing means stopping it, so the transport maps
/// onto those two calls and the reader's own listeners do the rest.
///
/// The media lease is taken when narration first starts and kept while it is
/// paused (so the lock screen can resume it) until narration mode is switched
/// off or the reader closes.
class BibleNarrationMediaControls {
  BibleNarrationMediaControls({
    required this.autoscroll,
    required this.location,
    required this.bookNames,
    required this.skip,
    this.chapterOnly = false,
    NarrationMediaSession? session,
  }) : _session = session ?? NarrationMediaSession.instance {
    autoscroll.addListener(_sync);
    location.addListener(_sync);
    _sync();
  }

  final MacReaderAutoScrollController autoscroll;
  final BibleLiveReferenceController location;

  /// Book number to name; filled in by the reader after construction.
  final Map<int, String> bookNames;

  /// Moves narration by whole verses (+1 next, -1 previous).
  final void Function(int delta) skip;
  final bool chapterOnly;
  final NarrationMediaSession _session;
  NarrationMediaLease? _lease;

  bool get isNarrating => autoscroll.isNarrationMode && autoscroll.isScrolling;

  /// True when leaving the screen should not stop narration: the OS lets it
  /// continue behind a locked screen and it is actually speaking.
  bool get keepsSpeakingInBackground => _session.supported && isNarrating;

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
        next: () => skip(1),
        previous: () => skip(-1),
      ),
    );
    lease.update(
      NarrationNowPlaying(
        title: _reference(location.value) ?? 'Bible narration',
        subtitle: 'Bible',
        playing: isNarrating,
      ),
    );
  }

  String? _reference(BibleVisibleLocation? spoken) {
    if (spoken == null) return null;
    final book = bookNames[spoken.bookNumber] ?? 'Book ${spoken.bookNumber}';
    return chapterOnly
        ? '$book ${spoken.chapter}'
        : '$book ${spoken.chapter}:${spoken.verse}';
  }

  void _release() {
    _lease?.dispose();
    _lease = null;
  }

  /// Must run before [autoscroll] and [location] are disposed.
  void dispose() {
    autoscroll.removeListener(_sync);
    location.removeListener(_sync);
    _release();
  }
}
