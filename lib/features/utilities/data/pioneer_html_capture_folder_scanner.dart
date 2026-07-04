import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'pioneer_capture_folder_metadata.dart';
import 'egw_copied_range_parser.dart';
import 'pioneer_source_catalog.dart';

const String kDefaultPioneerHtmlCaptureRoot = 'assets/scans';
const String kKnownDevPioneerHtmlCaptureRoot =
    '/Users/deanbowen/Development/StudyBible2/assets/scans';

typedef PioneerHtmlCaptureAssetStringLoader =
    Future<String> Function(String assetKey);

@immutable
class PioneerHtmlCaptureFolderScanResult {
  const PioneerHtmlCaptureFolderScanResult({
    required this.previews,
    required this.assetKeyCount,
    required this.scanAssetKeyCount,
    required this.usedAssetManifest,
    required this.usedFileSystemFallback,
    required this.checkedRootPath,
    required this.currentWorkingDirectory,
    required this.absolutePathChecked,
    required this.fileSystemPathExists,
    required this.immediateChildFolderCount,
    required this.htmlFileCount,
    required this.fallbackAttemptsTried,
    this.fileSystemFallbackPath,
  });

  final List<PioneerHtmlCaptureFolderPreview> previews;
  final int assetKeyCount;
  final int scanAssetKeyCount;
  final bool usedAssetManifest;
  final bool usedFileSystemFallback;
  final String checkedRootPath;
  final String currentWorkingDirectory;
  final String absolutePathChecked;
  final bool fileSystemPathExists;
  final int immediateChildFolderCount;
  final int htmlFileCount;
  final List<String> fallbackAttemptsTried;
  final String? fileSystemFallbackPath;

  String get emptyStateMessage {
    final attempts = fallbackAttemptsTried.isEmpty
        ? 'none'
        : fallbackAttemptsTried.join(' | ');
    final buffer = StringBuffer(
      'No capture folders found. CWD: $currentWorkingDirectory; '
      'absolute path checked: $absolutePathChecked; '
      'exists: $fileSystemPathExists; '
      'child folders: $immediateChildFolderCount; '
      'HTML files: $htmlFileCount; '
      'fallback attempts: $attempts.',
    );
    if (usedAssetManifest) {
      buffer.write(
        ' AssetManifest had $scanAssetKeyCount assets under $checkedRootPath/ '
        '($assetKeyCount total assets).',
      );
    }
    return buffer.toString();
  }
}

enum PioneerHtmlCaptureImportStatus {
  newImport,
  existing,
  overwriteAvailable,
  invalid;

  String get label => switch (this) {
    PioneerHtmlCaptureImportStatus.newImport => 'new',
    PioneerHtmlCaptureImportStatus.existing => 'existing',
    PioneerHtmlCaptureImportStatus.overwriteAvailable => 'overwrite available',
    PioneerHtmlCaptureImportStatus.invalid => 'invalid',
  };
}

@immutable
class EgwHtmlCaptureExtractionResult {
  const EgwHtmlCaptureExtractionResult({
    required this.text,
    required this.detectedAbbreviation,
    required this.firstRef,
    required this.lastRef,
    required this.refCount,
    required this.duplicateRefs,
    required this.chapterHeadingCount,
    required this.detectedTitle,
    required this.warnings,
    this.detectedAuthor,
  });

  final String text;
  final String? detectedAbbreviation;
  final String? firstRef;
  final String? lastRef;
  final int refCount;
  final List<String> duplicateRefs;
  final int chapterHeadingCount;
  final String? detectedTitle;
  final String? detectedAuthor;
  final List<String> warnings;

  int get duplicateRefCount => duplicateRefs.length;
}

@immutable
class PioneerHtmlCaptureFolderPreview {
  const PioneerHtmlCaptureFolderPreview({
    required this.folderPath,
    required this.folderName,
    required this.metadata,
    required this.htmlFiles,
    required this.imageFiles,
    this.availableFileNames = const <String>[],
    this.sourceFileHash,
    required this.preferredCoverImagePath,
    required this.detectedTitle,
    required this.detectedAuthor,
    required this.detectedAbbreviation,
    required this.firstRef,
    required this.lastRef,
    required this.refCount,
    required this.duplicateRefCount,
    required this.chapterHeadingCount,
    this.firstChapterLabel,
    this.lastChapterLabel,
    required this.isValid,
    required this.warnings,
    this.validationReasons = const <String>[],
    required this.importStatus,
    this.catalogWork,
    this.extractedText,
  });

  final String folderPath;
  final String folderName;
  final PioneerCaptureFolderMetadata metadata;
  final List<String> htmlFiles;
  final List<String> imageFiles;
  final List<String> availableFileNames;
  final String? sourceFileHash;
  final String? preferredCoverImagePath;
  final String? detectedTitle;
  final String? detectedAuthor;
  final String? detectedAbbreviation;
  final String? firstRef;
  final String? lastRef;
  final int refCount;
  final int duplicateRefCount;
  final int chapterHeadingCount;
  final String? firstChapterLabel;
  final String? lastChapterLabel;
  final bool isValid;
  final List<String> warnings;
  final List<String> validationReasons;
  final PioneerHtmlCaptureImportStatus importStatus;
  final PioneerSourceWork? catalogWork;
  final String? extractedText;

  int get htmlFileCount => htmlFiles.length;
  int get imageFileCount => imageFiles.length;
  int get generatedNavigationCount => chapterHeadingCount;

  bool get hasMetadataIdentity => metadata.hasIdentity;

  PioneerSourceWork get bestEffortWork {
    final catalog = catalogWork;
    final sourceTitle = _resolveBestEffortTitle(
      catalog,
      folderName: folderName,
    );
    final sourceAbbreviation =
        metadata.preferredAbbreviation ??
        detectedAbbreviation ??
        catalog?.abbreviation ??
        _abbreviationFromFolder(folderName);
    final sourceAuthor = _resolveBestEffortAuthor(
      catalog,
      folderName: folderName,
    );
    final workId = metadata.workId?.trim();
    final baseWork =
        catalog ??
        PioneerSourceWork(
          id: workId?.isNotEmpty == true ? workId! : folderName,
          authorId: _stableCaptureId(sourceAuthor),
          authorName: sourceAuthor,
          sourceFamily: 'Pioneer',
          title: sourceTitle,
          abbreviation: sourceAbbreviation,
          group: 'Pioneer Authors',
          subgroup: 'Captured HTML',
          availability: PioneerSourceAvailability.available,
          verified: true,
          catalogImportable: true,
          sourceType: metadata.sourceType ?? 'egw_html_capture',
          sourceUrl: null,
          collectionUrl: null,
          captureUrl: null,
          readerUrl: null,
          directFileUrl: null,
          directFileType: null,
          thumbnailUrl: null,
          coverUrl: null,
          cachedThumbnailPath: null,
          cachedCoverPath: null,
          sourceLabel: metadata.sourceSite ?? 'EGW Writings',
          notes: null,
        );

    return baseWork.copyWith(
      id: workId?.isNotEmpty == true ? workId : baseWork.id,
      authorId: _stableCaptureId(sourceAuthor),
      authorName: sourceAuthor,
      title: sourceTitle,
      abbreviation: sourceAbbreviation,
      sourceType: metadata.sourceType ?? 'egw_html_capture',
      sourceUrl: firstRef == null
          ? baseWork.sourceUrl
          : 'https://egwwritings.org/read?ref=$firstRef',
      sourceLabel: metadata.sourceSite ?? 'EGW Writings',
      cachedCoverPath:
          metadata.coverImagePath ??
          preferredCoverImagePath ??
          baseWork.cachedCoverPath,
      sourceCandidates: const <PioneerSourceCandidate>[
        PioneerSourceCandidate(
          provider: 'egwWritings',
          sourceType: 'capturedHtml',
          priority: 1,
          qualityTier: 'capturedhtml',
          availability: PioneerSourceAvailability.available,
          notes: 'Local staged HTML capture folder.',
        ),
      ],
      availability: PioneerSourceAvailability.available,
      verified: true,
      catalogImportable: true,
    );
  }

  String _resolveBestEffortTitle(
    PioneerSourceWork? catalog, {
    required String folderName,
  }) {
    final metadataTitle = metadata.title?.trim() ?? '';
    final catalogTitle = catalog?.title.trim() ?? '';
    final detectedTitleValue = detectedTitle?.trim() ?? '';
    if (catalogTitle.isNotEmpty &&
        looksLikeCaptureFolderPlaceholderTitle(
          metadataTitle,
          folderCode: folderName,
          abbreviation: metadata.preferredAbbreviation,
        )) {
      return catalogTitle;
    }
    if (metadataTitle.isNotEmpty) return metadataTitle;
    if (catalogTitle.isNotEmpty) return catalogTitle;
    if (detectedTitleValue.isNotEmpty) return detectedTitleValue;
    return folderName;
  }

  String _resolveBestEffortAuthor(
    PioneerSourceWork? catalog, {
    required String folderName,
  }) {
    final metadataAuthor = metadata.primaryContributorName?.trim() ?? '';
    final catalogAuthor = catalog?.authorName.trim() ?? '';
    final folderAuthor = _authorFromFolderName(folderName)?.trim() ?? '';
    final placeholderMetadataAuthor =
        metadataAuthor.isEmpty ||
        metadataAuthor.toLowerCase() == 'unknown' ||
        metadataAuthor.toLowerCase() == 'unknown author' ||
        looksLikeCaptureFolderPlaceholderTitle(
          metadataAuthor,
          folderCode: folderName,
          abbreviation: metadata.preferredAbbreviation,
        );

    if (catalogAuthor.isNotEmpty && placeholderMetadataAuthor) {
      return catalogAuthor;
    }
    if (metadataAuthor.isNotEmpty && !placeholderMetadataAuthor) {
      return metadataAuthor;
    }
    if (catalogAuthor.isNotEmpty) return catalogAuthor;
    if (folderAuthor.isNotEmpty) return folderAuthor;
    return detectedAuthor?.trim().isNotEmpty == true
        ? detectedAuthor!.trim()
        : 'Unknown';
  }

  PioneerSourceWork get importWork {
    if (!isValid) {
      throw StateError('Capture preview is not importable: $folderName');
    }
    return bestEffortWork;
  }

  PioneerHtmlCaptureFolderPreview copyWith({
    PioneerHtmlCaptureImportStatus? importStatus,
    List<String>? warnings,
    List<String>? validationReasons,
    bool? isValid,
  }) {
    return PioneerHtmlCaptureFolderPreview(
      folderPath: folderPath,
      folderName: folderName,
      metadata: metadata,
      htmlFiles: htmlFiles,
      imageFiles: imageFiles,
      availableFileNames: availableFileNames,
      sourceFileHash: sourceFileHash,
      preferredCoverImagePath: preferredCoverImagePath,
      detectedTitle: detectedTitle,
      detectedAuthor: detectedAuthor,
      detectedAbbreviation: detectedAbbreviation,
      firstRef: firstRef,
      lastRef: lastRef,
      refCount: refCount,
      duplicateRefCount: duplicateRefCount,
      chapterHeadingCount: chapterHeadingCount,
      firstChapterLabel: firstChapterLabel,
      lastChapterLabel: lastChapterLabel,
      isValid: isValid ?? this.isValid,
      warnings: warnings ?? this.warnings,
      validationReasons: validationReasons ?? this.validationReasons,
      importStatus: importStatus ?? this.importStatus,
      catalogWork: catalogWork,
      extractedText: extractedText,
    );
  }
}

class EgwHtmlCaptureExtractor {
  const EgwHtmlCaptureExtractor();

  EgwHtmlCaptureExtractionResult extract(
    String html, {
    String? fallbackAbbreviation,
    String? fallbackTitle,
  }) {
    final readableBlocks = _extractReadableBlocks(html);
    final warnings = <String>[];
    if (readableBlocks.isEmpty) {
      warnings.add('No div.clip.clip-text paragraphs were found.');
    }
    final allText = _normalizeWhitespace(
      readableBlocks.map((block) => block.text).join(' '),
    );
    final abbreviation =
        _detectAbbreviation(allText) ?? fallbackAbbreviation?.trim();
    if (abbreviation == null || abbreviation.isEmpty) {
      return EgwHtmlCaptureExtractionResult(
        text: '',
        detectedAbbreviation: null,
        firstRef: null,
        lastRef: null,
        refCount: 0,
        duplicateRefs: const <String>[],
        chapterHeadingCount: 0,
        detectedTitle: fallbackTitle,
        warnings: List<String>.unmodifiable([
          ...warnings,
          'No paragraph ref prefix was detected.',
        ]),
      );
    }

    final normalizedAbbreviation = abbreviation.toUpperCase();
    final refPattern = _paragraphRefPattern(normalizedAbbreviation);
    final refs = refPattern
        .allMatches(allText)
        .map((match) => match.group(0)!)
        .toList(growable: false);
    final duplicateRefs = _duplicateRefs(refs);
    final copiedPrefix = _detectCopiedEgwPrefix(allText);
    final fallbackTitleIsPlaceholder =
        fallbackTitle == null ||
        looksLikeCaptureFolderPlaceholderTitle(
          fallbackTitle,
          folderCode: fallbackAbbreviation,
          abbreviation: normalizedAbbreviation,
        );
    if (copiedPrefix != null) {
      return _extractCopiedEgwCapture(
        allText: allText,
        prefix: copiedPrefix,
        abbreviation: normalizedAbbreviation,
        refs: refs,
        duplicateRefs: duplicateRefs,
        title: fallbackTitleIsPlaceholder
            ? copiedPrefix.title
            : fallbackTitle.trim(),
        initialWarnings: warnings,
      );
    }
    final title = fallbackTitle?.trim().isNotEmpty == true
        ? fallbackTitle!.trim()
        : _detectTitle(
            readableBlocks.map((block) => block.text).toList(growable: false),
            normalizedAbbreviation,
          );
    final lines = <String>[];
    var currentPage = -1;
    var emittedHeading = false;
    var chapterHeadingCount = 0;

    void ensureFallbackHeading() {
      if (emittedHeading) return;
      final cleanTitle = _normalizeChapterTitle(title ?? 'Captured Text');
      lines.add('Chapter 1 — $cleanTitle');
      emittedHeading = true;
    }

    for (final readableBlock in readableBlocks) {
      var block = _normalizeWhitespace(readableBlock.text);
      if (block.isEmpty) continue;

      final chapter = _chapterHeading(block, normalizedAbbreviation);
      if (chapter != null) {
        lines.add(chapter.heading);
        emittedHeading = true;
        chapterHeadingCount += 1;
        block = chapter.remainingText;
      } else if (readableBlock.isHeadingCandidate &&
          _looksLikeStandaloneHeadingBlock(block)) {
        lines.add(block);
        emittedHeading = true;
        chapterHeadingCount += 1;
        continue;
      } else {
        ensureFallbackHeading();
      }

      for (final paragraph in _paragraphsFromBlock(
        block,
        normalizedAbbreviation,
      )) {
        final page = _pageFromRef(paragraph.ref);
        if (page != null && page != currentPage) {
          lines.add('$normalizedAbbreviation $page');
          currentPage = page;
        }
        final text = _stripLeadingAuthor(paragraph.text);
        if (text.isEmpty) {
          warnings.add('Empty paragraph text for ref ${paragraph.ref}');
          lines.add(paragraph.ref);
          continue;
        }
        lines.add(text);
        lines.add(paragraph.ref);
      }
    }

    final normalizedText = '${lines.join('\n')}\n';
    return EgwHtmlCaptureExtractionResult(
      text: normalizedText,
      detectedAbbreviation: normalizedAbbreviation,
      firstRef: refs.isEmpty ? null : refs.first,
      lastRef: refs.isEmpty ? null : refs.last,
      refCount: refs.length,
      duplicateRefs: duplicateRefs,
      chapterHeadingCount: chapterHeadingCount,
      detectedTitle: title,
      warnings: List<String>.unmodifiable([
        ...warnings,
        if (duplicateRefs.isNotEmpty)
          'Duplicate refs detected: ${duplicateRefs.join(', ')}',
        if (refs.isEmpty) 'No paragraph refs were detected.',
      ]),
    );
  }

  List<_ReadableHtmlBlock> _extractReadableBlocks(String html) {
    final blocks = <_ReadableHtmlBlock>[];
    final blockPattern = RegExp(
      r'<(h[2-6]|p|b|strong)\b[^>]*>(.*?)</\1>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final match in blockPattern.allMatches(html)) {
      final tag = (match.group(1) ?? '').toLowerCase();
      final text = _stripHtml(match.group(2) ?? '');
      if (text.isEmpty) continue;
      if (tag.startsWith('h') || tag == 'p') {
        blocks.add(
          _ReadableHtmlBlock(tag: tag, text: text, isHeadingCandidate: true),
        );
        continue;
      }
      if ((tag == 'b' || tag == 'strong') && _looksLikeHeadingText(text)) {
        blocks.add(
          _ReadableHtmlBlock(tag: tag, text: text, isHeadingCandidate: true),
        );
      }
    }
    if (blocks.isNotEmpty) {
      return List<_ReadableHtmlBlock>.unmodifiable(blocks);
    }

    final paragraphPattern = RegExp(
      r'<p\b[^>]*>(.*?)</p>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final paragraph in paragraphPattern.allMatches(html)) {
      final text = _stripHtml(paragraph.group(1) ?? '');
      if (text.isNotEmpty) {
        blocks.add(
          _ReadableHtmlBlock(tag: 'p', text: text, isHeadingCandidate: false),
        );
      }
    }
    return List<_ReadableHtmlBlock>.unmodifiable(blocks);
  }

  /// Detects EGW's "copy with reference" format, where every copied
  /// paragraph is prefixed with `Title, p. N[.M] (Author)`. Returns null
  /// when the capture does not repeat such a prefix.
  _CopiedEgwPrefix? _detectCopiedEgwPrefix(String allText) {
    final leading = RegExp(
      r'^(.{1,120}?),\s+p\.\s+\d+(?:\.\d+)?\s+\(([^()]{2,80})\)',
    ).firstMatch(allText);
    if (leading == null) return null;
    final title = _normalizeWhitespace(leading.group(1) ?? '');
    final author = _normalizeWhitespace(leading.group(2) ?? '');
    if (title.isEmpty || author.isEmpty) return null;
    final pattern = RegExp(
      '${RegExp.escape(title)},\\s+p\\.\\s+(\\d+(?:\\.\\d+)?)\\s+'
      '\\(${RegExp.escape(author)}\\)',
    );
    if (pattern.allMatches(allText).length < 2) return null;
    return _CopiedEgwPrefix(title: title, author: author, pattern: pattern);
  }

  /// Normalizes a copied-EGW capture into clean copied-range lines:
  /// real headings, `ABBR page` markers, paragraph text with the
  /// `Title, p. N (Author)` prefixes stripped, and trailing ref lines.
  EgwHtmlCaptureExtractionResult _extractCopiedEgwCapture({
    required String allText,
    required _CopiedEgwPrefix prefix,
    required String abbreviation,
    required List<String> refs,
    required List<String> duplicateRefs,
    required String title,
    required List<String> initialWarnings,
  }) {
    final warnings = <String>[...initialWarnings];
    final lines = <String>[];
    var chapterHeadingCount = 0;
    var currentPage = -1;
    var lastHeading = '';
    final matches = prefix.pattern.allMatches(allText).toList(growable: false);
    final pageMarkerPattern = RegExp(
      '\\b${RegExp.escape(abbreviation)}\\s+(\\d+)\\b',
    );
    final trailingRefPattern = RegExp(
      '\\{?\\b${RegExp.escape(abbreviation)}\\s+\\d+\\.\\d+\\b\\}?\\s*\$',
    );

    void emitPageMarker(int? page) {
      if (page == null || page == currentPage) return;
      lines.add('$abbreviation $page');
      currentPage = page;
    }

    void skipFrontMatter(String text) {
      final normalized = _normalizeWhitespace(text);
      if (normalized.isEmpty) return;
      warnings.add(
        'Skipped unreferenced front matter: ${_frontMatterSnippet(normalized)}',
      );
    }

    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final locator = match.group(1) ?? '';
      final contentEnd = index + 1 < matches.length
          ? matches[index + 1].start
          : allText.length;
      final content = _normalizeWhitespace(
        allText.substring(match.end, contentEnd),
      );
      if (content.isEmpty) continue;

      if (locator.contains('.')) {
        final refMatch = trailingRefPattern.firstMatch(content);
        final ref = refMatch == null
            ? '$abbreviation $locator'
            : _normalizeCapturedRef(refMatch.group(0)!);
        final body = refMatch == null
            ? content
            : content.substring(0, refMatch.start);
        final text = _removeInlinePageMarkers(body, abbreviation);
        if (text.isEmpty) {
          warnings.add('Skipped empty paragraph text for ref $ref');
          continue;
        }
        emitPageMarker(_pageFromRef(ref));
        lines.add(text);
        lines.add(ref);
        continue;
      }

      final page = int.tryParse(locator);
      final markerMatch = pageMarkerPattern.firstMatch(content);
      final head = _normalizeWhitespace(
        markerMatch == null ? content : content.substring(0, markerMatch.start),
      );
      final remainder = markerMatch == null
          ? ''
          : _normalizeWhitespace(content.substring(markerMatch.end));
      if (head.isNotEmpty) {
        if (_looksLikeCopiedEgwHeading(head)) {
          final heading = head.toUpperCase();
          if (heading != lastHeading) {
            lines.add(heading);
            lastHeading = heading;
            chapterHeadingCount += 1;
          }
        } else {
          skipFrontMatter(head);
        }
      }
      emitPageMarker(page);
      skipFrontMatter(remainder);
    }

    final normalizedText = lines.isEmpty ? '' : '${lines.join('\n')}\n';
    return EgwHtmlCaptureExtractionResult(
      text: normalizedText,
      detectedAbbreviation: abbreviation,
      firstRef: refs.isEmpty ? null : refs.first,
      lastRef: refs.isEmpty ? null : refs.last,
      refCount: refs.length,
      duplicateRefs: duplicateRefs,
      chapterHeadingCount: chapterHeadingCount,
      detectedTitle: title,
      detectedAuthor: prefix.author,
      warnings: List<String>.unmodifiable([
        ...warnings,
        if (duplicateRefs.isNotEmpty)
          'Duplicate refs detected: ${duplicateRefs.join(', ')}',
        if (refs.isEmpty) 'No paragraph refs were detected.',
      ]),
    );
  }
}

@immutable
class _CopiedEgwPrefix {
  const _CopiedEgwPrefix({
    required this.title,
    required this.author,
    required this.pattern,
  });

  final String title;
  final String author;
  final RegExp pattern;
}

bool _looksLikeCopiedEgwHeading(String text) {
  final normalized = _normalizeWhitespace(text);
  if (normalized.isEmpty) return false;
  if (normalized.length > 120) return false;
  return normalized.split(RegExp(r'\s+')).length <= 16;
}

String _frontMatterSnippet(String text, {int limit = 80}) {
  if (text.length <= limit) return text;
  return '${text.substring(0, limit - 1).trimRight()}…';
}

class PioneerHtmlCaptureFolderScanner {
  const PioneerHtmlCaptureFolderScanner({
    this.rootPath = kDefaultPioneerHtmlCaptureRoot,
    this.extractor = const EgwHtmlCaptureExtractor(),
    this.projectRootPath,
    this.currentDirectoryPath,
    this.knownDevScanPath = kKnownDevPioneerHtmlCaptureRoot,
    this.assetManifestKeys,
    this.assetStringLoader,
    this.preferAssetManifest = true,
    this.ignoredFolderNames = const <String>{},
  });

  final String rootPath;
  final EgwHtmlCaptureExtractor extractor;
  final String? projectRootPath;
  final String? currentDirectoryPath;
  final String? knownDevScanPath;
  final List<String>? assetManifestKeys;
  final PioneerHtmlCaptureAssetStringLoader? assetStringLoader;
  final bool preferAssetManifest;
  final Set<String> ignoredFolderNames;

  Future<List<PioneerHtmlCaptureFolderPreview>> scan({
    PioneerSourceCatalog? catalog,
  }) async {
    final result = await scanWithReport(catalog: catalog);
    return result.previews;
  }

  Future<PioneerHtmlCaptureFolderScanResult> scanWithReport({
    PioneerSourceCatalog? catalog,
  }) async {
    final currentWorkingDirectory = _currentWorkingDirectory;
    final attempts = <String>[];
    var assetKeyCount = 0;
    var scanAssetKeyCount = 0;
    var usedAssetManifest = false;
    if (preferAssetManifest) {
      final assetKeys = await _loadAssetKeys();
      usedAssetManifest = true;
      assetKeyCount = assetKeys.length;
      scanAssetKeyCount = assetKeys.where(_isScanAssetKey).length;
      attempts.add(
        'AssetManifest: $scanAssetKeyCount assets under $_normalizedAssetRoot/',
      );
      final assetPreviews = await _scanAssetKeys(assetKeys, catalog: catalog);
      if (assetPreviews.isNotEmpty) {
        return PioneerHtmlCaptureFolderScanResult(
          previews: assetPreviews,
          assetKeyCount: assetKeyCount,
          scanAssetKeyCount: scanAssetKeyCount,
          usedAssetManifest: true,
          usedFileSystemFallback: false,
          checkedRootPath: _normalizedAssetRoot,
          currentWorkingDirectory: currentWorkingDirectory,
          absolutePathChecked: _absoluteScanPath(
            rootPath,
            currentWorkingDirectory,
          ),
          fileSystemPathExists: false,
          immediateChildFolderCount: 0,
          htmlFileCount: assetPreviews.fold<int>(
            0,
            (count, preview) => count + preview.htmlFileCount,
          ),
          fallbackAttemptsTried: List<String>.unmodifiable(attempts),
        );
      }
    }

    _FileSystemCaptureScanResult? lastFileSystemResult;
    for (final candidate in _fileSystemRootCandidates(
      currentWorkingDirectory,
    )) {
      attempts.add(candidate.description);
      final result = await _scanFileSystemRoot(
        candidate.absolutePath,
        catalog: catalog,
      );
      lastFileSystemResult = result;
      if (result.previews.isNotEmpty) {
        return PioneerHtmlCaptureFolderScanResult(
          previews: result.previews,
          assetKeyCount: assetKeyCount,
          scanAssetKeyCount: scanAssetKeyCount,
          usedAssetManifest: usedAssetManifest,
          usedFileSystemFallback: true,
          checkedRootPath: usedAssetManifest ? _normalizedAssetRoot : rootPath,
          currentWorkingDirectory: currentWorkingDirectory,
          absolutePathChecked: result.absolutePath,
          fileSystemPathExists: result.exists,
          immediateChildFolderCount: result.immediateChildFolderCount,
          htmlFileCount: result.htmlFileCount,
          fallbackAttemptsTried: List<String>.unmodifiable(attempts),
          fileSystemFallbackPath: result.absolutePath,
        );
      }
    }

    final fileSystemResult =
        lastFileSystemResult ??
        await _scanFileSystemRoot(
          _absoluteScanPath(rootPath, currentWorkingDirectory),
          catalog: catalog,
        );
    return PioneerHtmlCaptureFolderScanResult(
      previews: fileSystemResult.previews,
      assetKeyCount: assetKeyCount,
      scanAssetKeyCount: scanAssetKeyCount,
      usedAssetManifest: usedAssetManifest,
      usedFileSystemFallback: true,
      checkedRootPath: usedAssetManifest ? _normalizedAssetRoot : rootPath,
      currentWorkingDirectory: currentWorkingDirectory,
      absolutePathChecked: fileSystemResult.absolutePath,
      fileSystemPathExists: fileSystemResult.exists,
      immediateChildFolderCount: fileSystemResult.immediateChildFolderCount,
      htmlFileCount: fileSystemResult.htmlFileCount,
      fallbackAttemptsTried: List<String>.unmodifiable(attempts),
      fileSystemFallbackPath: fileSystemResult.absolutePath,
    );
  }

  String get _currentWorkingDirectory =>
      _normalizeAbsolutePath(currentDirectoryPath ?? Directory.current.path);

  List<_FileSystemRootCandidate> _fileSystemRootCandidates(
    String currentWorkingDirectory,
  ) {
    final candidates = <_FileSystemRootCandidate>[];
    final seen = <String>{};

    void add(String description, String path) {
      final normalized = _normalizeAbsolutePath(path);
      if (!seen.add(normalized)) return;
      candidates.add(
        _FileSystemRootCandidate(
          description: '$description: $normalized',
          absolutePath: normalized,
        ),
      );
    }

    final explicitProjectRoot = projectRootPath;
    if (explicitProjectRoot != null && explicitProjectRoot.trim().isNotEmpty) {
      add(
        'explicit project root',
        _scanPathForProjectRoot(explicitProjectRoot),
      );
    }

    final discoveredProjectRoot = _findProjectRootFrom(currentWorkingDirectory);
    if (discoveredProjectRoot != null) {
      add(
        'walked up from $currentWorkingDirectory',
        _scanPathForProjectRoot(discoveredProjectRoot),
      );
    } else {
      add(
        'walk-up failed from $currentWorkingDirectory',
        _absoluteScanPath(rootPath, currentWorkingDirectory),
      );
    }

    final devPath = knownDevScanPath;
    if (devPath != null && devPath.trim().isNotEmpty) {
      add('known dev repo path', devPath);
    }
    return List<_FileSystemRootCandidate>.unmodifiable(candidates);
  }

  String _scanPathForProjectRoot(String projectRoot) {
    if (p.isAbsolute(rootPath)) return rootPath;
    return p.join(projectRoot, rootPath);
  }

  String? _findProjectRootFrom(String startPath) {
    var directory = Directory(startPath);
    if (!directory.existsSync()) {
      directory = Directory(p.dirname(startPath));
    }
    var current = Directory(_normalizeAbsolutePath(directory.path));
    while (true) {
      final hasPubspec = File(
        p.join(current.path, 'pubspec.yaml'),
      ).existsSync();
      final hasScans = Directory(p.join(current.path, rootPath)).existsSync();
      if (hasPubspec && hasScans) {
        return current.path;
      }
      final parent = current.parent;
      if (parent.path == current.path) return null;
      current = parent;
    }
  }

  String _absoluteScanPath(String path, String currentWorkingDirectory) {
    if (p.isAbsolute(path)) return _normalizeAbsolutePath(path);
    return _normalizeAbsolutePath(p.join(currentWorkingDirectory, path));
  }

  String _normalizeAbsolutePath(String path) {
    if (p.isAbsolute(path)) {
      return p.normalize(path);
    }
    return p.normalize(p.absolute(path));
  }

  Future<List<String>> _loadAssetKeys() async {
    final injected = assetManifestKeys;
    if (injected != null) {
      return List<String>.unmodifiable(injected);
    }
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      return manifest.listAssets()..sort();
    } catch (_) {
      // Fall through to the legacy JSON manifest used by older Flutter builds.
    }
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final decoded = json.decode(manifestJson);
      if (decoded is Map) {
        return decoded.keys.map((key) => key.toString()).toList()..sort();
      }
    } catch (_) {
      return const <String>[];
    }
    return const <String>[];
  }

  Future<String> _loadAssetString(String assetKey) {
    final loader = assetStringLoader;
    if (loader != null) {
      return loader(assetKey);
    }
    return rootBundle.loadString(assetKey);
  }

  bool _isScanAssetKey(String key) {
    final root = _normalizedAssetRoot;
    return key == root || key.startsWith('$root/');
  }

  String get _normalizedAssetRoot =>
      rootPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');

  Future<List<PioneerHtmlCaptureFolderPreview>> _scanAssetKeys(
    List<String> assetKeys, {
    PioneerSourceCatalog? catalog,
  }) async {
    final root = _normalizedAssetRoot;
    final prefix = '$root/';
    final folderKeys = <String, List<String>>{};
    for (final key in assetKeys) {
      if (!key.startsWith(prefix)) continue;
      final remainder = key.substring(prefix.length);
      final slashIndex = remainder.indexOf('/');
      if (slashIndex <= 0) continue;
      final folderName = remainder.substring(0, slashIndex);
      if (folderName.trim().isEmpty) continue;
      folderKeys.putIfAbsent(folderName, () => <String>[]).add(key);
    }

    final folderNames = folderKeys.keys.toList(growable: false)..sort();
    final previews = <PioneerHtmlCaptureFolderPreview>[];
    for (final folderName in folderNames) {
      if (_isIgnoredFolderName(folderName)) {
        continue;
      }
      final keys = folderKeys[folderName]!
          .where((key) => !_isIgnoredFile(key))
          .toList(growable: false);
      final htmlFiles = keys.where(_isHtmlFile).toList();
      final imageFiles = keys.where(_isImageFile).toList();
      htmlFiles.sort(_compareCaptureFiles);
      imageFiles.sort();

      previews.add(
        await _buildPreview(
          folderPath: '$root/$folderName',
          folderName: folderName,
          htmlFiles: htmlFiles,
          imageFiles: imageFiles,
          allFileNames: keys.map((key) => p.basename(key)).toList(),
          catalog: catalog,
          loadHtml: _loadAssetString,
          metadata: await _assetMetadata(keys, folderName: folderName),
        ),
      );
    }
    return List<PioneerHtmlCaptureFolderPreview>.unmodifiable(previews);
  }

  bool _isIgnoredFolderName(String folderName) {
    final normalized = folderName.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return ignoredFolderNames.any(
      (value) => value.trim().toLowerCase() == normalized,
    );
  }

  Future<_CaptureFolderMetadata> _assetMetadata(
    List<String> keys, {
    required String folderName,
  }) async {
    try {
      final folderPath = '$_normalizedAssetRoot/$folderName';
      final metadataKey = keys.firstWhere(
        (key) => p.basename(key) == 'metadata.json',
        orElse: () => '',
      );
      final manifestKey = keys.firstWhere(
        (key) => p.basename(key) == 'manifest.json',
        orElse: () => '',
      );
      if (metadataKey.isEmpty && manifestKey.isEmpty) {
        return const _CaptureFolderMetadata();
      }
      final folderMetadata = metadataKey.isEmpty
          ? PioneerCaptureFolderMetadata.empty()
          : PioneerCaptureFolderMetadata.fromJsonString(
              await _loadAssetString(metadataKey),
              folderPath: folderPath,
              availableFiles: keys,
            );
      final manifestMetadata = manifestKey.isEmpty
          ? PioneerCaptureFolderMetadata.empty()
          : PioneerCaptureFolderMetadata.fromManifestString(
              await _loadAssetString(manifestKey),
              folderPath: folderPath,
              availableFiles: keys,
            );
      return _CaptureFolderMetadata(
        metadata: folderMetadata.mergeWith(manifestMetadata),
      );
    } catch (_) {
      return const _CaptureFolderMetadata();
    }
  }

  Future<_FileSystemCaptureScanResult> _scanFileSystemRoot(
    String absoluteRootPath, {
    PioneerSourceCatalog? catalog,
  }) async {
    final normalizedRootPath = _normalizeAbsolutePath(absoluteRootPath);
    final root = Directory(normalizedRootPath);
    if (!await root.exists()) {
      return _FileSystemCaptureScanResult.empty(
        absolutePath: normalizedRootPath,
        exists: false,
      );
    }

    final directories = await root
        .list(followLinks: false)
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    directories.sort(
      (left, right) => p
          .basename(left.path)
          .toLowerCase()
          .compareTo(p.basename(right.path).toLowerCase()),
    );

    final previews = <PioneerHtmlCaptureFolderPreview>[];
    var htmlFileCount = 0;
    for (final directory in directories) {
      final folderName = p.basename(directory.path);
      if (_isIgnoredFolderName(folderName)) {
        continue;
      }
      final files = await directory
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .cast<File>()
          .where((file) => !_isIgnoredFile(file.path))
          .toList();
      final htmlFiles = files
          .where((file) => _isHtmlFile(file.path))
          .map((file) => file.path)
          .toList();
      htmlFileCount += htmlFiles.length;
      final imageFiles = files
          .where((file) => _isImageFile(file.path))
          .map((file) => file.path)
          .toList();
      htmlFiles.sort(_compareCaptureFiles);
      imageFiles.sort();

      final warnings = <String>[];
      if (htmlFiles.isEmpty) {
        warnings.add('No HTML files found.');
      }

      previews.add(
        await _buildPreview(
          folderPath: directory.path,
          folderName: folderName,
          htmlFiles: htmlFiles,
          imageFiles: imageFiles,
          allFileNames: files.map((file) => p.basename(file.path)).toList(),
          catalog: catalog,
          initialWarnings: warnings,
          loadHtml: (path) => File(path).readAsString(encoding: utf8),
          metadata: _folderMetadata(directory),
        ),
      );
    }

    return _FileSystemCaptureScanResult(
      previews: List<PioneerHtmlCaptureFolderPreview>.unmodifiable(previews),
      absolutePath: normalizedRootPath,
      exists: true,
      immediateChildFolderCount: directories.length,
      htmlFileCount: htmlFileCount,
    );
  }

  Future<PioneerHtmlCaptureFolderPreview> _buildPreview({
    required String folderPath,
    required String folderName,
    required List<String> htmlFiles,
    required List<String> imageFiles,
    required Future<String> Function(String path) loadHtml,
    required List<String> allFileNames,
    PioneerSourceCatalog? catalog,
    _CaptureFolderMetadata metadata = const _CaptureFolderMetadata(),
    List<String> initialWarnings = const <String>[],
  }) async {
    final warnings = <String>[...initialWarnings];
    if (htmlFiles.isEmpty) {
      warnings.add('No HTML files found.');
    }

    final extractedParts = <String>[];
    final htmlHashes = <String>[];
    EgwHtmlCaptureExtractionResult? firstExtraction;
    EgwCopiedRangeParseResult? parseResult;
    for (final htmlFile in htmlFiles) {
      final html = await loadHtml(htmlFile);
      htmlHashes.add(sha256.convert(utf8.encode(html)).toString());
      final extraction = extractor.extract(
        html,
        fallbackAbbreviation: _abbreviationFromFolder(folderName),
        fallbackTitle: metadata.metadata.title,
      );
      firstExtraction ??= extraction;
      extractedParts.add(extraction.text.trim());
      warnings.addAll(extraction.warnings);
    }

    final extractedText = extractedParts
        .where((part) => part.isNotEmpty)
        .join('\n\n');
    if (extractedText.trim().isNotEmpty) {
      parseResult = parseEgwCopiedRangeText(
        extractedText,
        workAbbreviation:
            firstExtraction?.detectedAbbreviation ??
            _abbreviationFromFolder(folderName),
      );
    }
    final parseReport = parseResult?.report;
    final sectionTitles = parseResult?.document.sections
        .map((section) => section.title.trim())
        .where((title) => title.isNotEmpty)
        .toList(growable: false);
    final metadataTitle = metadata.metadata.title;
    final metadataTitleIsPlaceholder =
        metadataTitle == null ||
        looksLikeCaptureFolderPlaceholderTitle(
          metadataTitle,
          folderCode: folderName,
          abbreviation: metadata.metadata.preferredAbbreviation,
        );
    final detectedTitle = !metadataTitleIsPlaceholder
        ? metadataTitle
        : firstExtraction?.detectedTitle ?? metadataTitle ?? folderName;
    final detectedAbbreviation =
        metadata.metadata.preferredAbbreviation ??
        firstExtraction?.detectedAbbreviation ??
        _abbreviationFromFolder(folderName);
    final catalogWork = catalog == null
        ? null
        : _findCatalogWork(
            catalog,
            title: detectedTitle,
            abbreviation: detectedAbbreviation,
            folderName: folderName,
          );
    final detectedAuthor =
        metadata.metadata.primaryContributorName ??
        catalogWork?.authorName ??
        _authorFromFolderName(folderName) ??
        firstExtraction?.detectedAuthor;
    final inferredWorkId = _inferCaptureWorkId(
      detectedAbbreviation,
      detectedAuthor,
      folderName,
    );
    final effectiveMetadata =
        metadata.metadata.workId?.trim().isNotEmpty == true
        ? metadata.metadata
        : PioneerCaptureFolderMetadata(
            title: metadata.metadata.title,
            abbreviation: metadata.metadata.abbreviation,
            displayAbbreviation: metadata.metadata.displayAbbreviation,
            workId: inferredWorkId,
            sourceType: metadata.metadata.sourceType,
            sourceSite: metadata.metadata.sourceSite,
            sourceUrl: metadata.metadata.sourceUrl,
            coverImagePath: metadata.metadata.coverImagePath,
            contributors: metadata.metadata.contributors,
          );
    if (catalogWork == null && effectiveMetadata.hasIdentity) {
      warnings.add('No matching Pioneer catalog work was found.');
    }
    if (!effectiveMetadata.hasIdentity && catalogWork != null) {
      warnings.add('Metadata needed before import.');
    }
    final duplicateRefs =
        parseReport?.duplicateRefs.length ??
        firstExtraction?.duplicateRefCount ??
        0;
    final refCount =
        parseReport?.paragraphCount ?? firstExtraction?.refCount ?? 0;
    final sourceFileHash = htmlHashes.isEmpty
        ? null
        : sha256.convert(utf8.encode(htmlHashes.join('|'))).toString();
    final validationReasons = <String>[];
    if (htmlFiles.isEmpty) {
      validationReasons.add('no HTML files found');
    }
    if (extractedText.trim().isEmpty) {
      validationReasons.add('no extracted capture text');
    }
    if (refCount <= 0) {
      validationReasons.add('no ref codes were detected');
    }
    if (!effectiveMetadata.hasIdentity && catalogWork == null) {
      validationReasons.add('missing metadata identity or catalog match');
    }
    final isValid =
        htmlFiles.isNotEmpty &&
        extractedText.trim().isNotEmpty &&
        refCount > 0 &&
        (effectiveMetadata.hasIdentity || catalogWork != null);

    return PioneerHtmlCaptureFolderPreview(
      folderPath: folderPath,
      folderName: folderName,
      metadata: effectiveMetadata,
      htmlFiles: List<String>.unmodifiable(htmlFiles),
      imageFiles: List<String>.unmodifiable(imageFiles),
      availableFileNames: List<String>.unmodifiable(
        allFileNames.isEmpty
            ? [...htmlFiles.map(p.basename), ...imageFiles.map(p.basename)]
            : allFileNames,
      ),
      sourceFileHash: sourceFileHash,
      preferredCoverImagePath:
          effectiveMetadata.coverImagePath ?? _preferredCoverImage(imageFiles),
      detectedTitle: catalogWork?.title ?? detectedTitle,
      detectedAuthor: detectedAuthor,
      detectedAbbreviation: detectedAbbreviation,
      firstRef: parseReport?.firstRef ?? firstExtraction?.firstRef,
      lastRef: parseReport?.lastRef ?? firstExtraction?.lastRef,
      refCount: refCount,
      duplicateRefCount: duplicateRefs,
      chapterHeadingCount:
          parseReport?.headingCount ??
          firstExtraction?.chapterHeadingCount ??
          0,
      firstChapterLabel: sectionTitles == null || sectionTitles.isEmpty
          ? null
          : sectionTitles.first,
      lastChapterLabel: sectionTitles == null || sectionTitles.isEmpty
          ? null
          : sectionTitles.last,
      isValid: isValid,
      warnings: List<String>.unmodifiable(warnings.toSet()),
      validationReasons: List<String>.unmodifiable(validationReasons),
      importStatus: isValid
          ? PioneerHtmlCaptureImportStatus.newImport
          : PioneerHtmlCaptureImportStatus.invalid,
      catalogWork: catalogWork,
      extractedText: extractedText.trim().isEmpty ? null : '$extractedText\n',
    );
  }
}

class _FileSystemRootCandidate {
  const _FileSystemRootCandidate({
    required this.description,
    required this.absolutePath,
  });

  final String description;
  final String absolutePath;
}

class _FileSystemCaptureScanResult {
  const _FileSystemCaptureScanResult({
    required this.previews,
    required this.absolutePath,
    required this.exists,
    required this.immediateChildFolderCount,
    required this.htmlFileCount,
  });

  factory _FileSystemCaptureScanResult.empty({
    required String absolutePath,
    required bool exists,
  }) {
    return _FileSystemCaptureScanResult(
      previews: const <PioneerHtmlCaptureFolderPreview>[],
      absolutePath: absolutePath,
      exists: exists,
      immediateChildFolderCount: 0,
      htmlFileCount: 0,
    );
  }

  final List<PioneerHtmlCaptureFolderPreview> previews;
  final String absolutePath;
  final bool exists;
  final int immediateChildFolderCount;
  final int htmlFileCount;
}

class _LeadingChapter {
  const _LeadingChapter({required this.heading, required this.remainingText});

  final String heading;
  final String remainingText;
}

class _CapturedParagraph {
  const _CapturedParagraph({required this.text, required this.ref});

  final String text;
  final String ref;
}

_LeadingChapter? _chapterHeading(String block, String abbreviation) {
  final searchBlock = block.length > 500 ? block.substring(0, 500) : block;
  final match = RegExp(
    '(Chapter|Section)\\s+(\\d+)\\s*[—-]\\s*(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\b',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(searchBlock);
  if (match == null) return null;
  final label = match.group(1) ?? 'Chapter';
  final number = match.group(2) ?? '1';
  final title = _normalizeChapterTitle(match.group(3) ?? '');
  final remainingText = _normalizeWhitespace(block.substring(match.end));
  return _LeadingChapter(
    heading:
        '${label[0].toUpperCase()}${label.substring(1).toLowerCase()} $number — $title',
    remainingText: remainingText,
  );
}

List<_CapturedParagraph> _paragraphsFromBlock(
  String block,
  String abbreviation,
) {
  final paragraphs = <_CapturedParagraph>[];
  final refPattern = _paragraphRefPattern(abbreviation);
  var cursor = 0;
  for (final match in refPattern.allMatches(block)) {
    final text = _removeInlinePageMarkers(
      block.substring(cursor, match.start),
      abbreviation,
    );
    final ref = _normalizeCapturedRef(match.group(0) ?? '');
    if (ref.isNotEmpty) {
      paragraphs.add(_CapturedParagraph(text: text, ref: ref));
    }
    cursor = match.end;
  }
  return List<_CapturedParagraph>.unmodifiable(paragraphs);
}

String _removeInlinePageMarkers(String text, String abbreviation) {
  return _normalizeWhitespace(
    text.replaceAll(
      RegExp('\\b${RegExp.escape(abbreviation)}\\s+\\d+\\b'),
      ' ',
    ),
  );
}

String? _detectAbbreviation(String text) {
  final match = RegExp(
    r'\b([A-Z][A-Z0-9_]{1,24})\s+\d+\.\d+\b',
  ).firstMatch(text);
  return match?.group(1);
}

String? _detectTitle(List<String> blocks, String abbreviation) {
  for (final block in blocks) {
    final normalized = _normalizeWhitespace(block);
    if (normalized.isEmpty) continue;
    final match = RegExp(
      '^(.+?)\\s+${RegExp.escape(abbreviation)}\\s+\\d+\\b',
    ).firstMatch(normalized);
    final title = match?.group(1)?.trim();
    if (title != null &&
        title.isNotEmpty &&
        !_looksLikeSectionOrChapterHeading(title) &&
        !_looksLikeCaptureSessionTitle(title)) {
      return title;
    }
  }
  return null;
}

bool _looksLikeSectionOrChapterHeading(String title) {
  final normalized = title.trim().toLowerCase();
  return RegExp(r'^(chapter|section)\s+\d+\b').hasMatch(normalized);
}

bool _looksLikeCaptureSessionTitle(String title) {
  final normalized = title.trim();
  if (normalized.isEmpty) return true;
  if (normalized.contains('_')) return true;
  if (RegExp(r'\b\d{4}-\d{2}-\d{2}\b').hasMatch(normalized)) return true;
  if (RegExp(r'^\w+(?:[-_]\w+)+$', caseSensitive: false).hasMatch(normalized)) {
    return true;
  }
  return false;
}

class _CaptureFolderMetadata {
  const _CaptureFolderMetadata({
    this.metadata = const PioneerCaptureFolderMetadata(),
  });

  final PioneerCaptureFolderMetadata metadata;
}

PioneerSourceWork? _findCatalogWork(
  PioneerSourceCatalog catalog, {
  required String? title,
  required String? abbreviation,
  required String folderName,
}) {
  final normalizedTitle = _stableTextKey(title ?? '');
  final normalizedFolder = _stableTextKey(folderName);
  final normalizedAbbreviation = _stableTextKey(
    abbreviation?.replaceAll(RegExp(r'_[A-Z0-9]+$'), '') ?? '',
  );

  for (final work in catalog.works) {
    if (normalizedTitle.isNotEmpty &&
        _stableTextKey(work.title) == normalizedTitle) {
      return work;
    }
  }
  for (final work in catalog.works) {
    if (normalizedAbbreviation.isNotEmpty &&
        _stableTextKey(work.abbreviation) == normalizedAbbreviation) {
      return work;
    }
  }
  for (final work in catalog.works) {
    final workTitle = _stableTextKey(work.title);
    if (workTitle.isNotEmpty &&
        (normalizedFolder.contains(workTitle) ||
            workTitle.contains(normalizedFolder))) {
      return work;
    }
  }
  return null;
}

_CaptureFolderMetadata _folderMetadata(Directory directory) {
  final metadata = PioneerCaptureFolderMetadata.fromFolder(directory);
  return _CaptureFolderMetadata(metadata: metadata);
}

String? _authorFromFolderName(String folderName) {
  final upper = folderName.toUpperCase();
  if (upper.endsWith('_ATJ')) return 'A. T. Jones';
  if (upper.endsWith('_EJW')) return 'E. J. Waggoner';
  if (upper.endsWith('_US')) return 'Uriah Smith';
  if (upper.endsWith('_JNA')) return 'J. N. Andrews';
  return null;
}

String? _preferredCoverImage(List<String> imageFiles) {
  if (imageFiles.isEmpty) return null;
  const priorityNames = <String>[
    'cover.png',
    'cover.jpg',
    'cover.jpeg',
    'cover.webp',
    'thumbnail.png',
    'thumbnail.jpg',
    'thumbnail.jpeg',
    'thumbnail.webp',
  ];
  for (final priority in priorityNames) {
    for (final image in imageFiles) {
      if (p.basename(image).toLowerCase() == priority) {
        return image;
      }
    }
  }
  return imageFiles.first;
}

int _compareCaptureFiles(String left, String right) {
  final leftName = p.basename(left).toLowerCase();
  final rightName = p.basename(right).toLowerCase();
  if (leftName == 'capture.html' && rightName != 'capture.html') return -1;
  if (rightName == 'capture.html' && leftName != 'capture.html') return 1;
  return leftName.compareTo(rightName);
}

bool _isIgnoredFile(String path) {
  final name = p.basename(path);
  return name == '.DS_Store' || name.startsWith('._');
}

bool _isHtmlFile(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension == '.html' || extension == '.htm';
}

bool _isImageFile(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.webp':
    case '.gif':
      return true;
  }
  return false;
}

String _abbreviationFromFolder(String folderName) {
  final normalized = folderName.trim();
  if (normalized.isEmpty) return normalized;

  final upper = normalized.toUpperCase();
  if (normalized == upper) {
    final leadingCode = RegExp(r'^[A-Z]{2,12}').firstMatch(upper);
    if (leadingCode != null) {
      return leadingCode.group(0)!;
    }
  }

  return '';
}

String _inferCaptureWorkId(
  String? abbreviation,
  String? authorName,
  String folderName,
) {
  final normalizedAbbreviation = abbreviation?.trim().toUpperCase() ?? '';
  if (normalizedAbbreviation.isNotEmpty &&
      normalizedAbbreviation.contains('_')) {
    return normalizedAbbreviation;
  }

  final initials = _authorInitials(authorName);
  if (normalizedAbbreviation.isNotEmpty && initials.isNotEmpty) {
    return '${normalizedAbbreviation}_$initials';
  }

  if (normalizedAbbreviation.isNotEmpty) return normalizedAbbreviation;
  return folderName.trim().isNotEmpty
      ? folderName.trim().toUpperCase()
      : 'UNKNOWN';
}

String _authorInitials(String? authorName) {
  final normalized = authorName?.trim() ?? '';
  if (normalized.isEmpty) return '';
  final parts = normalized
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  return parts.map((part) => part[0].toUpperCase()).join();
}

String _stableCaptureId(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String _stripLeadingAuthor(String text) {
  return _normalizeWhitespace(
    text.replaceFirst(
      RegExp(
        r'^(A\.\s*T\.\s*Jones|Alonzo\s+Trevier\s+Jones|E\.\s*J\.\s*Waggoner|Uriah\s+Smith)\s+',
      ),
      '',
    ),
  );
}

String _normalizeChapterTitle(String title) {
  return _normalizeWhitespace(
    title,
  ).replaceAll(RegExp(r'\s*[—-]\s*'), '—').replaceAll('—', '—').trim();
}

List<String> _duplicateRefs(List<String> refs) {
  final seen = <String>{};
  final duplicates = <String>{};
  for (final ref in refs) {
    if (!seen.add(ref)) {
      duplicates.add(ref);
    }
  }
  return List<String>.unmodifiable(duplicates.toList()..sort());
}

int? _pageFromRef(String ref) {
  final match = RegExp(r'\s+(\d+)\.\d+$').firstMatch(ref);
  return match == null ? null : int.tryParse(match.group(1)!);
}

RegExp _paragraphRefPattern(String abbreviation) {
  return RegExp(
    r'\{?\b' + RegExp.escape(abbreviation) + r'\s+\d+\.\d+\b\}?',
    caseSensitive: false,
  );
}

String _normalizeCapturedRef(String ref) {
  return _normalizeWhitespace(
    ref.replaceAll(RegExp(r'^[{\[]\s*|\s*[}\]]$'), ''),
  );
}

String _stripHtml(String html) {
  return _decodeHtmlEntities(
    html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ' '),
  );
}

bool _looksLikeHeadingText(String text) {
  final normalized = _normalizeWhitespace(text);
  if (normalized.isEmpty) return false;
  if (normalized.length > 140) return false;
  if (normalized.split(RegExp(r'\s+')).length > 18) return false;
  return true;
}

bool _looksLikeStandaloneHeadingBlock(String text) {
  final normalized = _normalizeWhitespace(text);
  if (normalized.isEmpty) return false;
  if (normalized.length > 140) return false;
  if (normalized.split(RegExp(r'\s+')).length > 18) return false;
  if (RegExp(
    r'^(Chapter|Section)\s+\d+\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }
  if (normalized == normalized.toUpperCase()) {
    return true;
  }
  return false;
}

@immutable
class _ReadableHtmlBlock {
  const _ReadableHtmlBlock({
    required this.tag,
    required this.text,
    required this.isHeadingCandidate,
  });

  final String tag;
  final String text;
  final bool isHeadingCandidate;
}

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
        final codePoint = int.tryParse(match.group(1) ?? '');
        return codePoint == null
            ? match.group(0)!
            : String.fromCharCode(codePoint);
      });
}

String _normalizeWhitespace(String text) {
  return text.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _stableTextKey(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
