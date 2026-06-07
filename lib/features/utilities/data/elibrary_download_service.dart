import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import 'elibrary_install_estimate_repository.dart';
import 'elibrary_folder_policy.dart';

const bool _debugELibraryDownloadLogs = false;

class ELibraryDownloadService {
  ELibraryDownloadService._();

  static final ELibraryDownloadService instance = ELibraryDownloadService._();

  static const List<_CollectionSpec> _collections = <_CollectionSpec>[
    _CollectionSpec(
      label: 'EGW Books',
      cacheKey: 'EGW Books',
      url: 'https://egwwritings.org/allCollection/en/4',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/4',
      folderName: 'EGW_Books',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Devotionals',
      cacheKey: 'EGW Devotionals',
      url: 'https://egwwritings.org/allCollection/en/1227',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1227',
      folderName: 'EGW_Devotionals',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Commentaries',
      cacheKey: 'EGW Commentaries',
      url: 'https://egwwritings.org/allCollection/en/1371',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1371',
      folderName: 'EGW_Commentaries',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Misc Collections',
      cacheKey: 'EGW Misc Collections',
      url: 'https://egwwritings.org/allCollection/en/10',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/10',
      folderName: 'EGW_Misc_Collections',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Pamphlets',
      cacheKey: 'EGW Pamphlets',
      url: 'https://egwwritings.org/allCollection/en/8',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/8',
      folderName: 'EGW_Pamphlets',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Periodicals',
      cacheKey: 'EGW Periodicals',
      url: 'https://egwwritings.org/allCollection/en/5',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/5',
      folderName: 'EGW_Periodicals',
      items: <_CollectionItemSpec>[],
    ),
    _CollectionSpec(
      label: 'EGW Manuscript Releases',
      cacheKey: 'EGW Manuscript Releases',
      url: 'https://egwwritings.org/allCollection/en/1376',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1376',
      folderName: 'EGW_Manuscript_Releases',
      items: <_CollectionItemSpec>[],
    ),
  ];

  static Future<List<_CollectionSpec>>? _loadedCollections;

  Future<ELibraryDownloadReport> run({
    bool refreshExisting = false,
    bool dryRun = false,
    void Function(ELibraryDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final collections = await _collectionsWithItems();
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final destinationRoot = p.join(rootPath, 'eLibrary_Downloads');
    return _runDownloads(
      startedAt: startedAt,
      stopwatch: stopwatch,
      destinationRoot: destinationRoot,
      reportPrefix: 'elibrary_download_report',
      refreshExisting: refreshExisting,
      dryRun: dryRun,
      selectedCollections: collections,
      selectedFormats: _DownloadFormat.values,
      onProgress: onProgress,
      isCancelled: isCancelled,
      userAgent: 'StudyBible2 eLibrary Downloader',
      productionLayout: false,
    );
  }

  Future<ELibraryDownloadReport> runProductionSetup({
    bool installBooks = false,
    bool installDevotionals = false,
    bool installCommentaries = false,
    bool installMiscCollections = false,
    bool installPamphlets = false,
    bool installPeriodicals = false,
    bool installManuscriptReleases = false,
    bool installEpub = false,
    bool installPdf = false,
    bool dryRun = false,
    void Function(ELibraryDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final collections = await _collectionsWithItems();
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final selectedCollections = <_CollectionSpec>[
      if (installBooks) collections[0],
      if (installDevotionals) collections[1],
      if (installCommentaries) collections[2],
      if (installMiscCollections) collections[3],
      if (installPamphlets) collections[4],
      if (installPeriodicals) collections[5],
      if (installManuscriptReleases) collections[6],
    ];
    final selectedFormats = <_DownloadFormat>[
      if (installEpub) _DownloadFormat.epub,
      if (installPdf) _DownloadFormat.pdf,
    ];
    if (selectedCollections.isEmpty) {
      throw StateError('Select at least one collection to install.');
    }
    if (selectedFormats.isEmpty) {
      throw StateError('Select EPUB, PDF, or both before installing.');
    }

    await LibraryRootService.instance.ensureStructure(rootPath);

    return _runDownloads(
      startedAt: startedAt,
      stopwatch: stopwatch,
      destinationRoot: rootPath,
      reportPrefix: 'production_elibrary_setup',
      refreshExisting: false,
      dryRun: dryRun,
      selectedCollections: selectedCollections,
      selectedFormats: selectedFormats,
      onProgress: onProgress,
      isCancelled: isCancelled,
      userAgent: 'StudyBible2 eLibrary Setup',
      productionLayout: true,
    );
  }

  Future<List<int?>> estimateProductionCollectionCounts() async {
    final collections = await _collectionsWithItems();
    return collections
        .map((collection) => collection.items.length)
        .toList(growable: false);
  }

  Future<void> refreshProductionCollectionEstimates() async {
    final collections = await _collectionsWithItems();
    final checkedAt = DateTime.now().toUtc();
    final cacheWrites = <Future<void>>[];
    for (final collection in collections) {
      cacheWrites.add(
        _storeProductionCollectionEstimate(
          collection: collection,
          fileCount: collection.items.length,
          source: 'refresh_estimates',
          lastCheckedUtc: checkedAt,
        ),
      );
    }
    await Future.wait(cacheWrites);
  }

  Future<void> _storeProductionCollectionEstimate({
    required _CollectionSpec collection,
    required int fileCount,
    required String source,
    DateTime? lastCheckedUtc,
  }) {
    return ELibraryInstallEstimateRepository.instance
        .upsertCollectionCountForBothFormats(
          collectionKey: collection.cacheKey,
          fileCount: fileCount,
          sizeKnown: false,
          source: source,
          lastCheckedUtc: lastCheckedUtc,
        );
  }

  Future<String?> _writableLibraryRootPath() async {
    final explicit = await LibraryRootService.instance
        .explicitLibraryRootPath();
    if (explicit != null && explicit.trim().isNotEmpty) return explicit;
    return null;
  }

  Future<List<_CollectionSpec>> _collectionsWithItems() async {
    final cached = _loadedCollections;
    if (cached != null) {
      return cached;
    }
    final loaded = _loadCollectionsFromManifest();
    _loadedCollections = loaded;
    return loaded;
  }

  Future<List<_CollectionSpec>> _loadCollectionsFromManifest() async {
    final manifestJson = await rootBundle.loadString(
      'tool/elibrary_download_manifest.json',
    );
    final decoded = jsonDecode(manifestJson);
    if (decoded is! Map<String, Object?>) {
      throw StateError('Invalid eLibrary download manifest.');
    }

    final rawCollections = decoded['collections'];
    if (rawCollections is! List) {
      throw StateError('Invalid eLibrary download manifest collections.');
    }

    final itemsByCacheKey = <String, List<_CollectionItemSpec>>{};
    for (final entry in rawCollections) {
      if (entry is! Map) continue;
      final collectionMap = entry.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final cacheKey = collectionMap['cache_key']?.toString().trim() ?? '';
      if (cacheKey.isEmpty) continue;
      final rawItems = collectionMap['items'];
      final items = <_CollectionItemSpec>[];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is! Map) continue;
          final itemMap = item.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final code = itemMap['code']?.toString().trim() ?? '';
          if (code.isEmpty) continue;
          final title = itemMap['title']?.toString().trim() ?? '';
          items.add(
            _CollectionItemSpec(
              code: code,
              title: title.isEmpty ? code : title,
            ),
          );
        }
      }
      itemsByCacheKey[cacheKey] = List<_CollectionItemSpec>.unmodifiable(items);
    }

    return _collections
        .map((collection) {
          return collection.copyWith(
            items:
                itemsByCacheKey[collection.cacheKey] ??
                const <_CollectionItemSpec>[],
          );
        })
        .toList(growable: false);
  }

  Future<ELibraryDownloadReport> _runDownloads({
    required DateTime startedAt,
    required Stopwatch stopwatch,
    required String destinationRoot,
    required String reportPrefix,
    required bool refreshExisting,
    required bool dryRun,
    required List<_CollectionSpec> selectedCollections,
    required List<_DownloadFormat> selectedFormats,
    required void Function(ELibraryDownloadProgress progress)? onProgress,
    required bool Function()? isCancelled,
    required String userAgent,
    required bool productionLayout,
  }) async {
    if (!dryRun) {
      await _prepareDestinationFolders(destinationRoot, productionLayout);
    }
    final reportRoot = productionLayout
        ? p.join(destinationRoot, 'download_reports')
        : p.join(destinationRoot, 'download_reports');
    final client = HttpClient()..autoUncompress = true;
    client.userAgent = userAgent;
    final dryRunRoot = dryRun
        ? await Directory.systemTemp.createTemp('studybible2_elibrary_dryrun_')
        : null;
    final existingFingerprints = dryRun || refreshExisting
        ? <String, _ExistingFileFingerprint>{}
        : await _loadExistingFileFingerprints();

    final report = _MutableELibraryDownloadReport(
      startedAt: startedAt,
      sourceCollectionUrls: selectedCollections
          .map((c) => c.url)
          .toList(growable: false),
      destinationRoot: destinationRoot,
      destinationFolders: _buildDestinationFolders(
        destinationRoot,
        selectedCollections,
        productionLayout: productionLayout,
      ),
      dryRun: dryRun,
    );
    final unavailableUrls = <String>{};

    try {
      for (
        var collectionIndex = 0;
        collectionIndex < selectedCollections.length;
        collectionIndex++
      ) {
        if (isCancelled?.call() ?? false) break;
        final collection = selectedCollections[collectionIndex];
        if (collection.items.isEmpty) {
          throw StateError(
            'No download entries are configured for ${collection.label}.',
          );
        }
        if (_debugELibraryDownloadLogs) {
          debugPrint(
            '[ELibraryDownload] installing ${collection.label} (${collection.url})',
          );
        }
        onProgress?.call(
          ELibraryDownloadProgress(
            currentCollection: collection.label,
            collectionIndex: collectionIndex + 1,
            collectionTotal: selectedCollections.length,
            discoveredCount: report.totalLinksDiscovered,
            downloadedCount: report.downloadedCount,
            skippedCount: report.skippedExistingCount,
            unavailableCount: report.unavailableCount,
            failedCount: report.failedCount,
            currentFile: 'preparing...',
            elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
            statusMessage: 'Preparing ${collection.label} downloads...',
          ),
        );

        if (productionLayout) {
          await _storeProductionCollectionEstimate(
            collection: collection,
            fileCount: collection.items.length,
            source: 'production_setup_manifest',
          );
        }

        for (
          var bookIndex = 0;
          bookIndex < collection.items.length;
          bookIndex++
        ) {
          if (isCancelled?.call() ?? false) break;
          final book = collection.items[bookIndex];
          for (final format in selectedFormats) {
            if (isCancelled?.call() ?? false) break;

            final sourceUrl = format.sourceUrl(book.code);
            report.totalLinksDiscovered += 1;
            if (format == _DownloadFormat.epub) {
              report.epubDiscoveredCount += 1;
            } else {
              report.pdfDiscoveredCount += 1;
            }

            final relativePath = productionLayout
                ? _productionRelativePath(
                    collection: collection,
                    format: format,
                    bookCode: book.code,
                  )
                : _productionRelativePath(
                    collection: collection,
                    format: format,
                    bookCode: book.code,
                  );
            final destinationPath = p.join(destinationRoot, relativePath);
            final destinationFile = File(destinationPath);
            final cachedFingerprint =
                existingFingerprints[_normalizedRelativePath(relativePath)];

            if (!dryRun &&
                !refreshExisting &&
                cachedFingerprint != null &&
                await _isValidExistingFile(
                  file: destinationFile,
                  fingerprint: cachedFingerprint,
                )) {
              final existingSize = await destinationFile.length();
              final existingHash =
                  cachedFingerprint.fileHash ??
                  await _sha256ForFile(destinationFile);
              report.skippedExistingCount += 1;
              report.filesSkipped.add(
                ELibraryDownloadFileRecord(
                  title: book.title,
                  collection: collection.label,
                  format: format.name,
                  sourceUrl: sourceUrl,
                  relativePath: relativePath,
                  fileName: p.basename(destinationPath),
                  fileSize: existingSize,
                  sha256: existingHash,
                  status: 'skipped_existing',
                  error: null,
                ),
              );
              if (_debugELibraryDownloadLogs) {
                debugPrint(
                  '[ELibraryDownload] skipped cached ${collection.label} ${book.code} ${format.name}',
                );
              }
              continue;
            }

            final stagingFile = dryRun
                ? File(
                    p.join(
                      dryRunRoot!.path,
                      '${collection.folderName}_${book.code}_${format.name}.downloading',
                    ),
                  )
                : File('${destinationFile.path}.downloading');
            if (await stagingFile.exists()) {
              await stagingFile.delete();
            }

            onProgress?.call(
              ELibraryDownloadProgress(
                currentCollection: collection.label,
                collectionIndex: collectionIndex + 1,
                collectionTotal: selectedCollections.length,
                discoveredCount: report.totalLinksDiscovered,
                downloadedCount: report.downloadedCount,
                skippedCount: report.skippedExistingCount,
                unavailableCount: report.unavailableCount,
                failedCount: report.failedCount,
                currentFile: '${book.code}.${format.name}',
                elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
                statusMessage:
                    'Downloading ${collection.label} ${book.title} (${format.name.toUpperCase()})',
              ),
            );

            final downloadResult = unavailableUrls.contains(sourceUrl)
                ? _DownloadResult(
                    success: false,
                    unavailable: true,
                    error:
                        '${format.name.toUpperCase()} not available at expected URL.',
                  )
                : await _downloadFile(
                    client: client,
                    sourceUrl: sourceUrl,
                    destinationFile: stagingFile,
                    formatLabel: format.name.toUpperCase(),
                  );

            if (downloadResult.success) {
              final stagedSize = await stagingFile.length();
              final stagedHash = await _sha256ForFile(stagingFile);
              if (await destinationFile.exists()) {
                final destinationSize = await destinationFile.length();
                final destinationHash = destinationSize == stagedSize
                    ? await _sha256ForFile(destinationFile)
                    : null;
                if (destinationHash != null && destinationHash == stagedHash) {
                  report.skippedExistingCount += 1;
                  report.filesSkipped.add(
                    ELibraryDownloadFileRecord(
                      title: book.title,
                      collection: collection.label,
                      format: format.name,
                      sourceUrl: sourceUrl,
                      relativePath: relativePath,
                      fileName: p.basename(destinationPath),
                      fileSize: destinationSize,
                      sha256: destinationHash,
                      status: dryRun
                          ? 'would_skip_existing'
                          : 'skipped_existing',
                      error: null,
                    ),
                  );
                  await stagingFile.delete();
                  if (_debugELibraryDownloadLogs) {
                    debugPrint(
                      '[ELibraryDownload] skipped existing ${collection.label} ${book.code} ${format.name}',
                    );
                  }
                  continue;
                }

                final shouldRepairExisting =
                    destinationSize <= 0 ||
                    refreshExisting ||
                    (cachedFingerprint != null &&
                        !await _isValidExistingFile(
                          file: destinationFile,
                          fingerprint: cachedFingerprint,
                        ));
                if (shouldRepairExisting) {
                  if (!dryRun) {
                    final quarantinePath = _uniqueQuarantinePath(
                      rootPath: destinationRoot,
                      sourcePath: destinationPath,
                      suffix: 'repair',
                    );
                    final quarantineFile = File(quarantinePath);
                    await quarantineFile.parent.create(recursive: true);
                    if (await quarantineFile.exists()) {
                      await quarantineFile.delete();
                    }
                    await destinationFile.rename(quarantineFile.path);
                    await destinationFile.parent.create(recursive: true);
                    await stagingFile.rename(destinationFile.path);
                    report.quarantinedCount += 1;
                    report.filesQuarantined.add(
                      ELibraryDownloadFileRecord(
                        title: book.title,
                        collection: collection.label,
                        format: format.name,
                        sourceUrl: sourceUrl,
                        relativePath: p.relative(
                          quarantinePath,
                          from: destinationRoot,
                        ),
                        fileName: p.basename(quarantinePath),
                        fileSize: destinationSize,
                        sha256: destinationHash,
                        status: 'replaced_existing',
                        error:
                            'Existing file was zero-byte or failed validation.',
                      ),
                    );
                  } else {
                    await stagingFile.delete();
                  }
                  report.downloadedCount += 1;
                  report.filesDownloaded.add(
                    ELibraryDownloadFileRecord(
                      title: book.title,
                      collection: collection.label,
                      format: format.name,
                      sourceUrl: sourceUrl,
                      relativePath: relativePath,
                      fileName: p.basename(destinationPath),
                      fileSize: stagedSize,
                      sha256: stagedHash,
                      status: dryRun
                          ? 'would_repair_existing'
                          : 'repaired_existing',
                      error: null,
                    ),
                  );
                  if (_debugELibraryDownloadLogs) {
                    debugPrint(
                      '[ELibraryDownload] repaired existing ${collection.label} ${book.code} ${format.name}',
                    );
                  }
                  continue;
                }

                final quarantinePath = _uniqueQuarantinePath(
                  rootPath: destinationRoot,
                  sourcePath: destinationPath,
                  suffix: 'conflict',
                );
                if (!dryRun) {
                  final quarantineFile = File(quarantinePath);
                  await quarantineFile.parent.create(recursive: true);
                  if (await quarantineFile.exists()) {
                    await quarantineFile.delete();
                  }
                  await stagingFile.rename(quarantineFile.path);
                } else {
                  await stagingFile.delete();
                }
                report.quarantinedCount += 1;
                report.filesQuarantined.add(
                  ELibraryDownloadFileRecord(
                    title: book.title,
                    collection: collection.label,
                    format: format.name,
                    sourceUrl: sourceUrl,
                    relativePath: dryRun
                        ? relativePath
                        : p.relative(quarantinePath, from: destinationRoot),
                    fileName: dryRun
                        ? p.basename(destinationPath)
                        : p.basename(quarantinePath),
                    fileSize: stagedSize,
                    sha256: stagedHash,
                    status: dryRun
                        ? 'would_quarantine_conflict'
                        : 'quarantined_conflict',
                    error:
                        'Destination file already exists with different content.',
                  ),
                );
                if (_debugELibraryDownloadLogs) {
                  debugPrint(
                    '[ELibraryDownload] quarantined conflict ${collection.label} ${book.code} ${format.name}',
                  );
                }
                continue;
              }

              if (!dryRun) {
                await destinationFile.parent.create(recursive: true);
                await stagingFile.rename(destinationFile.path);
              } else {
                await stagingFile.delete();
              }
              report.downloadedCount += 1;
              report.filesDownloaded.add(
                ELibraryDownloadFileRecord(
                  title: book.title,
                  collection: collection.label,
                  format: format.name,
                  sourceUrl: sourceUrl,
                  relativePath: relativePath,
                  fileName: p.basename(destinationPath),
                  fileSize: stagedSize,
                  sha256: stagedHash,
                  status: dryRun ? 'would_download' : 'downloaded',
                  error: null,
                ),
              );
            } else if (downloadResult.unavailable) {
              unavailableUrls.add(sourceUrl);
              report.unavailableCount += 1;
              report.filesUnavailable.add(
                ELibraryDownloadFileRecord(
                  title: book.title,
                  collection: collection.label,
                  format: format.name,
                  sourceUrl: sourceUrl,
                  relativePath: relativePath,
                  fileName: p.basename(destinationPath),
                  fileSize: 0,
                  sha256: null,
                  status: dryRun ? 'would_be_unavailable' : 'unavailable',
                  error:
                      downloadResult.error ??
                      '${format.name.toUpperCase()} not available at expected URL.',
                ),
              );
              if (await stagingFile.exists()) {
                await stagingFile.delete();
              }
            } else {
              report.failedCount += 1;
              report.failures.add(
                ELibraryDownloadFileRecord(
                  title: book.title,
                  collection: collection.label,
                  format: format.name,
                  sourceUrl: sourceUrl,
                  relativePath: relativePath,
                  fileName: p.basename(destinationPath),
                  fileSize: 0,
                  sha256: null,
                  status: 'failed',
                  error: downloadResult.error,
                ),
              );
              if (await stagingFile.exists()) {
                await stagingFile.delete();
              }
            }

            if (_debugELibraryDownloadLogs) {
              debugPrint(
                '[ELibraryDownload] ${collection.label} ${book.code} ${format.name} '
                '${downloadResult.success
                    ? 'ok'
                    : downloadResult.unavailable
                    ? 'unavailable'
                    : 'failed'} '
                'downloaded=${report.downloadedCount} '
                'skipped=${report.skippedExistingCount} '
                'unavailable=${report.unavailableCount} '
                'failed=${report.failedCount}',
              );
            }

            await Future<void>.delayed(const Duration(milliseconds: 120));
          }
        }
      }
    } finally {
      client.close(force: true);
      if (dryRunRoot != null) {
        try {
          if (await dryRunRoot.exists()) {
            await dryRunRoot.delete(recursive: true);
          }
        } catch (_) {
          // Ignore temp cleanup failures in dry-run mode.
        }
      }
    }

    report.completedAt = DateTime.now().toUtc();
    report.elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
    final completedReport = report.toReport(
      p.join(
        reportRoot,
        '${reportPrefix}_${_timestamp(report.completedAt ?? DateTime.now().toUtc())}.json',
      ),
    );

    final reportFile = File(completedReport.reportFilePath);
    await reportFile.parent.create(recursive: true);
    await reportFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(completedReport.toJson()),
    );

    return completedReport;
  }

  Future<void> _prepareDestinationFolders(
    String destinationRoot,
    bool productionLayout,
  ) async {
    final root = Directory(destinationRoot);
    final epubRoot = Directory(p.join(root.path, 'ePubs'));
    final pdfRoot = Directory(p.join(root.path, 'PDFs'));
    final reportRoot = Directory(p.join(root.path, 'download_reports'));
    final folders = <Directory>[root, epubRoot, pdfRoot, reportRoot];
    if (productionLayout) {
      folders.addAll([
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Commentaries')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Books')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Devotionals')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Misc_Collections')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Pamphlets')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Periodicals')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Manuscript_Releases')),
        Directory(p.join(epubRoot.path, 'Commentaries', 'User')),
        Directory(p.join(epubRoot.path, 'Research', 'User')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Commentaries')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Books')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Devotionals')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Misc_Collections')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Pamphlets')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Periodicals')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Manuscript_Releases')),
        Directory(p.join(pdfRoot.path, 'Commentaries', 'User')),
        Directory(p.join(pdfRoot.path, 'Research', 'User')),
      ]);
    } else {
      folders.addAll([
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Commentaries')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Books')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Devotionals')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Misc_Collections')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Pamphlets')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Periodicals')),
        Directory(p.join(epubRoot.path, 'EGW', 'EGW_Manuscript_Releases')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Commentaries')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Books')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Devotionals')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Misc_Collections')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Pamphlets')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Periodicals')),
        Directory(p.join(pdfRoot.path, 'EGW', 'EGW_Manuscript_Releases')),
      ]);
    }
    for (final dir in folders) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  }

  List<String> _buildDestinationFolders(
    String destinationRoot,
    List<_CollectionSpec> selectedCollections, {
    required bool productionLayout,
  }) {
    final epubRoot = p.join(destinationRoot, 'ePubs');
    final pdfRoot = p.join(destinationRoot, 'PDFs');
    final folders = <String>[
      destinationRoot,
      epubRoot,
      pdfRoot,
      p.join(destinationRoot, 'download_reports'),
    ];
    if (productionLayout) {
      folders.addAll(
        const [
          'ePubs/EGW/EGW_Commentaries',
          'ePubs/EGW/EGW_Books',
          'ePubs/EGW/EGW_Devotionals',
          'ePubs/EGW/EGW_Misc_Collections',
          'ePubs/EGW/EGW_Pamphlets',
          'ePubs/EGW/EGW_Periodicals',
          'ePubs/EGW/EGW_Manuscript_Releases',
          'ePubs/Commentaries/User',
          'ePubs/Research/User',
          'PDFs/EGW/EGW_Commentaries',
          'PDFs/EGW/EGW_Books',
          'PDFs/EGW/EGW_Devotionals',
          'PDFs/EGW/EGW_Misc_Collections',
          'PDFs/EGW/EGW_Pamphlets',
          'PDFs/EGW/EGW_Periodicals',
          'PDFs/EGW/EGW_Manuscript_Releases',
          'PDFs/Commentaries/User',
          'PDFs/Research/User',
        ].map((relative) => p.join(destinationRoot, relative)),
      );
    } else {
      folders.addAll(
        selectedCollections.expand(
          (spec) => <String>[
            p.join(epubRoot, 'EGW', spec.folderName),
            p.join(pdfRoot, 'EGW', spec.folderName),
          ],
        ),
      );
    }
    return folders;
  }

  String _productionRelativePath({
    required _CollectionSpec collection,
    required _DownloadFormat format,
    required String bookCode,
  }) {
    return p.join(
      format.folderRootName,
      'EGW',
      collection.folderName,
      format.fileName(bookCode),
    );
  }

  Future<_DownloadResult> _downloadFile({
    required HttpClient client,
    required String sourceUrl,
    required File destinationFile,
    required String formatLabel,
  }) async {
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/epub+zip,application/pdf,*/*;q=0.8',
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        final isCollectionLandingPage = Uri.parse(
          sourceUrl,
        ).path.contains('/allCollection/');
        final errorMessage = response.statusCode == HttpStatus.notFound
            ? '$formatLabel not available at expected URL.\nFailed URL: $sourceUrl\nStatus code: ${response.statusCode}'
            : response.statusCode == HttpStatus.forbidden
            ? isCollectionLandingPage
                  ? 'EGW site refused this request. The URL looks like a collection landing page, not a direct EPUB/PDF download. Open the collection in a browser or try again later.\nFailed URL: $sourceUrl\nStatus code: ${response.statusCode}'
                  : 'EGW site refused this request. Open the collection in a browser or try again later.\nFailed URL: $sourceUrl\nStatus code: ${response.statusCode}'
            : 'HTTP ${response.statusCode} for $sourceUrl';
        final unavailable = response.statusCode == HttpStatus.notFound;
        return _DownloadResult(
          success: false,
          unavailable: unavailable,
          error: errorMessage,
        );
      }
      final sink = destinationFile.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();
      return _DownloadResult(
        success: true,
        unavailable: false,
        fileSize: await destinationFile.length(),
      );
    } catch (e) {
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      return _DownloadResult(
        success: false,
        unavailable: false,
        error: e.toString(),
      );
    }
  }

  Future<Map<String, _ExistingFileFingerprint>>
  _loadExistingFileFingerprints() async {
    final db = await UserDatabase.instance.database;
    final rows = await db.rawQuery('''
      SELECT relative_path, file_size, file_hash
      FROM library_items
      WHERE deleted_at IS NULL
        AND LOWER(COALESCE(file_format, '')) IN ('epub', 'pdf')
        AND (
          LOWER(COALESCE(relative_path, '')) LIKE 'epubs/%'
          OR LOWER(COALESCE(relative_path, '')) LIKE 'pdfs/%'
        )
    ''');

    final fingerprints = <String, _ExistingFileFingerprint>{};
    for (final row in rows) {
      final relativePath = row['relative_path']?.toString().trim() ?? '';
      if (relativePath.isEmpty) continue;
      fingerprints[_normalizedRelativePath(
        relativePath,
      )] = _ExistingFileFingerprint(
        fileSize: (row['file_size'] as num?)?.toInt(),
        fileHash: row['file_hash']?.toString().trim(),
      );
    }
    return fingerprints;
  }

  Future<bool> _isValidExistingFile({
    required File file,
    required _ExistingFileFingerprint fingerprint,
  }) async {
    if (!await file.exists()) return false;
    final size = await file.length();
    if (size <= 0) return false;

    final expectedSize = fingerprint.fileSize;
    final expectedHash = fingerprint.fileHash?.trim() ?? '';
    if (expectedSize != null && expectedSize != size) {
      return false;
    }
    if (expectedHash.isEmpty) {
      return true;
    }

    final hash = await _sha256ForFile(file);
    return hash == expectedHash;
  }

  String _uniqueQuarantinePath({
    required String rootPath,
    required String sourcePath,
    required String suffix,
  }) {
    final candidate = ELibraryFolderPolicy.quarantinePathFor(
      rootPath,
      sourcePath,
      suffix: suffix,
    );
    final directory = p.dirname(candidate);
    final base = p.basenameWithoutExtension(candidate);
    final extension = p.extension(candidate);
    var result = candidate;
    var counter = 1;
    while (File(result).existsSync()) {
      result = p.join(directory, '${base}_$counter$extension');
      counter += 1;
    }
    return result;
  }

  Future<String> _sha256ForFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  String _normalizedRelativePath(String relativePath) {
    return p.normalize(relativePath.trim()).replaceAll('\\', '/').toLowerCase();
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}

class ELibraryDownloadReport {
  const ELibraryDownloadReport({
    required this.startedAt,
    required this.completedAt,
    required this.elapsedSeconds,
    required this.dryRun,
    required this.sourceCollectionUrls,
    required this.destinationRoot,
    required this.totalLinksDiscovered,
    required this.epubDiscoveredCount,
    required this.pdfDiscoveredCount,
    required this.epubDownloadedCount,
    required this.pdfDownloadedCount,
    required this.skippedExistingCount,
    required this.unavailableCount,
    required this.failedCount,
    required this.filesDownloaded,
    required this.filesSkipped,
    required this.filesUnavailable,
    required this.filesQuarantined,
    required this.failures,
    required this.usedStaticPageDiscovery,
    required this.usedFallbackManifest,
    required this.usedDirectUrlVerification,
    required this.quarantinedCount,
    required this.destinationFolders,
    required this.reportFilePath,
  });

  final DateTime startedAt;
  final DateTime completedAt;
  final double elapsedSeconds;
  final bool dryRun;
  final List<String> sourceCollectionUrls;
  final String destinationRoot;
  final int totalLinksDiscovered;
  final int epubDiscoveredCount;
  final int pdfDiscoveredCount;
  final int epubDownloadedCount;
  final int pdfDownloadedCount;
  final int skippedExistingCount;
  final int unavailableCount;
  final int failedCount;
  final List<ELibraryDownloadFileRecord> filesDownloaded;
  final List<ELibraryDownloadFileRecord> filesSkipped;
  final List<ELibraryDownloadFileRecord> filesUnavailable;
  final List<ELibraryDownloadFileRecord> filesQuarantined;
  final List<ELibraryDownloadFileRecord> failures;
  final bool usedStaticPageDiscovery;
  final bool usedFallbackManifest;
  final bool usedDirectUrlVerification;
  final int quarantinedCount;
  final List<String> destinationFolders;
  final String reportFilePath;

  Map<String, Object?> toJson() => <String, Object?>{
    'started_at': startedAt.toIso8601String(),
    'completed_at': completedAt.toIso8601String(),
    'elapsed_seconds': elapsedSeconds,
    'dry_run': dryRun,
    'source_collection_urls': sourceCollectionUrls,
    'destination_root': destinationRoot,
    'total_links_discovered': totalLinksDiscovered,
    'epub_discovered_count': epubDiscoveredCount,
    'pdf_discovered_count': pdfDiscoveredCount,
    'epub_downloaded_count': epubDownloadedCount,
    'pdf_downloaded_count': pdfDownloadedCount,
    'skipped_existing_count': skippedExistingCount,
    'unavailable_count': unavailableCount,
    'failed_count': failedCount,
    'files_downloaded': filesDownloaded
        .map((item) => item.toJson())
        .toList(growable: false),
    'files_skipped': filesSkipped
        .map((item) => item.toJson())
        .toList(growable: false),
    'files_unavailable': filesUnavailable
        .map((item) => item.toJson())
        .toList(growable: false),
    'files_quarantined': filesQuarantined
        .map((item) => item.toJson())
        .toList(growable: false),
    'failures': failures.map((item) => item.toJson()).toList(growable: false),
    'used_static_page_discovery': usedStaticPageDiscovery,
    'used_fallback_manifest': usedFallbackManifest,
    'used_direct_url_verification': usedDirectUrlVerification,
    'quarantined_count': quarantinedCount,
    'destination_folders': destinationFolders,
    'report_file_path': reportFilePath,
  };
}

class ELibraryDownloadFileRecord {
  const ELibraryDownloadFileRecord({
    required this.title,
    required this.collection,
    required this.format,
    required this.sourceUrl,
    required this.relativePath,
    required this.fileName,
    required this.fileSize,
    required this.sha256,
    required this.status,
    required this.error,
  });

  final String title;
  final String collection;
  final String format;
  final String sourceUrl;
  final String relativePath;
  final String fileName;
  final int fileSize;
  final String? sha256;
  final String status;
  final String? error;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'collection': collection,
    'format': format,
    'source_url': sourceUrl,
    'relative_path': relativePath,
    'file_name': fileName,
    'file_size': fileSize,
    'sha256': sha256,
    'status': status,
    'error': error,
  };
}

class ELibraryDownloadProgress {
  const ELibraryDownloadProgress({
    required this.currentCollection,
    required this.collectionIndex,
    required this.collectionTotal,
    required this.discoveredCount,
    required this.downloadedCount,
    required this.skippedCount,
    required this.unavailableCount,
    required this.failedCount,
    required this.currentFile,
    required this.elapsedSeconds,
    required this.statusMessage,
  });

  final String currentCollection;
  final int collectionIndex;
  final int collectionTotal;
  final int discoveredCount;
  final int downloadedCount;
  final int skippedCount;
  final int unavailableCount;
  final int failedCount;
  final String currentFile;
  final double elapsedSeconds;
  final String statusMessage;
}

class _MutableELibraryDownloadReport {
  _MutableELibraryDownloadReport({
    required this.startedAt,
    required this.sourceCollectionUrls,
    required this.destinationRoot,
    required this.destinationFolders,
    required this.dryRun,
  });

  final DateTime startedAt;
  DateTime? completedAt;
  double elapsedSeconds = 0;
  final List<String> sourceCollectionUrls;
  final String destinationRoot;
  final bool dryRun;
  int totalLinksDiscovered = 0;
  int epubDiscoveredCount = 0;
  int pdfDiscoveredCount = 0;
  int downloadedCount = 0;
  int skippedExistingCount = 0;
  int unavailableCount = 0;
  int quarantinedCount = 0;
  int failedCount = 0;
  final List<ELibraryDownloadFileRecord> filesDownloaded =
      <ELibraryDownloadFileRecord>[];
  final List<ELibraryDownloadFileRecord> filesSkipped =
      <ELibraryDownloadFileRecord>[];
  final List<ELibraryDownloadFileRecord> filesUnavailable =
      <ELibraryDownloadFileRecord>[];
  final List<ELibraryDownloadFileRecord> filesQuarantined =
      <ELibraryDownloadFileRecord>[];
  final List<ELibraryDownloadFileRecord> failures =
      <ELibraryDownloadFileRecord>[];
  bool usedStaticPageDiscovery = false;
  bool usedFallbackManifest = false;
  bool usedDirectUrlVerification = true;
  final List<String> destinationFolders;

  ELibraryDownloadReport toReport(String reportFilePath) {
    final done = completedAt ?? DateTime.now().toUtc();
    return ELibraryDownloadReport(
      startedAt: startedAt,
      completedAt: done,
      elapsedSeconds: elapsedSeconds,
      dryRun: dryRun,
      sourceCollectionUrls: sourceCollectionUrls,
      destinationRoot: destinationRoot,
      totalLinksDiscovered: totalLinksDiscovered,
      epubDiscoveredCount: epubDiscoveredCount,
      pdfDiscoveredCount: pdfDiscoveredCount,
      epubDownloadedCount: filesDownloaded
          .where((item) => item.format == 'epub')
          .length,
      pdfDownloadedCount: filesDownloaded
          .where((item) => item.format == 'pdf')
          .length,
      skippedExistingCount: skippedExistingCount,
      unavailableCount: unavailableCount,
      failedCount: failedCount,
      filesDownloaded: List<ELibraryDownloadFileRecord>.unmodifiable(
        filesDownloaded,
      ),
      filesSkipped: List<ELibraryDownloadFileRecord>.unmodifiable(filesSkipped),
      filesUnavailable: List<ELibraryDownloadFileRecord>.unmodifiable(
        filesUnavailable,
      ),
      filesQuarantined: List<ELibraryDownloadFileRecord>.unmodifiable(
        filesQuarantined,
      ),
      failures: List<ELibraryDownloadFileRecord>.unmodifiable(failures),
      usedStaticPageDiscovery: usedStaticPageDiscovery,
      usedFallbackManifest: usedFallbackManifest,
      usedDirectUrlVerification: usedDirectUrlVerification,
      quarantinedCount: quarantinedCount,
      destinationFolders: List<String>.unmodifiable(destinationFolders),
      reportFilePath: reportFilePath,
    );
  }
}

class _ExistingFileFingerprint {
  const _ExistingFileFingerprint({
    required this.fileSize,
    required this.fileHash,
  });

  final int? fileSize;
  final String? fileHash;
}

class _CollectionSpec {
  const _CollectionSpec({
    required this.label,
    required this.cacheKey,
    required this.url,
    required this.fallbackUrl,
    required this.folderName,
    this.items = const <_CollectionItemSpec>[],
  });

  final String label;
  final String cacheKey;
  final String url;
  final String fallbackUrl;
  final String folderName;
  final List<_CollectionItemSpec> items;

  _CollectionSpec copyWith({List<_CollectionItemSpec>? items}) {
    return _CollectionSpec(
      label: label,
      cacheKey: cacheKey,
      url: url,
      fallbackUrl: fallbackUrl,
      folderName: folderName,
      items: items ?? this.items,
    );
  }
}

class _CollectionItemSpec {
  const _CollectionItemSpec({required this.code, required this.title});

  final String code;
  final String title;
}

enum _DownloadFormat {
  epub('epub', 'ePubs'),
  pdf('pdf', 'PDFs');

  const _DownloadFormat(this.name, this.folderRootName);

  final String name;
  final String folderRootName;

  String fileName(String code) => 'en_$code.$name';

  String sourceUrl(String code) {
    return 'https://media2.egwwritings.org/$name/en_$code.$name';
  }
}

class _DownloadResult {
  const _DownloadResult({
    required this.success,
    required this.unavailable,
    this.error,
    this.fileSize,
  });

  final bool success;
  final bool unavailable;
  final String? error;
  final int? fileSize;
}

class EgwCollectionFetchException implements Exception {
  const EgwCollectionFetchException({
    required this.url,
    required this.statusCode,
  });

  final String url;
  final int statusCode;

  bool get isForbidden => statusCode == HttpStatus.forbidden;

  String get userFacingMessage {
    if (isForbidden) {
      return 'EGW site refused this request. Open the collection in a browser or try again later.';
    }
    return 'EGW collection discovery failed with HTTP $statusCode.';
  }

  String get diagnosticDetails => 'Failed URL: $url\nStatus code: $statusCode';

  @override
  String toString() => '$userFacingMessage\n$diagnosticDetails';
}
