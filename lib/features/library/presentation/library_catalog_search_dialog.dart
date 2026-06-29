import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import '../data/library_catalog_service.dart';
import 'library_book_reader_screen.dart';
import 'library_catalog_search_panel.dart';
import 'library_font_scale.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';

double _libraryCatalogSearchDialogWidthFor(double screenWidth) {
  if (screenWidth < 700) {
    return (screenWidth - 32).clamp(280.0, double.infinity);
  }
  return (screenWidth * 0.75).clamp(0.0, 1100.0);
}

Future<void> showLibraryCatalogSearchDialog(
  BuildContext context, {
  required double fontScale,
  VoidCallback? onReturnToBible,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'eLibrary Search',
    barrierColor: Colors.black54,
    builder: (context) => LibraryFontScaleScope(
      scale: fontScale,
      child: _LibraryCatalogSearchDialog(onReturnToBible: onReturnToBible),
    ),
  );
}

class _LibraryCatalogSearchDialog extends StatelessWidget {
  const _LibraryCatalogSearchDialog({this.onReturnToBible});

  final VoidCallback? onReturnToBible;

  Future<void> _openItem(
    BuildContext context,
    LibraryCatalogSearchResult result,
    int index,
    List<LibraryCatalogSearchResult> results,
    String searchQuery,
    String collectionFilter,
  ) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final resolvedItem =
        await LibraryCatalogService.instance.loadItemById(result.item.id) ??
        result.item;
    navigator.pop();
    final session = LibraryCatalogSearchSession(
      query: searchQuery,
      collectionFilter: collectionFilter == 'all' ? null : collectionFilter,
      results: List<LibraryCatalogSearchResult>.unmodifiable(results),
      currentIndex: index,
    );
    unawaited(
      AppSettingsService.instance.saveLastElibrarySearchSessionJson(
        LibraryCatalogSearchSessionSnapshot.fromSession(session).toJsonString(),
      ),
    );
    unawaited(AppSettingsService.instance.saveLastElibrarySearch(searchQuery));
    unawaited(
      Future<void>.microtask(() {
        if (!navigator.mounted) return;
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => LibraryBookReaderScreen(
              item: resolvedItem,
              initialHref: resolvedItem.epubHref,
              initialAnchorId: resolvedItem.anchorId,
              initialSpineIndex: resolvedItem.spineIndex,
              initialParagraphIndex: resolvedItem.paragraphIndex,
              searchQuery: searchQuery,
              highlightTerms: extractLibrarySearchHighlightTerms(searchQuery),
              searchSession: session,
              onReturnToBible: onReturnToBible,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not add to #tag: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontScale = libraryFontScaleOf(context);

    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = _libraryCatalogSearchDialogWidthFor(screenSize.width);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      backgroundColor: theme.colorScheme.surface,
      child: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: dialogWidth,
            maxWidth: dialogWidth,
            maxHeight: screenSize.height * 0.85,
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
                        style: libraryScaledTextStyle(
                          theme.textTheme.titleMedium,
                          fontScale,
                          multiplier: 1.0,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
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
                  onSelectItem: (result, index, results, query, collection) =>
                      _openItem(
                        context,
                        result,
                        index,
                        results,
                        query,
                        collection,
                      ),
                  onQuickApplyItem: (result, query) =>
                      _quickApplyItem(context, result, query),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
