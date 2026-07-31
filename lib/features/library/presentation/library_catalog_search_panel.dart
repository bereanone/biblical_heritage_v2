import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_settings_service.dart';
import '../data/library_catalog_service.dart';
import 'library_font_scale.dart';
import '../../search/search_highlight_helper.dart';
import '../../search/search_result_quick_apply_button.dart';

class LibraryCatalogSearchPanel extends StatefulWidget {
  const LibraryCatalogSearchPanel({
    super.key,
    required this.onSelectItem,
    this.onQuickApplyItem,
    this.initialQuery,
  });

  final void Function(
    LibraryCatalogSearchResult result,
    int index,
    List<LibraryCatalogSearchResult> results,
    String searchQuery,
    String collectionFilter,
  )
  onSelectItem;
  final Future<void> Function(
    LibraryCatalogSearchResult result,
    String searchQuery,
  )?
  onQuickApplyItem;
  final String? initialQuery;

  @override
  State<LibraryCatalogSearchPanel> createState() =>
      _LibraryCatalogSearchPanelState();
}

const List<({String value, String label})> _kEgwCollectionFilters = [
  (value: 'all', label: 'All Collections'),
  (value: 'egw_books', label: 'Books'),
  (value: 'egw_devotionals', label: 'Devotionals'),
  (value: 'egw_commentaries', label: 'Commentaries'),
  (value: 'egw_misc_collections', label: 'Misc Collections'),
  (value: 'egw_pamphlets', label: 'Pamphlets'),
  (value: 'egw_periodicals', label: 'Periodicals'),
  (value: 'egw_manuscript_releases', label: 'Manuscript Releases'),
  (value: 'adventist_pioneer_library', label: 'Pioneer Library'),
];

class _LibraryCatalogSearchPanelState extends State<LibraryCatalogSearchPanel> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _resultsScrollController = ScrollController();
  List<LibraryCatalogSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  String? _lastSearchTerm;
  String? _activeSearchTerm;
  LibraryCatalogSearchSessionSnapshot? _rememberedSession;
  bool _hasSearched = false;
  int _searchRequestId = 0;
  String _selectedCollection = 'all';
  bool _selectedCollectionHasIndexedContent = true;

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _controller.text = initialQuery;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _lastSearchTerm = initialQuery;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      if (initialQuery.isEmpty) {
        _loadRememberedSearch();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedSearch() async {
    final rememberedSession =
        LibraryCatalogSearchSessionSnapshot.fromJsonString(
          await AppSettingsService.instance.loadLastElibrarySearchSessionJson(),
        );
    final remembered = await AppSettingsService.instance
        .loadLastElibrarySearch();
    if (!mounted) return;
    final query = rememberedSession?.query.trim().isNotEmpty == true
        ? rememberedSession!.query.trim()
        : remembered?.trim() ?? '';
    if (query.isEmpty || _controller.text.trim().isNotEmpty) {
      return;
    }
    setState(() {
      _lastSearchTerm = query;
      _rememberedSession = rememberedSession?.copyWith(query: query);
    });
  }

  void _resetSearchState() {
    _searchRequestId += 1;
    _results = const [];
    _loading = false;
    _error = null;
    _hasSearched = false;
    _activeSearchTerm = null;
    _selectedCollectionHasIndexedContent = true;
  }

  void _onFilterChanged(String filterValue) {
    if (_selectedCollection == filterValue) return;
    setState(() {
      _selectedCollection = filterValue;
      _selectedCollectionHasIndexedContent = true;
    });
    final hasQuery = _controller.text.trim().isNotEmpty;
    if (hasQuery) {
      _performSearch();
    }
  }

  Future<void> _performSearch({String? overrideQuery}) async {
    final query = (overrideQuery ?? _controller.text).trim();
    if (query.isEmpty) {
      if (!mounted) return;
      setState(() {
        _resetSearchState();
      });
      return;
    }

    final requestId = ++_searchRequestId;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _hasSearched = true;
        _lastSearchTerm = query;
        _activeSearchTerm = query;
      });
    }

    await AppSettingsService.instance.saveLastElibrarySearch(query);
    try {
      final normalizedCollectionFilter = _selectedCollection == 'all'
          ? null
          : _selectedCollection;
      final totalCount = await LibraryCatalogService.instance
          .countSearchContentResults(
            query: query,
            collectionFilter: normalizedCollectionFilter,
          );
      final results = await LibraryCatalogService.instance.searchContent(
        query: query,
        limit: totalCount <= 0 ? 50 : totalCount,
        collectionFilter: normalizedCollectionFilter,
      );
      final hasCollectionFilter = _selectedCollection != 'all';
      var hasIndexedContent = true;
      if (hasCollectionFilter && results.isEmpty) {
        hasIndexedContent =
            await LibraryCatalogService.instance.countIndexedSearchableItems(
              collectionFilter: _selectedCollection,
            ) >
            0;
      }
      if (!mounted || requestId != _searchRequestId) return;
      final snapshot = LibraryCatalogSearchSessionSnapshot(
        query: query,
        collectionFilter: normalizedCollectionFilter,
        totalCount: results.length,
      );
      setState(() {
        _results = results;
        _loading = false;
        _selectedCollectionHasIndexedContent = hasIndexedContent;
        _rememberedSession = snapshot;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_resultsScrollController.hasClients) return;
        if (_resultsScrollController.offset.abs() < 0.5) return;
        _resultsScrollController.jumpTo(0);
      });
      unawaited(
        AppSettingsService.instance.saveLastElibrarySearchSessionJson(
          snapshot.toJsonString(),
        ),
      );
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _error = 'Could not search the eLibrary: $error';
        _loading = false;
        _results = const [];
        _selectedCollectionHasIndexedContent = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rememberedSearch = _rememberedSession?.query.trim().isNotEmpty == true
        ? _rememberedSession!.query.trim()
        : _lastSearchTerm?.trim() ?? '';
    final displaySearchTerm = _activeSearchTerm ?? rememberedSearch;
    final highlightTerms = extractLibrarySearchHighlightTerms(
      displaySearchTerm,
    );
    final rememberedSearchLabel = _buildRememberedSearchLabel();
    final results = _results;
    final hasSelectedIndex = _rememberedSession?.hasCurrentIndex == true;
    final selectedIndex = hasSelectedIndex
        ? _rememberedSession!.currentIndex
        : null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final hasQuery = value.text.trim().isNotEmpty;
              return TextField(
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.search,
                style: libraryBodyTextStyle(
                  context,
                  theme.textTheme.bodyMedium,
                  color: scheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: 'Search eLibrary',
                  hintText: 'Search book text, titles, or authors',
                  border: const OutlineInputBorder(),
                  labelStyle: libraryControlTextStyle(
                    context,
                    theme.textTheme.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                  hintStyle: libraryCaptionTextStyle(
                    context,
                    theme.textTheme.bodySmall,
                    color: scheme.onSurfaceVariant,
                  ),
                  suffixIcon: hasQuery
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                setState(() {
                                  _resetSearchState();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => _performSearch(),
                            ),
                          ],
                        )
                      : IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: () => _performSearch(),
                        ),
                ),
                onSubmitted: (_) => _performSearch(),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Searches the indexed eLibrary text and opens the selected hit.',
              style: libraryCaptionTextStyle(
                context,
                theme.textTheme.bodySmall,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: _EgwCategoryFilterField(
            selectedValue: _selectedCollection,
            filters: _kEgwCollectionFilters,
            onChanged: _onFilterChanged,
          ),
        ),
        if (rememberedSearchLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  minimumSize: const Size(0, 44),
                  foregroundColor: scheme.onSurface,
                  textStyle: libraryBodyTextStyle(
                    context,
                    theme.textTheme.bodyMedium,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: () => _resumeRememberedSearch(),
                child: Text.rich(
                  TextSpan(
                    text: rememberedSearchLabel,
                    style: libraryBodyTextStyle(
                      context,
                      theme.textTheme.bodyMedium,
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: libraryBodyTextStyle(
                        context,
                        theme.textTheme.bodyMedium,
                        color: scheme.onSurface,
                      ),
                    ),
                  )
                : !_hasSearched
                ? ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) {
                      final hasDraftQuery = value.text.trim().isNotEmpty;
                      final message = hasDraftQuery
                          ? 'Type a search term, then press Search.'
                          : rememberedSearchLabel.isNotEmpty
                          ? 'Tap the remembered search below to restore the last session.'
                          : 'Type a search term, then press Search.';
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: libraryBodyTextStyle(
                                  context,
                                  theme.textTheme.bodyMedium,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : results.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedCollection != 'all' &&
                                    !_selectedCollectionHasIndexedContent
                                ? 'No indexed books are available in this section yet. You can index missing books from eLibrary Setup.'
                                : 'No eLibrary matches found.',
                            textAlign: TextAlign.center,
                            style: libraryBodyTextStyle(
                              context,
                              theme.textTheme.bodyMedium,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: _resultsScrollController,
                    itemCount: results.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final item = result.item;
                      final locationText = result.locationText.trim();
                      final snippetText = result.snippet.trim();
                      final hasLocation = locationText.isNotEmpty;
                      return ListTile(
                        dense: true,
                        minLeadingWidth: 40,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        selected: selectedIndex == index,
                        selectedTileColor: scheme.secondaryContainer.withValues(
                          alpha: 0.45,
                        ),
                        leading: widget.onQuickApplyItem == null
                            ? Icon(
                                item.isPdf
                                    ? Icons.picture_as_pdf_outlined
                                    : Icons.menu_book_outlined,
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SearchResultQuickApplyButton(
                                    onPressed: () {
                                      unawaited(
                                        widget.onQuickApplyItem!(
                                          result,
                                          displaySearchTerm,
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    item.isPdf
                                        ? Icons.picture_as_pdf_outlined
                                        : Icons.menu_book_outlined,
                                  ),
                                ],
                              ),
                        title: Text(
                          item.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: libraryTitleTextStyle(
                            context,
                            theme.textTheme.titleMedium,
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: libraryCaptionTextStyle(
                                context,
                                theme.textTheme.bodySmall,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (hasLocation)
                              Text(
                                locationText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryCaptionTextStyle(
                                  context,
                                  theme.textTheme.bodySmall,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            if (snippetText.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              _HighlightedSearchText(
                                text: snippetText,
                                baseStyle: libraryBodyTextStyle(
                                  context,
                                  theme.textTheme.bodyMedium,
                                  color: scheme.onSurface,
                                ),
                                highlightTerms: highlightTerms,
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => widget.onSelectItem(
                          result,
                          index,
                          results,
                          displaySearchTerm,
                          _selectedCollection,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  String _collectionFilterLabel(String? filterValue) {
    final normalized = filterValue?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'all') {
      return '';
    }
    return libraryCollectionFilterLabelForValue(normalized);
  }

  String _buildRememberedSearchLabel() {
    final session = _rememberedSession;
    final query = session?.query.trim().isNotEmpty == true
        ? session!.query.trim()
        : _lastSearchTerm?.trim() ?? '';
    if (query.isEmpty) {
      return '';
    }

    final parts = <String>[stripWrappingSearchQuotes(query)];

    final collectionLabel = _collectionFilterLabel(session?.collectionFilter);
    if (collectionLabel.isNotEmpty) {
      parts.add(collectionLabel);
    }

    if (session?.hasCurrentIndex == true) {
      parts.add(session!.counterLabel);
    } else if (session != null) {
      parts.add('${session.totalCount} results');
    }

    return 'Last search: ${parts.join(' — ')}';
  }

  Future<void> _resumeRememberedSearch() async {
    final session = _rememberedSession;
    final query = session?.query.trim().isNotEmpty == true
        ? session!.query.trim()
        : _lastSearchTerm?.trim() ?? '';
    if (query.isEmpty) {
      return;
    }

    final collectionFilter =
        session?.collectionFilter?.trim().isNotEmpty == true
        ? session!.collectionFilter!.trim()
        : 'all';
    if (!mounted) return;
    setState(() {
      _selectedCollection = collectionFilter;
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
      _selectedCollectionHasIndexedContent = true;
    });

    await _performSearch(overrideQuery: query);
    if (!mounted) {
      return;
    }
    if (session == null || !session.hasCurrentIndex || _results.isEmpty) {
      return;
    }

    final index = session.currentIndex!.clamp(0, _results.length - 1).toInt();
    final normalizedCollectionFilter = collectionFilter == 'all'
        ? null
        : collectionFilter;
    final restoredSnapshot = LibraryCatalogSearchSessionSnapshot(
      query: query,
      collectionFilter: normalizedCollectionFilter,
      currentIndex: index,
      totalCount: _results.length,
    );
    setState(() {
      _rememberedSession = restoredSnapshot;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_resultsScrollController.hasClients) return;
      final viewport = _resultsScrollController.position.viewportDimension;
      final estimatedOffset = (index * 88.0) - (viewport * 0.2);
      final target = estimatedOffset
          .clamp(0.0, _resultsScrollController.position.maxScrollExtent)
          .toDouble();
      if ((target - _resultsScrollController.offset).abs() >= 0.5) {
        _resultsScrollController.jumpTo(target);
      }
    });
    await AppSettingsService.instance.saveLastElibrarySearchSessionJson(
      restoredSnapshot.toJsonString(),
    );
  }
}

class _EgwCategoryFilterField extends StatelessWidget {
  const _EgwCategoryFilterField({
    required this.selectedValue,
    required this.filters,
    required this.onChanged,
  });

  final String selectedValue;
  final List<({String value, String label})> filters;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = filters.firstWhere(
      (f) => f.value == selectedValue,
      orElse: () => filters.first,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => _EgwCategoryFilterDialog(
            selectedValue: selectedValue,
            filters: filters,
          ),
        );
        if (result != null) onChanged(result);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Category Filter',
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.fromLTRB(10, 10, 8, 8),
          labelStyle: libraryControlTextStyle(
            context,
            theme.textTheme.bodyMedium,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.label,
                overflow: TextOverflow.ellipsis,
                style: libraryBodyTextStyle(
                  context,
                  theme.textTheme.bodyMedium,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _EgwCategoryFilterDialog extends StatelessWidget {
  const _EgwCategoryFilterDialog({
    required this.selectedValue,
    required this.filters,
  });

  final String selectedValue;
  final List<({String value, String label})> filters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 320,
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Category Filter',
                style: libraryTitleTextStyle(
                  context,
                  theme.textTheme.titleMedium,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filters.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 2),
                  itemBuilder: (context, index) {
                    final filter = filters[index];
                    final isSelected = filter.value == selectedValue;
                    return ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      tileColor: isSelected
                          ? theme.colorScheme.surfaceContainerHigh
                          : null,
                      title: Text(filter.label),
                      titleTextStyle: libraryBodyTextStyle(
                        context,
                        theme.textTheme.bodyMedium,
                        color: theme.colorScheme.onSurface,
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : null,
                      onTap: () => Navigator.of(context).pop(filter.value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HighlightedSearchText extends StatelessWidget {
  const _HighlightedSearchText({
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
