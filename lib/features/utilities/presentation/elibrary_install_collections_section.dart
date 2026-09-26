part of 'elibrary_setup_screen.dart';

const _installCollectionsDisclosureText =
    'Books are downloaded directly from the official EGW Writings website into your eLibrary. Please follow the source website\'s terms and do not redistribute downloaded files.';

const _collectionTitles = <String>[
  'EGW Books',
  'EGW Devotionals',
  'EGW Commentaries',
  'EGW Miscellaneous',
  'EGW Pamphlets',
  'EGW Periodicals',
  'EGW Manuscript Releases',
];

bool _isMeaningfulCollectionEstimateText(String text) {
  final normalized = text.trim();
  return normalized.isNotEmpty &&
      normalized != '0 files found • size unknown' &&
      normalized != 'file count not cached yet • size unknown';
}

String _displaySelectedDownloadSummary(String summary) {
  if (summary == 'Selected download: 0 files found • size unknown' ||
      summary ==
          'Selected download: file count not cached yet • size unknown') {
    return 'No collections selected';
  }
  return summary;
}

class ELibraryInstallCollectionsSection extends StatelessWidget {
  const ELibraryInstallCollectionsSection({
    super.key,
    required this.running,
    required this.selectionWarning,
    required this.installBooks,
    required this.installDevotionals,
    required this.installCommentaries,
    required this.installMiscCollections,
    required this.installPamphlets,
    required this.installPeriodicals,
    required this.installManuscriptReleases,
    required this.installEpub,
    required this.installPdf,
    required this.collectionEstimateLines,
    required this.selectedDownloadSummary,
    required this.onSelectAllCollectionsAndFormats,
    required this.onClearAllSelections,
    required this.onSetPresetEpubOnly,
    required this.onSetPresetPdfOnly,
    required this.onSetPresetBoth,
    required this.onStartSetup,
    required this.onCancel,
    required this.onBooksChanged,
    required this.onDevotionalsChanged,
    required this.onCommentariesChanged,
    required this.onMiscCollectionsChanged,
    required this.onPamphletsChanged,
    required this.onPeriodicalsChanged,
    required this.onManuscriptReleasesChanged,
    required this.onEpubChanged,
    required this.onPdfChanged,
  });

  final bool running;
  final String? selectionWarning;
  final bool installBooks;
  final bool installDevotionals;
  final bool installCommentaries;
  final bool installMiscCollections;
  final bool installPamphlets;
  final bool installPeriodicals;
  final bool installManuscriptReleases;
  final bool installEpub;
  final bool installPdf;
  final List<String> collectionEstimateLines;
  final String selectedDownloadSummary;
  final VoidCallback onSelectAllCollectionsAndFormats;
  final VoidCallback onClearAllSelections;
  final VoidCallback onSetPresetEpubOnly;
  final VoidCallback onSetPresetPdfOnly;
  final VoidCallback onSetPresetBoth;
  final VoidCallback onStartSetup;
  final VoidCallback onCancel;
  final ValueChanged<bool?> onBooksChanged;
  final ValueChanged<bool?> onDevotionalsChanged;
  final ValueChanged<bool?> onCommentariesChanged;
  final ValueChanged<bool?> onMiscCollectionsChanged;
  final ValueChanged<bool?> onPamphletsChanged;
  final ValueChanged<bool?> onPeriodicalsChanged;
  final ValueChanged<bool?> onManuscriptReleasesChanged;
  final ValueChanged<bool?> onEpubChanged;
  final ValueChanged<bool?> onPdfChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    String estimateLine(int index) => collectionEstimateLines[index];
    String collectionTitle(int index) => _collectionTitles[index];
    String? collectionEstimateText(int index) {
      final estimate = estimateLine(index);
      return _isMeaningfulCollectionEstimateText(estimate) ? estimate : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose Collections', style: theme.textTheme.titleMedium),
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
              label: const Text('Select All Collections + All File Types'),
              onPressed: running ? null : onSelectAllCollectionsAndFormats,
            ),
            ActionChip(
              label: const Text('Clear All'),
              onPressed: running ? null : onClearAllSelections,
            ),
            ActionChip(
              label: const Text('EPUB Only'),
              onPressed: running ? null : onSetPresetEpubOnly,
            ),
            ActionChip(
              label: const Text('PDF Only'),
              onPressed: running ? null : onSetPresetPdfOnly,
            ),
            ActionChip(
              label: const Text('EPUB + PDF'),
              onPressed: running ? null : onSetPresetBoth,
            ),
          ],
        ),
        if (selectionWarning != null) ...[
          const SizedBox(height: 12),
          Text(
            selectionWarning!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 16),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installBooks,
          onChanged: running ? null : onBooksChanged,
          title: Text(collectionTitle(0)),
          subtitle: collectionEstimateText(0) == null
              ? null
              : Text(
                  collectionEstimateText(0)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installDevotionals,
          onChanged: running ? null : onDevotionalsChanged,
          title: Text(collectionTitle(1)),
          subtitle: collectionEstimateText(1) == null
              ? null
              : Text(
                  collectionEstimateText(1)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installCommentaries,
          onChanged: running ? null : onCommentariesChanged,
          title: Text(collectionTitle(2)),
          subtitle: collectionEstimateText(2) == null
              ? null
              : Text(
                  collectionEstimateText(2)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installMiscCollections,
          onChanged: running ? null : onMiscCollectionsChanged,
          title: Text(collectionTitle(3)),
          subtitle: collectionEstimateText(3) == null
              ? null
              : Text(
                  collectionEstimateText(3)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installPamphlets,
          onChanged: running ? null : onPamphletsChanged,
          title: Text(collectionTitle(4)),
          subtitle: collectionEstimateText(4) == null
              ? null
              : Text(
                  collectionEstimateText(4)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installPeriodicals,
          onChanged: running ? null : onPeriodicalsChanged,
          title: Text(collectionTitle(5)),
          subtitle: collectionEstimateText(5) == null
              ? null
              : Text(
                  collectionEstimateText(5)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          controlAffinity: ListTileControlAffinity.trailing,
          value: installManuscriptReleases,
          onChanged: running ? null : onManuscriptReleasesChanged,
          title: Text(collectionTitle(6)),
          subtitle: collectionEstimateText(6) == null
              ? null
              : Text(
                  collectionEstimateText(6)!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Text(
          _displaySelectedDownloadSummary(selectedDownloadSummary),
          style: theme.textTheme.titleMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Divider(height: 24),
        CheckboxListTile(
          value: installEpub,
          onChanged: running ? null : onEpubChanged,
          title: const Text('EPUB'),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: installPdf,
          onChanged: running ? null : onPdfChanged,
          title: const Text('PDF'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 8),
        Text(
          _installCollectionsDisclosureText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton(
              onPressed: running ? null : onStartSetup,
              child: const Text('Install Selected'),
            ),
            OutlinedButton(
              onPressed: running ? onCancel : null,
              child: const Text('Cancel'),
            ),
          ],
        ),
      ],
    );
  }
}
