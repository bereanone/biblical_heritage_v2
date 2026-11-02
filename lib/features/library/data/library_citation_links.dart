import 'library_citation_parser.dart';

/// Adds lookup targets without rewriting source text, marks, or existing links.
/// Formatting boundaries may divide references; line breaks and existing links
/// remain boundaries. Each styled piece points to the whole reference.
/// The popup validates every requested verse against the installed Bible.
///
/// [resolves], when given, is consulted per candidate match (raw book text,
/// raw chapter/verse locator text) before it is linked. A candidate this
/// rejects is left as plain, unlinked, undecorated text — never underlined —
/// so a reference that will not resolve in the popup is never presented as
/// tappable. Omitting [resolves] keeps every syntactic match linked, as
/// before.
List<Map<String, Object?>> linkLibraryCitations(
  List<Map<String, Object?>> nodes, {
  bool Function(String book, String locator)? resolves,
}) {
  final result = <Map<String, Object?>>[];
  final run = <Map<String, Object?>>[];
  void flush() {
    final text = run.map((node) => node['text'] as String).join();
    final matches = findLibraryCitations(text);
    var offset = 0;
    for (final node in run) {
      final value = node['text'] as String;
      final end = offset + value.length;
      var cursor = offset;
      for (final match in matches) {
        if (match.end <= offset || match.start >= end) continue;
        final start = match.start < offset ? offset : match.start;
        final stop = match.end > end ? end : match.end;
        if (start > cursor) {
          result.add({...node, 'text': text.substring(cursor, start)});
        }
        final book = match.book;
        final locator = match.locator;
        final ok = resolves == null || resolves(book, locator);
        result.add({
          ...node,
          'text': text.substring(start, stop),
          if (ok)
            'link':
                'studybible-citation:${Uri.encodeComponent('$book $locator')}',
          if (ok) 'link_kind': 'external',
        });
        cursor = stop;
      }
      if (cursor < end)
        result.add({...node, 'text': text.substring(cursor, end)});
      if (value.isEmpty) result.add(node);
      offset = end;
    }
    run.clear();
  }

  for (final node in nodes) {
    final text = node['text'];
    final existingLink = node['link'];
    // A citation link baked in at import time (or by an earlier app version,
    // before a book/abbreviation gap was fixed) gets the same live check as
    // a freshly detected one. Every other kind of existing link — authored
    // navigation, footnote returns, the legacy reader's 'existing' sentinel —
    // is never touched here.
    if (existingLink is String &&
        existingLink.startsWith('studybible-citation:') &&
        resolves != null) {
      flush();
      final parts = _splitCitationLookup(
        Uri.decodeComponent(
          existingLink.substring('studybible-citation:'.length),
        ),
      );
      if (parts == null || !resolves(parts.$1, parts.$2)) {
        result.add(
          {...node}
            ..remove('link')
            ..remove('link_kind'),
        );
      } else {
        result.add(node);
      }
      continue;
    }
    if (node['type'] != 'text' || text is! String || existingLink != null) {
      flush();
      result.add(node);
      continue;
    }
    run.add(node);
  }
  flush();
  return result;
}

/// Reverses the `'$book $locator'` join used to build a citation lookup
/// string. The locator always starts with a digit and the book text never
/// contains one, so the first "whitespace then digit" boundary is the split
/// point even for a numbered book like "1 Pet".
(String, String)? _splitCitationLookup(String citation) {
  final match = RegExp(r'^(.*?)\s+(\d.*)$').firstMatch(citation);
  if (match == null) return null;
  return (match.group(1)!, match.group(2)!);
}
