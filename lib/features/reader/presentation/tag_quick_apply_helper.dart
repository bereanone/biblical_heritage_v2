import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/database/user_database.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';

class HashTagTarget {
  const HashTagTarget({
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.verseRef,
    this.tokenNumber,
  });

  final int bookNumber;
  final int chapter;
  final int verse;
  final String verseRef;
  final int? tokenNumber;
}

class HashTagSummary {
  const HashTagSummary({required this.tag, required this.count});

  final String tag;
  final int count;
}

class HashTagEntry {
  const HashTagEntry({
    required this.id,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.verseRef,
    required this.verseText,
    required this.createdAt,
    required this.sortOrder,
    this.contentHtml,
  });

  final int id;
  final int bookNumber;
  final int chapter;
  final int verse;
  final String verseRef;
  final String verseText;
  final int createdAt;
  final int sortOrder;
  final String? contentHtml;
}

enum HashTagEntrySortMode { slideOrder, verseOrder }

class HashTagQuickApplyResult {
  const HashTagQuickApplyResult({
    required this.tag,
    required this.inserted,
    required this.skipped,
  });

  final String? tag;
  final int inserted;
  final int skipped;
}

class HashTagImportResult {
  const HashTagImportResult({
    required this.tag,
    required this.parsedCount,
    required this.insertedCount,
    required this.updatedExistingCount,
    required this.skippedExistingCount,
    required this.failedCount,
    required this.failures,
  });

  final String tag;
  final int parsedCount;
  final int insertedCount;
  final int updatedExistingCount;
  final int skippedExistingCount;
  final int failedCount;
  final List<HashTagImportFailure> failures;

  int get importedCount => insertedCount;
}

class HashTagImportFailure {
  const HashTagImportFailure({
    required this.lineNumber,
    required this.reason,
    required this.line,
  });

  final int lineNumber;
  final String reason;
  final String line;
}

class HashTagRepository {
  HashTagRepository({
    this.tableName = 'hash_tags',
    this.defaultSettingKey = 'tags.default.hash',
    this.categorySettingKeyPrefix = 'tags.category.',
    this.tagPrefix = '#',
  });

  final String tableName;
  final String defaultSettingKey;
  final String categorySettingKeyPrefix;
  final String tagPrefix;
  static const recentImportCategory = 'Recent Import';

  Future<Database> _db() async {
    return UserDatabase.instance.database;
  }

  Future<void> ensureSchema() async {
    final db = await _db();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        tag TEXT NOT NULL,
        category TEXT,
        verse_ref TEXT NOT NULL,
        book_number INTEGER NOT NULL,
        chapter_number INTEGER NOT NULL,
        verse_number INTEGER NOT NULL,
        token_number INTEGER,
        sort_order INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await _addColumnIfMissing(
      db,
      tableName: tableName,
      columnName: 'sort_order',
      columnDefinition: 'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      tableName: tableName,
      columnName: 'category',
      columnDefinition: 'TEXT',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_tag ON $tableName(tag)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_tag_category ON $tableName(tag, category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_${tableName}_ref ON $tableName(verse_ref)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String tableName,
    required String columnName,
    required String columnDefinition,
  }) async {
    final rows = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = rows.any((row) => row['name']?.toString() == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnDefinition',
      );
    }
  }

  Future<int> ensureUserId() async {
    final db = await _db();
    final rows = await db.query(
      'users',
      columns: ['id'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final value = rows.first['id'];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 1;
    }
    return 1;
  }

  String normalizeTagName(String input) {
    final normalizedPrefix = tagPrefix.isEmpty ? '#' : tagPrefix;
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^[#\$@]+'), '');
    if (cleaned.isEmpty) return '';
    return '$normalizedPrefix$cleaned';
  }

  Future<String?> loadDefaultTag() async {
    await ensureSchema();
    final db = await _db();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [defaultSettingKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['value']?.toString().trim() ?? '';
    final normalized = normalizeTagName(raw);
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> saveDefaultTag(String tag) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return;
    await ensureSchema();
    final db = await _db();
    await db.insert('app_settings', {
      'key': defaultSettingKey,
      'value': normalized,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearDefaultTag() async {
    await ensureSchema();
    final db = await _db();
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [defaultSettingKey],
    );
  }

  Future<int> renameTag({
    required String oldTag,
    required String newTag,
  }) async {
    final normalizedOld = normalizeTagName(oldTag);
    final normalizedNew = normalizeTagName(newTag);
    if (normalizedOld.isEmpty || normalizedNew.isEmpty) return 0;
    await ensureSchema();
    final db = await _db();
    final count = await db.update(
      tableName,
      {'tag': normalizedNew},
      where: 'tag = ?',
      whereArgs: [normalizedOld],
    );
    final oldCategoryKey = '$categorySettingKeyPrefix$normalizedOld';
    final newCategoryKey = '$categorySettingKeyPrefix$normalizedNew';
    final categoryRows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [oldCategoryKey],
      limit: 1,
    );
    if (categoryRows.isNotEmpty) {
      await db.insert('app_settings', {
        'key': newCategoryKey,
        'value': categoryRows.first['value']?.toString() ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: [oldCategoryKey],
      );
    }
    return count;
  }

  Future<String?> loadTagCategory(String tag) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return null;
    try {
      await ensureSchema();
      final db = await _db();
      final settingsRows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['$categorySettingKeyPrefix$normalized'],
        limit: 1,
      );
      if (settingsRows.isNotEmpty) {
        final stored = settingsRows.first['value']?.toString().trim() ?? '';
        if (stored.isNotEmpty) return stored;
      }
      final rows = await db.query(
        tableName,
        columns: ['category'],
        where: 'tag = ? AND category IS NOT NULL AND TRIM(category) <> \'\'',
        whereArgs: [normalized],
        orderBy: 'created_at DESC, id DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final category = rows.first['category']?.toString().trim() ?? '';
      return category.isEmpty ? null : category;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>> loadCategoryOptions() async {
    try {
      await ensureSchema();
      final db = await _db();
      final values = <String>[];

      final tagRows = await db.rawQuery('''
        SELECT DISTINCT category AS category
        FROM $tableName
        WHERE category IS NOT NULL AND TRIM(category) <> ''
        ORDER BY category COLLATE NOCASE ASC
      ''');
      for (final row in tagRows) {
        final value = row['category']?.toString().trim() ?? '';
        if (value.isNotEmpty) values.add(value);
      }

      final settingRows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key LIKE ? AND value IS NOT NULL AND TRIM(value) <> \'\'',
        whereArgs: ['$categorySettingKeyPrefix%'],
        orderBy: 'value COLLATE NOCASE ASC',
      );
      for (final row in settingRows) {
        final value = row['value']?.toString().trim() ?? '';
        if (value.isNotEmpty) values.add(value);
      }

      final normalized = <String, String>{};
      for (final value in values) {
        normalized.putIfAbsent(value.toLowerCase(), () => value);
      }
      final options = normalized.values.toList(growable: false)
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return options;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> saveTagCategory(String tag, String category) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedCategory = category.trim();
    if (normalizedTag.isEmpty || normalizedCategory.isEmpty) return;
    try {
      await ensureSchema();
      final db = await _db();
      await db.insert('app_settings', {
        'key': '$categorySettingKeyPrefix$normalizedTag',
        'value': normalizedCategory,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.update(
        tableName,
        {'category': normalizedCategory},
        where: 'tag = ?',
        whereArgs: [normalizedTag],
      );
    } catch (_) {
      // If the category migration is unavailable, keep tagging working.
    }
  }

  Future<int> deleteTag(String tag) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return 0;
    await ensureSchema();
    final db = await _db();
    final deleted = await db.delete(
      tableName,
      where: 'tag = ?',
      whereArgs: [normalized],
    );
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['$categorySettingKeyPrefix$normalized'],
    );
    return deleted;
  }

  Future<List<HashTagSummary>> loadSummaries() async {
    await ensureSchema();
    final db = await _db();
    final rows = await db.rawQuery('''
      SELECT tag, COUNT(*) AS cnt
      FROM $tableName
      GROUP BY tag
      ORDER BY tag COLLATE NOCASE ASC
    ''');
    return rows
        .map(
          (row) => HashTagSummary(
            tag: row['tag']?.toString() ?? '',
            count: (row['cnt'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((summary) => summary.tag.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<List<HashTagEntry>> loadEntries(
    String tag, {
    HashTagEntrySortMode sortMode = HashTagEntrySortMode.slideOrder,
  }) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return const <HashTagEntry>[];
    await ensureSchema();
    final db = await _db();
    final orderBy = switch (sortMode) {
      HashTagEntrySortMode.slideOrder =>
        'sort_order ASC, created_at ASC, id ASC',
      HashTagEntrySortMode.verseOrder =>
        'book_number ASC, chapter_number ASC, verse_number ASC, id ASC',
    };
    final columns = <String>[
      'id',
      'book_number',
      'chapter_number',
      'verse_number',
      'verse_ref',
      'created_at',
      'sort_order',
      if (tableName == 'dollar_tags') 'content_html',
    ];
    final rows = await db.query(
      tableName,
      columns: columns,
      where: 'tag = ?',
      whereArgs: [normalized],
      orderBy: orderBy,
    );
    final baseEntries = rows
        .map(
          (row) => (
            id: (row['id'] as num).toInt(),
            bookNumber: (row['book_number'] as num).toInt(),
            chapter: (row['chapter_number'] as num).toInt(),
            verse: (row['verse_number'] as num).toInt(),
            verseRef: row['verse_ref']?.toString() ?? '',
            createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
            sortOrder:
                (row['sort_order'] as num?)?.toInt() ??
                (row['created_at'] as num?)?.toInt() ??
                0,
            contentHtml: row['content_html']?.toString(),
          ),
        )
        .toList(growable: false);
    final verseTexts = await Future.wait(
      baseEntries
          .map(
            (entry) => StudyBibleDatabase.instance.loadVerseText(
              bookNumber: entry.bookNumber,
              chapter: entry.chapter,
              verse: entry.verse,
            ),
          )
          .toList(growable: false),
    );
    return [
      for (var i = 0; i < baseEntries.length; i++)
        HashTagEntry(
          id: baseEntries[i].id,
          bookNumber: baseEntries[i].bookNumber,
          chapter: baseEntries[i].chapter,
          verse: baseEntries[i].verse,
          verseRef: baseEntries[i].verseRef,
          verseText: verseTexts[i] ?? '',
          createdAt: baseEntries[i].createdAt,
          sortOrder: baseEntries[i].sortOrder,
          contentHtml: baseEntries[i].contentHtml,
        ),
    ];
  }

  Future<HashTagQuickApplyResult> quickApplyTargets({
    required List<HashTagTarget> targets,
    String? tag,
  }) async {
    if (targets.isEmpty) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = normalizeTagName(tag ?? await loadDefaultTag() ?? '');
    if (normalizedTag.isEmpty) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }

    var inserted = 0;
    var skipped = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final target in targets) {
      final exists = await db.rawQuery(
        '''
        SELECT 1
        FROM $tableName
        WHERE user_id = ?
          AND tag = ?
          AND ((book_number = ? AND chapter_number = ? AND verse_number = ?) OR verse_ref = ?)
        LIMIT 1
        ''',
        [
          userId,
          normalizedTag,
          target.bookNumber,
          target.chapter,
          target.verse,
          target.verseRef,
        ],
      );
      if (exists.isNotEmpty) {
        skipped++;
        continue;
      }
      await db.insert(tableName, {
        'user_id': userId,
        'tag': normalizedTag,
        'verse_ref': target.verseRef,
        'book_number': target.bookNumber,
        'chapter_number': target.chapter,
        'verse_number': target.verse,
        'token_number': target.tokenNumber,
        if (tableName == 'dollar_tags') 'content_html': '',
        'sort_order': now,
        'created_at': now,
      });
      inserted++;
    }
    return HashTagQuickApplyResult(
      tag: normalizedTag,
      inserted: inserted,
      skipped: skipped,
    );
  }

  Future<void> deleteEntry(int id) async {
    await ensureSchema();
    final db = await _db();
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateEntry({
    required int id,
    required Map<String, Object?> values,
  }) async {
    await ensureSchema();
    final db = await _db();
    await db.update(tableName, values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertNoteSlide({
    required String tag,
    required String contentHtml,
  }) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = normalizeTagName(tag);
    if (normalizedTag.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(tableName, {
      'user_id': userId,
      'tag': normalizedTag,
      'verse_ref': 'note:$now',
      'book_number': 0,
      'chapter_number': 0,
      'verse_number': 0,
      'token_number': null,
      'content_html': contentHtml,
      'source_author': '',
      'source_work_title': '',
      'source_title_acronym': '',
      'source_chapter_title': '',
      'source_chapter_number': '',
      'source_page_number': '',
      'source_paragraph_number': '',
      'source_year': '',
      'study_order': now,
      'created_at': now,
    });
  }

  Future<HashTagImportResult?> importSharedListFromText(String text) async {
    final parsed = tableName == 'dollar_tags'
        ? await _parseDollarSharedListFromText(text)
        : await _parseSharedListFromText(text);
    if (parsed == null || parsed.slides.isEmpty) return null;

    if (tableName == 'dollar_tags') {
      return _importDollarSharedList(parsed);
    }
    return _importHashSharedList(parsed);
  }

  Future<bool> moveEntry({
    required String tag,
    required int entryId,
    required int delta,
  }) async {
    if (delta == 0) return false;
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return false;
    await ensureSchema();
    final db = await _db();
    return db.transaction((txn) async {
      final rows = await txn.query(
        tableName,
        columns: ['id'],
        where: 'tag = ?',
        whereArgs: [normalized],
        orderBy: 'sort_order ASC, created_at ASC, id ASC',
      );
      final ids = rows
          .map((row) => (row['id'] as num).toInt())
          .toList(growable: false);
      final index = ids.indexOf(entryId);
      if (index < 0) return false;
      final targetIndex = index + delta;
      if (targetIndex < 0 || targetIndex >= ids.length) return false;
      final moved = [...ids];
      final temp = moved[index];
      moved[index] = moved[targetIndex];
      moved[targetIndex] = temp;
      for (var i = 0; i < moved.length; i++) {
        await txn.update(
          tableName,
          {'sort_order': i + 1},
          where: 'id = ?',
          whereArgs: [moved[i]],
        );
      }
      return true;
    });
  }

  List<HashTagTarget> buildSelectionTargets({
    required PassageData passage,
    required ViewerRangeSelection selection,
    required int currentBookNumber,
    required int currentChapter,
    required int currentVerse,
  }) {
    final lines = passage.lines;
    if (lines.isEmpty) {
      return [
        HashTagTarget(
          bookNumber: currentBookNumber,
          chapter: currentChapter,
          verse: currentVerse,
          verseRef: '$currentBookNumber:$currentChapter:$currentVerse',
        ),
      ];
    }

    if (selection.hasCompletedRange) {
      final startId = selection.startBlockId ?? 0;
      final endId = selection.endBlockId ?? startId;
      if (startId > 0 && endId > 0) {
        final low = startId < endId ? startId : endId;
        final high = startId < endId ? endId : startId;
        final selected = lines
            .where((line) {
              final blockId = line.blockId ?? 0;
              return blockId >= low && blockId <= high;
            })
            .map(
              (line) => HashTagTarget(
                bookNumber: line.bookNumber,
                chapter: line.chapter,
                verse: line.verse,
                verseRef: '${line.bookNumber}:${line.chapter}:${line.verse}',
              ),
            )
            .toList(growable: false);
        if (selected.isNotEmpty) {
          return _dedupeTargets(selected);
        }
      }
    }

    final verseLine = lines.firstWhere(
      (line) =>
          line.bookNumber == currentBookNumber &&
          line.chapter == currentChapter &&
          line.verse == currentVerse,
      orElse: () => lines.first,
    );
    return [
      HashTagTarget(
        bookNumber: verseLine.bookNumber,
        chapter: verseLine.chapter,
        verse: verseLine.verse,
        verseRef:
            '${verseLine.bookNumber}:${verseLine.chapter}:${verseLine.verse}',
      ),
    ];
  }

  List<HashTagTarget> _dedupeTargets(List<HashTagTarget> targets) {
    final seen = <String>{};
    final unique = <HashTagTarget>[];
    for (final target in targets) {
      if (seen.add(target.verseRef)) {
        unique.add(target);
      }
    }
    return unique;
  }

  Future<_ParsedSharedList?> _parseSharedListFromText(String text) async {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = {
      for (final book in books)
        _normalizeBookKey(book.bookName): (book.bookNumber, book.bookName),
    };

    final tagName = _detectSharedListName(lines) ?? _fallbackImportedTagName();
    final blocks = _splitSharedListBlocks(lines, tagName);
    final slides = <_ParsedSharedSlide>[];
    final seen = <String>{};

    for (final block in blocks) {
      final slide = _parseSharedSlideBlock(block, bookLookup, tagName);
      if (slide == null) continue;
      final dedupeKey = slide.target?.verseRef ?? slide.noteRef;
      if (!seen.add(dedupeKey)) continue;
      slides.add(slide);
    }

    if (slides.isEmpty) return null;
    return _ParsedSharedList(tag: normalizeTagName(tagName), slides: slides);
  }

  Future<_ParsedSharedList?> _parseDollarSharedListFromText(String text) async {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = {
      for (final book in books)
        _normalizeBookKey(book.bookName): (book.bookNumber, book.bookName),
    };

    final tagName = _detectSharedListName(lines) ?? _fallbackImportedTagName();
    final slides = <_ParsedSharedSlide>[];
    final currentNote = <String>[];
    final currentVerse = <String>[];
    HashTagTarget? currentTarget;
    var inNote = false;
    var inVerse = false;

    void flush() {
      if (currentTarget != null) {
        slides.add(
          _ParsedSharedSlide(
            target: currentTarget,
            contentText: currentVerse.join('\n').trim(),
            noteRef: currentTarget!.verseRef,
          ),
        );
      } else if (currentNote.isNotEmpty) {
        slides.add(
          _ParsedSharedSlide(
            target: null,
            contentText: currentNote.join('\n').trim(),
            noteRef:
                'note:${DateTime.now().microsecondsSinceEpoch}:${slides.length}',
          ),
        );
      }
      currentNote.clear();
      currentVerse.clear();
      currentTarget = null;
      inNote = false;
      inVerse = false;
    }

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final normalized = line.trim();
      if (_isSharedListWrapperLine(normalized) ||
          _isSharedListHeaderLine(normalized, tagName) ||
          normalized.isEmpty) {
        if (normalized.isEmpty && (inNote || inVerse)) {
          if (inNote && currentNote.isNotEmpty) currentNote.add('');
          if (inVerse && currentVerse.isNotEmpty) currentVerse.add('');
        }
        continue;
      }

      if (normalized.toLowerCase().startsWith('note slide')) {
        flush();
        inNote = true;
        continue;
      }

      final reference = _parseSharedReferenceLine(normalized, bookLookup);
      if (reference != null) {
        if (inNote && currentNote.isNotEmpty) {
          flush();
        } else if (inVerse && currentVerse.isNotEmpty) {
          flush();
        }
        currentTarget = reference;
        inVerse = true;
        continue;
      }

      if (normalized.toLowerCase() == 'notes:') {
        inNote = true;
        continue;
      }

      if (inVerse) {
        currentVerse.add(line);
      } else {
        inNote = true;
        currentNote.add(line);
      }
    }

    flush();
    if (slides.isEmpty) return null;
    return _ParsedSharedList(tag: normalizeTagName(tagName), slides: slides);
  }

  String? _detectSharedListName(List<String> lines) {
    final headerRegex = RegExp(
      r'^\s*([#\$@][^\s(]+)\s*(?:\(\s*\d+\s+(?:verse|slide)(?:s)?\s*\))?\s*$',
      caseSensitive: false,
    );
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = headerRegex.firstMatch(line);
      if (match == null) continue;
      final candidate = match.group(1)?.trim() ?? '';
      if (candidate.isNotEmpty) return candidate;
    }
    return null;
  }

  List<List<String>> _splitSharedListBlocks(
    List<String> lines,
    String tagName,
  ) {
    final blocks = <List<String>>[];
    var current = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.replaceAll('\r', '');
      final normalized = line.trim();
      if (_isSharedListWrapperLine(normalized) ||
          _isSharedListHeaderLine(normalized, tagName)) {
        continue;
      }
      if (current.isNotEmpty && _isSharedSlideStartLine(normalized)) {
        blocks.add(current);
        current = <String>[];
      }
      if (normalized.isEmpty) {
        if (current.isNotEmpty) {
          blocks.add(current);
          current = <String>[];
        }
        continue;
      }
      current.add(line);
    }
    if (current.isNotEmpty) {
      blocks.add(current);
    }
    return blocks;
  }

  _ParsedSharedSlide? _parseSharedSlideBlock(
    List<String> block,
    Map<String, (int, String)> bookLookup,
    String tagName,
  ) {
    if (block.isEmpty) return null;
    final firstLine = block.first.trim();
    if (firstLine.isEmpty) return null;
    if (_detectSharedListName([firstLine]) == firstLine) {
      return null;
    }

    final reference = _parseSharedReferenceLine(firstLine, bookLookup);
    if (reference != null) {
      final content = _extractSharedVerseContent(block.skip(1).toList());
      return _ParsedSharedSlide(
        target: reference,
        contentText: content,
        noteRef: reference.verseRef,
      );
    }

    if (_looksLikeSharedNoteBlock(block)) {
      final content = _extractSharedNoteContent(block, tagName);
      return _ParsedSharedSlide(
        target: null,
        contentText: content,
        noteRef:
            'note:${DateTime.now().microsecondsSinceEpoch}:${block.join('|')}',
      );
    }

    return null;
  }

  bool _looksLikeSharedNoteBlock(List<String> block) {
    final first = block.first.trim().toLowerCase();
    return first.startsWith('note slide') ||
        first == 'notes:' ||
        block.any((line) => line.trim().toLowerCase() == 'notes:');
  }

  bool _isSharedListHeaderLine(String line, String tagName) {
    final normalized = line
        .trim()
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    final normalizedTag = tagName
        .trim()
        .replaceAll('*', '')
        .replaceAll('_', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
    return normalized.isNotEmpty &&
        normalizedTag.isNotEmpty &&
        normalized.startsWith(normalizedTag) &&
        (normalized.contains('slide') || normalized.contains('verse'));
  }

  bool _isSharedSlideStartLine(String line) {
    final normalized = line.trim();
    if (normalized.isEmpty) return false;
    if (normalized.toLowerCase().startsWith('note slide')) return true;
    return RegExp(r'^(.*?)\s+\d+\s*:\s*\d+\s*$').hasMatch(normalized);
  }

  String _extractSharedVerseContent(List<String> lines) {
    final contentLines = <String>[];
    var skipNotesMarker = true;
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final normalized = line.trim();
      if (normalized.isEmpty) {
        contentLines.add('');
        continue;
      }
      if (normalized.toLowerCase().startsWith('note slide')) {
        continue;
      }
      if (skipNotesMarker && normalized.toLowerCase() == 'notes:') {
        skipNotesMarker = false;
        continue;
      }
      skipNotesMarker = false;
      contentLines.add(line);
    }
    return contentLines.join('\n').trim();
  }

  String _extractSharedNoteContent(List<String> lines, String tagName) {
    final contentLines = <String>[];
    var skipNotesMarker = true;
    for (final rawLine in lines) {
      final normalized = rawLine.trim();
      if (normalized.isEmpty) {
        contentLines.add('');
        continue;
      }
      if (_isSharedListHeaderLine(normalized, tagName)) {
        continue;
      }
      if (normalized.toLowerCase().startsWith('note slide')) {
        continue;
      }
      if (skipNotesMarker && normalized.toLowerCase() == 'notes:') {
        skipNotesMarker = false;
        continue;
      }
      skipNotesMarker = false;
      contentLines.add(rawLine);
    }
    return contentLines.join('\n').trim();
  }

  HashTagTarget? _parseSharedReferenceLine(
    String line,
    Map<String, (int, String)> bookLookup,
  ) {
    final referenceRegex = RegExp(r'^(.*?)\s+(\d+)\s*:\s*(\d+)\s*$');
    final match = referenceRegex.firstMatch(line);
    if (match == null) return null;

    final rawBook = match.group(1)?.trim() ?? '';
    final chapter = int.tryParse(match.group(2) ?? '');
    final verse = int.tryParse(match.group(3) ?? '');
    if (rawBook.isEmpty || chapter == null || verse == null) return null;

    final lookup = bookLookup[_normalizeBookKey(rawBook)];
    if (lookup == null) return null;

    return HashTagTarget(
      bookNumber: lookup.$1,
      chapter: chapter,
      verse: verse,
      verseRef: '${lookup.$1}:$chapter:$verse',
    );
  }

  bool _isSharedListWrapperLine(String line) {
    final normalized = line
        .trim()
        .replaceAll('*', '')
        .replaceAll('_', '')
        .toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized.contains('formatted sharing list') ||
        normalized.contains('biblical heritage #studybible app') ||
        normalized.contains(r'biblical heritage $studybible app') ||
        normalized.contains('learn more at biblicalheritage.net') ||
        normalized.contains('tutorials, downloads, shared lists') ||
        normalized.contains('verse text here');
  }

  Future<HashTagImportResult?> _importDollarSharedList(
    _ParsedSharedList parsed,
  ) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = parsed.tag;
    if (normalizedTag.isEmpty) return null;

    final failures = <HashTagImportFailure>[];
    var parsedCount = 0;
    var inserted = 0;
    var updatedExisting = 0;
    var skippedExisting = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    var order = 1;

    for (final slide in parsed.slides) {
      parsedCount++;
      final target = slide.target;
      final contentText = slide.contentText.trim();
      final verseRef = target?.verseRef ?? slide.noteRef;
      if (verseRef.isEmpty) {
        failures.add(
          HashTagImportFailure(
            lineNumber: parsedCount,
            reason: 'Missing slide reference',
            line: slide.contentText,
          ),
        );
        continue;
      }
      if (target == null && contentText.isEmpty) {
        failures.add(
          HashTagImportFailure(
            lineNumber: parsedCount,
            reason: 'Missing note content',
            line: slide.noteRef,
          ),
        );
        continue;
      }
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, verseRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'verse_ref': verseRef,
        'book_number': target?.bookNumber ?? 0,
        'chapter_number': target?.chapter ?? 0,
        'verse_number': target?.verse ?? 0,
        'token_number': target?.tokenNumber,
        'content_html': _plainTextToHtml(contentText),
        'source_author': '',
        'source_work_title': '',
        'source_title_acronym': '',
        'source_chapter_title': '',
        'source_chapter_number': '',
        'source_page_number': '',
        'source_paragraph_number': '',
        'source_year': '',
        'study_order': order,
        'created_at': now + inserted,
      };

      if (exists.isNotEmpty) {
        final existingId = (exists.first['id'] as num?)?.toInt();
        if (existingId != null) {
          await db.update(
            tableName,
            values,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          updatedExisting++;
          order += 1;
          continue;
        }
        skippedExisting++;
        continue;
      }

      await db.insert(tableName, values);
      order += 1;
      inserted++;
    }

    await saveTagCategory(normalizedTag, recentImportCategory);
    return HashTagImportResult(
      tag: normalizedTag,
      parsedCount: parsedCount,
      insertedCount: inserted,
      updatedExistingCount: updatedExisting,
      skippedExistingCount: skippedExisting,
      failedCount: failures.length,
      failures: failures,
    );
  }

  Future<HashTagImportResult?> _importHashSharedList(
    _ParsedSharedList parsed,
  ) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = parsed.tag;
    if (normalizedTag.isEmpty) return null;

    final scriptureSlides = parsed.slides
        .where((slide) => slide.target != null)
        .toList(growable: false);
    if (scriptureSlides.isEmpty) return null;

    final failures = <HashTagImportFailure>[];
    var inserted = 0;
    var updatedExisting = 0;
    var skippedExisting = 0;
    var studyOrder = 1;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final slide in scriptureSlides) {
      final target = slide.target!;
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, target.verseRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'verse_ref': target.verseRef,
        'book_number': target.bookNumber,
        'chapter_number': target.chapter,
        'verse_number': target.verse,
        'token_number': target.tokenNumber,
        'sort_order': studyOrder,
        'created_at': now + inserted,
      };
      if (exists.isNotEmpty) {
        final existingId = (exists.first['id'] as num?)?.toInt();
        if (existingId != null) {
          await db.update(
            tableName,
            values,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          updatedExisting++;
          studyOrder++;
          continue;
        }
        skippedExisting++;
        continue;
      }
      await db.insert(tableName, values);
      inserted++;
      studyOrder++;
    }

    await saveTagCategory(normalizedTag, recentImportCategory);
    return HashTagImportResult(
      tag: normalizedTag,
      parsedCount: scriptureSlides.length,
      insertedCount: inserted,
      updatedExistingCount: updatedExisting,
      skippedExistingCount: skippedExisting,
      failedCount: failures.length,
      failures: failures,
    );
  }

  String _fallbackImportedTagName() {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    return 'Imported $stamp';
  }

  String _plainTextToHtml(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return '<p></p>';
    final escaped = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    return '<p>${escaped.replaceAll('\n', '<br>')}</p>';
  }

  String _normalizeBookKey(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String buildSelectionLabel({
    required PassageData passage,
    required List<HashTagTarget> targets,
  }) {
    if (targets.isEmpty) return 'No selection';
    if (targets.length == 1) {
      final target = targets.first;
      return '${passage.bookName} ${target.chapter}:${target.verse}';
    }
    final first = targets.first;
    final last = targets.last;
    if (first.chapter == last.chapter) {
      return '${passage.bookName} ${first.chapter}:${first.verse}-${last.verse}';
    }
    return '${passage.bookName} ${first.chapter}:${first.verse} - ${passage.bookName} ${last.chapter}:${last.verse}';
  }

  Future<Map<int, String>> loadBookNames() async {
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'books',
      columns: ['book_number', 'book_name'],
      orderBy: 'book_number ASC',
    );
    return {
      for (final row in rows)
        (row['book_number'] as num).toInt(): row['book_name']?.toString() ?? '',
    };
  }
}

class DollarTagRepository extends HashTagRepository {
  DollarTagRepository()
    : super(
        tableName: 'dollar_tags',
        defaultSettingKey: 'tags.default.dollar',
        categorySettingKeyPrefix: 'tags.category.dollar.',
        tagPrefix: r'$',
      );
}

class _ParsedSharedList {
  const _ParsedSharedList({required this.tag, required this.slides});

  final String tag;
  final List<_ParsedSharedSlide> slides;
}

class _ParsedSharedSlide {
  const _ParsedSharedSlide({
    required this.target,
    required this.contentText,
    required this.noteRef,
  });

  final HashTagTarget? target;
  final String contentText;
  final String noteRef;
}
