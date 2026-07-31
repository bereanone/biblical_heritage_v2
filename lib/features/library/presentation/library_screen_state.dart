part of 'library_screen.dart';

class _LibraryScreenState extends State<LibraryScreen> with RouteAware {
  static const Set<String> _supportedCollectionFilterValues = <String>{
    'egw_books',
    'egw_devotionals',
    'egw_commentaries',
    'egw_misc_collections',
    'egw_pamphlets',
    'egw_periodicals',
    'egw_manuscript_releases',
    'adventist_pioneer_library',
  };

  final _service = LibraryCatalogService.instance;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  // Large/compact/keyboard-open layouts place the search field at different
  // positions in the widget tree. A stable GlobalKey lets Flutter relocate
  // its Element (and the EditableText's live input connection) across those
  // positions instead of disposing and recreating it, which would otherwise
  // close the on-screen keyboard mid-focus.
  final GlobalKey _searchFieldKey = GlobalKey();
  LibraryRootSelection? _selection;
  bool _loading = true;
  String _loadingStatus = 'Loading library...';
  String? _loadingError;
  _LibraryTab _tab = _LibraryTab.books;
  _LibraryView _view = _LibraryView.shelf;
  double _viewerFontScale = 1.3;
  String _fileTypeFilter = libraryMediaFilterAll;
  String _collectionFilter = 'all';
  String _searchQuery = '';
  String? _selectedInitialLetter;
  String? _selectedBookId;
  List<LibraryCatalogItem> _items = const [];
  PioneerCapturedHtmlAvailableImportReport? _captureImportReport;
  bool _loadingCaptureImports = false;
  bool _captureImportDialogVisible = false;
  PageRoute<dynamic>? _observedRoute;

  // Compact-layout secondary control collapse (see build()). Secondary
  // controls hide on downward scroll and restore on upward scroll once the
  // accumulated delta crosses a hysteresis threshold, to avoid jitter.
  bool _secondaryControlsCollapsed = false;
  double _scrollHysteresisAccumulator = 0;
  bool _wasCompactLayout = false;
  // macOS enforces a 900x700 minimum window size (MainFlutterWindow.swift),
  // which leaves ~568 logical px of height for this LayoutBuilder at the
  // smallest window the OS allows. The height threshold must sit above
  // that floor or the compact layout would be unreachable by resizing a
  // macOS window at all, even at the smallest size a user can drag to.
  static const double _kCompactHeightThreshold = 650;
  static const double _kCompactWidthThreshold = 640;
  static const double _kScrollCollapseThreshold = 28;

  @override
  void initState() {
    super.initState();
    final initialReport = widget.initialCapturedImportReport;
    if (initialReport != null) {
      _captureImportReport = initialReport;
      _loading = false;
      _loadingStatus = 'Library loaded.';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !initialReport.hasAvailableImports) {
          return;
        }
        unawaited(_showCaptureImportOffer(initialReport));
      });
      return;
    }
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && route != _observedRoute) {
      if (_observedRoute != null) {
        appRouteObserver.unsubscribe(this);
      }
      _observedRoute = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _observedRoute = null;
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didPopNext() {
    unawaited(_reloadItems());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadingStatus = 'Loading library...';
        _loadingError = null;
      });
    }
    try {
      final selection = await LibraryRootService.instance.loadSelection();
      final viewerFontScale = await AppSettingsService.instance
          .loadViewerFontScale();
      final fileTypeFilter = normalizeLibraryMediaFilter(
        await AppSettingsService.instance.loadElibraryMediaFilter(),
      );
      var items = await _service.loadItems();
      final hasCommentaryItems = items.any(
        (item) => item.collectionGroupKey == 'egw_commentaries',
      );
      if (!hasCommentaryItems && selection.exists) {
        await _service.refreshManagedItemsFromDisk();
        items = await _service.loadItems();
      }
      if (!mounted) return;
      setState(() {
        _selection = selection;
        _items = items;
        _viewerFontScale = viewerFontScale;
        _fileTypeFilter = fileTypeFilter;
        _loading = false;
        _loadingStatus = 'Library loaded.';
        _loadingError = null;
      });
      await _syncSelectionAndNavigation(
        _filteredBooks,
        preferExistingSelection: false,
      );
      await _refreshCaptureImportReport(promptOnDiscovery: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingStatus = 'Library could not finish loading.';
        _loadingError = error.toString();
      });
    }
  }

  Future<void> _reloadItems() async {
    final items = await _service.loadItems();
    if (!mounted) return;
    setState(() => _items = items);
    await _refreshCaptureImportReport(promptOnDiscovery: false);
    await _syncSelectionAndNavigation(
      _filteredBooks,
      preferExistingSelection: true,
    );
  }

  Future<void> _refreshCaptureImportReport({
    required bool promptOnDiscovery,
  }) async {
    if (shouldSkipCaptureClipperStartupScan()) {
      if (mounted) setState(() => _loadingCaptureImports = false);
      debugPrint(
        'CaptureClipper library availability scan skipped by development override.',
      );
      return;
    }
    if (mounted) {
      setState(() => _loadingCaptureImports = true);
    }
    try {
      final report =
          await (widget.capturedImportAvailabilityLoader ??
              _defaultCapturedImportAvailabilityLoader)();
      if (!mounted) return;
      setState(() {
        _captureImportReport = report;
        _loadingCaptureImports = false;
      });
      if (promptOnDiscovery && report.hasAvailableImports) {
        await _showCaptureImportOffer(report);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCaptureImports = false;
      });
      debugPrint('CaptureClipper import discovery failed: $error');
    }
  }

  void _openCaptureImports() {
    unawaited(_handleOpenCaptureImports());
  }

  Future<void> _handleOpenCaptureImports() async {
    final report = _captureImportReport;
    if (report == null || !report.hasAvailableImports) {
      await _refreshCaptureImportReport(promptOnDiscovery: false);
    }
    if (!mounted) return;
    final refreshedReport = _captureImportReport;
    if (refreshedReport == null || !refreshedReport.hasAvailableImports) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No CaptureClipper imports are currently available.'),
        ),
      );
      return;
    }
    await _showCaptureImportOffer(refreshedReport);
  }

  Future<void> _showCaptureImportOffer(
    PioneerCapturedHtmlAvailableImportReport report,
  ) async {
    if (_captureImportDialogVisible ||
        !mounted ||
        !report.hasAvailableImports) {
      return;
    }
    final availableImports = report.imports;
    _captureImportDialogVisible = true;
    List<String>? selectedPaths;
    try {
      selectedPaths = await showDialog<List<String>?>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final selected = <String>{
            for (final candidate in availableImports) candidate.folderPath,
          };
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final title = availableImports.length == 1
                  ? '1 CaptureClipper book is ready to import'
                  : '${availableImports.length} CaptureClipper books are ready to import';
              final subtitle = availableImports.length == 1
                  ? '${availableImports.first.folderName}. Import now?'
                  : 'Select one or more books to import.';
              return AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: 520,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subtitle),
                        const SizedBox(height: 12),
                        if (availableImports.length > 1)
                          ...availableImports.map(
                            (candidate) => CheckboxListTile(
                              value: selected.contains(candidate.folderPath),
                              onChanged: (checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    selected.add(candidate.folderPath);
                                  } else {
                                    selected.remove(candidate.folderPath);
                                  }
                                });
                              },
                              title: Text(candidate.displayLabel),
                              subtitle: Text(candidate.author),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                            ),
                          )
                        else
                          Text(
                            availableImports.single.displayLabel,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        const SizedBox(height: 8),
                        const Text(
                          'You can import later from the Capture Imports button.',
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Not Now'),
                  ),
                  FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.of(
                            dialogContext,
                          ).pop(selected.toList(growable: false)),
                    child: const Text('Import'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      if (mounted) {
        setState(() => _captureImportDialogVisible = false);
      } else {
        _captureImportDialogVisible = false;
      }
    }
    if (selectedPaths == null || selectedPaths.isEmpty || !mounted) {
      return;
    }
    try {
      final report = await PioneerCapturedHtmlImportFolderService.instance
          .importConfiguredCloudFolder(selectedFolderPaths: selectedPaths);
      if (!mounted) return;
      final importedCount = report.importedCount + report.repairedCount;
      final skippedCount = report.skippedCount;
      PioneerCapturedHtmlCloudFolderImportEntry? failedEntry;
      PioneerCapturedHtmlCloudFolderImportEntry? skippedEntry;
      for (final entry in report.entries) {
        if (failedEntry == null && entry.importStatus?.name == 'failed') {
          failedEntry = entry;
        }
        if (skippedEntry == null &&
            entry.importStatus?.name == 'skippedExisting') {
          skippedEntry = entry;
        }
      }
      await _reloadItems();
      String message;
      if (importedCount > 0) {
        message =
            'Imported $importedCount CaptureClipper book${importedCount == 1 ? '' : 's'}.';
      } else if (failedEntry != null) {
        final label = '${failedEntry.folderName} — ${failedEntry.title}';
        final reason = failedEntry.reason?.trim().isNotEmpty == true
            ? failedEntry.reason!.trim()
            : 'Unknown reason';
        message = 'CaptureClipper import failed for $label: $reason';
      } else if (skippedEntry != null) {
        final label = '${skippedEntry.folderName} — ${skippedEntry.title}';
        final reason = skippedEntry.reason?.trim().isNotEmpty == true
            ? skippedEntry.reason!.trim()
            : 'Already imported';
        message = 'Already imported: $label. $reason';
      } else if (skippedCount > 0) {
        message = 'No new CaptureClipper imports were needed.';
      } else {
        message = 'No CaptureClipper import folders were selected.';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CaptureClipper import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _captureImportDialogVisible = false);
      }
      await _refreshCaptureImportReport(promptOnDiscovery: false);
    }
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
    final resolvedItem = await _service.loadItemById(item.id) ?? item;
    if (!mounted) return;
    if (!await ensureLibraryItemOpenable(context, resolvedItem)) return;
    if (!mounted) return;
    final initialHref = _initialBookHref(resolvedItem);
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: resolvedItem,
          initialHref: initialHref,
          onReturnToBible: _returnToBibleFromBookReader,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
    if (!mounted) return;
    await _reloadItems();
  }

  void _returnToBibleFromBookReader() {
    final navigator = Navigator.of(context, rootNavigator: true);
    final openBible = widget.onOpenBible;
    if (openBible != null) {
      if (navigator.canPop()) {
        navigator.pop();
      }
      openBible();
      return;
    }

    if (navigator.canPop()) {
      navigator.pop();
    }
    if (navigator.canPop()) {
      navigator.pop();
    }
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
    // Only a position saved by an actual open counts; a stray epub_href on a
    // never-opened item must not override the reader's first-open defaults
    // (devotional current-date entry, front-matter skipping).
    if (item.lastOpened == null) return null;
    final savedHref = item.epubHref?.trim() ?? '';
    if (savedHref.isNotEmpty) return savedHref;

    return null;
  }

  Future<void> _setFileTypeFilter(String value) async {
    final normalizedValue = normalizeLibraryMediaFilter(value);
    if (_fileTypeFilter == normalizedValue) return;
    setState(() {
      _fileTypeFilter = normalizedValue;
      _selectedInitialLetter = null;
      _tab = _LibraryTab.books;
    });
    await AppSettingsService.instance.saveElibraryMediaFilter(normalizedValue);
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
    _searchFocusNode.unfocus();
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

  // Collapses/restores the compact-layout secondary control panel based on
  // book-list scroll direction, with a pixel threshold (hysteresis) so small
  // back-and-forth movements don't cause jitter. Snapping back to the top
  // always restores the full controls immediately.
  bool _handleBookListScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification) return false;
    final metrics = notification.metrics;
    if (metrics.pixels <= metrics.minScrollExtent + 1) {
      _scrollHysteresisAccumulator = 0;
      if (_secondaryControlsCollapsed) {
        setState(() => _secondaryControlsCollapsed = false);
      }
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta == 0) return false;
    if (delta > 0) {
      _scrollHysteresisAccumulator = _scrollHysteresisAccumulator < 0
          ? delta
          : _scrollHysteresisAccumulator + delta;
    } else {
      _scrollHysteresisAccumulator = _scrollHysteresisAccumulator > 0
          ? delta
          : _scrollHysteresisAccumulator + delta;
    }
    if (_scrollHysteresisAccumulator >= _kScrollCollapseThreshold &&
        !_secondaryControlsCollapsed) {
      _scrollHysteresisAccumulator = 0;
      setState(() => _secondaryControlsCollapsed = true);
    } else if (_scrollHysteresisAccumulator <= -_kScrollCollapseThreshold &&
        _secondaryControlsCollapsed) {
      _scrollHysteresisAccumulator = 0;
      setState(() => _secondaryControlsCollapsed = false);
    }
    return false;
  }

  Future<void> _selectBook(LibraryCatalogItem item) async {
    setState(() => _selectedBookId = item.id);
    final availability = libraryItemAvailability(item);
    if (!availability.isAvailable) {
      await _handleUnavailableBookSelected(item, availability);
      return;
    }
    await _openBookReader(item);
  }

  Future<void> _handleUnavailableBookSelected(
    LibraryCatalogItem item,
    LibraryItemAvailability availability,
  ) async {
    final canRetry = libraryItemSupportsRetryDownload(item);
    final action = await showLibraryUnavailableBookDialog(
      context,
      item: item,
      availability: availability,
      canRetry: canRetry,
    );
    if (!mounted ||
        action != LibraryUnavailableBookDialogAction.retryDownload) {
      return;
    }
    await _retryUnavailableBookDownload(item);
  }

  Future<void> _retryUnavailableBookDownload(LibraryCatalogItem item) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Retrying download for "${item.displayTitle}"…')),
    );
    LibraryItemRetryDownloadResult result;
    try {
      result = await LibraryItemRetryDownloadService.instance.retry(
        libraryItemId: item.id,
        collectionName: item.collectionName ?? '',
        relativePath: item.relativePath,
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Retry failed: $error')));
      return;
    }
    if (!mounted) return;
    await _reloadItems();
    if (!mounted) return;
    if (result.succeeded) {
      messenger.showSnackBar(
        SnackBar(content: Text('"${item.displayTitle}" is now available.')),
      );
      final refreshed = _firstWhereOrNull(_items, (i) => i.id == item.id);
      if (refreshed != null) {
        await _openBookReader(refreshed);
      }
      return;
    }
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'The retry did not produce a readable copy. The source may still '
          'be unavailable.',
        ),
      ),
    );
  }

  List<LibraryCatalogItem> get _filteredBooks {
    final query = compactLibrarySearchText(_searchQuery);
    final initial = query.isEmpty
        ? _selectedInitialLetter?.trim().toUpperCase()
        : null;
    final sortByAuthorFirst =
        _collectionFilter.trim().toLowerCase() == 'adventist_pioneer_library';
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
    filtered.sort(
      (a, b) =>
          _compareBooksForShelf(a, b, sortByAuthorFirst: sortByAuthorFirst),
    );
    return filtered;
  }

  List<LibraryCatalogItem> get _recentBooks {
    return selectRecentLibraryItems(_items, searchQuery: _searchQuery);
  }

  String _recentEmptyMessage() {
    if (_searchQuery.trim().isNotEmpty) {
      return 'No recently opened items match "${_searchQuery.trim()}".';
    }
    return 'No recently opened items yet. Books you open will appear here.';
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
    final discovered = buildLibraryCollectionFilterOptions(_items)
        .where(
          (option) =>
              option.value == 'all' ||
              _supportedCollectionFilterValues.contains(option.value),
        )
        .toList(growable: false);
    final hasCommentaries = discovered.any(
      (option) => option.value == 'egw_commentaries',
    );
    if (hasCommentaries) {
      return discovered;
    }
    return <LibraryCollectionFilterOption>[
      ...discovered,
      const LibraryCollectionFilterOption(
        value: 'egw_commentaries',
        label: 'EGW Commentaries',
      ),
    ];
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

  int _compareBooksForShelf(
    LibraryCatalogItem a,
    LibraryCatalogItem b, {
    required bool sortByAuthorFirst,
  }) {
    if (sortByAuthorFirst) {
      final authorCompare = _naturalCompare(a.displayAuthor, b.displayAuthor);
      if (authorCompare != 0) return authorCompare;
    }
    final titleCompare = _naturalCompare(
      _sortableTitle(a.displayTitle),
      _sortableTitle(b.displayTitle),
    );
    if (titleCompare != 0) return titleCompare;
    final authorCompare = _naturalCompare(a.displayAuthor, b.displayAuthor);
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
    final collectionOptions = _availableCollectionFilters;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

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
                  selection: selection,
                  captureImportReport: _captureImportReport,
                  captureImportLoading: _loadingCaptureImports,
                  onOpenBible: _openBibleApp,
                  onOpenLibraryRootSetup: _openLibraryRootSetup,
                  onOpenELibrarySetup: _openELibrarySetup,
                  onRefresh: _refreshFolders,
                  onOpenCaptureImports: _openCaptureImports,
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
                          final useKeyboardScrollablePhoneLayout =
                              constraints.maxWidth < 600 && keyboardInset > 0;
                          final isCompact =
                              constraints.maxHeight <
                                  _kCompactHeightThreshold ||
                              constraints.maxWidth < _kCompactWidthThreshold;
                          if (isCompact != _wasCompactLayout) {
                            _wasCompactLayout = isCompact;
                            if (isCompact && _secondaryControlsCollapsed) {
                              _scrollHysteresisAccumulator = 0;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (!mounted) return;
                                setState(
                                  () => _secondaryControlsCollapsed = false,
                                );
                              });
                            }
                          }

                          final catalogPane = AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: switch (_tab) {
                              _LibraryTab.books => _LibraryPane(
                                key: const ValueKey('books'),
                                books: _filteredBooks,
                                selectedBookId: _selectedBookId,
                                view: _view,
                                onSelectBook: _selectBook,
                                isEmptyMessage: _booksEmptyMessage(),
                              ),
                              _LibraryTab.recent => _RecentPane(
                                key: const ValueKey('recent'),
                                books: _recentBooks,
                                selectedBookId: _selectedBookId,
                                onSelectBook: _selectBook,
                                isEmptyMessage: _recentEmptyMessage(),
                              ),
                            },
                          );

                          final titleFilterRow = Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
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
                                  onSelected: _handleCollectionFilterSelected,
                                ),
                              ),
                              _FileTypeFilterMenu(
                                currentValue: _fileTypeFilter,
                                onSelected: _setFileTypeFilter,
                              ),
                              _SearchTextButton(
                                onPressed: () => showLibraryCatalogSearchDialog(
                                  context,
                                  fontScale: _viewerFontScale,
                                  onReturnToBible: _returnToBibleFromBookReader,
                                ),
                              ),
                            ],
                          );

                          // Full, non-collapsing control set used both by the
                          // keyboard-open phone layout (scrolls as one unit
                          // with the results) and by large/tall layouts
                          // (stays fixed above an independently-scrolling
                          // results area — see the `!isCompact` branch below).
                          final catalogControls = <Widget>[
                            titleFilterRow,
                            const SizedBox(height: 10),
                            _SearchField(
                              key: _searchFieldKey,
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: _setSearchQuery,
                              onSubmitted: (_) => _applySearchQueryFromField(),
                              onApply: _applySearchQueryFromField,
                              onClear: _clearSearchQuery,
                            ),
                            const SizedBox(height: 10),
                            _TabSelector(selectedTab: _tab, onChanged: _setTab),
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
                          ];

                          if (_loading) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text(
                                          _loadingStatus,
                                          textAlign: TextAlign.center,
                                        ),
                                        if (_loadingError != null) ...[
                                          const SizedBox(height: 12),
                                          SelectableText(
                                            _loadingError!,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: theme.colorScheme.error,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 16),
                                        Wrap(
                                          spacing: 12,
                                          runSpacing: 12,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            FilledButton(
                                              onPressed: _load,
                                              child: const Text('Retry'),
                                            ),
                                            OutlinedButton(
                                              onPressed: _openELibrarySetup,
                                              child: const Text(
                                                'Open eLibrary Setup',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }

                          if (useKeyboardScrollablePhoneLayout) {
                            // A focused text field must stay reachable above
                            // the keyboard, so controls and results scroll
                            // together as a single unit here.
                            return CustomScrollView(
                              key: const ValueKey('library-standard-layout'),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.manual,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: catalogControls,
                                  ),
                                ),
                                SliverFillRemaining(
                                  hasScrollBody: false,
                                  child: SizedBox(
                                    height: constraints.maxHeight
                                        .clamp(180.0, 360.0)
                                        .toDouble(),
                                    child: catalogPane,
                                  ),
                                ),
                              ],
                            );
                          }

                          if (!isCompact) {
                            // Enough vertical space: keep every control
                            // fixed and permanently visible; only the
                            // book-results area scrolls.
                            return Column(
                              key: const ValueKey('library-standard-layout'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ...catalogControls,
                                Expanded(child: catalogPane),
                              ],
                            );
                          }

                          // Short or narrow layout: a compact sticky toolbar
                          // (collection, search access, Books/Recent,
                          // Shelf/List) stays visible at all times; secondary
                          // controls (title, file-type filter, title search
                          // box, alphabet row) collapse on downward scroll
                          // and restore on upward scroll or at the top.
                          final stickyToolbar = Column(
                            key: const ValueKey('library-sticky-toolbar'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _CollectionFilterMenu(
                                      currentValue: _collectionFilter,
                                      options: collectionOptions,
                                      onSelected:
                                          _handleCollectionFilterSelected,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _SearchTextButton(
                                    onPressed: () =>
                                        showLibraryCatalogSearchDialog(
                                          context,
                                          fontScale: _viewerFontScale,
                                          onReturnToBible:
                                              _returnToBibleFromBookReader,
                                        ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _TabSelector(
                                    selectedTab: _tab,
                                    onChanged: _setTab,
                                  ),
                                  if (_tab == _LibraryTab.books)
                                    _ViewToggleRow(
                                      view: _view,
                                      onViewChanged: _setView,
                                    ),
                                ],
                              ),
                            ],
                          );

                          final secondaryControls = <Widget>[
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
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
                                _FileTypeFilterMenu(
                                  currentValue: _fileTypeFilter,
                                  onSelected: _setFileTypeFilter,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _SearchField(
                              key: _searchFieldKey,
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              onChanged: _setSearchQuery,
                              onSubmitted: (_) => _applySearchQueryFromField(),
                              onApply: _applySearchQueryFromField,
                              onClear: _clearSearchQuery,
                            ),
                            if (_tab == _LibraryTab.books) ...[
                              const SizedBox(height: 10),
                              _AlphabetStrip(
                                selectedInitialLetter: _selectedInitialLetter,
                                availableInitialLetters:
                                    _availableInitialLetters,
                                onChanged: _setInitialLetter,
                              ),
                            ],
                          ];

                          return Column(
                            key: const ValueKey('library-standard-layout'),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              stickyToolbar,
                              AnimatedSize(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                alignment: Alignment.topCenter,
                                child: _secondaryControlsCollapsed
                                    ? const SizedBox(width: double.infinity)
                                    : Padding(
                                        key: const ValueKey(
                                          'library-secondary-controls',
                                        ),
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: secondaryControls,
                                        ),
                                      ),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: NotificationListener<ScrollNotification>(
                                  onNotification:
                                      _handleBookListScrollNotification,
                                  child: catalogPane,
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
