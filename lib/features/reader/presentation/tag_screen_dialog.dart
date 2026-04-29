import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tag_dialog_header.dart';
import 'tag_dialog_hash_tab.dart';
import 'tag_dialog_models.dart';
import 'tag_dialog_styles.dart';
import 'tag_detail_screen_launcher.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';

class HashTagDialog extends StatefulWidget {
  const HashTagDialog({
    super.key,
    required this.repository,
    required this.passage,
    required this.selection,
    required this.selectionTargets,
    required this.initialTabIndex,
    required this.tagSymbol,
    this.onTagTabChanged,
    this.initialTag,
    this.onSelectBlockId,
    this.legacyStyle = false,
  });

  final HashTagRepository repository;
  final PassageData passage;
  final ViewerRangeSelection selection;
  final List<HashTagTarget> selectionTargets;
  final int initialTabIndex;
  final String tagSymbol;
  final ValueChanged<int>? onTagTabChanged;
  final String? initialTag;
  final Future<void> Function(int blockId)? onSelectBlockId;
  final bool legacyStyle;

  @override
  State<HashTagDialog> createState() => _HashTagDialogState();
}

class _HashTagDialogState extends State<HashTagDialog>
    with SingleTickerProviderStateMixin {
  static const String _addNewCategoryValue = '__add_new_category__';

  HashTagRepository get _repository => widget.repository;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController(
    text: '',
  );
  final TextEditingController _searchController = TextEditingController();

  List<HashTagSummary> _summaries = const <HashTagSummary>[];
  List<String> _categoryOptions = const <String>[];
  Map<String, String?> _summaryCategories = const <String, String?>{};
  String? _defaultTag;
  String? _selectedCategory;
  int _categoryFieldRevision = 0;
  String? _categoryFilter;
  int _browseStateRevision = 0;
  TagSortMode _sortMode = TagSortMode.verseCount;
  bool _loading = true;
  bool _working = false;
  late final TabController _tabController;

  String get _tagSymbol =>
      widget.tagSymbol.trim().isEmpty ? '#' : widget.tagSymbol.trim();

  String get _tagLabel => _tagSymbol == r'$' ? r'$' : _tagSymbol;

  String get _tagName => '${_tagLabel}tag';

  @override
  void initState() {
    super.initState();
    if (widget.legacyStyle) {
      _sortMode = TagSortMode.categoryAlpha;
    }
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1).toInt(),
    )..addListener(_handleTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    _tagController.dispose();
    _categoryController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    widget.onTagTabChanged?.call(_tabController.index);
  }

  Future<void> _load() async {
    final summaries = await _repository.loadSummaries();
    final categoryOptions = await _repository.loadCategoryOptions();
    final summaryCategories = await _loadSummaryCategories(summaries);
    final defaultTag = await _repository.loadDefaultTag();
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _categoryOptions = categoryOptions;
      _summaryCategories = summaryCategories;
      _defaultTag = defaultTag;
      _tagController.clear();
      _selectedCategory = null;
      _categoryController.clear();
      _categoryFilter = null;
      _searchController.clear();
      _categoryFieldRevision += 1;
      _loading = false;
    });
  }

  String get _currentTag => _repository.normalizeTagName(_tagController.text);

  String get _selectionLabel {
    if (widget.selectionTargets.isEmpty) return 'No verse selected';
    if (widget.selectionTargets.length == 1) {
      final target = widget.selectionTargets.first;
      return '${widget.passage.bookName} ${target.chapter}:${target.verse}';
    }
    final first = widget.selectionTargets.first;
    final last = widget.selectionTargets.last;
    return '${widget.passage.bookName} ${first.chapter}:${first.verse} - ${widget.passage.bookName} ${last.chapter}:${last.verse}';
  }

  static const String _uncategorizedCategoryFilterValue =
      '__uncategorized_category_filter__';

  List<MapEntry<String?, List<HashTagSummary>>> _groupedVisibleSummaries() {
    final searchTag = _repository.normalizeTagName(_searchController.text);
    final filtered = _summaries
        .where((summary) {
          if (searchTag.isNotEmpty &&
              _repository.normalizeTagName(summary.tag) != searchTag) {
            return false;
          }

          final category = _summaryCategories[summary.tag]?.trim();
          final normalizedCategory = category == null || category.isEmpty
              ? null
              : category;

          final filter = _categoryFilter;
          if (filter == null) return true;
          if (filter == _uncategorizedCategoryFilterValue) {
            return normalizedCategory == null;
          }
          return normalizedCategory != null &&
              normalizedCategory.toLowerCase() == filter.toLowerCase();
        })
        .toList(growable: false);

    if (filtered.isEmpty) return const [];

    final groups = <String?, List<HashTagSummary>>{};
    for (final summary in filtered) {
      final category = _summaryCategories[summary.tag]?.trim();
      final normalizedCategory = category == null || category.isEmpty
          ? null
          : category;
      groups.putIfAbsent(normalizedCategory, () => []).add(summary);
    }

    final categoryOrder = <String, int>{
      for (var i = 0; i < _categoryOptions.length; i++)
        _categoryOptions[i].toLowerCase(): i,
    };

    final sections = groups.entries.toList()
      ..sort((a, b) {
        final aIsNull = a.key == null;
        final bIsNull = b.key == null;
        if (aIsNull && bIsNull) return 0;
        if (aIsNull) return 1;
        if (bIsNull) return -1;
        final aIndex = categoryOrder[a.key!.toLowerCase()];
        final bIndex = categoryOrder[b.key!.toLowerCase()];
        if (aIndex != null || bIndex != null) {
          if (aIndex == null) return 1;
          if (bIndex == null) return -1;
          return aIndex.compareTo(bIndex);
        }
        return a.key!.toLowerCase().compareTo(b.key!.toLowerCase());
      });

    for (final section in sections) {
      section.value.sort((a, b) {
        switch (_sortMode) {
          case TagSortMode.categoryAlpha:
            return a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
          case TagSortMode.verseCount:
            final countCompare = b.count.compareTo(a.count);
            if (countCompare != 0) return countCompare;
            return a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
        }
      });
    }

    return sections;
  }

  Future<void> _saveCurrentCategory() async {
    final tag = _currentTag;
    if (tag.isEmpty) {
      _showSnack('No tag selected. Enter or select a tag first.');
      return;
    }
    await _repository.saveTagCategory(tag, _selectedCategory ?? '');
    if (!mounted) return;
    _scheduleCategoryRefresh(selectedCategory: _selectedCategory);
    _showSnack('Category saved for $tag');
  }

  Future<String?> _resolveTagForSelection() async {
    final tag = _currentTag;
    if (tag.isEmpty) {
      await _showNoTagSelectedDialog();
      return null;
    }
    return tag;
  }

  Future<void> _applySelectionToTargets(String tag) async {
    setState(() => _working = true);
    final result = await _repository.quickApplyTargets(
      targets: widget.selectionTargets,
      tag: tag,
    );
    if (!mounted) return;
    setState(() => _working = false);
    if (result.tag == null) {
      await _showNoTagSelectedDialog();
      return;
    }
    await _repository.saveTagCategory(result.tag!, _selectedCategory ?? '');
    await _reloadSelectedTag(result.tag!);
    _showSnack(
      'Tagged ${result.inserted} verse(s) with ${result.tag}'
      '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
    );
  }

  Future<void> _applySelection() async {
    final tag = await _resolveTagForSelection();
    if (tag == null) return;
    await _applySelectionToTargets(tag);
  }

  Future<void> _refreshCategoryOptions({
    String? selectedCategory,
    int? expectedBrowseStateRevision,
  }) async {
    final categoryOptions = await _repository.loadCategoryOptions();
    if (!mounted) return;
    if (expectedBrowseStateRevision != null &&
        expectedBrowseStateRevision != _browseStateRevision) {
      return;
    }
    final resolvedSelected = _resolveCategorySelection(
      categoryOptions,
      selectedCategory ?? _selectedCategory,
    );
    final resolvedFilter = _resolveCategoryFilterSelection(
      categoryOptions,
      preferredCategory: resolvedSelected,
    );
    setState(() {
      _categoryOptions = categoryOptions;
      _selectedCategory = resolvedSelected;
      _categoryController.text = resolvedSelected ?? '';
      _categoryFilter = resolvedFilter;
      _categoryFieldRevision += 1;
    });
  }

  Future<Map<String, String?>> _loadSummaryCategories(
    List<HashTagSummary> summaries,
  ) async {
    final pairs = await Future.wait(
      summaries.map(
        (summary) async => MapEntry(
          summary.tag,
          await _repository.loadTagCategory(summary.tag),
        ),
      ),
    );
    return {for (final pair in pairs) pair.key: pair.value};
  }

  Future<void> _refreshBrowseCategoryMap() async {
    final summaryCategories = await _loadSummaryCategories(_summaries);
    if (!mounted) return;
    setState(() {
      _summaryCategories = summaryCategories;
    });
  }

  void _scheduleCategoryRefresh({String? selectedCategory}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _refreshCategoryOptions(selectedCategory: selectedCategory);
      if (!mounted) return;
      await _refreshBrowseCategoryMap();
    });
  }

  String? _resolveCategorySelection(
    List<String> categories,
    String? candidate,
  ) {
    final normalizedCandidate = candidate?.trim() ?? '';
    if (normalizedCandidate.isEmpty) return null;
    for (final category in categories) {
      if (category.toLowerCase() == normalizedCandidate.toLowerCase()) {
        return category;
      }
    }
    return normalizedCandidate;
  }

  String? _resolveCategoryFilterSelection(
    List<String> categories, {
    String? preferredCategory,
  }) {
    final currentFilter = _categoryFilter;
    if (currentFilter == null) return null;
    if (currentFilter == _uncategorizedCategoryFilterValue) {
      return _uncategorizedCategoryFilterValue;
    }

    final matchingCurrent = _findMatchingCategory(categories, currentFilter);
    if (matchingCurrent != null) return matchingCurrent;

    final matchingPreferred = preferredCategory == null
        ? null
        : _findMatchingCategory(categories, preferredCategory);
    return matchingPreferred;
  }

  String? _findMatchingCategory(List<String> categories, String candidate) {
    final normalizedCandidate = candidate.trim();
    if (normalizedCandidate.isEmpty) return null;
    for (final category in categories) {
      if (category.toLowerCase() == normalizedCandidate.toLowerCase()) {
        return category;
      }
    }
    return null;
  }

  String? _categoryLabel(String? category) {
    final normalized = category?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  String _browseCategoryFilterForSelection() {
    final selectedCategory = _selectedCategory?.trim() ?? '';
    return selectedCategory.isEmpty
        ? _uncategorizedCategoryFilterValue
        : selectedCategory;
  }

  List<HashTagSummary> _summariesInSelectedCategory() {
    final selectedCategory = _selectedCategory?.trim() ?? '';
    return _summaries
        .where((summary) {
          final category = _summaryCategories[summary.tag]?.trim();
          final normalizedCategory = category == null || category.isEmpty
              ? ''
              : category;
          if (selectedCategory.isEmpty) return normalizedCategory.isEmpty;
          return normalizedCategory.toLowerCase() ==
              selectedCategory.toLowerCase();
        })
        .toList(growable: false);
  }

  void _toggleSelectedCategoryBrowseFilter() {
    setState(() {
      if (_categoryFilter == null) {
        _categoryFilter = _browseCategoryFilterForSelection();
      } else {
        _categoryFilter = null;
      }
    });
  }

  Future<void> _resetBrowseState() async {
    final summaries = await _repository.loadSummaries();
    final categoryOptions = await _repository.loadCategoryOptions();
    final summaryCategories = await _loadSummaryCategories(summaries);
    final defaultTag = await _repository.loadDefaultTag();
    if (!mounted) return;
    setState(() {
      _summaries = summaries;
      _categoryOptions = categoryOptions;
      _summaryCategories = summaryCategories;
      _defaultTag = defaultTag;
      _clearSelectedTagOnly();
      _categoryFilter = null;
      _browseStateRevision += 1;
    });
  }

  void _syncCategoryBrowseFilterToSelection() {
    if (_categoryFilter == null) return;
    _categoryFilter = _browseCategoryFilterForSelection();
  }

  Future<void> _selectTagFromSearch(String value) async {
    final tag = value.trim();
    if (tag.isEmpty) return;

    final requestRevision = ++_browseStateRevision;
    await _reloadSelectedTag(tag, expectedBrowseStateRevision: requestRevision);
    if (!mounted) return;
    if (requestRevision != _browseStateRevision) return;

    setState(() {
      _searchController.text = _repository.normalizeTagName(tag);
    });
  }

  Future<void> _reloadSelectedTag(
    String tag, {
    int? expectedBrowseStateRevision,
  }) async {
    final normalizedTag = _repository.normalizeTagName(tag);
    if (normalizedTag.isEmpty) {
      if (!mounted) return;
      setState(_clearSelectedTagOnly);
      return;
    }

    final summaries = await _repository.loadSummaries();
    final summaryCategories = await _loadSummaryCategories(summaries);
    final category = await _repository.loadTagCategory(normalizedTag);
    if (!mounted) return;
    if (expectedBrowseStateRevision != null &&
        expectedBrowseStateRevision != _browseStateRevision) {
      return;
    }
    final tagStillExists = summaries.any((summary) => summary.tag == normalizedTag);
    setState(() {
      _summaries = summaries;
      _summaryCategories = summaryCategories;
      if (tagStillExists) {
        _tagController.text = normalizedTag;
        _selectedCategory = category;
        _categoryController.text = category ?? '';
      } else {
        _clearSelectedTagOnly();
      }
    });
    await _refreshCategoryOptions(
      selectedCategory: tagStillExists ? category : null,
      expectedBrowseStateRevision: expectedBrowseStateRevision,
    );
  }

  Future<void> _useDefaultTag() async {
    final defaultTag = _defaultTag;
    if (defaultTag == null) return;
    await _reloadSelectedTag(defaultTag);
  }

  Future<void> _saveDefaultTag() async {
    final tag = _currentTag;
    if (tag.isEmpty) return;
    await _saveCurrentCategory();
    await _repository.saveDefaultTag(tag);
    if (!mounted) return;
    setState(() {
      _defaultTag = tag;
    });
    await _reloadSelectedTag(tag);
    _showSnack('Default set to $tag');
  }

  Future<void> _renameCurrentTag() async {
    final current = _currentTag;
    if (current.isEmpty) return;
    final controller = TextEditingController(text: current);
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename current tag'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '$_tagLabel tag',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: TagDialogStyles.fittedButtonLabel('Rename'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    final normalized = _repository.normalizeTagName(renamed ?? '');
    if (normalized.isEmpty || normalized == current) return;
    final count = await _repository.renameTag(
      oldTag: current,
      newTag: normalized,
    );
    if (!mounted) return;
    await _reloadSelectedTag(normalized);
    _showSnack(
      'Renamed $current to $normalized ($count row${count == 1 ? '' : 's'}).',
    );
  }

  Future<void> _showInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Instructions'),
          content: Text(
            '$_tagLabel tags collect verse references into reusable lists. '
            'Use Tag Verse to add the current verse or range. '
            'Tap a tag line to open the verse list on the next screen. '
            'Use Save to set the rapid-tag default. '
            'Use the Rapid Tag Session controls when you want to tag many verses without extra prompts. '
            'A verse can appear in multiple different $_tagName lists; duplicates are only blocked inside the same tag.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFindText() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Find Text'),
          content: const Text(
            'This keeps the old popup layout first. We can wire the full find-text flow next.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel('Done'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showClipboardImport() async {
    final clipboard = await Clipboard.getData('text/plain');
    final clipboardText = clipboard?.text?.trim() ?? '';
    if (clipboardText.isEmpty) {
      _showSnack('Clipboard is empty.');
      return;
    }
    if (!mounted) return;
    await _showClipboardImportDialog(clipboardText);
  }

  Future<void> _showClipboardImportDialog(String clipboardText) async {
    final controller = TextEditingController(text: clipboardText);
    final imported = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Import $_tagLabel list from Clipboard'),
          content: SizedBox(
            width: 560,
            child: TextField(
              controller: controller,
              minLines: 10,
              maxLines: 18,
              decoration: InputDecoration(
                hintText:
                    'Paste the $_tagLabel list text here. Verse + text blocks are preferred.',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (imported == null || !mounted) return;
    final result = await _repository.importSharedListFromText(imported);
    if (result == null) {
      _showSnack(
        'No usable $_tagLabel list found. Verse + text blocks import best, and note text is preserved.',
      );
      return;
    }
    await _reloadSelectedTag(result.tag);
    await _showImportResultsDialog(result);
  }

  Future<void> _showImportResultsDialog(HashTagImportResult result) async {
    final isDollar = _repository is DollarTagRepository;
    final parsedLabel = isDollar ? 'Parsed slides' : 'Parsed refs';
    final itemLabel = isDollar ? 'slide' : 'verse';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (resultCtx) {
        final media = MediaQuery.of(resultCtx);
        return MediaQuery(
          data: media.copyWith(
            textScaler: MediaQuery.textScalerOf(resultCtx),
          ),
          child: AlertDialog(
            title: Text(
              'Import Results',
              style: Theme.of(resultCtx).textTheme.titleLarge?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.0,
                  ),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (media.size.width * 0.9).clamp(420.0, 820.0),
                maxHeight: (media.size.height * 0.72).clamp(320.0, 700.0),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Tag: ${result.tag}'),
                    Text('$parsedLabel: ${result.parsedCount}'),
                    Text('Inserted: ${result.insertedCount}'),
                    Text('Reordered existing: ${result.updatedExistingCount}'),
                    Text('Skipped existing: ${result.skippedExistingCount}'),
                    Text('Failed lines: ${result.failedCount}'),
                    if (result.failures.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Failures',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      ...result.failures.map(
                        (failure) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Line ${failure.lineNumber}: ${failure.reason}${failure.line.isNotEmpty ? ' — ${failure.line}' : ''}',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(resultCtx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    _showSnack('Imported ${result.insertedCount} $itemLabel${result.insertedCount == 1 ? '' : 's'} into ${result.tag}.');
  }

  Future<void> _openSummaryDetails(HashTagSummary summary) async {
    final previousDefault = _defaultTag;
    final changed = await showHashTagDetailPopup(
      context,
      repository: _repository,
      tag: summary.tag,
      onSelectBlockId: widget.onSelectBlockId,
      onSelectTag: (tag) async {
        await _reloadSelectedTag(tag);
      },
    );
    if (!mounted) return;
    final refreshedDefault = await _repository.loadDefaultTag();
    if (refreshedDefault != previousDefault && refreshedDefault != null) {
      setState(() => _defaultTag = refreshedDefault);
      await _reloadSelectedTag(refreshedDefault);
      return;
    }
    if (changed == true) {
      await _reloadSelectedTag(summary.tag);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showNoTagSelectedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('No Tag Selected'),
          content: Text('Enter or select a $_tagName before tagging a verse.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _clearSelectedTagOnly() {
    _searchController.clear();
    _tagController.clear();
    _selectedCategory = null;
    _categoryController.clear();
    _categoryFieldRevision += 1;
  }

  Future<void> _handleCategoryChanged(String? value) async {
    if (value == _addNewCategoryValue) {
      final previousSelection = _selectedCategory;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final created = await _showNewCategoryDialog();
      if (!mounted) return;
      if (created == null) {
        setState(() {
          _selectedCategory = previousSelection;
          _categoryController.text = previousSelection ?? '';
          _categoryFieldRevision += 1;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedCategory = _categoryLabel(value);
      _categoryController.text = _selectedCategory ?? '';
      _syncCategoryBrowseFilterToSelection();
      _categoryFieldRevision += 1;
    });
  }

  Future<String?> _showNewCategoryDialog() async {
    final currentTag = _currentTag;
    final controller = TextEditingController();
    final categoryName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('New Category'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Category name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(controller.text.trim());
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    final normalized = categoryName?.trim() ?? '';
    if (normalized.isEmpty) return null;

    final currentOptions = _categoryOptions.isEmpty
        ? await _repository.loadCategoryOptions()
        : _categoryOptions;
    final existing = _findMatchingCategory(currentOptions, normalized);
    if (existing != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return null;
      setState(() {
        _selectedCategory = existing;
        _categoryController.text = existing;
        _syncCategoryBrowseFilterToSelection();
        _categoryFieldRevision += 1;
      });
      return existing;
    }

    if (currentTag.isEmpty) {
      _showSnack('Choose a $_tagName first.');
      return null;
    }

    await _repository.saveTagCategory(currentTag, normalized);
    if (!mounted) return null;
    _scheduleCategoryRefresh(selectedCategory: normalized);
    _showSnack('Category saved for $currentTag');
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final constrainedWidth = media.size.width < 820
        ? media.size.width - 24
        : TagDialogStyles.maxWidth;
    final constrainedHeight = media.size.height < 760
        ? media.size.height - 24
        : TagDialogStyles.maxHeight;

    final isLegacy = widget.legacyStyle;
    final dialogTheme = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(
        surface: isLegacy
            ? const Color(0xFFF6EEE3)
            : TagDialogStyles.surface(theme),
        surfaceContainerHighest: isLegacy
            ? const Color(0xFFF1E1CF)
            : TagDialogStyles.surfaceHigh(theme),
        primary: isLegacy
            ? const Color(0xFF9D6225)
            : TagDialogStyles.accent(theme),
        onPrimary: theme.brightness == Brightness.dark
            ? theme.colorScheme.onPrimary
            : Colors.white,
        outline: isLegacy
            ? const Color(0xFFC39B66)
            : TagDialogStyles.outlineColor(theme),
      ),
      scaffoldBackgroundColor: isLegacy
          ? const Color(0xFFF6EEE3)
          : TagDialogStyles.surface(theme),
      tabBarTheme: theme.tabBarTheme.copyWith(
        labelColor: isLegacy
            ? const Color(0xFF4A2B12)
            : TagDialogStyles.title(theme),
        unselectedLabelColor: isLegacy
            ? const Color(0xFF4A2B12)
            : TagDialogStyles.title(theme),
        dividerColor: Colors.transparent,
        indicatorColor: isLegacy
            ? const Color(0xFF9D6225)
            : TagDialogStyles.accent(theme),
      ),
    );

    return Theme(
      data: dialogTheme,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constrainedWidth,
                  maxHeight: constrainedHeight,
                ),
                child: Dialog(
                  insetPadding: TagDialogStyles.outerInset,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      TagDialogStyles.borderRadius,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  backgroundColor: TagDialogStyles.surface(theme),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TagDialogHeader(
                        title: '$_tagLabel Tags for $_selectionLabel',
                        onClose: () => Navigator.of(context).pop(),
                        onShowInstructions: _showInstructions,
                        onFindText: _showFindText,
                        onImportClipboard: _showClipboardImport,
                        onRenameCurrentTag: _renameCurrentTag,
                        defaultTag: _defaultTag,
                        onUseDefault: _defaultTag == null
                            ? null
                            : _useDefaultTag,
                        onSaveDefault: _saveDefaultTag,
                        legacyStyle: isLegacy,
                      ),
                      Expanded(
                        child: TagDialogHashTab(
                          tagSymbol: _tagLabel,
                          loading: _loading,
                          groupedSummaries: _groupedVisibleSummaries(),
                          searchSummaries: _summariesInSelectedCategory(),
                          tagController: _tagController,
                          categoryController: _categoryController,
                          searchController: _searchController,
                          selectedCategory: _selectedCategory,
                          categoryOptions: _categoryOptions,
                          categoryFieldRevision: _categoryFieldRevision,
                          categoryFilter: _categoryFilter,
                          sortMode: _sortMode,
                          working: _working,
                          onTagSubmitted: (value) => _reloadSelectedTag(value),
                          onApplySelection: _applySelection,
                          onCategoryChanged: _handleCategoryChanged,
                          onToggleSelectedCategoryBrowseFilter:
                              _toggleSelectedCategoryBrowseFilter,
                          onResetBrowseState: _resetBrowseState,
                          onSearchSelected: _selectTagFromSearch,
                          onSortModeChanged: (mode) =>
                              setState(() => _sortMode = mode),
                          onOpenSummaryDetails: _openSummaryDetails,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
