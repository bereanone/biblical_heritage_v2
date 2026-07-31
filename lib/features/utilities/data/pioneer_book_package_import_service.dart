import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import 'pioneer_captured_html_import_folder_service.dart';
import 'pioneer_capture_folder_metadata.dart';

/// Resolves the stable book code from a `.studybook`/`.zip` package file name
/// by stripping a trailing capture-date suffix:
/// `CSCP07-5-2026` -> `CSCP`, `SDP07-5-2026` -> `SDP`, `DAR1897` -> `DAR1897`.
String studybookBookCodeFromPackageName(String packagePath) {
  var base = p.basename(packagePath).trim();
  // Some export/backup tools append a redundant .zip suffix on top of
  // .studybook (e.g. "CWCP07-05-2026.studybook.zip"); strip whichever
  // known package suffix is present before parsing the date suffix below.
  for (final suffix in const ['.studybook.zip', '.studybook', '.zip']) {
    if (base.toLowerCase().endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
      break;
    }
  }
  final stripped = base
      .replaceFirst(RegExp(r'[\s_.-]*\d{1,2}-\d{1,2}-\d{4}$'), '')
      .trim();
  final candidate = stripped.isEmpty ? base : stripped;
  final sanitized = candidate.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
  return sanitized.isEmpty ? 'package' : sanitized;
}

class PioneerBookPackageImportException implements Exception {
  const PioneerBookPackageImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class PioneerBookPackageImportResult {
  const PioneerBookPackageImportResult({
    required this.sourcePackagePath,
    required this.managedRootPath,
    required this.destinationFolderPath,
    required this.bookCode,
    required this.workId,
    required this.packageId,
    required this.extractedFilePaths,
    required this.htmlFileCount,
  });

  final String sourcePackagePath;
  final String managedRootPath;
  final String destinationFolderPath;
  final String bookCode;
  final String workId;
  final String packageId;
  final List<String> extractedFilePaths;
  final int htmlFileCount;
}

/// Imports a single `.studybook` (or `.zip`) CaptureClipper book package
/// picked from the iOS Files app. The selected package is a read-only input:
/// it is only read as bytes and never moved, renamed, deleted, or rewritten.
/// Its contents are unpacked into the app-managed
/// `<Application Support>/ImportedCaptureClipper/<BOOKCODE>/` folder so the
/// existing CaptureClipper folder scanner/importer can pick the book up.
class PioneerBookPackageImportService {
  static final PioneerBookPackageImportService instance =
      PioneerBookPackageImportService();

  PioneerBookPackageImportService({LocalSettingsStore? settingsStore})
    : _settingsStore = settingsStore ?? LocalSettingsStore.instance;

  final LocalSettingsStore _settingsStore;

  static const Set<String> supportedPackageExtensions = <String>{
    '.studybook',
    '.studybook.zip',
  };

  static const Set<String> _htmlExtensions = <String>{'.html', '.htm'};

  Future<String> managedImportRootPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(
      supportDir.path,
      PioneerCapturedHtmlImportFolderService.managedImportFolderName,
    );
  }

  Future<PioneerBookPackageImportResult> importPackage(
    String packagePath, {
    String? managedRootPath,
    bool setAsConfiguredFolder = true,
    String? expectedWorkId,
    String? expectedPackageId,
  }) async {
    final sourcePath = packagePath.trim();
    if (sourcePath.isEmpty) {
      throw const PioneerBookPackageImportException(
        'No package file was selected.',
      );
    }
    final lowerSourcePath = sourcePath.toLowerCase();
    final isSupportedPackage = supportedPackageExtensions.any(
      lowerSourcePath.endsWith,
    );
    if (!isSupportedPackage) {
      final packageExtension = p.extension(sourcePath).toLowerCase();
      throw PioneerBookPackageImportException(
        'Unsupported package type "$packageExtension". Please select a '
        '.studybook CaptureClipper package.',
      );
    }
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw PioneerBookPackageImportException(
        'The selected package no longer exists at $sourcePath.',
      );
    }

    // Read-only access to the picked package; the source is never modified.
    final packageBytes = await sourceFile.readAsBytes();
    // ZIP files start with a "PK" local-file or end-of-central-directory
    // signature; ZipDecoder silently yields an empty archive for garbage.
    if (packageBytes.length < 4 ||
        packageBytes[0] != 0x50 ||
        packageBytes[1] != 0x4B) {
      throw const PioneerBookPackageImportException(
        'The selected package is not a valid ZIP archive.',
      );
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(packageBytes, verify: true);
    } catch (error) {
      throw PioneerBookPackageImportException(
        'The selected package is not a valid ZIP archive: $error',
      );
    }

    // Detect a single top-level wrapper folder, which is the normal result
    // of compressing a folder directly (e.g. macOS Finder's "Compress"),
    // and treat its contents as the package root rather than requiring
    // manifest.json to sit at the literal archive root.
    String? commonRootPrefix;
    {
      final candidateNames = archive
          .map((entry) => entry.name.replaceAll('\\', '/').trim())
          .where((name) => name.isNotEmpty && !_isIgnoredArchivePath(name))
          .toList(growable: false);
      if (candidateNames.isNotEmpty) {
        final firstSlash = candidateNames.first.indexOf('/');
        if (firstSlash > 0) {
          final prefix = candidateNames.first.substring(0, firstSlash + 1);
          if (candidateNames.every((name) => name.startsWith(prefix))) {
            commonRootPrefix = prefix;
          }
        }
      }
    }
    String stripRootPrefix(String name) {
      final prefix = commonRootPrefix;
      if (prefix != null && name.startsWith(prefix)) {
        return name.substring(prefix.length);
      }
      return name;
    }

    final fileEntries = <ArchiveFile>[];
    const maxEntries = 10000;
    const maxExpandedBytes = 1024 * 1024 * 1024;
    var expandedBytes = 0;
    final entryNames = <String>{};
    for (final entry in archive) {
      final entryName = stripRootPrefix(
        entry.name.replaceAll('\\', '/').trim(),
      );
      if (entryName.isEmpty || _isIgnoredArchivePath(entryName)) continue;
      _ensureSafeArchivePath(entryName);
      if (entry.isSymbolicLink) {
        throw PioneerBookPackageImportException(
          'Package entry "$entryName" is a symbolic link.',
        );
      }
      if (!entry.isFile) continue;
      if (!entryNames.add(entryName)) {
        throw PioneerBookPackageImportException(
          'Package contains duplicate entry "$entryName".',
        );
      }
      expandedBytes += entry.size;
      if (entryNames.length > maxEntries) {
        throw const PioneerBookPackageImportException(
          'Package contains too many entries.',
        );
      }
      if (expandedBytes > maxExpandedBytes) {
        throw const PioneerBookPackageImportException(
          'Package expanded size is too large.',
        );
      }
      fileEntries.add(entry);
    }
    if (fileEntries.isEmpty) {
      throw const PioneerBookPackageImportException(
        'The selected package is empty.',
      );
    }
    final manifests = fileEntries
        .where(
          (entry) =>
              stripRootPrefix(entry.name.replaceAll('\\', '/').trim()) ==
              'manifest.json',
        )
        .toList();
    if (manifests.length != 1) {
      throw const PioneerBookPackageImportException(
        'Package must contain exactly one root manifest.json.',
      );
    }
    String relativeEntryPath(ArchiveFile entry) {
      return stripRootPrefix(entry.name.replaceAll('\\', '/').trim());
    }

    final manifestData = json.decode(
      utf8.decode(manifests.single.readBytes()!),
    );
    if (manifestData is! Map<String, Object?>) {
      throw const PioneerBookPackageImportException(
        'Manifest is not a JSON object.',
      );
    }
    final parsedMetadata = PioneerCaptureFolderMetadata.fromManifestMap(
      manifestData,
      folderPath: '',
    );
    if (parsedMetadata.hasManifestError) {
      throw PioneerBookPackageImportException(parsedMetadata.manifestError!);
    }
    if (parsedMetadata.schemaVersion != 1 &&
        parsedMetadata.schemaVersion != 2) {
      throw const PioneerBookPackageImportException(
        'Only schema-1 and schema-2 packages are supported.',
      );
    }
    final metadata = _withSynthesizedLegacyIdentity(
      parsedMetadata,
      packageBytes: packageBytes,
      sourcePath: sourcePath,
    );
    if (!RegExp(r'^[A-Z][A-Z0-9_-]{1,63}$').hasMatch(metadata.workId ?? '') ||
        (metadata.packageId?.trim().isEmpty ?? true) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(metadata.contentHash ?? '')) {
      throw const PioneerBookPackageImportException(
        'Manifest package identity is invalid.',
      );
    }
    if ((expectedWorkId?.trim().isNotEmpty ?? false) &&
        metadata.workId != expectedWorkId!.trim()) {
      throw PioneerBookPackageImportException(
        'The selected package is for ${metadata.workId}, not '
        '${expectedWorkId.trim()}.',
      );
    }
    if ((expectedPackageId?.trim().isNotEmpty ?? false) &&
        metadata.packageId != expectedPackageId!.trim()) {
      throw const PioneerBookPackageImportException(
        'The selected package does not match this book package identity.',
      );
    }
    final declaredHtml = metadata.htmlFile?.trim() ?? '';
    if (declaredHtml.isEmpty || !entryNames.contains(declaredHtml)) {
      throw const PioneerBookPackageImportException(
        'Manifest-declared HTML file is missing.',
      );
    }

    final metadataBookCode = _bookCodeFromPackageMetadata(
      fileEntries,
      relativeEntryPath: relativeEntryPath,
    );
    final bookCode = metadataBookCode?.trim().isNotEmpty == true
        ? metadataBookCode!
              .trim()
              .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
              .trim()
        : studybookBookCodeFromPackageName(sourcePath);

    final rootPath = managedRootPath ?? await managedImportRootPath();
    final destinationFolderPath = p.normalize(p.join(rootPath, bookCode));
    final root = Directory(rootPath);
    await root.create(recursive: true);
    final destination = Directory(destinationFolderPath);
    if (await destination.exists()) {
      final existing = PioneerCaptureFolderMetadata.fromFolder(destination);
      if ((existing.packageId?.isNotEmpty ?? false) &&
          existing.packageId != metadata.packageId) {
        throw const PioneerBookPackageImportException(
          'A different package lineage already exists for this work.',
        );
      }
      if (existing.packageId == metadata.packageId &&
          existing.contentHash == metadata.contentHash) {
        final existingFiles = destination
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .map((file) => file.path)
            .toList(growable: false);
        return PioneerBookPackageImportResult(
          sourcePackagePath: sourcePath,
          managedRootPath: rootPath,
          destinationFolderPath: destinationFolderPath,
          bookCode: bookCode,
          workId: metadata.workId!,
          packageId: metadata.packageId!,
          extractedFilePaths: existingFiles,
          htmlFileCount: existingFiles
              .where(
                (path) =>
                    _htmlExtensions.contains(p.extension(path).toLowerCase()),
              )
              .length,
        );
      }
    }
    final staging = await root.createTemp('.studybook-$bookCode-');

    final extracted = <String>[];
    var htmlFileCount = 0;
    for (final entry in fileEntries) {
      final relativePath = relativeEntryPath(entry);
      if (relativePath.isEmpty) continue;
      final destinationPath = p.normalize(p.join(staging.path, relativePath));
      if (!p.isWithin(staging.path, destinationPath)) {
        throw PioneerBookPackageImportException(
          'Package entry "${entry.name}" escapes the destination folder and '
          'was rejected.',
        );
      }
      await Directory(p.dirname(destinationPath)).create(recursive: true);
      await File(
        destinationPath,
      ).writeAsBytes(entry.readBytes() ?? Uint8List(0));
      extracted.add(destinationPath);
      if (_htmlExtensions.contains(
        p.extension(destinationPath).toLowerCase(),
      )) {
        htmlFileCount += 1;
      }
    }

    final stagedMetadata = _withSynthesizedLegacyIdentity(
      PioneerCaptureFolderMetadata.fromFolder(staging),
      packageBytes: packageBytes,
      sourcePath: sourcePath,
    );
    if (stagedMetadata.hasManifestError ||
        stagedMetadata.workId != metadata.workId ||
        stagedMetadata.packageId != metadata.packageId ||
        stagedMetadata.contentHash != metadata.contentHash) {
      await staging.delete(recursive: true);
      throw const PioneerBookPackageImportException(
        'Extracted package identity is invalid.',
      );
    }
    final rollback = Directory('$destinationFolderPath.rollback');
    if (await rollback.exists()) {
      await rollback.delete(recursive: true);
    }
    if (await destination.exists()) {
      await destination.rename(rollback.path);
    }
    try {
      await staging.rename(destination.path);
      if (await rollback.exists()) {
        await rollback.delete(recursive: true);
      }
    } catch (_) {
      if (await rollback.exists()) {
        await rollback.rename(destination.path);
      }
      rethrow;
    }
    final promotedPaths = extracted
        .map(
          (path) => p.join(
            destinationFolderPath,
            p.relative(path, from: staging.path),
          ),
        )
        .toList(growable: false);

    if (setAsConfiguredFolder) {
      await _settingsStore.savePioneerCapturedHtmlFolder(path: rootPath);
      debugPrint(
        'CaptureClipper package import: configured folder set to app-managed '
        'root $rootPath.',
      );
    }

    debugPrint(
      'CaptureClipper package import: unpacked ${extracted.length} file(s) '
      '($htmlFileCount HTML) from ${p.basename(sourcePath)} into '
      '$destinationFolderPath.',
    );
    return PioneerBookPackageImportResult(
      sourcePackagePath: sourcePath,
      managedRootPath: rootPath,
      destinationFolderPath: destinationFolderPath,
      bookCode: bookCode,
      workId: metadata.workId!,
      packageId: metadata.packageId!,
      extractedFilePaths: List<String>.unmodifiable(promotedPaths),
      htmlFileCount: htmlFileCount,
    );
  }

  /// Schema-1 is CaptureClipper's original manifest format, which predates
  /// the workId/packageId/contentHash package-identity fields. Synthesizes
  /// stable equivalents from the short code and package bytes so these
  /// older captures can still be imported and deduplicated like schema-2
  /// packages, rather than rejecting them outright. Schema-2 metadata (or
  /// any metadata that already has these fields) is returned unchanged.
  PioneerCaptureFolderMetadata _withSynthesizedLegacyIdentity(
    PioneerCaptureFolderMetadata parsed, {
    required Uint8List packageBytes,
    required String sourcePath,
  }) {
    if (parsed.workId != null &&
        parsed.packageId != null &&
        parsed.contentHash != null) {
      return parsed;
    }
    return PioneerCaptureFolderMetadata(
      schemaVersion: parsed.schemaVersion,
      title: parsed.title,
      abbreviation: parsed.abbreviation,
      displayAbbreviation: parsed.displayAbbreviation,
      workId: parsed.workId ?? parsed.preferredAbbreviation,
      packageId:
          parsed.packageId ??
          'captureclipper:${parsed.preferredAbbreviation ?? studybookBookCodeFromPackageName(sourcePath)}',
      contentHash:
          parsed.contentHash ?? sha256.convert(packageBytes).toString(),
      createdAt: parsed.createdAt,
      updatedAt: parsed.updatedAt,
      htmlFile: parsed.htmlFile,
      imageCount: parsed.imageCount,
      captureApp: parsed.captureApp,
      captureMode: parsed.captureMode,
      fromRef: parsed.fromRef,
      toRef: parsed.toRef,
      manifestError: parsed.manifestError,
      sourceType: parsed.sourceType,
      sourceSite: parsed.sourceSite,
      sourceUrl: parsed.sourceUrl,
      coverImagePath: parsed.coverImagePath,
      contributors: parsed.contributors,
    );
  }

  bool _isIgnoredArchivePath(String entryName) {
    final segments = p.posix.split(entryName);
    return segments.contains('__MACOSX') ||
        p.basename(entryName) == '.DS_Store';
  }

  void _ensureSafeArchivePath(String entryName) {
    if (p.posix.isAbsolute(entryName) || p.windows.isAbsolute(entryName)) {
      throw PioneerBookPackageImportException(
        'Package entry "$entryName" uses an absolute path and was rejected.',
      );
    }
    if (p.posix.split(entryName).contains('..')) {
      throw PioneerBookPackageImportException(
        'Package entry "$entryName" contains a ".." path segment and was '
        'rejected.',
      );
    }
  }

  String? _bookCodeFromPackageMetadata(
    List<ArchiveFile> fileEntries, {
    required String Function(ArchiveFile entry) relativeEntryPath,
  }) {
    for (final metadataName in const <String>[
      'metadata.json',
      'manifest.json',
    ]) {
      for (final entry in fileEntries) {
        if (relativeEntryPath(entry).toLowerCase() != metadataName) continue;
        final bytes = entry.readBytes();
        if (bytes == null) continue;
        try {
          final decoded = json.decode(utf8.decode(bytes, allowMalformed: true));
          if (decoded is! Map) continue;
          for (final key in const <String>[
            'shortCode',
            'short_code',
            'bookCode',
            'book_code',
          ]) {
            final value = decoded[key]?.toString().trim() ?? '';
            if (value.isNotEmpty) return value;
          }
        } catch (error) {
          debugPrint(
            'CaptureClipper package import: could not parse $metadataName '
            'for a book code: $error',
          );
        }
      }
    }
    return null;
  }
}
