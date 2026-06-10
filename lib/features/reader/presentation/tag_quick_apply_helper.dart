import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
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
      displayTextFormatJson: decoded['display_text_format_json']
          ?.toString()
          .trim(),
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

  String? _normalizeCategoryName(String? input) {
    final normalized = input?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String _legacyCategoryWhereClause(
    String column,
    String? category,
    List<Object?> whereArgs,
  ) {
    final normalizedCategory = _normalizeCategoryName(category);
    if (normalizedCategory == null) {
      return '($column IS NULL OR TRIM($column) = \'\')';
    }
    whereArgs.add(normalizedCategory);
    return 'COALESCE(TRIM($column), \'\') = ?';
  }

  Future<List<Map<String, Object?>>> _loadNormalizedTagRows(
    DatabaseExecutor executor, {
    required String normalizedTag,
    String? category,
  }) async {
    final normalizedCategory = _normalizeCategoryName(category);
    final tagKind = _tagKindForTable();
    if (normalizedCategory == null) {
      return executor.query(
        'tag_groups',
        columns: ['id', 'parent_group_id'],
        where: '''
          tag_kind = ?
          AND name = ?
          AND COALESCE(deleted_at, '') = ''
        ''',
        whereArgs: [tagKind, normalizedTag],
        orderBy: 'created_at ASC, id ASC',
      );
    }
    return executor.rawQuery(
      '''
      SELECT groups.id, groups.parent_group_id
      FROM tag_groups AS groups
      LEFT JOIN tag_groups AS parent
        ON parent.id = groups.parent_group_id
      WHERE groups.tag_kind = ?
        AND groups.name = ?
        AND COALESCE(groups.deleted_at, '') = ''
        AND COALESCE(parent.name, '') = ?
      ORDER BY groups.created_at ASC, groups.id ASC
      ''',
      [tagKind, normalizedTag, normalizedCategory],
    );
  }

  Future<List<Map<String, Object?>>> _loadNormalizedTagItemRows(
    DatabaseExecutor executor,
    List<String> groupIds,
  ) async {
    if (groupIds.isEmpty) return const <Map<String, Object?>>[];
    final placeholders = List.filled(groupIds.length, '?').join(', ');
    return executor.rawQuery('''
      SELECT *
      FROM tag_items
      WHERE tag_group_id IN ($placeholders)
        AND COALESCE(deleted_at, '') = ''
      ORDER BY tag_group_id ASC, sort_order ASC, created_at ASC, id ASC
      ''', groupIds);
  }

  Future<String?> _ensureNormalizedCategoryGroupId(
    DatabaseExecutor executor,
    String? category,
  ) async {
    final normalizedCategory = _normalizeCategoryName(category);
    if (normalizedCategory == null) return null;
    final tagKind = _tagKindForTable();
    final rows = await executor.query(
      'tag_groups',
      columns: ['id'],
      where: '''
        tag_kind = ?
        AND name = ?
        AND COALESCE(parent_group_id, '') = ''
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [tagKind, normalizedCategory],
      orderBy: 'created_at ASC, id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['id']?.toString();
    }
    final now = _utcNow();
    return _ensureNormalizedTagGroup(
      executor,
      normalizedTag: normalizedCategory,
      now: now,
    );
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

  Future<String?> loadDefaultTagCategory() async {
    await ensureSchema();
    final db = await _db();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['$defaultSettingKey.category'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _normalizeCategoryName(rows.first['value']?.toString());
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

  Future<void> saveDefaultTagCategory(String? category) async {
    await ensureSchema();
    final db = await _db();
    final normalized = _normalizeCategoryName(category);
    if (normalized == null) {
      await db.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['$defaultSettingKey.category'],
      );
      return;
    }
    await db.insert('app_settings', {
      'key': '$defaultSettingKey.category',
      'value': normalized,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearDefaultTag() async {
    await ensureSchema();
    final db = await _db();
    await db.delete(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: [defaultSettingKey, '$defaultSettingKey.category'],
    );
  }

  Future<String?> loadActiveDefaultTag() async {
    final defaultTag = normalizeTagName(await loadDefaultTag() ?? '');
    if (defaultTag.isEmpty) return null;
    final defaultCategory = await loadDefaultTagCategory();
    if (defaultCategory != null &&
        defaultCategory.trim().isNotEmpty &&
        await _tagExists(defaultTag, category: defaultCategory)) {
      return defaultTag;
    }
    if (defaultCategory == null && await _tagExists(defaultTag)) {
      return defaultTag;
    }

    await clearDefaultTag();
    return null;
  }

  Future<int> renameTag({
    required String oldTag,
    required String newTag,
    String? category,
    bool categoryKnown = false,
  }) async {
    final normalizedOld = normalizeTagName(oldTag);
    final normalizedNew = normalizeTagName(newTag);
    if (normalizedOld.isEmpty || normalizedNew.isEmpty) return 0;
    final normalizedCategory = _normalizeCategoryName(category);
    // Refuse name-only rename: without knowing the category we cannot safely
    // scope the UPDATE — same-name tags in other categories would be affected.
    if (!categoryKnown && normalizedCategory == null) {
      debugPrint(
        'renameTag: refused name-only rename for "$normalizedOld" — '
        'category unknown; pass categoryKnown: true to rename a root-category tag',
      );
      return 0;
    }
    await ensureSchema();
    final db = await _db();
    final whereArgs = <Object?>[normalizedOld];
    var where = 'tag = ?';
    if (normalizedCategory != null) {
      where += ' AND category = ?';
      whereArgs.add(normalizedCategory);
    } else {
      // categoryKnown=true with null category → root/uncategorized tag.
      // Use IS NULL so the clause works correctly in SQLite.
      where += ' AND (category IS NULL OR TRIM(category) = \'\')';
    }
    final count = await db.update(
      tableName,
      {'tag': normalizedNew},
      where: where,
      whereArgs: whereArgs,
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

  Future<String?> loadTagCategory(String tag, {String? category}) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return null;
    final normalizedCategory = _normalizeCategoryName(category);
    if (normalizedCategory != null) return normalizedCategory;
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

  Future<bool> hasVisibleTagSummary(String tag, {String? category}) async {
    final normalizedTag = normalizeTagName(tag);
    if (normalizedTag.isEmpty) return false;
    final normalizedCategory = _normalizeCategoryName(category);
    final summaries = await loadSummaries();
    return summaries.any((summary) {
      if (summary.tag.toLowerCase() != normalizedTag.toLowerCase()) {
        return false;
      }
      final summaryCategory = summary.category?.trim() ?? '';
      if (normalizedCategory == null) {
        return summaryCategory.isEmpty;
      }
      return summaryCategory.toLowerCase() == normalizedCategory.toLowerCase();
    });
  }

  Future<bool> saveTagCategory(
    String tag,
    String category, {
    String? currentCategory,
    bool currentCategoryKnown = false,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedCategory = _normalizeCategoryName(category);
    final normalizedCurrentCategory = _normalizeCategoryName(currentCategory);
    if (normalizedTag.isEmpty) return false;
    try {
      await ensureSchema();
      final db = await _db();
      if (normalizedCategory == null) {
        await db.delete(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['$categorySettingKeyPrefix$normalizedTag'],
        );
      } else {
        await db.insert('app_settings', {
          'key': '$categorySettingKeyPrefix$normalizedTag',
          'value': normalizedCategory,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      final whereArgs = <Object?>[normalizedTag];
      var where = 'tag = ?';
      if (currentCategoryKnown) {
        // Caller knows the current category; scope the UPDATE precisely.
        // COALESCE handles NULL so this correctly matches root-category rows
        // when normalizedCurrentCategory is null ('').
        where += ' AND COALESCE(TRIM(category), \'\') = ?';
        whereArgs.add(normalizedCurrentCategory ?? '');
      } else {
        // Category is unknown: only update rows that currently have no
        // category.  This is safe for initial category assignments on newly
        // created tags while preventing cross-category contamination for
        // same-name tags that already have a category.
        where += ' AND (category IS NULL OR TRIM(category) = \'\')';
      }

      final values = <String, Object?>{'category': normalizedCategory};
      final updated = await db.update(
        tableName,
        values,
        where: where,
        whereArgs: whereArgs,
      );
      if (updated > 0) return true;

      final normalizedGroupRows = await _loadNormalizedTagRows(
        db,
        normalizedTag: normalizedTag,
        category: normalizedCurrentCategory,
      );
      if (normalizedGroupRows.isNotEmpty) {
        final targetCategoryGroupId = await _ensureNormalizedCategoryGroupId(
          db,
          normalizedCategory,
        );
        var normalizedUpdated = 0;
        for (final row in normalizedGroupRows) {
          final groupId = row['id']?.toString() ?? '';
          if (groupId.isEmpty) continue;
          normalizedUpdated += await db.update(
            'tag_groups',
            {'parent_group_id': targetCategoryGroupId},
            where: 'id = ?',
            whereArgs: [groupId],
          );
        }
        if (normalizedUpdated > 0) return true;
      }

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<HashTagCategoryMergeResult> mergeTagCategory({
    required String tag,
    required String sourceCategory,
    required String targetCategory,
    bool dryRun = false,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedSourceCategory = _normalizeCategoryName(sourceCategory);
    final normalizedTargetCategory = _normalizeCategoryName(targetCategory);
    if (normalizedTag.isEmpty) {
      return HashTagCategoryMergeResult(
        tag: normalizedTag,
        sourceCategory: normalizedSourceCategory,
        targetCategory: normalizedTargetCategory ?? '',
        sourceCount: 0,
        targetCount: 0,
        addedCount: 0,
        skippedCount: 0,
        sourceRemoved: false,
        dryRun: dryRun,
      );
    }

    await ensureSchema();
    final db = await _db();

    Future<List<Map<String, Object?>>> loadLegacyRows(
      DatabaseExecutor executor, {
      required String? category,
    }) async {
      final orderBy = tableName == 'dollar_tags'
          ? 'study_order ASC, created_at ASC, id ASC'
          : 'sort_order ASC, created_at ASC, id ASC';
      final whereArgs = <Object?>[normalizedTag];
      final whereClause = _legacyCategoryWhereClause(
        'category',
        category,
        whereArgs,
      );
      return executor.query(
        tableName,
        where: 'tag = ? AND $whereClause',
        whereArgs: whereArgs,
        orderBy: orderBy,
      );
    }

    int legacyRowSortOrder(Map<String, Object?> row) {
      return (tableName == 'dollar_tags'
              ? _i(row['study_order'])
              : _i(row['sort_order'])) ??
          _i(row['created_at']) ??
          0;
    }

    int normalizedRowSortOrder(Map<String, Object?> row) {
      return _i(row['sort_order']) ?? _i(row['created_at']) ?? 0;
    }

    String copyMediaRowId({
      required String sourceMediaId,
      required String targetItemId,
      required int index,
    }) {
      final encoded = base64Url
          .encode(utf8.encode('$sourceMediaId|$targetItemId|$index'))
          .replaceAll('=', '');
      return 'tag_item_media_$encoded';
    }

    String copyNormalizedItemId({
      required String sourceItemId,
      required String targetGroupId,
    }) {
      final encoded = base64Url
          .encode(utf8.encode('$sourceItemId|$targetGroupId'))
          .replaceAll('=', '');
      return 'tag_item_$encoded';
    }

    Future<String> ensureTargetNormalizedGroupId({
      required DatabaseExecutor executor,
      required String normalizedTag,
      required String? category,
      required String now,
    }) async {
      final normalizedCategory = _normalizeCategoryName(category);
      if (normalizedCategory == null) {
        return _ensureNormalizedTagGroup(
          executor,
          normalizedTag: normalizedTag,
          now: now,
        );
      }
      final rows = await executor.rawQuery(
        '''
        SELECT groups.id
        FROM tag_groups AS groups
        LEFT JOIN tag_groups AS parent
          ON parent.id = groups.parent_group_id
        WHERE groups.tag_kind = ?
          AND groups.name = ?
          AND COALESCE(groups.deleted_at, '') = ''
          AND COALESCE(parent.name, '') = ?
        ORDER BY groups.created_at ASC, groups.id ASC
        LIMIT 1
        ''',
        [_tagKindForTable(), normalizedTag, normalizedCategory],
      );
      if (rows.isNotEmpty) {
        return rows.first['id']?.toString() ?? '';
      }

      final parentGroupId = await _ensureNormalizedCategoryGroupId(
        executor,
        normalizedCategory,
      );
      final groupId =
          'tag_group_${_slug(normalizedCategory)}_${_slug(normalizedTag)}';
      final sortOrder = await _nextNormalizedTagGroupSortOrder(executor);
      await executor.insert('tag_groups', {
        'id': groupId,
        'parent_group_id': parentGroupId,
        'tag_kind': _tagKindForTable(),
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

    Future<void> copyMediaRows({
      required DatabaseExecutor executor,
      required String sourceItemId,
      required String targetItemId,
      required String now,
    }) async {
      final mediaRows = await executor.rawQuery(
        '''
        SELECT *
        FROM tag_item_media
        WHERE tag_item_id = ?
          AND COALESCE(deleted_at, '') = ''
        ORDER BY sort_order ASC, id ASC
        ''',
        [sourceItemId],
      );
      if (mediaRows.isEmpty) return;
      final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
      for (var index = 0; index < mediaRows.length; index++) {
        final mediaRow = Map<String, Object?>.from(mediaRows[index]);
        mediaRow
          ..remove('id')
          ..['id'] = copyMediaRowId(
            sourceMediaId: _s(mediaRows[index]['id']),
            targetItemId: targetItemId,
            index: index,
          )
          ..['tag_item_id'] = targetItemId
          ..['created_at'] = now
          ..['updated_at'] = now
          ..['deleted_at'] = null
          ..['device_id'] = deviceId
          ..['revision'] = 1
          ..['sync_status'] = 'pending'
          ..['last_synced_at'] = null
          ..['change_id'] = null;
        await executor.insert('tag_item_media', mediaRow);
      }
    }

    final result = await db.transaction((txn) async {
      final sourceRows = await loadLegacyRows(
        txn,
        category: normalizedSourceCategory,
      );
      final targetRows = await loadLegacyRows(
        txn,
        category: normalizedTargetCategory,
      );
      final sourceGroupRows = await _loadNormalizedTagRows(
        txn,
        normalizedTag: normalizedTag,
        category: normalizedSourceCategory,
      );
      final targetGroupRows = await _loadNormalizedTagRows(
        txn,
        normalizedTag: normalizedTag,
        category: normalizedTargetCategory,
      );
      final sourceGroupIds = [
        for (final row in sourceGroupRows) row['id']?.toString() ?? '',
      ].where((value) => value.isNotEmpty).toList(growable: false);
      final targetGroupIds = [
        for (final row in targetGroupRows) row['id']?.toString() ?? '',
      ].where((value) => value.isNotEmpty).toList(growable: false);
      final sourceItems = await _loadNormalizedTagItemRows(txn, sourceGroupIds);
      final targetItems = await _loadNormalizedTagItemRows(txn, targetGroupIds);

      final sourceCount = sourceRows.length + sourceItems.length;
      final targetCount = targetRows.length + targetItems.length;
      final targetKeys = <String>{
        for (final row in targetRows) _legacyMergeKey(row),
        for (final row in targetItems) _mergeKey(row),
      };

      int addedCount = 0;
      int skippedCount = 0;

      if (dryRun) {
        for (final row in sourceRows) {
          final key = _legacyMergeKey(row);
          if (targetKeys.contains(key)) {
            skippedCount += 1;
          } else {
            addedCount += 1;
            targetKeys.add(key);
          }
        }
        for (final row in sourceItems) {
          final key = _mergeKey(row);
          if (targetKeys.contains(key)) {
            skippedCount += 1;
          } else {
            addedCount += 1;
            targetKeys.add(key);
          }
        }
        return HashTagCategoryMergeResult(
          tag: normalizedTag,
          sourceCategory: normalizedSourceCategory,
          targetCategory: normalizedTargetCategory ?? '',
          sourceCount: sourceCount,
          targetCount: targetCount,
          addedCount: addedCount,
          skippedCount: skippedCount,
          sourceRemoved: false,
          dryRun: true,
        );
      }

      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final nowIso = _utcNow();
      var nextSortOrder = [
        for (final row in targetRows) legacyRowSortOrder(row),
        for (final row in targetItems) normalizedRowSortOrder(row),
      ].fold<int>(0, (highest, value) => value > highest ? value : highest);
      nextSortOrder += 1;

      for (final row in sourceRows) {
        final key = _legacyMergeKey(row);
        if (targetKeys.contains(key)) {
          skippedCount += 1;
          continue;
        }
        final values = Map<String, Object?>.from(row)
          ..remove('id')
          ..['category'] = normalizedTargetCategory
          ..[tableName == 'dollar_tags' ? 'study_order' : 'sort_order'] =
              nextSortOrder
          ..['created_at'] = nowMillis;
        if (values.containsKey('updated_at')) {
          values['updated_at'] = nowMillis;
        }
        final insertedId = await txn.insert(tableName, values);
        if (insertedId <= 0) {
          throw StateError('Failed to copy legacy tag row.');
        }
        await copyMediaRows(
          executor: txn,
          sourceItemId: _s(row['id']).trim(),
          targetItemId: insertedId.toString(),
          now: nowMillis.toString(),
        );
        targetKeys.add(key);
        addedCount += 1;
        nextSortOrder += 1;
      }

      if (sourceItems.isNotEmpty) {
        final targetGroupId = await ensureTargetNormalizedGroupId(
          executor: txn,
          normalizedTag: normalizedTag,
          category: normalizedTargetCategory,
          now: nowIso,
        );
        final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
        for (final row in sourceItems) {
          final key = _mergeKey(row);
          if (targetKeys.contains(key)) {
            skippedCount += 1;
            continue;
          }

          final sourceItemId = _s(row['id']).trim();
          if (sourceItemId.isEmpty) {
            skippedCount += 1;
            continue;
          }

          final itemId = copyNormalizedItemId(
            sourceItemId: sourceItemId,
            targetGroupId: targetGroupId,
          );
          final values = Map<String, Object?>.from(row)
            ..remove('id')
            ..['id'] = itemId
            ..['tag_group_id'] = targetGroupId
            ..['sort_order'] = nextSortOrder
            ..['created_at'] = nowIso
            ..['updated_at'] = nowIso
            ..['imported_at'] = nowIso
            ..['deleted_at'] = null
            ..['device_id'] = deviceId
            ..['revision'] = 1
            ..['sync_status'] = 'pending'
            ..['last_synced_at'] = null
            ..['change_id'] = null;
          await txn.insert(
            'tag_items',
            values,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          await copyMediaRows(
            executor: txn,
            sourceItemId: sourceItemId,
            targetItemId: itemId,
            now: nowIso,
          );
          targetKeys.add(key);
          addedCount += 1;
          nextSortOrder += 1;
        }
      }

      return HashTagCategoryMergeResult(
        tag: normalizedTag,
        sourceCategory: normalizedSourceCategory,
        targetCategory: normalizedTargetCategory ?? '',
        sourceCount: sourceCount,
        targetCount: targetCount,
        addedCount: addedCount,
        skippedCount: skippedCount,
        sourceRemoved: false,
        dryRun: false,
      );
    });

    return result;
  }

  Future<int> deleteTag(String tag, {String? category}) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return 0;
    await ensureSchema();
    final db = await _db();
    final normalizedCategory = _normalizeCategoryName(category);
    final whereArgs = <Object?>[normalized];
    var where = 'tag = ?';
    if (normalizedCategory != null) {
      where += ' AND category = ?';
      whereArgs.add(normalizedCategory);
    }
    final deleted = await db.delete(
      tableName,
      where: where,
      whereArgs: whereArgs,
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
    final categoryOptions = await loadCategoryOptions();
    final categoryNames = {
      for (final category in categoryOptions) category.toLowerCase(),
    };
    final legacyRows = await db.rawQuery('''
      SELECT tag, COALESCE(TRIM(category), '') AS category, COUNT(*) AS cnt
      FROM $tableName
      GROUP BY tag, COALESCE(TRIM(category), '')
    ''');
    final normalizedRows = await db.rawQuery(
      '''
      SELECT
        groups.name AS tag,
        COALESCE(parent.name, '') AS category,
        COUNT(items.id) AS cnt
      FROM tag_groups AS groups
      LEFT JOIN tag_groups AS parent
        ON parent.id = groups.parent_group_id
      LEFT JOIN tag_items AS items
        ON items.tag_group_id = groups.id
       AND COALESCE(items.deleted_at, '') = ''
      WHERE groups.tag_kind = ?
        AND COALESCE(groups.deleted_at, '') = ''
      GROUP BY groups.id, groups.name, COALESCE(parent.name, '')
    ''',
      [tagKind],
    );

    final merged = <String, HashTagSummary>{};
    void addRow(Map<String, Object?> row) {
      final tag = row['tag']?.toString().trim() ?? '';
      if (tag.isEmpty) return;
      final category = row['category']?.toString().trim() ?? '';
      final count = (row['cnt'] as num?)?.toInt() ?? 0;
      if (category.isEmpty &&
          count == 0 &&
          categoryNames.contains(tag.toLowerCase())) {
        return;
      }
      final key = '${tag.toLowerCase()}|${category.toLowerCase()}';
      final existing = merged[key];
      merged[key] = HashTagSummary(
        tag: existing?.tag ?? tag,
        count: (existing?.count ?? 0) + count,
        category: existing?.category ?? (category.isEmpty ? null : category),
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
    String? category,
    HashTagEntrySortMode sortMode = HashTagEntrySortMode.slideOrder,
  }) async {
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return const <HashTagEntry>[];
    final normalizedCategory = _normalizeCategoryName(category);
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
      final whereArgs = <Object?>[normalized];
      final whereClause = _legacyCategoryWhereClause(
        'category',
        normalizedCategory,
        whereArgs,
      );
      final rows = await db.query(
        tableName,
        columns: columns,
        where: 'tag = ? AND $whereClause',
        whereArgs: whereArgs,
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
      final groupRows = normalizedCategory == null
          ? await db.query(
              'tag_groups',
              columns: ['id', 'parent_group_id'],
              where: '''
                tag_kind = ?
                AND name = ?
                AND COALESCE(deleted_at, '') = ''
              ''',
              whereArgs: [tagKind, normalized],
              orderBy: 'created_at ASC, id ASC',
            )
          : await db.rawQuery(
              '''
              SELECT groups.id, groups.parent_group_id
              FROM tag_groups AS groups
              LEFT JOIN tag_groups AS parent
                ON parent.id = groups.parent_group_id
              WHERE groups.tag_kind = ?
                AND groups.name = ?
                AND COALESCE(groups.deleted_at, '') = ''
                AND COALESCE(parent.name, '') = ?
              ORDER BY groups.created_at ASC, groups.id ASC
              ''',
              [tagKind, normalized, normalizedCategory],
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
    String? category,
  }) async {
    if (targets.isEmpty) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = normalizeTagName(tag ?? await loadDefaultTag() ?? '');
    final normalizedCategory = _normalizeCategoryName(category);
    if (normalizedTag.isEmpty) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }

    var inserted = 0;
    var skipped = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final target in targets) {
      final categoryArgs = <Object?>[];
      final categoryClause = _legacyCategoryWhereClause(
        'category',
        normalizedCategory,
        categoryArgs,
      );
      final exists = await db.rawQuery(
        '''
        SELECT 1
        FROM $tableName
        WHERE user_id = ?
          AND tag = ?
          AND $categoryClause
          AND ((book_number = ? AND chapter_number = ? AND verse_number = ?) OR verse_ref = ?)
        LIMIT 1
        ''',
        [
          userId,
          normalizedTag,
          ...categoryArgs,
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
        if (normalizedCategory != null) 'category': normalizedCategory,
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
    final fallbackCategory = await loadDefaultTagCategory();
    final useFallbackCategory = tag?.trim().isNotEmpty != true;
    final resolvedTag = await _resolveSearchResultTag(
      tag,
      fallbackCategory: fallbackCategory,
    );
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
        category: useFallbackCategory ? fallbackCategory : null,
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
    String? category,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedCategory = _normalizeCategoryName(category);
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
    final legacyCategoryArgs = <Object?>[];
    final legacyCategoryClause = _legacyCategoryWhereClause(
      'category',
      normalizedCategory,
      legacyCategoryArgs,
    );
    final legacyExists = await db.query(
      tableName,
      columns: ['id'],
      where:
          '''
        tag = ?
        AND $legacyCategoryClause
        AND book_number = ?
        AND chapter_number = ?
        AND verse_number = ?
      ''',
      whereArgs: [
        normalizedTag,
        ...legacyCategoryArgs,
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
    String? category,
  }) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedCategory = _normalizeCategoryName(category);
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
    final legacyCategoryArgs = <Object?>[];
    final legacyCategoryClause = _legacyCategoryWhereClause(
      'category',
      normalizedCategory,
      legacyCategoryArgs,
    );
    final legacyExists = await db.query(
      tableName,
      columns: ['id'],
      where:
          '''
        tag = ?
        AND $legacyCategoryClause
        AND book_number = ?
        AND chapter_number = ?
        AND verse_number = ?
      ''',
      whereArgs: [
        normalizedTag,
        ...legacyCategoryArgs,
        bookNumber,
        chapter,
        verseStart,
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
    final normalizedCategory = _normalizeCategoryName(category);
    final cleanStableRef = stableRef.trim();
    final cleanParagraph = paragraphText.trim();
    final cleanTitle = bookTitle.trim();
    final cleanLocation = locationText.trim();
    final cleanReferenceText = referenceText?.trim() ?? '';
    final cleanHref = sourceHref?.trim() ?? '';
    final cleanAnchorId = sourceAnchorId?.trim() ?? '';
    final cleanRelativePath = sourceRelativePath?.trim() ?? '';
    final cleanLibraryItemId = sourceLibraryItemId?.trim() ?? '';
    final cleanSelectedText =
        (selectedTextSnapshot?.trim().isNotEmpty == true
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

    final categoryArgs = <Object?>[];
    final categoryClause = _legacyCategoryWhereClause(
      'category',
      normalizedCategory,
      categoryArgs,
    );
    final exists = await db.query(
      tableName,
      columns: ['id'],
      where:
          '''
        user_id = ?
        AND tag = ?
        AND $categoryClause
        AND verse_ref = ?
      ''',
      whereArgs: [userId, normalizedTag, ...categoryArgs, cleanStableRef],
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
      if (normalizedCategory != null) 'category': normalizedCategory,
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
      if (selectedTextSnapshot != null &&
          selectedTextSnapshot.trim().isNotEmpty)
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

  String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  String _legacyMergeKey(Map<String, Object?> row) {
    final noteFormatJson = _s(row['note_format_json']).trim();
    final legacyMetadata = _parseLegacyMergeMetadata(noteFormatJson);
    if (legacyMetadata != null) {
      return legacyMetadata.identityKey;
    }

    final verseRef = _s(row['verse_ref']).trim().toLowerCase();
    final bookNumber = _i(row['book_number']) ?? 0;
    final chapterNumber = _i(row['chapter_number']) ?? 0;
    final verseNumber = _i(row['verse_number']) ?? 0;
    final verseEndNumber = _i(row['verse_end']) ?? verseNumber;
    final referenceCode = _normalizeReferenceCode(
      _s(row['reference_code']),
    ).toLowerCase();
    final noteText = _normalizeMergeText(_s(row['note_text']));
    final contentHtml = _normalizeMergeText(
      _stripHtml(_s(row['content_html'])),
    );
    final presentationSlideNumber = _i(row['presentation_slide_number']) ?? -1;
    final presentationSlideRegion = _normalizeMergeText(
      _s(row['presentation_slide_region']),
    );

    if (bookNumber > 0 && chapterNumber > 0 && verseNumber > 0) {
      return [
        'verse',
        bookNumber,
        chapterNumber,
        verseNumber,
        verseEndNumber,
        verseRef,
        referenceCode,
      ].join('|');
    }

    return [
      'note',
      verseRef,
      referenceCode,
      noteText,
      contentHtml,
      presentationSlideNumber,
      presentationSlideRegion,
    ].join('|');
  }

  String _mergeKey(Map<String, Object?> row) {
    final noteFormatJson = _s(row['note_format_json']).trim();
    final legacyMetadata = _parseLegacyMergeMetadata(noteFormatJson);
    if (legacyMetadata != null) {
      return legacyMetadata.identityKey;
    }

    final bookNumber = _i(row['book_id']) ?? _i(row['book_number']) ?? 0;
    final chapterNumber = _i(row['chapter']) ?? _i(row['chapter_number']) ?? 0;
    final verseStart = _i(row['verse_start']) ?? _i(row['verse_number']) ?? 0;
    final verseEnd = _i(row['verse_end']) ?? verseStart;
    final verseRef = _s(row['verse_ref']).trim().toLowerCase();
    final referenceCode = _normalizeReferenceCode(
      _s(row['reference_code']),
    ).toLowerCase();
    final noteText = _normalizeMergeText(
      _s(row['note_text']).isNotEmpty
          ? _s(row['note_text'])
          : _s(row['content_html']),
    );
    final presentationSlideNumber = _i(row['presentation_slide_number']) ?? -1;
    final presentationSlideRegion = _normalizeMergeText(
      _s(row['presentation_slide_region']),
    );
    final legacyGroupId = _s(row['legacy_group_id']).trim().toLowerCase();
    final legacyItemId = _s(row['legacy_item_id']).trim().toLowerCase();
    final legacyImportPackageId = _s(
      row['legacy_import_package_id'],
    ).trim().toLowerCase();

    if (bookNumber > 0 && chapterNumber > 0 && verseStart > 0) {
      return [
        'verse',
        bookNumber,
        chapterNumber,
        verseStart,
        verseEnd,
        verseRef,
        referenceCode,
      ].join('|');
    }

    return [
      'item',
      referenceCode,
      noteText,
      presentationSlideNumber,
      presentationSlideRegion,
      legacyGroupId,
      legacyItemId,
      legacyImportPackageId,
    ].join('|');
  }

  Future<String> debugTagReport(String tag, {String? category}) async {
    final normalizedTag = normalizeTagName(tag);
    final normalizedCategory = _normalizeCategoryName(category);
    if (normalizedTag.isEmpty) {
      return 'Tag report: empty tag';
    }

    await ensureSchema();
    final db = await _db();
    final summaries = await loadSummaries();
    final summaryMatches = summaries
        .where(
          (summary) => summary.tag.toLowerCase() == normalizedTag.toLowerCase(),
        )
        .toList(growable: false);
    final browseVisible = summaryMatches
        .where((summary) {
          final summaryCategory = summary.category?.trim() ?? '';
          if (normalizedCategory == null) {
            return summaryCategory.isEmpty;
          }
          return summaryCategory.toLowerCase() ==
              normalizedCategory.toLowerCase();
        })
        .toList(growable: false);
    final detailEntries = await loadEntries(
      normalizedTag,
      category: normalizedCategory,
    );

    final legacyRows = await db.query(
      tableName,
      columns: [
        'id',
        'tag',
        'category',
        'verse_ref',
        'book_number',
        'chapter_number',
        'verse_number',
        'reference_code',
        'sort_order',
        'created_at',
      ],
      where: 'tag = ?',
      whereArgs: [normalizedTag],
      orderBy: 'created_at ASC, id ASC',
    );
    final legacySamples = legacyRows
        .take(3)
        .map(
          (row) =>
              '${_s(row['verse_ref'])} @ ${_s(row['category']).isEmpty ? 'None' : _s(row['category'])}',
        )
        .toList(growable: false);

    final normalizedRows = await _loadNormalizedTagRows(
      db,
      normalizedTag: normalizedTag,
      category: normalizedCategory,
    );
    final normalizedSamples = <String>[];
    for (final row in normalizedRows.take(3)) {
      final groupId = row['id']?.toString() ?? '';
      if (groupId.isEmpty) continue;
      final items = await _loadNormalizedTagItemRows(db, [groupId]);
      normalizedSamples.add(
        '$groupId items=${items.length} parent=${_s(row['parent_group_id']).isEmpty ? 'None' : _s(row['parent_group_id'])}',
      );
    }

    final buffer = StringBuffer()
      ..writeln(
        'Tag report for $normalizedTag${normalizedCategory == null ? '' : ' @ $normalizedCategory'}',
      )
      ..writeln('Browse visible: ${browseVisible.isNotEmpty}')
      ..writeln('Detail entries: ${detailEntries.length}')
      ..writeln('Legacy rows: ${legacyRows.length}')
      ..writeln(
        'Legacy samples: ${legacySamples.isEmpty ? 'none' : legacySamples.join(' | ')}',
      )
      ..writeln('Normalized groups: ${normalizedRows.length}')
      ..writeln(
        'Normalized samples: ${normalizedSamples.isEmpty ? 'none' : normalizedSamples.join(' | ')}',
      );
    return buffer.toString();
  }

  _LegacyMergeMetadata? _parseLegacyMergeMetadata(String rawJson) {
    if (rawJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;

      final parts = <String>[];
      void addPart(String label, Object? value) {
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) return;
        parts.add('$label=$text');
      }

      addPart('stable_ref', decoded['stable_ref']);
      addPart('source_type', decoded['source_type']);
      addPart('source_library_item_id', decoded['source_library_item_id']);
      addPart('source_href', decoded['source_href']);
      addPart('source_anchor_id', decoded['source_anchor_id']);
      addPart('source_relative_path', decoded['source_relative_path']);
      addPart('source_spine_index', decoded['source_spine_index']);
      addPart('source_paragraph_index', decoded['source_paragraph_index']);
      addPart('source_page_number', decoded['source_page_number']);
      addPart('source_paragraph_number', decoded['source_paragraph_number']);
      addPart('selected_text_snapshot', decoded['selected_text_snapshot']);
      addPart('excerpt', decoded['excerpt']);
      if (parts.isEmpty) return null;
      return _LegacyMergeMetadata(identityKey: 'elibrary|${parts.join('|')}');
    } catch (_) {
      return null;
    }
  }

  String _normalizeMergeText(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
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
    final resolvedCategory =
        _normalizeCategoryName(category) ??
        await loadTagCategory(normalizedTag);
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

  Future<bool> _tagExists(String normalizedTag, {String? category}) async {
    final db = await _db();
    final normalizedCategory = _normalizeCategoryName(category);
    final rows = await db.query(
      tableName,
      columns: ['id'],
      where: normalizedCategory == null
          ? 'tag = ?'
          : 'tag = ? AND COALESCE(TRIM(category), \'\') = ?',
      whereArgs: normalizedCategory == null
          ? [normalizedTag]
          : [normalizedTag, normalizedCategory],
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
    String? category,
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
    DatabaseExecutor db, {
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

  Future<int> _nextNormalizedTagGroupSortOrder(DatabaseExecutor db) async {
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

  Future<HashTagImportResult?> importSharedListFromText(
    String text, {
    String? targetCategory,
  }) async {
    final parsed = tableName == 'dollar_tags'
        ? await _parseDollarSharedListFromText(text)
        : await _parseSharedListFromText(text);
    if (parsed == null || parsed.slides.isEmpty) return null;

    final normalizedTargetCategory =
        _normalizeCategoryName(targetCategory) ?? recentImportCategory;
    final sameTagCategories = await (() async {
      final summaries = await loadSummaries();
      return summaries
          .where((summary) => summary.tag == parsed.tag)
          .map((summary) => summary.category?.trim() ?? '')
          .where(
            (category) =>
                category.isNotEmpty &&
                category.toLowerCase() !=
                    normalizedTargetCategory.toLowerCase(),
          )
          .toSet()
          .toList(growable: false);
    })();
    if (sameTagCategories.isNotEmpty) {
      debugPrint(
        'Same tag exists in ${sameTagCategories.join(', ')}; '
        'import will create/update $normalizedTargetCategory copy.',
      );
    }
    if (tableName == 'dollar_tags') {
      return _importDollarSharedList(
        parsed,
        targetCategory: normalizedTargetCategory,
      );
    }
    return _importHashSharedList(
      parsed,
      targetCategory: normalizedTargetCategory,
    );
  }

  Future<bool> moveEntry({
    required String tag,
    required int entryId,
    required int delta,
    String? category,
  }) async {
    if (delta == 0) return false;
    final normalized = normalizeTagName(tag);
    if (normalized.isEmpty) return false;
    await ensureSchema();
    final db = await _db();
    final normalizedCategory = _normalizeCategoryName(category);
    return db.transaction((txn) async {
      final rows = await txn.query(
        tableName,
        columns: ['id'],
        where: normalizedCategory == null
            ? 'tag = ?'
            : 'tag = ? AND category = ?',
        whereArgs: normalizedCategory == null
            ? [normalized]
            : [normalized, normalizedCategory],
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
    if (kDebugMode) {
      debugPrint(
        '[ImportDiag] _splitSharedListBlocks → ${blocks.length} block(s) for tag="$tagName"',
      );
      for (var i = 0; i < blocks.length; i++) {
        final b = blocks[i];
        debugPrint(
          '[ImportDiag] block[$i]: lines=${b.length} first="${b.isNotEmpty ? b.first.trim() : ''}"',
        );
      }
    }
    final slides = <_ParsedSharedSlide>[];
    final seen = <String>{};

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      final slide = _parseSharedSlideBlock(block, bookLookup, tagName);
      final kind = slide.target != null
          ? 'scripture'
          : slide.elibraryMetadata != null
              ? 'elibrary'
              : slide.noteRef.startsWith('note:')
                  ? 'note'
                  : 'unsupported';
      if (kDebugMode) {
        debugPrint(
          '[ImportDiag] block[$i] → kind=$kind noteRef=${slide.noteRef.substring(0, slide.noteRef.length.clamp(0, 60))} contentLen=${slide.contentText.length}',
        );
      }
      final dedupeKey = slide.target?.verseRef ?? slide.noteRef;
      if (!seen.add(dedupeKey)) {
        if (kDebugMode) debugPrint('[ImportDiag] block[$i] DEDUPED (key already seen)');
        continue;
      }
      slides.add(slide);
    }

    if (kDebugMode) {
      debugPrint('[ImportDiag] _parseSharedListFromText → ${slides.length} unique slide(s)');
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
      r'^\s*([#\$@][^\s(]+)\s*(?:\(\s*\d+\s+(?:verse|slide|item)(?:s)?\s*\))?\s*$',
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
      // A blank line ends the current card. This must be checked BEFORE the
      // wrapper/header skip below, because _isSharedListWrapperLine() returns
      // true for empty strings — if the wrapper check ran first it would
      // `continue` past this break, silently merging blank-separated cards
      // (e.g. a trailing readable eLibrary block) into the preceding card.
      if (normalized.isEmpty) {
        if (current.isNotEmpty) {
          blocks.add(current);
          current = <String>[];
        }
        continue;
      }
      if (_isSharedListWrapperLine(normalized) ||
          _isSharedListHeaderLine(normalized, tagName)) {
        continue;
      }
      if (current.isNotEmpty && _isSharedSlideStartLine(normalized)) {
        blocks.add(current);
        current = <String>[];
      }
      current.add(line);
    }
    if (current.isNotEmpty) {
      blocks.add(current);
    }
    return blocks;
  }

  _ParsedSharedSlide _parseSharedSlideBlock(
    List<String> block,
    Map<String, (int, String)> bookLookup,
    String tagName,
  ) {
    if (block.isEmpty) {
      return _ParsedSharedSlide(
        target: null,
        contentText: '',
        noteRef: 'unsupported:${DateTime.now().microsecondsSinceEpoch}:empty',
      );
    }
    final firstLine = block.first.trim();
    if (firstLine.isEmpty) {
      final content = _extractSharedNoteContent(block, tagName);
      return _ParsedSharedSlide(
        target: null,
        contentText: content,
        noteRef: content.isNotEmpty
            ? 'note:${DateTime.now().microsecondsSinceEpoch}:${block.join('|')}'
            : 'unsupported:${DateTime.now().microsecondsSinceEpoch}:empty',
      );
    }
    if (_detectSharedListName([firstLine]) == firstLine) {
      final content = _extractSharedNoteContent(block, tagName);
      return _ParsedSharedSlide(
        target: null,
        contentText: content,
        noteRef: content.isNotEmpty
            ? 'note:${DateTime.now().microsecondsSinceEpoch}:${block.join('|')}'
            : 'unsupported:${DateTime.now().microsecondsSinceEpoch}:empty',
      );
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

    final studyBibleMetadata = _extractSharedStudyBibleMetadata(block);
    if (studyBibleMetadata != null) {
      final kind = _s(studyBibleMetadata['kind']).trim().toLowerCase();
      if (kind == 'note') {
        final noteText =
            _s(studyBibleMetadata['note_text']).trim().isNotEmpty
            ? _s(studyBibleMetadata['note_text']).trim()
            : _extractSharedNoteContent(block, tagName);
        final noteKey = _sharedStudyBibleMetadataKey(
          metadata: studyBibleMetadata,
          block: block,
          kind: kind,
        );
        return _ParsedSharedSlide(
          target: null,
          contentText: noteText,
          noteRef: 'note:$noteKey',
          studyBibleMetadata: studyBibleMetadata,
        );
      }
      if (kind == 'bible') {
        final bookNumber = _i(studyBibleMetadata['book_number']) ?? 0;
        final chapter = _i(studyBibleMetadata['chapter_number']) ?? 0;
        final verseStart = _i(studyBibleMetadata['verse_number']) ?? 0;
        if (bookNumber > 0 && chapter > 0 && verseStart > 0) {
          final verseEnd = _i(studyBibleMetadata['verse_end']) ?? verseStart;
          final verseRef =
              _s(studyBibleMetadata['verse_ref']).trim().isNotEmpty
              ? _s(studyBibleMetadata['verse_ref']).trim()
              : '$bookNumber:$chapter:$verseStart';
          return _ParsedSharedSlide(
            target: HashTagTarget(
              bookNumber: bookNumber,
              chapter: chapter,
              verse: verseStart,
              verseRef: verseRef,
              verseEnd: verseEnd > verseStart ? verseEnd : null,
              tokenNumber: _i(studyBibleMetadata['token_number']),
            ),
            contentText:
                _s(studyBibleMetadata['verse_text']).trim().isNotEmpty
                ? _s(studyBibleMetadata['verse_text']).trim()
                : _extractSharedVerseContent(block.skip(1).toList()),
            noteRef: verseRef,
            studyBibleMetadata: studyBibleMetadata,
          );
        }
      }
    }

    final elibraryMetadata = _extractSharedELibraryMetadata(block);
    if (elibraryMetadata != null) {
      final stableRef = _s(elibraryMetadata['stable_ref']).trim();
      // When stable_ref is absent the block can't be re-linked to the eLibrary,
      // so use a deterministic note: ref derived from content. This ensures the
      // slide routes to noteSlides and is never silently dropped.
      final noteRef = stableRef.isNotEmpty
          ? stableRef
          : 'note:${_sharedStudyBibleMetadataKey(metadata: elibraryMetadata, block: block, kind: 'elibrary_note')}';
      final content = _extractSharedELibraryContent(block);
      return _ParsedSharedSlide(
        target: null,
        contentText: content,
        noteRef: noteRef,
        elibraryMetadata: elibraryMetadata,
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

    return _ParsedSharedSlide(
      target: null,
      contentText: _extractSharedNoteContent(block, tagName),
      noteRef:
          'note:${DateTime.now().microsecondsSinceEpoch}:${block.join('|')}',
    );
  }

  Map<String, Object?>? _extractSharedStudyBibleMetadata(List<String> block) {
    for (final rawLine in block) {
      final line = rawLine.trim();
      if (!_isSharedStudyBibleMetadataLine(line)) continue;
      final rawJson = line.substring(line.indexOf(':') + 1).trim();
      if (rawJson.isEmpty) return null;
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic>) {
          return decoded.cast<String, Object?>();
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _isSharedStudyBibleMetadataLine(String line) {
    final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.toLowerCase().startsWith('studybible metadata:');
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
        (normalized.contains('slide') ||
            normalized.contains('verse') ||
            normalized.contains('item'));
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
    // A generated note label (e.g. "SoulSleep2 Note 1") is the first line of
    // the exported block but also appears at the start of the stored noteText,
    // producing duplication. Strip it — and its repeat if present — so the
    // body begins with the real content.
    var startIndex = 0;
    if (lines.isNotEmpty) {
      final firstTrimmed = lines[0].trim();
      if (RegExp(r'^[A-Za-z0-9 _-]+ Note \d+$').hasMatch(firstTrimmed)) {
        startIndex = 1;
        if (lines.length > 1 && lines[1].trim() == firstTrimmed) {
          startIndex = 2;
        }
      }
    }
    final contentLines = <String>[];
    var skipNotesMarker = true;
    for (var i = startIndex; i < lines.length; i++) {
      final rawLine = lines[i];
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
      if (normalized.toLowerCase() == 'note item') {
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

  String _extractSharedELibraryContent(List<String> lines) {
    final contentLines = <String>[];
    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      final normalized = line.trim();
      if (normalized.isEmpty) {
        contentLines.add('');
        continue;
      }
      if (_isSharedELibraryMetadataLine(normalized)) {
        continue;
      }
      contentLines.add(line);
    }
    return contentLines.join('\n').trim();
  }

  Map<String, Object?>? _extractSharedELibraryMetadata(List<String> block) {
    for (final rawLine in block) {
      final line = rawLine.trim();
      if (!_isSharedELibraryMetadataLine(line)) continue;
      final rawJson = line.substring(line.indexOf(':') + 1).trim();
      if (rawJson.isEmpty) return null;
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic> &&
            decoded['kind']?.toString() == 'elibrary_note') {
          return decoded.cast<String, Object?>();
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _isSharedELibraryMetadataLine(String line) {
    final normalized = line.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized.toLowerCase().startsWith('elibrary metadata:') ||
        normalized.toLowerCase().startsWith('eLibrary metadata:'.toLowerCase());
  }

  String _sharedStudyBibleMetadataKey({
    required Map<String, Object?> metadata,
    required List<String> block,
    required String kind,
  }) {
    final seedParts = <String>[
      kind,
      _s(metadata['note_key']),
      _s(metadata['reference_code']),
      _s(metadata['note_text']),
      _s(metadata['title']),
      _s(metadata['verse_ref']),
      _s(metadata['book_number']),
      _s(metadata['chapter_number']),
      _s(metadata['verse_number']),
      _s(metadata['verse_end']),
      _s(metadata['selected_text_snapshot']),
      _s(metadata['source_paragraph']),
      _s(metadata['excerpt']),
    ];
    final identifyingParts = seedParts
        .skip(1)
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    // When there are no identifying metadata fields, derive the key from block
    // content so two different human-readable blocks never share the same key.
    final rawSeed = identifyingParts.isEmpty
        ? block.join('|')
        : [kind, ...identifyingParts].join('|');
    return sha1.convert(utf8.encode(rawSeed)).toString().substring(0, 16);
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
    _ParsedSharedList parsed, {
    required String targetCategory,
  }) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = parsed.tag;
    if (normalizedTag.isEmpty) return null;
    final normalizedTargetCategory =
        _normalizeCategoryName(targetCategory) ?? recentImportCategory;

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
      final categoryArgs = <Object?>[];
      final categoryClause = _legacyCategoryWhereClause(
        'category',
        normalizedTargetCategory,
        categoryArgs,
      );
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND $categoryClause AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, ...categoryArgs, verseRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'category': normalizedTargetCategory,
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

    await saveTagCategory(
      normalizedTag,
      normalizedTargetCategory,
      currentCategory: normalizedTargetCategory,
      currentCategoryKnown: true,
    );
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
    _ParsedSharedList parsed, {
    required String targetCategory,
  }) async {
    await ensureSchema();
    final db = await _db();
    final userId = await ensureUserId();
    final normalizedTag = parsed.tag;
    if (normalizedTag.isEmpty) return null;
    final normalizedTargetCategory =
        _normalizeCategoryName(targetCategory) ?? recentImportCategory;

    final scriptureSlides = parsed.slides
        .where((slide) => slide.target != null)
        .toList(growable: false);
    final eLibrarySlides = parsed.slides
        .where((slide) => slide.elibraryMetadata != null)
        .toList(growable: false);
    final noteSlides = parsed.slides
        .where(
          (slide) =>
              slide.target == null &&
              slide.elibraryMetadata == null &&
              slide.noteRef.startsWith('note:'),
        )
        .toList(growable: false);
    // Slides that could not be routed to scripture/eLibrary/note.
    // Any with non-empty content are recovered as note cards below so no
    // readable block is silently dropped.
    final unsupportedSlides = parsed.slides
        .where(
          (slide) =>
              slide.target == null &&
              slide.elibraryMetadata == null &&
              !slide.noteRef.startsWith('note:'),
        )
        .toList(growable: false);
    if (kDebugMode) {
      debugPrint(
        '[ImportDiag] _importHashSharedList buckets: total=${parsed.slides.length} '
        'scripture=${scriptureSlides.length} eLibrary=${eLibrarySlides.length} '
        'note=${noteSlides.length} unsupported=${unsupportedSlides.length}',
      );
      for (var i = 0; i < parsed.slides.length; i++) {
        final s = parsed.slides[i];
        final bucket = s.target != null
            ? 'scripture'
            : s.elibraryMetadata != null
                ? 'elibrary'
                : s.noteRef.startsWith('note:')
                    ? 'note'
                    : 'unsupported';
        debugPrint(
          '[ImportDiag] slide[$i] bucket=$bucket noteRef=${s.noteRef.substring(0, s.noteRef.length.clamp(0, 60))}',
        );
      }
    }
    if (parsed.slides.isEmpty) return null;

    final failures = <HashTagImportFailure>[];
    var inserted = 0;
    var updatedExisting = 0;
    var skippedExisting = 0;
    var bibleImportedCount = 0;
    var eLibraryImportedCount = 0;
    var noteImportedCount = 0;
    var studyOrder = 1;
    final now = DateTime.now().millisecondsSinceEpoch;
    final warnings = <String>[];

    // Recover unsupported slides with readable content as note cards so no
    // block is silently dropped.
    final recoveredAsNotes = <_ParsedSharedSlide>[];
    for (final slide in unsupportedSlides) {
      final content = slide.contentText.trim();
      if (content.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[ImportDiag] unsupported slide recovered as note: noteRef=${slide.noteRef.substring(0, slide.noteRef.length.clamp(0, 60))}',
          );
        }
        recoveredAsNotes.add(slide);
      } else {
        failures.add(
          HashTagImportFailure(
            lineNumber: unsupportedSlides.indexOf(slide) + 1,
            reason: 'Unsupported card type (empty content)',
            line: slide.noteRef,
          ),
        );
      }
    }
    if (unsupportedSlides.isNotEmpty && recoveredAsNotes.length < unsupportedSlides.length) {
      final droppedCount = unsupportedSlides.length - recoveredAsNotes.length;
      warnings.add(
        'Skipped $droppedCount unsupported item${droppedCount == 1 ? '' : 's'} with no readable content.',
      );
    }

    for (final slide in [...noteSlides, ...recoveredAsNotes]) {
      final metadata = slide.studyBibleMetadata ?? const <String, Object?>{};
      final noteText =
          _s(metadata['note_text']).trim().isNotEmpty
          ? _s(metadata['note_text']).trim()
          : slide.contentText.trim();
      final referenceCode = _s(metadata['reference_code']).trim();
      final noteKey = _s(metadata['note_key']).trim().isNotEmpty
          ? _s(metadata['note_key']).trim()
          : _sharedStudyBibleMetadataKey(
              metadata: metadata,
              block: slide.contentText.isEmpty
                  ? [slide.noteRef]
                  : [slide.contentText],
              kind: 'note',
            );
      final verseRef = 'note:$noteKey';
      if (kDebugMode) {
        debugPrint(
          '[ImportDiag] note slide: first="${slide.contentText.split('\n').first.substring(0, slide.contentText.split('\n').first.length.clamp(0, 60))}" verseRef=$verseRef',
        );
      }
      final categoryArgs = <Object?>[];
      final categoryClause = _legacyCategoryWhereClause(
        'category',
        normalizedTargetCategory,
        categoryArgs,
      );
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND $categoryClause AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, ...categoryArgs, verseRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'category': normalizedTargetCategory,
        'verse_ref': verseRef,
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'reference_code':
            referenceCode.isNotEmpty ? referenceCode : null,
        'note_text': noteText.isNotEmpty ? noteText : null,
        'note_format_json': jsonEncode(
          <String, Object?>{
            if (metadata.isNotEmpty) ...metadata,
            'kind': 'studybible_note',
            'note_key': noteKey,
            if (referenceCode.isNotEmpty) 'reference_code': referenceCode,
            if (noteText.isNotEmpty) 'note_text': noteText,
          },
        ),
        'sort_order': studyOrder,
        'created_at': now + inserted + updatedExisting,
      };
      if (exists.isNotEmpty) {
        final existingId = (exists.first['id'] as num?)?.toInt();
        if (existingId != null) {
          if (kDebugMode) debugPrint('[ImportDiag] note UPDATE existing id=$existingId verseRef=$verseRef');
          await db.update(
            tableName,
            values,
            where: 'id = ?',
            whereArgs: [existingId],
          );
          updatedExisting++;
          noteImportedCount++;
          studyOrder++;
          continue;
        }
        skippedExisting++;
        if (kDebugMode) debugPrint('[ImportDiag] note SKIPPED (null id) verseRef=$verseRef');
        continue;
      }
      if (kDebugMode) debugPrint('[ImportDiag] note INSERT verseRef=$verseRef contentLen=${noteText.length}');
      await db.insert(tableName, values);
      inserted++;
      noteImportedCount++;
      studyOrder++;
    }

    for (final slide in scriptureSlides) {
      final target = slide.target!;
      String? importedNoteText;
      for (final contentLine in slide.contentText.split('\n')) {
        final trimmed = contentLine.trim();
        if (trimmed.toLowerCase().startsWith('note:')) {
          final noteContent = trimmed.substring(5).trim();
          if (noteContent.isNotEmpty) importedNoteText = noteContent;
          break;
        }
      }
      final categoryArgs = <Object?>[];
      final categoryClause = _legacyCategoryWhereClause(
        'category',
        normalizedTargetCategory,
        categoryArgs,
      );
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND $categoryClause AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, ...categoryArgs, target.verseRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'category': normalizedTargetCategory,
        'verse_ref': target.verseRef,
        'book_number': target.bookNumber,
        'chapter_number': target.chapter,
        'verse_number': target.verse,
        'token_number': target.tokenNumber,
        if (importedNoteText != null) 'note_text': importedNoteText,
        'sort_order': studyOrder,
        'created_at': now + inserted + updatedExisting,
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
          bibleImportedCount++;
          studyOrder++;
          continue;
        }
        skippedExisting++;
        continue;
      }
      await db.insert(tableName, values);
      inserted++;
      bibleImportedCount++;
      studyOrder++;
    }

    for (final slide in eLibrarySlides) {
      final metadata = slide.elibraryMetadata!;
      final stableRef = _s(metadata['stable_ref']).trim();
      final paragraphText =
          _s(metadata['selected_text_snapshot']).trim().isNotEmpty
          ? _s(metadata['selected_text_snapshot']).trim()
          : _s(metadata['source_paragraph']).trim().isNotEmpty
          ? _s(metadata['source_paragraph']).trim()
          : _s(metadata['excerpt']).trim().isNotEmpty
          ? _s(metadata['excerpt']).trim()
          : slide.contentText.trim();
      final citation = libraryUserFacingELibraryCitationText(
        sourceTitle: _s(metadata['source_title']),
        sourceTitleAcronym: _s(metadata['source_title_acronym']).isNotEmpty
            ? _s(metadata['source_title_acronym'])
            : null,
        sourceLocation: _s(metadata['source_location']).isNotEmpty
            ? _s(metadata['source_location'])
            : null,
        sourceReferenceText: _s(metadata['source_reference_text']).isNotEmpty
            ? _s(metadata['source_reference_text'])
            : null,
        fileName: _s(metadata['source_relative_path']).trim().isNotEmpty
            ? p.basename(_s(metadata['source_relative_path']))
            : null,
        relativePath: _s(metadata['source_relative_path']),
        pageCitation:
            _s(metadata['source_page_number']).trim().isNotEmpty &&
                _s(metadata['source_paragraph_number']).trim().isNotEmpty
            ? '${_s(metadata['source_page_number']).trim()}.${_s(metadata['source_paragraph_number']).trim()}'
            : null,
        paragraphIndex: _i(metadata['source_paragraph_index']),
      );
      final displayLabel = libraryUserFacingELibraryDisplayLabel(
        sourceTitle: _s(metadata['source_title']),
        sourceTitleAcronym: _s(metadata['source_title_acronym']).isNotEmpty
            ? _s(metadata['source_title_acronym'])
            : null,
        sourceLocation: _s(metadata['source_location']).isNotEmpty
            ? _s(metadata['source_location'])
            : null,
        sourceReferenceText: _s(metadata['source_reference_text']).isNotEmpty
            ? _s(metadata['source_reference_text'])
            : null,
        fileName: _s(metadata['source_relative_path']).trim().isNotEmpty
            ? p.basename(_s(metadata['source_relative_path']))
            : null,
        relativePath: _s(metadata['source_relative_path']),
        pageCitation:
            _s(metadata['source_page_number']).trim().isNotEmpty &&
                _s(metadata['source_paragraph_number']).trim().isNotEmpty
            ? '${_s(metadata['source_page_number']).trim()}.${_s(metadata['source_paragraph_number']).trim()}'
            : null,
        paragraphIndex: _i(metadata['source_paragraph_index']),
      );
      final effectiveStableRef = stableRef.isNotEmpty
          ? stableRef
          : 'elibrary:${_sharedStudyBibleMetadataKey(
              metadata: metadata,
              block: [
                slide.contentText,
                citation,
                displayLabel,
              ],
              kind: 'elibrary_note',
            )}';
      final effectiveParagraphText = paragraphText.isNotEmpty
          ? paragraphText
          : (displayLabel.trim().isNotEmpty ? displayLabel.trim() : citation);
      if (effectiveParagraphText.isEmpty) {
        failures.add(
          HashTagImportFailure(
            lineNumber: parsed.slides.indexOf(slide) + 1,
            reason: 'Missing eLibrary content',
            line: slide.contentText,
          ),
        );
        continue;
      }

      final categoryArgs = <Object?>[];
      final categoryClause = _legacyCategoryWhereClause(
        'category',
        normalizedTargetCategory,
        categoryArgs,
      );
      final exists = await db.query(
        tableName,
        columns: ['id'],
        where: 'user_id = ? AND tag = ? AND $categoryClause AND verse_ref = ?',
        whereArgs: [userId, normalizedTag, ...categoryArgs, effectiveStableRef],
        limit: 1,
      );
      final values = <String, Object?>{
        'user_id': userId,
        'tag': normalizedTag,
        'category': normalizedTargetCategory,
        'verse_ref': effectiveStableRef,
        'book_number': 0,
        'chapter_number': 0,
        'verse_number': 0,
        'token_number': null,
        'reference_code': citation.isNotEmpty ? citation : null,
        'note_text': effectiveParagraphText,
        'note_format_json': jsonEncode(metadata),
        'sort_order': studyOrder,
        'created_at': now + inserted + updatedExisting,
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
          eLibraryImportedCount++;
          studyOrder++;
          continue;
        }
        skippedExisting++;
        continue;
      }
      await db.insert(tableName, values);
      inserted++;
      eLibraryImportedCount++;
      studyOrder++;
    }

    await saveTagCategory(
      normalizedTag,
      normalizedTargetCategory,
      currentCategory: normalizedTargetCategory,
      currentCategoryKnown: true,
    );
    return HashTagImportResult(
      tag: normalizedTag,
      parsedCount: parsed.slides.length,
      insertedCount: inserted,
      updatedExistingCount: updatedExisting,
      skippedExistingCount: skippedExisting,
      failedCount: failures.length,
      failures: failures,
      bibleImportedCount: bibleImportedCount,
      eLibraryImportedCount: eLibraryImportedCount,
      noteImportedCount: noteImportedCount,
      unsupportedCount: unsupportedSlides.length,
      warnings: warnings,
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

class _LegacyMergeMetadata {
  const _LegacyMergeMetadata({required this.identityKey});

  final String identityKey;
}
