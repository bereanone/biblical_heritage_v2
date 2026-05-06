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

mixin _CommentaryResearchLibraryServiceEpubSupport {
  Future<_FileIndexResult> _indexFile({
    required Database db,
    required String rootPath,
    required String folderType,
    required File file,
    required _IndexingStats stats,
    required Map<String, int> bookLookup,
    required List<String> bookAliases,
    required bool refresh,
    required String deviceId,
  }) async {
    stats.filesIndexed += 1;
    final stat = await file.stat();
    final fingerprint = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final relativePath = await LibraryRootService.instance.relativePathFor(
      absolutePath: file.path,
      rootPath: rootPath,
    );
    final itemId = _itemId(folderType, relativePath);
    final now = DateTime.now().toUtc().toIso8601String();
    final ext = p.extension(file.path).toLowerCase();
    final isEpub = ext == '.epub';
    final title = isEpub
        ? await _readTitle(file) ?? p.basenameWithoutExtension(file.path)
        : p.basenameWithoutExtension(file.path);
    final metadata = _inferLibraryFileMetadata(
      relativePath: relativePath,
      folderType: folderType,
      file: file,
      isEpub: isEpub,
    );
    final existing = await db.query(
      'library_items',
      columns: const [
        'file_hash',
        'source_url',
        'source_site',
        'collection_name',
        'indexed_at',
        'index_status',
        'index_error',
      ],
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    final needsIndex =
        refresh ||
        existing.isEmpty ||
        (existing.first['file_hash']?.toString() ?? '') != fingerprint ||
        (existing.first['index_status']?.toString() ?? '').toLowerCase() !=
            'indexed' ||
        (existing.first['index_error']?.toString().trim() ?? '').isNotEmpty;
    final existingRow = existing.isEmpty
        ? const <String, Object?>{}
        : existing.first;
    await db.insert('library_items', {
      'id': itemId,
      'title': title,
      'author': null,
      'file_name': p.basename(file.path),
      'relative_path': relativePath,
      'file_hash': fingerprint,
      'file_size': stat.size,
      'modified_at': stat.modified.toUtc().toIso8601String(),
      'mime_type': isEpub ? 'application/epub+zip' : 'application/pdf',
      'file_format': metadata.fileFormat,
      'folder_type': folderType,
      'library_role': metadata.libraryRole,
      'collection_name':
          metadata.collectionName ?? existingRow['collection_name']?.toString(),
      'source_site':
          metadata.sourceSite ?? existingRow['source_site']?.toString(),
      'source_url': existingRow['source_url']?.toString(),
      'date_added': now,
      'last_opened': null,
      'source_type': metadata.sourceType,
      'indexed_at': isEpub ? null : now,
      'index_status': isEpub ? 'pending' : 'metadata_only',
      'index_error': null,
      'epub_href': null,
      'epub_cfi': null,
      'anchor_id': null,
      'spine_index': null,
      'paragraph_index': null,
      'is_missing': 0,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (isEpub) {
      await _storeNavigationMetadata(
        db: db,
        file: file,
        libraryItemId: itemId,
        relativePath: relativePath,
        title: title,
        deviceId: deviceId,
      );
    }

    if (!isEpub) {
      return _FileIndexResult(
        fileItem: CommentaryResearchFileItem(
          id: itemId,
          title: title,
          fileName: p.basename(file.path),
          relativePath: relativePath,
          fileSize: stat.size,
          indexed: false,
        ),
        indexedLinks: 0,
        matches: const [],
        warnings: const [],
      );
    }

    if (!needsIndex) {
      final linksCount = await _countLinks(db, itemId, folderType);
      return _FileIndexResult(
        fileItem: CommentaryResearchFileItem(
          id: itemId,
          title: title,
          fileName: p.basename(file.path),
          relativePath: relativePath,
          fileSize: stat.size,
          indexed: linksCount > 0,
        ),
        indexedLinks: linksCount,
        matches: const [],
        warnings: const [],
      );
    }

    try {
      final extracted = await _extractReferences(
        file: file,
        libraryItemId: itemId,
        relativePath: relativePath,
        title: title,
        folderType: folderType,
        bookLookup: bookLookup,
        bookAliases: bookAliases,
        stats: stats,
      );
      await db.delete(
        'library_links',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );

      var inserted = 0;
      final matches = <CommentaryResearchMatchItem>[];
      for (final hit in extracted.hits) {
        final reference = hit.reference;
        final linkId =
            'link_${_slug(folderType)}_${_slug(relativePath)}_${reference.bookId}_${reference.chapter}_${reference.verseStart}_${reference.verseEnd}';
        await db.insert('library_links', {
          'id': linkId,
          'library_item_id': itemId,
          'book_id': reference.bookId,
          'chapter': reference.chapter,
          'verse_start': reference.verseStart,
          'verse_end': reference.verseEnd,
          'link_type': folderType,
          'anchor': hit.anchor,
          'original_reference_text': reference.originalReferenceText,
          'confidence': reference.confidence,
          'parser_warning': reference.parserWarning,
          'epub_href': hit.epubHref,
          'epub_cfi': null,
          'anchor_id': hit.anchorId,
          'spine_index': hit.spineIndex,
          'paragraph_index': hit.paragraphIndex,
          'full_paragraph': hit.fullParagraph,
          'created_by': 'epub_indexer',
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
          'device_id': deviceId,
          'revision': 1,
          'sync_status': 'pending',
          'last_synced_at': null,
          'change_id': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        inserted += 1;
        matches.add(
          CommentaryResearchMatchItem(
            libraryItemId: itemId,
            itemTitle: title,
            fileName: p.basename(file.path),
            relativePath: relativePath,
            originalReferenceText: reference.originalReferenceText,
            bookId: reference.bookId,
            chapter: reference.chapter,
            verseStart: reference.verseStart,
            verseEnd: reference.verseEnd,
            confidence: reference.confidence,
            anchor: hit.anchor,
            fullParagraph: hit.fullParagraph,
            parserWarning: reference.parserWarning,
            epubCfi: null,
          ),
        );
      }

      await db.update(
        'library_items',
        {
          'indexed_at': now,
          'index_status': inserted > 0 ? 'indexed' : 'indexed_empty',
          'index_error': null,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      return _FileIndexResult(
        fileItem: CommentaryResearchFileItem(
          id: itemId,
          title: title,
          fileName: p.basename(file.path),
          relativePath: relativePath,
          fileSize: stat.size,
          indexed: inserted > 0,
        ),
        indexedLinks: inserted,
        matches: matches,
        warnings: extracted.warnings,
      );
    } catch (error) {
      stats.indexingErrors.add(error.toString());
      await db.update(
        'library_items',
        {
          'indexed_at': now,
          'index_status': 'failed',
          'index_error': error.toString(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );
      return _FileIndexResult(
        fileItem: CommentaryResearchFileItem(
          id: itemId,
          title: title,
          fileName: p.basename(file.path),
          relativePath: relativePath,
          fileSize: stat.size,
          indexed: false,
        ),
        indexedLinks: 0,
        matches: const [],
        warnings: [error.toString()],
      );
    }
  }

  String _statusMessage({
    required String folderLabel,
    required int discoveredCount,
    required int indexedCount,
    required int matchCount,
  }) {
    if (discoveredCount == 0) {
      return 'No $folderLabel files found in the Library Root Folder.';
    }
    if (matchCount > 0) {
      return 'Matching $folderLabel entries found for this passage.';
    }
    if (indexedCount > 0) {
      return '$folderLabel files indexed, but no entries for this passage.';
    }
    return '$folderLabel files found, but not indexed to this passage yet.';
  }

  Future<_ReferenceExtractionResult> _extractReferences({
    required File file,
    required String libraryItemId,
    required String relativePath,
    required String title,
    required String folderType,
    required Map<String, int> bookLookup,
    required List<String> bookAliases,
    required _IndexingStats stats,
  }) async {
    final sections = await _readBodySections(
      file: file,
      libraryItemId: libraryItemId,
      stats: stats,
    );
    final buffer = StringBuffer();
    final hits = <_ParagraphReferenceHit>[];
    final seen = <String>{};
    final fileName = p.basename(file.path);

    for (final section in sections) {
      for (
        var paragraphIndex = 0;
        paragraphIndex < section.paragraphs.length;
        paragraphIndex++
      ) {
        final paragraph = section.paragraphs[paragraphIndex];
        final stripped = folderType == 'commentary'
            ? _cleanCommentaryParagraph(
                _expandParagraphContext(section.paragraphs, paragraphIndex),
                sectionTitle: section.sectionTitle,
                bookTitle: title,
              )
            : _stripHtml(paragraph);
        if (stripped.isEmpty) continue;

        final referenceText = [
          stripped,
          ...RegExp(r'title="([^"]+)"', caseSensitive: false)
              .allMatches(paragraph)
              .map((match) => match.group(1) ?? '')
              .where((value) => value.trim().isNotEmpty),
        ].join(' ');
        if (referenceText.trim().isEmpty) continue;

        final probe = CommentaryResearchMatchItem(
          libraryItemId: libraryItemId,
          itemTitle: section.sectionTitle.isNotEmpty
              ? section.sectionTitle
              : title,
          fileName: fileName,
          relativePath: relativePath,
          originalReferenceText: referenceText,
          bookId: 0,
          chapter: 0,
          verseStart: 0,
          verseEnd: 0,
          confidence: 0,
          anchor: stripped,
          parserWarning: null,
          epubCfi: null,
        );
        if (CommentaryResearchFilters.isFrontMatterOrEditorialHit(probe) ||
            !CommentaryResearchFilters.isUsableResearchParagraph(stripped)) {
          continue;
        }

        buffer.writeln(stripped);
        final extracted = BibleReferenceParser.extractReferences(
          referenceText,
          bookLookup,
          aliases: bookAliases,
        );
        for (final reference in extracted) {
          final hitProbe = CommentaryResearchMatchItem(
            libraryItemId: libraryItemId,
            itemTitle: section.sectionTitle.isNotEmpty
                ? section.sectionTitle
                : title,
            fileName: fileName,
            relativePath: relativePath,
            originalReferenceText: reference.originalReferenceText,
            bookId: reference.bookId,
            chapter: reference.chapter,
            verseStart: reference.verseStart,
            verseEnd: reference.verseEnd,
            confidence: reference.confidence,
            anchor: stripped,
            parserWarning: reference.parserWarning,
            epubCfi: null,
          );
          if (CommentaryResearchFilters.isFrontMatterOrEditorialHit(hitProbe)) {
            continue;
          }
          final key =
              '${reference.bookId}|${reference.chapter}|${reference.verseStart}|${reference.verseEnd}|${reference.originalReferenceText}';
          if (!seen.add(key)) continue;
          hits.add(
            _ParagraphReferenceHit(
              reference: reference,
              anchor: stripped,
              fullParagraph: folderType == 'commentary' ? stripped : null,
              epubHref: section.entryName,
              anchorId: null,
              spineIndex: section.spineIndex,
              paragraphIndex: paragraphIndex + 1,
            ),
          );
        }
      }
    }

    final cleaned = buffer.toString().trim();
    final warnings = <String>[];
    if (cleaned.isEmpty) {
      warnings.add('${file.path}: no readable HTML content.');
      return const _ReferenceExtractionResult(
        hits: <_ParagraphReferenceHit>[],
        warnings: <String>[],
      );
    }

    if (hits.isEmpty) {
      final fallbackReferences = BibleReferenceParser.extractReferences(
        cleaned,
        bookLookup,
        aliases: bookAliases,
      );
      for (final reference in fallbackReferences) {
        final key =
            '${reference.bookId}|${reference.chapter}|${reference.verseStart}|${reference.verseEnd}|${reference.originalReferenceText}';
        if (!seen.add(key)) continue;
        hits.add(
          _ParagraphReferenceHit(
            reference: reference,
            anchor: cleaned,
            fullParagraph: folderType == 'commentary' ? cleaned : null,
            epubHref: null,
            anchorId: null,
            spineIndex: null,
            paragraphIndex: null,
          ),
        );
      }
    }
    if (hits.isEmpty) {
      warnings.add('${p.basename(file.path)}: no canonical references found.');
    }
    return _ReferenceExtractionResult(hits: hits, warnings: warnings);
  }

  Future<void> _storeNavigationMetadata({
    required Database db,
    required File file,
    required String libraryItemId,
    required String relativePath,
    required String title,
    required String deviceId,
  }) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final packageInfo = _readEpubPackageInfo(archive);
    final now = DateTime.now().toUtc().toIso8601String();

    await db.delete(
      'library_navigation_items',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );

    final entries = <_NavigationEntryDraft>[];
    var sortOrder = 0;
    for (final spinePath in packageInfo.spineOrderedPaths) {
      final entry = packageInfo.findArchiveEntry(archive, spinePath);
      final sectionTitle = entry == null
          ? p.basenameWithoutExtension(spinePath)
          : _extractSectionTitle(
                  utf8.decode(entry.content as List<int>, allowMalformed: true),
                ) ??
                p.basenameWithoutExtension(spinePath);
      sortOrder += 1;
      entries.add(
        _NavigationEntryDraft(
          id: 'nav_${_slug(libraryItemId)}_${_slug(spinePath)}',
          libraryItemId: libraryItemId,
          parentId: null,
          label: sectionTitle,
          href: spinePath,
          anchorId: null,
          spineIndex: sortOrder,
          sortOrder: sortOrder,
          depth: 0,
          navType: 'spine',
          createdAt: now,
          updatedAt: now,
          deviceId: deviceId,
        ),
      );
    }

    for (final navPath in packageInfo.navigationPaths) {
      final navEntry = packageInfo.findArchiveEntry(archive, navPath);
      if (navEntry == null) continue;
      final raw = utf8.decode(
        navEntry.content as List<int>,
        allowMalformed: true,
      );
      final navType = packageInfo.navigationTypeFor(navPath, raw);
      entries.addAll(
        _extractNavigationEntriesFromDocument(
          raw: raw,
          basePath: navPath,
          libraryItemId: libraryItemId,
          navType: navType,
          deviceId: deviceId,
          startSortOrder: ++sortOrder,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    for (final entry in entries) {
      await db.insert(
        'library_navigation_items',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<List<_EpubSectionChunk>> _readBodySections({
    required File file,
    required String libraryItemId,
    _IndexingStats? stats,
  }) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final packageInfo = _readEpubPackageInfo(archive);
    final sections = <_EpubSectionChunk>[];
    final fileId = libraryItemId;

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final entryName = p.normalize(entry.name);
      final lowerName = entryName.toLowerCase();
      if (!lowerName.endsWith('.xhtml') && !lowerName.endsWith('.html')) {
        continue;
      }

      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final title =
          _extractSectionTitle(raw) ?? p.basenameWithoutExtension(entryName);
      final decision = _classifyEpubSection(
        entryName: entryName,
        sectionTitle: title,
        raw: raw,
        packageInfo: packageInfo,
      );
      if (decision.shouldSkip) {
        stats?.recordSkippedSection(
          libraryItemId: fileId,
          hrefPath: entryName,
          sectionTitle: title,
          reasonSkipped: decision.reason,
          category: decision.category,
        );
        continue;
      }

      final paragraphs =
          RegExp(r'<p[^>]*>.*?</p>', caseSensitive: false, dotAll: true)
              .allMatches(raw)
              .map((match) => match.group(0) ?? '')
              .where((paragraph) => paragraph.isNotEmpty)
              .toList(growable: false);
      if (paragraphs.isEmpty) {
        stats?.recordSkippedSection(
          libraryItemId: fileId,
          hrefPath: entryName,
          sectionTitle: title,
          reasonSkipped: 'No readable HTML content.',
          category: 'other',
        );
        continue;
      }

      stats?.sectionsIndexed += 1;
      sections.add(
        _EpubSectionChunk(
          entryName: entryName,
          sectionTitle: title,
          paragraphs: paragraphs,
          spineIndex: packageInfo.spineIndexForPath(entryName),
        ),
      );
    }

    if (sections.isEmpty) {
      stats?.indexingErrors.add('${file.path}: no readable HTML content.');
    }
    return sections;
  }

  _EpubSectionDecision _classifyEpubSection({
    required String entryName,
    required String sectionTitle,
    required String raw,
    required _EpubPackageInfo packageInfo,
  }) {
    final normalized = entryName.toLowerCase();
    final fileName = p.basename(normalized);
    final bodyText = _stripHtml(raw);
    final bodyPreview = CommentaryResearchFilters.normalizeForSearch(
      bodyText.length > 180 ? bodyText.substring(0, 180) : bodyText,
    );
    final titleText = CommentaryResearchFilters.normalizeForSearch(
      sectionTitle,
    );
    final sourceText = CommentaryResearchFilters.normalizeForSearch(
      '$sectionTitle $fileName $normalized $bodyPreview',
    );

    if (packageInfo.isNavigationPath(normalized) ||
        fileName == 'nav.xhtml' ||
        fileName == 'toc.xhtml' ||
        fileName == 'toc.ncx' ||
        fileName == 'cover.xhtml' ||
        fileName == 'titlepage.xhtml') {
      return _EpubSectionDecision.skip(
        category: 'navigation',
        reason: 'Navigation or table-of-contents document.',
        sectionTitle: sectionTitle,
      );
    }

    if (!packageInfo.isBodyPath(normalized)) {
      return _EpubSectionDecision.skip(
        category: 'metadata',
        reason: 'Not part of the EPUB spine.',
        sectionTitle: sectionTitle,
      );
    }

    if (_looksLikeFrontMatterSection(
      titleText: titleText,
      fileName: fileName,
      bodyPreview: bodyPreview,
      sourceText: sourceText,
    )) {
      final category =
          _looksLikeEditorialSection(
            titleText: titleText,
            fileName: fileName,
            bodyPreview: bodyPreview,
            sourceText: sourceText,
          )
          ? 'editorial'
          : 'front_matter';
      return _EpubSectionDecision.skip(
        category: category,
        reason: 'Front-matter or editorial section.',
        sectionTitle: sectionTitle,
      );
    }

    return _EpubSectionDecision.keep(sectionTitle: sectionTitle);
  }

  bool _looksLikeFrontMatterSection({
    required String titleText,
    required String fileName,
    required String bodyPreview,
    required String sourceText,
  }) {
    final exactTitleNeedles = <String>{
      'preface',
      'foreword',
      'introduction',
      'intro',
      'contents',
      'table of contents',
      'title page',
      'titlepage',
      'copyright',
      'publisher note',
      'editor note',
      'editorial note',
      'about this book',
      'about the author',
      'publication information',
      'source credits',
      'list of illustrations',
      'abbreviations',
      'dedication',
      'index',
      'bibliography',
      'metadata',
    };
    final filenameNeedles = <String>{
      'nav.xhtml',
      'toc.xhtml',
      'toc.ncx',
      'cover.xhtml',
      'titlepage.xhtml',
    };
    final titleStartsWith = <String>[
      'preface',
      'foreword',
      'introduction',
      'appendix',
      'index',
      'bibliography',
      'about this book',
      'about the author',
      'publication information',
      'source credits',
    ];

    if (filenameNeedles.contains(fileName)) return true;
    if (exactTitleNeedles.contains(titleText)) return true;
    for (final prefix in titleStartsWith) {
      if (titleText.startsWith(prefix)) return true;
    }

    final previewNeedles = <String>[
      'publisher note',
      'editor note',
      'editorial note',
      'table of contents',
      'copyright',
      'publication information',
      'source credits',
      'about this book',
      'about the author',
    ];
    for (final needle in previewNeedles) {
      if (bodyPreview.contains(needle)) return true;
    }

    return sourceText.contains('title page') ||
        sourceText.contains('table of contents') ||
        sourceText.contains('source credits');
  }

  bool _looksLikeEditorialSection({
    required String titleText,
    required String fileName,
    required String bodyPreview,
    required String sourceText,
  }) {
    final needles = <String>[
      'publisher note',
      'editor note',
      'editorial note',
      'source credits',
      'publication information',
      'about this book',
      'about the author',
    ];
    for (final needle in needles) {
      if (titleText.contains(needle) ||
          fileName.contains(needle) ||
          bodyPreview.contains(needle) ||
          sourceText.contains(needle)) {
        return true;
      }
    }
    return false;
  }

  String? _extractSectionTitle(String raw) {
    final titleMatch = RegExp(
      r'<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final headingMatch = RegExp(
      r'<h[1-6][^>]*>(.*?)</h[1-6]>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final candidate = _stripHtml(
      headingMatch?.group(1) ?? titleMatch?.group(1) ?? '',
    );
    return candidate.trim().isEmpty ? null : candidate.trim();
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

  List<_NavigationEntryDraft> _extractNavigationEntriesFromDocument({
    required String raw,
    required String basePath,
    required String libraryItemId,
    required String navType,
    required String deviceId,
    required int startSortOrder,
    required String createdAt,
    required String updatedAt,
  }) {
    final entries = <_NavigationEntryDraft>[];
    var sortOrder = startSortOrder;
    final anchorPattern = RegExp(
      r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in anchorPattern.allMatches(raw)) {
      final href = match.group(1)?.trim() ?? '';
      final label = _stripHtml(match.group(2) ?? '').trim();
      if (href.isEmpty || label.isEmpty) continue;
      final hrefParts = href.split('#');
      final resolvedPath = p.normalize(
        p.join(p.dirname(basePath), hrefParts.first),
      );
      final anchorId = hrefParts.length > 1
          ? hrefParts.sublist(1).join('#')
          : null;
      entries.add(
        _NavigationEntryDraft(
          id: 'nav_${_slug(libraryItemId)}_${_slug(basePath)}_$sortOrder',
          libraryItemId: libraryItemId,
          parentId: null,
          label: label,
          href: resolvedPath,
          anchorId: anchorId,
          spineIndex: null,
          sortOrder: sortOrder,
          depth: _estimateNavDepth(raw, match.start),
          navType: navType,
          createdAt: createdAt,
          updatedAt: updatedAt,
          deviceId: deviceId,
        ),
      );
      sortOrder += 1;
    }
    return entries;
  }

  int _estimateNavDepth(String raw, int anchorStart) {
    final prefix = raw.substring(0, anchorStart);
    final opened = RegExp(
      r'<ol\b',
      caseSensitive: false,
    ).allMatches(prefix).length;
    final closed = RegExp(
      r'</ol>',
      caseSensitive: false,
    ).allMatches(prefix).length;
    final depth = opened - closed;
    return depth < 0 ? 0 : depth;
  }

  Future<List<String>> _readBodyParagraphs(File file) async {
    final sections = await _readBodySections(file: file, libraryItemId: '');
    final paragraphs = <String>[];
    for (final section in sections) {
      paragraphs.addAll(section.paragraphs);
    }
    return paragraphs;
  }

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

    final filteredRows = preferredVolumeCode == null
        ? rows
        : rows
              .where((row) {
                final inferred = _inferVolumeCodeForItem(
                  row['file_name']?.toString() ?? '',
                  row['title']?.toString() ?? '',
                );
                return inferred == preferredVolumeCode;
              })
              .toList(growable: false);

    return filteredRows
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

  Future<List<CommentaryResearchMatchItem>> _hydrateCommentaryMatches({
    required String rootPath,
    required List<CommentaryResearchMatchItem> matches,
  }) async {
    if (matches.isEmpty) return matches;

    final grouped = <String, List<CommentaryResearchMatchItem>>{};
    for (final match in matches) {
      final path = match.relativePath.trim();
      if (path.isEmpty) continue;
      grouped
          .putIfAbsent(path, () => <CommentaryResearchMatchItem>[])
          .add(match);
    }
    if (grouped.isEmpty) return matches;

    final hydrated = <CommentaryResearchMatchItem>[];
    for (final entry in grouped.entries) {
      final file = File(p.join(rootPath, entry.key));
      if (!await file.exists()) {
        hydrated.addAll(entry.value);
        continue;
      }
      final sections = await _readBodySections(
        file: file,
        libraryItemId: entry.value.first.libraryItemId,
      );
      final allParagraphs = sections
          .expand((section) => section.paragraphs)
          .toList(growable: false);

      for (final match in entry.value) {
        final section = match.epubHref == null
            ? null
            : sections.firstWhere(
                (candidate) =>
                    p.normalize(candidate.entryName).toLowerCase() ==
                    p.normalize(match.epubHref!).toLowerCase(),
                orElse: () => const _EpubSectionChunk(
                  entryName: '',
                  sectionTitle: '',
                  paragraphs: <String>[],
                  spineIndex: null,
                ),
              );

        String? fullParagraph;
        final paragraphIndex = match.paragraphIndex;
        if (section != null &&
            section.entryName.isNotEmpty &&
            paragraphIndex != null &&
            paragraphIndex > 0 &&
            paragraphIndex <= section.paragraphs.length) {
          fullParagraph = _expandParagraphContext(
            section.paragraphs,
            paragraphIndex - 1,
          );
          if (fullParagraph.isEmpty) {
            fullParagraph = _stripHtml(section.paragraphs[paragraphIndex - 1]);
          }
        } else {
          fullParagraph = _bestCommentaryParagraphForMatch(
            allParagraphs,
            match: match,
          );
        }

        hydrated.add(
          CommentaryResearchMatchItem(
            libraryItemId: match.libraryItemId,
            itemTitle: match.itemTitle,
            fileName: match.fileName,
            relativePath: match.relativePath,
            sourceUrl: match.sourceUrl,
            originalReferenceText: match.originalReferenceText,
            bookId: match.bookId,
            chapter: match.chapter,
            verseStart: match.verseStart,
            verseEnd: match.verseEnd,
            confidence: match.confidence,
            anchor: fullParagraph ?? match.anchor,
            parserWarning: match.parserWarning,
            epubCfi: match.epubCfi,
            epubHref: match.epubHref,
            anchorId: match.anchorId,
            spineIndex: match.spineIndex,
            paragraphIndex: match.paragraphIndex,
          ),
        );
      }
    }
    return hydrated;
  }

  Future<List<String>> _readParagraphs(File file) async {
    return _readBodyParagraphs(file);
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

  String? _bestCommentaryParagraphForMatch(
    List<String> paragraphs, {
    required CommentaryResearchMatchItem match,
  }) {
    final candidate = _bestParagraphForMatch(paragraphs, match: match);
    if (candidate == null || candidate.trim().isEmpty) return candidate;

    final target = CommentaryResearchFilters.normalizeForSearch(candidate);
    if (target.isEmpty) return candidate;

    for (var index = 0; index < paragraphs.length; index++) {
      final paragraphText = _stripHtml(paragraphs[index]);
      final normalized = CommentaryResearchFilters.normalizeForSearch(
        paragraphText,
      );
      if (normalized.isEmpty) continue;
      if (normalized == target || normalized.contains(target)) {
        final expanded = _expandParagraphContext(paragraphs, index);
        return expanded.isNotEmpty ? expanded : paragraphText;
      }
    }

    return candidate;
  }

  String? _bestParagraphForMatch(
    List<String> paragraphs, {
    required CommentaryResearchMatchItem match,
  }) {
    if (paragraphs.isEmpty) return null;
    final reference = CommentaryResearchFilters.normalizeForSearch(
      '${match.originalReferenceText} ${match.itemTitle}',
    );
    final prefix = CommentaryResearchFilters.normalizeForSearch(
      (match.anchor ?? '').split(RegExp(r'\s+')).take(20).join(' '),
    );
    for (final paragraph in paragraphs) {
      final normalized = CommentaryResearchFilters.normalizeForSearch(
        paragraph,
      );
      if (reference.isNotEmpty && normalized.contains(reference)) {
        return paragraph;
      }
      if (prefix.isNotEmpty && normalized.startsWith(prefix)) {
        return paragraph;
      }
    }
    return null;
  }

  Future<List<CommentaryResearchMatchItem>> _loadLiveEpubMatches({
    required List<File> epubFiles,
    required String folderType,
    required String? preferredVolumeCode,
    required Map<String, int> bookLookup,
    required List<String> bookAliases,
    required String bookName,
    required int bookId,
    required int chapter,
    required int verse,
    required bool chapterWideMatches,
  }) async {
    if (epubFiles.isEmpty) return const [];
    final hits = <CommentaryResearchMatchItem>[];

    for (final file in epubFiles) {
      final inferred = preferredVolumeCode == null
          ? null
          : _inferVolumeCodeForItem(
              p.basename(file.path),
              await _readTitle(file) ?? '',
            );
      if (preferredVolumeCode != null && inferred != preferredVolumeCode) {
        continue;
      }

      final fileTitle =
          await _readTitle(file) ?? p.basenameWithoutExtension(file.path);
      final relativePath = await LibraryRootService.instance.relativePathFor(
        absolutePath: file.path,
        rootPath:
            (await LibraryRootService.instance.loadSelection()).path ?? '',
      );
      final paragraphs = await _readParagraphs(file);
      for (final paragraph in paragraphs) {
        final strippedParagraph = _stripHtml(paragraph);
        if (strippedParagraph.isEmpty) continue;
        final references = BibleReferenceParser.extractReferences(
          strippedParagraph,
          bookLookup,
          aliases: bookAliases,
        );
        final reference = _selectReferenceForParagraph(
          references,
          bookId: bookId,
          chapter: chapter,
          verse: verse,
          chapterWideMatches: chapterWideMatches,
        );
        if (reference == null) continue;
        hits.add(
          CommentaryResearchMatchItem(
            libraryItemId: _itemId(folderType, relativePath),
            itemTitle: fileTitle,
            fileName: p.basename(file.path),
            relativePath: relativePath,
            originalReferenceText: reference.originalReferenceText,
            bookId: reference.bookId,
            chapter: reference.chapter,
            verseStart: reference.verseStart,
            verseEnd: reference.verseEnd,
            confidence: reference.confidence,
            anchor: strippedParagraph,
            parserWarning: reference.parserWarning,
            epubCfi: null,
            epubHref: null,
            anchorId: null,
            spineIndex: null,
            paragraphIndex: null,
            sourceUrl: null,
          ),
        );
      }
    }

    debugPrint(
      '[CommentaryResearch] live fallback $folderType hits=${hits.length} '
      'selected=$bookName $chapter:${verse > 0 ? verse : 1}',
    );
    return hits;
  }

  ParsedBibleReference? _selectReferenceForParagraph(
    List<ParsedBibleReference> references, {
    required int bookId,
    required int chapter,
    required int verse,
    required bool chapterWideMatches,
  }) {
    for (final reference in references) {
      if (reference.bookId != bookId || reference.chapter != chapter) {
        continue;
      }
      if (!chapterWideMatches &&
          verse > 0 &&
          (verse < reference.verseStart || verse > reference.verseEnd)) {
        continue;
      }
      return reference;
    }
    return null;
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
    final candidate = '$fileName $title'
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
    final hasIndexedFiles = rows.any((row) {
      final format =
          row['file_format']?.toString().toLowerCase() ??
          row['source_type']?.toString().toLowerCase() ??
          '';
      if (format != 'epub') return false;
      final status = row['index_status']?.toString().toLowerCase() ?? '';
      final error = row['index_error']?.toString().trim() ?? '';
      return status == 'indexed' && error.isEmpty;
    });
    if (!hasIndexedFiles) return null;

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
      final linksCount = await _countLinks(db, itemId, folderType);
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
    required this.spineIndex,
  });

  final String entryName;
  final String sectionTitle;
  final List<String> paragraphs;
  final int? spineIndex;
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
  final String createdAt;
  final String updatedAt;
  final String deviceId;

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
    this.spinePaths = const <String>{},
    this.spineOrderedPaths = const <String>[],
    this.navigationPaths = const <String>{},
  });

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
