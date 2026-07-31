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

/// Compact notice for managed EPUBs that were set aside after indexing failed.
/// Details stay in an on-demand dialog so unreadable files do not dominate the
/// setup screen.
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
  Future<void> _showDetails() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${widget.items.length} unreadable '
          'book${widget.items.length == 1 ? '' : 's'} set aside',
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'These files remain safely stored, but are hidden from the '
                  'library because no readable book content was found.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final item in widget.items) ...[
                  Text(
                    _libraryNeedsAttentionTitle(item),
                    style: theme.textTheme.bodyMedium?.copyWith(
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
                    'Reason: ${_libraryNeedsAttentionFriendlyReason(item.reason)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (widget.onRetryRepairable != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onRetryRepairable!();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final items = widget.items;
    return Card(
      elevation: 0,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          '${items.length} unreadable '
          'book${items.length == 1 ? '' : 's'} set aside',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: const Text(
          'Hidden from the library; original files were preserved.',
        ),
        trailing: Wrap(
          spacing: 0,
          children: [
            TextButton(onPressed: _showDetails, child: const Text('Review')),
            if (widget.onRefresh != null)
              IconButton(
                tooltip: 'Refresh set-aside status',
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh),
              ),
          ],
        ),
      ),
    );
  }
}
