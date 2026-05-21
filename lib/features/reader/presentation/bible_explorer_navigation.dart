// ignore_for_file: invalid_use_of_protected_member

part of 'bible_explorer_screen.dart';

extension _BibleExplorerScreenNavigation on _BibleExplorerScreenState {
  Future<void> _initializeViewer() async {
    final db = StudyBibleDatabase.instance;
    final books = await db.loadBooks();
    final names = <int, String>{
      for (final book in books) book.bookNumber: book.bookName,
    };
    final latest = await NavigationHistoryService.instance.fetchLatest();
    final targetBook = latest?.book ?? _bookNumber;
    final targetChapter = latest?.chapter ?? _chapter;
    final targetVerse = latest?.verse ?? _verse;
    final targetBlockId =
        latest?.blockId ??
        await db.loadBlockIdForVerse(
          bookNumber: targetBook,
          chapter: targetChapter,
          verse: targetVerse,
        ) ??
        1;

    await _viewerData.ensureWindow(targetBlockId);
    if (!mounted) return;
    setState(() {
      _bookNames
        ..clear()
        ..addAll(names);
      _bookNumber = targetBook;
      _chapter = targetChapter;
      _verse = targetVerse;
      _anchorBlockId = targetBlockId;
      _selectedBlockId = targetBlockId;
      _viewerReady = true;
      _navigationTick += 1;
    });
  }

  void _handleVisibleBlockChanged(int blockId) {
    final pinnedBlockId = _headerPinnedBlockId;
    if (pinnedBlockId != null && blockId != pinnedBlockId) {
      return;
    }
    final line = _viewerData.getBlock(blockId);
    if (line == null) return;
    if (_bookNumber == line.bookNumber &&
        _chapter == line.chapter &&
        _verse == line.verse) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _bookNumber = line.bookNumber;
      _chapter = line.chapter;
      _verse = line.verse;
    });
  }

  Future<void> _navigateToBlockId(
    int blockId, {
    required bool recordHistory,
  }) async {
    final reference = await StudyBibleDatabase.instance.loadReferenceForBlockId(
      blockId,
    );
    if (reference == null || !mounted) return;

    await _viewerData.ensureWindow(blockId);
    if (!mounted) return;
    setState(() {
      _bookNumber = reference.bookNumber;
      _chapter = reference.chapter;
      _verse = reference.verse;
      _anchorBlockId = blockId;
      _selectedBlockId = blockId;
      _navigationTick += 1;
    });
    if (recordHistory) {
      await _recordHistory();
    }
  }

  Future<void> _openReferencePicker(BuildContext context) async {
    _resetRapidTagArmed();
    final selection = await showViewerReferencePicker(
      context,
      initialBookNumber: _bookNumber,
      initialChapter: _chapter,
      initialVerse: _verse,
    );
    if (selection == null || !mounted) return;
    final blockId = await StudyBibleDatabase.instance.loadBlockIdForVerse(
      bookNumber: selection.bookNumber,
      chapter: selection.chapter,
      verse: selection.verse,
    );
    if (blockId == null || !mounted) return;
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _openSearch(BuildContext context) async {
    _resetRapidTagArmed();
    if (!context.mounted) return;
    final ViewerSearchSelection? selection = await showViewerSearchDialog(
      context,
      fontScale: _fontScale,
      lastSearchTerm: _lastSearchTerm,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _lastSearchTerm = selection.lastSearchTerm;
    });
    await _openBlockId(selection.blockId);
  }

  Future<void> _openTopics(BuildContext context) async {
    _resetRapidTagArmed();
    final blockId = await showViewerTopicPicker(context, fontScale: _fontScale);
    if (blockId == null || !mounted) return;
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _openBlockId(int blockId) async {
    _resetRapidTagArmed();
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _recordHistory() async {
    final blockId =
        _selectedBlockId ??
        await StudyBibleDatabase.instance.loadBlockIdForVerse(
          bookNumber: _bookNumber,
          chapter: _chapter,
          verse: _verse,
        );
    if (blockId == null) return;

    await HistoryLogService.instance.insertHistory(blockId);
    await NavigationHistoryService.instance.saveSelection(
      blockId: blockId,
      book: _bookNumber,
      chapter: _chapter,
      verse: _verse,
    );
  }

  Future<void> _loadViewerSettings() async {
    final settings = await AppSettingsService.instance.loadVisualSettings(
      AppThemeMode.sepia,
    );
    if (!mounted) return;
    setState(() {
      _fontScale = settings.viewerFontScale.clamp(_minFontScale, _maxFontScale);
    });
  }

  Future<void> _loadInterlinearSettings() async {
    final enabled = await AppSettingsService.instance.loadInterlinearEnabled();
    final settings = await AppSettingsService.instance
        .loadInterlinearSettings();
    if (!mounted) return;
    setState(() {
      _interlinearEnabled = enabled;
      _interlinearSettings = settings;
    });
  }

  Future<void> _openHistory() async {
    _resetRapidTagArmed();
    final entries = await HistoryLogService.instance.fetchHistory(limit: 100);
    if (!mounted || entries.isEmpty) return;

    final references = await StudyBibleDatabase.instance
        .loadReferencesForBlockIds(
          entries.map((entry) => entry.blockId).toList(),
        );
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => ViewerHistorySheet(
        entries: entries,
        referencesByBlockId: {
          for (final entry in entries)
            entry.blockId: (() {
              final ref = references[entry.blockId];
              if (ref == null) return 'Block ${entry.blockId}';
              return '${ref.bookName} ${ref.chapter}:${ref.verse}';
            })(),
        },
        fontScale: _fontScale,
        onSelectBlockId: (blockId) {
          Navigator.of(sheetContext).pop();
          _openBlockId(blockId);
        },
      ),
    );
  }

  Future<void> _applyDefaultMarkup() async {
    _resetRapidTagArmed();
    final groupId = _defaultHighlightGroupId;
    if (groupId == null) return;
    final passage = await _currentPassageOrLoad();
    final applied = await applyDefaultMarkup(
      groupId: groupId,
      rangeSelection: _rangeSelection,
      passage: passage,
      isLineInRange: _isLineInsideMarkupRange,
      buildTokenSelections: (lines) =>
          _buildTokenHighlightSelections(lines, passage.bookName),
    );
    if (!applied || !mounted) return;
    setState(() {
      _highlightRefreshTick += 1;
      _rangeSelection = _rangeSelection.clear();
    });
  }

  Future<void> _openMode() async {
    _resetRapidTagArmed();
    await showViewerModePopup(
      context,
      themeMode: widget.themeMode,
      onThemeChanged: widget.onThemeChanged,
      onOpenBibleMemory: _openBibleMemory,
      onOpenInterlinearSettings: _openInterlinearSettings,
      onOpenColorSetup: _openMarkupSettings,
      presentationAspectRatio: _presentationAspectRatio,
      onPresentationAspectRatioChanged: (preset) {
        if (!mounted) return;
        setState(() {
          _presentationAspectRatio = preset;
        });
        AppSettingsService.instance.savePresentationAspectRatioPreset(preset);
      },
    );
  }

  Future<void> _openInterlinearSettings() async {
    final next = await showViewerInterlinearSettingsSheet(
      context,
      settings: _interlinearSettings,
    );
    if (next == null || !mounted) return;
    setState(() {
      _interlinearSettings = next;
    });
    await AppSettingsService.instance.saveInterlinearSettings(next);
  }

  Future<void> _openBibleMemory() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const BibleMemoryScreen()));
  }

  Future<void> _openLibrary() async {
    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => LibraryScreen(
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  Future<void> _openMarkupSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MarkupSettingsScreen()),
    );
  }
}
