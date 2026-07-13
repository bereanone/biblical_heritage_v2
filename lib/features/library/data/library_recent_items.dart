import 'library_catalog_service.dart';

/// Selects the items shown on the Library "Recent" tab.
///
/// Recents behave like reading history: an item qualifies only if the user
/// actually opened it (`lastOpened` is set). Items that were merely indexed,
/// refreshed, filtered, or shown inside a collection list have only
/// `dateAdded` and must never appear here. Collection/letter/file-type
/// filters are intentionally not applied so history stays global; only the
/// search query narrows the list.
List<LibraryCatalogItem> selectRecentLibraryItems(
  List<LibraryCatalogItem> items, {
  String searchQuery = '',
}) {
  final query = compactLibrarySearchText(searchQuery);
  final opened = items.where((item) {
    if (item.lastOpened == null) return false;
    if (query.isEmpty) return true;
    return libraryCatalogSearchTextForItem(item).contains(query);
  }).toList();
  opened.sort((a, b) {
    final compare = b.lastOpened!.compareTo(a.lastOpened!);
    if (compare != 0) return compare;
    return a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase());
  });
  return opened;
}
