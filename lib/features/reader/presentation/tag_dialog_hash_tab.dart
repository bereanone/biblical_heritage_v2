import 'package:flutter/material.dart';

import 'tag_dialog_models.dart';
import 'tag_dialog_styles.dart';
import 'tag_quick_apply_helper.dart';

class TagDialogHashTab extends StatelessWidget {
  const TagDialogHashTab({
    super.key,
    required this.tagSymbol,
    required this.fontScale,
    required this.loading,
    required this.groupedSummaries,
    required this.searchSummaries,
    required this.tagController,
    required this.categoryController,
    required this.searchController,
    required this.selectedCategory,
    required this.categoryOptions,
    required this.categoryFilter,
    required this.sortMode,
    required this.working,
    required this.onTagSubmitted,
    required this.onApplySelection,
    required this.onCategoryChanged,
    required this.onToggleSelectedCategoryBrowseFilter,
    required this.onResetBrowseState,
    required this.onSearchSelected,
    required this.onSortModeChanged,
    required this.onOpenSummaryDetails,
  });

  final String tagSymbol;
  final double fontScale;
  final bool loading;
  final List<MapEntry<String?, List<HashTagSummary>>> groupedSummaries;
  final List<HashTagSummary> searchSummaries;
  final TextEditingController tagController;
  final TextEditingController categoryController;
  final TextEditingController searchController;
  final String? selectedCategory;
  final List<String> categoryOptions;
  final String? categoryFilter;
  final TagSortMode sortMode;
  final bool working;
  final Future<void> Function(String value) onTagSubmitted;
  final VoidCallback onApplySelection;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onToggleSelectedCategoryBrowseFilter;
  final VoidCallback onResetBrowseState;
  final Future<void> Function(String value) onSearchSelected;
  final ValueChanged<TagSortMode> onSortModeChanged;
  final ValueChanged<HashTagSummary> onOpenSummaryDetails;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final selectedCategoryText = selectedCategory?.trim() ?? '';
    final hasSelectedCategory = selectedCategoryText.isNotEmpty;
    final categoryItems = <String>[
      ...categoryOptions,
      if (hasSelectedCategory &&
          !categoryOptions.any(
            (category) =>
                category.toLowerCase() == selectedCategoryText.toLowerCase(),
          ))
        selectedCategoryText,
    ];
    final effectiveCategoryValue = categoryItems.isEmpty
        ? null
        : categoryItems.firstWhere(
            (category) =>
                category.toLowerCase() == selectedCategoryText.toLowerCase(),
            orElse: () => '',
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      children: [
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 460;
            final tagField = TextField(
              controller: tagController,
              style: TagDialogStyles.titleTextStyle(
                theme,
                fontScale,
                color: TagDialogStyles.title(theme),
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                labelText: '$tagSymbol tag',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: TagDialogStyles.surface(theme),
                labelStyle: TagDialogStyles.labelTextStyle(
                  theme,
                  fontScale,
                  color: TagDialogStyles.body(theme),
                ),
                floatingLabelStyle: TagDialogStyles.labelTextStyle(
                  theme,
                  fontScale,
                  color: TagDialogStyles.title(theme),
                ),
              ),
              onSubmitted: (_) => onTagSubmitted(tagController.text),
            );
            final tagButton = SizedBox(
              width: isNarrow ? 92 : 112,
              height: isNarrow ? 60 : 62,
              child: FilledButton(
                onPressed: working ? null : onApplySelection,
                style: FilledButton.styleFrom(
                  backgroundColor: TagDialogStyles.accent(theme),
                  foregroundColor: theme.brightness == Brightness.dark
                      ? theme.colorScheme.onPrimary
                      : Colors.white,
                  textStyle: TagDialogStyles.buttonTextStyle(
                    theme,
                    fontScale,
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.onPrimary
                        : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: TagDialogStyles.fittedButtonLabel(
                  'Tag\nVerse',
                  maxLines: 2,
                  style: TagDialogStyles.buttonTextStyle(
                    theme,
                    fontScale,
                    color: theme.brightness == Brightness.dark
                        ? theme.colorScheme.onPrimary
                        : Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tagField,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: tagButton),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tagField),
                const SizedBox(width: 8),
                tagButton,
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 5),
                    child: Text(
                      'Category',
                      style: TagDialogStyles.labelTextStyle(
                        theme,
                        fontScale,
                        color: TagDialogStyles.body(theme),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: TagDialogStyles.surfaceHigh(theme),
                      border: Border.all(
                        color: TagDialogStyles.outlineColor(theme),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: effectiveCategoryValue == null ||
                                effectiveCategoryValue.isEmpty
                            ? null
                            : effectiveCategoryValue,
                        isDense: true,
                        isExpanded: true,
                        style: TagDialogStyles.titleTextStyle(
                          theme,
                          fontScale,
                          color: TagDialogStyles.title(theme),
                          fontWeight: FontWeight.w700,
                        ),
                        hint: const Text('None'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('None'),
                          ),
                          ...categoryItems.map(
                            (category) => DropdownMenuItem<String?>(
                              value: category,
                              child: Text(category, maxLines: 1),
                            ),
                          ),
                          const DropdownMenuItem<String?>(
                            value: _addNewCategoryValue,
                            child: Text('Add new...'),
                          ),
                        ],
                        onChanged: onCategoryChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 40,
              height: 40,
              child: Tooltip(
                message: categoryFilter == null
                    ? 'Filter by selected category'
                    : 'Show all categories',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onToggleSelectedCategoryBrowseFilter,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: categoryFilter == null
                            ? TagDialogStyles.surface(theme)
                            : TagDialogStyles.surfaceHigh(theme),
                        border: Border.all(
                          color: TagDialogStyles.outlineColor(theme),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                        child: Icon(
                          categoryFilter == null
                              ? Icons.filter_alt_outlined
                              : Icons.filter_alt,
                          size: 18,
                          color: TagDialogStyles.title(theme),
                        ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 40,
              height: 40,
              child: Tooltip(
                message: 'Reset to all tags and categories',
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onResetBrowseState,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: TagDialogStyles.surface(theme),
                        border: Border.all(
                          color: TagDialogStyles.outlineColor(theme),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.refresh,
                        size: 18,
                        color: TagDialogStyles.title(theme),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            PopupMenuButton<String>(
              tooltip: 'Search within category',
              initialValue: searchController.text.isEmpty
                  ? null
                  : searchController.text,
              onSelected: (value) async {
                await onSearchSelected(value);
              },
              itemBuilder: (_) => searchSummaries
                  .map(
                    (summary) => PopupMenuItem<String>(
                      value: summary.tag,
                      child: Text(
                        summary.tag,
                        maxLines: 1,
                        style: TagDialogStyles.buttonTextStyle(
                          theme,
                          fontScale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
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
                  color: TagDialogStyles.title(theme),
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
                  child: TagDialogStyles.fittedButtonLabel(
                    'A→Z',
                    style: TagDialogStyles.buttonTextStyle(
                      theme,
                      fontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: TagSortMode.verseCount,
                  child: TagDialogStyles.fittedButtonLabel(
                    'Count',
                    style: TagDialogStyles.buttonTextStyle(
                      theme,
                      fontScale,
                      fontWeight: FontWeight.w700,
                    ),
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
                  Icons.sort,
                  size: 18,
                  color: TagDialogStyles.body(theme),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (groupedSummaries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No tags in this category yet.',
              textAlign: TextAlign.center,
              style: TagDialogStyles.bodyTextStyle(
                theme,
                fontScale,
                color: TagDialogStyles.body(theme),
              ),
            ),
          )
        else
          ...groupedSummaries.map(
            (group) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _displayCategoryLabel(group.key),
                      style: TagDialogStyles.titleTextStyle(
                        theme,
                        fontScale,
                        color: TagDialogStyles.title(theme),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                ...group.value.map(
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
                          style: TagDialogStyles.titleTextStyle(
                            theme,
                            fontScale,
                            color: TagDialogStyles.title(theme),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: IconButton(
                          onPressed: () => onOpenSummaryDetails(summary),
                          tooltip: 'Open verses',
                          icon: Icon(
                            Icons.menu_book_outlined,
                            color: TagDialogStyles.title(theme),
                          ),
                        ),
                        onTap: () => onOpenSummaryDetails(summary),
                      ),
                      if (summary != group.value.last) const Divider(height: 1),
                    ],
                  ),
                ),
                if (group != groupedSummaries.last) const SizedBox(height: 8),
              ],
            ),
          ),
      ],
    );
  }

  String _displayCategoryLabel(String? category) {
    final normalized = category?.trim() ?? '';
    return normalized.isEmpty ? 'None' : normalized;
  }

  static const String _addNewCategoryValue = '__add_new_category__';
}
