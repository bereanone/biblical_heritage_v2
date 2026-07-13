import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
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
  final base = p.basenameWithoutExtension(packagePath).trim();
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
    required this.extractedFilePaths,
    required this.htmlFileCount,
  });

  final String sourcePackagePath;
  final String managedRootPath;
  final String destinationFolderPath;
  final String bookCode;
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

  static const Set<String> supportedPackageExtensions = <String>{'.studybook'};

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
    final packageExtension = p.extension(sourcePath).toLowerCase();
    if (!supportedPackageExtensions.contains(packageExtension)) {
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

    final fileEntries = <ArchiveFile>[];
    const maxEntries = 10000;
    const maxExpandedBytes = 1024 * 1024 * 1024;
    var expandedBytes = 0;
    final entryNames = <String>{};
    for (final entry in archive) {
      final entryName = entry.name.replaceAll('\\', '/').trim();
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
        .where((entry) => entry.name == 'manifest.json')
        .toList();
    if (manifests.length != 1) {
      throw const PioneerBookPackageImportException(
        'Package must contain exactly one root manifest.json.',
      );
    }
    String relativeEntryPath(ArchiveFile entry) {
      return entry.name.replaceAll('\\', '/').trim();
    }

    final manifestData = json.decode(
      utf8.decode(manifests.single.readBytes()!),
    );
    if (manifestData is! Map<String, Object?>) {
      throw const PioneerBookPackageImportException(
        'Manifest is not a JSON object.',
      );
    }
    final metadata = PioneerCaptureFolderMetadata.fromManifestMap(
      manifestData,
      folderPath: '',
    );
    if (metadata.schemaVersion != 2 || metadata.hasManifestError) {
      throw PioneerBookPackageImportException(
        metadata.manifestError ?? 'Only schema-2 packages are supported.',
      );
    }
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

    final stagedMetadata = PioneerCaptureFolderMetadata.fromFolder(staging);
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
      extractedFilePaths: List<String>.unmodifiable(promotedPaths),
      htmlFileCount: htmlFileCount,
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
