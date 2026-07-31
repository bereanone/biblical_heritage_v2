import 'dart:async';

import 'package:flutter/foundation.dart';

@immutable
class BibleVisibleLocation {
  const BibleVisibleLocation({
    required this.blockId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
  });

  final int blockId;
  final int bookNumber;
  final int chapter;
  final int verse;

  bool crossesChapterOrBook(BibleVisibleLocation? previous) =>
      previous == null ||
      bookNumber != previous.bookNumber ||
      chapter != previous.chapter;

  @override
  bool operator ==(Object other) =>
      other is BibleVisibleLocation &&
      blockId == other.blockId &&
      bookNumber == other.bookNumber &&
      chapter == other.chapter &&
      verse == other.verse;

  @override
  int get hashCode => Object.hash(blockId, bookNumber, chapter, verse);
}

@immutable
class BibleReaderLocation {
  const BibleReaderLocation({
    required this.blockId,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  final int blockId;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;

  String get label => '$bookName $chapter:$verse';
}

/// Resolves the one location used by the visible scripture and reader header.
/// Once a visible location exists, fallback route/selection state cannot
/// override it with an older book, chapter, or verse.
BibleReaderLocation resolveBibleReaderLocation({
  required BibleVisibleLocation? visibleLocation,
  required BibleVisibleLocation fallbackLocation,
  required Map<int, String> bookNamesByNumber,
}) {
  final location = visibleLocation ?? fallbackLocation;
  return BibleReaderLocation(
    blockId: location.blockId,
    bookNumber: location.bookNumber,
    bookName:
        bookNamesByNumber[location.bookNumber] ?? 'Book ${location.bookNumber}',
    chapter: location.chapter,
    verse: location.verse,
  );
}

typedef BibleLocationWriter =
    Future<void> Function(BibleVisibleLocation location);

class BibleLiveReferenceController
    extends ValueNotifier<BibleVisibleLocation?> {
  BibleLiveReferenceController([super.value]);

  BibleVisibleLocation? _selected;
  BibleVisibleLocation? _centered;
  BibleVisibleLocation? _firstAvailable;
  int updateCount = 0;

  BibleVisibleLocation? get selected => _selected;
  BibleVisibleLocation? get centered => _centered;
  BibleVisibleLocation? get firstAvailable => _firstAvailable;

  bool updateSelected(BibleVisibleLocation location) {
    _selected = location;
    return _publishResolved();
  }

  bool clearSelected() {
    if (_selected == null) return false;
    _selected = null;
    return _publishResolved();
  }

  bool updateCentered(BibleVisibleLocation location) {
    _centered = location;
    // A pending explicit selection only exists to bridge the gap between an
    // explicit navigation/tap and the viewport settling on that same verse
    // (avoiding a flash of a stale centered verse mid-scroll). Once the live
    // center tracking reports that exact verse, the viewport has settled and
    // control must pass to live tracking so scrolling away keeps updating
    // the label instead of freezing on the verse that used to be selected.
    if (_selected != null && _selected == location) {
      _selected = null;
    }
    return _publishResolved();
  }

  bool updateFirstAvailable(BibleVisibleLocation location) {
    _firstAvailable = location;
    return _publishResolved();
  }

  // Kept for callers that report passive visible-position changes.
  bool update(BibleVisibleLocation location) {
    return updateCentered(location);
  }

  bool _publishResolved() {
    final resolved = _selected ?? _centered ?? _firstAvailable;
    if (resolved == null || value == resolved) return false;
    updateCount += 1;
    value = resolved;
    return true;
  }
}

@immutable
class BibleViewportCandidate {
  const BibleViewportCandidate({
    required this.blockId,
    required this.leadingEdge,
    required this.trailingEdge,
    required this.isVerse,
  });

  final int blockId;
  final double leadingEdge;
  final double trailingEdge;
  final bool isVerse;
}

/// Item-position edges are normalized to the scripture scrollable itself, so
/// 0.5 is the center after the fixed top/bottom toolbars and safe areas have
/// already been excluded by the surrounding Expanded reader viewport.
int? centeredBibleVerseBlockId(
  Iterable<BibleViewportCandidate> candidates, {
  double viewportCenter = 0.5,
}) {
  BibleViewportCandidate? nearest;
  var nearestDistance = double.infinity;
  for (final candidate in candidates) {
    if (!candidate.isVerse ||
        candidate.trailingEdge <= 0 ||
        candidate.leadingEdge >= 1) {
      continue;
    }
    if (candidate.leadingEdge <= viewportCenter &&
        candidate.trailingEdge >= viewportCenter) {
      return candidate.blockId;
    }
    final midpoint = (candidate.leadingEdge + candidate.trailingEdge) / 2;
    final distance = (midpoint - viewportCenter).abs();
    if (distance < nearestDistance) {
      nearest = candidate;
      nearestDistance = distance;
    }
  }
  return nearest?.blockId;
}

/// Coalesces rapidly changing visible locations into one latest pending value.
/// It owns at most one database write and never queues individual positions.
class BibleLocationPersistenceCoordinator {
  BibleLocationPersistenceCoordinator({
    required BibleLocationWriter writer,
    this.throttle = const Duration(milliseconds: 750),
  }) : _writer = writer;

  final BibleLocationWriter _writer;
  final Duration throttle;
  Timer? _timer;
  Future<void>? _activeWrite;
  BibleVisibleLocation? _latest;
  BibleVisibleLocation? _persisted;
  bool _suspended = false;
  bool _disposed = false;
  int updateRequests = 0;
  int writesCompleted = 0;
  int activeWrites = 0;
  int maximumOverlappingWrites = 0;

  BibleVisibleLocation? get latest => _latest;
  BibleVisibleLocation? get persisted => _persisted;
  int get pendingLocationCount => _latest == _persisted ? 0 : 1;
  bool get isSuspended => _suspended;

  void update(
    BibleVisibleLocation location, {
    required bool persistenceSuspended,
  }) {
    if (_disposed) return;
    updateRequests += 1;
    _latest = location;
    setSuspended(persistenceSuspended);
    if (_suspended || _latest == _persisted || _timer != null) return;
    _timer = Timer(throttle, () {
      _timer = null;
      unawaited(flush());
    });
  }

  void setSuspended(bool value) {
    if (_disposed || _suspended == value) return;
    _suspended = value;
    if (value) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> resumeAndFlush() async {
    setSuspended(false);
    await flush();
  }

  Future<void> flush() async {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    if (_suspended) return;

    while (!_disposed) {
      final active = _activeWrite;
      if (active != null) {
        await active;
        continue;
      }
      final target = _latest;
      if (target == null || target == _persisted) return;

      final write = _performWrite(target);
      _activeWrite = write;
      await write;
    }
  }

  Future<void> _performWrite(BibleVisibleLocation target) async {
    activeWrites += 1;
    if (activeWrites > maximumOverlappingWrites) {
      maximumOverlappingWrites = activeWrites;
    }
    try {
      await _writer(target);
      _persisted = target;
      writesCompleted += 1;
    } finally {
      activeWrites -= 1;
      _activeWrite = null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> flushAndDispose() async {
    if (_disposed) return;
    await resumeAndFlush();
    dispose();
  }
}
