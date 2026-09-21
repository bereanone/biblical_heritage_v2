import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/audio/narration_diagnostics.dart';
import '../../../core/audio/narration_media_session.dart';
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
import '../../library/presentation/speech_tilt_binding.dart';
import '../data/highlights_repository.dart';
import '../data/history_log_service.dart';
import '../data/navigation_history_service.dart';
import '../data/bible_memory_repository.dart';
import 'bible_memory_screen.dart';
import 'bible_narration_media_controls.dart';
import 'bible_visible_location_controller.dart';
import 'kokoro_mac_test_narrator.dart';
import 'pronunciation_editor.dart';
import 'narration_pronunciation.dart';
import 'highlight_popup.dart';
import 'viewer_body.dart';
import 'viewer_bottom_bar.dart';
import 'commentary_research_screen.dart';
import 'cross_reference_panel.dart';
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
import 'viewer_selection_clipboard.dart';
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
import 'reader_autoscroll_diagnostics.dart';
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
  late final KokoroMacTestNarrator _kokoroNarrator;
  int _narrationSession = 0;
  int? _narrationBlockId;
  bool _narrationRunning = false;
  bool _narrationPrimed = false;
  bool _lastAudioEnabled = false;
  late final Future<void> _pronunciationsReady;
  final List<int> _crossReferenceReturnBlockIds = <int>[];
  late final BibleLocationPersistenceCoordinator _locationPersistence;
  bool _wasTiltAutoScrollActive = false;
  SpeechTiltBinding? _speechTilt;
  BibleNarrationMediaControls? _narrationMedia;

  @override
  void initState() {
    super.initState();
    _kokoroNarrator = KokoroMacTestNarrator(
      onPlaybackComplete: _advanceNarration,
      onError: _narrationFailed,
    );
    _pronunciationsReady = AppSettingsService.instance
        .loadRawSetting('narration_pronunciations_v1')
        .then((value) async {
          final rules = decodeNarrationPronunciations(value);
          _kokoroNarrator.pronunciationCorrections = rules;
          _kokoroNarrator.deferredPronunciationCorrections =
              await loadDeferredNarrationPronunciations(
                rules: rules,
                load: AppSettingsService.instance.loadRawSetting,
                save: AppSettingsService.instance.saveRawSetting,
              );
        });
    WidgetsBinding.instance.addObserver(this);
    _locationPersistence = BibleLocationPersistenceCoordinator(
      writer: (location) => NavigationHistoryService.instance.saveSelection(
        blockId: location.blockId,
        book: location.bookNumber,
        chapter: location.chapter,
        verse: location.verse,
      ),
    );
    _liveVisibleLocation.addListener(_onLiveVerseChanged);
    _tiltAutoScroll = ReaderTiltAutoScrollController(
      motionSource: PlatformReaderTiltMotionSource(),
      scrollTarget: _tiltScrollTarget,
    )..addListener(_onTiltAutoScrollChanged);
    // narrationControlsPacing below is unconditionally true, so on every
    // platform this controller runs in narration mode (block-advance on
    // speech completion), never continuous pixel autoscroll — safe to widen
    // to iOS now that the Kokoro engine is confirmed to synthesize audio
    // there (see kokoro_speech_worker.dart's platform-conditional `lang`).
    _usesMacAutoscroll =
        Platform.isMacOS || Platform.isWindows || Platform.isIOS;
    if (_usesMacAutoscroll) {
      _macAutoScroll = MacReaderAutoScrollController(
        scrollTarget: _tiltScrollTarget,
        narrationControlsPacing: true,
      )..addListener(_onMacAutoscrollChanged);
      AppSettingsService.instance.loadMacAutoscrollPreferences().then((value) {
        if (mounted) _macAutoScroll?.updatePreferences(value);
      });
    }
    if (Platform.isIOS && _macAutoScroll != null) {
      _speechTilt = SpeechTiltBinding(
        _macAutoScroll!,
        _tiltAutoScroll,
        (rate) => unawaited(_kokoroNarrator.setLiveRate(rate)),
      );
      _narrationMedia = BibleNarrationMediaControls(
        autoscroll: _macAutoScroll!,
        location: _liveVisibleLocation,
        bookNames: _bookNames,
        skip: (delta) => unawaited(_skipNarration(delta)),
      );
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
      canPop: _crossReferenceReturnBlockIds.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          unawaited(_locationPersistence.resumeAndFlush());
        } else if (_crossReferenceReturnBlockIds.isNotEmpty) {
          final sourceBlockId = _crossReferenceReturnBlockIds.removeLast();
          unawaited(_navigateToBlockId(sourceBlockId, recordHistory: false));
          setState(() {});
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
                        _macAutoScroll?.pauseNarrationForInteraction();
                        if (_usesMacAutoscroll) {
                          _readerFocusNode.requestFocus();
                        }
                        if (_tiltAutoScroll.isActive) {
                          _tiltAutoScroll.showStatusBanner();
                        }
                      },
                      child: _interlinearEnabled
                          ? ViewerInterlinearBody(
                              key: ValueKey(
                                'interlinear-reader-$_navigationTick',
                              ),
                              passage: passage,
                              selectedBookNumber: _bookNumber,
                              selectedChapter: _chapter,
                              selectedVerse: _verse,
                              fontScale: _fontScale,
                              settings: _interlinearSettings,
                              onSelectVerse: _selectLine,
                              onOpenCrossReferences: _openCrossReferences,
                              onSelectBlockId: _openBlockId,
                              onTapSelectedRange: _openRangeActions,
                              rangeSelection: _rangeSelection,
                              highlightRefreshTick: _highlightRefreshTick,
                              navigationTick: _navigationTick,
                            )
                          : ViewerBody(
                              key: ValueKey('standard-reader-$_navigationTick'),
                              anchorBlockId: _anchorBlockId!,
                              data: _viewerData,
                              bookNamesByNumber: _bookNames,
                              selectedBlockId: _selectedBlockId,
                              fontScale: _fontScale,
                              onVisibleIdChanged: _handleVisibleBlockChanged,
                              onSelectionVisibilityChanged:
                                  _handleSelectedVisibilityChanged,
                              onSelectVerse: _selectLine,
                              onOpenCrossReferences: _openCrossReferences,
                              onSelectVerseNumber: _selectMarkupAnchor,
                              onSelectVerseNumberLongPressMove:
                                  _dragVerseAnchor,
                              onSelectTokenLongPress: _selectTokenAnchor,
                              onTokenLongPressEnd: _finishTokenSelection,
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
                  if (_macAutoScroll != null) _speechControls(),
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
            if (!kReleaseMode && _showAutoScrollDiagnosticPanel)
              _AutoScrollDiagnosticPanel(controller: _tiltAutoScroll),
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
              (_macAutoScroll?.isPixelScrolling ?? false),
          onStop: _stopReaderAutoscroll,
          bottomInset: (_macAutoScroll?.audioEnabled ?? false)
              ? 120
              : kBottomNavigationBarHeight,
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
    _speechTilt?.dispose();
    _narrationMedia?.dispose();
    _macAutoScroll
      ?..removeListener(_onMacAutoscrollChanged)
      ..dispose();
    _tiltAutoScroll
      ..removeListener(_onTiltAutoScrollChanged)
      ..dispose();
    _readerFocusNode.dispose();
    _liveVisibleLocation.dispose();
    _kokoroNarrator.dispose();
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
    if (_lastAudioEnabled != controller.audioEnabled) {
      setState(() => _lastAudioEnabled = controller.audioEnabled);
    }
    _updateAutoscrollPersistenceSuspension();
    _syncKokoroNarration();
    if (controller.statusRevision == _lastMacAutoscrollStatusRevision) return;
    _lastMacAutoscrollStatusRevision = controller.statusRevision;
    unawaited(
      AppSettingsService.instance.saveMacAutoscrollPreferences(
        MacAutoscrollPreferences(
          baseSpeed: controller.baseSpeed,
          lastNonzeroStep: controller.lastNonzeroStep,
          maximumStep: controller.maximumStep,
          statusBannerMode: controller.statusBannerMode,
          audioEnabled: controller.audioEnabled,
          speechRate: controller.speechRate,
          announceChapter: controller.announceChapter,
          announceVerseNumbers: controller.announceVerseNumbers,
        ),
      ),
    );
  }

  void _onLiveVerseChanged() {
    if (!_narrationRunning) unawaited(_syncKokoroNarration());
  }

  bool _narrationIsCurrent(int session) =>
      mounted &&
      session == _narrationSession &&
      (_macAutoScroll?.isNarrationMode ?? false) &&
      (_macAutoScroll?.isScrolling ?? false);

  void _narrationFailed(String message) {
    NarrationDiagnostics.log('bible narration FAILED: $message');
    if (!mounted) return;
    _macAutoScroll?.stopForManualInteraction();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Speech stopped: $message')));
  }

  Future<void> _syncKokoroNarration() async {
    final controller = _macAutoScroll;
    if (controller == null ||
        !controller.isNarrationMode ||
        !controller.isScrolling) {
      if (_narrationRunning) {
        _narrationRunning = false;
        ++_narrationSession;
        await _kokoroNarrator.stop();
      }
      return;
    }
    if (_narrationRunning) return;
    final location = _liveVisibleLocation.value;
    if (location == null) return;
    _narrationRunning = true;
    _narrationPrimed = false;
    final session = ++_narrationSession;
    try {
      await _pronunciationsReady;
      final sharedRules = await AppSettingsService.instance.loadRawSetting(
        'narration_pronunciations_v1',
      );
      _kokoroNarrator.pronunciationCorrections = decodeNarrationPronunciations(
        sharedRules,
      );
      if (!_narrationIsCurrent(session)) return;
      await _speakNarrationBlock(
        location.blockId,
        session,
        announceChapter: true,
      );
    } catch (error) {
      if (_narrationIsCurrent(session)) _narrationFailed(error.toString());
    }
  }

  String _narrationText(VerseLine line, {required bool announceChapter}) {
    final controller = _macAutoScroll!;
    return [
      if (announceChapter && controller.announceChapter)
        '${_bookNames[line.bookNumber] ?? 'Book ${line.bookNumber}'} ${line.chapter}.',
      if (controller.announceVerseNumbers) 'Verse ${line.verse}.',
      line.text,
    ].join(' ');
  }

  Future<void> _speakNarrationBlock(
    int blockId,
    int session, {
    required bool announceChapter,
  }) async {
    await _viewerData.ensureWindow(blockId);
    if (!_narrationIsCurrent(session)) return;
    final line = _viewerData.getBlock(blockId);
    if (line == null || line.text.trim().isEmpty) {
      _narrationFailed('No verse text is available at this position.');
      return;
    }
    // Deep priming pays off only with the screen on. Resumed from the lock
    // screen, speak the first verse at once and buffer behind it.
    if (NarrationMediaSession.instance.backgrounded.value) {
      _narrationPrimed = true;
    }
    if (Platform.isIOS && !_narrationPrimed) {
      await _kokoroNarrator.prepare(
        blockId: blockId,
        text: _narrationText(line, announceChapter: announceChapter),
        speed: _macAutoScroll!.speechRate,
      );
      if (!_narrationIsCurrent(session)) return;
      await _prefetchBibleVerses(blockId, session);
      if (!_narrationIsCurrent(session)) return;
      _narrationPrimed = true;
    }
    _narrationBlockId = blockId;
    setState(() {
      _selectedBlockId = blockId;
      _bookNumber = line.bookNumber;
      _chapter = line.chapter;
      _verse = line.verse;
    });
    _liveVisibleLocation.updateSelected(
      BibleVisibleLocation(
        blockId: blockId,
        bookNumber: line.bookNumber,
        chapter: line.chapter,
        verse: line.verse,
      ),
    );
    await _kokoroNarrator.speak(
      verseKey: '$session-$blockId',
      blockId: blockId,
      text: _narrationText(line, announceChapter: announceChapter),
      speed: _macAutoScroll!.speechRate,
    );
    if (!_narrationIsCurrent(session)) return;
    unawaited(_prefetchBibleVerses(blockId, session));
  }

  Future<void> _prefetchBibleVerses(int blockId, int session) async {
    try {
      final count = KokoroMacTestNarrator.prefetchAhead();
      for (var offset = 1; offset <= count; offset++) {
        if (!_narrationIsCurrent(session)) return;
        final id = blockId + offset;
        if (id > _viewerData.maxBlockId) return;
        await _viewerData.ensureWindow(id);
        if (!_narrationIsCurrent(session)) return;
        final next = _viewerData.getBlock(id);
        final previous = _viewerData.getBlock(id - 1);
        if (next == null) return;
        await _kokoroNarrator.prepare(
          blockId: id,
          text: _narrationText(
            next,
            announceChapter:
                previous == null ||
                previous.chapter != next.chapter ||
                previous.bookNumber != next.bookNumber,
          ),
          speed: _macAutoScroll!.speechRate,
        );
      }
    } catch (error) {
      debugPrint('Speech prefetch failed: $error');
    }
  }

  void _advanceNarration() {
    final session = _narrationSession;
    final currentId = _narrationBlockId;
    if (!_narrationRunning ||
        !_narrationIsCurrent(session) ||
        currentId == null) {
      return;
    }
    if (currentId >= _viewerData.maxBlockId) {
      _macAutoScroll?.stopForManualInteraction();
      return;
    }
    final current = _viewerData.getBlock(currentId);
    final next = _viewerData.getBlock(currentId + 1);
    unawaited(
      _speakNarrationBlock(
        currentId + 1,
        session,
        announceChapter:
            next == null ||
            next.chapter != current?.chapter ||
            next.bookNumber != current?.bookNumber,
      ).catchError((Object error) {
        if (_narrationIsCurrent(session)) _narrationFailed(error.toString());
      }),
    );
  }

  /// Lock screen next/previous: jumps narration by whole verses.
  Future<void> _skipNarration(int delta) async {
    final current = _narrationBlockId;
    if (!_narrationRunning || current == null) return;
    final target = current + delta;
    if (target < 1 || target > _viewerData.maxBlockId) return;
    _narrationBlockId = target;
    final session = ++_narrationSession;
    await _kokoroNarrator.stop();
    if (!_narrationIsCurrent(session)) return;
    try {
      await _speakNarrationBlock(target, session, announceChapter: true);
    } catch (error) {
      if (_narrationIsCurrent(session)) _narrationFailed(error.toString());
    }
  }

  Future<void> _openPronunciations() async {
    _macAutoScroll?.stopForManualInteraction();
    await _kokoroNarrator.stop();
    await _pronunciationsReady;
    if (!mounted) return;
    _readerShortcutsSuspended = true;
    final original = Map<String, String>.of(
      _kokoroNarrator.pronunciationCorrections,
    );
    var saved = false;
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PronunciationEditor(
        initial: original,
        onPreview: (text, rules) async {
          await _kokoroNarrator.stop();
          _kokoroNarrator.pronunciationCorrections = rules;
          await _kokoroNarrator.speak(
            verseKey: 'preview-${DateTime.now().microsecondsSinceEpoch}',
            preferDictionary: false,
            text: text,
            speed: _macAutoScroll?.speechRate ?? 1,
          );
        },
        onStopPreview: _kokoroNarrator.stop,
        onSave: (rules) async {
          await AppSettingsService.instance.saveRawSetting(
            'narration_pronunciations_v1',
            jsonEncode(rules),
          );
          _kokoroNarrator.pronunciationCorrections = Map.of(rules);
          saved = true;
        },
      ),
    );
    await _kokoroNarrator.stop();
    if (!saved) _kokoroNarrator.pronunciationCorrections = original;
    _readerShortcutsSuspended = false;
    if (mounted) _readerFocusNode.requestFocus();
  }

  Widget _speechControls() => ListenableBuilder(
    listenable: _macAutoScroll!,
    builder: (context, _) {
      final controller = _macAutoScroll!;
      if (!controller.audioEnabled) {
        // The toolbar's autoscroll button prefers tilt settings on any
        // platform with a motion sensor (including iOS), so its long-press
        // never reaches the mac-style audio toggle. This bootstrap button is
        // the only iOS-reachable way to turn narration on, mirroring the
        // equivalent fallback in library_speech_controls.dart.
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.volume_up_outlined),
            label: const Text('Read aloud'),
            onPressed: () {
              controller.updatePreferences(
                MacAutoscrollPreferences(
                  baseSpeed: controller.baseSpeed,
                  lastNonzeroStep: controller.lastNonzeroStep,
                  maximumStep: controller.maximumStep,
                  statusBannerMode: controller.statusBannerMode,
                  audioEnabled: true,
                  announceChapter: controller.announceChapter,
                  announceVerseNumbers: controller.announceVerseNumbers,
                  speechRate: controller.speechRate,
                ),
              );
              controller.setSignedStep(1);
              _readerFocusNode.requestFocus();
            },
          ),
        );
      }
      return SizedBox(
        height: 64,
        child: Row(
          children: [
            TextButton.icon(
              label: const Text('Voice'),
              onPressed: () {
                controller.setSignedStep(controller.isScrolling ? 0 : 1);
                _readerFocusNode.requestFocus();
              },
              icon: Icon(
                controller.isScrolling ? Icons.pause : Icons.play_arrow,
              ),
            ),
            Expanded(
              child: Slider(
                key: const ValueKey('narration-speed'),
                value: controller.speechRate,
                min: 0.75,
                max: 1.5,
                divisions: 15,
                label: '${controller.speechRate.toStringAsFixed(2)}×',
                onChanged: controller.setSpeechRate,
              ),
            ),
            Text('${controller.speechRate.toStringAsFixed(2)}×'),
            TextButton.icon(
              onPressed: _openPronunciations,
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Pronunciations'),
            ),
          ],
        ),
      );
    },
  );

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
        audioEnabled: controller.audioEnabled,
        speechRate: controller.speechRate,
        announceChapter: controller.announceChapter,
        announceVerseNumbers: controller.announceVerseNumbers,
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
    if (_macAutoScroll?.audioEnabled == true) {
      _macAutoScroll!.setSignedStep(_macAutoScroll!.isScrolling ? 0 : 1);
      return;
    }
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
    _macAutoScroll?.stopForManualInteraction();
    await _tiltAutoScroll.stop();
    if (!mounted) return;
    await showReaderTiltSettingsSheet(
      context,
      speechController: _macAutoScroll,
      onPronunciations: _openPronunciations,
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
      // iOS keeps narrating behind a locked screen; stopping here would end it.
      if (!(_narrationMedia?.keepsSpeakingInBackground ?? false)) {
        _stopReaderAutoscroll();
      }
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

/// Flip to true locally to bring back the debug diagnostic panel below for
/// another autoscroll-smoothness measurement pass; keep false otherwise so
/// it doesn't cover the reader and block verse selection during normal use.
const bool _showAutoScrollDiagnosticPanel = false;

/// Debug-only overlay for the Android autoscroll smoothness investigation.
/// Runs a fixed-duration, fixed-speed autoscroll with no sensor input and
/// exports a bounded per-frame CSV via [readerAutoScrollDiagnostics]. Never
/// built outside `kDebugMode`; not reachable from any production entry point.
class _AutoScrollDiagnosticPanel extends StatefulWidget {
  const _AutoScrollDiagnosticPanel({required this.controller});

  final ReaderTiltAutoScrollController controller;

  @override
  State<_AutoScrollDiagnosticPanel> createState() =>
      _AutoScrollDiagnosticPanelState();
}

class _AutoScrollDiagnosticPanelState
    extends State<_AutoScrollDiagnosticPanel> {
  static const _testSpeeds = <double>[10, 20, 40, 80, 160, 320];
  static const _captureDuration = Duration(seconds: 45);
  bool _running = false;
  String? _lastExportName;

  void _onFrameTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final build = timing.buildDuration.inMicroseconds;
      final raster = timing.rasterDuration.inMicroseconds;
      final total = timing.totalSpan.inMicroseconds;
      readerAutoScrollDiagnostics.recordEvent(
        'frame_timing build=${build}us raster=${raster}us total=${total}us',
      );
    }
  }

  Future<void> _runTest(double speed) async {
    debugPrint('AUTOSCROLL_DEBUG_TAP speed=$speed running=$_running');
    if (_running) return;
    setState(() => _running = true);
    readerAutoScrollDiagnostics.start();
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    await widget.controller.debugRunConstantSpeedDiagnostic(speed);
    await Future.delayed(_captureDuration);
    widget.controller.debugStopConstantSpeedDiagnostic();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    final file = await readerAutoScrollDiagnostics.stopAndExport(
      label: 'autoscroll_diag_speed${speed.toStringAsFixed(0)}',
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _lastExportName = file?.path.split('/').last;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: SafeArea(
        bottom: false,
        child: Material(
          color: const Color(0xFFFF00FF),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final speed in _testSpeeds)
                      SizedBox(
                        height: 48,
                        width: 64,
                        child: ElevatedButton(
                          onPressed: _running ? null : () => _runTest(speed),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                          ),
                          child: Text(
                            'D${speed.toStringAsFixed(0)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  _running ? 'capturing…' : (_lastExportName ?? 'idle'),
                  style: const TextStyle(color: Colors.black, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
