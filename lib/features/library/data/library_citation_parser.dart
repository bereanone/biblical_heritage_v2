import 'library_bible_book_aliases.dart';

class LibraryCitationMatch {
  const LibraryCitationMatch(this.start, this.end, this.book, this.locator);
  final int start;
  final int end;
  final String book;
  final String locator;
}

/// Source-preserving citation ranges, including shorthand after edition labels.
List<LibraryCitationMatch> findLibraryCitations(String text) {
  final found = <LibraryCitationMatch>[];
  for (final m in _citation.allMatches(text)) {
    if (m.end < text.length && RegExp(r'[A-Za-z]').hasMatch(text[m.end]))
      continue;
    final book = m[1]!;
    found.add(LibraryCitationMatch(m.start, m.end, book, (m[2] ?? m[3])!));
    var end = m.end;
    while (true) {
      final next = _continuation.matchAsPrefix(text, end);
      if (next == null) break;
      final locator = next[1]!;
      final start = next.end - locator.length;
      found.add(LibraryCitationMatch(start, next.end, book, locator));
      end = next.end;
    }
  }
  found.sort((a, b) => a.start.compareTo(b.start));
  return found;
}

final _books = '${libraryBibleBookPattern()}\\.?';
const _numberedNames =
    r'(?:Samuel|Sam|Kings|Kgs|Chronicles|Chron|Chr|Corinthians|Cor|Thessalonians|Thess|Timothy|Tim|Peter|Pet|John|Jn)\b';
// A comma may introduce the next numbered book, not another verse.
const _verseNumber = r'\d+(?!\d)(?!\s+' + _numberedNames + ')';
const _verses =
    _verseNumber +
    r'(?:\s*[-–]\s*' +
    _verseNumber +
    r')?(?:\s*,\s*' +
    _verseNumber +
    r'(?:\s*[-–]\s*' +
    _verseNumber +
    ')?)*';
final _citation = RegExp(
  '(?<![\\w])($_books)\\s*(?:'
  '(\\d+\\s*:\\s*$_verses(?:\\s*;\\s*\\d+\\s*:\\s*$_verses)*)'
  '|($_verses))(?![\\d:–-])(?!\\s*[:,–-]\\s*(?![123]\\s+$_numberedNames)\\d)',
  caseSensitive: false,
);

// Qualifiers remain ordinary text. Only the following locator inherits the
// preceding book; unrelated prose never supplies a continuation context.
final _continuation = RegExp(
  r'\s*(?:(?:,?\s*(?:Rev\.\s*Ver\.|A\.\s*R\.\s*V\.|R\.\s*V\.|\(?margin\)?|marg\.))\s*)*;\s*'
  '(\\d+\\s*:\\s*$_verses|$_verses)'
  r'(?![\w:–-])(?!\s*[:,–-]\s*\d)',
  caseSensitive: false,
);
