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

String _formatBytes(int value) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = value.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  return '${size.toStringAsFixed(size < 10 && unitIndex > 0 ? 1 : 0)} ${units[unitIndex]}';
}

Object? _manifestValue(Map<String, Object?> manifest, List<String> keys) {
  for (final key in keys) {
    if (manifest.containsKey(key)) {
      return manifest[key];
    }
  }
  return null;
}

String? _manifestString(Map<String, Object?> manifest, List<String> keys) {
  final value = _manifestValue(manifest, keys);
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _manifestInt(Map<String, Object?> manifest, List<String> keys) {
  final value = _manifestValue(manifest, keys);
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

DateTime? _manifestDateTime(Map<String, Object?> manifest, List<String> keys) {
  final text = _manifestString(manifest, keys);
  if (text == null) return null;
  return DateTime.tryParse(text);
}

List<String> _manifestStringList(
  Map<String, Object?> manifest,
  List<String> keys,
) {
  final value = _manifestValue(manifest, keys);
  if (value is List) {
    return value.map((item) => item.toString()).toList();
  }
  return const <String>[];
}

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

class StudyBibleBackupInspectionResult {
  const StudyBibleBackupInspectionResult({
    required this.archivePath,
    required this.archiveName,
    required this.backupFormatVersion,
    required this.appName,
    required this.appVersion,
    required this.createdAtUtc,
    required this.createdAtLocal,
    required this.schemaOrAppDataVersion,
    required this.rootPath,
    required this.rootSource,
    required this.rootStatus,
    required this.includedFiles,
    required this.includedDataTypes,
    required this.optionalFiles,
    required this.totalFileCount,
    required this.totalSizeBytes,
    required this.requiredFileChecks,
    required this.optionalMediaPresent,
    required this.warnings,
    required this.errors,
    required this.manifest,
  });

  final String archivePath;
  final String archiveName;
  final int? backupFormatVersion;
  final String? appName;
  final String? appVersion;
  final DateTime? createdAtUtc;
  final DateTime? createdAtLocal;
  final int? schemaOrAppDataVersion;
  final String? rootPath;
  final String? rootSource;
  final String? rootStatus;
  final List<String> includedFiles;
  final List<String> includedDataTypes;
  final List<String> optionalFiles;
  final int totalFileCount;
  final int totalSizeBytes;
  final Map<String, bool> requiredFileChecks;
  final bool optionalMediaPresent;
  final List<String> warnings;
  final List<String> errors;
  final Map<String, Object?> manifest;

  bool get isPass =>
      errors.isEmpty && requiredFileChecks.values.every((value) => value);

  String? userFacingFailureMessage() {
    final manifestProblem =
        !includedFiles.contains('backup_manifest.json') ||
        errors.any(
          (error) =>
              error.contains('backup_manifest.json was not found.') ||
              error.contains('Could not read backup archive:') ||
              error.contains('backup_format_version is missing or invalid.'),
        ) ||
        (backupFormatVersion == null);
    if (manifestProblem) {
      return 'This does not appear to be a StudyBible2 backup file.';
    }

    final missingRequiredFiles =
        requiredFileChecks.values.any((value) => !value) ||
        errors.any(
          (error) => error.contains(
            'One or more required StudyBible2 backup files are missing.',
          ),
        );
    if (missingRequiredFiles) {
      return 'This backup cannot be restored because required user-data files are missing.';
    }

    return null;
  }

  String toDiagnosticText() {
    final buffer = StringBuffer();
    void line(String label, Object? value) {
      buffer.writeln('$label: ${value ?? '(not set)'}');
    }

    line('Result', isPass ? 'PASS' : 'FAIL');
    final failureMessage = userFacingFailureMessage();
    if (failureMessage != null) {
      line('Reason', failureMessage);
    }
    line('Archive', archiveName);
    line('Archive path', archivePath);
    line('Backup format version', backupFormatVersion);
    line('App name', appName);
    line('App version', appVersion);
    line('Backup created at UTC', createdAtUtc?.toIso8601String());
    line('Backup created at local', createdAtLocal?.toIso8601String());
    line('Source schema/app data version', schemaOrAppDataVersion);
    line('Source root path', rootPath);
    line('Source root source', rootSource);
    line('Source root status', rootStatus);
    line(
      'Included data types',
      includedDataTypes.isEmpty ? null : includedDataTypes.join(', '),
    );
    line(
      'Included files',
      includedFiles.isEmpty ? null : includedFiles.join('\n  '),
    );
    line(
      'Optional files',
      optionalFiles.isEmpty ? null : optionalFiles.join('\n  '),
    );
    line('File count', totalFileCount);
    line('Total size', _formatBytes(totalSizeBytes));
    requiredFileChecks.forEach((name, passed) {
      line('Required $name', passed ? 'present' : 'missing');
    });
    line('Optional library/media present', optionalMediaPresent ? 'yes' : 'no');
    if (warnings.isNotEmpty) {
      line('Warnings', warnings.join('\n  '));
    }
    if (errors.isNotEmpty) {
      line('Errors', errors.join('\n  '));
    }
    return buffer.toString().trimRight();
  }
}

class StudyBibleBackupRestoreResult {
  const StudyBibleBackupRestoreResult({
    required this.archivePath,
    required this.inspection,
    required this.targetRootPath,
    required this.userDatabasePath,
    required this.localSettingsPath,
    required this.restoredFiles,
    required this.safetyBackupPath,
    required this.success,
    required this.warnings,
    required this.errors,
  });

  final String archivePath;
  final StudyBibleBackupInspectionResult inspection;
  final String? targetRootPath;
  final String? userDatabasePath;
  final String? localSettingsPath;
  final List<String> restoredFiles;
  final String? safetyBackupPath;
  final bool success;
  final List<String> warnings;
  final List<String> errors;

  String toDiagnosticText() {
    final buffer = StringBuffer();
    void line(String label, Object? value) {
      buffer.writeln('$label: ${value ?? '(not set)'}');
    }

    line('Result', success ? 'PASS' : 'FAIL');
    line('Archive', archivePath);
    line('Target root path', targetRootPath);
    line('User database path', userDatabasePath);
    line('Local settings path', localSettingsPath);
    line('Safety backup', safetyBackupPath ?? 'not created');
    line(
      'Restored files',
      restoredFiles.isEmpty ? null : restoredFiles.join('\n  '),
    );
    if (warnings.isNotEmpty) {
      line('Warnings', warnings.join('\n  '));
    }
    if (errors.isNotEmpty) {
      line('Errors', errors.join('\n  '));
    }
    buffer.writeln();
    buffer.writeln('Validation report');
    buffer.writeln(inspection.toDiagnosticText());
    return buffer.toString().trimRight();
  }
}

class StudyBibleBackupService {
  StudyBibleBackupService._();

  static final StudyBibleBackupService instance = StudyBibleBackupService._();

  static const _appName = 'Biblical Heritage';
  static const _appVersion = '1.0.0+1';
  static const _backupFormatVersion = 2;
  static const _backupManifestPath = 'backup_manifest.json';
  static const _userDatabaseFileName = 'user.db';
  static const _localSettingsFileName = 'local_settings.json';
  static const _tableCountsFileName = 'table_counts.json';
  static const _optionalMediaPrefixes = <String>[
    'Media/',
    'Graphics/',
    'Images/',
    'ePubs/',
    'PDFs/',
  ];

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

  Future<String?> chooseBackupArchivePath() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choose a StudyBible2 backup',
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const <String>['zip'],
    );
    final path = result?.files.single.path?.trim() ?? '';
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
        await db.execute('VACUUM INTO ${_sqlQuote(userDbTarget.path)}');
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
        p.join(stagingDir.path, _localSettingsFileName),
      );
      await localSettingsFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(localSettings),
        flush: true,
      );

      final tableCountsFile = File(
        p.join(stagingDir.path, _tableCountsFileName),
      );
      await tableCountsFile.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(<String, Object?>{'table_counts': tableCounts}),
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
        'included_data_types': <String>[
          'user_database',
          'local_settings',
          'table_counts',
        ],
        'included_files': <String>[
          _backupManifestPath,
          _userDatabaseFileName,
          _localSettingsFileName,
          _tableCountsFileName,
        ],
        'excluded_files': excludedFiles,
        'schema_or_app_data_version': databaseVersion,
        'required_user_database_files': <String>[_userDatabaseFileName],
        'optional_library_media_included': false,
        'optional_library_media_files': <String>[],
        'table_counts': tableCounts,
        'database_copy_method': databaseCopyMethod,
        'root_path': rootPath,
        'root_source': rootSource,
        'root_status': rootStatus,
        'warnings': warnings,
      };
      final manifestFile = File(p.join(stagingDir.path, _backupManifestPath));
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
        await File(
          savedPath,
        ).writeAsBytes(await archiveFile.readAsBytes(), flush: true);
      }

      return StudyBibleBackupResult(
        backupPath: savedPath,
        archiveName: archiveName,
        manifestEntryPath: _backupManifestPath,
        includedFiles: const <String>[
          _backupManifestPath,
          _userDatabaseFileName,
          _localSettingsFileName,
          _tableCountsFileName,
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

  Future<StudyBibleBackupInspectionResult> inspectBackupArchive(
    String archivePath,
  ) async {
    final archiveFile = File(archivePath);
    final archiveName = p.basename(archivePath);
    final errors = <String>[];
    final warnings = <String>[];
    final requiredFileChecks = <String, bool>{
      _userDatabaseFileName: false,
      _localSettingsFileName: false,
      _tableCountsFileName: false,
    };
    final includedFiles = <String>[];
    final includedDataTypes = <String>[];
    final optionalFiles = <String>[];
    Map<String, Object?> manifest = <String, Object?>{};
    int? backupFormatVersion;
    String? appName;
    String? appVersion;
    DateTime? createdAtUtc;
    DateTime? createdAtLocal;
    int? schemaOrAppDataVersion;
    String? rootPath;
    String? rootSource;
    String? rootStatus;
    var totalFileCount = 0;
    var totalSizeBytes = 0;
    var optionalMediaPresent = false;

    if (!await archiveFile.exists()) {
      errors.add('Backup file not found.');
      return StudyBibleBackupInspectionResult(
        archivePath: archivePath,
        archiveName: archiveName,
        backupFormatVersion: backupFormatVersion,
        appName: appName,
        appVersion: appVersion,
        createdAtUtc: createdAtUtc,
        createdAtLocal: createdAtLocal,
        schemaOrAppDataVersion: schemaOrAppDataVersion,
        rootPath: rootPath,
        rootSource: rootSource,
        rootStatus: rootStatus,
        includedFiles: includedFiles,
        includedDataTypes: includedDataTypes,
        optionalFiles: optionalFiles,
        totalFileCount: totalFileCount,
        totalSizeBytes: totalSizeBytes,
        requiredFileChecks: requiredFileChecks,
        optionalMediaPresent: optionalMediaPresent,
        warnings: warnings,
        errors: errors,
        manifest: manifest,
      );
    }

    try {
      final bytes = await archiveFile.readAsBytes();
      if (bytes.isEmpty) {
        errors.add('Backup file is empty.');
      } else {
        final archive = ZipDecoder().decodeBytes(bytes, verify: true);
        for (final entry in archive.files) {
          final normalizedPath = _normalizeArchivePath(entry.name);
          if (normalizedPath == null) {
            errors.add('Archive contains an unsafe path: ${entry.name}');
            continue;
          }
          if (!entry.isFile) {
            continue;
          }

          totalFileCount += 1;
          totalSizeBytes += entry.size;
          includedFiles.add(normalizedPath);
          if (_isOptionalMediaPath(normalizedPath)) {
            optionalFiles.add(normalizedPath);
            optionalMediaPresent = true;
          }

          if (normalizedPath == _backupManifestPath) {
            final rawManifest = utf8.decode(entry.content as List<int>);
            final decoded = jsonDecode(rawManifest);
            if (decoded is Map) {
              manifest = decoded.map(
                (key, value) => MapEntry(key.toString(), value),
              );
            } else {
              errors.add(
                'backup_manifest.json does not contain a JSON object.',
              );
            }
          } else if (normalizedPath == _userDatabaseFileName) {
            requiredFileChecks[_userDatabaseFileName] = entry.size > 0;
          } else if (normalizedPath == _localSettingsFileName) {
            requiredFileChecks[_localSettingsFileName] = entry.size > 0;
          } else if (normalizedPath == _tableCountsFileName) {
            requiredFileChecks[_tableCountsFileName] = entry.size > 0;
          }
        }
      }
    } catch (error) {
      errors.add('Could not read backup archive: $error');
    }

    backupFormatVersion = _manifestInt(manifest, <String>[
      'backup_format_version',
      'backupFormatVersion',
    ]);
    appName = _manifestString(manifest, <String>['app_name', 'appName']);
    appVersion = _manifestString(manifest, <String>[
      'app_version',
      'appVersion',
    ]);
    createdAtUtc = _manifestDateTime(manifest, <String>[
      'backup_created_at_utc',
      'backupCreatedAtUtc',
    ]);
    createdAtLocal = _manifestDateTime(manifest, <String>[
      'backup_created_at_local',
      'backupCreatedAtLocal',
    ]);
    schemaOrAppDataVersion = _manifestInt(manifest, <String>[
      'schema_or_app_data_version',
      'schemaOrAppDataVersion',
    ]);
    rootPath = _manifestString(manifest, <String>['root_path', 'rootPath']);
    rootSource = _manifestString(manifest, <String>[
      'root_source',
      'rootSource',
    ]);
    rootStatus = _manifestString(manifest, <String>[
      'root_status',
      'rootStatus',
    ]);

    if (manifest.isEmpty) {
      errors.add('backup_manifest.json was not found.');
    } else {
      if (backupFormatVersion == null) {
        errors.add('backup_format_version is missing or invalid.');
      }
      if (appName == null) {
        warnings.add('The backup manifest did not include an app name.');
      }
      if (createdAtUtc == null) {
        warnings.add('The backup manifest did not include a backup date.');
      }
      if (_manifestValue(manifest, <String>[
            'schema_or_app_data_version',
            'schemaOrAppDataVersion',
          ]) ==
          null) {
        warnings.add('Schema/app data version was not recorded.');
      }
    }

    if (!requiredFileChecks.values.every((value) => value)) {
      errors.add('One or more required StudyBible2 backup files are missing.');
    }
    if (optionalMediaPresent) {
      warnings.add(
        'This backup includes personal-use library/media files. Users are responsible for copyright and source-site rules, and library PDF/EPUB files should not be shared or redistributed.',
      );
    }
    if (includedFiles.isEmpty) {
      errors.add('No files were found in the backup archive.');
    }

    final includedDataTypesFromManifest = _manifestStringList(
      manifest,
      <String>['included_data_types', 'includedDataTypes'],
    );
    if (includedDataTypesFromManifest.isNotEmpty) {
      includedDataTypes
        ..clear()
        ..addAll(includedDataTypesFromManifest);
    } else {
      if (requiredFileChecks[_userDatabaseFileName] == true) {
        includedDataTypes.add('user_database');
      }
      if (requiredFileChecks[_localSettingsFileName] == true) {
        includedDataTypes.add('local_settings');
      }
      if (requiredFileChecks[_tableCountsFileName] == true) {
        includedDataTypes.add('table_counts');
      }
      if (optionalMediaPresent) {
        includedDataTypes.add('library_media');
      }
    }

    return StudyBibleBackupInspectionResult(
      archivePath: archivePath,
      archiveName: archiveName,
      backupFormatVersion: backupFormatVersion,
      appName: appName,
      appVersion: appVersion,
      createdAtUtc: createdAtUtc,
      createdAtLocal: createdAtLocal,
      schemaOrAppDataVersion: schemaOrAppDataVersion,
      rootPath: rootPath,
      rootSource: rootSource,
      rootStatus: rootStatus,
      includedFiles: includedFiles,
      includedDataTypes: includedDataTypes,
      optionalFiles: optionalFiles,
      totalFileCount: totalFileCount,
      totalSizeBytes: totalSizeBytes,
      requiredFileChecks: requiredFileChecks,
      optionalMediaPresent: optionalMediaPresent,
      warnings: warnings,
      errors: errors,
      manifest: manifest,
    );
  }

  Future<StudyBibleBackupRestoreResult> restoreBackupArchive(
    String archivePath, {
    bool createSafetyBackup = false,
  }) async {
    final inspection = await inspectBackupArchive(archivePath);
    final restoreWarnings = <String>[...inspection.warnings];
    final restoreErrors = <String>[];
    String? safetyBackupPath;
    String? targetRootPath;
    String? userDatabasePath;
    String? localSettingsPath;
    final restoredFiles = <String>[];

    if (!inspection.isPass) {
      restoreErrors.addAll(inspection.errors);
      return StudyBibleBackupRestoreResult(
        archivePath: archivePath,
        inspection: inspection,
        targetRootPath: targetRootPath,
        userDatabasePath: userDatabasePath,
        localSettingsPath: localSettingsPath,
        restoredFiles: restoredFiles,
        safetyBackupPath: safetyBackupPath,
        success: false,
        warnings: restoreWarnings,
        errors: restoreErrors,
      );
    }

    final tempParent = await getTemporaryDirectory();
    final stagingDir = Directory(
      p.join(
        tempParent.path,
        'studybible_restore_${DateTime.now().toUtc().microsecondsSinceEpoch}',
      ),
    );
    await stagingDir.create(recursive: true);

    try {
      final archiveFile = File(archivePath);
      final bytes = await archiveFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      await _extractArchiveToDirectory(
        archive: archive,
        destinationDir: stagingDir,
      );

      final stagedManifest = await _readJsonFile(
        File(p.join(stagingDir.path, _backupManifestPath)),
      );
      final stagedLocalSettings = await _readJsonFile(
        File(p.join(stagingDir.path, _localSettingsFileName)),
      );
      final stagedUserDb = File(p.join(stagingDir.path, _userDatabaseFileName));

      if (stagedManifest == null) {
        throw StateError('backup_manifest.json could not be restored.');
      }
      if (stagedLocalSettings == null) {
        throw StateError('local_settings.json could not be restored.');
      }
      if (!await stagedUserDb.exists()) {
        throw StateError('user.db could not be restored.');
      }

      final selectedRootPath = _resolveRestoreRootPath(
        manifest: stagedManifest,
        localSettings: stagedLocalSettings,
      );
      if (selectedRootPath != null && selectedRootPath.trim().isNotEmpty) {
        targetRootPath = p.normalize(selectedRootPath.trim());
        await LibraryRootService.instance.ensureStructure(targetRootPath);
      }

      if (createSafetyBackup) {
        final backupResult = await createBackup();
        if (backupResult == null) {
          throw StateError('Safety backup was cancelled.');
        }
        safetyBackupPath = backupResult.backupPath;
      }

      await UserDatabase.instance.close();

      userDatabasePath = targetRootPath != null
          ? p.join(targetRootPath, 'Databases', _userDatabaseFileName)
          : await SandboxBootstrap.userDatabasePath();
      final rootForDb = targetRootPath ?? p.dirname(userDatabasePath);
      localSettingsPath = await _localSettingsFilePath();

      await _restoreFileWithRollback(
        sourcePath: stagedUserDb.path,
        targetPath: userDatabasePath,
      );
      restoredFiles.add(userDatabasePath);

      await _writeJsonAtomically(
        path: localSettingsPath,
        data: stagedLocalSettings,
      );
      LibraryRootService.instance.invalidateCachedSelection();
      restoredFiles.add(localSettingsPath);

      final optionalFilesToRestore = <String>[...inspection.optionalFiles];
      for (final relativePath in optionalFilesToRestore) {
        final source = File(p.join(stagingDir.path, relativePath));
        if (!await source.exists()) continue;
        final target = p.join(rootForDb, relativePath);
        await LibraryRootService.instance.ensureStructure(rootForDb);
        await _restoreFileWithRollback(
          sourcePath: source.path,
          targetPath: target,
        );
        restoredFiles.add(target);
      }

      return StudyBibleBackupRestoreResult(
        archivePath: archivePath,
        inspection: inspection,
        targetRootPath: targetRootPath ?? rootForDb,
        userDatabasePath: userDatabasePath,
        localSettingsPath: localSettingsPath,
        restoredFiles: restoredFiles,
        safetyBackupPath: safetyBackupPath,
        success: true,
        warnings: restoreWarnings,
        errors: restoreErrors,
      );
    } catch (error) {
      restoreErrors.add(error.toString());
      return StudyBibleBackupRestoreResult(
        archivePath: archivePath,
        inspection: inspection,
        targetRootPath: targetRootPath,
        userDatabasePath: userDatabasePath,
        localSettingsPath: localSettingsPath,
        restoredFiles: restoredFiles,
        safetyBackupPath: safetyBackupPath,
        success: false,
        warnings: restoreWarnings,
        errors: restoreErrors,
      );
    } finally {
      if (await stagingDir.exists()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  Future<void> _extractArchiveToDirectory({
    required Archive archive,
    required Directory destinationDir,
  }) async {
    for (final entry in archive.files) {
      if (!entry.isFile) {
        continue;
      }
      final normalizedPath = _normalizeArchivePath(entry.name);
      if (normalizedPath == null) {
        throw StateError(
          'Backup archive contains an unsafe path: ${entry.name}',
        );
      }
      final outputFile = File(p.join(destinationDir.path, normalizedPath));
      await outputFile.parent.create(recursive: true);
      await outputFile.writeAsBytes(entry.content as List<int>, flush: true);
    }
  }

  Future<void> _restoreFileWithRollback({
    required String sourcePath,
    required String targetPath,
  }) async {
    final source = File(sourcePath);
    final target = File(targetPath);
    await target.parent.create(recursive: true);

    final stagedFile = File('${target.path}.restore_in_progress');
    final previousFile = File('${target.path}.restore_previous');
    if (await stagedFile.exists()) {
      await stagedFile.delete();
    }
    if (await previousFile.exists()) {
      await previousFile.delete();
    }

    await source.copy(stagedFile.path);
    await _verifyBackupFile(stagedFile);

    var movedExistingTarget = false;
    try {
      if (await target.exists()) {
        await target.rename(previousFile.path);
        movedExistingTarget = true;
      }
      await stagedFile.rename(target.path);
    } catch (_) {
      if (await stagedFile.exists()) {
        try {
          await stagedFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      if (movedExistingTarget && await previousFile.exists()) {
        try {
          if (await target.exists()) {
            await target.delete();
          }
          await previousFile.rename(target.path);
        } catch (_) {
          // Best-effort rollback only.
        }
      }
      rethrow;
    } finally {
      if (await previousFile.exists()) {
        try {
          await previousFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      if (await stagedFile.exists()) {
        try {
          await stagedFile.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  Future<void> _writeJsonAtomically({
    required String path,
    required Map<String, Object?> data,
  }) async {
    final target = File(path);
    await target.parent.create(recursive: true);
    final staged = File('${target.path}.restore_in_progress');
    final previous = File('${target.path}.restore_previous');
    if (await staged.exists()) {
      await staged.delete();
    }
    if (await previous.exists()) {
      await previous.delete();
    }
    await staged.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    var movedExistingTarget = false;
    try {
      if (await target.exists()) {
        await target.rename(previous.path);
        movedExistingTarget = true;
      }
      await staged.rename(target.path);
    } catch (_) {
      if (await staged.exists()) {
        try {
          await staged.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      if (movedExistingTarget && await previous.exists()) {
        try {
          if (await target.exists()) {
            await target.delete();
          }
          await previous.rename(target.path);
        } catch (_) {
          // Best-effort rollback only.
        }
      }
      rethrow;
    } finally {
      if (await previous.exists()) {
        try {
          await previous.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
      if (await staged.exists()) {
        try {
          await staged.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }

  Future<Map<String, Object?>?> _readJsonFile(File file) async {
    if (!await file.exists()) {
      return null;
    }
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  Future<String> _localSettingsFilePath() async {
    final supportDir = await getApplicationSupportDirectory();
    return p.join(supportDir.path, 'local_settings', 'app_local_state.json');
  }

  String? _resolveRestoreRootPath({
    required Map<String, Object?> manifest,
    required Map<String, Object?> localSettings,
  }) {
    final manifestRoot = manifest['root_path']?.toString().trim() ?? '';
    if (manifestRoot.isNotEmpty) {
      return manifestRoot;
    }
    final settingsRoot =
        localSettings['library_root_path']?.toString().trim() ?? '';
    if (settingsRoot.isNotEmpty) {
      return settingsRoot;
    }
    return null;
  }

  String? _normalizeArchivePath(String pathName) {
    final normalized = p.posix.normalize(pathName.replaceAll('\\', '/')).trim();
    if (normalized.isEmpty || normalized == '.' || normalized == '/') {
      return null;
    }
    if (normalized.startsWith('../') ||
        normalized.contains('/../') ||
        normalized == '..' ||
        p.posix.isAbsolute(normalized)) {
      return null;
    }
    return normalized;
  }

  bool _isOptionalMediaPath(String pathName) {
    final normalized = pathName.replaceAll('\\', '/');
    return _optionalMediaPrefixes.any(
      (prefix) => normalized.startsWith(prefix),
    );
  }
}
