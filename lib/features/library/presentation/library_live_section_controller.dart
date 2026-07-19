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
