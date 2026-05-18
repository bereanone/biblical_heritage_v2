import 'package:flutter/material.dart';

List<String> extractSearchHighlightTerms(
  String query, {
  bool booleanSyntax = false,
}) {
  final normalizedQuery = _normalizeSearchInput(
    query,
  ).replaceAll('(', ' ( ').replaceAll(')', ' ) ');
  final regex = RegExp(r'"[^"]+"|\S+');
  final tokens = regex
      .allMatches(normalizedQuery)
      .map((match) => match.group(0)!)
      .toList(growable: false);

  final terms = <String>[];
  var excludeNext = false;
  var skipDepth = 0;

  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    final upper = token.toUpperCase();
    final isBooleanOperator =
        booleanSyntax &&
        token == upper &&
        const ['AND', 'OR', 'NOT'].contains(upper);

    if (skipDepth > 0) {
      if (token == '(') {
        skipDepth += 1;
      } else if (token == ')') {
        skipDepth -= 1;
      }
      continue;
    }

    if (token == '(') {
      if (excludeNext) {
        skipDepth = 1;
        excludeNext = false;
        continue;
      }
      continue;
    }

    if (token == ')') {
      continue;
    }

    if (isBooleanOperator) {
      if (upper == 'NOT') {
        excludeNext = true;
      }
      continue;
    }

    final cleaned = token.replaceAll('"', '').trim();
    if (cleaned.isEmpty) continue;

    final normalizedToken = _normalizeHighlightToken(
      cleaned,
    ).replaceAll('*', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalizedToken.isEmpty) continue;

    if (excludeNext) {
      excludeNext = false;
      continue;
    }

    if (token.startsWith('"') && token.endsWith('"')) {
      terms.add(normalizedToken);
    } else {
      terms.addAll(
        normalizedToken
            .split(' ')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }
  }

  final uniqueTerms = <String>[];
  final seen = <String>{};
  for (final term in terms) {
    final key = term.toLowerCase();
    if (seen.add(key)) {
      uniqueTerms.add(term);
    }
  }
  uniqueTerms.sort((a, b) => b.length.compareTo(a.length));
  return uniqueTerms;
}

List<InlineSpan> buildHighlightedSearchSpans(
  String text,
  List<String> highlightTerms, {
  TextStyle? baseStyle,
  TextStyle? highlightStyle,
}) {
  final terms = highlightTerms
      .map((term) => term.trim())
      .where((term) => term.isNotEmpty)
      .toList(growable: false);
  if (terms.isEmpty || text.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  final matches = <_SearchHighlightRange>[];
  for (final term in terms) {
    final pattern = _buildSearchHighlightPattern(term);
    for (final match in pattern.allMatches(text)) {
      matches.add(_SearchHighlightRange(match.start, match.end));
    }
  }

  if (matches.isEmpty) {
    return [TextSpan(text: text, style: baseStyle)];
  }

  matches.sort((left, right) {
    final startCompare = left.start.compareTo(right.start);
    if (startCompare != 0) return startCompare;
    return right.end.compareTo(left.end);
  });

  final merged = <_SearchHighlightRange>[];
  for (final match in matches) {
    if (merged.isEmpty || match.start > merged.last.end) {
      merged.add(match);
      continue;
    }
    final last = merged.removeLast();
    merged.add(
      _SearchHighlightRange(
        last.start,
        match.end > last.end ? match.end : last.end,
      ),
    );
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in merged) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: baseStyle),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(match.start, match.end),
        style: (highlightStyle ?? baseStyle ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
  }
  return spans;
}

String stripWrappingSearchQuotes(String query) {
  final trimmed = query.trim();
  if (trimmed.length < 2) {
    return trimmed;
  }

  const quotePairs = [
    ('"', '"'),
    ('“', '”'),
    ('„', '‟'),
    ("'", "'"),
    ('‘', '’'),
  ];

  for (final pair in quotePairs) {
    if (trimmed.startsWith(pair.$1) && trimmed.endsWith(pair.$2)) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
  }

  return trimmed;
}

String _normalizeSearchInput(String value) {
  return value
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'");
}

String _normalizeHighlightToken(String value) {
  return _normalizeSearchInput(value)
      .replaceAll(RegExp(r'[^a-zA-Z0-9\s]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
}

RegExp _buildSearchHighlightPattern(String term) {
  final words = term
      .split(RegExp(r'\s+'))
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .map(RegExp.escape)
      .toList(growable: false);
  if (words.isEmpty) {
    return RegExp(r'$.');
  }
  if (words.length == 1) {
    return RegExp(r'\b' + words.first + r'\b', caseSensitive: false);
  }
  const separator = r'[^a-z0-9]+';
  return RegExp(r'\b' + words.join(separator) + r'\b', caseSensitive: false);
}

class _SearchHighlightRange {
  const _SearchHighlightRange(this.start, this.end);

  final int start;
  final int end;
}
