part of 'library_screen.dart';

class _LibraryScreenState extends State<LibraryScreen> {
  static const Set<String> _supportedCollectionFilterValues = <String>{
    'egw_books',
    'egw_devotionals',
    'egw_misc_collections',
    'egw_pamphlets',
    'egw_periodicals',
    'egw_manuscript_releases',
  };

  final _service = LibraryCatalogService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  LibraryRootSelection? _selection;
  bool _loading = true;
  _LibraryTab _tab = _LibraryTab.books;
  _LibraryView _view = _LibraryView.shelf;
  double _viewerFontScale = 1.3;
  String _fileTypeFilter = 'ePubs';
  String _collectionFilter = 'all';
  String _searchQuery = '';
  String? _selectedInitialLetter;
  String? _selectedBookId;
  List<LibraryCatalogItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final viewerFontScale = await AppSettingsService.instance
        .loadViewerFontScale();
    final items = await _service.loadItems();
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _items = items;
      _viewerFontScale = viewerFontScale;
      _loading = false;
    });
    await _syncSelectionAndNavigation(
      _filteredBooks,
      preferExistingSelection: false,
    );
  }

  Future<void> _reloadItems() async {
    final items = await _service.loadItems();
    if (!mounted) return;
    setState(() => _items = items);
    await _syncSelectionAndNavigation(
      _filteredBooks,
      preferExistingSelection: true,
    );
  }

  Future<void> _syncSelectionAndNavigation(
    List<LibraryCatalogItem> items, {
    required bool preferExistingSelection,
  }) async {
    if (items.isEmpty) {
      if (!mounted) return;
      setState(() {
        _selectedBookId = null;
      });
      return;
    }

    final existing = preferExistingSelection
        ? _firstWhereOrNull(items, (item) => item.id == _selectedBookId)
        : null;
    final selected = existing ?? _mostRecentItem(items) ?? items.first;
    if (selected.id != _selectedBookId) {
      if (!mounted) return;
      setState(() => _selectedBookId = selected.id);
    }
    _syncInitialLetterSelection(_filteredBooks);
  }

  Future<void> _openLibraryRootSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LibraryRootSetupScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openELibrarySetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ELibrarySetupScreen()),
    );
    if (!mounted) return;
    await _reloadItems();
  }

  Future<void> _openBookReader(LibraryCatalogItem item) async {
    final initialHref = _initialBookHref(item);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: item,
          initialHref: initialHref,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadItems();
  }

  Future<void> _refreshFolders() async {
    final path = _selection?.path;
    if (path == null || path.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a Library Root first.')),
      );
      return;
    }

    await LibraryRootService.instance.ensureStructure(path);
    await _service.refreshManagedItemsFromDisk();
    if (!mounted) return;
    final unindexed = await _service.countUnindexedManagedItems();
    if (!mounted) return;
    final message = unindexed > 0
        ? 'Library refreshed — $unindexed book${unindexed == 1 ? '' : 's'} '
              'not yet indexed. Open eLibrary Setup and tap Index New/Changed Books.'
        : 'Library folders refreshed.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: unindexed > 0 ? 8 : 4),
      ),
    );
    await _load();
  }

  Future<void> _openBibleApp() async {
    final openBible = widget.onOpenBible;
    if (openBible != null) {
      openBible();
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    await navigator.maybePop();
  }

  String? _initialBookHref(LibraryCatalogItem item) {
    if (item.isPeriodical) return null;
    final savedHref = item.epubHref?.trim() ?? '';
    if (savedHref.isNotEmpty) return savedHref;

    return null;
  }

  Future<void> _setFileTypeFilter(String value) async {
    if (_fileTypeFilter == value) return;
    setState(() {
      _fileTypeFilter = value;
      _selectedInitialLetter = null;
      _tab = _LibraryTab.books;
    });
    await _syncSelectionAndNavigation(
      _filteredBooks,
      preferExistingSelection: true,
    );
  }

  Future<void> _setCollectionFilter(
    String value, {
    bool preserveLetterFilter = false,
  }) async {
    final normalizedValue = _normalizeCollectionFilterSelection(value);
    if (_collectionFilter == normalizedValue) return;
    setState(() {
      _collectionFilter = normalizedValue;
      if (!preserveLetterFilter) {
        _selectedInitialLetter = null;
      }
      _tab = _LibraryTab.books;
    });
    await _syncSelectionAndNavigation(
      _filteredBooks,
      preferExistingSelection: true,
    );
  }

  Future<void> _resetCollectionFilterToAll() {
    return _setCollectionFilter('all', preserveLetterFilter: true);
  }

  Future<void> _handleCollectionFilterSelected(String value) {
    if (_normalizeCollectionFilterSelection(value) == 'all') {
      return _resetCollectionFilterToAll();
    }
    return _setCollectionFilter(value);
  }

  void _setSearchQuery(String _) {
    // Typing only updates the field contents; the query is applied on submit.
  }

  void _applySearchQuery(String value) {
    final normalized = value.trim();
    if (!mounted) return;
    setState(() {
      _searchQuery = normalized;
    });
    _syncInitialLetterSelection(_filteredBooks);
  }

  void _applySearchQueryFromField() {
    _applySearchQuery(_searchController.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  void _clearSearchQuery() {
    _searchController.clear();
    _applySearchQuery('');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
    });
  }

  String _normalizeCollectionFilterSelection(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'all' ||
        normalized == 'all collections' ||
        normalized == 'all_collections') {
      return 'all';
    }
    return trimmed;
  }

  void _setTab(_LibraryTab tab) {
    setState(() => _tab = tab);
    if (tab == _LibraryTab.books) {
      _syncInitialLetterSelection(_filteredBooks);
    }
  }

  void _setView(_LibraryView view) {
    setState(() => _view = view);
  }

  void _setInitialLetter(String? letter) {
    setState(() => _selectedInitialLetter = letter);
  }

  Future<void> _selectBook(LibraryCatalogItem item) async {
    setState(() => _selectedBookId = item.id);
    await _openBookReader(item);
  }

  List<LibraryCatalogItem> get _filteredBooks {
    final query = compactLibrarySearchText(_searchQuery);
    final initial = query.isEmpty
        ? _selectedInitialLetter?.trim().toUpperCase()
        : null;
    final filtered = _items.where((item) {
      if (!_matchesFileTypeFilter(item, _fileTypeFilter)) return false;
      if (!libraryItemMatchesCollectionFilter(item, _collectionFilter)) {
        return false;
      }
      if (!_matchesInitialLetter(item, initial)) return false;
      if (query.isEmpty) return true;
      final haystack = libraryCatalogSearchTextForItem(item);
      return haystack.contains(query);
    }).toList();
    filtered.sort(_compareBooksForShelf);
    return filtered;
  }

  List<LibraryCatalogItem> get _recentBooks {
    final query = compactLibrarySearchText(_searchQuery);
    final initial = query.isEmpty
        ? _selectedInitialLetter?.trim().toUpperCase()
        : null;
    final filtered = _items.where((item) {
      if (!_matchesFileTypeFilter(item, _fileTypeFilter)) return false;
      if (!libraryItemMatchesCollectionFilter(item, _collectionFilter)) {
        return false;
      }
      if (!_matchesInitialLetter(item, initial)) return false;
      if (query.isEmpty) return true;
      final haystack = libraryCatalogSearchTextForItem(item);
      return haystack.contains(query);
    }).toList();
    filtered.sort((a, b) {
      final left =
          b.lastOpened ?? b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          a.lastOpened ?? a.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
      final compare = left.compareTo(right);
      if (compare != 0) return compare;
      return _compareBooksForShelf(a, b);
    });
    return filtered;
  }

  bool _matchesInitialLetter(
    LibraryCatalogItem item,
    String? selectedInitialLetter,
  ) {
    if (selectedInitialLetter == null || selectedInitialLetter.trim().isEmpty) {
      return true;
    }
    final title = _sortableTitle(item.displayTitle);
    if (title.isEmpty) return false;
    final firstChar = title[0].toUpperCase();
    if (selectedInitialLetter == '#') {
      return RegExp(r'^[0-9]').hasMatch(title);
    }
    return firstChar == selectedInitialLetter;
  }

  String _booksEmptyMessage() {
    if (_items.isEmpty) {
      return 'No library items are indexed yet.';
    }

    final query = _searchQuery.trim();
    if (query.isNotEmpty) {
      return 'No library items match "$query".';
    }

    final hasCollectionFilter = _collectionFilter.trim().toLowerCase() != 'all';
    final hasFileTypeFilter = _fileTypeFilter.trim().toLowerCase() != 'all';
    final hasLetterFilter =
        _selectedInitialLetter != null &&
        _selectedInitialLetter!.trim().isNotEmpty;
    if (hasCollectionFilter || hasFileTypeFilter || hasLetterFilter) {
      return 'No library items match the current filters.';
    }

    return 'No library items match the current filters.';
  }

  List<String> get _availableInitialLetters {
    final letters = _filteredBooks
        .map((item) {
          final title = _sortableTitle(item.displayTitle);
          if (title.isEmpty) return null;
          final first = title[0].toUpperCase();
          return RegExp(r'^[A-Z]').hasMatch(first) ? first : '#';
        })
        .whereType<String>()
        .toSet()
        .toList();
    letters.sort();
    return letters;
  }

  List<LibraryCollectionFilterOption> get _availableCollectionFilters {
    return buildLibraryCollectionFilterOptions(_items)
        .where(
          (option) =>
              option.value == 'all' ||
              _supportedCollectionFilterValues.contains(option.value),
        )
        .toList(growable: false);
  }

  void _syncInitialLetterSelection(List<LibraryCatalogItem> books) {
    final selected = _selectedInitialLetter?.trim().toUpperCase();
    if (selected == null || selected.isEmpty) {
      return;
    }
    final available = books
        .map((item) {
          final title = _sortableTitle(item.displayTitle);
          if (title.isEmpty) return null;
          final first = title[0].toUpperCase();
          return RegExp(r'^[A-Z]').hasMatch(first) ? first : '#';
        })
        .whereType<String>()
        .toSet()
        .toList();
    if (!available.contains(selected)) {
      if (!mounted) return;
      setState(() => _selectedInitialLetter = null);
    }
  }

  bool _matchesFileTypeFilter(
    LibraryCatalogItem item,
    String selectedFileType,
  ) {
    final normalized = selectedFileType.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'all') return true;
    if (normalized == 'epubs') return item.isEpub;
    if (normalized == 'pdfs') return item.isPdf;
    return true;
  }

  LibraryCatalogItem? _mostRecentItem(List<LibraryCatalogItem> items) {
    if (items.isEmpty) return null;
    final sorted = [...items];
    sorted.sort((a, b) {
      final left =
          b.lastOpened ?? b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          a.lastOpened ?? a.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });
    return sorted.first;
  }

  int _compareBooksForShelf(LibraryCatalogItem a, LibraryCatalogItem b) {
    final titleCompare = _naturalCompare(
      _sortableTitle(a.displayTitle),
      _sortableTitle(b.displayTitle),
    );
    if (titleCompare != 0) return titleCompare;
    final authorCompare = _naturalCompare(a.author ?? '', b.author ?? '');
    if (authorCompare != 0) return authorCompare;
    return (a.lastOpened ??
            a.dateAdded ??
            DateTime.fromMillisecondsSinceEpoch(0))
        .compareTo(
          b.lastOpened ?? b.dateAdded ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final cardBackground = _librarySurfaceLowColor(theme);
    final selection = _selection;
    final hasRoot = selection?.path != null && selection!.exists;
    final collectionOptions = _availableCollectionFilters;

    return Scaffold(
      backgroundColor: background,
      body: LibraryFontScaleScope(
        scale: _viewerFontScale,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LibraryHeader(
                  hasRoot: hasRoot,
                  rootPath: selection?.path,
                  onOpenBible: _openBibleApp,
                  onOpenLibraryRootSetup: _openLibraryRootSetup,
                  onOpenELibrarySetup: _openELibrarySetup,
                  onRefresh: _refreshFolders,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cardBackground,
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: _libraryOutlineColor(theme)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final collectionWidth = (constraints.maxWidth * 0.42)
                              .clamp(200.0, 300.0)
                              .toDouble();
                          return _loading
                              ? const Center(child: CircularProgressIndicator())
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'Library',
                                          style: libraryScaledTextStyle(
                                            theme.textTheme.headlineSmall,
                                            libraryTitleScale(
                                              libraryFontScaleOf(context),
                                            ),
                                            fontWeight: FontWeight.w800,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                        SizedBox(
                                          width: collectionWidth,
                                          child: _CollectionFilterMenu(
                                            currentValue: _collectionFilter,
                                            options: collectionOptions,
                                            onSelected:
                                                _handleCollectionFilterSelected,
                                          ),
                                        ),
                                        _FileTypeFilterMenu(
                                          currentValue: _fileTypeFilter,
                                          onSelected: _setFileTypeFilter,
                                        ),
                                        _SearchTextButton(
                                          onPressed: () =>
                                              showLibraryCatalogSearchDialog(
                                                context,
                                                fontScale: _viewerFontScale,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _SearchField(
                                      controller: _searchController,
                                      focusNode: _searchFocusNode,
                                      onChanged: _setSearchQuery,
                                      onSubmitted: (_) =>
                                          _applySearchQueryFromField(),
                                      onApply: _applySearchQueryFromField,
                                      onClear: _clearSearchQuery,
                                    ),
                                    const SizedBox(height: 10),
                                    _TabSelector(
                                      selectedTab: _tab,
                                      onChanged: _setTab,
                                    ),
                                    const SizedBox(height: 10),
                                    if (_tab == _LibraryTab.books) ...[
                                      _AlphabetStrip(
                                        selectedInitialLetter:
                                            _selectedInitialLetter,
                                        availableInitialLetters:
                                            _availableInitialLetters,
                                        onChanged: _setInitialLetter,
                                      ),
                                      const SizedBox(height: 10),
                                      _ViewToggleRow(
                                        view: _view,
                                        onViewChanged: _setView,
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        child: switch (_tab) {
                                          _LibraryTab.books => _LibraryPane(
                                            key: const ValueKey('books'),
                                            books: _filteredBooks,
                                            selectedBookId: _selectedBookId,
                                            view: _view,
                                            onSelectBook: _selectBook,
                                            isEmptyMessage:
                                                _booksEmptyMessage(),
                                          ),
                                          _LibraryTab.recent => _RecentPane(
                                            key: const ValueKey('recent'),
                                            books: _recentBooks,
                                            selectedBookId: _selectedBookId,
                                            onSelectBook: _selectBook,
                                            isEmptyMessage:
                                                _booksEmptyMessage(),
                                          ),
                                        },
                                      ),
                                    ),
                                  ],
                                );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
