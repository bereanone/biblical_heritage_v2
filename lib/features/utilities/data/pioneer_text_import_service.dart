import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/elibrary_database.dart';
import 'elibrary_folder_policy.dart';
import 'pioneer_capture_folder_metadata.dart';
import 'egw_copied_range_parser.dart';
import '../../library/data/canonical_activation.dart';
import '../../library/data/library_contributor.dart';
import '../../library/data/library_section_heuristics.dart';
import 'pioneer_html_capture_folder_scanner.dart';
import 'pioneer_source_catalog.dart';

typedef PioneerSourceBytesFetcher =
    Future<PioneerSourceDownloadResult> Function(Uri uri);
typedef PioneerImportDocumentParser =
    Future<PioneerImportDocument> Function(
      PioneerSourceWork work,
      Uint8List bytes,
    );

typedef PioneerImportProgressCallback =
    void Function(PioneerImportProgress progress);

typedef PioneerImportShouldContinue = bool Function();

enum PioneerImportSourceMethod {
  directUrl,
  userVerifiedAutomatedCapture,
  htmlCaptureFolder,
  clipboard,
  savedExport,
  copiedRange;

  String get label => switch (this) {
    PioneerImportSourceMethod.directUrl => 'direct URL',
    PioneerImportSourceMethod.userVerifiedAutomatedCapture =>
      'user-verified automated capture',
    PioneerImportSourceMethod.htmlCaptureFolder => 'HTML capture folder',
    PioneerImportSourceMethod.clipboard => 'clipboard',
    PioneerImportSourceMethod.savedExport => 'saved export',
    PioneerImportSourceMethod.copiedRange => 'copied range',
  };
}

enum PioneerSourcePathPreference {
  epub,
  textCapture,
  userSuppliedCleanedSource,
  sourceNeeded;

  String get label => switch (this) {
    PioneerSourcePathPreference.epub => 'Legacy EPUB fallback',
    PioneerSourcePathPreference.textCapture => 'Text/read capture',
    PioneerSourcePathPreference.userSuppliedCleanedSource =>
      'User-supplied cleaned source',
    PioneerSourcePathPreference.sourceNeeded => 'Source needed',
  };
}

enum PioneerExistingImportPolicy {
  skipExisting,
  overwriteExisting,
  importAsNewCopy;

  String get label => switch (this) {
    PioneerExistingImportPolicy.skipExisting => 'Skip existing',
    PioneerExistingImportPolicy.overwriteExisting => 'Overwrite existing',
    PioneerExistingImportPolicy.importAsNewCopy => 'Import as new copy',
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
  const PioneerImportDocument({required this.title, required this.sections});

  final String title;
  final List<PioneerImportSection> sections;
}

class PioneerEpubInspectionReport {
  const PioneerEpubInspectionReport({
    required this.byteCount,
    required this.isValidZip,
    required this.hasMimeType,
    required this.hasContainerXml,
    required this.opfPath,
    required this.manifestCount,
    required this.spineCount,
    required this.spineHrefs,
    required this.xhtmlHtmlEntries,
    required this.selectedContentFiles,
    required this.bodyFoundByFile,
    required this.rawTextPreviewLength,
    required this.rawTextPreview,
    required this.paragraphCandidateCount,
    required this.paragraphCountAfterFiltering,
    required this.sectionCount,
    required this.profileName,
  });

  final int byteCount;
  final bool isValidZip;
  final bool hasMimeType;
  final bool hasContainerXml;
  final String? opfPath;
  final int manifestCount;
  final int spineCount;
  final List<String> spineHrefs;
  final List<String> xhtmlHtmlEntries;
  final List<String> selectedContentFiles;
  final Map<String, bool> bodyFoundByFile;
  final int rawTextPreviewLength;
  final String rawTextPreview;
  final int paragraphCandidateCount;
  final int paragraphCountAfterFiltering;
  final int sectionCount;
  final String profileName;

  String get summaryText => [
    'byteCount=$byteCount',
    'isValidZip=$isValidZip',
    'hasMimeType=$hasMimeType',
    'hasContainerXml=$hasContainerXml',
    'opfPath=${opfPath ?? 'null'}',
    'manifestCount=$manifestCount',
    'spineCount=$spineCount',
    'sectionCount=$sectionCount',
    'paragraphCandidates=$paragraphCandidateCount',
    'paragraphs=$paragraphCountAfterFiltering',
  ].join(', ');
}

Future<PioneerEpubInspectionReport> inspectPioneerEpubBytes(
  Uint8List bytes, {
  PioneerSourceWork? work,
}) async {
  Archive archive;
  var isValidZip = true;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    isValidZip = false;
    return PioneerEpubInspectionReport(
      byteCount: bytes.length,
      isValidZip: false,
      hasMimeType: false,
      hasContainerXml: false,
      opfPath: null,
      manifestCount: 0,
      spineCount: 0,
      spineHrefs: const <String>[],
      xhtmlHtmlEntries: const <String>[],
      selectedContentFiles: const <String>[],
      bodyFoundByFile: const <String, bool>{},
      rawTextPreviewLength: 0,
      rawTextPreview: '',
      paragraphCandidateCount: 0,
      paragraphCountAfterFiltering: 0,
      sectionCount: 0,
      profileName:
          (work == null
                  ? PioneerEpubParserProfile.generic
                  : PioneerEpubParserProfile.infer(work))
              .name,
    );
  }

  final profile = work == null
      ? PioneerEpubParserProfile.generic
      : PioneerEpubParserProfile.infer(work);
  final hasMimeType = archive.findFile('mimetype') != null;
  final containerEntry = archive.findFile('META-INF/container.xml');
  final hasContainerXml = containerEntry != null;
  String? opfPath;
  var manifestCount = 0;
  var spineCount = 0;
  if (containerEntry != null) {
    final containerXml = utf8.decode(
      containerEntry.content as List<int>,
      allowMalformed: true,
    );
    final opfPathMatch = RegExp(
      r'full-path="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(containerXml);
    final rawOpfPath = opfPathMatch?.group(1);
    if (rawOpfPath != null && rawOpfPath.trim().isNotEmpty) {
      opfPath = _normalizeEpubPath(rawOpfPath);
      final opfEntry = archive.findFile(opfPath);
      if (opfEntry != null && opfEntry.isFile) {
        final opfXml = utf8.decode(
          opfEntry.content as List<int>,
          allowMalformed: true,
        );
        manifestCount = RegExp(
          r'<item\b[^>]*>',
          caseSensitive: false,
        ).allMatches(opfXml).length;
        spineCount = RegExp(
          r'<itemref\b[^>]*>',
          caseSensitive: false,
        ).allMatches(opfXml).length;
      }
    }
  }
  final packageInfo = _readEpubPackageInfo(archive);
  final selectedContentFiles = <String>[
    if (packageInfo.spineOrderedPaths.isNotEmpty)
      ...packageInfo.spineOrderedPaths,
  ];
  if (selectedContentFiles.isEmpty) {
    selectedContentFiles.addAll(
      archive.files
          .where((entry) {
            final name = p.normalize(entry.name).toLowerCase();
            return entry.isFile &&
                (name.endsWith('.xhtml') || name.endsWith('.html'));
          })
          .map((entry) => p.normalize(entry.name))
          .toList()
        ..sort(),
    );
  }

  final xhtmlHtmlEntries =
      archive.files
          .where((entry) {
            final name = p.normalize(entry.name).toLowerCase();
            return entry.isFile &&
                (name.endsWith('.xhtml') || name.endsWith('.html'));
          })
          .map((entry) => p.normalize(entry.name))
          .toList(growable: false)
        ..sort();

  final bodyFoundByFile = <String, bool>{};
  var paragraphCandidateCount = 0;
  var paragraphCountAfterFiltering = 0;
  var sectionCount = 0;
  var rawTextPreview = '';
  var rawTextPreviewLength = 0;

  for (final path in selectedContentFiles) {
    final entry = _findArchiveFileByNormalizedName(archive, path);
    if (entry == null || !entry.isFile) {
      bodyFoundByFile[path] = false;
      continue;
    }
    final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
    final body = _extractHtmlBody(raw);
    bodyFoundByFile[path] = body != null;
    final source = body ?? raw;
    final stripped = _stripHtml(source).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (rawTextPreview.isEmpty && stripped.isNotEmpty) {
      rawTextPreview = stripped.length <= 500
          ? stripped
          : stripped.substring(0, 500);
      rawTextPreviewLength = rawTextPreview.length;
    }
    final blocks = _extractHtmlBlocks(source, profile: profile);
    paragraphCandidateCount += blocks.length;
    final paragraphs = _parseHtmlSections(
      work ??
          PioneerSourceWork(
            id: 'debug',
            authorId: 'debug',
            authorName: 'debug',
            sourceFamily: 'debug',
            title: 'debug',
            abbreviation: 'DBG',
            group: 'debug',
            subgroup: 'debug',
            availability: PioneerSourceAvailability.available,
            verified: true,
            catalogImportable: true,
            sourceType: 'epub',
            sourceUrl: null,
            collectionUrl: null,
            captureUrl: null,
            readerUrl: null,
            directFileUrl: null,
            directFileType: null,
            sourceLabel: null,
            notes: null,
            sourceCandidates: const [],
          ),
      raw,
      baseHref: path,
      startingSpineIndex: 1,
      profile: profile,
    );
    sectionCount += paragraphs.length;
    paragraphCountAfterFiltering += paragraphs.fold<int>(
      0,
      (sum, section) => sum + section.paragraphs.length,
    );
  }

  return PioneerEpubInspectionReport(
    byteCount: bytes.length,
    isValidZip: isValidZip,
    hasMimeType: hasMimeType,
    hasContainerXml: hasContainerXml,
    opfPath: opfPath,
    manifestCount: manifestCount,
    spineCount: spineCount == 0 ? selectedContentFiles.length : spineCount,
    spineHrefs: List<String>.unmodifiable(selectedContentFiles),
    xhtmlHtmlEntries: List<String>.unmodifiable(xhtmlHtmlEntries),
    selectedContentFiles: List<String>.unmodifiable(selectedContentFiles),
    bodyFoundByFile: Map<String, bool>.unmodifiable(bodyFoundByFile),
    rawTextPreviewLength: rawTextPreviewLength,
    rawTextPreview: rawTextPreview,
    paragraphCandidateCount: paragraphCandidateCount,
    paragraphCountAfterFiltering: paragraphCountAfterFiltering,
    sectionCount: sectionCount,
    profileName: profile.name,
  );
}

class PioneerZipExtractionException implements Exception {
  const PioneerZipExtractionException({required this.message, this.zipEntry});

  final String message;
  final String? zipEntry;

  @override
  String toString() {
    if (zipEntry?.isNotEmpty == true) {
      return 'PioneerZipExtractionException: $message (zipEntry=$zipEntry)';
    }
    return 'PioneerZipExtractionException: $message';
  }
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

class PioneerImportQualityException implements Exception {
  const PioneerImportQualityException({required this.result});

  final PioneerEpubQualityValidationResult result;

  @override
  String toString() {
    return 'PioneerImportQualityException: ${result.reason}';
  }
}

class PioneerEpubQualityValidationResult {
  const PioneerEpubQualityValidationResult({
    required this.isValid,
    required this.reason,
    required this.detail,
    required this.textBlockCount,
    required this.meaningfulTextBlockCount,
    required this.navigationCount,
    required this.meaningfulNavigationCount,
    required this.firstBodySectionTitle,
    required this.epubAvailable,
    required this.textCaptureAvailable,
    required this.preferredImportPreference,
    this.expectedBodyPhrase,
  });

  final bool isValid;
  final String reason;
  final String detail;
  final int textBlockCount;
  final int meaningfulTextBlockCount;
  final int navigationCount;
  final int meaningfulNavigationCount;
  final String? firstBodySectionTitle;
  final bool epubAvailable;
  final bool textCaptureAvailable;
  final PioneerSourcePathPreference preferredImportPreference;
  final String? expectedBodyPhrase;

  String get summaryText => [
    reason,
    'text blocks=$textBlockCount',
    'meaningful body blocks=$meaningfulTextBlockCount',
    'navigation=$navigationCount',
    'meaningful navigation=$meaningfulNavigationCount',
    if (firstBodySectionTitle != null)
      'first body section=${firstBodySectionTitle!}',
  ].join(' • ');
}

enum PioneerEpubParserProfileKind {
  generic,
  aplibZip,
  ellenWhiteAudio,
  egwOfficial,
  pioneerPublicDomain,
}

class PioneerEpubParserProfile {
  const PioneerEpubParserProfile._({
    required this.kind,
    required this.name,
    required this.headingClassNeedles,
  });

  static const generic = PioneerEpubParserProfile._(
    kind: PioneerEpubParserProfileKind.generic,
    name: 'generic',
    headingClassNeedles: <String>[
      'heading',
      'chapter',
      'section',
      'title',
      'subtitle',
      'subhead',
      'headline',
      'chapterhead',
      'chapter-title',
      'section-title',
      'sub-title',
      'subheading',
    ],
  );

  static const aplibZip = PioneerEpubParserProfile._(
    kind: PioneerEpubParserProfileKind.aplibZip,
    name: 'aplibZip',
    headingClassNeedles: <String>[
      'heading',
      'chapter',
      'section',
      'title',
      'subtitle',
      'subhead',
      'headline',
      'chapterhead',
      'chapter-title',
      'section-title',
      'sub-title',
      'subheading',
    ],
  );

  static const ellenWhiteAudio = PioneerEpubParserProfile._(
    kind: PioneerEpubParserProfileKind.ellenWhiteAudio,
    name: 'ellenWhiteAudio',
    headingClassNeedles: <String>[
      'heading',
      'chapter',
      'section',
      'title',
      'subtitle',
      'subhead',
      'headline',
      'chapterhead',
      'chapter-title',
      'section-title',
      'sub-title',
      'subheading',
      'header-main',
    ],
  );

  static const egwOfficial = PioneerEpubParserProfile._(
    kind: PioneerEpubParserProfileKind.egwOfficial,
    name: 'egwOfficial',
    headingClassNeedles: <String>[
      'heading',
      'chapter',
      'section',
      'title',
      'subtitle',
      'subhead',
      'headline',
      'chapterhead',
      'chapter-title',
      'section-title',
      'sub-title',
      'subheading',
      'header-main',
    ],
  );

  static const pioneerPublicDomain = PioneerEpubParserProfile._(
    kind: PioneerEpubParserProfileKind.pioneerPublicDomain,
    name: 'pioneerPublicDomain',
    headingClassNeedles: <String>[
      'heading',
      'chapter',
      'section',
      'title',
      'subtitle',
      'subhead',
      'headline',
      'chapterhead',
      'chapter-title',
      'section-title',
      'sub-title',
      'subheading',
      'header-main',
    ],
  );

  final PioneerEpubParserProfileKind kind;
  final String name;
  final List<String> headingClassNeedles;

  bool get appliesPublicDomainCleanup =>
      kind == PioneerEpubParserProfileKind.pioneerPublicDomain;

  static PioneerEpubParserProfile infer(PioneerSourceWork work) {
    final sourceLabel = _normalizeText(work.sourceLabel ?? '');
    final sourceUrl = _normalizeText(work.sourceUrl ?? '');
    final sourceType = work.sourceType?.trim().toLowerCase() ?? '';
    if (_isPublicDomainPioneerEpub(work, sourceType: sourceType)) {
      return pioneerPublicDomain;
    }
    if (sourceLabel.contains('ellenwhiteaudio') ||
        sourceLabel.contains('egw audio') ||
        sourceUrl.contains('ellenwhiteaudio.org')) {
      return ellenWhiteAudio;
    }
    if (sourceLabel.contains('egw writings') ||
        sourceLabel.contains('egw official') ||
        sourceUrl.contains('egwwritings.org')) {
      return egwOfficial;
    }
    if (sourceType == 'epubzipentry' ||
        sourceLabel.contains('aplib') ||
        sourceUrl.contains('adventaudio.org')) {
      return aplibZip;
    }
    return generic;
  }
}

class PioneerPublicDomainExtractionProfile {
  const PioneerPublicDomainExtractionProfile._();

  static const Set<String> _frontMatterTitles = <String>{
    'cover',
    'contents',
    'table of contents',
    'toc',
    'copyright',
    'title page',
    'titlepage',
    'illustrations',
    'publication information',
    'source credits',
    'publisher note',
    'editor note',
    'editorial note',
    'publisher',
    'preface to the edition',
  };

  static const Set<String> _bodyStartTitles = <String>{
    'preface',
    'introduction',
    'chapter 1',
    'chapter i',
    'chapter one',
    'part 1',
    'part i',
  };

  static bool isSectionFrontMatter({
    required String title,
    required String rawText,
  }) {
    final normalizedTitle = _normalizeText(title);
    if (normalizedTitle.isEmpty) return true;
    if (_frontMatterTitles.contains(normalizedTitle)) return true;

    final normalizedText = normalizeWhitespace(rawText);
    if (normalizedText.isEmpty) return true;

    final lowerText = normalizedText.toLowerCase();
    if (lowerText.contains('adventist pioneer library')) return true;
    if (lowerText.contains('www.aplib.org')) return true;
    if (lowerText.contains('isbn:')) return true;
    if (lowerText.contains('published in the usa')) return true;
    if (lowerText.contains('originally published in')) return true;
    if (lowerText.contains('the original table of contents contained')) {
      return true;
    }
    if (lowerText.contains('support the ministry') ||
        lowerText.contains('donate') ||
        lowerText.contains('donation')) {
      return true;
    }
    if (RegExp(
      r'^©\s*\d{4}\s+adventist pioneer library$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
      r'^\+?\d[\d\s().-]{7,}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
          r'^\d{1,5}\s+[A-Za-z][A-Za-z0-9 .,\-#/&()]*$',
          caseSensitive: false,
        ).hasMatch(normalizedText) &&
        (lowerText.contains('road') ||
            lowerText.contains('street') ||
            lowerText.contains('avenue') ||
            lowerText.contains('lane') ||
            lowerText.contains('drive') ||
            lowerText.contains('highway') ||
            lowerText.contains('oregon') ||
            lowerText.contains('usa') ||
            lowerText.contains('aplib'))) {
      return true;
    }
    if (RegExp(
      r'^(january|february|march|april|may|june|july|august|september|october|november|december),\s*\d{4}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    return false;
  }

  static bool isBodyStartTitle(String title) {
    final normalizedTitle = _normalizeText(title);
    return _bodyStartTitles.contains(normalizedTitle);
  }

  static List<String> filterLeadingFrontMatterParagraphs(
    List<String> paragraphs,
  ) {
    var firstBodyParagraphIndex = 0;
    var foundBodyParagraph = false;
    for (var i = 0; i < paragraphs.length; i++) {
      final paragraph = paragraphs[i].trim();
      if (paragraph.isEmpty) continue;
      if (_looksLikeFrontMatterParagraph(paragraph)) {
        continue;
      }
      firstBodyParagraphIndex = i;
      foundBodyParagraph = true;
      break;
    }
    if (!foundBodyParagraph) {
      return const <String>[];
    }
    if (firstBodyParagraphIndex <= 0) {
      return List<String>.unmodifiable(paragraphs);
    }
    return List<String>.unmodifiable(
      paragraphs.sublist(firstBodyParagraphIndex),
    );
  }

  static bool _looksLikeFrontMatterParagraph(String text) {
    final normalizedText = normalizeWhitespace(text);
    if (normalizedText.isEmpty) return true;
    final lowerText = normalizedText.toLowerCase();
    if (lowerText.contains('adventist pioneer library')) return true;
    if (lowerText.contains('www.aplib.org')) return true;
    if (lowerText.contains('isbn:')) return true;
    if (lowerText.contains('published in the usa')) return true;
    if (lowerText.contains('originally published in')) return true;
    if (lowerText.contains('the original table of contents contained')) {
      return true;
    }
    if (RegExp(
      r'^©\s*\d{4}\s+adventist pioneer library$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
      r'^\+?\d[\d\s().-]{7,}$',
      caseSensitive: false,
    ).hasMatch(normalizedText)) {
      return true;
    }
    if (RegExp(
          r'^\d{1,5}\s+[A-Za-z][A-Za-z0-9 .,\-#/&()]*$',
          caseSensitive: false,
        ).hasMatch(normalizedText) &&
        (lowerText.contains('road') ||
            lowerText.contains('street') ||
            lowerText.contains('avenue') ||
            lowerText.contains('lane') ||
            lowerText.contains('drive') ||
            lowerText.contains('highway') ||
            lowerText.contains('oregon') ||
            lowerText.contains('usa') ||
            lowerText.contains('aplib'))) {
      return true;
    }
    return false;
  }
}

bool _isPublicDomainPioneerEpub(
  PioneerSourceWork work, {
  required String sourceType,
}) {
  const epubLikeSourceTypes = <String>{'epub', 'directepub', 'epubzipentry'};
  if (!epubLikeSourceTypes.contains(sourceType)) {
    return false;
  }

  final sourceFamily = _normalizeText(work.sourceFamily ?? '');
  final sourceLabel = _normalizeText(work.sourceLabel ?? '');
  final sourceUrl = _normalizeText(work.sourceUrl ?? '');
  return sourceFamily.contains('pioneer') ||
      sourceLabel.contains('adventist pioneer library') ||
      sourceLabel.contains('ellenwhiteaudio') ||
      sourceLabel.contains('adventaudio') ||
      sourceUrl.contains('adventaudio.org') ||
      sourceUrl.contains('ellenwhiteaudio.org');
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
  packageLineageConflict,
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
    this.epubAvailable = false,
    this.epubValidated = false,
    this.epubRejectedReason,
    this.textCaptureAvailable = false,
    this.preferredImportPreference = PioneerSourcePathPreference.sourceNeeded,
    this.qualityValidationSummary,
    this.coverImported = false,
    this.existingItemUpdated = false,
    this.createdNew = false,
    this.firstSectionLabel,
    this.lastSectionLabel,
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
  final bool epubAvailable;
  final bool epubValidated;
  final String? epubRejectedReason;
  final bool textCaptureAvailable;
  final PioneerSourcePathPreference preferredImportPreference;
  final String? qualityValidationSummary;
  final bool coverImported;
  final bool existingItemUpdated;
  final bool createdNew;
  final String? firstSectionLabel;
  final String? lastSectionLabel;

  String get title => work.title;
  String get sourceMethodLabel => sourceMethod.label;
  String get preferredImportPreferenceLabel => preferredImportPreference.label;
  int get textBlockCount => insertedTextBlocks;
  int get navigationCount => insertedNavigationItems;
  bool get isImported => status == PioneerImportWorkStatus.imported;
  bool get isSkipped => status != PioneerImportWorkStatus.imported;

  PioneerImportWorkResult copyWith({
    PioneerSourceWork? work,
    PioneerImportWorkStatus? status,
    String? stage,
    PioneerImportSourceMethod? sourceMethod,
    String? reason,
    String? libraryItemId,
    String? sourceType,
    int? insertedLibraryItems,
    int? insertedNavigationItems,
    int? insertedTextBlocks,
    bool? skippedExisting,
    String? refCodeHandlingSummary,
    String? detail,
    String? exceptionType,
    int? httpStatusCode,
    String? contentType,
    int? downloadedByteCount,
    int? parsedSectionCount,
    int? parsedParagraphCount,
    bool? requiresManualVerification,
    String? manualVerificationHint,
    bool? epubAvailable,
    bool? epubValidated,
    String? epubRejectedReason,
    bool? textCaptureAvailable,
    PioneerSourcePathPreference? preferredImportPreference,
    String? qualityValidationSummary,
    bool? coverImported,
    bool? existingItemUpdated,
    bool? createdNew,
    String? firstSectionLabel,
    String? lastSectionLabel,
  }) {
    return PioneerImportWorkResult(
      work: work ?? this.work,
      status: status ?? this.status,
      stage: stage ?? this.stage,
      sourceMethod: sourceMethod ?? this.sourceMethod,
      reason: reason ?? this.reason,
      libraryItemId: libraryItemId ?? this.libraryItemId,
      sourceType: sourceType ?? this.sourceType,
      insertedLibraryItems: insertedLibraryItems ?? this.insertedLibraryItems,
      insertedNavigationItems:
          insertedNavigationItems ?? this.insertedNavigationItems,
      insertedTextBlocks: insertedTextBlocks ?? this.insertedTextBlocks,
      skippedExisting: skippedExisting ?? this.skippedExisting,
      refCodeHandlingSummary:
          refCodeHandlingSummary ?? this.refCodeHandlingSummary,
      detail: detail ?? this.detail,
      exceptionType: exceptionType ?? this.exceptionType,
      httpStatusCode: httpStatusCode ?? this.httpStatusCode,
      contentType: contentType ?? this.contentType,
      downloadedByteCount: downloadedByteCount ?? this.downloadedByteCount,
      parsedSectionCount: parsedSectionCount ?? this.parsedSectionCount,
      parsedParagraphCount: parsedParagraphCount ?? this.parsedParagraphCount,
      requiresManualVerification:
          requiresManualVerification ?? this.requiresManualVerification,
      manualVerificationHint:
          manualVerificationHint ?? this.manualVerificationHint,
      epubAvailable: epubAvailable ?? this.epubAvailable,
      epubValidated: epubValidated ?? this.epubValidated,
      epubRejectedReason: epubRejectedReason ?? this.epubRejectedReason,
      textCaptureAvailable: textCaptureAvailable ?? this.textCaptureAvailable,
      preferredImportPreference:
          preferredImportPreference ?? this.preferredImportPreference,
      qualityValidationSummary:
          qualityValidationSummary ?? this.qualityValidationSummary,
      coverImported: coverImported ?? this.coverImported,
      existingItemUpdated: existingItemUpdated ?? this.existingItemUpdated,
      createdNew: createdNew ?? this.createdNew,
      firstSectionLabel: firstSectionLabel ?? this.firstSectionLabel,
      lastSectionLabel: lastSectionLabel ?? this.lastSectionLabel,
    );
  }
}

class _CapturedHtmlRepairAssessment {
  const _CapturedHtmlRepairAssessment({
    required this.shouldRepair,
    required this.reasons,
  });

  final bool shouldRepair;
  final List<String> reasons;
}

class PioneerExistingCapturedImportSummary {
  const PioneerExistingCapturedImportSummary({
    required this.itemIds,
    required this.textBlockCount,
    required this.navigationItemCount,
    required this.refIndexCount,
    required this.sourceTypes,
    required this.indexStatuses,
    required this.hasExistingImport,
  });

  final List<String> itemIds;
  final int textBlockCount;
  final int navigationItemCount;
  final int refIndexCount;
  final List<String> sourceTypes;
  final List<String> indexStatuses;
  final bool hasExistingImport;

  bool get hasTextBlocks => textBlockCount > 0;
  bool get hasNavigationItems => navigationItemCount > 0;

  bool get isPartialOrFailed {
    if (!hasExistingImport) return false;
    if (!hasTextBlocks || !hasNavigationItems) return true;
    return indexStatuses.any((status) {
      final normalized = status.trim().toLowerCase();
      return normalized.contains('partial') ||
          normalized.contains('failed') ||
          normalized.contains('needs_review') ||
          normalized.contains('error');
    });
  }

  bool get isVerifiedLike => hasExistingImport && !isPartialOrFailed;

  String get statusLabel {
    if (!hasExistingImport) return 'Not installed';
    if (isPartialOrFailed) return 'Existing partial import';
    return 'Existing verified import';
  }
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
      workResults
          .where(
            (result) =>
                result.status == PioneerImportWorkStatus.skippedExisting,
          )
          .length +
      workResults
          .where(
            (result) =>
                result.status == PioneerImportWorkStatus.skippedNotImportable,
          )
          .length +
      workResults
          .where(
            (result) =>
                result.status ==
                PioneerImportWorkStatus.skippedUnsupportedSource,
          )
          .length;

  int get failedCount => workResults
      .where(
        (result) =>
            result.status == PioneerImportWorkStatus.failed ||
            result.status == PioneerImportWorkStatus.packageLineageConflict,
      )
      .length;
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
    Future<void> Function(String libraryItemId)? beforeCapturedHtmlIndexWrite,
  }) : _fetchBytes = fetchBytes ?? _downloadSourceBytes,
       _parseDocument = parseDocument ?? _parseSourceDocument,
       _beforeCapturedHtmlIndexWrite = beforeCapturedHtmlIndexWrite;

  static final PioneerTextImportService instance = PioneerTextImportService();

  static const String _collectionName = 'Adventist Pioneer Library';
  static const String _folderType = 'research';
  static const String _libraryRole = 'research';
  static const String _virtualRoot = 'TextCaptures/Research/Pioneer Authors';

  final PioneerSourceBytesFetcher _fetchBytes;
  final PioneerImportDocumentParser _parseDocument;
  final Future<void> Function(String libraryItemId)?
  _beforeCapturedHtmlIndexWrite;

  Future<PioneerExistingCapturedImportSummary> inspectExistingCapturedImport(
    PioneerSourceWork work,
  ) async {
    final db = await ELibraryDatabase.instance.database;
    return _existingCanonicalCapturedImportSummary(db, work);
  }

  Future<PioneerImportBatchResult> importSelectedWorks(
    Iterable<PioneerSourceWork> selectedWorks, {
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
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
    // Cache downloaded bytes by URL so the same ZIP is fetched only once
    // across the entire batch (all APLIB works share one ZIP URL).
    final downloadCache = <String, PioneerSourceDownloadResult>{};

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
      if (existing.hasItem && !allowRepair) {
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
        final sourceCandidate = work.preferredImportCandidate;
        final sourceUrl = _candidateSourceUrl(work, sourceCandidate);
        if (sourceCandidate == null || sourceUrl == null || sourceUrl.isEmpty) {
          results.add(
            _buildSkippedNotImportableResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: PioneerImportSourceMethod.directUrl,
              reason: 'No verified importable source URL is available.',
            ),
          );
          completed += 1;
          continue;
        }

        if (sourceCandidate.sourceType == 'pdf') {
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

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'downloading',
            message: '$progressPrefix Downloading ${work.title}',
          ),
        );
        downloadResult =
            downloadCache[sourceUrl] ?? await _fetchBytes(Uri.parse(sourceUrl));
        downloadCache[sourceUrl] = downloadResult;
        final importBytes = await _resolveImportedSourceBytes(
          work: work,
          sourceCandidate: sourceCandidate,
          downloadResult: downloadResult,
        );

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'parsing',
            message: '$progressPrefix Parsing ${work.title}',
          ),
        );
        final document = await _parseDocument(work, importBytes);
        if (document.sections.isEmpty) {
          throw PioneerImportDocumentTooSparseException(
            sourceType: sourceCandidate.sourceType,
            message: 'No readable sections were found.',
            sectionsFound: 0,
            paragraphCount: 0,
          );
        }
        PioneerEpubQualityValidationResult? qualityValidation;
        if (_isEpubLikeSourceType(sourceCandidate.sourceType)) {
          qualityValidation = _validatePioneerEpubImportQuality(
            work: work,
            document: document,
          );
          if (!qualityValidation.isValid) {
            throw PioneerImportQualityException(result: qualityValidation);
          }
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
          sourceBytes: importBytes,
          downloadResult: downloadResult,
          sourceMethod: PioneerImportSourceMethod.directUrl,
          refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
          sourceUrl: sourceUrl,
          qualityValidation: qualityValidation,
        );
        results.add(result);
        if (result.status == PioneerImportWorkStatus.imported &&
            _isEpubLikeSourceType(sourceCandidate.sourceType)) {
          // Best-effort only: the flattened-text import above already
          // succeeded and must be reported as such regardless of whether
          // this step (which only adds images) succeeds.
          await _persistEpubSourceAndCanonicalize(
            db: db,
            itemId: itemId,
            epubBytes: importBytes,
          );
        }
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
            downloadedByteCount:
                downloadResult?.byteCount ??
                (error is PioneerSourceDownloadException
                    ? error.byteCount
                    : null),
            httpStatusCode:
                downloadResult?.httpStatusCode ??
                (error is PioneerSourceDownloadException
                    ? error.httpStatusCode
                    : null),
            contentType:
                downloadResult?.contentType ??
                (error is PioneerSourceDownloadException
                    ? error.contentType
                    : null),
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

  /// Persists the real EGW EPUB [epubBytes] already downloaded for [itemId]
  /// into the app-managed `ImportedPioneerEgwEpubs` folder, then runs it
  /// through [CanonicalActivation] so its images become readable via the
  /// canonical document reader (see `canonical_library_reader.dart`).
  ///
  /// This is purely additive to the flattened-text import already written by
  /// [_writeImportedWork]: `library_text_blocks` (search/snippets) is
  /// untouched either way, and this method never throws — a failure here
  /// (missing Library Root, canonicalization rejecting the EPUB, disk
  /// error) must never affect the outcome of the text import that already
  /// succeeded. The `library_items` row for [itemId] is only updated to
  /// point at the persisted EPUB (`file_format`/`source_type`/
  /// `relative_path`) after canonicalization actually produces a complete,
  /// activated generation — so a failure here leaves the item exactly as it
  /// was: readable via the existing flattened-text/legacy reader.
  Future<void> _persistEpubSourceAndCanonicalize({
    required Database db,
    required String itemId,
    required Uint8List epubBytes,
  }) async {
    try {
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath())
              ?.trim();
      if (rootPath == null || rootPath.isEmpty) return;

      final sanitizedId = itemId
          .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
          .trim();
      final fileName = '${sanitizedId.isEmpty ? 'egw_book' : sanitizedId}.epub';
      final relativePath = p.join(
        ELibraryFolderPolicy.pioneerEgwEpubSourceRelativeFolder,
        fileName,
      );
      final destination = File(
        await LibraryRootService.instance.resolveRelativePath(
          relativePath: relativePath,
          rootPath: rootPath,
        ),
      );
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(epubBytes, flush: true);

      final outcome = await CanonicalActivation.activate(
        db: db,
        libraryItemId: itemId,
        source: destination,
        applyStoragePolicy: true,
        rootPath: rootPath,
      );
      if (!outcome.isReady) return;

      final stat = await destination.exists() ? await destination.stat() : null;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.update(
        'library_items',
        <String, Object?>{
          'file_format': 'epub',
          'source_type': 'pioneer_egw_epub_source',
          'relative_path': relativePath,
          'file_name': fileName,
          'mime_type': 'application/epub+zip',
          if (stat != null) 'file_size': stat.size,
          if (stat != null)
            'modified_at': stat.modified.toUtc().toIso8601String(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[itemId],
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[PioneerImport] Image-source canonicalization skipped for '
        '$itemId: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<PioneerImportWorkResult> importLocalEpubFile({
    required PioneerSourceWork work,
    required String filePath,
    bool overwriteExisting = true,
  }) async {
    final sourceFile = File(filePath.trim());
    if (!await sourceFile.exists()) {
      throw StateError('The selected EPUB is no longer available.');
    }
    if (p.extension(sourceFile.path).toLowerCase() != '.epub') {
      throw const FormatException('Choose a Pioneer EPUB file.');
    }

    final bytes = await sourceFile.readAsBytes();
    final inspection = await inspectPioneerEpubBytes(bytes, work: work);
    if (!inspection.isValidZip ||
        !inspection.hasContainerXml ||
        inspection.sectionCount == 0 ||
        inspection.paragraphCountAfterFiltering == 0) {
      throw PioneerImportDocumentTooSparseException(
        sourceType: 'epub',
        message: 'The selected EPUB has no readable book content.',
        sectionsFound: inspection.sectionCount,
        paragraphCount: inspection.paragraphCountAfterFiltering,
      );
    }

    final document = await _parseDocument(work, bytes);
    final qualityValidation = _validatePioneerEpubImportQuality(
      work: work,
      document: document,
    );
    if (!qualityValidation.isValid) {
      throw PioneerImportQualityException(result: qualityValidation);
    }

    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final coverPath = await cachePioneerCaptureCoverPath(
      coverPath: work.coverImagePath,
      itemId: work.stableLibraryItemId,
    );
    final downloadResult = PioneerSourceDownloadResult(
      bytes: bytes,
      httpStatusCode: null,
      contentType: 'application/epub+zip',
      resolvedUri: sourceFile.uri,
    );
    return _writeImportedWork(
      db: db,
      deviceId: deviceId,
      work: work,
      libraryItemId: work.stableLibraryItemId,
      replaceCanonicalSiblings: overwriteExisting,
      document: document,
      sourceBytes: bytes,
      downloadResult: downloadResult,
      sourceMethod: PioneerImportSourceMethod.directUrl,
      refCodeHandlingSummary:
          'Local EPUB spine and chapter structure preserved during indexing.',
      sourceUrl: sourceFile.uri.toString(),
      sourceType: 'epub',
      sourceSite: 'local_cloud_file',
      relativePath: _buildVirtualRelativePath(work),
      coverPath: coverPath,
      qualityValidation: qualityValidation,
    );
  }

  Future<PioneerImportBatchResult> importFromCapturedText(
    Iterable<PioneerCapturedTextSource> capturedSources, {
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) async {
    final effectiveExistingImportPolicy = allowRepair
        ? PioneerExistingImportPolicy.overwriteExisting
        : existingImportPolicy;
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
      final itemId =
          effectiveExistingImportPolicy ==
              PioneerExistingImportPolicy.importAsNewCopy
          ? _newCopyLibraryItemId(work)
          : work.stableLibraryItemId;
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

      final existing = await _existingCanonicalCapturedImportSummary(db, work);
      if (existing.hasExistingImport &&
          effectiveExistingImportPolicy ==
              PioneerExistingImportPolicy.skipExisting) {
        results.add(
          _buildSkippedExistingResult(
            work: work,
            libraryItemId: existing.itemIds.first,
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
          sourceUrl: source.sourceUrl,
          sourceLabel: source.sourceLabel,
        );
        final downloadResult = PioneerSourceDownloadResult(
          bytes: Uint8List.fromList(utf8.encode(text)),
          httpStatusCode: null,
          contentType: _looksLikeHtmlMarkup(text) ? 'text/html' : 'text/plain',
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
          libraryItemId: itemId,
          replaceCanonicalSiblings:
              effectiveExistingImportPolicy ==
              PioneerExistingImportPolicy.overwriteExisting,
          document: document,
          sourceBytes: downloadResult.bytes,
          downloadResult: downloadResult,
          sourceMethod: source.sourceMethod,
          refCodeHandlingSummary:
              source.refCodeHandlingSummary ?? _refCodeHandlingSummary(text),
          sourceUrl: source.sourceUrl,
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
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
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
      allowRepair: allowRepair,
      existingImportPolicy: existingImportPolicy,
    );
  }

  Future<PioneerImportBatchResult> importFromCapturedHtml({
    required PioneerSourceWork work,
    required String html,
    String? sourceUrl,
    String? sourceLabel,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
  }) async {
    return importFromCapturedText(
      [
        PioneerCapturedTextSource(
          work: work,
          sourceMethod: PioneerImportSourceMethod.userVerifiedAutomatedCapture,
          text: html,
          sourceUrl: sourceUrl,
          sourceLabel: sourceLabel,
          refCodeHandlingSummary: _refCodeHandlingSummary(html),
        ),
      ],
      onProgress: onProgress,
      shouldContinue: shouldContinue,
      allowRepair: allowRepair,
      existingImportPolicy: existingImportPolicy,
    );
  }

  Future<PioneerImportBatchResult> importFromParsedCapturedHtml({
    required PioneerSourceWork work,
    required PioneerImportDocument document,
    required Uint8List sourceBytes,
    String? sourceUrl,
    String? sourceLabel,
    String? sourceType,
    String? sourceSite,
    String? relativePath,
    String? coverPath,
    List<ImportContributorSpec>? contributors,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    String? indexStatus,
    String? indexError,
  }) async {
    final effectiveExistingImportPolicy = allowRepair
        ? PioneerExistingImportPolicy.overwriteExisting
        : existingImportPolicy;
    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final itemId =
        effectiveExistingImportPolicy ==
            PioneerExistingImportPolicy.importAsNewCopy
        ? _newCopyLibraryItemId(work)
        : work.stableLibraryItemId;

    if (shouldContinue != null && !shouldContinue()) {
      return PioneerImportBatchResult(
        workResults: const [],
        wasCancelled: true,
      );
    }

    final existing = await _existingImportSummary(db, itemId);
    debugPrint(
      'CaptureClipper write check: itemId=$itemId, existing=${existing.hasItem}, '
      'nav=${existing.hasNavigationItems}, text=${existing.hasTextBlocks}, '
      'policy=${effectiveExistingImportPolicy.label}',
    );
    if (existing.hasItem &&
        effectiveExistingImportPolicy ==
            PioneerExistingImportPolicy.skipExisting) {
      debugPrint('CaptureClipper write check: skipping existing item $itemId.');
      return PioneerImportBatchResult(
        workResults: [
          _buildSkippedExistingResult(
            work: work,
            libraryItemId: itemId,
            sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
            refCodeHandlingSummary:
                'Captured HTML refs are generated from headings and paragraphs.',
          ),
        ],
      );
    }

    onProgress?.call(
      PioneerImportProgress(
        completedCount: 0,
        totalCount: 1,
        workTitle: work.title,
        stage: 'writing',
        message: 'Writing ${work.title}',
      ),
    );

    final downloadResult = PioneerSourceDownloadResult(
      bytes: sourceBytes,
      httpStatusCode: null,
      contentType:
          _looksLikeHtmlMarkup(utf8.decode(sourceBytes, allowMalformed: true))
          ? 'text/html'
          : 'text/plain',
      resolvedUri: sourceUrl == null ? null : Uri.tryParse(sourceUrl),
    );

    final result = await _writeImportedWork(
      db: db,
      deviceId: deviceId,
      work: work,
      libraryItemId: itemId,
      replaceCanonicalSiblings:
          effectiveExistingImportPolicy ==
          PioneerExistingImportPolicy.overwriteExisting,
      document: document,
      sourceBytes: sourceBytes,
      downloadResult: downloadResult,
      sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
      refCodeHandlingSummary:
          'Captured HTML refs are generated from headings and paragraphs.',
      sourceUrl: sourceUrl,
      sourceType: sourceType,
      sourceSite: sourceSite,
      relativePath: relativePath,
      coverPath: await cachePioneerCaptureCoverPath(
        coverPath: coverPath,
        itemId: itemId,
      ),
      contributors: contributors,
      indexStatus: indexStatus,
      indexError: indexError,
    );
    return PioneerImportBatchResult(workResults: [result]);
  }

  Future<PioneerImportBatchResult> importFromSavedExport({
    required PioneerSourceWork work,
    required String filePath,
    String? sourceUrl,
    String? sourceLabel,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    bool allowRepair = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
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
      allowRepair: allowRepair,
      existingImportPolicy: existingImportPolicy,
    );
  }

  Future<PioneerImportBatchResult> importFromCopiedRange({
    required PioneerSourceWork work,
    required String text,
    String? sourceUrl,
    String? sourceLabel,
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      return PioneerImportBatchResult(
        workResults: [
          _buildSkippedNotImportableResult(
            work: work,
            libraryItemId: work.stableLibraryItemId,
            sourceMethod: PioneerImportSourceMethod.copiedRange,
            reason: 'No copied EGW text was supplied.',
          ),
        ],
      );
    }

    onProgress?.call(
      PioneerImportProgress(
        completedCount: 0,
        totalCount: 1,
        workTitle: work.title,
        stage: 'parsing',
        message: 'Parsing copied range for ${work.title}',
      ),
    );

    final parseResult = parseEgwCopiedRangeText(
      normalizedText,
      workAbbreviation: work.abbreviation.trim().isNotEmpty
          ? work.abbreviation.trim()
          : 'DAR',
    );
    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final result = await _writeCopiedRangeImportedWork(
      db: db,
      deviceId: deviceId,
      work: work,
      parseResult: parseResult,
      sourceText: normalizedText,
      sourceMethod: PioneerImportSourceMethod.copiedRange,
      sourceUrl: sourceUrl,
      sourceLabel: sourceLabel,
      shouldContinue: shouldContinue,
    );
    return PioneerImportBatchResult(workResults: [result]);
  }

  Future<PioneerImportBatchResult> importHtmlCaptureFolders(
    Iterable<PioneerHtmlCaptureFolderPreview> previews, {
    PioneerImportProgressCallback? onProgress,
    PioneerImportShouldContinue? shouldContinue,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    bool forceReindex = false,
  }) async {
    final selectedPreviews = <String, PioneerHtmlCaptureFolderPreview>{};
    for (final preview in previews) {
      if (preview.folderPath.trim().isEmpty) continue;
      selectedPreviews[preview.folderPath] = preview;
    }

    final db = await ELibraryDatabase.instance.database;
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final results = <PioneerImportWorkResult>[];
    final total = selectedPreviews.length;
    var completed = 0;

    for (final preview in selectedPreviews.values) {
      final work = preview.bestEffortWork;
      final fallbackItemId = work.stableLibraryItemId;
      final sourceWorkId = preview.metadata.workId?.trim() ?? '';
      final sourcePackageId = preview.metadata.packageId?.trim() ?? '';
      final isSchema2Package =
          (preview.metadata.schemaVersion ?? 1) >= 2 &&
          sourceWorkId.isNotEmpty &&
          sourcePackageId.isNotEmpty;
      if (shouldContinue != null && !shouldContinue()) {
        return PioneerImportBatchResult(
          workResults: results,
          wasCancelled: true,
        );
      }

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

      String? existingCaptureItemId;
      if (isSchema2Package) {
        final lineageRows = await db.query(
          'library_items',
          columns: const ['id', 'source_work_id', 'source_package_id'],
          where: '''
            deleted_at IS NULL AND (
              LOWER(COALESCE(source_work_id, '')) = ? OR id = ?
            )
          ''',
          whereArgs: [sourceWorkId.toLowerCase(), work.stableLibraryItemId],
        );
        final differentLineage = lineageRows
            .where((row) {
              final stored = row['source_package_id']?.toString().trim() ?? '';
              return stored.isNotEmpty &&
                  stored.toLowerCase() != sourcePackageId.toLowerCase();
            })
            .toList(growable: false);
        if (lineageRows.length > 1 || differentLineage.isNotEmpty) {
          results.add(
            PioneerImportWorkResult(
              work: work,
              status: PioneerImportWorkStatus.packageLineageConflict,
              stage: 'package-lineage-conflict',
              sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
              reason:
                  'Package lineage conflict: workId "$sourceWorkId" is already associated with a different packageId. No local or source content was changed.',
              libraryItemId: lineageRows.isEmpty
                  ? fallbackItemId
                  : lineageRows.first['id']?.toString() ?? fallbackItemId,
              sourceType: 'egw_html_capture',
              insertedLibraryItems: 0,
              insertedNavigationItems: 0,
              insertedTextBlocks: 0,
              skippedExisting: false,
              refCodeHandlingSummary: 'Import rejected before database writes.',
              detail:
                  'Incoming packageId=$sourcePackageId; stored packageId=${differentLineage.isEmpty ? '(ambiguous rows)' : differentLineage.first['source_package_id']}.',
              exceptionType: 'PioneerPackageLineageConflict',
              httpStatusCode: null,
              contentType: null,
              downloadedByteCount: null,
              parsedSectionCount: null,
              parsedParagraphCount: null,
              requiresManualVerification: true,
              manualVerificationHint:
                  'Verify the CaptureClipper package lineage before importing this work.',
            ),
          );
          completed += 1;
          continue;
        }
        if (lineageRows.length == 1) {
          existingCaptureItemId = lineageRows.single['id']?.toString().trim();
        }
      } else {
        existingCaptureItemId = await _existingCapturedHtmlImportItemId(
          db,
          work,
          folderName: preview.folderName,
          sourceFileHash: preview.sourceFileHash,
          sourceUrl: preview.metadata.sourceUrl,
        );
      }
      String? existingCaptureItemHash;
      if (existingCaptureItemId != null) {
        final existingRows = await db.query(
          'library_items',
          columns: const ['file_hash'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [existingCaptureItemId],
          limit: 1,
        );
        if (existingRows.isNotEmpty) {
          existingCaptureItemHash = existingRows.first['file_hash']
              ?.toString()
              .trim();
        }
      }
      final currentSourceHash = preview.sourceFileHash?.trim() ?? '';
      final sourceChanged =
          existingCaptureItemHash != null &&
          currentSourceHash.isNotEmpty &&
          existingCaptureItemHash.isNotEmpty &&
          existingCaptureItemHash.toLowerCase() !=
              currentSourceHash.toLowerCase();
      final effectiveExistingImportPolicy =
          forceReindex ||
              (sourceChanged &&
                  existingImportPolicy ==
                      PioneerExistingImportPolicy.skipExisting)
          ? PioneerExistingImportPolicy.overwriteExisting
          : existingImportPolicy;
      debugPrint(
        'CaptureClipper import candidate: folder=${preview.folderName}, '
        'path=${preview.folderPath}, title=${work.title}, '
        'author=${work.authorName}, existingItem=${existingCaptureItemId ?? '(none)'}, '
        'policy=${effectiveExistingImportPolicy.label}, '
        'sourceChanged=$sourceChanged',
      );
      if (existingCaptureItemId != null) {
        await _softDeleteMatchingCapturedHtmlDuplicateItems(
          db,
          keepItemId: existingCaptureItemId,
          folderName: preview.folderName,
        );
      }
      if (!preview.isValid) {
        _logInvalidCapturedHtmlPreview(
          preview: preview,
          existingCaptureItemId: existingCaptureItemId,
        );
      }
      final itemId =
          existingCaptureItemId ??
          (existingImportPolicy == PioneerExistingImportPolicy.importAsNewCopy
              ? _newCopyLibraryItemId(work)
              : work.stableLibraryItemId);

      if (!preview.isValid && existingCaptureItemId == null) {
        results.add(
          _buildSkippedNotImportableResult(
            work: work,
            libraryItemId: fallbackItemId,
            sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
            reason: preview.validationReasons.isEmpty
                ? 'Capture folder is not importable.'
                : 'Capture folder is not importable: ${preview.validationReasons.join('; ')}.',
          ),
        );
        completed += 1;
        continue;
      }

      try {
        final sourceText = preview.extractedText?.trim() ?? '';
        if (sourceText.isEmpty && preview.isValid) {
          results.add(
            _buildSkippedNotImportableResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
              reason: 'No extracted capture text was available.',
            ),
          );
          completed += 1;
          continue;
        }

        final canUseSourceRepair = sourceText.isNotEmpty;
        final parseResult = canUseSourceRepair
            ? parseEgwCopiedRangeText(
                sourceText,
                workAbbreviation:
                    preview.detectedAbbreviation?.trim().isNotEmpty == true
                    ? preview.detectedAbbreviation!.trim()
                    : work.abbreviation,
              )
            : null;
        final existing = await _existingImportSummary(db, itemId);
        final repairAssessment = existing.hasItem && parseResult != null
            ? await _capturedHtmlRepairAssessment(
                db: db,
                itemId: itemId,
                work: work,
                preview: preview,
                parseResult: parseResult,
              )
            : const _CapturedHtmlRepairAssessment(
                shouldRepair: false,
                reasons: <String>[],
              );
        final shouldRepairExisting =
            existing.hasItem &&
            (effectiveExistingImportPolicy ==
                    PioneerExistingImportPolicy.skipExisting ||
                effectiveExistingImportPolicy ==
                    PioneerExistingImportPolicy.overwriteExisting) &&
            (forceReindex ||
                (parseResult != null ? repairAssessment.shouldRepair : true));
        if (existing.hasItem &&
            effectiveExistingImportPolicy ==
                PioneerExistingImportPolicy.skipExisting &&
            !shouldRepairExisting) {
          results.add(
            _buildSkippedExistingResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
              refCodeHandlingSummary:
                  'HTML capture refs preserved in source; import skipped.',
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

        onProgress?.call(
          PioneerImportProgress(
            completedCount: completed,
            totalCount: total,
            workTitle: work.title,
            stage: 'writing',
            message: '$progressPrefix Writing ${work.title}',
          ),
        );
        final metaContributors = _readCaptureMetadataContributors(
          preview.folderPath,
        );
        final effectiveImportPolicy = shouldRepairExisting
            ? PioneerExistingImportPolicy.overwriteExisting
            : effectiveExistingImportPolicy;
        if (parseResult != null &&
            !existing.hasItem &&
            (parseResult.document.sections.isEmpty ||
                parseResult.report.paragraphCount == 0 ||
                parseResult.report.firstRef == null)) {
          results.add(
            _buildSkippedNotImportableResult(
              work: work,
              libraryItemId: itemId,
              sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
              reason:
                  'Could not detect clean chapters and referenced paragraphs '
                  'in the captured HTML; the source folder was left in place.',
            ),
          );
          completed += 1;
          continue;
        }
        if (parseResult != null) {
          final result = await _writeCopiedRangeImportedWork(
            db: db,
            deviceId: deviceId,
            work: work,
            libraryItemId: itemId,
            fileHashOverride: preview.sourceFileHash,
            sourceWorkId: sourceWorkId.isEmpty ? null : sourceWorkId,
            sourcePackageId: sourcePackageId.isEmpty ? null : sourcePackageId,
            parseResult: parseResult,
            sourceText: sourceText,
            sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
            sourceType: 'egw_html_capture',
            sourceSite: preview.metadata.sourceSite ?? 'egwwritings.org',
            sourceUrl: p.relative(preview.htmlFiles.first),
            sourceLabel: preview.folderName,
            coverPath: await cachePioneerCaptureCoverPath(
              coverPath: preview.preferredCoverImagePath,
              itemId: itemId,
            ),
            relativePath: _buildHtmlCaptureRelativePath(
              work,
              preview.htmlFiles.first,
            ),
            contentType: 'text/html',
            shouldContinue: shouldContinue,
            contributors: metaContributors ?? _metadataContributors(preview),
            forceReindex: forceReindex,
            replaceCanonicalSiblings:
                effectiveImportPolicy ==
                PioneerExistingImportPolicy.overwriteExisting,
          );
          results.add(
            shouldRepairExisting && repairAssessment.reasons.isNotEmpty
                ? result.copyWith(
                    detail:
                        '${result.detail ?? ''}'
                        '${result.detail == null || result.detail!.isEmpty ? '' : ' '}'
                        'Repaired existing item: ${repairAssessment.reasons.join(', ')}.',
                    reason: 'Repaired existing CaptureClipper item in place.',
                  )
                : result,
          );
        } else {
          final repaired = await _repairBrokenCapturedHtmlItemInPlace(
            db: db,
            deviceId: deviceId,
            itemId: itemId,
            preview: preview,
            work: work,
            shouldContinue: shouldContinue,
          );
          results.add(repaired);
        }
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
            sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
            refCodeHandlingSummary:
                'HTML capture refs were parsed from staged files.',
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

  Future<_CapturedHtmlRepairAssessment> _capturedHtmlRepairAssessment({
    required Database db,
    required String itemId,
    required PioneerSourceWork work,
    required PioneerHtmlCaptureFolderPreview preview,
    required EgwCopiedRangeParseResult parseResult,
  }) async {
    final repairWork = preview.bestEffortWork;
    final itemRows = await db.query(
      'library_items',
      columns: const ['title', 'author', 'cover_path'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    if (itemRows.isEmpty) {
      return const _CapturedHtmlRepairAssessment(
        shouldRepair: false,
        reasons: <String>[],
      );
    }

    final itemRow = itemRows.first;
    final reasons = <String>[];
    final storedTitle = itemRow['title']?.toString().trim() ?? '';
    final storedAuthor = itemRow['author']?.toString().trim() ?? '';
    final storedCoverPath = itemRow['cover_path']?.toString().trim() ?? '';
    final expectedTitle = repairWork.title.trim();
    final expectedAuthor = repairWork.authorName.trim();
    final expectedCoverPath =
        repairWork.cachedCoverPath?.trim().isNotEmpty == true
        ? repairWork.cachedCoverPath!.trim()
        : preview.preferredCoverImagePath?.trim() ?? '';

    if (_looksLikeBadCapturedHtmlTitle(storedTitle) &&
        expectedTitle.isNotEmpty) {
      reasons.add('title');
    }
    if (_needsCapturedHtmlAuthorRepair(storedAuthor, expectedAuthor)) {
      reasons.add('author');
    }
    if (_needsCapturedHtmlCoverRepair(storedCoverPath, expectedCoverPath)) {
      reasons.add('cover');
    }

    final navigationRows = await db.query(
      'library_navigation_items',
      columns: const ['label'],
      where: 'library_item_id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      orderBy: 'sort_order ASC',
      limit: 1,
    );
    final firstStoredHeading = navigationRows.isEmpty
        ? ''
        : navigationRows.first['label']?.toString().trim() ?? '';
    final expectedFirstHeading = preview.firstChapterLabel?.trim() ?? '';
    if (_needsCapturedHtmlHeadingRepair(
      storedHeading: firstStoredHeading,
      expectedHeading: expectedFirstHeading,
    )) {
      reasons.add('heading');
    }

    final textRows = await db.query(
      'library_text_blocks',
      columns: const ['plain_text'],
      where: 'library_item_id = ?',
      whereArgs: [itemId],
      orderBy: 'paragraph_index ASC',
      limit: 1,
    );
    final firstStoredParagraph = textRows.isEmpty
        ? ''
        : textRows.first['plain_text']?.toString().trim() ?? '';
    final expectedFirstParagraph = _firstParagraphText(parseResult.document);
    if (_needsCapturedHtmlParagraphRepair(
      storedParagraph: firstStoredParagraph,
      storedHeading: firstStoredHeading,
      expectedHeading: expectedFirstHeading,
      expectedParagraph: expectedFirstParagraph,
    )) {
      reasons.add('body');
    }

    final zeroBodyLeafRows = await db.rawQuery(
      '''
      SELECT n.label
      FROM library_navigation_items n
      LEFT JOIN library_text_blocks b
        ON b.library_item_id = n.library_item_id
       AND LOWER(b.epub_href) = LOWER(n.href)
      WHERE n.library_item_id = ?
        AND n.deleted_at IS NULL
      GROUP BY n.id
      HAVING COUNT(b.id) = 0
      ''',
      [itemId],
    );
    final hasRedundantZeroBodyLeaf = zeroBodyLeafRows.any((row) {
      final label = row['label']?.toString().trim() ?? '';
      return !RegExp(
        r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
        caseSensitive: false,
      ).hasMatch(label);
    });
    if (hasRedundantZeroBodyLeaf) {
      reasons.add('navigation');
    }

    final refCount = _firstCount(
      await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM elibrary_ref_index WHERE library_item_id = ?',
        [itemId],
      ),
    );
    final expectedRefCount =
        parseResult.report.paragraphCount +
        parseResult.report.pageNumbers.length;
    if (refCount == 0 || refCount != expectedRefCount) {
      reasons.add('refs');
    }

    return _CapturedHtmlRepairAssessment(
      shouldRepair: reasons.isNotEmpty,
      reasons: List<String>.unmodifiable(reasons),
    );
  }

  void _logInvalidCapturedHtmlPreview({
    required PioneerHtmlCaptureFolderPreview preview,
    required String? existingCaptureItemId,
  }) {
    final existingLabel = existingCaptureItemId?.trim().isNotEmpty == true
        ? existingCaptureItemId!
        : '(none)';
    debugPrint(
      'CaptureClipper invalid candidate folder: path=${preview.folderPath}, '
      'folder=${preview.folderName}, files=${preview.availableFileNames.join(', ')}, '
      'expected=html + metadata.json/manifest.json + optional cover image, '
      'rule=${preview.validationReasons.join('; ')}, '
      'existingItem=$existingLabel',
    );
  }

  Future<PioneerImportWorkResult> _repairBrokenCapturedHtmlItemInPlace({
    required Database db,
    required String deviceId,
    required String itemId,
    required PioneerHtmlCaptureFolderPreview preview,
    required PioneerSourceWork work,
    PioneerImportShouldContinue? shouldContinue,
  }) async {
    if (shouldContinue != null && !shouldContinue()) {
      return _buildSkippedNotImportableResult(
        work: work,
        libraryItemId: itemId,
        sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
        reason: 'CaptureClipper repair was cancelled.',
      );
    }

    final itemRows = await db.query(
      'library_items',
      columns: const ['id', 'title', 'author', 'cover_path', 'updated_at'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    if (itemRows.isEmpty) {
      return _buildFailedResult(
        work: work,
        libraryItemId: itemId,
        error: StateError('Existing CaptureClipper item not found.'),
        stage: 'repairing',
        sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
        refCodeHandlingSummary: 'Repair could not locate the existing item.',
      );
    }

    final existingRow = itemRows.first;
    final updates = <String, Object?>{};
    final now = _utcNow();
    final repairWork = preview.bestEffortWork;
    final existingTitle = existingRow['title']?.toString().trim() ?? '';
    final existingAuthor = existingRow['author']?.toString().trim() ?? '';
    final existingCoverPath =
        existingRow['cover_path']?.toString().trim() ?? '';

    if (_needsCapturedHtmlTitleRepair(existingTitle, repairWork.title)) {
      updates['title'] = repairWork.title.trim();
    }
    if (_needsCapturedHtmlAuthorRepair(existingAuthor, repairWork.authorName)) {
      updates['author'] = repairWork.authorName.trim();
    }

    final preferredCoverPath = preview.preferredCoverImagePath?.trim() ?? '';
    if (preferredCoverPath.isNotEmpty) {
      final repairedCoverPath = await cachePioneerCaptureCoverPath(
        coverPath: preferredCoverPath,
        itemId: itemId,
      );
      if (repairedCoverPath != null && repairedCoverPath.trim().isNotEmpty) {
        updates['cover_path'] = repairedCoverPath;
      }
    } else if (existingCoverPath.trim().isEmpty) {
      // Leave the placeholder in place, but record the reason for the manual repair log.
      debugPrint(
        'CaptureClipper item $itemId could not repair cover because no cover file was available.',
      );
    }

    if (updates.isEmpty) {
      return _buildSkippedExistingResult(
        work: work,
        libraryItemId: itemId,
        sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
        refCodeHandlingSummary:
            'CaptureClipper item was already as repaired as possible from stored rows.',
      );
    }

    updates['updated_at'] = now;
    updates['device_id'] = deviceId;
    await db.update(
      'library_items',
      updates,
      where: 'id = ?',
      whereArgs: [itemId],
    );

    return PioneerImportWorkResult(
      work: work,
      status: PioneerImportWorkStatus.imported,
      stage: 'repaired-existing',
      sourceMethod: PioneerImportSourceMethod.htmlCaptureFolder,
      reason: 'Repaired existing CaptureClipper item in place.',
      libraryItemId: itemId,
      sourceType: 'egw_html_capture',
      insertedLibraryItems: 0,
      insertedNavigationItems: 0,
      insertedTextBlocks: 0,
      skippedExisting: false,
      refCodeHandlingSummary:
          'Repaired stored item rows without reimporting the source folder.',
      detail: 'Updated stored title/author/cover metadata where possible.',
      exceptionType: null,
      httpStatusCode: null,
      contentType: null,
      downloadedByteCount: null,
      parsedSectionCount: null,
      parsedParagraphCount: null,
      requiresManualVerification: false,
      manualVerificationHint: null,
      epubAvailable: work.epubAvailable,
      epubValidated: false,
      epubRejectedReason: null,
      textCaptureAvailable: work.textCaptureAvailable,
      preferredImportPreference:
          PioneerSourcePathPreference.userSuppliedCleanedSource,
      qualityValidationSummary: null,
      coverImported: updates.containsKey('cover_path'),
      existingItemUpdated: true,
      createdNew: false,
      firstSectionLabel: preview.firstChapterLabel,
      lastSectionLabel: preview.lastChapterLabel,
    );
  }

  bool _needsCapturedHtmlTitleRepair(String storedTitle, String expectedTitle) {
    final normalizedStored = storedTitle.trim().toLowerCase();
    final normalizedExpected = expectedTitle.trim().toLowerCase();
    if (normalizedExpected.isEmpty) return false;
    if (normalizedStored.isEmpty) return true;
    return _looksLikeBadCapturedHtmlTitle(storedTitle) ||
        normalizedStored != normalizedExpected;
  }

  Future<PioneerImportWorkResult> _writeCopiedRangeImportedWork({
    required Database db,
    required String deviceId,
    required PioneerSourceWork work,
    String? libraryItemId,
    String? fileHashOverride,
    String? sourceWorkId,
    String? sourcePackageId,
    bool replaceCanonicalSiblings = true,
    required EgwCopiedRangeParseResult parseResult,
    required String sourceText,
    required PioneerImportSourceMethod sourceMethod,
    String sourceType = 'egw_copied_range',
    String sourceSite = 'egwwritings.org',
    String? relativePath,
    String contentType = 'text/plain',
    String? sourceUrl,
    String? sourceLabel,
    String? coverPath,
    PioneerImportShouldContinue? shouldContinue,
    List<ImportContributorSpec>? contributors,
    bool forceReindex = false,
  }) async {
    final itemId = libraryItemId ?? work.copiedRangeLibraryItemId;
    final now = _utcNow();
    final document = parseResult.document;
    final report = parseResult.report;
    final sourceBytes = Uint8List.fromList(utf8.encode(sourceText));
    final fileHash = fileHashOverride?.trim().isNotEmpty == true
        ? fileHashOverride!.trim()
        : sha256.convert(sourceBytes).toString();
    final resolvedRelativePath =
        relativePath ?? _buildCopiedRangeRelativePath(work);
    final fileName = p.basename(resolvedRelativePath);
    final existingItemRows = await db.query(
      'library_items',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    final createdNew = existingItemRows.isEmpty;
    final existingItem = existingItemRows.isEmpty
        ? null
        : existingItemRows.first;
    final existingSourceType =
        existingItem?['source_type']?.toString().trim().toLowerCase() ?? '';
    final shouldCompareAgainstExistingCopiedRange =
        sourceType == 'egw_copied_range' &&
        existingSourceType == 'egw_copied_range';
    final existingParagraphRows = shouldCompareAgainstExistingCopiedRange
        ? await db.rawQuery(
            '''
            SELECT epub_href, COALESCE(MAX(paragraph_index), 0) AS max_paragraph_index
            FROM library_text_blocks
            WHERE library_item_id = ?
            GROUP BY epub_href
          ''',
            [itemId],
          )
        : const <Map<String, Object?>>[];
    final nextParagraphIndexByHref = <String, int>{};
    for (final row in existingParagraphRows) {
      final href = row['epub_href']?.toString().trim() ?? '';
      if (href.isEmpty) continue;
      nextParagraphIndexByHref[href] = _intValue(row, 'max_paragraph_index');
    }
    final existingRefRows = shouldCompareAgainstExistingCopiedRange
        ? await db.query(
            'elibrary_ref_index',
            where: 'library_item_id = ?',
            whereArgs: [itemId],
          )
        : const <Map<String, Object?>>[];
    final existingRefByCode = <String, Map<String, Object?>>{};
    for (final row in existingRefRows) {
      final refCode = row['ref_code']?.toString().trim() ?? '';
      if (refCode.isEmpty) continue;
      existingRefByCode[refCode] = row;
    }

    final sectionRows = <Map<String, Object?>>[];
    final paragraphRows = <Map<String, Object?>>[];
    final refRows = <Map<String, Object?>>[];
    final skippedRefs = <String>[];
    final conflictRefs = <String>[];
    final importedRefs = <String>[];
    final seenRefTextByCode = <String, String>{};
    final seenPageMarkerByHrefAndPage = <String>{};
    final warnings = <String>[...report.warnings];
    final pageParagraphCounts = <int, int>{};
    const insertedLibraryItems = 1;
    final currentParagraphIndexByHref = Map<String, int>.from(
      nextParagraphIndexByHref,
    );

    for (final section in document.sections) {
      if (shouldContinue != null && !shouldContinue()) {
        return _buildSkippedNotImportableResult(
          work: work,
          libraryItemId: itemId,
          sourceMethod: sourceMethod,
          reason: 'Copied range import was cancelled.',
        );
      }

      final sectionInfo = _copiedRangeSectionInfo(
        work: work,
        section: section,
        fallbackIndex: sectionRows.length + 1,
      );
      if (sectionInfo == null) {
        continue;
      }
      final hasReadableParagraph = section.paragraphs.any(
        (paragraph) =>
            paragraph.ref?.trim().isNotEmpty == true &&
            paragraph.text.trim().isNotEmpty,
      );
      final isStructuralChapter = RegExp(
        r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
        caseSensitive: false,
      ).hasMatch(section.title.trim());
      if (!hasReadableParagraph && !isStructuralChapter) {
        continue;
      }
      final href = sectionInfo.href;
      final chapterNumber = sectionInfo.chapterNumber;
      final normalizedBookAbbrev = work.abbreviation.trim().isNotEmpty
          ? work.abbreviation.trim().toUpperCase()
          : 'DAR';
      final navId = _copiedRangeNavigationItemId(
        itemId: itemId,
        chapterNumber: chapterNumber,
        sectionTitle: section.title,
      );
      sectionRows.add(<String, Object?>{
        'id': navId,
        'library_item_id': itemId,
        'parent_id': null,
        'label': section.title,
        'href': href,
        'anchor_id': null,
        'spine_index': chapterNumber,
        'sort_order': chapterNumber,
        'depth': 0,
        'nav_type': 'toc',
        'content_kind': 'chapter',
        'is_front_matter': 0,
        'is_body_start': sectionRows.isEmpty ? 1 : 0,
        'body_order': chapterNumber,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'device_id': deviceId,
        'revision': 1,
        'sync_status': 'pending',
        'last_synced_at': null,
        'change_id': null,
      });
      final paragraphRowCountBeforeSection = paragraphRows.length;

      for (final paragraph in section.paragraphs) {
        final ref = paragraph.ref?.trim() ?? '';
        final paragraphText = paragraph.text.trim();
        final pageNumber = paragraph.page ?? 0;
        if (paragraphText.isEmpty) {
          if (ref.isNotEmpty) {
            warnings.add('Empty paragraph text for ref $ref');
          }
          continue;
        }
        if (ref.isEmpty) {
          warnings.add(
            'Paragraph without ref: ${_copiedRangeSnippet(paragraphText)}',
          );
          continue;
        }
        final seenText = seenRefTextByCode[ref];
        if (seenText != null) {
          if (seenText == paragraphText) {
            skippedRefs.add(ref);
          } else {
            conflictRefs.add(ref);
          }
          continue;
        }
        seenRefTextByCode[ref] = paragraphText;

        final existingRefRow = existingRefByCode[ref];
        if (existingRefRow != null) {
          final existingText =
              existingRefRow['plain_text']?.toString().trim() ?? '';
          if (existingText == paragraphText) {
            skippedRefs.add(ref);
            continue;
          }
          conflictRefs.add(ref);
          continue;
        }

        if (pageNumber > 0) {
          final pageMarkerKey = '$href|$pageNumber';
          final pageMarkerRef = '$normalizedBookAbbrev $pageNumber';
          if (seenPageMarkerByHrefAndPage.add(pageMarkerKey) &&
              !existingRefByCode.containsKey(pageMarkerRef)) {
            refRows.add(<String, Object?>{
              'library_item_id': itemId,
              'work_key': itemId,
              'edition_key': null,
              'edition_year': null,
              'book_title': work.title,
              'book_abbrev': normalizedBookAbbrev,
              'href': href,
              'anchor_id': null,
              'paragraph_index': -pageNumber,
              'page_number': pageNumber,
              'paragraph_on_page': 0,
              'ref_code': pageMarkerRef,
              'stable_ref': pageMarkerRef,
              'plain_text': null,
              'text_hash': null,
              'ref_source': '${sourceMethod.label}:page-marker',
              'created_at': now,
              'updated_at': now,
            });
          }
        }
        final nextOnPage = (pageParagraphCounts[pageNumber] ?? 0) + 1;
        pageParagraphCounts[pageNumber] = nextOnPage;
        final nextParagraphIndex = (currentParagraphIndexByHref[href] ?? 0) + 1;
        currentParagraphIndexByHref[href] = nextParagraphIndex;

        paragraphRows.add(<String, Object?>{
          'library_item_id': itemId,
          'epub_href': href,
          'spine_index': chapterNumber,
          'paragraph_index': nextParagraphIndex,
          'paragraph_on_section': nextParagraphIndex,
          'section_title': section.title,
          'plain_text': paragraphText,
          'created_at': now,
          'updated_at': now,
        });
        refRows.add(<String, Object?>{
          'library_item_id': itemId,
          'work_key': itemId,
          'edition_key': null,
          'edition_year': null,
          'book_title': work.title,
          'book_abbrev': work.abbreviation.trim().isNotEmpty
              ? work.abbreviation.trim().toUpperCase()
              : 'DAR',
          'href': href,
          'anchor_id': null,
          'paragraph_index': nextParagraphIndex,
          'page_number': pageNumber,
          'paragraph_on_page': nextOnPage,
          'ref_code': ref,
          'stable_ref': ref,
          'plain_text': paragraphText,
          'text_hash': sha256.convert(utf8.encode(paragraphText)).toString(),
          'ref_source': sourceMethod.label,
          'created_at': now,
          'updated_at': now,
        });
        importedRefs.add(ref);
      }
      if (paragraphRows.length == paragraphRowCountBeforeSection &&
          !isStructuralChapter) {
        sectionRows.removeLast();
      }
    }

    // Enforce the persisted navigation invariant after all duplicate/conflict
    // handling has finished. A section can initially look readable, then end
    // up with no inserted rows because its refs duplicate an earlier section.
    // Keep honest structural Chapter headings, but never persist any other
    // zero-body leaf.
    final readableHrefs = paragraphRows
        .map((row) => row['epub_href']?.toString().trim().toLowerCase() ?? '')
        .where((href) => href.isNotEmpty)
        .toSet();
    sectionRows.removeWhere((row) {
      final href = row['href']?.toString().trim().toLowerCase() ?? '';
      if (href.isNotEmpty && readableHrefs.contains(href)) return false;
      final label = row['label']?.toString().trim() ?? '';
      return !RegExp(
        r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
        caseSensitive: false,
      ).hasMatch(label);
    });

    // Captured EGW text can represent a chapter heading as an empty section
    // followed by one or more named body sections (for example SSP Chapter
    // III followed by EPHESUS). Preserve that source-order branch explicitly
    // instead of leaving the heading and its content as unrelated root rows.
    // This relationship is based only on contiguous source structure; labels
    // are never used to borrow content from a duplicate or sibling chapter.
    for (var index = 0; index < sectionRows.length; index++) {
      final parent = sectionRows[index];
      final parentHref = parent['href']?.toString().trim().toLowerCase() ?? '';
      final parentLabel = parent['label']?.toString().trim() ?? '';
      final isEmptyChapter =
          !readableHrefs.contains(parentHref) &&
          RegExp(
            r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
            caseSensitive: false,
          ).hasMatch(parentLabel);
      if (!isEmptyChapter) continue;

      final parentId = parent['id']?.toString() ?? '';
      if (parentId.isEmpty) continue;
      for (
        var childIndex = index + 1;
        childIndex < sectionRows.length;
        childIndex++
      ) {
        final child = sectionRows[childIndex];
        final childLabel = child['label']?.toString().trim() ?? '';
        if (RegExp(
          r'^chapter\s+(?:\d+|[ivxlcdm]+)\b',
          caseSensitive: false,
        ).hasMatch(childLabel)) {
          break;
        }
        final childHref = child['href']?.toString().trim().toLowerCase() ?? '';
        if (!readableHrefs.contains(childHref)) continue;
        child['parent_id'] = parentId;
        child['depth'] = 1;
        child['content_kind'] = 'body_subsection';
      }
    }

    final insertedParagraphCount = paragraphRows.length;
    final sectionCount = sectionRows.length;
    if (insertedParagraphCount == 0 && conflictRefs.isEmpty && !forceReindex) {
      return _buildSkippedExistingResult(
        work: work,
        libraryItemId: itemId,
        sourceMethod: sourceMethod,
        refCodeHandlingSummary:
            'Copied range refs were already imported for ${work.abbreviation}.',
      );
    }

    final finalIndexStatus = conflictRefs.isNotEmpty
        ? 'partially_imported_needs_review'
        : sourceMethod == PioneerImportSourceMethod.htmlCaptureFolder
        ? 'indexed'
        : 'partially_imported';
    final nextRevision = _intValue(existingItem, 'revision') + 1;
    final resolvedContributors = contributors ?? _resolveContributors(work);
    final authorDisplayString = resolvedContributors.length > 1
        ? resolvedContributors.map((c) => c.name).join('; ')
        : work.authorName;
    final itemRow = <String, Object?>{
      'id': itemId,
      'title': work.title,
      'author': authorDisplayString,
      'file_name': fileName,
      'relative_path': resolvedRelativePath,
      'file_hash': fileHash,
      'source_work_id': sourceWorkId ?? existingItem?['source_work_id'],
      'source_package_id':
          sourcePackageId ?? existingItem?['source_package_id'],
      'file_size': sourceBytes.length,
      'modified_at': null,
      'mime_type': contentType,
      'file_format': 'html',
      'folder_type': _folderType,
      'library_role': _libraryRole,
      'collection_name': _collectionName,
      'source_site': sourceSite,
      'source_url': sourceUrl?.trim().isNotEmpty == true
          ? sourceUrl!.trim()
          : sourceLabel?.trim().isNotEmpty == true
          ? sourceLabel!.trim()
          : 'EGW Writings copied range',
      'source_type': sourceType,
      'cover_path': coverPath,
      'date_added': existingItem?['date_added'] ?? now,
      'last_opened': existingItem?['last_opened'],
      'indexed_at': now,
      'index_status': finalIndexStatus,
      'index_error': conflictRefs.isNotEmpty
          ? 'Conflicting refs need review: ${conflictRefs.join(', ')}'
          : null,
      'epub_href': existingItem?['epub_href'],
      'epub_cfi': existingItem?['epub_cfi'],
      'anchor_id': existingItem?['anchor_id'],
      'spine_index': existingItem?['spine_index'],
      'paragraph_index': existingItem?['paragraph_index'],
      'is_missing': 0,
      'created_at': existingItem?['created_at'] ?? now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': nextRevision,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    };

    final isCapturedHtmlIndex =
        sourceMethod == PioneerImportSourceMethod.htmlCaptureFolder;
    if (isCapturedHtmlIndex && !forceReindex) {
      await _upsertLibraryItem(db, <String, Object?>{
        ...itemRow,
        'indexed_at': null,
        'index_status': 'pending',
        'index_error': null,
      });
    }
    try {
      if (isCapturedHtmlIndex) {
        await _beforeCapturedHtmlIndexWrite?.call(itemId);
      }
      await db.transaction((txn) async {
        if (replaceCanonicalSiblings) {
          await _deleteCanonicalCapturedImportSiblingRows(
            txn,
            work: work,
            keepItemId: itemId,
          );
        }
        if (!shouldCompareAgainstExistingCopiedRange) {
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
            where:
                "library_item_id = ? AND LOWER(COALESCE(created_by, '')) != 'user'",
            whereArgs: [itemId],
          );
          await txn.delete(
            'elibrary_ref_index',
            where: 'library_item_id = ?',
            whereArgs: [itemId],
          );
        }
        await _upsertLibraryItem(txn, itemRow);
        await _writeContributorRows(txn, itemId, resolvedContributors, now);
        for (final navRow in sectionRows) {
          await txn.insert(
            'library_navigation_items',
            navRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final paragraphRow in paragraphRows) {
          await txn.insert(
            'library_text_blocks',
            paragraphRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        for (final refRow in refRows) {
          await txn.insert(
            'elibrary_ref_index',
            refRow,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (error) {
      if (isCapturedHtmlIndex) {
        await db.update(
          'library_items',
          <String, Object?>{
            if (!forceReindex) 'indexed_at': null,
            'index_status': 'needs_attention',
            'index_error': 'CaptureClipper indexing failed: $error',
            'updated_at': _utcNow(),
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }
      rethrow;
    }

    final importedRefCount = importedRefs.length;
    final validationWarnings = <String>[
      ...warnings,
      if (report.paragraphsWithoutRef.isNotEmpty)
        'Paragraphs without refs were skipped: ${report.paragraphsWithoutRef.length}',
      if (report.emptyParagraphRefs.isNotEmpty)
        'Empty paragraph refs detected: ${report.emptyParagraphRefs.join(', ')}',
      if (report.duplicateRefs.isNotEmpty)
        'Duplicate refs detected in source: ${report.duplicateRefs.join(', ')}',
      if (conflictRefs.isNotEmpty)
        'Conflicting refs need review: ${conflictRefs.join(', ')}',
      if (skippedRefs.isNotEmpty)
        'Already imported refs skipped: ${(skippedRefs.toSet().toList()..sort()).join(', ')}',
    ];
    final requiresManualVerification =
        conflictRefs.isNotEmpty ||
        report.paragraphsWithoutRef.isNotEmpty ||
        report.emptyParagraphRefs.isNotEmpty ||
        report.duplicateRefs.isNotEmpty;
    final manualVerificationHint = conflictRefs.isNotEmpty
        ? 'One or more refs already exist with different text and were not overwritten.'
        : report.paragraphsWithoutRef.isNotEmpty
        ? 'Some paragraphs did not end with a DAR ref and were skipped.'
        : report.duplicateRefs.isNotEmpty
        ? 'The pasted range contained duplicate refs and only the first matching text was kept.'
        : null;

    final status = insertedParagraphCount == 0 && conflictRefs.isNotEmpty
        ? PioneerImportWorkStatus.failed
        : PioneerImportWorkStatus.imported;
    final stage = conflictRefs.isNotEmpty
        ? 'completed-with-review'
        : 'completed';
    final detail = [
      'Captured ${report.paragraphCount} paragraph${report.paragraphCount == 1 ? '' : 's'} from ${report.headingCount} chapter heading${report.headingCount == 1 ? '' : 's'}.',
      if (report.firstRef != null) 'First captured ref: ${report.firstRef}',
      if (report.lastRef != null) 'Last captured ref: ${report.lastRef}',
      'Imported $importedRefCount ref${importedRefCount == 1 ? '' : 's'}.',
      if (validationWarnings.isNotEmpty)
        'Warnings: ${validationWarnings.join(' | ')}',
    ].join(' ');

    return PioneerImportWorkResult(
      work: work,
      status: status,
      stage: stage,
      sourceMethod: sourceMethod,
      reason: insertedParagraphCount == 0 && conflictRefs.isNotEmpty
          ? 'Copied range import conflicts need review.'
          : sourceMethod == PioneerImportSourceMethod.htmlCaptureFolder
          ? (conflictRefs.isNotEmpty
                ? 'Imported captured HTML book with ref conflicts that need review.'
                : 'Imported captured HTML book into eLibrary.db.')
          : conflictRefs.isNotEmpty
          ? 'Imported copied EGW text with ref conflicts that need review.'
          : 'Imported copied EGW text into eLibrary.db.',
      libraryItemId: itemId,
      sourceType: sourceType,
      insertedLibraryItems: insertedLibraryItems,
      insertedNavigationItems: sectionCount,
      insertedTextBlocks: insertedParagraphCount,
      skippedExisting: skippedRefs.isNotEmpty && conflictRefs.isEmpty,
      refCodeHandlingSummary:
          'Copied range refs preserved: ${importedRefs.length}/${report.paragraphCount}.',
      detail: detail,
      exceptionType: null,
      httpStatusCode: null,
      contentType: contentType,
      downloadedByteCount: sourceBytes.length,
      parsedSectionCount: sectionCount,
      parsedParagraphCount: report.paragraphCount,
      requiresManualVerification: requiresManualVerification,
      manualVerificationHint: manualVerificationHint,
      epubAvailable: work.epubAvailable,
      epubValidated: false,
      epubRejectedReason: null,
      textCaptureAvailable: work.textCaptureAvailable,
      preferredImportPreference:
          PioneerSourcePathPreference.userSuppliedCleanedSource,
      qualityValidationSummary: validationWarnings.isEmpty
          ? null
          : validationWarnings.join(' • '),
      coverImported: coverPath?.trim().isNotEmpty == true,
      existingItemUpdated: !createdNew,
      createdNew: createdNew,
      firstSectionLabel: document.sections.isEmpty
          ? null
          : document.sections.first.title,
      lastSectionLabel: document.sections.isEmpty
          ? null
          : document.sections.last.title,
    );
  }

  Future<PioneerImportWorkResult> _writeImportedWork({
    required Database db,
    required String deviceId,
    required PioneerSourceWork work,
    String? libraryItemId,
    bool replaceCanonicalSiblings = false,
    required PioneerImportDocument document,
    required Uint8List sourceBytes,
    required PioneerSourceDownloadResult downloadResult,
    required PioneerImportSourceMethod sourceMethod,
    required String refCodeHandlingSummary,
    PioneerEpubQualityValidationResult? qualityValidation,
    String? sourceUrl,
    String? sourceType,
    String? sourceSite,
    String? relativePath,
    String? coverPath,
    String? indexStatus,
    String? indexError,
    List<ImportContributorSpec>? contributors,
  }) async {
    final itemId = libraryItemId ?? work.stableLibraryItemId;
    final existingItemRows = await db.query(
      'library_items',
      columns: const ['id'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    final createdNew = existingItemRows.isEmpty;
    final now = _utcNow();
    final fileHash = sha256.convert(sourceBytes).toString();
    final resolvedRelativePath =
        relativePath ?? _buildVirtualRelativePath(work);
    final fileName = p.basename(resolvedRelativePath);
    final resolvedSourceUrl = sourceUrl?.trim().isNotEmpty == true
        ? sourceUrl!.trim()
        : work.launchUrl;
    final sourceHost = sourceSite?.trim().isNotEmpty == true
        ? sourceSite!.trim()
        : _sourceSiteForImportMethod(sourceMethod) ??
              _sourceHostFromUrl(resolvedSourceUrl);
    final resolvedSourceType = sourceType?.trim().isNotEmpty == true
        ? sourceType!.trim()
        : _sourceTypeForImportMethod(sourceMethod);
    final resolvedIndexStatus =
        indexStatus ??
        (document.sections.isEmpty ? 'indexed_empty' : 'indexed');
    final textBlockCount = document.sections.fold<int>(
      0,
      (sum, section) => sum + section.paragraphs.length,
    );
    final navigationCount = document.sections.length;
    final firstMeaningfulSectionIndex = _firstMeaningfulSectionIndex(
      document.sections,
      bookTitle: work.title,
    );
    final generatedRefIndexRows =
        _shouldGeneratePublicDomainReferenceIndex(work, document)
        ? _generatePublicDomainReferenceIndexRows(
            libraryItemId: itemId,
            work: work,
            document: document,
          )
        : const <Map<String, Object?>>[];

    await db.transaction((txn) async {
      if (replaceCanonicalSiblings) {
        await _deleteCanonicalCapturedImportRows(
          txn,
          work: work,
          keepItemId: itemId,
        );
      }
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
      await txn.delete(
        'elibrary_ref_index',
        where: 'library_item_id = ?',
        whereArgs: [itemId],
      );
      final resolvedContributors = contributors ?? _resolveContributors(work);
      final authorDisplayString = resolvedContributors.length > 1
          ? resolvedContributors.map((c) => c.name).join('; ')
          : work.authorName;
      final itemRow = <String, Object?>{
        'id': itemId,
        'title': work.title,
        'author': authorDisplayString,
        'file_name': fileName,
        'relative_path': resolvedRelativePath,
        'file_hash': fileHash,
        'file_size': sourceBytes.length,
        'modified_at': null,
        'mime_type': 'text/html',
        'file_format': 'html',
        'folder_type': _folderType,
        'library_role': _libraryRole,
        'collection_name': _collectionName,
        'source_site': sourceHost,
        'source_url': resolvedSourceUrl,
        'source_type': resolvedSourceType,
        'cover_path': coverPath,
        'date_added': now,
        'last_opened': null,
        'indexed_at': now,
        'index_status': resolvedIndexStatus,
        'index_error': indexError,
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
      };
      await _upsertLibraryItem(txn, itemRow);
      await _writeContributorRows(txn, itemId, resolvedContributors, now);

      for (
        var sectionIndex = 0;
        sectionIndex < document.sections.length;
        sectionIndex++
      ) {
        final section = document.sections[sectionIndex];
        final sectionNumber = sectionIndex + 1;
        final isBodyStart = sectionIndex == firstMeaningfulSectionIndex;
        final isFrontMatter =
            firstMeaningfulSectionIndex != null &&
            sectionIndex < firstMeaningfulSectionIndex;
        await txn.insert('library_navigation_items', <String, Object?>{
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
          'is_front_matter': isFrontMatter ? 1 : 0,
          'is_body_start': isBodyStart ? 1 : 0,
          'body_order': sectionNumber,
          'created_at': now,
          'updated_at': now,
          'deleted_at': null,
          'device_id': deviceId,
          'revision': 1,
          'sync_status': 'pending',
          'last_synced_at': null,
          'change_id': null,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (
          var paragraphIndex = 0;
          paragraphIndex < section.paragraphs.length;
          paragraphIndex++
        ) {
          final paragraphText = section.paragraphs[paragraphIndex].trim();
          if (paragraphText.isEmpty) continue;
          final bodyOrder = paragraphIndex + 1;
          await txn.insert('library_text_blocks', <String, Object?>{
            'library_item_id': itemId,
            'epub_href': section.href,
            'spine_index': section.spineIndex,
            'paragraph_index': bodyOrder,
            'paragraph_on_section': bodyOrder,
            'section_title': section.title,
            'plain_text': paragraphText,
            'created_at': now,
            'updated_at': now,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      for (final row in generatedRefIndexRows) {
        await txn.insert('elibrary_ref_index', {
          ...row,
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    return PioneerImportWorkResult(
      work: work,
      status: PioneerImportWorkStatus.imported,
      stage: 'completed',
      sourceMethod: sourceMethod,
      reason: 'Imported into eLibrary.db.',
      libraryItemId: itemId,
      sourceType: resolvedSourceType,
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
      epubAvailable: qualityValidation?.epubAvailable ?? work.epubAvailable,
      epubValidated:
          sourceMethod == PioneerImportSourceMethod.userVerifiedAutomatedCapture
          ? false
          : qualityValidation?.isValid ?? false,
      epubRejectedReason: qualityValidation?.isValid == false
          ? qualityValidation?.reason
          : null,
      textCaptureAvailable:
          qualityValidation?.textCaptureAvailable ?? work.textCaptureAvailable,
      preferredImportPreference:
          qualityValidation?.preferredImportPreference ??
          _preferredImportPreferenceForSourceMethod(sourceMethod),
      qualityValidationSummary: qualityValidation?.summaryText,
      coverImported: coverPath?.trim().isNotEmpty == true,
      existingItemUpdated: !createdNew,
      createdNew: createdNew,
      firstSectionLabel: document.sections.isEmpty
          ? null
          : document.sections.first.title,
      lastSectionLabel: document.sections.isEmpty
          ? null
          : document.sections.last.title,
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

  Future<PioneerExistingCapturedImportSummary>
  _existingCanonicalCapturedImportSummary(
    Database db,
    PioneerSourceWork work,
  ) async {
    final itemIds = _canonicalCapturedImportItemIds(work);
    final placeholders = List<String>.filled(itemIds.length, '?').join(', ');
    final itemRows = await db.rawQuery('''
      SELECT id, source_type, index_status
      FROM library_items
      WHERE id IN ($placeholders) AND deleted_at IS NULL
      ORDER BY id
      ''', itemIds);
    if (itemRows.isEmpty) {
      return const PioneerExistingCapturedImportSummary(
        itemIds: <String>[],
        textBlockCount: 0,
        navigationItemCount: 0,
        refIndexCount: 0,
        sourceTypes: <String>[],
        indexStatuses: <String>[],
        hasExistingImport: false,
      );
    }

    final existingIds = itemRows
        .map((row) => row['id']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final existingPlaceholders = List<String>.filled(
      existingIds.length,
      '?',
    ).join(', ');
    final textBlockCount = _firstCount(
      await db.rawQuery('''
        SELECT COUNT(*) AS cnt
        FROM library_text_blocks
        WHERE library_item_id IN ($existingPlaceholders)
        ''', existingIds),
    );
    final navCount = _firstCount(
      await db.rawQuery('''
        SELECT COUNT(*) AS cnt
        FROM library_navigation_items
        WHERE library_item_id IN ($existingPlaceholders) AND deleted_at IS NULL
        ''', existingIds),
    );
    final refCount = _firstCount(
      await db.rawQuery('''
        SELECT COUNT(*) AS cnt
        FROM elibrary_ref_index
        WHERE library_item_id IN ($existingPlaceholders)
        ''', existingIds),
    );

    return PioneerExistingCapturedImportSummary(
      itemIds: List<String>.unmodifiable(existingIds),
      textBlockCount: textBlockCount,
      navigationItemCount: navCount,
      refIndexCount: refCount,
      sourceTypes: List<String>.unmodifiable(
        itemRows
            .map((row) => row['source_type']?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty),
      ),
      indexStatuses: List<String>.unmodifiable(
        itemRows
            .map((row) => row['index_status']?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty),
      ),
      hasExistingImport: true,
    );
  }

  Future<void> _deleteCanonicalCapturedImportRows(
    DatabaseExecutor txn, {
    required PioneerSourceWork work,
    required String keepItemId,
  }) async {
    for (final itemId in _canonicalCapturedImportItemIds(work)) {
      if (itemId == keepItemId) {
        await _deleteImportedWorkRowsPreservingMarkups(txn, itemId);
        continue;
      }
      await _deleteImportedWorkRowsPreservingMarkups(txn, itemId);
      await _softDeleteLibraryItem(txn, itemId);
    }
  }

  Future<void> _deleteCanonicalCapturedImportSiblingRows(
    DatabaseExecutor txn, {
    required PioneerSourceWork work,
    required String keepItemId,
  }) async {
    for (final itemId in _canonicalCapturedImportItemIds(work)) {
      if (itemId == keepItemId) continue;
      await _deleteImportedWorkRowsPreservingMarkups(txn, itemId);
      await _softDeleteLibraryItem(txn, itemId);
    }
  }

  Future<void> _deleteImportedWorkRows(
    DatabaseExecutor txn,
    String libraryItemId,
  ) async {
    await txn.delete(
      'library_item_contributors',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_navigation_items',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_text_blocks',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_links',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'elibrary_ref_index',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'elibrary_markups',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
  }

  Future<void> _deleteImportedWorkRowsPreservingMarkups(
    DatabaseExecutor txn,
    String libraryItemId,
  ) async {
    await txn.delete(
      'library_item_contributors',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_navigation_items',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_text_blocks',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'library_links',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
    await txn.delete(
      'elibrary_ref_index',
      where: 'library_item_id = ?',
      whereArgs: [libraryItemId],
    );
  }

  Future<void> _softDeleteLibraryItem(
    DatabaseExecutor txn,
    String libraryItemId,
  ) async {
    final deletedAt = _utcNow();
    await txn.update(
      'library_items',
      <String, Object?>{
        'deleted_at': deletedAt,
        'updated_at': deletedAt,
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [libraryItemId],
    );
  }

  Future<String?> _existingCapturedHtmlImportItemId(
    Database db,
    PioneerSourceWork work, {
    String? folderName,
    String? sourceFileHash,
    String? sourceUrl,
  }) async {
    final normalizedHash = sourceFileHash?.trim().toLowerCase() ?? '';
    if (normalizedHash.isNotEmpty) {
      final hashRows = await db.query(
        'library_items',
        columns: const ['id'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(file_hash, '')) = ?
          AND LOWER(COALESCE(file_format, '')) = 'html'
        ''',
        whereArgs: [normalizedHash],
        limit: 1,
      );
      if (hashRows.isNotEmpty) {
        final id = hashRows.first['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
    }

    final existing = await _existingCanonicalCapturedImportSummary(db, work);
    if (existing.itemIds.isNotEmpty) {
      return existing.itemIds.first;
    }

    final normalizedFolderName = folderName?.trim().toLowerCase() ?? '';
    if (normalizedFolderName.isNotEmpty) {
      final folderLikePatterns = <String>[
        '%/$normalizedFolderName/%',
        '%\\$normalizedFolderName\\%',
        '%/$normalizedFolderName%',
        '%\\$normalizedFolderName%',
      ];
      for (final folderLikePattern in folderLikePatterns) {
        final folderRows = await db.query(
          'library_items',
          columns: const ['id', 'title', 'author', 'cover_path'],
          where: '''
            deleted_at IS NULL
            AND LOWER(COALESCE(file_format, '')) = 'html'
            AND (
              LOWER(COALESCE(relative_path, '')) LIKE ?
              OR LOWER(COALESCE(source_url, '')) LIKE ?
              OR LOWER(COALESCE(id, '')) LIKE ?
            )
          ''',
          whereArgs: [
            folderLikePattern,
            folderLikePattern,
            '%$normalizedFolderName%',
          ],
          limit: 20,
        );
        if (folderRows.isEmpty) continue;
        folderRows.sort((left, right) {
          final leftScore = _scoreCapturedHtmlImportRow(left);
          final rightScore = _scoreCapturedHtmlImportRow(right);
          return rightScore.compareTo(leftScore);
        });
        final bestRow = folderRows.first;
        if (_scoreCapturedHtmlImportRow(bestRow) < 5) {
          continue;
        }
        final id = bestRow['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
    }

    final normalizedSourceUrls = <String>{
      work.sourceUrl?.trim().toLowerCase() ?? '',
      sourceUrl?.trim().toLowerCase() ?? '',
    }.where((value) => value.isNotEmpty);
    for (final normalizedSourceUrl in normalizedSourceUrls) {
      final sourceUrlRows = await db.query(
        'library_items',
        columns: const ['id'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(source_url, '')) = ?
          AND LOWER(COALESCE(file_format, '')) = 'html'
        ''',
        whereArgs: [normalizedSourceUrl],
        limit: 1,
      );
      if (sourceUrlRows.isNotEmpty) {
        final id = sourceUrlRows.first['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) return id;
      }
    }
    return null;
  }

  bool _isRemovableCapturedHtmlItem(Map<String, Object?> row) {
    final sourceType =
        row['source_type']?.toString().trim().toLowerCase() ?? '';
    if (sourceType.contains('captured_html') ||
        sourceType.contains('html_capture') ||
        sourceType.contains('pioneer_captured_html')) {
      return true;
    }

    final collectionName =
        row['collection_name']?.toString().trim().toLowerCase() ?? '';
    if (collectionName.contains('pioneer authors')) {
      return true;
    }

    final relativePath =
        row['relative_path']?.toString().trim().toLowerCase() ?? '';
    return relativePath.contains('textcaptures/research/pioneer authors') ||
        relativePath.contains('/pioneer authors/') ||
        relativePath.contains('html_capture');
  }

  Future<void> _softDeleteMatchingCapturedHtmlDuplicateItems(
    Database db, {
    required String keepItemId,
    required String folderName,
  }) async {
    final normalizedFolderName = folderName.trim().toLowerCase();
    if (normalizedFolderName.isEmpty) return;

    final folderLikePatterns = <String>[
      '%/$normalizedFolderName/%',
      '%\\$normalizedFolderName\\%',
      '%/$normalizedFolderName%',
      '%\\$normalizedFolderName%',
    ];
    final rows = <Map<String, Object?>>[];
    for (final folderLikePattern in folderLikePatterns) {
      final matchedRows = await db.query(
        'library_items',
        columns: const ['id', 'title', 'author', 'cover_path'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(file_format, '')) = 'html'
          AND (
            LOWER(COALESCE(relative_path, '')) LIKE ?
            OR LOWER(COALESCE(source_url, '')) LIKE ?
            OR LOWER(COALESCE(id, '')) LIKE ?
          )
        ''',
        whereArgs: [
          folderLikePattern,
          folderLikePattern,
          '%$normalizedFolderName%',
        ],
        limit: 20,
      );
      rows.addAll(matchedRows);
    }

    final seenIds = <String>{};
    final duplicateIds = <String>[];
    for (final row in rows) {
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty || id == keepItemId || !seenIds.add(id)) continue;
      duplicateIds.add(id);
    }

    if (duplicateIds.isEmpty) return;
    final now = _utcNow();
    for (final duplicateId in duplicateIds) {
      await db.update(
        'library_items',
        {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'},
        where: 'id = ?',
        whereArgs: [duplicateId],
      );
    }
  }

  bool _needsCapturedHtmlAuthorRepair(
    String storedAuthor,
    String expectedAuthor,
  ) {
    if (expectedAuthor.trim().isEmpty) return false;
    final normalizedStored = storedAuthor.trim().toLowerCase();
    if (normalizedStored.isEmpty) return true;
    return normalizedStored == 'unknown' ||
        normalizedStored == 'unknown author' ||
        normalizedStored != expectedAuthor.trim().toLowerCase();
  }

  bool _needsCapturedHtmlCoverRepair(
    String storedCoverPath,
    String expectedCoverPath,
  ) {
    if (expectedCoverPath.trim().isEmpty) return false;
    if (storedCoverPath.trim().isEmpty) return true;
    return !File(storedCoverPath.trim()).existsSync();
  }

  bool _needsCapturedHtmlHeadingRepair({
    required String storedHeading,
    required String expectedHeading,
  }) {
    if (expectedHeading.trim().isEmpty) return false;
    if (storedHeading.trim().isEmpty) return true;
    if (_looksLikeBadCapturedHtmlHeading(storedHeading)) return true;
    return _normalizeLooseText(storedHeading) !=
        _normalizeLooseText(expectedHeading);
  }

  bool _needsCapturedHtmlParagraphRepair({
    required String storedParagraph,
    required String storedHeading,
    required String expectedHeading,
    required String expectedParagraph,
  }) {
    if (expectedParagraph.trim().isEmpty) return false;
    if (storedParagraph.trim().isEmpty) return true;
    if (_looksLikeBadCapturedHtmlHeading(storedParagraph)) return true;
    final normalizedStored = _normalizeLooseText(storedParagraph);
    final normalizedExpected = _normalizeLooseText(expectedParagraph);
    if (normalizedStored == normalizedExpected) return false;
    final headingPrefix = _normalizeLooseText(
      expectedHeading.isNotEmpty ? expectedHeading : storedHeading,
    );
    if (headingPrefix.isNotEmpty &&
        normalizedStored.startsWith(headingPrefix)) {
      return true;
    }
    return normalizedStored.contains(normalizedExpected) &&
        normalizedStored != normalizedExpected;
  }

  bool _looksLikeBadCapturedHtmlTitle(String value) {
    final normalized = _normalizeLooseText(value);
    if (normalized.isEmpty) return true;
    if (normalized.contains('...')) return true;
    return _looksLikeBadCapturedHtmlHeading(value);
  }

  bool _looksLikeBadCapturedHtmlHeading(String value) {
    final normalized = _normalizeLooseText(value);
    if (normalized.isEmpty) return false;
    return RegExp(r'^(chapter|section)\s+\d+\b').hasMatch(normalized) ||
        normalized.startsWith('chapter 0') ||
        normalized.startsWith('section 0');
  }

  int _scoreCapturedHtmlImportRow(Map<String, Object?> row) {
    var score = 0;
    final title = row['title']?.toString().trim() ?? '';
    final author = row['author']?.toString().trim() ?? '';
    final coverPath = row['cover_path']?.toString().trim() ?? '';

    if (_looksLikeBadCapturedHtmlTitle(title)) {
      score += 4;
    }
    if (author.isEmpty ||
        author.toLowerCase() == 'unknown' ||
        author.toLowerCase() == 'unknown author') {
      score += 3;
    }
    if (coverPath.isEmpty || !File(coverPath).existsSync()) {
      score += 2;
    }
    if ((row['id']?.toString().trim() ?? '').contains('unknown')) {
      score += 1;
    }
    return score;
  }

  String _normalizeLooseText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _firstParagraphText(EgwCopiedRangeDocument document) {
    for (final section in document.sections) {
      for (final paragraph in section.paragraphs) {
        final text = paragraph.text.trim();
        if (text.isNotEmpty) return text;
      }
    }
    return '';
  }

  /// Deletes all imported data for [work] and hard-deletes the library_items
  /// row so the catalog treats it as uninstalled. Temporary dev utility.
  Future<void> hardResetWork(PioneerSourceWork work) async {
    final db = await ELibraryDatabase.instance.database;
    await db.transaction((txn) async {
      for (final itemId in _canonicalCapturedImportItemIds(work)) {
        await _deleteImportedWorkRows(txn, itemId);
        await txn.delete('library_items', where: 'id = ?', whereArgs: [itemId]);
      }
      // Also nuke the stable item in case it was written directly.
      await _deleteImportedWorkRows(txn, work.stableLibraryItemId);
      await txn.delete(
        'library_items',
        where: 'id = ?',
        whereArgs: [work.stableLibraryItemId],
      );
    });
  }

  /// Removes a captured HTML import from the library database without
  /// touching the source folder or source files on disk.
  Future<bool> removeImportedLibraryItem(String libraryItemId) async {
    final normalizedItemId = libraryItemId.trim();
    if (normalizedItemId.isEmpty) return false;

    final db = await ELibraryDatabase.instance.database;
    final existingRows = await db.query(
      'library_items',
      columns: const [
        'id',
        'source_type',
        'collection_name',
        'relative_path',
        'file_format',
        'deleted_at',
      ],
      where: 'id = ?',
      whereArgs: [normalizedItemId],
      limit: 1,
    );
    if (existingRows.isEmpty) return false;

    final row = existingRows.first;
    if ((row['deleted_at']?.toString().trim() ?? '').isNotEmpty) {
      return false;
    }
    if (!_isRemovableCapturedHtmlItem(row)) {
      return false;
    }

    final candidateIds = await _capturedHtmlRemovalCandidateIds(db, row);
    if (candidateIds.isEmpty) {
      return false;
    }

    debugPrint(
      'CaptureClipper remove: removing ${candidateIds.length} captured HTML '
      'item(s) for $normalizedItemId.',
    );
    await db.transaction((txn) async {
      for (final candidateId in candidateIds) {
        await _deleteImportedWorkRows(txn, candidateId);
        await txn.delete(
          'library_items',
          where: 'id = ?',
          whereArgs: [candidateId],
        );
      }
    });
    return true;
  }

  Future<List<String>> _capturedHtmlRemovalCandidateIds(
    Database db,
    Map<String, Object?> row,
  ) async {
    final candidateIds = <String>{};
    void addId(Object? value) {
      final id = value?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        candidateIds.add(id);
      }
    }

    addId(row['id']);

    final normalizedFileHash = row['file_hash']?.toString().trim() ?? '';
    if (normalizedFileHash.isNotEmpty) {
      final rows = await db.query(
        'library_items',
        columns: const ['id'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(file_hash, '')) = ?
          AND LOWER(COALESCE(file_format, '')) = 'html'
        ''',
        whereArgs: [normalizedFileHash.toLowerCase()],
      );
      for (final candidate in rows) {
        addId(candidate['id']);
      }
    }

    final normalizedRelativePath =
        row['relative_path']?.toString().trim() ?? '';
    if (normalizedRelativePath.isNotEmpty) {
      final rows = await db.query(
        'library_items',
        columns: const ['id'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(relative_path, '')) = ?
        ''',
        whereArgs: [normalizedRelativePath.toLowerCase()],
      );
      for (final candidate in rows) {
        addId(candidate['id']);
      }

      final folderName = p.basename(p.dirname(normalizedRelativePath)).trim();
      if (folderName.isNotEmpty) {
        final folderPattern = folderName.toLowerCase();
        final folderLikePatterns = <String>[
          '%/$folderPattern/%',
          '%\\$folderPattern\\%',
          '%/$folderPattern%',
          '%\\$folderPattern%',
        ];
        for (final pattern in folderLikePatterns) {
          final matchedRows = await db.query(
            'library_items',
            columns: const ['id'],
            where: '''
              deleted_at IS NULL
              AND LOWER(COALESCE(file_format, '')) = 'html'
              AND (
                LOWER(COALESCE(relative_path, '')) LIKE ?
                OR LOWER(COALESCE(source_url, '')) LIKE ?
                OR LOWER(COALESCE(id, '')) LIKE ?
              )
            ''',
            whereArgs: [pattern, pattern, '%$folderPattern%'],
          );
          for (final candidate in matchedRows) {
            addId(candidate['id']);
          }
        }
      }
    }

    final normalizedSourceUrl = row['source_url']?.toString().trim() ?? '';
    if (normalizedSourceUrl.isNotEmpty) {
      final rows = await db.query(
        'library_items',
        columns: const ['id'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(source_url, '')) = ?
        ''',
        whereArgs: [normalizedSourceUrl.toLowerCase()],
      );
      for (final candidate in rows) {
        addId(candidate['id']);
      }
    }

    return candidateIds.toList(growable: false);
  }

  Future<void> _upsertLibraryItem(
    DatabaseExecutor txn,
    Map<String, Object?> row,
  ) async {
    final id = row['id']?.toString();
    if (id == null || id.trim().isEmpty) {
      throw ArgumentError('library_items row requires a non-empty id');
    }
    final incomingCoverPath = row['cover_path']?.toString().trim() ?? '';
    final existingRows = await txn.query(
      'library_items',
      columns: const ['cover_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    final existingCoverPath = existingRows.isEmpty
        ? ''
        : existingRows.first['cover_path']?.toString().trim() ?? '';
    final normalizedRow =
        incomingCoverPath.isNotEmpty || existingCoverPath.isEmpty
        ? row
        : <String, Object?>{...row, 'cover_path': existingCoverPath};
    final updated = await txn.update(
      'library_items',
      normalizedRow,
      where: 'id = ?',
      whereArgs: [id],
    );
    if (updated == 0) {
      await txn.insert('library_items', normalizedRow);
    }
  }

  /// Returns known contributors for multi-author works, or a single-entry list
  /// derived from [work.authorName] for all other works.
  List<ImportContributorSpec> _resolveContributors(PioneerSourceWork work) {
    // Lessons on Faith: joint work by A. T. Jones and E. J. Waggoner.
    if (work.authorId == 'at_jones' && work.id == 'lessons_on_faith') {
      return _kLofContributors;
    }
    return [
      ImportContributorSpec(
        name: work.authorName,
        role: 'author',
        sortOrder: 1,
        isPrimary: true,
      ),
    ];
  }

  Future<void> _writeContributorRows(
    DatabaseExecutor txn,
    String itemId,
    List<ImportContributorSpec> specs,
    String now,
  ) async {
    if (specs.isEmpty) return;
    // Delete and replace contributor links for this item.
    await txn.delete(
      'library_item_contributors',
      where: 'library_item_id = ?',
      whereArgs: [itemId],
    );
    for (final spec in specs) {
      if (spec.name.trim().isEmpty) continue;
      final contributor = spec.toContributor();
      await txn.insert(
        'library_contributors',
        contributor.toRow(now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final link = LibraryItemContributor(
        libraryItemId: itemId,
        contributor: contributor,
        role: spec.role,
        sortOrder: spec.sortOrder,
        isPrimary: spec.isPrimary,
      );
      await txn.insert(
        'library_item_contributors',
        link.toRow(now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  String _buildVirtualRelativePath(PioneerSourceWork work) {
    final authorSegment = _slug(work.authorName);
    final fileStem = work.abbreviation.trim().isNotEmpty
        ? work.abbreviation.trim()
        : _slug(work.title);
    return p.join(
      _virtualRoot,
      authorSegment.isEmpty ? 'unknown_author' : authorSegment,
      '$fileStem.html',
    );
  }

  String _buildCopiedRangeRelativePath(PioneerSourceWork work) {
    final authorSegment = _slug(work.authorName);
    final fileStem = work.abbreviation.trim().isNotEmpty
        ? work.abbreviation.trim()
        : _slug(work.title);
    return p.join(
      _virtualRoot,
      authorSegment.isEmpty ? 'unknown_author' : authorSegment,
      'copied_range',
      '$fileStem.copied-range.html',
    );
  }

  String _buildHtmlCaptureRelativePath(
    PioneerSourceWork work,
    String htmlFilePath,
  ) {
    final authorSegment = _slug(work.authorName);
    final fileStem = work.abbreviation.trim().isNotEmpty
        ? work.abbreviation.trim()
        : _slug(work.title);
    final fileName = p.basename(htmlFilePath).trim().isEmpty
        ? 'capture.html'
        : p.basename(htmlFilePath);
    return p.join(
      _virtualRoot,
      authorSegment.isEmpty ? 'unknown_author' : authorSegment,
      fileStem.isEmpty ? _slug(work.title) : fileStem,
      fileName,
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
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }
}

const List<ImportContributorSpec> _kLofContributors = [
  ImportContributorSpec(
    name: 'A. T. Jones',
    fullName: 'Alonzo Trevier Jones',
    role: 'author',
    sortOrder: 1,
    isPrimary: true,
  ),
  ImportContributorSpec(
    name: 'E. J. Waggoner',
    fullName: 'Ellet Joseph Waggoner',
    role: 'author',
    sortOrder: 2,
    isPrimary: false,
  ),
];

/// Reads an optional metadata.json file from a capture folder and returns
/// the [ImportContributorSpec] list, or null if the file is absent or invalid.
List<ImportContributorSpec>? _readCaptureMetadataContributors(
  String folderPath,
) {
  try {
    final metadata = PioneerCaptureFolderMetadata.fromFolder(
      Directory(folderPath),
    );
    final specs = metadata.contributors
        .map(
          (item) => ImportContributorSpec(
            name: item.name,
            fullName: item.fullName,
            role: item.role,
            sortOrder: item.sortOrder,
            isPrimary: item.isPrimary,
          ),
        )
        .where((spec) => spec.name.trim().isNotEmpty)
        .toList(growable: false);
    return specs.isEmpty ? null : specs;
  } catch (_) {
    return null;
  }
}

List<ImportContributorSpec>? _metadataContributors(
  PioneerHtmlCaptureFolderPreview preview,
) {
  if (preview.metadata.contributors.isEmpty) return null;
  final specs = preview.metadata.contributors
      .map(
        (item) => ImportContributorSpec(
          name: item.name,
          fullName: item.fullName,
          role: item.role,
          sortOrder: item.sortOrder,
          isPrimary: item.isPrimary,
        ),
      )
      .where((spec) => spec.name.trim().isNotEmpty)
      .toList(growable: false);
  return specs.isEmpty ? null : specs;
}

int _firstCount(List<Map<String, Object?>> rows) {
  if (rows.isEmpty) return 0;
  return (rows.first['cnt'] as num?)?.toInt() ?? 0;
}

List<String> _canonicalCapturedImportItemIds(PioneerSourceWork work) {
  return <String>{
    work.stableLibraryItemId,
    work.copiedRangeLibraryItemId,
  }.where((id) => id.trim().isNotEmpty).toList(growable: false);
}

String _newCopyLibraryItemId(PioneerSourceWork work) {
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  return '${work.stableLibraryItemId}_copy_$timestamp';
}

String _failureStageFor(Object error) {
  if (error is PioneerSourceDownloadException) {
    return 'downloading';
  }
  if (error is PioneerZipExtractionException) {
    return 'extracting';
  }
  if (error is PioneerImportDocumentTooSparseException) {
    return 'parsing';
  }
  if (error is PioneerImportQualityException) {
    return 'validating';
  }
  if (error is UnsupportedError) {
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
    sourceType: _sourceTypeForImportMethod(sourceMethod),
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
    sourceType: _sourceTypeForImportMethod(sourceMethod),
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: false,
    refCodeHandlingSummary: _defaultRefCodeHandlingSummary,
    detail:
        'Only text/browser capture Pioneer sources can be imported right now.',
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
    reason: 'Already installed.',
    libraryItemId: libraryItemId,
    sourceType: _sourceTypeForImportMethod(sourceMethod),
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: true,
    refCodeHandlingSummary: refCodeHandlingSummary,
    detail: 'A matching work already exists in eLibrary.db.',
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
    reason =
        'Download failed: ${error.message}'
        '${error.httpStatusCode == null ? '' : ' (HTTP ${error.httpStatusCode})'}';
  } else if (error is PioneerZipExtractionException) {
    reason =
        'ZIP extraction failed: ${error.message}'
        '${error.zipEntry?.isNotEmpty == true ? ' (entry: ${error.zipEntry})' : ''}';
  } else if (error is PioneerImportDocumentTooSparseException) {
    reason = 'Parse failed: ${error.message}';
  } else if (error is PioneerImportQualityException) {
    reason = error.result.reason;
  } else if (error is UnsupportedError) {
    reason = 'Parse failed: ${error.message ?? error.toString()}';
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
    sourceType: _sourceTypeForImportMethod(sourceMethod),
    insertedLibraryItems: 0,
    insertedNavigationItems: 0,
    insertedTextBlocks: 0,
    skippedExisting: false,
    refCodeHandlingSummary: refCodeHandlingSummary,
    detail: error.toString(),
    exceptionType: error.runtimeType.toString(),
    httpStatusCode:
        httpStatusCode ??
        (error is PioneerSourceDownloadException ? error.httpStatusCode : null),
    contentType:
        contentType ??
        (error is PioneerSourceDownloadException ? error.contentType : null),
    downloadedByteCount:
        downloadedByteCount ??
        (error is PioneerSourceDownloadException ? error.byteCount : null),
    parsedSectionCount: parsedSectionCount,
    parsedParagraphCount: parsedParagraphCount,
    requiresManualVerification: requiresManualVerification,
    manualVerificationHint: requiresManualVerification
        ? 'This source looks like it needs manual verification or a browser challenge. Open the source URL in a browser, complete any prompt, and retry the import.'
        : null,
    epubAvailable: error is PioneerImportQualityException
        ? error.result.epubAvailable
        : false,
    epubValidated: false,
    epubRejectedReason: error is PioneerImportQualityException
        ? error.result.reason
        : null,
    textCaptureAvailable: error is PioneerImportQualityException
        ? error.result.textCaptureAvailable
        : false,
    preferredImportPreference: error is PioneerImportQualityException
        ? error.result.preferredImportPreference
        : PioneerSourcePathPreference.sourceNeeded,
    qualityValidationSummary: error is PioneerImportQualityException
        ? error.result.summaryText
        : null,
  );
}

Future<PioneerSourceDownloadResult> _downloadSourceBytes(Uri uri) async {
  if (uri.scheme == 'file') {
    final bytes = await File.fromUri(uri).readAsBytes();
    return PioneerSourceDownloadResult(
      bytes: Uint8List.fromList(bytes),
      httpStatusCode: null,
      contentType: 'application/epub+zip',
      resolvedUri: uri,
    );
  }
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

String? _candidateSourceUrl(
  PioneerSourceWork work,
  PioneerSourceCandidate? candidate,
) {
  final candidateUrl = candidate?.url?.trim();
  if (candidateUrl?.isNotEmpty == true) {
    return candidateUrl;
  }
  return work.sourceUrl?.trim().isNotEmpty == true
      ? work.sourceUrl!.trim()
      : null;
}

Future<Uint8List> _resolveImportedSourceBytes({
  required PioneerSourceWork work,
  required PioneerSourceCandidate sourceCandidate,
  required PioneerSourceDownloadResult downloadResult,
}) async {
  if (!_shouldExtractEpubFromZip(sourceCandidate, downloadResult)) {
    return downloadResult.bytes;
  }

  final extracted = _extractBestEpubFromZipCollection(
    work: work,
    zipBytes: downloadResult.bytes,
    preferredZipEntry: sourceCandidate.zipEntry,
  );
  if (extracted != null) return extracted;
  final entryHint = sourceCandidate.zipEntry?.trim();
  throw PioneerZipExtractionException(
    message: entryHint?.isNotEmpty == true
        ? 'ZIP entry not found in the downloaded archive.'
        : 'No matching EPUB entry found in the downloaded ZIP archive.',
    zipEntry: entryHint,
  );
}

bool _shouldExtractEpubFromZip(
  PioneerSourceCandidate sourceCandidate,
  PioneerSourceDownloadResult downloadResult,
) {
  final normalizedSourceType = sourceCandidate.sourceType.trim().toLowerCase();
  // epubZipEntry always requires ZIP extraction.
  if (normalizedSourceType == 'epubzipentry') return true;
  if (normalizedSourceType != 'epub') return false;
  // For a direct epub sourceType: extract only when the URL is a .zip collection.
  final candidateUrl = sourceCandidate.url?.trim().toLowerCase() ?? '';
  if (candidateUrl.endsWith('.zip')) return true;
  // application/epub+zip is a direct EPUB file, not a collection ZIP — do not extract.
  final contentType = downloadResult.contentType?.toLowerCase() ?? '';
  return contentType == 'application/zip' ||
      contentType.startsWith('application/zip;');
}

Uint8List? _extractBestEpubFromZipCollection({
  required PioneerSourceWork work,
  required Uint8List zipBytes,
  String? preferredZipEntry,
}) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(zipBytes, verify: false);
  } catch (_) {
    return null;
  }

  final explicitEntry = preferredZipEntry?.trim();
  if (explicitEntry != null && explicitEntry.isNotEmpty) {
    final directEntry = _findArchiveFileByNormalizedName(
      archive,
      explicitEntry,
    );
    if (directEntry != null && directEntry.isFile) {
      return Uint8List.fromList(directEntry.content as List<int>);
    }
    return null;
  }

  final epubEntries = archive.files
      .where((entry) {
        final name = p.normalize(entry.name).toLowerCase();
        return entry.isFile && name.endsWith('.epub');
      })
      .toList(growable: false);
  if (epubEntries.isEmpty) return null;
  if (epubEntries.length == 1) {
    return Uint8List.fromList(epubEntries.single.content as List<int>);
  }

  final scoredEntries =
      epubEntries
          .map((entry) {
            final name = p.normalize(entry.name);
            return MapEntry(name, _scoreEpubEntryForWork(name, work));
          })
          .toList(growable: false)
        ..sort((left, right) {
          final scoreCompare = right.value.compareTo(left.value);
          if (scoreCompare != 0) return scoreCompare;
          return left.key.compareTo(right.key);
        });

  final bestName = scoredEntries.first.key;
  final bestEntry = archive.findFile(bestName);
  if (bestEntry == null || !bestEntry.isFile) return null;
  return Uint8List.fromList(bestEntry.content as List<int>);
}

ArchiveFile? _findArchiveFileByNormalizedName(
  Archive archive,
  String normalizedName,
) {
  final target = _normalizeEpubPath(normalizedName).toLowerCase();
  for (final entry in archive.files) {
    final entryName = _normalizeEpubPath(entry.name).toLowerCase();
    if (entryName == target) {
      return entry;
    }
    if (p.basename(entryName) == p.basename(target)) {
      return entry;
    }
  }
  return null;
}

int _scoreEpubEntryForWork(String entryName, PioneerSourceWork work) {
  final normalizedEntry = _normalizeText(entryName);
  final normalizedTitle = _normalizeText(work.title);
  final normalizedAuthor = _normalizeText(work.authorName);
  final normalizedAbbreviation = _normalizeText(work.abbreviation);
  var score = 0;

  if (normalizedTitle.isNotEmpty && normalizedEntry.contains(normalizedTitle)) {
    score += 100;
  }
  if (normalizedAbbreviation.isNotEmpty &&
      normalizedEntry.contains(normalizedAbbreviation)) {
    score += 40;
  }
  if (normalizedAuthor.isNotEmpty &&
      normalizedEntry.contains(normalizedAuthor)) {
    score += 25;
  }

  final titleWords = normalizedTitle
      .split(' ')
      .where((word) => word.length > 3)
      .take(8)
      .toList(growable: false);
  for (final word in titleWords) {
    if (normalizedEntry.contains(word)) {
      score += 8;
    }
  }

  final authorWords = normalizedAuthor
      .split(' ')
      .where((word) => word.length > 3)
      .take(6)
      .toList(growable: false);
  for (final word in authorWords) {
    if (normalizedEntry.contains(word)) {
      score += 5;
    }
  }

  return score;
}

int? _firstMeaningfulSectionIndex(
  List<PioneerImportSection> sections, {
  required String bookTitle,
}) {
  int? firstNonFrontMatterLabelIndex;
  for (var index = 0; index < sections.length; index++) {
    final section = sections[index];
    // A section can be full of real, substantial prose and still not be a
    // chapter — "Information about this Book" is the clearest case: it
    // easily clears libraryIsMeaningfulReadingSection's paragraph-length bar
    // but must never be treated as the book's first chapter. Gate on the
    // same front-matter label check the reader itself uses
    // (`_firstRealContentNavigationHref` in library_book_reader_screen.dart)
    // before paragraph content is even considered — otherwise the About
    // page gets picked as "chapter one" and every real chapter after it
    // ends up recorded as front matter instead.
    final looksLikeFrontMatterByLabel =
        libraryIsFrontMatterOpeningLabel(section.title) ||
        libraryIsFrontMatterOpeningLabel(
          p.basenameWithoutExtension(section.href),
        );
    if (!looksLikeFrontMatterByLabel) {
      firstNonFrontMatterLabelIndex ??= index;
    }
    if (!looksLikeFrontMatterByLabel &&
        libraryIsMeaningfulReadingSection(
          title: section.title,
          href: section.href,
          paragraphs: section.paragraphs,
          bookTitle: bookTitle,
        )) {
      return index;
    }
  }
  // If nothing passed the full "meaningful" bar (e.g. every chapter's
  // paragraph extraction came back thin), prefer the first section that at
  // least isn't itself front-matter-labeled over blindly picking index 0 —
  // index 0 is very often the cover or About page.
  if (firstNonFrontMatterLabelIndex != null) {
    return firstNonFrontMatterLabelIndex;
  }
  return sections.isEmpty ? null : 0;
}

PioneerEpubQualityValidationResult _validatePioneerEpubImportQuality({
  required PioneerSourceWork work,
  required PioneerImportDocument document,
}) {
  final textBlockCount = document.sections.fold<int>(
    0,
    (sum, section) => sum + section.paragraphs.length,
  );
  final meaningfulSections = document.sections
      .where(
        (section) =>
            section.paragraphs.any((p) => p.trim().isNotEmpty) &&
            !PioneerPublicDomainExtractionProfile.isSectionFrontMatter(
              title: section.title,
              rawText: section.paragraphs.join(' '),
            ),
      )
      .toList(growable: false);
  final meaningfulTextBlockCount = meaningfulSections.fold<int>(
    0,
    (sum, section) =>
        sum + section.paragraphs.where((p) => p.trim().isNotEmpty).length,
  );
  final navigationCount = document.sections.length;
  final meaningfulNavigationCount = meaningfulSections.length;
  final firstBodySectionTitle = meaningfulSections.isEmpty
      ? null
      : meaningfulSections.first.title.trim();
  final epubAvailable = work.epubAvailable;
  final textCaptureAvailable = work.textCaptureAvailable;

  if (textBlockCount <= 0) {
    final preference = textCaptureAvailable
        ? PioneerSourcePathPreference.textCapture
        : PioneerSourcePathPreference.sourceNeeded;
    return PioneerEpubQualityValidationResult(
      isValid: false,
      reason: 'EPUB parsed but failed quality validation: no body text found.',
      detail:
          'The parser did not produce any readable text blocks for ${work.title}.',
      textBlockCount: textBlockCount,
      meaningfulTextBlockCount: meaningfulTextBlockCount,
      navigationCount: navigationCount,
      meaningfulNavigationCount: meaningfulNavigationCount,
      firstBodySectionTitle: firstBodySectionTitle,
      epubAvailable: epubAvailable,
      textCaptureAvailable: textCaptureAvailable,
      preferredImportPreference: preference,
    );
  }

  if (navigationCount <= 0) {
    final preference = textCaptureAvailable
        ? PioneerSourcePathPreference.textCapture
        : PioneerSourcePathPreference.sourceNeeded;
    return PioneerEpubQualityValidationResult(
      isValid: false,
      reason: 'EPUB parsed but failed quality validation: no navigation found.',
      detail:
          'The EPUB parser did not produce any navigation sections for ${work.title}.',
      textBlockCount: textBlockCount,
      meaningfulTextBlockCount: meaningfulTextBlockCount,
      navigationCount: navigationCount,
      meaningfulNavigationCount: meaningfulNavigationCount,
      firstBodySectionTitle: firstBodySectionTitle,
      epubAvailable: epubAvailable,
      textCaptureAvailable: textCaptureAvailable,
      preferredImportPreference: preference,
    );
  }

  if (meaningfulNavigationCount <= 0) {
    final preference = textCaptureAvailable
        ? PioneerSourcePathPreference.textCapture
        : PioneerSourcePathPreference.sourceNeeded;
    return PioneerEpubQualityValidationResult(
      isValid: false,
      reason:
          'EPUB parsed but failed quality validation: no body text attached to navigation.',
      detail:
          'Navigation entries exist, but none of them carry readable body text.',
      textBlockCount: textBlockCount,
      meaningfulTextBlockCount: meaningfulTextBlockCount,
      navigationCount: navigationCount,
      meaningfulNavigationCount: meaningfulNavigationCount,
      firstBodySectionTitle: firstBodySectionTitle,
      epubAvailable: epubAvailable,
      textCaptureAvailable: textCaptureAvailable,
      preferredImportPreference: preference,
    );
  }

  if (meaningfulTextBlockCount < 1) {
    final preference = textCaptureAvailable
        ? PioneerSourcePathPreference.textCapture
        : PioneerSourcePathPreference.sourceNeeded;
    return PioneerEpubQualityValidationResult(
      isValid: false,
      reason:
          'EPUB parsed but failed quality validation: not enough body text.',
      detail:
          'Only $meaningfulTextBlockCount readable body block${meaningfulTextBlockCount == 1 ? '' : 's'} were found.',
      textBlockCount: textBlockCount,
      meaningfulTextBlockCount: meaningfulTextBlockCount,
      navigationCount: navigationCount,
      meaningfulNavigationCount: meaningfulNavigationCount,
      firstBodySectionTitle: firstBodySectionTitle,
      epubAvailable: epubAvailable,
      textCaptureAvailable: textCaptureAvailable,
      preferredImportPreference: preference,
    );
  }

  final badFirstSection = firstBodySectionTitle == null
      ? false
      : PioneerPublicDomainExtractionProfile.isSectionFrontMatter(
          title: firstBodySectionTitle,
          rawText: meaningfulSections.first.paragraphs.join(' '),
        );
  if (badFirstSection) {
    final preference = textCaptureAvailable
        ? PioneerSourcePathPreference.textCapture
        : PioneerSourcePathPreference.sourceNeeded;
    return PioneerEpubQualityValidationResult(
      isValid: false,
      reason:
          'EPUB parsed but failed quality validation: first body section is front matter.',
      detail:
          'The first readable section still looks like copyright or source metadata.',
      textBlockCount: textBlockCount,
      meaningfulTextBlockCount: meaningfulTextBlockCount,
      navigationCount: navigationCount,
      meaningfulNavigationCount: meaningfulNavigationCount,
      firstBodySectionTitle: firstBodySectionTitle,
      epubAvailable: epubAvailable,
      textCaptureAvailable: textCaptureAvailable,
      preferredImportPreference: preference,
    );
  }

  final expectedPhrase = _expectedBodyPhraseForWork(work);
  if (expectedPhrase != null && expectedPhrase.trim().isNotEmpty) {
    final bodyText = meaningfulSections
        .map((section) => [section.title, ...section.paragraphs].join(' '))
        .join(' ')
        .toLowerCase();
    if (!bodyText.contains(expectedPhrase.toLowerCase())) {
      final preference = textCaptureAvailable
          ? PioneerSourcePathPreference.textCapture
          : PioneerSourcePathPreference.sourceNeeded;
      return PioneerEpubQualityValidationResult(
        isValid: false,
        reason:
            'EPUB parsed but failed quality validation: expected body phrase not found.',
        detail:
            'Expected to find "$expectedPhrase" in the readable body, but it was absent.',
        textBlockCount: textBlockCount,
        meaningfulTextBlockCount: meaningfulTextBlockCount,
        navigationCount: navigationCount,
        meaningfulNavigationCount: meaningfulNavigationCount,
        firstBodySectionTitle: firstBodySectionTitle,
        epubAvailable: epubAvailable,
        textCaptureAvailable: textCaptureAvailable,
        preferredImportPreference: preference,
        expectedBodyPhrase: expectedPhrase,
      );
    }
  }

  return PioneerEpubQualityValidationResult(
    isValid: true,
    reason: 'EPUB passed quality validation.',
    detail:
        'Readable body sections and navigation were both present for ${work.title}.',
    textBlockCount: textBlockCount,
    meaningfulTextBlockCount: meaningfulTextBlockCount,
    navigationCount: navigationCount,
    meaningfulNavigationCount: meaningfulNavigationCount,
    firstBodySectionTitle: firstBodySectionTitle,
    epubAvailable: epubAvailable,
    textCaptureAvailable: textCaptureAvailable,
    preferredImportPreference: PioneerSourcePathPreference.epub,
    expectedBodyPhrase: expectedPhrase,
  );
}

String? _expectedBodyPhraseForWork(PioneerSourceWork work) {
  final workId = work.id.trim().toLowerCase();
  switch (workId) {
    case 'daniel_and_the_revelation':
      return 'daniel in captivity';
    case 'the_cross_and_its_shadow':
      return 'the sanctuary';
    case 'home_here_and_home_in_heaven':
      return 'home here';
    case 'christ_our_righteousness':
      return 'christ our righteousness';
    case 'herald_of_the_bridegroom':
      return 'bridegroom';
  }
  return null;
}

bool _isEpubLikeSourceType(String? sourceType) {
  switch (sourceType?.trim().toLowerCase()) {
    case 'epub':
    case 'directepub':
    case 'epubzipentry':
      return true;
  }
  return false;
}

PioneerSourcePathPreference _preferredImportPreferenceForSourceMethod(
  PioneerImportSourceMethod sourceMethod,
) {
  switch (sourceMethod) {
    case PioneerImportSourceMethod.directUrl:
      return PioneerSourcePathPreference.epub;
    case PioneerImportSourceMethod.userVerifiedAutomatedCapture:
      return PioneerSourcePathPreference.textCapture;
    case PioneerImportSourceMethod.htmlCaptureFolder:
      return PioneerSourcePathPreference.textCapture;
    case PioneerImportSourceMethod.clipboard:
    case PioneerImportSourceMethod.savedExport:
    case PioneerImportSourceMethod.copiedRange:
      return PioneerSourcePathPreference.userSuppliedCleanedSource;
  }
}

String _sourceTypeForImportMethod(PioneerImportSourceMethod sourceMethod) {
  switch (sourceMethod) {
    case PioneerImportSourceMethod.userVerifiedAutomatedCapture:
      return 'egw_browser_capture';
    case PioneerImportSourceMethod.htmlCaptureFolder:
      return 'egw_html_capture';
    case PioneerImportSourceMethod.clipboard:
    case PioneerImportSourceMethod.savedExport:
      return 'egw_text_capture';
    case PioneerImportSourceMethod.copiedRange:
      return 'egw_copied_range';
    case PioneerImportSourceMethod.directUrl:
      return 'egw_text_capture';
  }
}

String? _sourceSiteForImportMethod(PioneerImportSourceMethod sourceMethod) {
  switch (sourceMethod) {
    case PioneerImportSourceMethod.userVerifiedAutomatedCapture:
    case PioneerImportSourceMethod.htmlCaptureFolder:
    case PioneerImportSourceMethod.clipboard:
    case PioneerImportSourceMethod.savedExport:
    case PioneerImportSourceMethod.copiedRange:
      return 'egwwritings.org';
    case PioneerImportSourceMethod.directUrl:
      return null;
  }
}

_CopiedRangeSectionInfo? _copiedRangeSectionInfo({
  required PioneerSourceWork work,
  required EgwCopiedRangeSection section,
  required int fallbackIndex,
}) {
  final extractedChapterNumber = _extractChapterNumber(section.title);
  final chapterNumber = extractedChapterNumber > 0
      ? extractedChapterNumber
      : fallbackIndex;
  final workSegment = _slug(
    work.abbreviation.trim().isNotEmpty ? work.abbreviation : work.title,
  );
  final sectionSegment = _slug(section.title);
  final href = p.join(
    'captured',
    workSegment.isEmpty ? 'dar' : workSegment,
    'chapter_${chapterNumber.toString().padLeft(2, '0')}_${sectionSegment.isEmpty ? 'section_$fallbackIndex' : sectionSegment}.html',
  );
  return _CopiedRangeSectionInfo(href: href, chapterNumber: chapterNumber);
}

String _copiedRangeNavigationItemId({
  required String itemId,
  required int chapterNumber,
  required String sectionTitle,
}) {
  return 'nav_${_slug(itemId)}_${chapterNumber}_${_slug(sectionTitle)}';
}

int _extractChapterNumber(String title) {
  final match = RegExp(r'^Chapter\s+(\d+)\s+—\s+.+$').firstMatch(title.trim());
  if (match == null) {
    return 0;
  }
  return int.tryParse(match.group(1) ?? '') ?? 0;
}

int _intValue(Map<String, Object?>? row, String key) {
  if (row == null) return 0;
  final value = row[key];
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _copiedRangeSnippet(String text, {int limit = 120}) {
  final normalized = normalizeWhitespace(text);
  if (normalized.length <= limit) {
    return normalized;
  }
  return '${normalized.substring(0, limit - 1).trimRight()}…';
}

bool _shouldGeneratePublicDomainReferenceIndex(
  PioneerSourceWork work,
  PioneerImportDocument document,
) {
  final sourceType = work.sourceType?.trim().toLowerCase() ?? '';
  return document.sections.isNotEmpty &&
      (_isPublicDomainPioneerEpub(work, sourceType: sourceType) ||
          sourceType == 'pioneer_captured_html' ||
          sourceType == 'captured_html');
}

List<Map<String, Object?>> _generatePublicDomainReferenceIndexRows({
  required String libraryItemId,
  required PioneerSourceWork work,
  required PioneerImportDocument document,
}) {
  final abbreviation = work.abbreviation.trim().toUpperCase();
  if (abbreviation.isEmpty) {
    return const <Map<String, Object?>>[];
  }

  final entries = <_PublicDomainParagraphEntry>[];
  for (
    var sectionIndex = 0;
    sectionIndex < document.sections.length;
    sectionIndex++
  ) {
    final section = document.sections[sectionIndex];
    for (
      var paragraphIndex = 0;
      paragraphIndex < section.paragraphs.length;
      paragraphIndex++
    ) {
      final paragraphText = section.paragraphs[paragraphIndex].trim();
      if (paragraphText.isEmpty) continue;
      entries.add(
        _PublicDomainParagraphEntry(
          href: section.href,
          sectionIndex: sectionIndex + 1,
          paragraphIndexInSection: paragraphIndex + 1,
          paragraphText: paragraphText,
        ),
      );
    }
  }

  if (entries.isEmpty) {
    return const <Map<String, Object?>>[];
  }

  final markerLists = entries
      .map((entry) => _publicDomainPageNumbers(entry.paragraphText))
      .toList(growable: false);
  final hasPageMarkers = markerLists.any((markers) => markers.isNotEmpty);
  int? bookInitialPageNumber;
  if (hasPageMarkers) {
    for (final markers in markerLists) {
      if (markers.isEmpty) continue;
      final first = markers.first;
      bookInitialPageNumber = first > 1 ? first - 1 : 1;
      break;
    }
  }

  final rows = <Map<String, Object?>>[];
  int? currentPageNumber = hasPageMarkers ? bookInitialPageNumber : null;
  var paragraphNumberOnPage = 0;

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final markers = markerLists[i];

    if (hasPageMarkers && currentPageNumber == null) {
      currentPageNumber = markers.isNotEmpty
          ? (markers.first > 1 ? markers.first - 1 : 1)
          : bookInitialPageNumber;
    }

    final pageNumber = hasPageMarkers
        ? (currentPageNumber ?? bookInitialPageNumber ?? 1)
        : entry.sectionIndex;
    final paragraphOnPage = hasPageMarkers
        ? paragraphNumberOnPage + 1
        : entry.paragraphIndexInSection;
    final refCode = hasPageMarkers
        ? '$abbreviation $pageNumber.$paragraphOnPage'
        : '$abbreviation ${entry.sectionIndex}.${entry.paragraphIndexInSection}';
    final normalizedHref = _normalizeEpubPath(entry.href);

    rows.add({
      'library_item_id': libraryItemId,
      'work_key': work.id,
      'edition_key': work.editionLabel?.trim().isNotEmpty == true
          ? work.editionLabel!.trim()
          : work.abbreviation.trim().isNotEmpty
          ? work.abbreviation.trim()
          : work.id,
      'edition_year': work.editionYear,
      'book_title': work.title,
      'book_abbrev': abbreviation,
      'href': normalizedHref,
      'anchor_id': null,
      'paragraph_index': entry.paragraphIndexInSection,
      'page_number': pageNumber,
      'paragraph_on_page': paragraphOnPage,
      'ref_code': refCode,
      'stable_ref': _refCodeLocationKey(
        libraryItemId: libraryItemId,
        href: normalizedHref,
        paragraphIndex: entry.paragraphIndexInSection,
      ),
      'plain_text': entry.paragraphText,
      'text_hash': sha256.convert(utf8.encode(entry.paragraphText)).toString(),
      'ref_source': hasPageMarkers
          ? 'generated_from_page_marker'
          : 'generated_from_section_paragraph',
    });

    if (markers.isNotEmpty) {
      currentPageNumber = markers.last;
      paragraphNumberOnPage = 0;
    } else if (hasPageMarkers) {
      paragraphNumberOnPage += 1;
    }
  }

  return rows;
}

List<int> _publicDomainPageNumbers(String text) {
  final markers = <int>[];
  for (final match in RegExp(r'\[(\d{1,4})\]').allMatches(text)) {
    final pageNumber = int.tryParse(match.group(1) ?? '');
    if (pageNumber != null) {
      markers.add(pageNumber);
    }
  }
  return markers;
}

String _refCodeLocationKey({
  required String libraryItemId,
  required String href,
  required int paragraphIndex,
}) {
  return '$libraryItemId|${_normalizeEpubPath(href)}|$paragraphIndex';
}

@immutable
class _PublicDomainParagraphEntry {
  const _PublicDomainParagraphEntry({
    required this.href,
    required this.sectionIndex,
    required this.paragraphIndexInSection,
    required this.paragraphText,
  });

  final String href;
  final int sectionIndex;
  final int paragraphIndexInSection;
  final String paragraphText;
}

Future<PioneerImportDocument> _parseSourceDocument(
  PioneerSourceWork work,
  Uint8List bytes,
) async {
  final sourceType = work.sourceType?.trim().toLowerCase() ?? '';
  switch (sourceType) {
    case 'directepub':
    case 'epub':
    case 'epubzipentry':
      return _parseEpubDocument(work, bytes);
    case 'html':
      return _parseHtmlDocument(work, bytes);
    default:
      throw UnsupportedError(
        'Unsupported Pioneer source type: ${work.sourceType}',
      );
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
  final profile = PioneerEpubParserProfile.infer(work);
  final anchoredSections = _parseNcxAnchoredEpubSections(
    archive: archive,
    work: work,
    profile: profile,
  );
  if (anchoredSections.length >= 3) {
    return PioneerImportDocument(title: work.title, sections: anchoredSections);
  }
  final List<String> sourcePaths;
  if (packageInfo.spineOrderedPaths.isNotEmpty) {
    sourcePaths = packageInfo.spineOrderedPaths;
  } else {
    sourcePaths =
        archive.files
            .where((entry) {
              final name = p.normalize(entry.name).toLowerCase();
              return entry.isFile &&
                  (name.endsWith('.xhtml') || name.endsWith('.html'));
            })
            .map((entry) => p.normalize(entry.name))
            .toList()
          ..sort();
  }

  final sections = <PioneerImportSection>[];
  for (final path in sourcePaths) {
    final entry = _findArchiveFileByNormalizedName(archive, path);
    if (entry == null || !entry.isFile) continue;
    final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
    sections.addAll(
      _parseHtmlSections(
        work,
        raw,
        baseHref: _normalizeEpubPath(path),
        startingSpineIndex: sections.length + 1,
        profile: profile,
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

List<PioneerImportSection> _parseNcxAnchoredEpubSections({
  required Archive archive,
  required PioneerSourceWork work,
  required PioneerEpubParserProfile profile,
}) {
  final ncxEntry = archive.files.cast<ArchiveFile?>().firstWhere(
    (entry) =>
        entry?.isFile == true &&
        p.normalize(entry!.name).toLowerCase().endsWith('.ncx'),
    orElse: () => null,
  );
  if (ncxEntry == null) return const <PioneerImportSection>[];

  final ncxPath = p.normalize(ncxEntry.name);
  final ncxDirectory = p.dirname(ncxPath);
  final ncx = utf8.decode(ncxEntry.content as List<int>, allowMalformed: true);
  final targetPattern = RegExp(
    r'<navLabel\b[^>]*>\s*<text\b[^>]*>(.*?)</text>\s*</navLabel>\s*'
    r'<content\b[^>]*\bsrc\s*=\s*["'
    ']([^"'
    ']+)["'
    '][^>]*/?>',
    caseSensitive: false,
    dotAll: true,
  );
  final targets = <({String title, String path, String anchor})>[];
  for (final match in targetPattern.allMatches(ncx)) {
    final title = _cleanSectionTitle(
      match.group(1) ?? '',
      fallback: work.title,
    );
    final source = (match.group(2) ?? '').trim();
    final hashIndex = source.indexOf('#');
    if (hashIndex <= 0 || hashIndex >= source.length - 1) continue;
    final encodedPath = source.substring(0, hashIndex);
    final anchor = Uri.decodeComponent(source.substring(hashIndex + 1));
    if (anchor.isEmpty) continue;
    final decodedPath = Uri.decodeFull(encodedPath);
    final resolvedPath = _normalizeEpubPath(
      p.normalize(p.join(ncxDirectory, decodedPath)),
    );
    targets.add((title: title, path: resolvedPath, anchor: anchor));
  }
  if (targets.length < 3) return const <PioneerImportSection>[];

  final sections = <PioneerImportSection>[];
  var spineIndex = 1;
  for (var targetIndex = 0; targetIndex < targets.length; targetIndex++) {
    final target = targets[targetIndex];
    final entry = _findArchiveFileByNormalizedName(archive, target.path);
    if (entry == null || !entry.isFile) continue;
    final raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
    final anchorPattern = RegExp(
      '<[^>]*\\bid\\s*=\\s*["\\\']${RegExp.escape(target.anchor)}'
      '["\\\'][^>]*>',
      caseSensitive: false,
    );
    final startMatch = anchorPattern.firstMatch(raw);
    if (startMatch == null) continue;

    var end = raw.length;
    for (
      var nextIndex = targetIndex + 1;
      nextIndex < targets.length;
      nextIndex++
    ) {
      final next = targets[nextIndex];
      if (next.path != target.path) break;
      final nextPattern = RegExp(
        '<[^>]*\\bid\\s*=\\s*["\\\']${RegExp.escape(next.anchor)}'
        '["\\\'][^>]*>',
        caseSensitive: false,
      );
      final nextMatches = nextPattern.allMatches(raw, startMatch.end);
      final nextMatch = nextMatches.isEmpty ? null : nextMatches.first;
      if (nextMatch != null) {
        end = nextMatch.start;
        break;
      }
    }

    final fragment = raw.substring(startMatch.start, end);
    final blocks = _extractHtmlBlocks(fragment, profile: profile);
    final normalizedTitle = _normalizeText(target.title);
    final paragraphs = <String>[];
    for (final block in blocks) {
      final text = block.text.trim();
      if (text.isEmpty) continue;
      if (paragraphs.isEmpty && _normalizeText(text) == normalizedTitle) {
        continue;
      }
      paragraphs.add(text);
    }
    sections.add(
      PioneerImportSection(
        href: '${target.path}#${target.anchor}',
        title: target.title,
        paragraphs: List<String>.unmodifiable(paragraphs),
        spineIndex: spineIndex++,
      ),
    );
  }
  return List<PioneerImportSection>.unmodifiable(sections);
}

Future<PioneerImportDocument> _parseHtmlDocument(
  PioneerSourceWork work,
  Uint8List bytes, {
  String? sourceUrl,
}) async {
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
  final baseHref = sourceUrl?.trim().isNotEmpty == true
      ? sourceUrl!.trim()
      : _capturedTextHref(sourceUrl: sourceUrl, sectionIndex: 1);
  final sections = _parseHtmlSections(
    work,
    raw,
    baseHref: baseHref,
    startingSpineIndex: 1,
    profile: PioneerEpubParserProfile.generic,
  );
  if (sections.isEmpty) {
    throw PioneerImportDocumentTooSparseException(
      sourceType: 'html',
      message: 'No readable sections were found in the HTML source.',
      sectionsFound: 0,
      paragraphCount: 0,
    );
  }

  return PioneerImportDocument(title: work.title, sections: sections);
}

List<PioneerImportSection> _parseHtmlSections(
  PioneerSourceWork work,
  String raw, {
  required String baseHref,
  required int startingSpineIndex,
  required PioneerEpubParserProfile profile,
}) {
  final body = _extractHtmlBody(raw);
  final blocks = _extractHtmlBlocks(body ?? raw, profile: profile);
  final sections = <PioneerImportSection>[];
  var spineIndex = startingSpineIndex;
  var sectionNumber = 1;
  var sectionTitle = work.title;
  var sectionHref = _sectionHref(baseHref, sectionNumber);
  final sectionParagraphs = <String>[];
  final usePublicDomainCleanup = profile.appliesPublicDomainCleanup;

  void flushSection() {
    if (sectionParagraphs.isEmpty) {
      sectionTitle = work.title;
      sectionHref = _sectionHref(baseHref, sectionNumber + 1);
      return;
    }

    final title = _cleanSectionTitle(sectionTitle, fallback: work.title);
    final rawText = sectionParagraphs.join(' ');
    final shouldSkipSection = usePublicDomainCleanup
        ? PioneerPublicDomainExtractionProfile.isSectionFrontMatter(
            title: title,
            rawText: rawText,
          )
        : _shouldSkipBoilerplateSection(title, sectionHref, rawText);
    if (shouldSkipSection) {
      sectionParagraphs.clear();
      sectionTitle = work.title;
      sectionHref = _sectionHref(baseHref, sectionNumber + 1);
      return;
    }

    sections.add(
      PioneerImportSection(
        href: sectionHref,
        title: title,
        paragraphs: List<String>.unmodifiable(sectionParagraphs),
        spineIndex: spineIndex,
      ),
    );
    spineIndex += 1;
    sectionNumber += 1;
    sectionParagraphs.clear();
    sectionTitle = work.title;
    sectionHref = _sectionHref(baseHref, sectionNumber);
  }

  for (final block in blocks) {
    if (block.kind == 'heading') {
      if (sectionParagraphs.isNotEmpty) {
        flushSection();
      }
      sectionTitle = block.text;
      sectionHref = _sectionHref(baseHref, sectionNumber);
      continue;
    }

    final text = block.text.trim();
    if (text.isEmpty) continue;
    sectionParagraphs.add(text);
  }

  if (sectionParagraphs.isNotEmpty) {
    flushSection();
  }

  if (sections.isEmpty) {
    final paragraphs = usePublicDomainCleanup
        ? PioneerPublicDomainExtractionProfile.filterLeadingFrontMatterParagraphs(
            _extractParagraphTexts(body ?? raw),
          )
        : _extractParagraphTexts(body ?? raw);
    if (paragraphs.isNotEmpty) {
      sections.add(
        PioneerImportSection(
          href: baseHref,
          title: work.title,
          paragraphs: paragraphs,
          spineIndex: startingSpineIndex,
        ),
      );
    }
  }

  return sections;
}

String _capturedTextHref({
  required String? sourceUrl,
  required int sectionIndex,
}) {
  final normalizedSourceUrl = sourceUrl?.trim() ?? '';
  if (normalizedSourceUrl.isNotEmpty) {
    return sectionIndex <= 1
        ? normalizedSourceUrl
        : '$normalizedSourceUrl#section-$sectionIndex';
  }
  return p.normalize(
    'captured/section_${sectionIndex.toString().padLeft(2, '0')}.txt',
  );
}

String _sectionHref(String baseHref, int sectionIndex) {
  final normalized = baseHref.trim();
  if (normalized.isEmpty) {
    return _capturedTextHref(sourceUrl: null, sectionIndex: sectionIndex);
  }
  return sectionIndex <= 1 ? normalized : '$normalized#section-$sectionIndex';
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

List<String> _extractParagraphTexts(String raw) {
  final blocks = _extractHtmlBlocks(
    raw,
    profile: PioneerEpubParserProfile.generic,
  );
  return blocks
      .where((block) => block.kind == 'paragraph')
      .map((block) => block.text.trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
}

List<_HtmlBlock> _extractHtmlBlocks(
  String raw, {
  required PioneerEpubParserProfile profile,
}) {
  final source = _stripHtmlWrapperTags(raw);
  final blocks = <_HtmlBlock>[];
  final stack = <_HtmlFrame>[];
  final blockPattern = RegExp(
    r'<(/?)(h[1-6]|p|div|blockquote|li|b|strong)\b([^>]*)>',
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

    if ((tag == 'b' || tag == 'strong') &&
        _hasInlineContainingBlock(stack, openIndex)) {
      continue;
    }

    if (_looksLikeHeadingLikeBlock(
      tag: tag,
      attrs: frame.attrs,
      innerHtml: innerHtml,
      text: text,
      profile: profile,
    )) {
      blocks.add(_HtmlBlock(kind: 'heading', text: text));
      continue;
    }

    if (tag == 'div') {
      if (RegExp(
        r'<(/?)(h[1-6]|p|blockquote|li|b|strong)\b',
        caseSensitive: false,
      ).hasMatch(innerHtml)) {
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

bool _looksLikeHeadingLikeBlock({
  required String tag,
  required String attrs,
  required String innerHtml,
  required String text,
  required PioneerEpubParserProfile profile,
}) {
  final normalizedText = _normalizeText(text);
  if (tag.startsWith('h')) {
    return true;
  }
  if (tag == 'b' || tag == 'strong') {
    return normalizedText.split(RegExp(r'\s+')).length <= 18 &&
        normalizedText.length <= 140;
  }
  if (tag != 'p' && tag != 'div' && tag != 'blockquote' && tag != 'li') {
    return false;
  }

  if (normalizedText.isEmpty) return false;

  final className = _extractClassName(attrs);
  if (className != null) {
    final classValue = _normalizeText(className);
    for (final needle in profile.headingClassNeedles) {
      if (classValue.contains(_normalizeText(needle))) {
        return true;
      }
    }
    final classTokens = classValue.split(RegExp(r'\s+'));
    if (classTokens.any(
      (token) => token.startsWith('chapter') || token.startsWith('section'),
    )) {
      return true;
    }
  }

  if (RegExp(
    r'''style\s*=\s*["'][^"']*(font-weight\s*:\s*(bold|700|800)|text-align\s*:\s*center)[^"']*["']''',
    caseSensitive: false,
    dotAll: true,
  ).hasMatch(attrs)) {
    return normalizedText.split(RegExp(r'\s+')).length <= 16 &&
        normalizedText.length <= 140;
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

  final words = normalizedText.split(RegExp(r'\s+'));
  if (words.length <= 8 && normalizedText.endsWith(':')) {
    return true;
  }

  return false;
}

bool _hasInlineContainingBlock(List<_HtmlFrame> stack, int openIndex) {
  for (var index = openIndex - 1; index >= 0; index--) {
    final tag = stack[index].tag;
    if (tag == 'p' || tag == 'li' || tag == 'blockquote') {
      return true;
    }
    if (tag == 'div' || tag.startsWith('h')) {
      return false;
    }
  }
  return false;
}

String _stripHtmlWrapperTags(String raw) {
  final body = _extractHtmlBody(raw);
  if (body != null && body.trim().isNotEmpty) {
    return body;
  }
  return raw;
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
  if (normalizedHref.contains('nav.xhtml') ||
      normalizedHref.contains('toc.xhtml')) {
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
  for (final match in RegExp(
    r'<item\b[^>]*>',
    caseSensitive: false,
  ).allMatches(opfXml)) {
    final tag = match.group(0) ?? '';
    final id = _attributeValue(tag, 'id');
    final href = _attributeValue(tag, 'href');
    final properties = _attributeValue(tag, 'properties');
    if (id == null || href == null) continue;
    final normalizedPath = _normalizeEpubPath(p.join(opfDir, href));
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
    spinePaths.add(item.href);
  }

  final orderedPaths = spinePaths.isNotEmpty
      ? spinePaths
      : manifest.values.map((item) => item.href).toList(growable: false);

  return _EpubPackageInfo(
    spineOrderedPaths: List<String>.unmodifiable(orderedPaths),
  );
}

String _normalizeEpubPath(String path) {
  final decoded = Uri.decodeFull(path);
  return p.normalize(decoded);
}

String? _attributeValue(String tag, String name) {
  final match = RegExp('$name="([^"]+)"', caseSensitive: false).firstMatch(tag);
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
    'security verification',
    'performing security verification',
    'verify you are human',
    'checking your browser',
    'security check',
    'attention required',
    'captcha',
    'challenge verification',
    'challenge',
    'cf chl',
    'turnstile',
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
  String? sourceUrl,
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
    return _parseHtmlDocument(
      work,
      Uint8List.fromList(utf8.encode(rawText)),
      sourceUrl: sourceUrl,
    );
  }

  final lines = rawText
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
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
        href: _capturedTextHref(
          sourceUrl: sourceUrl,
          sectionIndex: sectionIndex,
        ),
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
        href: _capturedTextHref(sourceUrl: sourceUrl, sectionIndex: 1),
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
  for (final chunk
      in rawText
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split(RegExp(r'\n\s*\n'))) {
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
  if (RegExp(
    r'^(chapter|section|part|book)\b',
    caseSensitive: false,
  ).hasMatch(normalized)) {
    return true;
  }
  if (const {
    'introduction',
    'preface',
    'contents',
    'appendix',
    'index',
  }.contains(lower)) {
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
  final statusCode =
      downloadResult?.httpStatusCode ??
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

class _CopiedRangeSectionInfo {
  const _CopiedRangeSectionInfo({
    required this.href,
    required this.chapterNumber,
  });

  final String href;
  final int chapterNumber;
}

class _HtmlBlock {
  const _HtmlBlock({required this.kind, required this.text});

  final String kind;
  final String text;
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
  const _EpubPackageInfo({this.spineOrderedPaths = const <String>[]});

  final List<String> spineOrderedPaths;
}

class _EpubManifestItem {
  const _EpubManifestItem({required this.href, required this.properties});

  final String href;
  final String properties;
}
