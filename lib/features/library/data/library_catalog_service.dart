import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import 'library_citation_display_helper.dart';
import '../../search/search_highlight_helper.dart';
import 'library_author_resolver.dart';
import 'library_book_display_title.dart';
import 'library_contributor.dart';
import 'library_epub_cover_extractor.dart';
import 'library_epub_metadata.dart';
import 'library_item_availability.dart';
import 'library_item_identity.dart';
import 'library_search_navigation_target.dart';
import '../../utilities/data/pioneer_capture_folder_metadata.dart';
import '../../utilities/data/elibrary_folder_policy.dart';
import '../../utilities/data/epub_download_validator.dart';

part 'library_navigation_dedupe.dart';
part 'library_catalog_text_helpers.dart';
part 'library_catalog_collection_helpers.dart';
part 'library_catalog_search_result_helpers.dart';

class LibraryCatalogService {
  LibraryCatalogService._();

  static final LibraryCatalogService instance = LibraryCatalogService._();
  static final Map<String, Future<String?>> _coverWarmJobs = {};
  static final Map<String, Future<String?>> _authorWarmJobs = {};
  static final Map<String, Future<String?>> _titleWarmJobs = {};
  static Future<Map<String, String>>? _officialDownloadTitlesFuture;
  static final ELibraryReadResolver _readResolver =
      ELibraryReadResolver.instance;

  Future<List<LibraryCatalogItem>> loadItems({
    String folderRoot = 'all',
    bool includeAlternateEditions = false,
    bool hydrateMetadata = true,
  }) async {
    await LibraryRootService.instance.accessibleLibraryRootPath();
    final normalized = folderRoot.trim().toLowerCase();
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];

    where.add('''
      (
        LOWER(COALESCE(file_format, '')) = ?
        OR LOWER(COALESCE(file_format, '')) = ?
        OR (
          LOWER(COALESCE(file_format, '')) = ?
          AND (
            LOWER(COALESCE(collection_name, '')) LIKE ?
            OR LOWER(COALESCE(collection_name, '')) LIKE ?
            OR LOWER(COALESCE(relative_path, '')) LIKE ?
          )
        )
      )
      ''');
    args.addAll([
      'epub',
      'pdf',
      'html',
      '%pioneer authors%',
      '%adventist pioneer library%',
      '%adventist pioneer library%',
    ]);

    switch (normalized) {
      case 'epubs':
        where.add('LOWER(relative_path) LIKE ?');
        args.add('epubs/%');
        break;
      case 'pdfs':
        where.add('LOWER(relative_path) LIKE ?');
        args.add('pdfs/%');
        break;
      case 'all':
      default:
        break;
    }

    final rowResult = await _readResolver
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.rawQuery('''
      SELECT
        li.id,
        li.title,
        li.author,
        li.file_name,
        li.file_hash,
        li.relative_path,
        li.file_format,
        li.folder_type,
        li.library_role,
        li.collection_name,
        li.source_site,
        li.source_url,
        li.source_type,
        li.source_work_id,
        li.source_package_id,
        li.cover_path,
        li.date_added,
        li.last_opened,
        li.index_status,
        li.index_error,
        li.file_size,
        li.mime_type,
        li.spine_index,
        li.anchor_id,
        li.epub_href,
        li.paragraph_index,
        ${hydrateMetadata ? '''(
          SELECT COUNT(*)
          FROM library_navigation_items lni
          WHERE lni.library_item_id = li.id
            AND lni.deleted_at IS NULL
        )''' : '0'} AS navigation_count
        ,${hydrateMetadata ? '''(
          SELECT COUNT(*) FROM library_text_blocks ltb
          WHERE ltb.library_item_id = li.id
        )''' : '0'} AS readable_block_count
        ,${hydrateMetadata ? '''(
          SELECT COALESCE(SUM(LENGTH(ltb.plain_text)), 0)
          FROM library_text_blocks ltb WHERE ltb.library_item_id = li.id
        )''' : '0'} AS extracted_text_length
        ,${hydrateMetadata ? '''(
          SELECT COALESCE(MAX(lni.depth), 0)
          FROM library_navigation_items lni
          WHERE lni.library_item_id = li.id AND lni.deleted_at IS NULL
        )''' : '0'} AS navigation_max_depth
      FROM library_items li
      WHERE ${where.join(' AND ')}
      ORDER BY
        COALESCE(li.last_opened, li.date_added, li.created_at) DESC,
        li.title COLLATE NOCASE ASC,
        li.file_name COLLATE NOCASE ASC
    ''', args),
          hasData: (rows) => rows.isNotEmpty,
        );
    final rows = rowResult.value;
    if (rows.isEmpty) {
      return const [];
    }

    final normalizedRows = hydrateMetadata
        ? await _hydrateCatalogRows(rows, database: rowResult.database)
        : rows;

    final rootPath = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    final items = normalizedRows
        .map((row) => LibraryCatalogItem.fromRow(row, rootPath: rootPath))
        .toList();
    final projected = includeAlternateEditions
        ? items
        : selectPreferredLibraryEditions(items);
    final result = projected
        .where(_isVisibleLibraryItem)
        .toList(growable: false);
    return result;
  }

  Future<List<Map<String, Object?>>> _hydrateCatalogRows(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final warmedAuthorValues = await _warmMissingAuthorValues(
      rows,
      database: database,
    );
    final warmedCoverPaths = await _warmMissingCoverPaths(
      rows,
      database: database,
    );
    final repairedCaptureCoverPaths = await _warmMissingCaptureCoverPaths(
      rows,
      database: database,
    );
    final warmedTitleValues = await _warmMissingTitleValues(
      rows,
      database: database,
    );
    final repairedManagedPaths = await _repairMissingManagedPaths(
      rows,
      database: database,
    );
    final hydratedRows = rows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final warmedAuthor = warmedAuthorValues[id];
          final warmedCoverPath = warmedCoverPaths[id];
          final repairedCaptureCoverPath = repairedCaptureCoverPaths[id];
          final warmedTitle = warmedTitleValues[id];
          final repairedPathValues = repairedManagedPaths[id];
          if ((warmedAuthor == null || warmedAuthor.trim().isEmpty) &&
              (warmedCoverPath == null || warmedCoverPath.trim().isEmpty)) {
            if (warmedTitle == null || warmedTitle.trim().isEmpty) {
              if (repairedPathValues == null) {
                return row;
              }
            }
          }
          return <String, Object?>{
            ...row,
            if (warmedAuthor != null && warmedAuthor.trim().isNotEmpty)
              'author': warmedAuthor,
            if (warmedCoverPath != null && warmedCoverPath.trim().isNotEmpty)
              'cover_path': warmedCoverPath,
            if (repairedCaptureCoverPath != null &&
                repairedCaptureCoverPath.trim().isNotEmpty)
              'cover_path': repairedCaptureCoverPath,
            if (warmedTitle != null && warmedTitle.trim().isNotEmpty)
              'title': warmedTitle,
            if (repairedPathValues != null) ...repairedPathValues,
          };
        })
        .toList(growable: false);
    final repairedManagedIds = await _repairManagedItemIds(
      hydratedRows,
      database: database,
    );
    return hydratedRows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final repairedIdValues = repairedManagedIds[id];
          if (repairedIdValues == null) return row;
          return <String, Object?>{...row, ...repairedIdValues};
        })
        .toList(growable: false);
  }

  Future<int> refreshManagedItemsFromDisk({String? rootPathOverride}) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final override = rootPathOverride?.trim() ?? '';
    final rootPath = override.isNotEmpty
        ? p.normalize(override)
        : (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
              selection.path;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return 0;
    }
    if (!Directory(rootPath).existsSync()) {
      return 0;
    }

    await LibraryRootService.instance.ensureStructure(rootPath);
    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    var touched = 0;

    for (final folder in ELibraryFolderPolicy.allManagedEgwFolderDefinitions) {
      final directory = Directory(p.join(rootPath, folder.relativeFolder));
      if (!await directory.exists()) continue;

      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final ext = p.extension(entity.path).toLowerCase();
        if (ext != '.epub' && ext != '.pdf') continue;

        // A production EGW recovery can contain hundreds of EPUBs. Yield once
        // per candidate so metadata parsing cannot starve Flutter's UI/lifecycle
        // event queue for the duration of the complete scan on Android.
        await Future<void>.delayed(Duration.zero);

        final relativePath = await LibraryRootService.instance.relativePathFor(
          absolutePath: entity.path,
          rootPath: rootPath,
        );
        final itemId = canonicalLibraryItemId(
          folderType: folder.folderType,
          relativePath: relativePath,
        );
        final stat = await entity.stat();
        final isEpub = ext == '.epub';
        final matchingRows = await db.query(
          'library_items',
          columns: const ['id', 'collection_name', 'cover_path', 'deleted_at'],
          where: 'id = ? OR LOWER(relative_path) = ?',
          whereArgs: [itemId, relativePath.toLowerCase()],
          limit: 1,
        );
        final matchedRow = matchingRows.isEmpty ? null : matchingRows.first;
        final matchedIsSoftRetired =
            (matchedRow?['deleted_at'] as String?)?.trim().isNotEmpty == true;
        if (matchedIsSoftRetired) {
          // This exact managed path already has a soft-retired row (a
          // duplicate that lost edition selection, or a shell deliberately
          // archived as unreadable). The file being present on disk is not
          // evidence it should come back — resurrecting it here is exactly
          // the bug that let quarantined duplicates like the invalid IC/COS
          // placeholders reappear after a refresh. Leave the retired row
          // untouched and do not stand up a replacement active row for it.
          continue;
        }
        final existingRow = matchedRow;
        final existingId = existingRow?['id']?.toString().trim() ?? '';
        final existingCollection =
            existingRow?['collection_name']?.toString().trim() ?? '';
        final existingCoverPath =
            existingRow?['cover_path']?.toString().trim() ?? '';
        final title = await _resolveManagedTitle(file: entity, isEpub: isEpub);
        final author = await _resolveManagedAuthor(
          file: entity,
          isEpub: isEpub,
          collectionName: folder.collectionName,
          relativePath: relativePath,
        );
        final now = DateTime.now().toUtc().toIso8601String();
        final fileHash = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
        final detectedWorkId = ELibraryFolderPolicy.detectedAbbreviation(
          p.basename(entity.path),
        );
        final updatePayload = <String, Object?>{
          'title': title,
          'author': author,
          'file_name': p.basename(entity.path),
          'relative_path': relativePath,
          'file_hash': fileHash,
          if (detectedWorkId.isNotEmpty) 'source_work_id': detectedWorkId,
          'file_size': stat.size,
          'modified_at': stat.modified.toUtc().toIso8601String(),
          'mime_type': isEpub ? 'application/epub+zip' : 'application/pdf',
          'file_format': isEpub ? 'epub' : 'pdf',
          'folder_type': folder.folderType,
          'library_role': folder.folderType,
          'collection_name': folder.collectionName,
          'source_site': 'egwwritings.org',
          'source_type': 'official_download',
          'updated_at': now,
          'deleted_at': null,
        };
        // Rule: file presence alone must never imply readability. A brand
        // new managed EPUB (no existing row of any kind at this identity)
        // is only ever seen by the app for the first time here, so it must
        // be structurally validated before it is allowed to render as
        // 'metadata_only' (readable) in the normal Library — otherwise a
        // placeholder/teaser package briefly shows as a real book until a
        // later indexing pass catches it. PDFs have no structural gate here.
        var newItemIndexStatus = 'metadata_only';
        String? newItemIndexError;
        if (existingId.isEmpty && isEpub) {
          final structural = EpubDownloadValidator.validate(
            await entity.readAsBytes(),
          );
          if (!structural.isValid) {
            newItemIndexStatus = 'needs_attention';
            newItemIndexError = _structuralRejectionMessage(structural);
          }
        }
        final insertPayload = <String, Object?>{
          'id': itemId,
          ...updatePayload,
          'source_url': null,
          'cover_path': existingCoverPath.isNotEmpty ? existingCoverPath : null,
          'date_added': now,
          'last_opened': null,
          'index_status': newItemIndexStatus,
          'index_error': newItemIndexError,
          'epub_href': null,
          'epub_cfi': null,
          'anchor_id': null,
          'spine_index': null,
          'paragraph_index': null,
          'is_missing': 0,
          'created_at': now,
          'device_id': deviceId,
          'revision': 1,
          'sync_status': 'pending',
          'last_synced_at': null,
          'change_id': null,
        };

        if (existingId.isEmpty) {
          await db.insert(
            'library_items',
            insertPayload,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          if (existingId != itemId) {
            await migrateManagedLibraryItemId(
              db: db,
              oldId: existingId,
              newId: itemId,
            );
          }
          await db.update(
            'library_items',
            updatePayload,
            where: 'id = ?',
            whereArgs: [itemId],
          );
        }

        if (existingCollection != folder.collectionName ||
            existingId.isEmpty ||
            existingId != itemId) {
          touched += 1;
        }
      }
    }

    return touched;
  }

  /// Mirrors `LibraryDocumentCanonicalizer._structuralRejectionMessage`'s
  /// wording exactly (`Structurally invalid EPUB (reasonName): detail`) so a
  /// placeholder caught here at discovery time is indistinguishable — to
  /// [libraryItemAvailability]'s `_needsAttentionReasonPattern` matcher and
  /// to the user — from one caught later by the canonicalizer's own gate.
  String _structuralRejectionMessage(EpubDownloadValidationResult structural) {
    final reasonName = structural.rejectionReason?.name;
    final detail = structural.detail?.trim();
    final label = reasonName == null
        ? 'Structurally invalid EPUB'
        : 'Structurally invalid EPUB ($reasonName)';
    return detail == null || detail.isEmpty ? '$label.' : '$label: $detail';
  }

  /// Returns the count of managed EPUB items that have not yet been indexed
  /// (index_status is not 'indexed' or 'indexed_empty').  These items appear
  /// in the Library catalog and can be opened in the reader, but their body
  /// text is absent from the search index until the Commentary/Research panel
  /// runs an indexing pass. Items flagged 'needs_attention' (structurally
  /// broken source files) are excluded here since re-running the indexer
  /// cannot fix them — see [countNeedsAttentionManagedItems].
  Future<int> countUnindexedManagedItems() async {
    // Indexing writes exclusively to eLibrary.db. A zero here is an
    // authoritative result, not a reason to fall back to legacy user.db
    // rows (which may still carry stale pending statuses).
    final db = await _readResolver.primaryDatabase();
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(folder_type, '')) IN ('commentary', 'research')
        AND LOWER(COALESCE(index_status, '')) != 'needs_attention'
        AND LOWER(COALESCE(epub_storage_state, 'present')) = 'present'
        AND (
          LOWER(COALESCE(index_status, '')) NOT IN ('indexed', 'indexed_empty')
          OR NOT EXISTS (
            SELECT 1 FROM library_text_blocks WHERE library_item_id = library_items.id
          )
        )
    ''');
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<List<LibraryCatalogItem>> listUnindexedManagedItems({
    int limit = 500,
  }) async {
    final db = await _readResolver.primaryDatabase();
    return _queryItems(
      where: '''
        LOWER(COALESCE(li.file_format, '')) = 'epub'
        AND LOWER(COALESCE(li.folder_type, '')) IN ('commentary', 'research')
        AND LOWER(COALESCE(li.index_status, '')) != 'needs_attention'
        AND LOWER(COALESCE(li.epub_storage_state, 'present')) = 'present'
        AND (
          LOWER(COALESCE(li.index_status, '')) NOT IN ('indexed', 'indexed_empty')
          OR NOT EXISTS (
            SELECT 1 FROM library_text_blocks
            WHERE library_item_id = li.id
          )
        )
      ''',
      args: const <Object?>[],
      limit: limit,
      database: db,
    );
  }

  /// Returns the count of managed EPUB items whose source file failed
  /// structural validation (missing OPF, empty spine, or zero readable
  /// content) and therefore cannot be indexed until the file is replaced.
  Future<int> countNeedsAttentionManagedItems() async {
    final db = await _readResolver.primaryDatabase();
    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(folder_type, '')) IN ('commentary', 'research')
        AND LOWER(COALESCE(index_status, '')) = 'needs_attention'
    ''');
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<List<LibraryCatalogItem>> listNeedsAttentionManagedItems({
    int limit = 500,
  }) async {
    final db = await _readResolver.primaryDatabase();
    final rows = await _queryItems(
      where: '''
        LOWER(COALESCE(li.file_format, '')) = 'epub'
        AND LOWER(COALESCE(li.folder_type, '')) IN ('commentary', 'research')
        AND LOWER(COALESCE(li.index_status, '')) = 'needs_attention'
      ''',
      args: const <Object?>[],
      limit: limit,
      database: db,
    );
    // Two stale rows for the same work (e.g. a legacy-folder-layout copy and
    // a current-layout copy) must surface as one maintenance entry, not one
    // per row — reuse the same source_work_id grouping normal editions use.
    return selectPreferredLibraryEditions(rows);
  }

  Future<int> countIndexedSearchableItems({String? collectionFilter}) async {
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause(normalizedCollectionFilter));
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }

    final result = await _readResolver.readWithFallback<int>(
      read: (db) async {
        final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT li.id) AS cnt
      FROM library_items li
      INNER JOIN library_text_blocks ltb ON ltb.library_item_id = li.id
      WHERE ${where.join(' AND ')}
      ''', args);
        return (rows.first['cnt'] as num?)?.toInt() ?? 0;
      },
      hasData: (count) => count > 0,
    );
    return result.value;
  }

  Future<int> countCatalogItemsInScope({String? collectionFilter}) async {
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause(normalizedCollectionFilter));
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }

    final result = await _readResolver.readWithFallback<int>(
      read: (db) async {
        final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT li.id) AS cnt
      FROM library_items li
      WHERE ${where.join(' AND ')}
      ''', args);
        return (rows.first['cnt'] as num?)?.toInt() ?? 0;
      },
      hasData: (count) => count > 0,
    );
    return result.value;
  }

  Future<int> countSearchContentResults({
    required String query,
    String? collectionFilter,
  }) async {
    final normalizedTerms = extractLibrarySearchHighlightTerms(query);
    if (normalizedTerms.isEmpty) {
      return 0;
    }

    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause(normalizedCollectionFilter));
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }

    var termAdded = false;
    for (final term in normalizedTerms) {
      final normalizedTerm = _normalizedLibrarySearchText(term);
      if (normalizedTerm.isEmpty) continue;
      final pattern = _librarySearchLikePattern(normalizedTerm);
      where.add('(${_librarySearchTermClause()})');
      args.addAll(
        List<Object?>.filled(_librarySearchClauseFields.length, pattern),
      );
      termAdded = true;
    }

    if (!termAdded) {
      return 0;
    }

    final result = await _readResolver.readWithFallback<int>(
      read: (db) async {
        final rows = await db.rawQuery('''
      -- Search results are paragraph-level navigation targets. Counting only
      -- distinct books truncates broad searches to one result per matching
      -- book even though searchContent intentionally returns every matching
      -- paragraph.
      SELECT COUNT(*) AS cnt
      FROM library_text_blocks ltb
      INNER JOIN library_items li ON li.id = ltb.library_item_id
      WHERE ${where.join(' AND ')}
      ''', args);
        return (rows.first['cnt'] as num?)?.toInt() ?? 0;
      },
      hasData: (count) => count > 0,
    );
    return result.value;
  }

  String _libraryCollectionSearchClause(String normalizedCollectionFilter) {
    final searchTerms = _libraryCollectionSearchTerms(
      normalizedCollectionFilter,
    );
    if (searchTerms.isEmpty) {
      return '1 = 1';
    }

    final clauses = searchTerms
        .map(
          (_) => '''
            (
              LOWER(COALESCE(li.collection_name, '')) LIKE ?
              OR LOWER(COALESCE(li.relative_path, '')) LIKE ?
              OR LOWER(COALESCE(li.folder_type, '')) LIKE ?
              OR LOWER(COALESCE(li.library_role, '')) LIKE ?
            )
          ''',
        )
        .join(' OR ');
    return '($clauses)';
  }

  List<Object?> _libraryCollectionSearchArgs(
    String normalizedCollectionFilter,
  ) {
    final args = <Object?>[];
    for (final term in _libraryCollectionSearchTerms(
      normalizedCollectionFilter,
    )) {
      final likePattern = '%$term%';
      args.addAll(<Object?>[
        likePattern,
        likePattern,
        likePattern,
        likePattern,
      ]);
    }
    return args;
  }

  List<String> _libraryCollectionSearchTerms(
    String normalizedCollectionFilter,
  ) {
    switch (normalizedCollectionFilter) {
      case _libraryAllCollectionsFilterValue:
      case '':
        return const [];
      case 'egw_books':
        return const ['egw books', 'egw_books'];
      case 'egw_devotionals':
        return const ['egw devotionals', 'egw_devotionals'];
      case 'egw_commentaries':
        return const ['egw commentaries', 'egw_commentaries'];
      case 'egw_misc_collections':
        return const ['egw misc collections', 'egw_misc_collections'];
      case 'egw_pamphlets':
        return const ['egw pamphlets', 'egw_pamphlets'];
      case 'egw_periodicals':
        return const ['egw periodicals', 'egw_periodicals'];
      case 'egw_manuscript_releases':
        return const ['egw manuscript releases', 'egw_manuscript_releases'];
      case 'pioneer_authors':
      case 'adventist_pioneer_library':
        return const ['adventist pioneer library', 'pioneer authors'];
    }

    final humanizedFilter = normalizedCollectionFilter.replaceAll('_', ' ');
    return <String>[humanizedFilter, normalizedCollectionFilter];
  }

  Future<List<LibraryCatalogSearchResult>> searchContent({
    required String query,
    int limit = 50,
    String? collectionFilter,
  }) async {
    final normalizedTerms = extractLibrarySearchHighlightTerms(query);
    if (normalizedTerms.isEmpty || limit <= 0) {
      return const [];
    }

    final where = <String>[
      'li.deleted_at IS NULL',
      // Belt-and-suspenders alongside the text-block INNER JOIN below: a
      // needs_attention item must never surface in search even if it
      // retains stale blocks from before it was flagged unreadable.
      "LOWER(COALESCE(li.index_status, '')) != 'needs_attention'",
    ];
    final args = <Object?>[];
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause(normalizedCollectionFilter));
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }
    // Keep every matching paragraph independently navigable, including
    // multiple hits in the same Pioneer book.
    var termAdded = false;
    for (final term in normalizedTerms) {
      final normalizedTerm = _normalizedLibrarySearchText(term);
      if (normalizedTerm.isEmpty) continue;
      final pattern = _librarySearchLikePattern(normalizedTerm);
      where.add('(${_librarySearchTermClause()})');
      args.addAll(
        List<Object?>.filled(_librarySearchClauseFields.length, pattern),
      );
      termAdded = true;
    }

    if (!termAdded) {
      return const [];
    }

    final cteWhere = where.join(' AND ');
    // A single-collection search already narrows the CTE's candidate rows
    // via the collection WHERE clause, so 8x headroom above the requested
    // limit is enough. "All Collections" searches that same table with no
    // collection narrowing, so the pre-scoring LIMIT window has to cover
    // many more collections' worth of candidates to keep any one collection
    // (or any one early-sorting item ID) from crowding out the rest —
    // it needs at least as much headroom as a single collection, not less.
    final fetchLimit =
        limit *
        ((normalizedCollectionFilter.isNotEmpty &&
                normalizedCollectionFilter != _libraryAllCollectionsFilterValue)
            ? 8
            : 16);

    final rowResult = await _readResolver
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.rawQuery(
            '''
      WITH matching_hits AS (
        SELECT ltb.rowid AS hit_rowid
        FROM library_text_blocks ltb
        INNER JOIN library_items li ON li.id = ltb.library_item_id
        WHERE $cteWhere
        ORDER BY ltb.library_item_id COLLATE NOCASE, ltb.epub_href, ltb.paragraph_index
        LIMIT ?
      )
      SELECT
        li.id AS item_id,
        li.title,
        li.author,
        li.file_name,
        li.file_hash,
        li.relative_path,
        li.file_format,
        li.folder_type,
        li.library_role,
        li.collection_name,
        li.source_site,
        li.source_url,
        li.source_type,
        li.source_work_id,
        li.source_package_id,
        li.cover_path,
        li.date_added,
        li.last_opened,
        li.index_status,
        li.file_size,
        li.mime_type,
        li.spine_index AS item_spine_index,
        li.anchor_id AS item_anchor_id,
        li.epub_href AS item_epub_href,
        li.paragraph_index AS item_paragraph_index,
        ltb.id AS hit_text_block_id,
        ltb.epub_href AS hit_epub_href,
        ltb.spine_index AS hit_spine_index,
        ltb.paragraph_index AS hit_paragraph_index,
        ltb.section_title,
        ltb.paragraph_on_section,
        ltb.plain_text,
        eri.ref_code AS hit_ref_code,
        eri.stable_ref AS hit_stable_ref,
        eri.page_number AS hit_page_number,
        eri.paragraph_on_page AS hit_paragraph_on_page
      FROM matching_hits mh
      INNER JOIN library_text_blocks ltb ON ltb.rowid = mh.hit_rowid
      INNER JOIN library_items li ON li.id = ltb.library_item_id
      LEFT JOIN elibrary_ref_index eri
        ON eri.library_item_id = ltb.library_item_id
        AND LOWER(COALESCE(eri.href, '')) = LOWER(COALESCE(ltb.epub_href, ''))
        AND eri.paragraph_index = ltb.paragraph_index
      ORDER BY li.title COLLATE NOCASE ASC
      ''',
            [...args, fetchLimit],
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    final rows = rowResult.value;
    if (rows.isEmpty) {
      return const [];
    }

    final searchRootPath = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    final mappedResults = rows
        .map((row) {
          final item =
              LibraryCatalogItem.fromRow({
                'id': row['item_id'],
                'title': row['title'],
                'author': row['author'],
                'file_name': row['file_name'],
                'file_hash': row['file_hash'],
                'relative_path': row['relative_path'],
                'file_format': row['file_format'],
                'folder_type': row['folder_type'],
                'library_role': row['library_role'],
                'collection_name': row['collection_name'],
                'source_site': row['source_site'],
                'source_url': row['source_url'],
                'source_type': row['source_type'],
                'source_work_id': row['source_work_id'],
                'source_package_id': row['source_package_id'],
                'cover_path': row['cover_path'],
                'date_added': row['date_added'],
                'last_opened': row['last_opened'],
                'index_status': row['index_status'],
                'file_size': row['file_size'],
                'mime_type': row['mime_type'],
                'spine_index': row['item_spine_index'],
                'anchor_id': row['item_anchor_id'],
                'epub_href': row['item_epub_href'],
                'paragraph_index': row['item_paragraph_index'],
                'navigation_count': 0,
              }, rootPath: searchRootPath).copyWith(
                spineIndex: (row['hit_spine_index'] as num?)?.toInt(),
                epubHref: row['hit_epub_href']?.toString(),
                paragraphIndex: (row['paragraph_on_section'] as num?)?.toInt(),
              );

          final fullParagraph = row['plain_text']?.toString();
          final sectionTitle = row['section_title']?.toString();
          final paragraphOnSection = (row['paragraph_on_section'] as num?)
              ?.toInt();
          final refCode = row['hit_ref_code']?.toString();

          final locationText = _buildLibraryTextBlockLocationText(
            item: item,
            refCode: refCode,
            sectionTitle: sectionTitle,
            paragraphOnSection: paragraphOnSection,
          );

          final snippet = _buildLibrarySearchSnippet(
            fullParagraph: fullParagraph,
            terms: normalizedTerms,
          );
          if (snippet == null || snippet.trim().isEmpty) {
            return null;
          }

          final score = _scoreLibrarySearchResult(
            item: item,
            referenceText: null,
            fullParagraph: fullParagraph,
            queryTerms: normalizedTerms,
          );

          return LibraryCatalogSearchResult(
            item: item,
            snippet: snippet,
            locationText: locationText,
            referenceText: null,
            fullParagraph: fullParagraph,
            chapterNumber: null,
            verseStart: null,
            verseEnd: null,
            score: score,
            target: LibrarySearchNavigationTarget(
              libraryItemId: item.id,
              textBlockId: (row['hit_text_block_id'] as num?)?.toInt() ?? 0,
              href: row['hit_epub_href']?.toString() ?? '',
              paragraphIndex:
                  (row['hit_paragraph_index'] as num?)?.toInt() ?? 0,
              spineIndex: (row['hit_spine_index'] as num?)?.toInt(),
              sectionTitle: sectionTitle,
              paragraphOnSection: paragraphOnSection,
              stableSourceReference: row['hit_stable_ref']?.toString(),
              pageNumber: (row['hit_page_number'] as num?)?.toInt(),
              paragraphOnPage: (row['hit_paragraph_on_page'] as num?)?.toInt(),
              matchedText: fullParagraph,
              sourceWorkId: row['source_work_id']?.toString(),
              sourcePackageId: row['source_package_id']?.toString(),
            ),
          );
        })
        .toList(growable: false);

    final filteredResults = mappedResults
        .whereType<LibraryCatalogSearchResult>()
        .where((result) {
          if (normalizedCollectionFilter.isEmpty ||
              normalizedCollectionFilter == _libraryAllCollectionsFilterValue) {
            return true;
          }
          return libraryItemMatchesCollectionFilter(
            result.item,
            normalizedCollectionFilter,
          );
        })
        .toList();

    final preferredResultItemIds = selectPreferredLibraryEditions(
      filteredResults.map((result) => result.item).toList(growable: false),
    ).map((item) => item.id).toSet();
    filteredResults.removeWhere(
      (result) => !preferredResultItemIds.contains(result.item.id),
    );

    filteredResults.sort((left, right) {
      final scoreCompare = left.score.compareTo(right.score);
      if (scoreCompare != 0) return scoreCompare;
      final titleCompare = left.item.displayTitle.toLowerCase().compareTo(
        right.item.displayTitle.toLowerCase(),
      );
      if (titleCompare != 0) return titleCompare;
      return left.item.displayAuthor.toLowerCase().compareTo(
        right.item.displayAuthor.toLowerCase(),
      );
    });

    return filteredResults.take(limit).toList(growable: false);
  }

  Future<String?> loadSearchResultParagraph(
    LibraryCatalogSearchResult result,
  ) async {
    final existing = _firstNonEmpty([result.fullParagraph, result.snippet]);
    if (existing != null &&
        result.fullParagraph != null &&
        result.fullParagraph!.trim().isNotEmpty) {
      return result.fullParagraph!.trim();
    }

    final item = result.item;
    final libraryItemId = item.id.trim();
    if (libraryItemId.isEmpty) return existing;

    final where = <String>['library_item_id = ?'];
    final args = <Object?>[libraryItemId];
    final spineIndex = item.spineIndex;
    final paragraphIndex = item.paragraphIndex;
    if (spineIndex != null) {
      where.add('spine_index = ?');
      args.add(spineIndex);
    }
    if (paragraphIndex != null) {
      where.add('paragraph_index = ?');
      args.add(paragraphIndex);
    }
    final rowResult = await _readResolver
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.rawQuery('''
      SELECT full_paragraph, anchor
      FROM library_links
      WHERE ${where.join(' AND ')}
      ORDER BY paragraph_index ASC
      LIMIT 1
      ''', args),
          hasData: (rows) => rows.isNotEmpty,
        );
    final rows = rowResult.value;
    if (rows.isEmpty) return existing;
    return _firstNonEmpty([
      rows.first['full_paragraph']?.toString(),
      rows.first['anchor']?.toString(),
      existing,
    ]);
  }

  Future<List<LibraryCatalogNavigationItem>> loadNavigationItems(
    String libraryItemId,
  ) async {
    final rowResult = await _readResolver
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_navigation_items',
            columns: const [
              'id',
              'parent_id',
              'label',
              'href',
              'anchor_id',
              'spine_index',
              'sort_order',
              'depth',
              'nav_type',
              'content_kind',
              'is_front_matter',
              'is_body_start',
              'body_order',
            ],
            where: 'library_item_id = ? AND deleted_at IS NULL',
            whereArgs: [libraryItemId],
            orderBy: 'sort_order ASC, depth ASC, label COLLATE NOCASE ASC',
          ),
          hasData: (rows) => rows.isNotEmpty,
        );
    final rows = rowResult.value;
    final items = rows
        .map(
          (row) => LibraryCatalogNavigationItem(
            id: row['id']?.toString() ?? '',
            parentId: row['parent_id']?.toString(),
            label: row['label']?.toString() ?? '',
            href: row['href']?.toString(),
            anchorId: row['anchor_id']?.toString(),
            spineIndex: (row['spine_index'] as num?)?.toInt(),
            sortOrder: (row['sort_order'] as num?)?.toInt(),
            depth: (row['depth'] as num?)?.toInt(),
            navType: row['nav_type']?.toString(),
            contentKind: row['content_kind']?.toString(),
            isFrontMatter:
                ((row['is_front_matter'] as num?)?.toInt() ?? 0) != 0,
            isBodyStart: ((row['is_body_start'] as num?)?.toInt() ?? 0) != 0,
            bodyOrder: (row['body_order'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);
    final deduped = dedupeLibraryNavigationItems(items);
    return _isWaggonerOnRomansItemId(libraryItemId)
        ? _waggonerRomansNavigationHierarchy(deduped)
        : deduped;
  }

  Future<LibraryCatalogItem?> loadItemById(String id) async {
    final items = await _queryItems(
      where: 'li.id = ?',
      args: [id.trim()],
      limit: 1,
    );
    return items.isEmpty ? null : items.first;
  }

  Future<LibraryCatalogItem?> loadItemByRelativePath(
    String relativePath,
  ) async {
    final normalizedPath = relativePath.trim().toLowerCase();
    if (normalizedPath.isEmpty) return null;

    final items = await _queryItems(
      where: 'LOWER(li.relative_path) = ?',
      args: [normalizedPath],
      limit: 2,
    );
    return items.length == 1 ? items.first : null;
  }

  Future<List<LibraryCatalogItem>> findItemsByTitle({
    required String title,
    String? collectionName,
    int limit = 2,
  }) async {
    final normalizedTitle = title.trim().toLowerCase();
    if (normalizedTitle.isEmpty) return const [];

    final where = StringBuffer('''
      LOWER(li.title) = ?
    ''');
    final args = <Object?>[normalizedTitle];
    final normalizedCollection = collectionName?.trim().toLowerCase() ?? '';
    if (normalizedCollection.isNotEmpty) {
      where.write(' AND ');
      where.write(_libraryCollectionSearchClause(normalizedCollection));
      args.addAll(_libraryCollectionSearchArgs(normalizedCollection));
    }

    return _queryItems(where: where.toString(), args: args, limit: limit);
  }

  Future<Map<String, String>> _warmMissingCoverPaths(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, String>{};
    final candidates = <Map<String, Object?>>[];

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;

      final existingCoverPath = row['cover_path']?.toString().trim();
      if (existingCoverPath != null &&
          existingCoverPath.isNotEmpty &&
          File(existingCoverPath).existsSync()) {
        results[id] = existingCoverPath;
        continue;
      }

      final format = row['file_format']?.toString().trim().toLowerCase();
      // Non-EPUB items (e.g. captured HTML imports) cannot generate a new
      // cover, but a previously cached cover whose stored absolute path went
      // stale (iOS relocates the app container between installs) can still
      // be repaired from the current root's Graphics/eLibraryCovers mirror.
      if (format != 'epub' &&
          (existingCoverPath == null || existingCoverPath.isEmpty)) {
        continue;
      }
      candidates.add(row);
    }

    if (candidates.isEmpty) {
      return results;
    }

    final warmResults = await Future.wait(
      candidates.map(
        (row) => _ensureEpubCoverPath(database: database, row: row),
      ),
    );
    for (var index = 0; index < candidates.length; index++) {
      final coverPath = warmResults[index];
      if (coverPath == null || coverPath.trim().isEmpty) {
        continue;
      }
      final id = candidates[index]['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      results[id] = coverPath;
    }

    return results;
  }

  Future<Map<String, String>> _warmMissingCaptureCoverPaths(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, String>{};
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
        selection.path;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return results;
    }
    final normalizedRootPath = rootPath.trim();
    if (!Directory(normalizedRootPath).existsSync()) {
      return results;
    }

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;

      final existingCoverPath = row['cover_path']?.toString().trim() ?? '';
      if (existingCoverPath.isNotEmpty &&
          File(existingCoverPath).existsSync()) {
        continue;
      }

      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (relativePath.isEmpty) continue;
      final normalizedRelativePath = relativePath.replaceAll('\\', '/');
      if (!normalizedRelativePath.startsWith('assets/scans/')) continue;

      final captureFilePath = p.isAbsolute(normalizedRelativePath)
          ? normalizedRelativePath
          : p.join(normalizedRootPath, normalizedRelativePath);
      final captureFolder = Directory(p.dirname(captureFilePath));
      if (!captureFolder.existsSync()) continue;

      final resolvedCoverPath = await _resolveCaptureFolderCoverPath(
        captureFolder: captureFolder,
      );
      if (resolvedCoverPath == null || resolvedCoverPath.trim().isEmpty) {
        continue;
      }

      final durableCoverPath = await cachePioneerCaptureCoverPath(
        coverPath: resolvedCoverPath,
        itemId: id,
        rootPath: normalizedRootPath,
      );
      if (durableCoverPath == null || durableCoverPath.trim().isEmpty) {
        continue;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await database.update(
        'library_items',
        {'cover_path': durableCoverPath, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      results[id] = durableCoverPath;
    }

    return results;
  }

  Future<Map<String, String>> _warmMissingAuthorValues(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, String>{};
    final candidates = <Map<String, Object?>>[];

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;

      final existingAuthor = normalizeLibraryAuthor(row['author']?.toString());
      if (existingAuthor != null) {
        results[id] = existingAuthor;
        continue;
      }

      final egwAuthor = resolveLibraryAuthor(
        author: row['author']?.toString(),
        collectionName: row['collection_name']?.toString(),
        sourceSite: row['source_site']?.toString(),
        relativePath: row['relative_path']?.toString() ?? '',
      );
      if (egwAuthor != null) {
        results[id] = egwAuthor;
        continue;
      }

      final format = row['file_format']?.toString().trim().toLowerCase();
      if (format != 'epub') continue;
      candidates.add(row);
    }

    if (candidates.isEmpty) {
      return results;
    }

    final warmResults = await Future.wait(
      candidates.map((row) => _ensureEpubAuthor(database: database, row: row)),
    );
    for (var index = 0; index < candidates.length; index++) {
      final author = warmResults[index];
      if (author == null || author.trim().isEmpty) {
        continue;
      }
      final id = candidates[index]['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      results[id] = author;
    }

    return results;
  }

  Future<Map<String, String>> _warmMissingTitleValues(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, String>{};
    final candidates = <Map<String, Object?>>[];

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;

      final existingTitle = row['title']?.toString().trim() ?? '';
      if (!_shouldWarmLibraryTitle(existingTitle)) {
        continue;
      }

      final format = row['file_format']?.toString().trim().toLowerCase();
      if (format != 'epub') continue;
      candidates.add(row);
    }

    if (candidates.isEmpty) {
      return results;
    }

    final warmResults = await Future.wait(
      candidates.map((row) => _ensureEpubTitle(database: database, row: row)),
    );
    for (var index = 0; index < candidates.length; index++) {
      final title = warmResults[index];
      if (title == null || title.trim().isEmpty) {
        continue;
      }
      final id = candidates[index]['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      results[id] = title;
    }

    return results;
  }

  Future<String> _resolveManagedTitle({
    required File file,
    required bool isEpub,
  }) async {
    if (!isEpub) {
      return p.basenameWithoutExtension(file.path);
    }

    final metadata = await readLibraryEpubMetadata(file);
    final title = metadata?.title?.trim() ?? '';
    // Accept any non-empty EPUB title unless it is itself a language-prefixed
    // code (e.g. "en GW") — which would be no better than the filename stem.
    if (title.isNotEmpty && !_isLanguagePrefixedCodeTitle(title)) {
      return title;
    }

    return p.basenameWithoutExtension(file.path).replaceAll('_', ' ').trim();
  }

  Future<String?> _resolveManagedAuthor({
    required File file,
    required bool isEpub,
    required String collectionName,
    required String relativePath,
  }) async {
    if (!isEpub) {
      return resolveLibraryAuthor(
        author: null,
        collectionName: collectionName,
        sourceSite: 'egwwritings.org',
        relativePath: relativePath,
      );
    }

    return resolveLibraryAuthorFromEpub(
      file,
      collectionName: collectionName,
      sourceSite: 'egwwritings.org',
      relativePath: relativePath,
    );
  }

  Future<List<LibraryCatalogItem>> _queryItems({
    required String where,
    required List<Object?> args,
    required int limit,
    Database? database,
  }) async {
    Future<List<Map<String, Object?>>> read(Database db) => db.rawQuery(
      '''
      SELECT
        li.id,
        li.title,
        li.author,
        li.file_name,
        li.file_hash,
        li.relative_path,
        li.file_format,
        li.folder_type,
        li.library_role,
        li.collection_name,
        li.source_site,
        li.source_url,
        li.source_type,
        li.source_work_id,
        li.source_package_id,
        li.cover_path,
        li.date_added,
        li.last_opened,
        li.index_status,
        li.index_error,
        li.file_size,
        li.mime_type,
        li.spine_index,
        li.anchor_id,
        li.epub_href,
        li.paragraph_index,
        (
          SELECT COUNT(*)
          FROM library_navigation_items lni
          WHERE lni.library_item_id = li.id
            AND lni.deleted_at IS NULL
        ) AS navigation_count
      FROM library_items li
      WHERE li.deleted_at IS NULL
        AND $where
      ORDER BY
        COALESCE(li.last_opened, li.date_added, li.created_at) DESC,
        li.title COLLATE NOCASE ASC,
        li.file_name COLLATE NOCASE ASC
      LIMIT ?
      ''',
      [...args, limit],
    );
    final rowResult = database == null
        ? await _readResolver.readWithFallback<List<Map<String, Object?>>>(
            read: read,
            hasData: (rows) => rows.isNotEmpty,
          )
        : ELibraryReadResult<List<Map<String, Object?>>>(
            database: database,
            value: await read(database),
            source: ELibraryReadSource.eLibraryDb,
          );
    final rows = rowResult.value;
    final hydratedRows = await _hydrateCatalogRows(
      rows,
      database: rowResult.database,
    );
    final hydratedRootPath = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    return hydratedRows
        .map(
          (row) => LibraryCatalogItem.fromRow(row, rootPath: hydratedRootPath),
        )
        .toList(growable: false);
  }

  Future<String?> _ensureEpubAuthor({
    required Database database,
    required Map<String, Object?> row,
  }) async {
    final id = row['id']?.toString().trim() ?? '';
    final relativePath = row['relative_path']?.toString().trim() ?? '';
    if (id.isEmpty || relativePath.isEmpty) {
      return null;
    }

    final cacheKey = '$id|$relativePath';
    return _authorWarmJobs.putIfAbsent(cacheKey, () async {
      final existingAuthor = normalizeLibraryAuthor(row['author']?.toString());
      if (existingAuthor != null) {
        return existingAuthor;
      }

      final egwFallback = resolveLibraryAuthor(
        author: row['author']?.toString(),
        collectionName: row['collection_name']?.toString(),
        sourceSite: row['source_site']?.toString(),
        relativePath: relativePath,
      );
      if (egwFallback != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        await database.update(
          'library_items',
          {'author': egwFallback, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        return egwFallback;
      }

      final selection = await LibraryRootService.instance.loadSelection();
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
          selection.path;
      if (rootPath == null || rootPath.trim().isEmpty) {
        return null;
      }
      if (!Directory(rootPath).existsSync()) {
        return null;
      }

      final epubFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: relativePath,
            rootPath: rootPath,
          );
      if (epubFile == null) {
        return null;
      }

      final author = await resolveLibraryAuthorFromEpub(
        epubFile,
        collectionName: row['collection_name']?.toString(),
        sourceSite: row['source_site']?.toString(),
        relativePath: relativePath,
      );
      if (author == null) {
        return null;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await database.update(
        'library_items',
        {'author': author, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return author;
    });
  }

  Future<String?> _ensureEpubTitle({
    required Database database,
    required Map<String, Object?> row,
  }) {
    final id = row['id']?.toString().trim() ?? '';
    final relativePath = row['relative_path']?.toString().trim() ?? '';
    if (id.isEmpty || relativePath.isEmpty) {
      return Future.value(null);
    }

    final cacheKey = '$id|$relativePath';
    return _titleWarmJobs.putIfAbsent(cacheKey, () async {
      final existingTitle = row['title']?.toString().trim() ?? '';
      if (!_shouldWarmLibraryTitle(existingTitle)) {
        return existingTitle;
      }

      final officialTitle = await _resolveOfficialDownloadTitle(row);
      if (officialTitle != null && officialTitle.trim().isNotEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        await database.update(
          'library_items',
          {'title': officialTitle, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        return officialTitle;
      }

      final selection = await LibraryRootService.instance.loadSelection();
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
          selection.path;
      if (rootPath == null || rootPath.trim().isEmpty) {
        return null;
      }
      if (!Directory(rootPath).existsSync()) {
        return null;
      }

      final epubFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: relativePath,
            rootPath: rootPath,
          );
      if (epubFile == null) {
        return null;
      }

      final metadata = await readLibraryEpubMetadata(epubFile);
      final title = metadata?.title?.trim();
      if (title == null || title.isEmpty) {
        return null;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await database.update(
        'library_items',
        {'title': title, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return title;
    });
  }

  Future<String?> _resolveOfficialDownloadTitle(
    Map<String, Object?> row,
  ) async {
    final sourceType =
        row['source_type']?.toString().trim().toLowerCase() ?? '';
    if (sourceType != 'official_download') return null;

    final titles = await _loadOfficialDownloadTitles();
    if (titles.isEmpty) return null;

    for (final candidate in _officialDownloadTitleCandidates(row)) {
      final normalized = _normalizeOfficialDownloadCode(candidate);
      if (normalized == null || normalized.isEmpty) continue;
      final manuscriptReleaseTitle = _manuscriptReleasesVolumeTitleFromCode(
        normalized,
      );
      if (manuscriptReleaseTitle != null) {
        return manuscriptReleaseTitle;
      }
      final title = titles[normalized];
      if (title != null && title.trim().isNotEmpty) {
        return title.trim();
      }
    }

    return null;
  }

  Future<Map<String, String>> _loadOfficialDownloadTitles() {
    final existing = _officialDownloadTitlesFuture;
    if (existing != null) return existing;
    final future = () async {
      try {
        final manifestJson = await rootBundle.loadString(
          'tool/elibrary_download_manifest.json',
        );
        final decoded = jsonDecode(manifestJson);
        if (decoded is! Map) return <String, String>{};
        final collections = decoded['collections'];
        if (collections is! List) return <String, String>{};
        final titles = <String, String>{};
        for (final collection in collections) {
          if (collection is! Map) continue;
          final rawItems = collection['items'];
          if (rawItems is! List) continue;
          for (final item in rawItems) {
            if (item is! Map) continue;
            final code = item['code']?.toString().trim() ?? '';
            final title = item['title']?.toString().trim() ?? '';
            if (code.isEmpty || title.isEmpty) continue;
            titles[code.toLowerCase()] = _canonicalOfficialDownloadTitle(
              code: code,
              title: title,
            );
          }
        }
        return titles;
      } catch (_) {
        return <String, String>{};
      }
    }();
    _officialDownloadTitlesFuture = future;
    return future;
  }

  Iterable<String> _officialDownloadTitleCandidates(
    Map<String, Object?> row,
  ) sync* {
    final values = <String?>[
      row['title']?.toString(),
      row['file_name']?.toString(),
      row['relative_path']?.toString(),
    ];
    for (final value in values) {
      final normalized = _normalizeOfficialDownloadCode(value);
      if (normalized != null && normalized.isNotEmpty) {
        yield normalized;
      }
    }
  }

  String? _normalizeOfficialDownloadCode(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final basename = p.basenameWithoutExtension(trimmed.replaceAll('\\', '/'));
    final candidate = basename.replaceFirst(
      RegExp(r'^(?:[a-z]{2}|[A-Z]{2})[_-]'),
      '',
    );
    final compact = candidate.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    if (compact.isEmpty) return null;
    return compact.toLowerCase();
  }

  Future<Map<String, Map<String, Object?>>> _repairMissingManagedPaths(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, Map<String, Object?>>{};
    final candidates = <Map<String, Object?>>[];

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;

      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (relativePath.isEmpty) continue;

      final format = row['file_format']?.toString().trim().toLowerCase();
      if (format != 'epub') continue;

      final title = row['title']?.toString().trim() ?? '';
      final fileName = row['file_name']?.toString().trim() ?? '';
      if (title.isEmpty || fileName.isEmpty) continue;

      candidates.add(row);
    }

    if (candidates.isEmpty) return results;

    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
        selection.path;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return results;
    }
    if (!Directory(rootPath).existsSync()) {
      return results;
    }

    final managedFolders = ELibraryFolderPolicy.allManagedEgwFolderDefinitions
        .where((folder) => folder.relativeFolder.startsWith('ePubs/'))
        .map(
          (folder) => (
            collectionName: folder.collectionName,
            relativeFolder: folder.relativeFolder,
          ),
        )
        .toList(growable: false);

    for (final row in candidates) {
      final id = row['id']?.toString().trim() ?? '';
      final fileName = row['file_name']?.toString().trim() ?? '';
      final expectedTitle = _normalizedLibraryText(
        row['title']?.toString() ?? '',
      );
      if (id.isEmpty || fileName.isEmpty || expectedTitle.isEmpty) continue;

      final currentRelativePath = row['relative_path']?.toString().trim() ?? '';
      final currentFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: currentRelativePath,
            rootPath: rootPath,
          );
      if (currentFile != null) {
        continue;
      }

      for (final managedFolder in managedFolders) {
        final candidatePath = p.join(
          rootPath,
          managedFolder.relativeFolder,
          fileName,
        );
        final candidateFile = File(candidatePath);
        if (!candidateFile.existsSync()) continue;

        final metadata = await readLibraryEpubMetadata(candidateFile);
        final candidateTitle = _normalizedLibraryText(
          metadata?.title?.toString() ?? '',
        );
        if (candidateTitle.isNotEmpty && candidateTitle != expectedTitle) {
          continue;
        }

        final stat = await candidateFile.stat();
        final now = DateTime.now().toUtc().toIso8601String();
        final fingerprint =
            'epub_nav_v3:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
        final folderType =
            row['folder_type']?.toString().trim().isNotEmpty == true
            ? row['folder_type']?.toString().trim() ?? ''
            : row['library_role']?.toString().trim() ?? '';
        final canonicalId = canonicalLibraryItemId(
          folderType: folderType,
          relativePath: p.relative(candidatePath, from: rootPath),
        );
        results[id] = <String, Object?>{
          'id': canonicalId,
          'relative_path': p.relative(candidatePath, from: rootPath),
          'collection_name': managedFolder.collectionName,
          'source_type': 'official_download',
          'file_size': stat.size,
          'file_hash': fingerprint,
          'index_status': 'indexed',
          'updated_at': now,
        };

        await database.update(
          'library_items',
          results[id]!,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (canonicalId != id) {
          await migrateManagedLibraryItemId(
            db: database,
            oldId: id,
            newId: canonicalId,
          );
        }
        break;
      }
    }

    return results;
  }

  Future<Map<String, Map<String, Object?>>> _repairManagedItemIds(
    List<Map<String, Object?>> rows, {
    required Database database,
  }) async {
    final results = <String, Map<String, Object?>>{};
    if (rows.isEmpty) return results;

    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
        selection.path;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return results;
    }
    if (!Directory(rootPath).existsSync()) {
      return results;
    }

    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (id.isEmpty || relativePath.isEmpty) continue;
      final sourceType =
          row['source_type']?.toString().trim().toLowerCase() ?? '';
      if (sourceType == 'pioneer_epub_import') continue;
      if (!isManagedEgwRelativePath(relativePath)) continue;

      final folderType =
          row['folder_type']?.toString().trim().isNotEmpty == true
          ? row['folder_type']?.toString().trim() ?? ''
          : row['library_role']?.toString().trim() ?? '';
      if (folderType.isEmpty) continue;

      final existingFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: relativePath,
            rootPath: rootPath,
          );
      if (existingFile == null) continue;

      final canonicalId = canonicalLibraryItemId(
        folderType: folderType,
        relativePath: relativePath,
      );
      if (canonicalId == id) continue;

      await migrateManagedLibraryItemId(
        db: database,
        oldId: id,
        newId: canonicalId,
      );
      results[id] = <String, Object?>{
        'id': canonicalId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    return results;
  }

  Future<String?> _ensureEpubCoverPath({
    required Database database,
    required Map<String, Object?> row,
  }) {
    final id = row['id']?.toString().trim() ?? '';
    final relativePath = row['relative_path']?.toString().trim() ?? '';
    if (id.isEmpty || relativePath.isEmpty) {
      return Future.value(null);
    }

    final cacheKey = '$id|$relativePath';
    return _coverWarmJobs.putIfAbsent(cacheKey, () async {
      final existingCoverPath = row['cover_path']?.toString().trim();
      if (existingCoverPath != null &&
          existingCoverPath.isNotEmpty &&
          _isFlutterAssetPath(existingCoverPath)) {
        return existingCoverPath;
      }
      if (existingCoverPath != null &&
          existingCoverPath.isNotEmpty &&
          File(existingCoverPath).existsSync()) {
        return existingCoverPath;
      }

      final selection = await LibraryRootService.instance.loadSelection();
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
          selection.path;
      if (rootPath == null || rootPath.trim().isEmpty) {
        return null;
      }
      if (!Directory(rootPath).existsSync()) {
        return null;
      }

      final mirroredCoverPath = await _resolveMirroredCoverPath(
        rootPath: rootPath,
        existingCoverPath: existingCoverPath,
      );
      if (mirroredCoverPath != null) {
        final now = DateTime.now().toUtc().toIso8601String();
        await database.update(
          'library_items',
          {'cover_path': mirroredCoverPath, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        return mirroredCoverPath;
      }

      final format = row['file_format']?.toString().trim().toLowerCase();
      if (format != 'epub') {
        // Mirror repair missed; only EPUBs can regenerate a cover from the
        // source file.
        return null;
      }

      final epubFile = await LibraryRootService.instance
          .resolveExistingAssetFile(
            relativePath: relativePath,
            rootPath: rootPath,
          );
      if (epubFile == null) {
        return null;
      }

      final coverPath = await _cacheEpubCover(
        file: epubFile,
        rootPath: rootPath,
        itemId: id,
      );
      if (coverPath == null) {
        return null;
      }

      final now = DateTime.now().toUtc().toIso8601String();
      await database.update(
        'library_items',
        {'cover_path': coverPath, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return coverPath;
    });
  }

  Future<String?> _resolveMirroredCoverPath({
    required String rootPath,
    required String? existingCoverPath,
  }) async {
    final coverPath = existingCoverPath?.trim() ?? '';
    if (coverPath.isEmpty) return null;
    final fileName = p.basename(coverPath);
    if (fileName.isEmpty) return null;
    final mirrorPath = p.join(rootPath, 'Graphics', 'eLibraryCovers', fileName);
    final mirrorFile = File(mirrorPath);
    if (await mirrorFile.exists()) {
      return mirrorPath;
    }
    return null;
  }

  Future<String?> _resolveCaptureFolderCoverPath({
    required Directory captureFolder,
  }) async {
    final allFiles = captureFolder
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .map((file) => file.path)
        .toList(growable: false);
    final metadata = PioneerCaptureFolderMetadata.fromFolder(
      captureFolder,
      availableFiles: allFiles,
    );
    final metadataCoverPath = metadata.coverImagePath?.trim() ?? '';
    if (metadataCoverPath.isNotEmpty && File(metadataCoverPath).existsSync()) {
      return metadataCoverPath;
    }

    final folderName = p.basename(captureFolder.path);
    final candidatePaths = <String>[
      p.join(captureFolder.path, 'cover.jpg'),
      p.join(captureFolder.path, 'cover.jpeg'),
      p.join(captureFolder.path, 'cover.png'),
      p.join(captureFolder.path, 'cover.webp'),
      p.join(captureFolder.path, 'thumbnail.jpg'),
      p.join(captureFolder.path, 'thumbnail.jpeg'),
      p.join(captureFolder.path, 'thumbnail.png'),
      p.join(captureFolder.path, 'thumbnail.webp'),
      p.join(captureFolder.path, 'images', '$folderName.png'),
      p.join(captureFolder.path, 'images', '$folderName.jpg'),
      p.join(captureFolder.path, 'images', 'cover.png'),
      p.join(captureFolder.path, 'images', 'cover.jpg'),
      p.join(captureFolder.path, 'images', 'thumbnail.png'),
      p.join(captureFolder.path, 'images', 'thumbnail.jpg'),
    ];
    for (final candidate in candidatePaths) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    for (final filePath in allFiles) {
      if (_isImageFile(filePath) && File(filePath).existsSync()) {
        return filePath;
      }
    }

    return null;
  }

  bool _isImageFile(String pathValue) {
    switch (p.extension(pathValue).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.webp':
      case '.gif':
      case '.bmp':
        return true;
      default:
        return false;
    }
  }

  Future<String?> _cacheEpubCover({
    required File file,
    required String rootPath,
    required String itemId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final cover = LibraryEpubCoverExtractor.extractCoverImage(bytes);
      if (cover == null) return null;

      final coverDir = Directory(
        p.join(rootPath, 'Graphics', 'eLibraryCovers'),
      );
      await coverDir.create(recursive: true);
      final coverPath = p.join(coverDir.path, '$itemId${cover.extension}');
      await File(coverPath).writeAsBytes(cover.bytes, flush: true);
      return coverPath;
    } catch (_) {
      return null;
    }
  }

  bool _shouldWarmLibraryTitle(String title) {
    final normalized = title.trim();
    if (normalized.isEmpty) return true;
    if (_looksLikeFilename(normalized)) return true;
    // Language-prefixed codes like "en GW" or "en 1TT" stored from filename
    // stems must be replaced with the real EPUB title.
    if (_isLanguagePrefixedCodeTitle(normalized)) return true;
    if (RegExp(r'\d').hasMatch(normalized)) {
      return true;
    }
    final uppercaseish = normalized.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    if (uppercaseish.isNotEmpty &&
        uppercaseish.length <= 12 &&
        uppercaseish == uppercaseish.toUpperCase()) {
      return true;
    }
    return false;
  }
}

class LibraryCatalogItem {
  const LibraryCatalogItem({
    required this.id,
    required this.title,
    required this.author,
    required this.fileName,
    required this.fileHash,
    required this.relativePath,
    required this.fileFormat,
    required this.folderType,
    required this.libraryRole,
    required this.collectionName,
    required this.sourceSite,
    required this.sourceUrl,
    required this.sourceType,
    required this.coverPath,
    required this.dateAdded,
    required this.lastOpened,
    required this.indexStatus,
    this.indexError,
    required this.fileSize,
    required this.mimeType,
    required this.spineIndex,
    required this.anchorId,
    required this.epubHref,
    required this.paragraphIndex,
    required this.navigationCount,
    this.sourceWorkId,
    this.sourcePackageId,
    this.readableBlockCount = 0,
    this.extractedTextLength = 0,
    this.navigationMaxDepth = 0,
    this.contributors = const [],
  });

  factory LibraryCatalogItem.fromRow(
    Map<String, Object?> row, {
    String? rootPath,
  }) {
    final coverPathValue = row['cover_path']?.toString().trim();
    final resolvedCoverPath = _resolveCoverPath(
      coverPathValue,
      rootPath: rootPath,
    );
    return LibraryCatalogItem(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      author: row['author']?.toString(),
      fileName: row['file_name']?.toString() ?? '',
      fileHash: row['file_hash']?.toString(),
      relativePath: row['relative_path']?.toString() ?? '',
      fileFormat: row['file_format']?.toString(),
      folderType: row['folder_type']?.toString(),
      libraryRole: row['library_role']?.toString(),
      collectionName: row['collection_name']?.toString(),
      sourceSite: row['source_site']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      sourceType: row['source_type']?.toString(),
      coverPath: resolvedCoverPath,
      dateAdded: _parseDate(row['date_added']?.toString()),
      lastOpened: _parseDate(row['last_opened']?.toString()),
      indexStatus: row['index_status']?.toString(),
      indexError: row['index_error']?.toString(),
      fileSize: (row['file_size'] as num?)?.toInt(),
      mimeType: row['mime_type']?.toString(),
      spineIndex: (row['spine_index'] as num?)?.toInt(),
      anchorId: row['anchor_id']?.toString(),
      epubHref: row['epub_href']?.toString(),
      paragraphIndex: (row['paragraph_index'] as num?)?.toInt(),
      navigationCount: (row['navigation_count'] as num?)?.toInt() ?? 0,
      sourceWorkId: row['source_work_id']?.toString(),
      sourcePackageId: row['source_package_id']?.toString(),
      readableBlockCount: (row['readable_block_count'] as num?)?.toInt() ?? 0,
      extractedTextLength: (row['extracted_text_length'] as num?)?.toInt() ?? 0,
      navigationMaxDepth: (row['navigation_max_depth'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String fileName;
  final String? fileHash;
  final String relativePath;
  final String? fileFormat;
  final String? folderType;
  final String? libraryRole;
  final String? collectionName;
  final String? sourceSite;
  final String? sourceUrl;
  final String? sourceType;
  final String? coverPath;
  final DateTime? dateAdded;
  final DateTime? lastOpened;
  final String? indexStatus;
  final String? indexError;
  final int? fileSize;
  final String? mimeType;
  final int? spineIndex;
  final String? anchorId;
  final String? epubHref;
  final int? paragraphIndex;
  final int navigationCount;
  final String? sourceWorkId;
  final String? sourcePackageId;
  final int readableBlockCount;
  final int extractedTextLength;
  final int navigationMaxDepth;
  final List<LibraryItemContributor> contributors;

  bool get isEpub {
    final normalizedFileFormat = (fileFormat ?? '').toLowerCase();
    if (normalizedFileFormat == 'epub') return true;
    if (normalizedFileFormat != 'html') return false;
    return collectionGroupKey == 'adventist_pioneer_library';
  }

  bool get isPdf => (fileFormat ?? '').toLowerCase() == 'pdf';

  bool get isDevotional {
    final normalizedCollection = _normalizedLibraryText(collectionName);
    if (normalizedCollection.contains('egw devotionals')) return true;

    final normalizedPath = _normalizedLibraryText(relativePath);
    if (normalizedPath.contains('egw devotionals')) return true;

    final normalizedRole = _normalizedLibraryText(libraryRole);
    if (normalizedRole.contains('devotional')) return true;

    return false;
  }

  bool get isPeriodical {
    final normalizedCollection = _normalizedLibraryText(collectionName);
    if (normalizedCollection.contains('egw periodicals')) return true;

    final normalizedPath = _normalizedLibraryText(relativePath);
    if (normalizedPath.contains('egw periodicals')) return true;

    return false;
  }

  LibraryCatalogItem copyWith({
    String? title,
    String? author,
    String? fileName,
    String? fileHash,
    String? relativePath,
    String? fileFormat,
    String? folderType,
    String? libraryRole,
    String? collectionName,
    String? sourceSite,
    String? sourceUrl,
    String? sourceType,
    String? coverPath,
    DateTime? dateAdded,
    DateTime? lastOpened,
    String? indexStatus,
    String? indexError,
    int? fileSize,
    String? mimeType,
    int? spineIndex,
    String? anchorId,
    String? epubHref,
    int? paragraphIndex,
    int? navigationCount,
    List<LibraryItemContributor>? contributors,
  }) {
    return LibraryCatalogItem(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      fileName: fileName ?? this.fileName,
      fileHash: fileHash ?? this.fileHash,
      relativePath: relativePath ?? this.relativePath,
      fileFormat: fileFormat ?? this.fileFormat,
      folderType: folderType ?? this.folderType,
      libraryRole: libraryRole ?? this.libraryRole,
      collectionName: collectionName ?? this.collectionName,
      sourceSite: sourceSite ?? this.sourceSite,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceType: sourceType ?? this.sourceType,
      coverPath: coverPath ?? this.coverPath,
      dateAdded: dateAdded ?? this.dateAdded,
      lastOpened: lastOpened ?? this.lastOpened,
      indexStatus: indexStatus ?? this.indexStatus,
      indexError: indexError ?? this.indexError,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      spineIndex: spineIndex ?? this.spineIndex,
      anchorId: anchorId ?? this.anchorId,
      epubHref: epubHref ?? this.epubHref,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      navigationCount: navigationCount ?? this.navigationCount,
      contributors: contributors ?? this.contributors,
    );
  }

  String get folderRoot {
    final normalized = relativePath.replaceAll('\\', '/').toLowerCase();
    if (normalized.startsWith('epubs/')) return 'ePubs';
    if (normalized.startsWith('pdfs/')) return 'PDFs';
    return 'All';
  }

  String get collectionGroupKey => libraryCollectionFilterValueForItem(this);

  String get collectionGroupLabel => libraryCollectionFilterLabelForItem(this);

  String get displayTitle => _stripCatalogEditionCodeSuffix(_rawDisplayTitle);

  String get _rawDisplayTitle {
    final trimmed = title.trim();
    if (_isWaggonerOnRomansEdition(this)) return 'Waggoner on Romans';
    if (trimmed.isEmpty) {
      return _humanizeFileName(fileName);
    }
    final canonicalManuscriptReleaseTitle =
        _canonicalManuscriptReleasesDisplayTitle(
          title: trimmed,
          fileName: fileName,
          relativePath: relativePath,
        );
    if (canonicalManuscriptReleaseTitle != null) {
      return canonicalManuscriptReleaseTitle;
    }
    if (_looksLikeFilename(trimmed)) {
      return _humanizeFileName(trimmed);
    }
    if (isPeriodical) {
      final canonical = _canonicalPeriodicalTitle(trimmed);
      if (canonical != null) return canonical;
    }
    return normalizeBookDisplayTitle(
      trimmed,
      fallbacks: <String?>[_humanizeFileName(fileName)],
    );
  }

  String get subtitle {
    final authorPart = displayAuthors;
    final parts = <String>[
      if (authorPart.isNotEmpty) authorPart,
      if ((collectionName ?? '').trim().isNotEmpty) collectionName!.trim(),
    ];
    if (parts.isEmpty) return _fileTypeLabel;
    return parts.join(' • ');
  }

  String get displayAuthor {
    if (_isWaggonerOnRomansEdition(this)) return 'E. J. Waggoner';
    final normalizedAuthor = normalizeLibraryAuthor(author);
    if (normalizedAuthor != null) return normalizedAuthor;
    final resolved = resolveLibraryAuthor(
      author: author,
      collectionName: collectionName,
      sourceSite: sourceSite,
      relativePath: relativePath,
    );
    return resolved ?? 'Unknown author';
  }

  /// Human-readable provenance for editions that otherwise look identical.
  String? get editionLabel {
    if (!_isWaggonerOnRomansEdition(this)) return null;
    if (id == 'library_item_research_pioneer_e_j_waggoner_WOR') {
      return 'CaptureClipper edition';
    }
    return 'Official EPUB edition';
  }

  /// All contributor display names joined with "; ".
  /// e.g. "A. T. Jones; E. J. Waggoner"
  /// Falls back to [displayAuthor] when no contributors are loaded.
  String get displayAuthors {
    if (_isWaggonerOnRomansEdition(this)) return displayAuthor;
    if (contributors.isNotEmpty) {
      return displayAuthorsFromContributors(contributors);
    }
    return displayAuthor;
  }

  /// Contributor last names joined with " & ".
  /// e.g. "Jones & Waggoner"
  /// Falls back to [displayAuthor] when no contributors are loaded.
  String get shortAuthors {
    if (contributors.isNotEmpty) {
      return shortAuthorsFromContributors(contributors);
    }
    // Parse the denormalized author field if it contains ";".
    final a = author?.trim() ?? '';
    if (a.contains(';')) return shortAuthorsFromDisplayString(a);
    return displayAuthor;
  }

  String get _fileTypeLabel {
    if (isPdf) return 'PDF';
    if (isEpub) return 'EPUB';
    return 'Book';
  }
}

class LibraryCatalogSearchResult {
  const LibraryCatalogSearchResult({
    required this.item,
    required this.snippet,
    required this.locationText,
    required this.score,
    this.referenceText,
    this.fullParagraph,
    this.chapterNumber,
    this.verseStart,
    this.verseEnd,
    this.target,
  });

  final LibraryCatalogItem item;
  final String snippet;
  final String locationText;
  final int score;
  final String? referenceText;
  final String? fullParagraph;
  final int? chapterNumber;
  final int? verseStart;
  final int? verseEnd;
  final LibrarySearchNavigationTarget? target;

  LibrarySearchNavigationTarget? targetForQuery(String query) =>
      target?.withQuery(query);
}

class LibraryCatalogSearchSession {
  const LibraryCatalogSearchSession({
    required this.query,
    required this.collectionFilter,
    required this.results,
    required this.currentIndex,
  });

  final String query;
  final String? collectionFilter;
  final List<LibraryCatalogSearchResult> results;
  final int currentIndex;

  LibraryCatalogSearchResult get currentResult => results[currentIndex];

  String get counterLabel => '${currentIndex + 1} / ${results.length}';

  bool get hasPrevious => currentIndex > 0;

  bool get hasNext => currentIndex < results.length - 1;

  LibraryCatalogSearchSession copyWithIndex(int index) {
    return LibraryCatalogSearchSession(
      query: query,
      collectionFilter: collectionFilter,
      results: results,
      currentIndex: index.clamp(0, results.length - 1),
    );
  }
}

class LibraryCatalogSearchSessionSnapshot {
  const LibraryCatalogSearchSessionSnapshot({
    required this.query,
    required this.totalCount,
    this.collectionFilter,
    this.currentIndex,
  });

  final String query;
  final String? collectionFilter;
  final int? currentIndex;
  final int totalCount;

  bool get hasCurrentIndex => currentIndex != null && totalCount > 0;

  String get counterLabel {
    if (!hasCurrentIndex) {
      return totalCount > 0 ? '$totalCount' : '0';
    }
    return '${currentIndex! + 1} / $totalCount';
  }

  bool get hasPrevious => hasCurrentIndex && currentIndex! > 0;

  bool get hasNext => hasCurrentIndex && currentIndex! < totalCount - 1;

  LibraryCatalogSearchSessionSnapshot copyWithIndex(int index) {
    final clamped = totalCount <= 0 ? null : index.clamp(0, totalCount - 1);
    return LibraryCatalogSearchSessionSnapshot(
      query: query,
      collectionFilter: collectionFilter,
      currentIndex: clamped?.toInt(),
      totalCount: totalCount,
    );
  }

  LibraryCatalogSearchSessionSnapshot copyWith({
    String? query,
    String? collectionFilter,
    int? currentIndex,
    int? totalCount,
  }) {
    return LibraryCatalogSearchSessionSnapshot(
      query: query ?? this.query,
      collectionFilter: collectionFilter ?? this.collectionFilter,
      currentIndex: currentIndex ?? this.currentIndex,
      totalCount: totalCount ?? this.totalCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'query': query,
      if (collectionFilter != null && collectionFilter!.trim().isNotEmpty)
        'collectionFilter': collectionFilter!.trim(),
      if (currentIndex != null) 'currentIndex': currentIndex,
      'totalCount': totalCount,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static LibraryCatalogSearchSessionSnapshot? fromJsonString(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return null;
      final query = decoded['query']?.toString().trim() ?? '';
      final totalCount = (decoded['totalCount'] as num?)?.toInt() ?? 0;
      final currentIndex = (decoded['currentIndex'] as num?)?.toInt();
      final collectionFilter = decoded['collectionFilter']?.toString().trim();
      if (query.isEmpty && totalCount <= 0 && currentIndex == null) {
        return null;
      }
      return LibraryCatalogSearchSessionSnapshot(
        query: query,
        collectionFilter: collectionFilter == null || collectionFilter.isEmpty
            ? null
            : collectionFilter,
        currentIndex: currentIndex,
        totalCount: totalCount,
      );
    } catch (_) {
      return null;
    }
  }

  static LibraryCatalogSearchSessionSnapshot fromSession(
    LibraryCatalogSearchSession session,
  ) {
    return LibraryCatalogSearchSessionSnapshot(
      query: session.query,
      collectionFilter: session.collectionFilter,
      currentIndex: session.currentIndex,
      totalCount: session.results.length,
    );
  }
}

class LibraryCatalogNavigationItem {
  const LibraryCatalogNavigationItem({
    required this.id,
    required this.parentId,
    required this.label,
    required this.href,
    required this.anchorId,
    required this.spineIndex,
    required this.sortOrder,
    required this.depth,
    required this.navType,
    required this.contentKind,
    required this.isFrontMatter,
    required this.isBodyStart,
    required this.bodyOrder,
  });

  final String id;
  final String? parentId;
  final String label;
  final String? href;
  final String? anchorId;
  final int? spineIndex;
  final int? sortOrder;
  final int? depth;
  final String? navType;
  final String? contentKind;
  final bool isFrontMatter;
  final bool isBodyStart;
  final int? bodyOrder;

  LibraryCatalogNavigationItem copyWith({
    bool? isFrontMatter,
    bool? isBodyStart,
  }) {
    return LibraryCatalogNavigationItem(
      id: id,
      parentId: parentId,
      label: label,
      href: href,
      anchorId: anchorId,
      spineIndex: spineIndex,
      sortOrder: sortOrder,
      depth: depth,
      navType: navType,
      contentKind: contentKind,
      isFrontMatter: isFrontMatter ?? this.isFrontMatter,
      isBodyStart: isBodyStart ?? this.isBodyStart,
      bodyOrder: bodyOrder,
    );
  }
}

String? _buildLibrarySearchSnippet({
  required String? fullParagraph,
  required List<String> terms,
}) {
  final source = _cleanLibrarySearchText(fullParagraph ?? '');
  if (source.isEmpty) return null;

  final rankedTerms = terms.toSet().toList(growable: false)
    ..sort((left, right) => right.length.compareTo(left.length));

  var matchStart = -1;
  var matchLength = 0;
  for (final term in rankedTerms) {
    final cleaned = _normalizedLibrarySearchText(term);
    if (cleaned.isEmpty) continue;
    final pattern = _buildLibrarySearchSnippetPattern(cleaned);
    final match = pattern.firstMatch(source);
    if (match == null) continue;
    if (matchStart == -1 || match.start < matchStart) {
      matchStart = match.start;
      matchLength = match.end - match.start;
    }
  }

  if (matchStart < 0) {
    return null;
  }

  final sentenceSnippet = _buildLibrarySentenceSnippet(
    source: source,
    matchStart: matchStart,
    matchEnd: matchStart + matchLength,
  );
  if (sentenceSnippet != null && sentenceSnippet.isNotEmpty) {
    return sentenceSnippet;
  }

  final start = matchStart > 90 ? matchStart - 90 : 0;
  final end = (matchStart + matchLength + 120) < source.length
      ? matchStart + matchLength + 120
      : source.length;
  final prefix = start > 0 ? '...' : '';
  final suffix = end < source.length ? '...' : '';
  return '$prefix${source.substring(start, end).trim()}$suffix';
}

String? _buildLibrarySentenceSnippet({
  required String source,
  required int matchStart,
  required int matchEnd,
}) {
  final sentencePattern = RegExp(r'[^.!?]+(?:[.!?]+|$)');
  final sentences = <({int start, int end, String text})>[];
  for (final match in sentencePattern.allMatches(source)) {
    final text = match.group(0)?.trim();
    if (text == null || text.isEmpty) continue;
    sentences.add((
      start: match.start,
      end: match.end,
      text: text.replaceAll(RegExp(r'\s+'), ' ').trim(),
    ));
  }
  if (sentences.isEmpty) return null;

  var sentenceIndex = -1;
  for (var index = 0; index < sentences.length; index++) {
    final sentence = sentences[index];
    if (matchStart >= sentence.start && matchStart < sentence.end) {
      sentenceIndex = index;
      break;
    }
  }
  if (sentenceIndex < 0) return null;

  var startIndex = sentenceIndex;
  var endIndex = sentenceIndex;
  final sentenceText = sentences[sentenceIndex].text;
  final matchLength = matchEnd - matchStart;
  final needsMoreContext = sentenceText.length < 140 || matchLength < 24;

  if (needsMoreContext) {
    final matchOffset = matchStart - sentences[sentenceIndex].start;
    final preferNext = matchOffset > (sentenceText.length ~/ 2);
    if (preferNext && endIndex + 1 < sentences.length) {
      endIndex += 1;
    } else if (!preferNext && startIndex > 0) {
      startIndex -= 1;
    } else if (endIndex + 1 < sentences.length) {
      endIndex += 1;
    } else if (startIndex > 0) {
      startIndex -= 1;
    }
  }

  if (startIndex == endIndex &&
      sentenceText.length < 90 &&
      endIndex + 1 < sentences.length) {
    endIndex += 1;
  }

  final selected = sentences.sublist(startIndex, endIndex + 1);
  final prefix = startIndex > 0 ? '...' : '';
  final suffix = endIndex < sentences.length - 1 ? '...' : '';
  final body = selected.map((sentence) => sentence.text).join(' ').trim();
  return body.isEmpty ? null : '$prefix$body$suffix';
}

RegExp _buildLibrarySearchSnippetPattern(String term) {
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

List<String> extractLibrarySearchHighlightTerms(String query) {
  return extractSearchHighlightTerms(query, booleanSyntax: true);
}

const List<String> _librarySearchClauseFields = <String>[
  'LOWER(COALESCE(ltb.plain_text, \'\')) LIKE ?',
  'LOWER(COALESCE(ltb.section_title, \'\')) LIKE ?',
  'LOWER(COALESCE(li.title, \'\')) LIKE ?',
  'LOWER(COALESCE(li.author, \'\')) LIKE ?',
  'LOWER(COALESCE(li.collection_name, \'\')) LIKE ?',
];

String _librarySearchTermClause() {
  return _librarySearchClauseFields.join(' OR ');
}

// For multi-word phrases, join with % so punctuation between words is
// absorbed (e.g. "trouble, we" matches pattern %trouble%we%).
// Single-word terms keep the simpler %word% form.
String _librarySearchLikePattern(String normalizedTerm) {
  final words = normalizedTerm
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList(growable: false);
  if (words.length <= 1) return '%$normalizedTerm%';
  return '%${words.join('%')}%';
}

String? canonicalLibraryWorkId(LibraryCatalogItem item) {
  const explicitItemMappings = <String, String>{
    'library_item_research_pioneer_s_n_haskell_SSP_SNH': 'SSP',
    'library_item_research_pioneer_stephen_nelson_haskell_SSP': 'SSP',
    'library_item_research_epubs_egw_egw_pamphlets_en_spta02b_epub':
        'EGW:PAMPHLET:SPTA02B',
    'library_item_research_epubs_egw_egw_pamphlets_en_ph133_epub':
        'EGW:PAMPHLET:SPTA02B',
  };
  final explicit = explicitItemMappings[item.id];
  if (explicit != null) return explicit;
  final raw = item.sourceWorkId?.trim().toUpperCase() ?? '';
  if (raw.isEmpty) return null;
  // The official Pioneer catalog historically used WOR_EJW while the
  // CaptureClipper package uses WOR for the same stable catalog work.
  if (raw == 'WOR_EJW') return 'WOR';
  return raw;
}

int libraryEditionQualityScore(LibraryCatalogItem item) {
  var score = 0;
  score += (item.extractedTextLength ~/ 1000).clamp(0, 1000);
  score += item.readableBlockCount.clamp(0, 1000);
  score += item.navigationCount.clamp(0, 500) * 2;
  score += item.navigationMaxDepth.clamp(0, 10) * 20;
  if ((item.indexStatus ?? '').toLowerCase() == 'indexed') score += 100;
  if (item.title.trim().isNotEmpty && !_looksLikeFilename(item.title)) {
    score += 20;
  }
  if (normalizeLibraryAuthor(item.author) != null) score += 20;
  if ((item.coverPath ?? '').trim().isNotEmpty) score += 20;
  if ((item.indexError ?? '').trim().isNotEmpty) score -= 200;
  return score;
}

class LibraryEditionSelectionDecision {
  const LibraryEditionSelectionDecision({
    required this.workId,
    required this.editions,
    required this.preferredEdition,
    required this.preferredQualityScore,
    required this.preferredSourcePriority,
    required this.reason,
  });

  final String? workId;
  final List<LibraryCatalogItem> editions;
  final LibraryCatalogItem preferredEdition;
  final int preferredQualityScore;
  final int preferredSourcePriority;
  final String reason;
}

LibraryEditionSelectionDecision describePreferredLibraryEdition(
  Iterable<LibraryCatalogItem> editions,
) {
  final ranked = editions.toList(growable: false)
    ..sort((left, right) {
      final score = libraryEditionQualityScore(
        right,
      ).compareTo(libraryEditionQualityScore(left));
      if (score != 0) return score;
      final source = _libraryItemSourcePriority(
        right,
      ).compareTo(_libraryItemSourcePriority(left));
      if (source != 0) return source;
      final package = _packageBackedSourcePriority(
        right,
      ).compareTo(_packageBackedSourcePriority(left));
      if (package != 0) return package;
      return left.id.compareTo(right.id);
    });
  if (ranked.isEmpty) {
    throw ArgumentError.value(editions, 'editions', 'must not be empty');
  }

  final preferred = ranked.first;
  final preferredScore = libraryEditionQualityScore(preferred);
  final preferredSourcePriority = _libraryItemSourcePriority(preferred);
  final workId = canonicalLibraryWorkId(preferred);
  final reasons = <String>[];
  for (final candidate in ranked.skip(1)) {
    final candidateScore = libraryEditionQualityScore(candidate);
    if (preferredScore != candidateScore) {
      reasons.add(
        preferredScore > candidateScore
            ? 'higher quality score than ${candidate.id}'
            : 'lower quality score than ${candidate.id}',
      );
      continue;
    }

    final candidateSourcePriority = _libraryItemSourcePriority(candidate);
    if (preferredSourcePriority != candidateSourcePriority) {
      reasons.add(
        preferredSourcePriority > candidateSourcePriority
            ? 'preferred source tier over ${candidate.id}'
            : 'lower source tier than ${candidate.id}',
      );
      continue;
    }

    final candidatePackageId = candidate.sourcePackageId ?? '';
    final preferredPackageId = preferred.sourcePackageId ?? '';
    if (preferredPackageId != candidatePackageId) {
      reasons.add('deterministic package-id tie-break');
      continue;
    }

    if (preferred.id != candidate.id) {
      reasons.add('deterministic item-id tie-break');
    }
  }

  return LibraryEditionSelectionDecision(
    workId: workId,
    editions: ranked,
    preferredEdition: preferred,
    preferredQualityScore: preferredScore,
    preferredSourcePriority: preferredSourcePriority,
    reason: reasons.isEmpty ? 'single edition' : reasons.join('; '),
  );
}

int _packageBackedSourcePriority(LibraryCatalogItem item) {
  final sourceType = item.sourceType?.trim().toLowerCase() ?? '';
  final isHtmlCapture =
      sourceType == 'egw_html_capture' || sourceType == 'pioneer_captured_html';
  if (!isHtmlCapture) return 0;
  return (item.sourcePackageId ?? '').trim().isEmpty ? 0 : 1;
}

LibraryCatalogItem preferredLibraryEdition(
  Iterable<LibraryCatalogItem> editions,
) {
  return describePreferredLibraryEdition(editions).preferredEdition;
}

List<LibraryCatalogItem> selectPreferredLibraryEditions(
  List<LibraryCatalogItem> items,
) {
  final editionsByWork = <String, List<LibraryCatalogItem>>{};
  final ungrouped = <LibraryCatalogItem>[];
  for (final item in items) {
    final workId = canonicalLibraryWorkId(item);
    if (workId == null) {
      ungrouped.add(item);
    } else {
      (editionsByWork[workId] ??= <LibraryCatalogItem>[]).add(item);
    }
  }
  final visible = <LibraryCatalogItem>[
    ...ungrouped,
    for (final editions in editionsByWork.values)
      preferredLibraryEdition(editions),
  ]..sort(_compareLibraryCatalogItems);
  return List<LibraryCatalogItem>.unmodifiable(visible);
}

int _libraryItemSourcePriority(LibraryCatalogItem item) {
  final sourceType = (item.sourceType ?? '').trim().toLowerCase();
  if (sourceType == 'official_download') return 2;
  if (sourceType == 'user_added') return 0;

  final normalizedCollection = _normalizedLibraryText(item.collectionName);
  if (normalizedCollection == 'user') return 0;
  if (normalizedCollection == 'egw books' ||
      normalizedCollection == 'egw devotionals' ||
      normalizedCollection == 'egw commentaries') {
    return 2;
  }

  final sourceSite = (item.sourceSite ?? '').trim().toLowerCase();
  if (sourceSite == 'egwwritings.org') return 2;

  return 1;
}

bool _isVisibleLibraryItem(LibraryCatalogItem item) {
  return libraryItemIsNormallyReadable(item);
}

bool _isWaggonerOnRomansEdition(LibraryCatalogItem item) {
  return _isWaggonerOnRomansItemId(item.id);
}

bool _isWaggonerOnRomansItemId(String id) =>
    id == 'library_item_research_pioneer_e_j_waggoner_WOR' ||
    id == 'library_item_research_pioneer_ellet_joseph_waggoner_WOR_EJW';

List<LibraryCatalogNavigationItem> _waggonerRomansNavigationHierarchy(
  List<LibraryCatalogNavigationItem> items,
) {
  String? titleId;
  String? chapterId;
  String? studiesId;
  String? dateId;
  final result = <LibraryCatalogNavigationItem>[];
  for (final item in items) {
    final label = item.label.trim().toUpperCase();
    var depth = 4;
    var contentKind = item.contentKind;
    var isFrontMatter = item.isFrontMatter;
    String? parentId = dateId ?? studiesId ?? chapterId ?? titleId;
    if (label == 'WAGGONER ON ROMANS.') {
      depth = 0;
      parentId = null;
      titleId = item.id;
    } else if (label == 'PREFACE.') {
      depth = 1;
      parentId = titleId;
      contentKind = 'preface';
      isFrontMatter = true;
    } else if (RegExp(r'^CHAPTER\s+\d+\.?$').hasMatch(label)) {
      depth = 1;
      parentId = titleId;
      chapterId = item.id;
      studiesId = null;
      dateId = null;
    } else if (label == 'STUDIES IN ROMANS.') {
      depth = 2;
      parentId = chapterId ?? titleId;
      studiesId = item.id;
      dateId = null;
    } else if (RegExp(
      r'^(JANUARY|FEBRUARY|MARCH|APRIL|MAY|JUNE|JULY|AUGUST|SEPTEMBER|OCTOBER|NOVEMBER|DECEMBER)\s+\d{1,2},\s+\d{4}\.?$',
    ).hasMatch(label)) {
      depth = 3;
      parentId = studiesId ?? chapterId ?? titleId;
      dateId = item.id;
    }
    result.add(
      LibraryCatalogNavigationItem(
        id: item.id,
        parentId: parentId,
        label: item.label,
        href: item.href,
        anchorId: item.anchorId,
        spineIndex: item.spineIndex,
        sortOrder: item.sortOrder,
        depth: depth,
        navType: item.navType,
        contentKind: contentKind,
        isFrontMatter: isFrontMatter,
        isBodyStart: item.isBodyStart,
        bodyOrder: item.bodyOrder,
      ),
    );
  }
  return result;
}

bool _isFlutterAssetPath(String path) {
  return path.trim().replaceAll('\\', '/').startsWith('assets/');
}

/// Resolves a stored `cover_path` for display, tolerating a cover cached by
/// a *different* device sharing the same synced Library Root. Cover files
/// are cached under `<root>/Graphics/eLibraryCovers/<name>`
/// (`cachePioneerCaptureCoverPath` in `pioneer_capture_folder_metadata.dart`)
/// but historically stored as an absolute path — valid only on the device
/// that wrote it (e.g. a macOS path baked into a Library Root also opened
/// from Android). When the stored absolute path doesn't exist locally, retry
/// by basename under the current device's root before giving up, so a cover
/// cached on one platform still renders on another without needing a
/// database migration.
String? _resolveCoverPath(String? coverPathValue, {String? rootPath}) {
  if (coverPathValue == null || coverPathValue.isEmpty) return null;
  if (_isFlutterAssetPath(coverPathValue)) return coverPathValue;
  if (File(coverPathValue).existsSync()) return coverPathValue;
  final normalizedRoot = rootPath?.trim() ?? '';
  if (normalizedRoot.isEmpty) return null;
  final fileName = p.basename(coverPathValue);
  if (fileName.isEmpty) return null;
  final candidate = p.join(
    normalizedRoot,
    'Graphics',
    'eLibraryCovers',
    fileName,
  );
  return File(candidate).existsSync() ? candidate : null;
}

int _compareLibraryCatalogItems(LibraryCatalogItem a, LibraryCatalogItem b) {
  final aStamp =
      a.lastOpened ?? a.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bStamp =
      b.lastOpened ?? b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
  final recencyCompare = bStamp.compareTo(aStamp);
  if (recencyCompare != 0) return recencyCompare;

  final titleCompare = a.displayTitle.toLowerCase().compareTo(
    b.displayTitle.toLowerCase(),
  );
  if (titleCompare != 0) return titleCompare;

  final authorCompare = (a.author ?? '').toLowerCase().compareTo(
    (b.author ?? '').toLowerCase(),
  );
  if (authorCompare != 0) return authorCompare;

  return a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
}
