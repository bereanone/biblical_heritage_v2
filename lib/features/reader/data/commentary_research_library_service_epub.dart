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
    const indexVersion = 'epub_nav_v3';
    final fingerprint =
        '$indexVersion:${stat.size}:${stat.modified.millisecondsSinceEpoch}';
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
    final author = await _resolveLibraryAuthor(
      file: file,
      metadata: metadata,
      relativePath: relativePath,
    );
    final existing = await db.query(
      'library_items',
      columns: const [
        'file_hash',
        'source_url',
        'source_site',
        'collection_name',
        'cover_path',
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
    final existingCoverPath = existingRow['cover_path']?.toString().trim();
    await db.insert('library_items', {
      'id': itemId,
      'title': title,
      'author': author,
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
      'cover_path': existingCoverPath,
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
      final coverPath = await _cacheEpubCover(
        file: file,
        rootPath: rootPath,
        itemId: itemId,
      );
      if (coverPath != null) {
        await db.update(
          'library_items',
          {'cover_path': coverPath, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }
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
      if (isEpub &&
          (existingCoverPath == null || existingCoverPath.trim().isEmpty)) {
        final coverPath = await _cacheEpubCover(
          file: file,
          rootPath: rootPath,
          itemId: itemId,
        );
        if (coverPath != null) {
          await db.update(
            'library_items',
            {'cover_path': coverPath, 'updated_at': now},
            where: 'id = ?',
            whereArgs: [itemId],
          );
        }
      }
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
    final seenKeys = <String>{};
    for (final navPath in packageInfo.navigationPaths) {
      final navEntry = packageInfo.findArchiveEntry(archive, navPath);
      if (navEntry == null) continue;
      final raw = utf8.decode(
        navEntry.content as List<int>,
        allowMalformed: true,
      );
      final navType = packageInfo.navigationTypeFor(navPath, raw);
      for (final entry in _extractNavigationEntriesFromDocument(
        raw: raw,
        basePath: navPath,
        libraryItemId: libraryItemId,
        navType: navType,
        deviceId: deviceId,
        createdAt: now,
        updatedAt: now,
      )) {
        final key = _navigationEntryKey(
          entry.label,
          entry.href,
          entry.anchorId,
        );
        if (!seenKeys.add(key)) continue;
        entries.add(entry);
      }
    }

    final rootsByHref = <String, _NavigationEntryDraft>{};
    for (final entry in entries) {
      if (entry.parentId != null || entry.href == null) continue;
      rootsByHref.putIfAbsent(_navigationHrefKey(entry.href!), () => entry);
    }

    final hasTOCRoots = rootsByHref.isNotEmpty;
    if (!hasTOCRoots) {
      var spineSortOrder = 0;
      for (final spinePath in packageInfo.spineOrderedPaths) {
        final entry = packageInfo.findArchiveEntry(archive, spinePath);
        final sectionTitle = entry == null
            ? p.basenameWithoutExtension(spinePath)
            : _extractSectionTitle(
                    utf8.decode(
                      entry.content as List<int>,
                      allowMalformed: true,
                    ),
                  ) ??
                  p.basenameWithoutExtension(spinePath);
        spineSortOrder += 1;
        final rootEntry = _NavigationEntryDraft(
          id: 'nav_${_slug(libraryItemId)}_${_slug(spinePath)}',
          libraryItemId: libraryItemId,
          parentId: null,
          label: sectionTitle,
          href: spinePath,
          anchorId: null,
          spineIndex: spineSortOrder,
          sortOrder: spineSortOrder,
          depth: 0,
          navType: 'spine',
          contentKind: _navigationContentKind(
            label: sectionTitle,
            href: spinePath,
            navType: 'spine',
          ),
          createdAt: now,
          updatedAt: now,
          deviceId: deviceId,
        );
        final key = _navigationEntryKey(
          rootEntry.label,
          rootEntry.href,
          rootEntry.anchorId,
        );
        if (!seenKeys.add(key)) continue;
        entries.add(rootEntry);
        rootsByHref.putIfAbsent(_navigationHrefKey(spinePath), () => rootEntry);
      }
    }

    for (final spinePath in packageInfo.spineOrderedPaths) {
      final entry = packageInfo.findArchiveEntry(archive, spinePath);
      if (entry == null) continue;
      final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      final sectionTitle =
          _extractSectionTitle(raw) ?? p.basenameWithoutExtension(spinePath);
      final sectionBlocks = _extractBodyBlocks(
        raw: raw,
        chapterPath: spinePath,
        sectionTitle: sectionTitle,
        includeHeadingBlocks: true,
      );

      final rootEntry =
          rootsByHref[_navigationHrefKey(spinePath)] ??
          (() {
            final fallbackSortOrder =
                (packageInfo.spineIndexForPath(spinePath) ?? 1) * 1000;
            final fallbackRoot = _NavigationEntryDraft(
              id: 'nav_${_slug(libraryItemId)}_${_slug(spinePath)}',
              libraryItemId: libraryItemId,
              parentId: null,
              label: sectionTitle,
              href: spinePath,
              anchorId: null,
              spineIndex: packageInfo.spineIndexForPath(spinePath),
              sortOrder: fallbackSortOrder,
              depth: 0,
              navType: 'spine',
              contentKind: _navigationContentKind(
                label: sectionTitle,
                href: spinePath,
                navType: 'spine',
              ),
              createdAt: now,
              updatedAt: now,
              deviceId: deviceId,
            );
            final key = _navigationEntryKey(
              fallbackRoot.label,
              fallbackRoot.href,
              fallbackRoot.anchorId,
            );
            if (seenKeys.add(key)) {
              entries.add(fallbackRoot);
            }
            rootsByHref[_navigationHrefKey(spinePath)] = fallbackRoot;
            return fallbackRoot;
          })();

      var headingIndex = 0;
      for (final block in sectionBlocks) {
        if (!block.isHeading) continue;
        if (_isChapterTitleBlock(block.text, sectionTitle: sectionTitle)) {
          continue;
        }

        headingIndex += 1;
        final anchorId = _generatedHeadingAnchor(
          chapterPath: spinePath,
          headingIndex: headingIndex,
          headingText: block.text,
          explicitAnchorId: block.anchorId,
        );
        final childEntry = _NavigationEntryDraft(
          id: 'nav_${_slug(libraryItemId)}_${_slug(spinePath)}_heading_$headingIndex',
          libraryItemId: libraryItemId,
          parentId: rootEntry.id,
          label: block.text,
          href: rootEntry.href ?? spinePath,
          anchorId: anchorId,
          spineIndex: rootEntry.spineIndex,
          sortOrder: (rootEntry.sortOrder ?? 0) * 1000 + headingIndex,
          depth: (rootEntry.depth ?? 0) + 1,
          navType: 'body',
          contentKind: 'body_subsection',
          isFrontMatter: false,
          isBodyStart: false,
          bodyOrder: block.bodyOrder,
          createdAt: now,
          updatedAt: now,
          deviceId: deviceId,
        );
        final key = _navigationEntryKey(
          childEntry.label,
          childEntry.href,
          childEntry.anchorId,
        );
        if (!seenKeys.add(key)) continue;
        entries.add(childEntry);
      }
    }

    final finalizedEntries = _finalizeNavigationEntries(
      List<_NavigationEntryDraft>.of(entries)..sort(_compareNavigationDrafts),
    );
    for (final entry in finalizedEntries) {
      await db.insert(
        'library_navigation_items',
        entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  List<_NavigationEntryDraft> _finalizeNavigationEntries(
    List<_NavigationEntryDraft> entries,
  ) {
    if (entries.isEmpty) return entries;

    final bodyStartIndex = _navigationBodyStartIndex(entries);
    var bodyOrder = 0;
    final finalized = <_NavigationEntryDraft>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final contentKind = entry.contentKind;
      final isFrontMatter =
          _isNavigationFrontMatterKind(contentKind) ||
          (contentKind == 'introduction' &&
              bodyStartIndex != null &&
              index < bodyStartIndex);
      final isBodyStart =
          bodyStartIndex != null &&
          index == bodyStartIndex &&
          !isFrontMatter &&
          contentKind != 'appendix';
      final isBody =
          !isFrontMatter &&
          contentKind != 'appendix' &&
          (bodyStartIndex == null || index >= bodyStartIndex);
      finalized.add(
        entry.copyWith(
          isFrontMatter: isFrontMatter,
          isBodyStart: isBodyStart,
          bodyOrder: entry.bodyOrder ?? (isBody ? ++bodyOrder : null),
        ),
      );
    }
    return finalized;
  }

  int? _navigationBodyStartIndex(List<_NavigationEntryDraft> entries) {
    for (var index = 0; index < entries.length; index++) {
      if (entries[index].contentKind == 'body') {
        return index;
      }
    }

    for (var index = 0; index < entries.length; index++) {
      final contentKind = entries[index].contentKind;
      if (_isNavigationFrontMatterKind(contentKind) ||
          contentKind == 'appendix' ||
          contentKind == 'unknown') {
        continue;
      }
      return index;
    }

    return null;
  }

  bool _isNavigationFrontMatterKind(String kind) {
    return <String>{
      'cover',
      'title_page',
      'toc',
      'about',
      'copyright',
      'preface',
      'foreword',
      'introduction',
    }.contains(kind);
  }

  String _navigationContentKind({
    required String label,
    required String href,
    required String navType,
  }) {
    final normalizedLabel = _normalizeNavigationText(label);
    final normalizedHref = _normalizeNavigationText(
      p.basenameWithoutExtension(href),
    );
    final combined = '$normalizedLabel $normalizedHref';

    if (_isNavigationCoverLabel(combined)) return 'cover';
    if (_isNavigationTitlePageLabel(combined)) return 'title_page';
    if (_isNavigationTocLabel(combined) || navType.toLowerCase() == 'toc') {
      return 'toc';
    }
    if (_isNavigationAboutLabel(combined)) return 'about';
    if (_isNavigationCopyrightLabel(combined)) return 'copyright';
    if (_isNavigationForewordLabel(combined)) return 'foreword';
    if (_isNavigationPrefaceLabel(combined)) return 'preface';
    if (_isNavigationIntroductionLabel(combined)) return 'introduction';
    if (_isNavigationAppendixLabel(combined)) return 'appendix';
    if (_isNavigationBodyLabel(combined)) return 'body';
    return 'unknown';
  }

  bool _isNavigationCoverLabel(String value) {
    return value.contains('cover');
  }

  bool _isNavigationTitlePageLabel(String value) {
    return value.contains('title page') || value.contains('titlepage');
  }

  bool _isNavigationTocLabel(String value) {
    return value.contains('table of contents') ||
        value == 'toc' ||
        value.startsWith('toc ') ||
        value.contains(' contents') ||
        value.startsWith('nav ');
  }

  bool _isNavigationAboutLabel(String value) {
    return value.contains('about book') ||
        value.contains('aboutbook') ||
        value.contains('information about this book') ||
        value.contains('about this book') ||
        value.contains('about the author');
  }

  bool _isNavigationCopyrightLabel(String value) {
    return value.contains('copyright') ||
        value.contains('publisher') ||
        value.contains('editorial') ||
        value.contains('publication information') ||
        value.contains('source credits');
  }

  bool _isNavigationForewordLabel(String value) {
    return value.startsWith('foreword');
  }

  bool _isNavigationPrefaceLabel(String value) {
    return value.startsWith('preface');
  }

  bool _isNavigationIntroductionLabel(String value) {
    return value.startsWith('introduction') ||
        value.startsWith('intro') ||
        value.contains('to the reader') ||
        value.contains('for the reader');
  }

  bool _isNavigationAppendixLabel(String value) {
    return value.startsWith('appendix') ||
        value.contains('back matter') ||
        value.contains('afterword') ||
        value.contains('bibliography') ||
        value.contains('index');
  }

  bool _isNavigationBodyLabel(String value) {
    if (value.isEmpty) return false;
    const prefixes = <String>['chapter', 'section', 'day', 'lesson', 'part'];
    for (final prefix in prefixes) {
      if (value.startsWith(prefix)) return true;
    }

    return RegExp(
          r'^(chapter|section|day|lesson|part)\s+\d+',
        ).hasMatch(value) ||
        RegExp(
          r'^(chapter|section|day|lesson|part)\s+[ivxlcdm]+',
        ).hasMatch(value) ||
        RegExp(r'^\d+[\s\.\)]').hasMatch(value);
  }

  String _normalizeNavigationText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<List<_EpubSectionChunk>> _readBodySections({
    required File file,
    required String libraryItemId,
    _IndexingStats? stats,
    bool includeFrontMatter = false,
    bool preserveHeadingBlocks = false,
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
      final keepFrontMatter =
          includeFrontMatter &&
          (decision.category == 'front_matter' ||
              decision.category == 'editorial');
      if (decision.shouldSkip && !keepFrontMatter) {
        stats?.recordSkippedSection(
          libraryItemId: fileId,
          hrefPath: entryName,
          sectionTitle: title,
          reasonSkipped: decision.reason,
          category: decision.category,
        );
        continue;
      }

      final blocks = _extractBodyBlocks(
        raw: raw,
        chapterPath: entryName,
        sectionTitle: title,
        includeHeadingBlocks: preserveHeadingBlocks,
      );
      final paragraphs = blocks
          .where((block) => block.kind == 'paragraph')
          .map((block) => block.html)
          .toList(growable: false);
      if (blocks.isEmpty) {
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
          blocks: blocks,
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

  String? _extractClassName(String attrs) {
    final match = RegExp(
      r'''class\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    final value = match?.group(1)?.trim();
    return value != null && value.isNotEmpty ? value : null;
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

  bool _looksLikeCoverImagePath(String path) {
    final lower = path.toLowerCase();
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

  bool _isImageExtension(String path) {
    final ext = p.extension(path).toLowerCase();
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

  List<_NavigationEntryDraft> _extractNavigationEntriesFromDocument({
    required String raw,
    required String basePath,
    required String libraryItemId,
    required String navType,
    required String deviceId,
    required String createdAt,
    required String updatedAt,
  }) {
    final entries = <_NavigationEntryDraft>[];
    var sortOrder = 0;
    final navigationSource = navType.toLowerCase() == 'toc'
        ? _extractTocDocument(raw)
        : raw;
    final anchorPattern = RegExp(
      r'<a\b[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in anchorPattern.allMatches(navigationSource)) {
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
          depth: _estimateNavDepth(navigationSource, match.start),
          navType: navType,
          contentKind: _navigationContentKind(
            label: label,
            href: resolvedPath,
            navType: navType,
          ),
          createdAt: createdAt,
          updatedAt: updatedAt,
          deviceId: deviceId,
        ),
      );
      sortOrder += 1;
    }
    return entries;
  }

  List<LibraryBookBlock> _extractBodyBlocks({
    required String raw,
    required String chapterPath,
    required String sectionTitle,
    required bool includeHeadingBlocks,
  }) {
    final bodyMatch = RegExp(
      r'<body\b[^>]*>(.*?)</body>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(raw);
    final source = bodyMatch?.group(1) ?? raw;
    final blocks = <LibraryBookBlock>[];
    final stack = <_HtmlBlockFrame>[];
    final blockPattern = RegExp(
      r'<(/?)(h[1-6]|p|div|blockquote)\b([^>]*)>',
      caseSensitive: false,
      dotAll: true,
    );
    var bodyOrder = 0;

    for (final match in blockPattern.allMatches(source)) {
      final isClosing = (match.group(1) ?? '').isNotEmpty;
      final tag = (match.group(2) ?? '').toLowerCase();
      final attrs = match.group(3) ?? '';
      final token = match.group(0) ?? '';

      if (!isClosing) {
        if (token.endsWith('/>')) {
          continue;
        }
        stack.add(
          _HtmlBlockFrame(
            tag: tag,
            attrs: attrs,
            start: match.start,
            contentStart: match.end,
          ),
        );
        continue;
      }

      final openIndex = stack.lastIndexWhere((frame) => frame.tag == tag);
      if (openIndex < 0) continue;
      final frame = stack.removeAt(openIndex);
      final innerHtml = source.substring(frame.contentStart, match.start);
      final text = _stripHtml(innerHtml);
      if (text.isEmpty) continue;
      if (_isHiddenLikeBlock(attrs: frame.attrs, innerHtml: innerHtml)) {
        continue;
      }
      final hasBlockquoteAncestor = stack
          .take(openIndex)
          .any((ancestor) => ancestor.tag == 'blockquote');
      if (hasBlockquoteAncestor && tag != 'blockquote') {
        continue;
      }

      final headingLevel = tag.startsWith('h')
          ? int.tryParse(tag.substring(1))
          : null;
      final explicitAnchorId = _extractAnchorIdFromHtml(
        attrs: frame.attrs,
        innerHtml: innerHtml,
      );
      final headingLike =
          headingLevel != null ||
          _looksLikeHeadingLikeBlock(
            tag: tag,
            attrs: frame.attrs,
            innerHtml: innerHtml,
            text: text,
          );
      final hasNestedBlockTags = RegExp(
        r'<(/?)(h[1-6]|p|div)\b',
        caseSensitive: false,
      ).hasMatch(innerHtml);

      if (tag == 'div' && hasNestedBlockTags) {
        continue;
      }

      if (headingLike) {
        if (!includeHeadingBlocks) continue;
        bodyOrder += 1;
        blocks.add(
          LibraryBookBlock(
            html: source.substring(frame.start, match.end),
            text: text,
            kind: 'heading',
            sourceTag: tag,
            className: _extractClassName(frame.attrs),
            headingLevel: headingLevel ?? _headingLevelForHeadingLike(attrs),
            anchorId: explicitAnchorId?.trim().isNotEmpty == true
                ? explicitAnchorId!.trim()
                : _generatedHeadingAnchor(
                    chapterPath: chapterPath,
                    headingIndex: bodyOrder,
                    headingText: text,
                    explicitAnchorId: explicitAnchorId,
                  ),
            bodyOrder: bodyOrder,
          ),
        );
        continue;
      }

      bodyOrder += 1;
      blocks.add(
        LibraryBookBlock(
          html: source.substring(frame.start, match.end),
          text: text,
          kind: tag == 'blockquote' ? 'blockquote' : 'paragraph',
          sourceTag: tag,
          className: _extractClassName(frame.attrs),
          anchorId: explicitAnchorId?.trim().isNotEmpty == true
              ? explicitAnchorId!.trim()
              : null,
          bodyOrder: bodyOrder,
        ),
      );
    }

    return blocks;
  }

  bool _isHiddenLikeBlock({required String attrs, required String innerHtml}) {
    final normalizedAttrs = attrs.toLowerCase();
    final normalizedInner = innerHtml.toLowerCase();

    if (normalizedAttrs.contains('hidden') ||
        normalizedAttrs.contains('aria-hidden="true"') ||
        normalizedAttrs.contains("aria-hidden='true'") ||
        normalizedAttrs.contains('display:none') ||
        normalizedAttrs.contains('display: none') ||
        normalizedAttrs.contains('visibility:hidden') ||
        normalizedAttrs.contains('visibility: hidden')) {
      return true;
    }

    final classMatch = RegExp(
      r'''class\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    if (classMatch != null) {
      final classValue = classMatch.group(1)!.toLowerCase();
      final classTokens = classValue.split(RegExp(r'[\s_-]+'));
      if (classTokens.contains('nav') ||
          classTokens.contains('toc') ||
          classTokens.contains('metadata') ||
          classTokens.contains('meta') ||
          classTokens.contains('alternate') ||
          classTokens.contains('hidden') ||
          classTokens.contains('sr') ||
          classTokens.contains('only') ||
          classValue.contains('visually-hidden')) {
        return true;
      }
    }

    if (RegExp(
      r'<(nav|script|style|meta|link)\b',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(normalizedInner)) {
      return true;
    }

    return false;
  }

  String _extractTocDocument(String raw) {
    final tocNavPattern = RegExp(
      r'''<nav\b[^>]*(?:epub:type|type)\s*=\s*["']toc["'][^>]*>.*?</nav>''',
      caseSensitive: false,
      dotAll: true,
    );
    final tocMatch = tocNavPattern.firstMatch(raw);
    if (tocMatch != null) {
      return tocMatch.group(0) ?? raw;
    }

    final navPattern = RegExp(
      r'<nav\b[^>]*>.*?</nav>',
      caseSensitive: false,
      dotAll: true,
    );
    final navMatch = navPattern.firstMatch(raw);
    return navMatch?.group(0) ?? raw;
  }

  bool _isChapterTitleBlock(String text, {required String sectionTitle}) {
    final normalizedBlock = _normalizeNavigationText(text);
    final normalizedTitle = _normalizeNavigationText(sectionTitle);
    if (normalizedBlock.isEmpty || normalizedTitle.isEmpty) return false;
    return normalizedBlock == normalizedTitle;
  }

  bool _looksLikeHeadingLikeBlock({
    required String tag,
    required String attrs,
    required String innerHtml,
    required String text,
  }) {
    if (tag.startsWith('h')) return true;
    if (tag != 'p' && tag != 'div') return false;

    final normalizedText = _normalizeNavigationText(text);
    if (normalizedText.isEmpty) return false;

    if (RegExp(
      r'''class\s*=\s*["'][^"']*(heading|chapter|section|title|subhead|subtitle|headline|chapterhead|sectionhead|lessonhead|versehead|parthead|booktitle|chapter-title|section-title|sub-title|subheading)[^"']*["']''',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(attrs)) {
      return true;
    }

    if (RegExp(
      r'''style\s*=\s*["'][^"']*(font-weight\s*:\s*(bold|700|800)|text-align\s*:\s*center)[^"']*["']''',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(attrs)) {
      return true;
    }

    if (RegExp(
          r'<(strong|b)\b',
          caseSensitive: false,
          dotAll: true,
        ).hasMatch(innerHtml) &&
        normalizedText.split(RegExp(r'\s+')).length <= 16 &&
        normalizedText.length <= 140) {
      return true;
    }

    final lowerAttrs = attrs.toLowerCase();
    if ((lowerAttrs.contains('font-weight:bold') ||
            lowerAttrs.contains('font-weight: bold') ||
            lowerAttrs.contains('font-weight:700') ||
            lowerAttrs.contains('font-weight: 700')) &&
        normalizedText.split(RegExp(r'\s+')).length <= 16 &&
        normalizedText.length <= 140) {
      return true;
    }

    return false;
  }

  int? _headingLevelForHeadingLike(String attrs) {
    final inferred = RegExp(
      r'level\s*[:=]\s*([1-6])',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(attrs);
    final level = inferred?.group(1);
    if (level == null) return 4;
    return int.tryParse(level);
  }

  String? _extractAnchorIdFromHtml({
    required String attrs,
    required String innerHtml,
  }) {
    final explicit =
        _attributeValue(attrs, 'id') ?? _attributeValue(attrs, 'name');
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final nestedAnchorMatch = RegExp(
      r'''<a\b[^>]*(?:id|name)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(innerHtml);
    final nestedAnchor = nestedAnchorMatch?.group(1)?.trim();
    if (nestedAnchor != null && nestedAnchor.isNotEmpty) {
      return nestedAnchor;
    }

    final nestedSpanMatch = RegExp(
      r'''<(?:span|div)\b[^>]*(?:id|name)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(innerHtml);
    return nestedSpanMatch?.group(1)?.trim();
  }

  String _generatedHeadingAnchor({
    required String chapterPath,
    required int headingIndex,
    required String headingText,
    String? explicitAnchorId,
  }) {
    final preservedAnchor = explicitAnchorId?.trim();
    if (preservedAnchor != null && preservedAnchor.isNotEmpty) {
      return preservedAnchor;
    }

    final chapterSlug = _slug(p.basenameWithoutExtension(chapterPath));
    final headingSlug = _slug(headingText);
    if (headingSlug.isEmpty) {
      return '${chapterSlug}_heading_$headingIndex';
    }
    return '${chapterSlug}_heading_${headingIndex}_$headingSlug';
  }

  String _navigationEntryKey(String label, String? href, String? anchorId) {
    return [
      _normalizeNavigationText(label),
      _navigationHrefKey(href),
      _normalizeNavigationText(anchorId ?? ''),
    ].join('|');
  }

  String _navigationHrefKey(String? href) {
    final trimmed = href?.trim() ?? '';
    if (trimmed.isEmpty) return '';
    final base = trimmed.split('#').first;
    return p.normalize(base).toLowerCase();
  }

  int _compareNavigationDrafts(
    _NavigationEntryDraft a,
    _NavigationEntryDraft b,
  ) {
    final leftSort = a.sortOrder ?? 1 << 30;
    final rightSort = b.sortOrder ?? 1 << 30;
    final sortCompare = leftSort.compareTo(rightSort);
    if (sortCompare != 0) return sortCompare;

    final leftDepth = a.depth ?? 0;
    final rightDepth = b.depth ?? 0;
    final depthCompare = leftDepth.compareTo(rightDepth);
    if (depthCompare != 0) return depthCompare;

    final parentCompare = (a.parentId ?? '').compareTo(b.parentId ?? '');
    if (parentCompare != 0) return parentCompare;

    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
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
