import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../library/data/library_catalog_service.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../data/elibrary_download_service.dart';
import '../data/elibrary_storage_policy.dart';
import 'big_progress_bar.dart';
import 'library_indexing_prompt_dialogs.dart';

class ELibraryDownloadScreen extends StatefulWidget {
  const ELibraryDownloadScreen({super.key});

  @override
  State<ELibraryDownloadScreen> createState() => _ELibraryDownloadScreenState();
}

class _ELibraryDownloadScreenState extends State<ELibraryDownloadScreen> {
  bool _running = false;
  bool _cancelRequested = false;
  bool _hasStartedDownload = false;
  bool _loadingPolicy = true;
  ELibraryDownloadProgress? _progress;
  ELibraryDownloadReport? _report;
  String? _error;
  ELibraryStoragePolicy _storagePolicy = ELibraryStoragePolicy.saveSpace;
  int _pendingIndexCount = 0;
  bool _indexing = false;
  int _indexCompleted = 0;
  int _indexTotal = 0;
  String? _indexCurrentTitle;
  ({int indexed, int skipped, int failed})? _indexResult;

  @override
  void initState() {
    super.initState();
    _loadStoragePolicy();
  }

  Future<void> _loadStoragePolicy() async {
    try {
      final policy = await LocalSettingsStore.instance
          .loadELibraryStoragePolicy();
      if (!mounted) return;
      setState(() {
        _storagePolicy = policy;
        _loadingPolicy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPolicy = false);
    }
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_running) return;
    setState(() {
      _running = true;
      _cancelRequested = false;
      _error = null;
      _report = null;
      _hasStartedDownload = true;
    });

    try {
      final report = await ELibraryDownloadService.instance.run(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _progress = progress);
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() => _report = report);
      final snackMessage = report.failedCount > 0
          ? 'eLibrary download incomplete'
          : report.unavailableCount > 0
          ? 'eLibrary download completed with warnings'
          : 'eLibrary download complete';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$snackMessage in ${report.elapsedSeconds.toStringAsFixed(1)}s',
          ),
        ),
      );
      await _checkPendingIndexing();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('eLibrary download failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  void _cancelDownload() {
    if (!_running) return;
    setState(() => _cancelRequested = true);
  }

  Future<void> _checkPendingIndexing() async {
    final pending = await LibraryCatalogService.instance
        .countUnindexedManagedItems();
    if (!mounted) return;
    setState(() => _pendingIndexCount = pending);
    if (pending <= 0) return;
    final action = await showLibraryIndexingPromptDialog(
      context,
      pendingCount: pending,
    );
    if (!mounted || action != LibraryIndexingPromptAction.indexNow) return;
    await _runIndexing();
  }

  Future<void> _runIndexing() async {
    if (_indexing) return;
    setState(() {
      _indexing = true;
      _indexCompleted = 0;
      _indexTotal = 0;
      _indexCurrentTitle = null;
      _indexResult = null;
    });
    final result = await CommentaryResearchLibraryService.instance
        .indexLocalCatalogedEpubs(
          onProgress: (completed, total, currentTitle) {
            if (!mounted) return;
            setState(() {
              _indexCompleted = completed;
              _indexTotal = total;
              _indexCurrentTitle = currentTitle;
            });
          },
        );
    if (!mounted) return;
    final pending = await LibraryCatalogService.instance
        .countUnindexedManagedItems();
    if (!mounted) return;
    setState(() {
      _indexing = false;
      _indexResult = result;
      _pendingIndexCount = pending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = _progress;
    final report = _report;

    return Scaffold(
      appBar: AppBar(
        title: const Text('eLibrary Downloads'),
        centerTitle: true,
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EGW / Commentary downloads',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This screen downloads EGW/Commentary EPUB and PDF content. EPUB is preferred when available, TXT/HTML fallback is used only when EPUB is missing or selected, and imported works stay in eLibrary.db for search, reading, tagging, and navigation.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Destination: LibraryRoot/eLibrary_Downloads',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Source-file cleanup policy (future behavior)',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_loadingPolicy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(),
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Saved preference: ${_storagePolicy.label}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Source-file cleanup only affects downloaded EPUB/PDF files. It does not change imported eLibrary.db content, and this preference is stored for future cleanup behavior only.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Downloaded source files can be kept for backup or re-import. Imported works always remain in eLibrary.db for reading, search, tagging, and navigation.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Format guidance', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      '• EPUB: import into the library database, then removable after verified success.\n'
                      '• TXT/HTML: import cleaned text into the library database, then removable after verified success.\n'
                      '• PDF: keep only when original page layout or page images are needed.\n'
                      '• CaptureClipper HTML imports: use eLibrary Setup, not this screen.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_running) ...[
                      BigProgressBar(
                        value: (progress?.totalPlannedCount ?? 0) > 0
                            ? (progress!.completedCount /
                                      progress.totalPlannedCount)
                                  .clamp(0.0, 1.0)
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        (progress?.totalPlannedCount ?? 0) > 0
                            ? '${((progress!.completedCount / progress.totalPlannedCount) * 100).round()}%'
                            : 'Starting…',
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(progress?.statusMessage ?? 'Starting download...'),
                      const SizedBox(height: 8),
                      Text(
                        '${progress?.currentCollection ?? 'Collection'} '
                        '${progress?.collectionIndex ?? 0}/${progress?.collectionTotal ?? 0}',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Discovered: ${progress?.discoveredCount ?? 0}  '
                        'Downloaded: ${progress?.downloadedCount ?? 0}  '
                        'Skipped: ${progress?.skippedCount ?? 0}  '
                        'Unavailable in selected format: ${progress?.unavailableCount ?? 0}  '
                        'Failed: ${progress?.failedCount ?? 0}',
                      ),
                      const SizedBox(height: 4),
                      Text('Current file: ${progress?.currentFile ?? '-'}'),
                      const SizedBox(height: 4),
                      Text(
                        'Elapsed: ${(progress?.elapsedSeconds ?? 0).toStringAsFixed(1)}s',
                      ),
                    ] else if (report != null) ...[
                      Text(
                        'Completed in ${report.elapsedSeconds.toStringAsFixed(1)}s',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Downloaded: ${report.filesDownloaded.length}'),
                      Text('Skipped: ${report.filesSkipped.length}'),
                      Text(
                        'Unavailable in selected format: ${report.filesUnavailable.length}',
                      ),
                      Text('Failed: ${report.failures.length}'),
                      const SizedBox(height: 8),
                      SelectableText(report.reportFilePath),
                    ] else if (_error != null) ...[
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ] else if (!_hasStartedDownload) ...[
                      Text(
                        'Tap Start Download to begin an EGW/Commentary download run. Existing downloaded books are preserved and skipped when already current, and imported works are stored in eLibrary.db for reading, search, tagging, and navigation.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No download run starts until you choose Start Download.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Ready to run again when you tap Run Again.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (_indexing) ...[
                      const SizedBox(height: 16),
                      IndexingProgressStatus(
                        completed: _indexCompleted,
                        total: _indexTotal,
                        currentTitle: _indexCurrentTitle,
                      ),
                    ],
                    if (!_indexing && _indexResult != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Indexing complete — ${_indexResult!.indexed} indexed, '
                        '${_indexResult!.skipped} skipped, ${_indexResult!.failed} failed',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                    if (!_indexing) ...[
                      const SizedBox(height: 16),
                      LibraryIndexingPendingCard(
                        pendingCount: _pendingIndexCount,
                        busy: _indexing,
                        onIndexNow: _runIndexing,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton(
                          onPressed: _running ? null : _startDownload,
                          child: Text(
                            _report == null ? 'Start Download' : 'Run Again',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _running ? _cancelDownload : null,
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupLeading(BuildContext context) {
    final inset = defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0;
    return Padding(
      padding: EdgeInsets.only(left: inset),
      child: const BackButton(),
    );
  }

  double _setupLeadingWidth() {
    return 56 + (defaultTargetPlatform == TargetPlatform.macOS ? 48.0 : 0.0);
  }
}
