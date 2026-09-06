import 'package:path/path.dart' as p;

import '../data/library_catalog_service.dart';
import '../data/library_section_heuristics.dart';

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
  bool periodicalMode = false,
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
      //
      // But several sections can also legitimately share one physical file
      // via distinct anchors (e.g. INTRODUCTION, ARGUMENT, APPENDIX A all
      // living in the same content.xhtml, each its own top-level sibling).
      // Stripping the fragment for the href comparison above would otherwise
      // conflate that case with the duplicate-pass case, gluing every later
      // sibling under the first one. Only reparent when the anchor also
      // matches (including both being absent), which is what a genuine
      // repeated TOC row looks like. Some import pipelines (e.g. SL27's)
      // never populate the anchor_id column at all and fold the fragment
      // into href instead, so the anchor used here falls back to parsing it
      // straight off href rather than trusting an always-empty column.
      final rootForHref = rootsByHref[normalizedHref];
      if (rootForHref != null && rootForHref.id != item.id) {
        if (_isDuplicateRootEntry(item, rootForHref)) {
          continue;
        }
        final itemAnchor = _effectiveAnchorId(item);
        final rootAnchor = _effectiveAnchorId(rootForHref);
        if (itemAnchor == rootAnchor) {
          parentId = rootForHref.id;
        }
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

  final rootItems = childrenByParent[null];
  if (rootItems != null && rootItems.length > 1 && !periodicalMode) {
    rootItems.sort(_compareNavigationDisplayEntries);
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
    _effectiveAnchorId(item),
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

  return _effectiveAnchorId(item) == _effectiveAnchorId(root);
}

/// The anchor identifying which part of a shared physical file an item
/// points at. Prefers the stored `anchor_id` column, but some import
/// pipelines (e.g. SL27's) leave that column empty and fold the fragment
/// into `href` instead (`OEBPS/content.xhtml#heading-2-1`), so this falls
/// back to parsing the fragment straight off href rather than treating an
/// always-empty column as "no anchor" for every row.
String _effectiveAnchorId(LibraryCatalogNavigationItem item) {
  final explicit = item.anchorId?.trim().toLowerCase() ?? '';
  if (explicit.isNotEmpty) return explicit;

  final href = item.href?.trim() ?? '';
  final hashIndex = href.indexOf('#');
  if (hashIndex == -1) return '';
  return href.substring(hashIndex + 1).trim().toLowerCase();
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

int _compareNavigationDisplayEntries(
  LibraryCatalogNavigationItem a,
  LibraryCatalogNavigationItem b,
) {
  final leftBucket = _navigationDisplayBucket(a);
  final rightBucket = _navigationDisplayBucket(b);
  final bucketCompare = leftBucket.compareTo(rightBucket);
  if (bucketCompare != 0) return bucketCompare;

  final leftSort = a.sortOrder ?? 1 << 30;
  final rightSort = b.sortOrder ?? 1 << 30;
  final sortCompare = leftSort.compareTo(rightSort);
  if (sortCompare != 0) return sortCompare;

  return a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

int _navigationDisplayBucket(LibraryCatalogNavigationItem item) {
  if (item.isBodyStart) return 0;
  if (item.isFrontMatter) return 2;
  if (_isNavigationMetadataHelpEntry(item)) return 3;
  return 1;
}

bool _isNavigationMetadataHelpEntry(LibraryCatalogNavigationItem item) {
  final normalizedLabel = _normalizedNavigationText(item.label);
  final normalizedHref = _normalizedNavigationText(
    p.basenameWithoutExtension(item.href ?? ''),
  );
  final combined = '$normalizedLabel $normalizedHref';

  if (_isNavigationMetadataHelpLabel(combined)) return true;

  final contentKind = item.contentKind?.trim().toLowerCase() ?? '';
  switch (contentKind) {
    case 'cover':
    case 'title_page':
    case 'toc':
    case 'about':
    case 'copyright':
    case 'foreword':
    case 'preface':
    case 'introduction':
      return true;
    default:
      return false;
  }
}

bool _isNavigationMetadataHelpLabel(String value) {
  return libraryIsMetadataSectionLabel(value) ||
      value.contains('overview') ||
      value.contains('table of contents') ||
      value == 'toc' ||
      value.startsWith('toc ') ||
      value.contains(' contents') ||
      value.startsWith('nav ') ||
      value.contains('about book') ||
      value.contains('aboutbook') ||
      value.contains('information about this book') ||
      value.contains('about this book') ||
      value.contains('about the author') ||
      value.contains('further links') ||
      value.contains('further information') ||
      value.contains('end user license agreement') ||
      value.contains('ellen g white');
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
