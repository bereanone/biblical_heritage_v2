// ignore_for_file: invalid_use_of_protected_member

part of 'bible_explorer_screen.dart';

extension _BibleExplorerScreenNavigation on _BibleExplorerScreenState {
  Future<PassageData> _loadPassage() async {
    try {
      final db = StudyBibleDatabase.instance;
      final bookName = await db.loadBookName(_bookNumber);
      final centerBlockId = await db.loadBlockIdForVerse(
        bookNumber: _bookNumber,
        chapter: _chapter,
        verse: _verse,
      );
      final blocks = centerBlockId == null
          ? await db
                .loadBlocks(bookNumber: _bookNumber, chapter: _chapter)
                .timeout(const Duration(seconds: 2))
          : await db
                .loadBlockWindowById(centerBlockId)
                .timeout(const Duration(seconds: 2));
      if (blocks.isEmpty) return _fallbackPassage();

      return PassageData(
        bookNumber: _bookNumber,
        bookName: bookName ?? 'Book $_bookNumber',
        chapter: _chapter,
        lines: blocks
            .map(
              (row) => VerseLine(
                blockId: (row['id'] as int?) ?? 0,
                bookNumber: (row['book_number'] as int?) ?? _bookNumber,
                chapter: (row['chapter'] as int?) ?? _chapter,
                verse: (row['block_index'] as int?) ?? 0,
                html: (row['html'] as String?) ?? '',
                text: (row['plain_text'] as String?) ?? '',
              ),
            )
            .where(
              (line) =>
                  (line.blockId ?? 0) > 0 &&
                  line.verse > 0 &&
                  line.text.trim().isNotEmpty,
            )
            .toList(),
      );
    } catch (_) {
      return _fallbackPassage();
    }
  }

  PassageData _fallbackPassage() {
    return const PassageData(
      bookNumber: 1,
      bookName: 'Genesis',
      chapter: 1,
      lines: [
        VerseLine(
          blockId: 1,
          bookNumber: 1,
          chapter: 1,
          verse: 1,
          html: '',
          text: 'In the beginning God created the heaven and the earth.',
        ),
        VerseLine(
          blockId: 2,
          bookNumber: 1,
          chapter: 1,
          verse: 2,
          html: '',
          text:
              'And the earth was without form, and void; and darkness was upon the face of the deep.',
        ),
      ],
    );
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
    setState(() {
      _bookNumber = selection.bookNumber;
      _chapter = selection.chapter;
      _verse = selection.verse;
      _passageFuture = _loadPassage();
    });
    _recordHistory();
  }

  Future<void> _openSearch(BuildContext context) async {
    _resetRapidTagArmed();
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
    final reference = await StudyBibleDatabase.instance.loadReferenceForBlockId(
      blockId,
    );
    if (reference == null || !mounted) return;
    setState(() {
      _bookNumber = reference.bookNumber;
      _chapter = reference.chapter;
      _verse = reference.verse;
      _passageFuture = _loadPassage();
      _navigationTick += 1;
    });
    _recordHistory();
  }

  Future<void> _openBlockId(int blockId) async {
    _resetRapidTagArmed();
    final reference = await StudyBibleDatabase.instance.loadReferenceForBlockId(
      blockId,
    );
    if (reference == null || !mounted) return;
    setState(() {
      _bookNumber = reference.bookNumber;
      _chapter = reference.chapter;
      _verse = reference.verse;
      _passageFuture = _loadPassage();
      _navigationTick += 1;
    });
    _recordHistory();
  }

  Future<void> _restoreLatestHistory() async {
    final latest = await NavigationHistoryService.instance.fetchLatest();
    if (!mounted || latest == null) return;
    setState(() {
      _bookNumber = latest.book;
      _chapter = latest.chapter;
      _verse = latest.verse;
      _passageFuture = _loadPassage();
      _navigationTick += 1;
    });
  }

  Future<void> _recordHistory() async {
    final blockId = await StudyBibleDatabase.instance.loadBlockIdForVerse(
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
          final ref = references[blockId];
          if (ref == null || !mounted) return;
          setState(() {
            _bookNumber = ref.bookNumber;
            _chapter = ref.chapter;
            _verse = ref.verse;
            _passageFuture = _loadPassage();
          });
          _recordHistory();
        },
      ),
    );
  }

  Future<void> _applyDefaultMarkup() async {
    _resetRapidTagArmed();
    final groupId = _defaultHighlightGroupId;
    if (groupId == null) return;
    final passage = await _passageFuture;
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
      interlinearEnabled: _interlinearEnabled,
      onInterlinearChanged: (value) {
        if (!mounted) return;
        setState(() {
          _interlinearEnabled = value;
        });
        AppSettingsService.instance.saveInterlinearEnabled(value);
      },
      onOpenInterlinearSettings: _openInterlinearSettings,
      onOpenColorSetup: _openMarkupSettings,
      presentationAspectRatio: _presentationAspectRatio,
      onPresentationAspectRatioChanged: (preset) {
        if (!mounted) return;
        setState(() {
          _presentationAspectRatio = preset;
        });
        AppSettingsService.instance.savePresentationAspectRatioPreset(
          preset,
        );
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

  Future<void> _openMarkupSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MarkupSettingsScreen()),
    );
  }
}
