part of 'commentary_research_library_service.dart';

const bool _elibraryRefIndexDiagnosticsEnabled = false;

mixin _CommentaryResearchLibraryServiceElibraryRefIndexSupport {
  Future<void> ensureManagedEgwReferenceIndex({
    required Database db,
    required String rootPath,
    required String libraryItemId,
    required String relativePath,
    required String bookTitle,
    required String bookAbbrev,
    required String workKey,
    required String editionKey,
    required int? editionYear,
    bool refresh = false,
  }) async {
    final normalizedAbbrev = bookAbbrev.trim().toUpperCase();
    if (normalizedAbbrev != 'GC' && normalizedAbbrev != 'GC88') {
      return;
    }

    final normalizedRelativePath = p.normalize(relativePath.trim());
    if (!normalizedRelativePath.toLowerCase().contains('egw_books')) {
      return;
    }

    final existing = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM elibrary_ref_index
      WHERE library_item_id = ?
      ''',
      [libraryItemId],
    );
    final existingCount = (existing.first['count'] as num?)?.toInt() ?? 0;
    if (!refresh && existingCount > 0) {
      return;
    }

    final file = File(p.join(rootPath, normalizedRelativePath));
    if (!await file.exists()) {
      if (_elibraryRefIndexDiagnosticsEnabled) {
        debugPrint(
          '[ELibraryRefIndex] skipped missing file '
          'itemId=$libraryItemId path=${file.path}',
        );
      }
      return;
    }

    // _readBodySections lives in the EPUB parsing part file, so dynamic keeps
    // this mixin independent of the mixin declaration order.
    final sections = await (this as dynamic)._readBodySections(
      file: file,
      libraryItemId: libraryItemId,
      includeFrontMatter: true,
      preserveHeadingBlocks: true,
    );
    final rows = _generateManagedEgwReferenceIndexRows(
      libraryItemId: libraryItemId,
      bookTitle: bookTitle,
      bookAbbrev: normalizedAbbrev,
      workKey: workKey,
      editionKey: editionKey,
      editionYear: editionYear,
      sections: sections,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.delete(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [libraryItemId],
      );
      for (final row in rows) {
        await txn.insert(
          'elibrary_ref_index',
          {
            ...row,
            'created_at': now,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    if (_elibraryRefIndexDiagnosticsEnabled && normalizedAbbrev == 'GC') {
      final firstRef = rows.isEmpty ? '(none)' : rows.first['ref_code'];
      final lastRef = rows.isEmpty ? '(none)' : rows.last['ref_code'];
      final content02Rows = rows
          .where(
            (row) =>
                _sectionKey(row['href']?.toString() ?? '') ==
                _sectionKey('OEBPS/content02.xhtml'),
          )
          .toList(growable: false);
      debugPrint(
        '[ELibraryRefIndex] built '
        'itemTitle=$bookTitle '
        'itemId=$libraryItemId '
        'bookAbbrev=$normalizedAbbrev '
        'rows=${rows.length} '
        'firstRef=$firstRef '
        'lastRef=$lastRef '
        'content02Rows=${content02Rows.length}',
      );
      for (var i = 0; i < rows.length && i < 5; i++) {
        final row = rows[i];
        debugPrint(
          '[ELibraryRefIndex] sample ${i + 1} '
          'href=${row['href']} '
          'paragraphIndex=${row['paragraph_index']} '
          'ref=${row['ref_code']} '
          'page=${row['page_number']} '
          'paragraphOnPage=${row['paragraph_on_page']} '
          'preview=${_paragraphPreview(row['plain_text']?.toString() ?? '')}',
        );
      }
      for (var i = 0; i < content02Rows.length && i < 5; i++) {
        final row = content02Rows[i];
        debugPrint(
          '[ELibraryRefIndex] content02 sample ${i + 1} '
          'paragraphIndex=${row['paragraph_index']} '
          'ref=${row['ref_code']} '
          'preview=${_paragraphPreview(row['plain_text']?.toString() ?? '')}',
        );
      }
    }
  }

  Future<Map<String, String>> loadManagedEgwReferenceCodesForItem({
    required Database db,
    required String libraryItemId,
  }) async {
    final rowResult = await ELibraryReadResolver.instance.readWithFallback<
      List<Map<String, Object?>>
    >(
      read: (readDb) => readDb.rawQuery(
        '''
      SELECT href, paragraph_index, ref_code
      FROM elibrary_ref_index
      WHERE library_item_id = ?
      ORDER BY href ASC, paragraph_index ASC
      ''',
        [libraryItemId],
      ),
      hasData: (rows) => rows.isNotEmpty,
      fallbackDatabase: Future.value(db),
    );
    final rows = rowResult.value;
    final result = <String, String>{};
    for (final row in rows) {
      final href = row['href']?.toString().trim() ?? '';
      final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
      final refCode = row['ref_code']?.toString().trim() ?? '';
      if (href.isEmpty || paragraphIndex == null || paragraphIndex <= 0) {
        continue;
      }
      if (refCode.isEmpty) continue;
      result[_refCodeLocationKey(
        libraryItemId: libraryItemId,
        href: href,
        paragraphIndex: paragraphIndex,
      )] = refCode;
    }
    return result;
  }

  Future<Map<int, String>> loadManagedEgwReferenceCodesForSection({
    required Database db,
    required String libraryItemId,
    required String href,
  }) async {
    final rowResult = await ELibraryReadResolver.instance.readWithFallback<
      List<Map<String, Object?>>
    >(
      read: (readDb) => readDb.rawQuery(
        '''
      SELECT paragraph_index, ref_code, stable_ref, page_number,
             paragraph_on_page, ref_source, anchor_id, plain_text
      FROM elibrary_ref_index
      WHERE library_item_id = ?
        AND LOWER(REPLACE(REPLACE(COALESCE(href, ''), '\\', '/'), './', '')) = ?
      ORDER BY paragraph_index ASC
      ''',
        [libraryItemId, _sectionKey(href)],
      ),
      hasData: (rows) => rows.isNotEmpty,
      fallbackDatabase: Future.value(db),
    );
    final rows = rowResult.value;

    final result = <int, String>{};
    for (final row in rows) {
      final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
      final refCode = row['ref_code']?.toString().trim() ?? '';
      if (paragraphIndex == null || paragraphIndex <= 0 || refCode.isEmpty) {
        continue;
      }
      result[paragraphIndex] = refCode;

      if (_elibraryRefIndexDiagnosticsEnabled) {
        debugPrint(
          '[LibraryBookReader] ref index row '
          'showRefCodes=true '
          'paragraphIndex=$paragraphIndex '
          'href=${_sectionKey(href)} '
          'anchorId=${row['anchor_id']?.toString() ?? '(none)'} '
          'pageNumber=${row['page_number']?.toString() ?? '(none)'} '
          'paragraphOnPage=${row['paragraph_on_page']?.toString() ?? '(none)'} '
          'stableRef=${row['stable_ref']?.toString() ?? '(none)'} '
          'refSource=${row['ref_source']?.toString() ?? '(none)'} '
          'cleanRefCodeCandidate=$refCode '
          'finalCleanRefCode=$refCode',
        );
      }
    }
    if (_elibraryRefIndexDiagnosticsEnabled) {
      debugPrint(
        '[LibraryBookReader] ref index summary '
        'libraryItemId=$libraryItemId '
        'href=${_sectionKey(href)} '
        'resolved=${result.length}',
      );
    }
    return result;
  }

  List<Map<String, Object?>> _generateManagedEgwReferenceIndexRows({
    required String libraryItemId,
    required String bookTitle,
    required String bookAbbrev,
    required String workKey,
    required String editionKey,
    required int? editionYear,
    required List<_EpubSectionChunk> sections,
  }) {
    final rows = <Map<String, Object?>>[];
    int? currentPageNumber;
    var paragraphNumberOnPage = 0;
    var insideParagraphMarkerCount = 0;
    final sampleRows = <String>[];
    final content02Href = _sectionKey('OEBPS/content02.xhtml');

    for (final section in sections) {
      final paragraphBlocks = section.blocks
          .where((block) => block.kind == 'paragraph')
          .toList(growable: false);
      if (paragraphBlocks.isEmpty) {
        continue;
      }

      final firstMarkerInSection = _firstPageBreakMarkerOccurrence(
        paragraphBlocks,
      );
      if (currentPageNumber == null && firstMarkerInSection != null) {
        currentPageNumber = firstMarkerInSection.isInsideParagraph
            ? (firstMarkerInSection.pageNumber > 1
                ? firstMarkerInSection.pageNumber - 1
                : 1)
            : firstMarkerInSection.pageNumber;
      }

      var paragraphIndex = 0;
      for (final block in section.blocks) {
        if (block.kind != 'paragraph') {
          continue;
        }
        paragraphIndex += 1;
        final markers = _extractPageBreakMarkers(block.html);
        if (markers.isEmpty) {
          if (currentPageNumber == null) {
            continue;
          }
        } else {
          final firstMarkerBeforeText = markers.firstWhere(
            (marker) => !marker.isInsideParagraph,
            orElse: () => markers.first,
          );
          if (firstMarkerBeforeText.isInsideParagraph &&
              currentPageNumber == null) {
            currentPageNumber = firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
          } else if (firstMarkerBeforeText.isInsideParagraph) {
            currentPageNumber ??= firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
          } else {
            currentPageNumber = firstMarkerBeforeText.pageNumber;
          }
        }

        paragraphNumberOnPage += 1;
        final href = _sectionKey(section.entryName);
        final plainText = _stripHtmlForRefCode(block.text);
        final refCode = '$bookAbbrev $currentPageNumber.$paragraphNumberOnPage';
        rows.add({
          'library_item_id': libraryItemId,
          'work_key': workKey,
          'edition_key': editionKey,
          'edition_year': editionYear,
          'book_title': bookTitle,
          'book_abbrev': bookAbbrev,
          'href': href,
          'anchor_id': block.anchorId,
          'paragraph_index': paragraphIndex,
          'page_number': currentPageNumber,
          'paragraph_on_page': paragraphNumberOnPage,
          'ref_code': refCode,
          'stable_ref': _refCodeLocationKey(
            libraryItemId: libraryItemId,
            href: href,
            paragraphIndex: paragraphIndex,
          ),
          'plain_text': plainText.isEmpty ? null : plainText,
          'text_hash': plainText.isEmpty
              ? null
              : sha256.convert(utf8.encode(plainText)).toString(),
          'ref_source': 'generated_from_page_marker',
        });

        if (rows.length <= 5 || _sectionKey(section.entryName) == content02Href) {
          sampleRows.add(
            'href=${section.entryName} '
            'paragraphIndex=$paragraphIndex '
            'ref=$refCode '
            'page=$currentPageNumber '
            'paragraphOnPage=$paragraphNumberOnPage '
            'preview=${_paragraphPreview(plainText)}',
          );
        }

        if (markers.isNotEmpty) {
          for (final marker in markers) {
            if (marker.isInsideParagraph) {
              insideParagraphMarkerCount += 1;
            }
          }
          final lastMarker = markers.last;
          currentPageNumber = lastMarker.pageNumber;
          paragraphNumberOnPage = 0;
        }
      }
    }

    if (_elibraryRefIndexDiagnosticsEnabled) {
      debugPrint(
        '[ELibraryRefIndex] generated rows '
        'libraryItemId=$libraryItemId '
        'bookTitle=$bookTitle '
        'bookAbbrev=$bookAbbrev '
        'rows=${rows.length} '
        'pagebreakInsideParagraphCount=$insideParagraphMarkerCount',
      );
      for (var i = 0; i < sampleRows.length && i < 10; i++) {
        debugPrint('[ELibraryRefIndex] sample ${i + 1} ${sampleRows[i]}');
      }
      final content02Rows = rows
          .where(
            (row) =>
                _sectionKey(row['href']?.toString() ?? '') == content02Href,
          )
          .toList(growable: false);
      for (var i = 0; i < content02Rows.length && i < 5; i++) {
        final row = content02Rows[i];
        debugPrint(
          '[ELibraryRefIndex] content02 row ${i + 1} '
          'paragraphIndex=${row['paragraph_index']} '
          'ref=${row['ref_code']} '
          'preview=${_paragraphPreview(row['plain_text']?.toString() ?? '')}',
        );
      }
    }

    return rows;
  }

  _EgwPageBreakMarkerOccurrence? _firstPageBreakMarkerOccurrence(
    List<LibraryBookBlock> blocks,
  ) {
    for (final block in blocks) {
      final markers = _extractPageBreakMarkers(block.html);
      if (markers.isNotEmpty) {
        return markers.first;
      }
    }
    return null;
  }

  List<_EgwGeneratedPageBreakMarkerOccurrence> _extractPageBreakMarkers(
    String html,
  ) {
    final markers = <_EgwGeneratedPageBreakMarkerOccurrence>[];
    final spanPattern = RegExp(
      r'<span\b([^>]*)>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in spanPattern.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final lowerAttrs = attrs.toLowerCase();
      if (!lowerAttrs.contains('pagebreak')) {
        continue;
      }
      final titleMatch = RegExp(
        r'''title\s*=\s*["'](\d{1,4})["']''',
        caseSensitive: false,
      ).firstMatch(attrs);
      if (titleMatch == null) continue;
      final pageNumber = int.tryParse(titleMatch.group(1)!);
      if (pageNumber == null) continue;
      final textBefore = _stripHtmlForRefCode(html.substring(0, match.start));
      final isInsideParagraph = textBefore.trim().isNotEmpty;
      final preview = _pageBreakPreview(match.group(0) ?? '');
      markers.add(
        _EgwGeneratedPageBreakMarkerOccurrence(
          pageNumber: pageNumber,
          isInsideParagraph: isInsideParagraph,
          preview: preview,
        ),
      );
    }
    return markers;
  }

  String _paragraphPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  String _pageBreakPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  String _stripHtmlForRefCode(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _refCodeLocationKey({
    required String libraryItemId,
    required String href,
    required int paragraphIndex,
  }) {
    return '$libraryItemId|$href|$paragraphIndex';
  }

  String _sectionKey(String value) {
    return p.normalize(value).toLowerCase();
  }
}

class _EgwPageBreakMarkerOccurrence {
  const _EgwPageBreakMarkerOccurrence({
    required this.pageNumber,
    required this.isInsideParagraph,
    required this.preview,
  });

  final int pageNumber;
  final bool isInsideParagraph;
  final String preview;
}

class _EgwGeneratedPageBreakMarkerOccurrence extends _EgwPageBreakMarkerOccurrence {
  const _EgwGeneratedPageBreakMarkerOccurrence({
    required super.pageNumber,
    required super.isInsideParagraph,
    required super.preview,
  });
}
