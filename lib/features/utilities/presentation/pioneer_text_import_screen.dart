import 'package:flutter/material.dart';

import '../data/pioneer_text_import_service.dart';
import '../data/pioneer_source_catalog.dart';

class PioneerTextImportScreen extends StatefulWidget {
  const PioneerTextImportScreen({super.key});

  @override
  State<PioneerTextImportScreen> createState() =>
      _PioneerTextImportScreenState();
}

class _PioneerTextImportScreenState extends State<PioneerTextImportScreen> {
  late final Future<PioneerSourceCatalog> _catalogFuture;
  late final PioneerTextImportService _importService;
  PioneerSourceSelection _selection = PioneerSourceSelection.empty();
  bool _importing = false;
  double _importProgress = 0;
  String? _importStatusText;
  PioneerImportBatchResult? _importResult;

  @override
  void initState() {
    super.initState();
    _importService = PioneerTextImportService.instance;
    _catalogFuture = PioneerSourceCatalog.load();
  }

  void _toggleWork(PioneerSourceWork work) {
    if (!work.isImportable || _importing) {
      return;
    }
    setState(() {
      _selection = _selection.toggle(work.id);
      _importResult = null;
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
      _importProgress = 0;
      _importStatusText = 'Starting import...';
      _importResult = null;
    });

    try {
      final result = await _importService.importSelectedWorks(
        importableWorks,
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
        _importProgress = 1;
        _importStatusText = _buildImportSummaryText(result);
        _importResult = result;
        _selection = PioneerSourceSelection.empty();
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
    return [
      'Imported ${result.importedCount} work${result.importedCount == 1 ? '' : 's'}',
      'Skipped ${result.skippedCount}',
      'Failed ${result.failedCount}',
    ].join(' • ');
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
          final importableWorkCount =
              catalog.works.where((work) => work.isImportable).length;
          final blockedWorkCount = catalog.workCount - importableWorkCount;
          final canImport = importableWorks.isNotEmpty && !_importing;

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
                        'Only import works you are legally permitted to download and use. Verify source terms before import.',
                        style: theme.textTheme.bodyLarge,
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
                        '$importableWorkCount available • $blockedWorkCount source needed',
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
                      FilledButton(
                        onPressed: canImport
                            ? () => _importSelected(catalog)
                            : null,
                        child: const Text('Import Selected'),
                      ),
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
                        'Pioneer catalog',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expand an author to browse the seeded Pioneer works. Verified sources are importable. Source needed works remain visible but are disabled until a verified source is added.',
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
            enabled: work.isImportable,
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
    required this.work,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final PioneerSourceWork work;
  final bool selected;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = work.isImportable ? scheme.primary : scheme.error;

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
                        'Abbreviation: ${work.abbreviation.isEmpty ? 'n/a' : work.abbreviation}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
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
      PioneerImportWorkStatus.failed => scheme.error,
    };
    final statusLabel = switch (result.status) {
      PioneerImportWorkStatus.imported => 'Imported',
      PioneerImportWorkStatus.skippedExisting => 'Skipped existing',
      PioneerImportWorkStatus.skippedNotImportable => 'Blocked',
      PioneerImportWorkStatus.skippedUnsupportedSource => 'Unsupported',
      PioneerImportWorkStatus.failed => 'Failed',
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
                '$statusLabel${result.reason.isNotEmpty ? ' • ${result.reason}' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (result.isImported) ...[
                const SizedBox(height: 2),
                Text(
                  'Rows: ${result.insertedLibraryItems} library item, ${result.insertedNavigationItems} navigation items, ${result.insertedTextBlocks} text blocks',
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
