import 'package:flutter/foundation.dart';

@immutable
class LibraryLiveSectionLocation {
  const LibraryLiveSectionLocation({
    required this.navigationId,
    required this.sectionEntryName,
    required this.headingLabels,
    required this.generation,
  });

  final String? navigationId;
  final String sectionEntryName;
  final List<String> headingLabels;
  final int generation;

  String get displayLabel => headingLabels.join(' • ');

  bool sameVisibleIdentity(LibraryLiveSectionLocation other) =>
      navigationId == other.navigationId &&
      sectionEntryName == other.sectionEntryName &&
      listEquals(headingLabels, other.headingLabels);
}

/// Resolve the visible heading before falling back to a file-level navigation
/// ID. Several chapters may share one EPUB file and therefore the same fallback.
String? libraryLiveContentsNavigationId({
  required LibraryLiveSectionLocation? location,
  required Map<String, String> labelsById,
  String? fallbackId,
}) {
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  for (final heading in location?.headingLabels.reversed ?? const <String>[]) {
    final label = normalize(heading);
    if (label.isEmpty) continue;
    final matches = labelsById.entries
        .where((entry) => normalize(entry.value) == label)
        .map((entry) => entry.key)
        .toList();
    if (matches.length == 1) return matches.single;
    if (matches.contains(location?.navigationId)) return location!.navigationId;
  }
  final liveId = location?.navigationId;
  return labelsById.containsKey(liveId) ? liveId : fallbackId;
}

class LibraryLiveSectionController
    extends ValueNotifier<LibraryLiveSectionLocation?> {
  LibraryLiveSectionController() : super(null);

  int acceptedUpdates = 0;
  int rejectedStaleUpdates = 0;

  bool update(LibraryLiveSectionLocation next) {
    final current = value;
    if (current != null && next.generation < current.generation) {
      rejectedStaleUpdates += 1;
      return false;
    }
    if (current != null && current.sameVisibleIdentity(next)) return false;
    acceptedUpdates += 1;
    value = next;
    return true;
  }
}
