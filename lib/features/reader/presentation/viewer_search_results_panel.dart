import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';
import '../../search/search_highlight_helper.dart';
import '../../search/search_result_quick_apply_button.dart';
import 'tag_dialog_styles.dart';

class ViewerSearchResultsPanel extends StatefulWidget {
  const ViewerSearchResultsPanel({
    super.key,
    required this.results,
    required this.isLoading,
    required this.hasSearched,
    required this.totalResultsCount,
    required this.titleStyle,
    required this.bodyStyle,
    required this.maxHeight,
    this.highlightTerms = const [],
    this.currentTag,
    this.isCurrentTagLoading = false,
    this.selectedIndex,
    this.scrollToIndex,
    this.scrollRequestToken,
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
  final double maxHeight;
  final List<String> highlightTerms;
  final String? currentTag;
  final bool isCurrentTagLoading;
  final int? selectedIndex;
  final int? scrollToIndex;
  final int? scrollRequestToken;
  final void Function(PassageSearchResult result, int index) onSelectResult;
  final Future<void> Function(PassageSearchResult result)? onQuickApplyResult;
  final VoidCallback onLoadMore;

  @override
  State<ViewerSearchResultsPanel> createState() =>
      _ViewerSearchResultsPanelState();
}

class _ViewerSearchResultsPanelState extends State<ViewerSearchResultsPanel> {
  static const double _approximateResultExtent = 88.0;
  static const int _maxResumeScrollRetries = 12;
  final ScrollController _scrollController = ScrollController();
  int? _appliedScrollRequestToken;
  int _resumeScrollRetryCount = 0;

  @override
  void didUpdateWidget(covariant ViewerSearchResultsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isRestoreRequestChanged(oldWidget)) {
      _scheduleScrollToRequestedIndex();
      return;
    }

    if (!_isAppendUpdate(oldWidget.results, widget.results) &&
        widget.results.isNotEmpty &&
        oldWidget.results != widget.results) {
      _scheduleScrollToTop();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _isRestoreRequestChanged(ViewerSearchResultsPanel oldWidget) {
    return widget.scrollRequestToken != null &&
        (widget.scrollRequestToken != oldWidget.scrollRequestToken ||
            widget.scrollToIndex != oldWidget.scrollToIndex);
  }

  bool _isAppendUpdate(
    List<PassageSearchResult> oldResults,
    List<PassageSearchResult> newResults,
  ) {
    if (oldResults.isEmpty || newResults.length <= oldResults.length) {
      return false;
    }
    for (var i = 0; i < oldResults.length; i += 1) {
      final oldResult = oldResults[i];
      final newResult = newResults[i];
      if (oldResult.blockId != newResult.blockId ||
          oldResult.bookNumber != newResult.bookNumber ||
          oldResult.chapter != newResult.chapter ||
          oldResult.verse != newResult.verse) {
        return false;
      }
    }
    return true;
  }

  void _scheduleScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset.abs() < 0.5) return;
      _scrollController.jumpTo(0);
    });
  }

  void _scheduleScrollToRequestedIndex() {
    final token = widget.scrollRequestToken;
    final index = widget.scrollToIndex;
    if (token == null || index == null || widget.results.isEmpty) return;
    if (_appliedScrollRequestToken == token) return;
    _resumeScrollRetryCount = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToRequestedIndex(token, index);
    });
  }

  void _scrollToRequestedIndex(int token, int index) {
    if (!mounted) return;
    if (widget.scrollRequestToken != token || widget.scrollToIndex != index) {
      return;
    }
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      if (_resumeScrollRetryCount >= _maxResumeScrollRetries) {
        return;
      }
      _resumeScrollRetryCount += 1;
      // iOS can finish attaching and laying out the dialog a little later than
      // macOS, so give the list a few frames before falling back to a short delay.
      if (_resumeScrollRetryCount <= 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToRequestedIndex(token, index);
        });
      } else {
        Future<void>.delayed(const Duration(milliseconds: 32), () {
          _scrollToRequestedIndex(token, index);
        });
      }
      return;
    }
    if (widget.results.isEmpty) return;

    final clampedIndex = index.clamp(0, widget.results.length - 1).toInt();
    final viewport = _scrollController.position.viewportDimension;
    final estimatedOffset =
        (clampedIndex * _approximateResultExtent) - (viewport * 0.2);
    final target = estimatedOffset
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();

    if ((target - _scrollController.offset).abs() >= 0.5) {
      _scrollController.jumpTo(target);
    }
    _appliedScrollRequestToken = token;
    _resumeScrollRetryCount = 0;
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.results;
    final hasCurrentTag = widget.currentTag?.trim().isNotEmpty == true;
    if (widget.isLoading) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: widget.currentTag,
              isLoading: widget.isCurrentTagLoading,
              bodyStyle: widget.bodyStyle,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      );
    }

    if (widget.hasSearched && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: widget.currentTag,
              isLoading: widget.isCurrentTagLoading,
              bodyStyle: widget.bodyStyle,
            ),
            const SizedBox(height: 20),
            Text('No matches found.', style: widget.bodyStyle),
          ],
        ),
      );
    }

    if (!widget.hasSearched) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CurrentTagBanner(
              currentTag: widget.currentTag,
              isLoading: widget.isCurrentTagLoading,
              bodyStyle: widget.bodyStyle,
            ),
            const SizedBox(height: 20),
            Text(
              'Search the Bible and choose a verse to jump there.',
              textAlign: TextAlign.center,
              style: widget.bodyStyle,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: widget.maxHeight,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: _CurrentTagBanner(
              currentTag: widget.currentTag,
              isLoading: widget.isCurrentTagLoading,
              bodyStyle: widget.bodyStyle,
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.only(top: 4),
              itemCount: results.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final result = results[index];
                final hasQuickApplyTarget =
                    hasCurrentTag && widget.onQuickApplyResult != null;
                final quickApplyTooltip = widget.isCurrentTagLoading
                    ? 'Loading current #tag...'
                    : hasCurrentTag
                    ? 'Add to ${widget.currentTag}'
                    : 'Choose a #tag';
                final isSelected = widget.selectedIndex == index;
                return ListTile(
                  dense: true,
                  minLeadingWidth: 40,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  isThreeLine: true,
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer
                      .withValues(alpha: 0.45),
                  leading: widget.onQuickApplyResult == null
                      ? null
                      : SearchResultQuickApplyButton(
                          tooltip: quickApplyTooltip,
                          onPressed: hasQuickApplyTarget &&
                                  !widget.isCurrentTagLoading
                              ? () {
                                  unawaited(widget.onQuickApplyResult!(result));
                                }
                              : null,
                        ),
                  title: Text(
                    '${result.bookName} ${result.chapter}:${result.verse}',
                    style: widget.titleStyle,
                  ),
                  subtitle: _HighlightedResultText(
                    text: result.text,
                    baseStyle: widget.bodyStyle,
                    highlightTerms: widget.highlightTerms,
                  ),
                  onTap: () => widget.onSelectResult(result, index),
                );
              },
            ),
          ),
          if (results.length < widget.totalResultsCount)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: FilledButton.tonal(
                onPressed: widget.onLoadMore,
                child: Text(
                  'Load More (${widget.totalResultsCount - results.length} remaining)',
                ),
              ),
            ),
        ],
      ),
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
