// ignore_for_file: unused_element

part of 'commentary_research_library_service.dart';

const Map<String, ({int start, int end})> _volumeScopes =
    <String, ({int start, int end})>{
      '1BC': (start: 1, end: 5),
      '2BC': (start: 6, end: 12),
      '3BC': (start: 13, end: 22),
      '4BC': (start: 23, end: 39),
      '5BC': (start: 40, end: 43),
      '6BC': (start: 44, end: 49),
      '7BC': (start: 50, end: 66),
      '7ABC': (start: 44, end: 66),
    };

String? _inferCommentaryVolumeCodeForItem(String fileName, String title) {
  final rawCandidate = '$fileName $title';
  final volumeMatch = RegExp(
    r'\bvol(?:ume)?\.?\s*(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(rawCandidate);
  if (volumeMatch != null) {
    final volumeNumber = int.tryParse(volumeMatch.group(1) ?? '');
    if (volumeNumber != null && volumeNumber >= 1 && volumeNumber <= 7) {
      return '${volumeNumber}BC';
    }
  }

  final candidate = rawCandidate
      .replaceAll('_', '')
      .replaceAll('-', '')
      .replaceAll(' ', '');
  final match = RegExp(
    r'(?:(\dABC)|(\dBC))',
    caseSensitive: false,
  ).firstMatch(candidate);
  final raw = match?.group(1) ?? match?.group(2);
  return raw?.toUpperCase();
}

List<Map<String, Object?>> filterRowsByPreferredCommentaryVolume(
  List<Map<String, Object?>> rows,
  String? preferredVolumeCode,
) {
  if (preferredVolumeCode == null) return rows;
  return rows
      .where((row) {
        final inferred = _inferCommentaryVolumeCodeForItem(
          row['file_name']?.toString() ?? '',
          row['title']?.toString() ?? '',
        );
        return inferred == preferredVolumeCode;
      })
      .toList(growable: false);
}

mixin _CommentaryResearchLibraryServiceEpubStorageSupport {
  Future<List<CommentaryResearchMatchItem>> _loadMatches({
    required Database db,
    required String folderType,
    required int bookId,
    required int chapter,
    required int verse,
    required String? preferredVolumeCode,
    required bool chapterWideMatches,
  }) async {
    final rows = await db.rawQuery(
      chapterWideMatches
          ? '''
      SELECT
        ll.library_item_id,
        li.title,
        li.file_name,
        li.relative_path,
        li.source_url,
        ll.original_reference_text,
        ll.book_id,
        ll.chapter,
        ll.verse_start,
        ll.verse_end,
        ll.anchor,
        ll.full_paragraph,
        ll.confidence,
        ll.parser_warning,
        ll.epub_cfi,
        ll.epub_href,
        ll.anchor_id,
        ll.spine_index,
        ll.paragraph_index
      FROM library_links ll
      INNER JOIN library_items li ON li.id = ll.library_item_id
      WHERE ll.link_type = ?
        AND ll.book_id = ?
        AND ll.chapter = ?
      ORDER BY li.title COLLATE NOCASE ASC, ll.verse_start ASC, ll.verse_end ASC
      '''
          : '''
      SELECT
        li.title,
        li.file_name,
        li.relative_path,
        li.source_url,
        ll.original_reference_text,
        ll.book_id,
        ll.chapter,
        ll.verse_start,
        ll.verse_end,
        ll.anchor,
        ll.full_paragraph,
        ll.confidence,
        ll.parser_warning,
        ll.epub_cfi,
        ll.epub_href,
        ll.anchor_id,
        ll.spine_index,
        ll.paragraph_index
      FROM library_links ll
      INNER JOIN library_items li ON li.id = ll.library_item_id
      WHERE ll.link_type = ?
        AND ll.book_id = ?
        AND ll.chapter = ?
        AND ll.verse_start <= ?
        AND ll.verse_end >= ?
      ORDER BY li.title COLLATE NOCASE ASC, ll.verse_start ASC, ll.verse_end ASC
      ''',
      chapterWideMatches
          ? [folderType, bookId, chapter]
          : [folderType, bookId, chapter, verse, verse],
    );

    final visibleRows =
        filterRowsByPreferredCommentaryVolume(rows, preferredVolumeCode);

    return visibleRows
        .map(
          (row) => CommentaryResearchMatchItem(
            libraryItemId: row['library_item_id']?.toString() ?? '',
            itemTitle: row['title']?.toString() ?? '',
            fileName: row['file_name']?.toString() ?? '',
            relativePath: row['relative_path']?.toString() ?? '',
            sourceUrl: row['source_url']?.toString(),
            originalReferenceText:
                row['original_reference_text']?.toString() ?? '',
            bookId: (row['book_id'] as num?)?.toInt() ?? 0,
            chapter: (row['chapter'] as num?)?.toInt() ?? 0,
            verseStart: (row['verse_start'] as num?)?.toInt() ?? 0,
            verseEnd: (row['verse_end'] as num?)?.toInt() ?? 0,
            confidence: (row['confidence'] as num?)?.toDouble() ?? 0.0,
            anchor: row['anchor']?.toString(),
            fullParagraph: row['full_paragraph']?.toString(),
            parserWarning: row['parser_warning']?.toString(),
            epubCfi: row['epub_cfi']?.toString(),
            epubHref: row['epub_href']?.toString(),
            anchorId: row['anchor_id']?.toString(),
            spineIndex: (row['spine_index'] as num?)?.toInt(),
            paragraphIndex: (row['paragraph_index'] as num?)?.toInt(),
          ),
        )
        .toList(growable: false);
  }

  String _expandParagraphContext(List<String> paragraphs, int startIndex) {
    if (startIndex < 0 || startIndex >= paragraphs.length) {
      return '';
    }

    final buffer = StringBuffer(_stripHtml(paragraphs[startIndex]).trim());
    if (buffer.isEmpty) return '';

    var currentIndex = startIndex;
    var extensions = 0;
    while (_shouldExtendParagraph(buffer.toString()) &&
        currentIndex + 1 < paragraphs.length &&
        extensions < 8 &&
        buffer.length < 2400) {
      currentIndex += 1;
      final next = _stripHtml(paragraphs[currentIndex]).trim();
      if (next.isEmpty) break;
      buffer.write(' ');
      buffer.write(next);
      extensions += 1;
    }

    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _cleanCommentaryParagraph(
    String text, {
    required String sectionTitle,
    required String bookTitle,
  }) {
    var cleaned = _stripHtml(text).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return cleaned;

    for (final prefix in <String>[bookTitle, sectionTitle]) {
      final trimmedPrefix = prefix.trim();
      if (trimmedPrefix.isEmpty) continue;
      final escaped = RegExp.escape(trimmedPrefix);
      final pattern = RegExp(
        '^$escaped(?:\\s*[:;,.\\-–—]\\s*|\\s+)',
        caseSensitive: false,
      );
      if (pattern.hasMatch(cleaned)) {
        cleaned = cleaned.replaceFirst(pattern, '').trim();
      }
    }

    cleaned = cleaned.replaceAll(RegExp(r'^[\s:;,.–—-]+'), '').trim();
    return cleaned;
  }

  bool _shouldExtendParagraph(String text) {
    final trimmed = text.trimRight();
    if (trimmed.isEmpty) return false;
    if (trimmed.length >= 1200) return false;
    if (RegExp(r'[.!?][")\]]?\s*$').hasMatch(trimmed)) return false;
    return true;
  }

  Future<int> _countLinks(Database db, String itemId, String folderType) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM library_links
      WHERE library_item_id = ? AND link_type = ?
      ''',
      [itemId, folderType],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<String?> _readTitle(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: false);
      final containerEntry = archive.findFile('META-INF/container.xml');
      if (containerEntry == null) return null;
      final containerXml = utf8.decode(
        containerEntry.content as List<int>,
        allowMalformed: true,
      );
      final rootfileMatch = RegExp(
        r'full-path="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(containerXml);
      final opfPath = rootfileMatch?.group(1);
      if (opfPath == null || opfPath.isEmpty) return null;
      final opfEntry = archive.findFile(opfPath);
      if (opfEntry == null) return null;
      final opfXml = utf8.decode(
        opfEntry.content as List<int>,
        allowMalformed: true,
      );
      final titleMatch = RegExp(
        r'<dc:title[^>]*>(.*?)</dc:title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(opfXml);
      final title = titleMatch?.group(1)?.trim() ?? '';
      return _stripHtml(title);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolveLibraryAuthor({
    required File file,
    required _LibraryFileMetadata metadata,
    required String relativePath,
  }) async {
    if (metadata.fileFormat != 'epub') return null;
    return resolveLibraryAuthorFromEpub(
      file,
      collectionName: metadata.collectionName,
      sourceSite: metadata.sourceSite,
      relativePath: relativePath,
    );
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
      if (coverHref == null || coverHref.trim().isEmpty) return null;
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

  String _stripHtml(String text) {
    var out = text
        .replaceAll(
          RegExp(r'<script.*?</script>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(
          RegExp(r'<style.*?</style>', caseSensitive: false, dotAll: true),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' ');
    out = out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _itemId(String folderType, String relativePath) {
    return 'library_item_${_slug(folderType)}_${_slug(relativePath)}';
  }

  _LibraryFileMetadata _inferLibraryFileMetadata({
    required String relativePath,
    required String folderType,
    required File file,
    required bool isEpub,
  }) {
    final normalized = p.normalize(relativePath);
    final parts = p.split(normalized);
    final collectionName = parts.length >= 3 ? parts[2] : null;
    final sourceType = collectionName == 'User'
        ? 'user_added'
        : 'official_download';
    return _LibraryFileMetadata(
      fileFormat: isEpub ? 'epub' : 'pdf',
      libraryRole: folderType,
      collectionName: collectionName,
      sourceType: sourceType,
      sourceSite: sourceType == 'official_download' ? 'egwwritings.org' : null,
    );
  }

  String? _volumeForBook(int bookId) {
    for (final entry in _volumeScopes.entries) {
      if (bookId >= entry.value.start && bookId <= entry.value.end) {
        return entry.key;
      }
    }
    return null;
  }

  String? _inferVolumeCodeFromPath(String path) {
    final fileName = p.basename(path);
    final fromName = _inferVolumeCodeForItem(fileName, '');
    if (fromName != null) return fromName;
    return null;
  }

  String? _inferVolumeCodeForItem(String fileName, String title) {
    return _inferCommentaryVolumeCodeForItem(fileName, title);
  }

  List<File> _preferEpubs(List<File> files) {
    if (files.isEmpty) return files;
    final chosen = <String, File>{};
    for (final file in files) {
      final baseKey = p.basenameWithoutExtension(file.path).toLowerCase();
      final current = chosen[baseKey];
      if (current == null) {
        chosen[baseKey] = file;
        continue;
      }
      final currentIsEpub = p.extension(current.path).toLowerCase() == '.epub';
      final nextIsEpub = p.extension(file.path).toLowerCase() == '.epub';
      if (!currentIsEpub && nextIsEpub) {
        chosen[baseKey] = file;
      }
    }
    final result = chosen.values.toList(growable: false);
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  String _slug(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<CommentaryResearchSectionData?> _loadCachedSection({
    required Database db,
    required String folderType,
    required String folderLabel,
    required String rootPath,
    required String? preferredVolumeCode,
    required Map<String, int> bookLookup,
    required List<String> bookAliases,
    required String bookName,
    required int bookId,
    required int chapter,
    required int verse,
  }) async {
    final rows = await db.query(
      'library_items',
      columns: const [
        'id',
        'title',
        'file_name',
        'relative_path',
        'file_size',
        'file_format',
        'index_status',
        'index_error',
      ],
      where: 'folder_type = ? AND deleted_at IS NULL',
      whereArgs: [folderType],
      orderBy: 'title COLLATE NOCASE ASC, file_name COLLATE NOCASE ASC',
    );
    if (rows.isEmpty) return null;
    final hasEpubFiles = rows.any((row) {
      final format =
          row['file_format']?.toString().toLowerCase() ??
          row['source_type']?.toString().toLowerCase() ??
          '';
      return format == 'epub';
    });
    if (!hasEpubFiles) return null;

    final linkCounts = await _loadLinkCountsByItemId(
      db: db,
      folderType: folderType,
    );
    final files = <CommentaryResearchFileItem>[];
    var indexedCount = 0;
    for (final row in rows) {
      final format =
          row['file_format']?.toString().toLowerCase() ??
          row['source_type']?.toString().toLowerCase() ??
          '';
      if (format != 'epub') continue;
      final itemId = row['id']?.toString() ?? '';
      final fileName = row['file_name']?.toString() ?? '';
      final title = row['title']?.toString().trim().isNotEmpty == true
          ? row['title'].toString()
          : p.basenameWithoutExtension(fileName);
      final relativePath = row['relative_path']?.toString() ?? '';
      final fileSize = (row['file_size'] as num?)?.toInt() ?? 0;
      final linksCount = linkCounts[itemId] ?? 0;
      indexedCount += linksCount;
      files.add(
        CommentaryResearchFileItem(
          id: itemId,
          title: title,
          fileName: fileName,
          relativePath: relativePath,
          fileSize: fileSize,
          indexed: linksCount > 0,
        ),
      );
    }

    final matches = await _loadMatches(
      db: db,
      folderType: folderType,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      preferredVolumeCode: preferredVolumeCode,
      chapterWideMatches: true,
    );
    final commentaryCandidates = folderType == 'commentary'
        ? CommentaryResearchFilters.dedupeMatches(matches)
        : matches;
    final commentaryMatches = folderType == 'commentary'
        ? CommentaryResearchFilters.filterCommentaryMatches(
            commentaryCandidates,
            chapter,
          )
        : matches;
    final displayMatches = folderType == 'research'
        ? CommentaryResearchFilters.prepareResearchMatches(
            matches,
            bookId: bookId,
            chapter: chapter,
            verse: verse,
          )
        : commentaryMatches;

    return CommentaryResearchSectionData(
      folderType: folderType,
      title: folderLabel,
      statusMessage: _statusMessage(
        folderLabel: folderLabel,
        bookName: bookName,
        chapter: chapter,
        candidatePaths: folderType == 'commentary'
            ? [
                p.join(rootPath, 'ePubs', 'Commentaries'),
                p.join(rootPath, 'PDFs', 'Commentaries'),
              ]
            : [
                p.join(rootPath, 'ePubs', 'Research'),
                p.join(rootPath, 'PDFs', 'Research'),
              ],
        discoveredCount: files.length,
        indexedCount: indexedCount,
        matchCount: displayMatches.length,
      ),
      files: files,
      matches: displayMatches,
      discoveredCount: files.length,
      indexedCount: indexedCount,
      matchCount: displayMatches.length,
    );
  }

  Future<Map<String, int>> _loadLinkCountsByItemId({
    required Database db,
    required String folderType,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT library_item_id, COUNT(*) AS count
      FROM library_links
      WHERE link_type = ?
      GROUP BY library_item_id
      ''',
      [folderType],
    );
    final counts = <String, int>{};
    for (final row in rows) {
      final itemId = row['library_item_id']?.toString().trim() ?? '';
      if (itemId.isEmpty) continue;
      counts[itemId] = (row['count'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<void> _writeIndexReport(
    String? reportPath,
    Map<String, Object?> report,
  ) async {
    if (reportPath == null || reportPath.trim().isEmpty) return;
    final file = File(reportPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(JsonEncoder.withIndent('  ').convert(report));
  }

  Future<CommentaryResearchEpubBookData?> _loadEpubBookData({
    required String libraryItemId,
    String? initialHref,
    String? initialAnchorId,
  }) async {
    final db = await UserDatabase.instance.database;
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path;
    if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
      return null;
    }

    final rows = await db.query(
      'library_items',
      columns: const ['title', 'relative_path', 'file_name'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [libraryItemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final title = row['title']?.toString().trim().isNotEmpty == true
        ? row['title'].toString()
        : p.basenameWithoutExtension(row['file_name']?.toString() ?? '');
    final relativePath = row['relative_path']?.toString() ?? '';
    if (relativePath.trim().isEmpty) return null;

    final file = File(p.join(rootPath, relativePath));
    if (!await file.exists()) return null;

    final navRows = await db.query(
      'library_navigation_items',
      where: 'library_item_id = ? AND deleted_at IS NULL',
      whereArgs: [libraryItemId],
      orderBy: 'sort_order ASC, depth ASC, label COLLATE NOCASE ASC',
    );
    final navigationItems = navRows
        .map(
          (row) => CommentaryResearchNavigationItem(
            id: row['id']?.toString() ?? '',
            libraryItemId: row['library_item_id']?.toString() ?? '',
            parentId: row['parent_id']?.toString(),
            label: row['label']?.toString() ?? '',
            href: row['href']?.toString(),
            anchorId: row['anchor_id']?.toString(),
            spineIndex: (row['spine_index'] as num?)?.toInt(),
            sortOrder: (row['sort_order'] as num?)?.toInt(),
            depth: (row['depth'] as num?)?.toInt(),
            navType: row['nav_type']?.toString(),
            createdAt: row['created_at']?.toString() ?? '',
            updatedAt: row['updated_at']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
    final section = await _loadEpubSectionView(
      file,
      href: initialHref,
      anchorId: initialAnchorId,
    );

    return CommentaryResearchEpubBookData(
      libraryItemId: libraryItemId,
      title: title,
      relativePath: relativePath,
      navigationItems: navigationItems,
      currentHref: section?.href ?? initialHref,
      currentAnchorId: section?.anchorId ?? initialAnchorId,
      currentLabel: section?.label ?? title,
      currentText: section?.text ?? '',
    );
  }

  Future<_EpubSectionView?> _loadEpubSectionView(
    File file, {
    String? href,
    String? anchorId,
  }) async {
    final sections = await _readBodySections(file: file, libraryItemId: '');
    if (sections.isEmpty) return null;

    _EpubSectionChunk? selected;
    if (href != null && href.trim().isNotEmpty) {
      final normalizedHref = p.normalize(href).toLowerCase();
      for (final section in sections) {
        if (p.normalize(section.entryName).toLowerCase() == normalizedHref) {
          selected = section;
          break;
        }
      }
    }
    selected ??= sections.first;

    final bodyText = selected.paragraphs
        .map(_stripHtml)
        .where((value) => value.trim().isNotEmpty)
        .join('\n\n')
        .trim();
    if (bodyText.isEmpty) return null;

    return _EpubSectionView(
      href: selected.entryName,
      anchorId: anchorId,
      label: selected.sectionTitle,
      text: bodyText,
    );
  }

  _EpubPackageInfo _readEpubPackageInfo(Archive archive) =>
      (this as dynamic)._readEpubPackageInfo(archive) as _EpubPackageInfo;

  String _coverImageExtension(String fileName) =>
      (this as dynamic)._coverImageExtension(fileName) as String;

  Future<List<_EpubSectionChunk>> _readBodySections({
    required File file,
    required String libraryItemId,
    _IndexingStats? stats,
    bool includeFrontMatter = false,
    bool preserveHeadingBlocks = false,
  }) =>
      (this as dynamic)._readBodySections(
            file: file,
            libraryItemId: libraryItemId,
            stats: stats,
            includeFrontMatter: includeFrontMatter,
            preserveHeadingBlocks: preserveHeadingBlocks,
          )
          as Future<List<_EpubSectionChunk>>;
}

class _FileIndexResult {
  const _FileIndexResult({
    required this.fileItem,
    required this.indexedLinks,
    required this.matches,
    required this.warnings,
  });

  final CommentaryResearchFileItem fileItem;
  final int indexedLinks;
  final List<CommentaryResearchMatchItem> matches;
  final List<String> warnings;
}

class _ReferenceExtractionResult {
  const _ReferenceExtractionResult({
    required this.hits,
    required this.warnings,
  });

  final List<_ParagraphReferenceHit> hits;
  final List<String> warnings;
}

class _ParagraphReferenceHit {
  const _ParagraphReferenceHit({
    required this.reference,
    required this.anchor,
    required this.fullParagraph,
    required this.epubHref,
    required this.anchorId,
    required this.spineIndex,
    required this.paragraphIndex,
  });

  final ParsedBibleReference reference;
  final String anchor;
  final String? fullParagraph;
  final String? epubHref;
  final String? anchorId;
  final int? spineIndex;
  final int? paragraphIndex;
}

class _LibraryFileMetadata {
  const _LibraryFileMetadata({
    required this.fileFormat,
    required this.libraryRole,
    required this.collectionName,
    required this.sourceType,
    required this.sourceSite,
  });

  final String fileFormat;
  final String libraryRole;
  final String? collectionName;
  final String sourceType;
  final String? sourceSite;
}

class _SectionLoadResult {
  const _SectionLoadResult({required this.section, required this.stats});

  final CommentaryResearchSectionData section;
  final _IndexingStats stats;
}

class _IndexingStats {
  int filesIndexed = 0;
  int sectionsIndexed = 0;
  int sectionsSkippedFrontMatter = 0;
  int sectionsSkippedNavigation = 0;
  int sectionsSkippedMetadata = 0;
  int sectionsSkippedEditorial = 0;
  int sectionsSkippedOther = 0;
  final List<Map<String, Object?>> skippedSectionsSample =
      <Map<String, Object?>>[];
  final List<String> indexingErrors = <String>[];

  static _IndexingStats combine(Iterable<_IndexingStats> stats) {
    final merged = _IndexingStats();
    for (final stat in stats) {
      merged.filesIndexed += stat.filesIndexed;
      merged.sectionsIndexed += stat.sectionsIndexed;
      merged.sectionsSkippedFrontMatter += stat.sectionsSkippedFrontMatter;
      merged.sectionsSkippedNavigation += stat.sectionsSkippedNavigation;
      merged.sectionsSkippedMetadata += stat.sectionsSkippedMetadata;
      merged.sectionsSkippedEditorial += stat.sectionsSkippedEditorial;
      merged.sectionsSkippedOther += stat.sectionsSkippedOther;
      merged.skippedSectionsSample.addAll(stat.skippedSectionsSample);
      merged.indexingErrors.addAll(stat.indexingErrors);
    }
    return merged;
  }

  void recordSkippedSection({
    required String libraryItemId,
    required String hrefPath,
    required String sectionTitle,
    required String reasonSkipped,
    required String category,
  }) {
    switch (category) {
      case 'front_matter':
        sectionsSkippedFrontMatter += 1;
        break;
      case 'navigation':
        sectionsSkippedNavigation += 1;
        break;
      case 'metadata':
        sectionsSkippedMetadata += 1;
        break;
      case 'editorial':
        sectionsSkippedEditorial += 1;
        break;
      default:
        sectionsSkippedOther += 1;
        break;
    }
    if (skippedSectionsSample.length >= 20) return;
    skippedSectionsSample.add(<String, Object?>{
      'library_item_id': libraryItemId,
      'href_path': hrefPath,
      'section_title': sectionTitle,
      'reason_skipped': reasonSkipped,
      'indexed_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

class _EpubSectionChunk {
  const _EpubSectionChunk({
    required this.entryName,
    required this.sectionTitle,
    required this.paragraphs,
    required this.blocks,
    required this.spineIndex,
  });

  final String entryName;
  final String sectionTitle;
  final List<String> paragraphs;
  final List<LibraryBookBlock> blocks;
  final int? spineIndex;
}

class _HtmlBlockFrame {
  const _HtmlBlockFrame({
    required this.tag,
    required this.attrs,
    required this.start,
    required this.contentStart,
  });

  final String tag;
  final String attrs;
  final int start;
  final int contentStart;
}

class _EpubManifestItem {
  const _EpubManifestItem({required this.href, required this.properties});

  final String href;
  final String properties;
}

class _NavigationEntryDraft {
  const _NavigationEntryDraft({
    required this.id,
    required this.libraryItemId,
    required this.parentId,
    required this.label,
    required this.href,
    required this.anchorId,
    required this.spineIndex,
    required this.sortOrder,
    required this.depth,
    required this.navType,
    required this.contentKind,
    this.isFrontMatter = false,
    this.isBodyStart = false,
    this.bodyOrder,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
  });

  final String id;
  final String libraryItemId;
  final String? parentId;
  final String label;
  final String? href;
  final String? anchorId;
  final int? spineIndex;
  final int? sortOrder;
  final int? depth;
  final String navType;
  final String contentKind;
  final bool isFrontMatter;
  final bool isBodyStart;
  final int? bodyOrder;
  final String createdAt;
  final String updatedAt;
  final String deviceId;

  _NavigationEntryDraft copyWith({
    String? contentKind,
    bool? isFrontMatter,
    bool? isBodyStart,
    int? bodyOrder,
  }) {
    return _NavigationEntryDraft(
      id: id,
      libraryItemId: libraryItemId,
      parentId: parentId,
      label: label,
      href: href,
      anchorId: anchorId,
      spineIndex: spineIndex,
      sortOrder: sortOrder,
      depth: depth,
      navType: navType,
      contentKind: contentKind ?? this.contentKind,
      isFrontMatter: isFrontMatter ?? this.isFrontMatter,
      isBodyStart: isBodyStart ?? this.isBodyStart,
      bodyOrder: bodyOrder ?? this.bodyOrder,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deviceId: deviceId,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'library_item_id': libraryItemId,
    'parent_id': parentId,
    'label': label,
    'href': href,
    'anchor_id': anchorId,
    'spine_index': spineIndex,
    'sort_order': sortOrder,
    'depth': depth,
    'nav_type': navType,
    'content_kind': contentKind,
    'is_front_matter': isFrontMatter ? 1 : 0,
    'is_body_start': isBodyStart ? 1 : 0,
    'body_order': bodyOrder,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': null,
    'device_id': deviceId,
    'revision': 1,
    'sync_status': 'pending',
    'last_synced_at': null,
    'change_id': null,
  };
}

class _EpubSectionDecision {
  const _EpubSectionDecision._({
    required this.shouldSkip,
    required this.category,
    required this.reason,
    required this.sectionTitle,
  });

  const _EpubSectionDecision.keep({required String sectionTitle})
    : this._(
        shouldSkip: false,
        category: 'other',
        reason: '',
        sectionTitle: sectionTitle,
      );

  const _EpubSectionDecision.skip({
    required String category,
    required String reason,
    required String sectionTitle,
  }) : this._(
         shouldSkip: true,
         category: category,
         reason: reason,
         sectionTitle: sectionTitle,
       );

  final bool shouldSkip;
  final String category;
  final String reason;
  final String sectionTitle;
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

  bool isNavigationPath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    return navigationPaths.contains(normalized);
  }

  bool isBodyPath(String path) {
    if (spinePaths.isEmpty) return true;
    final normalized = p.normalize(path).toLowerCase();
    return spinePaths.contains(normalized);
  }

  ArchiveFile? findArchiveEntry(Archive archive, String path) {
    final normalized = p.normalize(path).toLowerCase();
    for (final entry in archive) {
      if (!entry.isFile) continue;
      if (p.normalize(entry.name).toLowerCase() == normalized) {
        return entry;
      }
    }
    return null;
  }

  int? spineIndexForPath(String path) {
    final normalized = p.normalize(path).toLowerCase();
    final index = spineOrderedPaths.indexOf(normalized);
    return index < 0 ? null : index + 1;
  }

  String navigationTypeFor(String path, String raw) {
    final normalized = p.normalize(path).toLowerCase();
    final lowerRaw = raw.toLowerCase();
    if (normalized.contains('landmark') || lowerRaw.contains('landmark')) {
      return 'landmark';
    }
    if (normalized.contains('nav') || normalized.contains('toc')) {
      return 'toc';
    }
    return 'navigation';
  }
}

class _EpubSectionView {
  const _EpubSectionView({
    required this.href,
    required this.anchorId,
    required this.label,
    required this.text,
  });

  final String href;
  final String? anchorId;
  final String label;
  final String text;
}
