import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/pioneer_install_status_service.dart';
import '../data/pioneer_html_capture_folder_scanner.dart';
import '../data/pioneer_text_import_service.dart';
import '../data/pioneer_source_catalog.dart';
import 'egw_copied_range_import_dialog.dart';

typedef PioneerExistingCapturedImportInspector =
    Future<PioneerExistingCapturedImportSummary> Function(
      PioneerSourceWork work,
    );

class PioneerTextImportScreen extends StatefulWidget {
  const PioneerTextImportScreen({
    super.key,
    this.catalogFuture,
    this.importService,
    this.installStatusFuture,
    this.htmlCaptureFolderScanner,
    this.existingCapturedImportInspector,
  });

  final Future<PioneerSourceCatalog>? catalogFuture;
  final PioneerTextImportService? importService;
  final Future<Map<String, PioneerWorkInstallStatus>>? installStatusFuture;
  final PioneerHtmlCaptureFolderScanner? htmlCaptureFolderScanner;
  final PioneerExistingCapturedImportInspector? existingCapturedImportInspector;

  @override
  State<PioneerTextImportScreen> createState() =>
      _PioneerTextImportScreenState();
}

class _PioneerTextImportScreenState extends State<PioneerTextImportScreen> {
  late Future<PioneerSourceCatalog> _catalogFuture;
  late Future<Map<String, PioneerWorkInstallStatus>> _installStatusFuture;
  late final PioneerTextImportService _importService;
  PioneerSourceSelection _selection = PioneerSourceSelection.empty();
  String? _selectedAuthorId;
  bool _showMoreActions = false;
  bool _showInstalled = true;
  bool _importing = false;
  bool _cancelImportRequested = false;
  double _importProgress = 0;
  String? _importStatusText;
  PioneerImportBatchResult? _importResult;

  @override
  void initState() {
    super.initState();
    _importService = widget.importService ?? PioneerTextImportService.instance;
    _catalogFuture = widget.catalogFuture ?? PioneerSourceCatalog.load();
    _installStatusFuture =
        widget.installStatusFuture ??
        _catalogFuture.then(
          PioneerInstallStatusService.instance.inspectCatalog,
        );
  }

  void _refreshCatalog() {
    if (_importing) return;
    setState(() {
      _catalogFuture = widget.catalogFuture ?? PioneerSourceCatalog.load();
      _installStatusFuture =
          widget.installStatusFuture ??
          _catalogFuture.then(
            PioneerInstallStatusService.instance.inspectCatalog,
          );
      _selection = PioneerSourceSelection.empty();
      _selectedAuthorId = null;
      _importResult = null;
      _importStatusText = 'Refreshing Pioneer source catalog...';
    });
  }

  void _refreshInstallStatuses() {
    if (_importing) return;
    setState(() {
      _installStatusFuture = _catalogFuture.then(
        PioneerInstallStatusService.instance.inspectCatalog,
      );
    });
  }

  bool _canUseCopiedRangePath(PioneerSourceWork work) {
    return work.abbreviation.trim().toUpperCase() == 'DAR';
  }

  bool _canSelectForImport(
    PioneerSourceWork work,
    PioneerWorkInstallStatus? installStatus,
  ) {
    if (installStatus?.isVerifiedInstalled == true) {
      return false;
    }
    return work.hasUsableSourcePath ||
        work.textCaptureAvailable ||
        _canUseCopiedRangePath(work);
  }

  void _toggleWork(PioneerSourceWork work) {
    if (_importing) {
      return;
    }
    setState(() {
      _selection = _selection.toggle(work.id);
    });
  }

  void _openAuthor(String authorId) {
    if (_importing) {
      return;
    }
    setState(() {
      _selectedAuthorId = authorId;
      _selection = PioneerSourceSelection.empty();
    });
  }

  void _closeAuthor() {
    if (_importing) return;
    setState(() {
      _selectedAuthorId = null;
      _selection = PioneerSourceSelection.empty();
    });
  }

  void _toggleMoreActions() {
    if (_importing) return;
    setState(() {
      _showMoreActions = !_showMoreActions;
    });
  }

  void _clearResults() {
    if (_importing) return;
    setState(() {
      _importStatusText = null;
      _importResult = null;
      _importProgress = 0;
    });
  }

  void _clearSelection() {
    if (_importing) return;
    setState(() {
      _selection = PioneerSourceSelection.empty();
    });
  }

  // TEMP DEV: hard-reset a work's import so the catalog treats it as uninstalled.
  Future<void> _resetWork(PioneerSourceCatalog catalog, String workId) async {
    if (_importing) return;
    final work = catalog.workById(workId);
    if (work == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Work not found: $workId')));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset ${work.abbreviation}?'),
        content: Text(
          'This will delete all imported text blocks for "${work.title}" '
          'and remove it from library_items so it shows as uninstalled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _importService.hardResetWork(work);
    _refreshCatalog();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${work.abbreviation} reset — ready for Capture.'),
        ),
      );
    }
  }

  void _selectVisibleWorks(
    Iterable<PioneerSourceWork> works,
    Map<String, PioneerWorkInstallStatus> installStatuses,
  ) {
    if (_importing) return;
    final selectableWorkIds = works
        .where((work) => _canSelectForImport(work, installStatuses[work.id]))
        .map((work) => work.id)
        .toList(growable: false);
    if (selectableWorkIds.isEmpty) return;
    setState(() {
      _selection = PioneerSourceSelection.fromWorkIds(selectableWorkIds);
      _importStatusText =
          'Selected works with importable or text-capture sources.';
    });
  }

  Future<void> _importSelected(
    PioneerSourceCatalog catalog, {
    bool allowRepair = false,
  }) async {
    if (_importing) return;
    final importableWorks = _selection.importableSelectedWorks(catalog);
    if (importableWorks.isEmpty) {
      setState(() {
        _importStatusText =
            'No importable works are selected. Use Import Clipboard, Import Saved Export, or Import EGW Copied Range from More Actions.';
      });
      return;
    }

    setState(() {
      _importing = true;
      _cancelImportRequested = false;
      _importProgress = 0;
      _importStatusText = 'Starting import...';
      _importResult = null;
    });

    try {
      final result = await _importService.importSelectedWorks(
        importableWorks,
        allowRepair: allowRepair,
        shouldContinue: () => !_cancelImportRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _importProgress = progress.fraction;
            _importStatusText = progress.message;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importProgress = result.wasCancelled ? _importProgress : 1;
        _importStatusText = result.wasCancelled
            ? 'Verified-source import cancelled.'
            : _buildImportSummaryText(result);
        _importResult = result;
        if (result.failedCount == 0 && !result.wasCancelled) {
          _selection = PioneerSourceSelection.empty();
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importStatusText = 'Import failed: $error';
      });
    }
  }

  Future<void> _repairSelected(
    PioneerSourceCatalog catalog,
    PioneerWorkInstallStatus installStatus,
  ) async {
    if (_importing) return;
    final selectedWorks = _selection.selectedWorks(catalog);
    if (selectedWorks.length != 1) {
      return;
    }
    final work = selectedWorks.single;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair selected work?'),
        content: Text(
          'This will replace the installed copy of ${work.title} in eLibrary.db.\n\n'
          '${installStatus.replacementWarningFor(work) ?? 'The existing copy will only be replaced because you explicitly chose Repair/Reimport.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await _importSelected(catalog, allowRepair: true);
  }

  Future<void> _cancelImport() async {
    if (!_importing) return;
    setState(() {
      _cancelImportRequested = true;
      _importStatusText = 'Stopping after the current work...';
    });
  }

  Future<void> _importClipboard(PioneerSourceCatalog catalog) async {
    if (_importing) return;
    final selectedWorks = _selection.selectedWorks(catalog);
    if (selectedWorks.length != 1) {
      setState(() {
        _importStatusText = 'Select exactly one work for clipboard import.';
      });
      return;
    }
    final work = selectedWorks.single;
    await _runCapturedTextImport(
      work: work,
      actionLabel: 'clipboard',
      run: () => _importService.importFromClipboard(
        work: work,
        sourceUrl: work.sourceUrl,
        sourceLabel: work.sourceSiteLabel,
        shouldContinue: () => !_cancelImportRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _importProgress = progress.fraction;
            _importStatusText = progress.message;
          });
        },
      ),
    );
  }

  Future<void> _importSavedExport(PioneerSourceCatalog catalog) async {
    if (_importing) return;
    final selectedWorks = _selection.selectedWorks(catalog);
    if (selectedWorks.length != 1) {
      setState(() {
        _importStatusText = 'Select exactly one work for saved export import.';
      });
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
      withData: false,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    final filePath = result.files.single.path;
    if (filePath == null || filePath.trim().isEmpty) {
      setState(() {
        _importStatusText = 'No file path was returned for the saved export.';
      });
      return;
    }
    final work = selectedWorks.single;
    await _runCapturedTextImport(
      work: work,
      actionLabel: 'saved export',
      run: () => _importService.importFromSavedExport(
        work: work,
        filePath: filePath,
        sourceUrl: work.sourceUrl,
        sourceLabel: work.sourceSiteLabel,
        shouldContinue: () => !_cancelImportRequested,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _importProgress = progress.fraction;
            _importStatusText = progress.message;
          });
        },
      ),
    );
  }

  Future<void> _importCopiedRange(PioneerSourceCatalog catalog) async {
    if (_importing) return;
    final selectedWorks = _selection.selectedWorks(catalog);
    if (selectedWorks.length != 1) {
      setState(() {
        _importStatusText = 'Select exactly one work for copied range import.';
      });
      return;
    }
    final work = selectedWorks.single;
    if (work.abbreviation.trim().toUpperCase() != 'DAR') {
      setState(() {
        _importStatusText = 'Copied range import is available for DAR only.';
      });
      return;
    }
    final result = await showDialog<PioneerImportBatchResult?>(
      context: context,
      builder: (context) =>
          EgwCopiedRangeImportDialog(work: work, importService: _importService),
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _importResult = result;
      _importStatusText = _buildImportSummaryText(result);
    });
    _refreshInstallStatuses();
  }

  Future<void> _runCapturedTextImport({
    required PioneerSourceWork work,
    required String actionLabel,
    required Future<PioneerImportBatchResult> Function() run,
  }) async {
    setState(() {
      _importing = true;
      _cancelImportRequested = false;
      _importProgress = 0;
      _importStatusText = 'Starting $actionLabel import for ${work.title}...';
      _importResult = null;
    });

    try {
      final result = await run();
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importProgress = result.wasCancelled ? _importProgress : 1;
        _importStatusText = result.wasCancelled
            ? 'Captured text import cancelled.'
            : _buildImportSummaryText(result);
        _importResult = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _importStatusText = 'Import failed: $error';
      });
    }
  }

  String _buildImportSummaryText(PioneerImportBatchResult result) {
    final summary = [
      'Imported ${result.importedCount} work${result.importedCount == 1 ? '' : 's'}',
      'Skipped ${result.skippedCount}',
      'Failed ${result.failedCount}',
      if (result.workResults.any(
        (workResult) => workResult.requiresManualVerification,
      ))
        'Review needed',
    ].join(' • ');
    final base = result.wasCancelled ? '$summary • Cancelled' : summary;
    if (result.failedCount > 0) {
      final firstFailed = result.workResults
          .where((r) => r.status == PioneerImportWorkStatus.failed)
          .toList();
      if (firstFailed.isNotEmpty) {
        final r = firstFailed.first;
        final hint = r.reason.length > 120
            ? '${r.reason.substring(0, 120)}…'
            : r.reason;
        return '$base\nFirst failure [${r.stage}]: ${r.work.title} — $hint';
      }
    }
    return base;
  }

  Future<void> _showCatalogDetails(
    BuildContext context,
    PioneerSourceCatalog catalog,
  ) async {
    final diagnostics = catalog.diagnostics;
    if (diagnostics == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Catalog Details'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(diagnostics.summaryText),
                const SizedBox(height: 12),
                Text(
                  'Top authors',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final entry in diagnostics.topAuthorCounts())
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${entry.key}: ${entry.value}'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showWorkDetails(
    BuildContext context,
    PioneerSourceWork work,
    PioneerWorkInstallStatus? installStatus,
    PioneerSourceCatalog catalog,
  ) async {
    final candidates = work.effectiveSourceCandidates
        .where((candidate) => !candidate.isLegacyFileCandidate)
        .toList(growable: false);
    final preferredImportCandidate = work.preferredImportCandidate;
    final hasMissingPreferredSource =
        candidates.isNotEmpty && !candidates.first.hasUrl;
    Widget detailLine(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SelectableText(text),
    );

    final detailWidgets = <Widget>[
      detailLine('Author: ${work.authorName}'),
      detailLine('Title: ${work.title}'),
      if (work.editionDisplayLabel != null)
        detailLine('Edition: ${work.editionDisplayLabel}'),
      if (work.abbreviation.trim().isNotEmpty)
        detailLine('Abbreviation: ${work.abbreviation}'),
      detailLine('Import status: ${installStatus?.statusLabel ?? 'Unknown'}'),
      detailLine('Text capture status: ${work.textCaptureStatus.label}'),
      if (work.textReadUrl != null)
        detailLine('Text/read URL: ${work.textReadUrl}'),
      detailLine('Preferred import method: ${work.preferredImportMethodLabel}'),
      detailLine('Fallback import method: ${work.fallbackImportMethodLabel}'),
      if (work.sourceNeededReason != null)
        detailLine('Source needed: ${work.sourceNeededReason}'),
      if (work.notes != null && work.notes!.trim().isNotEmpty)
        detailLine('Notes: ${work.notes}'),
      if (catalog.diagnostics != null)
        detailLine(catalog.diagnostics!.summaryText),
    ];

    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      final header = _buildSourceCandidateHeader(
        candidate: candidate,
        isFirstCandidate: index == 0,
        preferredImportCandidate: preferredImportCandidate,
        hasMissingPreferredSource: hasMissingPreferredSource,
      );
      detailWidgets.add(const SizedBox(height: 4));
      detailWidgets.add(
        Text(header, style: Theme.of(context).textTheme.titleSmall),
      );
      detailWidgets.add(const SizedBox(height: 2));
      detailWidgets.addAll([
        detailLine('Provider: ${candidate.providerLabel}'),
        detailLine('Source type: ${candidate.sourceTypeLabel}'),
        detailLine('Quality tier: ${candidate.qualityTier}'),
        if (candidate.editionDisplayLabel != null)
          detailLine('Edition: ${candidate.editionDisplayLabel}'),
        if (candidate.url?.trim().isNotEmpty == true)
          detailLine('Source URL: ${candidate.url}'),
        detailLine(
          'Importable: ${candidate.supportsAutoImport ? 'Yes' : 'No'}',
        ),
        if (candidate.notes != null && candidate.notes!.trim().isNotEmpty)
          detailLine('Notes: ${candidate.notes}'),
      ]);
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(work.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: detailWidgets,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _buildSourceCandidateHeader({
    required PioneerSourceCandidate candidate,
    required bool isFirstCandidate,
    required PioneerSourceCandidate? preferredImportCandidate,
    required bool hasMissingPreferredSource,
  }) {
    if (isFirstCandidate && !candidate.hasUrl) {
      return 'Preferred source needed: ${candidate.displayLabel}';
    }
    if (candidate == preferredImportCandidate && !hasMissingPreferredSource) {
      return 'Preferred source: ${candidate.displayLabel}';
    }
    return 'Alternate source: ${candidate.displayLabel}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pioneer Library Import'),
        centerTitle: true,
      ),
      body: FutureBuilder<PioneerSourceCatalog>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load Pioneer sources: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final catalog = snapshot.data!;
          return FutureBuilder<Map<String, PioneerWorkInstallStatus>>(
            future: _installStatusFuture,
            builder: (context, installSnapshot) {
              if (!installSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final installStatuses = installSnapshot.data!;
              final selectedWorks = _selection.selectedWorks(catalog);
              final allVisibleWorks = catalog.works.toList(growable: false);
              final textSourceWorksList = allVisibleWorks
                  .where(
                    (work) =>
                        work.textCaptureStatus ==
                        PioneerTextCaptureStatus.textSource,
                  )
                  .toList(growable: false);
              final captureNeededWorksList = allVisibleWorks
                  .where(
                    (work) =>
                        work.textCaptureStatus ==
                        PioneerTextCaptureStatus.captureNeeded,
                  )
                  .toList(growable: false);
              final sourceNeededWorksList = allVisibleWorks
                  .where(
                    (work) =>
                        work.textCaptureStatus ==
                        PioneerTextCaptureStatus.sourceNeeded,
                  )
                  .toList(growable: false);
              final regularAuthors = catalog.authors
                  .where((author) => !isNeedsReviewAuthor(author))
                  .toList(growable: false);
              final visibleRegularAuthors = regularAuthors
                  .where((author) {
                    return author.works.any((work) {
                      if (!_showInstalled &&
                          installStatuses[work.id]?.isVerifiedInstalled ==
                              true) {
                        return false;
                      }
                      return true;
                    });
                  })
                  .toList(growable: false);
              final installedWorkCount = installStatuses.values
                  .where((status) => status.isVerifiedInstalled)
                  .length;
              final usableSourceCount = allVisibleWorks
                  .where((work) => work.hasUsableSourcePath)
                  .length;
              final captureNeededCount = captureNeededWorksList.length;
              final textSourceCount = textSourceWorksList.length;
              final sourceNeededCount = sourceNeededWorksList.length;
              final selectedAuthor = _selectedAuthorId == null
                  ? null
                  : catalog.authorById(_selectedAuthorId!);
              final visibleAuthorWorks =
                  (selectedAuthor?.works ?? const <PioneerSourceWork>[])
                      .where((work) {
                        if (!_showInstalled &&
                            installStatuses[work.id]?.isVerifiedInstalled ==
                                true) {
                          return false;
                        }
                        return true;
                      })
                      .toList(growable: false);
              final canImport =
                  selectedWorks.any(
                    (work) =>
                        _canSelectForImport(work, installStatuses[work.id]) &&
                        (work.isImportable ||
                            work.textCaptureAvailable ||
                            _canUseCopiedRangePath(work)),
                  ) &&
                  !_importing;
              final selectedInstallStatus = selectedWorks.length == 1
                  ? installStatuses[selectedWorks.single.id]
                  : null;
              final canRepairSelected =
                  selectedWorks.length == 1 &&
                  selectedInstallStatus?.hasLibraryRow == true &&
                  selectedWorks.single.hasSupportedImportSource &&
                  !_importing;
              final canSelectVisibleWorks =
                  selectedAuthor != null &&
                  visibleAuthorWorks.any(
                    (work) =>
                        _canSelectForImport(work, installStatuses[work.id]),
                  ) &&
                  !_importing;

              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pioneer Library Import',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Usable $usableSourceCount | Text capture $textSourceCount | Capture needed $captureNeededCount | Source needed $sourceNeededCount | Installed $installedWorkCount | Selected ${_selection.selectedCount}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_importStatusText != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _importStatusText!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _importing
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_importing) ...[
                            const SizedBox(height: 8),
                            LinearProgressIndicator(value: _importProgress),
                          ],
                        ],
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            if (selectedAuthor != null)
                              OutlinedButton.icon(
                                key: const ValueKey<String>(
                                  'pioneer-author-back-button',
                                ),
                                onPressed: _importing ? null : _closeAuthor,
                                icon: const Icon(Icons.arrow_back),
                                label: const Text('Authors'),
                              ),
                            OutlinedButton(
                              key: const ValueKey<String>(
                                'pioneer-refresh-catalog-button',
                              ),
                              onPressed: _importing ? null : _refreshCatalog,
                              child: const Text('Refresh'),
                            ),
                            OutlinedButton(
                              key: const ValueKey<String>(
                                'pioneer-select-all-available-button',
                              ),
                              onPressed: canSelectVisibleWorks
                                  ? () => _selectVisibleWorks(
                                      visibleAuthorWorks,
                                      installStatuses,
                                    )
                                  : null,
                              child: const Text('Select All'),
                            ),
                            // Build-time only: assets/scans is imported via
                            // dart run tool/elibrary_acquisition/import_scans_to_asset_db.dart
                            // and must not be scanned at runtime (macOS sandbox blocks it).
                            OutlinedButton(
                              key: const ValueKey<String>(
                                'pioneer-select-none-button',
                              ),
                              onPressed:
                                  _selection.selectedCount > 0 && !_importing
                                  ? _clearSelection
                                  : null,
                              child: const Text('None'),
                            ),
                            FilledButton(
                              key: const ValueKey<String>(
                                'pioneer-import-selected-button',
                              ),
                              onPressed: canImport
                                  ? () => _importSelected(catalog)
                                  : null,
                              child: const Text('Import Selected'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              key: const ValueKey<String>(
                                'pioneer-hide-installed-toggle',
                              ),
                              onPressed: _importing
                                  ? null
                                  : () {
                                      setState(() {
                                        _showInstalled = !_showInstalled;
                                      });
                                    },
                              child: Text(
                                _showInstalled
                                    ? 'Hide Installed'
                                    : 'Show Installed',
                              ),
                            ),
                            TextButton(
                              key: const ValueKey<String>(
                                'pioneer-more-actions-button',
                              ),
                              onPressed: _importing ? null : _toggleMoreActions,
                              child: Text(
                                _showMoreActions
                                    ? 'Hide More Actions'
                                    : 'More Actions',
                              ),
                            ),
                            TextButton(
                              key: const ValueKey<String>(
                                'pioneer-catalog-details-button',
                              ),
                              onPressed: catalog.diagnostics == null
                                  ? null
                                  : () => _showCatalogDetails(context, catalog),
                              child: const Text('Catalog Details'),
                            ),
                          ],
                        ),
                        if (_showMoreActions) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              if (canRepairSelected)
                                OutlinedButton(
                                  key: const ValueKey<String>(
                                    'pioneer-repair-button',
                                  ),
                                  onPressed: () => _repairSelected(
                                    catalog,
                                    selectedInstallStatus!,
                                  ),
                                  child: const Text('Reimport / Repair'),
                                ),
                              if (selectedWorks.length == 1 &&
                                  !selectedWorks.single.isImportable)
                                FilledButton.tonal(
                                  key: const ValueKey<String>(
                                    'pioneer-import-clipboard-button',
                                  ),
                                  onPressed: () => _importClipboard(catalog),
                                  child: const Text('Import Clipboard'),
                                ),
                              if (selectedWorks.length == 1 &&
                                  !selectedWorks.single.isImportable)
                                OutlinedButton(
                                  key: const ValueKey<String>(
                                    'pioneer-import-saved-export-button',
                                  ),
                                  onPressed: () => _importSavedExport(catalog),
                                  child: const Text('Import Saved Export'),
                                ),
                              if (selectedWorks.length == 1 &&
                                  selectedWorks.single.abbreviation
                                          .trim()
                                          .toUpperCase() ==
                                      'DAR')
                                OutlinedButton(
                                  key: const ValueKey<String>(
                                    'pioneer-import-egw-copied-range-button',
                                  ),
                                  onPressed: () => _importCopiedRange(catalog),
                                  child: const Text('Import EGW Copied Range'),
                                ),
                              if (_importing)
                                OutlinedButton(
                                  key: const ValueKey<String>(
                                    'pioneer-cancel-button',
                                  ),
                                  onPressed: _cancelImport,
                                  child: const Text('Cancel'),
                                ),
                              if (_importResult != null && !_importing)
                                TextButton(
                                  onPressed: _clearResults,
                                  child: const Text('Clear Results'),
                                ),
                              // TEMP DEV: reset DAR to uninstalled so capture screen is accessible
                              TextButton(
                                key: const ValueKey<String>(
                                  'pioneer-reset-dar-button',
                                ),
                                onPressed: _importing
                                    ? null
                                    : () => _resetWork(
                                        catalog,
                                        'daniel_and_the_revelation',
                                      ),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('Reset DAR'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    selectedAuthor == null
                        ? 'Pioneer Authors'
                        : selectedAuthor.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (selectedAuthor == null)
                    for (final author in visibleRegularAuthors) ...[
                      _PioneerAuthorCard(
                        author: author,
                        installStatuses: installStatuses,
                        onOpen: () => _openAuthor(author.id),
                      ),
                      const SizedBox(height: 8),
                    ]
                  else ...[
                    if (visibleAuthorWorks.isEmpty)
                      Text(
                        _showInstalled
                            ? 'No works are listed for this author yet.'
                            : 'No uninstalled works are visible for this author.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    for (final work in visibleAuthorWorks) ...[
                      _PioneerWorkTile(
                        key: ValueKey<String>(
                          'pioneer_work_${selectedAuthor.id}_${work.id}',
                        ),
                        checkboxKey: ValueKey<String>(
                          'pioneer_work_checkbox_${selectedAuthor.id}_${work.id}',
                        ),
                        infoButtonKey: ValueKey<String>(
                          'pioneer_work_info_${selectedAuthor.id}_${work.id}',
                        ),
                        work: work,
                        selected: _selection.isSelected(work.id),
                        enabled: _canSelectForImport(
                          work,
                          installStatuses[work.id],
                        ),
                        installStatus: installStatuses[work.id],
                        onChanged: () => _toggleWork(work),
                        onShowDetails: () => _showWorkDetails(
                          context,
                          work,
                          installStatuses[work.id],
                          catalog,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (selectedWorks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Selected works',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              for (final work in selectedWorks) ...[
                                _SelectedWorkSummaryLine(
                                  work: work,
                                  installStatus: installStatuses[work.id],
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (_importResult != null) ...[
                    const SizedBox(height: 12),
                    _ImportResultSummaryCard(result: _importResult!),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

@visibleForTesting
class PioneerHtmlCaptureDialogColors {
  const PioneerHtmlCaptureDialogColors({
    required this.outlinedForeground,
    required this.outlinedDisabledForeground,
    required this.outlinedBorder,
    required this.outlinedDisabledBorder,
    required this.overwriteBackground,
    required this.overwriteSelectedBackground,
    required this.overwriteDisabledBackground,
    required this.overwriteLabel,
    required this.overwriteSelectedLabel,
    required this.overwriteDisabledLabel,
    required this.overwriteCheckmark,
    required this.importBackground,
    required this.importForeground,
    required this.importDisabledBackground,
    required this.importDisabledForeground,
  });

  final Color outlinedForeground;
  final Color outlinedDisabledForeground;
  final Color outlinedBorder;
  final Color outlinedDisabledBorder;
  final Color overwriteBackground;
  final Color overwriteSelectedBackground;
  final Color overwriteDisabledBackground;
  final Color overwriteLabel;
  final Color overwriteSelectedLabel;
  final Color overwriteDisabledLabel;
  final Color overwriteCheckmark;
  final Color importBackground;
  final Color importForeground;
  final Color importDisabledBackground;
  final Color importDisabledForeground;
}

@visibleForTesting
PioneerHtmlCaptureDialogColors pioneerHtmlCaptureDialogColors(
  ColorScheme scheme,
) {
  return PioneerHtmlCaptureDialogColors(
    outlinedForeground: scheme.primary,
    outlinedDisabledForeground: scheme.onSurface.withValues(alpha: 0.46),
    outlinedBorder: scheme.outline,
    outlinedDisabledBorder: scheme.onSurface.withValues(alpha: 0.18),
    overwriteBackground: scheme.surfaceContainerHighest,
    overwriteSelectedBackground: scheme.primaryContainer,
    overwriteDisabledBackground: scheme.onSurface.withValues(alpha: 0.12),
    overwriteLabel: scheme.onSurfaceVariant,
    overwriteSelectedLabel: scheme.onPrimaryContainer,
    overwriteDisabledLabel: scheme.onSurface.withValues(alpha: 0.52),
    overwriteCheckmark: scheme.onPrimaryContainer,
    importBackground: scheme.primary,
    importForeground: scheme.onPrimary,
    importDisabledBackground: scheme.onSurface.withValues(alpha: 0.16),
    importDisabledForeground: scheme.onSurface.withValues(alpha: 0.52),
  );
}

ButtonStyle _htmlCaptureOutlinedButtonStyle(
  PioneerHtmlCaptureDialogColors colors,
) {
  return OutlinedButton.styleFrom(
    foregroundColor: colors.outlinedForeground,
    disabledForegroundColor: colors.outlinedDisabledForeground,
    side: BorderSide(color: colors.outlinedBorder),
  ).copyWith(
    side: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: colors.outlinedDisabledBorder);
      }
      return BorderSide(color: colors.outlinedBorder);
    }),
  );
}

ButtonStyle _htmlCaptureFilledButtonStyle(
  PioneerHtmlCaptureDialogColors colors,
) {
  return FilledButton.styleFrom(
    backgroundColor: colors.importBackground,
    foregroundColor: colors.importForeground,
    disabledBackgroundColor: colors.importDisabledBackground,
    disabledForegroundColor: colors.importDisabledForeground,
  );
}

class _HtmlCaptureFolderImportDialog extends StatefulWidget {
  const _HtmlCaptureFolderImportDialog({
    required this.scanResult,
    required this.previews,
    required this.importService,
  });

  final PioneerHtmlCaptureFolderScanResult scanResult;
  final List<PioneerHtmlCaptureFolderPreview> previews;
  final PioneerTextImportService importService;

  @override
  State<_HtmlCaptureFolderImportDialog> createState() =>
      _HtmlCaptureFolderImportDialogState();
}

class _HtmlCaptureFolderImportDialogState
    extends State<_HtmlCaptureFolderImportDialog> {
  late Set<String> _selectedFolderPaths;
  var _overwriteExisting = true;
  var _importing = false;
  var _progress = 0.0;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _selectedFolderPaths = widget.previews
        .where((preview) => preview.isValid)
        .map((preview) => preview.folderPath)
        .toSet();
  }

  List<PioneerHtmlCaptureFolderPreview> get _validPreviews => widget.previews
      .where((preview) => preview.isValid)
      .toList(growable: false);

  List<PioneerHtmlCaptureFolderPreview> get _selectedPreviews => widget.previews
      .where((preview) => _selectedFolderPaths.contains(preview.folderPath))
      .toList(growable: false);

  void _toggle(PioneerHtmlCaptureFolderPreview preview, bool? selected) {
    if (_importing || !preview.isValid) return;
    setState(() {
      if (selected == true) {
        _selectedFolderPaths.add(preview.folderPath);
      } else {
        _selectedFolderPaths.remove(preview.folderPath);
      }
    });
  }

  void _selectAll() {
    if (_importing) return;
    setState(() {
      _selectedFolderPaths = _validPreviews
          .map((preview) => preview.folderPath)
          .toSet();
    });
  }

  void _clearAll() {
    if (_importing) return;
    setState(() {
      _selectedFolderPaths.clear();
    });
  }

  Future<void> _importSelected() async {
    if (_importing || _selectedPreviews.isEmpty) return;
    setState(() {
      _importing = true;
      _progress = 0;
      _statusText = 'Starting capture import...';
    });
    final result = await widget.importService.importHtmlCaptureFolders(
      _selectedPreviews,
      existingImportPolicy: _overwriteExisting
          ? PioneerExistingImportPolicy.overwriteExisting
          : PioneerExistingImportPolicy.skipExisting,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress.fraction;
          _statusText = progress.message;
        });
      },
    );
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dialogColors = pioneerHtmlCaptureDialogColors(scheme);
    final selectedCount = _selectedPreviews.length;
    return AlertDialog(
      title: const Text('Import assets/scans'),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.previews.length} folder(s) found | $selectedCount selected',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.previews.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  widget.scanResult.emptyStateMessage,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _importing ? null : _selectAll,
                    style: _htmlCaptureOutlinedButtonStyle(dialogColors),
                    child: const Text('Select All'),
                  ),
                  OutlinedButton(
                    onPressed: _importing ? null : _clearAll,
                    style: _htmlCaptureOutlinedButtonStyle(dialogColors),
                    child: const Text('Clear All'),
                  ),
                  FilterChip(
                    label: const Text('Overwrite existing'),
                    selected: _overwriteExisting,
                    backgroundColor: dialogColors.overwriteBackground,
                    selectedColor: dialogColors.overwriteSelectedBackground,
                    disabledColor: dialogColors.overwriteDisabledBackground,
                    checkmarkColor: dialogColors.overwriteCheckmark,
                    labelStyle: TextStyle(
                      color: _importing
                          ? dialogColors.overwriteDisabledLabel
                          : _overwriteExisting
                          ? dialogColors.overwriteSelectedLabel
                          : dialogColors.overwriteLabel,
                      fontWeight: FontWeight.w600,
                    ),
                    onSelected: _importing
                        ? null
                        : (value) {
                            setState(() {
                              _overwriteExisting = value;
                            });
                          },
                  ),
                ],
              ),
              if (_statusText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _statusText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_importing) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _progress),
                ],
              ],
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.previews.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final preview = widget.previews[index];
                    final selected = _selectedFolderPaths.contains(
                      preview.folderPath,
                    );
                    final warningText = preview.warnings.join(' | ');
                    return CheckboxListTile(
                      value: selected,
                      onChanged: preview.isValid
                          ? (value) => _toggle(preview, value)
                          : null,
                      title: Text(
                        '${preview.folderName} • ${preview.detectedTitle ?? 'Unknown title'}',
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                preview.detectedAuthor ?? 'Unknown author',
                                preview.detectedAbbreviation ??
                                    'Unknown abbreviation',
                                'work_id: ${preview.metadata.workId ?? 'missing'}',
                                '${preview.htmlFileCount} HTML',
                                '${preview.imageFileCount} image',
                                '${preview.refCount} refs',
                                '${preview.generatedNavigationCount} nav',
                                'cover: ${preview.preferredCoverImagePath != null ? 'yes' : 'no'}',
                                preview.importStatus.label,
                              ].join(' • '),
                            ),
                            Text('Path: ${preview.folderPath}'),
                            if (preview.firstRef != null ||
                                preview.lastRef != null)
                              Text(
                                'Refs: ${preview.firstRef ?? '?'} to ${preview.lastRef ?? '?'}',
                              ),
                            if (preview.duplicateRefCount > 0)
                              Text(
                                'Duplicate refs: ${preview.duplicateRefCount}',
                                style: TextStyle(color: scheme.error),
                              ),
                            if (warningText.isNotEmpty)
                              Text(
                                warningText,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: preview.isValid
                                      ? scheme.onSurfaceVariant
                                      : scheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: dialogColors.outlinedForeground,
            disabledForegroundColor: dialogColors.outlinedDisabledForeground,
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_importing && selectedCount > 0 ? _importSelected : null,
          style: _htmlCaptureFilledButtonStyle(dialogColors),
          child: const Text('Import Selected'),
        ),
      ],
    );
  }
}

class _SelectedWorkSummaryLine extends StatelessWidget {
  const _SelectedWorkSummaryLine({
    required this.work,
    required this.installStatus,
  });

  final PioneerSourceWork work;
  final PioneerWorkInstallStatus? installStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = work.hasUsableSourcePath
        ? scheme.primary
        : work.textCaptureStatus == PioneerTextCaptureStatus.captureNeeded
        ? scheme.secondary
        : scheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${work.authorName} — ${work.title}',
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${work.abbreviation.isEmpty ? 'No abbreviation' : work.abbreviation} • ${work.group} / ${work.subgroup}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          work.compactImportStatusLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (installStatus != null) ...[
          const SizedBox(height: 2),
          Text(
            installStatus!.statusLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _PioneerAuthorCard extends StatelessWidget {
  const _PioneerAuthorCard({
    required this.author,
    required this.installStatuses,
    required this.onOpen,
  });

  final PioneerSourceAuthor author;
  final Map<String, PioneerWorkInstallStatus> installStatuses;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installedCount = author.works
        .where((work) => installStatuses[work.id]?.isVerifiedInstalled == true)
        .length;
    final captureNeededCount = author.works
        .where(
          (work) =>
              work.textCaptureStatus == PioneerTextCaptureStatus.captureNeeded,
        )
        .length;
    final textSourceCount = author.works
        .where(
          (work) =>
              work.textCaptureStatus == PioneerTextCaptureStatus.textSource,
        )
        .length;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        key: ValueKey<String>('pioneer_author_${author.id}'),
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      author.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${author.works.length} works | Text capture $textSourceCount | Capture needed $captureNeededCount | Installed $installedCount',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PioneerCoverThumb extends StatelessWidget {
  const _PioneerCoverThumb({required this.work});

  final PioneerSourceWork work;

  @override
  Widget build(BuildContext context) {
    final coverPath = work.coverImagePath;
    if (coverPath != null && coverPath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          coverPath,
          width: 42,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _FallbackCover(work: work),
        ),
      );
    }
    return _FallbackCover(work: work);
  }
}

class _FallbackCover extends StatelessWidget {
  const _FallbackCover({required this.work});

  final PioneerSourceWork work;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'Fallback cover for ${work.title}',
      child: Container(
        width: 42,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          work.fallbackCoverLabel,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSecondaryContainer,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PioneerWorkTile extends StatelessWidget {
  const _PioneerWorkTile({
    super.key,
    this.checkboxKey,
    this.infoButtonKey,
    required this.work,
    required this.selected,
    required this.enabled,
    required this.installStatus,
    required this.onChanged,
    this.onShowDetails,
  });

  final Key? checkboxKey;
  final Key? infoButtonKey;
  final PioneerSourceWork work;
  final bool selected;
  final bool enabled;
  final PioneerWorkInstallStatus? installStatus;
  final VoidCallback onChanged;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final installed = installStatus?.hasLibraryRow == true;
    final statusLabel = installed
        ? installStatus!.statusLabel
        : work.compactImportStatusLabel;
    final statusColor = installed
        ? switch (installStatus!.qualityState) {
            PioneerInstalledQualityState.verified => scheme.tertiary,
            PioneerInstalledQualityState.needsReview => scheme.secondary,
            PioneerInstalledQualityState.partial => scheme.tertiary,
            PioneerInstalledQualityState.badImport => scheme.error,
            PioneerInstalledQualityState.empty => scheme.error,
            PioneerInstalledQualityState.frontMatterOnly => scheme.secondary,
            PioneerInstalledQualityState.navigationBroken => scheme.error,
            PioneerInstalledQualityState.notInstalled =>
              scheme.onSurfaceVariant,
          }
        : work.textCaptureStatus == PioneerTextCaptureStatus.textSource
        ? scheme.primary
        : work.textCaptureStatus == PioneerTextCaptureStatus.captureNeeded
        ? scheme.secondary
        : scheme.error;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onChanged : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 72,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  Checkbox(
                    key: checkboxKey,
                    value: selected,
                    onChanged: enabled ? (_) => onChanged() : null,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 2),
                  _PioneerCoverThumb(work: work),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          work.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          work.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (onShowDetails != null) ...[
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        key: infoButtonKey,
                        tooltip: 'Details',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        visualDensity: VisualDensity.compact,
                        onPressed: onShowDetails,
                        icon: const Icon(Icons.info_outline, size: 18),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool isNeedsReviewAuthor(PioneerSourceAuthor author) {
  return author.id == 'needs_review' ||
      author.name.toLowerCase() == 'needs review';
}

class _ImportResultSummaryCard extends StatelessWidget {
  const _ImportResultSummaryCard({required this.result});

  final PioneerImportBatchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import results', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Imported ${result.importedCount} • Skipped ${result.skippedCount} • Failed ${result.failedCount}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final workResult in result.workResults) ...[
              _ImportResultLine(result: workResult),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportResultLine extends StatelessWidget {
  const _ImportResultLine({required this.result});

  final PioneerImportWorkResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = switch (result.status) {
      PioneerImportWorkStatus.imported => scheme.primary,
      PioneerImportWorkStatus.skippedExisting => scheme.secondary,
      PioneerImportWorkStatus.packageLineageConflict => scheme.error,
      PioneerImportWorkStatus.skippedNotImportable ||
      PioneerImportWorkStatus.skippedUnsupportedSource => scheme.error,
      PioneerImportWorkStatus.failed =>
        result.requiresManualVerification ? scheme.tertiary : scheme.error,
    };
    final statusLabel = switch (result.status) {
      PioneerImportWorkStatus.imported => 'Imported',
      PioneerImportWorkStatus.skippedExisting => 'Skipped existing',
      PioneerImportWorkStatus.packageLineageConflict =>
        'Package lineage conflict',
      PioneerImportWorkStatus.skippedNotImportable => 'Blocked',
      PioneerImportWorkStatus.skippedUnsupportedSource => 'Unsupported',
      PioneerImportWorkStatus.failed =>
        result.requiresManualVerification
            ? 'Needs manual verification'
            : 'Failed',
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.book_outlined, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${result.work.authorName} — ${result.work.title}',
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$statusLabel • ${result.work.sourceTypeLabel} • ${result.work.sourceSiteLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Stage: ${result.stage}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Source method: ${result.sourceMethodLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Source path: ${result.preferredImportPreferenceLabel}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                result.reason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Ref codes: ${result.refCodeHandlingSummary}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (result.detail != null &&
                  result.detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  result.detail!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (result.httpStatusCode != null ||
                  result.contentType != null ||
                  result.downloadedByteCount != null) ...[
                const SizedBox(height: 2),
                Text(
                  [
                    if (result.httpStatusCode != null)
                      'HTTP ${result.httpStatusCode}',
                    if (result.contentType != null &&
                        result.contentType!.trim().isNotEmpty)
                      result.contentType!,
                    if (result.downloadedByteCount != null)
                      '${result.downloadedByteCount} bytes',
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (result.parsedSectionCount != null ||
                  result.parsedParagraphCount != null) ...[
                const SizedBox(height: 2),
                Text(
                  [
                    if (result.parsedSectionCount != null)
                      '${result.parsedSectionCount} parsed section${result.parsedSectionCount == 1 ? '' : 's'}',
                    if (result.parsedParagraphCount != null)
                      '${result.parsedParagraphCount} text block${result.parsedParagraphCount == 1 ? '' : 's'}',
                  ].join(' • '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (result.manualVerificationHint != null &&
                  result.manualVerificationHint!.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  result.manualVerificationHint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if ((result.work.sourceUrl ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    result.work.sourceUrl!.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final sourceUrl = result.work.sourceUrl?.trim();
                        if (sourceUrl == null || sourceUrl.isEmpty) return;
                        await Clipboard.setData(ClipboardData(text: sourceUrl));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Source URL copied.')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy source URL'),
                    ),
                  ),
                ],
              ],
              if (result.libraryItemId.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Library item id: ${result.libraryItemId}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (result.exceptionType != null &&
                  result.exceptionType!.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  'Exception: ${result.exceptionType}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
