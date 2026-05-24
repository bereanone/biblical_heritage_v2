import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_citation_display_helper.dart';
import '../../library/data/library_catalog_service.dart'
    show extractLibrarySearchHighlightTerms;
import '../data/presentation/presentation_models.dart';
import '../data/presentation/presentation_text_format.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';

part 'tag_quick_apply_helper_models.dart';

String bibleRangeReferenceLabel({
  required String bookName,
  required int chapter,
  required int verseStart,
  required int verseEnd,
}) {
  final normalizedEnd = verseEnd < verseStart ? verseStart : verseEnd;
  final cleanBookName = bookName.trim();
  if (cleanBookName.isEmpty || chapter <= 0 || verseStart <= 0) {
    return '';
  }
  final verseLabel = normalizedEnd > verseStart
      ? '$verseStart-$normalizedEnd'
      : '$verseStart';
  return '$cleanBookName $chapter:$verseLabel';
}

String bibleRangeSourceId({
  required int bookNumber,
  required int chapter,
  required int verseStart,
  required int verseEnd,
}) {
  final normalizedEnd = verseEnd < verseStart ? verseStart : verseEnd;
  if (bookNumber <= 0 || chapter <= 0 || verseStart <= 0) {
    return '';
  }
  return normalizedEnd > verseStart
      ? '$bookNumber:$chapter:$verseStart-$normalizedEnd'
      : '$bookNumber:$chapter:$verseStart';
}

Future<String> loadBibleRangeText({
  required int bookNumber,
  required int chapter,
  required int verseStart,
  required int verseEnd,
}) async {
  if (bookNumber <= 0 || chapter <= 0 || verseStart <= 0) return '';
  final normalizedEnd = verseEnd < verseStart ? verseStart : verseEnd;
  if (normalizedEnd <= verseStart) {
    return (await StudyBibleDatabase.instance.loadVerseText(
          bookNumber: bookNumber,
          chapter: chapter,
          verse: verseStart,
        ))?.trim() ??
        '';
  }

  final db = await StudyBibleDatabase.instance.bible;
  final rows = await db.query(
    'bible_blocks',
    columns: ['plain_text'],
    where: '''
      book_number = ?
      AND chapter = ?
      AND block_index BETWEEN ? AND ?
    ''',
    whereArgs: [bookNumber, chapter, verseStart, normalizedEnd],
    orderBy: 'block_index ASC',
  );
  if (rows.isEmpty) {
    return (await StudyBibleDatabase.instance.loadVerseText(
          bookNumber: bookNumber,
          chapter: chapter,
          verse: verseStart,
        ))?.trim() ??
        '';
  }
  final verses = rows
      .map((row) => row['plain_text']?.toString().trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  return verses.join('\n').trim();
}

class BibleItemOverlay {
  const BibleItemOverlay({
    this.userTitle,
    this.displayTextOverride,
    this.noteFormatJson,
    this.titleFormatJson,
    this.displayTextFormatJson,
  });

  final String? userTitle;
  final String? displayTextOverride;
  final String? noteFormatJson;
  final String? titleFormatJson;
  final String? displayTextFormatJson;

  bool get isEmpty =>
      (userTitle ?? '').trim().isEmpty &&
      (displayTextOverride ?? '').trim().isEmpty &&
      (noteFormatJson ?? '').trim().isEmpty &&
      (titleFormatJson ?? '').trim().isEmpty &&
      (displayTextFormatJson ?? '').trim().isEmpty;
}

BibleItemOverlay? parseBibleItemOverlay(Object? raw) {
  final text = (raw?.toString() ?? '').trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) return null;
    final kind = decoded['kind']?.toString();
    if (kind != 'bible_item_overlay' && kind != 'bible_item_meta') {
      return null;
    }
    return BibleItemOverlay(
      userTitle: decoded['user_title']?.toString().trim(),
      displayTextOverride: decoded['display_text_override']?.toString().trim(),
      noteFormatJson: decoded['note_format_json']?.toString().trim(),
      titleFormatJson: decoded['title_format_json']?.toString().trim(),
      displayTextFormatJson:
          decoded['display_text_format_json']?.toString().trim(),
    );
  } catch (_) {
    return null;
  }
}

String? bibleItemOverlayUserTitle(Object? raw) {
  final overlay = parseBibleItemOverlay(raw);
  final title = overlay?.userTitle?.trim() ?? '';
  return title.isEmpty ? null : title;
}

String? bibleItemOverlayDisplayTextOverride(Object? raw) {
  final overlay = parseBibleItemOverlay(raw);
  final text = overlay?.displayTextOverride?.trim() ?? '';
  return text.isEmpty ? null : text;
}

String? bibleItemOverlayNoteFormatJson(Object? raw) {
  final overlay = parseBibleItemOverlay(raw);
  if (overlay != null) {
    final nested = overlay.noteFormatJson?.trim() ?? '';
    if (nested.isNotEmpty) return nested;
    return null;
  }
  final rawText = (raw?.toString() ?? '').trim();
  return rawText.isEmpty ? null : rawText;
}

String? bibleItemOverlayTitleFormatJson(Object? raw) {
  final overlay = parseBibleItemOverlay(raw);
  final nested = overlay?.titleFormatJson?.trim() ?? '';
  return nested.isEmpty ? null : nested;
}

String? bibleItemOverlayDisplayTextFormatJson(Object? raw) {
  final overlay = parseBibleItemOverlay(raw);
  final nested = overlay?.displayTextFormatJson?.trim() ?? '';
  return nested.isEmpty ? null : nested;
}

String? buildBibleItemOverlayJson({
  String? userTitle,
  String? displayTextOverride,
  String? noteFormatJson,
  String? titleFormatJson,
  String? displayTextFormatJson,
}) {
  final title = userTitle?.trim() ?? '';
  final displayText = displayTextOverride?.trim() ?? '';
  final noteFormat = noteFormatJson?.trim() ?? '';
  final titleFormat = titleFormatJson?.trim() ?? '';
  final displayTextFormat = displayTextFormatJson?.trim() ?? '';
  final payload = <String, Object?>{
    'format_version': 1,
    'kind': 'bible_item_overlay',
    if (title.isNotEmpty) 'user_title': title,
    if (displayText.isNotEmpty) 'display_text_override': displayText,
    if (noteFormat.isNotEmpty) 'note_format_json': noteFormat,
    if (titleFormat.isNotEmpty) 'title_format_json': titleFormat,
    if (displayTextFormat.isNotEmpty)
      'display_text_format_json': displayTextFormat,
  };
  if (payload.length <= 2) return null;
  return jsonEncode(payload);
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

  Future<Database> _db() async {
    return UserDatabase.instance.database;
  }

  Future<void> ensureSchema() async {
    final db = await _db();
    final referenceCodeColumn =
        tableName == 'hash_tags' || tableName == 'dollar_tags'
        ? '        reference_code TEXT,\n'
        : '';
    final noteColumn = tableName == 'hash_tags'
        ? '        note_text TEXT,\n'
        : '';
    final noteFormatColumn = tableName == 'hash_tags'
        ? '        note_format_json TEXT,\n'
        : '';
    final presentationSlideColumn = tableName == 'hash_tags'
        ? '        presentation_slide_number INTEGER,\n'
        : '';
    final presentationSlideRegionColumn = tableName == 'hash_tags'
        ? '        presentation_slide_region TEXT,\n'
        : '';
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
$referenceCodeColumn$noteColumn$noteFormatColumn        sort_order INTEGER,
$presentationSlideColumn$presentationSlideRegionColumn        created_at INTEGER NOT NULL
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
    if (tableName == 'hash_tags' || tableName == 'dollar_tags') {
      await _addColumnIfMissing(
        db,
        tableName: tableName,
        columnName: 'reference_code',
        columnDefinition: 'TEXT',
      );
    }
    if (tableName == 'hash_tags') {
      await _addColumnIfMissing(
        db,
        tableName: tableName,
        columnName: 'note_text',
        columnDefinition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: tableName,
        columnName: 'note_format_json',
        columnDefinition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: tableName,
        columnName: 'presentation_slide_number',
        columnDefinition: 'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableName: tableName,
        columnName: 'presentation_slide_region',
        columnDefinition: 'TEXT',
      );
    }
    if (await _tableExists(db, 'tag_items')) {
      await _addColumnIfMissing(
        db,
        tableName: 'tag_items',
        columnName: 'reference_code',
        columnDefinition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'tag_items',
        columnName: 'presentation_slide_number',
        columnDefinition: 'INTEGER',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'tag_items',
        columnName: 'presentation_slide_region',
        columnDefinition: 'TEXT',
      );
      await _addColumnIfMissing(
        db,
        tableName: 'tag_items',
        columnName: 'note_format_json',
        columnDefinition: 'TEXT',
      );
    }
    if (await _tableExists(db, 'dollar_tags')) {
      await _addColumnIfMissing(
        db,
        tableName: 'dollar_tags',
        columnName: 'note_format_json',
        columnDefinition: 'TEXT',
      );
    }
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

  Future<bool> _tableExists(Database db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [tableName],
    );
    return rows.isNotEmpty;
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

  Future<String?> loadActiveDefaultTag() async {
    final defaultTag = normalizeTagName(await loadDefaultTag() ?? '');
    if (defaultTag.isEmpty) return null;
    if (await _tagExists(defaultTag)) {
      return defaultTag;
    }

    await clearDefaultTag();
    return null;
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
    final tagKind = _tagKindForTable();
    final legacyRows = await db.rawQuery('''
      SELECT tag, COUNT(*) AS cnt
      FROM $tableName
      GROUP BY tag
    ''');
    final normalizedRows = await db.rawQuery(
      '''
      SELECT groups.name AS tag, COUNT(items.id) AS cnt
      FROM tag_groups AS groups
      LEFT JOIN tag_items AS items
        ON items.tag_group_id = groups.id
       AND COALESCE(items.deleted_at, '') = ''
      WHERE groups.tag_kind = ?
        AND COALESCE(groups.deleted_at, '') = ''
      GROUP BY groups.id, groups.name
    ''',
      [tagKind],
    );

    final merged = <String, HashTagSummary>{};
    void addRow(Map<String, Object?> row) {
      final tag = row['tag']?.toString().trim() ?? '';
      if (tag.isEmpty) return;
      final count = (row['cnt'] as num?)?.toInt() ?? 0;
      final key = tag.toLowerCase();
      final existing = merged[key];
      merged[key] = HashTagSummary(
        tag: existing?.tag ?? tag,
        count: (existing?.count ?? 0) + count,
      );
    }

    for (final row in legacyRows) {
      addRow(row);
    }
    for (final row in normalizedRows) {
      addRow(row);
    }
    final rows = merged.values.toList(growable: false)
      ..sort(
        (left, right) =>
            left.tag.toLowerCase().compareTo(right.tag.toLowerCase()),
      );
    return rows;
  }

  Future<List<HashTagEntry>> loadEntries(
    String tag, {
    HashTagEntrySortMode sortMode = HashTagEntrySortMode.slideOrder,
  }) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return const <HashTagEntry>[];
    await ensureSchema();
    final db = await _db();
    final tagKind = _tagKindForTable();

    Future<List<HashTagEntry>> loadLegacyEntries() async {
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
        if (tableName == 'hash_tags' || tableName == 'dollar_tags')
          'reference_code',
        if (tableName == 'hash_tags') 'presentation_slide_number',
        if (tableName == 'hash_tags') 'presentation_slide_region',
        if (tableName == 'dollar_tags') 'content_html',
        if (tableName == 'dollar_tags') 'note_format_json',
        if (tableName == 'hash_tags') 'note_text',
        if (tableName == 'hash_tags') 'note_format_json',
      ];
      final rows = await db.query(
        tableName,
        columns: columns,
        where: 'tag = ?',
        whereArgs: [normalized],
        orderBy: orderBy,
      );
      final entries = rows
          .map(
            (row) => (
              id: (row['id'] as num).toInt(),
              bookNumber: (row['book_number'] as num).toInt(),
              chapter: (row['chapter_number'] as num).toInt(),
              verse: (row['verse_number'] as num).toInt(),
              verseEnd: (row['verse_number'] as num).toInt(),
              verseRef: row['verse_ref']?.toString() ?? '',
              createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
              sortOrder:
                  (row['sort_order'] as num?)?.toInt() ??
                  (row['created_at'] as num?)?.toInt() ??
                  0,
              presentationSlideNumber: _intValueNullable(
                row['presentation_slide_number'],
              ),
              presentationSlideRegion: presentationItemPlacementFromJson(
                row['presentation_slide_region']?.toString(),
              ),
              referenceCode: row['reference_code']?.toString(),
              contentHtml: row['content_html']?.toString(),
              noteText: row['note_text']?.toString(),
              noteFormatJson: row['note_format_json']?.toString(),
            ),
          )
          .toList(growable: false);
      final mediaByItemId = await _loadMediaRefsForEntries(
        db,
        entries.map((entry) => entry.id).toList(growable: false),
      );
      final verseTexts = await Future.wait(
        entries
            .map(
              (entry) => _loadVerseRangeText(
                bookNumber: entry.bookNumber,
                chapter: entry.chapter,
                verseStart: entry.verse,
                verseEnd: entry.verseEnd,
              ),
            )
            .toList(growable: false),
      );
      return [
        for (var i = 0; i < entries.length; i++)
          HashTagEntry(
            id: entries[i].id,
            bookNumber: entries[i].bookNumber,
            chapter: entries[i].chapter,
            verse: entries[i].verse,
            verseEnd: entries[i].verseEnd,
            verseRef: entries[i].verseRef,
            verseText: verseTexts[i],
            createdAt: entries[i].createdAt,
            sortOrder: entries[i].sortOrder,
            isNormalized: false,
            presentationSlideNumber: entries[i].presentationSlideNumber,
            referenceCode: entries[i].referenceCode,
            contentHtml: entries[i].contentHtml,
            noteText: entries[i].noteText,
            noteFormatJson: entries[i].noteFormatJson,
            mediaRefs: List.unmodifiable(
              mediaByItemId[entries[i].id] ?? const <String>[],
            ),
          ),
      ];
    }

    Future<List<HashTagEntry>> loadNormalizedEntries() async {
      final groupRows = await db.query(
        'tag_groups',
        columns: ['id'],
        where: '''
          tag_kind = ?
          AND name = ?
          AND COALESCE(deleted_at, '') = ''
        ''',
        whereArgs: [tagKind, normalized],
        limit: 1,
      );
      if (groupRows.isEmpty) return const <HashTagEntry>[];
      final groupId = groupRows.first['id']?.toString() ?? '';
      if (groupId.isEmpty) return const <HashTagEntry>[];

      final orderBy = switch (sortMode) {
        HashTagEntrySortMode.slideOrder =>
          'sort_order ASC, created_at ASC, id ASC',
        HashTagEntrySortMode.verseOrder =>
          'book_id ASC, chapter ASC, verse_start ASC, id ASC',
      };
      final rows = await db.query(
        'tag_items',
        columns: [
          'rowid AS numeric_id',
          'id',
          'book_id',
          'chapter',
          'verse_start',
          'verse_end',
          'presentation_slide_number',
          'reference_code',
          'presentation_slide_region',
          'note_format_json',
          'created_at',
          'sort_order',
          'note_text',
          'legacy_item_id',
        ],
        where: 'tag_group_id = ? AND COALESCE(deleted_at, \'\') = \'\'',
        whereArgs: [groupId],
        orderBy: orderBy,
      );
      final mediaByItemId = await _loadNormalizedMediaRefsForEntries(
        db,
        [
          for (final row in rows) row['id']?.toString() ?? '',
        ].where((value) => value.isNotEmpty).toList(growable: false),
      );
      final books = await StudyBibleDatabase.instance.loadBooks();
      final bookNames = {
        for (final book in books) book.bookNumber: book.bookName,
      };
      final verseTexts = await Future.wait(
        rows
            .map(
              (row) => _loadVerseRangeText(
                bookNumber: _i(row['book_id']) ?? 0,
                chapter: _i(row['chapter']) ?? 0,
                verseStart: _i(row['verse_start']) ?? 0,
                verseEnd: _i(row['verse_end']) ?? _i(row['verse_start']) ?? 0,
              ),
            )
            .toList(growable: false),
      );
      return [
        for (var i = 0; i < rows.length; i++)
          HashTagEntry(
            id: _i(rows[i]['numeric_id']) ?? i + 1,
            bookNumber: _i(rows[i]['book_id']) ?? 0,
            chapter: _i(rows[i]['chapter']) ?? 0,
            verse: _i(rows[i]['verse_start']) ?? 0,
            verseEnd:
                _i(rows[i]['verse_end']) ?? _i(rows[i]['verse_start']) ?? 0,
            verseRef: _normalizedVerseRef(rows[i], bookNames),
            verseText: verseTexts[i],
            createdAt: _i(rows[i]['created_at']) ?? 0,
            sortOrder:
                _i(rows[i]['sort_order']) ?? _i(rows[i]['created_at']) ?? 0,
            isNormalized: true,
            presentationSlideNumber: _i(rows[i]['presentation_slide_number']),
            presentationSlideRegion: presentationItemPlacementFromJson(
              rows[i]['presentation_slide_region']?.toString(),
            ),
            userTitle: bibleItemOverlayUserTitle(rows[i]['note_format_json']),
            referenceCode: _s(rows[i]['reference_code']).trim().isEmpty
                ? null
                : _s(rows[i]['reference_code']),
            displayTextOverride: bibleItemOverlayDisplayTextOverride(
              rows[i]['note_format_json'],
            ),
            titleFormatJson: bibleItemOverlayTitleFormatJson(
              rows[i]['note_format_json'],
            ),
            displayTextFormatJson: bibleItemOverlayDisplayTextFormatJson(
              rows[i]['note_format_json'],
            ),
            contentHtml: null,
            noteText: _s(rows[i]['note_text']).trim().isEmpty
                ? null
                : _s(rows[i]['note_text']),
            noteFormatJson: bibleItemOverlayNoteFormatJson(
              rows[i]['note_format_json'],
            ),
            mediaRefs: List.unmodifiable(
              mediaByItemId[_s(rows[i]['id'])] ?? const <String>[],
            ),
          ),
      ];
    }

    final combined =
        [...await loadLegacyEntries(), ...await loadNormalizedEntries()]..sort((
          left,
          right,
        ) {
          switch (sortMode) {
            case HashTagEntrySortMode.slideOrder:
              final sortCompare = left.sortOrder.compareTo(right.sortOrder);
              if (sortCompare != 0) return sortCompare;
              final createdCompare = left.createdAt.compareTo(right.createdAt);
              if (createdCompare != 0) return createdCompare;
              return left.id.compareTo(right.id);
            case HashTagEntrySortMode.verseOrder:
              final bookCompare = left.bookNumber.compareTo(right.bookNumber);
              if (bookCompare != 0) return bookCompare;
              final chapterCompare = left.chapter.compareTo(right.chapter);
              if (chapterCompare != 0) return chapterCompare;
              final verseCompare = left.verse.compareTo(right.verse);
              if (verseCompare != 0) return verseCompare;
              return left.id.compareTo(right.id);
          }
        });

    return combined;
  }

  Future<Map<String, List<String>>> _loadNormalizedMediaRefsForEntries(
    Database db,
    List<String> itemIds,
  ) async {
    if (itemIds.isEmpty) return const <String, List<String>>{};
    final placeholders = List.filled(itemIds.length, '?').join(', ');
    final rows = await db.rawQuery('''
      SELECT tag_item_id, relative_path
      FROM tag_item_media
      WHERE tag_item_id IN ($placeholders)
        AND COALESCE(deleted_at, '') = ''
      ORDER BY tag_item_id ASC, sort_order ASC, id ASC
      ''', itemIds);
    final grouped = <String, List<String>>{};
    for (final row in rows) {
      final itemId = row['tag_item_id']?.toString() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (itemId.isEmpty || relativePath.isEmpty) continue;
      grouped.putIfAbsent(itemId, () => <String>[]).add(relativePath);
    }
    return grouped;
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

  Future<HashTagResolvedTag?> getOrCreateDefaultSearchResultsTag({
    String fallbackTag = 'SearchResults',
    String category = 'Search',
  }) async {
    await ensureSchema();
    final existingDefault = normalizeTagName(await loadDefaultTag() ?? '');
    if (existingDefault.isNotEmpty) {
      return HashTagResolvedTag(tag: existingDefault, createdDefaultTag: false);
    }

    final normalizedFallback = normalizeTagName(fallbackTag);
    if (normalizedFallback.isEmpty) return null;

    final db = await _db();
    final existingRows = await db.query(
      tableName,
      columns: ['id'],
      where: 'tag = ?',
      whereArgs: [normalizedFallback],
      limit: 1,
    );
    final createdDefaultTag = existingRows.isEmpty;
    await saveDefaultTag(normalizedFallback);
    if (category.trim().isNotEmpty) {
      await saveTagCategory(normalizedFallback, category);
    }
    return HashTagResolvedTag(
      tag: normalizedFallback,
      createdDefaultTag: createdDefaultTag,
    );
  }

  Future<HashTagSearchQuickApplyResult> quickApplyBibleSearchResult({
    required List<HashTagTarget> targets,
    String? tag,
  }) async {
    final resolvedTag = await _resolveSearchResultTag(tag);
    if (resolvedTag == null) {
      return const HashTagSearchQuickApplyResult(
        tag: null,
        inserted: 0,
        skipped: 0,
        createdDefaultTag: false,
      );
    }

    var inserted = 0;
    var skipped = 0;
    for (final target in targets) {
      final result = await addBibleSearchResultToTag(
        tag: resolvedTag.tag,
        result: PassageSearchResult(
          blockId: 0,
          bookNumber: target.bookNumber,
          bookName: 'Book ${target.bookNumber}',
          chapter: target.chapter,
          verse: target.verse,
          text: '',
        ),
      );
      inserted += result.inserted;
      skipped += result.skipped;
    }
    return HashTagSearchQuickApplyResult(
      tag: resolvedTag.tag,
      inserted: inserted,
      skipped: skipped,
      createdDefaultTag: resolvedTag.createdDefaultTag,
    );
  }

  Future<HashTagSearchQuickApplyResult> addBibleSearchResultToTag({
    required String tag,
    required PassageSearchResult result,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    if (normalizedTag.isEmpty) {
      return const HashTagSearchQuickApplyResult(
        tag: null,
        inserted: 0,
        skipped: 0,
        createdDefaultTag: false,
      );
    }

    await ensureSchema();
    final db = await _db();
    final now = _utcNow();
    final tagKind = _tagKindForTable();
    final groupId = await _ensureNormalizedTagGroup(
      db,
      normalizedTag: normalizedTag,
      now: now,
    );
    final legacyExists = await db.query(
      tableName,
      columns: ['id'],
      where: '''
        tag = ?
        AND book_number = ?
        AND chapter_number = ?
        AND verse_number = ?
      ''',
      whereArgs: [
        normalizedTag,
        result.bookNumber,
        result.chapter,
        result.verse,
      ],
      limit: 1,
    );
    final normalizedExists = await db.query(
      'tag_items',
      columns: ['id'],
      where: '''
        tag_group_id = ?
        AND tag_kind = ?
        AND book_id = ?
        AND chapter = ?
        AND verse_start = ?
        AND verse_end = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [
        groupId,
        tagKind,
        result.bookNumber,
        result.chapter,
        result.verse,
        result.verse,
      ],
      limit: 1,
    );
    if (legacyExists.isNotEmpty || normalizedExists.isNotEmpty) {
      return HashTagSearchQuickApplyResult(
        tag: normalizedTag,
        inserted: 0,
        skipped: 1,
        createdDefaultTag: false,
      );
    }

    final sortOrder = await _nextSortOrderAcrossTagStores(
      db,
      normalizedTag: normalizedTag,
      groupId: groupId,
    );
    await db.insert('tag_items', {
      'id':
          'tag_item_${_slug(groupId)}_${result.bookNumber}_${result.chapter}_${result.verse}',
      'tag_group_id': groupId,
      'tag_kind': tagKind,
      'book_id': result.bookNumber,
      'chapter': result.chapter,
      'verse_start': result.verse,
      'verse_end': result.verse,
      'note_text': null,
      'sort_order': sortOrder,
      'source_device_name': null,
      'legacy_group_id': null,
      'legacy_item_id': null,
      'legacy_import_package_id': null,
      'imported_at': now,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': await LocalSettingsStore.instance.ensureDeviceId(),
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    return HashTagSearchQuickApplyResult(
      tag: normalizedTag,
      inserted: 1,
      skipped: 0,
      createdDefaultTag: false,
    );
  }

  Future<HashTagSearchQuickApplyResult> addBibleRangeToTag({
    required String tag,
    required int bookNumber,
    required int chapter,
    required int verseStart,
    required int verseEnd,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    if (normalizedTag.isEmpty ||
        bookNumber <= 0 ||
        chapter <= 0 ||
        verseStart <= 0) {
      return const HashTagSearchQuickApplyResult(
        tag: null,
        inserted: 0,
        skipped: 0,
        createdDefaultTag: false,
      );
    }

    final normalizedVerseEnd = verseEnd < verseStart ? verseStart : verseEnd;
    await ensureSchema();
    final db = await _db();
    final now = _utcNow();
    final tagKind = _tagKindForTable();
    final groupId = await _ensureNormalizedTagGroup(
      db,
      normalizedTag: normalizedTag,
      now: now,
    );
    final legacyExists = await db.query(
      tableName,
      columns: ['id'],
      where: '''
        tag = ?
        AND book_number = ?
        AND chapter_number = ?
        AND verse_number = ?
      ''',
      whereArgs: [normalizedTag, bookNumber, chapter, verseStart],
      limit: 1,
    );
    final normalizedExists = await db.query(
      'tag_items',
      columns: ['id'],
      where: '''
        tag_group_id = ?
        AND tag_kind = ?
        AND book_id = ?
        AND chapter = ?
        AND verse_start = ?
        AND verse_end = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [
        groupId,
        tagKind,
        bookNumber,
        chapter,
        verseStart,
        normalizedVerseEnd,
      ],
      limit: 1,
    );
    if (legacyExists.isNotEmpty || normalizedExists.isNotEmpty) {
      return HashTagSearchQuickApplyResult(
        tag: normalizedTag,
        inserted: 0,
        skipped: 1,
        createdDefaultTag: false,
      );
    }

    final sortOrder = await _nextSortOrderAcrossTagStores(
      db,
      normalizedTag: normalizedTag,
      groupId: groupId,
    );
    final itemId = [
      'tag_item',
      _slug(groupId),
      bookNumber,
      chapter,
      verseStart,
      normalizedVerseEnd,
    ].join('_');
    await db.insert('tag_items', {
      'id': itemId,
      'tag_group_id': groupId,
      'tag_kind': tagKind,
      'book_id': bookNumber,
      'chapter': chapter,
      'verse_start': verseStart,
      'verse_end': normalizedVerseEnd,
      'note_text': null,
      'sort_order': sortOrder,
      'source_device_name': null,
      'legacy_group_id': null,
      'legacy_item_id': null,
      'legacy_import_package_id': null,
      'imported_at': now,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': await LocalSettingsStore.instance.ensureDeviceId(),
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    return HashTagSearchQuickApplyResult(
      tag: normalizedTag,
      inserted: 1,
      skipped: 0,
      createdDefaultTag: false,
    );
  }

  Future<HashTagSearchQuickApplyResult> quickApplyELibrarySearchResult({
    required String bookTitle,
    required String locationText,
    required String paragraphText,
    required String stableRef,
    String? referenceText,
    String? sourceHref,
    String? sourceAnchorId,
    int? sourceSpineIndex,
    int? sourceParagraphIndex,
    String? sourceRelativePath,
    String? sourceLibraryItemId,
    String? selectedTextSnapshot,
    int? selectionStartBlockIndex,
    int? selectionStartCharOffset,
    int? selectionEndBlockIndex,
    int? selectionEndCharOffset,
    int? selectionStartTokenIndex,
    int? selectionEndTokenIndex,
    String? searchQuery,
    String? tag,
    String? category,
  }) async {
    final resolvedTag = await _resolveSearchResultTag(
      tag,
      fallbackCategory: category,
    );
    if (resolvedTag == null) {
      return const HashTagSearchQuickApplyResult(
        tag: null,
        inserted: 0,
        skipped: 0,
        createdDefaultTag: false,
      );
    }

    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = resolvedTag.tag;
    final cleanStableRef = stableRef.trim();
    final cleanParagraph = paragraphText.trim();
    final cleanTitle = bookTitle.trim();
    final cleanLocation = locationText.trim();
    final cleanReferenceText = referenceText?.trim() ?? '';
    final cleanHref = sourceHref?.trim() ?? '';
    final cleanAnchorId = sourceAnchorId?.trim() ?? '';
    final cleanRelativePath = sourceRelativePath?.trim() ?? '';
    final cleanLibraryItemId = sourceLibraryItemId?.trim() ?? '';
    final cleanSelectedText = (selectedTextSnapshot?.trim().isNotEmpty == true
            ? selectedTextSnapshot!
            : paragraphText)
        .trimRight();
    final cleanQuery = searchQuery?.trim() ?? '';
    if (cleanStableRef.isEmpty || cleanParagraph.isEmpty) {
      return HashTagSearchQuickApplyResult(
        tag: normalizedTag,
        inserted: 0,
        skipped: 0,
        createdDefaultTag: resolvedTag.createdDefaultTag,
      );
    }

    final exists = await db.query(
      tableName,
      columns: ['id'],
      where: 'user_id = ? AND tag = ? AND verse_ref = ?',
      whereArgs: [userId, normalizedTag, cleanStableRef],
      limit: 1,
    );
    if (exists.isNotEmpty) {
      return HashTagSearchQuickApplyResult(
        tag: normalizedTag,
        inserted: 0,
        skipped: 1,
        createdDefaultTag: resolvedTag.createdDefaultTag,
      );
    }

    final resolvedCategory = category?.trim().isNotEmpty == true
        ? category!.trim()
        : await loadTagCategory(normalizedTag);
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextSortOrder = await _nextSortOrderForTag(db, normalizedTag);
    final excerpt = buildFocusedSearchExcerpt(
      paragraphText: cleanParagraph,
      searchQuery: cleanQuery,
    );
    final isRangeSelection =
        selectedTextSnapshot?.trim().isNotEmpty == true ||
        selectionStartBlockIndex != null ||
        selectionStartCharOffset != null ||
        selectionEndBlockIndex != null ||
        selectionEndCharOffset != null ||
        selectionStartTokenIndex != null ||
        selectionEndTokenIndex != null;
    final noteText = isRangeSelection
        ? cleanSelectedText
        : (excerpt.isNotEmpty ? excerpt : cleanParagraph);
    final noteFormatJson = _buildELibraryNoteMetadataJson(
      sourceTitle: cleanTitle,
      sourceTitleAcronym: _libraryBookAbbreviation(cleanTitle) ?? '',
      sourceLocation: cleanLocation,
      sourceReferenceText: cleanReferenceText,
      sourceHref: cleanHref,
      sourceAnchorId: cleanAnchorId,
      sourceSpineIndex: sourceSpineIndex,
      sourceParagraphIndex: sourceParagraphIndex,
      sourceRelativePath: cleanRelativePath,
      sourcePageNumber: _citationPageNumberFromText(cleanLocation),
      sourceParagraphNumber:
          _citationParagraphNumberFromText(cleanLocation) ??
          sourceParagraphIndex,
      searchQuery: cleanQuery,
      sourceParagraph: cleanSelectedText,
      excerpt: noteText,
      stableRef: cleanStableRef,
      sourceType: 'elibrary',
      sourceLibraryItemId: cleanLibraryItemId,
      selectedTextSnapshot: cleanSelectedText,
      selectionStartBlockIndex: selectionStartBlockIndex,
      selectionStartCharOffset: selectionStartCharOffset,
      selectionEndBlockIndex: selectionEndBlockIndex,
      selectionEndCharOffset: selectionEndCharOffset,
      selectionStartTokenIndex: selectionStartTokenIndex,
      selectionEndTokenIndex: selectionEndTokenIndex,
    );
    final cleanReferenceCode = _normalizeReferenceCode(
      cleanReferenceText.isNotEmpty ? cleanReferenceText : cleanLocation,
    );

    await db.insert(tableName, {
      'user_id': userId,
      'tag': normalizedTag,
      if (resolvedCategory != null && resolvedCategory.trim().isNotEmpty)
        'category': resolvedCategory.trim(),
      'verse_ref': cleanStableRef,
      'book_number': 0,
      'chapter_number': 0,
      'verse_number': 0,
      'token_number': null,
      'reference_code': cleanReferenceCode.isEmpty ? null : cleanReferenceCode,
      'note_text': noteText,
      'note_format_json': noteFormatJson,
      'sort_order': nextSortOrder,
      'created_at': now,
    });
    return HashTagSearchQuickApplyResult(
      tag: normalizedTag,
      inserted: 1,
      skipped: 0,
      createdDefaultTag: resolvedTag.createdDefaultTag,
    );
  }

  String buildFocusedSearchExcerpt({
    required String paragraphText,
    required String searchQuery,
    int targetChars = 650,
    int maxChars = 1000,
  }) {
    final source = paragraphText.trim();
    if (source.isEmpty) return '';

    final searchTerms = extractLibrarySearchHighlightTerms(searchQuery);
    if (searchTerms.isEmpty) {
      return _trimToLength(source, maxChars);
    }

    final sentences = _splitSentences(source);
    if (sentences.isEmpty) return _trimToLength(source, maxChars);

    final match = _findFirstSearchMatch(source, searchTerms);
    var matchStart = match?.$1 ?? 0;
    var matchEnd = match?.$2 ?? 0;
    var startIndex = 0;
    var endIndex = sentences.length - 1;
    if (match != null) {
      final sentenceIndex = _sentenceIndexForOffset(sentences, matchStart);
      if (sentenceIndex >= 0) {
        startIndex = sentenceIndex > 0 ? sentenceIndex - 1 : sentenceIndex;
        endIndex = sentenceIndex < sentences.length - 1
            ? sentenceIndex + 1
            : sentenceIndex;
      }
    }

    String selectedText(int start, int end) {
      final boundedStart = start.clamp(0, sentences.length - 1).toInt();
      final boundedEnd = end.clamp(boundedStart, sentences.length - 1).toInt();
      final buffer = StringBuffer();
      for (var index = boundedStart; index <= boundedEnd; index++) {
        if (buffer.isNotEmpty) buffer.write(' ');
        buffer.write(sentences[index].text.trim());
      }
      return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    }

    var excerpt = selectedText(startIndex, endIndex);
    if (excerpt.length < targetChars) {
      while (excerpt.length < targetChars &&
          (startIndex > 0 || endIndex < sentences.length - 1)) {
        final expandBefore = startIndex > 0;
        final expandAfter = endIndex < sentences.length - 1;
        if (expandBefore &&
            (!expandAfter || startIndex >= (sentences.length - endIndex))) {
          startIndex -= 1;
        } else if (expandAfter) {
          endIndex += 1;
        } else {
          break;
        }
        excerpt = selectedText(startIndex, endIndex);
      }
    }

    if (excerpt.length > maxChars) {
      final trimmed = _trimExcerptAroundMatch(
        text: source,
        matchStart: matchStart,
        matchEnd: matchEnd,
        maxChars: maxChars,
      );
      if (trimmed.isNotEmpty) return trimmed;
    }

    return excerpt;
  }

  String _buildELibraryNoteMetadataJson({
    required String sourceTitle,
    required String sourceTitleAcronym,
    required String sourceLocation,
    required String sourceReferenceText,
    required String sourceHref,
    required String sourceAnchorId,
    required int? sourceSpineIndex,
    required int? sourceParagraphIndex,
    required String sourceRelativePath,
    required int? sourcePageNumber,
    required int? sourceParagraphNumber,
    required String searchQuery,
    required String sourceParagraph,
    required String excerpt,
    required String stableRef,
    String? sourceType,
    String? sourceLibraryItemId,
    String? selectedTextSnapshot,
    int? selectionStartBlockIndex,
    int? selectionStartCharOffset,
    int? selectionEndBlockIndex,
    int? selectionEndCharOffset,
    int? selectionStartTokenIndex,
    int? selectionEndTokenIndex,
  }) {
    final payload = <String, Object?>{
      'format_version': 1,
      'base_text_hash': presentationTextFormatHashForText(excerpt),
      'spans': const <Object?>[],
      'kind': 'elibrary_note',
      if (sourceType != null && sourceType.trim().isNotEmpty)
        'source_type': sourceType.trim(),
      'source_title': sourceTitle,
      'source_title_acronym': sourceTitleAcronym,
      'source_location': sourceLocation,
      'source_reference_text': sourceReferenceText,
      'source_href': sourceHref,
      if (sourceLibraryItemId != null && sourceLibraryItemId.trim().isNotEmpty)
        'source_library_item_id': sourceLibraryItemId.trim(),
      'source_anchor_id': sourceAnchorId,
      'source_spine_index': sourceSpineIndex,
      'source_paragraph_index': sourceParagraphIndex,
      'source_relative_path': sourceRelativePath,
      'source_page_number': sourcePageNumber,
      'source_paragraph_number': sourceParagraphNumber,
      'search_query': searchQuery,
      'source_paragraph': sourceParagraph,
      if (selectedTextSnapshot != null && selectedTextSnapshot.trim().isNotEmpty)
        'selected_text_snapshot': selectedTextSnapshot.trimRight(),
      if (selectionStartBlockIndex != null)
        'selection_start_block_index': selectionStartBlockIndex,
      if (selectionStartCharOffset != null)
        'selection_start_char_offset': selectionStartCharOffset,
      if (selectionEndBlockIndex != null)
        'selection_end_block_index': selectionEndBlockIndex,
      if (selectionEndCharOffset != null)
        'selection_end_char_offset': selectionEndCharOffset,
      if (selectionStartTokenIndex != null)
        'selection_start_token_index': selectionStartTokenIndex,
      if (selectionEndTokenIndex != null)
        'selection_end_token_index': selectionEndTokenIndex,
      'excerpt': excerpt,
      'stable_ref': stableRef,
    };
    return jsonEncode(payload);
  }

  String? _libraryBookAbbreviation(String title) {
    return libraryUserFacingBookAbbreviation(title: title);
  }

  String _normalizeReferenceCode(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<String> _loadVerseRangeText({
    required int bookNumber,
    required int chapter,
    required int verseStart,
    required int verseEnd,
  }) async {
    return loadBibleRangeText(
      bookNumber: bookNumber,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd,
    );
  }

  String _normalizedVerseRef(
    Map<String, Object?> row,
    Map<int, String> bookNames,
  ) {
    final book = _i(row['book_id']) ?? 0;
    final chapter = _i(row['chapter']) ?? 0;
    final verseStart = _i(row['verse_start']) ?? 0;
    final verseEnd = _i(row['verse_end']) ?? verseStart;
    final bookName = bookNames[book]?.trim() ?? '';
    if (book == 0 && chapter == 0 && verseStart == 0) {
      final legacyItemId = _s(row['legacy_item_id']);
      return legacyItemId.isEmpty
          ? 'note:${_s(row['id'])}'
          : 'note:$legacyItemId';
    }
    if (bookName.isNotEmpty && chapter > 0 && verseStart > 0) {
      return bibleRangeReferenceLabel(
        bookName: bookName,
        chapter: chapter,
        verseStart: verseStart,
        verseEnd: verseEnd,
      );
    }
    final verseLabel = verseEnd > verseStart
        ? '$verseStart-$verseEnd'
        : '$verseStart';
    return verseEnd > verseStart
        ? 'Book $book $chapter:$verseLabel'
        : 'Book $book $chapter:$verseLabel';
  }

  int? _citationPageNumberFromText(String text) {
    final match = RegExp(r'(\d{1,4})\s*[.:]\s*(\d{1,3})').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  int? _citationParagraphNumberFromText(String text) {
    final explicit = RegExp(r'(\d{1,4})\s*[.:]\s*(\d{1,3})').firstMatch(text);
    if (explicit != null) {
      return int.tryParse(explicit.group(2)!);
    }
    final paragraphOnly = RegExp(r'¶\s*(\d{1,3})').firstMatch(text);
    if (paragraphOnly != null) {
      return int.tryParse(paragraphOnly.group(1)!);
    }
    return null;
  }

  List<_SentenceSpan> _splitSentences(String text) {
    final matches = RegExp(r'[^.!?]+(?:[.!?]+|$)').allMatches(text);
    final sentences = <_SentenceSpan>[];
    for (final match in matches) {
      final value = match.group(0)?.trim();
      if (value == null || value.isEmpty) continue;
      sentences.add(_SentenceSpan(match.start, match.end, value));
    }
    return sentences;
  }

  int _sentenceIndexForOffset(List<_SentenceSpan> sentences, int offset) {
    for (var index = 0; index < sentences.length; index++) {
      final sentence = sentences[index];
      if (offset >= sentence.start && offset < sentence.end) {
        return index;
      }
    }
    return -1;
  }

  (int, int)? _findFirstSearchMatch(String text, List<String> terms) {
    final rankedTerms = terms.toSet().toList(growable: false)
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final term in rankedTerms) {
      final cleaned = _normalizeSearchInput(term);
      if (cleaned.isEmpty) continue;
      final pattern = _buildSearchPattern(cleaned);
      final match = pattern.firstMatch(text);
      if (match != null) {
        return (match.start, match.end);
      }
    }
    return null;
  }

  String _trimExcerptAroundMatch({
    required String text,
    required int matchStart,
    required int matchEnd,
    required int maxChars,
  }) {
    if (text.length <= maxChars) return text;

    final targetHalf = maxChars ~/ 2;
    var start = matchStart - targetHalf;
    var end = matchEnd + targetHalf;
    if (start < 0) start = 0;
    if (end > text.length) end = text.length;

    start = _snapToWordBoundary(text, start, forward: false);
    end = _snapToWordBoundary(text, end, forward: true);

    if (end - start > maxChars) {
      end = (start + maxChars).clamp(0, text.length).toInt();
      end = _snapToWordBoundary(text, end, forward: false);
      if (end <= start) {
        end = (start + maxChars).clamp(0, text.length).toInt();
      }
    }

    final prefix = start > 0 ? '...' : '';
    final suffix = end < text.length ? '...' : '';
    final body = text.substring(start, end).trim();
    return body.isEmpty ? text : '$prefix$body$suffix';
  }

  int _snapToWordBoundary(String text, int index, {required bool forward}) {
    if (index <= 0) return 0;
    if (index >= text.length) return text.length;
    var current = index;
    if (forward) {
      while (current < text.length && !_isWordBoundary(text[current])) {
        current++;
      }
    } else {
      while (current > 0 && !_isWordBoundary(text[current - 1])) {
        current--;
      }
    }
    return current.clamp(0, text.length).toInt();
  }

  bool _isWordBoundary(String char) {
    return RegExp(r'\s').hasMatch(char);
  }

  String _trimToLength(String text, int maxChars) {
    final cleaned = text.trim();
    if (cleaned.length <= maxChars) return cleaned;
    final cutoff = _snapToWordBoundary(cleaned, maxChars, forward: false);
    return '${cleaned.substring(0, cutoff).trimRight()}...';
  }

  String _normalizeSearchInput(String value) {
    return value
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('„', '"')
        .replaceAll('‟', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  RegExp _buildSearchPattern(String term) {
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
    return RegExp(
      r'\b' + words.join(r'[^a-z0-9]+') + r'\b',
      caseSensitive: false,
    );
  }

  Future<void> deleteEntry(int id, {bool normalized = false}) async {
    await ensureSchema();
    final db = await _db();
    if (normalized) {
      await db.delete('tag_items', where: 'rowid = ?', whereArgs: [id]);
      return;
    }
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateEntry({
    required int id,
    required Map<String, Object?> values,
    bool normalized = false,
  }) async {
    await ensureSchema();
    final db = await _db();
    if (normalized) {
      final updatedValues = Map<String, Object?>.from(values)
        ..['updated_at'] = _utcNow();
      await db.update(
        'tag_items',
        updatedValues,
        where: 'rowid = ?',
        whereArgs: [id],
      );
      return;
    }
    await db.update(tableName, values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertNoteItem({
    required String tag,
    required String noteText,
    String? referenceCode,
    String? category,
    String? noteFormatJson,
    bool allowBlank = false,
  }) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = normalizeTagName(tag);
    final cleanNote = noteText.trim();
    final cleanReferenceCode = _normalizeReferenceCode(referenceCode ?? '');
    if (normalizedTag.isEmpty) return 0;
    if (cleanNote.isEmpty && cleanReferenceCode.isEmpty && !allowBlank) {
      return 0;
    }
    final resolvedCategory = category?.trim().isNotEmpty == true
        ? category!.trim()
        : await loadTagCategory(normalizedTag);
    final now = DateTime.now().millisecondsSinceEpoch;
    final nextSortOrder = await _nextSortOrderForTag(db, normalizedTag);
    final values = <String, Object?>{
      'user_id': userId,
      'tag': normalizedTag,
      if (resolvedCategory != null && resolvedCategory.trim().isNotEmpty)
        'category': resolvedCategory.trim(),
      'verse_ref': 'note:$now',
      'book_number': 0,
      'chapter_number': 0,
      'verse_number': 0,
      'token_number': null,
      'reference_code': cleanReferenceCode.isEmpty ? null : cleanReferenceCode,
      'created_at': now,
    };
    if (tableName == 'dollar_tags') {
      values.addAll({
        'content_html': _plainTextToHtml(cleanNote),
        'source_author': '',
        'source_work_title': '',
        'source_title_acronym': '',
        'source_chapter_title': '',
        'source_chapter_number': '',
        'source_page_number': '',
        'source_paragraph_number': '',
        'source_year': '',
        'study_order': nextSortOrder,
      });
    } else {
      values.addAll({
        'note_text': cleanNote.isEmpty ? null : cleanNote,
        'note_format_json': noteFormatJson,
        'sort_order': nextSortOrder,
      });
    }
    return db.insert(tableName, values);
  }

  Future<HashTagResolvedTag?> _resolveSearchResultTag(
    String? tag, {
    String? fallbackCategory,
  }) async {
    final explicitTag = normalizeTagName(tag ?? '');
    if (explicitTag.isNotEmpty) {
      return HashTagResolvedTag(tag: explicitTag, createdDefaultTag: false);
    }

    final defaultTag = await loadActiveDefaultTag();
    if (defaultTag == null) {
      return null;
    }

    if (fallbackCategory != null && fallbackCategory.trim().isNotEmpty) {
      final category = fallbackCategory.trim();
      final existingCategory = await loadTagCategory(defaultTag);
      if (existingCategory == null || existingCategory.trim().isEmpty) {
        await saveTagCategory(defaultTag, category);
      }
    }

    return HashTagResolvedTag(tag: defaultTag, createdDefaultTag: false);
  }

  Future<bool> _tagExists(String normalizedTag) async {
    final db = await _db();
    final rows = await db.query(
      tableName,
      columns: ['id'],
      where: 'tag = ?',
      whereArgs: [normalizedTag],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> addMediaAttachment({
    required int entryId,
    required String relativePath,
    required String mimeType,
    required int fileSize,
    required String fileHash,
    String? caption,
    int sortOrder = 0,
  }) async {
    await ensureSchema();
    final db = await _db();
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    await db.insert('tag_item_media', {
      'id': 'legacy-media-$entryId-$now-${p.basename(relativePath)}',
      'tag_item_id': entryId.toString(),
      'media_type': _mediaTypeFromMimeType(mimeType),
      'relative_path': relativePath,
      'caption': caption,
      'file_hash': fileHash,
      'file_size': fileSize,
      'sort_order': sortOrder,
      'source_device_name': null,
      'legacy_group_id': null,
      'legacy_item_id': entryId.toString(),
      'legacy_import_package_id': null,
      'imported_at': null,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': await LocalSettingsStore.instance.ensureDeviceId(),
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    });
  }

  String _tagKindForTable() {
    return tableName == 'dollar_tags' ? 'dollar' : 'hash';
  }

  Future<void> deleteMediaAttachmentsForEntry(int entryId) async {
    await ensureSchema();
    final db = await _db();
    await db.delete(
      'tag_item_media',
      where: 'tag_item_id = ?',
      whereArgs: [entryId.toString()],
    );
  }

  Future<Map<int, List<String>>> _loadMediaRefsForEntries(
    Database db,
    List<int> entryIds,
  ) async {
    if (entryIds.isEmpty) return const <int, List<String>>{};
    final placeholders = List.filled(entryIds.length, '?').join(', ');
    final rows = await db.rawQuery(
      '''
      SELECT tag_item_id, relative_path, sort_order
      FROM tag_item_media
      WHERE tag_item_id IN ($placeholders)
      ORDER BY tag_item_id ASC, sort_order ASC, id ASC
      ''',
      [for (final id in entryIds) id.toString()],
    );
    final grouped = <int, List<String>>{};
    for (final row in rows) {
      final itemId = int.tryParse(row['tag_item_id']?.toString() ?? '');
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (itemId == null || relativePath.isEmpty) continue;
      grouped.putIfAbsent(itemId, () => <String>[]).add(relativePath);
    }
    return grouped;
  }

  String _mediaTypeFromMimeType(String mimeType) {
    final normalized = mimeType.trim().toLowerCase();
    if (normalized.startsWith('image/')) return 'image';
    if (normalized.startsWith('video/')) return 'video';
    if (normalized.startsWith('audio/')) return 'audio';
    return normalized.isEmpty ? 'image' : normalized;
  }

  Future<int> insertNoteSlide({
    required String tag,
    required String contentHtml,
    String? referenceCode,
    String? noteFormatJson,
  }) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = normalizeTagName(tag);
    if (normalizedTag.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cleanReferenceCode = _normalizeReferenceCode(referenceCode ?? '');
    return db.insert(tableName, {
      'user_id': userId,
      'tag': normalizedTag,
      'verse_ref': 'note:$now',
      'book_number': 0,
      'chapter_number': 0,
      'verse_number': 0,
      'token_number': null,
      'reference_code': cleanReferenceCode.isEmpty ? null : cleanReferenceCode,
      'content_html': contentHtml,
      'note_format_json': noteFormatJson,
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

  Future<int> _nextSortOrderForTag(Database db, String normalizedTag) async {
    final orderColumn = tableName == 'dollar_tags'
        ? 'study_order'
        : 'sort_order';
    final legacyRows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(COALESCE($orderColumn, created_at)), 0) AS max_sort_order
      FROM $tableName
      WHERE tag = ?
      ''',
      [normalizedTag],
    );
    final legacyMax =
        (legacyRows.isNotEmpty ? legacyRows.first['max_sort_order'] : null)
            as num?;

    final tagKind = _tagKindForTable();
    final groupRows = await db.query(
      'tag_groups',
      columns: ['id'],
      where: '''
        tag_kind = ?
        AND name = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [tagKind, normalizedTag],
      limit: 1,
    );
    var normalizedMax = 0;
    if (groupRows.isNotEmpty) {
      final normalizedRows = await db.rawQuery(
        '''
        SELECT COALESCE(MAX(sort_order), 0) AS max_sort_order
        FROM tag_items
        WHERE tag_group_id = ?
          AND tag_kind = ?
          AND COALESCE(deleted_at, '') = ''
        ''',
        [groupRows.first['id']?.toString() ?? '', tagKind],
      );
      final value = normalizedRows.isNotEmpty
          ? normalizedRows.first['max_sort_order']
          : null;
      normalizedMax = value is num ? value.toInt() : 0;
    }

    final highest = [
      legacyMax?.toInt() ?? 0,
      normalizedMax.toInt(),
    ].reduce((left, right) => left > right ? left : right);
    return highest + 1;
  }

  Future<String> _ensureNormalizedTagGroup(
    Database db, {
    required String normalizedTag,
    required String now,
  }) async {
    final tagKind = _tagKindForTable();
    final rows = await db.query(
      'tag_groups',
      columns: ['id'],
      where: '''
        tag_kind = ?
        AND name = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [tagKind, normalizedTag],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['id']?.toString() ?? '';
    }

    final groupId = 'tag_group_${_slug(normalizedTag)}';
    final sortOrder = await _nextNormalizedTagGroupSortOrder(db);
    await db.insert('tag_groups', {
      'id': groupId,
      'parent_group_id': null,
      'tag_kind': tagKind,
      'name': normalizedTag,
      'description': null,
      'sort_order': sortOrder,
      'source_device_name': null,
      'legacy_group_id': null,
      'legacy_item_id': null,
      'legacy_import_package_id': null,
      'imported_at': now,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': await LocalSettingsStore.instance.ensureDeviceId(),
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return groupId;
  }

  Future<int> _nextNormalizedTagGroupSortOrder(Database db) async {
    final tagKind = _tagKindForTable();
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(sort_order), 0) AS max_sort_order
      FROM tag_groups
      WHERE tag_kind = ?
        AND COALESCE(deleted_at, '') = ''
    ''',
      [tagKind],
    );
    final maxValue =
        (rows.isNotEmpty ? rows.first['max_sort_order'] : null) as num?;
    return (maxValue?.toInt() ?? 0) + 1;
  }

  Future<int> _nextSortOrderAcrossTagStores(
    Database db, {
    required String normalizedTag,
    required String groupId,
  }) async {
    final tagKind = _tagKindForTable();
    final legacyRows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(COALESCE(sort_order, created_at)), 0) AS max_sort_order
      FROM $tableName
      WHERE tag = ?
      ''',
      [normalizedTag],
    );
    final normalizedRows = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(sort_order), 0) AS max_sort_order
      FROM tag_items
      WHERE tag_group_id = ?
        AND tag_kind = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      [groupId, tagKind],
    );
    final legacyMax =
        (legacyRows.isNotEmpty ? legacyRows.first['max_sort_order'] : null)
            as num?;
    final normalizedMax =
        (normalizedRows.isNotEmpty
                ? normalizedRows.first['max_sort_order']
                : null)
            as num?;
    final highest = [
      legacyMax?.toInt() ?? 0,
      normalizedMax?.toInt() ?? 0,
    ].reduce((left, right) => left > right ? left : right);
    return highest + 1;
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

  int? _intValueNullable(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _s(Object? value) => value?.toString() ?? '';

  int? _i(Object? value) => _intValueNullable(value);

  String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }

  String _slug(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return 'item';
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
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

class _SentenceSpan {
  const _SentenceSpan(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}
