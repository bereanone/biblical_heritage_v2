class CanonicalScrollDiagnosticSample {
  const CanonicalScrollDiagnosticSample({
    required this.timestamp,
    required this.requestedDelta,
    required this.appliedDelta,
    required this.firstVisibleBlockId,
    required this.firstVisibleDisplayOrder,
    required this.headingBlockId,
    required this.headingTitle,
    required this.direction,
    required this.programmaticItemJump,
    required this.controllerIdentity,
    required this.chapterNavigationFired,
  });

  final DateTime timestamp;
  final double requestedDelta;
  final double appliedDelta;
  final String? firstVisibleBlockId;
  final int firstVisibleDisplayOrder;
  final String? headingBlockId;
  final String? headingTitle;
  final String direction;
  final bool programmaticItemJump;
  final int controllerIdentity;
  final bool chapterNavigationFired;
}

class CanonicalScrollDiagnostics {
  final List<CanonicalScrollDiagnosticSample> samples =
      <CanonicalScrollDiagnosticSample>[];

  void record(CanonicalScrollDiagnosticSample sample) => samples.add(sample);

  bool get hasForwardChapterRegression {
    String? currentHeadingId;
    final completedHeadingIds = <String>{};
    for (final sample in samples) {
      if (sample.requestedDelta <= 0) continue;
      final headingId = sample.headingBlockId;
      if (headingId == null) continue;
      if (currentHeadingId == null) {
        currentHeadingId = headingId;
        continue;
      }
      if (headingId == currentHeadingId) continue;
      completedHeadingIds.add(currentHeadingId);
      if (completedHeadingIds.contains(headingId)) return true;
      currentHeadingId = headingId;
    }
    return false;
  }

  int get headingOscillationCount {
    String? previous;
    String? current;
    var count = 0;
    for (final sample in samples.where((sample) => sample.requestedDelta > 0)) {
      final next = sample.headingBlockId;
      if (next == null || next == current) continue;
      if (next == previous) count++;
      previous = current;
      current = next;
    }
    return count;
  }

  int get headingFlashCount {
    var hasHeading = false;
    var flashing = false;
    var count = 0;
    for (final sample in samples.where((sample) => sample.requestedDelta > 0)) {
      if (sample.headingBlockId != null) {
        hasHeading = true;
        flashing = false;
      } else if (hasHeading && !flashing) {
        count++;
        flashing = true;
      }
    }
    return count;
  }

  int get controllerRecreationCount {
    final identities = samples
        .map((sample) => sample.controllerIdentity)
        .toSet();
    return identities.isEmpty ? 0 : identities.length - 1;
  }

  int get ordinaryItemJumpCount =>
      samples.where((sample) => sample.programmaticItemJump).length;
}
