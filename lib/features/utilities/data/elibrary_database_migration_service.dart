import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/sandbox_bootstrap.dart';
import '../../../core/database/elibrary_database.dart';
import '../../../core/database/user_database.dart';

class ELibraryDatabaseMigrationSchemaTableReport {
  const ELibraryDatabaseMigrationSchemaTableReport({
    required this.tableName,
    required this.sourceColumns,
    required this.destinationColumns,
    required this.missingColumnsInSource,
    required this.missingColumnsInDestination,
    required this.sourceIndexes,
    required this.destinationIndexes,
    required this.missingIndexesInSource,
    required this.missingIndexesInDestination,
  });

  final String tableName;
  final List<String> sourceColumns;
  final List<String> destinationColumns;
  final List<String> missingColumnsInSource;
  final List<String> missingColumnsInDestination;
  final List<String> sourceIndexes;
  final List<String> destinationIndexes;
  final List<String> missingIndexesInSource;
  final List<String> missingIndexesInDestination;

  bool get compatible =>
      missingColumnsInSource.isEmpty &&
      missingColumnsInDestination.isEmpty &&
      missingIndexesInSource.isEmpty &&
      missingIndexesInDestination.isEmpty;

  bool get identical =>
      compatible &&
      _sameOrder(sourceColumns, destinationColumns) &&
      _sameOrder(sourceIndexes, destinationIndexes);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'table_name': tableName,
      'source_columns': sourceColumns,
      'destination_columns': destinationColumns,
      'missing_columns_in_source': missingColumnsInSource,
      'missing_columns_in_destination': missingColumnsInDestination,
      'source_indexes': sourceIndexes,
      'destination_indexes': destinationIndexes,
      'missing_indexes_in_source': missingIndexesInSource,
      'missing_indexes_in_destination': missingIndexesInDestination,
      'compatible': compatible,
      'identical': identical,
    };
  }

  String toDiagnosticText() {
    final parts = <String>[
      compatible ? 'compatible' : 'blocked',
      if (!identical) 'compatible but not identical',
      if (missingColumnsInSource.isNotEmpty)
        'missing in source: ${missingColumnsInSource.join(", ")}',
      if (missingColumnsInDestination.isNotEmpty)
        'missing in eLibrary.db: ${missingColumnsInDestination.join(", ")}',
      if (missingIndexesInSource.isNotEmpty)
        'missing source indexes: ${missingIndexesInSource.join(", ")}',
      if (missingIndexesInDestination.isNotEmpty)
        'missing eLibrary.db indexes: ${missingIndexesInDestination.join(", ")}',
      if (sourceColumns != destinationColumns) 'column order differs',
      if (sourceIndexes != destinationIndexes) 'index order differs',
    ];
    return '$tableName: ${parts.join("; ")}';
  }

  static bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

class ELibraryDatabaseMigrationTableReport {
  const ELibraryDatabaseMigrationTableReport({
    required this.tableName,
    required this.sourceRowCount,
    required this.destinationRowCountBefore,
    required this.matchingRowCountBefore,
    required this.wouldInsertRowCount,
    required this.skippedExistingRowCount,
    required this.insertedRowCount,
    required this.destinationRowCountAfter,
    required this.matchingRowCountAfter,
    required this.schemaReport,
  });

  final String tableName;
  final int sourceRowCount;
  final int destinationRowCountBefore;
  final int matchingRowCountBefore;
  final int wouldInsertRowCount;
  final int skippedExistingRowCount;
  final int insertedRowCount;
  final int destinationRowCountAfter;
  final int matchingRowCountAfter;
  final ELibraryDatabaseMigrationSchemaTableReport schemaReport;

  bool get completeBefore => matchingRowCountBefore >= sourceRowCount;

  bool get completeAfter => matchingRowCountAfter >= sourceRowCount;

  double get completenessBefore =>
      sourceRowCount == 0 ? 1.0 : matchingRowCountBefore / sourceRowCount;

  double get completenessAfter =>
      sourceRowCount == 0 ? 1.0 : matchingRowCountAfter / sourceRowCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'table_name': tableName,
      'source_row_count': sourceRowCount,
      'destination_row_count_before': destinationRowCountBefore,
      'matching_row_count_before': matchingRowCountBefore,
      'would_insert_row_count': wouldInsertRowCount,
      'skipped_existing_row_count': skippedExistingRowCount,
      'inserted_row_count': insertedRowCount,
      'destination_row_count_after': destinationRowCountAfter,
      'matching_row_count_after': matchingRowCountAfter,
      'complete_before': completeBefore,
      'complete_after': completeAfter,
      'completeness_before': completenessBefore,
      'completeness_after': completenessAfter,
      'schema_report': schemaReport.toJson(),
    };
  }

  String toDiagnosticText() {
    return '$tableName: '
        'source=$sourceRowCount '
        'dest_before=$destinationRowCountBefore '
        'match_before=$matchingRowCountBefore '
        'would_insert=$wouldInsertRowCount '
        'inserted=$insertedRowCount '
        'dest_after=$destinationRowCountAfter '
        'match_after=$matchingRowCountAfter';
  }
}

class ELibraryDatabaseMigrationReport {
  const ELibraryDatabaseMigrationReport({
    required this.startedAtUtc,
    required this.completedAtUtc,
    required this.dryRun,
    required this.schemaCompatible,
    required this.schemaReports,
    required this.tableReports,
    required this.sourceDatabasePath,
    required this.destinationDatabasePath,
    required this.sourceRowCount,
    required this.destinationRowCountBefore,
    required this.destinationRowCountAfter,
    required this.matchingRowCountBefore,
    required this.matchingRowCountAfter,
    required this.wouldInsertRowCount,
    required this.skippedExistingRowCount,
    required this.insertedRowCount,
    required this.backupDirectoryPath,
    required this.reportFilePath,
  });

  final DateTime startedAtUtc;
  final DateTime? completedAtUtc;
  final bool dryRun;
  final bool schemaCompatible;
  final List<ELibraryDatabaseMigrationSchemaTableReport> schemaReports;
  final List<ELibraryDatabaseMigrationTableReport> tableReports;
  final String sourceDatabasePath;
  final String destinationDatabasePath;
  final int sourceRowCount;
  final int destinationRowCountBefore;
  final int destinationRowCountAfter;
  final int matchingRowCountBefore;
  final int matchingRowCountAfter;
  final int wouldInsertRowCount;
  final int skippedExistingRowCount;
  final int insertedRowCount;
  final String? backupDirectoryPath;
  final String? reportFilePath;

  bool get migrationNeeded => wouldInsertRowCount > 0;

  bool get migrationComplete => matchingRowCountAfter >= sourceRowCount;

  double get completenessBefore =>
      sourceRowCount == 0 ? 1.0 : matchingRowCountBefore / sourceRowCount;

  double get completenessAfter =>
      sourceRowCount == 0 ? 1.0 : matchingRowCountAfter / sourceRowCount;

  String get activeReadSourceAfterCopy {
    if (sourceRowCount == 0) return 'empty';
    if (migrationComplete) return 'eLibrary.db';
    if (matchingRowCountAfter > 0) return 'mixed';
    return 'user.db fallback';
  }

  List<String> get schemaIssues {
    return schemaReports
        .where((report) => !report.compatible)
        .map((report) => report.toDiagnosticText())
        .toList(growable: false);
  }

  String get completenessLabel =>
      '${(completenessAfter * 100).toStringAsFixed(1)}%';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'started_at_utc': startedAtUtc.toIso8601String(),
      'completed_at_utc': completedAtUtc?.toIso8601String(),
      'dry_run': dryRun,
      'schema_compatible': schemaCompatible,
      'schema_reports': schemaReports
          .map((report) => report.toJson())
          .toList(growable: false),
      'table_reports': tableReports
          .map((report) => report.toJson())
          .toList(growable: false),
      'source_database_path': sourceDatabasePath,
      'destination_database_path': destinationDatabasePath,
      'source_row_count': sourceRowCount,
      'destination_row_count_before': destinationRowCountBefore,
      'destination_row_count_after': destinationRowCountAfter,
      'matching_row_count_before': matchingRowCountBefore,
      'matching_row_count_after': matchingRowCountAfter,
      'would_insert_row_count': wouldInsertRowCount,
      'skipped_existing_row_count': skippedExistingRowCount,
      'inserted_row_count': insertedRowCount,
      'migration_needed': migrationNeeded,
      'migration_complete': migrationComplete,
      'completeness_before': completenessBefore,
      'completeness_after': completenessAfter,
      'completeness_label': completenessLabel,
      'active_read_source_after_copy': activeReadSourceAfterCopy,
      'backup_directory_path': backupDirectoryPath,
      'report_file_path': reportFilePath,
      'schema_issues': schemaIssues,
      'table_status_lines': tableReports
          .map((report) => report.toDiagnosticText())
          .toList(growable: false),
    };
  }

  String toDiagnosticText() {
    final buffer = StringBuffer();
    void line(String label, Object? value) {
      buffer.writeln('$label: ${value ?? '(not set)'}');
    }

    line('Dry run', dryRun ? 'yes' : 'no');
    line('Schema compatible', schemaCompatible ? 'yes' : 'no');
    line('Source database', sourceDatabasePath);
    line('Destination database', destinationDatabasePath);
    line('Migration needed', migrationNeeded ? 'yes' : 'no');
    line('Source rows', sourceRowCount);
    line('Destination rows before', destinationRowCountBefore);
    line('Destination rows after', destinationRowCountAfter);
    line('Matching rows before', matchingRowCountBefore);
    line('Matching rows after', matchingRowCountAfter);
    line('Would insert rows', wouldInsertRowCount);
    line('Skipped existing rows', skippedExistingRowCount);
    line('Inserted rows', insertedRowCount);
    line(
      'Completeness before',
      '${(completenessBefore * 100).toStringAsFixed(1)}%',
    );
    line('Completeness after', completenessLabel);
    line('Active read source after copy', activeReadSourceAfterCopy);
    line('Backup directory', backupDirectoryPath);
    line('Report file', reportFilePath);
    if (schemaIssues.isNotEmpty) {
      line('Schema issues', schemaIssues.join('\n  '));
    }
    for (final table in tableReports) {
      line(table.tableName, table.toDiagnosticText());
    }
    return buffer.toString().trimRight();
  }

  ELibraryDatabaseMigrationReport copyWith({
    DateTime? completedAtUtc,
    bool? dryRun,
    bool? schemaCompatible,
    List<ELibraryDatabaseMigrationSchemaTableReport>? schemaReports,
    List<ELibraryDatabaseMigrationTableReport>? tableReports,
    String? sourceDatabasePath,
    String? destinationDatabasePath,
    int? sourceRowCount,
    int? destinationRowCountBefore,
    int? destinationRowCountAfter,
    int? matchingRowCountBefore,
    int? matchingRowCountAfter,
    int? wouldInsertRowCount,
    int? skippedExistingRowCount,
    int? insertedRowCount,
    String? backupDirectoryPath,
    String? reportFilePath,
  }) {
    return ELibraryDatabaseMigrationReport(
      startedAtUtc: startedAtUtc,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      dryRun: dryRun ?? this.dryRun,
      schemaCompatible: schemaCompatible ?? this.schemaCompatible,
      schemaReports: schemaReports ?? this.schemaReports,
      tableReports: tableReports ?? this.tableReports,
      sourceDatabasePath: sourceDatabasePath ?? this.sourceDatabasePath,
      destinationDatabasePath:
          destinationDatabasePath ?? this.destinationDatabasePath,
      sourceRowCount: sourceRowCount ?? this.sourceRowCount,
      destinationRowCountBefore:
          destinationRowCountBefore ?? this.destinationRowCountBefore,
      destinationRowCountAfter:
          destinationRowCountAfter ?? this.destinationRowCountAfter,
      matchingRowCountBefore:
          matchingRowCountBefore ?? this.matchingRowCountBefore,
      matchingRowCountAfter:
          matchingRowCountAfter ?? this.matchingRowCountAfter,
      wouldInsertRowCount: wouldInsertRowCount ?? this.wouldInsertRowCount,
      skippedExistingRowCount:
          skippedExistingRowCount ?? this.skippedExistingRowCount,
      insertedRowCount: insertedRowCount ?? this.insertedRowCount,
      backupDirectoryPath: backupDirectoryPath ?? this.backupDirectoryPath,
      reportFilePath: reportFilePath ?? this.reportFilePath,
    );
  }
}

class ELibraryDatabaseMigrationService {
  ELibraryDatabaseMigrationService._();

  static final ELibraryDatabaseMigrationService instance =
      ELibraryDatabaseMigrationService._();

  static const List<String> _tables = <String>[
    'library_items',
    'library_links',
    'library_navigation_items',
    'library_text_blocks',
    'elibrary_ref_index',
    'elibrary_markups',
    'elibrary_install_estimates',
  ];

  Future<ELibraryDatabaseMigrationReport> buildDryRunReport() async {
    final startedAt = DateTime.now().toUtc();
    final sourceDb = await UserDatabase.instance.database;
    final destinationDb = await ELibraryDatabase.instance.database;
    final sourceDatabasePath = await SandboxBootstrap.userDatabasePath();
    final destinationDatabasePath =
        await SandboxBootstrap.eLibraryDatabasePath();
    final schemaReports = await _compareSchemas(sourceDb, destinationDb);
    final schemaCompatible = schemaReports.every((report) => report.compatible);
    final report =
        await _withAttachedLegacyDatabase<ELibraryDatabaseMigrationReport>(
          destinationDb,
          sourceDatabasePath,
          () async {
            final tableReports = await _buildTableReports(
              destinationDb: destinationDb,
              legacySchemaName: 'legacy_elibrary',
              schemaReports: schemaReports,
            );
            return _assembleReport(
              startedAt: startedAt,
              dryRun: true,
              schemaReports: schemaReports,
              schemaCompatible: schemaCompatible,
              tableReports: tableReports,
              sourceDatabasePath: sourceDatabasePath,
              destinationDatabasePath: destinationDatabasePath,
              backupDirectoryPath: null,
              reportFilePath: await _latestReportPath(),
            );
          },
        );
    return report;
  }

  Future<ELibraryDatabaseMigrationReport> copyLegacyData({
    bool createBackups = true,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final sourceDb = await UserDatabase.instance.database;
    final destinationDb = await ELibraryDatabase.instance.database;
    final sourceDatabasePath = await SandboxBootstrap.userDatabasePath();
    final destinationDatabasePath =
        await SandboxBootstrap.eLibraryDatabasePath();
    final schemaReports = await _compareSchemas(sourceDb, destinationDb);
    final schemaCompatible = schemaReports.every((report) => report.compatible);
    if (!schemaCompatible) {
      throw StateError(
        'eLibrary database schema is incompatible with user.db legacy rows.',
      );
    }

    final backupDirectoryPath = createBackups
        ? await _createDatabaseBackups(
            sourceDatabasePath: sourceDatabasePath,
            destinationDatabasePath: destinationDatabasePath,
            startedAt: startedAt,
          )
        : null;

    late List<ELibraryDatabaseMigrationTableReport> preCopyReports;
    late List<ELibraryDatabaseMigrationTableReport> postCopyReports;
    await _withAttachedLegacyDatabase<void>(
      destinationDb,
      sourceDatabasePath,
      () async {
        preCopyReports = await _buildTableReports(
          destinationDb: destinationDb,
          legacySchemaName: 'legacy_elibrary',
          schemaReports: schemaReports,
        );
        await _copyAllTables(destinationDb: destinationDb);
        postCopyReports = await _buildTableReports(
          destinationDb: destinationDb,
          legacySchemaName: 'legacy_elibrary',
          schemaReports: schemaReports,
        );
      },
    );

    final report = _assembleReport(
      startedAt: startedAt,
      dryRun: false,
      schemaReports: schemaReports,
      schemaCompatible: schemaCompatible,
      tableReports: _mergeTableReports(
        before: preCopyReports,
        after: postCopyReports,
      ),
      sourceDatabasePath: sourceDatabasePath,
      destinationDatabasePath: destinationDatabasePath,
      backupDirectoryPath: backupDirectoryPath,
      reportFilePath: null,
    );
    final savedReportPath = await _writeReport(report);
    return report.copyWith(
      completedAtUtc: DateTime.now().toUtc(),
      reportFilePath: savedReportPath,
    );
  }

  Future<String?> latestReportPath() async {
    final reportRoot = await _reportRootPath();
    if (reportRoot == null) {
      return null;
    }
    final directory = Directory(reportRoot);
    if (!await directory.exists()) {
      return null;
    }
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  p
                      .basename(file.path)
                      .startsWith('elibrary_database_migration_') &&
                  p.extension(file.path) == '.json',
            )
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    return files.isEmpty ? null : files.last.path;
  }

  Future<List<ELibraryDatabaseMigrationSchemaTableReport>> _compareSchemas(
    Database sourceDb,
    Database destinationDb,
  ) async {
    final reports = <ELibraryDatabaseMigrationSchemaTableReport>[];
    for (final table in _tables) {
      final sourceColumns = await _tableColumns(sourceDb, table);
      final destinationColumns = await _tableColumns(destinationDb, table);
      final sourceIndexes = await _tableIndexes(sourceDb, table);
      final destinationIndexes = await _tableIndexes(destinationDb, table);
      final sourceColumnMap = {
        for (final column in sourceColumns) column.name: column,
      };
      final destinationColumnMap = {
        for (final column in destinationColumns) column.name: column,
      };
      final sourceColumnNames = sourceColumns
          .map((column) => column.name)
          .toList(growable: false);
      final destinationColumnNames = destinationColumns
          .map((column) => column.name)
          .toList(growable: false);
      final sourceIndexNames = sourceIndexes
          .map((index) => index.name)
          .toList(growable: false);
      final destinationIndexNames = destinationIndexes
          .map((index) => index.name)
          .toList(growable: false);

      reports.add(
        ELibraryDatabaseMigrationSchemaTableReport(
          tableName: table,
          sourceColumns: sourceColumnNames,
          destinationColumns: destinationColumnNames,
          missingColumnsInSource: destinationColumnNames
              .where((name) => !sourceColumnMap.containsKey(name))
              .toList(growable: false),
          missingColumnsInDestination: sourceColumnNames
              .where((name) => !destinationColumnMap.containsKey(name))
              .toList(growable: false),
          sourceIndexes: sourceIndexNames,
          destinationIndexes: destinationIndexNames,
          missingIndexesInSource: destinationIndexNames
              .where((name) => !sourceIndexNames.contains(name))
              .toList(growable: false),
          missingIndexesInDestination: sourceIndexNames
              .where((name) => !destinationIndexNames.contains(name))
              .toList(growable: false),
        ),
      );
    }
    return reports;
  }

  Future<List<ELibraryDatabaseMigrationTableReport>> _buildTableReports({
    required Database destinationDb,
    required String legacySchemaName,
    required List<ELibraryDatabaseMigrationSchemaTableReport> schemaReports,
  }) async {
    final reports = <ELibraryDatabaseMigrationTableReport>[];
    for (var index = 0; index < _tables.length; index++) {
      final table = _tables[index];
      final schemaReport = schemaReports[index];
      final sourceRowCount = await _tableRowCount(
        destinationDb,
        table,
        schema: legacySchemaName,
      );
      final destinationRowCountBefore = await _tableRowCount(
        destinationDb,
        table,
      );
      final matchingRowCountBefore = await _tableMatchingRowCount(
        destinationDb: destinationDb,
        table: table,
        legacySchemaName: legacySchemaName,
      );
      final wouldInsertRowCount = sourceRowCount > matchingRowCountBefore
          ? sourceRowCount - matchingRowCountBefore
          : 0;
      reports.add(
        ELibraryDatabaseMigrationTableReport(
          tableName: table,
          sourceRowCount: sourceRowCount,
          destinationRowCountBefore: destinationRowCountBefore,
          matchingRowCountBefore: matchingRowCountBefore,
          wouldInsertRowCount: wouldInsertRowCount,
          skippedExistingRowCount: matchingRowCountBefore,
          insertedRowCount: 0,
          destinationRowCountAfter: destinationRowCountBefore,
          matchingRowCountAfter: matchingRowCountBefore,
          schemaReport: schemaReport,
        ),
      );
    }
    return reports;
  }

  List<ELibraryDatabaseMigrationTableReport> _mergeTableReports({
    required List<ELibraryDatabaseMigrationTableReport> before,
    required List<ELibraryDatabaseMigrationTableReport> after,
  }) {
    final reports = <ELibraryDatabaseMigrationTableReport>[];
    for (var index = 0; index < before.length; index++) {
      final beforeReport = before[index];
      final afterReport = after[index];
      reports.add(
        ELibraryDatabaseMigrationTableReport(
          tableName: beforeReport.tableName,
          sourceRowCount: beforeReport.sourceRowCount,
          destinationRowCountBefore: beforeReport.destinationRowCountBefore,
          matchingRowCountBefore: beforeReport.matchingRowCountBefore,
          wouldInsertRowCount: beforeReport.wouldInsertRowCount,
          skippedExistingRowCount: beforeReport.skippedExistingRowCount,
          insertedRowCount: beforeReport.wouldInsertRowCount,
          destinationRowCountAfter: afterReport.destinationRowCountBefore,
          matchingRowCountAfter: afterReport.matchingRowCountBefore,
          schemaReport: beforeReport.schemaReport,
        ),
      );
    }
    return reports;
  }

  ELibraryDatabaseMigrationReport _assembleReport({
    required DateTime startedAt,
    required bool dryRun,
    required List<ELibraryDatabaseMigrationSchemaTableReport> schemaReports,
    required bool schemaCompatible,
    required List<ELibraryDatabaseMigrationTableReport> tableReports,
    required String sourceDatabasePath,
    required String destinationDatabasePath,
    required String? backupDirectoryPath,
    required String? reportFilePath,
  }) {
    final sourceRowCount = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.sourceRowCount,
    );
    final destinationRowCountBefore = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.destinationRowCountBefore,
    );
    final destinationRowCountAfter = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.destinationRowCountAfter,
    );
    final matchingRowCountBefore = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.matchingRowCountBefore,
    );
    final matchingRowCountAfter = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.matchingRowCountAfter,
    );
    final wouldInsertRowCount = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.wouldInsertRowCount,
    );
    final skippedExistingRowCount = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.skippedExistingRowCount,
    );
    final insertedRowCount = tableReports.fold<int>(
      0,
      (sum, report) => sum + report.insertedRowCount,
    );

    return ELibraryDatabaseMigrationReport(
      startedAtUtc: startedAt,
      completedAtUtc: dryRun ? null : DateTime.now().toUtc(),
      dryRun: dryRun,
      schemaCompatible: schemaCompatible,
      schemaReports: schemaReports,
      tableReports: tableReports,
      sourceDatabasePath: sourceDatabasePath,
      destinationDatabasePath: destinationDatabasePath,
      sourceRowCount: sourceRowCount,
      destinationRowCountBefore: destinationRowCountBefore,
      destinationRowCountAfter: destinationRowCountAfter,
      matchingRowCountBefore: matchingRowCountBefore,
      matchingRowCountAfter: matchingRowCountAfter,
      wouldInsertRowCount: wouldInsertRowCount,
      skippedExistingRowCount: skippedExistingRowCount,
      insertedRowCount: insertedRowCount,
      backupDirectoryPath: backupDirectoryPath,
      reportFilePath: reportFilePath,
    );
  }

  Future<void> _copyAllTables({required Database destinationDb}) async {
    await destinationDb.transaction((txn) async {
      for (final table in _tables) {
        final columns = await _tableColumnNames(txn, table);
        final quotedColumns = columns.map(_quoteIdentifier).join(', ');
        final quotedTable = _quoteIdentifier(table);
        await txn.execute('''
          INSERT OR IGNORE INTO $quotedTable ($quotedColumns)
          SELECT $quotedColumns
          FROM legacy_elibrary.$quotedTable
        ''');
      }
    });
  }

  Future<String?> _createDatabaseBackups({
    required String sourceDatabasePath,
    required String destinationDatabasePath,
    required DateTime startedAt,
  }) async {
    final backupRoot = await LibraryRootService.instance.backupRootPath();
    final backupDir = Directory(
      p.join(
        backupRoot,
        'elibrary_database_migration_${_timestamp(startedAt)}',
      ),
    );
    await backupDir.create(recursive: true);

    await _copyDatabaseFiles(sourceDatabasePath, backupDir, prefix: 'user');
    await _copyDatabaseFiles(
      destinationDatabasePath,
      backupDir,
      prefix: 'elibrary',
    );
    return backupDir.path;
  }

  Future<void> _copyDatabaseFiles(
    String databasePath,
    Directory backupDir, {
    required String prefix,
  }) async {
    final file = File(databasePath);
    if (!await file.exists()) {
      return;
    }
    final base = p.basename(databasePath);
    await file.copy(p.join(backupDir.path, '$prefix-$base'));
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$databasePath$suffix');
      if (!await sidecar.exists()) continue;
      await sidecar.copy(p.join(backupDir.path, '$prefix-$base$suffix'));
    }
  }

  Future<List<_TableColumnInfo>> _tableColumns(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery(
      'PRAGMA table_info(${_quoteIdentifier(tableName)})',
    );
    return rows
        .map(
          (row) => _TableColumnInfo(
            name: row['name']?.toString() ?? '',
            type: row['type']?.toString() ?? '',
            notNull: ((row['notnull'] as num?)?.toInt() ?? 0) != 0,
            defaultValue: row['dflt_value']?.toString(),
            primaryKey: ((row['pk'] as num?)?.toInt() ?? 0) != 0,
          ),
        )
        .where((column) => column.name.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> _tableColumnNames(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final columns = await _tableColumns(db, tableName);
    return columns.map((column) => column.name).toList(growable: false);
  }

  Future<List<_TableIndexInfo>> _tableIndexes(
    DatabaseExecutor db,
    String tableName,
  ) async {
    final rows = await db.rawQuery(
      'PRAGMA index_list(${_quoteIdentifier(tableName)})',
    );
    final indexes = <_TableIndexInfo>[];
    for (final row in rows) {
      final name = row['name']?.toString() ?? '';
      if (name.isEmpty) continue;
      final unique = ((row['unique'] as num?)?.toInt() ?? 0) != 0;
      final origin = row['origin']?.toString() ?? '';
      final sqlRows = await db.rawQuery(
        '''
        SELECT sql
        FROM sqlite_master
        WHERE type = 'index' AND name = ?
        LIMIT 1
        ''',
        [name],
      );
      final sql = sqlRows.isEmpty ? null : sqlRows.first['sql']?.toString();
      indexes.add(
        _TableIndexInfo(
          name: name,
          unique: unique,
          origin: origin,
          sql: _normalizeSql(sql),
        ),
      );
    }
    indexes.sort((left, right) => left.name.compareTo(right.name));
    return indexes;
  }

  Future<int> _tableRowCount(
    DatabaseExecutor db,
    String tableName, {
    String schema = 'main',
  }) async {
    final qualifiedTable = schema == 'main'
        ? _quoteIdentifier(tableName)
        : '$schema.${_quoteIdentifier(tableName)}';
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM $qualifiedTable',
    );
    return rows.isEmpty ? 0 : (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  Future<int> _tableMatchingRowCount({
    required DatabaseExecutor destinationDb,
    required String table,
    required String legacySchemaName,
  }) async {
    final joinClause = _joinClause(table);
    final rows = await destinationDb.rawQuery('''
      SELECT COUNT(*) AS cnt
      FROM ${_quoteIdentifier(table)} dest
      INNER JOIN $legacySchemaName.${_quoteIdentifier(table)} src
        ON $joinClause
      ''');
    if (rows.isNotEmpty) {
      return (rows.first['cnt'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<T> _withAttachedLegacyDatabase<T>(
    Database destinationDb,
    String sourceDatabasePath,
    Future<T> Function() action,
  ) async {
    final escapedSourcePath = _escapeSqlLiteral(sourceDatabasePath);
    await destinationDb.execute(
      "ATTACH DATABASE '$escapedSourcePath' AS legacy_elibrary",
    );
    try {
      return await action();
    } finally {
      await destinationDb.execute('DETACH DATABASE legacy_elibrary');
    }
  }

  String _joinClause(String table) {
    if (table == 'elibrary_install_estimates') {
      return 'dest.collection_key = src.collection_key AND dest.format = src.format';
    }
    return 'dest.id = src.id';
  }

  Future<String?> _reportRootPath() async {
    final root = await LibraryRootService.instance.libraryRootPath();
    if (root == null || root.trim().isEmpty) return null;
    return p.join(root, 'legacy_migration_reports');
  }

  Future<String?> _latestReportPath() async {
    final reportRoot = await _reportRootPath();
    if (reportRoot == null) return null;
    final directory = Directory(reportRoot);
    if (!await directory.exists()) return null;
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  p
                      .basename(file.path)
                      .startsWith('elibrary_database_migration_') &&
                  p.extension(file.path) == '.json',
            )
            .toList(growable: false)
          ..sort((left, right) => left.path.compareTo(right.path));
    return files.isEmpty ? null : files.last.path;
  }

  Future<String> _writeReport(ELibraryDatabaseMigrationReport report) async {
    final reportRoot = await _reportRootPath();
    if (reportRoot == null) {
      throw StateError('Library root is not selected.');
    }
    final directory = Directory(reportRoot);
    await directory.create(recursive: true);
    final reportPath = p.join(
      directory.path,
      'elibrary_database_migration_${_timestamp(report.completedAtUtc ?? DateTime.now().toUtc())}.json',
    );
    await File(reportPath).writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({...report.toJson(), 'report_file_path': reportPath}),
    );
    return reportPath;
  }

  String _escapeSqlLiteral(String value) {
    return value.replaceAll("'", "''");
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  String _normalizeSql(String? sql) {
    if (sql == null) return '';
    return sql.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }

  String _timestamp(DateTime dt) {
    final utc = dt.toUtc();
    return utc
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('-', '')
        .replaceAll('.', '_');
  }
}

class _TableColumnInfo {
  const _TableColumnInfo({
    required this.name,
    required this.type,
    required this.notNull,
    required this.defaultValue,
    required this.primaryKey,
  });

  final String name;
  final String type;
  final bool notNull;
  final String? defaultValue;
  final bool primaryKey;
}

class _TableIndexInfo {
  const _TableIndexInfo({
    required this.name,
    required this.unique,
    required this.origin,
    required this.sql,
  });

  final String name;
  final bool unique;
  final String origin;
  final String sql;
}
