import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/audio/narration_media_session.dart';

class BundledChapter {
  const BundledChapter({
    required this.book,
    required this.chapter,
    required this.asset,
    required this.audioSha256,
    required this.durationSeconds,
    required this.segmentStarts,
    required this.verseStarts,
  });

  final int book;
  final int chapter;
  final String asset;
  final String audioSha256;
  final double durationSeconds;
  final List<BundledSegmentStart> segmentStarts;
  final List<BundledVerseStart> verseStarts;

  double? secondsForVerse(int verse) {
    for (final start in verseStarts) {
      if (start.verse == verse) return start.seconds;
    }
    return null;
  }

  int? verseForPosition(double seconds) {
    if (verseStarts.isEmpty) return null;
    var verse = verseStarts.first.verse;
    for (final start in verseStarts.skip(1)) {
      if (seconds < start.seconds) break;
      verse = start.verse;
    }
    return verse;
  }

  (double, double)? rangeForVerse(int verse) {
    final index = verseStarts.indexWhere((start) => start.verse == verse);
    if (index < 0) return null;
    final start = verseStarts[index].seconds;
    final end = index + 1 < verseStarts.length
        ? verseStarts[index + 1].seconds
        : durationSeconds;
    return end > start ? (start, end) : null;
  }

  static BundledChapter fromJson(Map<String, dynamic> json) => BundledChapter(
    book: (json['book'] as num).toInt(),
    chapter: (json['chapter'] as num).toInt(),
    asset: json['asset'] as String,
    audioSha256: json['audioSha256'] as String,
    durationSeconds: (json['durationSeconds'] as num).toDouble(),
    segmentStarts: (json['segmentStarts'] as List<dynamic>)
        .map(
          (item) => BundledSegmentStart.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false),
    verseStarts: ((json['verseStarts'] as List<dynamic>?) ?? const [])
        .map((item) => BundledVerseStart.fromJson(item as Map<String, dynamic>))
        .toList(growable: false),
  );
}

class BundledVerseStart {
  const BundledVerseStart({required this.verse, required this.seconds});
  final int verse;
  final double seconds;

  static BundledVerseStart fromJson(Map<String, dynamic> json) =>
      BundledVerseStart(
        verse: (json['verse'] as num).toInt(),
        seconds: (json['seconds'] as num).toDouble(),
      );
}

class BundledSegmentStart {
  const BundledSegmentStart({required this.seconds, required this.firstVerse});
  final double seconds;
  final int firstVerse;

  static BundledSegmentStart fromJson(Map<String, dynamic> json) =>
      BundledSegmentStart(
        seconds: (json['seconds'] as num).toDouble(),
        firstVerse: (json['firstVerse'] as num).toInt(),
      );
}

/// Plays the shipped recordings; the segment markers identify recorded group
/// boundaries, never invented timings for individual verses within a group.
class BundledBibleAudioNarrator extends ChangeNotifier {
  BundledBibleAudioNarrator({
    required this.onSegmentStart,
    required this.onChapterComplete,
    required this.onError,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'complete' && !_disposed) {
        _playing = false;
        notifyListeners();
        onChapterComplete();
      } else if (call.method == 'looped' && !_disposed) {
        final chapter = _current;
        if (chapter != null) {
          final verse = _repeatVerse ?? 1;
          _position = chapter.secondsForVerse(verse) ?? 0;
          _lastSegment = -1;
          onSegmentStart(chapter, verse);
          notifyListeners();
        }
      } else if (call.method == 'error' && !_disposed) {
        _playing = false;
        notifyListeners();
        onError(
          call.arguments?.toString() ?? 'Audio output changed unexpectedly',
        );
      }
    });
  }

  static const _channel = MethodChannel('studybible/recorded_audio');
  static const _catalogAsset = 'assets/audio/qwen_bible/catalog.json';

  final void Function(BundledChapter chapter, int firstVerse) onSegmentStart;
  final VoidCallback onChapterComplete;
  final void Function(String message) onError;

  Future<void>? _catalogLoad;
  final List<BundledChapter> _chapters = [];
  final Map<String, BundledChapter> _byReference = {};
  Timer? _poll;
  bool _polling = false;
  int _diagnosticTicks = 0;
  bool _disposed = false;
  int _generation = 0;
  bool _playing = false;
  double _position = 0;
  double _rate = 1;
  int _lastSegment = -1;
  BundledChapter? _current;
  int? _repeatVerse;

  bool get playing => _playing;
  double get position => _position;
  double get rate => _rate;
  BundledChapter? get current => _current;

  String _key(int book, int chapter) => '$book-$chapter';

  Future<void> loadCatalog() => _catalogLoad ??= _readCatalog();

  Future<void> _readCatalog() async {
    final data =
        jsonDecode(await rootBundle.loadString(_catalogAsset))
            as Map<String, dynamic>;
    final rows = data['chapters'] as List<dynamic>;
    if (rows.length != 1189) throw StateError('Incomplete bundled Bible audio');
    for (final row in rows) {
      final chapter = BundledChapter.fromJson(row as Map<String, dynamic>);
      _chapters.add(chapter);
      _byReference[_key(chapter.book, chapter.chapter)] = chapter;
    }
    if (_byReference.length != rows.length) {
      throw StateError('Duplicate bundled chapter references');
    }
  }

  Future<BundledChapter?> chapter(int book, int chapter) async {
    await loadCatalog();
    return _byReference[_key(book, chapter)];
  }

  Future<BundledChapter?> adjacentChapter(
    int book,
    int chapter,
    int step,
  ) async {
    await loadCatalog();
    final index = _chapters.indexWhere(
      (entry) => entry.book == book && entry.chapter == chapter,
    );
    final target = index + step;
    if (index < 0 || target < 0 || target >= _chapters.length) return null;
    return _chapters[target];
  }

  Future<String> _materialize(BundledChapter chapter) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/qwen_bible',
    );
    await directory.create(recursive: true);
    final filename = chapter.asset.split('/').last;
    final destination = File(
      '${directory.path}/${chapter.audioSha256.substring(0, 16)}_$filename',
    );
    if (await destination.exists() && await destination.length() > 0) {
      return destination.path;
    }
    final bytes = await rootBundle.load(chapter.asset);
    final temporary = File('${destination.path}.copying');
    await temporary.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    await temporary.rename(destination.path);
    return destination.path;
  }

  Future<void> playChapter(
    int book,
    int chapter, {
    int startVerse = 1,
    int? repeatVerse,
    bool repeatChapter = false,
  }) async {
    final generation = ++_generation;
    debugPrint('Qwen chapter request $book:$chapter');
    final item = await this.chapter(book, chapter);
    debugPrint('Qwen chapter catalog found=${item != null}');
    if (item == null) {
      throw StateError('Recording unavailable for $book:$chapter');
    }
    final startSeconds = startVerse == 1
        ? (repeatVerse == 1 ? item.secondsForVerse(1) ?? 0.0 : 0.0)
        : item.secondsForVerse(startVerse);
    if (startSeconds == null) {
      throw StateError(
        'Precise verse timing unavailable for $book:$chapter:$startVerse',
      );
    }
    final path = await _materialize(item);
    debugPrint('Qwen chapter copied $path');
    if (_disposed || generation != _generation) return;
    await _channel.invokeMethod<void>('load', {'path': path});
    debugPrint('Qwen native file loaded');
    if (_disposed || generation != _generation) return;
    // The old test player can change this shared native bridge. A new chapter
    // always starts at natural pitch; rate changes preserve that pitch.
    await _channel.invokeMethod<void>('setPitch', {'pitch': 0.0});
    await _channel.invokeMethod<void>('setRate', {'rate': _rate});
    if (_disposed || generation != _generation) return;
    if (repeatVerse != null || repeatChapter) {
      final range = repeatVerse != null
          ? item.rangeForVerse(repeatVerse)
          : (0.0, item.durationSeconds);
      if (range == null) {
        throw StateError('Precise verse timing unavailable for repeat');
      }
      await _channel.invokeMethod<void>('setLoopRange', {
        'startSeconds': range.$1,
        'endSeconds': range.$2,
      });
    }
    if (startSeconds > 0) {
      await _channel.invokeMethod<void>('seek', {'seconds': startSeconds});
    }
    _current = item;
    _repeatVerse = repeatVerse;
    _position = startSeconds;
    _lastSegment = -1;
    // The previously audible recorded-audio screen explicitly reactivates
    // the shared iOS session immediately before play. The reader's media lease
    // starts asynchronously, so do the same here to avoid a begin/end race.
    final activated = await NarrationMediaSession.instance.activateAudioSession(
      'bundled Bible',
    );
    debugPrint('Qwen audio session activated=$activated');
    await _channel.invokeMethod<void>('play');
    debugPrint('Qwen native play acknowledged');
    _playing = true;
    notifyListeners();
    _startPoll();
  }

  Future<void> setLoopForCurrent({
    int? verse,
    bool chapter = false,
    bool restart = false,
  }) async {
    final item = _current;
    if (item == null) return;
    final (double, double)? range = verse != null
        ? item.rangeForVerse(verse)
        : chapter
        ? (0.0, item.durationSeconds)
        : null;
    if (verse != null && range == null) {
      throw StateError('Precise verse timing unavailable for repeat');
    }
    await _channel.invokeMethod<void>('setLoopRange', {
      'startSeconds': range?.$1,
      'endSeconds': range?.$2,
      'restart': restart,
    });
    _repeatVerse = verse;
    if (restart && range != null) {
      _position = range.$1;
      _lastSegment = -1;
    }
  }

  Future<void> resume() async {
    if (_current == null) return;
    final activated = await NarrationMediaSession.instance.activateAudioSession(
      'bundled Bible resume',
    );
    debugPrint('Qwen audio session resume activated=$activated');
    await _channel.invokeMethod<void>('play');
    _playing = true;
    notifyListeners();
    _startPoll();
  }

  Future<void> pause() async {
    ++_generation;
    if (!_playing) return;
    await _channel.invokeMethod<void>('pause');
    _playing = false;
    notifyListeners();
  }

  Future<void> stop() async {
    ++_generation;
    _poll?.cancel();
    await _channel.invokeMethod<void>('stop');
    _current = null;
    _repeatVerse = null;
    _position = 0;
    _playing = false;
    notifyListeners();
  }

  Future<void> setRate(double value) async {
    _rate = value.clamp(0.75, 1.5);
    await _channel.invokeMethod<void>('setRate', {'rate': _rate});
    notifyListeners();
  }

  Future<void> seek(double seconds) async {
    if (_current == null) return;
    await _channel.invokeMethod<void>('seek', {
      'seconds': seconds.clamp(0.0, _current!.durationSeconds),
    });
    _lastSegment = -1;
    await _readState();
  }

  Future<void> seekToVerse(int verse) async {
    final chapter = _current;
    if (chapter == null) return;
    final seconds = verse == 1 ? 0.0 : chapter.secondsForVerse(verse);
    if (seconds == null) {
      throw StateError(
        'Precise verse timing unavailable for ${chapter.book}:${chapter.chapter}:$verse',
      );
    }
    await seek(seconds);
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_polling && !_disposed) unawaited(_readState());
    });
  }

  Future<void> _readState() async {
    final chapter = _current;
    if (chapter == null) return;
    _polling = true;
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('state');
      if (state == null || _disposed || chapter != _current) return;
      if (_diagnosticTicks++ % 10 == 0) {
        debugPrint('Qwen native state $state');
      }
      _position = (state['position'] as num?)?.toDouble() ?? 0;
      _playing = state['playing'] as bool? ?? false;
      final verseStarts = chapter.verseStarts;
      final starts = verseStarts.isNotEmpty
          ? verseStarts.map((entry) => (entry.seconds, entry.verse)).toList()
          : chapter.segmentStarts
                .map((entry) => (entry.seconds, entry.firstVerse))
                .toList();
      var segment = 0;
      for (var i = 1; i < starts.length; i++) {
        if (_position < starts[i].$1) break;
        segment = i;
      }
      if (segment != _lastSegment && starts.isNotEmpty && _playing) {
        _lastSegment = segment;
        onSegmentStart(chapter, starts[segment].$2);
      }
      notifyListeners();
    } catch (error) {
      _poll?.cancel();
      onError(error.toString());
    } finally {
      _polling = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _poll?.cancel();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('stop').catchError((Object _) {}));
    super.dispose();
  }
}
