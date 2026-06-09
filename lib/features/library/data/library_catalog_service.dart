import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/user_database.dart';
import 'library_citation_display_helper.dart';
import '../../search/search_highlight_helper.dart';
import 'library_author_resolver.dart';
import 'library_epub_metadata.dart';
import 'library_item_identity.dart';
import '../../utilities/data/elibrary_folder_policy.dart';

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

  Future<List<LibraryCatalogItem>> loadItems({
    String folderRoot = 'all',
  }) async {
    await LibraryRootService.instance.accessibleLibraryRootPath();
    final db = await UserDatabase.instance.database;
    final normalized = folderRoot.trim().toLowerCase();
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];

    where.add(
      "(LOWER(COALESCE(file_format, '')) = ? OR LOWER(COALESCE(file_format, '')) = ?)",
    );
    args.addAll(['epub', 'pdf']);

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

    final rows = await db.rawQuery('''
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
        li.cover_path,
        li.date_added,
        li.last_opened,
        li.index_status,
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
      WHERE ${where.join(' AND ')}
      ORDER BY
        COALESCE(li.last_opened, li.date_added, li.created_at) DESC,
        li.title COLLATE NOCASE ASC,
        li.file_name COLLATE NOCASE ASC
    ''', args);

    final warmedAuthorValues = await _warmMissingAuthorValues(rows);
    final warmedCoverPaths = await _warmMissingCoverPaths(rows);
    final warmedTitleValues = await _warmMissingTitleValues(rows);
    final repairedManagedPaths = await _repairMissingManagedPaths(rows);
    final hydratedRows = rows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final warmedAuthor = warmedAuthorValues[id];
          final warmedCoverPath = warmedCoverPaths[id];
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
            if (warmedTitle != null && warmedTitle.trim().isNotEmpty)
              'title': warmedTitle,
            if (repairedPathValues != null) ...repairedPathValues,
          };
        })
        .toList(growable: false);

    final repairedManagedIds = await _repairManagedItemIds(hydratedRows);
    final normalizedRows = hydratedRows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final repairedIdValues = repairedManagedIds[id];
          if (repairedIdValues == null) return row;
          return <String, Object?>{...row, ...repairedIdValues};
        })
        .toList(growable: false);

    final items = normalizedRows
        .map(LibraryCatalogItem.fromRow)
        .toList(growable: false);
    final result = _dedupeLibraryItems(
      items,
    ).where(_isVisibleLibraryItem).toList(growable: false);
    return result;
  }

  Future<int> refreshManagedItemsFromDisk() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
        selection.path;
    if (rootPath == null || rootPath.trim().isEmpty) {
      return 0;
    }
    if (!Directory(rootPath).existsSync()) {
      return 0;
    }

    await LibraryRootService.instance.ensureStructure(rootPath);
    final db = await UserDatabase.instance.database;
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
        final existingRows = await db.query(
          'library_items',
          columns: const ['id', 'collection_name'],
          where: 'id = ? OR LOWER(relative_path) = ?',
          whereArgs: [itemId, relativePath.toLowerCase()],
          limit: 1,
        );
        final existingRow = existingRows.isEmpty ? null : existingRows.first;
        final existingId = existingRow?['id']?.toString().trim() ?? '';
        final existingCollection =
            existingRow?['collection_name']?.toString().trim() ?? '';
        final title = await _resolveManagedTitle(file: entity, isEpub: isEpub);
        final author = await _resolveManagedAuthor(
          file: entity,
          isEpub: isEpub,
          collectionName: folder.collectionName,
          relativePath: relativePath,
        );
        final now = DateTime.now().toUtc().toIso8601String();
        final fileHash = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
        final updatePayload = <String, Object?>{
          'title': title,
          'author': author,
          'file_name': p.basename(entity.path),
          'relative_path': relativePath,
          'file_hash': fileHash,
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
        final insertPayload = <String, Object?>{
          'id': itemId,
          ...updatePayload,
          'source_url': null,
          'cover_path': null,
          'date_added': now,
          'last_opened': null,
          'index_status': 'metadata_only',
          'index_error': null,
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

  /// Returns the count of managed EPUB items that have not yet been indexed
  /// (index_status is not 'indexed' or 'indexed_empty').  These items appear
  /// in the Library catalog and can be opened in the reader, but their body
  /// text is absent from the search index until the Commentary/Research panel
  /// runs an indexing pass.
  Future<int> countUnindexedManagedItems() async {
    final db = await UserDatabase.instance.database;
    final result = await db.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(folder_type, '')) IN ('commentary', 'research')
        AND (
          LOWER(COALESCE(index_status, '')) NOT IN ('indexed', 'indexed_empty')
          OR NOT EXISTS (
            SELECT 1 FROM library_text_blocks WHERE library_item_id = library_items.id
          )
        )
    ''');
    return (result.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<List<LibraryCatalogItem>> listUnindexedManagedItems({
    int limit = 500,
  }) async {
    return _queryItems(
      where: '''
        LOWER(COALESCE(li.file_format, '')) = 'epub'
        AND LOWER(COALESCE(li.folder_type, '')) IN ('commentary', 'research')
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
    );
  }

  Future<int> countIndexedSearchableItems({String? collectionFilter}) async {
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    final db = await UserDatabase.instance.database;
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause());
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT li.id) AS cnt
      FROM library_items li
      INNER JOIN library_text_blocks ltb ON ltb.library_item_id = li.id
      WHERE ${where.join(' AND ')}
      ''', args);
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> countCatalogItemsInScope({String? collectionFilter}) async {
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    final db = await UserDatabase.instance.database;
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause());
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT li.id) AS cnt
      FROM library_items li
      WHERE ${where.join(' AND ')}
      ''', args);
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> countSearchContentResults({
    required String query,
    String? collectionFilter,
  }) async {
    final normalizedTerms = extractLibrarySearchHighlightTerms(query);
    if (normalizedTerms.isEmpty) {
      return 0;
    }

    final db = await UserDatabase.instance.database;
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause());
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

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT ltb.library_item_id) AS cnt
      FROM library_text_blocks ltb
      INNER JOIN library_items li ON li.id = ltb.library_item_id
      WHERE ${where.join(' AND ')}
      ''', args);
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  String _libraryCollectionSearchClause() {
    return '''
      (
        LOWER(COALESCE(li.collection_name, '')) LIKE ?
        OR LOWER(COALESCE(li.relative_path, '')) LIKE ?
        OR LOWER(COALESCE(li.folder_type, '')) LIKE ?
        OR LOWER(COALESCE(li.library_role, '')) LIKE ?
      )
    ''';
  }

  List<Object?> _libraryCollectionSearchArgs(
    String normalizedCollectionFilter,
  ) {
    final humanizedFilter = normalizedCollectionFilter.replaceAll('_', ' ');
    return <Object?>[
      '%$humanizedFilter%',
      '%$normalizedCollectionFilter%',
      normalizedCollectionFilter,
      normalizedCollectionFilter,
    ];
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

    final db = await UserDatabase.instance.database;
    final where = <String>['li.deleted_at IS NULL'];
    final args = <Object?>[];
    final normalizedCollectionFilter = _normalizeLibraryCollectionFilterValue(
      collectionFilter ?? '',
    );
    if (normalizedCollectionFilter.isNotEmpty &&
        normalizedCollectionFilter != _libraryAllCollectionsFilterValue) {
      where.add(_libraryCollectionSearchClause());
      args.addAll(_libraryCollectionSearchArgs(normalizedCollectionFilter));
    }
    // Per-book deduplication: pick the earliest matching paragraph (MIN rowid)
    // per book using a CTE with GROUP BY.  This is far faster than a correlated
    // subquery because SQLite resolves GROUP BY + MIN(rowid) in a single scan
    // rather than re-running the inner query for every candidate row.
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
    final fetchLimit =
        limit *
        ((normalizedCollectionFilter.isNotEmpty &&
                normalizedCollectionFilter != _libraryAllCollectionsFilterValue)
            ? 8
            : 4);

    final rows = await db.rawQuery(
      '''
      WITH best_hits AS (
        SELECT ltb.library_item_id, MIN(ltb.rowid) AS best_rowid
        FROM library_text_blocks ltb
        INNER JOIN library_items li ON li.id = ltb.library_item_id
        WHERE $cteWhere
        GROUP BY ltb.library_item_id
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
        ltb.epub_href AS hit_epub_href,
        ltb.spine_index AS hit_spine_index,
        ltb.paragraph_index AS hit_paragraph_index,
        ltb.section_title,
        ltb.paragraph_on_section,
        ltb.plain_text,
        eri.ref_code AS hit_ref_code
      FROM best_hits bh
      INNER JOIN library_text_blocks ltb ON ltb.rowid = bh.best_rowid
      INNER JOIN library_items li ON li.id = ltb.library_item_id
      LEFT JOIN elibrary_ref_index eri
        ON eri.library_item_id = ltb.library_item_id
        AND LOWER(COALESCE(eri.href, '')) = LOWER(COALESCE(ltb.epub_href, ''))
        AND eri.paragraph_index = ltb.paragraph_index
      ORDER BY li.title COLLATE NOCASE ASC
      ''',
      [...args, fetchLimit],
    );

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
              }).copyWith(
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
        .toList(growable: false);

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

    final db = await UserDatabase.instance.database;
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
    final rows = await db.rawQuery('''
      SELECT full_paragraph, anchor
      FROM library_links
      WHERE ${where.join(' AND ')}
      ORDER BY paragraph_index ASC
      LIMIT 1
      ''', args);
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
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
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
    );
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
    return dedupeLibraryNavigationItems(items);
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
      where.write(' AND LOWER(COALESCE(li.collection_name, \'\')) = ?');
      args.add(normalizedCollection);
    }

    return _queryItems(where: where.toString(), args: args, limit: limit);
  }

  Future<Map<String, String>> _warmMissingCoverPaths(
    List<Map<String, Object?>> rows,
  ) async {
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
      if (format != 'epub') continue;
      candidates.add(row);
    }

    if (candidates.isEmpty) {
      return results;
    }

    final warmResults = await Future.wait(candidates.map(_ensureEpubCoverPath));
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

  Future<Map<String, String>> _warmMissingAuthorValues(
    List<Map<String, Object?>> rows,
  ) async {
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

    final warmResults = await Future.wait(candidates.map(_ensureEpubAuthor));
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
    List<Map<String, Object?>> rows,
  ) async {
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

    final warmResults = await Future.wait(candidates.map(_ensureEpubTitle));
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
  }) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.rawQuery(
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
        li.cover_path,
        li.date_added,
        li.last_opened,
        li.index_status,
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
    return rows.map(LibraryCatalogItem.fromRow).toList(growable: false);
  }

  Future<String?> _ensureEpubAuthor(Map<String, Object?> row) async {
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
        final db = await UserDatabase.instance.database;
        final now = DateTime.now().toUtc().toIso8601String();
        await db.update(
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

      final epubPath = await LibraryRootService.instance.resolveRelativePath(
        relativePath: relativePath,
        rootPath: rootPath,
      );
      final epubFile = File(epubPath);
      if (!epubFile.existsSync()) {
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

      final db = await UserDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'library_items',
        {'author': author, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return author;
    });
  }

  Future<String?> _ensureEpubTitle(Map<String, Object?> row) {
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

      final epubPath = await LibraryRootService.instance.resolveRelativePath(
        relativePath: relativePath,
        rootPath: rootPath,
      );
      final epubFile = File(epubPath);
      if (!epubFile.existsSync()) {
        return null;
      }

      final metadata = await readLibraryEpubMetadata(epubFile);
      final title = metadata?.title?.trim();
      if (title == null || title.isEmpty) {
        return null;
      }

      final db = await UserDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'library_items',
        {'title': title, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      return title;
    });
  }

  Future<Map<String, Map<String, Object?>>> _repairMissingManagedPaths(
    List<Map<String, Object?>> rows,
  ) async {
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
      final currentPath = await LibraryRootService.instance.resolveRelativePath(
        relativePath: currentRelativePath,
        rootPath: rootPath,
      );
      if (File(currentPath).existsSync()) {
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

        final db = await UserDatabase.instance.database;
        await db.update(
          'library_items',
          results[id]!,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (canonicalId != id) {
          await migrateManagedLibraryItemId(
            db: db,
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
    List<Map<String, Object?>> rows,
  ) async {
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

    final db = await UserDatabase.instance.database;
    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (id.isEmpty || relativePath.isEmpty) continue;
      if (!isManagedEgwRelativePath(relativePath)) continue;

      final folderType =
          row['folder_type']?.toString().trim().isNotEmpty == true
          ? row['folder_type']?.toString().trim() ?? ''
          : row['library_role']?.toString().trim() ?? '';
      if (folderType.isEmpty) continue;

      final resolvedPath = await LibraryRootService.instance
          .resolveRelativePath(relativePath: relativePath, rootPath: rootPath);
      if (!File(resolvedPath).existsSync()) continue;

      final canonicalId = canonicalLibraryItemId(
        folderType: folderType,
        relativePath: relativePath,
      );
      if (canonicalId == id) continue;

      await migrateManagedLibraryItemId(db: db, oldId: id, newId: canonicalId);
      results[id] = <String, Object?>{
        'id': canonicalId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
    }

    return results;
  }

  Future<String?> _ensureEpubCoverPath(Map<String, Object?> row) {
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
        final db = await UserDatabase.instance.database;
        final now = DateTime.now().toUtc().toIso8601String();
        await db.update(
          'library_items',
          {'cover_path': mirroredCoverPath, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        return mirroredCoverPath;
      }

      final epubPath = await LibraryRootService.instance.resolveRelativePath(
        relativePath: relativePath,
        rootPath: rootPath,
      );
      final epubFile = File(epubPath);
      if (!epubFile.existsSync()) {
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

      final db = await UserDatabase.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
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

  Future<String?> _cacheEpubCover({
    required File file,
    required String rootPath,
    required String itemId,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final packageInfo = _readEpubPackageInfo(archive);
      final coverHref = packageInfo.coverImagePath;
      if (coverHref == null || coverHref.trim().isEmpty) {
        return null;
      }

      final entry = packageInfo.findArchiveEntry(archive, coverHref);
      if (entry == null || !entry.isFile) return null;
      final content = entry.content as List<int>;
      if (content.isEmpty) return null;

      final coverDir = Directory(
        p.join(rootPath, 'Graphics', 'eLibraryCovers'),
      );
      await coverDir.create(recursive: true);
      final extension = _coverImageExtension(entry.name);
      final coverPath = p.join(coverDir.path, '$itemId$extension');
      await File(coverPath).writeAsBytes(content, flush: true);
      return coverPath;
    } catch (_) {
      return null;
    }
  }

  _EpubPackageInfo _readEpubPackageInfo(Archive archive) {
    final containerEntry = archive.findFile('META-INF/container.xml');
    if (containerEntry == null) {
      return const _EpubPackageInfo();
    }

    final containerXml = utf8.decode(
      containerEntry.content as List<int>,
      allowMalformed: true,
    );
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    final opfPath = opfPathMatch?.group(1);
    if (opfPath == null || opfPath.trim().isEmpty) {
      return const _EpubPackageInfo();
    }

    final opfEntry = archive.findFile(opfPath);
    if (opfEntry == null) {
      return const _EpubPackageInfo();
    }

    final opfXml = utf8.decode(
      opfEntry.content as List<int>,
      allowMalformed: true,
    );
    final opfDir = p.dirname(opfPath);
    final manifest = <String, _EpubManifestItem>{};
    for (final match in RegExp(
      r'<item\b[^>]*>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final tag = match.group(0) ?? '';
      final id = _attributeValue(tag, 'id');
      final href = _attributeValue(tag, 'href');
      final properties = _attributeValue(tag, 'properties');
      if (id == null || href == null) continue;
      final normalizedPath = p.normalize(p.join(opfDir, href));
      manifest[id] = _EpubManifestItem(
        href: normalizedPath,
        properties: properties ?? '',
      );
    }

    final coverImagePath = _discoverCoverImagePath(
      archive: archive,
      opfXml: opfXml,
      manifest: manifest,
    );

    final spinePaths = <String>[];
    for (final match in RegExp(
      r'<itemref\b[^>]*>',
      caseSensitive: false,
    ).allMatches(opfXml)) {
      final tag = match.group(0) ?? '';
      final idref = _attributeValue(tag, 'idref');
      final linear = _attributeValue(tag, 'linear');
      if (idref == null || linear?.toLowerCase() == 'no') continue;
      final item = manifest[idref];
      if (item == null) continue;
      spinePaths.add(item.href.toLowerCase());
    }

    final navigationPaths = <String>{};
    for (final item in manifest.values) {
      final basename = p.basename(item.href).toLowerCase();
      if (item.properties.toLowerCase().contains('nav') ||
          basename == 'nav.xhtml' ||
          basename == 'toc.xhtml' ||
          basename == 'toc.ncx' ||
          basename == 'cover.xhtml' ||
          basename == 'titlepage.xhtml') {
        navigationPaths.add(item.href.toLowerCase());
      }
    }

    return _EpubPackageInfo(
      coverImagePath: coverImagePath,
      spinePaths: spinePaths.toSet(),
      spineOrderedPaths: List<String>.unmodifiable(
        spinePaths.map((path) => p.normalize(path).toLowerCase()),
      ),
      navigationPaths: navigationPaths,
    );
  }

  String? _attributeValue(String tag, String name) {
    final match = RegExp(
      '$name="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(1);
  }

  String? _discoverCoverImagePath({
    required Archive archive,
    required String opfXml,
    required Map<String, _EpubManifestItem> manifest,
  }) {
    final coverIdMatch = RegExp(
      r'<meta\b[^>]*name="cover"[^>]*content="([^"]+)"',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(opfXml);
    final coverId = coverIdMatch?.group(1)?.trim();
    if (coverId != null && coverId.isNotEmpty) {
      final manifestItem = manifest[coverId];
      if (manifestItem != null) {
        return manifestItem.href;
      }
    }

    for (final item in manifest.values) {
      if (item.properties.toLowerCase().contains('cover-image')) {
        return item.href;
      }
    }

    for (final item in manifest.values) {
      if (_looksLikeCoverImagePath(item.href)) {
        return item.href;
      }
    }

    for (final item in manifest.values) {
      final basename = p.basename(item.href).toLowerCase();
      if (basename != 'cover.xhtml' && basename != 'titlepage.xhtml') {
        continue;
      }
      final entry = archive.findFile(item.href);
      if (entry == null || !entry.isFile) continue;
      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final imgMatch = RegExp(
        r'<(?:img|image)\b[^>]*(?:src|href|xlink:href)="([^"]+)"',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw);
      final href = imgMatch?.group(1)?.trim();
      if (href == null || href.isEmpty) continue;
      return p.normalize(p.join(p.dirname(item.href), href));
    }

    final spineCandidates = <_EpubManifestItem>[];
    for (final item in manifest.values) {
      if (!item.href.toLowerCase().endsWith('.xhtml')) continue;
      spineCandidates.add(item);
    }
    spineCandidates.sort((left, right) {
      final leftName = p.basename(left.href).toLowerCase();
      final rightName = p.basename(right.href).toLowerCase();
      final leftScore = _coverFallbackScore(leftName);
      final rightScore = _coverFallbackScore(rightName);
      if (leftScore != rightScore) return leftScore.compareTo(rightScore);
      return left.href.compareTo(right.href);
    });

    for (final item in spineCandidates.take(4)) {
      final entry = archive.findFile(item.href);
      if (entry == null || !entry.isFile) continue;
      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final imgMatch = RegExp(
        r'<(?:img|image)\b[^>]*(?:src|href|xlink:href)="([^"]+)"',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(raw);
      final href = imgMatch?.group(1)?.trim();
      if (href == null || href.isEmpty) continue;
      return p.normalize(p.join(p.dirname(item.href), href));
    }

    return null;
  }

  int _coverFallbackScore(String basename) {
    if (basename == 'cover.xhtml') return 0;
    if (basename == 'titlepage.xhtml') return 1;
    if (basename.startsWith('cover')) return 2;
    if (basename.startsWith('title')) return 3;
    return 4;
  }

  bool _looksLikeCoverImagePath(String pathValue) {
    final lower = pathValue.toLowerCase();
    final basename = p.basename(lower);
    if (!_isImageExtension(lower)) return false;
    return basename.startsWith('cover') ||
        basename.startsWith('front-cover') ||
        basename.startsWith('frontcover') ||
        basename == 'titlepage.jpg' ||
        basename == 'titlepage.jpeg' ||
        basename == 'titlepage.png' ||
        basename == 'titlepage.webp';
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

  bool _isImageExtension(String pathValue) {
    final ext = p.extension(pathValue).toLowerCase();
    return const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext);
  }

  String _coverImageExtension(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    if (const <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    }.contains(ext)) {
      return ext;
    }
    return '.jpg';
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
    required this.fileSize,
    required this.mimeType,
    required this.spineIndex,
    required this.anchorId,
    required this.epubHref,
    required this.paragraphIndex,
    required this.navigationCount,
  });

  factory LibraryCatalogItem.fromRow(Map<String, Object?> row) {
    final coverPathValue = row['cover_path']?.toString().trim();
    final resolvedCoverPath =
        coverPathValue != null &&
            coverPathValue.isNotEmpty &&
            File(coverPathValue).existsSync()
        ? coverPathValue
        : null;
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
      fileSize: (row['file_size'] as num?)?.toInt(),
      mimeType: row['mime_type']?.toString(),
      spineIndex: (row['spine_index'] as num?)?.toInt(),
      anchorId: row['anchor_id']?.toString(),
      epubHref: row['epub_href']?.toString(),
      paragraphIndex: (row['paragraph_index'] as num?)?.toInt(),
      navigationCount: (row['navigation_count'] as num?)?.toInt() ?? 0,
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
  final int? fileSize;
  final String? mimeType;
  final int? spineIndex;
  final String? anchorId;
  final String? epubHref;
  final int? paragraphIndex;
  final int navigationCount;

  bool get isEpub => (fileFormat ?? '').toLowerCase() == 'epub';

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
    int? fileSize,
    String? mimeType,
    int? spineIndex,
    String? anchorId,
    String? epubHref,
    int? paragraphIndex,
    int? navigationCount,
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
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      spineIndex: spineIndex ?? this.spineIndex,
      anchorId: anchorId ?? this.anchorId,
      epubHref: epubHref ?? this.epubHref,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      navigationCount: navigationCount ?? this.navigationCount,
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

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return _humanizeFileName(fileName);
    }
    if (_looksLikeFilename(trimmed)) {
      return _humanizeFileName(trimmed);
    }
    if (isPeriodical) {
      final canonical = _canonicalPeriodicalTitle(trimmed);
      if (canonical != null) return canonical;
    }
    return trimmed;
  }

  String get subtitle {
    final parts = <String>[
      if ((author ?? '').trim().isNotEmpty) author!.trim(),
      if ((collectionName ?? '').trim().isNotEmpty) collectionName!.trim(),
    ];
    if (parts.isEmpty) return _fileTypeLabel;
    return parts.join(' • ');
  }

  String get displayAuthor {
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
        collectionFilter:
            collectionFilter == null || collectionFilter.isEmpty
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
}

class _EpubPackageInfo {
  const _EpubPackageInfo({
    this.coverImagePath,
    this.spinePaths = const <String>{},
    this.spineOrderedPaths = const <String>[],
    this.navigationPaths = const <String>{},
  });

  final String? coverImagePath;
  final Set<String> spinePaths;
  final List<String> spineOrderedPaths;
  final Set<String> navigationPaths;

  ArchiveFile? findArchiveEntry(Archive archive, String pathValue) {
    final normalized = p.normalize(pathValue).toLowerCase();
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (p.normalize(file.name).toLowerCase() == normalized) {
        return file;
      }
    }
    return null;
  }
}

class _EpubManifestItem {
  const _EpubManifestItem({required this.href, required this.properties});

  final String href;
  final String properties;
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

List<LibraryCatalogItem> _dedupeLibraryItems(List<LibraryCatalogItem> items) {
  if (items.length < 2) return items;

  final chosenByKey = <String, LibraryCatalogItem>{};
  for (final item in items) {
    final key = _libraryItemDedupKey(item);
    final existing = chosenByKey[key];
    if (existing == null) {
      chosenByKey[key] = item;
      continue;
    }
    chosenByKey[key] = _preferLibraryCatalogItem(existing, item);
  }

  final deduped = chosenByKey.values.toList(growable: false);
  deduped.sort(_compareLibraryCatalogItems);
  return deduped;
}

String _libraryItemDedupKey(LibraryCatalogItem item) {
  final sourceUrl = item.sourceUrl?.trim() ?? '';
  if (sourceUrl.isNotEmpty) {
    return 'source:${sourceUrl.toLowerCase()}';
  }

  final canonicalTitle = _normalizedLibraryText(item.displayTitle);
  if (canonicalTitle.isNotEmpty) {
    final canonicalAuthor = _normalizedLibraryText(item.displayAuthor);
    final format = (item.fileFormat ?? '').trim().toLowerCase();
    final parts = <String>['title:$canonicalTitle'];
    if (canonicalAuthor.isNotEmpty) {
      parts.add('author:$canonicalAuthor');
    }
    if (format.isNotEmpty) {
      parts.add('format:$format');
    }
    return parts.join('|');
  }

  final fileHash = item.fileHash?.trim() ?? '';
  if (fileHash.isNotEmpty) {
    return 'hash:$fileHash';
  }

  final normalizedPath = item.relativePath
      .replaceAll('\\', '/')
      .trim()
      .toLowerCase();
  if (normalizedPath.isNotEmpty) {
    return 'path:$normalizedPath';
  }

  return 'id:${item.id}';
}

LibraryCatalogItem _preferLibraryCatalogItem(
  LibraryCatalogItem left,
  LibraryCatalogItem right,
) {
  final leftSourcePriority = _libraryItemSourcePriority(left);
  final rightSourcePriority = _libraryItemSourcePriority(right);
  if (leftSourcePriority != rightSourcePriority) {
    return rightSourcePriority > leftSourcePriority ? right : left;
  }

  final leftScore = _libraryItemQualityScore(left);
  final rightScore = _libraryItemQualityScore(right);
  if (leftScore != rightScore) {
    return rightScore > leftScore ? right : left;
  }

  final leftStamp =
      left.lastOpened ??
      left.dateAdded ??
      DateTime.fromMillisecondsSinceEpoch(0);
  final rightStamp =
      right.lastOpened ??
      right.dateAdded ??
      DateTime.fromMillisecondsSinceEpoch(0);
  if (leftStamp != rightStamp) {
    return rightStamp.isAfter(leftStamp) ? right : left;
  }

  final leftTitle = left.displayTitle.toLowerCase();
  final rightTitle = right.displayTitle.toLowerCase();
  final titleCompare = leftTitle.compareTo(rightTitle);
  if (titleCompare != 0) {
    return titleCompare > 0 ? right : left;
  }

  return left.fileName.toLowerCase().compareTo(right.fileName.toLowerCase()) <=
          0
      ? left
      : right;
}

int _libraryItemQualityScore(LibraryCatalogItem item) {
  var score = 0;
  final title = item.title.trim();
  if (title.isNotEmpty && !_looksLikeFilename(title)) {
    score += 4;
  }
  if (normalizeLibraryAuthor(item.author) != null) {
    score += 1;
  }
  if ((item.coverPath ?? '').trim().isNotEmpty) {
    score += 1;
  }
  if ((item.sourceUrl ?? '').trim().isNotEmpty) {
    score += 1;
  }
  return score;
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
  return true;
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
