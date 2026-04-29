import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bootstrap/sandbox_bootstrap.dart';
import '../../features/reader/presentation/viewer_search_query.dart';

class StudyBibleDatabase {
  StudyBibleDatabase._();

  static final StudyBibleDatabase instance = StudyBibleDatabase._();

  static const bibleDbName = 'bible_base.db';

  Database? _bibleDb;

  Future<void> initialize() async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    await SandboxBootstrap.ensureReady();
    _bibleDb ??= await _openBibleDb();
  }

  Future<Database> get bible async {
    await initialize();
    return _bibleDb!;
  }

  Future<List<Map<String, Object?>>> loadBlocks({
    required int bookNumber,
    required int chapter,
  }) async {
    final db = await bible;
    return db.query(
      'bible_blocks',
      columns: ['id', 'block_index', 'html', 'plain_text'],
      where: 'book_number = ? AND chapter = ?',
      whereArgs: [bookNumber, chapter],
      orderBy: 'block_index',
    );
  }

  Future<List<Map<String, Object?>>> loadBlockWindowById(
    int centerBlockId, {
    int windowRadius = 250,
  }) async {
    final db = await bible;
    final minId = (centerBlockId - windowRadius).clamp(1, 1 << 62);
    final maxId = (centerBlockId + windowRadius).clamp(1, 1 << 62);
    return db.query(
      'bible_blocks',
      columns: [
        'id',
        'book_number',
        'chapter',
        'block_index',
        'html',
        'plain_text',
      ],
      where: 'id BETWEEN ? AND ?',
      whereArgs: [minId, maxId],
      orderBy: 'book_number, chapter, block_index, id',
    );
  }

  Future<List<BookRecord>> loadBooks() async {
    final db = await bible;
    final rows = await db.query(
      'books',
      columns: ['book_number', 'book_name', 'book_index'],
      orderBy: 'book_index',
    );
    return rows
        .map(
          (row) => BookRecord(
            bookNumber: row['book_number'] as int,
            bookName: row['book_name'] as String,
            bookIndex: row['book_index'] as int,
          ),
        )
        .toList();
  }

  Future<String?> loadBookName(int bookNumber) async {
    final db = await bible;
    final rows = await db.query(
      'books',
      columns: ['book_name'],
      where: 'book_number = ?',
      whereArgs: [bookNumber],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['book_name'] as String?;
  }

  Future<String?> loadVerseText({
    required int bookNumber,
    required int chapter,
    required int verse,
  }) async {
    final db = await bible;
    final rows = await db.query(
      'bible_blocks',
      columns: ['plain_text'],
      where: 'book_number = ? AND chapter = ? AND block_index = ?',
      whereArgs: [bookNumber, chapter, verse],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['plain_text']?.toString();
  }

  Future<List<int>> loadChapters(int bookNumber) async {
    final db = await bible;
    final rows = await db.rawQuery(
      'SELECT DISTINCT chapter FROM bible_blocks WHERE book_number = ? ORDER BY chapter',
      [bookNumber],
    );
    return rows.map((row) => row['chapter'] as int).toList();
  }

  Future<List<int>> loadVerses({
    required int bookNumber,
    required int chapter,
  }) async {
    final db = await bible;
    final rows = await db.rawQuery(
      'SELECT DISTINCT block_index AS verse FROM bible_blocks WHERE book_number = ? AND chapter = ? ORDER BY block_index',
      [bookNumber, chapter],
    );
    return rows.map((row) => row['verse'] as int).toList();
  }

  Future<int?> loadBlockIdForVerse({
    required int bookNumber,
    required int chapter,
    required int verse,
  }) async {
    final db = await bible;
    final rows = await db.query(
      'bible_blocks',
      columns: ['id'],
      where: 'book_number = ? AND chapter = ? AND block_index = ?',
      whereArgs: [bookNumber, chapter, verse],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['id'] as int?;
  }

  Future<Map<int, PassageReference>> loadReferencesForBlockIds(
    List<int> blockIds,
  ) async {
    if (blockIds.isEmpty) return const {};

    final db = await bible;
    final placeholders = List.filled(blockIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT id, book_number, chapter, block_index
      FROM bible_blocks
      WHERE id IN ($placeholders)
      ''', blockIds);
    final books = await loadBooks();
    final namesByNumber = {
      for (final book in books) book.bookNumber: book.bookName,
    };

    return {
      for (final row in rows)
        row['id'] as int: PassageReference(
          bookNumber: row['book_number'] as int,
          bookName:
              namesByNumber[row['book_number']] ?? 'Book ${row['book_number']}',
          chapter: row['chapter'] as int,
          verse: row['block_index'] as int,
        ),
    };
  }

  Future<PassageReference?> loadReferenceForBlockId(int blockId) async {
    final references = await loadReferencesForBlockIds([blockId]);
    return references[blockId];
  }

  Future<Map<int, List<String>>> loadSectionHeadings({
    required int bookNumber,
    required int chapter,
  }) async {
    final db = await bible;
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        '''
        SELECT block_id, heading
        FROM section_headings
        WHERE book_number = ? AND chapter = ?
        ORDER BY block_id
        ''',
        [bookNumber, chapter],
      );
    } on DatabaseException catch (error) {
      if (error.toString().contains('no such table: section_headings')) {
        return const <int, List<String>>{};
      }
      rethrow;
    }

    final headings = <int, List<String>>{};
    for (final row in rows) {
      final blockId = (row['block_id'] as num?)?.toInt();
      final heading = (row['heading'] ?? '').toString().trim();
      if (blockId == null || heading.isEmpty) continue;
      headings.putIfAbsent(blockId, () => <String>[]).add(heading);
    }
    return headings;
  }

  Future<Map<int, List<String>>> loadSectionHeadingsForBlockIds(
    List<int> blockIds,
  ) async {
    if (blockIds.isEmpty) return const <int, List<String>>{};

    final db = await bible;
    final placeholders = List.filled(blockIds.length, '?').join(', ');
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
        SELECT block_id, heading
        FROM section_headings
        WHERE block_id IN ($placeholders)
        ORDER BY block_id
        ''', blockIds);
    } on DatabaseException catch (error) {
      if (error.toString().contains('no such table: section_headings')) {
        return const <int, List<String>>{};
      }
      rethrow;
    }

    final headings = <int, List<String>>{};
    for (final row in rows) {
      final blockId = (row['block_id'] as num?)?.toInt();
      final heading = (row['heading'] ?? '').toString().trim();
      if (blockId == null || heading.isEmpty) continue;
      headings.putIfAbsent(blockId, () => <String>[]).add(heading);
    }
    return headings;
  }

  Future<Map<int, AcrosticRecord>> loadAcrostics({
    required int bookNumber,
    required int chapter,
  }) async {
    final db = await bible;
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery(
        '''
        SELECT block_id, label_native, label_en, label_string, sort_order
        FROM acrostics
        WHERE book_number = ? AND chapter = ?
          AND marker_type = 'acrostic'
        ORDER BY sort_order ASC
        ''',
        [bookNumber, chapter],
      );
    } on DatabaseException catch (error) {
      if (error.toString().contains('no such table: acrostics')) {
        return const <int, AcrosticRecord>{};
      }
      rethrow;
    }

    final acrostics = <int, AcrosticRecord>{};
    for (final row in rows) {
      final blockId = (row['block_id'] as num?)?.toInt();
      if (blockId == null || acrostics.containsKey(blockId)) continue;
      final native = (row['label_native'] ?? '').toString().trim();
      final english = (row['label_en'] ?? '').toString().trim();
      final fallback = (row['label_string'] ?? '').toString().trim();
      final transliteration = english.isNotEmpty ? english : fallback;
      if (native.isEmpty && transliteration.isEmpty) continue;
      acrostics[blockId] = AcrosticRecord(
        hebrew: native,
        transliteration: transliteration,
      );
    }
    return acrostics;
  }

  Future<Map<int, AcrosticRecord>> loadAcrosticsForBlockIds(
    List<int> blockIds,
  ) async {
    if (blockIds.isEmpty) return const <int, AcrosticRecord>{};

    final db = await bible;
    final placeholders = List.filled(blockIds.length, '?').join(', ');
    List<Map<String, Object?>> rows;
    try {
      rows = await db.rawQuery('''
        SELECT block_id, label_native, label_en, label_string, sort_order
        FROM acrostics
        WHERE block_id IN ($placeholders)
          AND marker_type = 'acrostic'
        ORDER BY sort_order ASC
        ''', blockIds);
    } on DatabaseException catch (error) {
      if (error.toString().contains('no such table: acrostics')) {
        return const <int, AcrosticRecord>{};
      }
      rethrow;
    }

    final acrostics = <int, AcrosticRecord>{};
    for (final row in rows) {
      final blockId = (row['block_id'] as num?)?.toInt();
      if (blockId == null || acrostics.containsKey(blockId)) continue;
      final native = (row['label_native'] ?? '').toString().trim();
      final english = (row['label_en'] ?? '').toString().trim();
      final fallback = (row['label_string'] ?? '').toString().trim();
      final transliteration = english.isNotEmpty ? english : fallback;
      if (native.isEmpty && transliteration.isEmpty) continue;
      acrostics[blockId] = AcrosticRecord(
        hebrew: native,
        transliteration: transliteration,
      );
    }
    return acrostics;
  }

  Future<PassageSearchResponse> searchPassages(
    String query, {
    String section = 'All',
    int? bookNumber,
    int limit = 50,
    int offset = 0,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }

    final searchQuery = buildViewerSearchQuery(
      trimmed,
      section: section,
      bookNumber: bookNumber,
    );
    if (searchQuery.whereClause.isEmpty) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }

    final db = await bible;
    final books = await loadBooks();
    final namesByNumber = {
      for (final book in books) book.bookNumber: book.bookName,
    };

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM bible_blocks WHERE (${searchQuery.whereClause})',
      searchQuery.whereArgs,
    );
    final totalCount = (countRows.first['count'] as num?)?.toInt() ?? 0;

    final rows = await db.query(
      'bible_blocks',
      columns: ['id', 'book_number', 'chapter', 'block_index', 'plain_text'],
      where: searchQuery.whereClause,
      whereArgs: searchQuery.whereArgs,
      orderBy: 'book_number, chapter, block_index',
      limit: limit,
      offset: offset,
    );

    final results = rows
        .map(
          (row) => PassageSearchResult(
            blockId: row['id'] as int,
            bookNumber: row['book_number'] as int,
            bookName:
                namesByNumber[row['book_number']] ??
                'Book ${row['book_number']}',
            chapter: row['chapter'] as int,
            verse: row['block_index'] as int,
            text: row['plain_text'] as String? ?? '',
          ),
        )
        .toList(growable: false);

    return PassageSearchResponse(results: results, totalCount: totalCount);
  }

  Future<PassageSearchResponse> loadPassagesForVerseRefs(
    List<String> verseRefs, {
    String section = 'All',
    int? bookNumber,
    int limit = 50,
    int offset = 0,
  }) async {
    if (verseRefs.isEmpty) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }

    final db = await bible;
    final books = await loadBooks();
    final namesByLower = {
      for (final book in books)
        book.bookName.trim().toLowerCase(): book.bookNumber,
    };
    final namesByNumber = {
      for (final book in books) book.bookNumber: book.bookName,
    };
    final range = bookNumber == null ? viewerSectionBookRange(section) : null;

    final parsed = <({int bookNumber, int chapter, int verse})>[];
    for (final rawRef in verseRefs) {
      final ref = rawRef.trim();
      final match = RegExp(r'^(.*)\s+(\d+):(\d+)$').firstMatch(ref);
      if (match == null) continue;
      final bookName = (match.group(1) ?? '').trim().toLowerCase();
      final resolvedBookNumber = namesByLower[bookName];
      final chapter = int.tryParse(match.group(2) ?? '');
      final verse = int.tryParse(match.group(3) ?? '');
      if (resolvedBookNumber == null || chapter == null || verse == null) {
        continue;
      }
      if (bookNumber != null && resolvedBookNumber != bookNumber) {
        continue;
      }
      if (range != null &&
          (resolvedBookNumber < range.$1 || resolvedBookNumber > range.$2)) {
        continue;
      }
      parsed.add((
        bookNumber: resolvedBookNumber,
        chapter: chapter,
        verse: verse,
      ));
    }

    if (parsed.isEmpty) {
      return const PassageSearchResponse(results: [], totalCount: 0);
    }

    final paged = parsed.skip(offset).take(limit).toList(growable: false);
    final results = <PassageSearchResult>[];
    for (final item in paged) {
      final rows = await db.query(
        'bible_blocks',
        columns: ['id', 'book_number', 'chapter', 'block_index', 'plain_text'],
        where: 'book_number = ? AND chapter = ? AND block_index = ?',
        whereArgs: [item.bookNumber, item.chapter, item.verse],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final row = rows.first;
      results.add(
        PassageSearchResult(
          blockId: row['id'] as int,
          bookNumber: row['book_number'] as int,
          bookName:
              namesByNumber[row['book_number']] ?? 'Book ${row['book_number']}',
          chapter: row['chapter'] as int,
          verse: row['block_index'] as int,
          text: row['plain_text'] as String? ?? '',
        ),
      );
    }

    return PassageSearchResponse(results: results, totalCount: parsed.length);
  }

  Future<Map<int, List<InterlinearTokenRecord>>>
  loadInterlinearTokensForBlockIds(
    List<int> blockIds, {
    bool englishOrder = false,
  }) async {
    if (blockIds.isEmpty) return const <int, List<InterlinearTokenRecord>>{};

    final db = await bible;
    final placeholders = List.filled(blockIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT
        bt.block_id,
        bt.verse_index,
        COALESCE(bt.english_gloss, '') AS english_gloss,
        COALESCE(bt.ancient_text, '') AS ancient_text,
        COALESCE(bt.transliteration, sd.transliteration, '') AS transliteration,
        COALESCE(bt.pronunciation, sd.pronunciation, '') AS pronunciation,
        COALESCE(bt.strongs_canonical, bt.strongs_number, '') AS strongs_number,
        COALESCE(bt.morphology_tag, '') AS morphology_tag
      FROM bible_tokens bt
      LEFT JOIN strongs_dictionary sd
        ON sd.strongs_canonical = bt.strongs_canonical
      WHERE bt.block_id IN ($placeholders)
      ORDER BY bt.block_id,
        ${englishOrder ? 'bt.english_gloss' : 'bt.verse_index'},
        bt.verse_index
      ''', blockIds);

    final byBlockId = <int, List<InterlinearTokenRecord>>{};
    for (final row in rows) {
      final blockId = (row['block_id'] as num?)?.toInt();
      if (blockId == null) continue;
      byBlockId
          .putIfAbsent(blockId, () => <InterlinearTokenRecord>[])
          .add(
            InterlinearTokenRecord(
              english: row['english_gloss']?.toString() ?? '',
              original: row['ancient_text']?.toString() ?? '',
              transliteration: row['transliteration']?.toString() ?? '',
              pronunciation: row['pronunciation']?.toString() ?? '',
              strongsNumber: row['strongs_number']?.toString() ?? '',
              morphology: row['morphology_tag']?.toString() ?? '',
            ),
          );
    }
    return byBlockId;
  }

  Future<Database> _openBibleDb() async {
    final path = await SandboxBootstrap.bibleDatabasePath();
    return openDatabase(path, readOnly: true);
  }
}

class InterlinearTokenRecord {
  const InterlinearTokenRecord({
    required this.english,
    required this.original,
    required this.transliteration,
    required this.pronunciation,
    required this.strongsNumber,
    required this.morphology,
  });

  final String english;
  final String original;
  final String transliteration;
  final String pronunciation;
  final String strongsNumber;
  final String morphology;
}

class AcrosticRecord {
  const AcrosticRecord({required this.hebrew, required this.transliteration});

  final String hebrew;
  final String transliteration;
}

class BookRecord {
  const BookRecord({
    required this.bookNumber,
    required this.bookName,
    required this.bookIndex,
  });

  final int bookNumber;
  final String bookName;
  final int bookIndex;
}

class PassageReference {
  const PassageReference({
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
  });

  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;
}

class PassageSearchResult {
  const PassageSearchResult({
    required this.blockId,
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final int blockId;
  final int bookNumber;
  final String bookName;
  final int chapter;
  final int verse;
  final String text;
}

class PassageSearchResponse {
  const PassageSearchResponse({
    required this.results,
    required this.totalCount,
  });

  final List<PassageSearchResult> results;
  final int totalCount;
}
