import '../../../core/database/study_bible_database.dart';

class ParsedBibleReference {
  const ParsedBibleReference({
    required this.originalReferenceText,
    required this.bookId,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.confidence,
    this.parserWarning,
  });

  final String originalReferenceText;
  final int bookId;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final double confidence;
  final String? parserWarning;
}

class BibleReferenceParser {
  BibleReferenceParser._();

  static Map<String, int> buildBookLookup(List<BookRecord> books) {
    final lookup = <String, int>{};
    for (final book in books) {
      for (final alias in _aliasesFor(book.bookName)) {
        lookup[_normalizeBookKey(alias)] = book.bookNumber;
      }
    }
    return lookup;
  }

  static List<String> buildBookAliases(List<BookRecord> books) {
    final aliases = <String>[];
    final seen = <String>{};
    for (final book in books) {
      for (final alias in _aliasesFor(book.bookName)) {
        final normalized = _normalizeBookKey(alias);
        if (normalized.isEmpty || !seen.add(normalized)) continue;
        aliases.add(alias);
      }
    }
    aliases.sort((a, b) => b.length.compareTo(a.length));
    return aliases;
  }

  static List<ParsedBibleReference> extractReferences(
    String text,
    Map<String, int> bookLookup,
    {required List<String> aliases}
  ) {
    final cleaned = text.trim();
    if (cleaned.isEmpty || bookLookup.isEmpty) return const [];

    final aliasList = aliases;
    final aliasPattern = aliasList.map(RegExp.escape).join('|');
    final regex = RegExp(
      r'(?<!\w)('
      '$aliasPattern'
      r')\s+(\d+)(?::(\d+)(?:\s*-\s*(\d+))?)?',
      caseSensitive: false,
    );

    final results = <ParsedBibleReference>[];
    final seen = <String>{};
    for (final match in regex.allMatches(cleaned)) {
      final rawBook = match.group(1)?.trim() ?? '';
      final chapter = int.tryParse(match.group(2) ?? '');
      if (rawBook.isEmpty || chapter == null) continue;

      final bookId = bookLookup[_normalizeBookKey(rawBook)];
      if (bookId == null) continue;

      final verseStartText = match.group(3);
      final verseEndText = match.group(4);
      final original = match.group(0)?.trim() ?? '';
      if (original.isEmpty) continue;

      if (verseStartText == null) {
        final key = '$bookId|$chapter|1|9999|$original';
        if (!seen.add(key)) continue;
        results.add(
          ParsedBibleReference(
            originalReferenceText: original,
            bookId: bookId,
            chapter: chapter,
            verseStart: 1,
            verseEnd: 9999,
            confidence: 0.88,
            parserWarning: 'chapter-level reference',
          ),
        );
        continue;
      }

      final verseStart = int.tryParse(verseStartText);
      final verseEnd = int.tryParse(verseEndText ?? verseStartText);
      if (verseStart == null || verseEnd == null || verseEnd < verseStart) {
        continue;
      }

      final key = '$bookId|$chapter|$verseStart|$verseEnd|$original';
      if (!seen.add(key)) continue;
      results.add(
        ParsedBibleReference(
          originalReferenceText: original,
          bookId: bookId,
          chapter: chapter,
          verseStart: verseStart,
          verseEnd: verseEnd,
          confidence: verseStart == verseEnd ? 1.0 : 0.96,
        ),
      );
    }

    return results;
  }

  static String normalizeBookKey(String input) {
    return _normalizeBookKey(input);
  }

  static List<String> _aliasesFor(String bookName) {
    final aliases = <String>{bookName.trim()};
    final normalized = _normalizeBookKey(bookName);

    if (normalized == 'john') {
      aliases.addAll(const ['Jn']);
    } else if (normalized == '1john') {
      aliases.addAll(const ['1 John', 'I John', 'First John', '1 Jn']);
    } else if (normalized == '2john') {
      aliases.addAll(const ['2 John', 'II John', 'Second John', '2 Jn']);
    } else if (normalized == '3john') {
      aliases.addAll(const ['3 John', 'III John', 'Third John', '3 Jn']);
    } else if (normalized == 'psalm' || normalized == 'psalms') {
      aliases.addAll(const ['Psalm', 'Psalms', 'Ps', 'Psa']);
    } else if (normalized == 'songofsolomon' || normalized == 'songofsongs') {
      aliases.addAll(const [
        'Song of Solomon',
        'Song of Songs',
        'Song',
        'Canticles',
      ]);
    } else if (normalized == 'revelation') {
      aliases.addAll(const ['Rev', 'Apocalypse']);
    }

    final numbered = RegExp(r'^([123])\s+(.+)$').firstMatch(bookName.trim());
    if (numbered != null) {
      final number = numbered.group(1) ?? '';
      final rest = numbered.group(2) ?? '';
      final ordinal = switch (number) {
        '1' => 'First',
        '2' => 'Second',
        '3' => 'Third',
        _ => '',
      };
      final roman = switch (number) {
        '1' => 'I',
        '2' => 'II',
        '3' => 'III',
        _ => '',
      };
      if (ordinal.isNotEmpty) {
        aliases.add('$ordinal $rest');
      }
      if (roman.isNotEmpty) {
        aliases.add('$roman $rest');
      }
      aliases.add('$number $rest');
    }

    return aliases.toList(growable: false);
  }

  static String _normalizeBookKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
