import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_settings_service.dart';
import 'presentation_prep/presentation_ui_helpers.dart';
import 'tag_dialog_header.dart';
import 'tag_dialog_hash_tab.dart';
import 'tag_dialog_models.dart';
import 'tag_dialog_styles.dart';
import 'tag_detail_screen_launcher.dart';
import 'tag_quick_apply_helper.dart';
import 'viewer_passage_models.dart';
import 'viewer_range_selection.dart';
import 'viewer_search_dialog.dart';

class HashTagDialog extends StatefulWidget {
  const HashTagDialog({
    super.key,
    required this.repository,
    required this.passage,
    required this.selection,
    required this.selectionTargets,
    required this.fontScale,
    required this.initialTabIndex,
    required this.tagSymbol,
    this.onTagTabChanged,
    this.initialTag,
    this.selectionLabelOverride,
    this.onApplySelectionOverride,
    this.onSelectBlockId,
    this.legacyStyle = false,
    this.fullScreen = false,
  });

  final HashTagRepository repository;
  final PassageData passage;
  final ViewerRangeSelection selection;
  final List<HashTagTarget> selectionTargets;
  final double fontScale;
  final int initialTabIndex;
  final String tagSymbol;
  final ValueChanged<int>? onTagTabChanged;
  final String? initialTag;
  final String? selectionLabelOverride;
  final Future<HashTagQuickApplyResult> Function(String tag)?
  onApplySelectionOverride;
  final Future<void> Function(int blockId)? onSelectBlockId;
  final bool legacyStyle;
  final bool fullScreen;

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
  List<MapEntry<String?, List<HashTagSummary>>> _visibleSummaryGroups =
      const <MapEntry<String?, List<HashTagSummary>>>[];
  List<HashTagSummary> _selectedCategorySummaries = const <HashTagSummary>[];
  String? _defaultTag;
  String? _tagCategory;
  String? _selectedCategory;
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
      _tagCategory = null;
      _tagController.clear();
      _selectedCategory = null;
      _categoryController.clear();
      _categoryFilter = null;
      _searchController.clear();
      _recomputeBrowseViews();
      _loading = false;
    });
    final initialTag = widget.initialTag?.trim() ?? '';
    if (mounted && initialTag.isNotEmpty) {
      await _reloadSelectedTag(initialTag);
    }
  }

  String get _currentTag => _repository.normalizeTagName(_tagController.text);

  String get _selectionLabel {
    final override = widget.selectionLabelOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
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

          final category = _summaryCategories[summary.identityKey]?.trim();
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
      final category = _summaryCategories[summary.identityKey]?.trim();
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

  void _recomputeBrowseViews() {
    _visibleSummaryGroups = _groupedVisibleSummaries();
    _selectedCategorySummaries = _summariesInSelectedCategory();
  }

  Future<void> _saveCurrentCategory() async {
    final tag = _currentTag;
    if (tag.isEmpty) {
      _showSnack('No tag selected. Enter or select a tag first.');
      return;
    }
    final newCategory = _selectedCategory?.trim();
    final oldCategory = _tagCategory?.trim();
    if ((oldCategory ?? '') == (newCategory ?? '')) {
      _showSnack('Category already set for $tag.');
      return;
    }
    final saved = await _repository.saveTagCategory(
      tag,
      newCategory ?? '',
      currentCategory: oldCategory,
      currentCategoryKnown: true,
    );
    if (!mounted) return;
    if (!saved) {
      _showSnack('Could not save category for $tag.');
      return;
    }
    await _reloadSelectedTag(tag, category: newCategory);
    _showSnack(
      'Category changed: $tag moved to ${newCategory?.isNotEmpty == true ? newCategory : 'None'}',
    );
  }

  Future<String?> _resolveTagForSelection() async {
    final currentTag = _currentTag;
    if (currentTag.isNotEmpty) {
      return currentTag;
    }

    final defaultTag =
        _defaultTag?.trim() ??
        _repository.normalizeTagName(await _repository.loadDefaultTag() ?? '');
    if (defaultTag.isNotEmpty) {
      return defaultTag;
    }

    await _showNoTagSelectedDialog();
    return null;
  }

  Future<void> _applySelectionToTargets(String tag) async {
    final applyOverride = widget.onApplySelectionOverride;
    if (applyOverride != null) {
      setState(() => _working = true);
      final result = await applyOverride(tag);
      if (!mounted) return;
      setState(() => _working = false);
      if (result.tag == null) {
        await _showNoTagSelectedDialog();
        return;
      }
      await _repository.saveTagCategory(
        result.tag!,
        _selectedCategory ?? '',
        currentCategory: _tagCategory,
        currentCategoryKnown: true,
      );
      await _reloadSelectedTag(result.tag!, category: _selectedCategory);
      _showSnack(
        'Tagged ${result.inserted} verse(s) with ${result.tag}'
        '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
      );
      return;
    }
    final targets = widget.selectionTargets;
    if (targets.length > 1) {
      final book = targets.first.bookNumber;
      final chapter = targets.first.chapter;
      final crossChapter = targets.any(
        (t) => t.bookNumber != book || t.chapter != chapter,
      );
      if (crossChapter) {
        _showSnack(
          'Multi-chapter ranges are not supported for tagging. '
          'Select verses within one chapter.',
        );
        return;
      }
      setState(() => _working = true);
      final result = await _repository.addBibleRangeToTag(
        tag: tag,
        category: _selectedCategory,
        bookNumber: book,
        chapter: chapter,
        verseStart: targets.first.verse,
        verseEnd: targets.last.verse,
      );
      if (!mounted) return;
      setState(() => _working = false);
      if (result.tag == null) {
        await _showNoTagSelectedDialog();
        return;
      }
      await _repository.saveTagCategory(
        result.tag!,
        _selectedCategory ?? '',
        currentCategory: _tagCategory,
        currentCategoryKnown: true,
      );
      await _reloadSelectedTag(result.tag!, category: _selectedCategory);
      _showSnack(
        'Tagged ${result.inserted} verse(s) with ${result.tag}'
        '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
      );
      return;
    }
    setState(() => _working = true);
    final result = await _repository.quickApplyTargets(
      targets: targets,
      tag: tag,
      category: _selectedCategory,
    );
    if (!mounted) return;
    setState(() => _working = false);
    if (result.tag == null) {
      await _showNoTagSelectedDialog();
      return;
    }
    await _repository.saveTagCategory(
      result.tag!,
      _selectedCategory ?? '',
      currentCategory: _tagCategory,
      currentCategoryKnown: true,
    );
    await _reloadSelectedTag(result.tag!, category: _selectedCategory);
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
      _recomputeBrowseViews();
    });
  }

  Future<Map<String, String?>> _loadSummaryCategories(
    List<HashTagSummary> summaries,
  ) async {
    final pairs = await Future.wait(
      summaries.map(
        (summary) async => MapEntry(summary.identityKey, summary.category),
      ),
    );
    return {for (final pair in pairs) pair.key: pair.value};
  }

  Future<void> _refreshBrowseCategoryMap() async {
    final summaryCategories = await _loadSummaryCategories(_summaries);
    if (!mounted) return;
    setState(() {
      _summaryCategories = summaryCategories;
      _recomputeBrowseViews();
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
          final category = _summaryCategories[summary.identityKey]?.trim();
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
      _recomputeBrowseViews();
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
      _recomputeBrowseViews();
    });
  }

  void _syncCategoryBrowseFilterToSelection() {
    if (_categoryFilter == null) return;
    _categoryFilter = _browseCategoryFilterForSelection();
  }

  Future<void> _selectTagFromSearch(HashTagSummary summary) async {
    final tag = summary.tag.trim();
    if (tag.isEmpty) return;

    final requestRevision = ++_browseStateRevision;
    await _reloadSelectedTag(
      tag,
      category: summary.category,
      expectedBrowseStateRevision: requestRevision,
    );
    if (!mounted) return;
    if (requestRevision != _browseStateRevision) return;

    setState(() {
      _searchController.text = _repository.normalizeTagName(tag);
      _recomputeBrowseViews();
    });
  }

  Future<void> _reloadSelectedTag(
    String tag, {
    String? category,
    int? expectedBrowseStateRevision,
    bool syncBrowseFilter = false,
  }) async {
    final normalizedTag = _repository.normalizeTagName(tag);
    if (normalizedTag.isEmpty) {
      if (!mounted) return;
      setState(_clearSelectedTagOnly);
      return;
    }

    final summaries = await _repository.loadSummaries();
    final summaryCategories = await _loadSummaryCategories(summaries);
    final resolvedCategory = await _repository.loadTagCategory(
      normalizedTag,
      category: category,
    );
    if (!mounted) return;
    if (expectedBrowseStateRevision != null &&
        expectedBrowseStateRevision != _browseStateRevision) {
      return;
    }
    final tagStillExists = summaries.any(
      (summary) =>
          summary.tag == normalizedTag &&
          ((resolvedCategory == null &&
                  (summary.category?.trim().isEmpty ?? true)) ||
              (resolvedCategory != null &&
                  summary.category?.trim().toLowerCase() ==
                      resolvedCategory.trim().toLowerCase())),
    );
    final resolvedCategoryRaw = resolvedCategory?.trim();
    String? resolvedCategoryValue = resolvedCategoryRaw;
    if (resolvedCategoryValue?.isEmpty ?? true) {
      resolvedCategoryValue = null;
    }
    final shouldShowMissingRowSnack = !tagStillExists;
    setState(() {
      _summaries = summaries;
      _summaryCategories = summaryCategories;
      _tagController.text = normalizedTag;
      _selectedCategory = resolvedCategoryValue;
      _tagCategory = resolvedCategoryValue;
      _categoryController.text = resolvedCategoryValue ?? '';
      _searchController.clear();
      _recomputeBrowseViews();
    });
    if (shouldShowMissingRowSnack) {
      debugPrint(
        await _repository.debugTagReport(
          normalizedTag,
          category: resolvedCategory,
        ),
      );
      _showMissingDefaultTagSnack(normalizedTag);
    }
    await _refreshCategoryOptions(
      selectedCategory: resolvedCategory,
      expectedBrowseStateRevision: expectedBrowseStateRevision,
    );
    if (!mounted || !syncBrowseFilter) return;
    setState(() {
      _categoryFilter = resolvedCategory ?? _uncategorizedCategoryFilterValue;
    });
  }

  Future<void> _useDefaultTag() async {
    final defaultTag = _defaultTag?.trim().isNotEmpty == true
        ? _defaultTag!.trim()
        : _repository.normalizeTagName(
            await _repository.loadDefaultTag() ?? '',
          );
    if (defaultTag.isEmpty) {
      _showSnack('No default $_tagName is set yet.');
      return;
    }
    final defaultCategory =
        await _repository.loadDefaultTagCategory() ??
        await _repository.loadTagCategory(defaultTag);
    if (!mounted) return;
    setState(() {
      _tagController.text = defaultTag;
      final resolvedCategoryRaw = defaultCategory?.trim();
      String? resolvedCategory = resolvedCategoryRaw;
      if (resolvedCategory?.isEmpty ?? true) {
        resolvedCategory = null;
      }
      _selectedCategory = resolvedCategory;
      _tagCategory = resolvedCategory;
      _categoryController.text = resolvedCategory ?? '';
      _categoryFilter = resolvedCategory ?? _uncategorizedCategoryFilterValue;
      _recomputeBrowseViews();
    });
    await _reloadSelectedTag(
      defaultTag,
      category: defaultCategory,
      syncBrowseFilter: true,
    );
  }

  void _showMissingDefaultTagSnack(String tag) {
    if (!mounted) return;
    _showSnack('$tag has no saved row yet. It is ready to tag with.');
  }

  Future<String?> _resolveFindTextTargetTag() async {
    final selectedTag = _currentTag;
    if (selectedTag.isNotEmpty) {
      return selectedTag;
    }

    final shownDefaultTag = _defaultTag?.trim() ?? '';
    if (shownDefaultTag.isNotEmpty) {
      return _repository.normalizeTagName(shownDefaultTag);
    }

    final activeDefaultTag = _repository.normalizeTagName(
      await _repository.loadActiveDefaultTag() ?? '',
    );
    if (activeDefaultTag.isNotEmpty) {
      return activeDefaultTag;
    }

    return null;
  }

  Future<void> _saveDefaultTag() async {
    final tag = _currentTag;
    if (tag.isEmpty) return;
    await _saveCurrentCategory();
    await _repository.saveDefaultTag(tag);
    await _repository.saveDefaultTagCategory(_tagCategory);
    await AppSettingsService.instance.saveActiveTagFamily(
      _repository is DollarTagRepository ? 'dollar' : 'hash',
    );
    if (!mounted) return;
    setState(() {
      _defaultTag = tag;
    });
    await _reloadSelectedTag(tag, category: _tagCategory);
    _showSnack('Default set to $tag');
  }

  Future<void> _renameCurrentTag() async {
    final current = _currentTag;
    if (current.isEmpty) return;
    final controller = TextEditingController(text: current);
    final renamed = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            'Rename current tag',
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '$_tagLabel tag',
              border: OutlineInputBorder(),
              labelStyle: TagDialogStyles.labelTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.body(theme),
              ),
              floatingLabelStyle: TagDialogStyles.labelTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.title(theme),
              ),
            ),
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel(
                'Cancel',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: TagDialogStyles.fittedButtonLabel(
                'Rename',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
      category: _tagCategory,
      categoryKnown: true,
    );
    if (!mounted) return;
    await _reloadSelectedTag(normalized, category: _tagCategory);
    _showSnack(
      'Renamed $current to $normalized ($count row${count == 1 ? '' : 's'}).',
    );
  }

  Future<void> _showInstructions() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            'Instructions',
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            '$_tagLabel tags collect verse references into reusable lists. '
            'Use Tag Verse to add the current verse or range. '
            'Tap a tag line to open the verse list on the next screen. '
            'Use Save to set the rapid-tag default. '
            'Use the Rapid Tag Session controls when you want to tag many verses without extra prompts. '
            'A verse can appear in multiple different $_tagName lists; duplicates are only blocked inside the same tag.',
            style: TagDialogStyles.bodyTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel(
                'Done',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showFindText() async {
    final currentTag = await _resolveFindTextTargetTag();
    if (!mounted) return;
    if (currentTag == null || currentTag.isEmpty) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return AlertDialog(
            title: Text(
              'Choose or create a #tag',
              style: TagDialogStyles.titleTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.title(theme),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              'Choose or create a #tag before adding search results.',
              style: TagDialogStyles.bodyTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.body(theme),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: TagDialogStyles.fittedButtonLabel(
                  'OK',
                  style: TagDialogStyles.buttonTextStyle(
                    theme,
                    widget.fontScale,
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      );
      return;
    }

    if (!mounted) return;
    await showViewerSearchDialog(
      context,
      fontScale: widget.fontScale,
      currentTag: currentTag,
      onBibleResultAdded: (tag) async {
        if (!mounted) return;
        await _reloadSelectedTag(tag, category: _tagCategory);
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
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            'Import $_tagLabel list from Clipboard',
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
              fontWeight: FontWeight.w900,
            ),
          ),
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
                hintStyle: TagDialogStyles.bodyTextStyle(
                  theme,
                  widget.fontScale,
                  color: TagDialogStyles.mutedBody(theme),
                ),
              ),
              style: TagDialogStyles.bodyTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.title(theme),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel(
                'Cancel',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: TagDialogStyles.fittedButtonLabel(
                'Import',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
        'No usable $_tagLabel list found. Bible and eLibrary cards import best, and note text is preserved.',
      );
      return;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_completeImportRefresh(result));
    });
  }

  Future<void> _completeImportRefresh(HashTagImportResult result) async {
    if (!mounted) return;
    await _reloadSelectedTag(result.tag);
    if (!mounted) return;
    await _showImportResultsDialog(result);
  }

  Future<void> _showImportResultsDialog(HashTagImportResult result) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (resultCtx) {
        final media = MediaQuery.of(resultCtx);
        final theme = Theme.of(resultCtx);
        return MediaQuery(
          data: media.copyWith(textScaler: MediaQuery.textScalerOf(resultCtx)),
          child: AlertDialog(
            title: Text(
              'Import Results',
              style: TagDialogStyles.titleTextStyle(
                theme,
                widget.fontScale,
                color: TagDialogStyles.title(theme),
                fontWeight: FontWeight.w900,
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
                    Text(
                      'Tag: ${result.tag}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.title(theme),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Parsed items: ${result.parsedCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'Bible cards imported: ${result.bibleImportedCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'eLibrary cards imported: ${result.eLibraryImportedCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'Unsupported/skipped cards: ${result.unsupportedCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'Inserted/updated rows: ${result.insertedCount + result.updatedExistingCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'Skipped existing: ${result.skippedExistingCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    Text(
                      'Failed lines: ${result.failedCount}',
                      style: TagDialogStyles.bodyTextStyle(
                        theme,
                        widget.fontScale,
                        color: TagDialogStyles.body(theme),
                      ),
                    ),
                    if (result.warnings.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Warnings',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: TagDialogStyles.title(theme),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...result.warnings.map(
                        (warning) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            warning,
                            style: TagDialogStyles.bodyTextStyle(
                              theme,
                              widget.fontScale,
                              color: TagDialogStyles.body(theme),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (result.failures.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Failures',
                        style: TagDialogStyles.bodyTextStyle(
                          theme,
                          widget.fontScale,
                          color: TagDialogStyles.title(theme),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...result.failures.map(
                        (failure) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Line ${failure.lineNumber}: ${failure.reason}${failure.line.isNotEmpty ? ' — ${failure.line}' : ''}',
                            style: TagDialogStyles.bodyTextStyle(
                              theme,
                              widget.fontScale,
                              color: TagDialogStyles.body(theme),
                            ),
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
                child: TagDialogStyles.fittedButtonLabel(
                  'OK',
                  style: TagDialogStyles.buttonTextStyle(
                    theme,
                    widget.fontScale,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSummaryDetails(HashTagSummary summary) async {
    final previousDefault = _defaultTag;
    final changed = await showHashTagDetailPopup(
      context,
      repository: _repository,
      tag: summary.tag,
      category: summary.category,
      fontScale: widget.fontScale,
      onSelectBlockId: widget.onSelectBlockId,
      onSelectTag: (tag) async {
        await _reloadSelectedTag(tag, syncBrowseFilter: true);
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
      await _reloadSelectedTag(summary.tag, syncBrowseFilter: true);
    }
  }

  void _showSnack(String message) {
    showReadableSnackBar(context, message, fontScale: widget.fontScale);
  }

  Future<void> _showNoTagSelectedDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(
            'No Tag Selected',
            style: TagDialogStyles.titleTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.title(theme),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Enter or select a $_tagName before tagging a verse.',
            style: TagDialogStyles.bodyTextStyle(
              theme,
              widget.fontScale,
              color: TagDialogStyles.body(theme),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: TagDialogStyles.fittedButtonLabel(
                'OK',
                style: TagDialogStyles.buttonTextStyle(
                  theme,
                  widget.fontScale,
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _clearSelectedTagOnly() {
    _searchController.clear();
    _tagController.clear();
    _tagCategory = null;
    _selectedCategory = null;
    _categoryController.clear();
    _recomputeBrowseViews();
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
          _recomputeBrowseViews();
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedCategory = _categoryLabel(value);
      _categoryController.text = _selectedCategory ?? '';
      _syncCategoryBrowseFilterToSelection();
      _recomputeBrowseViews();
    });
  }

  Future<String?> _showNewCategoryDialog() async {
    final currentTag = _currentTag;
    final controller = TextEditingController();
    String? errorText;
    String? categoryName;
    try {
      categoryName = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          final theme = Theme.of(dialogContext);
          return StatefulBuilder(
            builder: (context, setDialogState) {
              void submit() {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(() {
                    errorText = 'Enter a category name.';
                  });
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              }

              return AlertDialog(
                title: Text(
                  'New Category',
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.title(theme),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Category name',
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                    labelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.body(theme),
                    ),
                    floatingLabelStyle: TagDialogStyles.labelTextStyle(
                      theme,
                      widget.fontScale,
                      color: TagDialogStyles.title(theme),
                    ),
                    errorStyle: TagDialogStyles.bodyTextStyle(
                      theme,
                      widget.fontScale,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  style: TagDialogStyles.titleTextStyle(
                    theme,
                    widget.fontScale,
                    color: TagDialogStyles.title(theme),
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (_) {
                    if (errorText == null) return;
                    setDialogState(() {
                      errorText = null;
                    });
                  },
                  onSubmitted: (_) => submit(),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: TagDialogStyles.fittedButtonLabel(
                      'Cancel',
                      style: TagDialogStyles.buttonTextStyle(
                        theme,
                        widget.fontScale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: submit,
                    child: TagDialogStyles.fittedButtonLabel(
                      'Add',
                      style: TagDialogStyles.buttonTextStyle(
                        theme,
                        widget.fontScale,
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      await WidgetsBinding.instance.endOfFrame;
      controller.dispose();
    }

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
      });
      return existing;
    }

    if (currentTag.isEmpty) {
      _showSnack('Choose a $_tagName first.');
      return null;
    }

    final saved = await _repository.saveTagCategory(
      currentTag,
      normalized,
      currentCategory: _tagCategory,
      currentCategoryKnown: true,
    );
    if (!mounted) return null;
    if (!saved) {
      _showSnack('Could not save category for $currentTag');
      return null;
    }
    setState(() {
      _selectedCategory = normalized;
      _tagCategory = normalized;
      _categoryController.text = normalized;
      _syncCategoryBrowseFilterToSelection();
      _recomputeBrowseViews();
    });
    await _reloadSelectedTag(currentTag, category: normalized);
    _scheduleCategoryRefresh(selectedCategory: normalized);
    _showSnack('Category changed: $currentTag moved to $normalized');
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final modalSize = TagDialogStyles.mainModalSize(media.size);
    final constrainedWidth = modalSize.width;
    final constrainedHeight = modalSize.height;

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

    Widget buildBody() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TagDialogHeader(
            title: '$_tagLabel Tags for $_selectionLabel',
            fontScale: widget.fontScale,
            onClose: () => Navigator.of(context).pop(),
            onShowInstructions: _showInstructions,
            onFindText: _showFindText,
            onImportClipboard: _showClipboardImport,
            onRenameCurrentTag: _renameCurrentTag,
            defaultTag: _defaultTag,
            onUseDefault: _useDefaultTag,
            onSaveDefault: _saveDefaultTag,
            legacyStyle: isLegacy,
          ),
          Expanded(
            child: TagDialogHashTab(
              tagSymbol: _tagLabel,
              fontScale: widget.fontScale,
              loading: _loading,
              groupedSummaries: _visibleSummaryGroups,
              searchSummaries: _selectedCategorySummaries,
              tagController: _tagController,
              categoryController: _categoryController,
              searchController: _searchController,
              selectedCategory: _selectedCategory,
              categoryOptions: _categoryOptions,
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
              onSortModeChanged: (mode) => setState(() {
                _sortMode = mode;
                _recomputeBrowseViews();
              }),
              onOpenSummaryDetails: _openSummaryDetails,
            ),
          ),
        ],
      );
    }

    if (widget.fullScreen) {
      return Theme(
        data: dialogTheme,
        child: Scaffold(
          backgroundColor: dialogTheme.scaffoldBackgroundColor,
          body: SafeArea(child: buildBody()),
        ),
      );
    }

    return Theme(
      data: dialogTheme,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constrainedWidth,
            maxHeight: constrainedHeight,
          ),
          child: Dialog(
            insetPadding: TagDialogStyles.outerInset,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(TagDialogStyles.borderRadius),
            ),
            clipBehavior: Clip.antiAlias,
            backgroundColor: TagDialogStyles.surface(theme),
            child: buildBody(),
          ),
        ),
      ),
    );
  }
}
