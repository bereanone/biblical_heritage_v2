import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import 'library_author_resolver.dart';
import 'library_epub_metadata.dart';

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
    final hydratedRows = rows
        .map((row) {
          final id = row['id']?.toString() ?? '';
          final warmedAuthor = warmedAuthorValues[id];
          final warmedCoverPath = warmedCoverPaths[id];
          final warmedTitle = warmedTitleValues[id];
          if ((warmedAuthor == null || warmedAuthor.trim().isEmpty) &&
              (warmedCoverPath == null || warmedCoverPath.trim().isEmpty)) {
            if (warmedTitle == null || warmedTitle.trim().isEmpty) {
              return row;
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
          };
        })
        .toList(growable: false);

    final items = hydratedRows
        .map(LibraryCatalogItem.fromRow)
        .toList(growable: false);
    return _dedupeLibraryItems(
      items,
    ).where(_isVisibleLibraryItem).toList(growable: false);
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

    return null;
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
