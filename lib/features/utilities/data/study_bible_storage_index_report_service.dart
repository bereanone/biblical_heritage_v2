import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/sandbox_bootstrap.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../../core/database/elibrary_schema.dart';
import '../../../core/database/user_database.dart';
import 'elibrary_database_migration_service.dart';
import 'elibrary_storage_policy.dart';
import 'elibrary_file_management_service.dart';

class StudyBibleStorageIndexReport {
  const StudyBibleStorageIndexReport({
    required this.rootPath,
    required this.rootSource,
    required this.rootStatus,
    required this.rootBadge,
    required this.libraryOpenPath,
    required this.downloaderPath,
    required this.storageSummaryPath,
    required this.indexerPaths,
    required this.commentarySourcePaths,
    required this.researchSourcePaths,
    required this.commentaryIndexPath,
    required this.downloadReportsPath,
    required this.coverImagesPath,
    required this.backupPath,
    required this.userDatabasePath,
    required this.eLibraryDatabasePath,
    required this.eLibraryDatabaseExists,
    required this.eLibraryDatabaseSizeBytes,
    required this.eLibrarySchemaVersion,
    required this.eLibrarySchemaStatus,
    required this.storagePolicyLabel,
    required this.sourceCleanupStatus,
    required this.eLibraryWriteTarget,
    required this.eLibraryMigrationNeeded,
    required this.eLibraryMigrationCompletenessLabel,
    required this.eLibraryMigrationStatus,
    required this.eLibraryMigrationReportPath,
    required this.eLibraryMigrationTableSummaries,
    required this.epubCount,
    required this.pdfCount,
    required this.commentaryItemCount,
    required this.commentaryIndexedCount,
    required this.commentaryLinkCount,
    required this.researchItemCount,
    required this.researchIndexedCount,
    required this.researchLinkCount,
    required this.pathsMatch,
    required this.legacyFoldersDetected,
    required this.backupStatus,
    required this.commentaryIndexStatus,
    required this.storageSummaryStatus,
    required this.commentaryIndexReportExists,
    required this.tableCounts,
    required this.userELibraryTableCounts,
    required this.eLibraryTableCounts,
    required this.activeELibraryReadSource,
  });

  final String? rootPath;
  final String rootSource;
  final String rootStatus;
  final String rootBadge;
  final String? libraryOpenPath;
  final String? downloaderPath;
  final String? storageSummaryPath;
  final List<String> indexerPaths;
  final List<String> commentarySourcePaths;
  final List<String> researchSourcePaths;
  final String? commentaryIndexPath;
  final String? downloadReportsPath;
  final String? coverImagesPath;
  final String? backupPath;
  final String userDatabasePath;
  final String eLibraryDatabasePath;
  final bool eLibraryDatabaseExists;
  final int eLibraryDatabaseSizeBytes;
  final int? eLibrarySchemaVersion;
  final String eLibrarySchemaStatus;
  final String storagePolicyLabel;
  final String sourceCleanupStatus;
  final String eLibraryWriteTarget;
  final bool eLibraryMigrationNeeded;
  final String eLibraryMigrationCompletenessLabel;
  final String eLibraryMigrationStatus;
  final String? eLibraryMigrationReportPath;
  final List<String> eLibraryMigrationTableSummaries;
  final int epubCount;
  final int pdfCount;
  final int commentaryItemCount;
  final int commentaryIndexedCount;
  final int commentaryLinkCount;
  final int researchItemCount;
  final int researchIndexedCount;
  final int researchLinkCount;
  final bool pathsMatch;
  final List<String> legacyFoldersDetected;
  final String backupStatus;
  final String commentaryIndexStatus;
  final String storageSummaryStatus;
  final bool commentaryIndexReportExists;
  final Map<String, int> tableCounts;
  final Map<String, int> userELibraryTableCounts;
  final Map<String, int> eLibraryTableCounts;
  final String activeELibraryReadSource;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'root_path': rootPath,
      'root_source': rootSource,
      'root_status': rootStatus,
      'root_badge': rootBadge,
      'library_open_path': libraryOpenPath,
      'downloader_path': downloaderPath,
      'storage_summary_path': storageSummaryPath,
      'indexer_paths': indexerPaths,
      'commentary_source_paths': commentarySourcePaths,
      'research_source_paths': researchSourcePaths,
      'commentary_index_path': commentaryIndexPath,
      'download_reports_path': downloadReportsPath,
      'cover_images_path': coverImagesPath,
      'backup_path': backupPath,
      'user_database_path': userDatabasePath,
      'elibrary_database_path': eLibraryDatabasePath,
      'elibrary_database_exists': eLibraryDatabaseExists,
      'elibrary_database_size_bytes': eLibraryDatabaseSizeBytes,
      'elibrary_schema_version': eLibrarySchemaVersion,
      'elibrary_schema_status': eLibrarySchemaStatus,
      'storage_policy_label': storagePolicyLabel,
      'source_cleanup_status': sourceCleanupStatus,
      'elibrary_write_target': eLibraryWriteTarget,
      'elibrary_migration_needed': eLibraryMigrationNeeded,
      'elibrary_migration_completeness_label': eLibraryMigrationCompletenessLabel,
      'elibrary_migration_status': eLibraryMigrationStatus,
      'elibrary_migration_report_path': eLibraryMigrationReportPath,
      'elibrary_migration_table_summaries': eLibraryMigrationTableSummaries,
      'epub_count': epubCount,
      'pdf_count': pdfCount,
      'commentary_item_count': commentaryItemCount,
      'commentary_indexed_count': commentaryIndexedCount,
      'commentary_link_count': commentaryLinkCount,
      'research_item_count': researchItemCount,
      'research_indexed_count': researchIndexedCount,
      'research_link_count': researchLinkCount,
      'paths_match': pathsMatch,
      'legacy_folders_detected': legacyFoldersDetected,
      'backup_status': backupStatus,
      'commentary_index_status': commentaryIndexStatus,
      'storage_summary_status': storageSummaryStatus,
      'commentary_index_report_exists': commentaryIndexReportExists,
      'table_counts': tableCounts,
      'user_elibrary_table_counts': userELibraryTableCounts,
      'elibrary_table_counts': eLibraryTableCounts,
      'active_elibrary_read_source': activeELibraryReadSource,
    };
  }

  String toDiagnosticText() {
    final buffer = StringBuffer();
    void line(String label, Object? value) {
      buffer.writeln('$label: ${value ?? '(not set)'}');
    }

    line('Root path', rootPath);
    line('Root source', rootSource);
    line('Root status', rootStatus);
    line('Root badge', rootBadge);
    line('Library open path', libraryOpenPath);
    line('Downloader path', downloaderPath);
    line('Storage summary path', storageSummaryPath);
    line(
      'Indexer paths',
      indexerPaths.isEmpty ? null : indexerPaths.join('\n  '),
    );
    line(
      'Commentary source path',
      commentarySourcePaths.isEmpty ? null : commentarySourcePaths.join('\n  '),
    );
    line(
      'Research source path',
      researchSourcePaths.isEmpty ? null : researchSourcePaths.join('\n  '),
    );
    line('Commentary index path', commentaryIndexPath);
    line('Commentary index status', commentaryIndexStatus);
    line(
      'Commentary index report',
      commentaryIndexReportExists ? 'present' : 'missing',
    );
    line('Download reports path', downloadReportsPath);
    line('Cover images path', coverImagesPath);
    line('Backup path', backupPath);
    line('user.db path', userDatabasePath);
    line('eLibrary.db path', eLibraryDatabasePath);
    line('eLibrary.db exists', eLibraryDatabaseExists ? 'yes' : 'no');
    line('eLibrary.db size', eLibraryDatabaseSizeBytes);
    line('eLibrary schema version', eLibrarySchemaVersion);
    line('eLibrary schema status', eLibrarySchemaStatus);
    line('eLibrary active source', activeELibraryReadSource);
    line('user.db eLibrary row counts', _formatTableCounts(userELibraryTableCounts));
    line('eLibrary.db row counts', _formatTableCounts(eLibraryTableCounts));
    line('Backup status', backupStatus);
    line('eLibrary storage policy', storagePolicyLabel);
    line('eLibrary source cleanup', sourceCleanupStatus);
    line('eLibrary write target', eLibraryWriteTarget);
    line('eLibrary migration needed', eLibraryMigrationNeeded ? 'yes' : 'no');
    line('eLibrary migration status', eLibraryMigrationStatus);
    line(
      'eLibrary migration completeness',
      eLibraryMigrationCompletenessLabel,
    );
    line('eLibrary migration report', eLibraryMigrationReportPath);
    line(
      'eLibrary migration tables',
      eLibraryMigrationTableSummaries.isEmpty
          ? null
          : eLibraryMigrationTableSummaries.join('\n  '),
    );
    line('EPUB count', epubCount);
    line('PDF count', pdfCount);
    line(
      'Commentary items/indexed/links',
      '$commentaryItemCount / $commentaryIndexedCount / $commentaryLinkCount',
    );
    line(
      'Research items/indexed/links',
      '$researchItemCount / $researchIndexedCount / $researchLinkCount',
    );
    line('Paths match', pathsMatch ? 'yes' : 'no');
    line(
      'Legacy folders detected',
      legacyFoldersDetected.isEmpty
          ? 'none'
          : legacyFoldersDetected.join('\n  '),
    );
    line('Storage summary status', storageSummaryStatus);
    return buffer.toString().trimRight();
  }

  String _formatTableCounts(Map<String, int> tableCounts) {
    return tableCounts.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }
}

class StudyBibleStorageIndexReportService {
  StudyBibleStorageIndexReportService._();

  static final StudyBibleStorageIndexReportService instance =
      StudyBibleStorageIndexReportService._();

  Future<StudyBibleStorageIndexReport> build() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath = selection.path?.trim() ?? '';
    final hasRoot = rootPath.isNotEmpty && selection.exists;
    final storageSummary = await ELibraryFileManagementService.instance
        .computeDownloadedStorageSummary(
          rootPath: rootPath.isEmpty ? null : rootPath,
        );
    final storagePolicy = await LocalSettingsStore.instance
        .loadELibraryStoragePolicy();
    final migrationReport = await ELibraryDatabaseMigrationService.instance
        .buildDryRunReport();
    final db = await UserDatabase.instance.database;
    final counts = await _loadTableCounts(db);
    final userELibraryTableCounts = await _loadELibraryTableCounts(db);
    final commentaryItemStats = await _countLibraryItems(
      db: db,
      folderType: 'commentary',
    );
    final researchItemStats = await _countLibraryItems(
      db: db,
      folderType: 'research',
    );
    final commentaryLinkCount = await _countLibraryLinks(
      db: db,
      linkType: 'commentary',
    );
    final researchLinkCount = await _countLibraryLinks(
      db: db,
      linkType: 'research',
    );

    final commentarySourcePaths = rootPath.isEmpty
        ? const <String>[]
        : <String>[
            p.join(rootPath, 'ePubs', 'Commentaries'),
            p.join(rootPath, 'PDFs', 'Commentaries'),
          ];
    final researchSourcePaths = rootPath.isEmpty
        ? const <String>[]
        : <String>[
            p.join(rootPath, 'ePubs', 'Research'),
            p.join(rootPath, 'PDFs', 'Research'),
          ];
    final indexerPaths = <String>[
      ...commentarySourcePaths,
      ...researchSourcePaths,
    ];
    final commentaryIndexPath = rootPath.isEmpty
        ? null
        : p.join(rootPath, 'Index', 'commentary_index_report.json');
    final downloadReportsPath = rootPath.isEmpty
        ? null
        : p.join(rootPath, 'download_reports');
    final coverImagesPath = rootPath.isEmpty
        ? null
        : p.join(rootPath, 'Graphics', 'eLibraryCovers');
    final backupPath = await LibraryRootService.instance.backupRootPath();
    final userDatabasePath = await SandboxBootstrap.userDatabasePath();
    final eLibraryDatabaseSummary = await _loadELibraryDatabaseSummary();
    final eLibraryTableCounts = await _loadELibraryDatabaseTableCounts();
    final activeELibraryReadSource = _activeELibraryReadSource(
      userELibraryTableCounts: userELibraryTableCounts,
      eLibraryTableCounts: eLibraryTableCounts,
    );
    final legacyFoldersDetected = await _detectLegacyFolders(rootPath);
    final commentaryIndexReportExists =
        commentaryIndexPath != null && await File(commentaryIndexPath).exists();
    final pathsMatch =
        hasRoot &&
        _allDerivedPathsShareRoot(
          rootPath: rootPath,
          paths: <String?>[
            selection.path,
            commentaryIndexPath,
            downloadReportsPath,
            coverImagesPath,
            backupPath,
          ],
        );

    final storageSummaryStatus = hasRoot
        ? 'Scan complete'
        : 'No usable root selected';
    final commentaryIndexStatus = _commentaryIndexStatus(
      hasRoot: hasRoot,
      itemCount: commentaryItemStats.itemCount,
      indexedCount: commentaryItemStats.indexedCount,
      linkCount: commentaryLinkCount,
    );
    final backupStatus = hasRoot
        ? 'Available at $backupPath'
        : 'Using support-folder fallback until a root is confirmed';

    return StudyBibleStorageIndexReport(
      rootPath: selection.path?.trim(),
      rootSource: selection.sourceLabel,
      rootStatus: selection.statusLabel,
      rootBadge: selection.badgeLabel,
      libraryOpenPath: selection.path?.trim(),
      downloaderPath: selection.path?.trim(),
      storageSummaryPath: selection.path?.trim(),
      indexerPaths: indexerPaths,
      commentarySourcePaths: commentarySourcePaths,
      researchSourcePaths: researchSourcePaths,
      commentaryIndexPath: commentaryIndexPath,
      downloadReportsPath: downloadReportsPath,
      coverImagesPath: coverImagesPath,
      backupPath: backupPath,
      userDatabasePath: userDatabasePath,
      eLibraryDatabasePath: eLibraryDatabaseSummary.path,
      eLibraryDatabaseExists: eLibraryDatabaseSummary.exists,
      eLibraryDatabaseSizeBytes: eLibraryDatabaseSummary.sizeBytes,
      eLibrarySchemaVersion: eLibraryDatabaseSummary.schemaVersion,
      eLibrarySchemaStatus: eLibraryDatabaseSummary.schemaStatus,
      storagePolicyLabel: storagePolicy.label,
      sourceCleanupStatus: 'Deferred until verified import-to-db is wired.',
      eLibraryWriteTarget: 'eLibrary.db',
      eLibraryMigrationNeeded: migrationReport.migrationNeeded,
      eLibraryMigrationCompletenessLabel: migrationReport.completenessLabel,
      eLibraryMigrationStatus: migrationReport.schemaCompatible
          ? (migrationReport.migrationNeeded
              ? 'Legacy eLibrary rows pending copy.'
              : 'Legacy eLibrary rows already copied.')
          : 'Schema mismatch blocks copy.',
      eLibraryMigrationReportPath: migrationReport.reportFilePath,
      eLibraryMigrationTableSummaries: migrationReport.tableReports
          .map((report) => report.toDiagnosticText())
          .toList(growable: false),
      epubCount: storageSummary.epubCount,
      pdfCount: storageSummary.pdfCount,
      commentaryItemCount: commentaryItemStats.itemCount,
      commentaryIndexedCount: commentaryItemStats.indexedCount,
      commentaryLinkCount: commentaryLinkCount,
      researchItemCount: researchItemStats.itemCount,
      researchIndexedCount: researchItemStats.indexedCount,
      researchLinkCount: researchLinkCount,
      pathsMatch: pathsMatch,
      legacyFoldersDetected: legacyFoldersDetected,
      backupStatus: backupStatus,
      commentaryIndexStatus: commentaryIndexStatus,
      storageSummaryStatus: storageSummaryStatus,
      commentaryIndexReportExists: commentaryIndexReportExists,
      tableCounts: counts,
      userELibraryTableCounts: userELibraryTableCounts,
      eLibraryTableCounts: eLibraryTableCounts,
      activeELibraryReadSource: activeELibraryReadSource,
    );
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
        'SELECT COUNT(*) AS cnt FROM "${table.replaceAll('"', '""')}"',
      );
      counts[table] = countRows.isEmpty
          ? 0
          : (countRows.first['cnt'] as num?)?.toInt() ?? 0;
    }
    return counts;
  }

  Future<Map<String, int>> _loadELibraryTableCounts(Database db) async {
    return <String, int>{
      'library_items': await ELibraryReadResolver.instance.tableRowCount(
        db,
        'library_items',
      ),
      'library_links': await ELibraryReadResolver.instance.tableRowCount(
        db,
        'library_links',
      ),
      'library_navigation_items':
          await ELibraryReadResolver.instance.tableRowCount(
            db,
            'library_navigation_items',
          ),
      'library_text_blocks': await ELibraryReadResolver.instance.tableRowCount(
        db,
        'library_text_blocks',
      ),
      'elibrary_ref_index': await ELibraryReadResolver.instance.tableRowCount(
        db,
        'elibrary_ref_index',
      ),
      'elibrary_markups': await ELibraryReadResolver.instance.tableRowCount(
        db,
        'elibrary_markups',
      ),
      'elibrary_install_estimates':
          await ELibraryReadResolver.instance.tableRowCount(
            db,
            'elibrary_install_estimates',
          ),
    };
  }

  Future<Map<String, int>> _loadELibraryDatabaseTableCounts() async {
    final path = await SandboxBootstrap.eLibraryDatabasePath();
    final file = File(path);
    if (!await file.exists() || await file.length() == 0) {
      return _emptyELibraryTableCounts();
    }

    try {
      final db = await openDatabase(path, singleInstance: false);
      try {
        return await _loadELibraryTableCounts(db);
      } finally {
        await db.close();
      }
    } catch (_) {
      return _emptyELibraryTableCounts();
    }
  }

  Map<String, int> _emptyELibraryTableCounts() {
    return <String, int>{
      'library_items': 0,
      'library_links': 0,
      'library_navigation_items': 0,
      'library_text_blocks': 0,
      'elibrary_ref_index': 0,
      'elibrary_markups': 0,
      'elibrary_install_estimates': 0,
    };
  }

  String _activeELibraryReadSource({
    required Map<String, int> userELibraryTableCounts,
    required Map<String, int> eLibraryTableCounts,
  }) {
    final userTotal = userELibraryTableCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    final eLibraryTotal = eLibraryTableCounts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    if (userTotal == 0 && eLibraryTotal == 0) {
      return 'empty';
    }
    if (userTotal > 0 && eLibraryTotal > 0) {
      return 'mixed';
    }
    if (eLibraryTotal > 0) {
      return 'eLibrary.db';
    }
    return 'user.db fallback';
  }

  Future<_ELibraryDatabaseSummary> _loadELibraryDatabaseSummary() async {
    final path = await SandboxBootstrap.eLibraryDatabasePath();
    final file = File(path);
    final exists = await file.exists();
    final sizeBytes = exists ? await file.length() : 0;

    if (!exists) {
      return _ELibraryDatabaseSummary(
        path: path,
        exists: false,
        sizeBytes: 0,
        schemaVersion: null,
        schemaStatus: 'missing',
      );
    }

    if (sizeBytes == 0) {
      return _ELibraryDatabaseSummary(
        path: path,
        exists: true,
        sizeBytes: 0,
        schemaVersion: null,
        schemaStatus: 'empty',
      );
    }

    try {
      final db = await openDatabase(path, singleInstance: false);
      try {
        return _ELibraryDatabaseSummary(
          path: path,
          exists: true,
          sizeBytes: sizeBytes,
          schemaVersion: await ELibrarySchema.currentAppliedVersion(db),
          schemaStatus: await ELibrarySchema.schemaStatus(db),
        );
      } finally {
        await db.close();
      }
    } catch (error) {
      return _ELibraryDatabaseSummary(
        path: path,
        exists: true,
        sizeBytes: sizeBytes,
        schemaVersion: null,
        schemaStatus: 'unreadable: $error',
      );
    }
  }

  Future<({int itemCount, int indexedCount})> _countLibraryItems({
    required Database db,
    required String folderType,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS item_count,
        SUM(
          CASE
            WHEN LOWER(COALESCE(index_status, '')) IN ('indexed', 'indexed_empty')
            THEN 1 ELSE 0
          END
        ) AS indexed_count
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(folder_type, '')) = ?
        AND LOWER(COALESCE(file_format, '')) IN ('epub', 'pdf')
      ''',
      [folderType],
    );
    if (rows.isEmpty) {
      return (itemCount: 0, indexedCount: 0);
    }
    return (
      itemCount: (rows.first['item_count'] as num?)?.toInt() ?? 0,
      indexedCount: (rows.first['indexed_count'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int> _countLibraryLinks({
    required Database db,
    required String linkType,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM library_links ll
      INNER JOIN library_items li ON li.id = ll.library_item_id
      WHERE ll.link_type = ?
        AND li.deleted_at IS NULL
      ''',
      [linkType],
    );
    return (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<List<String>> _detectLegacyFolders(String rootPath) async {
    if (rootPath.trim().isEmpty) return const <String>[];
    final candidates = <String>[
      p.join(rootPath, 'Biblical Heritage'),
      p.join(rootPath, 'Biblical Heritage Test'),
      p.join(rootPath, 'Biblical Heritage Library'),
      p.join(rootPath, 'BiblicalHeritage', 'v2'),
      p.join(rootPath, '#StudyBible', 'research_library'),
      p.join(rootPath, 'eLibrary'),
      p.join(rootPath, 'eLibrary_Downloads'),
      p.join(rootPath, 'TEST_Downloads'),
    ];
    final detected = <String>[];
    for (final candidate in candidates) {
      if (await Directory(candidate).exists()) {
        detected.add(candidate);
      }
    }
    return detected;
  }

  bool _allDerivedPathsShareRoot({
    required String rootPath,
    required List<String?> paths,
  }) {
    final normalizedRoot = p.normalize(rootPath.trim());
    for (final path in paths) {
      final value = path?.trim() ?? '';
      if (value.isEmpty) continue;
      final normalized = p.normalize(value);
      if (!p.isWithin(normalizedRoot, normalized) &&
          normalized != normalizedRoot) {
        return false;
      }
    }
    return true;
  }

  String _commentaryIndexStatus({
    required bool hasRoot,
    required int itemCount,
    required int indexedCount,
    required int linkCount,
  }) {
    if (!hasRoot) {
      return 'Commentary library not found. Open eLibrary Setup.';
    }
    if (itemCount == 0) {
      return 'Commentary library not found. Open eLibrary Setup.';
    }
    if (indexedCount == 0 || linkCount == 0) {
      return 'Commentary index needed. Index now.';
    }
    return 'Commentary index ready.';
  }
}

class _ELibraryDatabaseSummary {
  const _ELibraryDatabaseSummary({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    required this.schemaVersion,
    required this.schemaStatus,
  });

  final String path;
  final bool exists;
  final int sizeBytes;
  final int? schemaVersion;
  final String schemaStatus;
}
