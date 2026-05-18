import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/study_bible_database.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_author_resolver.dart';
import '../../library/data/library_item_identity.dart';
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

  Future<List<LibraryBookSection>> loadBookSections({
    required String filePath,
    required String libraryItemId,
    bool includeFrontMatter = true,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return const [];
    final chunks = await _readBodySections(
      file: file,
      libraryItemId: libraryItemId,
      includeFrontMatter: includeFrontMatter,
      preserveHeadingBlocks: true,
    );
    return chunks
        .map(
          (chunk) => LibraryBookSection(
            entryName: chunk.entryName,
            title: chunk.sectionTitle,
            paragraphs: List<String>.unmodifiable(chunk.paragraphs),
            blocks: List<LibraryBookBlock>.unmodifiable(chunk.blocks),
            spineIndex: chunk.spineIndex,
          ),
        )
        .toList(growable: false);
  }

  Future<CommentaryResearchPassageData> loadPassage({
    required int bookId,
    required int chapter,
    required int verse,
    required String bookName,
    bool refresh = false,
  }) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path;
    final commentaryFolderPath = selection.path == null
        ? null
        : p.join(selection.path!, 'ePubs', 'Commentaries');
    final researchFolderPath = selection.path == null
        ? null
        : p.join(selection.path!, 'ePubs', 'Research');
    final reportPath = selection.path == null
        ? null
        : p.join(selection.path!, 'Index', 'commentary_index_report.json');

    if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
      if (_debugCommentaryResearchLogs) {
        debugPrint(
          '[CommentaryResearch] Root reconnect required for $bookName $chapter:$verse',
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
        commentary: const CommentaryResearchSectionData(
          folderType: 'commentary',
          title: 'Commentary',
          statusMessage:
              'Reconnect the Library Root Folder to load commentary files.',
          files: <CommentaryResearchFileItem>[],
          matches: <CommentaryResearchMatchItem>[],
          discoveredCount: 0,
          indexedCount: 0,
          matchCount: 0,
        ),
        research: const CommentaryResearchSectionData(
          folderType: 'research',
          title: 'Research',
          statusMessage:
              'Reconnect the Library Root Folder to load research files.',
          files: <CommentaryResearchFileItem>[],
          matches: <CommentaryResearchMatchItem>[],
          discoveredCount: 0,
          indexedCount: 0,
          matchCount: 0,
        ),
        indexReportPath: reportPath,
      );
    }

    await LibraryRootService.instance.ensureStructure(rootPath);

    final db = await UserDatabase.instance.database;
    final books = await StudyBibleDatabase.instance.loadBooks();
    final bookLookup = BibleReferenceParser.buildBookLookup(books);
    final bookAliases = BibleReferenceParser.buildBookAliases(books);
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final preferredCommentaryVolume = _volumeForBook(bookId);
    final sections = await Future.wait<_SectionLoadResult>([
      _loadSection(
        db: db,
        rootPath: rootPath,
        folderType: 'commentary',
        folderLabel: 'Commentary',
        preferredVolumeCode: preferredCommentaryVolume,
        candidatePaths: [
          p.join(rootPath, 'ePubs', 'Commentaries'),
          p.join(rootPath, 'PDFs', 'Commentaries'),
        ],
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
        candidatePaths: [
          p.join(rootPath, 'ePubs', 'Research'),
          p.join(rootPath, 'PDFs', 'Research'),
        ],
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
      rootPath: rootPath,
      commentaryFolderPath: commentaryFolderPath,
      researchFolderPath: researchFolderPath,
      commentary: commentary,
      research: research,
      indexReportPath: reportPath,
    );
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
  }) async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path;
    if (rootPath == null || rootPath.trim().isEmpty || !selection.exists) {
      return (indexed: 0, skipped: 0, failed: 0);
    }

    final db = await UserDatabase.instance.database;
    // Include books that are either not yet indexed OR indexed before
    // library_text_blocks was introduced (status = indexed but no text rows).
    final rows = await db.rawQuery('''
      SELECT relative_path, folder_type, title
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) = 'epub'
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
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      final rowTitle = row['title']?.toString().trim();
      onProgress?.call(completed, total, rowTitle?.isNotEmpty == true ? rowTitle : null);

      if (relativePath.isEmpty) {
        skipped += 1;
        completed += 1;
        continue;
      }
      final absolutePath = await LibraryRootService.instance.resolveRelativePath(
        relativePath: relativePath,
        rootPath: rootPath,
      );
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
      } catch (_) {
        failed += 1;
      }
      completed += 1;
    }

    return (indexed: indexed, skipped: skipped, failed: failed);
  }

  Future<List<CommentaryResearchNavigationItem>> loadNavigationItems({
    required String libraryItemId,
  }) async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'library_navigation_items',
      where: 'library_item_id = ? AND deleted_at IS NULL',
      whereArgs: [libraryItemId],
      orderBy: 'sort_order ASC, depth ASC, label COLLATE NOCASE ASC',
    );
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
      return _SectionLoadResult(
        section: CommentaryResearchSectionData(
          folderType: folderType,
          title: folderLabel,
          statusMessage: 'Library index needs refresh.',
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

    final scopedDiscovered =
        folderType == 'commentary' && preferredVolumeCode != null
        ? preferredFormatFiles
              .where(
                (file) =>
                    _inferVolumeCodeFromPath(file.path) == preferredVolumeCode,
              )
              .toList(growable: false)
        : preferredFormatFiles;
    final filesToIndex = preferredVolumeCode != null
        ? scopedDiscovered
        : preferredFormatFiles;

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
      preferredVolumeCode: preferredVolumeCode,
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
      discoveredCount: files.length,
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
  });

  final String html;
  final String text;
  final String kind;
  final String? sourceTag;
  final String? className;
  final int? headingLevel;
  final String? anchorId;
  final int? bodyOrder;

  bool get isHeading => kind == 'heading';
  bool get isBlockquote => kind == 'blockquote';
}
