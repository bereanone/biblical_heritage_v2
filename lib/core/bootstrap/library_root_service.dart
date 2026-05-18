import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/utilities/data/elibrary_folder_policy.dart';
import 'library_root_native.dart';
import 'local_settings_store.dart';

class LibraryRootSelection {
  const LibraryRootSelection({
    required this.path,
    required this.exists,
    required this.needsReconnect,
    this.bookmark,
  });

  final String? path;
  final bool exists;
  final bool needsReconnect;
  final String? bookmark;
}

class LibraryRootService {
  LibraryRootService._();

  static final LibraryRootService instance = LibraryRootService._();

  static const libraryFolders = <String>[
    'Databases',
    'Tags',
    'Markup',
    'Graphics',
    'Media',
    'ePubs',
    'PDFs',
    'Commentaries',
    'Research',
    'Images',
    'Translations',
    'SharedLists',
    'Sync',
    'Backups',
    'LegacyBackup',
    'Index',
    'download_reports',
    'legacy_migration_reports',
  ];

  static final elibraryFolders = <String>[
    for (final folder in ELibraryFolderPolicy.managedEgwFolderDefinitions)
      folder.relativeFolder,
    'ePubs/Commentaries/User',
    'ePubs/Research/User',
    'PDFs/Commentaries/User',
    'PDFs/Research/User',
  ];

  Future<LibraryRootSelection> loadSelection() async {
    final path = await LocalSettingsStore.instance.loadLibraryRootPath();
    final bookmark = await LocalSettingsStore.instance
        .loadLibraryRootBookmark();
    if (path == null) {
      return const LibraryRootSelection(
        path: null,
        exists: false,
        needsReconnect: false,
      );
    }
    final exists = Directory(path).existsSync();
    return LibraryRootSelection(
      path: path,
      exists: exists,
      needsReconnect: bookmark == null || !exists,
      bookmark: bookmark,
    );
  }

  Future<void> setLibraryRoot({required String path, String? bookmark}) async {
    final normalized = p.normalize(path.trim());
    if (normalized.isEmpty) return;
    await LocalSettingsStore.instance.saveLibraryRoot(
      path: normalized,
      bookmark: bookmark,
    );
    await ensureStructure(normalized);
  }

  Future<void> ensureStructure([String? rootPath]) async {
    final selection = rootPath == null
        ? await loadSelection()
        : LibraryRootSelection(
            path: p.normalize(rootPath.trim()),
            exists: true,
            needsReconnect: false,
          );
    final root = selection.path;
    if (root == null || root.trim().isEmpty) return;

    final rootDir = Directory(root);
    if (!await rootDir.exists()) {
      await rootDir.create(recursive: true);
    }
    for (final folder in libraryFolders) {
      final dir = Directory(p.join(rootDir.path, folder));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
    for (final folder in elibraryFolders) {
      final dir = Directory(p.join(rootDir.path, folder));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  Future<String?> libraryRootPath() async {
    final selection = await loadSelection();
    if (!selection.exists) return null;
    final localMirror = await _appManagedLibraryRootPath();
    if (localMirror != null) return localMirror;
    return selection.path;
  }

  Future<String?> accessibleLibraryRootPath() async {
    try {
      final selection = await loadSelection();
      if (selection.exists && selection.bookmark != null) {
        final activated = await LibraryRootNative.activateBookmark(
          selection.bookmark!,
        );
        final path = activated?.trim() ?? '';
        if (path.isNotEmpty) return path;
      }
    } catch (_) {
      // Fall through to the app-managed mirror.
    }
    return _appManagedLibraryRootPath();
  }

  Future<String?> databasesPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'Databases');
  }

  Future<String?> tagsPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'Tags');
  }

  Future<String?> markupPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'Markup');
  }

  Future<String?> graphicsPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'Graphics');
  }

  Future<String?> mediaPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'Media');
  }

  Future<String?> folderPath(String folderName) async {
    final root = await libraryRootPath();
    if (root == null || folderName.trim().isEmpty) return null;
    return p.join(root, folderName.trim());
  }

  Future<String> databaseFilePath(String fileName) async {
    final databases = await databasesPath();
    if (databases == null) {
      throw StateError('Library root is not selected.');
    }
    return p.join(databases, fileName);
  }

  Future<String> backupRootPath() async {
    final root = await libraryRootPath();
    if (root != null) {
      return p.join(root, 'Backups');
    }
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'legacy_backup');
  }

  Future<String?> legacyBackupPath() async {
    final root = await libraryRootPath();
    if (root == null) return null;
    return p.join(root, 'LegacyBackup');
  }

  Future<String> relativePathFor({
    required String absolutePath,
    required String rootPath,
  }) async {
    final normalizedRoot = p.normalize(rootPath.trim());
    final normalizedAbsolute = p.normalize(absolutePath.trim());
    if (!p.isWithin(normalizedRoot, normalizedAbsolute) &&
        p.normalize(normalizedRoot) != normalizedAbsolute) {
      return p.basename(normalizedAbsolute);
    }
    return p.relative(normalizedAbsolute, from: normalizedRoot);
  }

  Future<String> resolveRelativePath({
    required String relativePath,
    required String rootPath,
  }) async {
    return p.join(p.normalize(rootPath.trim()), relativePath.trim());
  }

  Future<String?> _appManagedLibraryRootPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final candidate = p.join(documentsDir.path, 'BiblicalHeritage', 'v2');
    final rootDir = Directory(candidate);
    if (!await rootDir.exists()) return null;
    final epubDir = Directory(p.join(candidate, 'ePubs'));
    final databaseDir = Directory(p.join(candidate, 'Databases'));
    if (await epubDir.exists() || await databaseDir.exists()) {
      return candidate;
    }
    return null;
  }

  Future<bool> needsReconnect() async {
    final selection = await loadSelection();
    return selection.needsReconnect;
  }
}
