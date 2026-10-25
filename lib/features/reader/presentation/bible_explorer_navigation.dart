// ignore_for_file: invalid_use_of_protected_member

part of 'bible_explorer_screen.dart';

extension _BibleExplorerScreenNavigation on _BibleExplorerScreenState {
  // Silent chapter navigation is independent of audio transport.
  Future<void> _skipReaderChapter(bool forward) async {
    if (!mounted ||
        _bundledSkipInProgress ||
        (_macAutoScroll?.isScrolling ?? false)) {
      return;
    }
    final current = _liveVisibleLocation.value;
    if (current == null) return;
    setState(() => _bundledSkipInProgress = true);
    try {
      final target = await loadBiblePlaybackSkipTarget(
        await StudyBibleDatabase.instance.bible,
        current: current,
        loop: BibleLoopUnit.chapter,
        forward: forward,
      );
      if (target == null ||
          !mounted ||
          (_macAutoScroll?.isScrolling ?? false)) {
        return;
      }
      await _navigateToBlockId(target.blockId, recordHistory: true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change chapter. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _bundledSkipInProgress = false);
    }
  }

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
      fontScale: _fontScale,
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
      unawaited(_adoptNativeWatchPlayback());
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
    if (_narrationRunning) return;
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
    ViewerReaderScrollPosition? restoreScrollPosition,
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
      _readerRestoreScrollPosition = restoreScrollPosition;
      // A deliberate jump leaves Greek/Hebrew study mode. Scrolling through
      // the current passage does not call this method, so it stays available
      // while the reader is studying that passage.
      _interlinearEnabled = false;
      _selectedMappedBlockId = null;
      _selectedMappedTokenIndex = null;
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

  Future<void> _openMappedPhrase(
    VerseLine line,
    ViewerMappedPhrase phrase,
  ) async {
    final blockId = line.blockId;
    if (blockId == null) return;
    final strongs = phrase.strongs
        .map(normalizeStrongsCanonical)
        .whereType<String>()
        .toList(growable: false);
    if (strongs.isEmpty) return;
    _stopReaderAutoscroll();
    String? chosen = strongs.singleOrNull;
    if (chosen == null) {
      final entries = await Future.wait(
        strongs.map((id) => const ViewerStrongsRepository().loadEntry(id)),
      );
      if (!mounted) return;
      chosen = selectPrimaryStrongsSource(entries);
      chosen ??= await showDialog<String>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('Sources for “${phrase.text}”'),
          children: [
            for (var index = 0; index < strongs.length; index++)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(strongs[index]),
                child: Text(
                  '${strongs[index]} · '
                  '${entries[index]?.lemma ?? 'Source entry'}',
                ),
              ),
          ],
        ),
      );
    }
    if (chosen == null || !mounted) return;
    final morphology = await const ViewerStrongsRepository().loadMorphologyTag(
      blockId: blockId,
      mappedTokenIndex: phrase.tokenIndex,
    );
    if (!mounted) return;
    setState(() {
      _selectedMappedBlockId = blockId;
      _selectedMappedTokenIndex = phrase.tokenIndex;
    });
    final source = _LexicalSourceContext(
      blockId: blockId,
      reference:
          '${_bookNames[line.bookNumber] ?? 'Book ${line.bookNumber}'} '
          '${line.chapter}:${line.verse}',
      phrase: phrase.text,
      tokenIndex: phrase.tokenIndex,
      strongsId: chosen,
      alternateStrongsIds: strongs,
      morphologyTag: morphology,
      readerPosition: _latestReaderScrollPosition,
    );
    await _showLexicalSource(source);
    if (!mounted) return;
    setState(() {
      _selectedMappedBlockId = null;
      _selectedMappedTokenIndex = null;
    });
  }

  Future<void> _showLexicalSource(
    _LexicalSourceContext source, {
    bool startOnOccurrences = false,
  }) {
    var activeSource = source;
    return showViewerStrongsPageOne(
      context,
      strongsId: source.strongsId,
      alternateStrongsIds: source.alternateStrongsIds,
      onStrongsChanged: (id) => activeSource = source.withStrongsId(id),
      mappedPhrase: source.phrase,
      morphologyTag: source.morphologyTag,
      startOnOccurrences: startOnOccurrences,
      occurrenceViewState: source.occurrenceState,
      initialPanelScrollOffset: source.panelScrollOffset,
      onSelectCitation: (blockId, panelScrollOffset) => unawaited(
        _openLexicalCitation(
          activeSource.withPanelScrollOffset(panelScrollOffset),
          blockId,
        ),
      ),
      onSelectBlockId: (blockId) => unawaited(_openBlockId(blockId)),
      onSelectOccurrence: (blockId, state) => unawaited(
        _openLexicalOccurrence(
          activeSource.withOccurrenceState(state),
          blockId,
        ),
      ),
    );
  }

  Future<void> _openLexicalOccurrence(
    _LexicalSourceContext source,
    int blockId,
  ) async {
    if (!mounted) return;
    setState(() => _lexicalReturnContext = source);
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _openLexicalCitation(
    _LexicalSourceContext source,
    int blockId,
  ) async {
    if (!mounted) return;
    setState(() => _lexicalReturnContext = source);
    await _navigateToBlockId(blockId, recordHistory: true);
  }

  Future<void> _returnToLexicalSource() async {
    final source = _lexicalReturnContext;
    if (source == null) return;
    await _navigateToBlockId(
      source.blockId,
      recordHistory: false,
      restoreScrollPosition: source.readerPosition,
    );
    if (!mounted) return;
    setState(() {
      _lexicalReturnContext = null;
      _interlinearEnabled = true;
      _selectedMappedBlockId = source.blockId;
      _selectedMappedTokenIndex = source.tokenIndex;
    });
    await _showLexicalSource(
      source,
      startOnOccurrences: source.returnToOccurrences,
    );
    if (!mounted) return;
    setState(() {
      _selectedMappedBlockId = null;
      _selectedMappedTokenIndex = null;
    });
  }

  Future<void> _openReferencePicker(BuildContext context) async {
    _resetRapidTagArmed();
    final selection = await showViewerReferencePicker(
      context,
      initialBookNumber: _bookNumber,
      initialChapter: _chapter,
      initialVerse: _verse,
      largerPhoneControls:
          Platform.isIOS && MediaQuery.sizeOf(context).shortestSide < 600,
      fontScale: _fontScale,
      fontScaleListenable: _referencePickerFontScale,
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
    _referencePickerFontScale.value = _fontScale;
  }

  Future<void> _loadInterlinearSettings() async {
    final settings = await AppSettingsService.instance
        .loadInterlinearSettings();
    if (!mounted) return;
    setState(() {
      // Study mode is opt-in for each reader session, even if an older build
      // saved its enabled state. Keep the user's display preferences only.
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
      onOpenAudioSettings: _macAutoScroll == null
          ? null
          : _openBibleAudioSettings,
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

  Future<void> _reloadDefaultHighlight() async {
    final id = await AppSettingsService.instance.loadDefaultHighlightGroupId();
    final groups = await HighlightGroupsRepository().loadGroups();
    if (!mounted) return;
    final group =
        groups.where((group) => group.id == id).firstOrNull ??
        (id == null ? groups.firstOrNull : null);
    setState(() {
      _defaultHighlightGroup = group;
      _defaultHighlightGroupId = group?.id;
    });
  }

  Future<void> _openMarkupSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MarkupSettingsScreen()),
    );
    await _reloadDefaultHighlight();
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
