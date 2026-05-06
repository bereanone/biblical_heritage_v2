import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';

class UtilityFolderConfig {
  const UtilityFolderConfig({
    required this.commentaryLocalRoot,
    required this.researchLocalRoot,
    required this.elibraryLocalRoot,
    required this.imagesLocalRoot,
    required this.translationsLocalRoot,
    required this.cloudRoot,
  });

  final String commentaryLocalRoot;
  final String researchLocalRoot;
  final String elibraryLocalRoot;
  final String imagesLocalRoot;
  final String translationsLocalRoot;
  final String? cloudRoot;

  Map<String, Object?> toJson() => <String, Object?>{
    'commentaryLocalRoot': commentaryLocalRoot,
    'researchLocalRoot': researchLocalRoot,
    'elibraryLocalRoot': elibraryLocalRoot,
    'imagesLocalRoot': imagesLocalRoot,
    'translationsLocalRoot': translationsLocalRoot,
    'cloudRoot': cloudRoot,
  };

  factory UtilityFolderConfig.fromJson(Map<String, Object?> json) {
    return UtilityFolderConfig(
      commentaryLocalRoot: json['commentaryLocalRoot']?.toString() ?? '',
      researchLocalRoot: json['researchLocalRoot']?.toString() ?? '',
      elibraryLocalRoot: json['elibraryLocalRoot']?.toString() ?? '',
      imagesLocalRoot: json['imagesLocalRoot']?.toString() ?? '',
      translationsLocalRoot: json['translationsLocalRoot']?.toString() ?? '',
      cloudRoot: json['cloudRoot']?.toString().trim().isEmpty == true
          ? null
          : json['cloudRoot']?.toString(),
    );
  }

  UtilityFolderConfig copyWith({
    String? commentaryLocalRoot,
    String? researchLocalRoot,
    String? elibraryLocalRoot,
    String? imagesLocalRoot,
    String? translationsLocalRoot,
    String? cloudRoot,
  }) {
    return UtilityFolderConfig(
      commentaryLocalRoot: commentaryLocalRoot ?? this.commentaryLocalRoot,
      researchLocalRoot: researchLocalRoot ?? this.researchLocalRoot,
      elibraryLocalRoot: elibraryLocalRoot ?? this.elibraryLocalRoot,
      imagesLocalRoot: imagesLocalRoot ?? this.imagesLocalRoot,
      translationsLocalRoot:
          translationsLocalRoot ?? this.translationsLocalRoot,
      cloudRoot: cloudRoot ?? this.cloudRoot,
    );
  }
}

class CommentaryLibraryDocument {
  const CommentaryLibraryDocument({
    required this.title,
    required this.volumeCode,
    required this.format,
    required this.managedPath,
    required this.fileName,
    required this.fileSize,
    required this.modifiedAt,
    required this.scopeStartBook,
    required this.scopeEndBook,
    required this.isResearch,
  });

  final String title;
  final String volumeCode;
  final String format;
  final String managedPath;
  final String fileName;
  final int fileSize;
  final int modifiedAt;
  final int scopeStartBook;
  final int scopeEndBook;
  final bool isResearch;
}

class CommentaryImportResult {
  const CommentaryImportResult({
    required this.importedCount,
    required this.refreshedCount,
    required this.commentaryCount,
    required this.researchCount,
    required this.message,
  });

  final int importedCount;
  final int refreshedCount;
  final int commentaryCount;
  final int researchCount;
  final String message;
}

class CommentarySyncResult {
  const CommentarySyncResult({
    required this.commentaryUploaded,
    required this.commentaryDownloaded,
    required this.commentaryRefreshed,
    required this.researchUploaded,
    required this.researchDownloaded,
    required this.researchRefreshed,
    required this.elibraryUploaded,
    required this.elibraryDownloaded,
    required this.elibraryRefreshed,
    required this.imagesUploaded,
    required this.imagesDownloaded,
    required this.imagesRefreshed,
    required this.translationsUploaded,
    required this.translationsDownloaded,
    required this.translationsRefreshed,
    required this.folderPath,
  });

  final int commentaryUploaded;
  final int commentaryDownloaded;
  final int commentaryRefreshed;
  final int researchUploaded;
  final int researchDownloaded;
  final int researchRefreshed;
  final int elibraryUploaded;
  final int elibraryDownloaded;
  final int elibraryRefreshed;
  final int imagesUploaded;
  final int imagesDownloaded;
  final int imagesRefreshed;
  final int translationsUploaded;
  final int translationsDownloaded;
  final int translationsRefreshed;
  final String folderPath;

  String get message =>
      'Synced local folders with cloud. '
      'Commentary: uploaded $commentaryUploaded, downloaded $commentaryDownloaded, refreshed $commentaryRefreshed. '
      'Research: uploaded $researchUploaded, downloaded $researchDownloaded, refreshed $researchRefreshed. '
      'eLibrary: uploaded $elibraryUploaded, downloaded $elibraryDownloaded, refreshed $elibraryRefreshed. '
      'Images: uploaded $imagesUploaded, downloaded $imagesDownloaded, refreshed $imagesRefreshed. '
      'Translations: uploaded $translationsUploaded, downloaded $translationsDownloaded, refreshed $translationsRefreshed.';
}

class UtilityFolderSetupService {
  UtilityFolderSetupService._();

  static final UtilityFolderSetupService instance =
      UtilityFolderSetupService._();

  static const _configKey = 'utilities.folder_setup.config';
  static const Map<String, ({int start, int end})> _volumeScopes =
      <String, ({int start, int end})>{
        '1BC': (start: 1, end: 5),
        '2BC': (start: 6, end: 12),
        '3BC': (start: 13, end: 22),
        '4BC': (start: 23, end: 39),
        '5BC': (start: 40, end: 43),
        '6BC': (start: 44, end: 49),
        '7BC': (start: 50, end: 66),
        '7ABC': (start: 44, end: 66),
      };

  Future<UtilityFolderConfig> loadConfig() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [_configKey],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final raw = rows.first['value']?.toString();
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, Object?>) {
            return _normalizedConfig(
              await _withLibraryRoot(UtilityFolderConfig.fromJson(decoded)),
            );
          }
          if (decoded is Map) {
            return _normalizedConfig(
              await _withLibraryRoot(
                UtilityFolderConfig.fromJson(decoded.cast<String, Object?>()),
              ),
            );
          }
        } catch (_) {
          // Fall through to defaults.
        }
      }
    }
    return _normalizedConfig(await _withLibraryRoot(await _defaultConfig()));
  }

  Future<void> saveConfig(UtilityFolderConfig config) async {
    final db = await UserDatabase.instance.database;
    await db.insert('app_settings', {
      'key': _configKey,
      'value': jsonEncode(config.toJson()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await ensureFolderStructure(config);
  }

  Future<void> setCloudRoot(String? cloudRoot) async {
    final config = await loadConfig();
    await saveConfig(config.copyWith(cloudRoot: _normalizeNullable(cloudRoot)));
  }

  Future<void> setLocalRoots({
    String? commentaryLocalRoot,
    String? researchLocalRoot,
    String? elibraryLocalRoot,
    String? imagesLocalRoot,
    String? translationsLocalRoot,
  }) async {
    final config = await loadConfig();
    await saveConfig(
      config.copyWith(
        commentaryLocalRoot: _normalizePath(
          commentaryLocalRoot ?? config.commentaryLocalRoot,
        ),
        researchLocalRoot: _normalizePath(
          researchLocalRoot ?? config.researchLocalRoot,
        ),
        elibraryLocalRoot: _normalizePath(
          elibraryLocalRoot ?? config.elibraryLocalRoot,
        ),
        imagesLocalRoot: _normalizePath(
          imagesLocalRoot ?? config.imagesLocalRoot,
        ),
        translationsLocalRoot: _normalizePath(
          translationsLocalRoot ?? config.translationsLocalRoot,
        ),
      ),
    );
  }

  Future<void> resetToDefaults() async {
    await saveConfig(await _defaultConfig());
  }

  Future<void> ensureFolderStructure(UtilityFolderConfig config) async {
    final localRoots = [
      config.commentaryLocalRoot,
      config.researchLocalRoot,
      config.elibraryLocalRoot,
      config.imagesLocalRoot,
      config.translationsLocalRoot,
    ];
    for (final root in localRoots) {
      if (root.trim().isEmpty) continue;
      final dir = Directory(root);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    final cloudRoot = config.cloudRoot;
    if (cloudRoot == null || cloudRoot.trim().isEmpty) return;
    final cloudDir = Directory(cloudRoot);
    if (!await cloudDir.exists()) {
      await cloudDir.create(recursive: true);
    }
    for (final folder in const [
      'Commentary',
      'Research',
      'eLibrary',
      'Images',
      'Translations',
      'SharedLists',
      'Sync',
      'Future',
    ]) {
      final dir = Directory(p.join(cloudDir.path, folder));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  Future<CommentaryImportResult> importFromDirectory(String sourcePath) async {
    final sourceDir = Directory(sourcePath);
    if (!await sourceDir.exists()) {
      return const CommentaryImportResult(
        importedCount: 0,
        refreshedCount: 0,
        commentaryCount: 0,
        researchCount: 0,
        message: 'Import cancelled or folder not found.',
      );
    }

    final config = await loadConfig();
    await ensureFolderStructure(config);
    final commentaryDir = Directory(config.commentaryLocalRoot);
    final researchDir = Directory(config.researchLocalRoot);

    var imported = 0;
    var refreshed = 0;
    var commentaryCount = 0;
    var researchCount = 0;

    await for (final entity in sourceDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final sourcePath = entity.path;
      final ext = p.extension(sourcePath).toLowerCase();
      if (ext != '.epub' && ext != '.pdf') continue;

      final fileName = p.basename(sourcePath);
      final volumeCode = _inferVolumeCode(fileName);
      final isCommentary = _isCommentaryVolume(volumeCode);
      final targetDir = isCommentary ? commentaryDir : researchDir;
      final targetPath = await _dedupeTargetPath(targetDir.path, fileName);
      final sourceStat = await entity.stat();
      final targetFile = File(targetPath);
      final existed = await targetFile.exists();

      if (p.normalize(sourcePath) != p.normalize(targetPath) || !existed) {
        await entity.copy(targetPath);
      } else if (sourceStat.modified.isAfter(
        (await targetFile.stat()).modified,
      )) {
        await entity.copy(targetPath);
      }

      if (existed) {
        refreshed += 1;
      } else {
        imported += 1;
      }
      if (isCommentary) {
        commentaryCount += 1;
      } else {
        researchCount += 1;
      }
    }

    return CommentaryImportResult(
      importedCount: imported,
      refreshedCount: refreshed,
      commentaryCount: commentaryCount,
      researchCount: researchCount,
      message:
          'Imported $imported files, refreshed $refreshed. Commentary: $commentaryCount. Research: $researchCount.',
    );
  }

  Future<List<CommentaryLibraryDocument>> loadCommentaryDocuments() async {
    return _loadDocuments(
      await _configuredDirectory((config) => config.commentaryLocalRoot),
      isResearch: false,
    );
  }

  Future<List<CommentaryLibraryDocument>> loadResearchDocuments() async {
    return _loadDocuments(
      await _configuredDirectory((config) => config.researchLocalRoot),
      isResearch: true,
    );
  }

  Future<CommentarySyncResult?> syncNow() async {
    final config = await loadConfig();
    if (config.cloudRoot == null || config.cloudRoot!.trim().isEmpty) {
      return null;
    }
    await ensureFolderStructure(config);

    final cloudRoot = Directory(config.cloudRoot!);
    final commentaryResult = await _syncDirectoryPair(
      localDir: Directory(config.commentaryLocalRoot),
      cloudDir: Directory(p.join(cloudRoot.path, 'Commentary')),
    );
    final researchResult = await _syncDirectoryPair(
      localDir: Directory(config.researchLocalRoot),
      cloudDir: Directory(p.join(cloudRoot.path, 'Research')),
    );
    final elibraryResult = await _syncDirectoryPair(
      localDir: Directory(config.elibraryLocalRoot),
      cloudDir: Directory(p.join(cloudRoot.path, 'eLibrary')),
    );
    final imagesResult = await _syncDirectoryPair(
      localDir: Directory(config.imagesLocalRoot),
      cloudDir: Directory(p.join(cloudRoot.path, 'Images')),
    );
    final translationsResult = await _syncDirectoryPair(
      localDir: Directory(config.translationsLocalRoot),
      cloudDir: Directory(p.join(cloudRoot.path, 'Translations')),
    );

    return CommentarySyncResult(
      commentaryUploaded: commentaryResult.uploaded,
      commentaryDownloaded: commentaryResult.downloaded,
      commentaryRefreshed: commentaryResult.refreshed,
      researchUploaded: researchResult.uploaded,
      researchDownloaded: researchResult.downloaded,
      researchRefreshed: researchResult.refreshed,
      elibraryUploaded: elibraryResult.uploaded,
      elibraryDownloaded: elibraryResult.downloaded,
      elibraryRefreshed: elibraryResult.refreshed,
      imagesUploaded: imagesResult.uploaded,
      imagesDownloaded: imagesResult.downloaded,
      imagesRefreshed: imagesResult.refreshed,
      translationsUploaded: translationsResult.uploaded,
      translationsDownloaded: translationsResult.downloaded,
      translationsRefreshed: translationsResult.refreshed,
      folderPath: cloudRoot.path,
    );
  }

  Future<String?> configuredCloudRoot() async {
    final config = await loadConfig();
    return config.cloudRoot;
  }

  Future<String> summaryLine() async {
    final config = await loadConfig();
    final cloud = config.cloudRoot == null || config.cloudRoot!.trim().isEmpty
        ? 'not set'
        : config.cloudRoot!;
    return 'Local folders: commentary, research, eLibrary, images, translations. Cloud root: $cloud';
  }

  Future<Directory> _configuredDirectory(
    String Function(UtilityFolderConfig config) selector,
  ) async {
    final config = await loadConfig();
    await ensureFolderStructure(config);
    return Directory(_normalizePath(selector(config)));
  }

  Future<UtilityFolderConfig> _defaultConfig() async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot != null) {
      return UtilityFolderConfig(
        commentaryLocalRoot: p.join(libraryRoot, 'Commentaries'),
        researchLocalRoot: p.join(libraryRoot, 'Research'),
        elibraryLocalRoot: p.join(libraryRoot, 'ePubs'),
        imagesLocalRoot: p.join(libraryRoot, 'Images'),
        translationsLocalRoot: p.join(libraryRoot, 'Translations'),
        cloudRoot: null,
      );
    }
    final supportDir = await getApplicationSupportDirectory();
    final root = p.join(supportDir.path, 'BiblicalHeritage');
    return UtilityFolderConfig(
      commentaryLocalRoot: p.join(root, 'Commentary'),
      researchLocalRoot: p.join(root, 'Research'),
      elibraryLocalRoot: p.join(root, 'eLibrary'),
      imagesLocalRoot: p.join(root, 'Images'),
      translationsLocalRoot: p.join(root, 'Translations'),
      cloudRoot: null,
    );
  }

  Future<UtilityFolderConfig> _withLibraryRoot(UtilityFolderConfig config) async {
    final libraryRoot = await LibraryRootService.instance.libraryRootPath();
    if (libraryRoot == null) return config;
    return UtilityFolderConfig(
      commentaryLocalRoot: p.join(libraryRoot, 'Commentaries'),
      researchLocalRoot: p.join(libraryRoot, 'Research'),
      elibraryLocalRoot: p.join(libraryRoot, 'ePubs'),
      imagesLocalRoot: p.join(libraryRoot, 'Images'),
      translationsLocalRoot: p.join(libraryRoot, 'Translations'),
      cloudRoot: config.cloudRoot,
    );
  }

  UtilityFolderConfig _normalizedConfig(UtilityFolderConfig config) {
    return UtilityFolderConfig(
      commentaryLocalRoot: _normalizePath(config.commentaryLocalRoot),
      researchLocalRoot: _normalizePath(config.researchLocalRoot),
      elibraryLocalRoot: _normalizePath(config.elibraryLocalRoot),
      imagesLocalRoot: _normalizePath(config.imagesLocalRoot),
      translationsLocalRoot: _normalizePath(config.translationsLocalRoot),
      cloudRoot: _normalizeNullable(config.cloudRoot),
    );
  }

  String _normalizePath(String path) {
    return p.normalize(path.trim());
  }

  String? _normalizeNullable(String? path) {
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return p.normalize(trimmed);
  }

  Future<List<CommentaryLibraryDocument>> _loadDocuments(
    Directory directory, {
    required bool isResearch,
  }) async {
    final files = <CommentaryLibraryDocument>[];
    if (!await directory.exists()) return files;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.epub' && ext != '.pdf') continue;
      final stat = await entity.stat();
      final fileName = p.basename(entity.path);
      final volumeCode = _inferVolumeCode(fileName);
      final scope = _volumeScopes[volumeCode];
      files.add(
        CommentaryLibraryDocument(
          title: _defaultTitle(fileName, volumeCode: volumeCode),
          volumeCode: volumeCode,
          format: ext.replaceFirst('.', ''),
          managedPath: entity.path,
          fileName: fileName,
          fileSize: stat.size,
          modifiedAt: stat.modified.millisecondsSinceEpoch,
          scopeStartBook: scope?.start ?? 0,
          scopeEndBook: scope?.end ?? 0,
          isResearch: isResearch,
        ),
      );
    }
    files.sort((a, b) {
      final volumeCmp = a.volumeCode.toLowerCase().compareTo(
        b.volumeCode.toLowerCase(),
      );
      if (volumeCmp != 0) return volumeCmp;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return files;
  }

  Future<({int uploaded, int downloaded, int refreshed})> _syncDirectoryPair({
    required Directory localDir,
    required Directory cloudDir,
  }) async {
    if (!await localDir.exists()) {
      await localDir.create(recursive: true);
    }
    if (!await cloudDir.exists()) {
      await cloudDir.create(recursive: true);
    }

    final localFiles = await _scanFiles(localDir);
    final cloudFiles = await _scanFiles(cloudDir);
    var uploaded = 0;
    var downloaded = 0;
    var refreshed = 0;

    for (final entry in localFiles.entries) {
      final cloud = cloudFiles[entry.key];
      final localStat = await File(entry.value).stat();
      if (cloud == null) {
        await _copyFile(entry.value, p.join(cloudDir.path, entry.key));
        uploaded += 1;
        continue;
      }
      final cloudStat = await File(cloud).stat();
      if (localStat.modified.isAfter(cloudStat.modified)) {
        await _copyFile(entry.value, cloud);
        refreshed += 1;
      } else if (cloudStat.modified.isAfter(localStat.modified)) {
        await _copyFile(cloud, entry.value);
        downloaded += 1;
      }
    }

    for (final entry in cloudFiles.entries) {
      if (localFiles.containsKey(entry.key)) continue;
      await _copyFile(entry.value, p.join(localDir.path, entry.key));
      downloaded += 1;
    }

    return (uploaded: uploaded, downloaded: downloaded, refreshed: refreshed);
  }

  Future<Map<String, String>> _scanFiles(Directory dir) async {
    final files = <String, String>{};
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final ext = p.extension(entity.path).toLowerCase();
      if (ext.isEmpty) continue;
      files[p.basename(entity.path)] = entity.path;
    }
    return files;
  }

  Future<void> _copyFile(String sourcePath, String targetPath) async {
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    if (p.normalize(sourcePath) == p.normalize(targetPath)) return;
    await File(sourcePath).copy(targetPath);
  }

  Future<String> _dedupeTargetPath(String dirPath, String fileName) async {
    var targetPath = p.join(dirPath, fileName);
    var dedupe = 2;
    while (await File(targetPath).exists()) {
      final base = p.basenameWithoutExtension(fileName);
      targetPath = p.join(dirPath, '$base ($dedupe)${p.extension(fileName)}');
      dedupe += 1;
    }
    return targetPath;
  }

  bool _isCommentaryVolume(String volumeCode) {
    final code = volumeCode.trim().toUpperCase();
    return code.isNotEmpty && _volumeScopes.containsKey(code);
  }

  String _inferVolumeCode(String fileName) {
    final match = RegExp(
      r'(?:(\dABC)|(\dBC))',
      caseSensitive: false,
    ).firstMatch(fileName.replaceAll('_', '').replaceAll('-', ''));
    final raw = match?.group(1) ?? match?.group(2) ?? '';
    return raw.toUpperCase();
  }

  String _defaultTitle(String fileName, {required String volumeCode}) {
    if (volumeCode.isNotEmpty) return volumeCode;
    return p.basenameWithoutExtension(fileName).replaceAll('_', ' ').trim();
  }
}
