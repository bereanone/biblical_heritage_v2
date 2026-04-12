import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../data/highlights_repository.dart';
import '../data/history_log_service.dart';
import '../data/navigation_history_service.dart';
import '../data/bible_memory_repository.dart';
import 'bible_memory_screen.dart';
import 'highlight_popup.dart';
import 'viewer_body.dart';
import 'viewer_bottom_bar.dart';
import 'viewer_history_sheet.dart';
import 'viewer_interlinear_body.dart';
import 'viewer_interlinear_settings.dart';
import 'viewer_interlinear_settings_sheet.dart';
import 'markup_settings_screen.dart';
import 'viewer_mode_popup.dart';
import 'viewer_reference_picker.dart';
import 'viewer_range_actions_sheet.dart';
import 'viewer_top_bar.dart';
import 'viewer_search_dialog.dart';
import 'viewer_search_models.dart';
import 'viewer_topic_picker.dart';

class BibleExplorerScreen extends StatefulWidget {
  const BibleExplorerScreen({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeChanged;

  @override
  State<BibleExplorerScreen> createState() => _BibleExplorerScreenState();
}

class _BibleExplorerScreenState extends State<BibleExplorerScreen> {
  static const double _minFontScale = 0.8;
  static const double _maxFontScale = 2.4;
  static const double _fontStep = 0.1;

  int _bookNumber = 1;
  int _chapter = 1;
  int _verse = 1;
  double _fontScale = 1.3;
  bool _interlinearEnabled = false;
  ViewerInterlinearSettings _interlinearSettings =
      const ViewerInterlinearSettings();
  bool _didRestoreHistory = false;
  bool _didLoadViewerSettings = false;
  bool _didLoadInterlinearSettings = false;
  String? _lastSearchTerm;
  VerseLine? _markupRangeStart;
  VerseLine? _markupRangeEnd;
  int _highlightRefreshTick = 0;
  late Future<PassageData> _passageFuture;

  @override
  void initState() {
    super.initState();
    _passageFuture = _loadPassage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<PassageData>(
        future: _passageFuture,
        builder: (context, snapshot) {
          final passage = snapshot.data;

          if (!_didRestoreHistory &&
              snapshot.connectionState == ConnectionState.done) {
            _didRestoreHistory = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _restoreLatestHistory();
            });
          }

          if (!_didLoadViewerSettings) {
            _didLoadViewerSettings = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadViewerSettings();
            });
          }

          if (!_didLoadInterlinearSettings) {
            _didLoadInterlinearSettings = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _loadInterlinearSettings();
            });
          }

          return SafeArea(
            child: Column(
              children: [
                ViewerTopBar(
                  bookName: passage?.bookName ?? 'Bible Explorer',
                  chapter: passage?.chapter ?? 0,
                  verse: passage == null ? null : _verse,
                  fontScale: _fontScale,
                  onSearch: () => _openSearch(context),
                  onTopics: () => _openTopics(context),
                  onChoosePassage: () => _openReferencePicker(context),
                ),
                Expanded(
                  child: _interlinearEnabled
                      ? ViewerInterlinearBody(
                          passage: passage,
                          selectedBookNumber: _bookNumber,
                          selectedChapter: _chapter,
                          selectedVerse: _verse,
                          fontScale: _fontScale,
                          settings: _interlinearSettings,
                          onSelectVerse: _selectLine,
                        )
                      : ViewerBody(
                          passage: passage,
                          selectedBookNumber: _bookNumber,
                          selectedChapter: _chapter,
                          selectedVerse: _verse,
                          fontScale: _fontScale,
                          onSelectVerse: _selectLine,
                          onSelectVerseNumber: _selectMarkupAnchor,
                          onTapSelectedRange: _openRangeActions,
                          selectedRangeStartBlockId: _markupRangeStart?.blockId,
                          selectedRangeEndBlockId:
                              (_markupRangeEnd ?? _markupRangeStart)?.blockId,
                          highlightRefreshTick: _highlightRefreshTick,
                        ),
                ),
                ViewerBottomBar(
                  onHistory: _openHistory,
                  onDecreaseFont: _decreaseFont,
                  onIncreaseFont: _increaseFont,
                  onMode: _openMode,
                  onMarkup: _openMarkupSettings,
                  canDecreaseFont: _fontScale > _minFontScale,
                  canIncreaseFont: _fontScale < _maxFontScale,
                  backgroundColor: Theme.of(context).bottomAppBarTheme.color ??
                      Theme.of(context).colorScheme.surface,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

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

  Future<void> _openReferencePicker(BuildContext context) async {
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
    final ViewerSearchSelection? selection = await showViewerSearchDialog(
      context,
      fontScale: _fontScale,
      lastSearchTerm: _lastSearchTerm,
    );
    if (selection == null || !mounted) return;
    setState(() {
      _bookNumber = selection.bookNumber;
      _chapter = selection.chapter;
      _verse = selection.verse;
      _lastSearchTerm = selection.lastSearchTerm;
      _passageFuture = _loadPassage();
    });
    _recordHistory();
  }

  Future<void> _openTopics(BuildContext context) async {
    final blockId = await showViewerTopicPicker(
      context,
      fontScale: _fontScale,
    );
    if (blockId == null || !mounted) return;
    final reference = await StudyBibleDatabase.instance.loadReferenceForBlockId(blockId);
    if (reference == null || !mounted) return;
    setState(() {
      _bookNumber = reference.bookNumber;
      _chapter = reference.chapter;
      _verse = reference.verse;
      _passageFuture = _loadPassage();
    });
    _recordHistory();
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

  void _decreaseFont() {
    setState(() {
      _fontScale = (_fontScale - _fontStep).clamp(_minFontScale, _maxFontScale);
    });
    AppSettingsService.instance.saveViewerFontScale(_fontScale);
  }

  void _increaseFont() {
    setState(() {
      _fontScale = (_fontScale + _fontStep).clamp(_minFontScale, _maxFontScale);
    });
    AppSettingsService.instance.saveViewerFontScale(_fontScale);
  }

  void _selectLine(VerseLine line) {
    final hasCompletedRange =
        _markupRangeStart != null && _markupRangeEnd != null;
    if (hasCompletedRange && _isLineInsideMarkupRange(line)) {
      _openRangeActions();
      return;
    }
    if (hasCompletedRange && !_isLineInsideMarkupRange(line)) {
      setState(() {
        _markupRangeStart = null;
        _markupRangeEnd = null;
      });
    }
    if (_markupRangeStart != null && _markupRangeEnd == null) {
      setState(() {
        _markupRangeStart = null;
        _markupRangeEnd = null;
      });
    }
    if (line.bookNumber == _bookNumber &&
        line.chapter == _chapter &&
        line.verse == _verse) {
      return;
    }
    setState(() {
      _bookNumber = line.bookNumber;
      _chapter = line.chapter;
      _verse = line.verse;
    });
    _recordHistory();
  }

  void _selectMarkupAnchor(VerseLine line) {
    final hasCompletedRange =
        _markupRangeStart != null && _markupRangeEnd != null;
    if (!hasCompletedRange && _markupRangeStart != null) {
      setState(() {
        _markupRangeEnd = line;
      });
      _showRangeActionMessage(
        'Range end set. Tap inside the highlighted range for actions.',
      );
      return;
    }

    setState(() {
      _markupRangeStart = line;
      _markupRangeEnd = null;
    });
    _showRangeActionMessage(
      'Range start set: ${line.chapter}:${line.verse}. Long-press end verse.',
    );
  }

  Future<void> _openRangeActions() async {
    final passage = await _passageFuture;
    if (!mounted) return;
    final start = _markupRangeStart;
    final end = _markupRangeEnd ?? _markupRangeStart;
    if (start == null || end == null) return;
    final startId = start.blockId ?? 0;
    final endId = end.blockId ?? 0;
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

    final verseRefs = selectedLines
        .map((line) => '${passage.bookName} ${line.chapter}:${line.verse}')
        .toList(growable: false);
    final label = _buildRangeLabel(
      passage.bookName,
      selectedLines.first,
      selectedLines.last,
    );
    final previewText =
        selectedLines.map((line) => '${line.verse} ${line.text}').join('\n');

    final action = await showViewerRangeActionsSheet(
      context,
      payload: ViewerRangeActionsPayload(
        label: label,
        previewText: previewText,
        startLabel: verseRefs.first,
        endLabel: verseRefs.last,
      ),
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
        final changed = await showHighlightPopup(
          context,
          verseRefs: verseRefs,
        );
        if (changed == true && mounted) {
          setState(() {
            _highlightRefreshTick += 1;
            _markupRangeStart = null;
            _markupRangeEnd = null;
          });
        }
        return;
      case ViewerRangeAction.clearMarkup:
        await _clearRangeMarkup(verseRefs);
        break;
      case ViewerRangeAction.addHashTag:
        _showRangeActionMessage('# tags are not wired in yet.');
        return;
      case ViewerRangeAction.addDollarTag:
        _showRangeActionMessage(r'$ tags are not wired in yet.');
        return;
      case ViewerRangeAction.addToMemory:
        await _addRangeToMemory(passage.bookName, selectedLines);
        break;
      case ViewerRangeAction.strongs:
        _showRangeActionMessage("Strong's is not wired for range actions yet.");
        return;
      case ViewerRangeAction.resetRange:
        break;
    }

    if (mounted) {
      setState(() {
        _markupRangeStart = null;
        _markupRangeEnd = null;
      });
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
    final startId = _markupRangeStart?.blockId ?? 0;
    final endId = _markupRangeEnd?.blockId ?? 0;
    final blockId = line.blockId ?? 0;
    if (startId <= 0 || endId <= 0 || blockId <= 0) return false;
    final low = startId < endId ? startId : endId;
    final high = startId < endId ? endId : startId;
    return blockId >= low && blockId <= high;
  }

  Future<void> _copyRangeToClipboard(
    List<VerseLine> lines, {
    required bool includeCitation,
  }) async {
    final passage = await _passageFuture;
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

  Future<void> _clearRangeMarkup(List<String> verseRefs) async {
    await HighlightsRepository().removeHighlightsForVerseRefs(verseRefs);
    if (!mounted) return;
    setState(() {
      _highlightRefreshTick += 1;
    });
    _showRangeActionMessage('Markup cleared for selected range.');
  }

  Future<void> _addRangeToMemory(
    String bookName,
    List<VerseLine> lines,
  ) async {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _restoreLatestHistory() async {
    final latest = await NavigationHistoryService.instance.fetchLatest();
    if (!mounted || latest == null) return;
    setState(() {
      _bookNumber = latest.book;
      _chapter = latest.chapter;
      _verse = latest.verse;
      _passageFuture = _loadPassage();
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
    final settings =
        await AppSettingsService.instance.loadVisualSettings(AppThemeMode.sepia);
    if (!mounted) return;
    setState(() {
      _fontScale = settings.viewerFontScale.clamp(_minFontScale, _maxFontScale);
    });
  }

  Future<void> _loadInterlinearSettings() async {
    final enabled = await AppSettingsService.instance.loadInterlinearEnabled();
    final settings = await AppSettingsService.instance.loadInterlinearSettings();
    if (!mounted) return;
    setState(() {
      _interlinearEnabled = enabled;
      _interlinearSettings = settings;
    });
  }

  Future<void> _openHistory() async {
    final entries = await HistoryLogService.instance.fetchHistory(limit: 100);
    if (!mounted || entries.isEmpty) return;

    final references = await StudyBibleDatabase.instance.loadReferencesForBlockIds(
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

  Future<void> _openMode() async {
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
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const BibleMemoryScreen(),
      ),
    );
  }

  Future<void> _openMarkupSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MarkupSettingsScreen(),
      ),
    );
  }

}

class PassageData {
  const PassageData({
    required this.bookNumber,
    required this.bookName,
    required this.chapter,
    required this.lines,
  });

  final int? bookNumber;
  final String bookName;
  final int chapter;
  final List<VerseLine> lines;
}

class VerseLine {
  const VerseLine({
    required this.blockId,
    required this.bookNumber,
    required this.chapter,
    required this.verse,
    required this.html,
    required this.text,
  });

  final int? blockId;
  final int bookNumber;
  final int chapter;
  final int verse;
  final String html;
  final String text;
}
