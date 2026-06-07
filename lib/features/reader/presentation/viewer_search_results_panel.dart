import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../../search/search_highlight_helper.dart';
import '../../search/search_result_quick_apply_button.dart';
import 'tag_dialog_styles.dart';

class ViewerSearchResultsPanel extends StatelessWidget {
  const ViewerSearchResultsPanel({
    super.key,
    required this.results,
    required this.isLoading,
    required this.hasSearched,
    required this.totalResultsCount,
    required this.titleStyle,
    required this.bodyStyle,
    this.highlightTerms = const [],
    this.currentTag,
    this.isCurrentTagLoading = false,
    required this.onSelectResult,
    this.onQuickApplyResult,
    required this.onLoadMore,
  });

  final List<PassageSearchResult> results;
  final bool isLoading;
  final bool hasSearched;
  final int totalResultsCount;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final List<String> highlightTerms;
  final String? currentTag;
  final bool isCurrentTagLoading;
  final void Function(PassageSearchResult result, int index) onSelectResult;
  final Future<void> Function(PassageSearchResult result)? onQuickApplyResult;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final hasCurrentTag = currentTag?.trim().isNotEmpty == true;
    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: currentTag,
              isLoading: isCurrentTagLoading,
              bodyStyle: bodyStyle,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    if (hasSearched && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: currentTag,
              isLoading: isCurrentTagLoading,
              bodyStyle: bodyStyle,
            ),
            const SizedBox(height: 20),
            Text('No matches found.', style: bodyStyle),
          ],
        ),
      );
    }

    if (!hasSearched) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: currentTag,
              isLoading: isCurrentTagLoading,
              bodyStyle: bodyStyle,
            ),
            const SizedBox(height: 20),
            Text(
              'Search the Bible and choose a verse to jump there.',
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
          child: _CurrentTagBanner(
            currentTag: currentTag,
            isLoading: isCurrentTagLoading,
            bodyStyle: bodyStyle,
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = results[index];
            final hasQuickApplyTarget =
                hasCurrentTag && onQuickApplyResult != null;
            final quickApplyTooltip = isCurrentTagLoading
                ? 'Loading current #tag...'
                : hasCurrentTag
                ? 'Add to $currentTag'
                : 'Choose a #tag';
            return ListTile(
              dense: true,
              minLeadingWidth: 40,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              isThreeLine: true,
              leading: onQuickApplyResult == null
                  ? null
                  : SearchResultQuickApplyButton(
                      tooltip: quickApplyTooltip,
                      onPressed: hasQuickApplyTarget && !isCurrentTagLoading
                          ? () {
                              unawaited(onQuickApplyResult!(result));
                            }
                          : null,
                    ),
              title: Text(
                '${result.bookName} ${result.chapter}:${result.verse}',
                style: titleStyle,
              ),
              subtitle: _HighlightedResultText(
                text: result.text,
                baseStyle: bodyStyle,
                highlightTerms: highlightTerms,
              ),
              onTap: () => onSelectResult(result, index),
            );
          },
        ),
        if (results.length < totalResultsCount)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.tonal(
              onPressed: onLoadMore,
              child: Text(
                'Load More (${totalResultsCount - results.length} remaining)',
              ),
            ),
          ),
      ],
    );
  }
}

class _CurrentTagBanner extends StatelessWidget {
  const _CurrentTagBanner({
    required this.currentTag,
    required this.isLoading,
    required this.bodyStyle,
  });

  final String? currentTag;
  final bool isLoading;
  final TextStyle? bodyStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCurrentTag = currentTag?.trim().isNotEmpty == true;
    final label = isLoading
        ? 'Current #tag: Loading...'
        : hasCurrentTag
        ? 'Current #tag:'
        : 'Current #tag: None selected';
    final buttonLabel = isLoading
        ? 'Loading...'
        : hasCurrentTag
        ? currentTag!.trim()
        : 'Choose a #tag';
    final buttonColor = hasCurrentTag
        ? TagDialogStyles.accent(theme)
        : TagDialogStyles.brownDark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: bodyStyle?.copyWith(
              fontWeight: FontWeight.w700,
              color: TagDialogStyles.body(theme),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            foregroundColor: buttonColor,
            side: BorderSide(color: TagDialogStyles.outlineColor(theme)),
            backgroundColor: hasCurrentTag
                ? TagDialogStyles.accentWash.withValues(alpha: 0.5)
                : TagDialogStyles.surface(theme),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            buttonLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _HighlightedResultText extends StatelessWidget {
  const _HighlightedResultText({
    required this.text,
    required this.baseStyle,
    required this.highlightTerms,
  });

  final String text;
  final TextStyle? baseStyle;
  final List<String> highlightTerms;

  @override
  Widget build(BuildContext context) {
    final spans = buildHighlightedSearchSpans(
      text,
      highlightTerms,
      baseStyle: baseStyle,
    );
    return Text.rich(
      TextSpan(style: baseStyle, children: spans),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
  }
}
