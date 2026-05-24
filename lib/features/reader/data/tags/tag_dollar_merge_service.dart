import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../../core/bootstrap/local_settings_store.dart';
import '../../../../core/database/user_database.dart';
import 'unified_tag_models.dart';
import 'tag_repository.dart';

String _legacyMediaTypeForPath(String path) {
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

class TagDollarMergeService {
  TagDollarMergeService({
    TagDatabaseProvider? databaseProvider,
    Future<String> Function()? deviceIdProvider,
  }) : _databaseProvider =
           databaseProvider ?? (() => UserDatabase.instance.database),
       _deviceIdProvider =
           deviceIdProvider ??
           (() => LocalSettingsStore.instance.ensureDeviceId());

  final TagDatabaseProvider _databaseProvider;
  final Future<String> Function() _deviceIdProvider;

  Future<bool> hasLegacyDollarTags() async {
    final db = await _databaseProvider();
    final rows = await db.query('dollar_tags', columns: ['id'], limit: 1);
    return rows.isNotEmpty;
  }

  Future<TagDollarMergeReport> mergeLegacyDollarTags({
    bool dryRun = false,
  }) async {
    final db = await _databaseProvider();
    final legacyRows = await db.query(
      'dollar_tags',
      orderBy: 'study_order ASC, created_at ASC, id ASC',
    );
    if (legacyRows.isEmpty) {
      return TagDollarMergeReport(
        dryRun: dryRun,
        legacyChainsFound: 0,
        legacyItemsFound: 0,
        legacyMediaFound: 0,
        chainsCreated: 0,
        itemsCopied: 0,
        mediaCopied: 0,
        itemsSkipped: 0,
        reusedMappings: 0,
        chainReports: const <TagDollarMergeChainReport>[],
        warnings: const <String>[],
        errors: const <String>[],
      );
    }

    final rowsByTag = <String, List<Map<String, Object?>>>{};
    for (final row in legacyRows) {
      final tagName = _readString(row['tag']);
      if (tagName.isEmpty) continue;
      rowsByTag.putIfAbsent(tagName, () => <Map<String, Object?>>[]).add(row);
    }

    final plans = <_DollarChainPlan>[];
    final warnings = <String>[];
    final errors = <String>[];
    var skippedLegacyRows = 0;
    var legacyMediaFound = 0;
    for (final entry in rowsByTag.entries) {
      try {
        final plan = await _buildChainPlan(db, entry.key, entry.value);
        legacyMediaFound += plan.legacyMediaFound;
        plans.add(plan);
        if (plan.namingStrategy == 'collision-renamed') {
          warnings.add(
            'Renamed imported chain "${plan.legacyTagName}" to "${plan.chainName}" to avoid a name collision.',
          );
        }
      } catch (error) {
        errors.add('Failed to plan merge for "${entry.key}": $error');
      }
    }
    for (final row in legacyRows) {
      final tagName = _readString(row['tag']);
      if (tagName.isNotEmpty) continue;
      skippedLegacyRows += 1;
    }
    if (skippedLegacyRows > 0) {
      warnings.add(
        'Skipped $skippedLegacyRows legacy dollar row(s) with no tag name.',
      );
    }

    final legacyItemsFound = legacyRows.length;
    final legacyChainsFound = plans.length;
    if (errors.isNotEmpty) {
      return TagDollarMergeReport(
        dryRun: dryRun,
        legacyChainsFound: legacyChainsFound,
        legacyItemsFound: legacyItemsFound,
        legacyMediaFound: legacyMediaFound,
        chainsCreated: 0,
        itemsCopied: 0,
        mediaCopied: 0,
        itemsSkipped: legacyItemsFound,
        reusedMappings: 0,
        chainReports: [
          for (final plan in plans)
            plan.toReport(
              copiedItems: 0,
              copiedMedia: 0,
              skippedItems: 0,
              reusedMappings: 0,
            ),
        ],
        warnings: List.unmodifiable(warnings),
        errors: List.unmodifiable(errors),
      );
    }

    if (dryRun) {
      var chainsCreated = 0;
      var itemsCopied = 0;
      var mediaCopied = 0;
      var reusedMappings = 0;
      var itemsSkipped = skippedLegacyRows;
      final chainReports = <TagDollarMergeChainReport>[];
      for (final plan in plans) {
        final itemCount = plan.items.where((item) => !item.isSkipped).length;
        final skippedCount = plan.items.where((item) => item.isSkipped).length;
        final copiedMedia = plan.items.fold<int>(
          0,
          (sum, item) => sum + item.mediaRefs.length,
        );
        chainsCreated += plan.isNewChain ? 1 : 0;
        itemsCopied += itemCount;
        mediaCopied += copiedMedia;
        itemsSkipped += skippedCount;
        reusedMappings += plan.existingChainId != null ? 1 : 0;
        chainReports.add(
          plan.toReport(
            copiedItems: itemCount,
            copiedMedia: copiedMedia,
            skippedItems: skippedCount,
            reusedMappings: plan.existingChainId != null ? 1 : 0,
          ),
        );
      }
      return TagDollarMergeReport(
        dryRun: true,
        legacyChainsFound: legacyChainsFound,
        legacyItemsFound: legacyItemsFound,
        legacyMediaFound: legacyMediaFound,
        chainsCreated: chainsCreated,
        itemsCopied: itemsCopied,
        mediaCopied: mediaCopied,
        itemsSkipped: itemsSkipped,
        reusedMappings: reusedMappings,
        chainReports: List.unmodifiable(chainReports),
        warnings: List.unmodifiable(warnings),
        errors: const <String>[],
      );
    }

    final deviceId = await _deviceIdProvider();
    var chainsCreated = 0;
    var itemsCopied = 0;
    var mediaCopied = 0;
    var reusedMappings = 0;
    var itemsSkipped = skippedLegacyRows;
    final chainReports = <TagDollarMergeChainReport>[];

    await db.transaction((txn) async {
      for (final plan in plans) {
        final result = await _mergePlan(txn, plan: plan, deviceId: deviceId);
        chainsCreated += result.chainsCreated;
        itemsCopied += result.itemsCopied;
        mediaCopied += result.mediaCopied;
        reusedMappings += result.reusedMappings;
        itemsSkipped += plan.items.length - result.itemsCopied;
        chainReports.add(result.report);
      }
    });

    return TagDollarMergeReport(
      dryRun: false,
      legacyChainsFound: legacyChainsFound,
      legacyItemsFound: legacyItemsFound,
      legacyMediaFound: legacyMediaFound,
      chainsCreated: chainsCreated,
      itemsCopied: itemsCopied,
      mediaCopied: mediaCopied,
      itemsSkipped: itemsSkipped,
      reusedMappings: reusedMappings,
      chainReports: List.unmodifiable(chainReports),
      warnings: List.unmodifiable(warnings),
      errors: const <String>[],
    );
  }

  Future<_DollarMergeResult> _mergePlan(
    Transaction txn, {
    required _DollarChainPlan plan,
    required String deviceId,
  }) async {
    var chainsCreated = 0;
    var itemsCopied = 0;
    var mediaCopied = 0;
    var reusedMappings = 0;

    final chainId = await _ensureUnifiedChain(
      txn,
      plan: plan,
      deviceId: deviceId,
    );
    if (plan.existingChainId != null) {
      reusedMappings += 1;
    } else {
      chainsCreated += 1;
    }

    for (final item in plan.items) {
      final alreadyCopied = await txn.query(
        'tag_items',
        columns: ['id'],
        where: 'legacy_group_id = ? AND legacy_item_id = ?',
        whereArgs: [plan.sourceKey, item.legacyItemId],
        limit: 1,
      );
      if (alreadyCopied.isEmpty) {
        await txn.insert(
          'tag_items',
          item.toRow(chainId: chainId, deviceId: deviceId),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        itemsCopied += 1;
      } else {
        reusedMappings += 1;
      }

      final mediaRows = item.buildMediaRows(
        deviceId: deviceId,
        chainId: chainId,
      );
      for (final mediaRow in mediaRows) {
        final existingMedia = await txn.query(
          'tag_item_media',
          columns: ['id'],
          where:
              'legacy_group_id = ? AND legacy_item_id = ? AND relative_path = ?',
          whereArgs: [
            plan.sourceKey,
            item.legacyItemId,
            mediaRow['relative_path'],
          ],
          limit: 1,
        );
        if (existingMedia.isEmpty) {
          await txn.insert(
            'tag_item_media',
            mediaRow,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          mediaCopied += 1;
        } else {
          reusedMappings += 1;
        }
      }
    }

    return _DollarMergeResult(
      chainsCreated: chainsCreated,
      itemsCopied: itemsCopied,
      mediaCopied: mediaCopied,
      reusedMappings: reusedMappings,
      report: plan.toReport(
        copiedItems: itemsCopied,
        copiedMedia: mediaCopied,
        skippedItems: plan.items.length - itemsCopied,
        reusedMappings: reusedMappings,
        chainId: chainId,
      ),
    );
  }

  Future<String> _ensureUnifiedChain(
    Transaction txn, {
    required _DollarChainPlan plan,
    required String deviceId,
  }) async {
    if (plan.existingChainId != null) return plan.existingChainId!;

    final now = plan.chainCreatedAtIso ?? _utcNow();
    await txn.insert('tag_groups', <String, Object?>{
      'id': plan.chainId,
      'parent_group_id': null,
      'tag_kind': 'hash',
      'name': plan.chainName,
      'description': plan.categoryName == null
          ? null
          : 'Imported from legacy dollar tags',
      'sort_order': plan.chainSortOrder,
      'source_device_name': null,
      'legacy_group_id': plan.sourceKey,
      'legacy_item_id': plan.legacyRows.isNotEmpty
          ? _readString(plan.legacyRows.first['id'])
          : null,
      'legacy_import_package_id': plan.legacyImportPackageId,
      'imported_at': now,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return plan.chainId;
  }

  Future<_DollarChainPlan> _buildChainPlan(
    Database db,
    String legacyTagName,
    List<Map<String, Object?>> rows,
  ) async {
    final sourceKey = _legacySourceKey(legacyTagName);
    final existingChain = await _findExistingChain(
      db,
      sourceKey,
      legacyTagName,
    );
    final categoryName = _firstNonEmpty([
      for (final row in rows) _readStringOrNull(row['category']),
    ]);
    final legacyImportPackageId = _firstNonEmpty([
      for (final row in rows)
        _readStringOrNull(row['legacy_import_package_id']),
    ]);
    final chainName =
        existingChain?.name ?? await _chooseChainName(db, legacyTagName);
    final chainId = existingChain?.id ?? _stableId('chain|$sourceKey');
    final chainSortOrder = _sortOrderFromRows(rows);
    final chainCreatedAtIso = _isoFromRows(rows, preferEarliest: true);
    final items = <_DollarItemPlan>[];
    var mediaFound = 0;
    for (final row in rows) {
      final itemPlan = _buildItemPlan(
        row: row,
        sourceKey: sourceKey,
        legacyTagName: legacyTagName,
      );
      mediaFound += itemPlan.mediaRefs.length;
      items.add(itemPlan);
    }

    return _DollarChainPlan(
      legacyTagName: legacyTagName,
      sourceKey: sourceKey,
      chainId: chainId,
      chainName: chainName,
      categoryName: categoryName,
      legacyImportPackageId: legacyImportPackageId,
      chainSortOrder: chainSortOrder,
      chainCreatedAtIso: chainCreatedAtIso,
      existingChainId: existingChain?.id,
      items: List.unmodifiable(items),
      legacyRows: List.unmodifiable(rows),
      legacyMediaFound: mediaFound,
      namingStrategy: existingChain != null
          ? 'reuse-existing'
          : (chainName == legacyTagName ? 'same-name' : 'collision-renamed'),
    );
  }

  Future<_ExistingChain?> _findExistingChain(
    Database db,
    String sourceKey,
    String legacyTagName,
  ) async {
    final importedRows = await db.query(
      'tag_groups',
      columns: ['id', 'name', 'legacy_group_id'],
      where: 'legacy_group_id = ?',
      whereArgs: [sourceKey],
      limit: 1,
    );
    if (importedRows.isNotEmpty) {
      return _ExistingChain(
        id: _readString(importedRows.first['id']),
        name: _readString(importedRows.first['name']),
      );
    }

    return null;
  }

  Future<String> _chooseChainName(Database db, String legacyTagName) async {
    final collision = await _hasNameCollision(db, legacyTagName);
    if (!collision) return legacyTagName;
    return 'Imported \$: $legacyTagName';
  }

  Future<bool> _hasNameCollision(Database db, String legacyTagName) async {
    final legacyRows = await db.query(
      'hash_tags',
      columns: ['id'],
      where: 'tag = ?',
      whereArgs: [legacyTagName],
      limit: 1,
    );
    if (legacyRows.isNotEmpty) return true;

    final normalizedRows = await db.query(
      'tag_groups',
      columns: ['id'],
      where: '''
        tag_kind = 'hash'
        AND name = ?
        AND COALESCE(deleted_at, '') = ''
      ''',
      whereArgs: [legacyTagName],
      limit: 1,
    );
    return normalizedRows.isNotEmpty;
  }

  _DollarItemPlan _buildItemPlan({
    required Map<String, Object?> row,
    required String sourceKey,
    required String legacyTagName,
  }) {
    final rowId = _readString(row['id']);
    final verseRef = _readString(row['verse_ref']);
    final bookNumber = _int(row['book_number']) ?? 0;
    final chapter = _int(row['chapter_number']) ?? 0;
    final verseNumber = _int(row['verse_number']) ?? 0;
    final tokenNumber = _int(row['token_number']);
    final sortOrder =
        _int(row['study_order']) ??
        _int(row['sort_order']) ??
        _int(row['created_at']) ??
        0;
    final contentHtml = _readStringOrNull(row['content_html']);
    final noteText =
        _readStringOrNull(row['note_text']) ?? _stripHtml(contentHtml ?? '');
    final legacyCategory = _readStringOrNull(row['category']);
    final sourceAuthor = _readStringOrNull(row['source_author']);
    final sourceWorkTitle = _readStringOrNull(row['source_work_title']);
    final sourceTitleAcronym = _readStringOrNull(row['source_title_acronym']);
    final sourceChapterTitle = _readStringOrNull(row['source_chapter_title']);
    final sourceChapterNumber = _readStringOrNull(row['source_chapter_number']);
    final sourcePageNumber = _readStringOrNull(row['source_page_number']);
    final sourceParagraphNumber = _readStringOrNull(
      row['source_paragraph_number'],
    );
    final sourceYear = _readStringOrNull(row['source_year']);
    final legacyImportPackageId = _readStringOrNull(
      row['legacy_import_package_id'],
    );
    final createdAt = _isoFromRow(row, preferEarliest: true) ?? _utcNow();
    final updatedAt = _isoFromRow(row, preferEarliest: false) ?? createdAt;
    final deletedAt = _isoFromRow(row, deleted: true);
    final deviceId = _readStringOrNull(row['device_id']) ?? '';
    final syncStatus = _readStringOrNull(row['sync_status']) ?? 'pending';
    final changeId = _readStringOrNull(row['change_id']);
    final lastSyncedAt = _isoFromRow(row, synced: true);
    final mediaRefs = _extractMediaRefs(contentHtml ?? '');
    final presentationSlideNumber = _int(row['presentation_slide_number']);
    final presentationSlideRegion = _readStringOrNull(
      row['presentation_slide_region'],
    );
    final noteFormatJson = _buildLegacyNoteFormatJson(
      sourceKey: sourceKey,
      legacyTagName: legacyTagName,
      legacyItemId: rowId,
      itemType: _inferItemType(
        verseRef: verseRef,
        noteText: noteText,
        contentHtml: contentHtml,
        mediaRefs: mediaRefs,
        noteFormatJson: _readStringOrNull(row['note_format_json']),
      ),
      legacyCategory: legacyCategory,
      contentHtml: contentHtml,
      noteText: noteText,
      sourceAuthor: sourceAuthor,
      sourceWorkTitle: sourceWorkTitle,
      sourceTitleAcronym: sourceTitleAcronym,
      sourceChapterTitle: sourceChapterTitle,
      sourceChapterNumber: sourceChapterNumber,
      sourcePageNumber: sourcePageNumber,
      sourceParagraphNumber: sourceParagraphNumber,
      sourceYear: sourceYear,
      legacyImportPackageId: legacyImportPackageId,
      presentationSlideNumber: presentationSlideNumber,
      presentationSlideRegion: presentationSlideRegion,
      existingNoteFormatJson: _readStringOrNull(row['note_format_json']),
    );
    final anchor = _parseLegacyBibleAnchor(
      verseRef: verseRef,
      bookNumber: bookNumber,
      chapter: chapter,
      verseNumber: verseNumber,
      tokenNumber: tokenNumber,
    );

    return _DollarItemPlan(
      legacyItemId: rowId,
      sortOrder: sortOrder,
      bookId: anchor?.bookNumber ?? 0,
      chapter: anchor?.chapter ?? 0,
      verseStart: anchor?.verseStart ?? 0,
      verseEnd: anchor?.verseEnd ?? 0,
      referenceCode: null,
      presentationSlideNumber: presentationSlideNumber,
      presentationSlideRegion: presentationSlideRegion,
      noteText: noteText.isEmpty ? null : noteText,
      noteFormatJson: noteFormatJson,
      sourceDeviceName: null,
      legacyGroupId: sourceKey,
      legacyImportPackageId: legacyImportPackageId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      deviceId: deviceId.isEmpty ? null : deviceId,
      revision: _int(row['revision']) ?? 1,
      syncStatus: syncStatus,
      lastSyncedAt: lastSyncedAt,
      changeId: changeId,
      mediaRefs: mediaRefs,
    );
  }

  UnifiedTagItemType _inferItemType({
    required String verseRef,
    required String? noteText,
    required String? contentHtml,
    required List<String> mediaRefs,
    required String? noteFormatJson,
  }) {
    final rawJson = noteFormatJson?.trim() ?? '';
    if (rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is Map<String, dynamic> &&
            decoded['kind']?.toString() == 'elibrary_note') {
          return UnifiedTagItemType.eLibraryRange;
        }
      } catch (_) {
        // Fall through to the normal heuristics.
      }
    }
    if (verseRef.trim().startsWith('note:')) {
      return UnifiedTagItemType.note;
    }
    if (mediaRefs.isNotEmpty &&
        (contentHtml ?? '').trim().isNotEmpty &&
        _stripHtml(contentHtml ?? '').isEmpty &&
        (noteText ?? '').trim().isEmpty) {
      final imageOnly = mediaRefs.every(
        (ref) => _legacyMediaTypeForPath(ref).startsWith('image/'),
      );
      return imageOnly ? UnifiedTagItemType.image : UnifiedTagItemType.media;
    }
    if ((noteText ?? '').trim().isNotEmpty ||
        (contentHtml ?? '').trim().isNotEmpty) {
      return UnifiedTagItemType.note;
    }
    if (mediaRefs.isNotEmpty) {
      final imageOnly = mediaRefs.every(
        (ref) => _legacyMediaTypeForPath(ref).startsWith('image/'),
      );
      return imageOnly ? UnifiedTagItemType.image : UnifiedTagItemType.media;
    }
    return UnifiedTagItemType.unknownLegacy;
  }

  List<String> _extractMediaRefs(String contentHtml) {
    final html = contentHtml.trim();
    if (html.isEmpty) return const <String>[];
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
    return List.unmodifiable(refs);
  }

  String _buildLegacyNoteFormatJson({
    required String sourceKey,
    required String legacyTagName,
    required String legacyItemId,
    required UnifiedTagItemType itemType,
    required String? legacyCategory,
    required String? contentHtml,
    required String? noteText,
    required String? sourceAuthor,
    required String? sourceWorkTitle,
    required String? sourceTitleAcronym,
    required String? sourceChapterTitle,
    required String? sourceChapterNumber,
    required String? sourcePageNumber,
    required String? sourceParagraphNumber,
    required String? sourceYear,
    required String? legacyImportPackageId,
    required int? presentationSlideNumber,
    required String? presentationSlideRegion,
    required String? existingNoteFormatJson,
  }) {
    final payload = <String, Object?>{
      'format_version': 1,
      'kind': 'legacy_dollar_note',
      'legacy_table': 'dollar_tags',
      'legacy_tag_name': legacyTagName,
      'legacy_tag_source_key': sourceKey,
      'legacy_item_id': legacyItemId,
      'legacy_item_type': itemType.name,
      if (legacyCategory != null) 'legacy_category': legacyCategory,
      if (legacyImportPackageId != null)
        'legacy_import_package_id': legacyImportPackageId,
      if ((contentHtml ?? '').trim().isNotEmpty) 'content_html': contentHtml,
      if ((noteText ?? '').trim().isNotEmpty) 'note_text': noteText,
      if (sourceAuthor != null) 'source_author': sourceAuthor,
      if (sourceWorkTitle != null) 'source_work_title': sourceWorkTitle,
      if (sourceTitleAcronym != null)
        'source_title_acronym': sourceTitleAcronym,
      if (sourceChapterTitle != null)
        'source_chapter_title': sourceChapterTitle,
      if (sourceChapterNumber != null)
        'source_chapter_number': sourceChapterNumber,
      if (sourcePageNumber != null) 'source_page_number': sourcePageNumber,
      if (sourceParagraphNumber != null)
        'source_paragraph_number': sourceParagraphNumber,
      if (sourceYear != null) 'source_year': sourceYear,
      if (presentationSlideNumber != null)
        'presentation_slide_number': presentationSlideNumber,
      if (presentationSlideRegion != null)
        'presentation_slide_region': presentationSlideRegion,
      if ((existingNoteFormatJson ?? '').trim().isNotEmpty)
        'legacy_note_format_json': existingNoteFormatJson,
    };
    return jsonEncode(payload);
  }

  _LegacyBibleAnchor? _parseLegacyBibleAnchor({
    required String verseRef,
    required int bookNumber,
    required int chapter,
    required int verseNumber,
    required int? tokenNumber,
  }) {
    if (bookNumber <= 0 || chapter <= 0 || verseNumber <= 0) return null;
    if (verseRef.trim().startsWith('note:')) return null;
    final rangeMatch = RegExp(
      r'^\d+:\d+:(\d+)-(\d+)$',
    ).firstMatch(verseRef.trim());
    final verseEnd = rangeMatch == null
        ? verseNumber
        : (int.tryParse(rangeMatch.group(2) ?? '') ?? verseNumber);
    return _LegacyBibleAnchor(
      bookNumber: bookNumber,
      chapter: chapter,
      verseStart: verseNumber,
      verseEnd: verseEnd < verseNumber ? verseNumber : verseEnd,
      tokenNumber: tokenNumber,
      verseRef: verseRef.isEmpty ? null : verseRef,
    );
  }

  String _legacySourceKey(String legacyTagName) {
    return 'dollar_tags|${legacyTagName.trim()}';
  }

  String _stableId(String input) {
    return sha1.convert(utf8.encode(input)).toString().substring(0, 16);
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

  String _utcNow() => DateTime.now().toUtc().toIso8601String();

  String? _isoFromRow(
    Map<String, Object?> row, {
    bool preferEarliest = false,
    bool deleted = false,
    bool synced = false,
  }) {
    final keys = deleted
        ? const ['deleted_at_utc', 'deleted_at']
        : synced
        ? const ['last_synced_at']
        : preferEarliest
        ? const ['created_at_utc', 'created_at']
        : const [
            'updated_at_utc',
            'updated_at',
            'created_at_utc',
            'created_at',
          ];
    for (final key in keys) {
      final value = row[key];
      if (value == null) continue;
      final parsed = _parseTimestamp(value);
      if (parsed != null) return parsed.toUtc().toIso8601String();
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String _isoFromRows(
    List<Map<String, Object?>> rows, {
    bool preferEarliest = false,
  }) {
    if (rows.isEmpty) return _utcNow();
    final row = preferEarliest ? rows.first : rows.last;
    return _isoFromRow(row, preferEarliest: preferEarliest) ?? _utcNow();
  }

  int _sortOrderFromRows(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return 0;
    final values =
        rows
            .map(
              (row) =>
                  _int(row['study_order']) ??
                  _int(row['sort_order']) ??
                  _int(row['created_at']) ??
                  0,
            )
            .toList(growable: false)
          ..sort();
    return values.first;
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
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
}

class TagDollarMergeReport {
  const TagDollarMergeReport({
    required this.dryRun,
    required this.legacyChainsFound,
    required this.legacyItemsFound,
    required this.legacyMediaFound,
    required this.chainsCreated,
    required this.itemsCopied,
    required this.mediaCopied,
    required this.itemsSkipped,
    required this.reusedMappings,
    required this.chainReports,
    required this.warnings,
    required this.errors,
  });

  final bool dryRun;
  final int legacyChainsFound;
  final int legacyItemsFound;
  final int legacyMediaFound;
  final int chainsCreated;
  final int itemsCopied;
  final int mediaCopied;
  final int itemsSkipped;
  final int reusedMappings;
  final List<TagDollarMergeChainReport> chainReports;
  final List<String> warnings;
  final List<String> errors;

  bool get hasChanges =>
      chainsCreated > 0 || itemsCopied > 0 || mediaCopied > 0;
}

class TagDollarMergeChainReport {
  const TagDollarMergeChainReport({
    required this.legacyTagName,
    required this.sourceKey,
    required this.chainId,
    required this.chainName,
    required this.namingStrategy,
    required this.legacyItemCount,
    required this.copiedItemCount,
    required this.copiedMediaCount,
    required this.skippedItemCount,
    required this.reusedMappings,
    required this.isNewChain,
  });

  final String legacyTagName;
  final String sourceKey;
  final String chainId;
  final String chainName;
  final String namingStrategy;
  final int legacyItemCount;
  final int copiedItemCount;
  final int copiedMediaCount;
  final int skippedItemCount;
  final int reusedMappings;
  final bool isNewChain;
}

class _ExistingChain {
  const _ExistingChain({required this.id, required this.name});

  final String id;
  final String name;
}

class _DollarMergeResult {
  const _DollarMergeResult({
    required this.chainsCreated,
    required this.itemsCopied,
    required this.mediaCopied,
    required this.reusedMappings,
    required this.report,
  });

  final int chainsCreated;
  final int itemsCopied;
  final int mediaCopied;
  final int reusedMappings;
  final TagDollarMergeChainReport report;
}

class _DollarChainPlan {
  const _DollarChainPlan({
    required this.legacyTagName,
    required this.sourceKey,
    required this.chainId,
    required this.chainName,
    required this.categoryName,
    required this.legacyImportPackageId,
    required this.chainSortOrder,
    required this.chainCreatedAtIso,
    required this.existingChainId,
    required this.items,
    required this.legacyRows,
    required this.legacyMediaFound,
    required this.namingStrategy,
  });

  final String legacyTagName;
  final String sourceKey;
  final String chainId;
  final String chainName;
  final String? categoryName;
  final String? legacyImportPackageId;
  final int chainSortOrder;
  final String? chainCreatedAtIso;
  final String? existingChainId;
  final List<_DollarItemPlan> items;
  final List<Map<String, Object?>> legacyRows;
  final int legacyMediaFound;
  final String namingStrategy;

  bool get isNewChain => existingChainId == null;

  TagDollarMergeChainReport toReport({
    required int copiedItems,
    required int copiedMedia,
    required int skippedItems,
    required int reusedMappings,
    String? chainId,
  }) {
    return TagDollarMergeChainReport(
      legacyTagName: legacyTagName,
      sourceKey: sourceKey,
      chainId: chainId ?? this.chainId,
      chainName: chainName,
      namingStrategy: namingStrategy,
      legacyItemCount: legacyRows.length,
      copiedItemCount: copiedItems,
      copiedMediaCount: copiedMedia,
      skippedItemCount: skippedItems,
      reusedMappings: reusedMappings,
      isNewChain: isNewChain,
    );
  }
}

class _DollarItemPlan {
  const _DollarItemPlan({
    required this.legacyItemId,
    required this.sortOrder,
    required this.bookId,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.referenceCode,
    required this.presentationSlideNumber,
    required this.presentationSlideRegion,
    required this.noteText,
    required this.noteFormatJson,
    required this.sourceDeviceName,
    required this.legacyGroupId,
    required this.legacyImportPackageId,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.deviceId,
    required this.revision,
    required this.syncStatus,
    required this.lastSyncedAt,
    required this.changeId,
    required this.mediaRefs,
  });

  final String legacyItemId;
  final int sortOrder;
  final int bookId;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final String? referenceCode;
  final int? presentationSlideNumber;
  final String? presentationSlideRegion;
  final String? noteText;
  final String? noteFormatJson;
  final String? sourceDeviceName;
  final String legacyGroupId;
  final String? legacyImportPackageId;
  final String createdAt;
  final String updatedAt;
  final String? deletedAt;
  final String? deviceId;
  final int revision;
  final String syncStatus;
  final String? lastSyncedAt;
  final String? changeId;
  final List<String> mediaRefs;

  bool get isSkipped => legacyItemId.trim().isEmpty;

  Map<String, Object?> toRow({
    required String chainId,
    required String deviceId,
  }) {
    return <String, Object?>{
      'id': _stableRowId(chainId, legacyItemId),
      'tag_group_id': chainId,
      'tag_kind': 'hash',
      'book_id': bookId,
      'chapter': chapter,
      'verse_start': verseStart,
      'verse_end': verseEnd,
      'reference_code': referenceCode,
      'presentation_slide_number': presentationSlideNumber,
      'presentation_slide_region': presentationSlideRegion,
      'note_text': noteText,
      'note_format_json': noteFormatJson,
      'sort_order': sortOrder,
      'source_device_name': sourceDeviceName,
      'legacy_group_id': legacyGroupId,
      'legacy_item_id': legacyItemId,
      'legacy_import_package_id': legacyImportPackageId,
      'imported_at': createdAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'device_id': this.deviceId ?? deviceId,
      'revision': revision,
      'sync_status': syncStatus,
      'last_synced_at': lastSyncedAt,
      'change_id': changeId,
    };
  }

  List<Map<String, Object?>> buildMediaRows({
    required String deviceId,
    required String chainId,
  }) {
    return [
      for (var index = 0; index < mediaRefs.length; index++)
        <String, Object?>{
          'id': _stableRowId('$chainId|media', '$legacyItemId|$index'),
          'tag_item_id': _stableRowId(chainId, legacyItemId),
          'media_type': _legacyMediaTypeForPath(mediaRefs[index]),
          'relative_path': mediaRefs[index],
          'caption': null,
          'file_hash': null,
          'file_size': null,
          'sort_order': index + 1,
          'source_device_name': sourceDeviceName,
          'legacy_group_id': legacyGroupId,
          'legacy_item_id': legacyItemId,
          'legacy_import_package_id': legacyImportPackageId,
          'imported_at': createdAt,
          'created_at': createdAt,
          'updated_at': updatedAt,
          'deleted_at': deletedAt,
          'device_id': this.deviceId ?? deviceId,
          'revision': revision,
          'sync_status': syncStatus,
          'last_synced_at': lastSyncedAt,
          'change_id': changeId,
        },
    ];
  }

  String _stableRowId(String parentId, String rowId) {
    return sha1
        .convert(utf8.encode('$parentId|$rowId'))
        .toString()
        .substring(0, 16);
  }
}

class _LegacyBibleAnchor {
  const _LegacyBibleAnchor({
    required this.bookNumber,
    required this.chapter,
    required this.verseStart,
    required this.verseEnd,
    required this.tokenNumber,
    required this.verseRef,
  });

  final int bookNumber;
  final int chapter;
  final int verseStart;
  final int verseEnd;
  final int? tokenNumber;
  final String? verseRef;
}
