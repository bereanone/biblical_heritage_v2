part of 'library_catalog_service.dart';

List<LibraryCatalogNavigationItem> dedupeLibraryNavigationItems(
  List<LibraryCatalogNavigationItem> items,
) {
  if (items.isEmpty) return items;

  final deduped = <LibraryCatalogNavigationItem>[];
  final seenKeys = <String>{};

  for (final item in items) {
    final key = _navigationDedupKey(item);
    if (!seenKeys.add(key)) {
      continue;
    }
    deduped.add(item);
  }

  return deduped;
}

String _navigationDedupKey(LibraryCatalogNavigationItem item) {
  final contentKind = _normalizedNavigationValue(item.contentKind);
  return [
    _normalizedNavigationValue(item.label),
    _normalizedNavigationHref(item.href) ?? '',
    _normalizedNavigationValue(item.anchorId),
    contentKind,
  ].join('|');
}

String _normalizedNavigationValue(String? value) {
  return (value?.trim() ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

String? _normalizedNavigationHref(String? href) {
  final value = href?.trim() ?? '';
  if (value.isEmpty) return null;
  return p.normalize(value).toLowerCase();
}
