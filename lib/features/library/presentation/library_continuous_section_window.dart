import 'package:flutter/foundation.dart';

@immutable
class LibraryContinuousSectionUnit<T> {
  const LibraryContinuousSectionUnit({
    required this.identity,
    required this.headingPath,
    required this.bodyBlocks,
    this.sourcePageMarkers = const <int, String>{},
  });

  final String identity;
  final List<String> headingPath;
  final List<T> bodyBlocks;

  /// Source-owned markers keyed by the block's stable source index.
  final Map<int, String> sourcePageMarkers;
}

List<LibraryContinuousSectionUnit<T>> libraryContinuousMountedUnits<T>({
  required LibraryContinuousSectionWindow window,
  required Map<int, LibraryContinuousSectionUnit<T>> unitsByIndex,
}) => List<LibraryContinuousSectionUnit<T>>.unmodifiable(
  window.mountedIndices.map((index) => unitsByIndex[index]).whereType(),
);

/// A bounded, identity-based window into the readable sections of a book.
///
/// The reader normally mounts the previous, current, and next readable unit.
/// Moving the center never changes the order of the document; it only returns
/// which far unit can be recycled and which adjacent unit should be mounted.
@immutable
class LibraryContinuousSectionWindow {
  const LibraryContinuousSectionWindow({
    required this.readableIndices,
    required this.centerIndex,
    this.minimumReadablePosition = 0,
  });

  final List<int> readableIndices;
  final int centerIndex;
  final int minimumReadablePosition;

  List<int> get mountedIndices {
    final centerPosition = readableIndices.indexOf(centerIndex);
    if (centerPosition < 0) return const <int>[];
    final first = (centerPosition - 1).clamp(
      minimumReadablePosition,
      readableIndices.length,
    );
    final lastExclusive = (centerPosition + 2).clamp(0, readableIndices.length);
    return List<int>.unmodifiable(
      readableIndices.sublist(first, lastExclusive),
    );
  }

  LibraryContinuousSectionWindow? moveTo(int nextCenterIndex) {
    final oldPosition = readableIndices.indexOf(centerIndex);
    final nextPosition = readableIndices.indexOf(nextCenterIndex);
    if (oldPosition < 0 || nextPosition < 0) return null;
    if ((nextPosition - oldPosition).abs() != 1) return null;
    return LibraryContinuousSectionWindow(
      readableIndices: readableIndices,
      centerIndex: nextCenterIndex,
      minimumReadablePosition: minimumReadablePosition,
    );
  }

  bool get isBounded => mountedIndices.length <= 3;
}

/// Offset to apply after recycling a window.
///
/// Removing content above subtracts its height. Prepending content adds its
/// height. Changes below the viewport require no compensation.
double libraryContinuousWindowCompensatedOffset({
  required double oldOffset,
  double removedAboveHeight = 0,
  double prependedAboveHeight = 0,
}) => oldOffset - removedAboveHeight + prependedAboveHeight;

double libraryStableLiveIndicatorHeight(double fontScale) =>
    44 * fontScale.clamp(1.0, 2.0);

double libraryStableSectionScrollTarget({
  required double pixels,
  required double delta,
  required double minimum,
  required double maximum,
}) {
  final safeMaximum = maximum < minimum ? minimum : maximum;
  return (pixels + delta).clamp(minimum, safeMaximum);
}

/// Returns the first section whose leading edge has reached the viewport's
/// live-location probe line. The inputs are document-relative top offsets.
int libraryFirstMeaningfulVisibleSection({
  required List<int> mountedIndices,
  required Map<int, double> sectionTopOffsets,
  required double viewportOffset,
  double probeInset = 24,
}) {
  if (mountedIndices.isEmpty) return -1;
  final probe = viewportOffset + probeInset;
  var visible = mountedIndices.first;
  for (final index in mountedIndices) {
    final top = sectionTopOffsets[index];
    if (top == null || top > probe) break;
    visible = index;
  }
  return visible;
}

@immutable
class LibrarySectionVisibilitySample {
  const LibrarySectionVisibilitySample({
    required this.currentIndex,
    required this.candidateIndex,
    required this.candidateTop,
    required this.viewportTop,
    required this.viewportHeight,
    required this.now,
  });

  final int currentIndex;
  final int candidateIndex;
  final double candidateTop;
  final double viewportTop;
  final double viewportHeight;
  final DateTime now;
}

@immutable
class LibrarySectionVisibilityDecision {
  const LibrarySectionVisibilityDecision({
    required this.index,
    required this.changed,
    required this.watchdogClamped,
  });

  final int index;
  final bool changed;
  final bool watchdogClamped;
}

/// Stabilizes live-section identity without mutating document layout.
class LibrarySectionVisibilityHysteresis {
  LibrarySectionVisibilityHysteresis({
    this.forwardActivationFraction = 0.25,
    this.reverseActivationFraction = 0.55,
    this.stableFramesRequired = 3,
    this.watchdogWindow = const Duration(milliseconds: 500),
    this.watchdogChangeLimit = 3,
  });

  final double forwardActivationFraction;
  final double reverseActivationFraction;
  final int stableFramesRequired;
  final Duration watchdogWindow;
  final int watchdogChangeLimit;

  int? _pendingIndex;
  int _pendingFrames = 0;
  final List<({int from, int to, DateTime at})> _changes = [];
  bool watchdogClamped = false;

  LibrarySectionVisibilityDecision update(
    LibrarySectionVisibilitySample sample,
  ) {
    if (watchdogClamped || sample.candidateIndex == sample.currentIndex) {
      _clearPending();
      return LibrarySectionVisibilityDecision(
        index: sample.currentIndex,
        changed: false,
        watchdogClamped: watchdogClamped,
      );
    }
    final movingForward = sample.candidateIndex > sample.currentIndex;
    final threshold =
        sample.viewportTop +
        sample.viewportHeight *
            (movingForward
                ? forwardActivationFraction
                : reverseActivationFraction);
    final crossed = movingForward
        ? sample.candidateTop <= threshold
        : sample.candidateTop >= threshold;
    if (!crossed) {
      _clearPending();
      return LibrarySectionVisibilityDecision(
        index: sample.currentIndex,
        changed: false,
        watchdogClamped: false,
      );
    }
    if (_pendingIndex != sample.candidateIndex) {
      _pendingIndex = sample.candidateIndex;
      _pendingFrames = 1;
    } else {
      _pendingFrames += 1;
    }
    if (_pendingFrames < stableFramesRequired) {
      return LibrarySectionVisibilityDecision(
        index: sample.currentIndex,
        changed: false,
        watchdogClamped: false,
      );
    }
    _clearPending();
    _changes.removeWhere(
      (change) => sample.now.difference(change.at) > watchdogWindow,
    );
    _changes.add((
      from: sample.currentIndex,
      to: sample.candidateIndex,
      at: sample.now,
    ));
    final alternatingPair =
        _changes.length > watchdogChangeLimit &&
        _changes.skip(_changes.length - watchdogChangeLimit - 1).every((
          change,
        ) {
          final first = _changes[_changes.length - watchdogChangeLimit - 1];
          return (change.from == first.from && change.to == first.to) ||
              (change.from == first.to && change.to == first.from);
        });
    if (alternatingPair) {
      watchdogClamped = true;
      return LibrarySectionVisibilityDecision(
        index: sample.currentIndex,
        changed: false,
        watchdogClamped: true,
      );
    }
    return LibrarySectionVisibilityDecision(
      index: sample.candidateIndex,
      changed: true,
      watchdogClamped: false,
    );
  }

  void reset() {
    _clearPending();
    _changes.clear();
    watchdogClamped = false;
  }

  void _clearPending() {
    _pendingIndex = null;
    _pendingFrames = 0;
  }
}
