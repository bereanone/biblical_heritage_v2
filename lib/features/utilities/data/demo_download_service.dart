import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import 'elibrary_folder_policy.dart';

const bool _debugDemoDownloadLogs = false;

class DemoDownloadService {
  DemoDownloadService._();

  static final DemoDownloadService instance = DemoDownloadService._();

  static const List<_CollectionSpec> _collections = <_CollectionSpec>[
    _CollectionSpec(
      label: 'EGW Books',
      url: 'https://egwwritings.org/allCollection/en/4',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/4',
      folderName: 'EGW_Books',
    ),
    _CollectionSpec(
      label: 'EGW Devotionals',
      url: 'https://egwwritings.org/allCollection/en/1227',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1227',
      folderName: 'EGW_Devotionals',
    ),
    _CollectionSpec(
      label: 'Commentaries',
      url: 'https://egwwritings.org/allCollection/en/1371',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1371',
      folderName: 'Commentaries',
    ),
    _CollectionSpec(
      label: 'EGW Misc Collections',
      url: 'https://egwwritings.org/allCollection/en/10',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/10',
      folderName: 'EGW_Misc_Collections',
    ),
    _CollectionSpec(
      label: 'EGW Pamphlets',
      url: 'https://egwwritings.org/allCollection/en/8',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/8',
      folderName: 'EGW_Pamphlets',
    ),
    _CollectionSpec(
      label: 'EGW Periodicals',
      url: 'https://egwwritings.org/allCollection/en/5',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/5',
      folderName: 'EGW_Periodicals',
    ),
    _CollectionSpec(
      label: 'EGW Manuscript Releases',
      url: 'https://egwwritings.org/allCollection/en/1376',
      fallbackUrl: 'https://next.egwwritings.org/allCollection/en/1376',
      folderName: 'EGW_Manuscript_Releases',
    ),
  ];

  Future<DemoDownloadReport> run({
    bool refreshExisting = false,
    bool dryRun = false,
    void Function(DemoDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final destinationRoot = p.join(rootPath, 'TEST_Downloads');
    return _runDownloads(
      startedAt: startedAt,
      stopwatch: stopwatch,
      destinationRoot: destinationRoot,
      reportPrefix: 'demo_download_report',
      refreshExisting: refreshExisting,
      dryRun: dryRun,
      selectedCollections: _collections,
      selectedFormats: _DownloadFormat.values,
      onProgress: onProgress,
      isCancelled: isCancelled,
      userAgent: 'StudyBible2 Demo Downloader',
      productionLayout: false,
    );
  }

  Future<DemoDownloadReport> runProductionSetup({
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
    void Function(DemoDownloadProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final stopwatch = Stopwatch()..start();
    final rootPath = await _writableLibraryRootPath();
    if (rootPath == null) {
      throw StateError('Library Root Folder is not selected.');
    }

    final selectedCollections = <_CollectionSpec>[
      if (installBooks) _collections[0],
      if (installDevotionals) _collections[1],
      if (installCommentaries) _collections[2],
      if (installMiscCollections) _collections[3],
      if (installPamphlets) _collections[4],
      if (installPeriodicals) _collections[5],
      if (installManuscriptReleases) _collections[6],
    ];
    final selectedFormats = <_DownloadFormat>[
      if (installEpub) _DownloadFormat.epub,
      if (installPdf) _DownloadFormat.pdf,
    ];

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

  Future<String?> _writableLibraryRootPath() async {
    final accessible = await LibraryRootService.instance
        .accessibleLibraryRootPath();
    if (accessible != null && accessible.trim().isNotEmpty) return accessible;
    final selection = await LibraryRootService.instance.loadSelection();
    if (selection.path == null || !selection.exists) return null;
    return selection.path;
  }

  Future<DemoDownloadReport> _runDownloads({
    required DateTime startedAt,
    required Stopwatch stopwatch,
    required String destinationRoot,
    required String reportPrefix,
    required bool refreshExisting,
    required bool dryRun,
    required List<_CollectionSpec> selectedCollections,
    required List<_DownloadFormat> selectedFormats,
    required void Function(DemoDownloadProgress progress)? onProgress,
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

    final report = _MutableDemoDownloadReport(
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

    try {
      for (
        var collectionIndex = 0;
        collectionIndex < selectedCollections.length;
        collectionIndex++
      ) {
        if (isCancelled?.call() ?? false) break;
        final collection = selectedCollections[collectionIndex];
        if (_debugDemoDownloadLogs) {
          debugPrint(
            '[DemoDownload] discovering ${collection.label} (${collection.url})',
          );
        }
        onProgress?.call(
          DemoDownloadProgress(
            currentCollection: collection.label,
            collectionIndex: collectionIndex + 1,
            collectionTotal: selectedCollections.length,
            discoveredCount: report.totalLinksDiscovered,
            downloadedCount: report.downloadedCount,
            skippedCount: report.skippedExistingCount,
            failedCount: report.failedCount,
            currentFile: 'discovering...',
            elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
            statusMessage: 'Discovering ${collection.label} links...',
          ),
        );

        final discovery = await _discoverBooks(
          client: client,
          collection: collection,
        );
        final books = discovery.books;
        report.usedStaticPageDiscovery = discovery.usedStaticPageDiscovery;
        if (discovery.usedFallbackManifest) {
          report.usedFallbackManifest = true;
        }
        if (_debugDemoDownloadLogs) {
          debugPrint(
            '[DemoDownload] ${collection.label} books discovered=${books.length}',
          );
        }

        for (var bookIndex = 0; bookIndex < books.length; bookIndex++) {
          if (isCancelled?.call() ?? false) break;
          final book = books[bookIndex];
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
                : p.join(
                    format.folderRootName,
                    collection.folderName,
                    format.fileName(book.code),
                  );
            final destinationPath = p.join(destinationRoot, relativePath);
            final destinationFile = File(destinationPath);

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
              DemoDownloadProgress(
                currentCollection: collection.label,
                collectionIndex: collectionIndex + 1,
                collectionTotal: selectedCollections.length,
                discoveredCount: report.totalLinksDiscovered,
                downloadedCount: report.downloadedCount,
                skippedCount: report.skippedExistingCount,
                failedCount: report.failedCount,
                currentFile: '${book.code}.${format.name}',
                elapsedSeconds: stopwatch.elapsedMilliseconds / 1000.0,
                statusMessage:
                    'Downloading ${collection.label} ${book.title} (${format.name.toUpperCase()})',
              ),
            );

            final downloadResult = await _downloadFile(
              client: client,
              sourceUrl: sourceUrl,
              destinationFile: stagingFile,
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
                    DemoDownloadFileRecord(
                      title: book.title,
                      collection: collection.label,
                      format: format.name,
                      sourceUrl: sourceUrl,
                      relativePath: relativePath,
                      fileName: p.basename(destinationPath),
                      fileSize: destinationSize,
                      sha256: destinationHash,
                      status: dryRun ? 'would_skip_existing' : 'skipped_existing',
                      error: null,
                    ),
                  );
                  await stagingFile.delete();
                  if (_debugDemoDownloadLogs) {
                    debugPrint(
                      '[DemoDownload] skipped existing ${collection.label} ${book.code} ${format.name}',
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
                  DemoDownloadFileRecord(
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
                    error: 'Destination file already exists with different content.',
                  ),
                );
                if (_debugDemoDownloadLogs) {
                  debugPrint(
                    '[DemoDownload] quarantined conflict ${collection.label} ${book.code} ${format.name}',
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
                DemoDownloadFileRecord(
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
            } else {
              report.failedCount += 1;
              report.failures.add(
                DemoDownloadFileRecord(
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

            if (_debugDemoDownloadLogs) {
              debugPrint(
                '[DemoDownload] ${collection.label} ${book.code} ${format.name} '
                '${downloadResult.success ? 'ok' : 'failed'} '
                'downloaded=${report.downloadedCount} '
                'skipped=${report.skippedExistingCount} '
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
        Directory(p.join(epubRoot.path, 'Commentaries', 'EGW_Commentaries')),
        Directory(p.join(epubRoot.path, 'Commentaries', 'User')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Books')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Devotionals')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Misc_Collections')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Pamphlets')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Periodicals')),
        Directory(p.join(epubRoot.path, 'Research', 'EGW_Manuscript_Releases')),
        Directory(p.join(epubRoot.path, 'Research', 'User')),
        Directory(p.join(pdfRoot.path, 'Commentaries', 'EGW_Commentaries')),
        Directory(p.join(pdfRoot.path, 'Commentaries', 'User')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Books')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Devotionals')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Misc_Collections')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Pamphlets')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Periodicals')),
        Directory(p.join(pdfRoot.path, 'Research', 'EGW_Manuscript_Releases')),
        Directory(p.join(pdfRoot.path, 'Research', 'User')),
      ]);
    } else {
      folders.addAll([
        Directory(p.join(epubRoot.path, 'EGW_Books')),
        Directory(p.join(epubRoot.path, 'EGW_Devotionals')),
        Directory(p.join(epubRoot.path, 'Commentaries')),
        Directory(p.join(pdfRoot.path, 'EGW_Books')),
        Directory(p.join(pdfRoot.path, 'EGW_Devotionals')),
        Directory(p.join(pdfRoot.path, 'Commentaries')),
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
          'ePubs/Commentaries/EGW_Commentaries',
          'ePubs/Commentaries/User',
          'ePubs/Research/EGW_Books',
          'ePubs/Research/EGW_Devotionals',
          'ePubs/Research/EGW_Misc_Collections',
          'ePubs/Research/EGW_Pamphlets',
          'ePubs/Research/EGW_Periodicals',
          'ePubs/Research/EGW_Manuscript_Releases',
          'ePubs/Research/User',
          'PDFs/Commentaries/EGW_Commentaries',
          'PDFs/Commentaries/User',
          'PDFs/Research/EGW_Books',
          'PDFs/Research/EGW_Devotionals',
          'PDFs/Research/EGW_Misc_Collections',
          'PDFs/Research/EGW_Pamphlets',
          'PDFs/Research/EGW_Periodicals',
          'PDFs/Research/EGW_Manuscript_Releases',
          'PDFs/Research/User',
        ].map((relative) => p.join(destinationRoot, relative)),
      );
    } else {
      folders.addAll(
        selectedCollections.expand(
          (spec) => <String>[
            p.join(epubRoot, spec.folderName),
            p.join(pdfRoot, spec.folderName),
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
    final librarySection = collection.folderName == 'Commentaries'
        ? 'Commentaries'
        : 'Research';
    return p.join(
      format.folderRootName,
      librarySection,
      collection.folderName,
      format.fileName(bookCode),
    );
  }

  Future<_DiscoveryResult<_BookSource>> _discoverBooks({
    required HttpClient client,
    required _CollectionSpec collection,
  }) async {
    final primary = await _discoverBookPaths(
      client: client,
      url: collection.url,
    );
    var bookPaths = primary.bookPaths;
    var bookPathsBaseUrl = primary.baseUrl;
    var usedFallback = false;
    if (bookPaths.isEmpty) {
      final fallback = await _discoverBookPaths(
        client: client,
        url: collection.fallbackUrl,
      );
      if (fallback.bookPaths.isNotEmpty) {
        bookPaths = fallback.bookPaths;
        bookPathsBaseUrl = fallback.baseUrl;
        usedFallback = true;
      }
    }
    final books = <_BookSource>[];
    for (final path in bookPaths) {
      final bookUrl = Uri.parse(bookPathsBaseUrl).resolve(path).toString();
      final bookHtml = await _fetchText(client, bookUrl);
      final code = _extractBookCode(bookHtml);
      if (code == null || code.trim().isEmpty) continue;
      books.add(
        _BookSource(
          title: _extractBookTitle(bookHtml) ?? code,
          code: code.trim(),
          pageUrl: bookUrl,
        ),
      );
    }
    return _DiscoveryResult<_BookSource>(
      books: books,
      usedStaticPageDiscovery: primary.usedStaticPageDiscovery,
      usedFallbackManifest: usedFallback,
    );
  }

  Future<_BookPathDiscovery> _discoverBookPaths({
    required HttpClient client,
    required String url,
  }) async {
    final collectionHtml = await _fetchText(client, url);
    final bookPaths = <String>{};
    for (final match in RegExp(
      r'href="([^"]*?/book/b\d+)"',
      caseSensitive: false,
    ).allMatches(collectionHtml)) {
      final href = match.group(1);
      if (href == null || href.trim().isEmpty) continue;
      bookPaths.add(href);
    }
    return _BookPathDiscovery(
      bookPaths: bookPaths.toList(growable: false),
      baseUrl: url,
      usedStaticPageDiscovery: true,
    );
  }

  Future<_DownloadResult> _downloadFile({
    required HttpClient client,
    required String sourceUrl,
    required File destinationFile,
  }) async {
    try {
      final request = await client.getUrl(Uri.parse(sourceUrl));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        if (await destinationFile.exists()) {
          await destinationFile.delete();
        }
        return _DownloadResult(
          success: false,
          error: 'HTTP ${response.statusCode} for $sourceUrl',
        );
      }
      final sink = destinationFile.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();
      return _DownloadResult(
        success: true,
        fileSize: await destinationFile.length(),
      );
    } catch (e) {
      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }
      return _DownloadResult(success: false, error: e.toString());
    }
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

  Future<String> _fetchText(HttpClient client, String url) async {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.transform(utf8.decoder).join();
  }

  String? _extractBookCode(String html) {
    final codeMatch = RegExp(
      r'Book code:\s*([A-Za-z0-9]+)',
      caseSensitive: false,
    ).firstMatch(html);
    return codeMatch?.group(1);
  }

  String? _extractBookTitle(String html) {
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

class DemoDownloadReport {
  const DemoDownloadReport({
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
    required this.failedCount,
    required this.filesDownloaded,
    required this.filesSkipped,
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
  final int failedCount;
  final List<DemoDownloadFileRecord> filesDownloaded;
  final List<DemoDownloadFileRecord> filesSkipped;
  final List<DemoDownloadFileRecord> filesQuarantined;
  final List<DemoDownloadFileRecord> failures;
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
    'failed_count': failedCount,
    'files_downloaded': filesDownloaded
        .map((item) => item.toJson())
        .toList(growable: false),
    'files_skipped': filesSkipped
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

class DemoDownloadFileRecord {
  const DemoDownloadFileRecord({
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

class DemoDownloadProgress {
  const DemoDownloadProgress({
    required this.currentCollection,
    required this.collectionIndex,
    required this.collectionTotal,
    required this.discoveredCount,
    required this.downloadedCount,
    required this.skippedCount,
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
  final int failedCount;
  final String currentFile;
  final double elapsedSeconds;
  final String statusMessage;
}

class _MutableDemoDownloadReport {
  _MutableDemoDownloadReport({
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
  int quarantinedCount = 0;
  int failedCount = 0;
  final List<DemoDownloadFileRecord> filesDownloaded =
      <DemoDownloadFileRecord>[];
  final List<DemoDownloadFileRecord> filesSkipped = <DemoDownloadFileRecord>[];
  final List<DemoDownloadFileRecord> filesQuarantined =
      <DemoDownloadFileRecord>[];
  final List<DemoDownloadFileRecord> failures = <DemoDownloadFileRecord>[];
  bool usedStaticPageDiscovery = false;
  bool usedFallbackManifest = false;
  bool usedDirectUrlVerification = true;
  final List<String> destinationFolders;

  DemoDownloadReport toReport(String reportFilePath) {
    final done = completedAt ?? DateTime.now().toUtc();
    return DemoDownloadReport(
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
      failedCount: failedCount,
      filesDownloaded: List<DemoDownloadFileRecord>.unmodifiable(
        filesDownloaded,
      ),
      filesSkipped: List<DemoDownloadFileRecord>.unmodifiable(filesSkipped),
      filesQuarantined: List<DemoDownloadFileRecord>.unmodifiable(
        filesQuarantined,
      ),
      failures: List<DemoDownloadFileRecord>.unmodifiable(failures),
      usedStaticPageDiscovery: usedStaticPageDiscovery,
      usedFallbackManifest: usedFallbackManifest,
      usedDirectUrlVerification: usedDirectUrlVerification,
      quarantinedCount: quarantinedCount,
      destinationFolders: List<String>.unmodifiable(destinationFolders),
      reportFilePath: reportFilePath,
    );
  }
}

class _CollectionSpec {
  const _CollectionSpec({
    required this.label,
    required this.url,
    required this.fallbackUrl,
    required this.folderName,
  });

  final String label;
  final String url;
  final String fallbackUrl;
  final String folderName;
}

class _BookPathDiscovery {
  const _BookPathDiscovery({
    required this.bookPaths,
    required this.baseUrl,
    required this.usedStaticPageDiscovery,
  });

  final List<String> bookPaths;
  final String baseUrl;
  final bool usedStaticPageDiscovery;
}

class _DiscoveryResult<T> {
  const _DiscoveryResult({
    required this.books,
    required this.usedStaticPageDiscovery,
    required this.usedFallbackManifest,
  });

  final List<T> books;
  final bool usedStaticPageDiscovery;
  final bool usedFallbackManifest;
}

class _BookSource {
  const _BookSource({
    required this.title,
    required this.code,
    required this.pageUrl,
  });

  final String title;
  final String code;
  final String pageUrl;
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
  const _DownloadResult({required this.success, this.error, this.fileSize});

  final bool success;
  final String? error;
  final int? fileSize;
}
