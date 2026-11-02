import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/user_database.dart';
import '../presentation/viewer_passage_models.dart';

class BibleVerseMarkup {
  const BibleVerseMarkup({
    this.markedVerseKeys = const {},
    this.taggedVerseKeys = const {},
  });
  final Set<String> markedVerseKeys;
  final Set<String> taggedVerseKeys;
}

class BibleMarkupRepository {
  BibleMarkupRepository({Database? database}) : _database = database;
  final Database? _database;

  Future<Set<String>> loadMarkedVerseKeys({
    required List<VerseLine> lines,
    required Map<int, String> bookNamesByNumber,
  }) async => (await loadVerseMarkup(
    lines: lines,
    bookNamesByNumber: bookNamesByNumber,
  )).markedVerseKeys;

  Future<BibleVerseMarkup> loadVerseMarkup({
    required List<VerseLine> lines,
    required Map<int, String> bookNamesByNumber,
  }) async {
    if (lines.isEmpty) return const BibleVerseMarkup();

    final displayRefToVerseKey = <String, String>{};
    final numericRefToVerseKey = <String, String>{};
    final groupsByChapter = <String, _VerseChapterGroup>{};

    for (final line in lines) {
      final bookNumber = line.bookNumber;
      final chapter = line.chapter;
      final verse = line.verse;
      if (bookNumber <= 0 || chapter <= 0 || verse <= 0) continue;

      final verseKey = _verseKey(bookNumber, chapter, verse);
      numericRefToVerseKey[_numericVerseRef(bookNumber, chapter, verse)] =
          verseKey;

      final bookName = (bookNamesByNumber[bookNumber] ?? 'Book $bookNumber')
          .trim();
      displayRefToVerseKey['$bookName $chapter:$verse'] = verseKey;

      final chapterKey = _chapterKey(bookNumber, chapter);
      groupsByChapter
          .putIfAbsent(
            chapterKey,
            () => _VerseChapterGroup(bookNumber: bookNumber, chapter: chapter),
          )
          .verses
          .add(verse);
    }

    if (groupsByChapter.isEmpty) return const BibleVerseMarkup();

    final db = _database ?? await UserDatabase.instance.database;
    final markedVerseKeys = <String>{};
    final taggedVerseKeys = <String>{};

    await _loadHighlightVerseKeys(
      db,
      displayRefToVerseKey: displayRefToVerseKey,
      numericRefToVerseKey: numericRefToVerseKey,
      markedVerseKeys: markedVerseKeys,
    );

    for (final tableName in const ['hash_tags', 'dollar_tags', 'at_tags']) {
      await _loadLegacyTableVerseKeys(
        db,
        tableName: tableName,
        groupsByChapter: groupsByChapter,
        markedVerseKeys: taggedVerseKeys,
      );
    }

    for (final tableName in const ['tag_items', 'bookmarks', 'notes']) {
      await _loadRangeTableVerseKeys(
        db,
        tableName: tableName,
        groupsByChapter: groupsByChapter,
        markedVerseKeys: tableName == 'tag_items'
            ? taggedVerseKeys
            : markedVerseKeys,
      );
    }

    markedVerseKeys.addAll(taggedVerseKeys);
    return BibleVerseMarkup(
      markedVerseKeys: markedVerseKeys,
      taggedVerseKeys: taggedVerseKeys,
    );
  }

  Future<List<String>> loadTagNamesForVerses(List<VerseLine> lines) async {
    if (lines.isEmpty) return const [];
    final db = _database ?? await UserDatabase.instance.database;
    final names = <String>{};
    for (final line in lines) {
      for (final table in const ['hash_tags', 'dollar_tags']) {
        final rows = await db.query(
          table,
          columns: ['tag'],
          where:
              "book_number = ? AND chapter_number = ? AND verse_number = ? AND deleted_at_utc IS NULL AND COALESCE(trashed_at_utc, '') = ''",
          whereArgs: [line.bookNumber, line.chapter, line.verse],
        );
        for (final row in rows) {
          final name = row['tag']?.toString().trim() ?? '';
          if (name.isNotEmpty) {
            names.add(name.replaceFirst(RegExp(r'^[#\$]+'), ''));
          }
        }
      }
      final rows = await db.rawQuery(
        """
        SELECT g.name FROM tag_items i JOIN tag_groups g ON g.id = i.tag_group_id
        WHERE i.book_id = ? AND i.chapter = ? AND i.verse_start <= ? AND MAX(i.verse_start, i.verse_end) >= ?
        AND i.deleted_at IS NULL AND g.deleted_at IS NULL
        AND COALESCE(i.trashed_at, '') = '' AND COALESCE(g.trashed_at, '') = ''
        AND g.tag_kind NOT IN ('import_root', 'import_package')
      """,
        [line.bookNumber, line.chapter, line.verse, line.verse],
      );
      for (final row in rows) {
        final name = row['name']?.toString().trim() ?? '';
        if (name.isNotEmpty) {
          names.add(name.replaceFirst(RegExp(r'^[#\$]+'), ''));
        }
      }
    }
    return names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  Future<void> _loadHighlightVerseKeys(
    Database db, {
    required Map<String, String> displayRefToVerseKey,
    required Map<String, String> numericRefToVerseKey,
    required Set<String> markedVerseKeys,
  }) async {
    if (displayRefToVerseKey.isEmpty) return;
    final verseRefs = <String>{
      ...displayRefToVerseKey.keys,
      ...numericRefToVerseKey.keys,
    }.toList(growable: false);
    final placeholders = List.filled(verseRefs.length, '?').join(',');
    final rows = await db.rawQuery('''
      SELECT verse_ref
      FROM highlights
      WHERE verse_ref IN ($placeholders)
      ''', verseRefs);
    for (final row in rows) {
      final verseRef = row['verse_ref']?.toString().trim() ?? '';
      if (verseRef.isEmpty) continue;
      final verseKey =
          displayRefToVerseKey[verseRef] ?? numericRefToVerseKey[verseRef];
      if (verseKey != null) {
        markedVerseKeys.add(verseKey);
      }
    }
  }

  Future<void> _loadLegacyTableVerseKeys(
    Database db, {
    required String tableName,
    required Map<String, _VerseChapterGroup> groupsByChapter,
    required Set<String> markedVerseKeys,
  }) async {
    for (final group in groupsByChapter.values) {
      final verses = group.sortedVerses;
      if (verses.isEmpty) continue;
      final placeholders = List.filled(verses.length, '?').join(',');
      final rows = await db.query(
        tableName,
        columns: ['verse_number'],
        where:
            '''
          book_number = ?
          AND chapter_number = ?
          AND deleted_at_utc IS NULL
          AND COALESCE(trashed_at_utc, '') = ''
          AND verse_number IN ($placeholders)
        ''',
        whereArgs: [group.bookNumber, group.chapter, ...verses],
        orderBy: 'verse_number ASC, id ASC',
      );
      for (final row in rows) {
        final verse = (row['verse_number'] as num?)?.toInt();
        if (verse == null || verse <= 0) continue;
        markedVerseKeys.add(_verseKey(group.bookNumber, group.chapter, verse));
      }
    }
  }

  Future<void> _loadRangeTableVerseKeys(
    Database db, {
    required String tableName,
    required Map<String, _VerseChapterGroup> groupsByChapter,
    required Set<String> markedVerseKeys,
  }) async {
    for (final group in groupsByChapter.values) {
      final rows = await db.query(
        tableName,
        columns: ['verse_start', 'verse_end'],
        where: '''
          book_id = ?
          AND chapter = ?
          AND deleted_at IS NULL
          AND verse_end >= ?
          AND verse_start <= ?
        ''',
        whereArgs: [
          group.bookNumber,
          group.chapter,
          group.minVerse,
          group.maxVerse,
        ],
        orderBy: 'verse_start ASC, verse_end ASC, id ASC',
      );
      for (final row in rows) {
        final startVerse = (row['verse_start'] as num?)?.toInt();
        final endVerse = (row['verse_end'] as num?)?.toInt() ?? startVerse;
        if (startVerse == null || startVerse <= 0) continue;
        final normalizedEnd = endVerse == null || endVerse < startVerse
            ? startVerse
            : endVerse;
        for (var verse = startVerse; verse <= normalizedEnd; verse++) {
          if (!group.verses.contains(verse)) continue;
          markedVerseKeys.add(
            _verseKey(group.bookNumber, group.chapter, verse),
          );
        }
      }
    }
  }
}

class _VerseChapterGroup {
  _VerseChapterGroup({required this.bookNumber, required this.chapter});

  final int bookNumber;
  final int chapter;
  final Set<int> verses = <int>{};

  List<int> get sortedVerses {
    final sorted = verses.toList(growable: false)..sort();
    return sorted;
  }

  int get minVerse {
    if (verses.isEmpty) return 0;
    var min = 1 << 30;
    for (final verse in verses) {
      if (verse < min) min = verse;
    }
    return min;
  }

  int get maxVerse {
    if (verses.isEmpty) return 0;
    var max = 0;
    for (final verse in verses) {
      if (verse > max) max = verse;
    }
    return max;
  }
}

String _chapterKey(int bookNumber, int chapter) => '$bookNumber:$chapter';

String _numericVerseRef(int bookNumber, int chapter, int verse) {
  return '$bookNumber:$chapter:$verse';
}

String _verseKey(int bookNumber, int chapter, int verse) {
  return '$bookNumber:$chapter:$verse';
}
