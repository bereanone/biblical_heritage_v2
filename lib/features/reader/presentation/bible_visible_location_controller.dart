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

typedef BibleLocationWriter =
    Future<void> Function(BibleVisibleLocation location);

class BibleLiveReferenceController
    extends ValueNotifier<BibleVisibleLocation?> {
  BibleLiveReferenceController([super.value]);

  int updateCount = 0;

  bool update(BibleVisibleLocation location) {
    if (value == location) return false;
    updateCount += 1;
    value = location;
    return true;
  }
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
