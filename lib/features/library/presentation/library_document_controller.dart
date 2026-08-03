import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/library_document_models.dart';
import '../data/library_document_repository.dart';

class LibraryDocumentController extends ChangeNotifier {
  LibraryDocumentController({
    required this.libraryItemId,
    required this.repository,
    this.windowRadius = 50,
  });
  final String libraryItemId;
  final LibraryDocumentRepository repository;
  final int windowRadius;
  final Map<int, LibraryDocumentBlock> _blocks = <int, LibraryDocumentBlock>{};
  final Map<int, LibraryDocumentBlock> _primaryHeadings =
      <int, LibraryDocumentBlock>{};
  int _count = 0;
  int _center = -1;
  int? _loadedFirst;
  int? _loadedLast;
  bool _loading = false;
  bool _disposed = false;
  int? _pending;
  bool _autoScrolling = false;
  bool _preserveExpandedCache = false;
  int _autoScrollDirection = 1;

  static const int autoScrollAhead = 200;
  static const int autoScrollBehind = 75;

  int get blockCount => _count;
  LibraryDocumentBlock? blockAt(int order) => _blocks[order];
  LibraryDocumentBlock? headingAtOrBefore(int order) {
    final knownPrimaryOrders =
        _primaryHeadings.keys.where((candidate) => candidate <= order).toList()
          ..sort();
    if (knownPrimaryOrders.isNotEmpty) {
      return _primaryHeadings[knownPrimaryOrders.last];
    }
    LibraryDocumentBlock? nearestSecondary;
    for (var candidate = order; candidate >= 0; candidate--) {
      final block = _blocks[candidate];
      if (block?.isPrimaryChapterHeading == true) return block;
      if (nearestSecondary == null && block?.isHeading == true) {
        nearestSecondary = block;
      }
    }
    return nearestSecondary;
  }

  List<int> get loadedOrders => (_blocks.keys.toList()..sort());

  Future<void> initialize({int centerOrder = 0}) async {
    _count = await repository.blockCount(libraryItemId);
    await ensureWindow(centerOrder);
  }

  Future<void> ensureWindow(int centerOrder) async {
    if (_loading) {
      _pending = centerOrder;
      return;
    }
    if (_count == 0) {
      _count = await repository.blockCount(libraryItemId);
    }
    if (_count == 0) return;
    final visibleTarget = centerOrder.clamp(0, _count - 1);
    if (_autoScrolling && _blocks.isNotEmpty) {
      final required = math.min(
        150,
        _autoScrollDirection > 0 ? _count - 1 - visibleTarget : visibleTarget,
      );
      final available = _autoScrollDirection > 0
          ? (_loadedLast ?? -1) - visibleTarget
          : visibleTarget - (_loadedFirst ?? _count);
      if (available >= required) return;
    }
    if (!_autoScrolling &&
        _blocks.isNotEmpty &&
        (visibleTarget - _center).abs() < windowRadius ~/ 3) {
      return;
    }
    final activeRadius = (autoScrollAhead + autoScrollBehind + 1) ~/ 2;
    final activeOffset = (autoScrollAhead - autoScrollBehind) ~/ 2;
    final radius = _autoScrolling ? activeRadius : windowRadius;
    final target = _autoScrolling
        ? (visibleTarget + _autoScrollDirection * activeOffset).clamp(
            0,
            _count - 1,
          )
        : visibleTarget;
    final desiredFirst = (target - radius).clamp(0, _count - 1);
    final desiredLast = (target + radius).clamp(0, _count - 1);
    if (_blocks.containsKey(desiredFirst) && _blocks.containsKey(desiredLast)) {
      return;
    }
    _loading = true;
    try {
      final rows = await repository.loadWindow(
        libraryItemId,
        centerOrder: target,
        radius: radius,
      );
      for (final block in rows) {
        _blocks[block.displayOrder] = block;
        if (block.isPrimaryChapterHeading) {
          _primaryHeadings[block.displayOrder] = block;
        }
      }
      if (rows.isNotEmpty) {
        _loadedFirst = math.min(
          _loadedFirst ?? rows.first.displayOrder,
          rows.first.displayOrder,
        );
        _loadedLast = math.max(
          _loadedLast ?? rows.last.displayOrder,
          rows.last.displayOrder,
        );
      }
      if (!_preserveExpandedCache) _trimAround(visibleTarget);
      _center = visibleTarget;
      if (!_disposed) notifyListeners();
    } finally {
      _loading = false;
      final pending = _pending;
      _pending = null;
      if (pending != null) await ensureWindow(pending);
    }
  }

  /// Expands the cache ahead of a frame-driven scroll and retains everything
  /// already loaded for this reader session. Removing variable-height rows
  /// while the reader remains visible can correct its geometry and blink.
  Future<void> beginAutoScroll(int visibleOrder, {required int direction}) {
    _autoScrolling = true;
    _preserveExpandedCache = true;
    _autoScrollDirection = direction < 0 ? -1 : 1;
    return ensureWindow(visibleOrder);
  }

  /// Stopping changes controller state only; disposal reclaims the session
  /// cache without mutating the visible list's geometry.
  void endAutoScroll(int visibleOrder) {
    if (!_autoScrolling) return;
    _autoScrolling = false;
    _center = visibleOrder;
  }

  bool _trimAround(int centerOrder) {
    final before = _blocks.length;
    _blocks.removeWhere(
      (order, _) =>
          order < centerOrder - windowRadius ||
          order > centerOrder + windowRadius,
    );
    if (_blocks.isEmpty) {
      _loadedFirst = null;
      _loadedLast = null;
    } else {
      _loadedFirst = _blocks.keys.reduce(math.min);
      _loadedLast = _blocks.keys.reduce(math.max);
    }
    return before != _blocks.length;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

int firstMeaningfullyVisibleCanonicalOrder(
  Iterable<({int index, double leading, double trailing})> positions, {
  double probe = 0.12,
}) {
  final visible =
      positions.where((item) => item.trailing > 0 && item.leading < 1).toList()
        ..sort((a, b) => a.index.compareTo(b.index));
  if (visible.isEmpty) return -1;
  var result = visible.first.index;
  for (final item in visible) {
    if (item.leading > probe) break;
    result = item.index;
  }
  return result;
}
