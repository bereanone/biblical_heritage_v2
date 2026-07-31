import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/user_database.dart';
import 'tag_models.dart';
import 'tag_repository.dart';

class LegacyTagAdapter implements TagRepository {
  LegacyTagAdapter({TagDatabaseProvider? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => UserDatabase.instance.database);

  final TagDatabaseProvider _databaseProvider;

  static const _defaultSettingKeys = <TagMode, String>{
    TagMode.quick: 'tags.default.hash',
    TagMode.studyList: 'tags.default.dollar',
  };

  static const _categoryPrefixes = <TagMode, String>{
    TagMode.quick: 'tags.category.',
    TagMode.studyList: 'tags.category.dollar.',
  };

  static const _tableNames = <TagMode, String>{
    TagMode.quick: 'hash_tags',
    TagMode.studyList: 'dollar_tags',
  };

  @override
  Future<List<TagGroup>> loadGroups({required TagMode mode}) async {
    final state = await _loadState(mode);
    return state.groups;
  }

  @override
  Future<TagGroup?> loadDefaultGroup({required TagMode mode}) async {
    final state = await _loadState(mode);
    return state.groupsByName[state.defaultTag];
  }

  @override
  Future<List<TagItem>> loadItems({
    required TagMode mode,
    required String groupId,
  }) async {
    final state = await _loadState(mode);
    final group = state.groupsById[groupId];
    if (group == null) return const <TagItem>[];

    final groupIds = group.isCategoryGroup
        ? _descendantLeafGroupIds(groupId, state.groupsById)
        : <String>{groupId};

    final selectedTags = <String>{
      for (final candidate in groupIds)
        state.groupsById[candidate]?.source?.legacyTag ?? '',
    }..removeWhere((value) => value.trim().isEmpty);

    final items = state.items
        .where((item) => selectedTags.contains(item.source?.legacyTag))
        .toList(growable: false);
    return items;
  }

  @override
  Future<List<TagItemMedia>> loadMedia({
    required TagMode mode,
    required String itemId,
  }) async {
    final state = await _loadState(mode);
    return state.mediaByItemId[itemId] ?? const <TagItemMedia>[];
  }

  Future<_LegacyTagState> _loadState(TagMode mode) async {
    final db = await _databaseProvider();
    final tableName = _tableNames[mode]!;
    final defaultTag = await _loadDefaultTag(db, mode);
    final rows = await db.query(
      tableName,
      where: "COALESCE(trashed_at_utc, '') = ''",
      orderBy: 'created_at ASC, id ASC',
    );
    final rowsByTag = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final tag = _readString(row['tag']);
      if (tag.isEmpty) continue;
      rowsByTag.putIfAbsent(tag, () => <Map<String, Object?>>[]).add(row);
    }

    final settingsCategories = await _loadCategorySettings(
      db,
      mode,
      rowsByTag.keys.toList(growable: false),
    );
    final defaultGroupId = defaultTag == null
        ? null
        : _buildTagGroupId(mode, defaultTag);

    final tagGroups = <TagGroup>[];
    final groupsById = <String, TagGroup>{};
    final groupsByName = <String, TagGroup>{};
    final categoryGroups = <String, TagGroup>{};
    final items = <TagItem>[];
    final mediaByItemId = <String, List<TagItemMedia>>{};

    final categorySortOrders = <String, int>{};

    for (final entry in rowsByTag.entries) {
      final tag = entry.key;
      final groupId = _buildTagGroupId(mode, tag);
      final legacyCategory =
          _firstNonEmpty([
            for (final row in entry.value) _readString(row['category']),
          ]) ??
          settingsCategories[tag];
      final parentGroupId = legacyCategory == null || legacyCategory.isEmpty
          ? null
          : _buildCategoryGroupId(mode, legacyCategory);

      final groupSync = _syncFromRows(entry.value);
      final groupSource = _sourceFromRows(
        tableName: tableName,
        rows: entry.value,
        legacyTag: tag,
        legacyCategory: legacyCategory,
      );
      final group = TagGroup(
        id: groupId,
        mode: mode,
        name: tag,
        description: null,
        parentGroupId: parentGroupId,
        sortOrder: _groupSortOrder(entry.value),
        isCategoryGroup: false,
        isDefault: defaultGroupId == groupId,
        sync: groupSync,
        source: groupSource,
      );
      tagGroups.add(group);
      groupsById[group.id] = group;
      groupsByName[group.name] = group;

      if (legacyCategory != null && legacyCategory.trim().isNotEmpty) {
        categorySortOrders.putIfAbsent(
          legacyCategory,
          () => _groupSortOrder(entry.value),
        );
      }

      for (final row in entry.value) {
        final item = _itemFromRow(
          mode: mode,
          tableName: tableName,
          row: row,
          groupId: groupId,
          tag: tag,
          legacyCategory: legacyCategory,
        );
        items.add(item);
        final extractedMedia = _extractMediaFromRow(
          mode: mode,
          tableName: tableName,
          row: row,
          itemId: item.id,
          legacyTag: tag,
          legacyCategory: legacyCategory,
        );
        if (extractedMedia.isNotEmpty) {
          mediaByItemId[item.id] = extractedMedia;
        }
      }
    }

    for (final entry in categorySortOrders.entries) {
      final categoryName = entry.key;
      final categoryId = _buildCategoryGroupId(mode, categoryName);
      final categoryGroup = TagGroup(
        id: categoryId,
        mode: mode,
        name: categoryName,
        description: null,
        parentGroupId: null,
        sortOrder: entry.value,
        isCategoryGroup: true,
        isDefault: false,
        sync: null,
        source: TagImportSource(
          legacyTable: tableName,
          legacyCategory: categoryName,
        ),
      );
      categoryGroups[categoryId] = categoryGroup;
      groupsById[categoryId] = categoryGroup;
      groupsByName.putIfAbsent(categoryName, () => categoryGroup);
    }

    final groups = <TagGroup>[...categoryGroups.values, ...tagGroups]
      ..sort((a, b) {
        final orderCompare = a.sortOrder.compareTo(b.sortOrder);
        if (orderCompare != 0) return orderCompare;
        final categoryCompare = a.isCategoryGroup == b.isCategoryGroup
            ? 0
            : (a.isCategoryGroup ? -1 : 1);
        if (categoryCompare != 0) return categoryCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return _LegacyTagState(
      mode: mode,
      tableName: tableName,
      defaultTag: defaultTag,
      groups: groups,
      groupsById: groupsById,
      groupsByName: groupsByName,
      items: items,
      mediaByItemId: mediaByItemId,
    );
  }

  Future<String?> _loadDefaultTag(Database db, TagMode mode) async {
    final key = _defaultSettingKeys[mode]!;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = _readString(rows.first['value']);
    return value.isEmpty ? null : value;
  }

  Future<Map<String, String>> _loadCategorySettings(
    Database db,
    TagMode mode,
    List<String> tags,
  ) async {
    final prefix = _categoryPrefixes[mode]!;
    final categories = <String, String>{};
    for (final tag in tags) {
      final rows = await db.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['$prefix$tag'],
        limit: 1,
      );
      if (rows.isEmpty) continue;
      final value = _readString(rows.first['value']);
      if (value.isEmpty) continue;
      categories[tag] = value;
    }
    return categories;
  }

  TagItem _itemFromRow({
    required TagMode mode,
    required String tableName,
    required Map<String, Object?> row,
    required String groupId,
    required String tag,
    required String? legacyCategory,
  }) {
    final bookNumber = _intValueNullable(row['book_number']);
    final chapter = _intValueNullable(row['chapter_number']);
    final verse = _intValueNullable(row['verse_number']);
    final verseRef = _readString(row['verse_ref']);
    final tokenNumber = _intValueNullable(row['token_number']);
    final createdAt =
        _parseTimestamp(row['created_at_utc']) ??
        _parseTimestamp(row['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt = _parseTimestamp(row['updated_at_utc']) ?? createdAt;
    final deletedAt =
        _parseTimestamp(row['deleted_at_utc']) ??
        _parseTimestamp(row['deleted_at']);
    final noteText = switch (mode) {
      TagMode.quick => _readStringOrNull(row['note_text']),
      TagMode.studyList => _readStringOrNull(row['content_html']),
    };
    final noteOnly =
        (bookNumber == null || bookNumber == 0) &&
        (chapter == null || chapter == 0) &&
        (verse == null || verse == 0) &&
        (verseRef.isEmpty || verseRef.startsWith('note:'));
    final anchor = noteOnly
        ? const TagAnchor.noteOnly()
        : TagAnchor.verseReference(
            bookNumber: bookNumber ?? 0,
            chapter: chapter ?? 0,
            verseStart: verse ?? 0,
            verseEnd: verse ?? 0,
            tokenStart: tokenNumber,
            tokenEnd: tokenNumber,
            verseRef: verseRef.isEmpty
                ? '${bookNumber ?? 0}:${chapter ?? 0}:${verse ?? 0}'
                : verseRef,
          );
    final itemId = _buildItemId(mode, tableName, row);
    return TagItem(
      id: itemId,
      groupId: groupId,
      kind: noteOnly ? TagItemKind.noteOnly : TagItemKind.verseReference,
      anchor: anchor,
      noteText: noteText,
      sortOrder:
          _intValueNullable(row['sort_order']) ??
          _intValueNullable(row['study_order']) ??
          _intValueNullable(row['created_at']) ??
          0,
      sync: TagSyncMetadata(
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        deviceId: _readStringOrNull(row['device_id']),
        revision: _intValueNullable(row['revision']) ?? 1,
        syncStatus: _readString(row['sync_status']).isEmpty
            ? 'pending'
            : _readString(row['sync_status']),
        lastSyncedAt: _parseTimestamp(row['last_synced_at']),
        changeId: _readStringOrNull(row['change_id']),
      ),
      source: TagImportSource(
        legacyTable: tableName,
        legacyRowId: _readString(row['id']),
        legacyTag: tag,
        legacyCategory: legacyCategory,
        legacyImportPackageId: _readStringOrNull(
          row['legacy_import_package_id'],
        ),
        deviceId: _readStringOrNull(row['device_id']),
        sourceDeviceName: _readStringOrNull(row['source_device_name']),
        importedAt: createdAt,
      ),
    );
  }

  List<TagItemMedia> _extractMediaFromRow({
    required TagMode mode,
    required String tableName,
    required Map<String, Object?> row,
    required String itemId,
    required String legacyTag,
    required String? legacyCategory,
  }) {
    if (mode != TagMode.studyList) return const <TagItemMedia>[];
    final html = _readStringOrNull(row['content_html']);
    if (html == null || html.trim().isEmpty) return const <TagItemMedia>[];

    final refs = <String>[];
    final regex = RegExp(
      r'''(?:src|href)=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(html)) {
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty || raw.startsWith('data:')) continue;
      refs.add(_normalizeMediaPath(raw));
    }

    final sync = TagSyncMetadata(
      createdAt:
          _parseTimestamp(row['created_at_utc']) ??
          _parseTimestamp(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          _parseTimestamp(row['updated_at_utc']) ??
          _parseTimestamp(row['created_at_utc']) ??
          _parseTimestamp(row['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deletedAt:
          _parseTimestamp(row['deleted_at_utc']) ??
          _parseTimestamp(row['deleted_at']),
      deviceId: _readStringOrNull(row['device_id']),
      revision: _intValueNullable(row['revision']) ?? 1,
      syncStatus: _readString(row['sync_status']).isEmpty
          ? 'pending'
          : _readString(row['sync_status']),
      lastSyncedAt: _parseTimestamp(row['last_synced_at']),
      changeId: _readStringOrNull(row['change_id']),
    );

    final source = TagImportSource(
      legacyTable: tableName,
      legacyRowId: _readString(row['id']),
      legacyTag: legacyTag,
      legacyCategory: legacyCategory,
      legacyImportPackageId: _readStringOrNull(row['legacy_import_package_id']),
      deviceId: _readStringOrNull(row['device_id']),
      sourceDeviceName: _readStringOrNull(row['source_device_name']),
      importedAt: sync.createdAt,
    );

    return [
      for (var index = 0; index < refs.length; index++)
        TagItemMedia(
          id: _buildMediaId(mode, tableName, row, index),
          itemId: itemId,
          mediaType: 'image',
          relativePath: refs[index],
          caption: null,
          fileHash: null,
          fileSize: null,
          sortOrder: index + 1,
          sync: sync,
          source: source,
        ),
    ];
  }

  TagSyncMetadata? _syncFromRows(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return null;
    final createdAt =
        _parseTimestamp(rows.first['created_at_utc']) ??
        _parseTimestamp(rows.first['created_at']) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final updatedAt =
        _parseTimestamp(rows.last['updated_at_utc']) ??
        _parseTimestamp(rows.last['created_at_utc']) ??
        _parseTimestamp(rows.last['created_at']) ??
        createdAt;
    final deletedAt =
        _parseTimestamp(rows.last['deleted_at_utc']) ??
        _parseTimestamp(rows.last['deleted_at']);
    return TagSyncMetadata(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      deviceId: _readStringOrNull(rows.last['device_id']),
      revision: _intValueNullable(rows.last['revision']) ?? 1,
      syncStatus: _readString(rows.last['sync_status']).isEmpty
          ? 'pending'
          : _readString(rows.last['sync_status']),
      lastSyncedAt: _parseTimestamp(rows.last['last_synced_at']),
      changeId: _readStringOrNull(rows.last['change_id']),
    );
  }

  TagImportSource _sourceFromRows({
    required String tableName,
    required List<Map<String, Object?>> rows,
    required String legacyTag,
    required String? legacyCategory,
  }) {
    return TagImportSource(
      legacyTable: tableName,
      legacyRowId: rows.isEmpty ? null : _readString(rows.first['id']),
      legacyTag: legacyTag,
      legacyCategory: legacyCategory,
      legacyImportPackageId: rows.isEmpty
          ? null
          : _readStringOrNull(rows.first['legacy_import_package_id']),
      deviceId: rows.isEmpty
          ? null
          : _readStringOrNull(rows.first['device_id']),
      sourceDeviceName: rows.isEmpty
          ? null
          : _readStringOrNull(rows.first['source_device_name']),
      importedAt: rows.isEmpty
          ? null
          : (_parseTimestamp(rows.first['created_at_utc']) ??
                _parseTimestamp(rows.first['created_at'])),
    );
  }

  int _groupSortOrder(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    final values = rows
        .map(
          (row) =>
              _intValueNullable(row['sort_order']) ??
              _intValueNullable(row['created_at']) ??
              0,
        )
        .toList(growable: false);
    values.sort();
    return values.first;
  }

  Set<String> _descendantLeafGroupIds(
    String groupId,
    Map<String, TagGroup> groupsById,
  ) {
    final descendants = <String>{};
    void visit(String parentId) {
      for (final group in groupsById.values) {
        if (group.parentGroupId != parentId) continue;
        if (group.isCategoryGroup) {
          visit(group.id);
        } else {
          descendants.add(group.id);
        }
      }
    }

    visit(groupId);
    return descendants;
  }

  String _buildTagGroupId(TagMode mode, String tag) {
    return 'legacy-tag-${mode.name}-${_slug(tag)}';
  }

  String _buildCategoryGroupId(TagMode mode, String category) {
    return 'legacy-category-${mode.name}-${_slug(category)}';
  }

  String _buildItemId(
    TagMode mode,
    String tableName,
    Map<String, Object?> row,
  ) {
    return 'legacy-item-${mode.name}-${_slug(tableName)}-${_slug(_readString(row['id']))}';
  }

  String _buildMediaId(
    TagMode mode,
    String tableName,
    Map<String, Object?> row,
    int index,
  ) {
    return 'legacy-media-${mode.name}-${_slug(tableName)}-${_slug(_readString(row['id']))}-$index';
  }

  String _normalizeMediaPath(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return cleaned;
    if (cleaned.startsWith('file://')) {
      return cleaned.replaceFirst('file://', '');
    }
    if (p.isAbsolute(cleaned)) {
      return p.basename(cleaned);
    }
    return p.normalize(cleaned);
  }

  String _slug(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return 'item';
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  int? _intValueNullable(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _readString(Object? value) => value?.toString().trim() ?? '';

  String? _readStringOrNull(Object? value) {
    final text = _readString(value);
    return text.isEmpty ? null : text;
  }

  String? _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsedInt = int.tryParse(text);
    if (parsedInt != null) {
      return DateTime.fromMillisecondsSinceEpoch(parsedInt, isUtc: true);
    }
    return DateTime.tryParse(text);
  }
}

class _LegacyTagState {
  const _LegacyTagState({
    required this.mode,
    required this.tableName,
    required this.defaultTag,
    required this.groups,
    required this.groupsById,
    required this.groupsByName,
    required this.items,
    required this.mediaByItemId,
  });

  final TagMode mode;
  final String tableName;
  final String? defaultTag;
  final List<TagGroup> groups;
  final Map<String, TagGroup> groupsById;
  final Map<String, TagGroup> groupsByName;
  final List<TagItem> items;
  final Map<String, List<TagItemMedia>> mediaByItemId;
}
