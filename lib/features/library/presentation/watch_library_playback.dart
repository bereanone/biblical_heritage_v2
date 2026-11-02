/// The phone's native recording state. The Watch is a remote for this player.
class WatchLibraryPlayback {
  const WatchLibraryPlayback({
    required this.bookId,
    required this.chapter,
    required this.paragraph,
    required this.position,
    required this.playing,
    required this.nativePlayback,
    required this.loop,
    this.duration = Duration.zero,
    this.pending = false,
    this.readingRate = 1,
  });

  final double readingRate;
  final String bookId;
  final int chapter;
  final int paragraph;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool pending;
  final bool nativePlayback;
  final String loop;

  String? get readerLoop => switch (loop) {
    'verse' => 'paragraph',
    'book' || 'chapter' => loop,
    _ => null,
  };

  static WatchLibraryPlayback? fromNative(Object? value) {
    if (value is! Map || value['libraryBookID'] is! String) return null;
    final chapter = value['chapter'], paragraph = value['verse'];
    final milliseconds = value['position_ms'];
    if (chapter is! int ||
        chapter < 1 ||
        paragraph is! int ||
        paragraph < 1 ||
        milliseconds is! int ||
        milliseconds < 0) {
      return null;
    }
    final duration = value['duration_ms'];
    final rate = value['reading_rate'];
    return WatchLibraryPlayback(
      bookId: value['libraryBookID'] as String,
      readingRate: rate is num && rate.isFinite
          ? (rate.toDouble().clamp(.75, 1.5) * 20).round() / 20
          : 1,
      chapter: chapter,
      paragraph: paragraph,
      position: Duration(milliseconds: milliseconds),
      duration: duration is int && duration > 0
          ? Duration(milliseconds: duration)
          : Duration.zero,
      playing: value['playing'] == true,
      pending: value['pending'] == true,
      nativePlayback: value['nativePlayback'] == true,
      loop: value['loop'] is String ? value['loop'] as String : 'off',
    );
  }
}
