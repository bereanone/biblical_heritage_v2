import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Reuses persisted block identities within one explicit imported work.
/// Ordinal hashes are initial IDs, not proof that an old and new paragraph
/// are the same. A newly recovered heading must not transfer an existing ID
/// (and its annotations/position) to the next paragraph.
///
/// Match unique source anchors first, then unique exact content at the same
/// source file/anchor. Unchanged runs between proven matches retain their
/// order. Ambiguous duplicate insertions are deliberately not guessed.
/// Activation guards decide whether an unmatched protected block can proceed.
Map<String, String> reconcileLibraryBlockIds({
  required String libraryItemId,
  required String sourceHash,
  required List<Map<String, Object?>> previous,
  required List<Map<String, Object?>> candidate,
}) {
  for (final row in [...previous, ...candidate]) {
    if (row['library_item_id'] != libraryItemId) {
      throw ArgumentError('Block reconciliation cannot cross work identities.');
    }
  }
  final matches = <String, String>{};
  final usedOld = <String>{};
  String id(Map<String, Object?> row) => row['id'] as String;
  String? anchorKey(Map<String, Object?> row) {
    final anchor = row['source_anchor']?.toString() ?? '';
    return anchor.isEmpty ? null : jsonEncode([row['source_href'], anchor]);
  }

  String contentKey(Map<String, Object?> row, {bool includeAnchor = true}) {
    // Image alt text does not identify the image. Extracted asset names carry
    // a byte hash, and must agree before unanchored images can be matched.
    final formatted = row['block_type'] == 'image'
        ? jsonDecode(row['formatted_content'] as String) as Map
        : null;
    return jsonEncode([
      row['source_href'],
      if (includeAnchor) row['source_anchor'],
      row['block_type'],
      row['plain_text'],
      if (formatted != null) formatted['nodes'],
    ]);
  }

  // Equal labels can point to different destinations (for example two
  // Appendix entries). Unchanged complete link nodes provide independent
  // source evidence when moving an intervening summary breaks ordinal runs.
  String? linkedContentKey(Map<String, Object?> row) {
    final formatted =
        jsonDecode(row['formatted_content'] as String? ?? '{}') as Map;
    final nodes = formatted['nodes'];
    if (nodes is! List ||
        !nodes.any(
          (n) =>
              n is Map && n['link_kind'] == 'internal' && n['link'] is String,
        )) {
      return null;
    }
    return jsonEncode([contentKey(row), nodes]);
  }

  void match(Map<String, Object?> old, Map<String, Object?> next) {
    if (matches.containsKey(id(next)) || usedOld.contains(id(old))) return;
    matches[id(next)] = id(old);
    usedOld.add(id(old));
  }

  Map<String, List<Map<String, Object?>>> groups(
    List<Map<String, Object?>> rows,
    String? Function(Map<String, Object?>) key,
  ) {
    final result = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final value = key(row);
      if (value != null) result.putIfAbsent(value, () => []).add(row);
    }
    return result;
  }

  for (final key in [anchorKey, linkedContentKey, contentKey]) {
    final oldGroups = groups(previous, key), newGroups = groups(candidate, key);
    for (final entry in newGroups.entries) {
      final old = oldGroups[entry.key];
      if (entry.value.length == 1 &&
          old?.length == 1 &&
          old!.single['block_type'] == entry.value.single['block_type']) {
        match(old.single, entry.value.single);
      }
    }
  }

  // Adding a new source landmark to unchanged, uniquely identified content
  // must not discard its existing annotations or position. This only permits
  // an unanchored -> newly anchored transition. Existing anchors, duplicates,
  // different source files, changed text and reused landmarks are not guessed.
  Set<String> landmarks(Map<String, Object?> row) {
    final result = <String>{};
    final primary = anchorKey(row);
    if (primary != null) result.add(primary);
    final formatted =
        jsonDecode(row['formatted_content'] as String? ?? '{}') as Map;
    final metadata = formatted['metadata'];
    final aliases = metadata is Map ? metadata['source_anchor_aliases'] : null;
    if (aliases is List) {
      for (final alias in aliases.whereType<String>()) {
        result.add(jsonEncode([row['source_href'], alias]));
      }
    }
    return result;
  }

  final oldLandmarks = previous.expand(landmarks).toSet();
  final oldContent = groups(
    previous,
    (row) => contentKey(row, includeAnchor: false),
  );
  final newContent = groups(
    candidate,
    (row) => contentKey(row, includeAnchor: false),
  );
  final newLandmarks = <String, int>{};
  for (final row in candidate) {
    for (final landmark in landmarks(row)) {
      newLandmarks.update(landmark, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  for (final entry in newContent.entries) {
    final old = oldContent[entry.key];
    if (old?.length != 1 || entry.value.length != 1) continue;
    final next = entry.value.single;
    final landmark = anchorKey(next);
    if (anchorKey(old!.single) == null &&
        landmark != null &&
        !oldLandmarks.contains(landmark) &&
        newLandmarks[landmark] == 1) {
      match(old.single, next);
    }
  }

  final oldFiles = groups(previous, (r) => r['source_href']?.toString() ?? '');
  final newFiles = groups(candidate, (r) => r['source_href']?.toString() ?? '');
  for (final entry in newFiles.entries) {
    final old = oldFiles[entry.key];
    if (old == null) continue;
    final next = entry.value;
    int order(Map<String, Object?> a, Map<String, Object?> b) =>
        (a['display_order'] as int).compareTo(b['display_order'] as int);
    old.sort(order);
    next.sort(order);
    final oldIndex = {for (var i = 0; i < old.length; i++) id(old[i]): i};
    var previousNew = -1, previousOld = -1;
    for (var endNew = 0; endNew <= next.length; endNew++) {
      final matchedOld = endNew == next.length
          ? null
          : matches[id(next[endNew])];
      if (endNew != next.length && matchedOld == null) continue;
      final endOld = endNew == next.length ? old.length : oldIndex[matchedOld]!;
      final length = endNew - previousNew - 1;
      if (endOld - previousOld - 1 == length && length > 0) {
        var equal = true;
        for (var offset = 1; offset <= length; offset++) {
          final a = old[previousOld + offset], b = next[previousNew + offset];
          if (usedOld.contains(id(a)) || contentKey(a) != contentKey(b)) {
            equal = false;
            break;
          }
        }
        if (equal) {
          for (var offset = 1; offset <= length; offset++) {
            match(old[previousOld + offset], next[previousNew + offset]);
          }
        }
      }
      previousNew = endNew;
      previousOld = endOld;
    }
  }

  // Reserve every former ID, including those of removed blocks. An unmatched
  // candidate must never inherit a removed paragraph's saved location merely
  // because its ordinal hash happens to be the same.
  final oldIds = previous.map(id).toSet();
  final reserved = {...oldIds, ...candidate.map(id), ...matches.values};
  for (final row in candidate) {
    final proposed = id(row);
    if (matches.containsKey(proposed)) continue;
    if (!oldIds.contains(proposed)) {
      matches[proposed] = proposed;
      continue;
    }
    var attempt = 0;
    String fresh;
    do {
      fresh =
          'ldb_${sha256.convert(utf8.encode(jsonEncode(['reconciled-block-v1', libraryItemId, sourceHash, proposed, attempt++])))}';
    } while (reserved.contains(fresh));
    matches[proposed] = fresh;
    reserved.add(fresh);
  }
  return matches;
}
