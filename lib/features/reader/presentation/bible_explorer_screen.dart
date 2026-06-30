import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../library/presentation/library_screen.dart';
import '../data/highlights_repository.dart';
import '../data/history_log_service.dart';
import '../data/navigation_history_service.dart';
import '../data/bible_memory_repository.dart';
import 'bible_memory_screen.dart';
import 'highlight_popup.dart';
import 'viewer_body.dart';
import 'viewer_bottom_bar.dart';
import 'commentary_research_screen.dart';
import 'viewer_data_controller.dart';
import 'viewer_history_sheet.dart';
import 'viewer_interlinear_body.dart';
import 'viewer_interlinear_settings.dart';
import 'viewer_interlinear_settings_sheet.dart';
import 'markup_settings_screen.dart';
import 'bible_explorer_range_interaction.dart';
import 'viewer_mode_popup.dart';
import 'viewer_presentation_settings.dart';
import 'viewer_reference_picker.dart';
import 'viewer_range_actions_sheet.dart';
import 'viewer_range_selection.dart';
import 'viewer_markup_applier.dart';
import 'viewer_markup_span_builder.dart';
import 'viewer_passage_models.dart';
import 'viewer_strongs_launcher.dart';
import 'viewer_top_bar.dart';
import 'viewer_search_dialog.dart';
import 'viewer_search_models.dart';
import 'viewer_topic_picker.dart';
import 'presentation_prep/presentation_ui_helpers.dart';
import 'presentation_prep/tag_presentation_prep_launcher.dart';
import 'presentation_prep/tag_presentation_prep_models.dart';
import 'presentation_prep/tag_saved_presentations_screen.dart';
import 'rapid_tag_state.dart';
import 'tag_quick_apply_helper.dart';
import 'tag_screen_launcher.dart';

part 'bible_explorer_navigation.dart';
part 'bible_explorer_range_actions.dart';

const double _minFontScale = 0.8;
const double _maxFontScale = 2.4;
const double _fontStep = 0.1;

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
  String _viewerStatus = 'Loading Bible Explorer...';
  String? _viewerLoadError;
  int _bookNumber = 1;
  int _chapter = 1;
  int _verse = 1;
  double _fontScale = 1.3;
  bool _interlinearEnabled = false;
  ViewerInterlinearSettings _interlinearSettings =
      const ViewerInterlinearSettings();
  PresentationAspectRatioPreset _presentationAspectRatio =
      PresentationAspectRatioPreset.auto;
  String? _lastSearchTerm;
  BibleSearchSession? _activeBibleSearchSession;
  bool _isBibleSearchNavigationActive = false;
  ViewerRangeSelection _rangeSelection = const ViewerRangeSelection();
  int _highlightRefreshTick = 0;
  int _navigationTick = 0;
  int? _defaultHighlightGroupId;
  int _lastTagTabIndex = 0;
  final RapidTagState _rapidTagState = RapidTagState();
  final ViewerDataController _viewerData = ViewerDataController();
  bool _isRapidTagApplying = false;
  bool _viewerReady = false;
  int? _anchorBlockId;
  int? _selectedBlockId;
  bool _selectedIsVisible = false;
  int? _headerPinnedBlockId;
  Timer? _headerPinTimer;
  final Map<int, String> _bookNames = <int, String>{};

  @override
  void initState() {
    super.initState();
    _initializeViewer();
    _loadViewerSettings();
    _loadInterlinearSettings();
    AppSettingsService.instance.loadDefaultHighlightGroupId().then((id) {
      if (mounted) setState(() => _defaultHighlightGroupId = id);
    });
    AppSettingsService.instance.loadLastTagTabIndex().then((index) {
      if (!mounted) return;
      setState(() => _lastTagTabIndex = index.clamp(0, 1).toInt());
    });
    AppSettingsService.instance.loadPresentationAspectRatioPreset().then((
      preset,
    ) {
      if (!mounted) return;
      setState(() => _presentationAspectRatio = preset);
    });
  }

  void _bumpMarkupRefresh() {
    if (!mounted) return;
    setState(() {
      _highlightRefreshTick += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_viewerReady || _anchorBlockId == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          _viewerLoadError == null
                              ? _viewerStatus
                              : 'Bible Explorer could not finish loading.',
                          textAlign: TextAlign.center,
                        ),
                        if (_viewerLoadError != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(
                            _viewerLoadError!,
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
                              onPressed: _initializeViewer,
                              child: const Text('Retry'),
                            ),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                              child: const Text('Back'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final passage = _buildCurrentPassage();
    final displayLine = _displayHeaderLine();
    final displayBookNumber = displayLine?.bookNumber ?? _bookNumber;
    final displayBookName = _bookNames[displayBookNumber] ?? 'Bible Explorer';
    final displayChapter = displayLine?.chapter ?? _chapter;
    final displayVerse = displayLine?.verse ?? _verse;
    final baseBibleFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewerTopBar(
              bookName: displayBookName,
              chapter: displayChapter,
              verse: displayVerse,
              fontScale: _fontScale,
              baseBibleFontSize: baseBibleFontSize,
              onSearch: () => _openSearch(context),
              bibleSearchSession: _activeBibleSearchSession,
              onPreviousBibleSearchHit: () => _navigateBibleSearchHit(-1),
              onNextBibleSearchHit: () => _navigateBibleSearchHit(1),
              onSavedPresentations: _openSavedPresentations,
              onStandardTag: _openTagButton,
              onDollarTag: _openDollarTagButton,
              onRapidTag: _openRapidTagButton,
              activeFamily: null,
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
                      onSelectBlockId: _openBlockId,
                      onTapSelectedRange: _openRangeActions,
                      rangeSelection: _rangeSelection,
                      highlightRefreshTick: _highlightRefreshTick,
                      navigationTick: _navigationTick,
                    )
                  : ViewerBody(
                      anchorBlockId: _anchorBlockId!,
                      data: _viewerData,
                      bookNamesByNumber: _bookNames,
                      selectedBlockId: _selectedBlockId,
                      fontScale: _fontScale,
                      onVisibleIdChanged: _handleVisibleBlockChanged,
                      onSelectionVisibilityChanged:
                          _handleSelectedVisibilityChanged,
                      onSelectVerse: _selectLine,
                      onSelectVerseNumber: _selectMarkupAnchor,
                      onSelectVerseNumberLongPressMove: _dragVerseAnchor,
                      onSelectTokenLongPress: _selectTokenAnchor,
                      onSelectTokenLongPressMove: _dragTokenAnchor,
                      onTapSelectedRange: _openRangeActions,
                      rangeSelection: _rangeSelection,
                      highlightRefreshTick: _highlightRefreshTick,
                      navigationTick: _navigationTick,
                    ),
            ),
            ViewerBottomBar(
              themeMode: widget.themeMode,
              onToggleThemeMode: _toggleThemeMode,
              bookNumber: _bookNumber,
              interlinearEnabled: _interlinearEnabled,
              onToggleInterlinear: _toggleInterlinearMode,
              onHistory: _openHistory,
              onLibrary: _openLibrary,
              onDecreaseFont: _decreaseFont,
              onIncreaseFont: _increaseFont,
              onCommentary: _openCommentary,
              onMode: _openMode,
              canDecreaseFont: _fontScale > _minFontScale,
              canIncreaseFont: _fontScale < _maxFontScale,
              backgroundColor:
                  Theme.of(context).bottomAppBarTheme.color ??
                  Theme.of(context).colorScheme.surface,
            ),
          ],
        ),
      ),
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

  void _toggleThemeMode() {
    final next = widget.themeMode == AppThemeMode.night
        ? AppThemeMode.sepia
        : AppThemeMode.night;
    widget.onThemeChanged(next);
  }

  void _toggleInterlinearMode() {
    final next = !_interlinearEnabled;
    setState(() {
      _interlinearEnabled = next;
    });
    AppSettingsService.instance.saveInterlinearEnabled(next);
  }

  void _pinHeaderToSelectedVerse(int? blockId) {
    _headerPinTimer?.cancel();
    if (mounted) {
      setState(() {
        _headerPinnedBlockId = blockId;
      });
    } else {
      _headerPinnedBlockId = blockId;
    }
    if (blockId == null) return;
    _headerPinTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        if (_headerPinnedBlockId == blockId) {
          _headerPinnedBlockId = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _headerPinTimer?.cancel();
    super.dispose();
  }

  Future<void> _openCommentary() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommentaryResearchScreen(
          bookId: _bookNumber,
          chapter: _chapter,
          verse: _verse,
          bookName: _bookNames[_bookNumber] ?? 'Book $_bookNumber',
          fontScale: _fontScale,
        ),
      ),
    );
  }

  Future<void> _saveLastTagTabIndex(int index) async {
    final normalized = index.clamp(0, 1).toInt();
    if (_lastTagTabIndex == normalized) return;
    setState(() {
      _lastTagTabIndex = normalized;
    });
    await AppSettingsService.instance.saveLastTagTabIndex(normalized);
  }

  void _resetRapidTagArmed() {
    if (!_rapidTagState.isArmed) return;
    setState(() {
      _rapidTagState.reset();
    });
  }

  Future<PassageData> _currentPassageOrLoad() async {
    return _buildCurrentPassage();
  }

  PassageData _buildCurrentPassage() {
    final lines = _viewerData.loadedLines;
    return PassageData(
      bookNumber: _bookNumber,
      bookName: _bookNames[_bookNumber] ?? 'Book $_bookNumber',
      chapter: _chapter,
      lines: lines,
    );
  }

  VerseLine? _displayHeaderLine() {
    final pinnedBlockId = _headerPinnedBlockId;
    if (pinnedBlockId != null) {
      final pinnedLine = _viewerData.getBlock(pinnedBlockId);
      if (pinnedLine != null) return pinnedLine;
    }
    final selectedBlockId = _selectedBlockId;
    if (_selectedIsVisible && selectedBlockId != null && selectedBlockId > 0) {
      final selectedLine = _viewerData.getBlock(selectedBlockId);
      if (selectedLine != null) {
        return selectedLine;
      }
    }
    return null;
  }

  void _handleSelectedVisibilityChanged(bool isVisible) {
    if (_selectedIsVisible == isVisible || !mounted) return;
    setState(() {
      _selectedIsVisible = isVisible;
    });
  }

  List<HashTagTarget> _currentTagTargets(PassageData passage) {
    final selection = HashTagRepository().buildSelectionTargets(
      passage: passage,
      selection: _rangeSelection,
      currentBookNumber: _bookNumber,
      currentChapter: _chapter,
      currentVerse: _verse,
    );
    return selection;
  }

  Future<void> _showTagScreen({
    required NavigatorState navigator,
    required PassageData passage,
    required List<HashTagTarget> targets,
    required HashTagLaunchMode launchMode,
    String tagSymbol = '#',
    String? initialTag,
  }) {
    final launcher = tagSymbol == r'$'
        ? showDollarTagScreen
        : showHashTagScreen;
    return launcher(
      navigator,
      passage: passage,
      selection: _rangeSelection,
      selectionTargets: targets,
      fontScale: _fontScale,
      initialTabIndex: _lastTagTabIndex,
      launchMode: launchMode,
      onTagTabChanged: _saveLastTagTabIndex,
      initialTag: initialTag,
      onSelectBlockId: _openBlockId,
    );
  }

  Future<void> _applyRapidTagTargets({
    required NavigatorState navigator,
    required PassageData passage,
    required List<HashTagTarget> targets,
    required HashTagRepository repository,
    required String defaultTag,
  }) async {
    setState(() {
      _isRapidTagApplying = true;
    });
    try {
      final defaultCategory = await repository.loadDefaultTagCategory();
      final result = await repository.quickApplyTargets(
        targets: targets,
        tag: defaultTag,
        category: defaultCategory,
      );
      if (!mounted) return;
      if (result.tag == null) {
        await _showTagScreen(
          navigator: navigator,
          passage: passage,
          targets: targets,
          launchMode: HashTagLaunchMode.scriptureOnly,
          initialTag: defaultTag,
        );
        _bumpMarkupRefresh();
        return;
      }
      showReadableSnackBar(
        context,
        result.inserted == 0 && result.skipped > 0
            ? 'Already in ${result.tag}'
            : 'Tagged ${result.tag}',
        fontScale: _fontScale,
        isRapid: true,
      );
      _bumpMarkupRefresh();
    } finally {
      if (mounted) {
        setState(() {
          _isRapidTagApplying = false;
        });
      } else {
        _isRapidTagApplying = false;
      }
    }
  }

  Future<void> _openTagButton() async {
    try {
      final navigator = Navigator.of(context);
      final passage = await _currentPassageOrLoad();
      if (!mounted) return;
      final targets = _currentTagTargets(passage);
      final repository = HashTagRepository();
      final defaultTag = await repository.loadDefaultTag();
      if (!mounted) return;
      await _showTagScreen(
        navigator: navigator,
        passage: passage,
        targets: targets,
        launchMode: HashTagLaunchMode.scriptureOnly,
        initialTag: defaultTag,
      );
      _bumpMarkupRefresh();
    } catch (error) {
      if (!mounted) return;
      showReadableSnackBar(
        context,
        'Could not open # tags: $error',
        fontScale: _fontScale,
      );
    }
  }

  Future<void> _openDollarTagButton() async {
    try {
      final repository = HashTagRepository();
      final defaultTag = await repository.loadDefaultTag();
      if (!mounted) return;
      final selectedTag = defaultTag?.trim() ?? '';
      if (selectedTag.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Presentation Setup'),
              content: const Text(
                'Create or select a #tag study chain before preparing a presentation.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
        return;
      }
      await openTagPresentationPrep(
        context,
        request: TagPresentationPrepRequest(tagName: selectedTag),
      );
    } catch (error) {
      if (!mounted) return;
      showReadableSnackBar(
        context,
        'Could not open presentation setup: $error',
        fontScale: _fontScale,
      );
    }
  }

  Future<void> _openRapidTagButton() async {
    if (_isRapidTagApplying) return;
    try {
      final navigator = Navigator.of(context);
      final passage = await _currentPassageOrLoad();
      if (!mounted) return;
      final targets = _currentTagTargets(passage);
      final repository = HashTagRepository();
      final defaultTag = await repository.loadDefaultTag();
      if (!mounted) return;

      if (defaultTag == null) {
        await _showTagScreen(
          navigator: navigator,
          passage: passage,
          targets: targets,
          launchMode: HashTagLaunchMode.scriptureOnly,
          initialTag: null,
        );
        _bumpMarkupRefresh();
        return;
      }

      await _applyRapidTagTargets(
        navigator: navigator,
        passage: passage,
        targets: targets,
        repository: repository,
        defaultTag: defaultTag,
      );
    } catch (error) {
      if (!mounted) return;
      showReadableSnackBar(
        context,
        'Could not open rapid # tags: $error',
        fontScale: _fontScale,
      );
    }
  }
}
