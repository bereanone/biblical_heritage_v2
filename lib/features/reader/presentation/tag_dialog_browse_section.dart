import 'package:flutter/material.dart';

import 'tag_dialog_styles.dart';
import 'tag_dialog_models.dart';
import 'tag_quick_apply_helper.dart';

class TagDialogBrowseSection extends StatelessWidget {
  const TagDialogBrowseSection({
    super.key,
    required this.summaries,
    required this.categoryController,
    required this.searchController,
    required this.sortMode,
    required this.onSortModeChanged,
    required this.onOpenSummaryDetails,
    required this.onSearchChanged,
  });

  final List<HashTagSummary> summaries;
  final TextEditingController categoryController;
  final TextEditingController searchController;
  final TagSortMode sortMode;
  final ValueChanged<TagSortMode> onSortModeChanged;
  final ValueChanged<HashTagSummary> onOpenSummaryDetails;
  final VoidCallback onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: TextField(
                controller: categoryController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: 'Category',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                  fillColor: TagDialogStyles.surfaceHigh(theme),
                ),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: TagDialogStyles.title(theme),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String?>(
              tooltip: 'Category filter',
              itemBuilder: (_) => const [
                PopupMenuItem<String?>(
                  value: null,
                  child: Text('All categories'),
                ),
              ],
              onSelected: (_) {},
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TagDialogStyles.surface(theme),
                  border: Border.all(
                    color: TagDialogStyles.outlineColor(theme),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.tune,
                  size: 18,
                  color: TagDialogStyles.body(theme),
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Search tags',
              initialValue: searchController.text.isEmpty
                  ? null
                  : searchController.text,
              onSelected: (value) {
                searchController.text = value;
                onSearchChanged();
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(value: '', child: Text('All tags')),
                ...summaries.map(
                  (summary) => PopupMenuItem<String>(
                    value: summary.tag,
                    child: Text(summary.tag, maxLines: 1),
                  ),
                ),
              ],
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TagDialogStyles.surface(theme),
                  border: Border.all(
                    color: TagDialogStyles.outlineColor(theme),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.search,
                  size: 18,
                  color: TagDialogStyles.body(theme),
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<TagSortMode>(
              tooltip: 'Sort tags',
              initialValue: sortMode,
              onSelected: onSortModeChanged,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: TagSortMode.categoryAlpha,
                  child: TagDialogStyles.fittedButtonLabel('A→Z'),
                ),
                PopupMenuItem(
                  value: TagSortMode.verseCount,
                  child: TagDialogStyles.fittedButtonLabel('Count'),
                ),
              ],
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TagDialogStyles.surface(theme),
                  border: Border.all(
                    color: TagDialogStyles.outlineColor(theme),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.sort,
                  size: 18,
                  color: TagDialogStyles.body(theme),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No tags in this category yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          )
        else
          ...summaries.map(
            (summary) => Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 0,
                  ),
                  tileColor: TagDialogStyles.card(theme),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Text(
                    '${summary.tag}  ·  ${summary.count}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: TagDialogStyles.title(theme),
                    ),
                  ),
                  trailing: IconButton(
                    onPressed: () => onOpenSummaryDetails(summary),
                    tooltip: 'Browse',
                    icon: Icon(
                      Icons.menu_book_outlined,
                      color: TagDialogStyles.body(theme),
                    ),
                  ),
                  onTap: () => onOpenSummaryDetails(summary),
                ),
                if (summary != summaries.last) const Divider(height: 1),
              ],
            ),
          ),
      ],
    );
  }
}
