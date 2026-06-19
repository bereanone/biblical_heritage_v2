import 'package:flutter/material.dart';

import '../data/pioneer_source_catalog.dart';

class PioneerTextImportScreen extends StatefulWidget {
  const PioneerTextImportScreen({super.key});

  @override
  State<PioneerTextImportScreen> createState() =>
      _PioneerTextImportScreenState();
}

class _PioneerTextImportScreenState extends State<PioneerTextImportScreen> {
  late final Future<PioneerSourceCatalog> _catalogFuture;
  PioneerSourceSelection _selection = PioneerSourceSelection.empty();

  @override
  void initState() {
    super.initState();
    _catalogFuture = PioneerSourceCatalog.load();
  }

  void _toggleWork(PioneerSourceWork work) {
    setState(() {
      _selection = _selection.toggle(work.id);
    });
  }

  void _importSelected(PioneerSourceCatalog catalog) {
    final importableWorks = _selection.importableSelectedWorks(catalog);
    if (importableWorks.isEmpty) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pioneer import is not wired yet because no verified sources are available.',
        ),
      ),
    );
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
          final blockedWorks = _selection.blockedSelectedWorks(catalog);
          final blockMessage = _selection.importBlockMessage(catalog);
          final canImport = importableWorks.isNotEmpty;

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
                        '${importableWorks.length} importable • ${blockedWorks.length} source needed',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (blockMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          blockMessage,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: blockedWorks.isEmpty
                                ? scheme.primary
                                : scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
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
                        'Expand an author to browse the seeded Pioneer works. Items marked Source needed are visible for planning but cannot be imported until a verified source is added.',
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
    required this.onChanged,
  });

  final PioneerSourceWork work;
  final bool selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = work.isImportable ? scheme.primary : scheme.error;

    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: (_) => onChanged()),
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
                label: Text(work.isImportable ? 'Importable' : 'Source needed'),
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
    );
  }
}
