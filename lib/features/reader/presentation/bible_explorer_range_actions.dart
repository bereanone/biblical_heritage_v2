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
          _selectedBlockId = line.blockId;
          _bookNumber = line.bookNumber;
          _chapter = line.chapter;
          _verse = line.verse;
        });
        _pinHeaderToSelectedVerse(line.blockId);
        _recordHistory();
      }
      _openRangeActions();
      return;
    }
    if (_rangeSelection.hasCompletedRange &&
        !isTapInsideCurrentSelection(_rangeSelection, line.blockId ?? 0)) {
      setState(() {
        _rangeSelection = _rangeSelection.clear();
      });
    }
    if (_rangeSelection.hasSelection && !_rangeSelection.hasCompletedRange) {
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
      _selectedBlockId = line.blockId;
      _bookNumber = line.bookNumber;
      _chapter = line.chapter;
      _verse = line.verse;
    });
    _pinHeaderToSelectedVerse(line.blockId);
    _recordHistory();
  }

  void _selectMarkupAnchor(VerseLine line) {
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
      _showRangeActionMessage(
        'Range end set. Tap inside the highlighted range for actions.',
      );
      return;
    }

    setState(() {
      _rangeSelection = _rangeSelection.beginVerseRange(blockId);
    });
    _showRangeActionMessage(
      'Range start set: ${line.chapter}:${line.verse}. Long-press end verse.',
    );
  }

  void _selectTokenAnchor(VerseLine line, int tokenIndex) {
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
      _showRangeActionMessage(
        'Token range end set. Tap inside the selected verse range for actions.',
      );
      return;
    }

    setState(() {
      _rangeSelection = _rangeSelection.beginTokenRange(blockId, tokenIndex);
    });
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
        _rangeSelection = _rangeSelection.beginTokenRange(blockId, tokenIndex);
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
    final passage = await _currentPassageOrLoad();
    if (!mounted) return;
    final startId = _rangeSelection.startBlockId ?? 0;
    final endId =
        _rangeSelection.endBlockId ?? _rangeSelection.startBlockId ?? 0;
    if (startId <= 0 || endId <= 0) return;
    final low = startId < endId ? startId : endId;
    final high = startId < endId ? endId : startId;
    final selectedLines = passage.lines
        .where((line) {
          final blockId = line.blockId ?? 0;
          return blockId >= low && blockId <= high;
        })
        .toList(growable: false);
    if (selectedLines.isEmpty || !mounted) return;

    final tokenPreview = _rangeSelection.hasTokenSelection
        ? _buildSelectedTokenPreview(selectedLines)
        : null;
    final previewText =
        tokenPreview ??
        selectedLines.map((line) => '${line.verse} ${line.text}').join('\n');

    final verseRefs = selectedLines
        .map((line) => '${passage.bookName} ${line.chapter}:${line.verse}')
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
        await _copyRangeToClipboard(selectedLines, includeCitation: false);
        break;
      case ViewerRangeAction.copyWithCitation:
        await _copyRangeToClipboard(selectedLines, includeCitation: true);
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
          if (changed == true && mounted) {
            setState(() {
              _highlightRefreshTick += 1;
              _rangeSelection = _rangeSelection.clear();
            });
          }
          return;
        }
        final changed = await showHighlightPopup(context, verseRefs: verseRefs);
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
        return;
      }
      final chapterGroups = <int, List<VerseLine>>{};
      for (final line in selectedLines) {
        chapterGroups.putIfAbsent(line.chapter, () => <VerseLine>[]).add(line);
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
        return;
      }
      _showRangeActionMessage(
        'Tagged $inserted verse(s) with $defaultTag'
        '${skipped > 0 ? ' ($skipped already in this tag)' : ''}.',
      );
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
    } catch (error) {
      if (!mounted) return;
      _showRangeActionMessage('Could not open # tags: $error');
    }
  }

  String _buildRangeLabel(String bookName, VerseLine first, VerseLine last) {
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
    List<VerseLine> lines, {
    required bool includeCitation,
  }) async {
    final passage = await _currentPassageOrLoad();
    if (!mounted || lines.isEmpty) return;
    final text = lines.map((line) => line.text.trim()).join('\n');
    final payload = includeCitation
        ? '$text\n${_buildRangeLabel(passage.bookName, lines.first, lines.last)}'
        : text;
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    _showRangeActionMessage(
      includeCitation
          ? 'Range copied with citation.'
          : 'Range copied without citation.',
    );
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
    });
    _showRangeActionMessage('Markup cleared for selected range.');
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
    _showRangeActionMessage('Added range to Bible Memory.');
  }

  void _showRangeActionMessage(String message) {
    if (!mounted) return;
    showReadableSnackBar(context, message, fontScale: _fontScale);
  }

  String? _buildSelectedTokenPreview(List<VerseLine> lines) {
    final pieces = <String>[];
    for (final line in lines) {
      final blockId = line.blockId ?? 0;
      for (final segment in parseViewerMarkupSegments(
        html: line.html,
        fallbackText: line.text,
        baseStyle: const TextStyle(),
        redLetterColor: Colors.red,
      )) {
        final tokenIndex = segment.tokenIndex;
        if (tokenIndex == null) continue;
        if (_rangeSelection.containsTokenPosition(blockId, tokenIndex)) {
          final text = segment.text.trim();
          if (text.isNotEmpty) {
            pieces.add(text);
          }
        }
      }
    }
    if (pieces.isEmpty) return null;
    return pieces.join(' ');
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
      )) {
        final tokenIndex = segment.tokenIndex;
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
      items.add(
        TokenHighlightSelection(
          verseRef: verseRef,
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
    )) {
      final tokenIndex = segment.tokenIndex;
      if (tokenIndex != null && tokenIndex > maxToken) {
        maxToken = tokenIndex;
      }
    }
    return maxToken == 0 ? 1 : maxToken;
  }
}
