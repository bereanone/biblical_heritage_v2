import 'package:flutter/foundation.dart';

import '../../../core/database/study_bible_database.dart';
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

  Future<void> ensureWindow(int centerId) async {
    await initialize();
    if (_isLoading) {
      _pendingCenter = centerId;
      return;
    }
    if ((centerId - _currentCenter).abs() < 15 && _blocks.isNotEmpty) {
      return;
    }

    _isLoading = true;
    try {
      final targetCenter = centerId.clamp(minId, _maxBlockId);
      var fetched = await _database.loadBlockWindowById(
        targetCenter,
        windowRadius: windowRadius,
      );
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

      final minKeep = targetCenter - windowRadius;
      final maxKeep = targetCenter + windowRadius;
      _blocks.removeWhere((id, _) => id < minKeep || id > maxKeep);

      _currentCenter = targetCenter;
      notifyListeners();
    } finally {
      _isLoading = false;
      if (_pendingCenter != null) {
        final next = _pendingCenter!;
        _pendingCenter = null;
        ensureWindow(next);
      }
    }
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
