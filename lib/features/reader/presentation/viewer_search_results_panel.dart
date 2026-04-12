import 'package:flutter/material.dart';

import '../../../core/database/study_bible_database.dart';

class ViewerSearchResultsPanel extends StatelessWidget {
  const ViewerSearchResultsPanel({
    super.key,
    required this.results,
    required this.isLoading,
    required this.hasSearched,
    required this.totalResultsCount,
    required this.titleStyle,
    required this.bodyStyle,
    required this.onSelectResult,
    required this.onLoadMore,
  });

  final List<PassageSearchResult> results;
  final bool isLoading;
  final bool hasSearched;
  final int totalResultsCount;
  final TextStyle? titleStyle;
  final TextStyle? bodyStyle;
  final ValueChanged<PassageSearchResult> onSelectResult;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      );
    }

    if (hasSearched && results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No matches found.', style: bodyStyle),
      );
    }

    if (!hasSearched) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Search the Bible and choose a verse to jump there.',
          textAlign: TextAlign.center,
          style: bodyStyle,
        ),
      );
    }

    return Column(
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final result = results[index];
            return ListTile(
              title: Text(
                '${result.bookName} ${result.chapter}:${result.verse}',
                style: titleStyle,
              ),
              subtitle: Text(
                result.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: bodyStyle,
              ),
              onTap: () => onSelectResult(result),
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
