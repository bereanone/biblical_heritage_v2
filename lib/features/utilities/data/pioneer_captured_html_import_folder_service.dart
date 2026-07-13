import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/database/elibrary_database.dart';
import '../../library/data/library_catalog_service.dart';
import 'pioneer_capture_folder_metadata.dart';
import 'pioneer_captured_html_import_review_store.dart';
import 'pioneer_html_capture_folder_scanner.dart';
import 'pioneer_source_catalog.dart';
import 'pioneer_text_import_service.dart';

@immutable
class PioneerBooksParentCopyResult {
  const PioneerBooksParentCopyResult({
    required this.copiedFolderPaths,
    required this.alreadyCurrentPackageNames,
    required this.conflictPackageNames,
    required this.invalidPackageNames,
  });

  final List<String> copiedFolderPaths;
  final List<String> alreadyCurrentPackageNames;
  final List<String> conflictPackageNames;
  final List<String> invalidPackageNames;
}

class _CopyPackageManifest {
  const _CopyPackageManifest({
    required this.workId,
    required this.packageId,
    required this.contentHash,
  });

  final String workId;
  final String packageId;
  final String contentHash;
}

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
    required this.sourceFileHash,
    required this.title,
    required this.author,
    required this.sourceType,
    required this.sourceSite,
    required this.sourceUrl,
    required this.coverImagePath,
    required this.coverImported,
    required this.headingCount,
    required this.paragraphCount,
    required this.sectionCount,
    required this.firstChapterLabel,
    required this.lastChapterLabel,
    required this.createdNew,
    required this.existingItemUpdated,
    required this.warnings,
    required this.status,
    this.reason,
    this.libraryItemId,
  });

  final String filePath;
  final String relativePath;
  final String fileHash;
  final String? sourceFileHash;
  final String title;
  final String author;
  final String sourceType;
  final String? sourceSite;
  final String? sourceUrl;
  final String? coverImagePath;
  final bool coverImported;
  final int headingCount;
  final int paragraphCount;
  final int sectionCount;
  final String? firstChapterLabel;
  final String? lastChapterLabel;
  final bool createdNew;
  final bool existingItemUpdated;
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
      .where(
        (file) =>
            file.status == PioneerCapturedHtmlFileStatus.imported &&
            file.createdNew,
      )
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
class PioneerCapturedHtmlCloudFolderImportEntry {
  const PioneerCapturedHtmlCloudFolderImportEntry({
    required this.folderPath,
    required this.folderName,
    required this.htmlFileCount,
    required this.title,
    required this.author,
    required this.coverImported,
    required this.chapterCount,
    required this.firstChapterLabel,
    required this.lastChapterLabel,
    required this.createdNew,
    required this.updatedExisting,
    required this.importStatus,
    required this.reason,
    required this.libraryItemId,
    this.archivePath,
    this.archiveError,
  });

  final String folderPath;
  final String folderName;
  final int htmlFileCount;
  final String title;
  final String author;
  final bool coverImported;
  final int chapterCount;
  final String? firstChapterLabel;
  final String? lastChapterLabel;
  final bool createdNew;
  final bool updatedExisting;
  final PioneerImportWorkStatus? importStatus;
  final String? reason;
  final String? libraryItemId;
  final String? archivePath;
  final String? archiveError;

  bool get imported => importStatus == PioneerImportWorkStatus.imported;
  bool get archived => archivePath != null && archivePath!.trim().isNotEmpty;
}

@immutable
class PioneerCapturedHtmlCloudFolderImportReport {
  const PioneerCapturedHtmlCloudFolderImportReport({
    required this.rootPath,
    required this.entries,
    required this.completedAt,
  });

  final String rootPath;
  final List<PioneerCapturedHtmlCloudFolderImportEntry> entries;
  final DateTime completedAt;

  int get importedCount =>
      entries.where((entry) => entry.imported && entry.createdNew).length;

  int get repairedCount =>
      entries.where((entry) => entry.imported && entry.updatedExisting).length;

  int get archivedCount => entries.where((entry) => entry.archived).length;

  int get failedCount => entries
      .where(
        (entry) =>
            entry.importStatus == PioneerImportWorkStatus.failed ||
            entry.importStatus ==
                PioneerImportWorkStatus.packageLineageConflict,
      )
      .length;

  int get healthySkippedCount => entries
      .where(
        (entry) =>
            entry.importStatus == PioneerImportWorkStatus.skippedExisting,
      )
      .length;

  int get invalidCount => entries.where((entry) {
    final status = entry.importStatus;
    return status == PioneerImportWorkStatus.skippedNotImportable ||
        status == PioneerImportWorkStatus.skippedUnsupportedSource;
  }).length;

  int get skippedCount => entries.where((entry) {
    final status = entry.importStatus;
    return status == PioneerImportWorkStatus.skippedExisting ||
        status == PioneerImportWorkStatus.skippedNotImportable ||
        status == PioneerImportWorkStatus.skippedUnsupportedSource;
  }).length;

  PioneerCapturedHtmlCloudFolderImportEntry? entryForFolder(String folderPath) {
    final normalized = folderPath.trim();
    if (normalized.isEmpty) return null;
    for (final entry in entries) {
      if (entry.folderPath == normalized) {
        return entry;
      }
    }
    return null;
  }
}

@immutable
class PioneerCapturedHtmlAvailableImport {
  const PioneerCapturedHtmlAvailableImport({
    required this.preview,
    required this.existingLibraryItemId,
  });

  final PioneerHtmlCaptureFolderPreview preview;
  final String? existingLibraryItemId;

  String get folderPath => preview.folderPath;
  String get folderName => preview.folderName;
  String get title => preview.importWork.title;
  String get author => preview.importWork.authorName;
  String get displayLabel => '$folderName — $title';

  bool get isAlreadyImported =>
      existingLibraryItemId?.trim().isNotEmpty == true;
}

@immutable
class _ExistingImportedCloudFolderState {
  const _ExistingImportedCloudFolderState({
    required this.libraryItemId,
    required this.fileHash,
    required this.indexStatus,
  });

  final String libraryItemId;
  final String? fileHash;
  final String? indexStatus;

  bool get needsIndexingAttention {
    final status = indexStatus?.trim().toLowerCase() ?? '';
    return status == 'pending' ||
        status == 'failed' ||
        status == 'needs_attention';
  }
}

@immutable
class PioneerCapturedHtmlAvailableImportReport {
  const PioneerCapturedHtmlAvailableImportReport({
    required this.rootPath,
    required this.imports,
    required this.completedAt,
    required this.message,
  });

  final String rootPath;
  final List<PioneerCapturedHtmlAvailableImport> imports;
  final DateTime completedAt;
  final String message;

  int get availableCount => imports.length;
  bool get hasAvailableImports => imports.isNotEmpty;
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

@immutable
class PioneerPickedCaptureFileCopyResult {
  const PioneerPickedCaptureFileCopyResult({
    required this.managedRootPath,
    required this.destinationFolderPath,
    required this.copiedFilePaths,
    required this.failedSourcePaths,
    required this.missingAssetReferences,
  });

  final String managedRootPath;
  final String destinationFolderPath;
  final List<String> copiedFilePaths;
  final List<String> failedSourcePaths;
  final List<String> missingAssetReferences;

  bool get copiedAnything => copiedFilePaths.isNotEmpty;
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

  String? lastRepairFailure;

  PioneerCapturedHtmlCloudFolderImportReport? _repairFailure(String reason) {
    lastRepairFailure = reason;
    debugPrint('CaptureClipper repair FAILED: $reason');
    return null;
  }

  static const Set<String> _ignoredConfiguredFolderNames = <String>{
    'archive',
    'archives',
    'backup',
    'imported',
    'scanned',
    'books',
  };

  static const String managedImportFolderName = 'ImportedCaptureClipper';

  static const Set<String> _htmlAssetReferenceExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.css',
  };

  /// App-managed root that iOS file-picker imports are copied into. Lives
  /// under Application Support so it survives Files-provider availability.
  Future<String> managedImportRootPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, managedImportFolderName);
  }

  /// Copies files the user picked from the iOS Files picker (already local
  /// copies handed over by iOS) into the app-managed import folder. Sources
  /// are read-only: they are never deleted, moved, renamed, or altered.
  ///
  /// HTML files define the book folder (named after the first HTML file's
  /// basename). A batch without any HTML file is treated as related assets
  /// for the most recently created book folder.
  Future<PioneerPickedCaptureFileCopyResult>
  copyPickedFilesIntoManagedImportFolder(
    List<String> pickedFilePaths, {
    String? managedRootPath,
    bool setAsConfiguredFolder = true,
  }) async {
    final rootPath = managedRootPath ?? await managedImportRootPath();
    await Directory(rootPath).create(recursive: true);

    final sources = pickedFilePaths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (sources.isEmpty) {
      throw StateError('No files were selected to import.');
    }

    final htmlSources = sources.where(_isHtmlFilePath).toList(growable: false);
    final String destinationFolderPath;
    if (htmlSources.isNotEmpty) {
      destinationFolderPath = p.join(
        rootPath,
        _managedBookFolderName(htmlSources.first),
      );
    } else {
      final latest = await _mostRecentManagedBookFolder(rootPath);
      if (latest == null) {
        throw StateError(
          'Pick the book\'s HTML file first so StudyBible2 can create its '
          'import folder, then add the related image/resource files.',
        );
      }
      destinationFolderPath = latest;
    }
    await Directory(destinationFolderPath).create(recursive: true);

    final copied = <String>[];
    final failed = <String>[];
    for (final source in sources) {
      final sourceFile = File(source);
      if (!await sourceFile.exists()) {
        debugPrint('CaptureClipper file import: source missing at $source.');
        failed.add(source);
        continue;
      }
      final destination = p.join(destinationFolderPath, p.basename(source));
      try {
        // Copy only; never move, rename, or delete the picked source file.
        await sourceFile.copy(destination);
        copied.add(destination);
        debugPrint(
          'CaptureClipper file import: copied $source -> $destination.',
        );
      } catch (error) {
        debugPrint(
          'CaptureClipper file import: failed to copy $source: $error',
        );
        failed.add(source);
      }
    }

    final missingAssets = <String>{};
    for (final copiedPath in copied.where(_isHtmlFilePath)) {
      missingAssets.addAll(await _missingRelativeAssetReferences(copiedPath));
    }

    if (setAsConfiguredFolder && copied.isNotEmpty) {
      await _settingsStore.savePioneerCapturedHtmlFolder(path: rootPath);
      debugPrint(
        'CaptureClipper file import: configured folder set to app-managed '
        'root $rootPath.',
      );
    }

    debugPrint(
      'CaptureClipper file import: copied ${copied.length}, failed '
      '${failed.length}, missing asset reference(s) ${missingAssets.length} '
      'in $destinationFolderPath.',
    );
    return PioneerPickedCaptureFileCopyResult(
      managedRootPath: rootPath,
      destinationFolderPath: destinationFolderPath,
      copiedFilePaths: List<String>.unmodifiable(copied),
      failedSourcePaths: List<String>.unmodifiable(failed),
      missingAssetReferences: List<String>.unmodifiable(
        missingAssets.toList()..sort(),
      ),
    );
  }

  /// Enumerates the immediate package folders beneath a picker-provided Books
  /// parent, then recursively copies them into app-managed storage. The source
  /// tree is read only and is never moved, renamed, deleted, or modified.
  Future<PioneerBooksParentCopyResult>
  copyPickedBooksParentIntoManagedImportFolder(
    String pickedBooksFolderPath, {
    String? managedRootPath,
    bool setAsConfiguredFolder = true,
  }) async {
    final rootPath = managedRootPath ?? await managedImportRootPath();
    await Directory(rootPath).create(recursive: true);
    final booksPath = pickedBooksFolderPath.trim();
    final books = Directory(booksPath);
    if (booksPath.isEmpty || !await books.exists()) {
      throw StateError('The selected Books folder is no longer available.');
    }
    final children = await books
        .list(followLinks: false)
        .where((entity) => entity is Directory && entity is! Link)
        .cast<Directory>()
        .where((directory) => !_ignoredBooksChild(directory.path))
        .toList();
    children.sort((a, b) => a.path.compareTo(b.path));
    final copiedFolders = <String>[];
    final alreadyCurrent = <String>[];
    final conflicts = <String>[];
    final invalid = <String>[];
    for (final source in children) {
      final sourcePath = source.path;
      final sourceManifest = await _readUsablePackageManifest(source);
      if (sourceManifest == null) {
        invalid.add(p.basename(sourcePath));
        continue;
      }
      final folderName = p.basename(p.normalize(sourcePath));
      final destinationPath = p.join(rootPath, folderName);
      final destination = Directory(destinationPath);
      if (await destination.exists()) {
        final destinationManifest = await _readUsablePackageManifest(
          destination,
        );
        if (destinationManifest != null) {
          if (sourceManifest.workId == destinationManifest.workId &&
              sourceManifest.packageId.isNotEmpty &&
              destinationManifest.packageId.isNotEmpty &&
              sourceManifest.packageId != destinationManifest.packageId) {
            conflicts.add(folderName);
            continue;
          }
          if (sourceManifest.workId == destinationManifest.workId &&
              sourceManifest.packageId == destinationManifest.packageId &&
              sourceManifest.contentHash.isNotEmpty &&
              sourceManifest.contentHash == destinationManifest.contentHash) {
            alreadyCurrent.add(folderName);
            continue;
          }
        }
      }
      await destination.create(recursive: true);
      await for (final entity in source.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is Link) continue;
        final relative = p.relative(entity.path, from: sourcePath);
        final target = p.normalize(p.join(destinationPath, relative));
        if (!p.isWithin(destinationPath, target)) {
          throw StateError('A selected package contains an unsafe path.');
        }
        if (entity is Directory) {
          await Directory(target).create(recursive: true);
        } else if (entity is File) {
          await Directory(p.dirname(target)).create(recursive: true);
          await entity.copy(target);
        }
      }
      copiedFolders.add(destinationPath);
    }
    if (copiedFolders.isEmpty && alreadyCurrent.isEmpty) {
      throw StateError('No valid CaptureClipper packages were found in Books.');
    }
    if (setAsConfiguredFolder) {
      await _settingsStore.savePioneerCapturedHtmlFolder(path: rootPath);
    }
    return PioneerBooksParentCopyResult(
      copiedFolderPaths: List<String>.unmodifiable(copiedFolders),
      alreadyCurrentPackageNames: List<String>.unmodifiable(alreadyCurrent),
      conflictPackageNames: List<String>.unmodifiable(conflicts),
      invalidPackageNames: List<String>.unmodifiable(invalid),
    );
  }

  bool _ignoredBooksChild(String path) {
    final name = p.basename(path).trim();
    final lower = name.toLowerCase();
    if (name.isEmpty || name.startsWith('.')) return true;
    if (const {'archive', 'backup', 'scanned', 'imported'}.contains(lower)) {
      return true;
    }
    return lower.contains('staging') ||
        lower.contains('rollback') ||
        lower.contains('temporary') ||
        lower.endsWith('.tmp');
  }

  Future<_CopyPackageManifest?> _readUsablePackageManifest(
    Directory folder,
  ) async {
    final manifestFile = File(p.join(folder.path, 'manifest.json'));
    if (!await manifestFile.exists()) return null;
    try {
      final decoded = json.decode(await manifestFile.readAsString());
      if (decoded is! Map) return null;
      final htmlFile = (decoded['htmlFile'] ?? decoded['html_file'])
          ?.toString()
          .trim();
      if (htmlFile == null || htmlFile.isEmpty || p.isAbsolute(htmlFile)) {
        return null;
      }
      final htmlPath = p.normalize(p.join(folder.path, htmlFile));
      if (!p.isWithin(folder.path, htmlPath) ||
          !await File(htmlPath).exists()) {
        return null;
      }
      return _CopyPackageManifest(
        workId:
            (decoded['workId'] ?? decoded['work_id'])?.toString().trim() ?? '',
        packageId: decoded['packageId']?.toString().trim() ?? '',
        contentHash: decoded['contentHash']?.toString().trim() ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  bool _isHtmlFilePath(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.html' || extension == '.htm';
  }

  String _managedBookFolderName(String htmlFilePath) {
    final base = p
        .basenameWithoutExtension(htmlFilePath)
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .trim();
    return base.isEmpty ? 'capture' : base;
  }

  Future<String?> _mostRecentManagedBookFolder(String rootPath) async {
    Directory? latest;
    DateTime? latestModified;
    await for (final entity in Directory(rootPath).list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = p.basename(entity.path).trim().toLowerCase();
      if (_ignoredConfiguredFolderNames.contains(name)) continue;
      final modified = (await entity.stat()).modified;
      if (latestModified == null || modified.isAfter(latestModified)) {
        latest = entity;
        latestModified = modified;
      }
    }
    return latest?.path;
  }

  Future<List<String>> _missingRelativeAssetReferences(
    String htmlFilePath,
  ) async {
    final String html;
    try {
      html = await File(htmlFilePath).readAsString();
    } catch (_) {
      return const <String>[];
    }
    final folderPath = p.dirname(htmlFilePath);
    final missing = <String>{};
    final references = RegExp(
      '''(?:src|href)=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html);
    for (final match in references) {
      final reference = match.group(1)?.trim() ?? '';
      if (reference.isEmpty ||
          reference.startsWith('#') ||
          reference.startsWith('/') ||
          reference.contains('://') ||
          reference.startsWith('data:') ||
          reference.startsWith('mailto:')) {
        continue;
      }
      final extension = p
          .extension(Uri.decodeComponent(reference))
          .toLowerCase();
      if (!_htmlAssetReferenceExtensions.contains(extension)) continue;
      final resolved = p.normalize(
        p.join(folderPath, Uri.decodeComponent(reference)),
      );
      if (!await File(resolved).exists()) {
        missing.add(reference);
      }
    }
    return missing.toList(growable: false);
  }

  Future<String?> _resolveAccessibleConfiguredRootPath() async {
    final rootPath = await _settingsStore.loadPioneerCapturedHtmlFolderPath();
    if (rootPath == null || rootPath.trim().isEmpty) {
      return null;
    }

    final normalizedRootPath = rootPath.trim();
    final defaultAppRoot = await LibraryRootService.instance
        .defaultAppLibraryRootPath();
    if (Platform.isIOS &&
        LibraryRootService.isDefaultAppDocumentsPath(
          candidatePath: normalizedRootPath,
          defaultAppRootPath: defaultAppRoot,
        )) {
      debugPrint(
        'CaptureClipper cloud import: rejecting app Documents fallback at '
        '$normalizedRootPath.',
      );
      return null;
    }
    final bookmark = await _settingsStore
        .loadPioneerCapturedHtmlFolderBookmark();
    final bookmarkSaved = bookmark?.trim().isNotEmpty == true;
    var accessibleRootPath = normalizedRootPath;
    debugPrint(
      'CaptureClipper cloud import: configured root=$normalizedRootPath '
      'bookmarkSaved=$bookmarkSaved',
    );
    if ((Platform.isMacOS || Platform.isIOS) && bookmarkSaved) {
      try {
        final activated = await LibraryRootNative.activateBookmark(bookmark!);
        final activatedPath = activated?.trim() ?? '';
        if (activatedPath.isNotEmpty) {
          accessibleRootPath = activatedPath;
          debugPrint(
            'CaptureClipper cloud import: bookmark activated for folder access.',
          );
        } else {
          debugPrint(
            'CaptureClipper cloud import: bookmark activation returned no path; '
            'using configured folder path.',
          );
        }
      } catch (error) {
        debugPrint(
          'CaptureClipper cloud import: bookmark activation failed: $error',
        );
      }
    }
    if (Platform.isIOS &&
        LibraryRootService.isDefaultAppDocumentsPath(
          candidatePath: accessibleRootPath,
          defaultAppRootPath: defaultAppRoot,
        )) {
      debugPrint(
        'CaptureClipper cloud import: rejecting activated app Documents fallback at '
        '$accessibleRootPath.',
      );
      return null;
    }
    return accessibleRootPath;
  }

  Future<PioneerSourceCatalog?> _loadConfiguredCatalog() async {
    try {
      return await PioneerSourceCatalog.load();
    } catch (error) {
      debugPrint('CaptureClipper cloud scan catalog load failed: $error');
      return null;
    }
  }

  Future<List<PioneerHtmlCaptureFolderPreview>> _scanConfiguredPreviews({
    required String accessibleRootPath,
    PioneerSourceCatalog? catalog,
  }) async {
    final rootDirectory = Directory(accessibleRootPath);
    if (!await rootDirectory.exists()) {
      debugPrint(
        'CaptureClipper cloud import: folder missing or unavailable at '
        '$accessibleRootPath',
      );
      return const <PioneerHtmlCaptureFolderPreview>[];
    }

    final resolvedCatalog = catalog ?? await _loadConfiguredCatalog();
    final booksPath = p.join(accessibleRootPath, 'Books');
    final booksPreviews = await PioneerHtmlCaptureFolderScanner(
      rootPath: booksPath,
      preferAssetManifest: false,
      knownDevScanPath: null,
      ignoredFolderNames: _ignoredConfiguredFolderNames,
    ).scan(catalog: resolvedCatalog);

    // Permanent CaptureClipper books are published only beneath Books/. A
    // root-level CloudFiles/<workId> folder is legacy input and must not be
    // rediscovered as a second permanent representation.
    return booksPreviews;
  }

  Future<PioneerCapturedHtmlAvailableImportReport>
  discoverConfiguredCloudFolderImports({PioneerSourceCatalog? catalog}) async {
    final completedAt = DateTime.now();
    final accessibleRootPath = await _resolveAccessibleConfiguredRootPath();
    if (accessibleRootPath == null) {
      final report = PioneerCapturedHtmlAvailableImportReport(
        rootPath: '',
        imports: const <PioneerCapturedHtmlAvailableImport>[],
        completedAt: completedAt,
        message: 'No CaptureClipper cloud folder is configured.',
      );
      debugPrint(report.message);
      return report;
    }

    final rootDirectory = Directory(accessibleRootPath);
    if (!await rootDirectory.exists()) {
      final report = PioneerCapturedHtmlAvailableImportReport(
        rootPath: accessibleRootPath,
        imports: const <PioneerCapturedHtmlAvailableImport>[],
        completedAt: completedAt,
        message:
            'CaptureClipper cloud folder is unavailable at $accessibleRootPath.',
      );
      debugPrint(report.message);
      return report;
    }

    final loadedCatalog = catalog ?? await _loadConfiguredCatalog();
    final previews = await _scanConfiguredPreviews(
      accessibleRootPath: accessibleRootPath,
      catalog: loadedCatalog,
    );
    if (previews.isEmpty) {
      final report = PioneerCapturedHtmlAvailableImportReport(
        rootPath: accessibleRootPath,
        imports: const <PioneerCapturedHtmlAvailableImport>[],
        completedAt: completedAt,
        message:
            'No CaptureClipper import folders were found under $accessibleRootPath.',
      );
      debugPrint(report.message);
      return report;
    }

    final imports = <PioneerCapturedHtmlAvailableImport>[];
    for (final preview in previews) {
      if (!_isImportCandidate(preview)) {
        continue;
      }
      final existingState = await _existingImportedCloudFolderState(preview);
      if (existingState != null) {
        final currentHash = preview.sourceFileHash?.trim().toLowerCase() ?? '';
        final storedHash = existingState.fileHash?.trim().toLowerCase() ?? '';
        if (!existingState.needsIndexingAttention &&
            currentHash.isNotEmpty &&
            storedHash.isNotEmpty &&
            currentHash == storedHash) {
          continue;
        }
      }
      imports.add(
        PioneerCapturedHtmlAvailableImport(
          preview: preview,
          existingLibraryItemId: existingState?.libraryItemId,
        ),
      );
    }

    final message = imports.isEmpty
        ? 'No CaptureClipper imports are currently available.'
        : imports.length == 1
        ? '1 CaptureClipper book is ready to import: ${imports.first.displayLabel}.'
        : '${imports.length} CaptureClipper books are ready to import.';
    final report = PioneerCapturedHtmlAvailableImportReport(
      rootPath: accessibleRootPath,
      imports: List<PioneerCapturedHtmlAvailableImport>.unmodifiable(imports),
      completedAt: completedAt,
      message: message,
    );
    debugPrint(
      'CaptureClipper import discovery: ${report.availableCount} ready folder(s) '
      'found under $accessibleRootPath.',
    );
    return report;
  }

  Future<_ExistingImportedCloudFolderState?> _existingImportedCloudFolderState(
    PioneerHtmlCaptureFolderPreview preview,
  ) async {
    final work = preview.importWork;
    final db = await ELibraryDatabase.instance.database;

    final normalizedFileHash = preview.sourceFileHash?.trim() ?? '';
    if (normalizedFileHash.isNotEmpty) {
      final hashRows = await db.query(
        'library_items',
        columns: const ['id', 'file_hash', 'index_status'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(file_hash, '')) = ?
          AND LOWER(COALESCE(file_format, '')) = 'html'
        ''',
        whereArgs: [normalizedFileHash.toLowerCase()],
        limit: 1,
      );
      if (hashRows.isNotEmpty) {
        final row = hashRows.first;
        final id = row['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          return _ExistingImportedCloudFolderState(
            libraryItemId: id,
            fileHash: row['file_hash']?.toString().trim(),
            indexStatus: row['index_status']?.toString().trim(),
          );
        }
      }
    }

    final stableId = work.stableLibraryItemId;
    final stableRows = await db.query(
      'library_items',
      columns: const ['id', 'file_hash', 'index_status'],
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [stableId],
      limit: 1,
    );
    if (stableRows.isNotEmpty) {
      final row = stableRows.first;
      final id = row['id']?.toString().trim() ?? '';
      if (id.isNotEmpty) {
        return _ExistingImportedCloudFolderState(
          libraryItemId: id,
          fileHash: row['file_hash']?.toString().trim(),
          indexStatus: row['index_status']?.toString().trim(),
        );
      }
    }

    if (preview.htmlFiles.isNotEmpty) {
      final relativePath = _buildHtmlCaptureRelativePath(
        work,
        preview.htmlFiles.first,
      );
      final pathRows = await db.query(
        'library_items',
        columns: const ['id', 'file_hash', 'index_status'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(relative_path, '')) = ?
        ''',
        whereArgs: [relativePath.toLowerCase()],
        limit: 1,
      );
      if (pathRows.isNotEmpty) {
        final row = pathRows.first;
        final id = row['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          return _ExistingImportedCloudFolderState(
            libraryItemId: id,
            fileHash: row['file_hash']?.toString().trim(),
            indexStatus: row['index_status']?.toString().trim(),
          );
        }
      }
    }

    final sourceUrl = preview.metadata.sourceUrl?.trim() ?? '';
    if (sourceUrl.isNotEmpty) {
      final sourceRows = await db.query(
        'library_items',
        columns: const ['id', 'file_hash', 'index_status'],
        where: '''
          deleted_at IS NULL
          AND LOWER(COALESCE(source_url, '')) = ?
        ''',
        whereArgs: [sourceUrl.toLowerCase()],
        limit: 1,
      );
      if (sourceRows.isNotEmpty) {
        final row = sourceRows.first;
        final id = row['id']?.toString().trim() ?? '';
        if (id.isNotEmpty) {
          return _ExistingImportedCloudFolderState(
            libraryItemId: id,
            fileHash: row['file_hash']?.toString().trim(),
            indexStatus: row['index_status']?.toString().trim(),
          );
        }
      }
    }

    return null;
  }

  Future<PioneerCapturedHtmlCloudFolderImportReport>
  importConfiguredCloudFolder({
    Iterable<String>? selectedFolderPaths,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    DateTime Function()? nowProvider,
    bool archiveImportedFolders = false,
    bool forceReindex = false,
    Future<PioneerImportBatchResult> Function(
      Iterable<PioneerHtmlCaptureFolderPreview> previews,
    )?
    importPreviews,
    PioneerSourceCatalog? catalog,
  }) async {
    if (archiveImportedFolders) {
      debugPrint(
        'CaptureClipper cloud import: archiveImportedFolders is ignored; '
        'shared source folders are permanent read-only inventory.',
      );
    }
    final accessibleRootPath = await _resolveAccessibleConfiguredRootPath();
    if (accessibleRootPath == null) {
      return PioneerCapturedHtmlCloudFolderImportReport(
        rootPath: '',
        entries: const <PioneerCapturedHtmlCloudFolderImportEntry>[],
        completedAt: DateTime.now(),
      );
    }

    final rootDirectory = Directory(accessibleRootPath);
    if (!await rootDirectory.exists()) {
      debugPrint(
        'CaptureClipper cloud import: folder missing or unavailable at '
        '$accessibleRootPath',
      );
      return PioneerCapturedHtmlCloudFolderImportReport(
        rootPath: accessibleRootPath,
        entries: const <PioneerCapturedHtmlCloudFolderImportEntry>[],
        completedAt: DateTime.now(),
      );
    }

    final previews = await _scanConfiguredPreviews(
      accessibleRootPath: accessibleRootPath,
      catalog: catalog,
    );

    final normalizedSelection = selectedFolderPaths
        ?.map((path) => p.normalize(path.trim()).toLowerCase())
        .where((path) => path.isNotEmpty)
        .toSet();
    final selectablePreviews = previews
        .where((preview) {
          if (!_isImportCandidate(preview)) return false;
          if (normalizedSelection == null) return true;
          return normalizedSelection.contains(
            p.normalize(preview.folderPath).toLowerCase(),
          );
        })
        .toList(growable: false);
    if (selectablePreviews.isEmpty) {
      return PioneerCapturedHtmlCloudFolderImportReport(
        rootPath: accessibleRootPath,
        entries: const <PioneerCapturedHtmlCloudFolderImportEntry>[],
        completedAt: DateTime.now(),
      );
    }

    debugPrint(
      'CaptureClipper cloud import: ${selectablePreviews.length} candidate '
      'folder(s) found under $accessibleRootPath.',
    );

    final batchResult =
        await (importPreviews ??
            ((Iterable<PioneerHtmlCaptureFolderPreview> previews) {
              return _importService.importHtmlCaptureFolders(
                previews,
                existingImportPolicy: existingImportPolicy,
                forceReindex: forceReindex,
              );
            }))(selectablePreviews);
    final completedAt = DateTime.now();
    nowProvider?.call();
    final entries = <PioneerCapturedHtmlCloudFolderImportEntry>[];
    for (var index = 0; index < selectablePreviews.length; index++) {
      final preview = selectablePreviews[index];
      final workResult = batchResult.workResults.length > index
          ? batchResult.workResults[index]
          : null;
      final resultStatus = workResult?.status;
      final libraryItemId = workResult?.libraryItemId.trim() ?? '';
      final itemExists =
          libraryItemId.isNotEmpty &&
          (await LibraryCatalogService.instance.loadItemById(libraryItemId)) !=
              null;
      final importNeedsReview = workResult?.requiresManualVerification == true;
      String? archivePath;
      String? archiveError;
      if (resultStatus == PioneerImportWorkStatus.imported &&
          importNeedsReview) {
        archiveError =
            'Import needs review; the source folder was left in place.';
      } else if (resultStatus == PioneerImportWorkStatus.imported &&
          !itemExists) {
        archiveError =
            'Imported item ${libraryItemId.isEmpty ? '(unknown)' : libraryItemId} was not found in eLibrary.db.';
      }

      entries.add(
        PioneerCapturedHtmlCloudFolderImportEntry(
          folderPath: preview.folderPath,
          folderName: preview.folderName,
          htmlFileCount: preview.htmlFileCount,
          title:
              workResult?.title ?? preview.detectedTitle ?? preview.folderName,
          author:
              workResult?.work.authorName ??
              preview.detectedAuthor ??
              'Unknown',
          coverImported: workResult?.coverImported ?? false,
          chapterCount:
              workResult?.parsedSectionCount ?? preview.chapterHeadingCount,
          firstChapterLabel:
              workResult?.firstSectionLabel ?? preview.firstChapterLabel,
          lastChapterLabel:
              workResult?.lastSectionLabel ?? preview.lastChapterLabel,
          createdNew: workResult?.createdNew ?? false,
          updatedExisting: workResult?.existingItemUpdated ?? false,
          importStatus: resultStatus,
          reason: workResult?.reason ?? preview.warnings.join(' | '),
          libraryItemId: libraryItemId.isEmpty ? null : libraryItemId,
          archivePath: archivePath,
          archiveError: archiveError,
        ),
      );
      final entry = entries.last;
      debugPrint(
        'CaptureClipper cloud import result: folder=${entry.folderName}, '
        'path=${entry.folderPath}, title=${entry.title}, author=${entry.author}, '
        'status=${entry.importStatus?.name ?? '(none)'}, '
        'reason=${entry.reason ?? '(none)'}, '
        'libraryItemId=${entry.libraryItemId ?? '(none)'}, '
        'archivePath=${entry.archivePath ?? '(none)'}, '
        'archiveError=${entry.archiveError ?? '(none)'}',
      );
    }

    return PioneerCapturedHtmlCloudFolderImportReport(
      rootPath: accessibleRootPath,
      entries: List<PioneerCapturedHtmlCloudFolderImportEntry>.unmodifiable(
        entries,
      ),
      completedAt: completedAt,
    );
  }

  Future<PioneerCapturedHtmlCloudFolderImportReport?>
  repairImportedCaptureClipperBook({
    required String libraryItemId,
    DateTime Function()? nowProvider,
    PioneerSourceCatalog? catalog,
  }) async {
    lastRepairFailure = null;
    debugPrint(
      'CaptureClipper repair START: libraryItemId=${libraryItemId.trim()}',
    );
    try {
      final db = await ELibraryDatabase.instance.database;
      final itemRows = await db.query(
        'library_items',
        columns: const [
          'id',
          'title',
          'author',
          'relative_path',
          'source_url',
          'file_hash',
          'source_work_id',
          'source_package_id',
        ],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [libraryItemId.trim()],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        return _repairFailure(
          'No active library_items row exists for id "${libraryItemId.trim()}".',
        );
      }
      final itemRow = itemRows.single;
      final workId = itemRow['source_work_id']?.toString().trim() ?? '';
      final packageId = itemRow['source_package_id']?.toString().trim() ?? '';
      if (workId.isEmpty) {
        return _repairFailure(
          'The current library item has no source_work_id.',
        );
      }
      if (packageId.isEmpty) {
        return _repairFailure(
          'The current library item has no source_package_id.',
        );
      }
      debugPrint(
        'CaptureClipper repair identity: workId=$workId packageId=$packageId.',
      );

      // Package-backed imports are repairable offline. Prefer the preserved
      // Application Support copy and never make iOS depend on a stale Mac or
      // cloud-provider path.
      final managedRoot = await managedImportRootPath();
      final managedPreviews = await _scanPackageRoot(
        rootPath: managedRoot,
        catalog: catalog,
      );
      debugPrint(
        'CaptureClipper repair managed scan: root=$managedRoot '
        'previews=${managedPreviews.length}.',
      );
      var matchingPreview = _matchingPackagePreview(
        managedPreviews,
        workId: workId,
        packageId: packageId,
      );
      if (matchingPreview == null) {
        final accessibleRootPath = await _resolveAccessibleConfiguredRootPath();
        if (accessibleRootPath != null) {
          debugPrint(
            'CaptureClipper repair configured scan: root=$accessibleRootPath.',
          );
          final configuredPreviews = await _scanConfiguredPreviews(
            accessibleRootPath: accessibleRootPath,
            catalog: catalog,
          );
          matchingPreview = _matchingPackagePreview(
            configuredPreviews,
            workId: workId,
            packageId: packageId,
          );
        }
      }
      if (matchingPreview == null) {
        final managedDetails = managedPreviews
            .map((preview) {
              return '${preview.folderPath} '
                  '(valid=${preview.isValid}, workId=${preview.metadata.workId}, '
                  'packageId=${preview.metadata.packageId}, html=${preview.htmlFiles.length}, '
                  'validation=${preview.validationReasons.join('; ')})';
            })
            .join(' | ');
        return _repairFailure(
          'No valid source matched workId=$workId and packageId=$packageId. '
          'Managed scan: ${managedDetails.isEmpty ? '(none)' : managedDetails}.',
        );
      }
      debugPrint(
        'CaptureClipper repair source selected: ${matchingPreview.folderPath} '
        '(workId=${matchingPreview.metadata.workId}, '
        'packageId=${matchingPreview.metadata.packageId}, '
        'html=${matchingPreview.htmlFiles.length}).',
      );

      // Repair is not discovery. The exact existing item and its validated
      // package source are already known, so invoke the production importer
      // directly. Re-scanning configuredRoot/Books would incorrectly apply
      // new-import inventory rules and may reference an obsolete iOS container.
      final batch = await _importService.importHtmlCaptureFolders(
        <PioneerHtmlCaptureFolderPreview>[matchingPreview],
        existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
        forceReindex: true,
      );
      if (batch.workResults.isEmpty) {
        return _repairFailure('Force reindex returned no work result.');
      }
      final result = batch.workResults.single;
      if (result.status != PioneerImportWorkStatus.imported) {
        return _repairFailure(
          'Force reindex failed at ${result.stage}: ${result.reason}',
        );
      }
      if (result.libraryItemId != libraryItemId.trim()) {
        return _repairFailure(
          'Force reindex targeted unexpected item "${result.libraryItemId}" '
          'instead of "${libraryItemId.trim()}".',
        );
      }
      final completedAt = DateTime.now();
      nowProvider?.call();
      final report = PioneerCapturedHtmlCloudFolderImportReport(
        rootPath: matchingPreview.folderPath,
        entries: <PioneerCapturedHtmlCloudFolderImportEntry>[
          PioneerCapturedHtmlCloudFolderImportEntry(
            folderPath: matchingPreview.folderPath,
            folderName: matchingPreview.folderName,
            htmlFileCount: matchingPreview.htmlFileCount,
            title: result.title,
            author: result.work.authorName,
            coverImported: result.coverImported,
            chapterCount:
                result.parsedSectionCount ??
                matchingPreview.chapterHeadingCount,
            firstChapterLabel:
                result.firstSectionLabel ?? matchingPreview.firstChapterLabel,
            lastChapterLabel:
                result.lastSectionLabel ?? matchingPreview.lastChapterLabel,
            createdNew: result.createdNew,
            updatedExisting: result.existingItemUpdated,
            importStatus: result.status,
            reason: result.reason,
            libraryItemId: result.libraryItemId,
            archivePath: null,
            archiveError: null,
          ),
        ],
        completedAt: completedAt,
      );
      debugPrint(
        'CaptureClipper repair SUCCESS: ${report.entries.length} result(s).',
      );
      return report;
    } catch (error, stackTrace) {
      debugPrint('CaptureClipper repair EXCEPTION: $error\n$stackTrace');
      return _repairFailure('Repair threw ${error.runtimeType}: $error');
    }
  }

  Future<List<PioneerHtmlCaptureFolderPreview>> _scanPackageRoot({
    required String rootPath,
    PioneerSourceCatalog? catalog,
  }) async {
    if (!await Directory(rootPath).exists()) {
      debugPrint('CaptureClipper repair scan: directory missing: $rootPath.');
      return const <PioneerHtmlCaptureFolderPreview>[];
    }
    return PioneerHtmlCaptureFolderScanner(
      rootPath: rootPath,
      preferAssetManifest: false,
      knownDevScanPath: null,
      ignoredFolderNames: _ignoredConfiguredFolderNames,
    ).scan(catalog: catalog ?? await _loadConfiguredCatalog());
  }

  PioneerHtmlCaptureFolderPreview? _matchingPackagePreview(
    Iterable<PioneerHtmlCaptureFolderPreview> previews, {
    required String workId,
    required String packageId,
  }) {
    for (final preview in previews) {
      debugPrint(
        'CaptureClipper repair candidate: path=${preview.folderPath} '
        'valid=${preview.isValid} workId=${preview.metadata.workId} '
        'packageId=${preview.metadata.packageId} html=${preview.htmlFiles.length} '
        'validation=${preview.validationReasons.join('; ')}.',
      );
      if (preview.isValid &&
          preview.metadata.workId?.trim() == workId &&
          preview.metadata.packageId?.trim() == packageId &&
          preview.htmlFiles.isNotEmpty) {
        return preview;
      }
    }
    return null;
  }

  bool _isImportCandidate(PioneerHtmlCaptureFolderPreview preview) {
    if (!preview.isValid) return false;
    final normalizedFolderName = preview.folderName.trim().toLowerCase();
    if (normalizedFolderName.isEmpty) return false;
    return !_ignoredConfiguredFolderNames.contains(normalizedFolderName);
  }

  String _buildHtmlCaptureRelativePath(
    PioneerSourceWork work,
    String htmlFilePath,
  ) {
    final authorSegment = _htmlCaptureSlug(work.authorName);
    final fileStem = work.abbreviation.trim().isNotEmpty
        ? work.abbreviation.trim()
        : _htmlCaptureSlug(work.title);
    final fileName = p.basename(htmlFilePath).trim().isEmpty
        ? 'capture.html'
        : p.basename(htmlFilePath);
    return p.join(
      'TextCaptures',
      'Research',
      'Pioneer Authors',
      authorSegment.isEmpty ? 'unknown_author' : authorSegment,
      fileStem.isEmpty ? _htmlCaptureSlug(work.title) : fileStem,
      fileName,
    );
  }

  String _htmlCaptureSlug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _inspectStoredCaptureClipperItems() async {
    final db = await ELibraryDatabase.instance.database;
    final catalog = await PioneerSourceCatalog.load();
    final rows = await db.query(
      'library_items',
      columns: const [
        'id',
        'title',
        'author',
        'cover_path',
        'source_type',
        'collection_name',
      ],
      where: '''
        deleted_at IS NULL
        AND (
          LOWER(COALESCE(source_type, '')) LIKE '%html_capture%'
          OR LOWER(COALESCE(collection_name, '')) = 'adventist pioneer library'
        )
      ''',
    );

    for (final row in rows) {
      final itemId = row['id']?.toString().trim() ?? '';
      if (itemId.isEmpty) continue;
      final title = row['title']?.toString().trim() ?? '';
      final author = row['author']?.toString().trim() ?? '';
      final coverPath = row['cover_path']?.toString().trim() ?? '';
      final brokenReasons = <String>[];
      if (_looksLikeBadCapturedHtmlTitle(title)) {
        brokenReasons.add('bad title');
      }
      if (author.isEmpty ||
          author.toLowerCase() == 'unknown' ||
          author.toLowerCase() == 'unknown author') {
        brokenReasons.add('unknown author');
      }
      if (coverPath.isEmpty || !File(coverPath).existsSync()) {
        brokenReasons.add('missing cover');
      }
      if (brokenReasons.isEmpty) continue;

      debugPrint(
        'Repair Broken CaptureClipper Items: item=$itemId needs ${brokenReasons.join(', ')}.',
      );
      try {
        final hydrated = await LibraryCatalogService.instance.loadItemById(
          itemId,
        );
        final repairRow = <String, Object?>{};
        final catalogWork = _captureClipperCatalogWorkForRow(
          row,
          catalog: catalog,
        );
        if (catalogWork != null) {
          if (_looksLikeBadCapturedHtmlTitle(title)) {
            repairRow['title'] = catalogWork.title;
          }
          if (author.isEmpty ||
              author.toLowerCase() == 'unknown' ||
              author.toLowerCase() == 'unknown author') {
            repairRow['author'] = catalogWork.authorName;
          }
          final catalogCoverPath = catalogWork.cachedCoverPath?.trim() ?? '';
          if (coverPath.isEmpty ||
              !File(coverPath).existsSync() &&
                  catalogCoverPath.isNotEmpty &&
                  File(catalogCoverPath).existsSync()) {
            repairRow['cover_path'] = catalogCoverPath;
          }
        }
        if (repairRow.isNotEmpty) {
          repairRow['updated_at'] = DateTime.now().toUtc().toIso8601String();
          await db.update(
            'library_items',
            repairRow,
            where: 'id = ?',
            whereArgs: [itemId],
          );
        }
        if (hydrated == null) {
          debugPrint(
            'CaptureClipper item could not be repaired because source files are missing/invalid: '
            '$itemId reason=catalog row unavailable',
          );
          continue;
        }
        final remainingReasons = <String>[];
        if (_looksLikeBadCapturedHtmlTitle(hydrated.displayTitle)) {
          remainingReasons.add('title');
        }
        if (hydrated.displayAuthor.trim().isEmpty ||
            hydrated.displayAuthor.toLowerCase() == 'unknown author') {
          remainingReasons.add('author');
        }
        if (hydrated.coverPath == null ||
            !File(hydrated.coverPath!).existsSync()) {
          remainingReasons.add('cover');
        }
        if (remainingReasons.isNotEmpty) {
          debugPrint(
            'CaptureClipper item could not be fully repaired because source files are missing/invalid: '
            '$itemId remaining=${remainingReasons.join(', ')}',
          );
        }
      } catch (error) {
        debugPrint(
          'CaptureClipper item could not be repaired because source files are missing/invalid: '
          '$itemId error=$error',
        );
      }
    }
  }

  PioneerSourceWork? _captureClipperCatalogWorkForRow(
    Map<String, Object?> row, {
    required PioneerSourceCatalog catalog,
  }) {
    final candidateKeys = <String>{};
    final sourceUrl = row['source_url']?.toString().trim() ?? '';
    final relativePath = row['relative_path']?.toString().trim() ?? '';
    final itemId = row['id']?.toString().trim() ?? '';

    void addCandidateFromPath(String value) {
      if (value.trim().isEmpty) return;
      final normalized = value.replaceAll('\\', '/');
      final baseName = p.basename(p.dirname(normalized)).trim();
      if (baseName.isNotEmpty) candidateKeys.add(baseName.toLowerCase());
      final folderName = p.basename(normalized).trim();
      if (folderName.isNotEmpty) candidateKeys.add(folderName.toLowerCase());
    }

    addCandidateFromPath(sourceUrl);
    addCandidateFromPath(relativePath);

    if (itemId.isNotEmpty) {
      final tokens = itemId.split('_');
      if (tokens.isNotEmpty) candidateKeys.add(tokens.last.toLowerCase());
    }

    for (final work in catalog.works) {
      final abbreviation = work.abbreviation.trim().toLowerCase();
      final workId = work.id.trim().toLowerCase();
      if (candidateKeys.contains(abbreviation) ||
          candidateKeys.contains(workId)) {
        return work;
      }
    }
    return null;
  }

  Future<PioneerCapturedHtmlFolderImportReport> scanConfiguredFolder({
    bool importFiles = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    PioneerSourceCatalog? catalog,
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
    final loadedCatalog = catalog ?? await _loadConfiguredCatalog();
    return scanFolder(
      folderPath: folderPath,
      importFiles: importFiles,
      existingImportPolicy: existingImportPolicy,
      catalog: loadedCatalog,
    );
  }

  Future<PioneerCapturedHtmlFolderImportReport> scanFolder({
    required String folderPath,
    bool importFiles = false,
    PioneerExistingImportPolicy existingImportPolicy =
        PioneerExistingImportPolicy.skipExisting,
    PioneerSourceCatalog? catalog,
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
          catalog: catalog,
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
    PioneerSourceCatalog? catalog,
  }) async {
    final loadedCatalog = catalog ?? await _loadConfiguredCatalog();
    final report = await scanConfiguredFolder(
      importFiles: true,
      existingImportPolicy: existingImportPolicy,
      catalog: loadedCatalog,
    );
    try {
      await PioneerCapturedHtmlImportReviewStore.instance.recordEntries(
        _reviewEntriesFromReport(report),
      );
    } catch (error) {
      debugPrint('Failed to persist CaptureClipper import review: $error');
    }
    return report;
  }

  Future<PioneerCapturedHtmlCloudFolderImportReport>
  repairBrokenCaptureClipperItems({DateTime Function()? nowProvider}) async {
    final report = await importConfiguredCloudFolder(
      existingImportPolicy: PioneerExistingImportPolicy.overwriteExisting,
      nowProvider: nowProvider,
    );
    await _inspectStoredCaptureClipperItems();
    return report;
  }

  Future<PioneerCapturedHtmlFileReport> _analyzeFile({
    required Database db,
    required String rootPath,
    required String filePath,
    required bool importFiles,
    required PioneerExistingImportPolicy existingImportPolicy,
    PioneerSourceCatalog? catalog,
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
    final resolvedTitle = _resolveCapturedTitle(
      parsed: parsed,
      metadata: metadata,
      filePath: filePath,
      catalog: catalog,
    );
    final resolvedAuthor = _resolveCapturedAuthor(
      parsed: parsed,
      metadata: metadata,
      filePath: filePath,
      catalog: catalog,
    );
    final resolvedCoverImagePath =
        await _discoverFolderCoverImage(rootPath) ?? parsed.coverImagePath;
    final work = _workFromParsed(
      parsed: parsed,
      title: resolvedTitle,
      authorName: resolvedAuthor,
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
    var importWork = work;
    if (duplicate != null) {
      final existingHash = duplicate['file_hash']?.toString().trim() ?? '';
      final existingPath = duplicate['relative_path']?.toString().trim() ?? '';
      final sameHash =
          existingHash.isNotEmpty &&
          existingHash.toLowerCase() == fileHash.toLowerCase();
      final samePath =
          existingPath.isNotEmpty &&
          existingPath.toLowerCase() == storageRelativePath.toLowerCase();
      final duplicateId = duplicate['id']?.toString().trim() ?? '';
      if (importFiles &&
          existingImportPolicy ==
              PioneerExistingImportPolicy.overwriteExisting &&
          duplicateId.isNotEmpty) {
        importWork = importWork.copyWith(id: duplicateId);
      } else if (importFiles &&
          existingImportPolicy == PioneerExistingImportPolicy.importAsNewCopy) {
        debugPrint(
          'CaptureClipper import duplicate matched but new-copy policy '
          'selected for ${work.title}; creating a fresh library item.',
        );
      } else {
        return PioneerCapturedHtmlFileReport(
          filePath: filePath,
          relativePath: relativePath,
          fileHash: fileHash,
          sourceFileHash: fileHash,
          title: resolvedTitle,
          author: resolvedAuthor,
          sourceType: metadata.sourceType?.trim().isNotEmpty == true
              ? metadata.sourceType!.trim()
              : 'pioneer_captured_html',
          sourceSite: parsed.sourceSite,
          sourceUrl: parsed.sourceUrl,
          coverImagePath: resolvedCoverImagePath,
          coverImported: false,
          headingCount: parsed.headingCount,
          paragraphCount: parsed.paragraphCount,
          sectionCount: parsed.document.sections.length,
          firstChapterLabel: parsed.document.sections.isEmpty
              ? null
              : parsed.document.sections.first.title,
          lastChapterLabel: parsed.document.sections.isEmpty
              ? null
              : parsed.document.sections.last.title,
          createdNew: false,
          existingItemUpdated: false,
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
    }

    final reportStatus = parsed.needsCleanup
        ? PioneerCapturedHtmlFileStatus.needsCleanup
        : PioneerCapturedHtmlFileStatus.ready;
    if (!importFiles) {
      return PioneerCapturedHtmlFileReport(
        filePath: filePath,
        relativePath: relativePath,
        fileHash: fileHash,
        sourceFileHash: fileHash,
        title: resolvedTitle,
        author: resolvedAuthor,
        sourceType: work.sourceType ?? 'pioneer_captured_html',
        sourceSite: parsed.sourceSite,
        sourceUrl: parsed.sourceUrl,
        coverImagePath: resolvedCoverImagePath,
        coverImported: false,
        headingCount: parsed.headingCount,
        paragraphCount: parsed.paragraphCount,
        sectionCount: parsed.document.sections.length,
        firstChapterLabel: parsed.document.sections.isEmpty
            ? null
            : parsed.document.sections.first.title,
        lastChapterLabel: parsed.document.sections.isEmpty
            ? null
            : parsed.document.sections.last.title,
        createdNew: false,
        existingItemUpdated: false,
        warnings: parsed.warnings,
        status: reportStatus,
        reason: parsed.warnings.isEmpty ? null : parsed.warnings.join(' | '),
      );
    }

    final importResult = await _importService.importFromParsedCapturedHtml(
      work: importWork,
      document: parsed.document,
      sourceBytes: rawBytes,
      sourceUrl: parsed.sourceUrl,
      sourceType: 'pioneer_captured_html',
      sourceSite: parsed.sourceSite,
      relativePath: _virtualRelativePath(importWork, relativePath),
      coverPath: resolvedCoverImagePath,
      existingImportPolicy: existingImportPolicy,
      indexStatus: parsed.needsCleanup
          ? 'partially_imported_needs_review'
          : 'indexed',
      indexError: parsed.warnings.isEmpty ? null : parsed.warnings.join(' | '),
    );
    final result = importResult.workResults.isEmpty
        ? null
        : importResult.workResults.first;
    final resolvedLibraryItemId = result == null
        ? ''
        : result.libraryItemId.trim();
    final fileStatus = result == null
        ? PioneerCapturedHtmlFileStatus.failed
        : switch (result.status) {
            PioneerImportWorkStatus.imported =>
              reportStatus == PioneerCapturedHtmlFileStatus.needsCleanup
                  ? PioneerCapturedHtmlFileStatus.needsCleanup
                  : PioneerCapturedHtmlFileStatus.imported,
            PioneerImportWorkStatus.skippedExisting =>
              PioneerCapturedHtmlFileStatus.skippedDuplicate,
            PioneerImportWorkStatus.packageLineageConflict ||
            PioneerImportWorkStatus.skippedNotImportable ||
            PioneerImportWorkStatus.skippedUnsupportedSource ||
            PioneerImportWorkStatus.failed =>
              PioneerCapturedHtmlFileStatus.failed,
          };
    return PioneerCapturedHtmlFileReport(
      filePath: filePath,
      relativePath: relativePath,
      fileHash: fileHash,
      sourceFileHash: fileHash,
      title: importWork.title,
      author: importWork.authorName,
      sourceType: importWork.sourceType ?? 'pioneer_captured_html',
      sourceSite: parsed.sourceSite,
      sourceUrl: parsed.sourceUrl,
      coverImagePath: resolvedCoverImagePath,
      coverImported: result?.coverImported ?? false,
      headingCount: parsed.headingCount,
      paragraphCount: parsed.paragraphCount,
      sectionCount: parsed.document.sections.length,
      firstChapterLabel: parsed.document.sections.isEmpty
          ? null
          : parsed.document.sections.first.title,
      lastChapterLabel: parsed.document.sections.isEmpty
          ? null
          : parsed.document.sections.last.title,
      createdNew: result?.createdNew ?? false,
      existingItemUpdated: result?.existingItemUpdated ?? false,
      warnings: parsed.warnings,
      status: fileStatus,
      reason: result?.reason ?? parsed.warnings.join(' | '),
      libraryItemId: resolvedLibraryItemId.isNotEmpty
          ? resolvedLibraryItemId
          : null,
    );
  }
}

Iterable<PioneerCapturedHtmlImportReviewEntry> _reviewEntriesFromReport(
  PioneerCapturedHtmlFolderImportReport report,
) sync* {
  for (var index = 0; index < report.files.length; index++) {
    final file = report.files[index];
    yield PioneerCapturedHtmlImportReviewEntry(
      importedAt: report.completedAt.add(Duration(microseconds: index)),
      title: file.title,
      author: file.author,
      sourceFilePath: file.filePath,
      sourceRelativePath: file.relativePath,
      sourceType: file.sourceType,
      status: file.status.name,
      warningOrFailureReason:
          file.status == PioneerCapturedHtmlFileStatus.needsCleanup
          ? (file.warnings.isEmpty
                ? file.reason?.trim()
                : file.warnings.join(' | '))
          : file.reason?.trim().isNotEmpty == true
          ? file.reason!.trim()
          : file.warnings.isEmpty
          ? null
          : file.warnings.join(' | '),
      libraryItemId: file.libraryItemId?.trim().isNotEmpty == true
          ? file.libraryItemId!.trim()
          : null,
    );
  }
}

PioneerCaptureFolderMetadata _folderMetadataFor(String filePath) {
  final folder = Directory(p.dirname(filePath));
  return PioneerCaptureFolderMetadata.fromFolder(folder);
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
  required String title,
  required String authorName,
  required String relativePath,
  required String filePath,
  required PioneerCaptureFolderMetadata metadata,
  required String fileHash,
}) {
  final fileStem = p.basenameWithoutExtension(filePath);
  final authorId = _stableId(
    authorName == 'Unknown' ? 'unknown_$relativePath' : authorName,
  );
  final workId = metadata.workId?.trim().isNotEmpty == true
      ? _stableId(metadata.workId!.trim())
      : _stableId(relativePath.isNotEmpty ? relativePath : fileStem);
  final abbreviation = _capturedHtmlAbbreviation(
    metadata.preferredAbbreviation,
    title: title,
    fileStem: fileStem,
    fileHash: fileHash,
  );
  final notes = parsed.warnings.isEmpty ? null : parsed.warnings.join(' ');
  return PioneerSourceWork(
    id: workId,
    authorId: authorId,
    authorName: authorName,
    sourceFamily: 'Pioneer',
    title: title,
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

String _resolveCapturedTitle({
  required PioneerCapturedHtmlParseResult parsed,
  required PioneerCaptureFolderMetadata metadata,
  required String filePath,
  PioneerSourceCatalog? catalog,
}) {
  final folderName = p.basename(p.dirname(filePath)).trim();
  final metadataTitle = metadata.title?.trim() ?? '';
  final catalogWork = catalog == null
      ? null
      : _findCatalogWork(
          catalog,
          parsed: parsed,
          metadata: metadata,
          filePath: filePath,
        );
  if (catalogWork != null &&
      looksLikeCaptureFolderPlaceholderTitle(
        metadataTitle,
        folderCode: folderName,
        abbreviation: metadata.preferredAbbreviation,
      )) {
    return catalogWork.title;
  }
  if (metadataTitle.isNotEmpty) return metadataTitle;

  final parsedTitle = parsed.title.trim();
  if (parsedTitle.isNotEmpty &&
      !_looksLikeSectionOrChapterHeading(parsedTitle)) {
    return parsedTitle;
  }
  final normalizedFolderName = folderName.toUpperCase();
  final folderCode = RegExp(
    r'^[A-Z]{2,8}',
  ).firstMatch(normalizedFolderName)?.group(0)?.trim();
  if (folderCode != null &&
      folderCode.isNotEmpty &&
      folderName == normalizedFolderName) {
    return folderCode;
  }

  final fileStem = p.basenameWithoutExtension(filePath).trim();
  if (fileStem.isNotEmpty) return _titleCaseFromFileStem(fileStem);

  return 'Captured HTML';
}

PioneerSourceWork? _findCatalogWork(
  PioneerSourceCatalog catalog, {
  required PioneerCapturedHtmlParseResult parsed,
  required PioneerCaptureFolderMetadata metadata,
  required String filePath,
}) {
  final folderName = p.basename(p.dirname(filePath));
  final normalizedTitle = _stableTextKey(metadata.title?.trim() ?? '');
  final normalizedDetectedTitle = _stableTextKey(parsed.title);
  final normalizedFolder = _stableTextKey(folderName);
  final normalizedAbbreviation = _stableTextKey(
    metadata.preferredAbbreviation ?? folderName,
  );

  for (final work in catalog.works) {
    if (normalizedTitle.isNotEmpty &&
        _stableTextKey(work.title) == normalizedTitle) {
      return work;
    }
    if (normalizedDetectedTitle.isNotEmpty &&
        _stableTextKey(work.title) == normalizedDetectedTitle) {
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

String _resolveCapturedAuthor({
  required PioneerCapturedHtmlParseResult parsed,
  required PioneerCaptureFolderMetadata metadata,
  required String filePath,
  PioneerSourceCatalog? catalog,
}) {
  final metadataAuthor = metadata.primaryContributorName?.trim() ?? '';
  final catalogWork = catalog == null
      ? null
      : _findCatalogWork(
          catalog,
          parsed: parsed,
          metadata: metadata,
          filePath: filePath,
        );
  final folderName = p.basename(p.dirname(filePath)).trim();
  final placeholderMetadataAuthor =
      metadataAuthor.isEmpty ||
      metadataAuthor.toLowerCase() == 'unknown' ||
      metadataAuthor.toLowerCase() == 'unknown author' ||
      looksLikeCaptureFolderPlaceholderTitle(
        metadataAuthor,
        folderCode: folderName,
        abbreviation: metadata.preferredAbbreviation,
      );
  final catalogAuthor = catalogWork?.authorName.trim() ?? '';
  if (catalogAuthor.isNotEmpty && placeholderMetadataAuthor) {
    return catalogAuthor;
  }
  if (metadataAuthor.isNotEmpty && !placeholderMetadataAuthor) {
    return metadataAuthor;
  }
  if (catalogAuthor.isNotEmpty) return catalogAuthor;

  final parsedAuthor = parsed.author.trim();
  if (parsedAuthor.isNotEmpty && parsedAuthor.toLowerCase() != 'unknown') {
    return parsedAuthor;
  }

  final folderAuthor = _authorFromFolderName(folderName);
  if (folderAuthor != null && folderAuthor.trim().isNotEmpty) {
    return folderAuthor.trim();
  }

  return 'Unknown';
}

String? _authorFromFolderName(String folderName) {
  final upper = folderName.toUpperCase();
  if (upper.endsWith('_ATJ')) return 'A. T. Jones';
  if (upper.endsWith('_EJW')) return 'E. J. Waggoner';
  if (upper.endsWith('_US')) return 'Uriah Smith';
  if (upper.endsWith('_JNA')) return 'J. N. Andrews';
  return null;
}

Future<String?> _discoverFolderCoverImage(String rootPath) async {
  final folder = Directory(rootPath);
  if (!await folder.exists()) return null;

  final imageFiles = <String>[];
  await for (final entity in folder.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!_isImageFile(entity.path)) continue;
    imageFiles.add(p.normalize(entity.path));
  }
  if (imageFiles.isEmpty) return null;
  imageFiles.sort();

  const priorityNames = <String>[
    'cover.png',
    'cover.jpg',
    'cover.jpeg',
    'thumbnail.png',
    'thumbnail.jpg',
    'thumbnail.jpeg',
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

bool _isImageFile(String path) {
  switch (p.extension(path).toLowerCase()) {
    case '.png':
    case '.jpg':
    case '.jpeg':
    case '.webp':
    case '.gif':
    case '.bmp':
      return true;
    default:
      return false;
  }
}

bool _looksLikeSectionOrChapterHeading(String value) {
  final normalized = value.trim().toLowerCase();
  return RegExp(r'^(chapter|section)\s+\d+\b').hasMatch(normalized);
}

bool _looksLikeBadCapturedHtmlTitle(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  if (normalized.contains('...')) return true;
  return looksLikeCaptureFolderPlaceholderTitle(value) ||
      _looksLikeSectionOrChapterHeading(value) ||
      normalized.startsWith('chapter 0') ||
      normalized.startsWith('section 0');
}

String _stableTextKey(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
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

  void flush({bool allowEmpty = false}) {
    if (currentParagraphs.isEmpty && !allowEmpty) return;
    if (currentParagraphs.isEmpty && currentHeading.trim().isEmpty) return;
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
      if (currentParagraphs.isEmpty && sections.isNotEmpty) {
        flush(allowEmpty: true);
      } else {
        flush();
      }
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
  if (title.isNotEmpty && !_looksLikeSectionOrChapterHeading(title)) {
    return title;
  }
  for (final heading in _headingTexts(bodyHtml)) {
    if (heading.isNotEmpty && !_looksLikeSectionOrChapterHeading(heading)) {
      return heading;
    }
  }
  final folderName = p.basename(p.dirname(filePath)).trim();
  if (folderName.isNotEmpty && !_looksLikeSectionOrChapterHeading(folderName)) {
    return folderName;
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
    r'<(/?)(h[1-3]|p|li|blockquote|div|b|strong)\b([^>]*)>',
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
    if ((tag == 'b' || tag == 'strong') &&
        _hasInlineContainingBlock(stack, openIndex)) {
      continue;
    }
    if (tag.startsWith('h')) {
      blocks.add(
        _HtmlBlock(
          kind: 'heading',
          text: text,
          level: int.tryParse(tag.substring(1)),
        ),
      );
    } else if (tag == 'b' || tag == 'strong') {
      blocks.add(_HtmlBlock(kind: 'heading', text: text, level: null));
    } else {
      if (tag == 'div' &&
          RegExp(
            r'<(/?)(h[1-3]|p|li|blockquote|b|strong)\b',
            caseSensitive: false,
          ).hasMatch(innerHtml)) {
        continue;
      }
      final splitHeading = _splitLeadingChapterHeading(text);
      if (splitHeading != null) {
        blocks.add(
          _HtmlBlock(kind: 'heading', text: splitHeading.heading, level: null),
        );
        if (splitHeading.body.isNotEmpty) {
          blocks.add(
            _HtmlBlock(kind: 'paragraph', text: splitHeading.body, level: null),
          );
        }
      } else {
        blocks.add(_HtmlBlock(kind: 'paragraph', text: text, level: null));
      }
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

bool _hasInlineContainingBlock(List<_OpenBlock> stack, int openIndex) {
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

class _LeadingChapterHeadingSplit {
  const _LeadingChapterHeadingSplit({
    required this.heading,
    required this.body,
  });

  final String heading;
  final String body;
}

_LeadingChapterHeadingSplit? _splitLeadingChapterHeading(String text) {
  final normalized = _cleanHtmlText(text);
  if (normalized.isEmpty) return null;
  if (normalized.contains('pg.') ||
      RegExp(r'\.{4,}').hasMatch(normalized) ||
      normalized.contains('....')) {
    return null;
  }

  final match = RegExp(
    r'^(Chapter|Section)\s+(\d+)\s*[\.\-—]\s*(.+?)(?=\s+[A-Z]{2,8}\s+\d+(?:\.\d+)?\b|$)',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(normalized);
  if (match == null) return null;

  final label = match.group(1) ?? 'Chapter';
  final number = match.group(2) ?? '1';
  final title = _cleanHtmlText(match.group(3));
  final heading = title.isEmpty
      ? '${label[0].toUpperCase()}${label.substring(1).toLowerCase()} $number'
      : '${label[0].toUpperCase()}${label.substring(1).toLowerCase()} $number — $title';
  final body = _cleanHtmlText(normalized.substring(match.end));

  return _LeadingChapterHeadingSplit(heading: heading, body: body);
}
