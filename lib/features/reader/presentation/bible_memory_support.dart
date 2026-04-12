import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/database/user_database.dart';
import '../data/bible_memory_repository.dart';

class BibleMemoryImportResult {
  const BibleMemoryImportResult({
    required this.importedCount,
    this.selectedGroup,
  });

  final int importedCount;
  final String? selectedGroup;
}

class BibleMemorySupport {
  static const allGroups = 'All Groups';
  static const ungrouped = 'Ungrouped';

  static Future<Set<String>> loadHashTagGroups() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT tag
      FROM hash_tags
      WHERE tag IS NOT NULL AND TRIM(tag) <> ''
      ORDER BY tag COLLATE NOCASE ASC
      ''',
    );
    return rows
        .map((row) => row['tag']?.toString().trim() ?? '')
        .where((tag) => tag.isNotEmpty)
        .map((tag) => tag.startsWith('#') ? tag : '#$tag')
        .toSet();
  }

  static Future<Map<String, Object?>?> loadVerseRow({
    required int bookNumber,
    required int chapter,
    required int verse,
  }) async {
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.rawQuery(
      '''
      SELECT books.book_name, bible_blocks.plain_text AS text
      FROM bible_blocks
      JOIN books ON books.book_number = bible_blocks.book_number
      WHERE bible_blocks.book_number = ? AND bible_blocks.chapter = ? AND bible_blocks.block_index = ?
      LIMIT 1
      ''',
      [bookNumber, chapter, verse],
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  static Future<List<Map<String, Object?>>> loadVerseRowsInRange({
    required int bookNumber,
    required int startChapter,
    required int startVerse,
    required int endChapter,
    required int endVerse,
  }) async {
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.rawQuery(
      '''
      SELECT books.book_name, bible_blocks.chapter, bible_blocks.block_index AS verse, bible_blocks.plain_text AS text
      FROM bible_blocks
      JOIN books ON books.book_number = bible_blocks.book_number
      WHERE bible_blocks.book_number = ?
      AND (
        (bible_blocks.chapter = ? AND bible_blocks.chapter = ? AND bible_blocks.block_index BETWEEN ? AND ?)
        OR
        (bible_blocks.chapter = ? AND bible_blocks.chapter < ? AND bible_blocks.block_index >= ?)
        OR
        (bible_blocks.chapter = ? AND bible_blocks.chapter > ? AND bible_blocks.block_index <= ?)
        OR
        (bible_blocks.chapter > ? AND bible_blocks.chapter < ?)
      )
      ORDER BY bible_blocks.chapter ASC, bible_blocks.block_index ASC
      ''',
      [
        bookNumber,
        startChapter,
        endChapter,
        startVerse,
        endVerse,
        startChapter,
        endChapter,
        startVerse,
        endChapter,
        startChapter,
        endVerse,
        startChapter,
        endChapter,
      ],
    );
    return rows
        .map(
          (row) => <String, Object?>{
            'book_name': row['book_name'],
            'chapter': row['chapter'],
            'verse': row['verse'],
            'text': row['text'],
          },
        )
        .toList(growable: false);
  }

  static Future<BibleMemoryImportResult?> importTagGroup(
    BuildContext context,
    BibleMemoryRepository repository,
  ) async {
    final userDb = await UserDatabase.instance.database;
    final tagRows = await userDb.rawQuery(
      '''
      SELECT DISTINCT tag
      FROM hash_tags
      WHERE tag IS NOT NULL AND TRIM(tag) <> ''
      ORDER BY tag COLLATE NOCASE ASC
      ''',
    );
    final tags = tagRows
        .map((row) => row['tag']?.toString() ?? '')
        .where((tag) => tag.trim().isNotEmpty)
        .toList(growable: false);
    if (tags.isEmpty || !context.mounted) return null;

    final selectedTag = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Import #Tag Group'),
        children: tags
            .map(
              (tag) => SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(tag),
                child: Text(tag.startsWith('#') ? tag : '#$tag'),
              ),
            )
            .toList(),
      ),
    );
    if (selectedTag == null || !context.mounted) return null;
    final displayTag =
        selectedTag.startsWith('#') ? selectedTag : '#$selectedTag';
    final verseRows = await userDb.rawQuery(
      '''
      SELECT DISTINCT book_number, chapter_number, verse_number
      FROM hash_tags
      WHERE tag = ?
      ORDER BY book_number ASC, chapter_number ASC, verse_number ASC
      ''',
      [selectedTag],
    );
    var imported = 0;
    for (final row in verseRows) {
      final bookNumber = (row['book_number'] as num?)?.toInt();
      final chapter = (row['chapter_number'] as num?)?.toInt();
      final verse = (row['verse_number'] as num?)?.toInt();
      if (bookNumber == null || chapter == null || verse == null) continue;
      final verseRow = await loadVerseRow(
        bookNumber: bookNumber,
        chapter: chapter,
        verse: verse,
      );
      if (verseRow == null) continue;
      await repository.upsertVerse(
        bookNumber: bookNumber,
        bookName: verseRow['book_name'] as String,
        chapter: chapter,
        verse: verse,
        verseText: verseRow['text'] as String,
        groupName: displayTag,
      );
      imported += 1;
    }
    return BibleMemoryImportResult(
      importedCount: imported,
      selectedGroup: displayTag,
    );
  }

  static String memoryPromoHeader() {
    return '*The following is a formatted Bible Memory list for use in the Biblical Heritage #StudyBible app.*';
  }

  static Future<void> exportSelectedGroup(
    BuildContext context, {
    required String selectedGroup,
    required List<MemoryVerse> visibleItems,
  }) async {
    if (selectedGroup == allGroups || visibleItems.isEmpty) return;
    final groupLabel = selectedGroup == ungrouped ? 'Ungrouped' : selectedGroup;
    final lines = <String>[
      memoryPromoHeader(),
      '',
      'Group: $groupLabel',
      '',
    ];
    for (final entry in visibleItems) {
      lines.add(entry.reference);
      if (entry.verseText.trim().isNotEmpty) {
        lines.add(entry.verseText.trim());
      }
      lines.add('');
    }
    await Clipboard.setData(ClipboardData(text: lines.join('\n').trimRight()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${visibleItems.length} verses to clipboard.')),
    );
  }

  static Future<BibleMemoryImportResult?> importExternalList(
    BuildContext context,
    BibleMemoryRepository repository, {
    required String? initialGroupName,
  }) async {
    final clipboard = await Clipboard.getData('text/plain');
    if (!context.mounted) return null;
    final controller = TextEditingController(text: clipboard?.text ?? '');
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import External Memory List'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 18,
            decoration: const InputDecoration(
              hintText: 'Paste memory list text',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || !context.mounted) return null;
    final text = input.trim();
    if (text.isEmpty) return null;

    final bookLookup = await _loadBookLookup();
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    String? activeGroup = initialGroupName;
    var imported = 0;
    var i = 0;
    final refRegex = RegExp(
      r'^(.+?)\s+(\d+)\s*:\s*(\d+)(?:\s*-\s*(?:(\d+)\s*:\s*)?(\d+))?\s*$',
    );
    final groupRegex = RegExp(r'^\s*Group:\s*(.+)\s*$', caseSensitive: false);

    while (i < lines.length) {
      var line = lines[i].trim();
      if (line.startsWith('- ')) line = line.substring(2).trim();
      if (line.isEmpty || _isMemoryPromoLine(line)) {
        i += 1;
        continue;
      }

      final groupMatch = groupRegex.firstMatch(line);
      if (groupMatch != null) {
        final raw = groupMatch.group(1)?.trim() ?? '';
        if (raw.isNotEmpty) {
          activeGroup = raw == ungrouped ? null : raw;
        }
        i += 1;
        continue;
      }

      final refMatch = refRegex.firstMatch(line);
      if (refMatch == null) {
        i += 1;
        continue;
      }

      final rawBook = refMatch.group(1)?.trim() ?? '';
      final startChapter = int.tryParse(refMatch.group(2) ?? '');
      final startVerse = int.tryParse(refMatch.group(3) ?? '');
      final endChapter = int.tryParse(refMatch.group(4) ?? '') ?? startChapter;
      final endVerse = int.tryParse(refMatch.group(5) ?? '') ?? startVerse;
      if (startChapter == null ||
          startVerse == null ||
          endChapter == null ||
          endVerse == null) {
        i += 1;
        continue;
      }

      final lookup = bookLookup[_normalizeBookKey(rawBook)];
      if (lookup == null) {
        i += 1;
        continue;
      }

      final canonicalRows = await loadVerseRowsInRange(
        bookNumber: lookup.$1,
        startChapter: startChapter,
        startVerse: startVerse,
        endChapter: endChapter,
        endVerse: endVerse,
      );
      var verseText = canonicalRows
          .map((row) => (row['text']?.toString() ?? '').trim())
          .where((text) => text.isNotEmpty)
          .join(' ');

      var j = i + 1;
      final inlineText = <String>[];
      while (j < lines.length) {
        var next = lines[j].trim();
        if (next.startsWith('- ')) next = next.substring(2).trim();
        if (next.isEmpty) {
          if (inlineText.isNotEmpty) break;
          j += 1;
          continue;
        }
        if (_isMemoryPromoLine(next) ||
            groupRegex.hasMatch(next) ||
            refRegex.hasMatch(next)) {
          break;
        }
        inlineText.add(next);
        j += 1;
      }

      if (verseText.isEmpty && inlineText.isNotEmpty) {
        verseText = inlineText.join(' ');
      }
      if (verseText.isNotEmpty) {
        await repository.upsertPassage(
          bookNumber: lookup.$1,
          bookName: lookup.$2,
          chapter: startChapter,
          verse: startVerse,
          endChapter: endChapter,
          endVerse: endVerse,
          verseText: verseText,
          groupName: activeGroup,
        );
        imported += 1;
      }
      i = j;
    }

    return BibleMemoryImportResult(importedCount: imported);
  }

  static Future<void> showInstructions(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bible Memory Instructions'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How Bible Memory works',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Bible Memory is built to help you hide Scripture in your heart through gradual recall and repeated review.',
              ),
              SizedBox(height: 10),
              Text(
                'The basic process',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('1. Add a verse or passage you want to memorize.'),
              SizedBox(height: 6),
              Text('2. Open that verse for practice.'),
              SizedBox(height: 6),
              Text('3. Read it carefully, then review it repeatedly.'),
              SizedBox(height: 6),
              Text('4. Use the due queue to keep your review schedule moving.'),
              SizedBox(height: 10),
              Text(
                'Helpful tools',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text('• Add Verse: memorize a single verse.'),
              SizedBox(height: 6),
              Text('• Add Range: memorize a passage range.'),
              SizedBox(height: 6),
              Text('• Import #Tag Group: bring in an existing #tag list as a memory group.'),
              SizedBox(height: 6),
              Text('• Import External: paste a formatted list from outside the app.'),
              SizedBox(height: 6),
              Text('• Export Group: copy the current memory list into a shareable text format.'),
              SizedBox(height: 6),
              Text('• Start Due Review: open the verses that are scheduled for review right now.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static String dueLabel(BuildContext context, MemoryVerse verse) {
    final now = DateTime.now();
    final due = DateTime.fromMillisecondsSinceEpoch(verse.nextDueAt);
    if (due.isBefore(now)) return 'Due now';
    if (due.difference(now).inHours < 24) {
      final time = TimeOfDay.fromDateTime(due);
      return 'Due ${MaterialLocalizations.of(context).formatTimeOfDay(time)}';
    }
    return 'Due ${due.month}/${due.day}';
  }

  static Future<Map<String, (int, String)>> _loadBookLookup() async {
    final books = await StudyBibleDatabase.instance.loadBooks();
    final lookup = <String, (int, String)>{};
    for (final book in books) {
      lookup[_normalizeBookKey(book.bookName)] = (book.bookNumber, book.bookName);
    }
    return lookup;
  }

  static String _normalizeBookKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static bool _isMemoryPromoLine(String input) {
    final line =
        input.trim().replaceAll('*', '').replaceAll('_', '').toLowerCase();
    if (line.isEmpty) return false;
    return (line.contains('formatted bible memory list') &&
            line.contains('biblical heritage')) ||
        (line.contains('formatted sharing list') &&
            line.contains('biblical heritage'));
  }
}
