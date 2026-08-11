import 'package:flutter/foundation.dart';

import '../../../core/database/study_bible_database.dart';
import 'reader_autoscroll_diagnostics.dart';
import 'viewer_passage_models.dart';

class ViewerDataController extends ChangeNotifier {
  ViewerDataController({StudyBibleDatabase? database})
    : _database = database ?? StudyBibleDatabase.instance;

  static const int minId = 1;
  static const int windowRadius = 50;

  final StudyBibleDatabase _database;
  final Map<int, VerseLine> _blocks = <int, VerseLine>{};

  bool _initialized = false;
  bool _isLoading = false;
  int _maxBlockId = 1;
  int _currentCenter = -1;
  int? _pendingCenter;
  int? _pendingRadius;
  bool _retainWindowForAutoScroll = false;
  bool _preserveExpandedCache = false;

  bool get isLoading => _isLoading;
  int get maxBlockId => _maxBlockId;

  VerseLine? getBlock(int blockId) => _blocks[blockId];

  List<int> get loadedBlockIds {
    final ids = _blocks.keys.toList(growable: false);
    ids.sort();
    return ids;
  }

  List<VerseLine> get loadedLines {
    final ids = loadedBlockIds;
    return ids
        .map((id) => _blocks[id])
        .whereType<VerseLine>()
        .toList(growable: false);
  }

  int? get firstBlockId {
    final ids = loadedBlockIds;
    return ids.isEmpty ? null : ids.first;
  }

  int? get lastBlockId {
    final ids = loadedBlockIds;
    return ids.isEmpty ? null : ids.last;
  }

  VerseLine? previousLoadedBlock(int blockId) {
    final ids = loadedBlockIds;
    final index = ids.indexOf(blockId);
    if (index <= 0) return null;
    return _blocks[ids[index - 1]];
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _maxBlockId = await _database.loadMaxBlockId();
    _initialized = true;
  }

  Future<void> ensureWindow(int centerId) =>
      _ensureWindow(centerId, radius: windowRadius);

  Future<void> ensureAutoScrollWindow(int visibleId, {required int direction}) {
    beginAutoScroll();
    const activeRadius = 125;
    const directionalOffset = 75;
    final target = (visibleId + (direction < 0 ? -1 : 1) * directionalOffset)
        .clamp(minId, _maxBlockId);
    return _ensureWindow(target, radius: activeRadius);
  }

  Future<void> _ensureWindow(int centerId, {required int radius}) async {
    await initialize();
    if (_isLoading) {
      _pendingCenter = centerId;
      _pendingRadius = radius;
      return;
    }
    if ((centerId - _currentCenter).abs() < 15 && _blocks.isNotEmpty) {
      return;
    }

    _isLoading = true;
    try {
      final targetCenter = centerId.clamp(minId, _maxBlockId);
      if (readerAutoScrollDiagnostics.isCapturing) {
        readerAutoScrollDiagnostics.recordEvent(
          'load_block_window_start center=$targetCenter radius=$radius',
        );
      }
      final queryStopwatch = readerAutoScrollDiagnostics.isCapturing
          ? (Stopwatch()..start())
          : null;
      var fetched = await _database.loadBlockWindowById(
        targetCenter,
        windowRadius: radius,
      );
      if (queryStopwatch != null) {
        readerAutoScrollDiagnostics.recordEvent(
          'load_block_window_done rows=${fetched.length} '
          'us=${queryStopwatch.elapsedMicroseconds}',
        );
      }
      if (fetched.isEmpty) {
        fetched = await _chapterFallback(targetCenter);
      }
      if (fetched.isEmpty) {
        throw StateError('No Bible blocks loaded for anchor $targetCenter.');
      }

      for (final row in fetched) {
        final line = _mapLine(row, fallbackBookNumber: 1, fallbackChapter: 1);
        final blockId = line.blockId ?? 0;
        if (blockId <= 0) continue;
        _blocks[blockId] = line;
      }

      if (!_preserveExpandedCache) _trimWindow(targetCenter);

      _currentCenter = targetCenter;
      notifyListeners();
    } finally {
      _isLoading = false;
      if (_pendingCenter != null) {
        final next = _pendingCenter!;
        final nextRadius = _pendingRadius ?? windowRadius;
        _pendingCenter = null;
        _pendingRadius = null;
        _ensureWindow(next, radius: nextRadius);
      }
    }
  }

  void beginAutoScroll() {
    _retainWindowForAutoScroll = true;
    _preserveExpandedCache = true;
  }

  void endAutoScroll(int centerId) {
    if (!_retainWindowForAutoScroll) return;
    _retainWindowForAutoScroll = false;
    final targetCenter = centerId.clamp(minId, _maxBlockId);
    _currentCenter = targetCenter;
  }

  void _trimWindow(int centerId) {
    final minKeep = centerId - windowRadius;
    final maxKeep = centerId + windowRadius;
    _blocks.removeWhere((id, _) => id < minKeep || id > maxKeep);
  }

  Future<List<Map<String, Object?>>> _chapterFallback(int centerId) async {
    final reference = await _database.loadReferenceForBlockId(centerId);
    if (reference == null) return const <Map<String, Object?>>[];
    final rows = await _database.loadBlocks(
      bookNumber: reference.bookNumber,
      chapter: reference.chapter,
    );
    return rows
        .map(
          (row) => <String, Object?>{
            'id': row['id'],
            'book_number': reference.bookNumber,
            'chapter': reference.chapter,
            'block_index': row['block_index'],
            'html': row['html'],
            'plain_text': row['plain_text'],
          },
        )
        .toList(growable: false);
  }

  VerseLine _mapLine(
    Map<String, Object?> row, {
    required int fallbackBookNumber,
    required int fallbackChapter,
  }) {
    return VerseLine(
      blockId: (row['id'] as num?)?.toInt(),
      bookNumber: (row['book_number'] as num?)?.toInt() ?? fallbackBookNumber,
      chapter: (row['chapter'] as num?)?.toInt() ?? fallbackChapter,
      verse: (row['block_index'] as num?)?.toInt() ?? 0,
      html: (row['html'] as String?) ?? '',
      text: (row['plain_text'] as String?) ?? '',
    );
  }
}
