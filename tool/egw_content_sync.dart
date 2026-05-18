import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String _defaultRootPath =
    '/Users/deanbowen/Library/Containers/com.example.studybible2/Data/Documents/BiblicalHeritage/v2';
const String _defaultDbPath =
    '/Users/deanbowen/Library/Containers/com.example.studybible2/Data/Documents/BiblicalHeritage/v2/user.db';
const String _manifestPath = 'tool/egw_content_manifest.json';
const String _egwEnglishRootUrl = 'https://egwwritings.org/allCollection/en';
const String _egwEnglishTextRootUrl =
    'https://text.egwwritings.org/allCollection/en';
const Set<String> _allowedEgwHosts = <String>{
  'egwwritings.org',
  'text.egwwritings.org',
  'next.egwwritings.org',
  'media2.egwwritings.org',
};
const Set<String> _siblingShelfLabels = <String>{
  'Books',
  'Devotionals',
  'Letters & Manuscripts',
  'Letters and Manuscripts',
  'Manuscript Releases',
  'Misc Collections',
  'Pamphlets',
  'Periodicals',
  'Biography',
  'Modern English',
  'The Conflict',
};
const Duration _egwHttpConnectTimeout = Duration(seconds: 20);
const Duration _egwHttpResponseTimeout = Duration(seconds: 30);
const Duration _egwHttpDownloadTimeout = Duration(seconds: 120);
const int _egwDebugLinkSampleLimit = 50;
const List<String> _defaultLegacyScanPaths = <String>[
  '/Users/deanbowen/Development/StudyBible2',
  '/Users/deanbowen/Development/eLibrary',
  '/Users/deanbowen/Development/bible_app_mac',
];

final Map<String, List<_MrVolumeSpec>> _mrVolumeSpecs = {
  'EGW_Manuscript_Releases': const [
    _MrVolumeSpec(1, 19, 96),
    _MrVolumeSpec(2, 97, 161),
    _MrVolumeSpec(3, 162, 209),
    _MrVolumeSpec(4, 210, 259),
    _MrVolumeSpec(5, 260, 346),
    _MrVolumeSpec(6, 347, 418),
    _MrVolumeSpec(7, 419, 525),
    _MrVolumeSpec(8, 526, 663),
    _MrVolumeSpec(9, 664, 770),
    _MrVolumeSpec(10, 771, 850),
    _MrVolumeSpec(11, 851, 920),
    _MrVolumeSpec(12, 921, 999),
    _MrVolumeSpec(13, 1000, 1080),
    _MrVolumeSpec(14, 1081, 1135),
    _MrVolumeSpec(15, 1136, 1185),
    _MrVolumeSpec(16, 1186, 1235),
    _MrVolumeSpec(17, 1236, 1300),
    _MrVolumeSpec(18, 1301, 1359),
    _MrVolumeSpec(19, 1360, 1419),
    _MrVolumeSpec(20, 1420, 1500),
    _MrVolumeSpec(21, 1501, 1598),
  ],
};

final Map<String, List<_LtMsVolumeSpec>> _ltMsVolumeSpecs = {
  'EGW_Letters_Manuscripts': const [
    _LtMsVolumeSpec(1, 1844, 1868),
    _LtMsVolumeSpec(2, 1869, 1875),
    _LtMsVolumeSpec(3, 1876, 1882),
    _LtMsVolumeSpec(4, 1883, 1886),
    _LtMsVolumeSpec(5, 1887, 1888),
    _LtMsVolumeSpec(6, 1889, 1890),
    _LtMsVolumeSpec(7, 1891, 1892),
    _LtMsVolumeSpec(8, 1893, 1893),
    _LtMsVolumeSpec(9, 1894, 1894),
    _LtMsVolumeSpec(10, 1895, 1895),
    _LtMsVolumeSpec(11, 1896, 1896),
    _LtMsVolumeSpec(12, 1897, 1897),
    _LtMsVolumeSpec(13, 1898, 1898),
    _LtMsVolumeSpec(14, 1899, 1899),
    _LtMsVolumeSpec(15, 1900, 1900),
    _LtMsVolumeSpec(16, 1901, 1901),
    _LtMsVolumeSpec(17, 1902, 1902),
    _LtMsVolumeSpec(18, 1903, 1903),
    _LtMsVolumeSpec(19, 1904, 1904),
    _LtMsVolumeSpec(20, 1905, 1905),
    _LtMsVolumeSpec(21, 1906, 1906),
    _LtMsVolumeSpec(22, 1907, 1907),
    _LtMsVolumeSpec(23, 1908, 1908),
    _LtMsVolumeSpec(24, 1909, 1909),
    _LtMsVolumeSpec(25, 1910, 1915),
  ],
};

const Set<String> _commentariesNeedsReviewCodes = <String>{
  '1SDABC',
  '2SDABC',
  '3SDABC',
  '4SDABC',
  '5SDABC',
  '6SDABC',
  '7SDABC',
  'SDASB',
  'ABC',
  'HSDAT',
  'MHBC',
  'MHBCC',
  'KJRSBM',
};

const Map<String, String> _categoryFolderAliases = <String, String>{
  'Books': 'EGW_Books',
  'Devotionals': 'EGW_Devotionals',
  'Letters & Manuscripts': 'EGW_Letters_Manuscripts',
  'Letters and Manuscripts': 'EGW_Letters_Manuscripts',
  'Manuscript Releases': 'EGW_Manuscript_Releases',
  'Misc Collections': 'EGW_Misc_Collections',
  'Pamphlets': 'EGW_Pamphlets',
  'Periodicals': 'EGW_Periodicals',
  'Modern English': 'EGW_Modern_English',
  'The Conflict': 'EGW_Conflict',
  'Commentaries': 'EGW_Commentaries',
};

Future<void> main(List<String> args) async {
  stdout.writeln('[egw-sync] entered main()');
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final parsed = _parseArgs(args);
  final progress = _AuditProgressLogger();
  progress.log(
    'argument parse complete '
    '(audit=${parsed.audit}, apply=${parsed.apply}, '
    'noRemote=${parsed.noRemote}, maxPages=${parsed.maxPages?.toString() ?? "unbounded"}, '
    'debugLinks=${parsed.debugLinks}, shelfUrl=${parsed.shelfUrl ?? "none"})',
  );
  if (parsed.showHelp) {
    stdout.writeln(_usage());
    return;
  }

  if (parsed.apply) {
    final tool = _EgwContentSyncTool(
      rootPath: parsed.rootPath,
      dbPath: parsed.dbPath,
      manifestPath: parsed.manifestPath,
      scanRoots: _defaultAuditScanRoots(parsed.rootPath),
      allowRemoteDiscovery: !parsed.noRemote,
      maxPages: parsed.maxPages,
      debugLinks: parsed.debugLinks,
      shelfUrl: parsed.shelfUrl,
    );
    final report = await tool.apply(
      limit: parsed.limit,
      category: parsed.category,
      dryRun: parsed.dryRun,
    );
    stdout.writeln('');
    stdout.writeln('EGW content sync apply completed.');
    stdout.writeln('Report: ${report.reportFilePath}');
    stdout.writeln('Audit report used: ${report.auditReportPath}');
    stdout.writeln('Managed root: ${report.rootPath}');
    stdout.writeln('Indexing deferred: ${report.summary.indexingDeferred}');
    stdout.writeln('Copied count: ${report.summary.copiedCount}');
    stdout.writeln('Downloaded count: ${report.summary.downloadedCount}');
    stdout.writeln(
      'Skipped existing count: ${report.summary.skippedExistingCount}',
    );
    stdout.writeln(
      'Skipped duplicate count: ${report.summary.skippedDuplicateCount}',
    );
    stdout.writeln('Needs review count: ${report.summary.needsReviewCount}');
    stdout.writeln(
      'Excluded from apply count: ${report.summary.excludedFromApplyCount}',
    );
    stdout.writeln('Failed count: ${report.summary.failedCount}');
    stdout.writeln('Conflict count: ${report.summary.conflictCount}');
    if (report.summary.dryRunCount > 0) {
      stdout.writeln('Dry-run count: ${report.summary.dryRunCount}');
    }
    stdout.writeln('Total tasks: ${report.summary.totalTasks}');
    if (report.summary.refusedDueToConflicts) {
      stdout.writeln('Apply was refused because real conflicts were detected.');
    }
    if (report.warnings.isNotEmpty) {
      stdout.writeln('Warnings:');
      for (final warning in report.warnings) {
        stdout.writeln('  - $warning');
      }
    }
    return;
  }

  if (!parsed.audit) {
    stdout.writeln(_usage());
    return;
  }

  final tool = _EgwContentSyncTool(
    rootPath: parsed.rootPath,
    dbPath: parsed.dbPath,
    manifestPath: parsed.manifestPath,
    scanRoots: _defaultAuditScanRoots(parsed.rootPath),
    allowRemoteDiscovery: !parsed.noRemote,
    maxPages: parsed.maxPages,
    debugLinks: parsed.debugLinks,
    shelfUrl: parsed.shelfUrl,
  );
  final report = await tool.audit(progress: progress);
  stdout.writeln('');
  stdout.writeln('EGW content audit completed.');
  stdout.writeln('Report: ${report.reportFilePath}');
  stdout.writeln('Managed root: ${report.rootPath}');
  stdout.writeln('English crawl root: ${report.summary.crawlRootUrl}');
  stdout.writeln('Shelf title: ${report.summary.shelfTitle}');
  stdout.writeln(
    'Direct /book/ links found on shelf page: ${report.summary.directBookLinksFound}',
  );
  stdout.writeln(
    'Child collections detected: ${report.summary.childCollectionDetectedCount}',
  );
  stdout.writeln(
    'Branch/category pages visited: ${report.summary.branchCategoryPagesVisited}',
  );
  stdout.writeln(
    'Final item pages visited: ${report.summary.finalItemPagesVisited}',
  );
  stdout.writeln(
    'Categories discovered: ${report.summary.discoveredCategoryCount}',
  );
  stdout.writeln('Verified EPUB count: ${report.summary.verifiedEpubCount}');
  stdout.writeln('Verified PDF count: ${report.summary.verifiedPdfCount}');
  stdout.writeln(
    'Verified English EPUB count: ${report.summary.verifiedEnglishEpubCount}',
  );
  stdout.writeln(
    'Verified English PDF count: ${report.summary.verifiedEnglishPdfCount}',
  );
  stdout.writeln(
    'Non-English files excluded: ${report.summary.nonEnglishExcludedCount}',
  );
  stdout.writeln(
    'Verified EPUB+PDF count: ${report.summary.verifiedEpubPdfCount}',
  );
  stdout.writeln(
    'Verified PDF-only count: ${report.summary.verifiedPdfOnlyCount}',
  );
  stdout.writeln('No EPUB found: ${report.summary.noEpubFoundCount}');
  stdout.writeln(
    'No download links found: ${report.summary.noDownloadLinksFoundCount}',
  );
  stdout.writeln('Page unavailable: ${report.summary.pageUnavailableCount}');
  stdout.writeln(
    'Discovered categories: ${report.summary.discoveredCategories.join(', ')}',
  );
  stdout.writeln('Manifest items: ${report.summary.manifestItems}');
  stdout.writeln('Present items: ${report.summary.presentItems}');
  stdout.writeln('Available to copy: ${report.summary.availableToCopyItems}');
  stdout.writeln('True missing items: ${report.summary.trueMissingItems}');
  stdout.writeln('Duplicate files: ${report.summary.duplicateFiles}');
  stdout.writeln('Conflicts: ${report.summary.conflicts}');
  stdout.writeln(
    'Unmatched local files: ${report.summary.unmatchedLocalFileCount}',
  );
  stdout.writeln('Indexed files: ${report.summary.indexedFiles}');
  stdout.writeln('Scan roots:');
  for (final root in report.scannedRoots) {
    stdout.writeln(
      '  - ${root.label}: ${root.path} '
      '(kind=${root.kind}, exists=${root.exists}, egwFiles=${root.egwFiles}, '
      'totalFiles=${root.totalFiles})',
    );
  }
  stdout.writeln('True missing items: ${report.summary.trueMissingItems}');
  stdout.writeln('Present in managed target: ${report.summary.presentItems}');
  stdout.writeln(
    'Present legacy locations: ${report.summary.presentLegacyLocationItems}',
  );
  stdout.writeln('Available to copy: ${report.summary.availableToCopyItems}');
  stdout.writeln('Needs review items: ${report.summary.needsReviewItems}');
  stdout.writeln(
    'Excluded from apply: ${report.summary.excludedFromApplyItems}',
  );
  stdout.writeln(
    'Duplicate same-hash groups: ${report.summary.duplicateSameHashCount}',
  );
  stdout.writeln(
    'Duplicate same-code/location groups: ${report.summary.duplicateSameCodeDifferentLocationCount}',
  );
  stdout.writeln(
    'Conflict same-code/different-hash groups: ${report.summary.conflictSameCodeDifferentHashCount}',
  );
  stdout.writeln(
    'Conflict target-exists/different-hash groups: ${report.summary.conflictTargetExistsDifferentHashCount}',
  );
  stdout.writeln(
    'Unmatched local files: ${report.summary.unmatchedLocalFileCount}',
  );
  if (report.warnings.isNotEmpty) {
    stdout.writeln('Warnings:');
    for (final warning in report.warnings) {
      stdout.writeln('  - $warning');
    }
  }
  for (final entry in report.categorySummaries.values) {
    stdout.writeln(
      '${entry.category}: manifest=${entry.manifestItems} '
      'present=${entry.presentItems} legacy=${entry.presentLegacyLocationItems} '
      'needs_review=${entry.needsReviewItems} '
      'excluded=${entry.excludedFromApplyItems} '
      'missing=${entry.missingItems} '
      'localFiles=${entry.localFiles} indexed=${entry.indexedFiles}',
    );
  }
}

class _EgwContentSyncTool {
  _EgwContentSyncTool({
    required this.rootPath,
    required this.dbPath,
    required this.manifestPath,
    required this.scanRoots,
    required this.allowRemoteDiscovery,
    required this.maxPages,
    required this.debugLinks,
    required this.shelfUrl,
  });

  final String rootPath;
  final String dbPath;
  final String manifestPath;
  final List<_ScanRootSpec> scanRoots;
  final bool allowRemoteDiscovery;
  final int? maxPages;
  final bool debugLinks;
  final String? shelfUrl;

  Future<_EgwAuditReport> audit({_AuditProgressLogger? progress}) async {
    final normalizedRoot = p.normalize(rootPath.trim());
    progress?.log('root discovery start');
    progress?.log(
      'root discovery end '
      '(managedRoot=$normalizedRoot, dbPath=$dbPath, scanRoots=${scanRoots.length})',
    );
    progress?.log('manifest load/build start');
    final manifestConfig = await _loadManifestConfig();
    progress?.log(
      'manifest load/build end '
      '(collections=${manifestConfig.collections.length})',
    );
    final warnings = <String>[];
    if (debugLinks) {
      warnings.add(
        'Debug link mode enabled; logging raw HTML summaries for known discovery pages.',
      );
      await _logDiscoveryPageDiagnostics(progress: progress);
    }
    final discovery = allowRemoteDiscovery
        ? await _discoverEnglishTreeItems(
            maxPages: maxPages,
            shelfUrl: shelfUrl,
            progress: progress,
          )
        : _EnglishTreeDiscovery(
            rootUrl: _egwEnglishRootUrl,
            shelfTitle: '',
            directBookLinksFound: 0,
            childCollectionsDetected: const <_ChildCollectionRecord>[],
            branchCategoryPagesVisited: 0,
            finalItemPagesVisited: 0,
            pageUnavailableCount: 0,
            discoveredCategories: <String>{},
            items: const <_EgwManifestItem>[],
            warnings: const <String>[
              'Remote discovery disabled by --no-remote; audit ran local-only.',
            ],
          );
    if (!allowRemoteDiscovery) {
      progress?.log('remote discovery skipped (--no-remote)');
    }
    final manifestItems = discovery.items;
    warnings.addAll(discovery.warnings);
    if (manifestConfig.collections.isEmpty) {
      warnings.add(
        'Manifest config had no collections; built-in defaults were used.',
      );
    }

    progress?.log('local scan start');
    final dbRows = await _readDbRows();
    final manifestIndex = _ManifestIndex.fromItems(manifestItems);
    final scanResult = await _scanLocalFiles(
      scanRoots,
      dbRows,
      manifestIndex,
      progress: progress,
    );
    progress?.log(
      'local scan end (files=${scanResult.localFiles.length}, roots=${scanResult.scannedRoots.length})',
    );
    final localFiles = scanResult.localFiles;
    final findings = _analyzeLocalFindings(localFiles, manifestIndex);
    final itemAudits = _compareManifestToLocal(manifestItems, localFiles);
    final categorySummaries = _summarizeCategories(
      manifestConfig.collections,
      manifestItems,
      localFiles,
      itemAudits,
    );

    final now = DateTime.now().toUtc();
    final reportRoot = Directory(p.join(normalizedRoot, 'download_reports'));
    await reportRoot.create(recursive: true);
    final reportFilePath = p.join(
      reportRoot.path,
      'egw_content_audit_${_timestamp(now)}.json',
    );
    progress?.log('report write start: $reportFilePath');

    final report = _EgwAuditReport(
      generatedAt: now,
      rootPath: normalizedRoot,
      dbPath: dbPath,
      manifestPath: manifestPath,
      scannedRoots: scanResult.scannedRoots,
      summary: _EgwAuditSummary(
        crawlRootUrl: discovery.rootUrl,
        shelfTitle: discovery.shelfTitle,
        directBookLinksFound: discovery.directBookLinksFound,
        childCollectionDetectedCount: discovery.childCollectionsDetected.length,
        childCollectionsDetected: discovery.childCollectionsDetected,
        branchCategoryPagesVisited: discovery.branchCategoryPagesVisited,
        finalItemPagesVisited: discovery.finalItemPagesVisited,
        discoveredCategoryCount: discovery.discoveredCategories.length,
        discoveredCategories: discovery.discoveredCategories.toList(
          growable: false,
        ),
        verifiedEpubCount: manifestItems
            .where((item) => item.verifiedEpubUrl.isNotEmpty)
            .length,
        verifiedPdfCount: manifestItems
            .where((item) => item.verifiedPdfUrl.isNotEmpty)
            .length,
        verifiedEnglishEpubCount: manifestItems
            .where((item) => _isEnglishDownloadUrl(item.verifiedEpubUrl))
            .length,
        verifiedEnglishPdfCount: manifestItems
            .where((item) => _isEnglishDownloadUrl(item.verifiedPdfUrl))
            .length,
        verifiedEpubPdfCount: manifestItems
            .where(
              (item) =>
                  item.verifiedEpubUrl.isNotEmpty &&
                  item.verifiedPdfUrl.isNotEmpty,
            )
            .length,
        verifiedPdfOnlyCount: manifestItems
            .where(
              (item) =>
                  item.verifiedEpubUrl.isEmpty &&
                  item.verifiedPdfUrl.isNotEmpty,
            )
            .length,
        nonEnglishExcludedCount: manifestItems
            .where(
              (item) =>
                  (item.verifiedEpubUrl.isNotEmpty ||
                      item.verifiedPdfUrl.isNotEmpty) &&
                  !_isEnglishDownloadUrl(item.verifiedEpubUrl) &&
                  !_isEnglishDownloadUrl(item.verifiedPdfUrl),
            )
            .length,
        noEpubFoundCount: manifestItems
            .where((item) => item.discoveryStatus == 'no_epub_found')
            .length,
        noDownloadLinksFoundCount: manifestItems
            .where((item) => item.discoveryStatus == 'no_download_links_found')
            .length,
        pageUnavailableCount: manifestItems
            .where((item) => item.discoveryStatus == 'page_unavailable')
            .length,
        manifestItems: manifestItems.length,
        localFiles: localFiles.length,
        presentItems: itemAudits.where((item) => item.present).length,
        presentLegacyLocationItems: itemAudits
            .where((item) => item.presentLegacyLocation)
            .length,
        availableToCopyItems: itemAudits
            .where((item) => item.availableToCopy)
            .length,
        needsReviewItems: itemAudits
            .where((item) => item.auditStatus == 'needs_review')
            .length,
        excludedFromApplyItems: itemAudits
            .where((item) => !item.applyEligible)
            .length,
        trueMissingItems: itemAudits
            .where(
              (item) =>
                  !item.present &&
                  !item.presentLegacyLocation &&
                  item.applyEligible,
            )
            .length,
        duplicateSameHashCount: findings.duplicateSameHashGroups.length,
        duplicateSameCodeDifferentLocationCount:
            findings.duplicateSameCodeDifferentLocationGroups.length,
        conflictSameCodeDifferentHashCount:
            findings.conflictSameCodeDifferentHashGroups.length,
        conflictTargetExistsDifferentHashCount:
            findings.conflictTargetExistsDifferentHashGroups.length,
        unmatchedLocalFileCount: findings.unmatchedLocalFiles.length,
        indexedFiles: localFiles.where((file) => file.indexed).length,
      ),
      categorySummaries: categorySummaries,
      localFiles: localFiles,
      manifestItems: manifestItems,
      itemAudits: itemAudits,
      duplicateSameHashGroups: findings.duplicateSameHashGroups,
      duplicateSameCodeDifferentLocationGroups:
          findings.duplicateSameCodeDifferentLocationGroups,
      conflictSameCodeDifferentHashGroups:
          findings.conflictSameCodeDifferentHashGroups,
      conflictTargetExistsDifferentHashGroups:
          findings.conflictTargetExistsDifferentHashGroups,
      unmatchedLocalFiles: findings.unmatchedLocalFiles,
      warnings: warnings,
      reportFilePath: reportFilePath,
    );

    await File(reportFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );
    progress?.log('report write end');
    return report;
  }

  Future<void> _logDiscoveryPageDiagnostics({
    _AuditProgressLogger? progress,
  }) async {
    final client = HttpClient()
      ..userAgent = 'StudyBible2 EGW Content Debug'
      ..connectionTimeout = _egwHttpConnectTimeout;
    client.autoUncompress = true;
    final urls = <String>[
      'https://egwwritings.org/allCollection/en',
      'https://text.egwwritings.org/allCollection/en',
      'https://egwwritings.org/allCollection/en/8',
      'https://egwwritings.org/allCollection/en/10',
      'https://egwwritings.org/allCollection/en/5',
      'https://text.egwwritings.org/allCollection/en/8',
      'https://text.egwwritings.org/allCollection/en/10',
      'https://text.egwwritings.org/allCollection/en/5',
      'https://text.egwwritings.org/book/b127',
      'https://text.egwwritings.org/book/b128',
      'https://text.egwwritings.org/book/b6',
    ];
    try {
      for (final url in urls) {
        final summary = await _fetchPageSummary(client, url);
        progress?.log(
          'debug url=$url status=${summary.statusCode} '
          'finalUrl=${summary.finalUrl} '
          'contentType=${summary.contentType ?? "unknown"} '
          'length=${summary.bodyLength} '
          'hrefs=${summary.hrefs.length}',
        );
        progress?.log('debug preview=$url :: ${summary.preview}');
        progress?.log(
          'debug href sample=$url :: ${summary.hrefs.take(_egwDebugLinkSampleLimit).join(' | ')}',
        );
        progress?.log(
          'debug discovery sample=$url :: ${summary.discoveryUrls.take(_egwDebugLinkSampleLimit).join(' | ')}',
        );
        progress?.log(
          'debug counts=$url :: '
          '/allCollection/=${summary.patternCounts['/allCollection/']} '
          '/book/=${summary.patternCounts['/book/']} '
          '/publicationtoc.php=${summary.patternCounts['/publicationtoc.php']} '
          '/folders/=${summary.patternCounts['/folders/']} '
          '/epub/=${summary.patternCounts['/epub/']} '
          '/pdf/=${summary.patternCounts['/pdf/']} '
          '.epub=${summary.patternCounts['.epub']} '
          '.pdf=${summary.patternCounts['.pdf']}',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<_EgwApplyReport> apply({
    int? limit,
    String? category,
    bool dryRun = false,
  }) async {
    final auditReport = await audit();
    final now = DateTime.now().toUtc();
    final reportRoot = Directory(
      p.join(auditReport.rootPath, 'download_reports'),
    );
    await reportRoot.create(recursive: true);
    final reportFilePath = p.join(
      reportRoot.path,
      'egw_content_sync_${_timestamp(now)}.json',
    );

    final warnings = <String>[...auditReport.warnings];
    final summary = _EgwApplySummary(
      indexingDeferred: true,
      refusedDueToConflicts:
          auditReport.summary.conflictSameCodeDifferentHashCount > 0 ||
          auditReport.summary.conflictTargetExistsDifferentHashCount > 0,
      needsReviewCount: auditReport.summary.needsReviewItems,
      excludedFromApplyCount: auditReport.summary.excludedFromApplyItems,
    );

    if (summary.refusedDueToConflicts) {
      warnings.add(
        'Apply refused because audit reported real conflicts. Resolve them before retrying.',
      );
      final report = _EgwApplyReport(
        generatedAt: now,
        rootPath: auditReport.rootPath,
        dbPath: auditReport.dbPath,
        manifestPath: auditReport.manifestPath,
        auditReportPath: auditReport.reportFilePath,
        scannedRoots: auditReport.scannedRoots,
        summary: summary,
        actions: const <_EgwSyncAction>[],
        warnings: warnings,
        reportFilePath: reportFilePath,
      );
      await File(reportFilePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report.toJson()),
        flush: true,
      );
      return report;
    }

    final taskPool = _buildApplyTasks(
      auditReport: auditReport,
      categoryFilter: category?.trim(),
    );
    final actionableTasks = taskPool
        .where((task) => task.managedTarget == null)
        .toList(growable: false);
    final selectedTasks = limit == null
        ? actionableTasks
        : actionableTasks
              .take(limit.clamp(0, actionableTasks.length).toInt())
              .toList(growable: false);

    final actions = <_EgwSyncAction>[];
    final httpClient = HttpClient()
      ..userAgent = 'StudyBible2 EGW Content Sync'
      ..connectionTimeout = _egwHttpConnectTimeout;
    httpClient.autoUncompress = true;
    try {
      for (final task in selectedTasks) {
        final action = await _executeApplyTask(
          task: task,
          auditReport: auditReport,
          httpClient: httpClient,
          dryRun: dryRun,
        );
        actions.add(action);
        if (action.status == 'conflict') {
          summary.conflictCount += 1;
        } else if (action.status == 'copied') {
          summary.copiedCount += 1;
        } else if (action.status == 'downloaded') {
          summary.downloadedCount += 1;
        } else if (action.status == 'skipped_existing') {
          summary.skippedExistingCount += 1;
        } else if (action.status == 'skipped_duplicate') {
          summary.skippedDuplicateCount += 1;
        } else if (action.status == 'failed') {
          summary.failedCount += 1;
        } else if (action.status == 'needs_review') {
          summary.needsReviewCount += 1;
        } else if (action.status.startsWith('dry_run')) {
          summary.dryRunCount += 1;
        }
        summary.skippedDuplicateCount += action.duplicateSourcesIgnored;
      }
    } finally {
      httpClient.close(force: true);
    }

    summary.totalTasks = selectedTasks.length;
    final report = _EgwApplyReport(
      generatedAt: now,
      rootPath: auditReport.rootPath,
      dbPath: auditReport.dbPath,
      manifestPath: auditReport.manifestPath,
      auditReportPath: auditReport.reportFilePath,
      scannedRoots: auditReport.scannedRoots,
      summary: summary,
      actions: actions,
      warnings: warnings,
      reportFilePath: reportFilePath,
    );

    await File(reportFilePath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
      flush: true,
    );
    return report;
  }

  Future<_ManifestConfig> _loadManifestConfig() async {
    final file = File(manifestPath);
    if (!await file.exists()) {
      return _ManifestConfig.defaultConfig();
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return _ManifestConfig.fromJson(Map<String, Object?>.from(decoded));
      }
      if (decoded is Map) {
        return _ManifestConfig.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {
      // Fall back to the built-in defaults if the manifest is absent or corrupt.
    }
    return _ManifestConfig.defaultConfig();
  }

  Future<_EnglishTreeDiscovery> _discoverEnglishTreeItems({
    int? maxPages,
    String? shelfUrl,
    _AuditProgressLogger? progress,
  }) async {
    final client = HttpClient()
      ..userAgent = 'StudyBible2 EGW Content Audit'
      ..connectionTimeout = _egwHttpConnectTimeout;
    client.autoUncompress = true;
    final warnings = <String>[];
    final items = <_EgwManifestItem>[];
    final discoveredCategories = <String>{};
    final visitedPages = <String>{};
    final visitedFinalPages = <String>{};
    final queuedPages = <String>{};
    final queue = Queue<_TreePageState>();
    var shelfTitle = '';
    var directBookLinksFound = 0;
    final childCollectionsDetected = <_ChildCollectionRecord>[];
    final shelfSeedUrl = shelfUrl?.trim();
    final rootCandidates = shelfSeedUrl == null || shelfSeedUrl.isEmpty
        ? <String>[_egwEnglishRootUrl, _egwEnglishTextRootUrl]
        : <String>[shelfSeedUrl];
    String rootUrlUsed = rootCandidates.first;
    var rootResolved = false;
    try {
      progress?.log('remote discovery start');
      if (shelfSeedUrl != null && shelfSeedUrl.isNotEmpty) {
        rootUrlUsed = shelfSeedUrl;
        rootResolved = true;
      } else {
        for (final candidate in rootCandidates) {
          try {
            final html = await _fetchText(client, candidate);
            final links = _extractTreeLinks(html, candidate);
            final hasRelevantLinks = links.any((link) {
              final resolved = _normalizeDiscoveryUrl(link.url);
              return _isCollectionPageUrl(resolved) || _isBookPageUrl(resolved);
            });
            if (!hasRelevantLinks) {
              warnings.add(
                'English root candidate had no branch links: $candidate',
              );
              continue;
            }
            rootUrlUsed = candidate;
            rootResolved = true;
            queue.add(
              _TreePageState(url: candidate, breadcrumbs: const <String>[]),
            );
            queuedPages.add(_normalizeDiscoveryUrl(candidate));
            break;
          } catch (error) {
            warnings.add(
              'Failed to fetch English root candidate $candidate: $error',
            );
          }
        }
      }
      if (!rootResolved) {
        warnings.add('Unable to resolve the English root branch tree.');
        progress?.log('remote discovery end (root unresolved)');
        return _EnglishTreeDiscovery(
          rootUrl: rootUrlUsed,
          shelfTitle: shelfTitle,
          directBookLinksFound: directBookLinksFound,
          childCollectionsDetected: childCollectionsDetected,
          branchCategoryPagesVisited: 0,
          finalItemPagesVisited: 0,
          pageUnavailableCount: 0,
          discoveredCategories: discoveredCategories,
          items: items,
          warnings: warnings,
        );
      }

      if (shelfSeedUrl != null && shelfSeedUrl.isNotEmpty) {
        var branchPagesVisited = 0;
        var finalItemPagesVisited = 0;
        var pageUnavailableCount = 0;
        String html;
        try {
          html = await _fetchText(client, shelfSeedUrl);
        } catch (error) {
          warnings.add('Page unavailable while crawling $shelfSeedUrl: $error');
          progress?.log('remote discovery end (shelf unavailable)');
          return _EnglishTreeDiscovery(
            rootUrl: rootUrlUsed,
            shelfTitle: shelfTitle,
            directBookLinksFound: 0,
            childCollectionsDetected: childCollectionsDetected,
            branchCategoryPagesVisited: 0,
            finalItemPagesVisited: 0,
            pageUnavailableCount: 1,
            discoveredCategories: discoveredCategories,
            items: items,
            warnings: warnings,
          );
        }

        branchPagesVisited = 1;
        final normalizedShelfUrl = _normalizeDiscoveryUrl(shelfSeedUrl);
        final pageLabel = _collectionLabelForPage(html, shelfSeedUrl);
        shelfTitle = pageLabel;
        final links = _extractTreeLinks(html, shelfSeedUrl);
        final bookPages = <_TreeLink>[];
        final childCollections = <_TreeLink>[];
        for (final link in links) {
          final resolved = _normalizeDiscoveryUrl(link.url);
          if (!_isAllowedEgwTreeUrl(resolved)) continue;
          if (_isBookPageUrl(resolved)) {
            bookPages.add(link);
          } else if (_isCollectionPageUrl(resolved) &&
              resolved != normalizedShelfUrl) {
            childCollections.add(link);
          }
        }
        directBookLinksFound = bookPages.length;
        for (final child in childCollections) {
          childCollectionsDetected.add(
            _ChildCollectionRecord(
              url: _normalizeDiscoveryUrl(child.url),
              label: _normalizeBreadcrumbLabel(child.label, child.url),
            ),
          );
        }
        if (debugLinks) {
          progress?.log(
            'shelf direct page=$normalizedShelfUrl label=${pageLabel.isEmpty ? "(none)" : pageLabel} '
            'children=${childCollections.length} books=${bookPages.length}',
          );
          if (childCollections.isNotEmpty) {
            progress?.log(
              'shelf child sample=$normalizedShelfUrl :: ${childCollections.take(10).map((child) => child.url).join(" | ")}',
            );
          }
          if (bookPages.isNotEmpty) {
            progress?.log(
              'shelf book sample=$normalizedShelfUrl :: ${bookPages.take(10).map((book) => book.url).join(" | ")}',
            );
          }
        }
        final effectiveBreadcrumbs = pageLabel.isEmpty
            ? const <String>[]
            : <String>[pageLabel];
        for (final bookPage in bookPages) {
          if (maxPages != null &&
              branchPagesVisited + finalItemPagesVisited >= maxPages) {
            warnings.add(
              'Remote discovery stopped after reaching --max-pages=$maxPages.',
            );
            break;
          }
          final itemPageUrl = _normalizeDiscoveryUrl(bookPage.url);
          if (!visitedFinalPages.add(itemPageUrl)) continue;
          final item = await _buildDiscoveredManifestItem(
            client: client,
            collectionUrl: shelfSeedUrl,
            itemPageUrl: bookPage.url,
            breadcrumbs: effectiveBreadcrumbs,
            bookLinkLabel: bookPage.label,
            progress: progress,
          );
          finalItemPagesVisited += 1;
          if (item == null) {
            pageUnavailableCount += 1;
            continue;
          }
          if (item.discoveryStatus == 'page_unavailable') {
            pageUnavailableCount += 1;
          }
          items.add(item);
          if (item.topCategory.isNotEmpty) {
            discoveredCategories.add(item.topCategory);
          } else if (item.category.isNotEmpty) {
            discoveredCategories.add(item.category);
          }
        }

        final discovery = _EnglishTreeDiscovery(
          rootUrl: rootUrlUsed,
          shelfTitle: shelfTitle,
          directBookLinksFound: directBookLinksFound,
          childCollectionsDetected: childCollectionsDetected,
          branchCategoryPagesVisited: branchPagesVisited,
          finalItemPagesVisited: finalItemPagesVisited,
          pageUnavailableCount: pageUnavailableCount,
          discoveredCategories: discoveredCategories,
          items: _dedupeManifestItems(items),
          warnings: warnings,
        );
        progress?.log(
          'remote discovery end '
          '(branchPages=${discovery.branchCategoryPagesVisited}, '
          'finalPages=${discovery.finalItemPagesVisited}, '
          'categories=${discovery.discoveredCategories.length})',
        );
        return discovery;
      }

      var branchPagesVisited = 0;
      var finalItemPagesVisited = 0;
      var pageUnavailableCount = 0;
      while (queue.isNotEmpty) {
        if (maxPages != null &&
            branchPagesVisited + finalItemPagesVisited >= maxPages) {
          warnings.add(
            'Remote discovery stopped after reaching --max-pages=$maxPages.',
          );
          break;
        }
        final state = queue.removeFirst();
        final normalizedPageUrl = _normalizeDiscoveryUrl(state.url);
        if (!visitedPages.add(normalizedPageUrl)) continue;

        String html;
        try {
          html = await _fetchText(client, state.url);
        } catch (error) {
          pageUnavailableCount += 1;
          warnings.add('Page unavailable while crawling ${state.url}: $error');
          continue;
        }

        branchPagesVisited += 1;
        final links = _extractTreeLinks(html, state.url);
        final pageLabel = _collectionLabelForPage(html, state.url);
        if (shelfTitle.isEmpty && shelfSeedUrl != null && shelfSeedUrl.isNotEmpty) {
          shelfTitle = pageLabel;
        } else if (shelfTitle.isEmpty && state.url == rootUrlUsed) {
          shelfTitle = pageLabel;
        }
        final effectiveBreadcrumbs = state.breadcrumbs.isNotEmpty
            ? state.breadcrumbs
            : (_isEnglishCollectionRootUrl(state.url) || pageLabel.isEmpty
                  ? const <String>[]
                  : <String>[pageLabel]);
        final childCollections = <_TreeLink>[];
        final bookPages = <_TreeLink>[];
        for (final link in links) {
          final resolved = _normalizeDiscoveryUrl(link.url);
          if (!_isAllowedEgwTreeUrl(resolved)) continue;
          if (_isCollectionPageUrl(resolved)) {
            if (resolved != normalizedPageUrl) {
              childCollections.add(link);
            }
          } else if (_isBookPageUrl(resolved)) {
            bookPages.add(link);
          }
        }

        if (debugLinks) {
          progress?.log(
            'crawl page=$normalizedPageUrl label=${pageLabel.isEmpty ? "(none)" : pageLabel} '
            'children=${childCollections.length} books=${bookPages.length}',
          );
          if (childCollections.isNotEmpty) {
            progress?.log(
              'crawl child sample=$normalizedPageUrl :: ${childCollections.take(10).map((child) => child.url).join(" | ")}',
            );
          }
          if (bookPages.isNotEmpty) {
            progress?.log(
              'crawl book sample=$normalizedPageUrl :: ${bookPages.take(10).map((book) => book.url).join(" | ")}',
            );
          }
        }

        for (final child in childCollections) {
          final childUrl = _normalizeDiscoveryUrl(child.url);
          if (visitedPages.contains(childUrl) ||
              queuedPages.contains(childUrl)) {
            continue;
          }
          final childLabel = _normalizeBreadcrumbLabel(child.label, child.url);
          if (_shouldSkipSiblingShelfLink(childLabel, childUrl, shelfTitle)) {
            continue;
          }
          queuedPages.add(childUrl);
          queue.add(
            _TreePageState(
              url: child.url,
              breadcrumbs: <String>[
                ...effectiveBreadcrumbs,
                if (childLabel.isNotEmpty) childLabel,
              ],
            ),
          );
        }

        for (final bookPage in bookPages) {
          if (maxPages != null &&
              branchPagesVisited + finalItemPagesVisited >= maxPages) {
            warnings.add(
              'Remote discovery stopped after reaching --max-pages=$maxPages.',
            );
            break;
          }
          final itemPageUrl = _normalizeDiscoveryUrl(bookPage.url);
          if (!visitedFinalPages.add(itemPageUrl)) continue;
          final item = await _buildDiscoveredManifestItem(
            client: client,
            collectionUrl: state.url,
            itemPageUrl: bookPage.url,
            breadcrumbs: effectiveBreadcrumbs,
            bookLinkLabel: bookPage.label,
            progress: progress,
          );
          finalItemPagesVisited += 1;
          if (item == null) {
            pageUnavailableCount += 1;
            continue;
          }
          if (item.discoveryStatus == 'page_unavailable') {
            pageUnavailableCount += 1;
          }
          items.add(item);
          if (item.topCategory.isNotEmpty) {
            discoveredCategories.add(item.topCategory);
          } else if (item.category.isNotEmpty) {
            discoveredCategories.add(item.category);
          }
        }
        if (normalizedPageUrl == _normalizeDiscoveryUrl(rootUrlUsed)) {
          directBookLinksFound = bookPages.length;
        }
        if (maxPages != null &&
            branchPagesVisited + finalItemPagesVisited >= maxPages) {
          break;
        }
      }

      final discovery = _EnglishTreeDiscovery(
        rootUrl: rootUrlUsed,
        shelfTitle: shelfTitle,
        directBookLinksFound: directBookLinksFound,
        childCollectionsDetected: childCollectionsDetected,
        branchCategoryPagesVisited: branchPagesVisited,
        finalItemPagesVisited: finalItemPagesVisited,
        pageUnavailableCount: pageUnavailableCount,
        discoveredCategories: discoveredCategories,
        items: _dedupeManifestItems(items),
        warnings: warnings,
      );
      progress?.log(
        'remote discovery end '
        '(branchPages=${discovery.branchCategoryPagesVisited}, '
        'finalPages=${discovery.finalItemPagesVisited}, '
        'categories=${discovery.discoveredCategories.length})',
      );
      return discovery;
    } finally {
      client.close(force: true);
    }
  }

  Future<_EgwManifestItem?> _buildDiscoveredManifestItem({
    required HttpClient client,
    required String collectionUrl,
    required String itemPageUrl,
    required List<String> breadcrumbs,
    required String bookLinkLabel,
    _AuditProgressLogger? progress,
  }) async {
    String html;
    try {
      html = await _fetchText(client, itemPageUrl);
    } catch (error) {
      final categoryPath = breadcrumbs.join(' > ');
      final topCategory = breadcrumbs.isEmpty ? '' : breadcrumbs.last;
      final category = _categoryCodeFor(topCategory, categoryPath);
      final displayName = _displayNameForCategory(category, topCategory);
      final normalizedLabel = _normalizeBreadcrumbLabel(
        bookLinkLabel,
        itemPageUrl,
      );
      return _EgwManifestItem(
        category: category,
        displayName: displayName,
        categoryPath: categoryPath,
        topCategory: topCategory,
        title: normalizedLabel.isEmpty ? 'Unavailable item' : normalizedLabel,
        code: '',
        language: 'en',
        year: null,
        pages: null,
        collectionUrl: collectionUrl,
        itemPageUrl: itemPageUrl,
        egwPageUrl: itemPageUrl,
        epubUrl: '',
        pdfUrl: '',
        verifiedEpubUrl: '',
        verifiedPdfUrl: '',
        epubFilename: '',
        pdfFilename: '',
        discoveryStatus: 'page_unavailable',
        applyEligible: false,
        recommendedAction: 'retry_later',
        targetEpubRelativePath: '',
        targetPdfRelativePath: '',
        modern: category == 'EGW_Modern_English',
        adapted: category == 'EGW_Modern_English',
        originalOrAdaptedLabel: category == 'EGW_Modern_English'
            ? 'adapted'
            : 'original',
        duplicateGroup: null,
        importStatus: 'page_unavailable',
        auditStatus: 'page_unavailable',
        reviewReason: error.toString(),
        searchScope: topCategory,
      );
    }

    final normalizedLabel = _normalizeBreadcrumbLabel(
      bookLinkLabel,
      itemPageUrl,
    );
    final title =
        _extractPageTitle(html) ??
        (normalizedLabel.isNotEmpty ? normalizedLabel : null) ??
        (breadcrumbs.isNotEmpty ? breadcrumbs.last : '');
    final pageCode = _extractBookCode(html) ?? '';
    final downloadLinks = _extractVerifiedDownloadLinks(html, itemPageUrl);
    final verifiedEpubUrl = downloadLinks.epubUrl ?? '';
    final verifiedPdfUrl = downloadLinks.pdfUrl ?? '';
    final availableFormats = downloadLinks.availableFormats;
    final code = pageCode.isNotEmpty
        ? pageCode
        : _codeFromDownloadUrl(
            verifiedEpubUrl.isNotEmpty ? verifiedEpubUrl : verifiedPdfUrl,
          );
    final categoryPath = breadcrumbs.join(' > ');
    final topCategory = breadcrumbs.isEmpty ? '' : breadcrumbs.last;
    final category = _categoryCodeFor(topCategory, categoryPath);
    final displayName = _displayNameForCategory(category, topCategory);
    final pageCount = _extractPageCount(html);
    final year = _extractYear(html);
    final detectedLanguage = _languageFromDownloadUrl(
      verifiedEpubUrl.isNotEmpty ? verifiedEpubUrl : verifiedPdfUrl,
    );
    final epubFilename = verifiedEpubUrl.isNotEmpty
        ? _filenameFromUrl(verifiedEpubUrl)
        : '';
    final pdfFilename = verifiedPdfUrl.isNotEmpty
        ? _filenameFromUrl(verifiedPdfUrl)
        : '';
    final verifiedAt = DateTime.now().toUtc().toIso8601String();
    final isEnglishDownload = _isEnglishDownloadUrl(verifiedEpubUrl) ||
        _isEnglishDownloadUrl(verifiedPdfUrl);
    final hasOtherDownloadFormats = availableFormats.any(
      (format) =>
          format != 'epub' && format != 'pdf' && format != 'online',
    );
    final discoveryStatus = verifiedEpubUrl.isNotEmpty
        ? (verifiedPdfUrl.isNotEmpty ? 'verified_epub_pdf' : 'verified_epub')
        : (verifiedPdfUrl.isNotEmpty
              ? (hasOtherDownloadFormats
                    ? 'no_epub_found'
                    : 'verified_pdf_only')
              : (hasOtherDownloadFormats
                    ? 'no_epub_found'
                    : 'no_download_links_found'));
    final applyEligible = verifiedEpubUrl.isNotEmpty && isEnglishDownload;
    final recommendedAction = applyEligible
        ? 'include_in_apply'
        : (discoveryStatus == 'page_unavailable'
              ? 'retry_later'
              : (discoveryStatus == 'verified_pdf_only'
                    ? 'pdf_available_but_epub_missing'
                    : 'skip_non_epub'));
    final reviewReason = discoveryStatus == 'verified_pdf_only'
        ? 'PDF-only item discovered; EPUB not present on the final item page.'
        : discoveryStatus == 'no_epub_found'
        ? 'No EPUB link was present; available formats: ${availableFormats.join(", ")}.'
        : discoveryStatus == 'no_download_links_found'
        ? 'Final item page did not expose downloadable file links.'
        : null;
    if (progress != null) {
      progress.log(
        'item page=$itemPageUrl title=$title epub=${verifiedEpubUrl.isEmpty ? "(none)" : verifiedEpubUrl} '
        'pdf=${verifiedPdfUrl.isEmpty ? "(none)" : verifiedPdfUrl} '
        'formats=${availableFormats.join(",")} status=$discoveryStatus',
      );
    }
    final targetEpubRelativePath = verifiedEpubUrl.isNotEmpty
        ? p.join(_folderForCategory(category), epubFilename)
        : '';
    final targetPdfRelativePath = verifiedPdfUrl.isNotEmpty
        ? p.join(_folderForCategory(category), pdfFilename)
        : '';
    return _EgwManifestItem(
      category: category,
      displayName: displayName,
      categoryPath: categoryPath,
      topCategory: topCategory,
      title: title,
      code: code,
      language: detectedLanguage,
      year: year,
      pages: pageCount,
      collectionUrl: collectionUrl,
      itemPageUrl: itemPageUrl,
      egwPageUrl: itemPageUrl,
      epubUrl: verifiedEpubUrl,
      pdfUrl: verifiedPdfUrl,
      availableFormats: availableFormats,
      verifiedEpubUrl: verifiedEpubUrl,
      verifiedPdfUrl: verifiedPdfUrl,
      epubFilename: epubFilename,
      pdfFilename: pdfFilename,
      verifiedEpubSize: null,
      verifiedPdfSize: null,
      verifiedEpubSha256: '',
      verifiedPdfSha256: '',
      lastVerifiedAt: verifiedAt,
      discoveryStatus: discoveryStatus,
      applyEligible: applyEligible,
      recommendedAction: recommendedAction,
      targetEpubRelativePath: targetEpubRelativePath,
      targetPdfRelativePath: targetPdfRelativePath,
      modern: category == 'EGW_Modern_English',
      adapted: category == 'EGW_Modern_English',
      originalOrAdaptedLabel: category == 'EGW_Modern_English'
          ? 'adapted'
          : 'original',
      duplicateGroup: null,
      importStatus: discoveryStatus,
      auditStatus: applyEligible ? 'eligible' : 'needs_review',
      reviewReason: reviewReason,
      searchScope: topCategory,
    );
  }

  List<_TreeLink> _extractTreeLinks(String html, String baseUrl) {
    final links = <_TreeLink>[];
    final seen = <String>{};
    for (final candidate in _extractDiscoveryUrlCandidates(html, baseUrl)) {
      if (!seen.add(candidate)) continue;
      links.add(
        _TreeLink(
          url: candidate,
          label: _normalizeBreadcrumbLabel('', candidate),
        ),
      );
    }
    return links;
  }

  bool _isAllowedEgwTreeUrl(String url) {
    if (!_isEnglishCollectionTreeUrl(url) && !_isBookPageUrl(url)) {
      return false;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (!_allowedEgwHosts.contains(uri.host.toLowerCase())) return false;
    return true;
  }

  bool _isCollectionPageUrl(String url) {
    return _isEnglishCollectionTreeUrl(url);
  }

  bool _shouldSkipSiblingShelfLink(
    String childLabel,
    String childUrl,
    String shelfTitle,
  ) {
    final normalizedLabel = childLabel.trim();
    if (normalizedLabel.isEmpty) return false;
    if (_isEnglishCollectionRootUrl(childUrl)) return true;
    if (_siblingShelfLabels.contains(normalizedLabel)) {
      if (shelfTitle.isEmpty) return true;
      if (normalizedLabel != shelfTitle) return true;
    }
    return false;
  }

  bool _isEnglishCollectionTreeUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final segments = uri.pathSegments;
    if (segments.isEmpty || segments.first != 'allCollection') return false;
    if (segments.length == 1) return false;
    if (segments.length == 2) {
      return segments[1] == 'en';
    }
    return segments.length >= 3 &&
        segments[1] == 'en' &&
        RegExp(r'^\d+$').hasMatch(segments[2]);
  }

  bool _isEnglishCollectionRootUrl(String url) {
    final normalized = _normalizeDiscoveryUrl(url);
    return normalized == _normalizeDiscoveryUrl(_egwEnglishRootUrl) ||
        normalized == _normalizeDiscoveryUrl(_egwEnglishTextRootUrl);
  }

  bool _isBookPageUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path;
    return path.startsWith('/book/') || path.startsWith('/en/book/');
  }

  String _normalizeDiscoveryUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url.trim();
    return uri.replace(fragment: '').toString().replaceAll(RegExp(r'/$'), '');
  }

  String _normalizeBreadcrumbLabel(String rawLabel, String fallbackUrl) {
    final cleaned = _cleanHtml(rawLabel);
    if (cleaned.isNotEmpty) return cleaned;
    final uri = Uri.tryParse(fallbackUrl);
    if (uri == null) return '';
    final lastSegment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return _cleanHtml(lastSegment);
  }

  String _displayNameForCategory(String category, String topCategory) {
    if (_categoryFolderAliases.containsValue(category)) {
      return _categoryFolderAliases.keys.firstWhere(
        (key) => _categoryFolderAliases[key] == category,
        orElse: () => topCategory,
      );
    }
    return topCategory.isNotEmpty ? topCategory : category;
  }

  String _folderForCategory(String category) {
    if (category == 'EGW_Commentaries') {
      return p.join('ePubs', 'Commentaries', 'EGW_Commentaries');
    }
    if (category.startsWith('EGW_')) {
      return p.join('ePubs', 'Research', category);
    }
    return p.join('ePubs', 'Research', 'EGW_${_sanitizeSegment(category)}');
  }

  String _categoryCodeFor(String topCategory, String categoryPath) {
    final normalizedTop = topCategory.trim();
    if (normalizedTop.isNotEmpty) {
      final alias = _categoryFolderAliases[normalizedTop];
      if (alias != null) return alias;
    }
    for (final entry in _categoryFolderAliases.entries) {
      if (categoryPath.contains(entry.key)) {
        return entry.value;
      }
    }
    final suffix = _sanitizeSegment(
      normalizedTop.isNotEmpty ? normalizedTop : categoryPath,
    );
    return suffix.isEmpty ? 'EGW_Unknown' : 'EGW_$suffix';
  }

  String _sanitizeSegment(String value) {
    final cleaned = value
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return cleaned;
  }

  String _codeFromDownloadUrl(String url) {
    if (url.trim().isEmpty) return '';
    final fileName = _filenameFromUrl(url);
    final match = RegExp(
      r'^en_([A-Za-z0-9]+(?:\.\d+)?)\.(?:epub|pdf)$',
      caseSensitive: false,
    ).firstMatch(fileName);
    return match?.group(1) ?? '';
  }

  String _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return '';
    return uri.pathSegments.last;
  }

  _VerifiedDownloadLinks _extractVerifiedDownloadLinks(
    String html,
    String baseUrl,
  ) {
    String? epubUrl;
    String? pdfUrl;
    final formats = <String>{};
    for (final href in _extractHrefAttributes(html)) {
      if (href.trim().isEmpty) continue;
      final resolved = _normalizeDiscoveryUrl(
        Uri.parse(baseUrl).resolve(href).toString(),
      );
      final uri = Uri.tryParse(resolved);
      if (uri == null || !_allowedEgwHosts.contains(uri.host.toLowerCase())) {
        continue;
      }
      final lower = resolved.toLowerCase();
      if (epubUrl == null &&
          (lower.contains('/epub/') || lower.endsWith('.epub'))) {
        epubUrl = resolved;
        formats.add('epub');
      }
      if (pdfUrl == null &&
          (lower.contains('/pdf/') || lower.endsWith('.pdf'))) {
        pdfUrl = resolved;
        formats.add('pdf');
      }
      if (lower.contains('/mobi/') ||
          lower.endsWith('.mobi') ||
          lower.contains('.azw3') ||
          lower.contains('.azw') ||
          lower.contains('kindle')) {
        formats.add('mobi');
      }
      if (lower.contains('/mp3/') ||
          lower.endsWith('.mp3') ||
          lower.contains('/audio/')) {
        formats.add('mp3');
      }
      if (epubUrl != null && pdfUrl != null) break;
    }
    if (formats.isEmpty) {
      formats.add('online');
    }
    return _VerifiedDownloadLinks(
      epubUrl: epubUrl,
      pdfUrl: pdfUrl,
      availableFormats: formats.toList(growable: false),
    );
  }

  bool _isEnglishDownloadUrl(String url) {
    if (url.trim().isEmpty) return false;
    final fileName = _filenameFromUrl(url).toLowerCase();
    return fileName.startsWith('en_');
  }

  String _languageFromDownloadUrl(String url) {
    if (url.trim().isEmpty) return 'unknown';
    final fileName = _filenameFromUrl(url);
    final match = RegExp(r'^([A-Za-z]{2})_').firstMatch(fileName);
    return match?.group(1)?.toLowerCase() ?? 'unknown';
  }

  // ignore: unused_element
  Future<_CollectionDiscovery> _discoverCollectionItems(
    _CollectionDefinition collection,
  ) async {
    final client = HttpClient()
      ..userAgent = 'StudyBible2 EGW Content Audit'
      ..connectionTimeout = _egwHttpConnectTimeout;
    client.autoUncompress = true;
    try {
      final primary = await _fetchCollectionPage(client, collection.pageUrl);
      var html = primary.html;
      var pageUrl = primary.pageUrl;
      var usedFallback = false;
      if (primary.bookPageUrls.isEmpty &&
          collection.fallbackPageUrl.trim().isNotEmpty) {
        final fallback = await _fetchCollectionPage(
          client,
          collection.fallbackPageUrl,
        );
        if (fallback.bookPageUrls.isNotEmpty) {
          html = fallback.html;
          pageUrl = fallback.pageUrl;
          usedFallback = true;
        }
      }
      final bookPageUrls = _extractBookPageUrls(html, pageUrl);
      final items = <_EgwManifestItem>[];
      for (final bookPageUrl in bookPageUrls) {
        final item = await _buildManifestItem(
          client: client,
          collection: collection,
          bookPageUrl: bookPageUrl,
        );
        if (item != null) {
          items.add(item);
        }
      }
      final deduped = _dedupeManifestItems(items);
      final fallbackItems = _fallbackItemsForCollection(collection);
      if (fallbackItems.isNotEmpty && deduped.length < fallbackItems.length) {
        return _CollectionDiscovery(
          items: fallbackItems,
          usedFallbackPage: true,
        );
      }
      return _CollectionDiscovery(
        items: deduped,
        usedFallbackPage: usedFallback,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<_CollectionPageResult> _fetchCollectionPage(
    HttpClient client,
    String url,
  ) async {
    final response = await _fetchText(client, url);
    return _CollectionPageResult(
      html: response,
      pageUrl: url,
      bookPageUrls: _extractBookPageUrls(response, url),
    );
  }

  List<String> _extractBookPageUrls(String html, String baseUrl) {
    final seen = <String>{};
    final urls = <String>[];
    final patterns = <RegExp>[
      RegExp(r'href="([^"]*?/book/b\d+)"', caseSensitive: false),
      RegExp(r'href="([^"]*?/en/book/\d+(?:\.\d+)?)"', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final href = match.group(1);
        if (href == null || href.trim().isEmpty) continue;
        final resolved = Uri.parse(baseUrl).resolve(href).toString();
        if (!seen.add(resolved)) continue;
        urls.add(resolved);
      }
    }
    return urls;
  }

  Future<_EgwManifestItem?> _buildManifestItem({
    required HttpClient client,
    required _CollectionDefinition collection,
    required String bookPageUrl,
  }) async {
    final html = await _fetchText(client, bookPageUrl);
    final title = _extractPageTitle(html) ?? collection.displayName;
    final code = _extractBookCode(html) ?? _extractCodeFromUrl(bookPageUrl);
    if (code.trim().isEmpty) return null;
    final pageCount = _extractPageCount(html);
    final year = _extractYear(html);
    final item = _EgwManifestItem(
      category: collection.category,
      displayName: collection.displayName,
      title: title,
      code: code,
      language: 'en',
      year: year,
      pages: pageCount,
      egwPageUrl: bookPageUrl,
      epubUrl: 'https://media2.egwwritings.org/epub/en_$code.epub',
      pdfUrl: 'https://media2.egwwritings.org/pdf/en_$code.pdf',
      targetEpubRelativePath: p.join(
        'ePubs',
        collection.folderRoot,
        collection.folderName,
        'en_$code.epub',
      ),
      targetPdfRelativePath: p.join(
        'PDFs',
        collection.folderRoot,
        collection.folderName,
        'en_$code.pdf',
      ),
      modern: collection.modern,
      adapted: collection.adapted,
      originalOrAdaptedLabel: collection.adapted ? 'adapted' : 'original',
      duplicateGroup: null,
      importStatus: _importStatusFor(collection.category, code),
      applyEligible: _applyEligibleFor(collection.category, code),
      auditStatus: _auditStatusFor(collection.category, code),
      recommendedAction: _recommendedActionFor(collection.category, code),
      reviewReason: _reviewReasonFor(collection.category, code),
      searchScope: collection.searchScope,
    );
    return item;
  }

  List<_EgwManifestItem> _fallbackItemsForCollection(
    _CollectionDefinition collection,
  ) {
    if (_mrVolumeSpecs.containsKey(collection.category)) {
      return _mrVolumeSpecs[collection.category]!
          .map(
            (spec) => _EgwManifestItem(
              category: collection.category,
              displayName: collection.displayName,
              title:
                  'Manuscript Releases, vol. ${spec.volume} [Nos. ${spec.start}-${spec.end}]',
              code: '${spec.volume}MR',
              language: 'en',
              year: 1990,
              pages: null,
              egwPageUrl: collection.pageUrl,
              epubUrl:
                  'https://media2.egwwritings.org/epub/en_${spec.volume}MR.epub',
              pdfUrl:
                  'https://media2.egwwritings.org/pdf/en_${spec.volume}MR.pdf',
              targetEpubRelativePath: p.join(
                'ePubs',
                collection.folderRoot,
                collection.folderName,
                'en_${spec.volume}MR.epub',
              ),
              targetPdfRelativePath: p.join(
                'PDFs',
                collection.folderRoot,
                collection.folderName,
                'en_${spec.volume}MR.pdf',
              ),
              modern: collection.modern,
              adapted: collection.adapted,
              originalOrAdaptedLabel: 'original',
              duplicateGroup: null,
              importStatus: _importStatusFor(
                collection.category,
                '${spec.volume}MR',
              ),
              applyEligible: _applyEligibleFor(
                collection.category,
                '${spec.volume}MR',
              ),
              auditStatus: _auditStatusFor(
                collection.category,
                '${spec.volume}MR',
              ),
              recommendedAction: _recommendedActionFor(
                collection.category,
                '${spec.volume}MR',
              ),
              reviewReason: _reviewReasonFor(
                collection.category,
                '${spec.volume}MR',
              ),
              searchScope: collection.searchScope,
            ),
          )
          .toList(growable: false);
    }
    if (_ltMsVolumeSpecs.containsKey(collection.category)) {
      return _ltMsVolumeSpecs[collection.category]!
          .map(
            (spec) => _EgwManifestItem(
              category: collection.category,
              displayName: collection.displayName,
              title:
                  'Letters and Manuscripts — Volume ${spec.volume} (${spec.start} - ${spec.end})',
              code: '${spec.volume}LtMs',
              language: 'en',
              year: spec.start,
              pages: null,
              egwPageUrl: collection.pageUrl,
              epubUrl:
                  'https://media2.egwwritings.org/epub/en_${spec.volume}LtMs.epub',
              pdfUrl:
                  'https://media2.egwwritings.org/pdf/en_${spec.volume}LtMs.pdf',
              targetEpubRelativePath: p.join(
                'ePubs',
                collection.folderRoot,
                collection.folderName,
                'en_${spec.volume}LtMs.epub',
              ),
              targetPdfRelativePath: p.join(
                'PDFs',
                collection.folderRoot,
                collection.folderName,
                'en_${spec.volume}LtMs.pdf',
              ),
              modern: collection.modern,
              adapted: collection.adapted,
              originalOrAdaptedLabel: 'original',
              duplicateGroup: null,
              importStatus: _importStatusFor(
                collection.category,
                '${spec.volume}LtMs',
              ),
              applyEligible: _applyEligibleFor(
                collection.category,
                '${spec.volume}LtMs',
              ),
              auditStatus: _auditStatusFor(
                collection.category,
                '${spec.volume}LtMs',
              ),
              recommendedAction: _recommendedActionFor(
                collection.category,
                '${spec.volume}LtMs',
              ),
              reviewReason: _reviewReasonFor(
                collection.category,
                '${spec.volume}LtMs',
              ),
              searchScope: collection.searchScope,
            ),
          )
          .toList(growable: false);
    }
    return const <_EgwManifestItem>[];
  }

  Future<List<_DbCatalogRow>> _readDbRows() async {
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) return const <_DbCatalogRow>[];
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final rows = await db.query(
        'library_items',
        columns: const [
          'id',
          'title',
          'file_name',
          'file_hash',
          'relative_path',
          'file_format',
          'folder_type',
          'library_role',
          'collection_name',
          'source_site',
          'source_url',
          'source_type',
          'index_status',
          'file_size',
          'mime_type',
          'spine_index',
          'anchor_id',
          'epub_href',
          'paragraph_index',
          'date_added',
          'last_opened',
          'deleted_at',
        ],
        where:
            "deleted_at IS NULL AND (LOWER(COALESCE(collection_name, '')) LIKE 'egw%' OR LOWER(COALESCE(relative_path, '')) LIKE 'epubs/%' OR LOWER(COALESCE(relative_path, '')) LIKE 'pdfs/%')",
      );
      return rows
          .map((row) => _DbCatalogRow.fromRow(Map<String, Object?>.from(row)))
          .toList(growable: false);
    } finally {
      await db.close();
    }
  }

  Future<_ScanResult> _scanLocalFiles(
    List<_ScanRootSpec> scanRoots,
    List<_DbCatalogRow> dbRows,
    _ManifestIndex manifestIndex, {
    _AuditProgressLogger? progress,
  }) async {
    final dbByRelativePath = {
      for (final row in dbRows) _normalizePath(row.relativePath): row,
    };
    final allFiles = <_LocalFileRecord>[];
    final summaries = <_ScanRootSummary>[];
    progress?.log('size/hash scan start');

    for (final spec in scanRoots) {
      final root = Directory(spec.path);
      final summary = _ScanRootSummary(
        label: spec.label,
        path: spec.path,
        kind: spec.kind,
        exists: await root.exists(),
      );
      if (!summary.exists) {
        summaries.add(summary);
        continue;
      }

      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        summary.totalFiles += 1;
        final lower = entity.path.toLowerCase();
        if (!lower.endsWith('.epub') && !lower.endsWith('.pdf')) continue;
        final relativePath = p.relative(entity.path, from: spec.path);
        if (_shouldSkipPath(relativePath)) continue;
        final code =
            _codeFromRelativePath(relativePath) ??
            _codeFromFileName(entity.path) ??
            '';
        final pathCategory = _categoryForRelativePath(relativePath);
        final category = manifestIndex.categoryForCode(code) ?? pathCategory;
        if (category == null) continue;
        summary.egwFiles += 1;

        final size = await entity.length();
        final sha = await _sha256ForFile(entity);
        final dbRow = spec.kind == _ScanRootKind.managed
            ? dbByRelativePath[_normalizePath(relativePath)]
            : null;
        final targetRelativePath = manifestIndex.targetRelativePathFor(
          category: category,
          code: code,
          format: p.extension(entity.path).toLowerCase().replaceFirst('.', ''),
        );
        allFiles.add(
          _LocalFileRecord(
            filePath: entity.path,
            rootLabel: spec.label,
            rootPath: spec.path,
            rootKind: spec.kind.name,
            relativePath: relativePath,
            targetRelativePath: targetRelativePath,
            category: category,
            fileName: p.basename(entity.path),
            fileSize: size,
            sha256: sha,
            code: code,
            indexed: dbRow?.indexed ?? false,
            indexStatus: dbRow?.indexStatus,
            dbTitle: dbRow?.title,
            dbCollectionName: dbRow?.collectionName,
            dbRelativePath: dbRow?.relativePath,
            dbFileHash: dbRow?.fileHash,
            duplicateGroup: sha,
            conflict:
                dbRow != null &&
                _normalizePath(dbRow.relativePath) !=
                    _normalizePath(relativePath),
          ),
        );
      }
      summaries.add(summary);
      progress?.log(
        'size/hash scan root end '
        '(${spec.label}: total=${summary.totalFiles}, egw=${summary.egwFiles})',
      );
    }
    progress?.log('size/hash scan end');
    return _ScanResult(localFiles: allFiles, scannedRoots: summaries);
  }

  _InventoryAnalysis _analyzeLocalFindings(
    List<_LocalFileRecord> files,
    _ManifestIndex manifestIndex,
  ) {
    final unmatchedLocalFiles = <_LocalFileRecord>[];
    final groups = <String, List<_LocalFileRecord>>{};

    for (final file in files) {
      final code = file.code.trim();
      if (code.isEmpty || !manifestIndex.hasCode(code)) {
        unmatchedLocalFiles.add(file);
        continue;
      }
      final key = '${code.toLowerCase()}|${file.format}';
      groups.putIfAbsent(key, () => <_LocalFileRecord>[]).add(file);
    }

    final duplicateSameHashGroups = <_AuditFindingGroup>[];
    final duplicateSameCodeDifferentLocationGroups = <_AuditFindingGroup>[];
    final conflictSameCodeDifferentHashGroups = <_AuditFindingGroup>[];
    final conflictTargetExistsDifferentHashGroups = <_AuditFindingGroup>[];

    for (final entry in groups.entries) {
      final group = entry.value;
      if (group.length < 2) continue;

      final hashes = group.map((file) => file.sha256).toSet();
      final sizes = group.map((file) => file.fileSize).toSet();
      final category = group.first.category;
      final code = group.first.code;
      final title =
          manifestIndex.titleForCode(code) ??
          group.first.dbTitle ??
          group.first.fileName;
      final targetRelativePaths = group
          .map((file) => file.targetRelativePath)
          .whereType<String>()
          .map((path) => _normalizePath(path))
          .toSet()
          .toList(growable: false);
      final managedTargetFiles = group
          .where((file) => file.rootKind == _ScanRootKind.managed.name)
          .toList(growable: false);
      final legacyFiles = group
          .where((file) => file.rootKind != _ScanRootKind.managed.name)
          .toList(growable: false);

      if (hashes.length == 1) {
        final status = legacyFiles.isNotEmpty && managedTargetFiles.isEmpty
            ? 'duplicate_same_code_different_location'
            : 'duplicate_same_hash';
        final groupRecord = _AuditFindingGroup(
          status: status,
          category: category,
          code: code,
          title: title,
          targetRelativePaths: targetRelativePaths,
          recommendedAction: managedTargetFiles.isEmpty
              ? 'copy_to_managed'
              : 'ignore_duplicate',
          reason: managedTargetFiles.isEmpty
              ? 'Same code and hash found only in legacy locations.'
              : 'Same code and hash found in multiple approved roots.',
          files: List<_LocalFileRecord>.unmodifiable(group),
        );
        duplicateSameHashGroups.add(groupRecord);
        duplicateSameCodeDifferentLocationGroups.add(groupRecord);
        continue;
      }

      final managedTargetHash = managedTargetFiles.isNotEmpty
          ? managedTargetFiles.first.sha256
          : null;
      final hasTargetConflict =
          managedTargetHash != null &&
          legacyFiles.any(
            (file) =>
                file.targetRelativePath != null &&
                _normalizePath(file.targetRelativePath!) ==
                    _normalizePath(
                      managedTargetFiles.first.targetRelativePath ?? '',
                    ) &&
                file.sha256 != managedTargetHash,
          );

      if (hasTargetConflict) {
        conflictTargetExistsDifferentHashGroups.add(
          _AuditFindingGroup(
            status: 'conflict_target_exists_different_hash',
            category: category,
            code: code,
            title: title,
            targetRelativePaths: targetRelativePaths,
            recommendedAction: 'manual_review',
            reason:
                'Managed target exists with a different hash from a legacy source copy.',
            files: List<_LocalFileRecord>.unmodifiable(group),
          ),
        );
        continue;
      }

      conflictSameCodeDifferentHashGroups.add(
        _AuditFindingGroup(
          status: 'conflict_same_code_different_hash',
          category: category,
          code: code,
          title: title,
          targetRelativePaths: targetRelativePaths,
          recommendedAction: 'manual_review',
          reason:
              'Same code and format have different hashes across locations.',
          files: List<_LocalFileRecord>.unmodifiable(group),
        ),
      );

      // If size matches but hash differs, keep the record as a conflict and let the
      // report show the full source set for manual review.
      if (sizes.length == 1) {
        // no-op; the report already captures the conflict grouping.
      }
    }

    return _InventoryAnalysis(
      duplicateSameHashGroups: duplicateSameHashGroups,
      duplicateSameCodeDifferentLocationGroups:
          duplicateSameCodeDifferentLocationGroups,
      conflictSameCodeDifferentHashGroups: conflictSameCodeDifferentHashGroups,
      conflictTargetExistsDifferentHashGroups:
          conflictTargetExistsDifferentHashGroups,
      unmatchedLocalFiles: unmatchedLocalFiles,
    );
  }

  List<_EgwItemAudit> _compareManifestToLocal(
    List<_EgwManifestItem> manifestItems,
    List<_LocalFileRecord> localFiles,
  ) {
    final byTargetPath = <String, List<_LocalFileRecord>>{};
    for (final file in localFiles) {
      final target = file.targetRelativePath;
      if (target == null || target.trim().isEmpty) continue;
      byTargetPath
          .putIfAbsent(_normalizePath(target), () => <_LocalFileRecord>[])
          .add(file);
    }
    final audits = <_EgwItemAudit>[];
    for (final item in manifestItems) {
      final epubMatches =
          byTargetPath[_normalizePath(item.targetEpubRelativePath)] ??
          const <_LocalFileRecord>[];
      final pdfMatches =
          byTargetPath[_normalizePath(item.targetPdfRelativePath)] ??
          const <_LocalFileRecord>[];
      final needsReview = !item.applyEligible;
      final managedTargetMatches = <_LocalFileRecord>[
        ...epubMatches.where(
          (file) => file.rootKind == _ScanRootKind.managed.name,
        ),
        ...pdfMatches.where(
          (file) => file.rootKind == _ScanRootKind.managed.name,
        ),
      ];
      final legacyMatches = <_LocalFileRecord>[
        ...epubMatches.where(
          (file) => file.rootKind != _ScanRootKind.managed.name,
        ),
        ...pdfMatches.where(
          (file) => file.rootKind != _ScanRootKind.managed.name,
        ),
      ];
      final present = managedTargetMatches.isNotEmpty;
      final presentLegacyLocation =
          !present && legacyMatches.isNotEmpty && !needsReview;
      final localMatches = <_LocalFileRecord>[
        ...managedTargetMatches,
        ...legacyMatches,
      ];
      final missingTargets = <String>[
        ...?(epubMatches.isEmpty
            ? <String>[item.targetEpubRelativePath]
            : null),
        ...?(pdfMatches.isEmpty ? <String>[item.targetPdfRelativePath] : null),
      ];
      audits.add(
        _EgwItemAudit(
          category: item.category,
          code: item.code,
          title: item.title,
          applyEligible: item.applyEligible,
          auditStatus: item.auditStatus,
          recommendedAction: item.recommendedAction,
          reviewReason: item.reviewReason,
          present: present,
          presentLegacyLocation: presentLegacyLocation,
          availableToCopy: presentLegacyLocation && item.applyEligible,
          epubPresent: epubMatches.isNotEmpty,
          pdfPresent: pdfMatches.isNotEmpty,
          missingTargets: List<String>.unmodifiable(missingTargets),
          localMatches: List<_LocalFileRecord>.unmodifiable(localMatches),
          recommendedTargetFolder: _recommendedFolderFor(item.category),
          duplicateRisk: _duplicateRiskFor(item),
        ),
      );
    }
    return audits;
  }

  List<_EgwApplyTask> _buildApplyTasks({
    required _EgwAuditReport auditReport,
    String? categoryFilter,
  }) {
    final managedByTargetPath = <String, _LocalFileRecord>{};
    for (final file in auditReport.localFiles) {
      if (file.rootKind != _ScanRootKind.managed.name) continue;
      final target = file.targetRelativePath;
      if (target == null || target.trim().isEmpty) continue;
      managedByTargetPath[_normalizePath(target)] = file;
    }

    final tasks = <_EgwApplyTask>[];
    for (var index = 0; index < auditReport.manifestItems.length; index++) {
      final item = auditReport.manifestItems[index];
      if (categoryFilter != null &&
          categoryFilter.trim().isNotEmpty &&
          item.category != categoryFilter.trim()) {
        continue;
      }
      if (!item.applyEligible) {
        continue;
      }
      final audit = index < auditReport.itemAudits.length
          ? auditReport.itemAudits[index]
          : null;
      if (audit == null) continue;
      tasks.addAll(
        _tasksForManifestItem(
          item: item,
          audit: audit,
          managedByTargetPath: managedByTargetPath,
        ),
      );
    }
    return tasks;
  }

  List<_EgwApplyTask> _tasksForManifestItem({
    required _EgwManifestItem item,
    required _EgwItemAudit audit,
    required Map<String, _LocalFileRecord> managedByTargetPath,
  }) {
    final targetPath = item.targetEpubRelativePath.trim();
    if (targetPath.isEmpty) return const <_EgwApplyTask>[];

    final managedTarget = managedByTargetPath[_normalizePath(targetPath)];
    final candidates = audit.localMatches
        .where((file) => file.format == 'epub')
        .toList(growable: false);
    return <_EgwApplyTask>[
      _EgwApplyTask(
        category: item.category,
        code: item.code,
        title: item.title,
        format: 'epub',
        targetRelativePath: targetPath,
        sourceUrl: item.epubUrl,
        managedTarget: managedTarget,
        sourceCandidates: candidates,
        recommendedTargetFolder: audit.recommendedTargetFolder,
      ),
    ];
  }

  Future<_EgwSyncAction> _executeApplyTask({
    required _EgwApplyTask task,
    required _EgwAuditReport auditReport,
    required HttpClient httpClient,
    required bool dryRun,
  }) async {
    final targetPath = p.join(auditReport.rootPath, task.targetRelativePath);
    final targetFile = File(targetPath);
    final targetExists = await targetFile.exists();
    final targetHash = targetExists ? await _sha256ForFile(targetFile) : null;
    final targetSize = targetExists ? await targetFile.length() : null;
    final chosenSource = _chooseSourceCandidate(task.sourceCandidates);
    final sourceHash = chosenSource?.sha256;

    if (targetExists) {
      if (sourceHash != null && targetHash == sourceHash) {
        return _EgwSyncAction(
          status: 'skipped_existing',
          category: task.category,
          code: task.code,
          title: task.title,
          format: task.format,
          targetPath: targetPath,
          sourcePath: chosenSource?.filePath ?? task.sourceUrl,
          sourceKind: chosenSource?.rootKind ?? 'managed',
          fileSize: targetSize,
          sha256: targetHash,
          recommendedTargetFolder: task.recommendedTargetFolder,
          reason: 'Target already exists with the same hash.',
          duplicateSourcesIgnored: _duplicateSourceCount(
            task.sourceCandidates,
            chosenSource,
          ),
        );
      }
      if (sourceHash == null) {
        return _EgwSyncAction(
          status: 'skipped_existing',
          category: task.category,
          code: task.code,
          title: task.title,
          format: task.format,
          targetPath: targetPath,
          sourcePath: task.sourceUrl,
          sourceKind: 'remote',
          fileSize: targetSize,
          sha256: targetHash,
          recommendedTargetFolder: task.recommendedTargetFolder,
          reason: 'Target already exists and no source copy is needed.',
          duplicateSourcesIgnored: _duplicateSourceCount(
            task.sourceCandidates,
            chosenSource,
          ),
        );
      }
      return _EgwSyncAction(
        status: 'conflict',
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: chosenSource!.filePath,
        sourceKind: chosenSource.rootKind,
        fileSize: targetSize,
        sha256: targetHash,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason:
            'Target exists with a different hash from the available source copy.',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    }

    if (dryRun) {
      final actionStatus = chosenSource == null
          ? 'dry_run_download'
          : 'dry_run_copy';
      return _EgwSyncAction(
        status: actionStatus,
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: chosenSource?.filePath ?? task.sourceUrl,
        sourceKind: chosenSource?.rootKind ?? 'remote',
        fileSize: chosenSource?.fileSize,
        sha256: chosenSource?.sha256,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason: chosenSource == null
            ? 'Dry run: would download missing file.'
            : 'Dry run: would copy legacy file into managed target.',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    }

    await targetFile.parent.create(recursive: true);
    if (chosenSource != null) {
      final tempPath =
          '${targetFile.path}.tmp_${DateTime.now().microsecondsSinceEpoch}';
      final tempFile = File(tempPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      await File(chosenSource.filePath).copy(tempPath);
      final copiedHash = await _sha256ForFile(tempFile);
      final copiedSize = await tempFile.length();
      if (await targetFile.exists()) {
        final currentHash = await _sha256ForFile(targetFile);
        if (currentHash == copiedHash) {
          await tempFile.delete();
          return _EgwSyncAction(
            status: 'skipped_existing',
            category: task.category,
            code: task.code,
            title: task.title,
            format: task.format,
            targetPath: targetPath,
            sourcePath: chosenSource.filePath,
            sourceKind: chosenSource.rootKind,
            fileSize: copiedSize,
            sha256: copiedHash,
            recommendedTargetFolder: task.recommendedTargetFolder,
            reason:
                'Target appeared during copy and already matches the source hash.',
            duplicateSourcesIgnored: _duplicateSourceCount(
              task.sourceCandidates,
              chosenSource,
            ),
          );
        }
        await tempFile.delete();
        return _EgwSyncAction(
          status: 'conflict',
          category: task.category,
          code: task.code,
          title: task.title,
          format: task.format,
          targetPath: targetPath,
          sourcePath: chosenSource.filePath,
          sourceKind: chosenSource.rootKind,
          fileSize: copiedSize,
          sha256: copiedHash,
          recommendedTargetFolder: task.recommendedTargetFolder,
          reason:
              'Target appeared during copy and its hash differs from the source.',
          duplicateSourcesIgnored: _duplicateSourceCount(
            task.sourceCandidates,
            chosenSource,
          ),
        );
      }
      await tempFile.rename(targetFile.path);
      return _EgwSyncAction(
        status: 'copied',
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: chosenSource.filePath,
        sourceKind: chosenSource.rootKind,
        fileSize: copiedSize,
        sha256: copiedHash,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason: 'Legacy file copied into managed target.',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    }

    final url = task.sourceUrl.trim();
    if (url.isEmpty) {
      return _EgwSyncAction(
        status: 'needs_review',
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: '',
        sourceKind: 'remote',
        fileSize: null,
        sha256: null,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason: 'No download URL was available for the missing file.',
        recommendedAction: 'manifest_correction_needed',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    }

    final uri = Uri.parse(url);
    final tempPath =
        '${targetFile.path}.download_${DateTime.now().microsecondsSinceEpoch}';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    try {
      final request = await _getUrlWithTimeout(
        httpClient,
        uri,
        _egwHttpConnectTimeout,
      );
      final response = await _closeRequestWithTimeout(
        request,
        uri,
        _egwHttpDownloadTimeout,
      );
      final retryableStatuses = <int>{
        HttpStatus.badGateway,
        HttpStatus.serviceUnavailable,
        HttpStatus.gatewayTimeout,
      };
      if (response.statusCode != HttpStatus.ok) {
        if (retryableStatuses.contains(response.statusCode)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          final retryRequest = await _getUrlWithTimeout(
            httpClient,
            uri,
            _egwHttpConnectTimeout,
          );
          final retryResponse = await _closeRequestWithTimeout(
            retryRequest,
            uri,
            _egwHttpDownloadTimeout,
          );
          if (retryResponse.statusCode != HttpStatus.ok) {
            return _EgwSyncAction(
              status: retryResponse.statusCode == HttpStatus.notFound
                  ? 'needs_review'
                  : 'failed',
              category: task.category,
              code: task.code,
              title: task.title,
              format: task.format,
              targetPath: targetPath,
              sourcePath: url,
              sourceKind: 'remote',
              fileSize: null,
              sha256: null,
              recommendedTargetFolder: task.recommendedTargetFolder,
              reason: 'HTTP ${retryResponse.statusCode} while downloading.',
              recommendedAction: retryResponse.statusCode == HttpStatus.notFound
                  ? 'manifest_correction_needed'
                  : 'retry_later',
              duplicateSourcesIgnored: _duplicateSourceCount(
                task.sourceCandidates,
                chosenSource,
              ),
            );
          }
          await retryResponse
              .pipe(tempFile.openWrite())
              .timeout(_egwHttpDownloadTimeout);
        } else {
          return _EgwSyncAction(
            status: response.statusCode == HttpStatus.notFound
                ? 'needs_review'
                : 'failed',
            category: task.category,
            code: task.code,
            title: task.title,
            format: task.format,
            targetPath: targetPath,
            sourcePath: url,
            sourceKind: 'remote',
            fileSize: null,
            sha256: null,
            recommendedTargetFolder: task.recommendedTargetFolder,
            reason: 'HTTP ${response.statusCode} while downloading.',
            recommendedAction: response.statusCode == HttpStatus.notFound
                ? 'manifest_correction_needed'
                : 'retry_later',
            duplicateSourcesIgnored: _duplicateSourceCount(
              task.sourceCandidates,
              chosenSource,
            ),
          );
        }
      } else {
        await response
            .pipe(tempFile.openWrite())
            .timeout(_egwHttpDownloadTimeout);
      }
      final downloadedHash = await _sha256ForFile(tempFile);
      final downloadedSize = await tempFile.length();
      if (await targetFile.exists()) {
        final currentHash = await _sha256ForFile(targetFile);
        if (currentHash == downloadedHash) {
          await tempFile.delete();
          return _EgwSyncAction(
            status: 'skipped_existing',
            category: task.category,
            code: task.code,
            title: task.title,
            format: task.format,
            targetPath: targetPath,
            sourcePath: url,
            sourceKind: 'remote',
            fileSize: downloadedSize,
            sha256: downloadedHash,
            recommendedTargetFolder: task.recommendedTargetFolder,
            reason: 'Target already existed with the same downloaded hash.',
            duplicateSourcesIgnored: _duplicateSourceCount(
              task.sourceCandidates,
              chosenSource,
            ),
          );
        }
        await tempFile.delete();
        return _EgwSyncAction(
          status: 'conflict',
          category: task.category,
          code: task.code,
          title: task.title,
          format: task.format,
          targetPath: targetPath,
          sourcePath: url,
          sourceKind: 'remote',
          fileSize: downloadedSize,
          sha256: downloadedHash,
          recommendedTargetFolder: task.recommendedTargetFolder,
          reason:
              'Target exists with a different hash from the downloaded file.',
          duplicateSourcesIgnored: _duplicateSourceCount(
            task.sourceCandidates,
            chosenSource,
          ),
        );
      }
      await tempFile.rename(targetFile.path);
      return _EgwSyncAction(
        status: 'downloaded',
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: url,
        sourceKind: 'remote',
        fileSize: downloadedSize,
        sha256: downloadedHash,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason: 'Downloaded from verified manifest URL.',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    } catch (error) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      return _EgwSyncAction(
        status: 'failed',
        category: task.category,
        code: task.code,
        title: task.title,
        format: task.format,
        targetPath: targetPath,
        sourcePath: url,
        sourceKind: 'remote',
        fileSize: null,
        sha256: null,
        recommendedTargetFolder: task.recommendedTargetFolder,
        reason: error.toString(),
        recommendedAction: 'retry_later',
        duplicateSourcesIgnored: _duplicateSourceCount(
          task.sourceCandidates,
          chosenSource,
        ),
      );
    }
  }

  _LocalFileRecord? _chooseSourceCandidate(List<_LocalFileRecord> candidates) {
    if (candidates.isEmpty) return null;
    final legacy = candidates
        .where((file) => file.rootKind != _ScanRootKind.managed.name)
        .toList(growable: false);
    if (legacy.isNotEmpty) {
      legacy.sort((a, b) => a.rootKind.compareTo(b.rootKind));
      return legacy.first;
    }
    final managed = candidates
        .where((file) => file.rootKind == _ScanRootKind.managed.name)
        .toList(growable: false);
    if (managed.isNotEmpty) return managed.first;
    return candidates.first;
  }

  int _duplicateSourceCount(
    List<_LocalFileRecord> candidates,
    _LocalFileRecord? chosen,
  ) {
    if (candidates.length < 2) return 0;
    final hashes = candidates.map((file) => file.sha256).toSet();
    if (hashes.length != 1) return 0;
    if (chosen == null) return candidates.length - 1;
    return candidates.where((file) => file.filePath != chosen.filePath).length;
  }

  Map<String, _EgwCategorySummary> _summarizeCategories(
    List<_CollectionDefinition> collections,
    List<_EgwManifestItem> manifestItems,
    List<_LocalFileRecord> localFiles,
    List<_EgwItemAudit> audits,
  ) {
    final summaries = <String, _EgwCategorySummary>{};
    for (final item in manifestItems) {
      summaries.putIfAbsent(
        item.category,
        () => _EgwCategorySummary(
          category: item.category,
          displayName: item.displayName,
          recommendedTargetFolder: _recommendedFolderFor(item.category),
        ),
      );
    }
    for (final file in localFiles) {
      summaries.putIfAbsent(
        file.category,
        () => _EgwCategorySummary(
          category: file.category,
          displayName: file.category.replaceAll('_', ' '),
          recommendedTargetFolder: _recommendedFolderFor(file.category),
        ),
      );
    }
    for (final summary in summaries.values) {
      final manifestForCategory = manifestItems
          .where((item) => item.category == summary.category)
          .toList(growable: false);
      final localForCategory = localFiles
          .where((file) => file.category == summary.category)
          .toList(growable: false);
      final auditsForCategory = audits
          .where((audit) => audit.category == summary.category)
          .toList(growable: false);
      summary.manifestItems = manifestForCategory.length;
      summary.localFiles = localForCategory.length;
      summary.presentItems = auditsForCategory
          .where((audit) => audit.present)
          .length;
      summary.presentLegacyLocationItems = auditsForCategory
          .where((audit) => audit.presentLegacyLocation)
          .length;
      summary.needsReviewItems = auditsForCategory
          .where((audit) => audit.auditStatus == 'needs_review')
          .length;
      summary.excludedFromApplyItems = auditsForCategory
          .where((audit) => !audit.applyEligible)
          .length;
      summary.missingItems = auditsForCategory
          .where(
            (audit) =>
                !audit.present &&
                !audit.presentLegacyLocation &&
                audit.applyEligible,
          )
          .length;
      summary.indexedFiles = localForCategory
          .where((file) => file.indexed)
          .length;
      summary.duplicateFiles = localForCategory.fold<int>(
        0,
        (count, file) => count + (file.duplicateGroup.isNotEmpty ? 0 : 0),
      );
      summary.localPresentFiles = localForCategory
          .where((file) => file.isManaged)
          .length;
    }
    return summaries;
  }

  bool _applyEligibleFor(String category, String code) {
    if (category == 'EGW_Commentaries' &&
        _commentariesNeedsReviewCodes.contains(code)) {
      return false;
    }
    return true;
  }

  String _auditStatusFor(String category, String code) {
    return _applyEligibleFor(category, code) ? 'eligible' : 'needs_review';
  }

  String _importStatusFor(String category, String code) {
    return _applyEligibleFor(category, code) ? 'audited' : 'needs_review';
  }

  String _recommendedActionFor(String category, String code) {
    return _applyEligibleFor(category, code)
        ? 'include_in_apply'
        : 'manifest_correction_needed';
  }

  String? _reviewReasonFor(String category, String code) {
    if (_applyEligibleFor(category, code)) return null;
    if (category == 'EGW_Commentaries') {
      return 'Known EGW Writings 404 entry; keep visible in audit, but exclude from apply until manifest is corrected.';
    }
    return 'Item requires manual review before apply.';
  }

  String? _duplicateRiskFor(_EgwManifestItem item) {
    if (item.category != 'EGW_Manuscript_Releases') return null;
    const duplicates = <String, String>{
      'MR728': 'duplicates content inside 9MR',
      'MR760': 'duplicates content inside 9MR',
      'MR852': 'duplicates content inside 11MR',
      'MR926': 'duplicates content inside 12MR',
      'MR1033': 'duplicates content inside 13MR',
    };
    return duplicates[item.code];
  }

  String _recommendedFolderFor(String category) {
    final collection = _collectionByCategory(category);
    if (collection == null) {
      return 'ePubs/Research/$category';
    }
    if (collection.folderRoot == 'Commentaries') {
      return 'ePubs/Commentaries/${collection.folderName}';
    }
    return 'ePubs/${collection.folderRoot}/${collection.folderName}';
  }

  _CollectionDefinition? _collectionByCategory(String category) {
    final config = _ManifestConfig.defaultConfig();
    for (final collection in config.collections) {
      if (collection.category == category) return collection;
    }
    return null;
  }

  bool _shouldSkipPath(String relativePath) {
    final normalized = _normalizePath(relativePath);
    return normalized.contains('/user/') ||
        normalized.contains('/download_reports/') ||
        normalized.contains('/legacy_migration_reports/') ||
        normalized.contains('/backups/') ||
        normalized.contains('/legacybackup/') ||
        normalized.contains('test_downloads/') ||
        normalized.contains('/cache/') ||
        normalized.contains('cache/') ||
        normalized.contains('/temp/') ||
        normalized.contains('temp/') ||
        normalized.contains('/_quarantine_duplicates/');
  }

  String? _categoryForRelativePath(String relativePath) {
    final normalized = _normalizePath(relativePath);
    if (normalized.contains('/epubs/research/egw_books/') ||
        normalized.contains('/pdfs/research/egw_books/')) {
      return 'EGW_Books';
    }
    if (normalized.contains('/epubs/research/egw_devotionals/') ||
        normalized.contains('/pdfs/research/egw_devotionals/')) {
      return 'EGW_Devotionals';
    }
    if (normalized.contains('/epubs/commentaries/egw_commentaries/') ||
        normalized.contains('/pdfs/commentaries/egw_commentaries/')) {
      return 'EGW_Commentaries';
    }
    if (normalized.contains('/epubs/research/egw_letters_manuscripts/') ||
        normalized.contains('/pdfs/research/egw_letters_manuscripts/')) {
      return 'EGW_Letters_Manuscripts';
    }
    if (normalized.contains('/epubs/research/egw_manuscript_releases/') ||
        normalized.contains('/pdfs/research/egw_manuscript_releases/')) {
      return 'EGW_Manuscript_Releases';
    }
    if (normalized.contains('/epubs/research/egw_misc_collections/') ||
        normalized.contains('/pdfs/research/egw_misc_collections/')) {
      return 'EGW_Misc_Collections';
    }
    if (normalized.contains('/epubs/research/egw_pamphlets/') ||
        normalized.contains('/pdfs/research/egw_pamphlets/')) {
      return 'EGW_Pamphlets';
    }
    if (normalized.contains('/epubs/research/egw_periodicals/') ||
        normalized.contains('/pdfs/research/egw_periodicals/')) {
      return 'EGW_Periodicals';
    }
    if (normalized.contains('/epubs/research/egw_modern_english/') ||
        normalized.contains('/pdfs/research/egw_modern_english/')) {
      return 'EGW_Modern_English';
    }
    if (normalized.contains('/epubs/research/egw_conflict/') ||
        normalized.contains('/pdfs/research/egw_conflict/')) {
      return 'EGW_Conflict';
    }
    return null;
  }

  String? _codeFromRelativePath(String relativePath) {
    final fileName = p.basename(relativePath);
    return _codeFromFileName(fileName);
  }

  String? _codeFromFileName(String value) {
    final stem = p.basenameWithoutExtension(value).trim();
    final match = RegExp(
      r'^en_([A-Za-z0-9]+(?:\.\d+)?)(?:-[A-Za-z0-9]+)?(?:\s*\(\d+\))?$',
      caseSensitive: false,
    ).firstMatch(stem);
    return match?.group(1);
  }

  Future<String> _sha256ForFile(File file) async {
    return sha256
        .bind(file.openRead())
        .first
        .then((digest) => digest.toString());
  }

  Future<String> _fetchText(HttpClient client, String url) async {
    final uri = Uri.parse(url);
    const retryableStatuses = <int>{
      HttpStatus.badGateway,
      HttpStatus.serviceUnavailable,
      HttpStatus.gatewayTimeout,
    };
    for (var attempt = 0; attempt < 3; attempt++) {
      final request = await _getUrlWithTimeout(
        client,
        uri,
        _egwHttpConnectTimeout,
      );
      final response = await _closeRequestWithTimeout(
        request,
        uri,
        _egwHttpResponseTimeout,
      );
      if (response.statusCode == HttpStatus.ok) {
        return response
            .transform(utf8.decoder)
            .join()
            .timeout(_egwHttpResponseTimeout);
      }
      if (!retryableStatuses.contains(response.statusCode) || attempt == 2) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
    }
    throw HttpException('HTTP 503', uri: uri);
  }

  Future<_PageSummary> _fetchPageSummary(HttpClient client, String url) async {
    final uri = Uri.parse(url);
    final request = await _getUrlWithTimeout(
      client,
      uri,
      _egwHttpConnectTimeout,
    );
    final response = await _closeRequestWithTimeout(
      request,
      uri,
      _egwHttpResponseTimeout,
    );
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_egwHttpResponseTimeout);
    final finalUrl = response.redirects.isNotEmpty
        ? response.redirects.last.location.toString()
        : url;
    final hrefs = _extractHrefAttributes(body);
    final discoveryUrls = _extractDiscoveryUrlCandidates(body, url);
    final normalizedHrefs = hrefs
        .map((href) => href.trim())
        .where((href) => href.isNotEmpty)
        .toList(growable: false);
    final counts = _countHrefPatterns(normalizedHrefs);
    return _PageSummary(
      url: url,
      finalUrl: finalUrl,
      statusCode: response.statusCode,
      contentType: response.headers.contentType?.mimeType,
      bodyLength: body.length,
      preview: _sanitizePreview(body),
      hrefs: normalizedHrefs,
      discoveryUrls: discoveryUrls,
      patternCounts: counts,
    );
  }

  List<String> _extractHrefAttributes(String html) {
    final hrefs = <String>[];
    for (final match in RegExp(
      "href\\s*=\\s*(\"([^\"]*)\"|'([^']*)')",
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html)) {
      final href = match.group(2) ?? match.group(3) ?? '';
      hrefs.add(href);
    }
    return hrefs;
  }

  List<String> _extractDiscoveryUrlCandidates(String html, String baseUrl) {
    final urls = <String>{};

    void addCandidate(String candidate) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) return;
      try {
        final resolved = _normalizeDiscoveryUrl(
          Uri.parse(baseUrl).resolve(trimmed).toString(),
        );
        final uri = Uri.tryParse(resolved);
        if (uri == null) return;
        if (!_allowedEgwHosts.contains(uri.host.toLowerCase())) return;
        urls.add(resolved);
      } catch (_) {
        // Ignore malformed candidate URLs.
      }
    }

    for (final href in _extractHrefAttributes(html)) {
      addCandidate(href);
    }

    for (final match in RegExp(
      r'''((?:https?://[^"'<>\s]+)?/(?:allCollection/en/\d+(?:\.\d+)?|book/b\d+(?:\.\d+)?))''',
      caseSensitive: false,
    ).allMatches(html)) {
      final candidate = match.group(1);
      if (candidate == null || candidate.trim().isEmpty) continue;
      addCandidate(candidate);
    }

    return urls.toList(growable: false);
  }

  Map<String, int> _countHrefPatterns(List<String> hrefs) {
    final counts = <String, int>{
      '/allCollection/': 0,
      '/book/': 0,
      '/publicationtoc.php': 0,
      '/folders/': 0,
      '/epub/': 0,
      '/pdf/': 0,
      '.epub': 0,
      '.pdf': 0,
    };
    for (final href in hrefs) {
      for (final key in counts.keys) {
        if (href.contains(key)) {
          counts[key] = counts[key]! + 1;
        }
      }
    }
    return counts;
  }

  String _sanitizePreview(String body) {
    final collapsed = body
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .trim();
    if (collapsed.length <= 500) return collapsed;
    return collapsed.substring(0, 500);
  }

  Future<HttpClientRequest> _getUrlWithTimeout(
    HttpClient client,
    Uri uri,
    Duration timeout,
  ) async {
    try {
      return await client.getUrl(uri).timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'Timed out connecting to $uri after ${timeout.inSeconds}s',
        timeout,
      );
    }
  }

  Future<HttpClientResponse> _closeRequestWithTimeout(
    HttpClientRequest request,
    Uri uri,
    Duration timeout,
  ) async {
    try {
      return await request.close().timeout(timeout);
    } on TimeoutException {
      request.abort();
      throw TimeoutException(
        'Timed out waiting for headers from $uri after ${timeout.inSeconds}s',
        timeout,
      );
    }
  }

  String? _extractPageTitle(String html) {
    final titleMatch = RegExp(
      r'<title>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    final title = _cleanHtml(titleMatch?.group(1) ?? '');
    if (title.isEmpty) return null;
    return title
        .replaceAll(
          RegExp(r'\s+\|\s+EGW Writings.*$', caseSensitive: false),
          '',
        )
        .trim();
  }

  String _collectionLabelForPage(String html, String pageUrl) {
    final title = _extractPageTitle(html);
    if (title != null && title.trim().isNotEmpty) {
      final cleaned = title.trim();
      if (!RegExp(r'^(English|EGW Writings)$', caseSensitive: false)
          .hasMatch(cleaned)) {
        return cleaned;
      }
    }
    final uri = Uri.tryParse(pageUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = uri.pathSegments.last;
      if (lastSegment.isNotEmpty) {
        return _cleanHtml(lastSegment);
      }
    }
    return '';
  }

  String? _extractBookCode(String html) {
    final codeMatch = RegExp(
      r'Book code:\s*([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(html);
    return codeMatch?.group(1);
  }

  String _extractCodeFromUrl(String url) {
    final match = RegExp(
      r'/book/(?:b)?([A-Za-z0-9]+(?:\.\d+)?)(?:/|$)',
      caseSensitive: false,
    ).firstMatch(url);
    return match == null ? '' : match.group(1)!;
  }

  int? _extractPageCount(String html) {
    final match = RegExp(
      r'(\d+)\s+Pages',
      caseSensitive: false,
    ).firstMatch(html);
    return int.tryParse(match?.group(1) ?? '');
  }

  int? _extractYear(String html) {
    final match = RegExp(
      r'\((1[89]\d{2}|20\d{2})\)',
      caseSensitive: false,
    ).firstMatch(html);
    return int.tryParse(match?.group(1) ?? '');
  }

  String _cleanHtml(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

List<_ScanRootSpec> _defaultAuditScanRoots(String managedRootPath) {
  final normalizedManagedRoot = p.normalize(managedRootPath.trim());
  final managedRoot = _ScanRootSpec(
    label: 'managed_v2',
    path: normalizedManagedRoot,
    kind: _ScanRootKind.managed,
  );
  final siblingRoots = <_ScanRootSpec>[
    for (final candidate in _defaultLegacyScanPaths)
      if (p.normalize(candidate) != normalizedManagedRoot)
        _ScanRootSpec(
          label: p.basename(candidate),
          path: p.normalize(candidate),
          kind: candidate == _defaultLegacyScanPaths.first
              ? _ScanRootKind.repo
              : _ScanRootKind.legacy,
        ),
  ];
  return <_ScanRootSpec>[managedRoot, ...siblingRoots];
}

class _ManifestConfig {
  const _ManifestConfig({required this.collections});

  final List<_CollectionDefinition> collections;

  factory _ManifestConfig.defaultConfig() {
    return const _ManifestConfig(
      collections: <_CollectionDefinition>[
        _CollectionDefinition(
          category: 'EGW_Books',
          displayName: 'Books',
          pageUrl: 'https://text.egwwritings.org/allCollection/4',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/4',
          folderRoot: 'Research',
          folderName: 'EGW_Books',
          modern: false,
          adapted: false,
          searchScope: 'Books',
        ),
        _CollectionDefinition(
          category: 'EGW_Devotionals',
          displayName: 'Devotionals',
          pageUrl: 'https://text.egwwritings.org/allCollection/1227',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/1227',
          folderRoot: 'Research',
          folderName: 'EGW_Devotionals',
          modern: false,
          adapted: false,
          searchScope: 'Devotionals',
        ),
        _CollectionDefinition(
          category: 'EGW_Commentaries',
          displayName: 'Commentaries',
          pageUrl: 'https://text.egwwritings.org/allCollection/1371',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/1371',
          folderRoot: 'Commentaries',
          folderName: 'EGW_Commentaries',
          modern: false,
          adapted: false,
          searchScope: 'Commentaries',
        ),
        _CollectionDefinition(
          category: 'EGW_Letters_Manuscripts',
          displayName: 'Letters & Manuscripts',
          pageUrl: 'https://text.egwwritings.org/allCollection/1277',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/1277',
          folderRoot: 'Research',
          folderName: 'EGW_Letters_Manuscripts',
          modern: false,
          adapted: false,
          searchScope: 'Letters & Manuscripts',
        ),
        _CollectionDefinition(
          category: 'EGW_Manuscript_Releases',
          displayName: 'Manuscript Releases',
          pageUrl: 'https://text.egwwritings.org/allCollection/en/1376',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/en/1376',
          folderRoot: 'Research',
          folderName: 'EGW_Manuscript_Releases',
          modern: false,
          adapted: false,
          searchScope: 'Manuscript Releases',
        ),
        _CollectionDefinition(
          category: 'EGW_Misc_Collections',
          displayName: 'Misc Collections',
          pageUrl: 'https://text.egwwritings.org/allCollection/en/10',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/en/10',
          folderRoot: 'Research',
          folderName: 'EGW_Misc_Collections',
          modern: false,
          adapted: false,
          searchScope: 'Misc Collections',
        ),
        _CollectionDefinition(
          category: 'EGW_Pamphlets',
          displayName: 'Pamphlets',
          pageUrl: 'https://text.egwwritings.org/allCollection/en/8',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/en/8',
          folderRoot: 'Research',
          folderName: 'EGW_Pamphlets',
          modern: false,
          adapted: false,
          searchScope: 'Pamphlets',
        ),
        _CollectionDefinition(
          category: 'EGW_Periodicals',
          displayName: 'Periodicals',
          pageUrl: 'https://text.egwwritings.org/allCollection/en/5',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/en/5',
          folderRoot: 'Research',
          folderName: 'EGW_Periodicals',
          modern: false,
          adapted: false,
          searchScope: 'Periodicals',
        ),
        _CollectionDefinition(
          category: 'EGW_Modern_English',
          displayName: 'Modern English',
          pageUrl: 'https://m.egwwritings.org/en/folders/218',
          fallbackPageUrl: 'https://m.egwwritings.org/en/folders/218',
          folderRoot: 'Research',
          folderName: 'EGW_Modern_English',
          modern: true,
          adapted: true,
          searchScope: 'Modern',
        ),
        _CollectionDefinition(
          category: 'EGW_Conflict',
          displayName: 'The Conflict',
          pageUrl: 'https://text.egwwritings.org/allCollection/1469',
          fallbackPageUrl: 'https://next.egwwritings.org/allCollection/1469',
          folderRoot: 'Research',
          folderName: 'EGW_Conflict',
          modern: false,
          adapted: false,
          searchScope: 'Conflict',
        ),
      ],
    );
  }

  factory _ManifestConfig.fromJson(Map<String, Object?> json) {
    final collectionsRaw = json['collections'];
    final collections = <_CollectionDefinition>[];
    if (collectionsRaw is List) {
      for (final entry in collectionsRaw) {
        if (entry is Map) {
          collections.add(
            _CollectionDefinition.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }
    return _ManifestConfig(collections: collections);
  }
}

class _CollectionDefinition {
  const _CollectionDefinition({
    required this.category,
    required this.displayName,
    required this.pageUrl,
    required this.fallbackPageUrl,
    required this.folderRoot,
    required this.folderName,
    required this.modern,
    required this.adapted,
    required this.searchScope,
  });

  final String category;
  final String displayName;
  final String pageUrl;
  final String fallbackPageUrl;
  final String folderRoot;
  final String folderName;
  final bool modern;
  final bool adapted;
  final String searchScope;

  factory _CollectionDefinition.fromJson(Map<String, Object?> json) {
    return _CollectionDefinition(
      category: json['category']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      pageUrl: json['collection_page_url']?.toString() ?? '',
      fallbackPageUrl: json['fallback_collection_page_url']?.toString() ?? '',
      folderRoot: json['folder_root']?.toString() ?? 'Research',
      folderName: json['folder_name']?.toString() ?? '',
      modern: json['modern'] is bool
          ? json['modern'] as bool
          : json['modern']?.toString().toLowerCase() == 'true',
      adapted: json['adapted'] is bool
          ? json['adapted'] as bool
          : json['adapted']?.toString().toLowerCase() == 'true',
      searchScope: json['search_scope']?.toString() ?? '',
    );
  }
}

class _EgwManifestItem {
  const _EgwManifestItem({
    required this.category,
    required this.displayName,
    this.categoryPath = '',
    this.topCategory = '',
    required this.title,
    required this.code,
    required this.language,
    required this.year,
    required this.pages,
    this.collectionUrl = '',
    this.itemPageUrl = '',
    required this.egwPageUrl,
    this.verifiedEpubUrl = '',
    this.verifiedPdfUrl = '',
    this.epubFilename = '',
    this.pdfFilename = '',
    this.verifiedEpubSize,
    this.verifiedPdfSize,
    this.verifiedEpubSha256 = '',
    this.verifiedPdfSha256 = '',
    this.lastVerifiedAt = '',
    this.discoveryStatus = 'unknown',
    required this.epubUrl,
    required this.pdfUrl,
    this.availableFormats = const <String>[],
    required this.targetEpubRelativePath,
    required this.targetPdfRelativePath,
    required this.modern,
    required this.adapted,
    required this.originalOrAdaptedLabel,
    required this.duplicateGroup,
    required this.importStatus,
    this.applyEligible = true,
    this.auditStatus = 'eligible',
    this.recommendedAction = 'include_in_apply',
    this.reviewReason,
    required this.searchScope,
  });

  final String category;
  final String displayName;
  final String categoryPath;
  final String topCategory;
  final String title;
  final String code;
  final String language;
  final int? year;
  final int? pages;
  final String collectionUrl;
  final String itemPageUrl;
  final String egwPageUrl;
  final String verifiedEpubUrl;
  final String verifiedPdfUrl;
  final String epubFilename;
  final String pdfFilename;
  final int? verifiedEpubSize;
  final int? verifiedPdfSize;
  final String verifiedEpubSha256;
  final String verifiedPdfSha256;
  final String lastVerifiedAt;
  final String discoveryStatus;
  final String epubUrl;
  final String pdfUrl;
  final List<String> availableFormats;
  final String targetEpubRelativePath;
  final String targetPdfRelativePath;
  final bool modern;
  final bool adapted;
  final String originalOrAdaptedLabel;
  final String? duplicateGroup;
  final String importStatus;
  final bool applyEligible;
  final String auditStatus;
  final String recommendedAction;
  final String? reviewReason;
  final String searchScope;

  String get sourceFamily => 'EGW';

  String get stableSourceId {
    final identityCode = code.trim().isEmpty ? 'nocode' : code.trim();
    final pageId = itemPageUrl.trim().isNotEmpty
        ? itemPageUrl.trim()
        : egwPageUrl.trim();
    return '$sourceFamily|$category|$identityCode|$pageId';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category,
    'display_name': displayName,
    'category_path': categoryPath,
    'top_category': topCategory,
    'title': title,
    'code': code,
    'language': language,
    'year': year,
    'pages': pages,
    'source_family': sourceFamily,
    'stable_source_id': stableSourceId,
    'collection_url': collectionUrl,
    'item_page_url': itemPageUrl,
    'egw_page_url': egwPageUrl,
    'verified_epub_url': verifiedEpubUrl,
    'verified_pdf_url': verifiedPdfUrl,
    'epub_filename': epubFilename,
    'pdf_filename': pdfFilename,
    'verified_epub_size': verifiedEpubSize,
    'verified_pdf_size': verifiedPdfSize,
    'verified_epub_sha256': verifiedEpubSha256,
    'verified_pdf_sha256': verifiedPdfSha256,
    'last_verified_at': lastVerifiedAt,
    'discovery_status': discoveryStatus,
    'epub_url': epubUrl,
    'pdf_url': pdfUrl,
    'available_formats': availableFormats,
    'target_epub_relative_path': targetEpubRelativePath,
    'target_pdf_relative_path': targetPdfRelativePath,
    'modern': modern,
    'adapted': adapted,
    'original_or_adapted_label': originalOrAdaptedLabel,
    'duplicate_group': duplicateGroup,
    'import_status': importStatus,
    'apply_eligible': applyEligible,
    'audit_status': auditStatus,
    'recommended_action': recommendedAction,
    'review_reason': reviewReason,
    'search_scope': searchScope,
  };
}

class _EgwItemAudit {
  _EgwItemAudit({
    required this.category,
    required this.code,
    required this.title,
    required this.applyEligible,
    required this.auditStatus,
    required this.recommendedAction,
    required this.reviewReason,
    required this.present,
    required this.presentLegacyLocation,
    required this.availableToCopy,
    required this.epubPresent,
    required this.pdfPresent,
    required this.missingTargets,
    required this.localMatches,
    required this.recommendedTargetFolder,
    required this.duplicateRisk,
  });

  final String category;
  final String code;
  final String title;
  final bool applyEligible;
  final String auditStatus;
  final String recommendedAction;
  final String? reviewReason;
  final bool present;
  final bool presentLegacyLocation;
  final bool availableToCopy;
  final bool epubPresent;
  final bool pdfPresent;
  final List<String> missingTargets;
  final List<_LocalFileRecord> localMatches;
  final String recommendedTargetFolder;
  final String? duplicateRisk;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category,
    'code': code,
    'title': title,
    'apply_eligible': applyEligible,
    'audit_status': auditStatus,
    'recommended_action': recommendedAction,
    'review_reason': reviewReason,
    'present': present,
    'present_legacy_location': presentLegacyLocation,
    'available_to_copy': availableToCopy,
    'epub_present': epubPresent,
    'pdf_present': pdfPresent,
    'missing_targets': missingTargets,
    'local_matches': localMatches
        .map((item) => item.toJson())
        .toList(growable: false),
    'recommended_target_folder': recommendedTargetFolder,
    'duplicate_risk': duplicateRisk,
  };
}

class _EgwCategorySummary {
  _EgwCategorySummary({
    required this.category,
    required this.displayName,
    required this.recommendedTargetFolder,
  });

  final String category;
  final String displayName;
  final String recommendedTargetFolder;
  int manifestItems = 0;
  int localFiles = 0;
  int presentItems = 0;
  int presentLegacyLocationItems = 0;
  int needsReviewItems = 0;
  int excludedFromApplyItems = 0;
  int missingItems = 0;
  int indexedFiles = 0;
  int duplicateFiles = 0;
  int localPresentFiles = 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'category': category,
    'display_name': displayName,
    'recommended_target_folder': recommendedTargetFolder,
    'manifest_items': manifestItems,
    'local_files': localFiles,
    'present_items': presentItems,
    'present_legacy_location_items': presentLegacyLocationItems,
    'needs_review_items': needsReviewItems,
    'excluded_from_apply_items': excludedFromApplyItems,
    'missing_items': missingItems,
    'indexed_files': indexedFiles,
    'duplicate_files': duplicateFiles,
    'local_present_files': localPresentFiles,
  };
}

class _EgwAuditSummary {
  _EgwAuditSummary({
    required this.crawlRootUrl,
    required this.shelfTitle,
    required this.directBookLinksFound,
    required this.childCollectionDetectedCount,
    required this.childCollectionsDetected,
    required this.branchCategoryPagesVisited,
    required this.finalItemPagesVisited,
    required this.discoveredCategoryCount,
    required this.discoveredCategories,
    required this.verifiedEpubCount,
    required this.verifiedPdfCount,
    required this.verifiedEnglishEpubCount,
    required this.verifiedEnglishPdfCount,
    required this.verifiedEpubPdfCount,
    required this.verifiedPdfOnlyCount,
    required this.nonEnglishExcludedCount,
    required this.noEpubFoundCount,
    required this.noDownloadLinksFoundCount,
    required this.pageUnavailableCount,
    required this.manifestItems,
    required this.localFiles,
    required this.presentItems,
    required this.presentLegacyLocationItems,
    required this.availableToCopyItems,
    required this.needsReviewItems,
    required this.excludedFromApplyItems,
    required this.trueMissingItems,
    required this.duplicateSameHashCount,
    required this.duplicateSameCodeDifferentLocationCount,
    required this.conflictSameCodeDifferentHashCount,
    required this.conflictTargetExistsDifferentHashCount,
    required this.unmatchedLocalFileCount,
    required this.indexedFiles,
  });

  final String crawlRootUrl;
  final String shelfTitle;
  final int directBookLinksFound;
  final int childCollectionDetectedCount;
  final List<_ChildCollectionRecord> childCollectionsDetected;
  final int branchCategoryPagesVisited;
  final int finalItemPagesVisited;
  final int discoveredCategoryCount;
  final List<String> discoveredCategories;
  final int verifiedEpubCount;
  final int verifiedPdfCount;
  final int verifiedEnglishEpubCount;
  final int verifiedEnglishPdfCount;
  final int verifiedEpubPdfCount;
  final int verifiedPdfOnlyCount;
  final int nonEnglishExcludedCount;
  final int noEpubFoundCount;
  final int noDownloadLinksFoundCount;
  final int pageUnavailableCount;
  final int manifestItems;
  final int localFiles;
  final int presentItems;
  final int presentLegacyLocationItems;
  final int availableToCopyItems;
  final int needsReviewItems;
  final int excludedFromApplyItems;
  final int trueMissingItems;
  final int duplicateSameHashCount;
  final int duplicateSameCodeDifferentLocationCount;
  final int conflictSameCodeDifferentHashCount;
  final int conflictTargetExistsDifferentHashCount;
  final int unmatchedLocalFileCount;
  final int indexedFiles;

  int get missingItems => trueMissingItems;
  int get duplicateFiles =>
      duplicateSameHashCount + duplicateSameCodeDifferentLocationCount;
  int get conflicts =>
      conflictSameCodeDifferentHashCount +
      conflictTargetExistsDifferentHashCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'crawl_root_url': crawlRootUrl,
    'shelf_title': shelfTitle,
    'direct_book_links_found': directBookLinksFound,
    'child_collection_detected_count': childCollectionDetectedCount,
    'child_collections_detected': childCollectionsDetected
        .map((item) => item.toJson())
        .toList(growable: false),
    'branch_category_pages_visited': branchCategoryPagesVisited,
    'final_item_pages_visited': finalItemPagesVisited,
    'discovered_category_count': discoveredCategoryCount,
    'discovered_categories': discoveredCategories,
    'verified_epub_count': verifiedEpubCount,
    'verified_pdf_count': verifiedPdfCount,
    'verified_english_epub_count': verifiedEnglishEpubCount,
    'verified_english_pdf_count': verifiedEnglishPdfCount,
    'verified_epub_pdf_count': verifiedEpubPdfCount,
    'verified_pdf_only_count': verifiedPdfOnlyCount,
    'non_english_excluded_count': nonEnglishExcludedCount,
    'no_epub_found_count': noEpubFoundCount,
    'no_download_links_found_count': noDownloadLinksFoundCount,
    'page_unavailable_count': pageUnavailableCount,
    'manifest_items': manifestItems,
    'local_files': localFiles,
    'present_items': presentItems,
    'present_legacy_location_items': presentLegacyLocationItems,
    'available_to_copy_items': availableToCopyItems,
    'needs_review_items': needsReviewItems,
    'excluded_from_apply_items': excludedFromApplyItems,
    'true_missing_items': trueMissingItems,
    'duplicate_same_hash_count': duplicateSameHashCount,
    'duplicate_same_code_different_location_count':
        duplicateSameCodeDifferentLocationCount,
    'conflict_same_code_different_hash_count':
        conflictSameCodeDifferentHashCount,
    'conflict_target_exists_different_hash_count':
        conflictTargetExistsDifferentHashCount,
    'unmatched_local_file_count': unmatchedLocalFileCount,
    'indexed_files': indexedFiles,
  };
}

class _EgwAuditReport {
  _EgwAuditReport({
    required this.generatedAt,
    required this.rootPath,
    required this.dbPath,
    required this.manifestPath,
    required this.scannedRoots,
    required this.summary,
    required this.categorySummaries,
    required this.localFiles,
    required this.manifestItems,
    required this.itemAudits,
    required this.duplicateSameHashGroups,
    required this.duplicateSameCodeDifferentLocationGroups,
    required this.conflictSameCodeDifferentHashGroups,
    required this.conflictTargetExistsDifferentHashGroups,
    required this.unmatchedLocalFiles,
    required this.warnings,
    required this.reportFilePath,
  });

  final DateTime generatedAt;
  final String rootPath;
  final String dbPath;
  final String manifestPath;
  final List<_ScanRootSummary> scannedRoots;
  final _EgwAuditSummary summary;
  final Map<String, _EgwCategorySummary> categorySummaries;
  final List<_LocalFileRecord> localFiles;
  final List<_EgwManifestItem> manifestItems;
  final List<_EgwItemAudit> itemAudits;
  final List<_AuditFindingGroup> duplicateSameHashGroups;
  final List<_AuditFindingGroup> duplicateSameCodeDifferentLocationGroups;
  final List<_AuditFindingGroup> conflictSameCodeDifferentHashGroups;
  final List<_AuditFindingGroup> conflictTargetExistsDifferentHashGroups;
  final List<_LocalFileRecord> unmatchedLocalFiles;
  final List<String> warnings;
  final String reportFilePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'generated_at': generatedAt.toIso8601String(),
    'root_path': rootPath,
    'db_path': dbPath,
    'manifest_path': manifestPath,
    'scanned_roots': scannedRoots
        .map((item) => item.toJson())
        .toList(growable: false),
    'summary': summary.toJson(),
    'category_summaries': categorySummaries.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'warnings': warnings,
    'local_files': localFiles
        .map((item) => item.toJson())
        .toList(growable: false),
    'manifest_items': manifestItems
        .map((item) => item.toJson())
        .toList(growable: false),
    'item_audits': itemAudits
        .map((item) => item.toJson())
        .toList(growable: false),
    'duplicate_same_hash_groups': duplicateSameHashGroups
        .map((item) => item.toJson())
        .toList(growable: false),
    'duplicate_same_code_different_location_groups':
        duplicateSameCodeDifferentLocationGroups
            .map((item) => item.toJson())
            .toList(growable: false),
    'conflict_same_code_different_hash_groups':
        conflictSameCodeDifferentHashGroups
            .map((item) => item.toJson())
            .toList(growable: false),
    'conflict_target_exists_different_hash_groups':
        conflictTargetExistsDifferentHashGroups
            .map((item) => item.toJson())
            .toList(growable: false),
    'unmatched_local_files': unmatchedLocalFiles
        .map((item) => item.toJson())
        .toList(growable: false),
    'report_file_path': reportFilePath,
  };
}

class _EgwApplySummary {
  _EgwApplySummary({
    required this.indexingDeferred,
    required this.refusedDueToConflicts,
    required this.needsReviewCount,
    required this.excludedFromApplyCount,
  });

  final bool indexingDeferred;
  final bool refusedDueToConflicts;
  int totalTasks = 0;
  int copiedCount = 0;
  int downloadedCount = 0;
  int skippedExistingCount = 0;
  int skippedDuplicateCount = 0;
  int needsReviewCount = 0;
  int excludedFromApplyCount = 0;
  int failedCount = 0;
  int conflictCount = 0;
  int dryRunCount = 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'indexing_deferred': indexingDeferred,
    'refused_due_to_conflicts': refusedDueToConflicts,
    'total_tasks': totalTasks,
    'copied_count': copiedCount,
    'downloaded_count': downloadedCount,
    'skipped_existing_count': skippedExistingCount,
    'skipped_duplicate_count': skippedDuplicateCount,
    'needs_review_count': needsReviewCount,
    'excluded_from_apply_count': excludedFromApplyCount,
    'failed_count': failedCount,
    'conflict_count': conflictCount,
    'dry_run_count': dryRunCount,
  };
}

class _EgwApplyReport {
  _EgwApplyReport({
    required this.generatedAt,
    required this.rootPath,
    required this.dbPath,
    required this.manifestPath,
    required this.auditReportPath,
    required this.scannedRoots,
    required this.summary,
    required this.actions,
    required this.warnings,
    required this.reportFilePath,
  });

  final DateTime generatedAt;
  final String rootPath;
  final String dbPath;
  final String manifestPath;
  final String auditReportPath;
  final List<_ScanRootSummary> scannedRoots;
  final _EgwApplySummary summary;
  final List<_EgwSyncAction> actions;
  final List<String> warnings;
  final String reportFilePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'generated_at': generatedAt.toIso8601String(),
    'root_path': rootPath,
    'db_path': dbPath,
    'manifest_path': manifestPath,
    'audit_report_path': auditReportPath,
    'scanned_roots': scannedRoots
        .map((item) => item.toJson())
        .toList(growable: false),
    'summary': summary.toJson(),
    'warnings': warnings,
    'actions': actions.map((item) => item.toJson()).toList(growable: false),
    'report_file_path': reportFilePath,
  };
}

class _EgwSyncAction {
  _EgwSyncAction({
    required this.status,
    required this.category,
    required this.code,
    required this.title,
    required this.format,
    required this.targetPath,
    required this.sourcePath,
    required this.sourceKind,
    required this.fileSize,
    required this.sha256,
    required this.recommendedTargetFolder,
    required this.reason,
    this.recommendedAction = 'skip',
    this.duplicateSourcesIgnored = 0,
  });

  final String status;
  final String category;
  final String code;
  final String title;
  final String format;
  final String targetPath;
  final String sourcePath;
  final String sourceKind;
  final int? fileSize;
  final String? sha256;
  final String recommendedTargetFolder;
  final String reason;
  final String recommendedAction;
  final int duplicateSourcesIgnored;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'category': category,
    'code': code,
    'title': title,
    'format': format,
    'target_path': targetPath,
    'source_path': sourcePath,
    'source_kind': sourceKind,
    'file_size': fileSize,
    'sha256': sha256,
    'recommended_target_folder': recommendedTargetFolder,
    'reason': reason,
    'recommended_action': recommendedAction,
    'duplicate_sources_ignored': duplicateSourcesIgnored,
  };
}

class _EgwApplyTask {
  const _EgwApplyTask({
    required this.category,
    required this.code,
    required this.title,
    required this.format,
    required this.targetRelativePath,
    required this.sourceUrl,
    required this.managedTarget,
    required this.sourceCandidates,
    required this.recommendedTargetFolder,
  });

  final String category;
  final String code;
  final String title;
  final String format;
  final String targetRelativePath;
  final String sourceUrl;
  final _LocalFileRecord? managedTarget;
  final List<_LocalFileRecord> sourceCandidates;
  final String recommendedTargetFolder;
}

class _CollectionDiscovery {
  const _CollectionDiscovery({
    required this.items,
    required this.usedFallbackPage,
  });

  final List<_EgwManifestItem> items;
  final bool usedFallbackPage;
}

class _EnglishTreeDiscovery {
  const _EnglishTreeDiscovery({
    required this.rootUrl,
    required this.shelfTitle,
    required this.directBookLinksFound,
    required this.childCollectionsDetected,
    required this.branchCategoryPagesVisited,
    required this.finalItemPagesVisited,
    required this.pageUnavailableCount,
    required this.discoveredCategories,
    required this.items,
    required this.warnings,
  });

  final String rootUrl;
  final String shelfTitle;
  final int directBookLinksFound;
  final List<_ChildCollectionRecord> childCollectionsDetected;
  final int branchCategoryPagesVisited;
  final int finalItemPagesVisited;
  final int pageUnavailableCount;
  final Set<String> discoveredCategories;
  final List<_EgwManifestItem> items;
  final List<String> warnings;
}

class _TreePageState {
  const _TreePageState({required this.url, required this.breadcrumbs});

  final String url;
  final List<String> breadcrumbs;
}

class _TreeLink {
  const _TreeLink({required this.url, required this.label});

  final String url;
  final String label;
}

class _ChildCollectionRecord {
  const _ChildCollectionRecord({
    required this.url,
    required this.label,
  });

  final String url;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
    'child_collection_url': url,
    'child_collection_label': label,
    'child_collection_detected': true,
    'followed': false,
  };
}

class _VerifiedDownloadLinks {
  const _VerifiedDownloadLinks({
    required this.epubUrl,
    required this.pdfUrl,
    required this.availableFormats,
  });

  final String? epubUrl;
  final String? pdfUrl;
  final List<String> availableFormats;
}

class _CollectionPageResult {
  const _CollectionPageResult({
    required this.html,
    required this.pageUrl,
    required this.bookPageUrls,
  });

  final String html;
  final String pageUrl;
  final List<String> bookPageUrls;
}

class _PageSummary {
  const _PageSummary({
    required this.url,
    required this.finalUrl,
    required this.statusCode,
    required this.contentType,
    required this.bodyLength,
    required this.preview,
    required this.hrefs,
    required this.discoveryUrls,
    required this.patternCounts,
  });

  final String url;
  final String finalUrl;
  final int statusCode;
  final String? contentType;
  final int bodyLength;
  final String preview;
  final List<String> hrefs;
  final List<String> discoveryUrls;
  final Map<String, int> patternCounts;
}

enum _ScanRootKind { managed, legacy, repo }

class _ScanRootSpec {
  const _ScanRootSpec({
    required this.label,
    required this.path,
    required this.kind,
  });

  final String label;
  final String path;
  final _ScanRootKind kind;
}

class _ScanRootSummary {
  _ScanRootSummary({
    required this.label,
    required this.path,
    required this.kind,
    required this.exists,
  });

  final String label;
  final String path;
  final _ScanRootKind kind;
  final bool exists;
  int totalFiles = 0;
  int egwFiles = 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'path': path,
    'kind': kind.name,
    'exists': exists,
    'total_files': totalFiles,
    'egw_files': egwFiles,
  };
}

class _ScanResult {
  const _ScanResult({required this.localFiles, required this.scannedRoots});

  final List<_LocalFileRecord> localFiles;
  final List<_ScanRootSummary> scannedRoots;
}

class _InventoryAnalysis {
  const _InventoryAnalysis({
    required this.duplicateSameHashGroups,
    required this.duplicateSameCodeDifferentLocationGroups,
    required this.conflictSameCodeDifferentHashGroups,
    required this.conflictTargetExistsDifferentHashGroups,
    required this.unmatchedLocalFiles,
  });

  final List<_AuditFindingGroup> duplicateSameHashGroups;
  final List<_AuditFindingGroup> duplicateSameCodeDifferentLocationGroups;
  final List<_AuditFindingGroup> conflictSameCodeDifferentHashGroups;
  final List<_AuditFindingGroup> conflictTargetExistsDifferentHashGroups;
  final List<_LocalFileRecord> unmatchedLocalFiles;
}

class _AuditFindingGroup {
  const _AuditFindingGroup({
    required this.status,
    required this.category,
    required this.code,
    required this.title,
    required this.targetRelativePaths,
    required this.recommendedAction,
    required this.reason,
    required this.files,
  });

  final String status;
  final String category;
  final String code;
  final String? title;
  final List<String> targetRelativePaths;
  final String recommendedAction;
  final String reason;
  final List<_LocalFileRecord> files;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status,
    'category': category,
    'code': code,
    'title': title,
    'target_relative_paths': targetRelativePaths,
    'recommended_action': recommendedAction,
    'reason': reason,
    'files': files.map((item) => item.toJson()).toList(growable: false),
  };
}

class _ManifestIndex {
  const _ManifestIndex({required this.byCategoryCode, required this.byCode});

  final Map<String, _EgwManifestItem> byCategoryCode;
  final Map<String, List<_EgwManifestItem>> byCode;

  factory _ManifestIndex.fromItems(List<_EgwManifestItem> items) {
    final byCategoryCode = <String, _EgwManifestItem>{};
    final byCode = <String, List<_EgwManifestItem>>{};
    for (final item in items) {
      byCategoryCode['${item.category}|${item.code}'] = item;
      if (item.code.trim().isEmpty) continue;
      byCode.putIfAbsent(item.code, () => <_EgwManifestItem>[]).add(item);
    }
    return _ManifestIndex(byCategoryCode: byCategoryCode, byCode: byCode);
  }

  String? categoryForCode(String code) {
    final items = byCode[code];
    if (items == null || items.isEmpty) return null;
    return items.first.category;
  }

  String? targetRelativePathFor({
    required String category,
    required String code,
    required String format,
  }) {
    final item = byCategoryCode['$category|$code'];
    if (item == null) return null;
    return format == 'pdf'
        ? item.targetPdfRelativePath
        : item.targetEpubRelativePath;
  }

  String? titleForCode(String code) {
    final items = byCode[code];
    if (items == null || items.isEmpty) return null;
    return items.first.title;
  }

  bool hasCode(String code) => byCode.containsKey(code);
}

class _LocalFileRecord {
  const _LocalFileRecord({
    required this.filePath,
    required this.rootLabel,
    required this.rootPath,
    required this.rootKind,
    required this.relativePath,
    required this.targetRelativePath,
    required this.category,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.code,
    required this.indexed,
    required this.indexStatus,
    required this.dbTitle,
    required this.dbCollectionName,
    required this.dbRelativePath,
    required this.dbFileHash,
    required this.duplicateGroup,
    required this.conflict,
  });

  final String filePath;
  final String rootLabel;
  final String rootPath;
  final String rootKind;
  final String relativePath;
  final String? targetRelativePath;
  final String category;
  final String fileName;
  final int fileSize;
  final String sha256;
  final String code;
  final bool indexed;
  final String? indexStatus;
  final String? dbTitle;
  final String? dbCollectionName;
  final String? dbRelativePath;
  final String? dbFileHash;
  final String duplicateGroup;
  final bool conflict;

  String get format =>
      p.extension(fileName).toLowerCase().replaceFirst('.', '');
  bool get isEpub => format == 'epub';
  bool get isPdf => format == 'pdf';
  bool get isManaged => category.isNotEmpty;
  bool get isEmpty => filePath.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'file_path': filePath,
    'root_label': rootLabel,
    'root_path': rootPath,
    'root_kind': rootKind,
    'relative_path': relativePath,
    'target_relative_path': targetRelativePath,
    'category': category,
    'file_name': fileName,
    'file_size': fileSize,
    'sha256': sha256,
    'code': code,
    'indexed': indexed,
    'index_status': indexStatus,
    'db_title': dbTitle,
    'db_collection_name': dbCollectionName,
    'db_relative_path': dbRelativePath,
    'db_file_hash': dbFileHash,
    'duplicate_group': duplicateGroup,
    'conflict': conflict,
  };
}

class _DbCatalogRow {
  const _DbCatalogRow({
    required this.id,
    required this.title,
    required this.fileName,
    required this.fileHash,
    required this.relativePath,
    required this.fileFormat,
    required this.folderType,
    required this.libraryRole,
    required this.collectionName,
    required this.sourceSite,
    required this.sourceUrl,
    required this.sourceType,
    required this.indexStatus,
    required this.fileSize,
    required this.mimeType,
    required this.spineIndex,
    required this.anchorId,
    required this.epubHref,
    required this.paragraphIndex,
    required this.dateAdded,
    required this.lastOpened,
    required this.deletedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final String? fileHash;
  final String relativePath;
  final String? fileFormat;
  final String? folderType;
  final String? libraryRole;
  final String? collectionName;
  final String? sourceSite;
  final String? sourceUrl;
  final String? sourceType;
  final String? indexStatus;
  final int? fileSize;
  final String? mimeType;
  final int? spineIndex;
  final String? anchorId;
  final String? epubHref;
  final int? paragraphIndex;
  final String? dateAdded;
  final String? lastOpened;
  final String? deletedAt;

  bool get indexed => (indexStatus ?? '').toLowerCase() == 'indexed';

  factory _DbCatalogRow.fromRow(Map<String, Object?> row) {
    return _DbCatalogRow(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? '',
      fileName: row['file_name']?.toString() ?? '',
      fileHash: row['file_hash']?.toString(),
      relativePath: row['relative_path']?.toString() ?? '',
      fileFormat: row['file_format']?.toString(),
      folderType: row['folder_type']?.toString(),
      libraryRole: row['library_role']?.toString(),
      collectionName: row['collection_name']?.toString(),
      sourceSite: row['source_site']?.toString(),
      sourceUrl: row['source_url']?.toString(),
      sourceType: row['source_type']?.toString(),
      indexStatus: row['index_status']?.toString(),
      fileSize: (row['file_size'] as num?)?.toInt(),
      mimeType: row['mime_type']?.toString(),
      spineIndex: (row['spine_index'] as num?)?.toInt(),
      anchorId: row['anchor_id']?.toString(),
      epubHref: row['epub_href']?.toString(),
      paragraphIndex: (row['paragraph_index'] as num?)?.toInt(),
      dateAdded: row['date_added']?.toString(),
      lastOpened: row['last_opened']?.toString(),
      deletedAt: row['deleted_at']?.toString(),
    );
  }
}

class _MrVolumeSpec {
  const _MrVolumeSpec(this.volume, this.start, this.end);
  final int volume;
  final int start;
  final int end;
}

class _LtMsVolumeSpec {
  const _LtMsVolumeSpec(this.volume, this.start, this.end);
  final int volume;
  final int start;
  final int end;
}

class _AuditProgressLogger {
  _AuditProgressLogger() : _startedAt = Stopwatch()..start();

  final Stopwatch _startedAt;

  void log(String message) {
    stdout.writeln(
      '[egw-audit +${_formatDuration(_startedAt.elapsed)}] $message',
    );
  }
}

String _formatDuration(Duration duration) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60);
  final milliseconds = duration.inMilliseconds.remainder(1000);
  return '${twoDigits(minutes)}:${twoDigits(seconds)}.${milliseconds.toString().padLeft(3, '0')}';
}

class _ParsedArgs {
  const _ParsedArgs({
    required this.audit,
    required this.apply,
    required this.rootPath,
    required this.dbPath,
    required this.manifestPath,
    required this.limit,
    required this.category,
    required this.dryRun,
    required this.noRemote,
    required this.maxPages,
    required this.debugLinks,
    required this.shelfUrl,
    required this.showHelp,
  });

  final bool audit;
  final bool apply;
  final String rootPath;
  final String dbPath;
  final String manifestPath;
  final int? limit;
  final String? category;
  final bool dryRun;
  final bool noRemote;
  final int? maxPages;
  final bool debugLinks;
  final String? shelfUrl;
  final bool showHelp;
}

_ParsedArgs _parseArgs(List<String> args) {
  var audit = false;
  var apply = false;
  var showHelp = false;
  var rootPath = _defaultRootPath;
  var dbPath = _defaultDbPath;
  var manifest = _manifestPath;
  int? limit;
  String? category;
  var dryRun = false;
  var noRemote = false;
  var debugLinks = false;
  String? shelfUrl;
  int? maxPages;

  for (final arg in args) {
    final trimmed = arg.trim();
    if (trimmed == '--help' || trimmed == '-h') {
      showHelp = true;
      continue;
    }
    if (trimmed == '--audit') {
      audit = true;
      continue;
    }
    if (trimmed == '--apply') {
      apply = true;
      continue;
    }
    if (trimmed.startsWith('--root=')) {
      rootPath = trimmed.substring('--root='.length).trim();
      continue;
    }
    if (trimmed.startsWith('--db=')) {
      dbPath = trimmed.substring('--db='.length).trim();
      continue;
    }
    if (trimmed.startsWith('--manifest=')) {
      manifest = trimmed.substring('--manifest='.length).trim();
      continue;
    }
    if (trimmed.startsWith('--limit=')) {
      limit = int.tryParse(trimmed.substring('--limit='.length).trim());
      continue;
    }
    if (trimmed.startsWith('--category=')) {
      final value = trimmed.substring('--category='.length).trim();
      category = value.isEmpty ? null : value;
      continue;
    }
    if (trimmed == '--dry-run') {
      dryRun = true;
      continue;
    }
    if (trimmed == '--no-remote') {
      noRemote = true;
      continue;
    }
    if (trimmed.startsWith('--max-pages=')) {
      maxPages = int.tryParse(trimmed.substring('--max-pages='.length).trim());
      continue;
    }
    if (trimmed.startsWith('--shelf-url=')) {
      final value = trimmed.substring('--shelf-url='.length).trim();
      shelfUrl = value.isEmpty ? null : value;
      continue;
    }
    if (trimmed == '--debug-links') {
      debugLinks = true;
      continue;
    }
  }

  return _ParsedArgs(
    audit: audit,
    apply: apply,
    rootPath: rootPath.isEmpty ? _defaultRootPath : rootPath,
    dbPath: dbPath.isEmpty ? _defaultDbPath : dbPath,
    manifestPath: manifest.isEmpty ? _manifestPath : manifest,
    limit: limit,
    category: category,
    dryRun: dryRun,
    noRemote: noRemote,
    maxPages: maxPages,
    debugLinks: debugLinks,
    shelfUrl: shelfUrl,
    showHelp: showHelp,
  );
}

String _usage() {
  return '''
EGW Content Sync

Usage:
  dart run tool/egw_content_sync.dart --audit
  dart run tool/egw_content_sync.dart --audit --root=/path/to/BiblicalHeritage/v2
  dart run tool/egw_content_sync.dart --apply
  dart run tool/egw_content_sync.dart --apply --limit=5
  dart run tool/egw_content_sync.dart --apply --category=EGW_Commentaries

Options:
  --audit        Run read-only EGW inventory audit.
  --apply        Copy legacy files and download missing files.
  --root=PATH    Override the managed EGW root folder.
  --db=PATH      Override the user.db path.
  --manifest=PATH Override the EGW manifest config path.
  --limit=N      Limit apply to the first N actionable EPUB tasks.
  --category=CAT Limit apply to a single EGW category.
  --dry-run      Build the apply plan without copying/downloading.
  --no-remote    Skip remote EGW discovery and audit local files only.
  --max-pages=N  Cap remote crawl pages to keep audit bounded.
  --shelf-url=URL Seed remote discovery from a single shelf page.
  --debug-links  Log raw link/HTML diagnostics for discovery pages.
  --help         Show this help.
''';
}

List<_EgwManifestItem> _dedupeManifestItems(List<_EgwManifestItem> items) {
  if (items.length < 2) return items;
  final chosen = <String, _EgwManifestItem>{};
  for (final item in items) {
    final key = item.itemPageUrl.trim().isNotEmpty
        ? item.itemPageUrl.trim()
        : '${item.category}|${item.code}|${item.title}';
    chosen.putIfAbsent(key, () => item);
  }
  return chosen.values.toList(growable: false);
}

String _normalizePath(String path) {
  return p.normalize(path).replaceAll('\\', '/').toLowerCase();
}
