/// A cursor belongs to a book reader, never to the Bible verse map.
class LibrarySpeechItem {
  const LibrarySpeechItem({
    required this.cursor,
    required this.nextCursor,
    required this.text,
    String? sourceCursor,
    this.startOffset = 0,
    this.sourceLength,
    this.showSectionStart = false,
    this.showMarginNotes = false,
    this.marginNoteIndex,
    this.marginNoteProgress,
  }) : sourceCursor = sourceCursor ?? cursor;

  /// Show the chapter heading while its opening announcement is spoken.
  final bool showSectionStart;

  /// Expand the notes attached to this paragraph while their recording plays.
  final bool showMarginNotes;

  /// Which linked note group is being spoken, and progress through that group.
  /// Readers use this to keep long expanded notes aligned with recorded audio.
  final int? marginNoteIndex;
  final double? marginNoteProgress;
  final String sourceCursor;
  final int startOffset;

  /// Length of the whole reader block this slice was cut from, so a reader can
  /// estimate how far into the paragraph the voice has moved.
  final int? sourceLength;
  final String cursor;
  final String nextCursor;
  final String text;
}

class LibrarySpeechQueue {
  LibrarySpeechQueue({
    required this.load,
    required this.reveal,
    required this.speak,
    required this.stopAudio,
    required this.onEnd,
    required this.onError,
  });
  final Future<LibrarySpeechItem?> Function(String) load;
  final Future<void> Function(LibrarySpeechItem) reveal;
  final Future<void> Function(LibrarySpeechItem) speak;
  final Future<void> Function() stopAudio;
  final void Function() onEnd;
  final void Function(Object) onError;
  int _generation = 0;
  bool running = false;
  bool _advancing = false;
  bool _completionPending = false;
  bool _awaitingCompletion = false;
  Future<void> _stopBarrier = Future<void>.value();
  LibrarySpeechItem? current;

  Future<void> start(String cursor) async {
    if (running) return;
    final beforeWait = _generation;
    await _stopBarrier;
    if (running || beforeWait != _generation) return;
    running = true;
    final generation = ++_generation;
    await _advance(cursor, generation);
  }

  Future<void> completed() async {
    final item = current;
    if (!running || item == null || !_awaitingCompletion) return;
    _awaitingCompletion = false;
    if (_advancing) {
      _completionPending = true;
      return;
    }
    await _advance(item.nextCursor, _generation);
  }

  Future<void> _advance(String cursor, int generation) async {
    _advancing = true;
    _awaitingCompletion = false;
    try {
      final item = await load(cursor);
      if (!running || generation != _generation) return;
      if (item == null) {
        running = false;
        current = null;
        onEnd();
        return;
      }
      if (item.nextCursor == item.cursor || item.text.trim().isEmpty) {
        throw StateError('The book contains an invalid narration item.');
      }
      current = item;
      await reveal(item);
      if (!running || generation != _generation) return;
      _awaitingCompletion = true;
      await speak(item);
    } catch (error) {
      if (generation == _generation && running) {
        running = false;
        onError(error);
      }
    } finally {
      if (generation == _generation) {
        _advancing = false;
        if (_completionPending && running) {
          _completionPending = false;
          final item = current;
          if (item != null) await _advance(item.nextCursor, generation);
        }
      }
    }
  }

  Future<void> stop() async {
    ++_generation;
    running = false;
    _advancing = false;
    current = null;
    _completionPending = false;
    _awaitingCompletion = false;
    _stopBarrier = stopAudio();
    await _stopBarrier;
  }
}

/// Bounded, exact slices of a reader block. Rendering still uses its source cursor.
class LibrarySpeechSegmenter {
  LibrarySpeechSegmenter(this.loadBlock);
  final Future<LibrarySpeechItem?> Function(String) loadBlock;
  static const maximumCharacters = 320;
  static const _separator = '|speech:';

  Future<LibrarySpeechItem?> load(String cursor) async {
    final marker = cursor.lastIndexOf(_separator);
    final blockCursor = marker < 0 ? cursor : cursor.substring(0, marker);
    final start = marker < 0
        ? 0
        : int.parse(cursor.substring(marker + _separator.length));
    final block = await loadBlock(blockCursor);
    if (block == null) return null;
    final text = block.text;
    if (start < 0 || start >= text.length) {
      throw StateError('Invalid speech segment offset.');
    }
    var end = text.length;
    if (text.length - start > maximumCharacters) {
      final window = text.substring(start, start + maximumCharacters);
      // Prefer a complete sentence, then a clause, then a word boundary.
      final sentences = RegExp(
        r'''[.!?][”'’"]?\s+''',
      ).allMatches(window).where((m) => m.end >= 100).toList();
      final clauses = RegExp(
        r'[,;:]\s+',
      ).allMatches(window).where((m) => m.end >= 160).toList();
      final spaces = RegExp(r'\s+').allMatches(window).toList();
      if (sentences.isNotEmpty) {
        end = start + sentences.last.end;
      } else if (clauses.isNotEmpty) {
        end = start + clauses.last.end;
      } else if (spaces.isNotEmpty) {
        end = start + spaces.last.end;
      } else {
        // Do not split a single long token or a Unicode surrogate pair.
        final nextSpace = RegExp(
          r'\s+',
        ).firstMatch(text.substring(start + maximumCharacters));
        end = nextSpace == null
            ? text.length
            : start + maximumCharacters + nextSpace.end;
      }
    }
    return LibrarySpeechItem(
      cursor: '${block.cursor}$_separator$start',
      sourceCursor: block.cursor,
      startOffset: start,
      sourceLength: text.length,
      nextCursor: end < text.length
          ? '${block.cursor}$_separator$end'
          : block.nextCursor,
      text: text.substring(start, end),
    );
  }
}
