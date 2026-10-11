import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/database/user_database.dart';

enum UserContentRemovalScope { library, allUserData }

/// Only app-owned content folders inside the chosen library are eligible.
/// External import sources and bundled Bible assets are never scanned.
const libraryRemovalFolders = <String>[
  'ePubs',
  'PDFs',
  'Library',
  'ImportedPioneerEpubs',
  'Imports',
  'Packages',
  'Books',
  'Commentaries',
  'Research',
  'Index',
  'Indexes',
  'Temporary',
  'Translations',
  'download_reports',
];
const personalRemovalFolders = <String>[
  'Tags',
  'Markup',
  'Media',
  'Graphics',
  'Images',
  'SharedLists',
];

class UserContentRemovalPlan {
  UserContentRemovalPlan({
    required this.root,
    required this.scope,
    required this.includeBackups,
    required this.files,
    required this.fileBytes,
    required this.databaseBytes,
    required this.remoteFiles,
    required this.remoteBytes,
    required this.ownedRoots,
  });
  final String root;
  final UserContentRemovalScope scope;
  final bool includeBackups;
  final Map<String, int> files;
  final int fileBytes, databaseBytes, remoteFiles, remoteBytes;
  final List<String> ownedRoots;
  bool get allUserData => scope == UserContentRemovalScope.allUserData;
}

class UserContentRemovalService {
  static const metadataTables = {
    'android_metadata',
    'app_migrations',
    'elibrary_schema_migrations',
    'devices',
    'sync_state',
  };

  static bool removesTable(String name, UserContentRemovalScope scope) {
    if (name.startsWith('sqlite_') || metadataTables.contains(name)) {
      return false;
    }
    // Never permit a bundled Bible table, even in an incorrectly supplied DB.
    if (name.startsWith('bible_') ||
        name == 'books' ||
        name == 'verses' ||
        name.startsWith('strong') ||
        name.startsWith('cross_reference')) {
      return false;
    }
    if (scope == UserContentRemovalScope.allUserData) return true;
    if (name == 'library_items' || name == 'elibrary_markups') return false;
    return name.startsWith('library_') ||
        name == 'elibrary_ref_index' ||
        name == 'elibrary_install_estimates';
  }

  /// Exposed for disposable-copy verification. No database files are removed.
  static Future<void> clearDatabase(
    Database db,
    UserContentRemovalScope scope,
  ) async {
    if (!{'user.db', 'eLibrary.db'}.contains(p.basename(db.path))) {
      throw StateError('Only user.db and eLibrary.db may be cleared.');
    }
    final foreignKeys = (await db.rawQuery(
      'PRAGMA foreign_keys',
    )).first.values.first;
    await db.execute('PRAGMA foreign_keys=OFF');
    try {
      await db.transaction((txn) async {
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );
        for (final row in tables) {
          final name = row['name'] as String;
          if (!removesTable(name, scope) &&
              !(scope == UserContentRemovalScope.library &&
                  p.basename(db.path) == 'eLibrary.db' &&
                  name != 'library_items' &&
                  name != 'elibrary_markups' &&
                  !metadataTables.contains(name) &&
                  !name.startsWith('bible_') &&
                  name != 'books' &&
                  name != 'verses' &&
                  !name.startsWith('strong') &&
                  !name.startsWith('cross_reference'))) {
            continue;
          }
          await txn.execute('DELETE FROM "${name.replaceAll('"', '""')}"');
        }
        if (scope == UserContentRemovalScope.library &&
            tables.any((t) => t['name'] == 'library_items')) {
          final columns = await txn.rawQuery(
            'PRAGMA table_info(library_items)',
          );
          final names = columns.map((c) => c['name']).toSet();
          final values = <String, Object?>{};
          if (names.contains('deleted_at')) {
            values['deleted_at'] = DateTime.now().toUtc().toIso8601String();
          }
          if (names.contains('is_missing')) values['is_missing'] = 1;
          if (names.contains('anchor_id')) values['anchor_id'] = null;
          if (values.isNotEmpty) await txn.update('library_items', values);
        }
      });
      // DELETE alone does not return SQLite pages to the operating system.
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      await db.execute('VACUUM');
      await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      final check = await db.rawQuery('PRAGMA quick_check');
      if (check.first.values.first != 'ok') {
        throw StateError('Database integrity check failed.');
      }
    } finally {
      await db.execute('PRAGMA foreign_keys=${foreignKeys == 1 ? 1 : 0}');
    }
  }

  static List<String> folders(UserContentRemovalScope scope, bool backups) => [
    ...libraryRemovalFolders,
    if (scope == UserContentRemovalScope.allUserData) ...personalRemovalFolders,
    if (backups) 'Backups',
    if (backups) 'LegacyBackup',
  ];

  static Future<Map<String, int>> scanFiles(
    String root,
    List<String> folders,
  ) async {
    final canonicalRoot = await Directory(root).resolveSymbolicLinks();
    final result = <String, int>{};
    for (final folder in folders) {
      final path = p.join(root, folder);
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      final directory = Directory(path);
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final resolved = await entity.resolveSymbolicLinks();
        if (!p.isWithin(canonicalRoot, resolved)) {
          throw StateError('A content path escapes the library folder.');
        }
        final base = p.basename(entity.path).toLowerCase();
        if (base == 'bible_base.db' || base == 'cross_references.db') continue;
        result[entity.path] = await entity.length();
      }
    }
    return result;
  }

  static Future<Map<String, int>> scanAllOwnedFiles(
    List<String> roots,
    bool backups,
    Set<String> activeDatabases,
  ) async {
    final result = <String, int>{};
    for (final root in roots) {
      if (!await Directory(root).exists()) continue;
      final canonical = await Directory(root).resolveSymbolicLinks();
      await for (final entity in Directory(
        root,
      ).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final resolved = await entity.resolveSymbolicLinks();
        if (!p.isWithin(canonical, resolved)) {
          throw StateError('A file escapes app-owned storage.');
        }
        final parts = p.split(p.relative(entity.path, from: root));
        if (!backups &&
            parts.any(
              (part) =>
                  {'backups', 'legacybackup'}.contains(part.toLowerCase()),
            )) {
          continue;
        }
        final base = p.basename(entity.path).toLowerCase();
        if ({
          'bible_base.db',
          'cross_references.db',
          'app_local_state.json',
        }.contains(base)) {
          continue;
        }
        if (activeDatabases.any(
          (db) =>
              entity.path == db ||
              entity.path == '$db-wal' ||
              entity.path == '$db-shm' ||
              entity.path == '$db-journal',
        )) {
          continue;
        }
        result[entity.path] = await entity.length();
      }
    }
    return result;
  }

  Future<UserContentRemovalPlan> preview(
    UserContentRemovalScope scope,
    bool backups,
  ) async {
    await LibraryRootService.instance.requireLibraryAuthorization(write: true);
    final root = await LibraryRootService.instance.accessibleLibraryRootPath();
    if (root == null || !await Directory(root).exists()) {
      throw StateError('Reconnect your library folder first.');
    }
    final remoteProof = await LibraryRootNative.removeAndroidUserContent(
      allUserData: scope == UserContentRemovalScope.allUserData,
      includeBackups: backups,
      preview: true,
    );
    if (remoteProof == null ||
        p.normalize(remoteProof['privatePath']?.toString() ?? '') !=
            p.normalize(root)) {
      throw StateError(
        'Cleanup is available only for the isolated Android app library. Shared folders are never deleted.',
      );
    }
    final user = await UserDatabase.instance.database;
    final library = await ELibraryDatabase.instance.database;
    final ownedRoots = (remoteProof['ownedRoots'] as List).cast<String>();
    final files = scope == UserContentRemovalScope.allUserData
        ? await scanAllOwnedFiles(ownedRoots, backups, {
            user.path,
            library.path,
          })
        : await scanFiles(root, folders(scope, backups));
    final remote = await LibraryRootNative.removeAndroidUserContent(
      allUserData: scope == UserContentRemovalScope.allUserData,
      includeBackups: backups,
      preview: true,
    );
    return UserContentRemovalPlan(
      root: root,
      scope: scope,
      includeBackups: backups,
      files: Map.unmodifiable(files),
      ownedRoots: List.unmodifiable(ownedRoots),
      fileBytes: files.values.fold(0, (a, b) => a + b),
      databaseBytes:
          await File(user.path).length() + await File(library.path).length(),
      remoteFiles: remote?['files'] as int? ?? 0,
      remoteBytes: remote?['bytes'] as int? ?? 0,
    );
  }

  Future<int> remove(UserContentRemovalPlan plan) async {
    await LibraryRootService.instance.requireLibraryAuthorization(write: true);
    final currentRoot = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    final proof = await LibraryRootNative.removeAndroidUserContent(
      allUserData: plan.allUserData,
      includeBackups: plan.includeBackups,
      preview: true,
    );
    if (proof == null ||
        p.normalize(proof['privatePath']?.toString() ?? '') !=
            p.normalize(plan.root)) {
      throw StateError('The app-owned folder could not be verified.');
    }
    if (currentRoot != plan.root) {
      throw StateError('The library location changed. Review a new preview.');
    }
    final user = await UserDatabase.instance.database;
    final library = await ELibraryDatabase.instance.database;
    final roots = (proof['ownedRoots'] as List).cast<String>();
    if (roots.join('\n') != plan.ownedRoots.join('\n')) {
      throw StateError('App storage changed. Review a new preview.');
    }
    final current = plan.allUserData
        ? await scanAllOwnedFiles(roots, plan.includeBackups, {
            user.path,
            library.path,
          })
        : await scanFiles(plan.root, folders(plan.scope, plan.includeBackups));
    if (current.length != plan.files.length ||
        current.entries.any((e) => plan.files[e.key] != e.value)) {
      throw StateError(
        'Library files changed. Review a new preview before removing.',
      );
    }
    final before =
        await File(user.path).length() + await File(library.path).length();
    // Close readers by returning to Utilities after success; callers cannot
    // navigate or start another operation while this removal is running.
    // Stop native playback before deleting any materialized audio files.
    await const MethodChannel(
      'studybible/recorded_audio',
    ).invokeMethod<void>('stop');
    await clearDatabase(library, plan.scope);
    await clearDatabase(user, plan.scope);
    final after =
        await File(user.path).length() + await File(library.path).length();
    // Native code verifies private ownership; shared originals are untouched.
    await LibraryRootNative.removeAndroidUserContent(
      allUserData: plan.allUserData,
      includeBackups: plan.includeBackups,
      preview: false,
    );
    for (final file in plan.files.keys) {
      if (await File(file).exists()) await File(file).delete();
    }
    if (plan.allUserData) {
      final settings = await LocalSettingsStore.instance.load();
      settings.removeWhere(
        (key, value) =>
            key != 'device_id' &&
            !key.startsWith('library_root_') &&
            !key.startsWith('startup_') &&
            key != 'migration_state',
      );
      await LocalSettingsStore.instance.save(settings);
    }
    // Derived audio and import caches can be regenerated from the bundled
    // recordings; their removal never edits the APK or original recordings.
    final temporary = await getTemporaryDirectory();
    for (final name in [
      'qwen_bible',
      'qwen_loop_cues',
      'FilesProviderImports',
    ]) {
      final cache = Directory(p.join(temporary.path, name));
      if (await cache.exists()) await cache.delete(recursive: true);
    }
    return plan.fileBytes +
        plan.remoteBytes +
        (before - after).clamp(0, before).toInt();
  }
}
