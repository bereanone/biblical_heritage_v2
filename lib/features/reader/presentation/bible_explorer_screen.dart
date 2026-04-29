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
  int _bookNumber = 1;
  int _chapter = 1;
  int _verse = 1;
  double _fontScale = 1.3;
  bool _interlinearEnabled = false;
  ViewerInterlinearSettings _interlinearSettings =
      const ViewerInterlinearSettings();
  PresentationAspectRatioPreset _presentationAspectRatio =
      PresentationAspectRatioPreset.auto;
  bool _didRestoreHistory = false;
  bool _didLoadViewerSettings = false;
  bool _didLoadInterlinearSettings = false;
  String? _lastSearchTerm;
  ViewerRangeSelection _rangeSelection = const ViewerRangeSelection();
  int _highlightRefreshTick = 0;
  int _navigationTick = 0;
  int? _defaultHighlightGroupId;
  int _lastTagTabIndex = 0;
  final RapidTagState _rapidTagState = RapidTagState();
  bool _isRapidTagApplying = false;
  late Future<PassageData> _passageFuture;

  @override
  void initState() {
    super.initState();
    _passageFuture = _loadPassage();
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
                  onStandardTag: _openTagButton,
                  onDollarTag: _openDollarTagButton,
                  onRapidTag: _openRapidTagButton,
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
                          navigationTick: _navigationTick,
                        )
                      : ViewerBody(
                          passage: passage,
                          selectedBookNumber: _bookNumber,
                          selectedChapter: _chapter,
                          selectedVerse: _verse,
                          fontScale: _fontScale,
                          onSelectVerse: _selectLine,
                          onSelectVerseNumber: _selectMarkupAnchor,
                          onSelectTokenLongPress: _selectTokenAnchor,
                          onTapSelectedRange: _openRangeActions,
                          rangeSelection: _rangeSelection,
                          highlightRefreshTick: _highlightRefreshTick,
                          navigationTick: _navigationTick,
                        ),
                ),
                ViewerBottomBar(
                  onHistory: _openHistory,
                  onDecreaseFont: _decreaseFont,
                  onIncreaseFont: _increaseFont,
                  onMode: _openMode,
                  onMarkup: _applyDefaultMarkup,
                  canDecreaseFont: _fontScale > _minFontScale,
                  canIncreaseFont: _fontScale < _maxFontScale,
                  backgroundColor:
                      Theme.of(context).bottomAppBarTheme.color ??
                      Theme.of(context).colorScheme.surface,
                ),
              ],
            ),
          );
        },
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
    return _passageFuture;
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
      final result = await repository.quickApplyTargets(
        targets: targets,
        tag: defaultTag,
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
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tagged ${result.inserted} verse(s) with ${result.tag}'
            '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
          ),
        ),
      );
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open # tags: $error')));
    }
  }

  Future<void> _openDollarTagButton() async {
    try {
      final navigator = Navigator.of(context);
      final passage = await _currentPassageOrLoad();
      if (!mounted) return;
      final targets = _currentTagTargets(passage);
      final repository = DollarTagRepository();
      final defaultTag = await repository.loadDefaultTag();
      if (!mounted) return;
      await _showTagScreen(
        navigator: navigator,
        passage: passage,
        targets: targets,
        launchMode: HashTagLaunchMode.studyChain,
        tagSymbol: r'$',
        initialTag: defaultTag,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open \$ tags: $error')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open rapid # tags: $error')),
      );
    }
  }
}
