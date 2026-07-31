import 'package:flutter/material.dart';

import '../../library/data/library_catalog_service.dart';
import '../../library/presentation/library_book_reader_screen.dart';
import '../data/pioneer_captured_html_import_review_store.dart';

class PioneerCapturedHtmlImportReviewScreen extends StatefulWidget {
  const PioneerCapturedHtmlImportReviewScreen({super.key});

  @override
  State<PioneerCapturedHtmlImportReviewScreen> createState() =>
      _PioneerCapturedHtmlImportReviewScreenState();
}

class _PioneerCapturedHtmlImportReviewScreenState
    extends State<PioneerCapturedHtmlImportReviewScreen> {
  bool _loading = true;
  List<PioneerCapturedHtmlImportReviewEntry> _entries =
      const <PioneerCapturedHtmlImportReviewEntry>[];

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final entries = await PioneerCapturedHtmlImportReviewStore.instance
          .loadRecentEntries();
      if (!mounted) return;
      setState(() => _entries = entries);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(
    ThemeData theme,
    PioneerCapturedHtmlImportReviewEntry entry,
  ) {
    if (entry.isFailed) return theme.colorScheme.errorContainer;
    if (entry.isNeedsCleanup) {
      return theme.colorScheme.tertiaryContainer;
    }
    if (entry.isSkippedDuplicate) {
      return theme.colorScheme.surfaceContainerHighest;
    }
    return theme.colorScheme.secondaryContainer;
  }

  Color _statusBorderColor(
    ThemeData theme,
    PioneerCapturedHtmlImportReviewEntry entry,
  ) {
    if (entry.isFailed) return theme.colorScheme.error;
    if (entry.isNeedsCleanup) return theme.colorScheme.tertiary;
    if (entry.isSkippedDuplicate) return theme.colorScheme.outlineVariant;
    return theme.colorScheme.primary;
  }

  Future<void> _openImportedItem(
    PioneerCapturedHtmlImportReviewEntry entry,
  ) async {
    final itemId = entry.libraryItemId?.trim() ?? '';
    if (itemId.isEmpty) return;
    final item = await LibraryCatalogService.instance.loadItemById(itemId);
    if (!mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Imported item is no longer available.')),
      );
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: item,
          initialHref: item.epubHref,
          initialAnchorId: item.anchorId,
          initialSpineIndex: item.spineIndex,
          initialParagraphIndex: item.paragraphIndex,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review CaptureClipper Imports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadEntries,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadEntries,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No recent CaptureClipper imports yet.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: _entries.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  final statusColor = _statusColor(theme, entry);
                  final borderColor = _statusBorderColor(theme, entry);
                  return Container(
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.title.isEmpty
                                          ? 'Untitled import'
                                          : entry.title,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.author.isEmpty
                                          ? 'Unknown author'
                                          : entry.author,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Chip(label: Text(entry.displayStatusLabel)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            entry.sourceRelativePath.isNotEmpty
                                ? entry.sourceRelativePath
                                : entry.sourceFilePath,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (entry.warningOrFailureReason != null &&
                              entry.warningOrFailureReason!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(entry.warningOrFailureReason!),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            '${entry.sourceType} • ${MaterialLocalizations.of(context).formatFullDate(entry.importedAt.toLocal())}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: entry.hasLibraryItemId
                                  ? () => _openImportedItem(entry)
                                  : null,
                              child: const Text('Open imported item'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
