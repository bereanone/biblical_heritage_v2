import 'package:flutter/material.dart';

enum LibraryIndexingPromptAction { indexNow, later }

/// Tracks whether the "books need indexing" prompt has already been shown
/// once for the lifetime of a screen instance, so a later state refresh
/// (e.g. returning from Manage Library Root) does not reopen it repeatedly
/// while pending items remain.
class LibraryIndexingPromptGate {
  bool _shown = false;

  bool shouldPrompt(int pendingCount) {
    if (_shown || pendingCount <= 0) return false;
    _shown = true;
    return true;
  }
}

Future<LibraryIndexingPromptAction?> showLibraryIndexingPromptDialog(
  BuildContext context, {
  required int pendingCount,
}) {
  return showDialog<LibraryIndexingPromptAction>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Finish Setting Up Your Library'),
      content: Text(libraryIndexingPromptBody(pendingCount)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(LibraryIndexingPromptAction.later),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            dialogContext,
          ).pop(LibraryIndexingPromptAction.indexNow),
          child: const Text('Index Now'),
        ),
      ],
    ),
  );
}

String libraryIndexingPromptBody(int pendingCount) {
  final noun = pendingCount == 1 ? 'book' : 'books';
  final verb = pendingCount == 1 ? 'needs' : 'need';
  return '$pendingCount downloaded $noun still $verb indexing. Indexing '
      "enables chapters, search, reading position, and today's devotional "
      'entry.';
}

/// Persistent, non-intrusive banner shown while managed library items remain
/// unindexed. Stays visible until indexing succeeds and the pending count
/// reaches zero.
class LibraryIndexingPendingCard extends StatelessWidget {
  const LibraryIndexingPendingCard({
    super.key,
    required this.pendingCount,
    required this.busy,
    required this.onIndexNow,
  });

  final int pendingCount;
  final bool busy;
  final VoidCallback onIndexNow;

  @override
  Widget build(BuildContext context) {
    if (pendingCount <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$pendingCount book${pendingCount == 1 ? '' : 's'} '
              '${pendingCount == 1 ? 'needs' : 'need'} indexing',
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              libraryIndexingPromptBody(pendingCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : onIndexNow,
              child: Text(busy ? 'Indexing…' : 'Index Now'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A managed EPUB whose source file failed structural validation and so
/// cannot be indexed until it is replaced. Carries just enough detail
/// (title/file/reason) for the setup-screen card to surface it honestly
/// instead of the item silently sitting at 0% indexed.
class LibraryNeedsAttentionEntry {
  const LibraryNeedsAttentionEntry({
    required this.title,
    required this.fileName,
    required this.reason,
  });

  final String title;
  final String fileName;
  final String? reason;
}

String _libraryNeedsAttentionTitle(LibraryNeedsAttentionEntry item) {
  final title = item.title.trim();
  if (title.isNotEmpty) return title;
  final fileName = item.fileName.trim();
  if (fileName.isNotEmpty) return fileName;
  return 'Untitled book';
}

String _libraryNeedsAttentionFriendlyReason(String? reason) {
  final normalized = reason?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return 'The downloaded book file could not be prepared for reading.';
  }
  if (normalized.contains('no readable text content found')) {
    return 'No readable book content was found.';
  }
  if (normalized.contains('opf') ||
      normalized.contains('spine') ||
      normalized.contains('container.xml')) {
    return 'The downloaded book file is incomplete.';
  }
  return 'The downloaded book file could not be prepared for reading.';
}

/// Compact warning card for managed EPUBs that need attention. The card keeps
/// the summary human-friendly by default and exposes technical details behind
/// a review toggle for support/debugging.
class LibraryNeedsAttentionCard extends StatefulWidget {
  const LibraryNeedsAttentionCard({
    super.key,
    required this.items,
    this.onRetryRepairable,
    this.onRefresh,
  });

  final List<LibraryNeedsAttentionEntry> items;
  final VoidCallback? onRetryRepairable;
  final VoidCallback? onRefresh;

  @override
  State<LibraryNeedsAttentionCard> createState() =>
      _LibraryNeedsAttentionCardState();
}

class _LibraryNeedsAttentionCardState extends State<LibraryNeedsAttentionCard> {
  bool _showDetails = false;

  void _toggleDetails() {
    setState(() => _showDetails = !_showDetails);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = widget.items;
    return Card(
      elevation: 0,
      color: Color.lerp(scheme.errorContainer, scheme.surface, 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.error.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: scheme.error,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${items.length} book${items.length == 1 ? '' : 's'} '
                    'need${items.length == 1 ? 's' : ''} attention',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'These books could not be prepared for reading.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _toggleDetails,
                  icon: Icon(
                    _showDetails
                        ? Icons.expand_less
                        : Icons.manage_search_outlined,
                  ),
                  label: Text(_showDetails ? 'Hide Details' : 'Review Details'),
                ),
                FilledButton.tonalIcon(
                  onPressed: widget.onRetryRepairable,
                  icon: const Icon(Icons.build_circle_outlined),
                  label: const Text('Retry Repairable'),
                ),
                IconButton(
                  tooltip: 'Refresh warning status',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_showDetails) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Review Details',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final item in items) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _libraryNeedsAttentionTitle(item),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  'Filename: ${item.fileName.trim().isEmpty ? '(not set)' : item.fileName.trim()}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  'Technical reason: ${_libraryNeedsAttentionFriendlyReason(item.reason)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                SelectableText(
                                  'Exact index_error: ${(item.reason?.trim().isNotEmpty == true ? item.reason!.trim() : 'No diagnostic details available.')}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
