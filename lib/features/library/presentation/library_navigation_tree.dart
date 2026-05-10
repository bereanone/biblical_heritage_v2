import 'package:path/path.dart' as p;

import '../data/library_catalog_service.dart';

class LibraryNavigationTreeResult {
  const LibraryNavigationTreeResult({
    required this.items,
    required this.childrenByParent,
  });

  final List<LibraryCatalogNavigationItem> items;
  final Map<String?, List<LibraryCatalogNavigationItem>> childrenByParent;
}

LibraryNavigationTreeResult buildLibraryNavigationTree(
  List<LibraryCatalogNavigationItem> items, {
  bool devotionalMode = false,
}) {
  if (items.isEmpty) {
    return const LibraryNavigationTreeResult(
      items: <LibraryCatalogNavigationItem>[],
      childrenByParent: <String?, List<LibraryCatalogNavigationItem>>{},
    );
  }

  final sortedItems = List<LibraryCatalogNavigationItem>.of(items)
    ..sort(_compareNavigationEntries);
  final shouldGroupDevotionals =
      devotionalMode || isDevotionalNavigation(sortedItems);
  final childrenByParent = <String?, List<LibraryCatalogNavigationItem>>{};
  final itemsByDepth = <int, LibraryCatalogNavigationItem>{};
  final rootsByHref = <String, LibraryCatalogNavigationItem>{};
  final seenExactEntries = <String>{};
  final devotionalMonthParents = <int, LibraryCatalogNavigationItem>{};

  for (final item in sortedItems) {
    final exactKey = _navigationEntryKey(item);
    if (!seenExactEntries.add(exactKey)) {
      continue;
    }

    final depth = (item.depth ?? 0).clamp(0, 99);
    var parentId = shouldGroupDevotionals
        ? _devotionalParentId(item, devotionalMonthParents)
        : _effectiveParentId(item, depth, itemsByDepth);
    final normalizedHref = _normalizedNavigationHref(item.href);

    if (parentId == null && normalizedHref != null) {
      // Some EPUBs emit a second linear TOC pass with the same hrefs later in
      // the file. Keep the first occurrence as the root and tuck later rows
      // under that root instead of letting depth-based inference glue them to
      // the previous root chapter.
      final rootForHref = rootsByHref[normalizedHref];
      if (rootForHref != null && rootForHref.id != item.id) {
        if (_isDuplicateRootEntry(item, rootForHref)) {
          continue;
        }
        parentId = rootForHref.id;
      }
    }

    childrenByParent.putIfAbsent(parentId, () => []).add(item);

    if (shouldGroupDevotionals) {
      final devotionalLabel = parseDevotionalNavigationLabel(item.label);
      if (devotionalLabel?.day == null && devotionalLabel != null) {
        devotionalMonthParents[devotionalLabel.monthIndex] = item;
      }
    }

    if (parentId == null && normalizedHref != null) {
      rootsByHref.putIfAbsent(normalizedHref, () => item);
    }

    if (!shouldGroupDevotionals) {
      itemsByDepth[depth] = item;
      final deeperDepths =
          itemsByDepth.keys.where((value) => value > depth).toList()..sort();
      for (final deeperDepth in deeperDepths) {
        itemsByDepth.remove(deeperDepth);
      }
    }
  }

  final flattened = <LibraryCatalogNavigationItem>[];
  final visited = <String>{};

  void visit(LibraryCatalogNavigationItem item) {
    if (!visited.add(item.id)) return;
    flattened.add(item);
    for (final child in childrenByParent[item.id] ?? const []) {
      visit(child);
    }
  }

  for (final root in childrenByParent[null] ?? const []) {
    visit(root);
  }

  for (final item in sortedItems) {
    if (visited.contains(item.id)) continue;
    visit(item);
  }

  return LibraryNavigationTreeResult(
    items: flattened,
    childrenByParent: childrenByParent,
  );
}

String? _effectiveParentId(
  LibraryCatalogNavigationItem item,
  int depth,
  Map<int, LibraryCatalogNavigationItem> itemsByDepth,
) {
  final explicitParentId = item.parentId?.trim() ?? '';
  if (explicitParentId.isNotEmpty) return explicitParentId;
  if (depth <= 0) return null;

  for (var candidateDepth = depth - 1; candidateDepth >= 0; candidateDepth--) {
    final parent = itemsByDepth[candidateDepth];
    if (parent != null) return parent.id;
  }

  return null;
}

String _navigationEntryKey(LibraryCatalogNavigationItem item) {
  return [
    _normalizedNavigationHref(item.href) ?? '',
    item.label.trim().toLowerCase(),
    item.anchorId?.trim().toLowerCase() ?? '',
  ].join('|');
}

String navigationDisplayLabel(
  LibraryCatalogNavigationItem item, {
  bool devotionalMode = false,
}) {
  if (!devotionalMode) return item.label;

  final labelInfo = parseDevotionalNavigationLabel(item.label);
  if (labelInfo == null || !labelInfo.isMonthHeading) {
    return item.label;
  }

  return _devotionalMonthName(labelInfo.monthIndex);
}

bool isDevotionalNavigation(List<LibraryCatalogNavigationItem> items) {
  var monthHeadingCount = 0;
  var dayLabelCount = 0;
  for (final item in items) {
    final labelInfo = parseDevotionalNavigationLabel(item.label);
    if (labelInfo == null) continue;
    if (labelInfo.isMonthHeading) {
      monthHeadingCount += 1;
    } else {
      dayLabelCount += 1;
    }
  }

  return monthHeadingCount >= 2 && dayLabelCount >= 8;
}

DevotionalNavigationLabelInfo? parseDevotionalNavigationLabel(String label) {
  final normalized = _normalizedNavigationText(label);
  if (normalized.isEmpty) return null;

  for (var index = 0; index < _devotionalMonthNames.length; index++) {
    final month = _devotionalMonthNames[index];
    final dayMatch = RegExp(
      r'\b' + month + r'\s+([1-9]|[12]\d|3[01])\b',
    ).firstMatch(normalized);
    if (dayMatch != null) {
      return DevotionalNavigationLabelInfo(
        monthIndex: index + 1,
        day: int.tryParse(dayMatch.group(1) ?? ''),
      );
    }

    if (normalized == month ||
        normalized.startsWith('$month ') ||
        normalized.startsWith('$month-') ||
        normalized.startsWith('$month—') ||
        normalized.startsWith('$month:')) {
      return DevotionalNavigationLabelInfo(monthIndex: index + 1);
    }
  }

  return null;
}

String? _devotionalParentId(
  LibraryCatalogNavigationItem item,
  Map<int, LibraryCatalogNavigationItem> monthParents,
) {
  final labelInfo = parseDevotionalNavigationLabel(item.label);
  if (labelInfo == null) return null;
  if (labelInfo.isMonthHeading) return null;
  return monthParents[labelInfo.monthIndex]?.id;
}

String? _normalizedNavigationHref(String? href) {
  final value = href?.trim() ?? '';
  if (value.isEmpty) return null;
  final clean = value.split('#').first.split('?').first.trim();
  if (clean.isEmpty) return null;
  return p.normalize(clean).toLowerCase();
}

bool _isDuplicateRootEntry(
  LibraryCatalogNavigationItem item,
  LibraryCatalogNavigationItem root,
) {
  final itemHref = _normalizedNavigationHref(item.href);
  final rootHref = _normalizedNavigationHref(root.href);
  if (itemHref == null || rootHref == null || itemHref != rootHref) {
    return false;
  }

  final itemLabel = item.label.trim().toLowerCase();
  final rootLabel = root.label.trim().toLowerCase();
  if (itemLabel != rootLabel) return false;

  final itemAnchor = item.anchorId?.trim().toLowerCase() ?? '';
  final rootAnchor = root.anchorId?.trim().toLowerCase() ?? '';
  return itemAnchor == rootAnchor;
}

int _compareNavigationEntries(
  LibraryCatalogNavigationItem a,
  LibraryCatalogNavigationItem b,
) {
  final leftSort = a.sortOrder ?? 1 << 30;
  final rightSort = b.sortOrder ?? 1 << 30;
  final sortCompare = leftSort.compareTo(rightSort);
  if (sortCompare != 0) return sortCompare;

  final leftDepth = a.depth ?? 0;
  final rightDepth = b.depth ?? 0;
  final depthCompare = leftDepth.compareTo(rightDepth);
  if (depthCompare != 0) return depthCompare;

  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

String _normalizedNavigationText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _devotionalMonthName(int monthIndex) {
  if (monthIndex < 1 || monthIndex > _devotionalMonthNames.length) {
    return '';
  }
  return _devotionalMonthNames[monthIndex - 1].replaceFirstMapped(
    RegExp(r'^[a-z]'),
    (match) => match.group(0)!.toUpperCase(),
  );
}

const List<String> _devotionalMonthNames = <String>[
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

class DevotionalNavigationLabelInfo {
  const DevotionalNavigationLabelInfo({required this.monthIndex, this.day});

  final int monthIndex;
  final int? day;

  bool get isMonthHeading => day == null;
}
