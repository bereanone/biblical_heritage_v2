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
    required this.source,
    this.bookmark,
  });

  final String? path;
  final bool exists;
  final bool needsReconnect;
  final LibraryRootSource source;
  final String? bookmark;

  bool get isExplicitlySelected => switch (source) {
    LibraryRootSource.userSelected => true,
    LibraryRootSource.defaultAppFolder => true,
    LibraryRootSource.legacyImplicit => false,
    LibraryRootSource.unknown => false,
  };

  bool get isDefaultAppManaged =>
      source == LibraryRootSource.defaultAppFolder;

  bool get isUserSelected => source == LibraryRootSource.userSelected;

  bool get isLegacyImplicit => source == LibraryRootSource.legacyImplicit;

  String get sourceLabel {
    switch (source) {
      case LibraryRootSource.userSelected:
        return 'User-selected';
      case LibraryRootSource.defaultAppFolder:
        return 'Default app-managed';
      case LibraryRootSource.legacyImplicit:
        return 'Legacy implicit';
      case LibraryRootSource.unknown:
        return 'Unknown';
    }
  }

  String get statusLabel {
    if (path == null) {
      return 'No Library Root selected.';
    }
    if (!exists) {
      return 'Library Root missing, reconnect needed.';
    }
    switch (source) {
      case LibraryRootSource.userSelected:
        return 'Confirmed Library Root selected.';
      case LibraryRootSource.defaultAppFolder:
        return 'App folder selected as the Library Root.';
      case LibraryRootSource.legacyImplicit:
        return 'Legacy Library Root detected.';
      case LibraryRootSource.unknown:
        return 'Unconfirmed Library Root detected.';
    }
  }

  String get badgeLabel {
    if (path == null) {
      return 'No root';
    }
    if (!exists) {
      return 'Confirm root';
    }
    switch (source) {
      case LibraryRootSource.userSelected:
        return 'Ready';
      case LibraryRootSource.defaultAppFolder:
        return 'App folder';
      case LibraryRootSource.legacyImplicit:
        return 'Legacy root';
      case LibraryRootSource.unknown:
        return 'Unconfirmed root';
    }
  }
}

enum LibraryRootSource {
  unknown,
  userSelected,
  defaultAppFolder,
  legacyImplicit,
}

class LibraryRootService {
  LibraryRootService._();

  static final LibraryRootService instance = LibraryRootService._();
  LibraryRootSelection? _cachedSelection;
  String? _cachedAccessiblePath;

  static const defaultAppLibraryFolderName = 'Biblical Heritage Library';

  static const libraryFolders = <String>[
    'Databases',
    'Tags',
    'Markup',
    'Graphics',
    'Media',
    'ePubs',
    'PDFs',
    'Indexes',
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
    final cached = _cachedSelection;
    if (cached != null) {
      return cached;
    }
    final path = await LocalSettingsStore.instance.loadLibraryRootPath();
    final bookmark = await LocalSettingsStore.instance
        .loadLibraryRootBookmark();
    final sourceName = await LocalSettingsStore.instance
        .loadLibraryRootSource();
    final defaultAppRoot = await defaultAppLibraryRootPath();
    var resolvedPath = path;
    var source = _selectionSource(
      sourceName: sourceName,
      path: resolvedPath,
      bookmark: bookmark,
      defaultAppRoot: defaultAppRoot,
    );

    if (resolvedPath != null && resolvedPath.trim().isNotEmpty) {
      if (Platform.isMacOS &&
          bookmark != null &&
          bookmark.trim().isNotEmpty) {
        final activated = await LibraryRootNative.activateBookmark(bookmark);
        final activatedPath = activated?.trim() ?? '';
        if (activatedPath.isNotEmpty) {
          resolvedPath = activatedPath;
        }
      }
      final exists = Directory(resolvedPath).existsSync();
      final selection = LibraryRootSelection(
        path: resolvedPath,
        exists: exists,
        needsReconnect: source == LibraryRootSource.userSelected
            ? bookmark == null || !exists
            : !exists,
        source: source,
        bookmark: bookmark,
      );
      _cachedSelection = selection;
      return selection;
    }

    if (Platform.isIOS) {
      final detected = await _detectImplicitLibraryRoot(
        preferredRoots: [
          defaultAppRoot,
          await _legacySupportRootPath(),
          await _legacyDocumentsRootPath(),
        ],
      );
      final implicitPath = detected?.path ?? defaultAppRoot;
      final implicitSource =
          detected?.source ?? LibraryRootSource.defaultAppFolder;
      final exists = Directory(implicitPath).existsSync();
      final selection = LibraryRootSelection(
        path: implicitPath,
        exists: exists,
        needsReconnect: !exists,
        source: implicitSource,
        bookmark: null,
      );
      _cachedSelection = selection;
      return selection;
    }

    final selection = const LibraryRootSelection(
      path: null,
      exists: false,
      needsReconnect: false,
      source: LibraryRootSource.unknown,
    );
    _cachedSelection = selection;
    return selection;
  }

  Future<void> setLibraryRoot({
    required String path,
    String? bookmark,
    LibraryRootSource source = LibraryRootSource.userSelected,
  }) async {
    if (Platform.isIOS) {
      source = LibraryRootSource.defaultAppFolder;
      bookmark = null;
      path = await defaultAppLibraryRootPath();
    }
    var normalized = p.normalize(path.trim());
    if (normalized.isEmpty) return;

    final bookmarkValue = bookmark?.trim() ?? '';
    if (bookmarkValue.isNotEmpty && Platform.isMacOS) {
      final activated = await LibraryRootNative.activateBookmark(bookmarkValue);
      final activatedPath = activated?.trim() ?? '';
      if (activatedPath.isEmpty) {
        throw StateError('Could not access the selected Library Root.');
      }
      normalized = p.normalize(activatedPath);
    }

    await ensureStructure(normalized);
    await LocalSettingsStore.instance.saveLibraryRoot(
      path: normalized,
      bookmark: bookmarkValue.isEmpty ? null : bookmarkValue,
      source: source.name,
    );
    _invalidateCachedSelection();
  }

  Future<void> clearLibraryRoot() async {
    await LocalSettingsStore.instance.clearLibraryRoot();
    _invalidateCachedSelection();
  }

  Future<void> ensureStructure([String? rootPath]) async {
    final selection = rootPath == null
        ? await loadSelection()
        : LibraryRootSelection(
            path: p.normalize(rootPath.trim()),
            exists: true,
            needsReconnect: false,
            source: LibraryRootSource.unknown,
          );
    final root = selection.path;
    if (root == null || root.trim().isEmpty) return;

    var rootToUse = root;
    if (selection.isUserSelected &&
        selection.bookmark != null &&
        Platform.isMacOS) {
      final activated = await LibraryRootNative.activateBookmark(
        selection.bookmark!,
      );
      final activatedPath = activated?.trim() ?? '';
      if (activatedPath.isEmpty) {
        return;
      }
      rootToUse = activatedPath;
    }

    final rootDir = Directory(rootToUse);
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
    return selection.path;
  }

  Future<String?> accessibleLibraryRootPath() async {
    final cached = _cachedAccessiblePath;
    if (cached != null) {
      return cached;
    }
    try {
      final selection = await loadSelection();
      if (selection.exists &&
          selection.isUserSelected &&
          selection.bookmark != null &&
          Platform.isMacOS) {
        final activated = await LibraryRootNative.activateBookmark(
          selection.bookmark!,
        );
        final path = activated?.trim() ?? '';
        if (path.isNotEmpty) {
          _cachedAccessiblePath = path;
          return path;
        }
      }
    } catch (_) {
      // Fall through to the configured path.
    }
    final selection = await loadSelection();
    if (selection.exists) {
      _cachedAccessiblePath = selection.path;
      return selection.path;
    }
    return null;
  }

  Future<String?> explicitLibraryRootPath() async {
    final selection = await loadSelection();
    if (!selection.exists || !selection.isExplicitlySelected) {
      return null;
    }
    return selection.path;
  }

  Future<String> defaultAppLibraryRootPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return documentsDir.path;
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

  Future<bool> needsReconnect() async {
    final selection = await loadSelection();
    return selection.needsReconnect;
  }

  void _invalidateCachedSelection() {
    _cachedSelection = null;
    _cachedAccessiblePath = null;
  }

  LibraryRootSource _selectionSource({
    required String? sourceName,
    required String? path,
    required String? bookmark,
    required String defaultAppRoot,
  }) {
    final normalized = sourceName?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'userselected':
      case 'user_selected':
        return LibraryRootSource.userSelected;
      case 'defaultappfolder':
      case 'default_app_folder':
      case 'default_app':
        return LibraryRootSource.defaultAppFolder;
      case 'legacyimplicit':
      case 'legacy_implicit':
        return LibraryRootSource.legacyImplicit;
      case '':
        break;
      default:
        return LibraryRootSource.unknown;
    }

    if (bookmark != null && bookmark.trim().isNotEmpty) {
      return LibraryRootSource.userSelected;
    }
    if (path != null && path.trim().isNotEmpty) {
      final normalizedPath = p.normalize(path.trim());
      final normalizedDefaultAppRoot = p.normalize(defaultAppRoot.trim());
      if (normalizedPath == normalizedDefaultAppRoot) {
        return LibraryRootSource.defaultAppFolder;
      }
      return LibraryRootSource.legacyImplicit;
    }
    return LibraryRootSource.unknown;
  }

  Future<({String path, LibraryRootSource source})?> _detectImplicitLibraryRoot({
    required List<String> preferredRoots,
  }) async {
    for (final candidate in preferredRoots) {
      final normalized = candidate.trim();
      if (normalized.isEmpty) continue;
      if (await _looksLikeLibraryRoot(normalized)) {
        final source = Platform.isIOS &&
                p.normalize(normalized) == p.normalize(await defaultAppLibraryRootPath())
            ? LibraryRootSource.defaultAppFolder
            : LibraryRootSource.legacyImplicit;
        return (path: normalized, source: source);
      }
    }
    return null;
  }

  Future<bool> _looksLikeLibraryRoot(String rootPath) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) return false;
    final markers = <String>[
      'Databases',
      'Tags',
      'Markup',
      'Graphics',
      'Media',
      'ePubs',
      'PDFs',
      'Indexes',
      'Commentaries',
      'Research',
      'Backups',
      'download_reports',
      'user.db',
      'commentary_library',
      'research_library',
      'eLibrary',
    ];
    for (final marker in markers) {
      if (await Directory(p.join(rootDir.path, marker)).exists() ||
          await File(p.join(rootDir.path, marker)).exists()) {
        return true;
      }
    }
    return false;
  }

  Future<String> _legacySupportRootPath() async {
    final supportDir = await getApplicationSupportDirectory();
    return supportDir.path;
  }

  Future<String> _legacyDocumentsRootPath() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, 'BiblicalHeritage', 'v2');
  }
}
