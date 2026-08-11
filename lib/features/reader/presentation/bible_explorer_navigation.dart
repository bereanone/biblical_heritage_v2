// ignore_for_file: invalid_use_of_protected_member

part of 'bible_explorer_screen.dart';

extension _BibleExplorerScreenNavigation on _BibleExplorerScreenState {
  Future<void> _openCrossReferences(VerseLine line) async {
    if (crossReferenceTapStopsAutoscroll(
      tiltAutoscrollActive: _tiltAutoScroll.isActive,
      steadyAutoscrollActive: _macAutoScroll?.isActive ?? false,
    )) {
      _macAutoScroll?.stopForManualInteraction();
      _tiltAutoScroll.stopForManualInteraction();
      return;
    }
    final sourceBlockId = line.blockId;
    if (sourceBlockId == null || sourceBlockId <= 0) return;
    final bookName = _bookNames[line.bookNumber] ?? 'Book ${line.bookNumber}';
    final targetBlockId = await showCrossReferencePanel(
      context: context,
      sourceVerseId: sourceBlockId,
      sourceReference: '$bookName ${line.chapter}:${line.verse}',
    );
    if (targetBlockId == null || targetBlockId == sourceBlockId || !mounted) {
      return;
    }
    await HistoryLogService.instance.insertHistory(sourceBlockId);
    if (!mounted) return;
    setState(() => _crossReferenceReturnBlockIds.add(sourceBlockId));
    await _navigateToBlockId(targetBlockId, recordHistory: false);
  }

  Future<void> _initializeViewer() async {
    if (mounted) {
      setState(() {
        _viewerStatus = 'Loading Bible Explorer...';
        _viewerLoadError = null;
      });
    }
    try {
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
        _viewerStatus = 'Bible Explorer loaded.';
        _viewerLoadError = null;
        _navigationTick += 1;
      });
      _liveVisibleLocation.updateSelected(
        BibleVisibleLocation(
          blockId: targetBlockId,
          bookNumber: targetBook,
          chapter: targetChapter,
          verse: targetVerse,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _viewerReady = false;
        _anchorBlockId = null;
        _selectedBlockId = null;
        _viewerStatus = 'Bible Explorer could not finish loading.';
        _viewerLoadError = error.toString();
      });
    }
  }

  void _handleVisibleBlockChanged(int blockId) {
    final line = _viewerData.getBlock(blockId);
    if (line == null) return;
    final session = _activeBibleSearchSession;
    if (session != null && session.results.isNotEmpty) {
      final currentResult = session.currentResult;
      final isCurrentSearchResultVerse =
          currentResult.bookNumber == line.bookNumber &&
          currentResult.chapter == line.chapter &&
          currentResult.verse == line.verse;
      if (_isBibleSearchNavigationActive && isCurrentSearchResultVerse) {
        _isBibleSearchNavigationActive = false;
      } else if (!_isBibleSearchNavigationActive &&
          !isCurrentSearchResultVerse) {
        setState(() {
          _activeBibleSearchSession = null;
        });
      }
    }
    if (!mounted) return;
    final location = BibleVisibleLocation(
      blockId: blockId,
      bookNumber: line.bookNumber,
      chapter: line.chapter,
      verse: line.verse,
    );
    _liveVisibleLocation.updateCentered(location);
    if (_liveVisibleLocation.selected != null) return;
    _bookNumber = line.bookNumber;
    _chapter = line.chapter;
    _verse = line.verse;
    _locationPersistence.update(
      location,
      persistenceSuspended:
          _tiltAutoScroll.isActive || (_macAutoScroll?.isActive ?? false),
    );
  }

  Future<void> _navigateToBlockId(
    int blockId, {
    required bool recordHistory,
    bool preserveBibleSearchSession = false,
  }) async {
    final reference = await StudyBibleDatabase.instance.loadReferenceForBlockId(
      blockId,
    );
    if (reference == null || !mounted) return;

    await _viewerData.ensureWindow(blockId);
    if (!mounted) return;
    setState(() {
      if (!preserveBibleSearchSession) {
        _activeBibleSearchSession = null;
        _isBibleSearchNavigationActive = false;
      }
      _bookNumber = reference.bookNumber;
      _chapter = reference.chapter;
      _verse = reference.verse;
      _anchorBlockId = blockId;
      _selectedBlockId = blockId;
      _navigationTick += 1;
    });
    final location = BibleVisibleLocation(
      blockId: blockId,
      bookNumber: reference.bookNumber,
      chapter: reference.chapter,
      verse: reference.verse,
    );
    _liveVisibleLocation.updateSelected(location);
    _locationPersistence.update(location, persistenceSuspended: false);
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
      lastSearchTerm: _activeBibleSearchSession?.query ?? _lastSearchTerm,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _lastSearchTerm = selection.lastSearchTerm;
      _activeBibleSearchSession = selection.bibleSearchSession;
    });
    final searchSession = selection.bibleSearchSession;
    if (searchSession != null) {
      unawaited(
        AppSettingsService.instance.saveLastBibleSearchSessionJson(
          BibleSearchSessionSnapshot.fromSession(searchSession).toJsonString(),
        ),
      );
    }
    await _openBibleSearchBlock(selection.blockId);
  }

  Future<void> _navigateBibleSearchHit(int delta) async {
    final session = _activeBibleSearchSession;
    if (session == null || session.results.isEmpty) return;
    if (delta > 0 && !session.hasNext) return;
    if (delta < 0 && !session.hasPrevious) return;

    final nextIndex = session.currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= session.results.length) return;

    final nextSession = session.copyWithIndex(nextIndex);
    final nextResult = session.results[nextIndex];
    if (!mounted) return;
    setState(() {
      _activeBibleSearchSession = nextSession;
      _lastSearchTerm = nextSession.query;
    });
    unawaited(
      AppSettingsService.instance.saveLastBibleSearchSessionJson(
        BibleSearchSessionSnapshot.fromSession(nextSession).toJsonString(),
      ),
    );
    await _openBibleSearchBlock(nextResult.blockId);
  }

  Future<void> _openTopics(BuildContext context) async {
    _resetRapidTagArmed();
    final blockId = await showViewerTopicPicker(context, fontScale: _fontScale);
    if (blockId == null || !mounted) return;
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _openBlockId(
    int blockId, {
    bool preserveBibleSearchSession = false,
  }) async {
    _resetRapidTagArmed();
    await _navigateToBlockId(
      blockId,
      recordHistory: true,
      preserveBibleSearchSession: preserveBibleSearchSession,
    );
  }

  Future<void> _openBibleSearchBlock(int blockId) async {
    _isBibleSearchNavigationActive = true;
    await _openBlockId(blockId, preserveBibleSearchSession: true);
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
    final location = BibleVisibleLocation(
      blockId: blockId,
      bookNumber: _bookNumber,
      chapter: _chapter,
      verse: _verse,
    );
    _locationPersistence.update(location, persistenceSuspended: false);
    await _locationPersistence.flush();
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
      onApplyDefaultMarkup: _applyDefaultMarkup,
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
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => LibraryScreen(
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

  Future<void> _openSavedPresentations() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TagSavedPresentationsScreen(),
      ),
    );
  }
}
