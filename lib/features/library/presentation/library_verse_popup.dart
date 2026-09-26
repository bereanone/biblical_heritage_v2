import 'package:flutter/material.dart';
import '../../../core/database/study_bible_database.dart';
import '../../reader/data/commentary_reference_parser.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';
import '../../reader/presentation/viewer_markup_span_builder.dart';

class LibraryVerseTarget {
  const LibraryVerseTarget(this.book, this.chapter, this.verse);
  final int book;
  final int chapter;
  final int verse;
}

String _expandedLibraryBook(String book) {
  var value = book.replaceAll('.', '').trim();
  value = value.replaceFirstMapped(
    RegExp(r'^(III|II|I)\s+', caseSensitive: false),
    (m) => '${{'I': 1, 'II': 2, 'III': 3}[m[1]!.toUpperCase()]} ',
  );
  const aliases = {
    'gen': 'Genesis',
    'ex': 'Exodus',
    'lev': 'Leviticus',
    'num': 'Numbers',
    'deut': 'Deuteronomy',
    'josh': 'Joshua',
    'judg': 'Judges',
    'neh': 'Nehemiah',
    'sam': 'Samuel',
    'chron': 'Chronicles',
    'ps': 'Psalms',
    'prov': 'Proverbs',
    'eccl': 'Ecclesiastes',
    'isa': 'Isaiah',
    'jer': 'Jeremiah',
    'ezek': 'Ezekiel',
    'dan': 'Daniel',
    'hos': 'Hosea',
    'zech': 'Zechariah',
    'zeph': 'Zephaniah',
    'mal': 'Malachi',
    'matt': 'Matthew',
    'rom': 'Romans',
    'cor': 'Corinthians',
    'gal': 'Galatians',
    'eph': 'Ephesians',
    'phil': 'Philippians',
    'col': 'Colossians',
    'thess': 'Thessalonians',
    'tim': 'Timothy',
    'heb': 'Hebrews',
    'pet': 'Peter',
    'rev': 'Revelation',
  };
  final numbered = RegExp(r'^([123])\s+(.+)$').firstMatch(value);
  if (numbered != null) {
    return '${numbered[1]} ${aliases[numbered[2]!.toLowerCase()] ?? numbered[2]}';
  }
  return aliases[value.toLowerCase()] ?? value;
}

/// Fail closed on qualifiers/unknown syntax, never silently omit a verse suffix.
List<LibraryVerseTarget> parseLibraryCitation(
  String citation,
  List<BookRecord> books,
) {
  var text = citation.trim();
  if (text.startsWith('(') && text.endsWith(')')) {
    text = text.substring(1, text.length - 1);
  }
  final lookup = BibleReferenceParser.buildBookLookup(books);
  final aliases = BibleReferenceParser.buildBookAliases(books);
  final result = <LibraryVerseTarget>[];
  String? previousBook;
  for (final part in text.split(';')) {
    final match = RegExp(
      r'^\s*(?:(.+?)\s+)?(\d+)\s*:\s*([\d,\s–-]+)\.?\s*$',
    ).firstMatch(part);
    if (match == null) throw const FormatException('Citation needs review');
    final book = match.group(1)?.trim() ?? previousBook;
    if (book == null) throw const FormatException('Book name missing');
    previousBook = book;
    final chapter = int.parse(match.group(2)!);
    final probe = '${_expandedLibraryBook(book)} $chapter:1';
    final parsed = BibleReferenceParser.extractReferences(
      probe,
      lookup,
      aliases: aliases,
    );
    if (parsed.length != 1 ||
        parsed.single.originalReferenceText.toLowerCase() !=
            probe.toLowerCase()) {
      throw const FormatException('Book name not recognized');
    }
    for (final range in match.group(3)!.split(',')) {
      final span = RegExp(
        r'^\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*$',
      ).firstMatch(range);
      if (span == null) throw const FormatException('Verse range needs review');
      final first = int.parse(span.group(1)!);
      final last = int.parse(span.group(2) ?? span.group(1)!);
      if (chapter < 1 || first < 1 || last < first || last - first > 200) {
        throw const FormatException('Invalid verse range');
      }
      for (var verse = first; verse <= last; verse++) {
        if (result.length >= 200) {
          throw const FormatException('Citation too long');
        }
        if (!result.any(
          (v) =>
              v.book == parsed.single.bookId &&
              v.chapter == chapter &&
              v.verse == verse,
        )) {
          result.add(LibraryVerseTarget(parsed.single.bookId, chapter, verse));
        }
      }
    }
  }
  return result;
}

/// Mirrors [loadLibraryPopupVerses]'s resolution rules synchronously against
/// a preloaded verse-count table (bookNumber -> chapter -> highest verse), so
/// the reader can decide whether to underline a detected reference without a
/// database round trip per candidate. Any syntax or bound this rejects is
/// exactly what the popup itself would reject or fail to find text for.
bool libraryCitationResolves(
  String book,
  String locator,
  List<BookRecord> books,
  Map<int, Map<int, int>> verseCounts,
) {
  try {
    if (locator.contains(':')) {
      final targets = parseLibraryCitation('$book $locator', books);
      if (targets.isEmpty) return false;
      return targets.every((target) {
        final maxVerse = verseCounts[target.book]?[target.chapter];
        return maxVerse != null &&
            target.verse >= 1 &&
            target.verse <= maxVerse;
      });
    }
    // Bare number(s) with no colon: either chapter number(s) in a
    // multi-chapter book, or verse number(s) in a single-chapter book
    // (Obadiah, Jude). Reuse the chapter-1 probe purely to resolve the book
    // and split the number list, exactly as loadLibraryPopupVerses does.
    final probe = parseLibraryCitation('$book 1:$locator', books);
    if (probe.isEmpty) return false;
    final chapters = verseCounts[probe.first.book];
    if (chapters == null || chapters.isEmpty) return false;
    if (chapters.length == 1) {
      final maxVerse = chapters.values.single;
      return probe.every((t) => t.verse >= 1 && t.verse <= maxVerse);
    }
    return probe.every((t) => chapters.containsKey(t.verse));
  } on FormatException {
    return false;
  }
}

class LibraryPopupVerse {
  const LibraryPopupVerse(
    this.target,
    this.label,
    this.html, {
    this.blockId,
    this.startsInRedLetter = false,
  });
  final LibraryVerseTarget target;
  final String label;
  final String html;
  final int? blockId;
  final bool startsInRedLetter;

  InlineSpan buildSpan({
    required TextStyle baseStyle,
    required Color redLetterColor,
    bool isNightMode = false,
  }) => buildViewerMarkupSpan(
    html: html,
    fallbackText: '',
    baseStyle: baseStyle,
    redLetterColor: redLetterColor,
    isNightMode: isNightMode,
    startsInRedLetter: startsInRedLetter,
    blockId: blockId,
  );
}

Future<List<LibraryPopupVerse>> loadLibraryPopupVerses(String citation) async {
  final db = StudyBibleDatabase.instance;
  final books = await db.loadBooks();
  var lookup = citation.trim();
  if (lookup.startsWith('(') && lookup.endsWith(')')) {
    lookup = lookup.substring(1, lookup.length - 1).trim();
  }
  final chapterOnly = lookup.contains(':')
      ? null
      : RegExp(r'^(.+?)\s+(\d+(?:\s*[-–,]\s*\d+)*)\.?$').firstMatch(lookup);
  if (chapterOnly != null) {
    final book = chapterOnly[1]!;
    final numbers = chapterOnly[2]!;
    final probe = parseLibraryCitation('$book 1:$numbers', books);
    final bookId = probe.first.book;
    final chapters = await db.loadChapters(bookId);
    if (chapters.length == 1) {
      // Obadiah 15,16 and Jude 14 are verse references in one-chapter books.
      lookup = '$book ${chapters.single}:$numbers';
    } else {
      final expanded = <String>[];
      var count = 0;
      for (final requested in probe) {
        final chapter = requested.verse;
        if (!chapters.contains(chapter)) {
          throw const FormatException('Chapter unavailable');
        }
        final verses = await db.loadVerses(
          bookNumber: bookId,
          chapter: chapter,
        );
        count += verses.length;
        if (verses.isEmpty || count > 200) {
          throw const FormatException('Chapter range unavailable or too long');
        }
        expanded.add('$book $chapter:${verses.join(',')}');
      }
      lookup = expanded.join('; ');
    }
  }
  final targets = parseLibraryCitation(lookup, books);
  final throughChapterByBook = <int, int>{};
  for (final target in targets) {
    final previous = throughChapterByBook[target.book] ?? 0;
    if (target.chapter > previous) {
      throughChapterByBook[target.book] = target.chapter;
    }
  }
  final blocks = <(int, int, int), LibraryPopupVerse>{};
  for (final entry in throughChapterByBook.entries) {
    final rows = await db.loadVerseBlocks(
      bookNumber: entry.key,
      throughChapter: entry.value,
    );
    final name = books.firstWhere((b) => b.bookNumber == entry.key).bookName;
    var inRedLetter = false;
    for (final row in rows) {
      final chapter = (row['chapter'] as num).toInt();
      final verse = (row['block_index'] as num).toInt();
      final html = row['html']?.toString() ?? '';
      final key = (entry.key, chapter, verse);
      if (blocks.containsKey(key)) {
        throw const FormatException('Ambiguous Bible verse block');
      }
      blocks[key] = LibraryPopupVerse(
        LibraryVerseTarget(entry.key, chapter, verse),
        '$name $chapter:$verse',
        html,
        blockId: (row['id'] as num).toInt(),
        startsInRedLetter: inRedLetter,
      );
      inRedLetter = computeViewerRedLetterContinuation(
        html,
        startsInRedLetter: inRedLetter,
      );
    }
  }
  final verses = <LibraryPopupVerse>[];
  for (final target in targets) {
    final block = blocks[(target.book, target.chapter, target.verse)];
    if (block == null ||
        block.html.trim().isEmpty ||
        block
            .buildSpan(baseStyle: const TextStyle(), redLetterColor: Colors.red)
            .toPlainText()
            .trim()
            .isEmpty) {
      throw const FormatException('Verse block unavailable in this Bible');
    }
    verses.add(block);
  }
  return verses;
}

Future<String> tagLibraryPopupVerses(List<LibraryPopupVerse> verses) async {
  final repository = HashTagRepository();
  final tag = repository.normalizeTagName(
    await repository.loadDefaultTag() ?? '',
  );
  if (tag.isEmpty) return 'No default hashtag currently selected.';
  final category = await repository.loadDefaultTagCategory();
  var inserted = 0;
  var skipped = 0;
  for (final verse in verses) {
    final target = verse.target;
    final result = await repository.addBibleRangeToTag(
      tag: tag,
      bookNumber: target.book,
      chapter: target.chapter,
      verseStart: target.verse,
      verseEnd: target.verse,
      category: category,
    );
    inserted += result.inserted;
    skipped += result.skipped;
  }
  return inserted > 0
      ? 'Added $inserted verse(s) to $tag.'
      : skipped == verses.length
      ? 'These verses are already in $tag.'
      : 'No verses were added. Please check the active hashtag.';
}

Future<void> showLibraryVersePopup(
  BuildContext context,
  String citation,
  double fontScale,
) => showDialog<void>(
  context: context,
  builder: (_) => LibraryVersePopup(citation: citation, fontScale: fontScale),
);

class LibraryVersePopup extends StatefulWidget {
  const LibraryVersePopup({
    super.key,
    required this.citation,
    this.fontScale = 1,
    this.loader = loadLibraryPopupVerses,
    this.tagger = tagLibraryPopupVerses,
  });
  final String citation;
  final double fontScale;
  final Future<List<LibraryPopupVerse>> Function(String) loader;
  final Future<String> Function(List<LibraryPopupVerse>) tagger;
  @override
  State<LibraryVersePopup> createState() => _LibraryVersePopupState();
}

class _LibraryVersePopupState extends State<LibraryVersePopup> {
  late final Future<List<LibraryPopupVerse>> _verses = widget.loader(
    widget.citation,
  );
  bool _busy = false;
  String? _message;
  Future<void> _tag(List<LibraryPopupVerse> verses) async {
    if (_busy || verses.isEmpty) return;
    setState(() => _busy = true);
    try {
      final message = await widget.tagger(verses);
      if (mounted) setState(() => _message = message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Tagging did not finish. Please check your hashtag before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LibraryPopupVerse>>(
    future: _verses,
    builder: (context, snapshot) {
      final verses = snapshot.data ?? const <LibraryPopupVerse>[];
      final narrow =
          MediaQuery.sizeOf(context).width < 620 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.3;
      final back = IconButton(
        tooltip: 'Close verse popup',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      );
      final action = snapshot.hasData && !snapshot.hasError && verses.isNotEmpty
          ? Tooltip(
              message: 'Add to active hashtag',
              child: ElevatedButton.icon(
                icon: const Text('!'),
                label: const Text('Add to default hashtag'),
                onPressed: _busy ? null : () => _tag(verses),
              ),
            )
          : null;
      return AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                back,
                Expanded(
                  child: Text(widget.citation, textAlign: TextAlign.center),
                ),
                if (!narrow && action != null)
                  action
                else
                  const SizedBox(width: 48),
              ],
            ),
            if (narrow && action != null)
              Align(alignment: Alignment.centerRight, child: action),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _message!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
            if (_message == 'No default hashtag currently selected.')
              Text(
                'Select a default hashtag in the Bible reader.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: snapshot.hasError
              ? const Text(
                  'This Bible reference could not be fully resolved in the installed Bible.',
                )
              : !snapshot.hasData
              ? const SizedBox(
                  height: 64,
                  child: Center(child: CircularProgressIndicator()),
                )
              : SingleChildScrollView(
                  key: const ValueKey('library-popup-verses'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final verse in verses)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText.rich(
                            TextSpan(
                              children: [
                                TextSpan(text: '${verse.label}\n'),
                                verse.buildSpan(
                                  baseStyle: TextStyle(
                                    fontSize: 18 * widget.fontScale,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                  redLetterColor:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? const Color(0xFFFF3B30)
                                      : const Color(0xFFC62828),
                                  isNightMode:
                                      Theme.of(context).brightness ==
                                      Brightness.dark,
                                ),
                              ],
                            ),
                            style: TextStyle(
                              fontSize: 18 * widget.fontScale,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      );
    },
  );
}
