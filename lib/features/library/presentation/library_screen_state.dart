part of 'library_screen.dart';

class _LibraryScreenState extends State<LibraryScreen> {
  final _service = LibraryCatalogService.instance;
  final TextEditingController _searchController = TextEditingController();
  LibraryRootSelection? _selection;
  bool _loading = true;
  _LibraryTab _tab = _LibraryTab.books;
  _LibraryView _view = _LibraryView.shelf;
  String _folderRootFilter = 'ePubs';
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final selection = await LibraryRootService.instance.loadSelection();
    final items = await _service.loadItems(folderRoot: _folderRootFilter);
    if (!mounted) return;
    setState(() {
      _selection = selection;
      _items = items;
      _loading = false;
    });
    await _syncSelectionAndNavigation(items, preferExistingSelection: false);
  }

  Future<void> _reloadItems() async {
    final items = await _service.loadItems(folderRoot: _folderRootFilter);
    if (!mounted) return;
    setState(() => _items = items);
    await _syncSelectionAndNavigation(items, preferExistingSelection: true);
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
        builder: (_) =>
            LibraryBookReaderScreen(item: item, initialHref: initialHref),
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
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Library folders refreshed.')));
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
    final savedHref = item.epubHref?.trim() ?? '';
    if (savedHref.isNotEmpty) return savedHref;

    return null;
  }

  Future<void> _setFolderRootFilter(String value) async {
    if (_folderRootFilter == value) return;
    setState(() {
      _folderRootFilter = value;
      _selectedInitialLetter = null;
      _tab = _LibraryTab.books;
    });
    await _reloadItems();
  }

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
    _syncInitialLetterSelection(_filteredBooks);
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
    final query = _searchQuery.trim().toLowerCase();
    final initial = _selectedInitialLetter?.trim().toUpperCase();
    final filtered = _items.where((item) {
      if (!_matchesInitialLetter(item, initial)) return false;
      if (query.isEmpty) return true;
      final haystack = [
        item.displayTitle,
        item.author ?? '',
        item.fileName,
        item.collectionName ?? '',
        item.relativePath,
        item.libraryRole ?? '',
        item.folderType ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    filtered.sort(_compareBooksForShelf);
    return filtered;
  }

  List<LibraryCatalogItem> get _recentBooks {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = _items.where((item) {
      if (query.isEmpty) return true;
      final haystack = [
        item.displayTitle,
        item.author ?? '',
        item.fileName,
        item.collectionName ?? '',
        item.relativePath,
        item.libraryRole ?? '',
        item.folderType ?? '',
      ].join(' ').toLowerCase();
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
    final title = item.displayTitle.trim();
    if (title.isEmpty) return false;
    final firstChar = title[0].toUpperCase();
    if (selectedInitialLetter == '#') {
      return RegExp(r'^[0-9]').hasMatch(title);
    }
    return firstChar == selectedInitialLetter;
  }

  List<String> get _availableInitialLetters {
    final letters = _filteredBooks
        .map((item) {
          final title = item.displayTitle.trim();
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

  void _syncInitialLetterSelection(List<LibraryCatalogItem> books) {
    final selected = _selectedInitialLetter?.trim().toUpperCase();
    if (selected == null || selected.isEmpty) {
      return;
    }
    final available = books
        .map((item) {
          final title = item.displayTitle.trim();
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
    final titleCompare = _naturalCompare(a.displayTitle, b.displayTitle);
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
    final rootLabel = _folderRootFilter == 'all' ? 'All' : _folderRootFilter;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LibraryHeader(
                hasRoot: hasRoot,
                rootPath: selection?.path,
                currentFolderFilter: _folderRootFilter,
                currentFolderLabel: rootLabel,
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
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Library',
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(width: 10),
                                  _FolderRootMenu(
                                    currentValue: _folderRootFilter,
                                    currentLabel: rootLabel,
                                    onSelected: _setFolderRootFilter,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _SearchField(
                                      controller: _searchController,
                                      onChanged: _setSearchQuery,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _TabSelector(
                                selectedTab: _tab,
                                onChanged: _setTab,
                              ),
                              const SizedBox(height: 10),
                              if (_tab == _LibraryTab.books) ...[
                                _AlphabetStrip(
                                  selectedInitialLetter: _selectedInitialLetter,
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
                                  duration: const Duration(milliseconds: 180),
                                  child: switch (_tab) {
                                    _LibraryTab.books => _LibraryPane(
                                      key: const ValueKey('books'),
                                      books: _filteredBooks,
                                      selectedBookId: _selectedBookId,
                                      view: _view,
                                      onSelectBook: _selectBook,
                                      isEmptyMessage: rootLabel == 'All'
                                          ? 'No books are indexed yet.'
                                          : 'No books found in $rootLabel.',
                                    ),
                                    _LibraryTab.recent => _RecentPane(
                                      key: const ValueKey('recent'),
                                      books: _recentBooks,
                                      selectedBookId: _selectedBookId,
                                      onSelectBook: _selectBook,
                                      isEmptyMessage:
                                          'No recent books in this filter yet.',
                                    ),
                                  },
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
      ),
    );
  }
}
