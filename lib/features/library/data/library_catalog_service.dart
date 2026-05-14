import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import '../../search/search_highlight_helper.dart';
import 'library_author_resolver.dart';
import 'library_epub_metadata.dart';
import 'library_item_identity.dart';

part 'library_navigation_dedupe.dart';

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
    return _dedupeLibraryItems(
      items,
    ).where(_isVisibleLibraryItem).toList(growable: false);
  }

  Future<List<LibraryCatalogSearchResult>> searchContent({
    required String query,
    int limit = 50,
  }) async {
    final normalizedTerms = extractLibrarySearchHighlightTerms(query);
    if (normalizedTerms.isEmpty || limit <= 0) {
      return const [];
    }

    final db = await UserDatabase.instance.database;
    final where = <String>['li.deleted_at IS NULL', 'll.deleted_at IS NULL'];
    final args = <Object?>[];
    for (final term in normalizedTerms) {
      final normalizedTerm = _normalizedLibrarySearchText(term);
      if (normalizedTerm.isEmpty) continue;
      where.add('(${_librarySearchTermClause()})');
      args.addAll(
        List<Object?>.filled(
          _librarySearchClauseFields.length,
          '%$normalizedTerm%',
        ),
      );
    }

    if (args.isEmpty) {
      return const [];
    }

    final rows = await db.rawQuery(
      '''
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
        ll.original_reference_text,
        ll.full_paragraph,
        ll.epub_href AS hit_epub_href,
        ll.anchor_id AS hit_anchor_id,
        ll.spine_index AS hit_spine_index,
        ll.paragraph_index AS hit_paragraph_index,
        ll.book_id,
        ll.chapter,
        ll.verse_start,
        ll.verse_end,
        ll.anchor,
        ll.link_type
      FROM library_links ll
      INNER JOIN library_items li ON li.id = ll.library_item_id
      WHERE ${where.join(' AND ')}
      ORDER BY
        li.title COLLATE NOCASE ASC,
        ll.book_id ASC,
        ll.chapter ASC,
        ll.verse_start ASC,
        ll.verse_end ASC
      LIMIT ?
      ''',
      [...args, limit * 4],
    );

    final citationCache = <String, Future<_LibraryCitation?>>{};
    final results = await Future.wait(
      rows.map((row) async {
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
              anchorId: row['hit_anchor_id']?.toString(),
              epubHref: row['hit_epub_href']?.toString(),
              paragraphIndex: (row['hit_paragraph_index'] as num?)?.toInt(),
            );

        final fullParagraph = _firstNonEmpty([
          row['full_paragraph']?.toString(),
          row['anchor']?.toString(),
        ]);
        final referenceText = row['original_reference_text']?.toString();
        final locationText = await _buildLibrarySearchLocationText(
          db: db,
          citationCache: citationCache,
          item: item,
          libraryItemId: row['item_id']?.toString() ?? item.id,
          spineIndex: (row['hit_spine_index'] as num?)?.toInt(),
          paragraphIndex: (row['hit_paragraph_index'] as num?)?.toInt(),
          chapterNumber: (row['chapter'] as num?)?.toInt(),
          epubHref: row['hit_epub_href']?.toString(),
          anchorId: row['hit_anchor_id']?.toString(),
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
          referenceText: referenceText,
          fullParagraph: fullParagraph,
          queryTerms: normalizedTerms,
        );
        return LibraryCatalogSearchResult(
          item: item,
          snippet: snippet,
          locationText: locationText,
          referenceText: referenceText,
          fullParagraph: fullParagraph,
          chapterNumber: (row['chapter'] as num?)?.toInt(),
          verseStart: (row['verse_start'] as num?)?.toInt(),
          verseEnd: (row['verse_end'] as num?)?.toInt(),
          score: score,
        );
      }),
    );

    final filteredResults = results
        .whereType<LibraryCatalogSearchResult>()
        .toList(growable: false);

    filteredResults.sort((left, right) {
      final scoreCompare = left.score.compareTo(right.score);
      if (scoreCompare != 0) return scoreCompare;
      final titleCompare = left.item.displayTitle.toLowerCase().compareTo(
        right.item.displayTitle.toLowerCase(),
      );
      if (titleCompare != 0) return titleCompare;
      final referenceCompare = (left.referenceText ?? '')
          .toLowerCase()
          .compareTo((right.referenceText ?? '').toLowerCase());
      if (referenceCompare != 0) return referenceCompare;
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
      if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
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
      if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
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
    if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
      return results;
    }

    const managedFolders = <({String collectionName, String relativeFolder})>[
      (collectionName: 'EGW_Books', relativeFolder: 'ePubs/Research/EGW_Books'),
      (
        collectionName: 'EGW_Devotionals',
        relativeFolder: 'ePubs/Research/EGW_Devotionals',
      ),
      (
        collectionName: 'EGW_Commentaries',
        relativeFolder: 'ePubs/Commentaries/EGW_Commentaries',
      ),
    ];

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
    if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
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
      if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
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

  String get displayTitle {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return _humanizeFileName(fileName);
    }
    if (_looksLikeFilename(trimmed)) {
      return _humanizeFileName(trimmed);
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

DateTime? _parseDate(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return DateTime.tryParse(trimmed);
}

bool _looksLikeFilename(String value) {
  final base = value.trim();
  if (base.isEmpty) {
    return true;
  }

  return base.contains('_') ||
      base.contains('-') ||
      RegExp(r'^\d{4}[_-]').hasMatch(base) ||
      (RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(base) && !base.contains(' '));
}

String _humanizeFileName(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) {
    return value.trim();
  }

  return cleaned
      .split(' ')
      .map((part) {
        if (part.length <= 2) {
          return part.toUpperCase();
        }
        if (RegExp(r'^\d+$').hasMatch(part)) {
          return part;
        }
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

String _normalizedLibraryText(String? value) {
  return (value?.trim() ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizedLibrarySearchText(String value) {
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

Future<String> _buildLibrarySearchLocationText({
  required Database db,
  required Map<String, Future<_LibraryCitation?>> citationCache,
  required LibraryCatalogItem item,
  required String libraryItemId,
  required int? spineIndex,
  required int? paragraphIndex,
  required int? chapterNumber,
  required String? epubHref,
  required String? anchorId,
}) async {
  final abbreviation = _libraryBookAbbreviation(item);
  final title = item.displayTitle.trim();
  final citation = paragraphIndex != null && paragraphIndex > 0
      ? await _resolveLibraryCitation(
          db: db,
          cache: citationCache,
          libraryItemId: libraryItemId,
          spineIndex: spineIndex,
          paragraphIndex: paragraphIndex,
          epubHref: epubHref,
        )
      : null;

  if (abbreviation != null) {
    if (citation != null) {
      return '$abbreviation ${citation.pageNumber}.${citation.paragraphNumber}';
    }
    if (paragraphIndex != null && paragraphIndex > 0) {
      return '$abbreviation ¶$paragraphIndex';
    }
    if (chapterNumber != null && chapterNumber > 0) {
      return '$abbreviation ch. $chapterNumber';
    }
    return abbreviation;
  }

  if (citation != null) {
    return '$title ${citation.pageNumber}.${citation.paragraphNumber}';
  }
  if (paragraphIndex != null && paragraphIndex > 0) {
    return '$title ¶$paragraphIndex';
  }
  if (chapterNumber != null && chapterNumber > 0) {
    return '$title ch. $chapterNumber';
  }

  final cleanHref = epubHref?.trim() ?? '';
  if (cleanHref.isNotEmpty) {
    final cleanAnchor = anchorId?.trim() ?? '';
    final hrefLabel = cleanAnchor.isNotEmpty
        ? '$cleanHref#$cleanAnchor'
        : cleanHref;
    return '$title · $hrefLabel';
  }

  return title;
}

String? _firstNonEmpty(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String? _libraryBookAbbreviation(LibraryCatalogItem item) {
  final normalizedTitle = _normalizedLibraryText(item.displayTitle);
  if (normalizedTitle.contains('christ triumphant')) {
    return 'CTr';
  }
  if (normalizedTitle.contains('maranatha')) {
    return 'Mar';
  }
  if (normalizedTitle.contains('radiant religion')) {
    return 'RRe';
  }

  final fromFileName = _abbreviationFromPathSegment(item.fileName);
  if (fromFileName != null) return fromFileName;

  final fromRelativePath = _abbreviationFromPathSegment(item.relativePath);
  if (fromRelativePath != null) return fromRelativePath;

  final normalized = _normalizedLibraryText(item.displayTitle);
  if (normalized.isEmpty) return null;

  const rules = <({String needle, String code})>[
    (needle: 'the great controversy', code: 'GC'),
    (needle: 'the great controversy 1888', code: 'GC88'),
    (needle: 'desire of ages', code: 'DA'),
    (needle: 'christ triumphant', code: 'CTr'),
    (needle: 'steps to christ', code: 'SC'),
    (needle: 'patriarchs and prophets', code: 'PP'),
    (needle: 'prophets and kings', code: 'PK'),
    (needle: 'acts of the apostles', code: 'AA'),
    (needle: 'early writings', code: 'EW'),
    (needle: 'gospel workers', code: 'GW'),
    (needle: 'life sketches', code: 'LS'),
    (needle: 'ministry of healing', code: 'MH'),
    (needle: 'christ s object lessons', code: 'COL'),
    (needle: 'education', code: 'Ed.'),
    (needle: 'thoughts from the mount of blessing', code: 'MB'),
    (needle: 'the faith i live by', code: 'FLB'),
    (needle: 'homeward bound', code: 'HB'),
    (needle: 'reflecting christ', code: 'RC'),
    (needle: 'that i may know him', code: 'TMK'),
    (needle: 'testimonies for the church vol 1', code: '1T'),
    (needle: 'testimonies for the church vol 2', code: '2T'),
    (needle: 'testimonies for the church vol 3', code: '3T'),
    (needle: 'testimonies for the church vol 4', code: '4T'),
    (needle: 'testimonies for the church vol 5', code: '5T'),
    (needle: 'testimonies for the church vol 6', code: '6T'),
    (needle: 'testimonies for the church vol 7', code: '7T'),
    (needle: 'testimonies for the church vol 8', code: '8T'),
    (needle: 'testimonies for the church vol 9', code: '9T'),
    (needle: 'spiritual gifts vol 1', code: 'SG1'),
  ];

  for (final rule in rules) {
    if (normalized.contains(rule.needle)) {
      return rule.code;
    }
  }

  return null;
}

String? _abbreviationFromPathSegment(String value) {
  final stem = p.basenameWithoutExtension(value).trim();
  if (stem.isEmpty) return null;
  final withoutPrefix = stem.replaceFirst(
    RegExp(r'^[a-z]{2}[_-]', caseSensitive: false),
    '',
  );
  final candidate = withoutPrefix.trim();
  if (candidate.isEmpty) return null;
  if (!RegExp(r'^[A-Za-z0-9]+$').hasMatch(candidate)) return null;
  if (candidate.length > 10) return null;
  return candidate.toUpperCase();
}

Future<_LibraryCitation?> _resolveLibraryCitation({
  required Database db,
  required Map<String, Future<_LibraryCitation?>> cache,
  required String libraryItemId,
  required int? spineIndex,
  required int paragraphIndex,
  required String? epubHref,
}) {
  final key = [
    libraryItemId,
    spineIndex?.toString() ?? '',
    paragraphIndex.toString(),
    epubHref?.trim() ?? '',
  ].join('|');
  return cache.putIfAbsent(key, () async {
    final lowerBound = paragraphIndex > 24 ? paragraphIndex - 24 : 1;
    final args = <Object?>[libraryItemId, lowerBound, paragraphIndex];
    final where = StringBuffer('library_item_id = ?');
    if (spineIndex != null) {
      where.write(' AND spine_index = ?');
      args.insert(1, spineIndex);
    }
    where.write(' AND paragraph_index BETWEEN ? AND ?');
    final rows = await db.rawQuery('''
        SELECT paragraph_index, anchor, full_paragraph
        FROM library_links
        WHERE $where
        ORDER BY paragraph_index ASC
        ''', args);

    int? pageNumber;
    int? pageParagraphIndex;
    for (final row in rows) {
      final text = _firstNonEmpty([
        row['anchor']?.toString(),
        row['full_paragraph']?.toString(),
      ]);
      if (text == null) continue;
      final match = RegExp(r'\[(\d{1,4})\]').firstMatch(text);
      if (match == null) continue;
      pageNumber = int.tryParse(match.group(1)!);
      pageParagraphIndex = (row['paragraph_index'] as num?)?.toInt();
    }

    if (pageNumber == null || pageParagraphIndex == null) {
      return null;
    }

    final paragraphNumber = paragraphIndex - pageParagraphIndex + 1;
    return _LibraryCitation(
      pageNumber: pageNumber,
      paragraphNumber: paragraphNumber > 0 ? paragraphNumber : 1,
    );
  });
}

class _LibraryCitation {
  const _LibraryCitation({
    required this.pageNumber,
    required this.paragraphNumber,
  });

  final int pageNumber;
  final int paragraphNumber;
}

int _scoreLibrarySearchResult({
  required LibraryCatalogItem item,
  required String? referenceText,
  required String? fullParagraph,
  required List<String> queryTerms,
}) {
  final title = _normalizedLibraryText(item.displayTitle);
  final author = _normalizedLibraryText(item.displayAuthor);
  final reference = _normalizedLibraryText(referenceText);
  final paragraph = _normalizedLibrarySearchText(fullParagraph ?? '');

  var bestScore = 6;
  for (final term in queryTerms) {
    final normalizedTerm = _normalizedLibrarySearchText(term);
    if (normalizedTerm.isEmpty) continue;
    var termScore = 5;
    if (paragraph.contains(normalizedTerm)) {
      termScore = 0;
    } else if (reference.contains(normalizedTerm)) {
      termScore = 1;
    } else if (title.contains(normalizedTerm)) {
      termScore = 2;
    } else if (author.contains(normalizedTerm)) {
      termScore = 3;
    }
    if (termScore < bestScore) {
      bestScore = termScore;
    }
  }
  return bestScore;
}

String _cleanLibrarySearchText(String value) {
  return value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('„', '"')
      .replaceAll('‟', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .trim();
}

List<String> extractLibrarySearchHighlightTerms(String query) {
  return extractSearchHighlightTerms(query, booleanSyntax: true);
}

const List<String> _librarySearchClauseFields = <String>[
  'LOWER(COALESCE(ll.full_paragraph, \'\')) LIKE ?',
  'LOWER(COALESCE(ll.original_reference_text, \'\')) LIKE ?',
  'LOWER(COALESCE(ll.anchor, \'\')) LIKE ?',
  'LOWER(COALESCE(li.title, \'\')) LIKE ?',
  'LOWER(COALESCE(li.author, \'\')) LIKE ?',
  'LOWER(COALESCE(li.collection_name, \'\')) LIKE ?',
  'LOWER(COALESCE(li.relative_path, \'\')) LIKE ?',
  'LOWER(COALESCE(li.file_name, \'\')) LIKE ?',
];

String _librarySearchTermClause() {
  return _librarySearchClauseFields.join(' OR ');
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
  final status = (item.indexStatus ?? '').trim().toLowerCase();
  return status != 'indexed_empty';
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
