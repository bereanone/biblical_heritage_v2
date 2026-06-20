import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import 'pioneer_source_catalog.dart';

typedef PioneerSourceBytesFetcher =
    Future<PioneerSourceDownloadResult> Function(Uri uri);
typedef PioneerImportDocumentParser = Future<PioneerImportDocument> Function(
  PioneerSourceWork work,
  Uint8List bytes,
);

typedef PioneerImportProgressCallback = void Function(
  PioneerImportProgress progress,
);

typedef PioneerImportShouldContinue = bool Function();

enum PioneerImportSourceMethod {
  directUrl,
  userVerifiedAutomatedCapture,
  clipboard,
  savedExport;

  String get label => switch (this) {
    PioneerImportSourceMethod.directUrl => 'direct URL',
    PioneerImportSourceMethod.userVerifiedAutomatedCapture =>
      'user-verified automated capture',
    PioneerImportSourceMethod.clipboard => 'clipboard',
    PioneerImportSourceMethod.savedExport => 'saved export',
  };
}

class PioneerCapturedTextSource {
  const PioneerCapturedTextSource({
    required this.work,
    required this.sourceMethod,
    required this.text,
    this.sourceUrl,
    this.sourceLabel,
    this.refCodeHandlingSummary,
  });

  final PioneerSourceWork work;
  final PioneerImportSourceMethod sourceMethod;
  final String text;
  final String? sourceUrl;
  final String? sourceLabel;
  final String? refCodeHandlingSummary;
}

class PioneerImportSection {
  const PioneerImportSection({
    required this.href,
    required this.title,
    required this.paragraphs,
    required this.spineIndex,
  });

  final String href;
  final String title;
  final List<String> paragraphs;
  final int spineIndex;
}

class PioneerImportDocument {
  const PioneerImportDocument({
    required this.title,
    required this.sections,
  });

  final String title;
  final List<PioneerImportSection> sections;
}

class PioneerImportDocumentTooSparseException implements Exception {
  const PioneerImportDocumentTooSparseException({
    required this.sourceType,
    required this.message,
    required this.sectionsFound,
    required this.paragraphCount,
  });

  final String sourceType;
  final String message;
  final int sectionsFound;
  final int paragraphCount;

  @override
  String toString() {
    return 'PioneerImportDocumentTooSparseException: $message '
        '(sourceType=$sourceType, sectionsFound=$sectionsFound, paragraphs=$paragraphCount)';
  }
}

class PioneerSourceDownloadResult {
  const PioneerSourceDownloadResult({
    required this.bytes,
    this.httpStatusCode,
    this.contentType,
    this.resolvedUri,
  });

  final Uint8List bytes;
  final int? httpStatusCode;
  final String? contentType;
  final Uri? resolvedUri;

  int get byteCount => bytes.length;
}

class PioneerSourceDownloadException implements Exception {
  const PioneerSourceDownloadException({
    required this.uri,
    required this.message,
    this.httpStatusCode,
    this.contentType,
    this.byteCount,
    this.responseBodySnippet,
  });

  final Uri uri;
  final String message;
  final int? httpStatusCode;
  final String? contentType;
  final int? byteCount;
  final String? responseBodySnippet;

  @override
  String toString() {
    final details = <String>[
      if (httpStatusCode != null) 'HTTP $httpStatusCode',
      if (contentType != null && contentType!.trim().isNotEmpty)
        'content-type=$contentType',
      if (byteCount != null) 'bytes=$byteCount',
      uri.toString(),
    ];
    return 'PioneerSourceDownloadException: $message (${details.join(', ')})';
  }
}

enum PioneerImportWorkStatus {
  imported,
  skippedExisting,
  skippedNotImportable,
  skippedUnsupportedSource,
  failed,
}

class PioneerImportWorkResult {
  const PioneerImportWorkResult({
    required this.work,
    required this.status,
    required this.stage,
    required this.sourceMethod,
    required this.reason,
    required this.libraryItemId,
    required this.sourceType,
    required this.insertedLibraryItems,
    required this.insertedNavigationItems,
    required this.insertedTextBlocks,
    required this.skippedExisting,
    required this.refCodeHandlingSummary,
    required this.detail,
    required this.exceptionType,
    required this.httpStatusCode,
    required this.contentType,
    required this.downloadedByteCount,
    required this.parsedSectionCount,
    required this.parsedParagraphCount,
    required this.requiresManualVerification,
    required this.manualVerificationHint,
  });

  final PioneerSourceWork work;
  final PioneerImportWorkStatus status;
  final String stage;
  final PioneerImportSourceMethod sourceMethod;
  final String reason;
  final String libraryItemId;
  final String? sourceType;
  final int insertedLibraryItems;
  final int insertedNavigationItems;
  final int insertedTextBlocks;
  final bool skippedExisting;
  final String refCodeHandlingSummary;
  final String? detail;
  final String? exceptionType;
  final int? httpStatusCode;
  final String? contentType;
  final int? downloadedByteCount;
  final int? parsedSectionCount;
  final int? parsedParagraphCount;
  final bool requiresManualVerification;
  final String? manualVerificationHint;

  String get title => work.title;
  String get sourceMethodLabel => sourceMethod.label;
  int get textBlockCount => insertedTextBlocks;
  int get navigationCount => insertedNavigationItems;
  bool get isImported => status == PioneerImportWorkStatus.imported;
  bool get isSkipped => status != PioneerImportWorkStatus.imported;
}

class PioneerImportBatchResult {
  const PioneerImportBatchResult({
    required this.workResults,
    this.wasCancelled = false,
  });

  final List<PioneerImportWorkResult> workResults;
  final bool wasCancelled;

  int get importedCount =>
      workResults.where((result) => result.isImported).length;

  int get skippedCount =>
      workResults.where((result) => result.status == PioneerImportWorkStatus.skippedExisting).length +
      workResults.where((result) => result.status == PioneerImportWorkStatus.skippedNotImportable).length +
      workResults.where((result) => result.status == PioneerImportWorkStatus.skippedUnsupportedSource).length;

  int get failedCount =>
      workResults.where((result) => result.status == PioneerImportWorkStatus.failed).length;
}

class PioneerImportProgress {
  const PioneerImportProgress({
    required this.completedCount,
    required this.totalCount,
    required this.workTitle,
    required this.stage,
    required this.message,
  });

  final int completedCount;
  final int totalCount;
  final String workTitle;
  final String stage;
  final String message;

  double get fraction =>
      totalCount <= 0 ? 0 : completedCount.clamp(0, totalCount) / totalCount;
}

class PioneerTextImportService {
  PioneerTextImportService({
    PioneerSourceBytesFetcher? fetchBytes,
    PioneerImportDocumentParser? parseDocument,
  })  : _fetchBytes = fetchBytes ?? _downloadSourceBytes,
        _parseDocument = parseDocument ?? _parseSourceDocument;

  static final PioneerTextImportService instance = PioneerTextImportService();

  static const String _collectionName = 'Pioneer Authors';
  static const String _folderType = 'research';
  static const String _libraryRole = 'research';
  static const String _virtualRoot = 'ePubs/Research/Pioneer Authors';

  final PioneerSourceBytesFetcher _fetchBytes;
  final PioneerImportDocumentParser _parseDocument;

  Future<PioneerImportBatchResult> importSelectedWorks(
    Iterable<PioneerSourceWork> selectedWorks, {
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    final uniqueWorks = <String, PioneerSourceWork>{};
    for (final work in selectedWorks) {
      if (work.id.trim().isEmpty) continue;
      uniqueWorks[work.id] = work;
    }

    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final results = <PioneerImportWorkResult>[];
    final total = uniqueWorks.length;
    var completed = 0;

    for (final work in uniqueWorks.values) {
      if (shouldContinue != null && !shouldContinue()) {
        return PioneerImportBatchResult(
          workResults: results,
          wasCancelled: true,
        );
      }
      final itemId = work.stableLibraryItemId;
      final progressPrefix = '${completed + 1}/$total';
      onProgress?.call(
        PioneerImportProgress(
          completedCount: completed,
          totalCount: total,
          workTitle: work.title,
          stage: 'checking',
          message: '$progressPrefix Checking ${work.title}',
        ),
      );

      if (!work.hasVerifiedSource ||
          !work.catalogImportable ||
          !work.availability.isImportable) {
        results.add(
          _buildSkippedNotImportableResult(
            work: work,
            libraryItemId: itemId,
            sourceMethod: PioneerImportSourceMethod.directUrl,
          ),
        );
        completed += 1;
        continue;
      }

      if (!work.hasSupportedImportSource) {
        results.add(
          _buildSkippedUnsupportedSourceResult(
            work: work,
            libraryItemId: itemId,
            sourceMethod: PioneerImportSourceMethod.directUrl,
          ),
        );
        completed += 1;
        continue;
      }

      final existing = await _existingImportSummary(db, itemId);
      if (existing.isComplete) {
        results.add(
          _buildSkippedExistingResult(
            work: work,
            libraryItemId: itemId,
            sourceMethod: PioneerImportSourceMethod.directUrl,
            refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
          ),
        );
        completed += 1;
        continue;
      }

      PioneerSourceDownloadResult? downloadResult;
      try {
        final sourceUrl = work.sourceUrl?.trim();
        if (sourceUrl == null || sourceUrl.isEmpty) {
          results.add(
            _buildSkippedNotImportableResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: PioneerImportSourceMethod.directUrl,
              reason: 'No verified source URL is available.',
            ),
          );
          completed += 1;
          continue;
        }

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'downloading',
            message: '$progressPrefix Downloading ${work.title}',
          ),
        );
        downloadResult = await _fetchBytes(Uri.parse(sourceUrl));

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'parsing',
            message: '$progressPrefix Parsing ${work.title}',
          ),
        );
        final document = await _parseDocument(work, downloadResult.bytes);
        if (document.sections.isEmpty) {
          throw PioneerImportDocumentTooSparseException(
            sourceType: work.sourceType ?? 'unknown',
            message: 'No readable sections were found.',
            sectionsFound: 0,
            paragraphCount: 0,
          );
        }

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'writing',
            message: '$progressPrefix Writing ${work.title}',
          ),
        );
        final result = await _writeImportedWork(
          db: db,
          deviceId: deviceId,
          work: work,
          document: document,
          sourceBytes: downloadResult.bytes,
          downloadResult: downloadResult,
          sourceMethod: PioneerImportSourceMethod.directUrl,
          refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
        );
        results.add(result);
      } catch (error, stackTrace) {
        final stage = _failureStageFor(error);
        debugPrint(
          '[PioneerImport] Failed to import ${work.title} at $stage: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        results.add(
          _buildFailedResult(
            work: work,
            libraryItemId: itemId,
            error: error,
            stage: stage,
            sourceMethod: PioneerImportSourceMethod.directUrl,
            downloadResult: downloadResult,
            downloadedByteCount: downloadResult?.byteCount ??
                (error is PioneerSourceDownloadException ? error.byteCount : null),
            httpStatusCode: downloadResult?.httpStatusCode ??
                (error is PioneerSourceDownloadException ? error.httpStatusCode : null),
            contentType: downloadResult?.contentType ??
                (error is PioneerSourceDownloadException ? error.contentType : null),
            parsedSectionCount: error is PioneerImportDocumentTooSparseException
                ? error.sectionsFound
                : null,
            parsedParagraphCount:
                error is PioneerImportDocumentTooSparseException
                    ? error.paragraphCount
                    : null,
            refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
          ),
        );
      }

      completed += 1;
    }

    return PioneerImportBatchResult(workResults: results);
  }

  Future<PioneerImportBatchResult> importFromCapturedText(
    Iterable<PioneerCapturedTextSource> capturedSources, {
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    final uniqueSources = <String, PioneerCapturedTextSource>{};
    for (final source in capturedSources) {
      if (source.work.id.trim().isEmpty) continue;
      uniqueSources[source.work.id] = source;
    }

    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final results = <PioneerImportWorkResult>[];
    final total = uniqueSources.length;
    var completed = 0;

    for (final source in uniqueSources.values) {
      if (shouldContinue != null && !shouldContinue()) {
        return PioneerImportBatchResult(
          workResults: results,
          wasCancelled: true,
        );
      }

      final work = source.work;
      final itemId = work.stableLibraryItemId;
      final progressPrefix = '${completed + 1}/$total';
      onProgress?.call(
        PioneerImportProgress(
          completedCount: completed,
          totalCount: total,
          workTitle: work.title,
          stage: 'checking',
          message: '$progressPrefix Checking ${work.title}',
        ),
      );

      final existing = await _existingImportSummary(db, itemId);
      if (existing.isComplete) {
        results.add(
          _buildSkippedExistingResult(
            work: work,
            libraryItemId: itemId,
            sourceMethod: source.sourceMethod,
            refCodeHandlingSummary:
                source.refCodeHandlingSummary ?? _defaultRefCodeHandlingSummary,
          ),
        );
        completed += 1;
        continue;
      }

      try {
        final text = source.text.trim();
        if (text.isEmpty) {
          results.add(
            _buildSkippedNotImportableResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: source.sourceMethod,
              reason: 'No captured text was supplied.',
            ),
          );
          completed += 1;
          continue;
        }

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'parsing',
            message: '$progressPrefix Parsing ${work.title}',
          ),
        );
        final document = await _parseCapturedTextDocument(
          work,
          text,
          sourceLabel: source.sourceLabel,
        );
        final downloadResult = PioneerSourceDownloadResult(
          bytes: Uint8List.fromList(utf8.encode(text)),
          httpStatusCode: null,
          contentType: _looksLikeHtmlMarkup(text)
              ? 'text/html'
              : 'text/plain',
          resolvedUri: source.sourceUrl == null
              ? null
              : Uri.tryParse(source.sourceUrl!),
        );

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'writing',
            message: '$progressPrefix Writing ${work.title}',
          ),
        );
        final result = await _writeImportedWork(
          db: db,
          deviceId: deviceId,
          work: work,
          document: document,
          sourceBytes: downloadResult.bytes,
          downloadResult: downloadResult,
          sourceMethod: source.sourceMethod,
          refCodeHandlingSummary:
              source.refCodeHandlingSummary ?? _refCodeHandlingSummary(text),
        );
        results.add(result);
      } catch (error, stackTrace) {
        final stage = _failureStageFor(error);
        debugPrint(
          '[PioneerImport] Failed to import ${work.title} at $stage: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        results.add(
          _buildFailedResult(
            work: work,
            libraryItemId: itemId,
            error: error,
            stage: stage,
            sourceMethod: source.sourceMethod,
            refCodeHandlingSummary:
                source.refCodeHandlingSummary ?? _defaultRefCodeHandlingSummary,
            downloadedByteCount: error is PioneerSourceDownloadException
                ? error.byteCount
                : null,
            httpStatusCode: error is PioneerSourceDownloadException
                ? error.httpStatusCode
                : null,
            contentType: error is PioneerSourceDownloadException
                ? error.contentType
                : null,
            parsedSectionCount: error is PioneerImportDocumentTooSparseException
                ? error.sectionsFound
                : null,
            parsedParagraphCount:
                error is PioneerImportDocumentTooSparseException
                    ? error.paragraphCount
                    : null,
          ),
        );
      }

      completed += 1;
    }

    return PioneerImportBatchResult(workResults: results);
  }

  Future<PioneerImportBatchResult> importFromClipboard({
    required PioneerSourceWork work,
    String? sourceUrl,
    String? sourceLabel,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboard?.text?.trim() ?? '';
    if (clipboardText.isEmpty) {
      return PioneerImportBatchResult(
        workResults: [
          _buildSkippedNotImportableResult(
            work: work,
            libraryItemId: work.stableLibraryItemId,
            sourceMethod: PioneerImportSourceMethod.clipboard,
            reason: 'Clipboard is empty.',
          ),
        ],
      );
    }

    return importFromCapturedText(
      [
        PioneerCapturedTextSource(
          work: work,
          sourceMethod: PioneerImportSourceMethod.clipboard,
          text: clipboardText,
          sourceUrl: sourceUrl,
          sourceLabel: sourceLabel,
          refCodeHandlingSummary: _refCodeHandlingSummary(clipboardText),
        ),
      ],
      onProgress: onProgress,
      shouldContinue: shouldContinue,
    );
  }

  Future<PioneerImportBatchResult> importFromSavedExport({
    required PioneerSourceWork work,
    required String filePath,
    String? sourceUrl,
    String? sourceLabel,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return PioneerImportBatchResult(
        workResults: [
          _buildSkippedNotImportableResult(
            work: work,
            libraryItemId: work.stableLibraryItemId,
            sourceMethod: PioneerImportSourceMethod.savedExport,
            reason: 'Saved export file not found.',
          ),
        ],
      );
    }

    final text = await file.readAsString(encoding: utf8);
    return importFromCapturedText(
      [
        PioneerCapturedTextSource(
          work: work,
          sourceMethod: PioneerImportSourceMethod.savedExport,
          text: text,
          sourceUrl: sourceUrl,
          sourceLabel: sourceLabel,
          refCodeHandlingSummary: _refCodeHandlingSummary(text),
        ),
      ],
      onProgress: onProgress,
      shouldContinue: shouldContinue,
    );
  }

  Future<PioneerImportWorkResult> _writeImportedWork({
    required Database db,
    required String deviceId,
    required PioneerSourceWork work,
    required PioneerImportDocument document,
    required Uint8List sourceBytes,
    required PioneerSourceDownloadResult downloadResult,
    required PioneerImportSourceMethod sourceMethod,
    required String refCodeHandlingSummary,
  }) async {
    final itemId = work.stableLibraryItemId;
    final now = _utcNow();
    final fileHash = sha256.convert(sourceBytes).toString();
    final relativePath = _buildVirtualRelativePath(work);
    final fileName = p.basename(relativePath);
    final sourceHost = _sourceHostFromUrl(work.sourceUrl);
    final textBlockCount = document.sections.fold<int>(
      0,
      (sum, section) => sum + section.paragraphs.length,
    );
    final navigationCount = document.sections.length;

    await db.transaction((txn) async {
      await txn.delete(
        'library_navigation_items',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      await txn.delete(
        'library_text_blocks',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      await txn.delete(
        'library_links',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      await txn.insert(
        'library_items',
        <String, Object?>{
          'id': itemId,
          'title': work.title,
          'author': work.authorName,
          'file_name': fileName,
          'relative_path': relativePath,
          'file_hash': fileHash,
          'file_size': sourceBytes.length,
          'modified_at': null,
          'mime_type': 'application/epub+zip',
          'file_format': 'epub',
          'folder_type': _folderType,
          'library_role': _libraryRole,
          'collection_name': _collectionName,
          'source_site': sourceHost,
          'source_url': work.sourceUrl,
          'source_type': work.sourceType,
          'cover_path': null,
          'date_added': now,
          'last_opened': null,
          'indexed_at': now,
          'index_status': 'indexed',
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
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (var sectionIndex = 0; sectionIndex < document.sections.length; sectionIndex++) {
        final section = document.sections[sectionIndex];
        final sectionNumber = sectionIndex + 1;
        await txn.insert(
          'library_navigation_items',
          <String, Object?>{
            'id': _navigationItemId(itemId, sectionNumber),
            'library_item_id': itemId,
            'parent_id': null,
            'label': section.title,
            'href': section.href,
            'anchor_id': null,
            'spine_index': section.spineIndex,
            'sort_order': sectionNumber,
            'depth': 0,
            'nav_type': 'toc',
            'content_kind': 'chapter',
            'is_front_matter': 0,
            'is_body_start': sectionNumber == 1 ? 1 : 0,
            'body_order': sectionNumber,
            'created_at': now,
            'updated_at': now,
            'deleted_at': null,
            'device_id': deviceId,
            'revision': 1,
            'sync_status': 'pending',
            'last_synced_at': null,
            'change_id': null,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (var paragraphIndex = 0;
            paragraphIndex < section.paragraphs.length;
            paragraphIndex++) {
          final paragraphText = section.paragraphs[paragraphIndex].trim();
          if (paragraphText.isEmpty) continue;
          final bodyOrder = paragraphIndex + 1;
          await txn.insert(
            'library_text_blocks',
            <String, Object?>{
              'library_item_id': itemId,
              'epub_href': section.href,
              'spine_index': section.spineIndex,
              'paragraph_index': bodyOrder,
              'paragraph_on_section': bodyOrder,
              'section_title': section.title,
              'plain_text': paragraphText,
              'created_at': now,
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    return PioneerImportWorkResult(
      work: work,
      status: PioneerImportWorkStatus.imported,
      stage: 'completed',
      sourceMethod: sourceMethod,
      reason: 'Imported into eLibrary.db.',
      libraryItemId: itemId,
      sourceType: work.sourceType,
      insertedLibraryItems: 1,
      insertedNavigationItems: navigationCount,
      insertedTextBlocks: textBlockCount,
      skippedExisting: false,
      refCodeHandlingSummary: refCodeHandlingSummary,
      detail:
          'Wrote ${document.sections.length} section${document.sections.length == 1 ? '' : 's'} and $textBlockCount text block${textBlockCount == 1 ? '' : 's'}.',
      exceptionType: null,
      httpStatusCode: downloadResult.httpStatusCode,
      contentType: downloadResult.contentType,
      downloadedByteCount: downloadResult.byteCount,
      parsedSectionCount: document.sections.length,
      parsedParagraphCount: textBlockCount,
      requiresManualVerification: false,
      manualVerificationHint: null,
    );
  }

  Future<_ExistingImportSummary> _existingImportSummary(
    Database db,
    String libraryItemId,
  ) async {
    final itemRows = await db.query(
      'library_items',
      columns: const ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [libraryItemId],
      limit: 1,
    );
    if (itemRows.isEmpty) {
      return const _ExistingImportSummary(
        hasItem: false,
        hasNavigationItems: false,
        hasTextBlocks: false,
      );
    }

    final navCount = _firstCount(
      await db.rawQuery(
        '''
        SELECT COUNT(*) AS cnt
        FROM library_navigation_items
        WHERE library_item_id = ? AND deleted_at IS NULL
        ''',
        [libraryItemId],
      ),
    );
    final textCount = _firstCount(
      await db.rawQuery(
        '''
        SELECT COUNT(*) AS cnt
        FROM library_text_blocks
        WHERE library_item_id = ?
        ''',
        [libraryItemId],
      ),
    );

    return _ExistingImportSummary(
      hasItem: true,
      hasNavigationItems: navCount > 0,
      hasTextBlocks: textCount > 0,
    );
  }

  String _buildVirtualRelativePath(PioneerSourceWork work) {
    final authorSegment = _slug(work.authorName);
    final fileStem = work.abbreviation.trim().isNotEmpty
        ? work.abbreviation.trim()
        : _slug(work.title);
    return p.join(
      _virtualRoot,
      authorSegment.isEmpty ? 'unknown_author' : authorSegment,
      '$fileStem.epub',
    );
  }

  String _navigationItemId(String libraryItemId, int sectionNumber) {
    return 'nav_${_slug(libraryItemId)}_$sectionNumber';
  }

  String? _sourceHostFromUrl(String? sourceUrl) {
    final normalized = sourceUrl?.trim() ?? '';
    if (normalized.isEmpty) return null;
    try {
      return Uri.parse(normalized).host;
    } catch (_) {
      return null;
    }
  }

  String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.')
        ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z')
        : iso;
  }
}

int _firstCount(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return 0;
  return (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

String _failureStageFor(Object error) {
  if (error is PioneerSourceDownloadException) {
    return 'downloading';
  }
  if (error is PioneerImportDocumentTooSparseException) {
    return 'parsing';
  }
  return 'writing';
}

PioneerImportWorkResult _buildSkippedNotImportableResult({
  required PioneerSourceWork work,
  required String libraryItemId,
  required PioneerImportSourceMethod sourceMethod,
  String? reason,
}) {
  return PioneerImportWorkResult(
    work: work,
    status: PioneerImportWorkStatus.skippedNotImportable,
    stage: 'blocked',
    sourceMethod: sourceMethod,
    reason: reason ?? 'Source needed or unsupported source type.',
    libraryItemId: libraryItemId,
    sourceType: work.sourceType,
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: false,
    refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
    detail: 'The selected work cannot be imported yet.',
    exceptionType: null,
    httpStatusCode: null,
    contentType: null,
    downloadedByteCount: null,
    parsedSectionCount: null,
    parsedParagraphCount: null,
    requiresManualVerification: false,
    manualVerificationHint: null,
  );
}

PioneerImportWorkResult _buildSkippedUnsupportedSourceResult({
  required PioneerSourceWork work,
  required String libraryItemId,
  required PioneerImportSourceMethod sourceMethod,
}) {
  return PioneerImportWorkResult(
    work: work,
    status: PioneerImportWorkStatus.skippedUnsupportedSource,
    stage: 'blocked',
    sourceMethod: sourceMethod,
    reason: 'Unsupported Pioneer source type: ${work.sourceType ?? 'unknown'}.',
    libraryItemId: libraryItemId,
    sourceType: work.sourceType,
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: false,
    refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
    detail: 'Only EPUB and HTML Pioneer sources can be imported right now.',
    exceptionType: null,
    httpStatusCode: null,
    contentType: null,
    downloadedByteCount: null,
    parsedSectionCount: null,
    parsedParagraphCount: null,
    requiresManualVerification: false,
    manualVerificationHint: null,
  );
}

PioneerImportWorkResult _buildSkippedExistingResult({
  required PioneerSourceWork work,
  required String libraryItemId,
  required PioneerImportSourceMethod sourceMethod,
  required String refCodeHandlingSummary,
}) {
  return PioneerImportWorkResult(
    work: work,
    status: PioneerImportWorkStatus.skippedExisting,
    stage: 'existing',
    sourceMethod: sourceMethod,
    reason: 'Already imported in eLibrary.db.',
    libraryItemId: libraryItemId,
    sourceType: work.sourceType,
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: true,
    refCodeHandlingSummary: refCodeHandlingSummary,
    detail: 'A complete copy already exists in eLibrary.db.',
    exceptionType: null,
    httpStatusCode: null,
    contentType: null,
    downloadedByteCount: null,
    parsedSectionCount: null,
    parsedParagraphCount: null,
    requiresManualVerification: false,
    manualVerificationHint: null,
  );
}

PioneerImportWorkResult _buildFailedResult({
  required PioneerSourceWork work,
  required String libraryItemId,
  required Object error,
  required String stage,
  required PioneerImportSourceMethod sourceMethod,
  required String refCodeHandlingSummary,
  PioneerSourceDownloadResult? downloadResult,
  int? downloadedByteCount,
  int? httpStatusCode,
  String? contentType,
  int? parsedSectionCount,
  int? parsedParagraphCount,
}) {
  String reason;
  if (error is PioneerSourceDownloadException) {
    reason = 'Download failed: ${error.message}'
        '${error.httpStatusCode == null ? '' : ' (HTTP ${error.httpStatusCode})'}';
  } else if (error is PioneerImportDocumentTooSparseException) {
    reason = 'Parse failed: ${error.message}';
  } else {
    reason = '$stage failed: ${error.toString()}';
  }
  final requiresManualVerification = _requiresManualVerification(
    error: error,
    downloadResult: downloadResult,
  );

  return PioneerImportWorkResult(
    work: work,
    status: PioneerImportWorkStatus.failed,
    stage: stage,
    sourceMethod: sourceMethod,
    reason: reason,
    libraryItemId: libraryItemId,
    sourceType: work.sourceType,
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: false,
    refCodeHandlingSummary: refCodeHandlingSummary,
    detail: error.toString(),
    exceptionType: error.runtimeType.toString(),
    httpStatusCode: httpStatusCode ??
        (error is PioneerSourceDownloadException ? error.httpStatusCode : null),
    contentType: contentType ??
        (error is PioneerSourceDownloadException ? error.contentType : null),
    downloadedByteCount: downloadedByteCount ??
        (error is PioneerSourceDownloadException ? error.byteCount : null),
    parsedSectionCount: parsedSectionCount,
    parsedParagraphCount: parsedParagraphCount,
    requiresManualVerification: requiresManualVerification,
    manualVerificationHint: requiresManualVerification
        ? 'This source looks like it needs manual verification or a browser challenge. Open the source URL in a browser, complete any prompt, and retry the import.'
        : null,
  );
}

Future<PioneerSourceDownloadResult> _downloadSourceBytes(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'StudyBible2 Pioneer Import',
    );
    final response = await request.close();
    final contentType = response.headers.contentType?.mimeType;
    if (response.statusCode != HttpStatus.ok) {
      final bytes = await consolidateHttpClientResponseBytes(response);
      throw PioneerSourceDownloadException(
        uri: uri,
        message: 'Unexpected HTTP response while downloading source.',
        httpStatusCode: response.statusCode,
        contentType: contentType,
        byteCount: bytes.length,
        responseBodySnippet: _responseBodySnippet(bytes),
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    return PioneerSourceDownloadResult(
      bytes: Uint8List.fromList(bytes),
      httpStatusCode: response.statusCode,
      contentType: contentType,
      resolvedUri: response.redirects.isNotEmpty
          ? response.redirects.last.location
          : uri,
    );
  } finally {
    client.close(force: true);
  }
}

Future<PioneerImportDocument> _parseSourceDocument(
  PioneerSourceWork work,
  Uint8List bytes,
) async {
  final sourceType = work.sourceType?.trim().toLowerCase() ?? '';
  switch (sourceType) {
    case 'epub':
      return _parseEpubDocument(work, bytes);
    case 'html':
      return _parseHtmlDocument(work, bytes);
    default:
      throw UnsupportedError('Unsupported Pioneer source type: ${work.sourceType}');
  }
}

Future<PioneerImportDocument> _parseEpubDocument(
  PioneerSourceWork work,
  Uint8List bytes,
) async {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    if (_looksLikeManualVerificationText(
      utf8.decode(bytes, allowMalformed: true),
    )) {
      throw const PioneerImportDocumentTooSparseException(
        sourceType: 'epub',
        message:
            'The source appears to require manual verification before readable EPUB content is available.',
        sectionsFound: 0,
        paragraphCount: 0,
      );
    }
    rethrow;
  }
  final packageInfo = _readEpubPackageInfo(archive);
  final sourcePaths = packageInfo.spineOrderedPaths.isNotEmpty
      ? packageInfo.spineOrderedPaths
      : archive.files
          .where((entry) {
            final name = p.normalize(entry.name).toLowerCase();
            return entry.isFile &&
                (name.endsWith('.xhtml') || name.endsWith('.html'));
          })
          .map((entry) => p.normalize(entry.name))
          .toList(growable: false)
        ..sort();

  final sections = <PioneerImportSection>[];
  for (var index = 0; index < sourcePaths.length; index++) {
    final path = sourcePaths[index];
    final entry = archive.findFile(path);
    if (entry == null || !entry.isFile) continue;
    final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
    final title = _cleanSectionTitle(
      _extractHtmlTitle(raw) ?? p.basenameWithoutExtension(path),
      fallback: work.title,
    );
    if (_shouldSkipBoilerplateSection(title, path, raw)) {
      continue;
    }

    final paragraphs = _extractParagraphTexts(raw);
    if (paragraphs.isEmpty) continue;
    sections.add(
      PioneerImportSection(
        href: p.normalize(path),
        title: title,
        paragraphs: paragraphs,
        spineIndex: index + 1,
      ),
    );
  }

  if (sections.isEmpty) {
    throw PioneerImportDocumentTooSparseException(
      sourceType: 'epub',
      message: 'No readable sections were found in the EPUB source.',
      sectionsFound: 0,
      paragraphCount: 0,
    );
  }

  return PioneerImportDocument(title: work.title, sections: sections);
}

Future<PioneerImportDocument> _parseHtmlDocument(
  PioneerSourceWork work,
  Uint8List bytes,
) async {
  final raw = utf8.decode(bytes, allowMalformed: true);
  if (_looksLikeManualVerificationText(raw)) {
    throw const PioneerImportDocumentTooSparseException(
      sourceType: 'html',
      message:
          'The source appears to require manual verification before readable HTML content is available.',
      sectionsFound: 0,
      paragraphCount: 0,
    );
  }
  final body = _extractHtmlBody(raw);
  final sections = <PioneerImportSection>[];
  final blocks = _extractHtmlBlocks(body ?? raw);
  var current = _HtmlSectionDraft(
    href: _virtualHtmlHref(1),
    title: work.title,
  );
  var sectionNumber = 1;

  void flushCurrent() {
    if (current.paragraphs.isEmpty) return;
    final title = _cleanSectionTitle(current.title, fallback: work.title);
    if (_shouldSkipBoilerplateSection(title, current.href, current.paragraphs.join(' '))) {
      current = _HtmlSectionDraft(
        href: _virtualHtmlHref(sectionNumber + 1),
        title: work.title,
      );
      return;
    }
    sections.add(
      PioneerImportSection(
        href: current.href,
        title: title,
        paragraphs: List<String>.unmodifiable(current.paragraphs),
        spineIndex: sectionNumber,
      ),
    );
    sectionNumber += 1;
    current = _HtmlSectionDraft(
      href: _virtualHtmlHref(sectionNumber),
      title: work.title,
    );
  }

  for (final block in blocks) {
    if (block.kind == 'heading') {
      if (current.paragraphs.isNotEmpty) {
        flushCurrent();
      }
      current.title = block.text;
      continue;
    }
    if (block.text.trim().isEmpty) continue;
    current.paragraphs.add(block.text.trim());
  }

  if (current.paragraphs.isNotEmpty) {
    flushCurrent();
  }

  if (sections.isEmpty) {
    final paragraphs = _extractParagraphTexts(body ?? raw);
    if (paragraphs.isEmpty) {
      throw PioneerImportDocumentTooSparseException(
        sourceType: 'html',
        message: 'No readable sections were found in the HTML source.',
        sectionsFound: 0,
        paragraphCount: 0,
      );
    }
    sections.add(
      PioneerImportSection(
        href: _virtualHtmlHref(1),
        title: work.title,
        paragraphs: paragraphs,
        spineIndex: 1,
      ),
    );
  }

  return PioneerImportDocument(title: work.title, sections: sections);
}

String _virtualHtmlHref(int sectionNumber) {
  return p.normalize('OEBPS/content${sectionNumber.toString().padLeft(2, '0')}.xhtml');
}

String _cleanSectionTitle(String value, {required String fallback}) {
  final cleaned = _stripHtml(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

String? _extractHtmlBody(String raw) {
  final match = RegExp(
    r'<body\b[^>]*>(.*?)</body>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(raw);
  return match?.group(1);
}

String? _extractHtmlTitle(String raw) {
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
  final candidate = _stripHtml(headingMatch?.group(1) ?? titleMatch?.group(1) ?? '');
  final cleaned = candidate.replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? null : cleaned;
}

List<String> _extractParagraphTexts(String raw) {
  final blocks = _extractHtmlBlocks(raw);
  return blocks
      .where((block) => block.kind == 'paragraph')
      .map((block) => block.text.trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
}

List<_HtmlBlock> _extractHtmlBlocks(String raw) {
  final source = _stripHtmlWrapperTags(raw);
  final blocks = <_HtmlBlock>[];
  final stack = <_HtmlFrame>[];
  final blockPattern = RegExp(
    r'<(/?)(h[1-6]|p|div|blockquote|li)\b([^>]*)>',
    caseSensitive: false,
    dotAll: true,
  );

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
        _HtmlFrame(
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
    final text = _stripHtml(innerHtml).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    if (_isHiddenHtmlBlock(frame.attrs, innerHtml)) continue;

    if (tag.startsWith('h')) {
      blocks.add(_HtmlBlock(kind: 'heading', text: text));
      continue;
    }

    if (tag == 'div') {
      if (RegExp(r'<(/?)(h[1-6]|p|blockquote|li)\b', caseSensitive: false)
          .hasMatch(innerHtml)) {
        continue;
      }
    }

    blocks.add(_HtmlBlock(kind: 'paragraph', text: text));
  }

  if (blocks.isEmpty) {
    final text = _stripHtml(source).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isNotEmpty) {
      blocks.add(_HtmlBlock(kind: 'paragraph', text: text));
    }
  }

  return blocks;
}

String _stripHtmlWrapperTags(String raw) {
  final body = _extractHtmlBody(raw);
  if (body != null && body.trim().isNotEmpty) {
    return body;
  }
  return raw;
}

bool _isHiddenHtmlBlock(String attrs, String innerHtml) {
  final combined = '${attrs.toLowerCase()} ${innerHtml.toLowerCase()}';
  const needles = <String>[
    'display:none',
    'visibility:hidden',
    'aria-hidden="true"',
    'aria-hidden=\'true\'',
  ];
  for (final needle in needles) {
    if (combined.contains(needle)) return true;
  }
  return false;
}

bool _shouldSkipBoilerplateSection(String title, String href, String raw) {
  final normalizedTitle = _normalizeText(title);
  final normalizedHref = _normalizeText(href);
  final combined = _normalizeText(raw);

  const exactTitles = <String>{
    'table of contents',
    'contents',
    'toc',
    'title page',
    'titlepage',
    'cover',
    'nav',
    'copyright',
  };
  if (exactTitles.contains(normalizedTitle)) return true;
  if (normalizedHref.contains('nav.xhtml') || normalizedHref.contains('toc.xhtml')) {
    return true;
  }
  if (combined.contains('project gutenberg') &&
      combined.contains('start of the project gutenberg')) {
    return true;
  }
  return false;
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
  for (final match in RegExp(r'<item\b[^>]*>', caseSensitive: false).allMatches(opfXml)) {
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
  for (final match in RegExp(r'<itemref\b[^>]*>', caseSensitive: false).allMatches(opfXml)) {
    final tag = match.group(0) ?? '';
    final idref = _attributeValue(tag, 'idref');
    final linear = _attributeValue(tag, 'linear');
    if (idref == null || linear?.toLowerCase() == 'no') continue;
    final item = manifest[idref];
    if (item == null) continue;
    spinePaths.add(item.href);
  }

  final orderedPaths = spinePaths.isNotEmpty
      ? spinePaths
      : manifest.values.map((item) => item.href).toList(growable: false);

  return _EpubPackageInfo(
    spineOrderedPaths: List<String>.unmodifiable(orderedPaths),
  );
}

String? _attributeValue(String tag, String name) {
  final match = RegExp(
    '$name="([^"]+)"',
    caseSensitive: false,
  ).firstMatch(tag);
  return match?.group(1);
}

String? _responseBodySnippet(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) return null;
  return text.length <= 1600 ? text : text.substring(0, 1600);
}

String _stripHtml(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _looksLikeManualVerificationText(String? text) {
  final normalized = _normalizeText(text ?? '');
  if (normalized.isEmpty) return false;
  const markers = <String>[
    'cloudflare',
    'just a moment',
    'manual verification',
    'verify you are human',
    'checking your browser',
    'security check',
    'attention required',
    'captcha',
    'challenge verification',
  ];
  for (final marker in markers) {
    if (normalized.contains(_normalizeText(marker))) {
      return true;
    }
  }
  return false;
}

const String _defaultRefCodeHandlingSummary =
    'Display-only: source ref codes are preserved in the imported text and are not separately indexed yet.';

String _refCodeHandlingSummary(String text) {
  final matches = RegExp(
    r'\b[A-Z0-9]{2,12}\s+\d+(?:[.:]\d+)+\b',
  ).allMatches(text).length;
  if (matches == 0) {
    return 'Display-only: no source ref codes were detected.';
  }
  return 'Display-only: $matches source ref code${matches == 1 ? '' : 's'} preserved in the imported text.';
}

bool _looksLikeHtmlMarkup(String text) {
  final normalized = text.trimLeft().toLowerCase();
  return normalized.startsWith('<!doctype') ||
      normalized.startsWith('<html') ||
      normalized.contains('<body') ||
      normalized.contains('<p') ||
      normalized.contains('<div') ||
      normalized.contains('<section');
}

Future<PioneerImportDocument> _parseCapturedTextDocument(
  PioneerSourceWork work,
  String rawText, {
  String? sourceLabel,
}) async {
  final normalized = rawText.trim();
  if (normalized.isEmpty) {
    throw const PioneerImportDocumentTooSparseException(
      sourceType: 'captured-text',
      message: 'No captured text was supplied.',
      sectionsFound: 0,
      paragraphCount: 0,
    );
  }

  if (_looksLikeManualVerificationText(normalized)) {
    throw const PioneerImportDocumentTooSparseException(
      sourceType: 'captured-text',
      message:
          'The captured text still looks like a human-verification or challenge page.',
      sectionsFound: 0,
      paragraphCount: 0,
    );
  }

  if (_looksLikeHtmlMarkup(normalized)) {
    return _parseHtmlDocument(work, Uint8List.fromList(utf8.encode(rawText)));
  }

  final lines = rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final sections = <PioneerImportSection>[];
  final sectionParagraphs = <String>[];
  var currentTitle = work.title;
  var sectionIndex = 1;
  final paragraphBuffer = <String>[];

  void flushParagraph() {
    final paragraph = normalizeWhitespace(paragraphBuffer.join(' '));
    paragraphBuffer.clear();
    if (paragraph.isNotEmpty) {
      sectionParagraphs.add(paragraph);
    }
  }

  void flushSection() {
    flushParagraph();
    if (sectionParagraphs.isEmpty) {
      return;
    }
    sections.add(
      PioneerImportSection(
        href: p.normalize('captured/section_${sectionIndex.toString().padLeft(2, '0')}.txt'),
        title: currentTitle,
        paragraphs: List<String>.unmodifiable(sectionParagraphs),
        spineIndex: sectionIndex,
      ),
    );
    sectionIndex += 1;
    sectionParagraphs.clear();
  }

  for (final rawLine in lines) {
    final line = normalizeWhitespace(rawLine);
    if (line.isEmpty) {
      flushParagraph();
      continue;
    }

    if (_looksLikeCapturedHeading(line)) {
      if (sectionParagraphs.isNotEmpty || paragraphBuffer.isNotEmpty) {
        flushSection();
      }
      currentTitle = line;
      continue;
    }

    paragraphBuffer.add(line);
    if (_looksLikeParagraphBoundary(rawLine)) {
      flushParagraph();
    }
  }

  flushSection();

  if (sections.isEmpty) {
    final fallbackParagraphs = _splitCapturedParagraphs(rawText);
    if (fallbackParagraphs.isEmpty) {
      throw const PioneerImportDocumentTooSparseException(
        sourceType: 'captured-text',
        message: 'No readable text blocks were found in the captured text.',
        sectionsFound: 0,
        paragraphCount: 0,
      );
    }
    sections.add(
      PioneerImportSection(
        href: p.normalize('captured/section_01.txt'),
        title: sourceLabel?.trim().isNotEmpty == true
            ? sourceLabel!.trim()
            : work.title,
        paragraphs: fallbackParagraphs,
        spineIndex: 1,
      ),
    );
  }

  return PioneerImportDocument(title: work.title, sections: sections);
}

List<String> _splitCapturedParagraphs(String rawText) {
  final paragraphs = <String>[];
  for (final chunk in rawText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n\s*\n'))) {
    final paragraph = normalizeWhitespace(chunk);
    if (paragraph.isNotEmpty) {
      paragraphs.add(paragraph);
    }
  }
  return paragraphs;
}

bool _looksLikeParagraphBoundary(String line) {
  return line.trim().endsWith('.') ||
      line.trim().endsWith('!') ||
      line.trim().endsWith('?') ||
      line.trim().endsWith(':');
}

bool _looksLikeCapturedHeading(String line) {
  final normalized = normalizeWhitespace(line);
  if (normalized.isEmpty || normalized.length > 120) {
    return false;
  }
  final lower = normalized.toLowerCase();
  if (RegExp(r'^(chapter|section|part|book)\b', caseSensitive: false)
      .hasMatch(normalized)) {
    return true;
  }
  if (const {'introduction', 'preface', 'contents', 'appendix', 'index'}
      .contains(lower)) {
    return true;
  }
  if (RegExp(r'^\d+([.)-]|\s)').hasMatch(normalized)) {
    return true;
  }
  final words = normalized.split(RegExp(r'\s+'));
  if (words.length <= 12 && normalized == normalized.toUpperCase()) {
    return true;
  }
  if (words.length <= 8 && normalized.endsWith(':')) {
    return true;
  }
  return false;
}

bool _requiresManualVerification({
  required Object error,
  PioneerSourceDownloadResult? downloadResult,
}) {
  final statusCode = downloadResult?.httpStatusCode ??
      (error is PioneerSourceDownloadException ? error.httpStatusCode : null);
  if (statusCode == HttpStatus.forbidden ||
      statusCode == HttpStatus.unauthorized ||
      statusCode == HttpStatus.tooManyRequests ||
      statusCode == HttpStatus.serviceUnavailable) {
    return true;
  }

  final errorSnippet = error is PioneerSourceDownloadException
      ? error.responseBodySnippet
      : null;
  final message = error is PioneerImportDocumentTooSparseException
      ? error.message
      : error.toString();
  return _looksLikeManualVerificationText(errorSnippet) ||
      _looksLikeManualVerificationText(message);
}

String _slug(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

class _HtmlBlock {
  const _HtmlBlock({required this.kind, required this.text});

  final String kind;
  final String text;
}

class _HtmlSectionDraft {
  _HtmlSectionDraft({
    required this.href,
    required this.title,
  });

  final String href;
  String title;
  final List<String> paragraphs = <String>[];
}

class _HtmlFrame {
  const _HtmlFrame({
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

class _ExistingImportSummary {
  const _ExistingImportSummary({
    required this.hasItem,
    required this.hasNavigationItems,
    required this.hasTextBlocks,
  });

  final bool hasItem;
  final bool hasNavigationItems;
  final bool hasTextBlocks;

  bool get isComplete => hasItem && hasNavigationItems && hasTextBlocks;
}

class _EpubPackageInfo {
  const _EpubPackageInfo({
    this.spineOrderedPaths = const <String>[],
  });

  final List<String> spineOrderedPaths;
}

class _EpubManifestItem {
  const _EpubManifestItem({
    required this.href,
    required this.properties,
  });

  final String href;
  final String properties;
}
