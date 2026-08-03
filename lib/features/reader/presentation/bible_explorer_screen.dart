import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/study_bible_database.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../library/presentation/library_screen.dart';
import '../../library/presentation/mac_reader_autoscroll_controller.dart';
import '../../library/presentation/mac_reader_autoscroll_controls.dart';
import '../../library/presentation/reader_tilt_autoscroll_controller.dart';
import '../../library/presentation/reader_tilt_autoscroll_controls.dart';
import '../../library/presentation/reader_tilt_motion_source.dart';
import '../../library/presentation/reader_tilt_preferences.dart';
import '../data/highlights_repository.dart';
import '../data/history_log_service.dart';
import '../data/navigation_history_service.dart';
import '../data/bible_memory_repository.dart';
import 'bible_memory_screen.dart';
import 'bible_visible_location_controller.dart';
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

class _BibleExplorerScreenState extends State<BibleExplorerScreen>
    with WidgetsBindingObserver {
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
  final CallbackReaderAutoScrollTarget _tiltScrollTarget =
      CallbackReaderAutoScrollTarget();
  late final ReaderTiltAutoScrollController _tiltAutoScroll;
  MacReaderAutoScrollController? _macAutoScroll;
  late final bool _usesMacAutoscroll;
  final FocusNode _readerFocusNode = FocusNode(
    debugLabel: 'bible-reader-keyboard-focus',
  );
  bool _readerShortcutsSuspended = false;
  int _lastMacAutoscrollStatusRevision = 0;
  final ReaderTiltPreferencesStore _tiltPreferencesStore =
      const ReaderTiltPreferencesStore();
  bool _isRapidTagApplying = false;
  bool _viewerReady = false;
  int? _anchorBlockId;
  int? _selectedBlockId;
  bool _selectedIsVisible = false;
  final Map<int, String> _bookNames = <int, String>{};
  final BibleLiveReferenceController _liveVisibleLocation =
      BibleLiveReferenceController();
  late final BibleLocationPersistenceCoordinator _locationPersistence;
  bool _wasTiltAutoScrollActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _locationPersistence = BibleLocationPersistenceCoordinator(
      writer: (location) => NavigationHistoryService.instance.saveSelection(
        blockId: location.blockId,
        book: location.bookNumber,
        chapter: location.chapter,
        verse: location.verse,
      ),
    );
    _tiltAutoScroll = ReaderTiltAutoScrollController(
      motionSource: PlatformReaderTiltMotionSource(),
      scrollTarget: _tiltScrollTarget,
    )..addListener(_onTiltAutoScrollChanged);
    _usesMacAutoscroll = Platform.isMacOS || Platform.isWindows;
    if (_usesMacAutoscroll) {
      _macAutoScroll = MacReaderAutoScrollController(
        scrollTarget: _tiltScrollTarget,
      )..addListener(_onMacAutoscrollChanged);
      AppSettingsService.instance.loadMacAutoscrollPreferences().then((value) {
        if (mounted) _macAutoScroll?.updatePreferences(value);
      });
    }
    _loadTiltPreferences();
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
                            style: TextStyle(color: theme.colorScheme.error),
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
    final baseBibleFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale;

    final reader = PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_locationPersistence.resumeAndFlush());
        }
      },
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: Column(
                children: [
                  ValueListenableBuilder<BibleVisibleLocation?>(
                    valueListenable: _liveVisibleLocation,
                    builder: (context, liveLocation, _) {
                      final displayLocation = resolveBibleReaderLocation(
                        visibleLocation: liveLocation,
                        fallbackLocation: BibleVisibleLocation(
                          blockId: _anchorBlockId!,
                          bookNumber: _bookNumber,
                          chapter: _chapter,
                          verse: _verse,
                        ),
                        bookNamesByNumber: _bookNames,
                      );
                      return ViewerTopBar(
                        bookName: displayLocation.bookName,
                        chapter: displayLocation.chapter,
                        verse: displayLocation.verse,
                        fontScale: _fontScale,
                        baseBibleFontSize: baseBibleFontSize,
                        onSearch: () {
                          _stopReaderAutoscroll();
                          _openSearch(context);
                        },
                        bibleSearchSession: _activeBibleSearchSession,
                        onPreviousBibleSearchHit: () =>
                            _navigateBibleSearchHit(-1),
                        onNextBibleSearchHit: () => _navigateBibleSearchHit(1),
                        onSavedPresentations: () {
                          _stopReaderAutoscroll();
                          _openSavedPresentations();
                        },
                        onStandardTag: () {
                          _stopReaderAutoscroll();
                          _openTagButton();
                        },
                        onDollarTag: () {
                          _stopReaderAutoscroll();
                          _openDollarTagButton();
                        },
                        onRapidTag: () {
                          _stopReaderAutoscroll();
                          _openRapidTagButton();
                        },
                        activeFamily: null,
                        onTopics: () {
                          _stopReaderAutoscroll();
                          _openTopics(context);
                        },
                        onChoosePassage: () {
                          _stopReaderAutoscroll();
                          _openReferencePicker(context);
                        },
                      );
                    },
                  ),
                  ReaderTiltAutoScrollActiveIndicator(
                    controller: _tiltAutoScroll,
                  ),
                  Expanded(
                    child: Listener(
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (_) {
                        if (_usesMacAutoscroll) {
                          _readerFocusNode.requestFocus();
                        }
                        if (_tiltAutoScroll.isActive) {
                          _tiltAutoScroll.showStatusBanner();
                        }
                      },
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
                              onSelectVerseNumberLongPressMove:
                                  _dragVerseAnchor,
                              onSelectTokenLongPress: _selectTokenAnchor,
                              onSelectTokenLongPressMove: _dragTokenAnchor,
                              onTapSelectedRange: _openRangeActions,
                              rangeSelection: _rangeSelection,
                              highlightRefreshTick: _highlightRefreshTick,
                              navigationTick: _navigationTick,
                              autoScrollTarget: _tiltScrollTarget,
                              onManualScroll: () {
                                _liveVisibleLocation.clearSelected();
                                _macAutoScroll?.stopForManualInteraction();
                                _tiltAutoScroll.stopForManualInteraction();
                              },
                            ),
                    ),
                  ),
                  ViewerBottomBar(
                    themeMode: widget.themeMode,
                    onToggleThemeMode: _toggleThemeMode,
                    bookNumber: _bookNumber,
                    interlinearEnabled: _interlinearEnabled,
                    onToggleInterlinear: _toggleInterlinearMode,
                    onHistory: () {
                      _stopReaderAutoscroll();
                      _openHistory();
                    },
                    onLibrary: () {
                      _stopReaderAutoscroll();
                      _openLibrary();
                    },
                    onDecreaseFont: _decreaseFont,
                    onIncreaseFont: _increaseFont,
                    tiltAutoScrollController: _tiltAutoScroll,
                    onToggleTiltAutoScroll: _toggleTiltAutoScroll,
                    onOpenTiltAutoScrollSettings: _openTiltSettings,
                    macAutoScrollController: _macAutoScroll,
                    onToggleMacAutoScroll: _toggleMacAutoscroll,
                    onOpenMacAutoScrollSettings: _openMacAutoscrollSettings,
                    onCommentary: () {
                      _stopReaderAutoscroll();
                      _openCommentary();
                    },
                    onMode: () {
                      _stopReaderAutoscroll();
                      _openMode();
                    },
                    canDecreaseFont: _fontScale > _minFontScale,
                    canIncreaseFont: _fontScale < _maxFontScale,
                    backgroundColor:
                        Theme.of(context).bottomAppBarTheme.color ??
                        Theme.of(context).colorScheme.surface,
                  ),
                ],
              ),
            ),
            if (_macAutoScroll != null)
              MacReaderAutoscrollStatusOverlay(
                controller: _macAutoScroll!,
                foregroundColor: theme.colorScheme.onSurface,
                backgroundColor: theme.colorScheme.surface,
              ),
          ],
        ),
      ),
    );
    final guardedReader = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        reader,
        ReaderAutoscrollTapShield(
          listenables: <Listenable>[_tiltAutoScroll, ?_macAutoScroll],
          isScrolling: () =>
              _tiltAutoScroll.isActive ||
              (_macAutoScroll?.isScrolling ?? false),
          onStop: _stopReaderAutoscroll,
        ),
      ],
    );
    if (!_usesMacAutoscroll) return guardedReader;
    return Focus(
      focusNode: _readerFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
        event: event,
        readerFocusNode: node,
        controller: _macAutoScroll!,
        suspended: _readerShortcutsSuspended || _interlinearEnabled,
      ),
      child: guardedReader,
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
    _stopReaderAutoscroll();
    final next = !_interlinearEnabled;
    setState(() {
      _interlinearEnabled = next;
    });
    AppSettingsService.instance.saveInterlinearEnabled(next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _macAutoScroll
      ?..removeListener(_onMacAutoscrollChanged)
      ..dispose();
    _tiltAutoScroll
      ..removeListener(_onTiltAutoScrollChanged)
      ..dispose();
    _readerFocusNode.dispose();
    _liveVisibleLocation.dispose();
    _locationPersistence.dispose();
    super.dispose();
  }

  void _onTiltAutoScrollChanged() {
    _updateAutoscrollPersistenceSuspension();
  }

  void _updateAutoscrollPersistenceSuspension() {
    final active =
        _tiltAutoScroll.isActive || (_macAutoScroll?.isActive ?? false);
    if (active == _wasTiltAutoScrollActive) return;
    _wasTiltAutoScrollActive = active;
    _locationPersistence.setSuspended(active);
    if (!active) {
      unawaited(_locationPersistence.resumeAndFlush());
    }
  }

  void _onMacAutoscrollChanged() {
    final controller = _macAutoScroll;
    if (!mounted || controller == null) return;
    _updateAutoscrollPersistenceSuspension();
    if (controller.statusRevision == _lastMacAutoscrollStatusRevision) return;
    _lastMacAutoscrollStatusRevision = controller.statusRevision;
    unawaited(
      AppSettingsService.instance.saveMacAutoscrollPreferences(
        MacAutoscrollPreferences(
          baseSpeed: controller.baseSpeed,
          lastNonzeroStep: controller.lastNonzeroStep,
          maximumStep: controller.maximumStep,
          statusBannerMode: controller.statusBannerMode,
        ),
      ),
    );
  }

  void _toggleMacAutoscroll() {
    if (!_macAutoScroll!.isActive) {
      _tiltAutoScroll.stop(notify: false);
    }
    _macAutoScroll!.toggle();
    _readerFocusNode.requestFocus();
  }

  Future<void> _openMacAutoscrollSettings() async {
    if (!Platform.isMacOS && _tiltAutoScroll.motionSource.isSupported) {
      await _openTiltSettings();
      return;
    }
    final controller = _macAutoScroll!;
    _readerShortcutsSuspended = true;
    final result = await showMacAutoscrollSettingsDialog(
      context: context,
      initial: MacAutoscrollPreferences(
        baseSpeed: controller.baseSpeed,
        lastNonzeroStep: controller.lastNonzeroStep,
        maximumStep: controller.maximumStep,
        statusBannerMode: controller.statusBannerMode,
      ),
    );
    if (!mounted) return;
    _readerShortcutsSuspended = false;
    if (result != null) {
      controller.updatePreferences(result);
      await AppSettingsService.instance.saveMacAutoscrollPreferences(result);
    }
    _readerFocusNode.requestFocus();
  }

  void _stopReaderAutoscroll() {
    _macAutoScroll?.stopForManualInteraction();
    _tiltAutoScroll.stop();
  }

  void _toggleTiltAutoScroll() {
    if (_tiltAutoScroll.isActive) {
      _tiltAutoScroll.stop();
    } else {
      _macAutoScroll?.stopWithoutNotification();
      _tiltAutoScroll.activate();
    }
  }

  Future<void> _loadTiltPreferences() async {
    final preferences = await _tiltPreferencesStore.load();
    if (mounted) {
      _tiltAutoScroll.updatePreferences(preferences, showBanner: false);
    }
  }

  Future<void> _saveTiltPreferences(ReaderTiltPreferences preferences) async {
    _tiltAutoScroll.updatePreferences(preferences);
    await _tiltPreferencesStore.save(preferences);
  }

  Future<void> _openTiltSettings() async {
    await _tiltAutoScroll.stop();
    if (!mounted) return;
    await showReaderTiltSettingsSheet(
      context,
      preferences: _tiltAutoScroll.preferences,
      includeChapterTilt: false,
      onChanged: _saveTiltPreferences,
      onRecalibrate: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tiltAutoScroll.activate();
        });
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _stopReaderAutoscroll();
      unawaited(_locationPersistence.resumeAndFlush());
    }
  }

  @override
  void deactivate() {
    if (_macAutoScroll?.isActive ?? false) {
      _macAutoScroll?.stopWithoutNotification();
      _updateAutoscrollPersistenceSuspension();
    }
    _tiltAutoScroll.removeListener(_onTiltAutoScrollChanged);
    _tiltAutoScroll.stop(notify: false);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _tiltAutoScroll.addListener(_onTiltAutoScrollChanged);
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
