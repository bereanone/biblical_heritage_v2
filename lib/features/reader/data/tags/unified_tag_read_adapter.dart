import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/database/user_database.dart';
import 'tag_models.dart';
import 'tag_repository.dart';
import 'unified_tag_models.dart';

class UnifiedTagReadAdapter {
  UnifiedTagReadAdapter({TagDatabaseProvider? databaseProvider})
    : _databaseProvider =
          databaseProvider ?? (() => UserDatabase.instance.database);

  final TagDatabaseProvider _databaseProvider;

  Future<UnifiedTagReadSnapshot> loadSnapshot() async {
    final db = await _databaseProvider();
    final hashDefaults = await _loadDefaultTags(db, TagMode.quick);
    final dollarDefaults = await _loadDefaultTags(db, TagMode.studyList);
    final categoryNames = await _loadCategoryNames(db);

    final chains = <UnifiedTagChain>[];
    chains.addAll(
      await _loadLegacyChains(
        db: db,
        tableName: 'hash_tags',
        storageKind: UnifiedTagStorageKind.hash,
        defaultTag: hashDefaults,
      ),
    );
    chains.addAll(
      await _loadLegacyChains(
        db: db,
        tableName: 'dollar_tags',
        storageKind: UnifiedTagStorageKind.dollar,
        defaultTag: dollarDefaults,
      ),
    );
    chains.addAll(
      await _loadUnifiedChains(
        db: db,
        categoryNames: categoryNames,
        hashDefault: hashDefaults,
        dollarDefault: dollarDefaults,
      ),
    );

    chains.sort((left, right) {
      final kindCompare = left.storageKind.index.compareTo(
        right.storageKind.index,
      );
      if (kindCompare != 0) return kindCompare;
      final categoryCompare = (left.categoryName ?? '').toLowerCase().compareTo(
        (right.categoryName ?? '').toLowerCase(),
      );
      if (categoryCompare != 0) return categoryCompare;
      return left.name.toLowerCase().compareTo(right.name.toLowerCase());
    });

    return UnifiedTagReadSnapshot(
      chains: List.unmodifiable(chains),
      loadedAt: DateTime.now().toUtc(),
    );
  }

  Future<List<UnifiedTagChain>> loadChains() async {
    return (await loadSnapshot()).chains;
  }

  Future<UnifiedTagChain?> loadChainById(String chainId) async {
    final snapshot = await loadSnapshot();
    for (final chain in snapshot.chains) {
      if (chain.id == chainId) return chain;
    }
    return null;
  }

  Future<List<UnifiedTagChainItem>> loadItemsForChain(String chainId) async {
    final chain = await loadChainById(chainId);
    return chain?.items ?? const <UnifiedTagChainItem>[];
  }

  Future<List<UnifiedTagChain>> _loadLegacyChains({
    required Database db,
    required String tableName,
    required UnifiedTagStorageKind storageKind,
    required Set<String> defaultTag,
  }) async {
    final rows = await db.query(tableName, orderBy: 'created_at ASC, id ASC');
    final rowsByTag = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final tag = _normalizeTagName(row['tag']?.toString() ?? '', storageKind);
      rowsByTag.putIfAbsent(tag, () => <Map<String, Object?>>[]).add(row);
    }

    final chains = <UnifiedTagChain>[];
    for (final entry in rowsByTag.entries) {
      final tag = entry.key;
      final items = <UnifiedTagChainItem>[
        for (final row in entry.value)
          _legacyItemFromRow(
            row: row,
            tableName: tableName,
            storageKind: storageKind,
            tagName: tag,
          ),
      ]..sort(_compareItemsByOrder);

      final firstRow = entry.value.isNotEmpty
          ? entry.value.first
          : const <String, Object?>{};
      chains.add(
        UnifiedTagChain(
          id: 'legacy:${storageKind.name}:${Uri.encodeComponent(tag)}',
          name: tag,
          storageKind: storageKind,
          categoryName: _readString(firstRow['category']),
          isDefault: defaultTag.contains(tag),
          legacyTable: tableName,
          legacyTagName: tag,
          legacyGroupId: null,
          legacyImportPackageId: _readStringOrNull(
            firstRow['legacy_import_package_id'],
          ),
          createdAt:
              _parseTimestamp(firstRow['created_at_utc']) ??
              _parseTimestamp(firstRow['created_at']),
          updatedAt:
              _parseTimestamp(firstRow['updated_at_utc']) ??
              _parseTimestamp(firstRow['created_at_utc']) ??
              _parseTimestamp(firstRow['created_at']),
          deletedAt:
              _parseTimestamp(firstRow['deleted_at_utc']) ??
              _parseTimestamp(firstRow['deleted_at']),
          rawFields: _asUnmodifiableMap({'table_name': tableName, 'tag': tag}),
          items: List.unmodifiable(items),
        ),
      );
    }

    return chains;
  }

  Future<List<UnifiedTagChain>> _loadUnifiedChains({
    required Database db,
    required Map<String, String> categoryNames,
    required Set<String> hashDefault,
    required Set<String> dollarDefault,
  }) async {
    final groupRows = await db.query(
      'tag_groups',
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    if (groupRows.isEmpty) return const <UnifiedTagChain>[];

    final mediaByItemId = await _loadUnifiedMediaByItemId(db);
    final itemsByGroupId = <String, List<Map<String, Object?>>>{};
    final itemRows = await db.query(
      'tag_items',
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    for (final row in itemRows) {
      final groupId = _readString(row['tag_group_id']);
      if (groupId.isEmpty) continue;
      itemsByGroupId
          .putIfAbsent(groupId, () => <Map<String, Object?>>[])
          .add(row);
    }

    final chains = <UnifiedTagChain>[];
    for (final groupRow in groupRows) {
      final groupId = _readString(groupRow['id']);
      if (groupId.isEmpty) continue;
      final groupName = _readString(groupRow['name']);
      final tagKind = _readString(groupRow['tag_kind']);
      final storageKind = _storageKindFromTagKind(tagKind);
      final parentId = _readStringOrNull(groupRow['parent_group_id']);
      final parentName = parentId == null ? null : categoryNames[parentId];
      final isDefault = switch (storageKind) {
        UnifiedTagStorageKind.hash => hashDefault.contains(groupName),
        UnifiedTagStorageKind.dollar => dollarDefault.contains(groupName),
        UnifiedTagStorageKind.unified =>
          hashDefault.contains(groupName) || dollarDefault.contains(groupName),
        UnifiedTagStorageKind.unknownLegacy => false,
      };

      final itemRowsForGroup =
          itemsByGroupId[groupId] ?? const <Map<String, Object?>>[];
      final items = [
        for (final row in itemRowsForGroup)
          _unifiedItemFromRow(
            row: row,
            groupRow: groupRow,
            mediaByItemId: mediaByItemId,
          ),
      ]..sort(_compareItemsByOrder);

      chains.add(
        UnifiedTagChain(
          id: 'unified:$groupId',
          name: groupName,
          storageKind: UnifiedTagStorageKind.unified,
          categoryId: parentId,
          categoryName: parentName,
          isDefault: isDefault,
          legacyTable: null,
          legacyTagName: groupName,
          legacyTagId: groupId,
          legacyGroupId: _readStringOrNull(groupRow['legacy_group_id']),
          legacyImportPackageId: _readStringOrNull(
            groupRow['legacy_import_package_id'],
          ),
          createdAt: _parseTimestamp(groupRow['created_at']),
          updatedAt: _parseTimestamp(groupRow['updated_at']),
          deletedAt: _parseTimestamp(groupRow['deleted_at']),
          rawFields: _asUnmodifiableMap(groupRow),
          items: List.unmodifiable(items),
        ),
      );
    }

    return chains;
  }

  UnifiedTagChainItem _legacyItemFromRow({
    required Map<String, Object?> row,
    required String tableName,
    required UnifiedTagStorageKind storageKind,
    required String tagName,
  }) {
    final rowId = _readString(row['id']);
    final bookNumber = _int(row['book_number']);
    final chapter = _int(row['chapter_number']);
    final verseStart = _int(row['verse_number']);
    final verseRef = _readString(row['verse_ref']);
    final sortOrder =
        _int(row['sort_order']) ??
        _int(row['study_order']) ??
        _int(row['created_at']) ??
        0;
    final noteText = _readStringOrNull(row['note_text']);
    final contentHtml = _readStringOrNull(row['content_html']);
    final noteFormatJson = _readStringOrNull(row['note_format_json']);
    final media = _legacyMediaForRow(
      itemId: rowId,
      tableName: tableName,
      tagName: tagName,
      contentHtml: contentHtml,
    );
    final bibleAnchor = _legacyBibleAnchor(
      row: row,
      bookNumber: bookNumber,
      chapter: chapter,
      verseStart: verseStart,
      verseRef: verseRef,
    );
    final elibraryAnchor = _legacyELibraryAnchor(
      noteFormatJson: noteFormatJson,
      contentHtml: contentHtml,
    );
    final isNoteOnly = bibleAnchor == null && verseRef.startsWith('note:');
    final layoutHint = UnifiedTagLayoutHint(
      presentationSlideNumber: _int(row['presentation_slide_number']),
      presentationSlideRegion: _readStringOrNull(
        row['presentation_slide_region'],
      ),
      rawFields: _asUnmodifiableMap({
        'presentation_slide_number': row['presentation_slide_number'],
        'presentation_slide_region': row['presentation_slide_region'],
      }),
    );
    final itemType = _legacyItemType(
      bibleAnchor: bibleAnchor,
      elibraryAnchor: elibraryAnchor,
      noteText: noteText,
      contentHtml: contentHtml,
      media: media,
      isNoteOnly: isNoteOnly,
      verseRef: verseRef,
    );

    return UnifiedTagChainItem(
      id: 'legacy:${storageKind.name}:$tableName:$rowId',
      chainId: 'legacy:${storageKind.name}:${Uri.encodeComponent(tagName)}',
      storageKind: storageKind,
      sourceType: _sourceTypeForItemType(itemType),
      itemType: itemType,
      sortOrder: sortOrder,
      displayTitle: _legacyDisplayTitle(
        itemType: itemType,
        bibleAnchor: bibleAnchor,
        elibraryAnchor: elibraryAnchor,
        tagName: tagName,
        noteText: noteText,
      ),
      textSnapshot: _legacyTextSnapshot(
        itemType: itemType,
        noteText: noteText,
        contentHtml: contentHtml,
        elibraryAnchor: elibraryAnchor,
      ),
      noteText: noteText,
      htmlContent: contentHtml,
      media: media,
      bibleAnchor: bibleAnchor,
      elibraryAnchor: elibraryAnchor,
      layoutHint: layoutHint,
      legacyTable: tableName,
      legacyTagName: tagName,
      legacyItemId: rowId.isEmpty ? null : rowId,
      legacyImportPackageId: _readStringOrNull(row['legacy_import_package_id']),
      createdAt:
          _parseTimestamp(row['created_at_utc']) ??
          _parseTimestamp(row['created_at']),
      updatedAt:
          _parseTimestamp(row['updated_at_utc']) ??
          _parseTimestamp(row['created_at_utc']) ??
          _parseTimestamp(row['created_at']),
      deletedAt:
          _parseTimestamp(row['deleted_at_utc']) ??
          _parseTimestamp(row['deleted_at']),
      rawFields: _asUnmodifiableMap(row),
    );
  }

  UnifiedTagChainItem _unifiedItemFromRow({
    required Map<String, Object?> row,
    required Map<String, Object?> groupRow,
    required Map<String, List<UnifiedTagMedia>> mediaByItemId,
  }) {
    final rowId = _readString(row['id']);
    final bookNumber = _int(row['book_id']);
    final chapter = _int(row['chapter']);
    final verseStart = _int(row['verse_start']);
    final verseEnd = _int(row['verse_end']);
    final noteFormatJson = _readStringOrNull(row['note_format_json']);
    final legacyDollarPayload = _parseLegacyDollarNotePayload(noteFormatJson);
    final noteText =
        _readStringOrNull(row['note_text']) ?? legacyDollarPayload?.noteText;
    final referenceCode = _readStringOrNull(row['reference_code']);
    final sortOrder = _int(row['sort_order']) ?? _int(row['created_at']) ?? 0;
    final media = List<UnifiedTagMedia>.unmodifiable(
      mediaByItemId[rowId] ?? const <UnifiedTagMedia>[],
    );
    final elibraryAnchor =
        _unifiedELibraryAnchorFromNoteFormat(noteFormatJson) ??
        _unifiedELibraryAnchorFromNoteFormat(
          legacyDollarPayload?.legacyNoteFormatJson,
        );
    final htmlContent = legacyDollarPayload?.contentHtml;
    final bibleAnchor =
        (bookNumber != null &&
            chapter != null &&
            verseStart != null &&
            bookNumber > 0 &&
            chapter > 0 &&
            verseStart > 0)
        ? UnifiedTagBibleAnchor(
            bookNumber: bookNumber,
            chapter: chapter,
            verseStart: verseStart,
            verseEnd: verseEnd != null && verseEnd > 0 ? verseEnd : verseStart,
            referenceCode: referenceCode,
            rawFields: _asUnmodifiableMap(row),
          )
        : null;
    final layoutHint = UnifiedTagLayoutHint(
      presentationSlideNumber: _int(row['presentation_slide_number']),
      presentationSlideRegion: _readStringOrNull(
        row['presentation_slide_region'],
      ),
      rawFields: _asUnmodifiableMap({
        'presentation_slide_number': row['presentation_slide_number'],
        'presentation_slide_region': row['presentation_slide_region'],
      }),
    );
    final itemType = _unifiedItemType(
      bibleAnchor: bibleAnchor,
      elibraryAnchor: elibraryAnchor,
      noteText: noteText,
      media: media,
      noteFormatJson: noteFormatJson,
      htmlContent: htmlContent,
      legacyItemType: legacyDollarPayload?.legacyItemType,
    );
    final chainName = _readString(groupRow['name']);

    return UnifiedTagChainItem(
      id: 'unified:$rowId',
      chainId: 'unified:${_readString(groupRow['id'])}',
      storageKind: UnifiedTagStorageKind.unified,
      sourceType: _sourceTypeForItemType(itemType),
      itemType: itemType,
      sortOrder: sortOrder,
      displayTitle: _unifiedDisplayTitle(
        itemType: itemType,
        bibleAnchor: bibleAnchor,
        elibraryAnchor: elibraryAnchor,
        chainName: chainName,
        noteText: noteText,
        referenceCode: referenceCode,
      ),
      textSnapshot: _unifiedTextSnapshot(
        itemType: itemType,
        noteText: noteText,
        noteFormatJson: noteFormatJson,
        htmlContent: htmlContent,
        legacyDollarPayload: legacyDollarPayload,
      ),
      noteText: noteText,
      htmlContent: htmlContent,
      media: media,
      bibleAnchor: bibleAnchor,
      elibraryAnchor: elibraryAnchor,
      layoutHint: layoutHint,
      legacyTable: null,
      legacyTagName: chainName,
      legacyTagId: _readStringOrNull(row['legacy_group_id']),
      legacyItemId: _readStringOrNull(row['legacy_item_id']),
      legacyGroupId: _readStringOrNull(row['legacy_group_id']),
      legacyImportPackageId: _readStringOrNull(row['legacy_import_package_id']),
      createdAt: _parseTimestamp(row['created_at']),
      updatedAt: _parseTimestamp(row['updated_at']),
      deletedAt: _parseTimestamp(row['deleted_at']),
      rawFields: _asUnmodifiableMap(row),
    );
  }

  UnifiedTagBibleAnchor? _legacyBibleAnchor({
    required Map<String, Object?> row,
    required int? bookNumber,
    required int? chapter,
    required int? verseStart,
    required String verseRef,
  }) {
    if (bookNumber == null || chapter == null || verseStart == null) {
      return null;
    }
    final isNoteOnly =
        verseRef.trim().startsWith('note:') ||
        (bookNumber == 0 && chapter == 0 && verseStart == 0);
    if (isNoteOnly) return null;
    final rangeMatch = RegExp(
      r'^\d+:\d+:(\d+)-(\d+)$',
    ).firstMatch(verseRef.trim());
    final verseEnd = rangeMatch == null
        ? verseStart
        : (int.tryParse(rangeMatch.group(2) ?? '') ?? verseStart);
    final tokenNumber = _int(row['token_number']);
    return UnifiedTagBibleAnchor(
      bookNumber: bookNumber,
      chapter: chapter,
      verseStart: verseStart,
      verseEnd: verseEnd < verseStart ? verseStart : verseEnd,
      tokenStart: tokenNumber,
      tokenEnd: tokenNumber,
      verseRef: verseRef.isEmpty ? null : verseRef,
      rawFields: _asUnmodifiableMap(row),
    );
  }

  UnifiedTagELibraryAnchor? _legacyELibraryAnchor({
    required String? noteFormatJson,
    required String? contentHtml,
  }) {
    final raw = noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      final compactRef = _firstNonEmptyString([
        _readStringOrNull(decoded['source_location']),
        _readStringOrNull(decoded['source_reference_text']),
        _readStringOrNull(decoded['source_title_acronym']),
        'eLibrary',
      ]);
      return UnifiedTagELibraryAnchor(
        compactRef: compactRef,
        sourceTitle: _readStringOrNull(decoded['source_title']),
        sourceTitleAcronym: _readStringOrNull(decoded['source_title_acronym']),
        sourceLocation: _readStringOrNull(decoded['source_location']),
        sourceReferenceText: _readStringOrNull(
          decoded['source_reference_text'],
        ),
        sourceHref: _readStringOrNull(decoded['source_href']),
        sourceAnchorId: _readStringOrNull(decoded['source_anchor_id']),
        sourceSpineIndex: _int(decoded['source_spine_index']),
        sourceParagraphIndex: _int(decoded['source_paragraph_index']),
        sourceRelativePath: _readStringOrNull(decoded['source_relative_path']),
        sourceLibraryItemId: _readStringOrNull(
          decoded['source_library_item_id'],
        ),
        selectedTextSnapshot: _readStringOrNull(
          decoded['selected_text_snapshot'],
        ),
        selectionStartBlockIndex: _int(decoded['selection_start_block_index']),
        selectionStartCharOffset: _int(decoded['selection_start_char_offset']),
        selectionEndBlockIndex: _int(decoded['selection_end_block_index']),
        selectionEndCharOffset: _int(decoded['selection_end_char_offset']),
        selectionStartTokenIndex: _int(decoded['selection_start_token_index']),
        selectionEndTokenIndex: _int(decoded['selection_end_token_index']),
        sourcePageNumber: _int(decoded['source_page_number']),
        sourceParagraphNumber: _int(decoded['source_paragraph_number']),
        searchQuery: _readStringOrNull(decoded['search_query']),
        sourceParagraph: _readStringOrNull(decoded['source_paragraph']),
        excerpt: _readStringOrNull(decoded['excerpt']),
        stableRef: _readStringOrNull(decoded['stable_ref']),
        rawFields: _asUnmodifiableMap(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  UnifiedTagELibraryAnchor? _unifiedELibraryAnchorFromNoteFormat(
    String? noteFormatJson,
  ) {
    final raw = noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() == 'legacy_dollar_note') {
        final nested =
            decoded['legacy_note_format_json']?.toString().trim() ?? '';
        if (nested.isNotEmpty) {
          return _unifiedELibraryAnchorFromNoteFormat(nested);
        }
        return null;
      }
      if (decoded['kind']?.toString() != 'elibrary_note') return null;
      final compactRef = _firstNonEmptyString([
        _readStringOrNull(decoded['source_location']),
        _readStringOrNull(decoded['source_reference_text']),
        _readStringOrNull(decoded['source_title_acronym']),
        'eLibrary',
      ]);
      return UnifiedTagELibraryAnchor(
        compactRef: compactRef,
        sourceTitle: _readStringOrNull(decoded['source_title']),
        sourceTitleAcronym: _readStringOrNull(decoded['source_title_acronym']),
        sourceLocation: _readStringOrNull(decoded['source_location']),
        sourceReferenceText: _readStringOrNull(
          decoded['source_reference_text'],
        ),
        sourceHref: _readStringOrNull(decoded['source_href']),
        sourceAnchorId: _readStringOrNull(decoded['source_anchor_id']),
        sourceSpineIndex: _int(decoded['source_spine_index']),
        sourceParagraphIndex: _int(decoded['source_paragraph_index']),
        sourceRelativePath: _readStringOrNull(decoded['source_relative_path']),
        sourceLibraryItemId: _readStringOrNull(
          decoded['source_library_item_id'],
        ),
        selectedTextSnapshot: _readStringOrNull(
          decoded['selected_text_snapshot'],
        ),
        selectionStartBlockIndex: _int(decoded['selection_start_block_index']),
        selectionStartCharOffset: _int(decoded['selection_start_char_offset']),
        selectionEndBlockIndex: _int(decoded['selection_end_block_index']),
        selectionEndCharOffset: _int(decoded['selection_end_char_offset']),
        selectionStartTokenIndex: _int(decoded['selection_start_token_index']),
        selectionEndTokenIndex: _int(decoded['selection_end_token_index']),
        sourcePageNumber: _int(decoded['source_page_number']),
        sourceParagraphNumber: _int(decoded['source_paragraph_number']),
        searchQuery: _readStringOrNull(decoded['search_query']),
        sourceParagraph: _readStringOrNull(decoded['source_paragraph']),
        excerpt: _readStringOrNull(decoded['excerpt']),
        stableRef: _readStringOrNull(decoded['stable_ref']),
        rawFields: _asUnmodifiableMap(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  UnifiedTagItemType _legacyItemType({
    required UnifiedTagBibleAnchor? bibleAnchor,
    required UnifiedTagELibraryAnchor? elibraryAnchor,
    required String? noteText,
    required String? contentHtml,
    required List<UnifiedTagMedia> media,
    required bool isNoteOnly,
    required String verseRef,
  }) {
    if (elibraryAnchor != null) return UnifiedTagItemType.eLibraryRange;
    if (isNoteOnly) return UnifiedTagItemType.note;
    if (bibleAnchor != null) {
      return bibleAnchor.isRange
          ? UnifiedTagItemType.bibleRange
          : UnifiedTagItemType.bibleVerse;
    }
    if ((noteText ?? '').trim().isNotEmpty && verseRef.startsWith('note:')) {
      return UnifiedTagItemType.note;
    }
    if (media.isNotEmpty &&
        (contentHtml ?? '').trim().isEmpty &&
        (noteText ?? '').trim().isEmpty) {
      final imageOnly = media.every(
        (entry) => entry.mediaType.toLowerCase().startsWith('image/'),
      );
      return imageOnly ? UnifiedTagItemType.image : UnifiedTagItemType.media;
    }
    if ((contentHtml ?? '').trim().isNotEmpty ||
        (noteText ?? '').trim().isNotEmpty) {
      return UnifiedTagItemType.note;
    }
    return UnifiedTagItemType.unknownLegacy;
  }

  UnifiedTagItemType _unifiedItemType({
    required UnifiedTagBibleAnchor? bibleAnchor,
    required UnifiedTagELibraryAnchor? elibraryAnchor,
    required String? noteText,
    required List<UnifiedTagMedia> media,
    required String? noteFormatJson,
    required String? htmlContent,
    required UnifiedTagItemType? legacyItemType,
  }) {
    if (legacyItemType != null) return legacyItemType;
    if (elibraryAnchor != null) return UnifiedTagItemType.eLibraryRange;
    if (bibleAnchor != null) {
      return bibleAnchor.isRange
          ? UnifiedTagItemType.bibleRange
          : UnifiedTagItemType.bibleVerse;
    }
    if ((noteText ?? '').trim().isNotEmpty) return UnifiedTagItemType.note;
    if (media.isNotEmpty) {
      final imageOnly = media.every(
        (entry) => entry.mediaType.toLowerCase().startsWith('image/'),
      );
      return imageOnly ? UnifiedTagItemType.image : UnifiedTagItemType.media;
    }
    if ((noteFormatJson ?? '').trim().isNotEmpty ||
        (htmlContent ?? '').trim().isNotEmpty) {
      return UnifiedTagItemType.note;
    }
    return UnifiedTagItemType.unknownLegacy;
  }

  UnifiedTagSourceType _sourceTypeForItemType(UnifiedTagItemType itemType) {
    return switch (itemType) {
      UnifiedTagItemType.bibleVerse => UnifiedTagSourceType.bible,
      UnifiedTagItemType.bibleRange => UnifiedTagSourceType.bibleRange,
      UnifiedTagItemType.eLibraryRange => UnifiedTagSourceType.eLibrary,
      UnifiedTagItemType.note => UnifiedTagSourceType.note,
      UnifiedTagItemType.image => UnifiedTagSourceType.image,
      UnifiedTagItemType.media => UnifiedTagSourceType.media,
      UnifiedTagItemType.heading => UnifiedTagSourceType.heading,
      UnifiedTagItemType.unknownLegacy => UnifiedTagSourceType.unknownLegacy,
    };
  }

  UnifiedTagStorageKind _storageKindFromTagKind(String tagKind) {
    final normalized = tagKind.trim().toLowerCase();
    if (normalized == 'hash') return UnifiedTagStorageKind.unified;
    if (normalized == 'dollar') return UnifiedTagStorageKind.unified;
    if (normalized.isEmpty) return UnifiedTagStorageKind.unknownLegacy;
    return UnifiedTagStorageKind.unified;
  }

  String _legacyDisplayTitle({
    required UnifiedTagItemType itemType,
    required UnifiedTagBibleAnchor? bibleAnchor,
    required UnifiedTagELibraryAnchor? elibraryAnchor,
    required String tagName,
    required String? noteText,
  }) {
    if (elibraryAnchor != null) {
      final title = elibraryAnchor.sourceTitle?.trim() ?? '';
      if (title.isNotEmpty) return title;
      return elibraryAnchor.compactRef;
    }
    if (bibleAnchor != null) {
      return _bibleDisplayLabel(bibleAnchor);
    }
    if ((noteText ?? '').trim().isNotEmpty) return 'Note';
    if (itemType == UnifiedTagItemType.image ||
        itemType == UnifiedTagItemType.media) {
      return 'Media';
    }
    if (tagName.trim().isNotEmpty) return tagName;
    return 'Legacy item';
  }

  String _unifiedDisplayTitle({
    required UnifiedTagItemType itemType,
    required UnifiedTagBibleAnchor? bibleAnchor,
    required UnifiedTagELibraryAnchor? elibraryAnchor,
    required String chainName,
    required String? noteText,
    required String? referenceCode,
  }) {
    if (elibraryAnchor != null) {
      final title = elibraryAnchor.sourceTitle?.trim() ?? '';
      if (title.isNotEmpty) return title;
      final location = elibraryAnchor.sourceLocation?.trim() ?? '';
      if (location.isNotEmpty) return location;
      return elibraryAnchor.compactRef;
    }
    if (bibleAnchor != null) {
      if (referenceCode != null && referenceCode.trim().isNotEmpty) {
        return referenceCode.trim();
      }
      return _bibleDisplayLabel(bibleAnchor);
    }
    if ((noteText ?? '').trim().isNotEmpty) return 'Note';
    if (itemType == UnifiedTagItemType.image ||
        itemType == UnifiedTagItemType.media) {
      return chainName.isNotEmpty ? chainName : 'Media';
    }
    return chainName.isNotEmpty ? chainName : 'Item';
  }

  String? _legacyTextSnapshot({
    required UnifiedTagItemType itemType,
    required String? noteText,
    required String? contentHtml,
    required UnifiedTagELibraryAnchor? elibraryAnchor,
  }) {
    if (elibraryAnchor != null) {
      final excerpt = elibraryAnchor.excerpt?.trim() ?? '';
      if (excerpt.isNotEmpty) return excerpt;
      final paragraph = elibraryAnchor.sourceParagraph?.trim() ?? '';
      if (paragraph.isNotEmpty) return paragraph;
      final selected = elibraryAnchor.selectedTextSnapshot?.trim() ?? '';
      if (selected.isNotEmpty) return selected;
    }
    final note = (noteText ?? '').trim();
    if (note.isNotEmpty) return note;
    final html = (contentHtml ?? '').trim();
    if (html.isNotEmpty) return _stripHtml(html);
    return null;
  }

  String? _unifiedTextSnapshot({
    required UnifiedTagItemType itemType,
    required String? noteText,
    required String? noteFormatJson,
    required String? htmlContent,
    required _LegacyDollarNotePayload? legacyDollarPayload,
  }) {
    final note = (noteText ?? '').trim();
    if (note.isNotEmpty) return note;
    if (legacyDollarPayload != null) {
      final legacyText = (legacyDollarPayload.noteText ?? '').trim();
      if (legacyText.isNotEmpty) return legacyText;
      final legacyHtml = (legacyDollarPayload.contentHtml ?? '').trim();
      if (legacyHtml.isNotEmpty) return _stripHtml(legacyHtml);
    }
    final html = (htmlContent ?? '').trim();
    if (html.isNotEmpty) return _stripHtml(html);
    if ((noteFormatJson ?? '').trim().isNotEmpty &&
        itemType == UnifiedTagItemType.note) {
      return noteFormatJson;
    }
    return null;
  }

  Future<Map<String, List<UnifiedTagMedia>>> _loadUnifiedMediaByItemId(
    Database db,
  ) async {
    final rows = await db.query(
      'tag_item_media',
      orderBy: 'tag_item_id ASC, sort_order ASC, id ASC',
    );
    final grouped = <String, List<UnifiedTagMedia>>{};
    for (final row in rows) {
      final itemId = _readString(row['tag_item_id']);
      final relativePath = _readString(row['relative_path']);
      if (itemId.isEmpty || relativePath.isEmpty) continue;
      grouped
          .putIfAbsent(itemId, () => <UnifiedTagMedia>[])
          .add(
            UnifiedTagMedia(
              id: 'unified:${_readString(row['id'])}',
              itemId: itemId,
              relativePath: relativePath,
              mediaType: _readString(row['media_type']),
              sortOrder: _int(row['sort_order']) ?? 0,
              caption: _readStringOrNull(row['caption']),
              fileHash: _readStringOrNull(row['file_hash']),
              fileSize: _int(row['file_size']),
              legacyTable:
                  _readStringOrNull(row['legacy_group_id']) != null ||
                      _readStringOrNull(row['legacy_item_id']) != null
                  ? 'tag_item_media'
                  : null,
              legacyTagName: null,
              legacyTagId: _readStringOrNull(row['legacy_group_id']),
              legacyItemId: _readStringOrNull(row['legacy_item_id']),
              legacyImportPackageId: _readStringOrNull(
                row['legacy_import_package_id'],
              ),
              createdAt: _parseTimestamp(row['created_at']),
              updatedAt: _parseTimestamp(row['updated_at']),
              deletedAt: _parseTimestamp(row['deleted_at']),
              rawFields: _asUnmodifiableMap(row),
            ),
          );
    }
    return grouped;
  }

  List<UnifiedTagMedia> _legacyMediaForRow({
    required String itemId,
    required String tableName,
    required String tagName,
    required String? contentHtml,
  }) {
    final html = contentHtml?.trim() ?? '';
    if (html.isEmpty) return const <UnifiedTagMedia>[];

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

    return [
      for (var index = 0; index < refs.length; index++)
        UnifiedTagMedia(
          id: 'legacy-media:${Uri.encodeComponent(tableName)}:$itemId:$index',
          itemId: itemId,
          relativePath: refs[index],
          mediaType: _mediaTypeForPath(refs[index]),
          sortOrder: index + 1,
          legacyTable: tableName,
          legacyTagName: tagName,
          legacyTagId: null,
          legacyItemId: itemId,
          legacyImportPackageId: null,
          createdAt: null,
          updatedAt: null,
          deletedAt: null,
          rawFields: _asUnmodifiableMap({
            'table_name': tableName,
            'tag_name': tagName,
            'content_html': html,
            'relative_path': refs[index],
          }),
        ),
    ];
  }

  Future<Map<String, String>> _loadCategoryNames(Database db) async {
    final rows = await db.query(
      'tag_groups',
      columns: ['id', 'name'],
      orderBy: 'sort_order ASC, created_at ASC, id ASC',
    );
    return {
      for (final row in rows) _readString(row['id']): _readString(row['name']),
    };
  }

  Future<Set<String>> _loadDefaultTags(Database db, TagMode mode) async {
    final key = mode == TagMode.quick
        ? 'tags.default.hash'
        : 'tags.default.dollar';
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return const <String>{};
    final value = _normalizeTagName(
      rows.first['value']?.toString() ?? '',
      mode == TagMode.quick
          ? UnifiedTagStorageKind.hash
          : UnifiedTagStorageKind.dollar,
    );
    return value.isEmpty ? const <String>{} : {value};
  }

  String _normalizeTagName(String input, UnifiedTagStorageKind storageKind) {
    final prefix = switch (storageKind) {
      UnifiedTagStorageKind.hash => '#',
      UnifiedTagStorageKind.dollar => r'$',
      UnifiedTagStorageKind.unified => '#',
      UnifiedTagStorageKind.unknownLegacy => '',
    };
    final cleaned = input
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^[#\$@]+'), '');
    if (cleaned.isEmpty) return '';
    return prefix.isEmpty ? cleaned : '$prefix$cleaned';
  }

  String _bibleDisplayLabel(UnifiedTagBibleAnchor anchor) {
    final verseLabel = anchor.verseEnd > anchor.verseStart
        ? '${anchor.verseStart}-${anchor.verseEnd}'
        : '${anchor.verseStart}';
    return 'Book ${anchor.bookNumber} ${anchor.chapter}:$verseLabel';
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

  _LegacyDollarNotePayload? _parseLegacyDollarNotePayload(
    String? noteFormatJson,
  ) {
    final raw = noteFormatJson?.trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['kind']?.toString() != 'legacy_dollar_note') return null;
      return _LegacyDollarNotePayload(
        contentHtml: _readStringOrNull(decoded['content_html']),
        noteText: _readStringOrNull(decoded['note_text']),
        legacyNoteFormatJson: _readStringOrNull(
          decoded['legacy_note_format_json'],
        ),
        legacyItemType: _legacyItemTypeFromString(
          _readStringOrNull(decoded['legacy_item_type']),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  UnifiedTagItemType? _legacyItemTypeFromString(String? value) {
    final normalized = (value ?? '').trim().toLowerCase();
    return switch (normalized) {
      'bibleverse' || 'verse' => UnifiedTagItemType.bibleVerse,
      'biblerange' || 'range' => UnifiedTagItemType.bibleRange,
      'elibraryrange' || 'elibrary' => UnifiedTagItemType.eLibraryRange,
      'note' => UnifiedTagItemType.note,
      'image' => UnifiedTagItemType.image,
      'media' => UnifiedTagItemType.media,
      'heading' => UnifiedTagItemType.heading,
      'unknownlegacy' => UnifiedTagItemType.unknownLegacy,
      _ => null,
    };
  }

  int? _int(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  String _readString(Object? value) => value?.toString().trim() ?? '';

  String? _readStringOrNull(Object? value) {
    final text = _readString(value);
    return text.isEmpty ? null : text;
  }

  DateTime? _parseTimestamp(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = int.tryParse(text);
    if (parsed != null) {
      return DateTime.fromMillisecondsSinceEpoch(parsed, isUtc: true);
    }
    return DateTime.tryParse(text);
  }

  Map<String, Object?> _asUnmodifiableMap(Map<String, Object?> source) {
    return Map<String, Object?>.unmodifiable({...source});
  }

  String _firstNonEmptyString(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
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

  String _mediaTypeForPath(String path) {
    return switch (p.extension(path).toLowerCase()) {
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.mp4' => 'video/mp4',
      '.mov' => 'video/quicktime',
      '.mp3' => 'audio/mpeg',
      '.m4a' => 'audio/mp4',
      _ => 'image',
    };
  }

  int _compareItemsByOrder(
    UnifiedTagChainItem left,
    UnifiedTagChainItem right,
  ) {
    final sortCompare = left.sortOrder.compareTo(right.sortOrder);
    if (sortCompare != 0) return sortCompare;
    final createdCompare =
        (left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
    if (createdCompare != 0) return createdCompare;
    return left.id.compareTo(right.id);
  }
}

class _LegacyDollarNotePayload {
  const _LegacyDollarNotePayload({
    required this.contentHtml,
    required this.noteText,
    required this.legacyNoteFormatJson,
    required this.legacyItemType,
  });

  final String? contentHtml;
  final String? noteText;
  final String? legacyNoteFormatJson;
  final UnifiedTagItemType? legacyItemType;
}
