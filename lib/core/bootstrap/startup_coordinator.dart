import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/elibrary_database.dart';
import '../database/user_database.dart';
import 'library_root_service.dart';
import 'library_root_native.dart';
import 'local_settings_store.dart';
import 'sandbox_bootstrap.dart';
import 'development_runtime_overrides.dart';
import '../../features/library/data/canonical_epub_generation_repair_service.dart';
import '../../features/library/data/library_catalog_service.dart';
import '../../features/utilities/data/pioneer_captured_html_import_availability_service.dart';
import '../../features/utilities/data/elibrary_catalog_duplicate_repair_service.dart';

enum StartupPhase {
  noLegacyFound,
  legacyFoundWaitingForUser,
  backupInProgress,
  backupCompleted,
  migrationInProgress,
  migrationCompleted,
  freshInstallSelected,
  migrationFailed,
  ready,
}

class StartupSnapshot {
  const StartupSnapshot({
    required this.phase,
    required this.message,
    this.migrationKey,
    this.backupPath,
    this.importReportPath,
    this.errorMessage,
  });

  final StartupPhase phase;
  final String message;
  final String? migrationKey;
  final String? backupPath;
  final String? importReportPath;
  final String? errorMessage;

  bool get isReady => phase == StartupPhase.ready;
  bool get requiresDecision => phase == StartupPhase.legacyFoundWaitingForUser;
}

class StartupCoordinator {
  StartupCoordinator._();

  static final StartupCoordinator instance = StartupCoordinator._();

  static const _fromVersion = 'legacy-v1';
  static const _toVersion = 'v2';

  Future<StartupSnapshot> initialize({ValueChanged<String>? onStatus}) async {
    onStatus?.call('Checking saved startup state...');
    _ensureDesktopSqlite();
    onStatus?.call('Reading device identity...');
    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    onStatus?.call('Reading saved migration state...');
    final migrationState = await LocalSettingsStore.instance
        .loadMigrationState();
    final migrationStatus = migrationState['status']?.toString() ?? '';
    final migrationKey = migrationState['migration_key']?.toString().trim();

    if (migrationStatus == 'migration_completed' ||
        migrationStatus == 'fresh_install_selected') {
      onStatus?.call('Preparing user database...');
      await _ensureFreshV2Database(deviceId: deviceId);
      onStatus?.call('Recording startup state...');
      await _recordMigrationRow(
        deviceId: deviceId,
        migrationKey: migrationKey ?? 'migration_completed',
        startedAt: migrationState['started_at']?.toString() ?? _utcNow(),
        completedAt: migrationState['completed_at']?.toString() ?? _utcNow(),
        backupPath: migrationState['backup_path']?.toString(),
        status: migrationStatus,
        errorMessage: migrationState['error_message']?.toString(),
        sourceDeviceName: _sourceDeviceName(),
      );
      return StartupSnapshot(
        phase: StartupPhase.ready,
        message: 'User database ready.',
        migrationKey: migrationKey,
        backupPath: migrationState['backup_path']?.toString(),
      );
    }

    onStatus?.call('Scanning for legacy user data...');
    final legacyFiles = await _discoverLegacyWritableFiles();
    final hasRealLegacyContent =
        legacyFiles.isNotEmpty && await _legacyDatabaseHasRealContent();
    if (legacyFiles.isEmpty || !hasRealLegacyContent) {
      // A legacy user.db file can exist (and be non-zero bytes purely from
      // SQLite's own page/schema overhead) without containing any actual
      // tags, notes, bookmarks, or highlights. Treat that case the same as
      // no legacy file at all so users on the default library location
      // never see the 3-way decision prompt for data that isn't really
      // there to lose.
      final migrationKey = legacyFiles.isEmpty
          ? 'no_legacy_found'
          : 'no_legacy_content';
      onStatus?.call('Preparing fresh user database...');
      await _ensureFreshV2Database(deviceId: deviceId);
      onStatus?.call('Recording startup state...');
      await _recordMigrationRow(
        deviceId: deviceId,
        migrationKey: migrationKey,
        startedAt: _utcNow(),
        completedAt: _utcNow(),
        backupPath: null,
        status: migrationKey,
        errorMessage: null,
        sourceDeviceName: _sourceDeviceName(),
      );
      await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
        'migration_key': migrationKey,
        'from_version': _fromVersion,
        'to_version': _toVersion,
        'started_at': _utcNow(),
        'completed_at': _utcNow(),
        'backup_path': null,
        'status': migrationKey,
        'error_message': null,
      });
      return StartupSnapshot(
        phase: StartupPhase.noLegacyFound,
        message: legacyFiles.isEmpty
            ? 'No legacy user data found.'
            : 'Legacy user database found but contained no tags, notes, '
                  'bookmarks, or highlights to preserve.',
        migrationKey: migrationKey,
      );
    }

    final backupPath = migrationState['backup_path']?.toString();
    final promptMessage = switch (migrationStatus) {
      'backup_completed' =>
        'Legacy data backup already exists. Choose how to proceed.',
      'backup_in_progress' =>
        'A legacy backup was already started. Choose how to proceed.',
      'migration_in_progress' =>
        'A migration was already started. Choose how to proceed.',
      'migration_failed' =>
        'The prior migration attempt failed. Choose how to proceed.',
      _ => 'Legacy writable user data was found.',
    };

    return StartupSnapshot(
      phase: StartupPhase.legacyFoundWaitingForUser,
      message: promptMessage,
      migrationKey: migrationKey,
      backupPath: backupPath,
    );
  }

  Future<void> runBackgroundMaintenance({
    bool forceLibraryRescan = false,
  }) async {
    final startedAt = DateTime.now();
    debugPrint('Startup background maintenance started.');
    if (LibraryRootNative.usesAndroidDocumentTree) {
      try {
        final report = await LibraryRootNative.scanAndroidLibraryTree(
          force: forceLibraryRescan,
        );
        if (report != null) {
          debugPrint(
            'Android library snapshot scan complete in '
            '${report.elapsedMilliseconds}ms: changed=${report.changed} '
            'unchanged=${report.unchanged} removed=${report.removed} '
            'full=${report.fullScan}.',
          );
          if (report.fullScan || report.changed > 0 || report.removed > 0) {
            final catalogStartedAt = DateTime.now();
            await LibraryCatalogService.instance.refreshManagedItemsFromDisk();
            debugPrint(
              'Android changed-library catalog reconciliation complete in '
              '${DateTime.now().difference(catalogStartedAt).inMilliseconds}ms.',
            );
          }
        }
      } catch (error) {
        debugPrint('Android background library scan failed: $error');
      }
    }
    await _runLegacyEgwCatalogRepair();
    await _runConfiguredCaptureFolderImport();
    debugPrint(
      'Startup background maintenance complete in '
      '${DateTime.now().difference(startedAt).inMilliseconds}ms.',
    );
  }

  Future<void> _runConfiguredCaptureFolderImport({
    ValueChanged<String>? onStatus,
  }) async {
    if (shouldSkipCaptureClipperStartupScan()) {
      onStatus?.call('CaptureClipper startup scan disabled for this run.');
      debugPrint(
        'CaptureClipper startup availability scan skipped by development override.',
      );
      return;
    }
    final folderPath = await LocalSettingsStore.instance
        .loadPioneerCapturedHtmlFolderPath();
    if (folderPath == null || folderPath.trim().isEmpty) {
      onStatus?.call(
        'No CaptureClipper cloud folder configured; skipping detection.',
      );
      debugPrint(
        'CaptureClipper startup detection skipped: no configured folder.',
      );
      return;
    }

    onStatus?.call('Checking CaptureClipper cloud folders...');
    try {
      final report = await PioneerCapturedHtmlImportAvailabilityService.instance
          .refresh();
      if (!report.hasAvailableImports) {
        onStatus?.call('CaptureClipper cloud folders checked.');
        debugPrint(
          'CaptureClipper startup discovery found no importable folders at '
          '${report.rootPath}.',
        );
      } else {
        onStatus?.call(
          'CaptureClipper cloud import available: ${report.availableCount} '
          'folder${report.availableCount == 1 ? '' : 's'}.',
        );
        debugPrint(
          'CaptureClipper startup discovery found ${report.availableCount} '
          'importable folder(s) under ${report.rootPath}.',
        );
      }
    } catch (error) {
      debugPrint(
        'CaptureClipper cloud discovery failed during startup: $error',
      );
    }

    await _runCanonicalEpubGenerationRepair(onStatus: onStatus);
  }

  Future<void> _runLegacyEgwCatalogRepair({
    ValueChanged<String>? onStatus,
  }) async {
    try {
      onStatus?.call('Checking eLibrary catalog identities...');
      final db = await ELibraryDatabase.instance.database;
      await ELibraryCatalogDuplicateRepairService.instance.repair(db: db);
    } catch (error) {
      debugPrint('Legacy EGW catalog duplicate repair failed: $error');
    }
  }

  /// Best-effort, non-fatal repair pass for canonical EPUB data left over
  /// from before the canonicalizer gained its structural validation gate
  /// (see CanonicalEpubGenerationRepairService). Never blocks startup: any
  /// failure here is logged and swallowed, matching the CaptureClipper scan
  /// immediately above.
  Future<void> _runCanonicalEpubGenerationRepair({
    ValueChanged<String>? onStatus,
  }) async {
    try {
      final rootPath =
          (await LibraryRootService.instance.accessibleLibraryRootPath())
              ?.trim();
      if (rootPath == null || rootPath.isEmpty) return;
      onStatus?.call('Checking canonical eLibrary data...');
      debugPrint('Canonical EPUB repair pass started.');
      final startedAt = DateTime.now();
      final db = await ELibraryDatabase.instance.database;
      final report = await CanonicalEpubGenerationRepairService.instance.repair(
        db: db,
        rootPath: rootPath,
        // A version mismatch is not, by itself, authority for startup
        // to rewrite every canonical EPUB. Broad upgrades are explicit
        // maintenance operations; startup retains only the safe
        // storage-state reconciliation below.
        allowVersionUpgrade: false,
      );
      final finishedAt = DateTime.now();
      debugPrint(
        'Canonical EPUB repair pass complete in '
        '${finishedAt.difference(startedAt).inMilliseconds}ms: '
        'scanned=${report.staleGenerationsScanned} '
        'regenerated=${report.regenerated} '
        'rejected=${report.rejected} '
        'skippedMissingFile=${report.skippedMissingFile} '
        'staleStorageStatesRepaired=${report.staleStorageStatesRepaired}.',
      );
    } catch (error) {
      debugPrint(
        'Canonical EPUB generation repair failed during startup: $error',
      );
    }
  }

  Future<StartupSnapshot> backUpAndUpgrade() async {
    return _runSelection(importLegacyData: true);
  }

  Future<StartupSnapshot> startFreshButKeepLegacyBackup() async {
    return _runSelection(importLegacyData: false);
  }

  Future<StartupSnapshot> _runSelection({
    required bool importLegacyData,
  }) async {
    _ensureDesktopSqlite();

    final deviceId = await LocalSettingsStore.instance.ensureDeviceId();
    final snapshot = await LocalSettingsStore.instance.loadMigrationState();
    final migrationKey = _migrationKey(snapshot);
    final sourceDeviceName = _sourceDeviceName();
    final legacyFiles = await _discoverLegacyWritableFiles();

    if (legacyFiles.isEmpty) {
      await _ensureFreshV2Database(deviceId: deviceId);
      await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
        'migration_key': 'fresh_install_selected',
        'from_version': _fromVersion,
        'to_version': _toVersion,
        'started_at': _utcNow(),
        'completed_at': _utcNow(),
        'backup_path': null,
        'status': 'fresh_install_selected',
        'error_message': null,
      });
      return const StartupSnapshot(
        phase: StartupPhase.freshInstallSelected,
        message: 'Fresh install selected.',
        migrationKey: 'fresh_install_selected',
      );
    }

    final backupRoot = await LibraryRootService.instance.backupRootPath();
    final backupDir = Directory(
      p.join(backupRoot, 'pre_v2_upgrade_${_timestampForPath()}'),
    );
    await backupDir.create(recursive: true);

    await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
      'migration_key': migrationKey,
      'from_version': _fromVersion,
      'to_version': _toVersion,
      'started_at': snapshot['started_at']?.toString() ?? _utcNow(),
      'completed_at': null,
      'backup_path': backupDir.path,
      'status': 'backup_in_progress',
      'error_message': null,
    });

    final manifest = await _backUpLegacyFiles(
      legacyFiles: legacyFiles,
      backupDir: backupDir,
      migrationKey: migrationKey,
      sourceDeviceName: sourceDeviceName,
    );

    await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
      'migration_key': migrationKey,
      'from_version': _fromVersion,
      'to_version': _toVersion,
      'started_at': manifest['started_at'],
      'completed_at': null,
      'backup_path': backupDir.path,
      'status': 'backup_completed',
      'error_message': null,
    });

    if (!importLegacyData) {
      await _ensureFreshV2Database(deviceId: deviceId);
      await _writeJson(
        File(p.join(backupDir.path, 'backup_manifest.json')),
        manifest,
      );
      await _writeJson(
        File(p.join(backupDir.path, 'import_report.json')),
        <String, Object?>{
          'migration_key': migrationKey,
          'started_at': manifest['started_at'],
          'completed_at': _utcNow(),
          'source_files': legacyFiles.map((file) => file.path).toList(),
          'source_packages_imported': 1,
          'imported_categories_created': 0,
          'groups_imported': 0,
          'items_imported': 0,
          'duplicates_skipped_within_package': 0,
          'items_preserved_for_later_processing': legacyFiles.length,
          'counts': <String, int>{
            'hash_tags': 0,
            'dollar_tags': 0,
            'tag_media': 0,
            'notes': 0,
            'bookmarks': 0,
            'highlights': 0,
            'reading_history': 0,
            'search_history': 0,
            'library_items': 0,
            'library_links': 0,
            'unmapped_records': legacyFiles.length,
          },
          'warnings': <String>['Legacy data was backed up but not imported.'],
          'skipped_records': <String>[],
          'errors': <String>[],
        },
      );
      await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
        'migration_key': migrationKey,
        'from_version': _fromVersion,
        'to_version': _toVersion,
        'started_at': manifest['started_at'],
        'completed_at': _utcNow(),
        'backup_path': backupDir.path,
        'status': 'fresh_install_selected',
        'error_message': null,
      });
      await _recordMigrationRow(
        deviceId: deviceId,
        migrationKey: migrationKey,
        startedAt: manifest['started_at']?.toString() ?? _utcNow(),
        completedAt: _utcNow(),
        backupPath: backupDir.path,
        status: 'fresh_install_selected',
        errorMessage: null,
        sourceDeviceName: sourceDeviceName,
      );
      return StartupSnapshot(
        phase: StartupPhase.freshInstallSelected,
        message: 'Fresh install selected.',
        migrationKey: migrationKey,
        backupPath: backupDir.path,
        importReportPath: p.join(backupDir.path, 'import_report.json'),
      );
    }

    await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
      'migration_key': migrationKey,
      'from_version': _fromVersion,
      'to_version': _toVersion,
      'started_at': manifest['started_at'],
      'completed_at': null,
      'backup_path': backupDir.path,
      'status': 'migration_in_progress',
      'error_message': null,
    });

    final importResult = await _importLegacyData(
      deviceId: deviceId,
      migrationKey: migrationKey,
      backupDir: backupDir,
      sourceDeviceName: sourceDeviceName,
      legacyFiles: legacyFiles,
    );

    await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
      'migration_key': migrationKey,
      'from_version': _fromVersion,
      'to_version': _toVersion,
      'started_at': manifest['started_at'],
      'completed_at': _utcNow(),
      'backup_path': backupDir.path,
      'status': 'migration_completed',
      'error_message': null,
    });
    await _recordMigrationRow(
      deviceId: deviceId,
      migrationKey: migrationKey,
      startedAt: manifest['started_at']?.toString() ?? _utcNow(),
      completedAt: _utcNow(),
      backupPath: backupDir.path,
      status: 'migration_completed',
      errorMessage: null,
      sourceDeviceName: sourceDeviceName,
    );

    return StartupSnapshot(
      phase: StartupPhase.migrationCompleted,
      message: 'Legacy data imported into the new v2 database.',
      migrationKey: migrationKey,
      backupPath: backupDir.path,
      importReportPath: importResult.importReportPath,
    );
  }

  Future<_ImportResult> _importLegacyData({
    required String deviceId,
    required String migrationKey,
    required Directory backupDir,
    required String sourceDeviceName,
    required List<File> legacyFiles,
  }) async {
    final legacyDbPath = await _primaryLegacyDatabasePath();
    if (legacyDbPath == null) {
      throw StateError('Legacy database not found.');
    }

    await _resetV2DatabaseFiles();
    final newDb = await _openV2Database(deviceId: deviceId);

    final report = <String, Object?>{
      'migration_key': migrationKey,
      'started_at': _utcNow(),
      'completed_at': null,
      'source_files': legacyFiles.map((file) => file.path).toList(),
      'source_packages_imported': 1,
      'imported_categories_created': 0,
      'groups_imported': 0,
      'items_imported': 0,
      'duplicates_skipped_within_package': 0,
      'items_preserved_for_later_processing': 0,
      'counts': <String, int>{
        'hash_tags': 0,
        'dollar_tags': 0,
        'tag_media': 0,
        'notes': 0,
        'bookmarks': 0,
        'highlights': 0,
        'reading_history': 0,
        'search_history': 0,
        'library_items': 0,
        'library_links': 0,
        'unmapped_records': 0,
      },
      'warnings': <String>[],
      'skipped_records': <String>[],
      'errors': <String>[],
    };

    try {
      final legacyOpen = await openDatabase(
        legacyDbPath,
        readOnly: true,
        singleInstance: false,
      );
      try {
        await newDb.transaction((txn) async {
          final counts = report['counts'] as Map<String, int>;
          await _clearImportedTables(txn);
          final importedAt = _utcNow();
          final packageId = migrationKey;
          final rootGroupId = 'imported_legacy_tags_root';
          final packageGroupId =
              'imported_legacy_tags_${_slug(sourceDeviceName)}_${_slug(migrationKey)}';

          var categoriesCreated = 0;
          var groupsImported = 0;
          var itemsImported = 0;
          var duplicatesSkipped = 0;
          var preservedCount = 0;

          await _upsertTagGroup(
            txn,
            id: rootGroupId,
            parentGroupId: null,
            tagKind: 'import_root',
            name: 'Imported Legacy Tags',
            description:
                'Legacy tag imports preserved for review before merge.',
            sortOrder: 0,
            sourceDeviceName: sourceDeviceName,
            legacyGroupId: null,
            legacyItemId: null,
            legacyImportPackageId: packageId,
            importedAt: importedAt,
            deviceId: deviceId,
          );
          categoriesCreated += 1;

          await _upsertTagGroup(
            txn,
            id: packageGroupId,
            parentGroupId: rootGroupId,
            tagKind: 'import_package',
            name: '$sourceDeviceName Import - ${_dateOnly(importedAt)}',
            description: 'Legacy import package $migrationKey',
            sortOrder: 0,
            sourceDeviceName: sourceDeviceName,
            legacyGroupId: null,
            legacyItemId: null,
            legacyImportPackageId: packageId,
            importedAt: importedAt,
            deviceId: deviceId,
          );
          categoriesCreated += 1;

          final tagRowSources = <({String tableName, String tagKind})>[
            (tableName: 'hash_tags', tagKind: 'hash'),
            (tableName: 'dollar_tags', tagKind: 'dollar'),
          ];

          for (final source in tagRowSources) {
            final rows = await legacyOpen.query(source.tableName);
            final groupsByTag = <String, String>{};
            final seenKeys = <String>{};
            for (final row in rows) {
              final legacyId = row['id']?.toString() ?? '';
              final tag = row['tag']?.toString().trim() ?? '';
              if (tag.isEmpty) {
                preservedCount++;
                await _insertUnmappedRow(
                  txn,
                  deviceId: deviceId,
                  sourceTable: source.tableName,
                  sourceDeviceName: sourceDeviceName,
                  legacyGroupId: row['user_id']?.toString(),
                  legacyItemId: legacyId,
                  legacyImportPackageId: packageId,
                  payload: Map<String, Object?>.from(row),
                  reason: 'Missing tag name.',
                );
                continue;
              }

              final dedupeKey = [
                source.tableName,
                tag,
                row['verse_ref']?.toString() ?? '',
                row['book_number']?.toString() ?? '',
                row['chapter_number']?.toString() ?? '',
                row['verse_number']?.toString() ?? '',
                row['token_number']?.toString() ?? '',
                row['content_html']?.toString() ?? '',
              ].join('|');
              if (!seenKeys.add(dedupeKey)) {
                duplicatesSkipped += 1;
                continue;
              }

              final tagGroupId = groupsByTag.putIfAbsent(tag, () {
                final generated =
                    'tag_group_${_slug(packageGroupId)}_${_slug(tag)}';
                return generated;
              });
              if (await _tagGroupMissing(txn, tagGroupId)) {
                await _upsertTagGroup(
                  txn,
                  id: tagGroupId,
                  parentGroupId: packageGroupId,
                  tagKind: source.tagKind,
                  name: tag,
                  description: null,
                  sortOrder: groupsImported + 1,
                  sourceDeviceName: sourceDeviceName,
                  legacyGroupId: row['user_id']?.toString(),
                  legacyItemId: legacyId,
                  legacyImportPackageId: packageId,
                  importedAt: importedAt,
                  deviceId: deviceId,
                );
                groupsImported += 1;
              }

              final bookId = (row['book_number'] as num?)?.toInt() ?? 0;
              final chapter = (row['chapter_number'] as num?)?.toInt() ?? 0;
              final verseStart = (row['verse_number'] as num?)?.toInt() ?? 0;
              final verseEnd = verseStart;
              final noteText = source.tagKind == 'dollar'
                  ? _cleanHtml(row['content_html']?.toString() ?? '')
                  : _cleanHtml(row['note_text']?.toString() ?? '');

              await txn.insert('tag_items', {
                'id':
                    'tag_item_${source.tableName}_${legacyId.isEmpty ? _slug(dedupeKey) : _slug(legacyId)}',
                'tag_group_id': tagGroupId,
                'tag_kind': source.tagKind,
                'book_id': bookId,
                'chapter': chapter,
                'verse_start': verseStart,
                'verse_end': verseEnd,
                'note_text': noteText,
                'sort_order':
                    (row['sort_order'] as num?)?.toInt() ??
                    (row['study_order'] as num?)?.toInt() ??
                    itemsImported + 1,
                'source_device_name': sourceDeviceName,
                'legacy_group_id': row['user_id']?.toString(),
                'legacy_item_id': legacyId,
                'legacy_import_package_id': packageId,
                'imported_at': importedAt,
                'created_at': importedAt,
                'updated_at': importedAt,
                'deleted_at': null,
                'device_id': deviceId,
                'revision': 1,
                'sync_status': 'pending',
                'last_synced_at': null,
                'change_id': null,
              }, conflictAlgorithm: ConflictAlgorithm.ignore);
              itemsImported += 1;
              if (source.tableName == 'hash_tags') {
                counts.update('hash_tags', (value) => value + 1);
              } else {
                counts.update('dollar_tags', (value) => value + 1);
              }

              if (source.tagKind == 'dollar') {
                final mediaRefs = _extractMediaReferences(
                  row['content_html']?.toString() ?? '',
                );
                for (var index = 0; index < mediaRefs.length; index++) {
                  final mediaRef = mediaRefs[index];
                  await txn.insert('tag_item_media', {
                    'id':
                        'tag_media_${source.tableName}_${legacyId.isEmpty ? _slug(dedupeKey) : _slug(legacyId)}_$index',
                    'tag_item_id':
                        'tag_item_${source.tableName}_${legacyId.isEmpty ? _slug(dedupeKey) : _slug(legacyId)}',
                    'media_type': 'image',
                    'relative_path': mediaRef,
                    'caption': null,
                    'file_hash': null,
                    'file_size': null,
                    'sort_order': index + 1,
                    'source_device_name': sourceDeviceName,
                    'legacy_group_id': row['user_id']?.toString(),
                    'legacy_item_id': legacyId,
                    'legacy_import_package_id': packageId,
                    'imported_at': importedAt,
                    'created_at': importedAt,
                    'updated_at': importedAt,
                    'deleted_at': null,
                    'device_id': deviceId,
                    'revision': 1,
                    'sync_status': 'pending',
                    'last_synced_at': null,
                    'change_id': null,
                  }, conflictAlgorithm: ConflictAlgorithm.ignore);
                }
                counts.update('tag_media', (value) => value + mediaRefs.length);
              }
            }
          }

          final legacyUnmappedTables = <String>[
            'at_tags',
            'history',
            'navigation_history',
            'memory_verses',
          ];
          for (final tableName in legacyUnmappedTables) {
            final rows = await legacyOpen.query(tableName);
            for (final row in rows) {
              preservedCount += 1;
              await _insertUnmappedRow(
                txn,
                deviceId: deviceId,
                sourceTable: tableName,
                sourceDeviceName: sourceDeviceName,
                legacyGroupId: row['user_id']?.toString(),
                legacyItemId: row['id']?.toString(),
                legacyImportPackageId: packageId,
                payload: Map<String, Object?>.from(row),
                reason: 'Legacy record preserved for a later import pass.',
              );
            }
          }

          await _copyCompatibilityTable(legacyOpen, txn, 'app_settings');
          await _copyCompatibilityTable(legacyOpen, txn, 'prefs');
          await _copyCompatibilityTable(legacyOpen, txn, 'users');
          await _copyCompatibilityTable(legacyOpen, txn, 'highlight_groups');
          await _copyCompatibilityTable(legacyOpen, txn, 'highlights');

          report['completed_at'] = _utcNow();
          report['imported_categories_created'] = categoriesCreated;
          report['groups_imported'] = groupsImported;
          report['items_imported'] = itemsImported;
          report['duplicates_skipped_within_package'] = duplicatesSkipped;
          report['items_preserved_for_later_processing'] = preservedCount;
          report['counts'] = <String, int>{
            'hash_tags': counts['hash_tags'] ?? 0,
            'dollar_tags': counts['dollar_tags'] ?? 0,
            'tag_media': counts['tag_media'] ?? 0,
            'notes': counts['notes'] ?? 0,
            'bookmarks': counts['bookmarks'] ?? 0,
            'highlights': counts['highlights'] ?? 0,
            'reading_history': counts['reading_history'] ?? 0,
            'search_history': counts['search_history'] ?? 0,
            'library_items': counts['library_items'] ?? 0,
            'library_links': counts['library_links'] ?? 0,
            'unmapped_records': preservedCount,
          };
        });
      } finally {
        await legacyOpen.close();
      }
    } catch (error) {
      await LocalSettingsStore.instance.saveMigrationState(<String, Object?>{
        'migration_key': migrationKey,
        'from_version': _fromVersion,
        'to_version': _toVersion,
        'started_at': _utcNow(),
        'completed_at': null,
        'backup_path': backupDir.path,
        'status': 'migration_failed',
        'error_message': error.toString(),
      });
      await _recordMigrationRow(
        deviceId: deviceId,
        migrationKey: migrationKey,
        startedAt: _utcNow(),
        completedAt: _utcNow(),
        backupPath: backupDir.path,
        status: 'migration_failed',
        errorMessage: error.toString(),
        sourceDeviceName: sourceDeviceName,
      );
      rethrow;
    } finally {
      await _writeJson(
        File(p.join(backupDir.path, 'import_report.json')),
        report,
      );
    }

    return _ImportResult(
      backupPath: backupDir.path,
      importReportPath: p.join(backupDir.path, 'import_report.json'),
      report: report,
    );
  }

  Future<void> _ensureFreshV2Database({required String deviceId}) async {
    await _openV2Database(deviceId: deviceId);
  }

  Future<void> _recordMigrationRow({
    required String deviceId,
    required String migrationKey,
    required String startedAt,
    required String completedAt,
    required String? backupPath,
    required String status,
    required String? errorMessage,
    required String sourceDeviceName,
  }) async {
    final db = await _openV2Database(deviceId: deviceId);
    await db.insert('app_migrations', {
      'migration_key': migrationKey,
      'from_version': _fromVersion,
      'to_version': _toVersion,
      'started_at': startedAt,
      'completed_at': completedAt,
      'backup_path': backupPath,
      'status': status,
      'error_message': errorMessage,
      'source_device_name': sourceDeviceName,
      'created_at': completedAt,
      'updated_at': completedAt,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Database> _openV2Database({required String deviceId}) =>
      UserDatabase.instance.database;

  Future<void> _resetV2DatabaseFiles() async {
    final path = await SandboxBootstrap.userDatabasePath();
    final candidates = [path, '$path-wal', '$path-shm', '$path-journal'];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<List<File>> _discoverLegacyWritableFiles() async {
    final paths = <String>{
      await SandboxBootstrap.legacyUserDatabasePath(),
      await SandboxBootstrap.legacyDocumentsUserDatabasePath(),
      await SandboxBootstrap.legacySupportUserDatabasePath(),
    };
    final files = <File>[];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists() && file.lengthSync() > 0) {
        files.add(file);
        for (final suffix in const ['-wal', '-shm', '-journal']) {
          final companion = File('$path$suffix');
          if (await companion.exists()) {
            files.add(companion);
          }
        }
      }
    }
    return files;
  }

  Future<String?> _primaryLegacyDatabasePath() async {
    final candidates = [
      await SandboxBootstrap.legacyUserDatabasePath(),
      await SandboxBootstrap.legacySupportUserDatabasePath(),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists() && file.lengthSync() > 0) {
        return candidate;
      }
    }
    return null;
  }

  /// Legacy content tables that hold irreplaceable user-created data. A
  /// legacy user.db with rows in none of these has nothing worth the 3-way
  /// backup/upgrade decision — it's SQLite page overhead, not user content.
  static const _legacyContentTables = <String>[
    'hash_tags',
    'dollar_tags',
    'at_tags',
    'highlights',
    'memory_verses',
    'history',
    'navigation_history',
  ];

  Future<bool> _legacyDatabaseHasRealContent() async {
    final legacyDbPath = await _primaryLegacyDatabasePath();
    if (legacyDbPath == null) return false;
    Database? legacyDb;
    try {
      legacyDb = await openDatabase(
        legacyDbPath,
        readOnly: true,
        singleInstance: false,
      );
      // Confirm this is actually a readable SQLite database (and see which
      // tables it really has) before trusting an all-tables-missing result
      // as "empty" rather than "unreadable/corrupt". A file that isn't a
      // valid SQLite database at all throws here, falling into the outer
      // catch, which conservatively treats it as containing data.
      final tableRows = await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final existingTables = tableRows
          .map((row) => row['name']?.toString() ?? '')
          .toSet();
      for (final table in _legacyContentTables) {
        if (!existingTables.contains(table)) continue;
        final result = await legacyDb.rawQuery(
          'SELECT COUNT(*) AS c FROM $table',
        );
        final count = (result.firstOrNull?['c'] as int?) ?? 0;
        if (count > 0) return true;
      }
      return false;
    } catch (error) {
      debugPrint(
        'StartupCoordinator: could not inspect legacy database for real '
        'content ($legacyDbPath): $error. Treating as containing data to '
        'be safe.',
      );
      return true;
    } finally {
      await legacyDb?.close();
    }
  }

  Future<Map<String, Object?>> _backUpLegacyFiles({
    required List<File> legacyFiles,
    required Directory backupDir,
    required String migrationKey,
    required String sourceDeviceName,
  }) async {
    final startedAt = _utcNow();
    final documentsPath = (await getApplicationDocumentsDirectory()).path;
    final supportPath = (await getApplicationSupportDirectory()).path;
    final manifest = <String, Object?>{
      'migration_key': migrationKey,
      'started_at': startedAt,
      'completed_at': null,
      'source_device_name': sourceDeviceName,
      'files': <Map<String, Object?>>[],
    };
    final backupEntries = manifest['files'] as List<Map<String, Object?>>;
    final seen = <String>{};
    for (final legacyFile in legacyFiles) {
      final normalized = p.normalize(legacyFile.path);
      if (!seen.add(normalized)) continue;
      final relative = _legacyRelativePath(
        normalized,
        documentsPath: documentsPath,
        supportPath: supportPath,
      );
      final backupPath = p.join(backupDir.path, relative);
      final targetFile = File(backupPath);
      await targetFile.parent.create(recursive: true);
      await legacyFile.copy(targetFile.path);
      final sourceStat = await legacyFile.stat();
      final targetStat = await targetFile.stat();
      if (sourceStat.size > 0 && targetStat.size != sourceStat.size) {
        throw StateError('Backup verification failed for ${legacyFile.path}.');
      }
      if (sourceStat.size <= 0 && targetStat.size <= 0) {
        throw StateError('Backup verification failed for ${legacyFile.path}.');
      }
      backupEntries.add(<String, Object?>{
        'original_path': legacyFile.path,
        'backup_path': targetFile.path,
        'size': sourceStat.size,
        'modified_at': sourceStat.modified.toUtc().toIso8601String(),
        'backup_timestamp': startedAt,
      });
    }
    manifest['completed_at'] = _utcNow();
    await _writeJson(
      File(p.join(backupDir.path, 'backup_manifest.json')),
      manifest,
    );
    return manifest;
  }

  Future<void> _copyCompatibilityTable(
    Database legacyDb,
    Transaction txn,
    String tableName,
  ) async {
    final rows = await legacyDb.query(tableName);
    await txn.delete(tableName);
    for (final row in rows) {
      await txn.insert(
        tableName,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> _clearImportedTables(Transaction txn) async {
    for (final table in const [
      'devices',
      'sync_state',
      'sync_changes',
      'tag_groups',
      'tag_items',
      'tag_item_media',
      'bookmarks',
      'notes',
      'reading_history',
      'search_history',
      'library_items',
      'library_links',
      'library_navigation_items',
      'elibrary_ref_index',
      'presentation_lists',
      'presentation_items',
      'app_migrations',
      'legacy_unmapped_import',
    ]) {
      await txn.delete(table);
    }
  }

  Future<void> _upsertTagGroup(
    Transaction txn, {
    required String id,
    required String? parentGroupId,
    required String tagKind,
    required String name,
    required String? description,
    required int sortOrder,
    required String sourceDeviceName,
    required String? legacyGroupId,
    required String? legacyItemId,
    required String legacyImportPackageId,
    required String importedAt,
    required String deviceId,
  }) async {
    await txn.insert('tag_groups', {
      'id': id,
      'parent_group_id': parentGroupId,
      'tag_kind': tagKind,
      'name': name,
      'description': description,
      'sort_order': sortOrder,
      'source_device_name': sourceDeviceName,
      'legacy_group_id': legacyGroupId,
      'legacy_item_id': legacyItemId,
      'legacy_import_package_id': legacyImportPackageId,
      'imported_at': importedAt,
      'created_at': importedAt,
      'updated_at': importedAt,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<bool> _tagGroupMissing(Transaction txn, String id) async {
    final rows = await txn.query(
      'tag_groups',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty;
  }

  Future<void> _insertUnmappedRow(
    Transaction txn, {
    required String deviceId,
    required String sourceTable,
    required String? sourceDeviceName,
    required String? legacyGroupId,
    required String? legacyItemId,
    required String legacyImportPackageId,
    required Map<String, Object?> payload,
    required String reason,
  }) async {
    final now = _utcNow();
    await txn.insert('legacy_unmapped_import', {
      'id':
          'legacy_unmapped_${_slug(sourceTable)}_${_slug(legacyItemId ?? payload.hashCode.toString())}',
      'source_table': sourceTable,
      'source_device_name': sourceDeviceName,
      'legacy_group_id': legacyGroupId,
      'legacy_item_id': legacyItemId,
      'legacy_import_package_id': legacyImportPackageId,
      'imported_at': now,
      'payload_json': jsonEncode(payload),
      'reason': reason,
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'device_id': deviceId,
      'revision': 1,
      'sync_status': 'pending',
      'last_synced_at': null,
      'change_id': null,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  List<String> _extractMediaReferences(String html) {
    final refs = <String>[];
    if (html.trim().isEmpty) return refs;
    final regex = RegExp(
      r'''(?:src|href)=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(html)) {
      final raw = match.group(1)?.trim() ?? '';
      if (raw.isEmpty) continue;
      if (raw.startsWith('data:')) continue;
      refs.add(_normalizeRelativeMediaPath(raw));
    }
    return refs;
  }

  String _normalizeRelativeMediaPath(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return cleaned;
    if (cleaned.startsWith('file://')) {
      return cleaned.replaceFirst('file://', '');
    }
    if (p.isAbsolute(cleaned)) {
      return p.basename(cleaned);
    }
    return p.normalize(cleaned);
  }

  String _cleanHtml(String raw) {
    return raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  Future<void> _writeJson(File file, Map<String, Object?> data) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
  }

  String _legacyRelativePath(
    String absolutePath, {
    required String documentsPath,
    required String supportPath,
  }) {
    final normalizedDocuments = p.normalize(documentsPath);
    final normalizedSupport = p.normalize(supportPath);
    final normalized = p.normalize(absolutePath);
    if (p.isWithin(normalizedDocuments, normalized)) {
      return p.join(
        'documents',
        p.relative(normalized, from: normalizedDocuments),
      );
    }
    if (p.isWithin(normalizedSupport, normalized)) {
      return p.join('support', p.relative(normalized, from: normalizedSupport));
    }
    return p.basename(normalized);
  }

  String _migrationKey(Map<String, Object?> state) {
    final existing = state['migration_key']?.toString().trim() ?? '';
    if (existing.isNotEmpty) return existing;
    return 'pre_v2_upgrade_${_timestampForPath()}';
  }

  String _sourceDeviceName() {
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isIOS) return 'iPad';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  String _dateOnly(String utcIso) {
    return utcIso.split('T').first;
  }

  String _slug(String input) {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return 'item';
    return normalized
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _timestampForPath() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    final compact = iso.replaceAll(RegExp(r'[-:]'), '').replaceAll('.', '_');
    return compact.replaceAll('Z', '');
  }

  String _utcNow() {
    final now = DateTime.now().toUtc();
    final iso = now.toIso8601String();
    return iso.contains('.') ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z') : iso;
  }

  void _ensureDesktopSqlite() {
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isLinux || Platform.isWindows)) {
      SandboxBootstrap.ensureSqfliteInitializedOnce();
    }
  }
}

class _ImportResult {
  const _ImportResult({
    required this.backupPath,
    required this.importReportPath,
    required this.report,
  });

  final String backupPath;
  final String importReportPath;
  final Map<String, Object?> report;
}
