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

  final void Function(LibraryCatalogItem item, String searchQuery) onSelectItem;
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
  (value: 'all', label: 'All'),
  (value: 'EGW Books', label: 'Books'),
  (value: 'EGW Devotionals', label: 'Devotionals'),
  (value: 'EGW Commentaries', label: 'Commentaries'),
  (value: 'EGW Misc Collections', label: 'Misc Collections'),
  (value: 'EGW Pamphlets', label: 'Pamphlets'),
  (value: 'EGW Periodicals', label: 'Periodicals'),
  (value: 'EGW Manuscript Releases', label: 'Manuscript Releases'),
];

class _LibraryCatalogSearchPanelState extends State<LibraryCatalogSearchPanel> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<LibraryCatalogSearchResult> _results = const [];
  bool _loading = false;
  String? _error;
  String? _lastSearchTerm;
  String? _activeSearchTerm;
  bool _hasSearched = false;
  int _searchRequestId = 0;
  int _unindexedCount = 0;
  String _selectedCollection = 'all';

  @override
  void initState() {
    super.initState();
    _loadUnindexedCount();
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
    super.dispose();
  }

  Future<void> _loadUnindexedCount() async {
    final count = await LibraryCatalogService.instance
        .countUnindexedManagedItems();
    if (!mounted) return;
    setState(() => _unindexedCount = count);
  }

  Future<void> _loadRememberedSearch() async {
    final remembered = await AppSettingsService.instance
        .loadLastElibrarySearch();
    if (!mounted) return;
    final query = remembered?.trim() ?? '';
    if (query.isEmpty || _controller.text.trim().isNotEmpty) {
      return;
    }
    setState(() {
      _lastSearchTerm = query;
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
    });
  }

  void _resetSearchState() {
    _searchRequestId += 1;
    _results = const [];
    _loading = false;
    _error = null;
    _hasSearched = false;
    _activeSearchTerm = null;
  }

  void _onFilterChanged(String filterValue) {
    if (_selectedCollection == filterValue) return;
    setState(() {
      _selectedCollection = filterValue;
    });
    final hasQuery =
        _controller.text.trim().isNotEmpty ||
        (_lastSearchTerm?.trim().isNotEmpty ?? false);
    if (hasQuery) {
      _performSearch();
    }
  }

  Future<void> _performSearch({String? overrideQuery}) async {
    final query = (overrideQuery ?? _controller.text).trim();
    if (query.isEmpty) {
      final resume = _lastSearchTerm?.trim() ?? '';
      if (resume.isEmpty) {
        if (!mounted) return;
        setState(() {
          _resetSearchState();
        });
        return;
      }
      _controller.text = resume;
      _controller.selection = TextSelection.collapsed(offset: resume.length);
      await _performSearch(overrideQuery: resume);
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
      final results = await LibraryCatalogService.instance.searchContent(
        query: query,
        limit: 50,
        collectionFilter: _selectedCollection == 'all'
            ? null
            : _selectedCollection,
      );
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _error = 'Could not search the eLibrary: $error';
        _loading = false;
        _results = const [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rememberedSearch = _lastSearchTerm?.trim() ?? '';
    final displaySearchTerm = _activeSearchTerm ?? rememberedSearch;
    final highlightTerms = extractLibrarySearchHighlightTerms(
      displaySearchTerm,
    );
    final results = _results;

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
        if (rememberedSearch.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding: EdgeInsets.zero,
                ),
                onPressed: () =>
                    _performSearch(overrideQuery: rememberedSearch),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Last search: ',
                        style: libraryCaptionTextStyle(
                          context,
                          theme.textTheme.bodySmall,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: stripWrappingSearchQuotes(displaySearchTerm),
                        style: libraryCaptionTextStyle(
                          context,
                          theme.textTheme.bodySmall,
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
                          : rememberedSearch.isNotEmpty
                          ? 'Press Search to rerun the remembered query.'
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
                              if (!hasDraftQuery && rememberedSearch.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextButton.icon(
                                    onPressed: () => _performSearch(
                                      overrideQuery: rememberedSearch,
                                    ),
                                    icon: const Icon(Icons.history),
                                    label: Text(
                                      'Resume last search',
                                      style: libraryControlTextStyle(
                                        context,
                                        theme.textTheme.labelLarge,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.primary,
                                      ),
                                    ),
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
                            'No eLibrary matches found.',
                            textAlign: TextAlign.center,
                            style: libraryBodyTextStyle(
                              context,
                              theme.textTheme.bodyMedium,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (_unindexedCount > 0) ...[
                            const SizedBox(height: 10),
                            Text(
                              '$_unindexedCount book${_unindexedCount == 1 ? '' : 's'} '
                              'in your library ${_unindexedCount == 1 ? 'has' : 'have'} '
                              'not been indexed yet and cannot be searched. '
                              'Open the Commentary panel and tap Refresh to index them.',
                              textAlign: TextAlign.center,
                              style: libraryCaptionTextStyle(
                                context,
                                theme.textTheme.bodySmall,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
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
                        onTap: () =>
                            widget.onSelectItem(item, displaySearchTerm),
                      );
                    },
                  ),
          ),
        ),
      ],
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
