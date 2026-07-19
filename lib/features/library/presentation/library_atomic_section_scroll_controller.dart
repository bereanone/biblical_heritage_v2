import 'package:flutter/widgets.dart';

enum LibrarySectionInitialEdge { top, bottom }

bool librarySectionTransitionCanPublish({
  required int currentGeneration,
  required int callbackGeneration,
  required int attachedPositionCount,
  required bool hasValidContentDimensions,
  required int? appliedOffsetGeneration,
}) =>
    callbackGeneration == currentGeneration &&
    attachedPositionCount == 1 &&
    hasValidContentDimensions &&
    appliedOffsetGeneration == callbackGeneration;

/// Applies a section's initial offset while the new content dimensions are
/// being accepted, before that section can paint at the previous section's
/// absolute offset.
class LibraryAtomicSectionScrollController extends ScrollController {
  int? _pendingGeneration;
  LibrarySectionInitialEdge? _pendingEdge;

  int initialOffsetRequests = 0;
  int initialOffsetsApplied = 0;
  int staleOffsetRequestsRejected = 0;
  int? lastAppliedGeneration;
  double? lastAppliedOffset;

  void requestInitialEdge({
    required int generation,
    required LibrarySectionInitialEdge edge,
  }) {
    final newestGeneration = _pendingGeneration ?? lastAppliedGeneration;
    if (newestGeneration != null && generation <= newestGeneration) {
      staleOffsetRequestsRejected += 1;
      return;
    }
    _pendingGeneration = generation;
    _pendingEdge = edge;
    initialOffsetRequests += 1;
  }

  double? takePendingOffset({
    required double minScrollExtent,
    required double maxScrollExtent,
  }) {
    final generation = _pendingGeneration;
    final edge = _pendingEdge;
    if (generation == null || edge == null) return null;
    if (!minScrollExtent.isFinite || !maxScrollExtent.isFinite) return null;
    _pendingGeneration = null;
    _pendingEdge = null;
    final offset = edge == LibrarySectionInitialEdge.top
        ? minScrollExtent
        : maxScrollExtent;
    initialOffsetsApplied += 1;
    lastAppliedGeneration = generation;
    lastAppliedOffset = offset;
    return offset;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _LibraryAtomicSectionScrollPosition(
    physics: physics,
    context: context,
    oldPosition: oldPosition,
    controller: this,
  );
}

class _LibraryAtomicSectionScrollPosition
    extends ScrollPositionWithSingleContext {
  _LibraryAtomicSectionScrollPosition({
    required super.physics,
    required super.context,
    required this.controller,
    super.oldPosition,
  });

  final LibraryAtomicSectionScrollController controller;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final initialOffset = controller.takePendingOffset(
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
    );
    if (initialOffset != null) correctPixels(initialOffset);
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}
