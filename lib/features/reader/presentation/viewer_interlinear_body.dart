import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/study_bible_database.dart';
import 'bible_explorer_screen.dart';
import 'viewer_acrostic_block.dart';
import 'viewer_heading_block.dart';
import 'viewer_interlinear_settings.dart';
import 'viewer_render_models.dart';
import 'viewer_render_resolver.dart';

class ViewerInterlinearBody extends StatefulWidget {
  const ViewerInterlinearBody({
    super.key,
    required this.passage,
    required this.selectedBookNumber,
    required this.selectedChapter,
    required this.selectedVerse,
    required this.fontScale,
    required this.settings,
    required this.onSelectVerse,
  });

  final PassageData? passage;
  final int selectedBookNumber;
  final int selectedChapter;
  final int selectedVerse;
  final double fontScale;
  final ViewerInterlinearSettings settings;
  final ValueChanged<VerseLine> onSelectVerse;

  @override
  State<ViewerInterlinearBody> createState() => _ViewerInterlinearBodyState();
}

class _ViewerInterlinearBodyState extends State<ViewerInterlinearBody> {
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  final Map<String, Map<int, List<String>>> _headingCache =
      <String, Map<int, List<String>>>{};
  final Map<String, Map<int, AcrosticRecord>> _acrosticCache =
      <String, Map<int, AcrosticRecord>>{};
  final Map<String, Map<int, List<InterlinearTokenRecord>>> _tokenCache =
      <String, Map<int, List<InterlinearTokenRecord>>>{};
  int? _lastScrolledBlockId;
  int _recenterToken = 0;
  Object? _loadError;

  @override
  void didUpdateWidget(covariant ViewerInterlinearBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVerse != widget.selectedVerse ||
        oldWidget.selectedChapter != widget.selectedChapter ||
        oldWidget.selectedBookNumber != widget.selectedBookNumber ||
        oldWidget.passage?.chapter != widget.passage?.chapter ||
        oldWidget.passage?.bookName != widget.passage?.bookName) {
      _lastScrolledBlockId = null;
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final passage = widget.passage;
    if (passage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final blockIds = passage.lines
        .map((line) => line.blockId ?? 0)
        .where((id) => id > 0)
        .toList(growable: false);

    final cacheKey = blockIds.isEmpty
        ? '${passage.bookName}|${passage.chapter}|${widget.settings.englishOrder}'
        : '${blockIds.first}-${blockIds.last}|${widget.settings.englishOrder}';
    final cachedHeadings = _headingCache[cacheKey];
    final cachedAcrostics = _acrosticCache[cacheKey];
    final cachedTokens = _tokenCache[cacheKey];

    if (cachedHeadings == null || cachedAcrostics == null || cachedTokens == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          final headings = cachedHeadings ??
              await StudyBibleDatabase.instance.loadSectionHeadingsForBlockIds(
                blockIds,
              );
          final acrostics = cachedAcrostics ??
              await StudyBibleDatabase.instance.loadAcrosticsForBlockIds(
                blockIds,
              );
          final tokens = cachedTokens ??
              await _loadCompleteTokenMap(
                blockIds,
                englishOrder: widget.settings.englishOrder,
              );
          if (!mounted) return;
          setState(() {
            _headingCache[cacheKey] = headings;
            _acrosticCache[cacheKey] = acrostics;
            _tokenCache[cacheKey] = tokens;
            _loadError = null;
          });
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _loadError = error;
          });
        }
      });
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Unable to load interlinear data.\n\n$_loadError',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (cachedTokens == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    final renderItems = resolveViewerRenderItems(
      passage,
      headingsByBlockId: cachedHeadings ?? const <int, List<String>>{},
      acrosticsByBlockId: cachedAcrostics ?? const <int, AcrosticRecord>{},
    );

    final verseItemIndex = <int, int>{};
    for (var index = 0; index < renderItems.length; index++) {
      final item = renderItems[index];
      if (item case ViewerVerseItem(:final line)) {
        final blockId = line.blockId;
        if (blockId != null) {
          verseItemIndex[blockId] = index;
        }
      }
    }

    final selectedLine = _findSelectedLine(passage.lines);
    final selectedBlockId = selectedLine?.blockId ?? 0;
    final initialIndex =
        selectedBlockId > 0 ? (verseItemIndex[selectedBlockId] ?? 0) : 0;

    if (cachedHeadings != null && selectedBlockId > 0) {
      if (_lastScrolledBlockId != selectedBlockId) {
        _scheduleRecenter(verseItemIndex, selectedBlockId);
      }
    }

    return ScrollablePositionedList.builder(
      itemCount: renderItems.length,
      itemScrollController: _itemScrollController,
      itemPositionsListener: _itemPositionsListener,
      initialScrollIndex: initialIndex,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemBuilder: (context, index) {
        final item = renderItems[index];
        VerseLine? previousVerseLine;
        for (var probe = index - 1; probe >= 0; probe--) {
          final prior = renderItems[probe];
          if (prior case ViewerVerseItem(:final line)) {
            previousVerseLine = line;
            break;
          }
        }
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == renderItems.length - 1
                ? 0
                : item is ViewerHeadingItem
                ? 4
                : item is ViewerAcrosticItem
                ? 0
                : 10,
          ),
          child: switch (item) {
            ViewerAcrosticItem(:final hebrew, :final transliteration) =>
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 8),
                  ViewerAcrosticBlock(
                    hebrew: hebrew,
                    transliteration: transliteration,
                    fontScale: widget.fontScale,
                  ),
                ],
              ),
            ViewerHeadingItem(:final text) =>
              ViewerHeadingBlock(text: text, fontScale: widget.fontScale),
            ViewerVerseItem(:final line) => _InterlinearVerseFlow(
                blockId: line.blockId,
                line: line,
                tokens:
                    cachedTokens[line.blockId] ??
                    const <InterlinearTokenRecord>[],
                fontScale: widget.fontScale,
                settings: widget.settings,
                isSelected: _matchesSelectedLine(line),
                showChapterNumber:
                    previousVerseLine == null ||
                    previousVerseLine.bookNumber != line.bookNumber ||
                    previousVerseLine.chapter != line.chapter,
                isHebrew: (passage.bookNumber ?? 1) <= 39,
                showTopDivider:
                    index == 0 || renderItems[index - 1] is! ViewerAcrosticItem,
                onTap: () => widget.onSelectVerse(line),
              ),
          },
        );
      },
    );
  }

  bool _isVerseVisible(Map<int, int> verseItemIndex, int blockId) {
    final targetIndex = verseItemIndex[blockId];
    if (targetIndex == null) return false;
    for (final position in _itemPositionsListener.itemPositions.value) {
      if (position.index == targetIndex) {
        return position.itemTrailingEdge > 0 && position.itemLeadingEdge < 1;
      }
    }
    return false;
  }

  Future<Map<int, List<InterlinearTokenRecord>>> _loadCompleteTokenMap(
    List<int> blockIds, {
    required bool englishOrder,
  }) async {
    if (blockIds.isEmpty) {
      return const <int, List<InterlinearTokenRecord>>{};
    }

    final tokens = await StudyBibleDatabase.instance.loadInterlinearTokensForBlockIds(
      blockIds,
      englishOrder: englishOrder,
    );

    final missingBlockIds = blockIds
        .where((id) => (tokens[id] ?? const <InterlinearTokenRecord>[]).isEmpty)
        .toList(growable: false);

    if (missingBlockIds.isEmpty) {
      return tokens;
    }

    final repaired = <int, List<InterlinearTokenRecord>>{
      ...tokens,
    };
    for (final blockId in missingBlockIds) {
      final single = await StudyBibleDatabase.instance.loadInterlinearTokensForBlockIds(
        <int>[blockId],
        englishOrder: englishOrder,
      );
      final rows = single[blockId];
      if (rows != null && rows.isNotEmpty) {
        repaired[blockId] = rows;
      }
    }
    return repaired;
  }

  void _scheduleRecenter(Map<int, int> verseItemIndex, int blockId) {
    final targetIndex = verseItemIndex[blockId];
    if (targetIndex == null) return;
    final int token = ++_recenterToken;
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 140),
      Duration(milliseconds: 320),
    ];

    void runAttempt(int attempt) {
      final delay = delays[attempt];
      Future<void>.delayed(delay, () {
        if (!mounted || token != _recenterToken) return;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted || token != _recenterToken) return;
          if (!_itemScrollController.isAttached) {
            if (attempt + 1 < delays.length) {
              runAttempt(attempt + 1);
            }
            return;
          }
          final shouldScroll =
              attempt == 0 || !_isVerseVisible(verseItemIndex, blockId);
          if (shouldScroll) {
            await _itemScrollController.scrollTo(
              index: targetIndex,
              alignment: 0.22,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeInOut,
            );
          }
          if (!mounted || token != _recenterToken) return;
          _lastScrolledBlockId = blockId;
          if (attempt + 1 < delays.length) {
            runAttempt(attempt + 1);
          }
        });
      });
    }

    runAttempt(0);
  }

  VerseLine? _findSelectedLine(List<VerseLine> lines) {
    for (final line in lines) {
      if (_matchesSelectedLine(line)) return line;
    }
    return null;
  }

  bool _matchesSelectedLine(VerseLine line) {
    return line.bookNumber == widget.selectedBookNumber &&
        line.chapter == widget.selectedChapter &&
        line.verse == widget.selectedVerse;
  }
}

class _InterlinearVerseFlow extends StatefulWidget {
  const _InterlinearVerseFlow({
    required this.blockId,
    required this.line,
    required this.tokens,
    required this.fontScale,
    required this.settings,
    required this.isSelected,
    required this.showChapterNumber,
    required this.isHebrew,
    required this.showTopDivider,
    required this.onTap,
  });

  final int? blockId;
  final VerseLine line;
  final List<InterlinearTokenRecord> tokens;
  final double fontScale;
  final ViewerInterlinearSettings settings;
  final bool isSelected;
  final bool showChapterNumber;
  final bool isHebrew;
  final bool showTopDivider;
  final VoidCallback onTap;

  @override
  State<_InterlinearVerseFlow> createState() => _InterlinearVerseFlowState();
}

class _InterlinearVerseFlowState extends State<_InterlinearVerseFlow> {
  Future<List<InterlinearTokenRecord>>? _recoveryFuture;
  bool _retriedEmptyTokens = false;

  @override
  void initState() {
    super.initState();
    _primeRecoveryFuture();
  }

  @override
  void didUpdateWidget(covariant _InterlinearVerseFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockId != widget.blockId ||
        oldWidget.settings.englishOrder != widget.settings.englishOrder) {
      _retriedEmptyTokens = false;
      _primeRecoveryFuture();
    }
  }

  void _primeRecoveryFuture() {
    final blockId = widget.blockId;
    if (blockId == null || blockId <= 0) {
      _recoveryFuture = Future<List<InterlinearTokenRecord>>.value(
        const <InterlinearTokenRecord>[],
      );
      return;
    }
    _recoveryFuture = StudyBibleDatabase.instance
        .loadInterlinearTokensForBlockIds(
          <int>[blockId],
          englishOrder: widget.settings.englishOrder,
        )
        .then((map) => map[blockId] ?? const <InterlinearTokenRecord>[]);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tokens.isNotEmpty) {
      return _InterlinearVerseContent(
        line: widget.line,
        tokens: widget.tokens,
        fontScale: widget.fontScale,
        settings: widget.settings,
        isSelected: widget.isSelected,
        showChapterNumber: widget.showChapterNumber,
        isHebrew: widget.isHebrew,
        showTopDivider: widget.showTopDivider,
        onTap: widget.onTap,
      );
    }

    return FutureBuilder<List<InterlinearTokenRecord>>(
      future: _recoveryFuture,
      builder: (context, snapshot) {
        final recoveredTokens = snapshot.data ?? const <InterlinearTokenRecord>[];
        if (snapshot.connectionState == ConnectionState.done &&
            recoveredTokens.isEmpty &&
            !_retriedEmptyTokens) {
          _retriedEmptyTokens = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _primeRecoveryFuture();
            });
          });
        }

        if (snapshot.connectionState != ConnectionState.done &&
            recoveredTokens.isEmpty) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh.withValues(alpha: 0.72)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          );
        }

        return _InterlinearVerseContent(
          line: widget.line,
          tokens: recoveredTokens,
          fontScale: widget.fontScale,
          settings: widget.settings,
          isSelected: widget.isSelected,
          showChapterNumber: widget.showChapterNumber,
          isHebrew: widget.isHebrew,
          showTopDivider: widget.showTopDivider,
          onTap: widget.onTap,
        );
      },
    );
  }
}

class _InterlinearVerseContent extends StatelessWidget {
  const _InterlinearVerseContent({
    required this.line,
    required this.tokens,
    required this.fontScale,
    required this.settings,
    required this.isSelected,
    required this.showChapterNumber,
    required this.isHebrew,
    required this.showTopDivider,
    required this.onTap,
  });

  final VerseLine line;
  final List<InterlinearTokenRecord> tokens;
  final double fontScale;
  final ViewerInterlinearSettings settings;
  final bool isSelected;
  final bool showChapterNumber;
  final bool isHebrew;
  final bool showTopDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final baseSize = (textTheme.bodyMedium?.fontSize ?? 16) * fontScale;
    final headerStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: isHebrew ? baseSize * 1.32 : baseSize,
      height: 1.1,
      fontWeight: isHebrew ? FontWeight.w700 : FontWeight.w500,
      fontFamily: isHebrew ? 'SBLHebrew' : 'NotoSerif',
      color: theme.colorScheme.onSurface,
    );
    final englishStyle = (textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: baseSize * 0.82,
      height: 1.05,
      color: theme.colorScheme.onSurfaceVariant,
      fontFamily: 'Lato',
      fontWeight: FontWeight.w500,
    );
    final originalStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: isHebrew ? baseSize * 1.32 : baseSize,
      height: 1.1,
      fontWeight: FontWeight.w700,
      fontFamily: isHebrew ? 'SBLHebrew' : 'NotoSerif',
      color: theme.colorScheme.onSurface,
    );
    final metaStyle = (textTheme.labelSmall ?? const TextStyle()).copyWith(
      fontSize: baseSize * 0.85,
      height: 1.05,
      color: theme.colorScheme.onSurfaceVariant,
      fontFamily: 'Lato',
      letterSpacing: 0.0,
    );

    final headerText = tokens.isEmpty
        ? line.text
        : tokens
            .map((token) => token.original.trim())
            .where((text) => text.isNotEmpty && text != '.')
            .join(' ');
    final orderedTokens = settings.englishOrder
        ? (tokens.toList()
          ..sort((a, b) {
            final englishCompare =
                a.english.toLowerCase().compareTo(b.english.toLowerCase());
            if (englishCompare != 0) return englishCompare;
            return a.original.compareTo(b.original);
          }))
        : tokens;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showTopDivider) const Divider(height: 8),
              _InterlinearHeaderRow(
                verse: line.verse,
                chapter: line.chapter,
                showChapterNumber: showChapterNumber,
                text: headerText,
                style: headerStyle,
                fontScale: fontScale,
              ),
              const SizedBox(height: 2),
              Directionality(
                textDirection: isHebrew ? TextDirection.rtl : TextDirection.ltr,
                child: Wrap(
                  alignment: WrapAlignment.start,
                  spacing: (10 * fontScale).clamp(8.0, 18.0),
                  runSpacing: (3 * fontScale).clamp(2.0, 8.0),
                  children: orderedTokens
                      .map(
                        (token) => _InterlinearTokenColumn(
                          token: token,
                          settings: settings,
                          englishStyle: englishStyle,
                          originalStyle: originalStyle,
                          metaStyle: metaStyle,
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InterlinearHeaderRow extends StatelessWidget {
  const _InterlinearHeaderRow({
    required this.verse,
    required this.chapter,
    required this.showChapterNumber,
    required this.text,
    required this.style,
    required this.fontScale,
  });

  final int verse;
  final int chapter;
  final bool showChapterNumber;
  final String text;
  final TextStyle style;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _VerseNumberChip(
            verse: verse,
            chapter: chapter,
            showChapterNumber: showChapterNumber,
            fontScale: fontScale,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _VerseNumberChip extends StatelessWidget {
  const _VerseNumberChip({
    required this.verse,
    required this.chapter,
    required this.showChapterNumber,
    required this.fontScale,
  });

  final int verse;
  final int chapter;
  final bool showChapterNumber;
  final double fontScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: (6 * fontScale).clamp(5.0, 9.0),
        vertical: (1.5 * fontScale).clamp(1.0, 3.0),
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        showChapterNumber ? '$chapter:$verse' : '$verse',
        style: (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InterlinearTokenColumn extends StatelessWidget {
  const _InterlinearTokenColumn({
    required this.token,
    required this.settings,
    required this.englishStyle,
    required this.originalStyle,
    required this.metaStyle,
  });

  final InterlinearTokenRecord token;
  final ViewerInterlinearSettings settings;
  final TextStyle englishStyle;
  final TextStyle originalStyle;
  final TextStyle metaStyle;

  @override
  Widget build(BuildContext context) {
    final englishText =
        (token.english.trim().isNotEmpty && token.english != '.')
            ? token.english.replaceAll('-', '\u2011')
            : ' ';
    final originalText =
        (token.original.trim().isNotEmpty && token.original != '.')
            ? token.original
            : ' ';
    final transliterationText =
        token.transliteration.trim().isNotEmpty ? token.transliteration : ' ';
    final pronunciationText =
        token.pronunciation.trim().isNotEmpty ? token.pronunciation : ' ';
    final strongsText =
        token.strongsNumber.trim().isNotEmpty ? token.strongsNumber : ' ';
    final morphologyText = token.morphology.trim();
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (settings.showEnglishGloss)
            Text(
              englishText,
              style: englishStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showOriginalText)
            Text(
              originalText,
              style: originalStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showTransliteration)
            Text(
              transliterationText,
              style: metaStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showPronunciation)
            Text(
              pronunciationText,
              style: metaStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showStrongsNumber)
            Text(
              strongsText,
              style: metaStyle,
              textAlign: TextAlign.center,
            ),
          if (settings.showMorphology && morphologyText.isNotEmpty) ...[
            const SizedBox(height: 2),
            _MorphologyBubble(
              morphology: morphologyText,
              style: metaStyle.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MorphologyBubble extends StatelessWidget {
  const _MorphologyBubble({
    required this.morphology,
    required this.style,
  });

  final String morphology;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final compact = _compactMorphology(morphology);
    if (compact.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _morphColor(compact),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        compact,
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}

Color _morphColor(String value) {
  final upper = value.toUpperCase();
  if (upper.startsWith('C')) {
    return Colors.teal.shade600;
  }
  if (upper.startsWith('T')) {
    return Colors.brown.shade400;
  }
  if (upper.startsWith('N')) {
    return Colors.green.shade600;
  }
  if (upper.startsWith('A')) {
    return Colors.green.shade600;
  }
  if (upper.startsWith('V')) {
    return Colors.blue.shade600;
  }
  if (upper.startsWith('P') || upper.startsWith('R') || upper.startsWith('D')) {
    return Colors.teal.shade500;
  }
  return Colors.blueGrey.shade400;
}

String _compactMorphology(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return '';
  final parts = normalized
      .split('/')
      .map((part) => part.replaceAll('-', '').trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';
  const primaryOrder = ['N', 'V', 'A', 'P', 'C', 'T', 'R', 'D', 'S', 'H'];
  for (final tag in primaryOrder) {
    for (final part in parts) {
      if (part.toUpperCase().startsWith(tag)) {
        return part;
      }
    }
  }
  return parts.first;
}
