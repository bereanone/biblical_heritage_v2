import 'package:flutter/material.dart';

import 'memory_schedule/memory_schedule.dart';
import 'memory_schedule/memory_schedule_editor.dart';
import 'memory_schedule/memory_schedule_reminder.dart';
import 'tag_dialog_models.dart';
import 'tag_dialog_styles.dart';
import 'tag_playback/tag_playback_popup.dart';
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
  final Future<void> Function(HashTagSummary summary) onSearchSelected;
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
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.none,
              smartDashesType: SmartDashesType.disabled,
              smartQuotesType: SmartQuotesType.disabled,
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
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(categoryFilter == null
              ? 'Folder filter: OFF'
              : 'Folder filter: ON'),
          subtitle: Text(categoryFilter == null
              ? 'Showing all folders'
              : 'Showing only the selected folder'),
          value: categoryFilter != null,
          onChanged: (_) => onToggleSelectedCategoryBrowseFilter(),
        ),
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
                      'Folder',
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
                        value:
                            effectiveCategoryValue == null ||
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
                message: 'Show all lists and folders',
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
            PopupMenuButton<HashTagSummary>(
              tooltip: 'Search within folder',
              initialValue: null,
              onSelected: (summary) async {
                await onSearchSelected(summary);
              },
              itemBuilder: (_) => searchSummaries
                  .map(
                    (summary) => PopupMenuItem<HashTagSummary>(
                      value: summary,
                      child: Text(
                        summary.displayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
              'No lists in this folder yet.',
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
                          '${summary.displayLabel}  ·  ${summary.count}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TagDialogStyles.titleTextStyle(
                            theme,
                            fontScale,
                            color: TagDialogStyles.title(theme),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TagReminderIndicator(
                              target: MemoryAudioTarget(
                                label: summary.displayLabel,
                                tag: summary.tag,
                                category: summary.category,
                                isDollar: tagSymbol == r'$',
                              ),
                              color: TagDialogStyles.title(theme),
                            ),
                            IconButton(
                              onPressed: summary.count == 0
                                  ? null
                                  : () => showTagPlaybackPopup(
                                      context,
                                      tag: summary.tag,
                                      category: summary.category,
                                      isDollar: tagSymbol == r'$',
                                      fontScale: fontScale,
                                    ),
                              tooltip: 'Listen to this tag',
                              icon: Icon(
                                Icons.headphones_rounded,
                                color: TagDialogStyles.title(theme),
                              ),
                            ),
                            IconButton(
                              onPressed: () => onOpenSummaryDetails(summary),
                              tooltip: 'Open verses',
                              icon: Icon(
                                Icons.menu_book_outlined,
                                color: TagDialogStyles.title(theme),
                              ),
                            ),
                          ],
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

class _TagReminderIndicator extends StatefulWidget {
  const _TagReminderIndicator({required this.target, required this.color});
  final MemoryAudioTarget target;
  final Color color;
  @override
  State<_TagReminderIndicator> createState() => _TagReminderIndicatorState();
}

class _TagReminderIndicatorState extends State<_TagReminderIndicator> {
  bool _enabled = false;
  int _request = 0;
  @override
  void initState() {
    super.initState();
    MemoryAudioScheduleStore.instance.changes.addListener(_refresh);
    _refresh();
  }

  Future<void> _refresh() async {
    final request = ++_request;
    final key = widget.target.key;
    try {
      final schedules = await MemoryAudioScheduleStore.instance.load();
      if (!mounted || request != _request || key != widget.target.key) return;
      final enabled = schedules.any((s) => s.target.key == key && s.enabled);
      if (_enabled != enabled) setState(() => _enabled = enabled);
    } catch (_) {
      // A failed read must not imply a reminder is enabled.
      if (mounted && request == _request) setState(() => _enabled = false);
    }
  }

  @override
  void didUpdateWidget(covariant _TagReminderIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.target.key != widget.target.key) {
      _enabled = false;
      _refresh();
    }
  }

  @override
  void dispose() {
    MemoryAudioScheduleStore.instance.changes.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_enabled
      ? const SizedBox.shrink()
      : IconButton(
          tooltip: 'Reminder enabled · edit schedule',
          icon: Icon(Icons.schedule, color: widget.color),
          onPressed: () => showMemoryScheduleEditor(
            context,
            widget.target,
            preview: () => showMemoryAudioReminder(context, widget.target),
          ),
        );
}
