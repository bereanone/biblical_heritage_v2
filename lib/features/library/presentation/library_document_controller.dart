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
  bool _loading = false;
  bool _disposed = false;
  int? _pending;

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
    final target = centerOrder.clamp(0, _count - 1);
    if (_blocks.isNotEmpty && (target - _center).abs() < windowRadius ~/ 3) {
      return;
    }
    _loading = true;
    try {
      final rows = await repository.loadWindow(
        libraryItemId,
        centerOrder: target,
        radius: windowRadius,
      );
      for (final block in rows) {
        _blocks[block.displayOrder] = block;
        if (block.isPrimaryChapterHeading) {
          _primaryHeadings[block.displayOrder] = block;
        }
      }
      _blocks.removeWhere(
        (order, _) =>
            order < target - windowRadius || order > target + windowRadius,
      );
      _center = target;
      if (!_disposed) notifyListeners();
    } finally {
      _loading = false;
      final pending = _pending;
      _pending = null;
      if (pending != null) await ensureWindow(pending);
    }
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
