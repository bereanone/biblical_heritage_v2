part of 'library_catalog_service.dart';

class LibraryCollectionFilterOption {
  const LibraryCollectionFilterOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

const String _libraryAllCollectionsFilterValue = 'all';
const String _libraryAllCollectionsFilterLabel = 'All Collections';
const List<String> _libraryCollectionFilterPriority = <String>[
  'egw_books',
  'egw_devotionals',
  'egw_commentaries',
  'egw_misc_collections',
  'egw_pamphlets',
  'egw_periodicals',
  'egw_manuscript_releases',
];

List<LibraryCollectionFilterOption> buildLibraryCollectionFilterOptions(
  Iterable<LibraryCatalogItem> items,
) {
  final discovered = <String, String>{};
  for (final item in items) {
    final value = libraryCollectionFilterValueForItem(item);
    if (value == _libraryAllCollectionsFilterValue) continue;
    discovered.putIfAbsent(
      value,
      () => libraryCollectionFilterLabelForItem(item),
    );
  }

  final orderedKeys = discovered.keys.toList(growable: false)
    ..sort((left, right) {
      final leftPriority = _libraryCollectionFilterPriority.indexOf(left);
      final rightPriority = _libraryCollectionFilterPriority.indexOf(right);
      if (leftPriority != rightPriority) {
        if (leftPriority == -1) return 1;
        if (rightPriority == -1) return -1;
        return leftPriority.compareTo(rightPriority);
      }
      return discovered[left]!.compareTo(discovered[right]!);
    });

  return <LibraryCollectionFilterOption>[
    const LibraryCollectionFilterOption(
      value: _libraryAllCollectionsFilterValue,
      label: _libraryAllCollectionsFilterLabel,
    ),
    for (final key in orderedKeys)
      LibraryCollectionFilterOption(value: key, label: discovered[key]!),
  ];
}

bool libraryItemMatchesCollectionFilter(
  LibraryCatalogItem item,
  String filterValue,
) {
  final normalizedFilter = _normalizeLibraryCollectionFilterValue(filterValue);
  if (normalizedFilter.isEmpty ||
      normalizedFilter == _libraryAllCollectionsFilterValue) {
    return true;
  }
  return libraryCollectionFilterValueForItem(item) == normalizedFilter;
}

String libraryCollectionFilterValueForItem(LibraryCatalogItem item) {
  final candidate = _libraryCollectionFilterCandidateForItem(item);
  if (candidate == null || candidate.trim().isEmpty) {
    return _libraryAllCollectionsFilterValue;
  }
  return _normalizeLibraryCollectionFilterValue(candidate);
}

String libraryCollectionFilterLabelForItem(LibraryCatalogItem item) {
  final candidate = _libraryCollectionFilterCandidateForItem(item);
  if (candidate == null || candidate.trim().isEmpty) {
    return _libraryAllCollectionsFilterLabel;
  }
  return _humanizeLibraryCollectionLabel(candidate);
}

String? _libraryCollectionFilterCandidateForItem(LibraryCatalogItem item) {
  final candidates = <String?>[
    item.collectionName,
    _collectionFolderFromRelativePath(item.relativePath),
  ];
  for (final candidate in candidates) {
    final trimmed = candidate?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _collectionFolderFromRelativePath(String relativePath) {
  final normalized = relativePath.replaceAll('\\', '/').trim();
  if (normalized.isEmpty) return null;
  final segments = normalized
      .split('/')
      .map((segment) => segment.trim())
      .where((segment) => segment.isNotEmpty)
      .toList(growable: false);
  for (final segment in segments) {
    if (segment.startsWith('EGW_')) return segment;
  }
  if (segments.length >= 3) return segments[2];
  if (segments.length >= 2) return segments[1];
  return segments.isEmpty ? null : segments.first;
}

String _humanizeLibraryCollectionLabel(String value) {
  return value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) {
        if (part.toUpperCase() == 'EGW') return 'EGW';
        if (part.length <= 2) return part.toUpperCase();
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

String _normalizeLibraryCollectionFilterValue(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_\-\s]+'), '_')
      .replaceAll(RegExp(r'[^a-z0-9_]+'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}
