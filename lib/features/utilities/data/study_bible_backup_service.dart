import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/sandbox_bootstrap.dart';
import '../../../core/database/user_database.dart';

class StudyBibleBackupResult {
  const StudyBibleBackupResult({
    required this.backupPath,
    required this.archiveName,
    required this.manifestEntryPath,
    required this.includedFiles,
    required this.excludedFiles,
    required this.tableCounts,
    required this.databaseCopyMethod,
    required this.databaseVersion,
    required this.warnings,
    required this.rootPath,
    required this.rootSource,
    required this.rootStatus,
  });

  final String backupPath;
  final String archiveName;
  final String manifestEntryPath;
  final List<String> includedFiles;
  final List<String> excludedFiles;
  final Map<String, int> tableCounts;
  final String databaseCopyMethod;
  final int databaseVersion;
  final List<String> warnings;
  final String? rootPath;
  final String rootSource;
  final String rootStatus;
}

class StudyBibleBackupService {
  StudyBibleBackupService._();

  static final StudyBibleBackupService instance =
      StudyBibleBackupService._();

  static const _appName = 'Biblical Heritage';
  static const _appVersion = '1.0.0+1';
  static const _backupFormatVersion = 2;

  bool get supportsFolderChooser => !Platform.isIOS;

  Future<String> defaultBackupParentFolder() async {
    final backupRoot = await LibraryRootService.instance.backupRootPath();
    await Directory(backupRoot).create(recursive: true);
    return backupRoot;
  }

  Future<String?> chooseBackupParentFolder() async {
    if (!supportsFolderChooser) {
      return null;
    }
    final picked = await LibraryRootNative.pickFolder();
    final path = picked?.path.trim() ?? '';
    if (path.isEmpty) return null;
    return path;
  }

  Future<StudyBibleBackupResult?> createBackup() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path?.trim();
    final rootSource = selection.sourceLabel;
    final rootStatus = selection.statusLabel;
    final createdAtUtc = DateTime.now().toUtc();
    final createdAtLocal = createdAtUtc.toLocal();
    final archiveName = _archiveName(createdAtLocal);

    final tempParent = await getTemporaryDirectory();
    final stagingDir = Directory(
      p.join(
        tempParent.path,
        'studybible_backup_${createdAtUtc.microsecondsSinceEpoch}',
      ),
    );
    final archivePath = p.join(tempParent.path, 'tmp_$archiveName');
    await stagingDir.create(recursive: true);

    try {
      final sourceDbPath = await SandboxBootstrap.userDatabasePath();
      final sourceDbFile = File(sourceDbPath);
      if (!await sourceDbFile.exists() || await sourceDbFile.length() <= 0) {
        throw StateError('user.db was not found or is empty.');
      }

      final db = await UserDatabase.instance.database;
      await _checkpointWalBestEffort(db);
      final tableCounts = await _loadTableCounts(db);
      final databaseVersion = await db.getVersion();
      final localSettings = await LocalSettingsStore.instance.load();
      final warnings = <String>[
        'Downloaded EGW EPUB/PDF files are excluded by default.',
        'Caches and derived indexes are not exported separately.',
      ];
      final excludedFiles = <String>[
        'Downloaded EGW EPUB/PDF library files',
        'Caches and derived indexes',
        'Temporary folders',
      ];

      final userDbTarget = File(p.join(stagingDir.path, 'user.db'));
      var databaseCopyMethod = 'vacuum_into';
      try {
        await db.execute(
          'VACUUM INTO ${_sqlQuote(userDbTarget.path)}',
        );
      } catch (_) {
        databaseCopyMethod = 'file_copy_with_wal';
        await sourceDbFile.copy(userDbTarget.path);
        await _copySidecarIfPresent(
          sourceDbPath: sourceDbPath,
          targetDbPath: userDbTarget.path,
          sidecarSuffix: '-wal',
        );
        await _copySidecarIfPresent(
          sourceDbPath: sourceDbPath,
          targetDbPath: userDbTarget.path,
          sidecarSuffix: '-shm',
        );
        await _copySidecarIfPresent(
          sourceDbPath: sourceDbPath,
          targetDbPath: userDbTarget.path,
          sidecarSuffix: '-journal',
        );
      }

      final localSettingsFile = File(
        p.join(stagingDir.path, 'local_settings.json'),
      );
      await localSettingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(localSettings),
        flush: true,
      );

      final tableCountsFile = File(p.join(stagingDir.path, 'table_counts.json'));
      await tableCountsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'table_counts': tableCounts,
        }),
        flush: true,
      );

      final manifest = <String, Object?>{
        'backup_format_version': _backupFormatVersion,
        'app_name': _appName,
        'app_version': _appVersion,
        'backup_created_at_utc': createdAtUtc.toIso8601String(),
        'backup_created_at_local': createdAtLocal.toIso8601String(),
        'platform': Platform.operatingSystem,
        'database_file_names': <String>['user.db'],
        'included_files': <String>[
          'backup_manifest.json',
          'user.db',
          'local_settings.json',
          'table_counts.json',
        ],
        'excluded_files': excludedFiles,
        'schema_or_app_data_version': databaseVersion,
        'table_counts': tableCounts,
        'database_copy_method': databaseCopyMethod,
        'root_path': rootPath,
        'root_source': rootSource,
        'root_status': rootStatus,
        'warnings': warnings,
      };
      final manifestFile = File(
        p.join(stagingDir.path, 'backup_manifest.json'),
      );
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
        flush: true,
      );

      await _verifyBackupFile(userDbTarget);
      await _verifyBackupFile(localSettingsFile);
      await _verifyBackupFile(tableCountsFile);
      await _verifyBackupFile(manifestFile);

      final encoder = ZipFileEncoder();
      await encoder.zipDirectory(
        stagingDir,
        filename: archivePath,
        modified: createdAtUtc,
      );

      final archiveFile = File(archivePath);
      if (!await archiveFile.exists() || await archiveFile.length() <= 0) {
        throw StateError('Backup archive was not created.');
      }

      final mobileSave = Platform.isIOS || Platform.isAndroid;
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save $archiveName',
        fileName: archiveName,
        initialDirectory: tempParent.path,
        type: FileType.custom,
        allowedExtensions: const <String>['zip'],
        bytes: mobileSave ? await archiveFile.readAsBytes() : null,
      );

      if (savedPath == null || savedPath.trim().isEmpty) {
        return null;
      }

      if (!mobileSave) {
        await File(savedPath).writeAsBytes(
          await archiveFile.readAsBytes(),
          flush: true,
        );
      }

      return StudyBibleBackupResult(
        backupPath: savedPath,
        archiveName: archiveName,
        manifestEntryPath: 'backup_manifest.json',
        includedFiles: const <String>[
          'backup_manifest.json',
          'user.db',
          'local_settings.json',
          'table_counts.json',
        ],
        excludedFiles: excludedFiles,
        tableCounts: tableCounts,
        databaseCopyMethod: databaseCopyMethod,
        databaseVersion: databaseVersion,
        warnings: warnings,
        rootPath: rootPath,
        rootSource: rootSource,
        rootStatus: rootStatus,
      );
    } finally {
      if (await stagingDir.exists()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      final archiveFile = File(archivePath);
      if (await archiveFile.exists()) {
        try {
          await archiveFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  Future<Map<String, int>> _loadTableCounts(Database db) async {
    final rows = await db.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name COLLATE NOCASE ASC
    ''');
    final counts = <String, int>{};
    for (final row in rows) {
      final table = row['name']?.toString().trim() ?? '';
      if (table.isEmpty) continue;
      final countRows = await db.rawQuery(
        'SELECT COUNT(*) AS cnt FROM ${_quoteIdentifier(table)}',
      );
      final count = countRows.isNotEmpty
          ? (countRows.first['cnt'] as num?)?.toInt() ?? 0
          : 0;
      counts[table] = count;
    }
    return counts;
  }

  Future<void> _copySidecarIfPresent({
    required String sourceDbPath,
    required String targetDbPath,
    required String sidecarSuffix,
  }) async {
    final source = File('$sourceDbPath$sidecarSuffix');
    if (!await source.exists()) return;
    final target = File('$targetDbPath$sidecarSuffix');
    await source.copy(target.path);
  }

  Future<void> _checkpointWalBestEffort(Database db) async {
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(PASSIVE)');
    } catch (_) {
      // If the checkpoint cannot run, the backup can still fall back to a
      // sidecar-aware file copy.
    }
  }

  Future<void> _verifyBackupFile(File file) async {
    if (!await file.exists()) {
      throw StateError('Backup file missing: ${file.path}');
    }
    if (await file.length() <= 0) {
      throw StateError('Backup file is empty: ${file.path}');
    }
  }

  String _archiveName(DateTime localTime) {
    final year = localTime.year.toString().padLeft(4, '0');
    final month = localTime.month.toString().padLeft(2, '0');
    final day = localTime.day.toString().padLeft(2, '0');
    final hour = localTime.hour.toString().padLeft(2, '0');
    final minute = localTime.minute.toString().padLeft(2, '0');
    final timestamp = '$year$month${day}_$hour$minute';
    return 'BiblicalHeritage_Backup_$timestamp.zip';
  }

  String _sqlQuote(String input) {
    return "'${input.replaceAll("'", "''")}'";
  }

  String _quoteIdentifier(String input) {
    return '"${input.replaceAll('"', '""')}"';
  }
}
