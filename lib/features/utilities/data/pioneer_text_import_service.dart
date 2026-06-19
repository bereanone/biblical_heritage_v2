import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import 'pioneer_source_catalog.dart';

typedef PioneerSourceBytesFetcher = Future<Uint8List> Function(Uri uri);
typedef PioneerImportDocumentParser = Future<PioneerImportDocument> Function(
  PioneerSourceWork work,
  Uint8List bytes,
);

typedef PioneerImportProgressCallback = void Function(
  PioneerImportProgress progress,
);

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
    required this.reason,
    required this.libraryItemId,
    required this.sourceType,
    required this.insertedLibraryItems,
    required this.insertedNavigationItems,
    required this.insertedTextBlocks,
    required this.skippedExisting,
  });

  final PioneerSourceWork work;
  final PioneerImportWorkStatus status;
  final String reason;
  final String libraryItemId;
  final String? sourceType;
  final int insertedLibraryItems;
  final int insertedNavigationItems;
  final int insertedTextBlocks;
  final bool skippedExisting;

  bool get isImported => status == PioneerImportWorkStatus.imported;
  bool get isSkipped => status != PioneerImportWorkStatus.imported;
}

class PioneerImportBatchResult {
  const PioneerImportBatchResult({
    required this.workResults,
  });

  final List<PioneerImportWorkResult> workResults;

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
          PioneerImportWorkResult(
            work: work,
            status: PioneerImportWorkStatus.skippedNotImportable,
            reason: 'Source needed or unsupported source type.',
            libraryItemId: work.stableLibraryItemId,
            sourceType: work.sourceType,
            insertedLibraryItems: 0,
            insertedNavigationItems: 0,
            insertedTextBlocks: 0,
            skippedExisting: false,
          ),
        );
        completed += 1;
        continue;
      }

      if (!work.hasSupportedImportSource) {
        results.add(
          PioneerImportWorkResult(
            work: work,
            status: PioneerImportWorkStatus.skippedUnsupportedSource,
            reason: 'Unsupported Pioneer source type: ${work.sourceType ?? 'unknown'}.',
            libraryItemId: work.stableLibraryItemId,
            sourceType: work.sourceType,
            insertedLibraryItems: 0,
            insertedNavigationItems: 0,
            insertedTextBlocks: 0,
            skippedExisting: false,
          ),
        );
        completed += 1;
        continue;
      }

      final existing = await _existingImportSummary(db, work.stableLibraryItemId);
      if (existing.isComplete) {
        results.add(
          PioneerImportWorkResult(
            work: work,
            status: PioneerImportWorkStatus.skippedExisting,
            reason: 'Already imported in eLibrary.db.',
            libraryItemId: work.stableLibraryItemId,
            sourceType: work.sourceType,
            insertedLibraryItems: 0,
            insertedNavigationItems: 0,
            insertedTextBlocks: 0,
            skippedExisting: true,
          ),
        );
        completed += 1;
        continue;
      }

      try {
        final sourceUrl = work.sourceUrl?.trim();
        if (sourceUrl == null || sourceUrl.isEmpty) {
          results.add(
            PioneerImportWorkResult(
              work: work,
              status: PioneerImportWorkStatus.skippedNotImportable,
              reason: 'No verified source URL is available.',
              libraryItemId: work.stableLibraryItemId,
              sourceType: work.sourceType,
              insertedLibraryItems: 0,
              insertedNavigationItems: 0,
              insertedTextBlocks: 0,
              skippedExisting: false,
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
        final sourceBytes = await _fetchBytes(Uri.parse(sourceUrl));

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'parsing',
            message: '$progressPrefix Parsing ${work.title}',
          ),
        );
        final document = await _parseDocument(work, sourceBytes);
        if (document.sections.isEmpty) {
          throw StateError('No readable sections were found.');
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
          sourceBytes: sourceBytes,
        );
        results.add(result);
      } catch (error, stackTrace) {
        debugPrint(
          '[PioneerImport] Failed to import ${work.title}: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
        results.add(
          PioneerImportWorkResult(
            work: work,
            status: PioneerImportWorkStatus.failed,
            reason: error.toString(),
            libraryItemId: work.stableLibraryItemId,
            sourceType: work.sourceType,
            insertedLibraryItems: 0,
            insertedNavigationItems: 0,
            insertedTextBlocks: 0,
            skippedExisting: false,
          ),
        );
      }

      completed += 1;
    }

    return PioneerImportBatchResult(workResults: results);
  }

  Future<PioneerImportWorkResult> _writeImportedWork({
    required Database db,
    required String deviceId,
    required PioneerSourceWork work,
    required PioneerImportDocument document,
    required Uint8List sourceBytes,
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
      reason: 'Imported into eLibrary.db.',
      libraryItemId: itemId,
      sourceType: work.sourceType,
      insertedLibraryItems: 1,
      insertedNavigationItems: navigationCount,
      insertedTextBlocks: textBlockCount,
      skippedExisting: false,
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

Future<Uint8List> _downloadSourceBytes(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'StudyBible2 Pioneer Import',
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('HTTP ${response.statusCode} while downloading ${uri.toString()}');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    return Uint8List.fromList(bytes);
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
  final archive = ZipDecoder().decodeBytes(bytes, verify: false);
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
    throw StateError('No readable sections were found in the EPUB source.');
  }

  return PioneerImportDocument(title: work.title, sections: sections);
}

Future<PioneerImportDocument> _parseHtmlDocument(
  PioneerSourceWork work,
  Uint8List bytes,
) async {
  final raw = utf8.decode(bytes, allowMalformed: true);
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
      throw StateError('No readable sections were found in the HTML source.');
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

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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
