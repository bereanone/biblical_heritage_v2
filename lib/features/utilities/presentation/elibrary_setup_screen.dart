import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/database/user_database.dart';
import '../../library/data/library_catalog_service.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../data/elibrary_file_management_service.dart';
import '../data/elibrary_duplicate_cleanup_service.dart';
import '../data/elibrary_install_estimate_repository.dart';
import '../data/elibrary_migration_service.dart';
import '../data/elibrary_download_service.dart';
import '../data/elibrary_storage_policy.dart';
import '../data/pioneer_captured_html_import_availability_service.dart';
import '../data/pioneer_captured_html_import_folder_service.dart';
import '../data/pioneer_text_import_service.dart';
import 'pioneer_captured_html_import_dialogs.dart';
import 'pioneer_captured_html_import_review_screen.dart';
import 'library_root_setup_screen.dart';

const _sourceCleanupDeferredMessage =
    'Future-facing cleanup policy: imported works stay in eLibrary.db and only downloaded source files are eligible for removal.';

enum _ELibraryRunCompletionStatus {
  cleanSuccess,
  completedWithWarnings,
  failedOrIncomplete,
}

class CaptureClipperFolderDetails extends StatelessWidget {
  const CaptureClipperFolderDetails({
    super.key,
    required this.loading,
    required this.path,
    required this.access,
    required this.status,
  });

  final bool loading;
  final String? path;
  final String? access;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget pathLine(String label, String? value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SelectableText('$label: ${value ?? "(not set)"}'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading)
          const LinearProgressIndicator()
        else ...[
          pathLine('Folder path', path),
          pathLine('Folder access', access),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              status!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class CaptureClipperImportButton extends StatelessWidget {
  const CaptureClipperImportButton({
    super.key,
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String? label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = label;
    if (text == null) {
      return const SizedBox.shrink();
    }
    return FilledButton(onPressed: busy ? null : onPressed, child: Text(text));
  }
}

class ELibrarySetupScreen extends StatefulWidget {
  const ELibrarySetupScreen({super.key});

  @override
  State<ELibrarySetupScreen> createState() => _ELibrarySetupScreenState();
}

class _ELibrarySetupScreenState extends State<ELibrarySetupScreen> {
  LibraryRootSelection? _selection;
  bool _loading = true;
  bool _loadingStorageSummary = true;
  bool _running = false;
  bool _indexing = false;
  bool _removingFiles = false;
  bool _cancelRequested = false;
  bool _installBooks = false;
  bool _installDevotionals = false;
  bool _installCommentaries = false;
  bool _installMiscCollections = false;
  bool _installPamphlets = false;
  bool _installPeriodicals = false;
  bool _installManuscriptReleases = false;
  bool _installEpub = false;
  bool _installPdf = false;
  bool _refreshingEstimateCache = false;
  bool _loadingCaptureFolder = true;
  bool _loadingCaptureImportAvailability = true;
  bool _captureFolderBusy = false;
  ELibraryStoragePolicy _storagePolicy = ELibraryStoragePolicy.saveSpace;
  Map<String, Map<String, ELibraryInstallEstimateRecord>>
  _estimateCacheByCollection =
      <String, Map<String, ELibraryInstallEstimateRecord>>{};
  ELibraryDownloadProgress? _progress;
  ELibraryDownloadReport? _downloadReport;
  LegacyELibraryMigrationReport? _migrationReport;
  ELibraryDuplicateCleanupReport? _cleanupReport;
  String? _setupReportPath;
  String? _indexReportPath;
  String? _setupStatusMessage;
  String? _selectionWarning;
  ELibraryStorageSummary? _storageSummary;
  String? _error;
  String? _errorDetails;
  int _indexedCount = 0;
  int _indexingErrors = 0;
  bool _manualIndexing = false;
  String? _manualIndexStatus;
  int _manualIndexCompleted = 0;
  int _manualIndexTotal = 0;
  String? _manualIndexCurrentTitle;
  String? _captureFolderPath;
  String? _captureFolderAccess;
  String? _captureFolderStatus;
  PioneerCapturedHtmlAvailableImportReport? _captureImportReport;

  @override
  void initState() {
    super.initState();
    _load();
    _loadEstimateCache();
    _loadCaptureFolderState();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final storagePolicy = await LocalSettingsStore.instance
        .loadELibraryStoragePolicy();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _storagePolicy = storagePolicy;
      _loading = false;
    });
    await _loadStorageSummary();
  }

  Future<void> _loadStorageSummary() async {
    if (!mounted) return;
    setState(() => _loadingStorageSummary = true);
    try {
      final summary = await ELibraryFileManagementService.instance
          .computeDownloadedStorageSummary(rootPath: _selection?.path);
      if (!mounted) return;
      setState(() => _storageSummary = summary);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _storageSummary = const ELibraryStorageSummary(
          epubCount: 0,
          epubSizeBytes: 0,
          pdfCount: 0,
          pdfSizeBytes: 0,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _loadingStorageSummary = false);
      }
    }
  }

  Future<void> _loadEstimateCache() async {
    try {
      final cache = await ELibraryInstallEstimateRepository.instance
          .loadByCollectionAndFormat();
      if (!mounted) {
        return;
      }
      setState(() {
        _estimateCacheByCollection = cache;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _estimateCacheByCollection =
            <String, Map<String, ELibraryInstallEstimateRecord>>{};
      });
    }
  }

  Future<void> _loadCaptureFolderState() async {
    setState(() => _loadingCaptureFolder = true);
    try {
      final path = await LocalSettingsStore.instance
          .loadPioneerCapturedHtmlFolderPath();
      final bookmark = await LocalSettingsStore.instance
          .loadPioneerCapturedHtmlFolderBookmark();
      if (!mounted) return;
      setState(() {
        _captureFolderPath = path;
        _captureFolderAccess = path == null
            ? null
            : bookmark == null
            ? 'Not saved'
            : 'Saved';
        _captureFolderStatus = path == null
            ? 'No CaptureClipper folder configured.'
            : 'CaptureClipper folder ready.';
      });
      await _loadCaptureImportAvailability();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _captureFolderPath = null;
        _captureFolderAccess = null;
        _captureFolderStatus = 'Failed to load CaptureClipper folder: $error';
        _captureImportReport = null;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCaptureFolder = false);
      }
    }
  }

  Future<void> _loadCaptureImportAvailability() async {
    if (!mounted) return;
    setState(() => _loadingCaptureImportAvailability = true);
    try {
      final report = await PioneerCapturedHtmlImportAvailabilityService.instance
          .refresh();
      if (!mounted) return;
      setState(() => _captureImportReport = report);
    } catch (_) {
      if (!mounted) return;
      setState(() => _captureImportReport = null);
    } finally {
      if (mounted) {
        setState(() => _loadingCaptureImportAvailability = false);
      }
    }
  }

  Future<void> _chooseCaptureFolder() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      final result = await LibraryRootNative.pickFolder();
      if (result == null) return;
      await LocalSettingsStore.instance.savePioneerCapturedHtmlFolder(
        path: result.path,
        bookmark: result.bookmark,
      );
      await _loadCaptureFolderState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CaptureClipper folder saved.')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _clearCaptureFolder() async {
    if (_captureFolderBusy) return;
    setState(() => _captureFolderBusy = true);
    try {
      await LocalSettingsStore.instance.clearPioneerCapturedHtmlFolder();
      await _loadCaptureFolderState();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CaptureClipper folder cleared.')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _importCaptureFolder({bool repairExistingItems = false}) async {
    if (_captureFolderBusy) return;
    setState(() {
      _captureFolderBusy = true;
      _captureFolderStatus = repairExistingItems
          ? 'Repairing CaptureClipper cloud folders...'
          : 'Scanning CaptureClipper cloud folders...';
    });
    try {
      final report = repairExistingItems
          ? await PioneerCapturedHtmlImportFolderService.instance
                .repairBrokenCaptureClipperItems()
          : await PioneerCapturedHtmlImportFolderService.instance
                .importConfiguredCloudFolder(
                  existingImportPolicy:
                      PioneerExistingImportPolicy.skipExisting,
                );
      if (!mounted) return;
      final summary = report.rootPath.trim().isEmpty
          ? (repairExistingItems
                ? 'Repair attempted on stored CaptureClipper items.'
                : 'No CaptureClipper folder is configured.')
          : 'Imported ${report.importedCount}, repaired ${report.repairedCount}, '
                'archived ${report.archivedCount}, skipped ${report.healthySkippedCount}, '
                'invalid ${report.invalidCount}, failed ${report.failedCount}.';
      setState(() => _captureFolderStatus = summary);
      await _loadCaptureImportAvailability();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(summary)));
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _captureFolderStatus = 'CaptureClipper import failed: $error',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CaptureClipper import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureFolderBusy = false);
      }
    }
  }

  Future<void> _reviewCaptureFolderImports() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PioneerCapturedHtmlImportReviewScreen(),
      ),
    );
    if (!mounted) return;
    await _loadCaptureFolderState();
  }

  Future<void> _promptCaptureImports() async {
    final report = _captureImportReport;
    if (report == null || !report.hasAvailableImports) {
      return;
    }

    final selectedImports = await showCaptureClipperImportChooserDialog(
      context,
      report,
    );
    if (!mounted || selectedImports == null || selectedImports.isEmpty) {
      return;
    }

    final result = await PioneerCapturedHtmlImportFolderService.instance
        .importConfiguredCloudFolder(
          selectedFolderPaths: selectedImports.map((item) => item.folderPath),
        );
    if (!mounted) return;
    await _loadCaptureFolderState();
    final imported = result.importedCount;
    final archived = result.archivedCount;
    final firstEntry = result.entries.isEmpty ? null : result.entries.first;
    final entryLabel = firstEntry == null
        ? 'CaptureClipper'
        : '${firstEntry.folderName} — ${firstEntry.title}';
    final reason = firstEntry?.archiveError?.trim().isNotEmpty == true
        ? firstEntry!.archiveError!.trim()
        : firstEntry?.reason?.trim().isNotEmpty == true
        ? firstEntry!.reason!.trim()
        : null;
    final message = imported == 0
        ? reason == null
              ? 'No CaptureClipper books were imported.'
              : 'No CaptureClipper books were imported. $entryLabel: $reason'
        : 'Imported $imported CaptureClipper book${imported == 1 ? '' : 's'}'
              '${archived > 0 ? ' and archived $archived source folder${archived == 1 ? '' : 's'}' : ''}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _captureImportButtonLabel() {
    final report = _captureImportReport;
    if (_loadingCaptureImportAvailability ||
        report == null ||
        !report.hasAvailableImports) {
      return null;
    }
    if (report.availableCount == 1) {
      return 'Import 1 Book';
    }
    return 'Import Ready';
  }

  Future<void> _refreshEstimateCache() async {
    if (_refreshingEstimateCache) return;
    setState(() => _refreshingEstimateCache = true);
    try {
      await ELibraryDownloadService.instance
          .refreshProductionCollectionEstimates();
      await _loadEstimateCache();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estimate cache refreshed.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estimate refresh failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _refreshingEstimateCache = false);
      }
    }
  }

  Future<({int indexed, int skipped, int failed})> _runManualIndex() async {
    if (_manualIndexing) {
      return (indexed: 0, skipped: 0, failed: 0);
    }
    setState(() {
      _manualIndexing = true;
      _manualIndexStatus = 'Indexing new/changed books...';
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
      if (!mounted) {
        return (indexed: 0, skipped: 0, failed: 0);
      }
      final String status;
      if (result.indexed == 0 && result.skipped == 0 && result.failed == 0) {
        status = 'Library is already indexed';
      } else {
        status =
            'Indexing complete — ${result.indexed} indexed, ${result.skipped} skipped, ${result.failed} failed';
      }
      setState(() => _manualIndexStatus = status);
      return result;
    } catch (error) {
      if (!mounted) {
        return (indexed: 0, skipped: 0, failed: 0);
      }
      setState(() => _manualIndexStatus = 'Indexing failed: $error');
      return (indexed: 0, skipped: 0, failed: 1);
    } finally {
      if (mounted) setState(() => _manualIndexing = false);
    }
  }

  Future<void> _chooseRoot() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryRootSetupScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  void _clearSelectionWarning() {
    _selectionWarning = null;
  }

  void _selectAllCollectionsAndFormats() {
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
      _clearSelectionWarning();
    });
  }

  void _setPresetEpubOnly() {
    setState(() {
      _installEpub = true;
      _installPdf = false;
      _clearSelectionWarning();
    });
  }

  void _setPresetPdfOnly() {
    setState(() {
      _installEpub = false;
      _installPdf = true;
      _clearSelectionWarning();
    });
  }

  void _setPresetBoth() {
    setState(() {
      _installEpub = true;
      _installPdf = true;
      _clearSelectionWarning();
    });
  }

  void _clearAllSelections() {
    setState(() {
      _installBooks = false;
      _installDevotionals = false;
      _installCommentaries = false;
      _installMiscCollections = false;
      _installPamphlets = false;
      _installPeriodicals = false;
      _installManuscriptReleases = false;
      _installEpub = false;
      _installPdf = false;
      _clearSelectionWarning();
    });
  }

  Set<String> _selectedCollectionNames() {
    final selections = <String>{};
    if (_installBooks) selections.add('EGW Books');
    if (_installDevotionals) selections.add('EGW Devotionals');
    if (_installCommentaries) selections.add('EGW Commentaries');
    if (_installMiscCollections) selections.add('EGW Misc Collections');
    if (_installPamphlets) selections.add('EGW Pamphlets');
    if (_installPeriodicals) selections.add('EGW Periodicals');
    if (_installManuscriptReleases) {
      selections.add('EGW Manuscript Releases');
    }
    return selections;
  }

  Set<ELibraryManagedDownloadFormat> _selectedFormats() {
    final formats = <ELibraryManagedDownloadFormat>{};
    if (_installEpub) {
      formats.add(ELibraryManagedDownloadFormat.epub);
    }
    if (_installPdf) {
      formats.add(ELibraryManagedDownloadFormat.pdf);
    }
    return formats;
  }

  int _selectedFormatCount() {
    return _selectedFormats().length;
  }

  bool _isCollectionSelected(int index) {
    switch (index) {
      case 0:
        return _installBooks;
      case 1:
        return _installDevotionals;
      case 2:
        return _installCommentaries;
      case 3:
        return _installMiscCollections;
      case 4:
        return _installPamphlets;
      case 5:
        return _installPeriodicals;
      case 6:
        return _installManuscriptReleases;
      default:
        return false;
    }
  }

  String _fileCountLabel(int count) {
    return count == 1 ? '1 file' : '$count files';
  }

  static const List<String> _collectionKeys = <String>[
    'EGW Books',
    'EGW Devotionals',
    'EGW Commentaries',
    'EGW Misc Collections',
    'EGW Pamphlets',
    'EGW Periodicals',
    'EGW Manuscript Releases',
  ];

  Map<String, ELibraryInstallEstimateRecord>? _collectionCache(int index) {
    if (index < 0 || index >= _collectionKeys.length) return null;
    return _estimateCacheByCollection[_collectionKeys[index]];
  }

  ELibraryInstallEstimateRecord? _bestCachedRecord(int index) {
    final cache = _collectionCache(index);
    if (cache == null || cache.isEmpty) return null;
    return cache['epub'] ?? cache['pdf'] ?? cache.values.first;
  }

  String _estimateLineForCollection(int index) {
    final record = _bestCachedRecord(index);
    if (record == null) {
      return 'file count not cached yet • size unknown';
    }
    final count = record.fileCount * _selectedFormatCount();
    if (count == 0) {
      return '0 files found • size unknown';
    }
    return '${_fileCountLabel(count)} • size unknown';
  }

  String _selectedDownloadSummary() {
    final formatCount = _selectedFormatCount();
    if (formatCount == 0) {
      return 'Selected download: 0 files found • size unknown';
    }
    var totalCount = 0;
    var knownCount = 0;
    var selectedCount = 0;
    for (var index = 0; index < _collectionKeys.length; index++) {
      if (!_isCollectionSelected(index)) continue;
      selectedCount += 1;
      final record = _bestCachedRecord(index);
      if (record == null) continue;
      knownCount += 1;
      totalCount += record.fileCount * formatCount;
    }
    if (selectedCount == 0) {
      return 'Selected download: 0 files found • size unknown';
    }
    if (knownCount == 0) {
      return 'Selected download: file count not cached yet • size unknown';
    }
    if (knownCount < selectedCount) {
      return 'Selected download: partial count available • size unknown';
    }
    return 'Selected download: ${_fileCountLabel(totalCount)} • size unknown';
  }

  String? _installSelectionWarning() {
    if (_selectedCollectionNames().isEmpty) {
      return 'Select at least one collection to install.';
    }
    if (_selectedFormats().isEmpty) {
      return 'Select EPUB, PDF, or both before installing.';
    }
    return null;
  }

  String _friendlyErrorMessage(Object error) {
    if (error is EgwCollectionFetchException) {
      return error.userFacingMessage;
    }
    final message = error.toString();
    if (message.contains('EGW site refused this request')) {
      return 'EGW site refused this request. Open the collection in a browser or try again later.';
    }
    return message;
  }

  String? _errorDiagnostics(Object error) {
    if (error is EgwCollectionFetchException) {
      return error.diagnosticDetails;
    }
    final message = error.toString();
    final match = RegExp(
      r'Failed URL: .+\nStatus code: \d+',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(message);
    return match?.group(0);
  }

  String? _downloadFailureSummary(ELibraryDownloadReport? report) {
    if (report == null || report.failures.isEmpty) {
      return null;
    }
    for (final failure in report.failures) {
      final error = failure.error ?? '';
      if (error.contains('EGW site refused this request')) {
        return 'EGW site refused this request. Open the collection in a browser or try again later.';
      }
    }
    return 'Some eLibrary files could not be downloaded.';
  }

  String? _downloadUnavailableSummary(ELibraryDownloadReport? report) {
    if (report == null || report.filesUnavailable.isEmpty) {
      return null;
    }
    return 'Some books did not have a verified EPUB/PDF file in the selected format.';
  }

  _ELibraryRunCompletionStatus _completionStatus({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
    required bool isRunning,
  }) {
    if (isRunning) {
      return _ELibraryRunCompletionStatus.failedOrIncomplete;
    }
    final failed = downloadReport?.failures.length ?? 0;
    final unavailable = downloadReport?.filesUnavailable.length ?? 0;
    if (failed > 0 || indexingErrors > 0 || indexedCount == 0) {
      return _ELibraryRunCompletionStatus.failedOrIncomplete;
    }
    if (unavailable > 0) {
      return _ELibraryRunCompletionStatus.completedWithWarnings;
    }
    return _ELibraryRunCompletionStatus.cleanSuccess;
  }

  String _completionHeading({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
  }) {
    final status = _completionStatus(
      downloadReport: downloadReport,
      indexingErrors: indexingErrors,
      indexedCount: indexedCount,
      isRunning: false,
    );
    return switch (status) {
      _ELibraryRunCompletionStatus.cleanSuccess => 'eLibrary setup complete',
      _ELibraryRunCompletionStatus.completedWithWarnings =>
        'eLibrary setup completed with warnings',
      _ELibraryRunCompletionStatus.failedOrIncomplete =>
        'eLibrary setup incomplete',
    };
  }

  String _completionSummary({
    required ELibraryDownloadReport? downloadReport,
    required int indexingErrors,
    required int indexedCount,
  }) {
    final unavailable = downloadReport?.filesUnavailable.length ?? 0;
    final failed = downloadReport?.failures.length ?? 0;
    return 'Indexed: $indexedCount\n'
        'Unavailable in selected format: $unavailable\n'
        'Failed: $failed\n'
        'Indexing errors: $indexingErrors';
  }

  Future<void> _showUnavailableItemsDialog() async {
    final report = _downloadReport;
    if (report == null || report.filesUnavailable.isEmpty) return;
    final items = report.filesUnavailable;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Unavailable in selected format'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final item = items[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    if (item.collection.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Collection: ${item.collection}'),
                    ],
                    const SizedBox(height: 4),
                    Text('Format: ${item.format.toUpperCase()}'),
                    const SizedBox(height: 4),
                    SelectableText(item.sourceUrl),
                    if ((item.error ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SelectableText(item.error!),
                    ],
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<bool?> _confirmLegacyMigration() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Move legacy eLibrary files?'),
          content: const SingleChildScrollView(
            child: Text(
              'Legacy eLibrary files can be copied into the new EGW folder layout before the download starts.\n\n'
              'Some duplicate or conflicting legacy files may be moved to a quarantine folder after a verified copy so the original can be reviewed later.\n\n'
              'This is not a delete or reset operation. Your downloaded books are preserved.\n\n'
              'You can cancel now and come back later.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Move Files'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startSetup() async {
    if (_running) return;
    final selection = _selection;
    if (selection?.path == null ||
        selection?.exists != true ||
        selection?.isExplicitlySelected != true) {
      final warning = selection?.path == null
          ? 'Choose a Library Root before installing eLibrary files.'
          : 'Legacy Library Root detected. Open Library Root Setup to confirm or migrate before installing.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    final validationWarning = _installSelectionWarning();
    if (validationWarning != null) {
      if (!mounted) return;
      setState(() {
        _selectionWarning = validationWarning;
        _setupStatusMessage = validationWarning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationWarning)));
      return;
    }

    final needsLegacyMigration = await LegacyELibraryMigrationService.instance
        .hasMigrationCandidates();
    if (!mounted) return;
    if (needsLegacyMigration) {
      final confirmed = await _confirmLegacyMigration();
      if (!mounted) return;
      if (confirmed != true) {
        setState(() {
          _setupStatusMessage =
              'Legacy migration cancelled. No files were changed.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Legacy migration cancelled. No files were changed.'),
          ),
        );
        return;
      }
    }

    final rootPath = selection!.path!;

    setState(() {
      _running = true;
      _indexing = false;
      _cancelRequested = false;
      _error = null;
      _errorDetails = null;
      _downloadReport = null;
      _migrationReport = null;
      _cleanupReport = null;
      _setupReportPath = null;
      _indexReportPath = null;
      _setupStatusMessage = null;
      _progress = null;
      _indexedCount = 0;
      _indexingErrors = 0;
      _clearSelectionWarning();
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

      final downloadReport = await ELibraryDownloadService.instance
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
        _setupStatusMessage = 'Updating estimates...';
      });
      await _loadEstimateCache();
      if (!mounted) return;

      final cleanupReport = await ELibraryDuplicateCleanupService.instance
          .quarantineDuplicates(isCancelled: () => _cancelRequested);

      if (!mounted) return;
      setState(() {
        _cleanupReport = cleanupReport;
        _setupStatusMessage = 'Refreshing catalog...';
      });

      final catalogTouched = await LibraryCatalogService.instance
          .refreshManagedItemsFromDisk();
      if (!mounted) return;
      setState(() {
        _setupStatusMessage = catalogTouched == 0
            ? 'Catalog already up to date.'
            : 'Catalog refreshed ($catalogTouched items).';
      });

      if (!mounted) return;
      setState(() {
        _setupStatusMessage = 'Indexing new/changed books...';
        _indexing = true;
      });

      final indexResult = await _runManualIndex();
      if (!mounted) return;
      setState(() {
        _setupStatusMessage = 'Finalizing setup...';
      });

      final passageData = await CommentaryResearchLibraryService.instance
          .loadPassage(
            bookId: 1,
            chapter: 1,
            verse: 1,
            bookName: 'Genesis',
            refresh: false,
          );
      if (!mounted) return;
      final db = await UserDatabase.instance.database;
      final unindexedItems = await LibraryCatalogService.instance
          .listUnindexedManagedItems();
      final failedRows = await db.rawQuery('''
        SELECT COUNT(*) AS count
        FROM library_items
        WHERE folder_type IN ('commentary', 'research')
          AND index_status = 'failed'
          AND deleted_at IS NULL
      ''');
      final indexingErrors = (failedRows.first['count'] as num?)?.toInt() ?? 0;
      final indexedCount = indexResult.indexed;

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
        'unavailable_count': downloadReport.unavailableCount,
        'failed_count': downloadReport.failedCount,
        'indexed_count': indexedCount,
        'indexing_errors': indexingErrors,
        'unindexed_item_count': unindexedItems.length,
        'unindexed_items': unindexedItems
            .map(
              (item) => {
                'id': item.id,
                'title': item.displayTitle,
                'collection_name': item.collectionName,
                'relative_path': item.relativePath,
                'index_status': item.indexStatus,
              },
            )
            .toList(growable: false),
        'auto_index_result': {
          'indexed': indexResult.indexed,
          'skipped': indexResult.skipped,
          'failed': indexResult.failed,
        },
        'migration_report_path': _migrationReport?.reportFilePath,
        'source_cleanup_policy': _storagePolicy.name,
        'source_cleanup_policy_label': _storagePolicy.label,
        'source_cleanup_status': _sourceCleanupDeferredMessage,
        'source_files_downloaded': downloadReport.filesDownloaded.length,
        'source_files_retained':
            downloadReport.filesDownloaded.length +
            downloadReport.filesSkipped.length,
        'source_files_removed_after_import': 0,
        'source_files_not_removed_because_import_not_verified':
            downloadReport.filesDownloaded.length +
            downloadReport.filesSkipped.length,
        // Source cleanup is future-facing here; imported works already live in
        // eLibrary.db and only downloaded source files can be removed.
        'files_downloaded': downloadReport.filesDownloaded
            .map((item) => item.toJson())
            .toList(growable: false),
        'files_skipped': downloadReport.filesSkipped
            .map((item) => item.toJson())
            .toList(growable: false),
        'files_unavailable': downloadReport.filesUnavailable
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
        _setupStatusMessage = switch (_completionStatus(
          downloadReport: downloadReport,
          indexingErrors: indexingErrors,
          indexedCount: indexedCount,
          isRunning: false,
        )) {
          _ELibraryRunCompletionStatus.cleanSuccess =>
            'eLibrary setup complete',
          _ELibraryRunCompletionStatus.completedWithWarnings =>
            'eLibrary setup completed with warnings',
          _ELibraryRunCompletionStatus.failedOrIncomplete =>
            'eLibrary setup incomplete',
        };
        _indexing = false;
      });
      await _loadStorageSummary();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_setupStatusMessage ?? 'eLibrary setup complete'} in '
            '${downloadReport.elapsedSeconds.toStringAsFixed(1)}s',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyErrorMessage(error);
        _errorDetails = _errorDiagnostics(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('eLibrary setup failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _indexing = false;
          _setupStatusMessage ??= 'Done';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = -1;
    do {
      value /= 1024;
      unitIndex += 1;
    } while (value >= 1024 && unitIndex < units.length - 1);
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unitIndex]}';
  }

  Future<void> _removeDownloadedFiles({
    required Set<String> collectionNames,
    required Set<ELibraryManagedDownloadFormat> formats,
    required String actionLabel,
  }) async {
    if (_running || _removingFiles) return;
    final selection = _selection;
    if (selection?.path == null ||
        selection?.exists != true ||
        selection?.isExplicitlySelected != true) {
      final warning = selection?.path == null
          ? 'Choose a Library Root before removing downloaded eLibrary files.'
          : 'Legacy Library Root detected. Open Library Root Setup to confirm or migrate before removing files.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    if (collectionNames.isEmpty) {
      final warning = 'Select at least one collection to remove.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }
    if (formats.isEmpty) {
      final warning = 'Select EPUB, PDF, or both before removing.';
      if (!mounted) return;
      setState(() {
        _selectionWarning = warning;
        _setupStatusMessage = warning;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(warning)));
      return;
    }

    final rootPath = selection!.path!;
    setState(() {
      _removingFiles = true;
      _selectionWarning = null;
      _setupStatusMessage = 'Scanning downloaded files...';
      _error = null;
      _errorDetails = null;
    });

    try {
      final queue = await ELibraryFileManagementService.instance
          .buildFilteredRemovalQueue(
            collectionNames: collectionNames,
            formats: formats,
            rootPath: rootPath,
          );
      if (!mounted) return;
      if (queue.isEmpty) {
        setState(
          () =>
              _setupStatusMessage = 'No matching downloaded files were found.',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No matching downloaded files were found.'),
          ),
        );
        return;
      }

      final totalBytes = queue.fold<int>(
        0,
        (sum, record) => sum + record.fileSize,
      );
      final managedFolders =
          queue
              .map((record) => p.dirname(record.relativePath))
              .toSet()
              .toList(growable: false)
            ..sort();
      final epubCount = queue
          .where(
            (record) => record.format == ELibraryManagedDownloadFormat.epub,
          )
          .length;
      final pdfCount = queue
          .where((record) => record.format == ELibraryManagedDownloadFormat.pdf)
          .length;
      final breakdown = epubCount > 0 && pdfCount > 0
          ? '$epubCount EPUB and $pdfCount PDF'
          : epubCount > 0
          ? '$epubCount EPUB'
          : '$pdfCount PDF';
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(actionLabel),
            content: Text(
              'Library Root:\n${selection.path}\n\n'
              'Managed folders:\n${managedFolders.join('\n')}\n\n'
              'Remove ${queue.length} $breakdown files '
              '(${_formatBytes(totalBytes)}) from the eLibrary?\n\n'
              'If this Library Root is shared with another Biblical Heritage or standalone eLibrary app, removing files here may remove files used by that app too. This will not delete tags, notes, highlights, bookmarks, saved presentations, or user.db.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Remove'),
              ),
            ],
          );
        },
      );
      if (confirm != true) {
        if (!mounted) return;
        setState(() => _setupStatusMessage = 'Removal cancelled.');
        return;
      }

      setState(() => _setupStatusMessage = 'Removing downloaded files...');
      final report = await ELibraryFileManagementService.instance
          .removeDownloadedFiles(
            collectionNames: collectionNames,
            formats: formats,
            rootPath: rootPath,
          );
      if (!mounted) return;
      setState(() {
        _setupStatusMessage =
            'Removed ${report.removedCount} files '
            '(${_formatBytes(report.removedBytes)}). '
            'User tags, notes, highlights, and saved presentations were not changed.';
      });
      await _loadStorageSummary();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Removed ${report.removedCount} files '
            '(${report.epubRemovedCount} EPUB, ${report.pdfRemovedCount} PDF).',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyErrorMessage(error);
        _errorDetails = _errorDiagnostics(error);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removal failed: $error')));
    } finally {
      if (mounted) {
        setState(() => _removingFiles = false);
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
      appBar: AppBar(
        title: const Text('eLibrary Setup'),
        centerTitle: true,
        leading: _setupLeading(context),
        leadingWidth: _setupLeadingWidth(),
      ),
      body: SafeArea(
        top: false,
        child: _loading
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
                            selection?.statusLabel ??
                                'No Library Root selected.',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _pathLine('Root path', selection?.path),
                          _pathLine('Root source', selection?.sourceLabel),
                          const SizedBox(height: 8),
                          Text(
                            'Source-file cleanup policy (future behavior): ${_storagePolicy.label}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            'Imported works stay in eLibrary.db for reading, search, tagging, and navigation. Source-file cleanup only affects downloaded EPUB/PDF files.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton(
                                onPressed: _chooseRoot,
                                child: const Text('Manage Library Root'),
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
                                      ? 'Indexing new/changed books...'
                                      : 'Index New/Changed Books',
                                ),
                              ),
                              OutlinedButton(
                                onPressed:
                                    (_running || _refreshingEstimateCache)
                                    ? null
                                    : _refreshEstimateCache,
                                child: Text(
                                  _refreshingEstimateCache
                                      ? 'Refreshing estimates...'
                                      : 'Refresh estimates',
                                ),
                              ),
                            ],
                          ),
                          if (_setupStatusMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _setupStatusMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
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
                                  : 'Indexing new/changed books...',
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
                            'CaptureClipper Imports',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose the folder where CaptureClipper saves captured HTML files, then import anything new into the Pioneer authors library. This is a local HTML import path, not EGW online downloads.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          CaptureClipperFolderDetails(
                            loading: _loadingCaptureFolder,
                            path: _captureFolderPath,
                            access: _captureFolderAccess,
                            status: _captureFolderStatus,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton(
                                onPressed: _captureFolderBusy
                                    ? null
                                    : _chooseCaptureFolder,
                                child: const Text('Choose Folder'),
                              ),
                              CaptureClipperImportButton(
                                label: _captureImportButtonLabel(),
                                busy: _captureFolderBusy,
                                onPressed: _promptCaptureImports,
                              ),
                              OutlinedButton(
                                onPressed: _captureFolderBusy
                                    ? null
                                    : () => _importCaptureFolder(
                                        repairExistingItems: true,
                                      ),
                                child: const Text(
                                  'Repair Broken CaptureClipper Items',
                                ),
                              ),
                              OutlinedButton(
                                onPressed: _captureFolderBusy
                                    ? null
                                    : _clearCaptureFolder,
                                child: const Text('Clear Folder'),
                              ),
                              TextButton(
                                onPressed: _captureFolderBusy
                                    ? null
                                    : _reviewCaptureFolderImports,
                                child: const Text('Review Imports'),
                              ),
                            ],
                          ),
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
                            'Install eLibrary Collections',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose your eLibrary collections and formats, then use Install Selected to begin. The selection buttons only change checkmarks; they do not start a download.',
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
                                label: const Text(
                                  'Select All Collections + All File Types',
                                ),
                                onPressed: _running
                                    ? null
                                    : _selectAllCollectionsAndFormats,
                              ),
                              ActionChip(
                                label: const Text('Clear All'),
                                onPressed: _running
                                    ? null
                                    : _clearAllSelections,
                              ),
                              ActionChip(
                                label: const Text('EPUB Only'),
                                onPressed: _running ? null : _setPresetEpubOnly,
                              ),
                              ActionChip(
                                label: const Text('PDF Only'),
                                onPressed: _running ? null : _setPresetPdfOnly,
                              ),
                              ActionChip(
                                label: const Text('EPUB + PDF'),
                                onPressed: _running ? null : _setPresetBoth,
                              ),
                            ],
                          ),
                          if (_selectionWarning != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _selectionWarning!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            value: _installBooks,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installBooks = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Books'),
                            subtitle: Text(
                              _estimateLineForCollection(0),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installDevotionals,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installDevotionals = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Devotionals'),
                            subtitle: Text(
                              _estimateLineForCollection(1),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installCommentaries,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installCommentaries = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Commentaries'),
                            subtitle: Text(
                              _estimateLineForCollection(2),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installMiscCollections,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installMiscCollections = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Misc Collections'),
                            subtitle: Text(
                              _estimateLineForCollection(3),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installPamphlets,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installPamphlets = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Pamphlets'),
                            subtitle: Text(
                              _estimateLineForCollection(4),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installPeriodicals,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installPeriodicals = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('Install EGW Periodicals'),
                            subtitle: Text(
                              _estimateLineForCollection(5),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installManuscriptReleases,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installManuscriptReleases = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text(
                              'Install EGW Manuscript Releases',
                            ),
                            subtitle: Text(
                              _estimateLineForCollection(6),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selectedDownloadSummary(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Divider(height: 24),
                          CheckboxListTile(
                            value: _installEpub,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installEpub = value ?? false;
                                    _clearSelectionWarning();
                                  }),
                            title: const Text('EPUB'),
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            value: _installPdf,
                            onChanged: _running
                                ? null
                                : (value) => setState(() {
                                    _installPdf = value ?? false;
                                    _clearSelectionWarning();
                                  }),
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Manage Downloaded Files',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'These removal actions only touch the managed eLibrary EPUB/PDF folders under the current Library Root. User tags, notes, highlights, bookmarks, saved presentations, and user.db are not deleted.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingStorageSummary)
                            const LinearProgressIndicator()
                          else if (_storageSummary != null) ...[
                            Text(
                              'Downloaded library files: '
                              '${_storageSummary!.epubCount} EPUB '
                              '(${_formatBytes(_storageSummary!.epubSizeBytes)}), '
                              '${_storageSummary!.pdfCount} PDF '
                              '(${_formatBytes(_storageSummary!.pdfSizeBytes)}), '
                              'total ${_storageSummary!.totalCount} files '
                              '(${_formatBytes(_storageSummary!.totalSizeBytes)}).',
                            ),
                          ],
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              OutlinedButton(
                                onPressed:
                                    (_running ||
                                        _removingFiles ||
                                        selection?.isExplicitlySelected != true)
                                    ? null
                                    : () => _removeDownloadedFiles(
                                        collectionNames:
                                            _selectedCollectionNames(),
                                        formats: _selectedFormats(),
                                        actionLabel: 'Remove Selected',
                                      ),
                                child: const Text('Remove Selected'),
                              ),
                              OutlinedButton(
                                onPressed:
                                    (_running ||
                                        _removingFiles ||
                                        selection?.isExplicitlySelected != true)
                                    ? null
                                    : () => _removeDownloadedFiles(
                                        collectionNames: _collectionKeys
                                            .toSet(),
                                        formats: const {
                                          ELibraryManagedDownloadFormat.epub,
                                        },
                                        actionLabel: 'Remove EPUBs',
                                      ),
                                child: const Text('Remove EPUBs'),
                              ),
                              OutlinedButton(
                                onPressed:
                                    (_running ||
                                        _removingFiles ||
                                        selection?.isExplicitlySelected != true)
                                    ? null
                                    : () => _removeDownloadedFiles(
                                        collectionNames: _collectionKeys
                                            .toSet(),
                                        formats: const {
                                          ELibraryManagedDownloadFormat.pdf,
                                        },
                                        actionLabel: 'Remove PDFs',
                                      ),
                                child: const Text('Remove PDFs'),
                              ),
                              FilledButton.tonal(
                                onPressed:
                                    (_running ||
                                        _removingFiles ||
                                        selection?.isExplicitlySelected != true)
                                    ? null
                                    : () => _removeDownloadedFiles(
                                        collectionNames: _collectionKeys
                                            .toSet(),
                                        formats: const {
                                          ELibraryManagedDownloadFormat.epub,
                                          ELibraryManagedDownloadFormat.pdf,
                                        },
                                        actionLabel:
                                            'Remove All Downloaded Library Files',
                                      ),
                                child: const Text(
                                  'Remove All Downloaded Library Files',
                                ),
                              ),
                            ],
                          ),
                          if (_removingFiles) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                          ],
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
                              Text(
                                _setupStatusMessage ??
                                    'Indexing new/changed books...',
                              ),
                            ] else ...[
                              const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              Text(
                                _setupStatusMessage ??
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
                              'Unavailable in selected format: ${_progress?.unavailableCount ?? 0}  '
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
                              _completionHeading(
                                downloadReport: _downloadReport,
                                indexingErrors: _indexingErrors,
                                indexedCount: _indexedCount,
                              ),
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _completionSummary(
                                downloadReport: _downloadReport,
                                indexingErrors: _indexingErrors,
                                indexedCount: _indexedCount,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Downloaded: ${_downloadReport!.filesDownloaded.length}',
                            ),
                            Text(
                              'Skipped existing: ${_downloadReport!.filesSkipped.length}',
                            ),
                            Text(
                              'Unavailable in selected format: ${_downloadReport!.filesUnavailable.length}',
                            ),
                            Text('Failed: ${_downloadReport!.failures.length}'),
                            Text('Indexed: $_indexedCount'),
                            Text('Indexing errors: $_indexingErrors'),
                            Text(
                              'Elapsed: ${_downloadReport!.elapsedSeconds.toStringAsFixed(1)}s',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Source cleanup policy: ${_storagePolicy.label} (future behavior)',
                            ),
                            Text(
                              'Source files downloaded: ${_downloadReport!.filesDownloaded.length}',
                            ),
                            Text(
                              'Source files retained for backup/re-import: ${_downloadReport!.filesDownloaded.length + _downloadReport!.filesSkipped.length}',
                            ),
                            Text('Source files removed after import: 0'),
                            Text(
                              'Source files not removed yet: ${_downloadReport!.filesDownloaded.length + _downloadReport!.filesSkipped.length}',
                            ),
                            Text(
                              'Cleanup status: $_sourceCleanupDeferredMessage',
                            ),
                            if (_downloadReport!
                                .filesUnavailable
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _downloadUnavailableSummary(_downloadReport) ??
                                    'Some books did not have a verified EPUB/PDF file in the selected format.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.tertiary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton(
                                  onPressed: _showUnavailableItemsDialog,
                                  child: const Text('View unavailable items'),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _downloadReport!.filesUnavailable
                                    .take(3)
                                    .map(
                                      (item) =>
                                          '${item.title} (${item.format.toUpperCase()}): ${item.sourceUrl}\n${item.error ?? "No diagnostic details available."}',
                                    )
                                    .join('\n\n'),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'These are candidates for a later fallback import path. Some may be available as PDF or online text/HTML, but fallback import is not implemented in this screen yet.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (_downloadReport!.failures.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                _downloadFailureSummary(_downloadReport) ??
                                    'Some eLibrary files could not be downloaded.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                _downloadReport!.failures.first.error ??
                                    'No diagnostic details available.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            SelectableText(
                              _setupReportPath ??
                                  _downloadReport!.reportFilePath,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                            if (_errorDetails != null &&
                                _errorDetails!.trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SelectableText(
                                _errorDetails!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
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
                            'EGW EPUBs:\nLibraryRoot/ePubs/EGW/\n\nEGW PDFs:\nLibraryRoot/PDFs/EGW/\n\nThe setup screen uses the simplified EGW folder layout.',
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
