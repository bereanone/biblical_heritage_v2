import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/database/study_bible_database.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_author_resolver.dart';
import '../../library/data/library_citation_display_helper.dart';
import '../../library/data/library_item_identity.dart';
import '../../library/data/library_section_heuristics.dart';
import '../../utilities/data/elibrary_catalog_duplicate_repair_service.dart';
import 'commentary_research_models.dart';
import 'commentary_research_filters.dart';
import 'commentary_reference_parser.dart';
export 'commentary_research_models.dart';
part 'commentary_research_library_service_epub_indexing.dart';
part 'commentary_research_library_service_epub_parsing.dart';
part 'commentary_research_library_service_elibrary_ref_index.dart';
part 'commentary_research_library_service_epub_storage.dart';

const bool _debugCommentaryResearchLogs = false;

class CommentaryResearchLibraryService
    with
        _CommentaryResearchLibraryServiceEpubIndexingSupport,
        _CommentaryResearchLibraryServiceElibraryRefIndexSupport,
        _CommentaryResearchLibraryServiceEpubStorageSupport,
        _CommentaryResearchLibraryServiceEpubParsingSupport {
  CommentaryResearchLibraryService._();

  static final CommentaryResearchLibraryService instance =
      CommentaryResearchLibraryService._();

  String? preferredCommentaryVolumeCodeForBook(int bookId) {
    return _volumeForBook(bookId);
  }

  Future<List<LibraryBookSection>> loadBookSections({
    required String filePath,
    required String libraryItemId,
    bool includeFrontMatter = true,
  }) async {
    final itemProfile = await _loadLibraryItemProfile(libraryItemId);
    if (itemProfile?.preferStoredTextBlocks == true) {
      return _loadBookSectionsFromTextBlocks(libraryItemId: libraryItemId);
    }

    final file = File(filePath);
    if (await file.exists()) {
      final sections = await loadBookSectionsFromEpubFile(
        file: file,
        libraryItemId: libraryItemId,
        includeFrontMatter: includeFrontMatter,
      );
      if (sections.isNotEmpty) {
        return sections;
      }
    }

    // If the EPUB parser cannot expose body sections, reuse the indexed text
    // blocks so books that already have stored content still open in the reader.
    return _loadBookSectionsFromTextBlocks(libraryItemId: libraryItemId);
  }

  /// Parses an EPUB file directly into sections, bypassing the `library_items`
  /// profile lookup and the stored-text-blocks fallback entirely. Callers that
  /// already know they want the live, heading-aware EPUB parse — e.g. batch
  /// tooling that has no running catalog database connection for the profile
  /// check — can use this directly instead of [loadBookSections].
  Future<List<LibraryBookSection>> loadBookSectionsFromEpubFile({
    required File file,
    required String libraryItemId,
    bool includeFrontMatter = true,
  }) async {
    final chunks = await _readBodySections(
      file: file,
      libraryItemId: libraryItemId,
      includeFrontMatter: includeFrontMatter,
      preserveHeadingBlocks: true,
    );
    return _sectionsFromChunks(chunks);
  }

  Future<_LibraryItemProfile?> _loadLibraryItemProfile(String libraryItemId) {
    final normalizedId = libraryItemId.trim();
    if (normalizedId.isEmpty) {
      return Future.value(null);
    }

    return ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_items',
            columns: const ['source_type'],
            where: 'id = ?',
            whereArgs: [normalizedId],
            limit: 1,
          ),
          hasData: (rows) => rows.isNotEmpty,
          fallbackDatabase: null,
        )
        .then((result) {
          final rows = result.value;
          if (rows.isEmpty) return null;
          final sourceType = rows.first['source_type']?.toString().trim() ?? '';
          if (sourceType.isEmpty) return null;
          return _LibraryItemProfile(sourceType: sourceType.toLowerCase());
        });
  }

  List<LibraryBookSection> _sectionsFromChunks(List<_EpubSectionChunk> chunks) {
    final sectionsWithOrder = chunks
        .asMap()
        .entries
        .map((entry) {
          final chunk = entry.value;
          return (
            order: entry.key,
            section: LibraryBookSection(
              entryName: chunk.entryName,
              title: chunk.sectionTitle,
              paragraphs: List<String>.unmodifiable(chunk.paragraphs),
              blocks: List<LibraryBookBlock>.unmodifiable(chunk.blocks),
              spineIndex: chunk.spineIndex,
            ),
          );
        })
        .toList(growable: false);
    sectionsWithOrder.sort((left, right) {
      final leftSpine = left.section.spineIndex ?? 1 << 30;
      final rightSpine = right.section.spineIndex ?? 1 << 30;
      final spineCompare = leftSpine.compareTo(rightSpine);
      if (spineCompare != 0) return spineCompare;
      return left.order.compareTo(right.order);
    });
    return sectionsWithOrder
        .map((entry) => entry.section)
        .toList(growable: false);
  }

  Future<List<LibraryBookSection>> _loadBookSectionsFromTextBlocks({
    required String libraryItemId,
  }) async {
    final rowResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_text_blocks',
            columns: const [
              'id',
              'epub_href',
              'spine_index',
              'paragraph_index',
              'paragraph_on_section',
              'section_title',
              'plain_text',
            ],
            where: 'library_item_id = ?',
            whereArgs: [libraryItemId],
            orderBy:
                'COALESCE(spine_index, 1073741824), epub_href COLLATE NOCASE ASC, paragraph_index ASC',
          ),
          hasData: (rows) => rows.isNotEmpty,
          fallbackDatabase: null,
        );
    final rows = rowResult.value;

    if (rows.isEmpty) {
      return const [];
    }

    final itemResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_items',
            columns: const ['title', 'file_name', 'relative_path'],
            where: 'id = ?',
            whereArgs: [libraryItemId],
            limit: 1,
          ),
          hasData: (rows) => rows.isNotEmpty,
          fallbackDatabase: null,
        );
    final itemRows = itemResult.value;
    final itemRow = itemRows.isEmpty
        ? const <String, Object?>{}
        : itemRows.first;
    final itemAbbreviation = libraryUserFacingBookAbbreviation(
      title: itemRow['title']?.toString() ?? '',
      fileName: itemRow['file_name']?.toString(),
      relativePath: itemRow['relative_path']?.toString(),
    );
    final generatedReferenceCodes = generateLibraryTextBlockReferenceCodes(
      plainTexts: rows
          .map((row) => row['plain_text']?.toString() ?? '')
          .toList(growable: false),
      itemAbbreviation: itemAbbreviation,
    );
    final refCodesByLocation = await loadManagedEgwReferenceCodesForItem(
      db: rowResult.database,
      libraryItemId: libraryItemId,
    );

    final orderedKeys = <String>[];
    final builders = <String, _LibraryTextBlockSectionBuilder>{};

    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final text = libraryCleanVisibleMarginArtifacts(
        row['plain_text']?.toString().trim() ?? '',
      );
      if (text.isEmpty) continue;

      final href = row['epub_href']?.toString().trim() ?? '';
      final paragraphIndex = (row['paragraph_index'] as num?)?.toInt() ?? 0;
      final fallbackKey = 'row_${row['id']?.toString() ?? orderedKeys.length}';
      final key = href.isNotEmpty
          ? p.normalize(href).toLowerCase()
          : fallbackKey;
      final builder = builders.putIfAbsent(key, () {
        orderedKeys.add(key);
        return _LibraryTextBlockSectionBuilder(
          entryName: href.isNotEmpty ? href : fallbackKey,
          title: row['section_title']?.toString().trim() ?? '',
          spineIndex: (row['spine_index'] as num?)?.toInt(),
        );
      });
      final locationKey = _refCodeLocationKey(
        libraryItemId: libraryItemId,
        href: href,
        paragraphIndex: paragraphIndex,
      );
      final referenceCode =
          refCodesByLocation[locationKey] ?? generatedReferenceCodes[index];
      builder.addRow(row, text, referenceCode: referenceCode);
    }

    final sections = <LibraryBookSection>[];
    for (final key in orderedKeys) {
      final builder = builders[key];
      if (builder == null || builder.paragraphs.isEmpty) continue;
      sections.add(builder.build());
    }
    return sections;
  }

  Future<CommentaryResearchPassageData> loadPassage({
    required int bookId,
    required int chapter,
    required int verse,
    required String bookName,
    bool refresh = false,
  }) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path?.trim() ?? '';
    final rootAvailable = rootPath.isNotEmpty && selection.exists;
    final commentaryFolderPath = selection.path == null
        ? null
        : p.join(selection.path!, 'ePubs', 'EGW');
    final researchFolderPath = selection.path == null
        ? null
        : p.join(selection.path!, 'PDFs', 'EGW');
    final reportPath = selection.path == null
        ? null
        : p.join(selection.path!, 'Index', 'commentary_index_report.json');
    if (rootAvailable) {
      await LibraryRootService.instance.ensureStructure(rootPath);
    }

    final db = await ELibraryDatabase.instance.database;
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = BibleReferenceParser.buildBookLookup(books);
    final bookAliases = BibleReferenceParser.buildBookAliases(books);
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final preferredCommentaryVolume = _volumeForBook(bookId);
    final commentaryCandidatePaths = rootAvailable
        ? [
            p.join(rootPath, 'ePubs', 'EGW'),
            p.join(rootPath, 'PDFs', 'EGW'),
            p.join(rootPath, 'ePubs', 'Commentaries'),
            p.join(rootPath, 'PDFs', 'Commentaries'),
            p.join(rootPath, 'ePubs', 'Research'),
            p.join(rootPath, 'PDFs', 'Research'),
          ]
        : const <String>[];
    final researchCandidatePaths = rootAvailable
        ? [
            p.join(rootPath, 'ePubs', 'EGW'),
            p.join(rootPath, 'PDFs', 'EGW'),
            p.join(rootPath, 'ePubs', 'Commentaries'),
            p.join(rootPath, 'PDFs', 'Commentaries'),
            p.join(rootPath, 'ePubs', 'Research'),
            p.join(rootPath, 'PDFs', 'Research'),
          ]
        : const <String>[];
    final sections = await Future.wait<_SectionLoadResult>([
      _loadSection(
        db: db,
        rootPath: rootPath,
        folderType: 'commentary',
        folderLabel: 'Commentary',
        preferredVolumeCode: preferredCommentaryVolume,
        candidatePaths: commentaryCandidatePaths,
        bookLookup: bookLookup,
        bookAliases: bookAliases,
        refresh: refresh,
        deviceId: deviceId,
        bookName: bookName,
        bookId: bookId,
        chapter: chapter,
        verse: verse,
        chapterWideMatches: true,
      ),
      _loadSection(
        db: db,
        rootPath: rootPath,
        folderType: 'research',
        folderLabel: 'Research',
        preferredVolumeCode: null,
        candidatePaths: researchCandidatePaths,
        bookLookup: bookLookup,
        bookAliases: bookAliases,
        refresh: refresh,
        deviceId: deviceId,
        bookName: bookName,
        bookId: bookId,
        chapter: chapter,
        verse: verse,
        chapterWideMatches: true,
      ),
    ]);
    final commentary = sections.first.section;
    final research = sections.last.section;
    final indexingStats = _IndexingStats.combine(
      sections.map((result) => result.stats),
    );

    final report = <String, Object?>{
      'selected_reference': {
        'book_id': bookId,
        'chapter': chapter,
        'verse': verse,
        'book_name': bookName,
      },
      'root_path': rootPath,
      'commentary_folder_path': commentaryFolderPath,
      'research_folder_path': researchFolderPath,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'files_indexed': indexingStats.filesIndexed,
      'sections_indexed': indexingStats.sectionsIndexed,
      'sections_skipped_front_matter': indexingStats.sectionsSkippedFrontMatter,
      'sections_skipped_navigation': indexingStats.sectionsSkippedNavigation,
      'sections_skipped_metadata': indexingStats.sectionsSkippedMetadata,
      'sections_skipped_editorial': indexingStats.sectionsSkippedEditorial,
      'sections_skipped_other': indexingStats.sectionsSkippedOther,
      'skipped_sections_sample': indexingStats.skippedSectionsSample,
      'indexing_errors': indexingStats.indexingErrors,
      'commentary': _sectionReport(commentary),
      'research': _sectionReport(research),
    };
    await _writeIndexReport(reportPath, report);

    if (_debugCommentaryResearchLogs) {
      debugPrint(
        '[CommentaryResearch] selected=$bookName $chapter:$verse '
        'bookId=$bookId root=$rootPath '
        'commentary=${commentary.discoveredCount}/${commentary.matchCount} '
        'research=${research.discoveredCount}/${research.matchCount} '
        'report=$reportPath',
      );
    }

    return CommentaryResearchPassageData(
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      bookName: bookName,
      rootPath: selection.path,
      commentaryFolderPath: commentaryFolderPath,
      researchFolderPath: researchFolderPath,
      commentary: commentary,
      research: research,
      indexReportPath: reportPath,
    );
  }

  Future<CommentaryResearchSectionData> loadSection({
    required int bookId,
    required int chapter,
    required int verse,
    required String bookName,
    required String folderType,
    required String folderLabel,
    required List<String> candidatePaths,
    required bool chapterWideMatches,
    String? preferredVolumeCode,
    bool refresh = false,
  }) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path?.trim() ?? '';
    final rootAvailable = rootPath.isNotEmpty && selection.exists;

    if (rootAvailable) {
      await LibraryRootService.instance.ensureStructure(rootPath);
    }

    final db = await ELibraryDatabase.instance.database;
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = BibleReferenceParser.buildBookLookup(books);
    final bookAliases = BibleReferenceParser.buildBookAliases(books);
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final effectiveCandidatePaths = rootAvailable
        ? candidatePaths
        : const <String>[];

    final sectionResult = await _loadSection(
      db: db,
      rootPath: rootPath,
      folderType: folderType,
      folderLabel: folderLabel,
      preferredVolumeCode: preferredVolumeCode,
      candidatePaths: effectiveCandidatePaths,
      bookLookup: bookLookup,
      bookAliases: bookAliases,
      refresh: refresh,
      deviceId: deviceId,
      bookName: bookName,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      chapterWideMatches: chapterWideMatches,
    );

    return sectionResult.section;
  }

  /// Indexes all local cataloged EPUBs whose index_status is not yet
  /// 'indexed' or 'indexed_empty'.  Uses the existing _indexFile pipeline
  /// (text-blocks + bible-reference links) with refresh:true so each file
  /// is fully processed on this call.
  ///
  /// Returns (indexed, skipped, failed):
  ///   indexed – files processed without error (may have 0 bible references)
  ///   skipped – catalog rows whose file is missing on disk
  ///   failed  – files that threw during navigation/body parsing
  Future<({int indexed, int skipped, int failed})> indexLocalCatalogedEpubs({
    void Function(int completed, int total, String? currentTitle)? onProgress,
    String? rootPathOverride,
    void Function(String fileName, Object error)? onFailure,
  }) async {
    final stopwatch = Stopwatch()..start();
    final selection = await LibraryRootService.instance.loadSelection();
    final override = rootPathOverride?.trim() ?? '';
    final rootPath = override.isNotEmpty
        ? p.normalize(override)
        : (await LibraryRootService.instance.accessibleLibraryRootPath()) ??
              selection.path;
    if (rootPath == null ||
        rootPath.trim().isEmpty ||
        !Directory(rootPath).existsSync()) {
      return (indexed: 0, skipped: 0, failed: 0);
    }

    final db = await ELibraryDatabase.instance.database;
    // Include books that are either not yet indexed OR indexed before
    // library_text_blocks was introduced (status = indexed but no text rows).
    // Items whose app-managed EPUB was already removed after a validated
    // canonical import (see EpubStoragePolicyService) are intentionally
    // absent from disk and are read exclusively through the canonical
    // reader — this legacy indexer must not try to open them and flag them
    // broken.
    final rows = await db.rawQuery('''
      SELECT relative_path, folder_type, title
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
        AND LOWER(COALESCE(epub_storage_state, 'present')) = 'present'
        AND (
          LOWER(COALESCE(index_status, '')) NOT IN ('indexed', 'indexed_empty')
          OR NOT EXISTS (
            SELECT 1 FROM library_text_blocks
            WHERE library_item_id = library_items.id
          )
        )
    ''');

    if (rows.isEmpty) {
      return (indexed: 0, skipped: 0, failed: 0);
    }

    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = BibleReferenceParser.buildBookLookup(books);
    final bookAliases = BibleReferenceParser.buildBookAliases(books);
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();

    var indexed = 0;
    var skipped = 0;
    var failed = 0;
    var completed = 0;
    final total = rows.length;

    for (final row in rows) {
      // Keep long retained-library recovery passes responsive on Android.
      // EPUB parsing itself is unchanged; this only lets Flutter service UI,
      // cancellation, and lifecycle events between candidates.
      await Future<void>.delayed(Duration.zero);
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      final rowTitle = row['title']?.toString().trim();
      onProgress?.call(
        completed,
        total,
        rowTitle?.isNotEmpty == true ? rowTitle : null,
      );

      if (relativePath.isEmpty) {
        skipped += 1;
        completed += 1;
        continue;
      }
      final absolutePath = await LibraryRootService.instance
          .resolveRelativePath(relativePath: relativePath, rootPath: rootPath);
      final file = File(absolutePath);
      if (!await file.exists()) {
        skipped += 1;
        completed += 1;
        continue;
      }
      final rawFolderType = row['folder_type']?.toString().trim() ?? '';
      final folderType = rawFolderType.isNotEmpty ? rawFolderType : 'research';
      final stats = _IndexingStats();
      try {
        await _indexFile(
          db: db,
          rootPath: rootPath,
          folderType: folderType,
          file: file,
          stats: stats,
          bookLookup: bookLookup,
          bookAliases: bookAliases,
          refresh: true,
          deviceId: deviceId,
        );
        indexed += 1;
      } catch (error) {
        failed += 1;
        onFailure?.call(p.basename(file.path), error);
      }
      completed += 1;
    }

    debugPrint(
      '[CommentaryResearch] indexLocalCatalogedEpubs complete in ${stopwatch.elapsedMilliseconds}ms indexed=$indexed skipped=$skipped failed=$failed root=$rootPath',
    );
    return (indexed: indexed, skipped: skipped, failed: failed);
  }

  Future<List<CommentaryResearchNavigationItem>> loadNavigationItems({
    required String libraryItemId,
  }) async {
    final rowResult = await ELibraryReadResolver.instance
        .readWithFallback<List<Map<String, Object?>>>(
          read: (db) => db.query(
            'library_navigation_items',
            where: 'library_item_id = ? AND deleted_at IS NULL',
            whereArgs: [libraryItemId],
            orderBy: 'sort_order ASC, depth ASC, label COLLATE NOCASE ASC',
          ),
          hasData: (rows) => rows.isNotEmpty,
          fallbackDatabase: null,
        );
    final rows = rowResult.value;
    return rows
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
  }

  Future<CommentaryResearchEpubBookData?> loadEpubBook({
    required String libraryItemId,
    String? initialHref,
    String? initialAnchorId,
  }) async {
    return _loadEpubBookData(
      libraryItemId: libraryItemId,
      initialHref: initialHref,
      initialAnchorId: initialAnchorId,
    );
  }

  Map<String, Object?> _sectionReport(CommentaryResearchSectionData section) {
    return <String, Object?>{
      'folder_type': section.folderType,
      'discovered_count': section.discoveredCount,
      'indexed_count': section.indexedCount,
      'match_count': section.matchCount,
      'status_message': section.statusMessage,
      'files': section.files
          .map(
            (file) => <String, Object?>{
              'id': file.id,
              'title': file.title,
              'file_name': file.fileName,
              'relative_path': file.relativePath,
              'file_size': file.fileSize,
              'indexed': file.indexed,
            },
          )
          .toList(growable: false),
      'matches': section.matches
          .map(
            (match) => <String, Object?>{
              'library_item_id': match.libraryItemId,
              'item_title': match.itemTitle,
              'file_name': match.fileName,
              'relative_path': match.relativePath,
              'original_reference_text': match.originalReferenceText,
              'book_id': match.bookId,
              'chapter': match.chapter,
              'verse_start': match.verseStart,
              'verse_end': match.verseEnd,
              'confidence': match.confidence,
              'anchor': match.anchor,
              'parser_warning': match.parserWarning,
            },
          )
          .toList(growable: false),
    };
  }

  Future<_SectionLoadResult> _loadSection({
    required Database db,
    required String rootPath,
    required String folderType,
    required String folderLabel,
    required String? preferredVolumeCode,
    required List<String> candidatePaths,
    required Map<String, int> bookLookup,
    required List<String> bookAliases,
    required bool refresh,
    required String deviceId,
    required String bookName,
    required int bookId,
    required int chapter,
    required int verse,
    required bool chapterWideMatches,
  }) async {
    final stats = _IndexingStats();
    final rootAvailable =
        rootPath.trim().isNotEmpty && await Directory(rootPath).exists();
    if (!refresh) {
      final cached = await _loadCachedSection(
        db: db,
        folderType: folderType,
        folderLabel: folderLabel,
        rootPath: rootPath,
        preferredVolumeCode: preferredVolumeCode,
        bookLookup: bookLookup,
        bookAliases: bookAliases,
        bookName: bookName,
        bookId: bookId,
        chapter: chapter,
        verse: verse,
      );
      if (cached != null) {
        return _SectionLoadResult(section: cached, stats: stats);
      }
      if (!rootAvailable) {
        return _SectionLoadResult(
          section: CommentaryResearchSectionData(
            folderType: folderType,
            title: folderLabel,
            statusMessage: folderLabel == 'Commentary'
                ? 'Commentary library not found. Open eLibrary Setup.'
                : 'Research library not found. Open eLibrary Setup.',
            files: const <CommentaryResearchFileItem>[],
            matches: const <CommentaryResearchMatchItem>[],
            discoveredCount: 0,
            indexedCount: 0,
            matchCount: 0,
          ),
          stats: stats,
        );
      }
      final discoveredCount = await _countDiscoverableFiles(
        candidatePaths: candidatePaths,
      );
      final candidateFoldersExist = await _allCandidatePathsExist(
        candidatePaths: candidatePaths,
      );
      return _SectionLoadResult(
        section: CommentaryResearchSectionData(
          folderType: folderType,
          title: folderLabel,
          statusMessage: _statusMessage(
            folderLabel: folderLabel,
            bookName: bookName,
            chapter: chapter,
            candidatePaths: candidatePaths,
            discoveredCount: discoveredCount,
            candidateFoldersExist: candidateFoldersExist,
            indexedCount: 0,
            matchCount: 0,
          ),
          files: const <CommentaryResearchFileItem>[],
          matches: const <CommentaryResearchMatchItem>[],
          discoveredCount: discoveredCount,
          indexedCount: 0,
          matchCount: 0,
        ),
        stats: stats,
      );
    }

    if (!rootAvailable) {
      return _SectionLoadResult(
        section: CommentaryResearchSectionData(
          folderType: folderType,
          title: folderLabel,
          statusMessage: folderLabel == 'Commentary'
              ? 'Commentary library not found. Open eLibrary Setup.'
              : 'Research library not found. Open eLibrary Setup.',
          files: const <CommentaryResearchFileItem>[],
          matches: const <CommentaryResearchMatchItem>[],
          discoveredCount: 0,
          indexedCount: 0,
          matchCount: 0,
        ),
        stats: stats,
      );
    }

    final discovered = <File>[];
    final seenPaths = <String>{};
    for (final candidate in candidatePaths) {
      final directory = Directory(candidate);
      if (!await directory.exists()) continue;
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.epub') && !lower.endsWith('.pdf')) continue;
        if (folderType == 'research' &&
            _inferVolumeCodeFromPath(entity.path) != null) {
          continue;
        }
        final normalized = p.normalize(entity.path);
        if (!seenPaths.add(normalized)) continue;
        discovered.add(entity);
      }
    }

    final preferredFormatFiles = _preferEpubs(discovered);
    final indexableFiles = <File>[];
    for (final file in preferredFormatFiles) {
      final relativePath = await LibraryRootService.instance.relativePathFor(
        absolutePath: file.path,
        rootPath: rootPath,
      );
      final skipLegacy = await ELibraryCatalogDuplicateRepairService.instance
          .shouldSkipLegacyCandidate(db: db, relativePath: relativePath);
      if (!skipLegacy) indexableFiles.add(file);
    }

    final scopedDiscovered =
        folderType == 'commentary' && preferredVolumeCode != null
        ? indexableFiles
              .where(
                (file) =>
                    _inferVolumeCodeFromPath(file.path) == preferredVolumeCode,
              )
              .toList(growable: false)
        : indexableFiles;
    final filesToIndex =
        preferredVolumeCode != null && scopedDiscovered.isNotEmpty
        ? scopedDiscovered
        : indexableFiles;
    final effectivePreferredVolumeCode =
        preferredVolumeCode != null && scopedDiscovered.isNotEmpty
        ? preferredVolumeCode
        : null;

    final files = <CommentaryResearchFileItem>[];
    var indexedCount = 0;
    final lookupMatches = <CommentaryResearchMatchItem>[];
    final warnings = <String>[];
    for (final file in filesToIndex) {
      final result = await _indexFile(
        db: db,
        rootPath: rootPath,
        folderType: folderType,
        file: file,
        stats: stats,
        bookLookup: bookLookup,
        bookAliases: bookAliases,
        refresh: refresh,
        deviceId: deviceId,
      );
      files.add(result.fileItem);
      indexedCount += result.indexedLinks;
      lookupMatches.addAll(result.matches);
      warnings.addAll(result.warnings);
    }

    final matches = await _loadMatches(
      db: db,
      folderType: folderType,
      bookId: bookId,
      chapter: chapter,
      verse: verse,
      preferredVolumeCode: effectivePreferredVolumeCode,
      chapterWideMatches: chapterWideMatches,
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
    final dedupedMatches = folderType == 'research'
        ? CommentaryResearchFilters.prepareResearchMatches(
            matches,
            bookId: bookId,
            chapter: chapter,
            verse: verse,
          )
        : CommentaryResearchFilters.dedupeMatches(commentaryMatches);

    final statusMessage = _statusMessage(
      folderLabel: folderLabel,
      bookName: bookName,
      chapter: chapter,
      candidatePaths: candidatePaths,
      discoveredCount: files.length,
      candidateFoldersExist: await _allCandidatePathsExist(
        candidatePaths: candidatePaths,
      ),
      indexedCount: indexedCount,
      matchCount: dedupedMatches.length,
    );

    if (warnings.isNotEmpty) {
      warnings.sort();
    }
    if (lookupMatches.isNotEmpty) {
      // Keep the local report useful even when a file indexed successfully.
      if (_debugCommentaryResearchLogs) {
        debugPrint(
          '[CommentaryResearch] $folderLabel warnings: ${warnings.join(' | ')}',
        );
      }
    }
    if (folderType == 'commentary') {
      if (_debugCommentaryResearchLogs) {
        debugPrint(
          '[CommentaryResearch] commentary raw=${matches.length} '
          'duplicateRejected=${matches.length - commentaryCandidates.length} '
          'filteredRejected=${commentaryCandidates.length - commentaryMatches.length} '
          'final=${dedupedMatches.length} '
          'labels=${dedupedMatches.take(3).map((m) => '${m.verseStart}-${m.verseEnd}').join(' | ')}',
        );
      }
    }

    return _SectionLoadResult(
      section: CommentaryResearchSectionData(
        folderType: folderType,
        title: folderLabel,
        statusMessage: statusMessage,
        files: files,
        matches: dedupedMatches,
        discoveredCount: files.length,
        indexedCount: indexedCount,
        matchCount: dedupedMatches.length,
      ),
      stats: stats,
    );
  }
}

class _LibraryItemProfile {
  const _LibraryItemProfile({required this.sourceType});

  final String sourceType;

  bool get preferStoredTextBlocks =>
      sourceType == 'egw_copied_range' ||
      sourceType == 'egw_browser_capture' ||
      sourceType == 'egw_text_capture' ||
      sourceType == 'pioneer_captured_html' ||
      sourceType == 'pioneer_epub_import';
}

Future<int> _countDiscoverableFiles({
  required List<String> candidatePaths,
}) async {
  var discoveredCount = 0;
  final seenPaths = <String>{};
  for (final candidate in candidatePaths) {
    final directory = Directory(candidate);
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!lower.endsWith('.epub') && !lower.endsWith('.pdf')) continue;
      final normalized = p.normalize(entity.path);
      if (!seenPaths.add(normalized)) continue;
      discoveredCount += 1;
    }
  }
  return discoveredCount;
}

String _statusMessage({
  required String folderLabel,
  required String bookName,
  required int chapter,
  required List<String> candidatePaths,
  required int discoveredCount,
  required bool candidateFoldersExist,
  required int indexedCount,
  required int matchCount,
}) {
  if (discoveredCount == 0) {
    if (candidateFoldersExist) {
      return 'No ${folderLabel.toLowerCase()} files have been imported yet.';
    }
    final searchedPaths = candidatePaths.join(', ');
    return '$folderLabel files not found in $searchedPaths (0 found).';
  }
  if (matchCount > 0) {
    return 'Matching $folderLabel entries found for this passage.';
  }
  if (indexedCount > 0) {
    if (folderLabel == 'Commentary') {
      return 'No commentary found for $bookName $chapter';
    }
    return '$folderLabel files indexed, but no entries for this passage.';
  }
  if (folderLabel == 'Commentary') {
    return 'Commentary files found but not indexed.';
  }
  return '$folderLabel files found but not indexed.';
}

Future<bool> _allCandidatePathsExist({
  required List<String> candidatePaths,
}) async {
  for (final candidate in candidatePaths) {
    final directory = Directory(candidate);
    if (!await directory.exists()) {
      return false;
    }
  }
  return true;
}

class LibraryBookSection {
  const LibraryBookSection({
    required this.entryName,
    required this.title,
    required this.paragraphs,
    required this.blocks,
    required this.spineIndex,
  });

  final String entryName;
  final String title;
  final List<String> paragraphs;
  final List<LibraryBookBlock> blocks;
  final int? spineIndex;
}

class LibraryBookBlock {
  const LibraryBookBlock({
    required this.html,
    required this.text,
    required this.kind,
    this.sourceTag,
    this.className,
    this.headingLevel,
    this.anchorId,
    this.bodyOrder,
    this.referenceCode,
  });

  final String html;
  final String text;
  final String kind;
  final String? sourceTag;
  final String? className;
  final int? headingLevel;
  final String? anchorId;
  final int? bodyOrder;
  final String? referenceCode;

  bool get isHeading => kind == 'heading';
  bool get isBlockquote => kind == 'blockquote';
}

class _LibraryTextBlockSectionBuilder {
  _LibraryTextBlockSectionBuilder({
    required this.entryName,
    required this.title,
    required this.spineIndex,
  });

  final String entryName;
  String title;
  int? spineIndex;
  final List<String> paragraphs = <String>[];
  final List<LibraryBookBlock> blocks = <LibraryBookBlock>[];

  void addRow(Map<String, Object?> row, String text, {String? referenceCode}) {
    final plainText = text.trim();
    if (plainText.isEmpty) return;

    final rowTitle = row['section_title']?.toString().trim() ?? '';
    if (title.trim().isEmpty && rowTitle.isNotEmpty) {
      title = rowTitle;
    }

    final rowSpineIndex = (row['spine_index'] as num?)?.toInt();
    if (spineIndex == null && rowSpineIndex != null) {
      spineIndex = rowSpineIndex;
    }

    final paragraphIndex = (row['paragraph_index'] as num?)?.toInt();
    final paragraphOnSection = (row['paragraph_on_section'] as num?)?.toInt();
    paragraphs.add(plainText);
    blocks.add(
      LibraryBookBlock(
        html: plainText,
        text: plainText,
        kind: 'paragraph',
        bodyOrder: paragraphIndex ?? paragraphOnSection,
        referenceCode: referenceCode,
      ),
    );
  }

  LibraryBookSection build() {
    final displayTitle = title.trim().isNotEmpty
        ? title.trim()
        : p.basenameWithoutExtension(entryName);
    return LibraryBookSection(
      entryName: entryName,
      title: displayTitle,
      paragraphs: List<String>.unmodifiable(paragraphs),
      blocks: List<LibraryBookBlock>.unmodifiable(blocks),
      spineIndex: spineIndex,
    );
  }
}

@visibleForTesting
List<String?> generateLibraryTextBlockReferenceCodes({
  required List<String> plainTexts,
  required String? itemAbbreviation,
}) {
  final abbreviation = itemAbbreviation?.trim();
  if (abbreviation == null || abbreviation.isEmpty || plainTexts.isEmpty) {
    return List<String?>.filled(plainTexts.length, null, growable: false);
  }

  int? bookInitialPageNumber;
  for (final text in plainTexts) {
    final markers = _textBlockPageNumbers(text);
    if (markers.isEmpty) continue;
    final firstMarker = markers.first;
    bookInitialPageNumber = firstMarker > 1 ? firstMarker - 1 : 1;
    break;
  }

  final referenceCodes = List<String?>.filled(
    plainTexts.length,
    null,
    growable: false,
  );
  int? currentPageNumber;
  var paragraphNumberOnPage = 0;

  for (var index = 0; index < plainTexts.length; index++) {
    final markers = _textBlockPageNumbers(plainTexts[index]);
    currentPageNumber ??= markers.isNotEmpty
        ? (markers.first > 1 ? markers.first - 1 : 1)
        : bookInitialPageNumber;

    paragraphNumberOnPage += 1;
    if (currentPageNumber != null) {
      referenceCodes[index] =
          '$abbreviation $currentPageNumber.$paragraphNumberOnPage';
    }

    if (markers.isNotEmpty) {
      currentPageNumber = markers.last;
      paragraphNumberOnPage = 0;
    }
  }

  return referenceCodes;
}

List<int> _textBlockPageNumbers(String text) {
  final markers = <int>[];
  for (final match in RegExp(r'\[(\d{1,4})\]').allMatches(text)) {
    final pageNumber = int.tryParse(match.group(1) ?? '');
    if (pageNumber == null) continue;
    markers.add(pageNumber);
  }
  return markers;
}
