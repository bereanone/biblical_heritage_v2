import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import 'pioneer_capture_folder_metadata.dart';
import 'pioneer_source_catalog.dart';
import 'pioneer_text_import_service.dart';

enum PioneerCapturedHtmlFileStatus {
  ready,
  imported,
  skippedDuplicate,
  needsCleanup,
  failed;

  String get label => switch (this) {
    PioneerCapturedHtmlFileStatus.ready => 'ready',
    PioneerCapturedHtmlFileStatus.imported => 'imported',
    PioneerCapturedHtmlFileStatus.skippedDuplicate => 'skipped duplicate',
    PioneerCapturedHtmlFileStatus.needsCleanup => 'needs cleanup',
    PioneerCapturedHtmlFileStatus.failed => 'failed',
  };
}

@immutable
class PioneerCapturedHtmlFileReport {
  const PioneerCapturedHtmlFileReport({
    required this.filePath,
    required this.relativePath,
    required this.fileHash,
    required this.title,
    required this.author,
    required this.sourceType,
    required this.sourceSite,
    required this.sourceUrl,
    required this.coverImagePath,
    required this.headingCount,
    required this.paragraphCount,
    required this.sectionCount,
    required this.warnings,
    required this.status,
    this.reason,
    this.libraryItemId,
  });

  final String filePath;
  final String relativePath;
  final String fileHash;
  final String title;
  final String author;
  final String sourceType;
  final String? sourceSite;
  final String? sourceUrl;
  final String? coverImagePath;
  final int headingCount;
  final int paragraphCount;
  final int sectionCount;
  final List<String> warnings;
  final PioneerCapturedHtmlFileStatus status;
  final String? reason;
  final String? libraryItemId;

  bool get needsCleanup => status == PioneerCapturedHtmlFileStatus.needsCleanup;
}

@immutable
class PioneerCapturedHtmlFolderImportReport {
  const PioneerCapturedHtmlFolderImportReport({
    required this.folderPath,
    required this.files,
    required this.scannedFileCount,
    required this.htmlFileCount,
    required this.completedAt,
  });

  final String folderPath;
  final List<PioneerCapturedHtmlFileReport> files;
  final int scannedFileCount;
  final int htmlFileCount;
  final DateTime completedAt;

  int get readyCount => files
      .where((file) => file.status == PioneerCapturedHtmlFileStatus.ready)
      .length;

  int get importedCount => files
      .where((file) => file.status == PioneerCapturedHtmlFileStatus.imported)
      .length;

  int get skippedDuplicateCount => files
      .where(
        (file) => file.status == PioneerCapturedHtmlFileStatus.skippedDuplicate,
      )
      .length;

  int get needsCleanupCount => files
      .where(
        (file) => file.status == PioneerCapturedHtmlFileStatus.needsCleanup,
      )
      .length;

  int get failedCount => files
      .where((file) => file.status == PioneerCapturedHtmlFileStatus.failed)
      .length;
}

@immutable
class PioneerCapturedHtmlParseResult {
  const PioneerCapturedHtmlParseResult({
    required this.title,
    required this.author,
    required this.sourceUrl,
    required this.sourceSite,
    required this.coverImagePath,
    required this.document,
    required this.headingCount,
    required this.paragraphCount,
    required this.pageMarkerCount,
    required this.warnings,
  });

  final String title;
  final String author;
  final String? sourceUrl;
  final String? sourceSite;
  final String? coverImagePath;
  final PioneerImportDocument document;
  final int headingCount;
  final int paragraphCount;
  final int pageMarkerCount;
  final List<String> warnings;

  bool get needsCleanup => warnings.isNotEmpty || headingCount == 0;
  bool get isValid => document.sections.isNotEmpty && paragraphCount > 0;
}

class PioneerCapturedHtmlParser {
  const PioneerCapturedHtmlParser();

  PioneerCapturedHtmlParseResult parse({
    required String html,
    required String filePath,
    required String relativePath,
    PioneerCaptureFolderMetadata metadata =
        const PioneerCaptureFolderMetadata(),
  }) {
    final decoded = html;
    final body = _extractHtmlBody(decoded) ?? decoded;
    final metaTitle = _titleFromMetadata(metadata);
    final hasTitleTag = RegExp(
      r'<title\b[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(decoded);
    final headingTexts = _headingTexts(body);
    final title = _titleFromHtml(
      rawHtml: decoded,
      bodyHtml: body,
      metadata: metadata,
      filePath: filePath,
    );
    final author = _authorFromHtml(
      rawHtml: decoded,
      bodyHtml: body,
      metadata: metadata,
    );
    final sourceUrl = metadata.sourceUrl?.trim().isNotEmpty == true
        ? metadata.sourceUrl!.trim()
        : _sourceUrlFromHtml(decoded);
    final metadataSourceSite = metadata.sourceSite?.trim().toLowerCase() ?? '';
    final sourceSite = metadataSourceSite == 'user_capture'
        ? 'user_capture'
        : 'local_cloud_folder';
    final coverImagePath =
        metadata.coverImagePath ?? _coverImageFromHtml(decoded, filePath);
    final blocks = _extractHtmlBlocks(body);
    final sections = _sectionsFromBlocks(
      blocks,
      title: title,
      relativePath: relativePath,
    );
    final paragraphs = sections.fold<int>(
      0,
      (sum, section) => sum + section.paragraphs.length,
    );
    final headingCount = blocks
        .where((block) => block.kind == 'heading')
        .length;
    final pageMarkerCount = RegExp(r'\[(\d{1,4})\]').allMatches(body).length;
    final warnings = <String>[];
    if (metaTitle.isEmpty && !hasTitleTag && headingTexts.isEmpty) {
      warnings.add('Title fell back to the filename.');
    }
    if (author == 'Unknown') {
      warnings.add('Author was not obvious in the HTML metadata or byline.');
    }
    if (headingCount == 0) {
      warnings.add('No h1/h2/h3 headings were found.');
    }
    if (paragraphs == 0) {
      warnings.add('No readable paragraphs were found.');
    }
    if (sections.length == 1 && headingCount == 0) {
      warnings.add('Imported as a single fallback section.');
    }

    return PioneerCapturedHtmlParseResult(
      title: title,
      author: author,
      sourceUrl: sourceUrl,
      sourceSite: sourceSite,
      coverImagePath: coverImagePath,
      document: PioneerImportDocument(title: title, sections: sections),
      headingCount: headingCount,
      paragraphCount: paragraphs,
      pageMarkerCount: pageMarkerCount,
      warnings: List<String>.unmodifiable(warnings),
    );
  }
}

class PioneerCapturedHtmlImportFolderService {
  static final PioneerCapturedHtmlImportFolderService instance =
      PioneerCapturedHtmlImportFolderService();

  PioneerCapturedHtmlImportFolderService({
    PioneerCapturedHtmlParser? parser,
    PioneerTextImportService? importService,
    LocalSettingsStore? settingsStore,
  }) : _parser = parser ?? const PioneerCapturedHtmlParser(),
       _importService = importService ?? PioneerTextImportService.instance,
       _settingsStore = settingsStore ?? LocalSettingsStore.instance;

  final PioneerCapturedHtmlParser _parser;
  final PioneerTextImportService _importService;
  final LocalSettingsStore _settingsStore;

  Future<PioneerCapturedHtmlFolderImportReport> scanConfiguredFolder({
    bool importFiles = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) async {
    final folderPath = await _settingsStore.loadPioneerCapturedHtmlFolderPath();
    if (folderPath == null || folderPath.trim().isEmpty) {
      return PioneerCapturedHtmlFolderImportReport(
        folderPath: '',
        files: const <PioneerCapturedHtmlFileReport>[],
        scannedFileCount: 0,
        htmlFileCount: 0,
        completedAt: DateTime.now().toUtc(),
      );
    }
    return scanFolder(
      folderPath: folderPath,
      importFiles: importFiles,
      existingImportPolicy: existingImportPolicy,
    );
  }

  Future<PioneerCapturedHtmlFolderImportReport> scanFolder({
    required String folderPath,
    bool importFiles = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) async {
    final root = Directory(folderPath);
    if (!await root.exists()) {
      return PioneerCapturedHtmlFolderImportReport(
        folderPath: folderPath,
        files: const <PioneerCapturedHtmlFileReport>[],
        scannedFileCount: 0,
        htmlFileCount: 0,
        completedAt: DateTime.now().toUtc(),
      );
    }

    final htmlFiles = await _discoverHtmlFiles(root);
    final db = await ELibraryDatabase.instance.database;
    final entries = <PioneerCapturedHtmlFileReport>[];
    for (final filePath in htmlFiles) {
      entries.add(
        await _analyzeFile(
          db: db,
          rootPath: root.path,
          filePath: filePath,
          importFiles: importFiles,
          existingImportPolicy: existingImportPolicy,
        ),
      );
    }

    return PioneerCapturedHtmlFolderImportReport(
      folderPath: root.path,
      files: List<PioneerCapturedHtmlFileReport>.unmodifiable(entries),
      scannedFileCount: entries.length,
      htmlFileCount: entries.length,
      completedAt: DateTime.now().toUtc(),
    );
  }

  Future<PioneerCapturedHtmlFolderImportReport> importConfiguredFolder({
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) {
    return scanConfiguredFolder(
      importFiles: true,
      existingImportPolicy: existingImportPolicy,
    );
  }

  Future<PioneerCapturedHtmlFileReport> _analyzeFile({
    required Database db,
    required String rootPath,
    required String filePath,
    required bool importFiles,
    required PioneerExistingImportPolicy existingImportPolicy,
  }) async {
    final file = File(filePath);
    final rawBytes = await file.readAsBytes();
    final fileHash = sha256.convert(rawBytes).toString();
    final relativePath = p.normalize(p.relative(filePath, from: rootPath));
    final metadata = _folderMetadataFor(filePath);
    final html = utf8.decode(rawBytes, allowMalformed: true);
    final parsed = _parser.parse(
      html: html,
      filePath: filePath,
      relativePath: relativePath,
      metadata: metadata,
    );
    final work = _workFromParsed(
      parsed: parsed,
      relativePath: relativePath,
      filePath: filePath,
      metadata: metadata,
      fileHash: fileHash,
    );
    final storageRelativePath = _virtualRelativePath(work, relativePath);
    final duplicate = await _existingDuplicate(
      db: db,
      fileHash: fileHash,
      relativePath: storageRelativePath,
      sourceUrl: parsed.sourceUrl,
    );
    if (duplicate != null) {
      final existingHash = duplicate['file_hash']?.toString().trim() ?? '';
      final existingPath = duplicate['relative_path']?.toString().trim() ?? '';
      final sameHash =
          existingHash.isNotEmpty &&
          existingHash.toLowerCase() == fileHash.toLowerCase();
      final samePath =
          existingPath.isNotEmpty &&
          existingPath.toLowerCase() == storageRelativePath.toLowerCase();
      return PioneerCapturedHtmlFileReport(
        filePath: filePath,
        relativePath: relativePath,
        fileHash: fileHash,
        title: parsed.title,
        author: parsed.author,
        sourceType: metadata.sourceType?.trim().isNotEmpty == true
            ? metadata.sourceType!.trim()
            : 'pioneer_captured_html',
        sourceSite: parsed.sourceSite,
        sourceUrl: parsed.sourceUrl,
        coverImagePath: parsed.coverImagePath,
        headingCount: parsed.headingCount,
        paragraphCount: parsed.paragraphCount,
        sectionCount: parsed.document.sections.length,
        warnings: parsed.warnings,
        status: sameHash
            ? PioneerCapturedHtmlFileStatus.skippedDuplicate
            : samePath
            ? PioneerCapturedHtmlFileStatus.needsCleanup
            : PioneerCapturedHtmlFileStatus.skippedDuplicate,
        reason: sameHash
            ? 'Already imported as ${duplicate['id']?.toString() ?? 'existing item'}.'
            : samePath
            ? 'A file already exists at this relative path but the contents changed.'
            : 'Already imported as ${duplicate['id']?.toString() ?? 'existing item'}.',
        libraryItemId: duplicate['id']?.toString(),
      );
    }

    final reportStatus = parsed.needsCleanup
        ? PioneerCapturedHtmlFileStatus.needsCleanup
        : PioneerCapturedHtmlFileStatus.ready;
    if (!importFiles) {
      return PioneerCapturedHtmlFileReport(
        filePath: filePath,
        relativePath: relativePath,
        fileHash: fileHash,
        title: parsed.title,
        author: parsed.author,
        sourceType: work.sourceType ?? 'pioneer_captured_html',
        sourceSite: parsed.sourceSite,
        sourceUrl: parsed.sourceUrl,
        coverImagePath: parsed.coverImagePath,
        headingCount: parsed.headingCount,
        paragraphCount: parsed.paragraphCount,
        sectionCount: parsed.document.sections.length,
        warnings: parsed.warnings,
        status: reportStatus,
        reason: parsed.warnings.isEmpty ? null : parsed.warnings.join(' | '),
      );
    }

    final importResult = await _importService.importFromParsedCapturedHtml(
      work: work,
      document: parsed.document,
      sourceBytes: rawBytes,
      sourceUrl: parsed.sourceUrl,
      sourceType: 'pioneer_captured_html',
      sourceSite: parsed.sourceSite,
      relativePath: _virtualRelativePath(work, relativePath),
      coverPath: parsed.coverImagePath,
      existingImportPolicy: existingImportPolicy,
      indexStatus: parsed.needsCleanup
          ? 'partially_imported_needs_review'
          : 'indexed',
      indexError: parsed.warnings.isEmpty ? null : parsed.warnings.join(' | '),
    );
    final result = importResult.workResults.isEmpty
        ? null
        : importResult.workResults.first;
    final fileStatus = result == null
        ? PioneerCapturedHtmlFileStatus.failed
        : switch (result.status) {
            PioneerImportWorkStatus.imported =>
              reportStatus == PioneerCapturedHtmlFileStatus.needsCleanup
                  ? PioneerCapturedHtmlFileStatus.needsCleanup
                  : PioneerCapturedHtmlFileStatus.imported,
            PioneerImportWorkStatus.skippedExisting =>
              PioneerCapturedHtmlFileStatus.skippedDuplicate,
            PioneerImportWorkStatus.skippedNotImportable ||
            PioneerImportWorkStatus.skippedUnsupportedSource ||
            PioneerImportWorkStatus.failed =>
              PioneerCapturedHtmlFileStatus.failed,
          };
    return PioneerCapturedHtmlFileReport(
      filePath: filePath,
      relativePath: relativePath,
      fileHash: fileHash,
      title: parsed.title,
      author: parsed.author,
      sourceType: work.sourceType ?? 'pioneer_captured_html',
      sourceSite: parsed.sourceSite,
      sourceUrl: parsed.sourceUrl,
      coverImagePath: parsed.coverImagePath,
      headingCount: parsed.headingCount,
      paragraphCount: parsed.paragraphCount,
      sectionCount: parsed.document.sections.length,
      warnings: parsed.warnings,
      status: fileStatus,
      reason: result?.reason ?? parsed.warnings.join(' | '),
      libraryItemId: result?.libraryItemId,
    );
  }
}

PioneerCaptureFolderMetadata _folderMetadataFor(String filePath) {
  final folder = Directory(p.dirname(filePath));
  final metadataFile = File(p.join(folder.path, 'metadata.json'));
  if (!metadataFile.existsSync()) {
    return PioneerCaptureFolderMetadata.empty();
  }
  return PioneerCaptureFolderMetadata.fromFile(
    metadataFile,
    folderPath: folder.path,
  );
}

Future<List<String>> _discoverHtmlFiles(Directory root) async {
  final files = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final extension = p.extension(entity.path).toLowerCase();
    if (extension != '.html' && extension != '.htm') continue;
    files.add(p.normalize(entity.path));
  }
  files.sort(
    (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
  );
  return List<String>.unmodifiable(files);
}

Future<Map<String, Object?>?> _existingDuplicate({
  required Database db,
  required String fileHash,
  required String relativePath,
  required String? sourceUrl,
}) async {
  final normalizedRelativePath = relativePath.trim().toLowerCase();
  final normalizedSourceUrl = sourceUrl?.trim().toLowerCase() ?? '';
  final rows = await db.query(
    'library_items',
    columns: const ['id', 'file_hash', 'relative_path', 'source_url'],
    where: '''
      deleted_at IS NULL AND (
        LOWER(COALESCE(file_hash, '')) = ? OR
        LOWER(COALESCE(relative_path, '')) = ? OR
        (? <> '' AND LOWER(COALESCE(source_url, '')) = ?)
      )
    ''',
    whereArgs: [
      fileHash.toLowerCase(),
      normalizedRelativePath,
      normalizedSourceUrl,
      normalizedSourceUrl,
    ],
    limit: 1,
  );
  return rows.isEmpty ? null : rows.first;
}

PioneerSourceWork _workFromParsed({
  required PioneerCapturedHtmlParseResult parsed,
  required String relativePath,
  required String filePath,
  required PioneerCaptureFolderMetadata metadata,
  required String fileHash,
}) {
  final fileStem = p.basenameWithoutExtension(filePath);
  final authorName = parsed.author.trim().isNotEmpty
      ? parsed.author.trim()
      : 'Unknown';
  final authorId = _stableId(
    authorName == 'Unknown' ? 'unknown_$relativePath' : authorName,
  );
  final workId = metadata.workId?.trim().isNotEmpty == true
      ? _stableId(metadata.workId!.trim())
      : _stableId(relativePath.isNotEmpty ? relativePath : fileStem);
  final abbreviation = _capturedHtmlAbbreviation(
    metadata.preferredAbbreviation,
    title: parsed.title,
    fileStem: fileStem,
    fileHash: fileHash,
  );
  final notes = parsed.warnings.isEmpty ? null : parsed.warnings.join(' ');
  return PioneerSourceWork(
    id: workId,
    authorId: authorId,
    authorName: authorName,
    sourceFamily: 'Pioneer',
    title: parsed.title,
    abbreviation: abbreviation,
    group: 'Pioneer Authors',
    subgroup: 'Captured HTML',
    availability: PioneerSourceAvailability.available,
    verified: true,
    catalogImportable: true,
    sourceType: 'pioneer_captured_html',
    sourceUrl: parsed.sourceUrl,
    sourceLabel: parsed.sourceSite ?? 'local_cloud_folder',
    notes: notes,
  );
}

String _virtualRelativePath(PioneerSourceWork work, String sourceRelativePath) {
  final fileStem = p.basenameWithoutExtension(sourceRelativePath);
  return p.join(
    'TextCaptures',
    'Research',
    'Pioneer Authors',
    _stableId(work.id).isEmpty ? 'captured_html' : _stableId(work.id),
    'captured_html',
    '$fileStem.html',
  );
}

String _capturedHtmlAbbreviation(
  String? metadataAbbreviation, {
  required String title,
  required String fileStem,
  required String fileHash,
}) {
  final metadata = metadataAbbreviation?.trim() ?? '';
  if (metadata.isNotEmpty) return metadata;
  final stem = _compactCode(fileStem);
  if (stem.isNotEmpty && stem.length <= 16) return stem.toUpperCase();
  final titleWords = title
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((word) => word.trim().isNotEmpty)
      .where((word) => !_abbrevStopWords.contains(word.toLowerCase()))
      .toList(growable: false);
  if (titleWords.isNotEmpty) {
    final initials = titleWords.take(4).map((word) => word[0]).join();
    if (initials.isNotEmpty) return initials.toUpperCase();
  }
  final hashCode = fileHash.substring(
    0,
    fileHash.length >= 8 ? 8 : fileHash.length,
  );
  return 'CAP${hashCode.toUpperCase()}';
}

String _stableId(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String _compactCode(String value) {
  return value.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
}

const Set<String> _abbrevStopWords = <String>{
  'a',
  'an',
  'and',
  'by',
  'for',
  'in',
  'of',
  'on',
  'the',
  'to',
  'with',
};

@immutable
class _HtmlBlock {
  const _HtmlBlock({
    required this.kind,
    required this.text,
    required this.level,
  });

  final String kind;
  final String text;
  final int? level;
}

List<PioneerImportSection> _sectionsFromBlocks(
  List<_HtmlBlock> blocks, {
  required String title,
  required String relativePath,
}) {
  final sections = <PioneerImportSection>[];
  final pathSegments = <String>[];
  final headingTitles = <String>[];
  var currentHeading = title;
  var currentParagraphs = <String>[];
  var sectionIndex = 1;

  void flush() {
    if (currentParagraphs.isEmpty) return;
    final rootSegment = _stableId(relativePath).isEmpty
        ? 'captured_html'
        : _stableId(relativePath);
    final href = p.joinAll([
      'captured',
      rootSegment,
      ...pathSegments,
      'section_${sectionIndex.toString().padLeft(2, '0')}.html',
    ]);
    sections.add(
      PioneerImportSection(
        href: href,
        title: currentHeading.trim().isNotEmpty ? currentHeading.trim() : title,
        paragraphs: List<String>.unmodifiable(currentParagraphs),
        spineIndex: sectionIndex,
      ),
    );
    sectionIndex += 1;
    currentParagraphs = <String>[];
  }

  for (final block in blocks) {
    if (block.kind == 'heading') {
      flush();
      final level = block.level ?? 1;
      while (pathSegments.length >= level) {
        pathSegments.removeLast();
      }
      while (headingTitles.length >= level) {
        headingTitles.removeLast();
      }
      pathSegments.add(
        _stableId(block.text).isEmpty
            ? 'section_$sectionIndex'
            : _stableId(block.text),
      );
      headingTitles.add(block.text.trim());
      currentHeading = headingTitles.join(' — ').trim();
      if (currentHeading.isEmpty) {
        currentHeading = title;
      }
      continue;
    }
    if (block.text.trim().isEmpty) continue;
    currentParagraphs.add(block.text.trim());
  }
  flush();

  if (sections.isEmpty && blocks.isNotEmpty) {
    final paragraphs = blocks
        .where((block) => block.kind != 'heading')
        .map((block) => block.text.trim())
        .where((text) => text.isNotEmpty)
        .toList(growable: false);
    if (paragraphs.isNotEmpty) {
      final rootSegment = _stableId(relativePath).isEmpty
          ? 'captured_html'
          : _stableId(relativePath);
      sections.add(
        PioneerImportSection(
          href: p.joinAll(['captured', rootSegment, 'section_01.html']),
          title: title,
          paragraphs: List<String>.unmodifiable(paragraphs),
          spineIndex: 1,
        ),
      );
    }
  }

  return sections;
}

String _titleFromMetadata(PioneerCaptureFolderMetadata metadata) {
  return metadata.title?.trim() ?? '';
}

String _titleFromHtml({
  required String rawHtml,
  required String bodyHtml,
  required PioneerCaptureFolderMetadata metadata,
  required String filePath,
}) {
  final metaTitle = _titleFromMetadata(metadata);
  if (metaTitle.isNotEmpty) return metaTitle;
  final titleMatch = RegExp(
    r'<title\b[^>]*>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(rawHtml);
  final title = _cleanHtmlText(titleMatch?.group(1));
  if (title.isNotEmpty) return title;
  for (final heading in _headingTexts(bodyHtml)) {
    if (heading.isNotEmpty) return heading;
  }
  final fileStem = p.basenameWithoutExtension(filePath).trim();
  return fileStem.isEmpty ? 'Captured HTML' : _titleCaseFromFileStem(fileStem);
}

String _authorFromHtml({
  required String rawHtml,
  required String bodyHtml,
  required PioneerCaptureFolderMetadata metadata,
}) {
  final metadataAuthor = metadata.primaryContributorName?.trim() ?? '';
  if (metadataAuthor.isNotEmpty) return metadataAuthor;
  for (final pattern in const <String>[
    r'''<meta[^>]+name=["']author["'][^>]+content=["']([^"']+)["']''',
    r'''<meta[^>]+property=["']article:author["'][^>]+content=["']([^"']+)["']''',
    r'''<meta[^>]+name=["']citation_author["'][^>]+content=["']([^"']+)["']''',
    r'''<meta[^>]+name=["']dc\.creator["'][^>]+content=["']([^"']+)["']''',
  ]) {
    final match = RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawHtml);
    final value = _cleanHtmlText(match?.group(1));
    if (value.isNotEmpty) return value;
  }
  final leadingText = _cleanHtmlText(
    bodyHtml.length > 2000 ? bodyHtml.substring(0, 2000) : bodyHtml,
  );
  final bylineMatch = RegExp(
    r"\b(?:by|author|written by)\s+([A-Z][A-Za-z0-9.,'’\-\s]{2,80})",
    caseSensitive: false,
  ).firstMatch(leadingText);
  final byline = _cleanHtmlText(bylineMatch?.group(1));
  if (byline.isNotEmpty) return byline;
  return 'Unknown';
}

String? _sourceUrlFromHtml(String rawHtml) {
  for (final pattern in const <String>[
    r'''<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']''',
    r'''<meta[^>]+property=["']og:url["'][^>]+content=["']([^"']+)["']''',
  ]) {
    final match = RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawHtml);
    final value = match?.group(1)?.trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

String? _coverImageFromHtml(String rawHtml, String filePath) {
  for (final pattern in const <String>[
    r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''',
    r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''',
    r'''<img[^>]+src=["']([^"']+)["']''',
  ]) {
    final match = RegExp(
      pattern,
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawHtml);
    final value = match?.group(1)?.trim() ?? '';
    if (value.isEmpty) continue;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final resolved = p.normalize(p.join(p.dirname(filePath), value));
    return resolved;
  }
  return null;
}

List<String> _headingTexts(String html) {
  final headings = <String>[];
  final headingPattern = RegExp(
    r'<(h[1-3])\b[^>]*>(.*?)</\1>',
    caseSensitive: false,
    dotAll: true,
  );
  for (final match in headingPattern.allMatches(html)) {
    final text = _cleanHtmlText(match.group(2));
    if (text.isNotEmpty) headings.add(text);
  }
  return headings;
}

List<_HtmlBlock> _extractHtmlBlocks(String rawHtml) {
  final body = _extractHtmlBody(rawHtml) ?? rawHtml;
  final blocks = <_HtmlBlock>[];
  final blockPattern = RegExp(
    r'<(/?)(h[1-3]|p|li|blockquote|div)\b([^>]*)>',
    caseSensitive: false,
    dotAll: true,
  );
  final stack = <_OpenBlock>[];

  for (final match in blockPattern.allMatches(body)) {
    final isClosing = (match.group(1) ?? '').isNotEmpty;
    final tag = (match.group(2) ?? '').toLowerCase();
    final attrs = match.group(3) ?? '';
    if (!isClosing) {
      if ((match.group(0) ?? '').endsWith('/>')) {
        continue;
      }
      stack.add(_OpenBlock(tag: tag, attrs: attrs, contentStart: match.end));
      continue;
    }

    final openIndex = stack.lastIndexWhere((block) => block.tag == tag);
    if (openIndex < 0) continue;
    final open = stack.removeAt(openIndex);
    final innerHtml = body.substring(open.contentStart, match.start);
    if (_isHiddenHtmlBlock(open.attrs, innerHtml)) continue;
    final text = _cleanHtmlText(innerHtml);
    if (text.isEmpty) continue;
    if (tag.startsWith('h')) {
      blocks.add(
        _HtmlBlock(
          kind: 'heading',
          text: text,
          level: int.tryParse(tag.substring(1)),
        ),
      );
    } else {
      blocks.add(_HtmlBlock(kind: 'paragraph', text: text, level: null));
    }
  }

  if (blocks.isEmpty) {
    final text = _cleanHtmlText(body);
    if (text.isNotEmpty) {
      blocks.add(_HtmlBlock(kind: 'paragraph', text: text, level: null));
    }
  }
  return blocks;
}

String? _extractHtmlBody(String rawHtml) {
  final match = RegExp(
    r'<body\b[^>]*>(.*?)</body>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(rawHtml);
  return match?.group(1);
}

String _cleanHtmlText(String? html) {
  if (html == null) return '';
  return html
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

bool _isHiddenHtmlBlock(String attrs, String innerHtml) {
  final combined = '${attrs.toLowerCase()} ${innerHtml.toLowerCase()}';
  return combined.contains('display:none') ||
      combined.contains('visibility:hidden') ||
      combined.contains('aria-hidden="true"') ||
      combined.contains("aria-hidden='true'");
}

String _titleCaseFromFileStem(String fileStem) {
  final parts = fileStem
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts
      .map((part) {
        if (part.isEmpty) return part;
        return part[0].toUpperCase() + part.substring(1).toLowerCase();
      })
      .join(' ');
}

class _OpenBlock {
  const _OpenBlock({
    required this.tag,
    required this.attrs,
    required this.contentStart,
  });

  final String tag;
  final String attrs;
  final int contentStart;
}
