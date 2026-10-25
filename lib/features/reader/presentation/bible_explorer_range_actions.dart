// ignore_for_file: invalid_use_of_protected_member

part of 'bible_explorer_screen.dart';

extension _BibleExplorerScreenRangeActions on _BibleExplorerScreenState {
  void _clearBibleSearchSessionForManualSelection() {
    if (_activeBibleSearchSession == null && !_isBibleSearchNavigationActive) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _activeBibleSearchSession = null;
      _isBibleSearchNavigationActive = false;
    });
  }

  void _selectLine(VerseLine line) {
    _clearBibleSearchSessionForManualSelection();
    if (shouldOpenRangeActionsOnTap(_rangeSelection, line.blockId ?? 0)) {
      if (line.bookNumber != _bookNumber ||
          line.chapter != _chapter ||
          line.verse != _verse) {
        setState(() {
          _interlinearEnabled = false;
          _selectedBlockId = line.blockId;
          _bookNumber = line.bookNumber;
          _chapter = line.chapter;
          _verse = line.verse;
        });
        _publishSelectedLocation(line);
        _recordHistory();
      }
      _openRangeActions();
      return;
    }
    if (_rangeSelection.hasSelection) {
      setState(() {
        _rangeSelection = _rangeSelection.clear();
      });
    }
    if (_selectedBlockId == line.blockId &&
        line.bookNumber == _bookNumber &&
        line.chapter == _chapter &&
        line.verse == _verse) {
      return;
    }
    _resetRapidTagArmed();
    setState(() {
      _interlinearEnabled = false;
      _selectedBlockId = line.blockId;
      _bookNumber = line.bookNumber;
      _chapter = line.chapter;
      _verse = line.verse;
    });
    _publishSelectedLocation(line);
    _recordHistory();
  }

  void _publishSelectedLocation(VerseLine line) {
    final blockId = line.blockId;
    if (blockId == null || blockId <= 0) return;
    _liveVisibleLocation.updateSelected(
      BibleVisibleLocation(
        blockId: blockId,
        bookNumber: line.bookNumber,
        chapter: line.chapter,
        verse: line.verse,
      ),
    );
  }

  void _selectMarkupAnchor(VerseLine line) {
    if (_rangeSelection.hasCompletedRange) {
      final blockId = line.blockId ?? 0;
      if (blockId <= 0) return;
      setState(
        () => _rangeSelection = _rangeSelection.extendVerseRange(blockId),
      );
      unawaited(_openRangeActions());
      return;
    }

    _clearBibleSearchSessionForManualSelection();
    final blockId = line.blockId ?? 0;
    if (blockId <= 0) return;
    _resetRapidTagArmed();
    final isPendingVerseRange =
        _rangeSelection.hasSelection &&
        !_rangeSelection.hasCompletedRange &&
        !_rangeSelection.hasTokenSelection;
    if (isPendingVerseRange) {
      setState(() {
        _rangeSelection = _rangeSelection.completeVerseRange(blockId);
      });
      return;
    }

    setState(() {
      _rangeSelection = _rangeSelection.beginVerseRange(blockId);
    });
  }

  void _selectTokenAnchor(VerseLine line, int tokenIndex) {
    _stopReaderAutoscroll();
    _clearBibleSearchSessionForManualSelection();
    final blockId = line.blockId ?? 0;
    if (blockId <= 0 || tokenIndex <= 0) return;
    _resetRapidTagArmed();
    final isPendingTokenRange =
        _rangeSelection.hasSelection &&
        !_rangeSelection.hasCompletedRange &&
        _rangeSelection.hasTokenSelection;
    if (isPendingTokenRange) {
      setState(() {
        _rangeSelection = _rangeSelection.completeTokenRange(
          blockId,
          tokenIndex,
        );
      });
      return;
    }

    setState(() {
      _rangeSelection = _rangeSelection.beginTokenRange(
        blockId,
        tokenIndex,
        wordIndices: true,
      );
    });
  }

  void _finishTokenSelection() {
    if (!mounted || !_rangeSelection.hasTokenSelection) return;
    if (!_rangeSelection.hasCompletedRange) {
      final blockId = _rangeSelection.startBlockId;
      final tokenIndex = _rangeSelection.startTokenIndex;
      if (blockId == null || tokenIndex == null) return;
      setState(() {
        _rangeSelection = _rangeSelection.completeTokenRange(
          blockId,
          tokenIndex,
        );
      });
    }
    // Release leaves the range selected; a separate tap opens actions.
  }

  void _dragVerseAnchor(VerseLine line) {
    final blockId = line.blockId ?? 0;
    if (blockId <= 0) return;
    if (!_rangeSelection.hasSelection) {
      setState(() {
        _rangeSelection = _rangeSelection.beginVerseRange(blockId);
      });
      return;
    }
    setState(() {
      _rangeSelection = _rangeSelection.completeVerseRange(blockId);
    });
  }

  void _dragTokenAnchor(VerseLine line, int tokenIndex) {
    final blockId = line.blockId ?? 0;
    if (blockId <= 0 || tokenIndex <= 0) return;
    if (!_rangeSelection.hasSelection) {
      setState(() {
        _rangeSelection = _rangeSelection.beginTokenRange(
          blockId,
          tokenIndex,
          wordIndices: true,
        );
      });
      return;
    }
    if (_rangeSelection.hasTokenSelection &&
        !_rangeSelection.hasCompletedRange) {
      setState(() {
        _rangeSelection = _rangeSelection.completeTokenRange(
          blockId,
          tokenIndex,
        );
      });
      return;
    }
    setState(() {
      _rangeSelection = _rangeSelection.completeTokenRange(blockId, tokenIndex);
    });
  }

  Future<void> _openRangeActions() async {
    _stopReaderAutoscroll();
    if (!mounted) return;
    final low = _rangeSelection.lowerBlockId ?? 0;
    final high = _rangeSelection.upperBlockId ?? low;
    if (low <= 0 || high <= 0) return;
    // The scrolling window may have discarded earlier verses. Load the full
    // selection from the Bible, including every intervening block.
    final db = await StudyBibleDatabase.instance.bible;
    final rows = await db.query(
      'bible_blocks',
      where: 'id BETWEEN ? AND ?',
      whereArgs: [low, high],
      orderBy: 'id ASC',
    );
    final selectedLines = rows
        .map(
          (row) => VerseLine(
            blockId: (row['id'] as num).toInt(),
            bookNumber: (row['book_number'] as num).toInt(),
            chapter: (row['chapter'] as num).toInt(),
            verse: (row['block_index'] as num).toInt(),
            html: row['html']?.toString() ?? '',
            text: row['plain_text']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
    if (selectedLines.isEmpty || !mounted) return;

    final first = selectedLines.first;
    final passage = PassageData(
      bookNumber: first.bookNumber,
      bookName: _bookNames[first.bookNumber] ?? 'Book ${first.bookNumber}',
      chapter: first.chapter,
      lines: selectedLines,
    );

    final tokenPreview = _rangeSelection.hasTokenSelection
        ? _buildSelectedTokenPreview(selectedLines)
        : null;
    final numberedText =
        (_rangeSelection.hasTokenSelection
            ? _buildSelectedTokenPreview(
                selectedLines,
                includeVerseNumbers: true,
              )
            : null) ??
        selectedLines
            .map((line) => '${line.verse} ${line.text.trim()}')
            .join('\n');
    final previewText = numberedText; // The preview matches Copy With Citation.

    final copyText =
        tokenPreview ??
        selectedLines.map((line) => line.text.trim()).join('\n');

    final verseRefs = selectedLines
        .map(
          (line) =>
              '${_bookNames[line.bookNumber] ?? passage.bookName} ${line.chapter}:${line.verse}',
        )
        .toList(growable: false);
    final label = _buildRangeLabel(
      passage.bookName,
      selectedLines.first,
      selectedLines.last,
    );
    final selectedStrongs = _selectedSingleStrongs(selectedLines);

    final action = await showViewerRangeActionsSheet(
      context,
      payload: ViewerRangeActionsPayload(
        label: label,
        previewText: previewText,
        startLabel: verseRefs.first,
        endLabel: verseRefs.last,
      ),
      fontScale: _fontScale,
      enableStrongs: selectedStrongs != null,
    );
    if (!mounted || action == null) return;

    switch (action) {
      case ViewerRangeAction.copyNoCitation:
        await _copyRangeToClipboard(copyText, label, includeCitation: false);
        break;
      case ViewerRangeAction.copyWithCitation:
        await _copyRangeToClipboard(numberedText, label, includeCitation: true);
        break;
      case ViewerRangeAction.highlight:
        if (_rangeSelection.hasTokenSelection) {
          final changed = await showHighlightPopup(
            context,
            verseRefs: verseRefs,
            tokenSelections: _buildTokenHighlightSelections(
              selectedLines,
              passage.bookName,
            ),
          );
          if (changed == true) await _reloadDefaultHighlight();
          if (changed == true && mounted) {
            setState(() {
              _highlightRefreshTick += 1;
              _rangeSelection = _rangeSelection.clear();
            });
          }
          return;
        }
        final changed = await showHighlightPopup(context, verseRefs: verseRefs);
        if (changed == true) await _reloadDefaultHighlight();
        if (changed == true && mounted) {
          setState(() {
            _highlightRefreshTick += 1;
            _rangeSelection = _rangeSelection.clear();
          });
        }
        return;
      case ViewerRangeAction.clearMarkup:
        await _clearRangeMarkup(
          verseRefs,
          tokenSelections: _rangeSelection.hasTokenSelection
              ? _buildTokenHighlightSelections(selectedLines, passage.bookName)
              : null,
        );
        break;
      case ViewerRangeAction.addHashTag:
        await _applyHashTagToSelection(selectedLines, passage);
        break;
      case ViewerRangeAction.addDollarTag:
        await _openHashTagScreenForSelection(selectedLines, passage);
        return;
      case ViewerRangeAction.addToMemory:
        await _addRangeToMemory(passage.bookName, selectedLines);
        break;
      case ViewerRangeAction.strongs:
        if (selectedStrongs == null) {
          _showRangeActionMessage(
            "Strong's is available for a single token selection.",
          );
          return;
        }
        await showViewerStrongsPageOne(
          context,
          strongsId: selectedStrongs,
          onSelectBlockId: _openBlockId,
        );
        return;
      case ViewerRangeAction.extendRange:
        ScaffoldMessenger.of(context).clearSnackBars();
        return;
      case ViewerRangeAction.resetRange:
        if (mounted) {
          setState(() {
            _rangeSelection = _rangeSelection.clear();
          });
        }
        return;
    }
  }

  Future<void> _applyHashTagToSelection(
    List<VerseLine> selectedLines,
    PassageData passage,
  ) async {
    if (selectedLines.isEmpty) return;
    try {
      final navigator = Navigator.of(context);
      final repository = HashTagRepository();
      final targets = selectedLines
          .map(
            (line) => HashTagTarget(
              bookNumber: line.bookNumber,
              chapter: line.chapter,
              verse: line.verse,
              verseRef: '${line.bookNumber}:${line.chapter}:${line.verse}',
            ),
          )
          .toList(growable: false);
      final defaultTag = repository.normalizeTagName(
        await repository.loadDefaultTag() ?? '',
      );
      final defaultCategory = await repository.loadDefaultTagCategory();
      if (!mounted) return;
      if (defaultTag.isEmpty) {
        _resetRapidTagArmed();
        await showHashTagScreen(
          navigator,
          passage: passage,
          selection: _rangeSelection,
          selectionTargets: targets,
          fontScale: _fontScale,
          initialTabIndex: _lastTagTabIndex,
          onTagTabChanged: _saveLastTagTabIndex,
          onSelectBlockId: _openBlockId,
        );
        if (mounted) {
          setState(() {
            _highlightRefreshTick += 1;
          });
        }
        return;
      }
      final chapterGroups = <String, List<VerseLine>>{};
      for (final line in selectedLines) {
        chapterGroups
            .putIfAbsent(
              '${line.bookNumber}:${line.chapter}',
              () => <VerseLine>[],
            )
            .add(line);
      }
      var inserted = 0;
      var skipped = 0;
      for (final chapterLines in chapterGroups.values) {
        if (chapterLines.isEmpty) continue;
        chapterLines.sort((left, right) => left.verse.compareTo(right.verse));
        final result = await repository.addBibleRangeToTag(
          tag: defaultTag,
          bookNumber: chapterLines.first.bookNumber,
          chapter: chapterLines.first.chapter,
          verseStart: chapterLines.first.verse,
          verseEnd: chapterLines.last.verse,
          category: defaultCategory,
        );
        inserted += result.inserted;
        skipped += result.skipped;
      }
      if (!mounted) return;
      if (inserted == 0 && skipped == 0) {
        _resetRapidTagArmed();
        await showHashTagScreen(
          navigator,
          passage: passage,
          selection: _rangeSelection,
          selectionTargets: targets,
          fontScale: _fontScale,
          initialTabIndex: _lastTagTabIndex,
          onTagTabChanged: _saveLastTagTabIndex,
          initialTag: defaultTag,
          onSelectBlockId: _openBlockId,
        );
        if (mounted) {
          setState(() {
            _highlightRefreshTick += 1;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _highlightRefreshTick += 1;
        });
      }
    } catch (error) {
      if (!mounted) return;
      _showRangeActionMessage('Could not open # tags: $error');
    }
  }

  Future<void> _openHashTagScreenForSelection(
    List<VerseLine> selectedLines,
    PassageData passage,
  ) async {
    if (selectedLines.isEmpty) return;
    try {
      final navigator = Navigator.of(context);
      final targets = selectedLines
          .map(
            (line) => HashTagTarget(
              bookNumber: line.bookNumber,
              chapter: line.chapter,
              verse: line.verse,
              verseRef: '${line.bookNumber}:${line.chapter}:${line.verse}',
            ),
          )
          .toList(growable: false);
      await showHashTagScreen(
        navigator,
        passage: passage,
        selection: _rangeSelection,
        selectionTargets: targets,
        fontScale: _fontScale,
        initialTabIndex: _lastTagTabIndex,
        onTagTabChanged: _saveLastTagTabIndex,
        onSelectBlockId: _openBlockId,
      );
      if (mounted) {
        setState(() {
          _highlightRefreshTick += 1;
        });
      }
    } catch (error) {
      if (!mounted) return;
      _showRangeActionMessage('Could not open # tags: $error');
    }
  }

  String _buildRangeLabel(String bookName, VerseLine first, VerseLine last) {
    if (first.bookNumber != last.bookNumber) {
      final lastBook = _bookNames[last.bookNumber] ?? 'Book ${last.bookNumber}';
      return '$bookName ${first.chapter}:${first.verse} - $lastBook ${last.chapter}:${last.verse}';
    }
    if (first.chapter == last.chapter) {
      if (first.verse == last.verse) {
        return '$bookName ${first.chapter}:${first.verse}';
      }
      return '$bookName ${first.chapter}:${first.verse}-${last.verse}';
    }
    return '$bookName ${first.chapter}:${first.verse} - $bookName ${last.chapter}:${last.verse}';
  }

  bool _isLineInsideMarkupRange(VerseLine line) {
    final blockId = line.blockId ?? 0;
    return isTapInsideCurrentSelection(_rangeSelection, blockId);
  }

  Future<void> _copyRangeToClipboard(
    String selectedText,
    String citation, {
    required bool includeCitation,
  }) async {
    await copyViewerSelectionToClipboard(
      selectedText: selectedText,
      citation: citation,
      includeCitation: includeCitation,
    );
    if (!mounted) return;
    // Copy closes the action menu; no extra confirmation needs dismissing.
    ScaffoldMessenger.of(context).clearSnackBars();
  }

  Future<void> _clearRangeMarkup(
    List<String> verseRefs, {
    List<TokenHighlightSelection>? tokenSelections,
  }) async {
    if (tokenSelections != null && tokenSelections.isNotEmpty) {
      await HighlightsRepository().removeHighlightRanges(tokenSelections);
    } else {
      await HighlightsRepository().removeHighlightsForVerseRefs(verseRefs);
    }
    if (!mounted) return;
    setState(() {
      _highlightRefreshTick += 1;
      _rangeSelection = _rangeSelection.clear();
    });
  }

  Future<void> _addRangeToMemory(String bookName, List<VerseLine> lines) async {
    if (lines.isEmpty) return;
    final first = lines.first;
    final last = lines.last;
    final verseText = lines.map((line) => line.text.trim()).join(' ');
    await BibleMemoryRepository().upsertPassage(
      bookNumber: first.bookNumber,
      bookName: bookName,
      chapter: first.chapter,
      verse: first.verse,
      endChapter: last.chapter,
      endVerse: last.verse,
      verseText: verseText,
    );
    if (!mounted) return;
  }

  void _showRangeActionMessage(String message) {
    if (!mounted) return;
    _showReaderFeedback(context, message, fontScale: _fontScale);
  }

  String? _buildSelectedTokenPreview(
    List<VerseLine> lines, {
    bool includeVerseNumbers = false,
  }) {
    final pieces = <String>[];
    for (final line in lines) {
      final versePieces = <String>[];
      final blockId = line.blockId ?? 0;
      if (_rangeSelection.usesWordIndices) {
        final text = parseViewerMarkupSegments(
          html: line.html,
          fallbackText: line.text,
          baseStyle: const TextStyle(),
          redLetterColor: Colors.red,
        ).map((s) => s.text).join();
        final words = RegExp(
          r'[^\s]+',
          unicode: true,
        ).allMatches(text).toList();
        final selected = <RegExpMatch>[];
        for (var index = 0; index < words.length; index++) {
          if (_rangeSelection.containsTokenPosition(blockId, index + 1)) {
            selected.add(words[index]);
          }
        }
        if (selected.isNotEmpty) {
          final part = text.substring(selected.first.start, selected.last.end);
          pieces.add(includeVerseNumbers ? '${line.verse} $part' : part);
        }
        continue;
      }
      for (final segment in parseViewerMarkupSegments(
        html: line.html,
        fallbackText: line.text,
        baseStyle: const TextStyle(),
        redLetterColor: Colors.red,
        splitWords: _rangeSelection.usesWordIndices,
      )) {
        final tokenIndex = _rangeSelection.usesWordIndices
            ? segment.wordIndex
            : segment.tokenIndex;
        if (tokenIndex == null) continue;
        if (_rangeSelection.containsTokenPosition(blockId, tokenIndex)) {
          versePieces.add(segment.text);
        }
      }
      if (versePieces.isNotEmpty) {
        final text = versePieces.join(' ').trim();
        pieces.add(includeVerseNumbers ? '${line.verse} $text' : text);
      }
    }
    if (pieces.isEmpty) return null;
    return pieces.join(includeVerseNumbers ? '\n' : ' ');
  }

  String? _selectedSingleStrongs(List<VerseLine> lines) {
    if (!_rangeSelection.isSingleToken) return null;
    for (final line in lines) {
      final blockId = line.blockId ?? 0;
      for (final segment in parseViewerMarkupSegments(
        html: line.html,
        fallbackText: line.text,
        baseStyle: const TextStyle(),
        redLetterColor: Colors.red,
        splitWords: _rangeSelection.usesWordIndices,
      )) {
        final tokenIndex = _rangeSelection.usesWordIndices
            ? segment.wordIndex
            : segment.tokenIndex;
        if (tokenIndex == null) continue;
        if (_rangeSelection.containsTokenPosition(blockId, tokenIndex)) {
          final strongs = _preferredStrongs(segment.strongs);
          if (strongs != null && strongs.isNotEmpty) {
            return strongs;
          }
        }
      }
    }
    return null;
  }

  String? _preferredStrongs(Set<String>? strongs) {
    if (strongs == null || strongs.isEmpty) return null;
    if (strongs.length == 1) return strongs.first;

    const ignore = {'G3588', 'H853', 'H136'};
    final preferred = strongs
        .where((value) => !ignore.contains(value))
        .toList();
    if (preferred.isNotEmpty) {
      return preferred.first;
    }

    return strongs.first;
  }

  List<TokenHighlightSelection> _buildTokenHighlightSelections(
    List<VerseLine> lines,
    String bookName,
  ) {
    final items = <TokenHighlightSelection>[];
    for (final line in lines) {
      final blockId = line.blockId ?? 0;
      final verseRef = '$bookName ${line.chapter}:${line.verse}';
      if (!_rangeSelection.containsBlock(blockId)) continue;
      if (!_rangeSelection.hasTokenSelection) {
        items.add(TokenHighlightSelection(verseRef: verseRef));
        continue;
      }
      int? startToken;
      int? endToken;
      final lowBlock = _rangeSelection.lowerBlockId;
      final highBlock = _rangeSelection.upperBlockId;
      if (lowBlock == null || highBlock == null) continue;
      if (blockId == lowBlock) {
        startToken = _rangeSelection.lowerTokenIndex;
      }
      if (blockId == highBlock) {
        endToken = _rangeSelection.upperTokenIndex;
      }
      final tokenCount = _tokenCountForLine(line);
      startToken ??= 1;
      endToken ??= tokenCount;
      final startWord = _rangeSelection.usesWordIndices ? startToken : null;
      final endWord = _rangeSelection.usesWordIndices ? endToken : null;
      if (_rangeSelection.usesWordIndices) {
        final words = parseViewerMarkupSegments(
          html: line.html,
          fallbackText: line.text,
          baseStyle: const TextStyle(),
          redLetterColor: Colors.red,
          splitWords: true,
        );
        final selected = words
            .where(
              (w) =>
                  w.wordIndex != null &&
                  w.wordIndex! >= startWord! &&
                  w.wordIndex! <= endWord!,
            )
            .toList();
        final source = selected
            .map((w) => w.tokenIndex)
            .whereType<int>()
            .toList();
        startToken = source.isEmpty ? 1 : source.first;
        endToken = source.isEmpty ? 1 : source.last;
      }
      items.add(
        TokenHighlightSelection(
          verseRef: verseRef,
          startWord: startWord,
          endWord: endWord,
          startToken: startToken,
          endToken: endToken,
        ),
      );
    }
    return items;
  }

  int _tokenCountForLine(VerseLine line) {
    var maxToken = 0;
    for (final segment in parseViewerMarkupSegments(
      html: line.html,
      fallbackText: line.text,
      baseStyle: const TextStyle(),
      redLetterColor: Colors.red,
      splitWords: _rangeSelection.usesWordIndices,
    )) {
      final tokenIndex = _rangeSelection.usesWordIndices
          ? segment.wordIndex
          : segment.tokenIndex;
      if (tokenIndex != null && tokenIndex > maxToken) {
        maxToken = tokenIndex;
      }
    }
    return maxToken == 0 ? 1 : maxToken;
  }
}
