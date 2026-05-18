import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/database/user_database.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../data/elibrary_duplicate_cleanup_service.dart';
import '../data/elibrary_migration_service.dart';
import '../data/demo_download_service.dart';

class ELibrarySetupScreen extends StatefulWidget {
  const ELibrarySetupScreen({super.key});

  @override
  State<ELibrarySetupScreen> createState() => _ELibrarySetupScreenState();
}

class _ELibrarySetupScreenState extends State<ELibrarySetupScreen> {
  LibraryRootSelection? _selection;
  bool _loading = true;
  bool _running = false;
  bool _indexing = false;
  bool _cancelRequested = false;
  bool _installBooks = true;
  bool _installDevotionals = true;
  bool _installCommentaries = true;
  bool _installMiscCollections = true;
  bool _installPamphlets = true;
  bool _installPeriodicals = true;
  bool _installManuscriptReleases = true;
  bool _installEpub = true;
  bool _installPdf = true;
  DemoDownloadProgress? _progress;
  DemoDownloadReport? _downloadReport;
  LegacyELibraryMigrationReport? _migrationReport;
  ELibraryDuplicateCleanupReport? _cleanupReport;
  String? _setupReportPath;
  String? _indexReportPath;
  String? _error;
  int _indexedCount = 0;
  int _indexingErrors = 0;
  bool _manualIndexing = false;
  String? _manualIndexStatus;
  int _manualIndexCompleted = 0;
  int _manualIndexTotal = 0;
  String? _manualIndexCurrentTitle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _loading = false;
    });
  }

  Future<void> _runManualIndex() async {
    if (_manualIndexing) return;
    setState(() {
      _manualIndexing = true;
      _manualIndexStatus = null;
      _manualIndexCompleted = 0;
      _manualIndexTotal = 0;
      _manualIndexCurrentTitle = null;
    });
    try {
      final result = await CommentaryResearchLibraryService.instance
          .indexLocalCatalogedEpubs(
            onProgress: (completed, total, currentTitle) {
              if (!mounted) return;
              setState(() {
                _manualIndexCompleted = completed;
                _manualIndexTotal = total;
                _manualIndexCurrentTitle = currentTitle;
              });
            },
          );
      if (!mounted) return;
      final String status;
      if (result.indexed == 0 && result.skipped == 0 && result.failed == 0) {
        status = 'Library is already indexed';
      } else {
        status =
            'Indexing complete — ${result.indexed} indexed, ${result.skipped} skipped, ${result.failed} failed';
      }
      setState(() => _manualIndexStatus = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _manualIndexStatus = 'Indexing failed: $error');
    } finally {
      if (mounted) setState(() => _manualIndexing = false);
    }
  }

  Future<void> _chooseRoot() async {
    final selectedPath = await _pickRootFolder();
    if (!mounted || selectedPath == null || selectedPath.path.trim().isEmpty) {
      return;
    }
    await LibraryRootService.instance.setLibraryRoot(
      path: selectedPath.path,
      bookmark: selectedPath.bookmark,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Library root saved and folders created.')),
    );
    await _load();
  }

  Future<({String path, String bookmark})?> _pickRootFolder() async {
    try {
      return await LibraryRootNative.pickFolder();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Folder picker failed: $error')));
      }
      return null;
    }
  }

  void _setPresetAll() {
    setState(() {
      _installBooks = true;
      _installDevotionals = true;
      _installCommentaries = true;
      _installMiscCollections = true;
      _installPamphlets = true;
      _installPeriodicals = true;
      _installManuscriptReleases = true;
      _installEpub = true;
      _installPdf = true;
    });
  }

  void _setPresetEpubOnly() {
    setState(() {
      _installEpub = true;
      _installPdf = false;
    });
  }

  void _setPresetPdfOnly() {
    setState(() {
      _installEpub = false;
      _installPdf = true;
    });
  }

  void _setPresetBoth() {
    setState(() {
      _installEpub = true;
      _installPdf = true;
    });
  }

  void _setPresetSkip() {
    setState(() {
      _installBooks = false;
      _installDevotionals = false;
      _installCommentaries = false;
      _installMiscCollections = false;
      _installPamphlets = false;
      _installPeriodicals = false;
      _installManuscriptReleases = false;
    });
  }

  Future<void> _startSetup() async {
    if (_running) return;
    final selection = _selection;
    if (selection?.path == null || selection?.exists != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a Library Root Folder first.')),
      );
      return;
    }
    final rootPath = selection!.path!;

    setState(() {
      _running = true;
      _indexing = false;
      _cancelRequested = false;
      _error = null;
      _downloadReport = null;
      _migrationReport = null;
      _cleanupReport = null;
      _setupReportPath = null;
      _indexReportPath = null;
      _progress = null;
      _indexedCount = 0;
      _indexingErrors = 0;
    });

    try {
      final migrationReport = await LegacyELibraryMigrationService.instance
          .migrate();
      if (!mounted) return;
      if (migrationReport.filesCopied > 0 ||
          migrationReport.filesRenamedDueToConflict > 0) {
        setState(() => _migrationReport = migrationReport);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Existing eLibrary files were organized into the new folder structure. A report was saved.',
            ),
          ),
        );
      }

      final downloadReport = await DemoDownloadService.instance
          .runProductionSetup(
            installBooks: _installBooks,
            installDevotionals: _installDevotionals,
            installCommentaries: _installCommentaries,
            installMiscCollections: _installMiscCollections,
            installPamphlets: _installPamphlets,
            installPeriodicals: _installPeriodicals,
            installManuscriptReleases: _installManuscriptReleases,
            installEpub: _installEpub,
            installPdf: _installPdf,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
            isCancelled: () => _cancelRequested,
          );

      if (!mounted) return;
      setState(() {
        _downloadReport = downloadReport;
        _indexing = true;
      });

      final cleanupReport = await ELibraryDuplicateCleanupService.instance
          .quarantineDuplicates(
            isCancelled: () => _cancelRequested,
          );

      if (!mounted) return;
      setState(() {
        _cleanupReport = cleanupReport;
        _indexing = true;
      });

      final passageData = await CommentaryResearchLibraryService.instance
          .loadPassage(
            bookId: 1,
            chapter: 1,
            verse: 1,
            bookName: 'Genesis',
            refresh: true,
          );
      if (!mounted) return;
      final db = await UserDatabase.instance.database;
      final failedRows = await db.rawQuery('''
        SELECT COUNT(*) AS count
        FROM library_items
        WHERE folder_type IN ('commentary', 'research')
          AND index_status = 'failed'
          AND deleted_at IS NULL
      ''');
      final indexingErrors = (failedRows.first['count'] as num?)?.toInt() ?? 0;
      final indexedCount = [
        passageData.commentary.discoveredCount,
        passageData.research.discoveredCount,
      ].fold<int>(0, (sum, value) => sum + value);

      final completedAt = DateTime.now().toUtc();
      final report = <String, Object?>{
        'started_at': downloadReport.startedAt.toIso8601String(),
        'completed_at': completedAt.toIso8601String(),
        'elapsed_seconds': downloadReport.elapsedSeconds,
        'selected_collections': <String>[
          if (_installBooks) 'EGW Books',
          if (_installDevotionals) 'EGW Devotionals',
          if (_installCommentaries) 'EGW Commentaries',
          if (_installMiscCollections) 'EGW Misc Collections',
          if (_installPamphlets) 'EGW Pamphlets',
          if (_installPeriodicals) 'EGW Periodicals',
          if (_installManuscriptReleases) 'EGW Manuscript Releases',
        ],
        'selected_formats': <String>[
          if (_installEpub) 'EPUB',
          if (_installPdf) 'PDF',
        ],
        'source_collection_urls': downloadReport.sourceCollectionUrls,
        'destination_root': downloadReport.destinationRoot,
        'total_links_discovered': downloadReport.totalLinksDiscovered,
        'epub_downloaded_count': downloadReport.epubDownloadedCount,
        'pdf_downloaded_count': downloadReport.pdfDownloadedCount,
        'skipped_existing_count': downloadReport.skippedExistingCount,
        'failed_count': downloadReport.failedCount,
        'indexed_count': indexedCount,
        'indexing_errors': indexingErrors,
        'migration_report_path': _migrationReport?.reportFilePath,
        'files_downloaded': downloadReport.filesDownloaded
            .map((item) => item.toJson())
            .toList(growable: false),
        'files_skipped': downloadReport.filesSkipped
            .map((item) => item.toJson())
            .toList(growable: false),
        'failures': downloadReport.failures
            .map((item) => item.toJson())
            .toList(growable: false),
        'destination_folders': downloadReport.destinationFolders,
        'download_report_path': downloadReport.reportFilePath,
        'cleanup_report_path': _cleanupReport?.reportFilePath,
        'index_report_path': passageData.indexReportPath,
      };

      final reportPath = p.join(
        rootPath,
        'download_reports',
        'production_elibrary_setup_${_timestamp(completedAt)}.json',
      );
      final reportFile = File(reportPath);
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
      );

      if (!mounted) return;
      setState(() {
        _setupReportPath = reportPath;
        _indexReportPath = passageData.indexReportPath;
        _indexedCount = indexedCount;
        _indexingErrors = indexingErrors;
        _indexing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'eLibrary setup finished in ${downloadReport.elapsedSeconds.toStringAsFixed(1)}s',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('eLibrary setup failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _indexing = false;
        });
      }
    }
  }

  void _cancelSetup() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
  }

  Widget _pathLine(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText('$label: ${value ?? "(not set)"}'),
    );
  }

  String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selection = _selection;

    return Scaffold(
      appBar: AppBar(title: const Text('eLibrary Setup'), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selection?.path == null
                              ? 'No Library Root selected'
                              : selection!.exists
                              ? 'Library Root selected'
                              : 'Library Root missing, reconnect needed',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        _pathLine('Root', selection?.path),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            FilledButton(
                              onPressed: _chooseRoot,
                              child: const Text('Choose Library Folder'),
                            ),
                            OutlinedButton(
                              onPressed: _running ? null : _startSetup,
                              child: const Text('Install Selected'),
                            ),
                            OutlinedButton(
                              onPressed: _running ? _cancelSetup : null,
                              child: const Text('Cancel'),
                            ),
                            OutlinedButton(
                              onPressed: (_running || _manualIndexing)
                                  ? null
                                  : _runManualIndex,
                              child: Text(
                                _manualIndexing
                                    ? 'Indexing eLibrary books...'
                                    : 'Index New/Changed Books',
                              ),
                            ),
                          ],
                        ),
                        if (_manualIndexing) ...[
                          const SizedBox(height: 12),
                          LinearProgressIndicator(
                            value: _manualIndexTotal > 0
                                ? _manualIndexCompleted / _manualIndexTotal
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _manualIndexTotal > 0
                                ? 'Indexing $_manualIndexCompleted of $_manualIndexTotal'
                                : 'Preparing...',
                          ),
                          if (_manualIndexCurrentTitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Current: $_manualIndexCurrentTitle',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                        if (_manualIndexStatus != null) ...[
                          const SizedBox(height: 8),
                          Text(_manualIndexStatus!),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download choices',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Choose your EGW collections and formats, then use Install all or Install Selected to begin.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            ActionChip(
                              label: const Text('Install all'),
                              onPressed: _running
                                  ? null
                                  : () {
                                      _setPresetAll();
                                      _startSetup();
                                    },
                            ),
                            ActionChip(
                              label: const Text('EPUB only'),
                              onPressed: _running ? null : _setPresetEpubOnly,
                            ),
                            ActionChip(
                              label: const Text('PDF only'),
                              onPressed: _running ? null : _setPresetPdfOnly,
                            ),
                            ActionChip(
                              label: const Text('EPUB and PDF'),
                              onPressed: _running ? null : _setPresetBoth,
                            ),
                            ActionChip(
                              label: const Text('Skip EGW download'),
                              onPressed: _running ? null : _setPresetSkip,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: _installBooks,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installBooks = value ?? false,
                                ),
                          title: const Text('Install EGW Books'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installDevotionals,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installDevotionals = value ?? false,
                                ),
                          title: const Text('Install EGW Devotionals'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installCommentaries,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installCommentaries = value ?? false,
                                ),
                          title: const Text('Install EGW Commentaries'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installMiscCollections,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () =>
                                      _installMiscCollections = value ?? false,
                                ),
                          title: const Text('Install EGW Misc Collections'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installPamphlets,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installPamphlets = value ?? false,
                                ),
                          title: const Text('Install EGW Pamphlets'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installPeriodicals,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installPeriodicals = value ?? false,
                                ),
                          title: const Text('Install EGW Periodicals'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installManuscriptReleases,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () =>
                                      _installManuscriptReleases =
                                          value ?? false,
                                ),
                          title: const Text('Install EGW Manuscript Releases'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const Divider(height: 24),
                        CheckboxListTile(
                          value: _installEpub,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installEpub = value ?? false,
                                ),
                          title: const Text('EPUB'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        CheckboxListTile(
                          value: _installPdf,
                          onChanged: _running
                              ? null
                              : (value) => setState(
                                  () => _installPdf = value ?? false,
                                ),
                          title: const Text('PDF'),
                          contentPadding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This app does not include or redistribute these books. If you choose to download them, the files are downloaded directly from the official EGW Writings website into your own local eLibrary folder. Please honor the terms and notices of the source website and do not redistribute the downloaded files.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_running) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_indexing) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            const Text('Indexing library files...'),
                          ] else ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            Text(
                              _progress?.statusMessage ??
                                  'Preparing download...',
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '${_progress?.currentCollection ?? 'Collection'} '
                            '${_progress?.collectionIndex ?? 0}/${_progress?.collectionTotal ?? 0}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Downloaded: ${_progress?.downloadedCount ?? 0}  '
                            'Skipped: ${_progress?.skippedCount ?? 0}  '
                            'Failed: ${_progress?.failedCount ?? 0}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Current file: ${_progress?.currentFile ?? '-'}',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Elapsed: ${(_progress?.elapsedSeconds ?? 0).toStringAsFixed(1)}s',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_downloadReport != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Setup complete',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Downloaded: ${_downloadReport!.filesDownloaded.length}',
                          ),
                          Text(
                            'Skipped existing: ${_downloadReport!.filesSkipped.length}',
                          ),
                          Text('Failed: ${_downloadReport!.failures.length}'),
                          Text('Indexed: $_indexedCount'),
                          Text('Indexing errors: $_indexingErrors'),
                          Text(
                            'Elapsed: ${_downloadReport!.elapsedSeconds.toStringAsFixed(1)}s',
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            _setupReportPath ?? _downloadReport!.reportFilePath,
                          ),
                          if (_indexReportPath != null) ...[
                            const SizedBox(height: 8),
                            SelectableText(_indexReportPath!),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'To add your own files later, place them in the appropriate folder and then tap Index New/Changed Books.',
                        ),
                        SizedBox(height: 12),
                        SelectableText(
                          'Commentary EPUBs:\nLibraryRoot/ePubs/Commentaries/User/\n\nCommentary PDFs:\nLibraryRoot/PDFs/Commentaries/User/\n\nResearch EPUBs:\nLibraryRoot/ePubs/Research/User/\n\nResearch PDFs:\nLibraryRoot/PDFs/Research/User/',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
