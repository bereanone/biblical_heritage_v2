import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/pioneer_text_import_service.dart';
import '../data/pioneer_source_catalog.dart';

class PioneerTextImportScreen extends StatefulWidget {
  const PioneerTextImportScreen({
    super.key,
    this.catalogFuture,
    this.importService,
  });

  final Future<PioneerSourceCatalog>? catalogFuture;
  final PioneerTextImportService? importService;

  @override
  State<PioneerTextImportScreen> createState() =>
      _PioneerTextImportScreenState();
}

class _PioneerTextImportScreenState extends State<PioneerTextImportScreen> {
  late final Future<PioneerSourceCatalog> _catalogFuture;
  late final PioneerTextImportService _importService;
  PioneerSourceSelection _selection = PioneerSourceSelection.empty();
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
  }

  void _toggleWork(PioneerSourceWork work) {
    if (_importing) {
      return;
    }
    setState(() {
      _selection = _selection.toggle(work.id);
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

  Future<void> _importSelected(PioneerSourceCatalog catalog) async {
    if (_importing) return;
    final importableWorks = _selection.importableSelectedWorks(catalog);
    if (importableWorks.isEmpty) {
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
    ].join(' • ');
    return result.wasCancelled ? '$summary • Cancelled' : summary;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pioneer Text Import'),
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
          final selectedWorks = _selection.selectedWorks(catalog);
          final importableWorks = _selection.importableSelectedWorks(catalog);
          final importableWorksList = catalog.importableWorks.toList(growable: false);
          final sourceNeededWorksList = catalog.sourceNeededWorks.toList(growable: false);
          final importableWorkCount = importableWorksList.length;
          final sourceNeededWorkCount = sourceNeededWorksList.length;
          final canImport = importableWorks.isNotEmpty && !_importing;
          final canImportCapturedText =
              selectedWorks.length == 1 &&
              !selectedWorks.single.isImportable &&
              !_importing;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pioneer Text Import',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Import a few works at a time. Verified sources can batch import; clipboard or saved-export fallback works best one work at a time.',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'If a source returns a verification challenge, complete it manually and then continue with the source site’s own copy, save, or export controls.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${_selection.selectedCount} works selected',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$importableWorkCount verified now • $sourceNeededWorkCount source needed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
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
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          FilledButton(
                            onPressed: canImport
                                ? () => _importSelected(catalog)
                                : null,
                            child: const Text('Import Verified Sources'),
                          ),
                          FilledButton.tonal(
                            onPressed: canImportCapturedText
                                ? () => _importClipboard(catalog)
                                : null,
                            child: const Text('Import Clipboard'),
                          ),
                          OutlinedButton(
                            onPressed: canImportCapturedText
                                ? () => _importSavedExport(catalog)
                                : null,
                            child: const Text('Import Saved Export'),
                          ),
                          OutlinedButton(
                            onPressed: _importing ? _cancelImport : null,
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed:
                                _importResult == null || _importing
                                    ? null
                                    : _clearResults,
                            child: const Text('Clear Results'),
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
                        'Available to import',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verified source-backed Pioneer works are listed here first so you can choose one or both without hunting through the author groups below.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final work in importableWorksList) ...[
                        _PioneerWorkTile(
                          key: ValueKey<String>('available-${work.id}'),
                          work: work,
                          selected: _selection.isSelected(work.id),
                          enabled: true,
                          displayMode: _PioneerWorkDisplayMode.available,
                          onChanged: () => _toggleWork(work),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (selectedWorks.isNotEmpty)
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
                          _SelectedWorkSummaryLine(work: work),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                ),
              if (selectedWorks.isNotEmpty) const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Source needed works',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'These works stay visible even without a verified direct URL. Select one of them, then import from clipboard or a saved export after you complete the source-site verification manually.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final work in sourceNeededWorksList) ...[
                        _PioneerWorkTile(
                          key: ValueKey<String>('source-needed-${work.id}'),
                          work: work,
                          selected: _selection.isSelected(work.id),
                          enabled: true,
                          displayMode: _PioneerWorkDisplayMode.catalog,
                          onChanged: () => _toggleWork(work),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (sourceNeededWorksList.isEmpty)
                        Text(
                          'No source-needed Pioneer works are currently seeded.',
                          style: theme.textTheme.bodySmall?.copyWith(
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
                        'Pioneer catalog',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expand an author to browse the seeded Pioneer works. Verified sources can batch import, and source-needed works remain selectable if you want to import from clipboard or a saved export.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (final author in catalog.authors) ...[
                        _PioneerAuthorSection(
                          author: author,
                          selection: _selection,
                          onToggleWork: _toggleWork,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              if (_importResult != null) ...[
                const SizedBox(height: 12),
                _ImportResultSummaryCard(result: _importResult!),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SelectedWorkSummaryLine extends StatelessWidget {
  const _SelectedWorkSummaryLine({required this.work});

  final PioneerSourceWork work;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = work.isImportable ? scheme.primary : scheme.error;
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
          work.friendlyAvailabilityLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

enum _PioneerWorkDisplayMode {
  available,
  catalog,
}

class _PioneerAuthorSection extends StatelessWidget {
  const _PioneerAuthorSection({
    required this.author,
    required this.selection,
    required this.onToggleWork,
  });

  final PioneerSourceAuthor author;
  final PioneerSourceSelection selection;
  final void Function(PioneerSourceWork work) onToggleWork;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ExpansionTile(
      key: PageStorageKey<String>('pioneer-author-${author.id}'),
      maintainState: true,
      title: Text(
        author.name,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        '${author.works.length} work${author.works.length == 1 ? '' : 's'}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      children: [
        for (final work in author.works) ...[
          _PioneerWorkTile(
            work: work,
            selected: selection.isSelected(work.id),
            enabled: true,
            displayMode: _PioneerWorkDisplayMode.catalog,
            onChanged: () => onToggleWork(work),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PioneerWorkTile extends StatelessWidget {
  const _PioneerWorkTile({
    super.key,
    required this.work,
    required this.selected,
    required this.enabled,
    required this.displayMode,
    required this.onChanged,
  });

  final PioneerSourceWork work;
  final bool selected;
  final bool enabled;
  final _PioneerWorkDisplayMode displayMode;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = work.isImportable ? scheme.primary : scheme.error;
    final isAvailableMode = displayMode == _PioneerWorkDisplayMode.available;
    final sourceType = work.sourceTypeLabel;
    final sourceSite = work.sourceSiteLabel;

    return Opacity(
      opacity: enabled ? 1 : 0.56,
      child: InkWell(
        onTap: enabled ? onChanged : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: enabled ? (_) => onChanged() : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.title,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Author: ${work.authorName}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Abbreviation: ${work.abbreviation.isEmpty ? 'n/a' : work.abbreviation}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (isAvailableMode) ...[
                        Text(
                          'Source type: $sourceType',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Source site: $sourceSite',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Status: ${work.friendlyAvailabilityLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Group: ${work.group.isEmpty ? 'n/a' : work.group} • Subgroup: ${work.subgroup.isEmpty ? 'n/a' : work.subgroup}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Availability: ${work.friendlyAvailabilityLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Source status: ${work.friendlySourceStatusLabel}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (work.notes != null &&
                            work.notes!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            work.notes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Chip(
                  label: Text(work.friendlyAvailabilityLabel),
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: work.isImportable ? scheme.primary : scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide(
                    color: work.isImportable
                        ? scheme.primary.withValues(alpha: 0.4)
                        : scheme.error.withValues(alpha: 0.4),
                  ),
                  backgroundColor: work.isImportable
                      ? scheme.primary.withValues(alpha: 0.08)
                      : scheme.error.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
            Text(
              'Import results',
              style: theme.textTheme.titleMedium,
            ),
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
      PioneerImportWorkStatus.skippedNotImportable ||
      PioneerImportWorkStatus.skippedUnsupportedSource => scheme.error,
      PioneerImportWorkStatus.failed => result.requiresManualVerification
          ? scheme.tertiary
          : scheme.error,
    };
    final statusLabel = switch (result.status) {
      PioneerImportWorkStatus.imported => 'Imported',
      PioneerImportWorkStatus.skippedExisting => 'Skipped existing',
      PioneerImportWorkStatus.skippedNotImportable => 'Blocked',
      PioneerImportWorkStatus.skippedUnsupportedSource => 'Unsupported',
      PioneerImportWorkStatus.failed =>
          result.requiresManualVerification ? 'Needs manual verification' : 'Failed',
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
              if (result.detail != null && result.detail!.trim().isNotEmpty) ...[
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
                          const SnackBar(
                            content: Text('Source URL copied.'),
                          ),
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
