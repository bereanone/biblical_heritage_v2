import 'dart:async';

import 'package:flutter/material.dart';

import '../data/library_catalog_service.dart';
import 'library_book_reader_screen.dart';
import 'library_catalog_search_panel.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';

Future<void> showLibraryCatalogSearchDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'eLibrary Search',
    barrierColor: Colors.black54,
    builder: (context) => const _LibraryCatalogSearchDialog(),
  );
}

class _LibraryCatalogSearchDialog extends StatelessWidget {
  const _LibraryCatalogSearchDialog();

  void _openItem(
    BuildContext context,
    LibraryCatalogItem item,
    String searchQuery,
  ) {
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop();
    unawaited(
      Future<void>.microtask(() {
        if (!navigator.mounted) return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => LibraryBookReaderScreen(
              item: item,
              initialHref: item.epubHref,
              initialAnchorId: item.anchorId,
              initialSpineIndex: item.spineIndex,
              initialParagraphIndex: item.paragraphIndex,
              searchQuery: searchQuery,
              highlightTerms: extractLibrarySearchHighlightTerms(searchQuery),
            ),
          ),
        );
      }),
    );
  }

  String _stableRefForResult(LibraryCatalogSearchResult result) {
    final item = result.item;
    return [
      'elibrary',
      item.id.trim(),
      item.spineIndex?.toString() ?? '',
      item.paragraphIndex?.toString() ?? '',
      item.anchorId?.trim() ?? '',
      item.epubHref?.trim() ?? '',
    ].join(':');
  }

  Future<void> _quickApplyItem(
    BuildContext context,
    LibraryCatalogSearchResult result,
    String searchQuery,
  ) async {
    try {
      final paragraphText =
          (await LibraryCatalogService.instance.loadSearchResultParagraph(
                result,
              ))?.trim() ??
          '';
      if (paragraphText.isEmpty) {
        throw StateError('Missing paragraph text.');
      }
      final response = await HashTagRepository().quickApplyELibrarySearchResult(
        bookTitle: result.item.displayTitle,
        locationText: result.locationText,
        paragraphText: paragraphText,
        stableRef: _stableRefForResult(result),
        referenceText: result.referenceText,
        sourceHref: result.item.epubHref,
        sourceAnchorId: result.item.anchorId,
        sourceSpineIndex: result.item.spineIndex,
        sourceParagraphIndex: result.item.paragraphIndex,
        sourceRelativePath: result.item.relativePath,
        searchQuery: searchQuery,
      );
      if (!context.mounted || response.tag == null) return;
      final tagLabel = response.tag!;
      final message = response.inserted > 0
          ? (response.createdDefaultTag
              ? 'Created SearchResults and added result'
              : 'Added to $tagLabel')
          : response.skipped > 0
          ? 'Already in $tagLabel'
          : 'Could not add to $tagLabel';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add to #tag: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width.clamp(320.0, 720.0),
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close Search',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'eLibrary Search',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: LibraryCatalogSearchPanel(
                onSelectItem: (item, query) => _openItem(context, item, query),
                onQuickApplyItem: (result, query) =>
                    _quickApplyItem(context, result, query),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
