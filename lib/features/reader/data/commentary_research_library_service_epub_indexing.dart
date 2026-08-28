// ignore_for_file: unused_element, unused_element_parameter

part of 'commentary_research_library_service.dart';

mixin _CommentaryResearchLibraryServiceEpubIndexingSupport {
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
    await _normalizeManagedLibraryItemIdentity(
      db: db,
      folderType: folderType,
      relativePath: relativePath,
      canonicalItemId: itemId,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final ext = p.extension(file.path).toLowerCase();
    final isEpub = ext == '.epub';
    final structuralValidation = isEpub
        ? await _validateEpubStructure(file)
        : null;
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
      'index_status': !isEpub
          ? 'metadata_only'
          : (structuralValidation!.isValid ? 'pending' : 'needs_attention'),
      'index_error': isEpub && !structuralValidation!.isValid
          ? structuralValidation.reason
          : null,
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

    if (isEpub && !structuralValidation!.isValid) {
      final reason = structuralValidation.reason ?? 'Invalid EPUB structure.';
      stats.indexingErrors.add('${file.path}: $reason');
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
        warnings: [reason],
      );
    }

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
      final textBlockCount = await _storeLibraryTextBlocks(
        db: db,
        file: file,
        libraryItemId: itemId,
        now: now,
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

      final hasReadableContent = textBlockCount > 0;
      await db.update(
        'library_items',
        {
          'indexed_at': now,
          'index_status': !hasReadableContent
              ? 'needs_attention'
              : (inserted > 0 ? 'indexed' : 'indexed_empty'),
          'index_error': hasReadableContent
              ? null
              : 'No readable text content found after parsing.',
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [itemId],
      );

      final managedEgwAbbreviation = _managedEgwReferenceBookAbbreviation(
        title: title,
        relativePath: relativePath,
        fileName: p.basename(file.path),
      );
      if (managedEgwAbbreviation != null) {
        // This part file is compiled before the ref-index mixin in the service
        // declaration, so dynamic keeps the cross-part call explicit and local.
        await (this as dynamic).ensureManagedEgwReferenceIndex(
          db: db,
          rootPath: rootPath,
          libraryItemId: itemId,
          relativePath: relativePath,
          bookTitle: title,
          bookAbbrev: managedEgwAbbreviation,
          workKey: 'great_controversy',
          editionKey: managedEgwAbbreviation,
          editionYear: managedEgwAbbreviation == 'GC88' ? 1888 : 1911,
          refresh: true,
        );
      }

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
        warnings: hasReadableContent
            ? extracted.warnings
            : [
                ...extracted.warnings,
                'No readable text content found after parsing.',
              ],
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

  /// Validates that [file] is a structurally complete EPUB before any
  /// content is extracted: the ZIP must open, reference an OPF package
  /// document via container.xml, that OPF must declare a non-empty spine,
  /// and at least one spine-referenced content document must actually exist
  /// in the archive. Catches incomplete source-side stubs (valid ZIP, no
  /// package document) so they are never reported as successfully indexed.
  Future<_EpubStructuralValidation> _validateEpubStructure(File file) async {
    Archive archive;
    try {
      final bytes = await file.readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (error) {
      return _EpubStructuralValidation.invalid(
        'Not a valid ZIP/EPUB container: $error',
      );
    }

    final packageInfo = _readEpubPackageInfo(archive);
    if (!packageInfo.containerFound) {
      return const _EpubStructuralValidation.invalid(
        'Missing META-INF/container.xml.',
      );
    }
    if (packageInfo.opfPath == null || packageInfo.opfPath!.trim().isEmpty) {
      return const _EpubStructuralValidation.invalid(
        'container.xml does not reference an OPF package document.',
      );
    }
    if (!packageInfo.opfFound) {
      return _EpubStructuralValidation.invalid(
        'Referenced OPF package document "${packageInfo.opfPath}" is '
        'missing from the archive.',
      );
    }
    if (packageInfo.spineOrderedPaths.isEmpty) {
      return const _EpubStructuralValidation.invalid(
        'OPF package document has no readable spine.',
      );
    }
    final hasSpineContent = packageInfo.spineOrderedPaths.any(
      (spinePath) => packageInfo.findArchiveEntry(archive, spinePath) != null,
    );
    if (!hasSpineContent) {
      return const _EpubStructuralValidation.invalid(
        'None of the spine-referenced content documents exist in the '
        'archive.',
      );
    }
    return const _EpubStructuralValidation.valid();
  }

  String? _managedEgwReferenceBookAbbreviation({
    required String title,
    required String relativePath,
    required String fileName,
  }) {
    final lowerTitle = title.toLowerCase();
    final lowerRelativePath = p.normalize(relativePath).toLowerCase();
    final lowerFileName = p.basename(fileName).toLowerCase();

    if (lowerTitle.contains('great controversy 1888') ||
        lowerRelativePath.endsWith('/en_gc88.epub') ||
        lowerFileName == 'en_gc88.epub') {
      return 'GC88';
    }
    if (lowerTitle.contains('great controversy') ||
        lowerRelativePath.endsWith('/en_gc.epub') ||
        lowerFileName == 'en_gc.epub') {
      return 'GC';
    }
    return null;
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

  Future<int> _storeLibraryTextBlocks({
    required Database db,
    required File file,
    required String libraryItemId,
    required String now,
  }) async {
    final sections = await _readBodySections(
      file: file,
      libraryItemId: libraryItemId,
      stats: null,
    );
    await db.delete(
      'library_text_blocks',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    var globalParagraphIndex = 0;
    for (final section in sections) {
      var paragraphOnSection = 0;
      final sectionTitle = section.sectionTitle.trim().isNotEmpty
          ? section.sectionTitle.trim()
          : null;
      for (final block in section.blocks) {
        final text = block.text.trim();
        if (text.isEmpty) continue;
        globalParagraphIndex += 1;
        paragraphOnSection += 1;
        await db.insert('library_text_blocks', {
          'library_item_id': libraryItemId,
          'epub_href': section.entryName,
          'spine_index': section.spineIndex,
          'paragraph_index': globalParagraphIndex,
          'paragraph_on_section': paragraphOnSection,
          'section_title': sectionTitle,
          'plain_text': text,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
    return globalParagraphIndex;
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

    // Every TOC/navMap entry is eligible to anchor its own file's body
    // content here, regardless of whether it's nested under another entry
    // for display purposes (a nested chapter still owns its own spine page).
    // `putIfAbsent` keeps the first entry seen per href, same as before this
    // comment was added, back when every entry from that source had a null
    // parentId and this check was a no-op.
    final rootsByHref = <String, _NavigationEntryDraft>{};
    for (final entry in entries) {
      if (entry.href == null) continue;
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
      _orderNavigationEntriesHierarchically(entries),
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

  String _itemId(String folderType, String relativePath) =>
      (this as dynamic)._itemId(folderType, relativePath) as String;

  Future<void> _normalizeManagedLibraryItemIdentity({
    required Database db,
    required String folderType,
    required String relativePath,
    required String canonicalItemId,
  }) async {
    if (!isManagedEgwRelativePath(relativePath)) return;

    final rows = await db.query(
      'library_items',
      columns: const ['id'],
      where: 'relative_path = ? AND deleted_at IS NULL',
      whereArgs: [relativePath],
      limit: 10,
    );
    if (rows.isEmpty) return;

    final normalizedFolderType = folderType.trim();
    if (normalizedFolderType.isEmpty) return;

    final canonicalRow = rows.firstWhere(
      (row) => row['id']?.toString().trim() == canonicalItemId,
      orElse: () => rows.first,
    );
    final canonicalRowId = canonicalRow['id']?.toString().trim() ?? '';
    if (canonicalRowId.isNotEmpty && canonicalRowId != canonicalItemId) {
      await migrateManagedLibraryItemId(
        db: db,
        oldId: canonicalRowId,
        newId: canonicalItemId,
      );
    }

    for (final row in rows) {
      final rowId = row['id']?.toString().trim() ?? '';
      if (rowId.isEmpty || rowId == canonicalItemId) continue;
      await migrateManagedLibraryItemId(
        db: db,
        oldId: rowId,
        newId: canonicalItemId,
      );
    }
  }

  Future<String?> _readTitle(File file) =>
      (this as dynamic)._readTitle(file) as Future<String?>;

  _LibraryFileMetadata _inferLibraryFileMetadata({
    required String relativePath,
    required String folderType,
    required File file,
    required bool isEpub,
  }) =>
      (this as dynamic)._inferLibraryFileMetadata(
            relativePath: relativePath,
            folderType: folderType,
            file: file,
            isEpub: isEpub,
          )
          as _LibraryFileMetadata;

  Future<String?> _resolveLibraryAuthor({
    required File file,
    required _LibraryFileMetadata metadata,
    required String relativePath,
  }) =>
      (this as dynamic)._resolveLibraryAuthor(
            file: file,
            metadata: metadata,
            relativePath: relativePath,
          )
          as Future<String?>;

  Future<String?> _cacheEpubCover({
    required File file,
    required String rootPath,
    required String itemId,
  }) =>
      (this as dynamic)._cacheEpubCover(
            file: file,
            rootPath: rootPath,
            itemId: itemId,
          )
          as Future<String?>;

  Future<int> _countLinks(Database db, String itemId, String folderType) =>
      (this as dynamic)._countLinks(db, itemId, folderType) as Future<int>;

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

  String _cleanCommentaryParagraph(
    String text, {
    required String sectionTitle,
    required String bookTitle,
  }) =>
      (this as dynamic)._cleanCommentaryParagraph(
            text,
            sectionTitle: sectionTitle,
            bookTitle: bookTitle,
          )
          as String;

  String _expandParagraphContext(List<String> paragraphs, int startIndex) =>
      (this as dynamic)._expandParagraphContext(paragraphs, startIndex)
          as String;

  String _stripHtml(String text) =>
      (this as dynamic)._stripHtml(text) as String;

  _EpubPackageInfo _readEpubPackageInfo(Archive archive) =>
      (this as dynamic)._readEpubPackageInfo(archive) as _EpubPackageInfo;

  List<_NavigationEntryDraft> _extractNavigationEntriesFromDocument({
    required String raw,
    required String basePath,
    required String libraryItemId,
    required String navType,
    required String deviceId,
    required String createdAt,
    required String updatedAt,
  }) =>
      (this as dynamic)._extractNavigationEntriesFromDocument(
            raw: raw,
            basePath: basePath,
            libraryItemId: libraryItemId,
            navType: navType,
            deviceId: deviceId,
            createdAt: createdAt,
            updatedAt: updatedAt,
          )
          as List<_NavigationEntryDraft>;

  String _navigationEntryKey(String label, String? href, String? anchorId) =>
      (this as dynamic)._navigationEntryKey(label, href, anchorId) as String;

  String _navigationHrefKey(String? href) =>
      (this as dynamic)._navigationHrefKey(href) as String;

  String? _extractSectionTitle(String raw) =>
      (this as dynamic)._extractSectionTitle(raw) as String?;

  List<LibraryBookBlock> _extractBodyBlocks({
    required String raw,
    required String chapterPath,
    required String sectionTitle,
    required bool includeHeadingBlocks,
  }) =>
      (this as dynamic)._extractBodyBlocks(
            raw: raw,
            chapterPath: chapterPath,
            sectionTitle: sectionTitle,
            includeHeadingBlocks: includeHeadingBlocks,
          )
          as List<LibraryBookBlock>;

  bool _isChapterTitleBlock(String text, {required String sectionTitle}) =>
      (this as dynamic)._isChapterTitleBlock(text, sectionTitle: sectionTitle)
          as bool;

  String _generatedHeadingAnchor({
    required String chapterPath,
    required int headingIndex,
    required String headingText,
    String? explicitAnchorId,
  }) =>
      (this as dynamic)._generatedHeadingAnchor(
            chapterPath: chapterPath,
            headingIndex: headingIndex,
            headingText: headingText,
            explicitAnchorId: explicitAnchorId,
          )
          as String;

  String _slug(String input) => (this as dynamic)._slug(input) as String;

  int _compareNavigationDrafts(
    _NavigationEntryDraft a,
    _NavigationEntryDraft b,
  ) => (this as dynamic)._compareNavigationDrafts(a, b) as int;

  /// Renumbers every entry's `sortOrder` via a depth-first walk of the
  /// parent/child tree, replacing whatever draft values each entry was
  /// assigned during extraction.
  ///
  /// Root entries (from a real TOC/navMap) get small sequential sortOrder
  /// values, while a heading found inside one of those root's pages is
  /// assigned `rootSortOrder * 1000 + headingIndex` so it lands after its
  /// root. That scheme only stays collision-free if roots are spaced at
  /// least 1000 apart — with real navMap roots numbered 0, 1, 2, ... those
  /// derived child values land directly on top of neighboring roots'
  /// sortOrder (root 2's first heading becomes sortOrder 1, identical to
  /// root 1), and a flat sort by sortOrder alone then interleaves unrelated
  /// chapters with another chapter's subheadings. Draft sortOrder values are
  /// still reliable *within* one parent's sibling group (they come from a
  /// simple local counter), so re-deriving a single global sequence by
  /// walking the tree — siblings ordered by their draft sortOrder, still
  /// nested under their real parent — sidesteps the collision entirely.
  List<_NavigationEntryDraft> _orderNavigationEntriesHierarchically(
    List<_NavigationEntryDraft> entries,
  ) {
    final childrenByParentId = <String?, List<_NavigationEntryDraft>>{};
    for (final entry in entries) {
      childrenByParentId.putIfAbsent(entry.parentId, () => []).add(entry);
    }
    for (final siblings in childrenByParentId.values) {
      siblings.sort(_compareNavigationDrafts);
    }

    final ordered = <_NavigationEntryDraft>[];
    var nextSortOrder = 0;
    void visit(_NavigationEntryDraft entry) {
      ordered.add(entry.copyWith(sortOrder: nextSortOrder));
      nextSortOrder += 1;
      for (final child in childrenByParentId[entry.id] ?? const []) {
        visit(child);
      }
    }

    for (final root in childrenByParentId[null] ?? const []) {
      visit(root);
    }
    return ordered;
  }
}
