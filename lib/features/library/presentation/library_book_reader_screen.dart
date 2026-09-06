// ignore_for_file: unused_element, dead_code

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/bootstrap/library_root_native.dart';
import '../../../core/database/elibrary_read_resolver.dart';
import '../../../core/database/user_database.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../core/theme/app_settings_service.dart';
import '../../../core/theme/theme_preferences.dart';
import '../data/elibrary_markup_repository.dart';
import '../data/library_citation_display_helper.dart';
import '../data/library_reader_opening.dart';
import '../data/library_reader_state_writer.dart';
import '../data/library_search_navigation_target.dart';
import '../data/library_section_heuristics.dart';
import '../../reader/data/commentary_research_library_service.dart';
import '../../reader/presentation/highlight_render.dart';
import '../../reader/presentation/tag_quick_apply_helper.dart';
import '../../reader/presentation/tag_screen_launcher.dart';
import '../../reader/presentation/tag_dialog_styles.dart';
import '../../reader/presentation/reader_search_mode_picker.dart';
import '../../reader/presentation/viewer_search_dialog.dart';
import '../../reader/presentation/viewer_passage_models.dart';
import '../../reader/presentation/viewer_range_selection.dart';
import '../../search/search_highlight_helper.dart';
import '../data/library_catalog_service.dart';
import 'elibrary_highlight_color_picker.dart';
import 'epub_text_flow.dart';
import 'library_continuous_section_window.dart';
import 'library_font_scale.dart';
import 'library_navigation_tree.dart';
import 'library_live_section_controller.dart';
import 'reader_tilt_autoscroll_controller.dart';
import 'reader_tilt_autoscroll_controls.dart';
import 'reader_tilt_motion_source.dart';
import 'reader_tilt_preferences.dart';
import 'mac_reader_autoscroll_controller.dart';
import 'mac_reader_autoscroll_controls.dart';
import 'canonical_library_reader.dart';
import '../../reader/presentation/text_range_geometry.dart';
import '../../utilities/data/pioneer_captured_html_import_folder_service.dart';
import '../../utilities/data/pioneer_book_package_import_service.dart';
import '../../utilities/data/pioneer_text_import_service.dart';
import '../../utilities/presentation/elibrary_setup_screen.dart';

part 'epub_inline_span_builder.dart';
part 'epub_body_block_parser.dart';
part 'library_contents_popup.dart';
part 'library_reader_bottom_bar.dart';
part 'library_book_reader_range_selection.dart';
part 'library_book_reader_selection_menu.dart';
part 'library_book_reader_screen_helpers.dart';

const bool _enableTextRangeGeometry = false;
const bool elibraryAutomaticTiltChapterTransitionsEnabled = false;

@visibleForTesting
bool libraryReaderUsesSteadyAutoscroll(TargetPlatform platform) =>
    platform != TargetPlatform.iOS && platform != TargetPlatform.android;

@visibleForTesting
bool libraryReaderSteadyAutoscrollEnabled({
  required LibraryCatalogItem item,
  required bool hasReadableSections,
}) => hasReadableSections && !item.isPdf;

enum _ReaderBookMenuAction {
  openELibrarySetup,
  removeCurrentBook,
  repairCurrentImportedBook,
}

class LibraryBookReaderScreen extends StatefulWidget {
  const LibraryBookReaderScreen({
    super.key,
    required this.item,
    this.initialHref,
    this.initialAnchorId,
    this.initialSpineIndex,
    this.initialParagraphIndex,
    this.searchTarget,
    this.searchQuery,
    this.highlightTerms = const [],
    this.searchSession,
    this.onReturnToBible,
    this.themeMode,
    this.onThemeChanged,
    this.enableCanonicalReader = true,
  });

  final LibraryCatalogItem item;
  final String? initialHref;
  final String? initialAnchorId;
  final int? initialSpineIndex;
  final int? initialParagraphIndex;
  final LibrarySearchNavigationTarget? searchTarget;
  final String? searchQuery;
  final List<String> highlightTerms;
  final LibraryCatalogSearchSession? searchSession;
  final VoidCallback? onReturnToBible;
  final AppThemeMode? themeMode;
  final ValueChanged<AppThemeMode>? onThemeChanged;
  final bool enableCanonicalReader;

  @override
  State<LibraryBookReaderScreen> createState() =>
      _LibraryBookReaderScreenState();
}

class _LibraryBookReaderScreenState extends State<LibraryBookReaderScreen>
    with WidgetsBindingObserver {
  final _service = CommentaryResearchLibraryService.instance;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  ScrollPosition? _bodyScrollPosition;
  final CallbackReaderAutoScrollTarget _tiltScrollTarget =
      CallbackReaderAutoScrollTarget();
  late final ReaderTiltAutoScrollController _tiltAutoScroll;
  late final MacReaderAutoScrollController _steadyAutoScroll;
  final FocusNode _readerFocusNode = FocusNode(
    debugLabel: 'library-reader-keyboard-focus',
  );
  bool _readerShortcutsSuspended = false;
  int _lastMacAutoscrollStatusRevision = 0;
  final ReaderTiltPreferencesStore _tiltPreferencesStore =
      const ReaderTiltPreferencesStore();
  final Map<String, GlobalKey> _bodyBlockKeys = <String, GlobalKey>{};
  final Map<String, GlobalKey> _bodyTextKeys = <String, GlobalKey>{};
  final TextRangeGeometryRegistry _geometryRegistry =
      TextRangeGeometryRegistry();
  String? _lastSearchTerm;
  LibraryRangeSelection _rangeSelection = const LibraryRangeSelection();
  bool _librarySelectionActionsOpen = false;
  bool _loading = true;
  bool _nightMode = false;
  bool _showRefCodes = false;
  bool _refCodesLoaded = false;
  double _fontScale = 1.3;
  double _zoomScale = 1.0;
  final int _geometryTick = 0;
  String? _error;
  List<LibraryBookSection> _sections = const [];
  List<LibraryCatalogNavigationItem> _navigationItems = const [];
  int _selectedIndex = 0;
  List<int> _readableSectionIndices = const <int>[];
  LibraryContinuousSectionWindow? _sectionWindow;
  final LibrarySectionVisibilityHysteresis _sectionVisibilityHysteresis =
      LibrarySectionVisibilityHysteresis();
  int? _stableLiveSectionIndex;
  final Map<int, GlobalKey> _sectionUnitKeys = <int, GlobalKey>{};
  final GlobalKey _continuousScrollViewKey = GlobalKey(
    debugLabel: 'elibrary-continuous-scroll-view',
  );
  bool _windowUpdateScheduled = false;
  int _selectedNavigationIndex = 0;
  int _chapterGeneration = 0;
  int _liveSectionGeneration = 0;
  final LibraryLiveSectionController _liveSection =
      LibraryLiveSectionController();
  int? _selectedHeadingTargetIndex;
  String? _pendingBodyScrollTargetKey;
  bool _searchTargetPositioned = false;
  bool _ignoreSavedInitialLocation = false;
  Map<String, String> _refCodeByLocation = <String, String>{};
  Map<String, Map<int, String>> _paragraphReferenceCodesBySection =
      <String, Map<int, String>>{};
  Map<String, List<ElibraryMarkupRecord>> _elibraryMarkupsByHref =
      <String, List<ElibraryMarkupRecord>>{};

  String get _geometryScopeId {
    final section = _sections.isEmpty
        ? null
        : _sections[_selectedIndex.clamp(0, _sections.length - 1)];
    return 'elibrary:${widget.item.id}:${section?.entryName ?? '(none)'}';
  }

  @override
  void initState() {
    super.initState();
    final searchTarget = widget.searchTarget;
    if (searchTarget != null) {
      debugPrint('search_target_received ${searchTarget.diagnosticSummary}');
    }
    WidgetsBinding.instance.addObserver(this);
    _tiltAutoScroll = ReaderTiltAutoScrollController(
      motionSource: PlatformReaderTiltMotionSource(),
      scrollTarget: _tiltScrollTarget,
      // Vertical movement uses the same continuous document as manual scroll.
      // No horizontal callback is registered, preserving the rocking fail-safe.
    );
    _steadyAutoScroll = MacReaderAutoScrollController(
      scrollTarget: _tiltScrollTarget,
    )..addListener(_onMacAutoscrollChanged);
    _tiltScrollTarget.attach(_scrollContinuousDocument);
    _loadTiltPreferences();
    _loadSteadyAutoscrollPreferences();
    _nightMode = widget.themeMode == AppThemeMode.night;
    final initialSearchTerm = widget.searchQuery?.trim() ?? '';
    _lastSearchTerm = initialSearchTerm.isNotEmpty ? initialSearchTerm : null;
    _itemPositionsListener.itemPositions.addListener(_onBodyScroll);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tiltAutoScroll.dispose();
    _steadyAutoScroll
      ..removeListener(_onMacAutoscrollChanged)
      ..dispose();
    _readerFocusNode.dispose();
    _tiltScrollTarget.detach();
    _geometryDebounce?.cancel();
    _itemPositionsListener.itemPositions.removeListener(_onBodyScroll);
    _liveSection.dispose();
    super.dispose();
  }

  Timer? _geometryDebounce;

  void _onBodyScroll() {
    if (_windowUpdateScheduled || _bodyScrollPosition == null) return;
    _windowUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _windowUpdateScheduled = false;
      if (!mounted || _bodyScrollPosition == null) return;
      _updateContinuousWindowFromVisibility();
    });
  }

  /// The section's current on-screen distance from the viewport's top edge,
  /// or null if either isn't laid out yet. Zero means its leading edge is
  /// exactly at the top of the viewport.
  double? _sectionViewportOffset(int index) {
    final viewportBox =
        _continuousScrollViewKey.currentContext?.findRenderObject()
            as RenderBox?;
    final sectionBox =
        _sectionUnitKeys[index]?.currentContext?.findRenderObject()
            as RenderBox?;
    if (viewportBox == null ||
        sectionBox == null ||
        !viewportBox.attached ||
        !sectionBox.attached) {
      return null;
    }
    return sectionBox.localToGlobal(Offset.zero).dy -
        viewportBox.localToGlobal(Offset.zero).dy;
  }

  double? _sectionDocumentTop(int index) {
    final position = _bodyScrollPosition;
    if (position == null) return null;
    final onScreenOffset = _sectionViewportOffset(index);
    if (onScreenOffset == null) return null;
    return position.pixels + onScreenOffset;
  }

  bool _scrollContinuousDocument(double delta) {
    final position = _bodyScrollPosition;
    if (position == null || delta == 0) return false;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() <= 0.01) {
      return false;
    }
    // Use jumpTo for sub-pixel movements to avoid animation overhead,
    // but ensure we're moving the position directly without easing.
    // This preserves frame-by-frame control from the autoscroll controller.
    position.jumpTo(target);
    return true;
  }

  Future<void> _loadTiltPreferences() async {
    var preferences = await _tiltPreferencesStore.load();
    if (!preferences.horizontalChapterTiltAvailabilityMigrated) {
      preferences = preferences.copyWith(
        horizontalChapterTiltEnabled: true,
        horizontalChapterTiltAvailabilityMigrated: true,
      );
      await _tiltPreferencesStore.save(preferences);
    }
    if (mounted) {
      _tiltAutoScroll.updatePreferences(preferences, showBanner: false);
    }
  }

  Future<void> _loadSteadyAutoscrollPreferences() async {
    final preferences = await AppSettingsService.instance
        .loadMacAutoscrollPreferences();
    if (mounted) _steadyAutoScroll.updatePreferences(preferences);
  }

  Future<void> _openSteadyAutoscrollSettings() async {
    final initial = MacAutoscrollPreferences(
      baseSpeed: _steadyAutoScroll.baseSpeed,
      lastNonzeroStep: _steadyAutoScroll.lastNonzeroStep,
      maximumStep: _steadyAutoScroll.maximumStep,
      statusBannerMode: _steadyAutoScroll.statusBannerMode,
    );
    _readerShortcutsSuspended = true;
    final preferences = await (defaultTargetPlatform == TargetPlatform.macOS
        ? showMacAutoscrollSettingsDialog(context: context, initial: initial)
        : showReaderAutoscrollSettingsDialog(
            context: context,
            initial: initial,
          ));
    if (!mounted) return;
    _readerShortcutsSuspended = false;
    if (preferences != null) {
      _steadyAutoScroll.updatePreferences(preferences);
      await AppSettingsService.instance.saveMacAutoscrollPreferences(
        preferences,
      );
    }
    _readerFocusNode.requestFocus();
  }

  void _onMacAutoscrollChanged() {
    if (!mounted) return;
    final controller = _steadyAutoScroll;
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

  void _toggleSteadyAutoscroll() {
    if (!_steadyAutoScroll.isActive) _tiltAutoScroll.stop(notify: false);
    _steadyAutoScroll.toggle();
    _readerFocusNode.requestFocus();
  }

  void _toggleTiltAutoscroll() {
    if (_tiltAutoScroll.isActive) {
      _tiltAutoScroll.stop();
    } else {
      _steadyAutoScroll.stopWithoutNotification();
      _tiltAutoScroll.activate();
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
      includeChapterTilt: true,
      onChanged: _saveTiltPreferences,
      onRecalibrate: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tiltAutoScroll.activate();
        });
      },
    );
  }

  bool _sectionIsReadableForAutomaticContinuation(int index) {
    if (index < 0 || index >= _sections.length) return false;
    final section = _sections[index];
    if (section.blocks.isNotEmpty ||
        section.paragraphs.any((paragraph) => paragraph.trim().isNotEmpty)) {
      return true;
    }

    final navigationIndex = _navigationIndexForSectionIndex(index);
    if (navigationIndex == null || _navigationItems.isEmpty) return false;
    final orderedNavigation = _orderedNavigationItems;
    if (navigationIndex < 0 || navigationIndex >= orderedNavigation.length) {
      return false;
    }
    final tree = buildLibraryNavigationTree(
      _navigationItems,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    return libraryReaderFirstReadableDescendant(
          navItem: orderedNavigation[navigationIndex],
          tree: tree,
          sections: _sections,
        ) !=
        null;
  }

  bool _handleReaderScrollNotification(ScrollNotification notification) {
    final isManualStart =
        notification is ScrollStartNotification &&
        notification.dragDetails != null;
    final isManualUpdate =
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    if (isManualStart || isManualUpdate) {
      _tiltAutoScroll.stopForManualInteraction();
      _steadyAutoScroll.stopForManualInteraction();
      _readerFocusNode.requestFocus();
    }
    return false;
  }

  bool _handleReaderScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    _bodyScrollPosition = Scrollable.maybeOf(notification.context)?.position;
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _tiltAutoScroll.stop();
      _steadyAutoScroll.stopWithoutNotification();
    }
  }

  @override
  void deactivate() {
    _tiltAutoScroll.stop(notify: false);
    _steadyAutoScroll.stopWithoutNotification();
    super.deactivate();
  }

  Future<void> _load() async {
    final savedFontScale = await AppSettingsService.instance
        .loadViewerFontScale();
    final savedZoomScale = await AppSettingsService.instance
        .loadElibraryZoomScale();
    final savedShowRefCodes = await LocalSettingsStore.instance
        .loadLibraryReaderShowRefCodes();
    final selection = await LibraryRootService.instance.loadSelection();
    final rootPath =
        (await LibraryRootService.instance.accessibleLibraryRootPath())
            ?.trim() ??
        (selection.exists ? selection.path?.trim() ?? '' : '');

    if (rootPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = 'Reconnect the Library Root to open this book.';
        _loading = false;
      });
      return;
    }

    final existingFile = await LibraryRootService.instance
        .resolveExistingAssetFile(
          rootPath: rootPath,
          relativePath: widget.item.relativePath,
        );
    final filePath =
        existingFile?.path ?? p.join(rootPath, widget.item.relativePath);
    try {
      final loadedSections = widget.item.isPdf
          ? const <LibraryBookSection>[]
          : await _service.loadBookSections(
              filePath: filePath,
              libraryItemId: widget.item.id,
              includeFrontMatter: true,
            );
      final navigationItems = widget.item.isPdf
          ? const <LibraryCatalogNavigationItem>[]
          : await LibraryCatalogService.instance.loadNavigationItems(
              widget.item.id,
            );
      final sections = widget.item.isPdf
          ? loadedSections
          : libraryReaderSectionsWithHeadingOnlyNavigation(
              sections: loadedSections,
              navigationItems: navigationItems,
            );
      final devotionalMode =
          widget.item.isDevotional || isDevotionalNavigation(navigationItems);
      if (widget.searchTarget == null && !widget.item.isPdf) {
        debugPrint(
          'default_open_resolution_started workId=${widget.item.id} '
          'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id}',
        );
      }
      final navigationTree = widget.item.isPdf
          ? const LibraryNavigationTreeResult(
              items: <LibraryCatalogNavigationItem>[],
              childrenByParent: <String?, List<LibraryCatalogNavigationItem>>{},
            )
          : buildLibraryNavigationTree(
              navigationItems,
              devotionalMode: devotionalMode,
              periodicalMode: widget.item.isPeriodical,
            );
      final initialIndex = widget.item.isPdf
          ? 0
          : libraryReaderInitialSectionIndex(
              item: widget.item,
              sections: sections,
              navigationItems: navigationItems,
              devotionalMode: devotionalMode,
              initialHref: widget.searchTarget?.href ?? widget.initialHref,
              initialSpineIndex:
                  widget.searchTarget?.spineIndex ?? widget.initialSpineIndex,
            );
      final ignoreSavedInitialLocation =
          !widget.item.isPdf &&
          libraryReaderSavedLocationTargetsFrontMatter(
            item: widget.item,
            sections: sections,
            navigationItems: navigationItems,
          );
      var initialNavigationIndex = widget.item.isPdf
          ? 0
          : _navigationIndexForSectionIndex(initialIndex) ?? 0;
      final chapterInitialNavigationIndex = widget.item.isPdf
          ? null
          : libraryReaderInitialNavigationIndex(
              item: widget.item,
              sections: sections,
              navigationItems: navigationItems,
              initialSectionIndex: initialIndex,
              hasExplicitInitialLocation:
                  widget.searchTarget != null ||
                  (widget.initialHref?.trim().isNotEmpty ?? false) ||
                  (widget.initialAnchorId?.trim().isNotEmpty ?? false) ||
                  widget.initialSpineIndex != null ||
                  widget.initialParagraphIndex != null,
            );
      if (chapterInitialNavigationIndex != null) {
        initialNavigationIndex = chapterInitialNavigationIndex;
      }
      var resolvedInitialIndex = initialIndex;
      if (navigationItems.isNotEmpty) {
        final selectedNavItem =
            navigationItems[initialNavigationIndex.clamp(
              0,
              navigationItems.length - 1,
            )];
        final normalizedNavItem = libraryReaderVisibleContentsNavigationItem(
          navItem: selectedNavItem,
          tree: navigationTree,
          sections: sections,
        );
        if (normalizedNavItem != null &&
            normalizedNavItem.id != selectedNavItem.id) {
          final normalizedNavIndex = navigationItems.indexWhere(
            (nav) => nav.id == normalizedNavItem.id,
          );
          final normalizedSectionIndex =
              _sectionIndexForNavigationItemInSections(
                sections,
                normalizedNavItem,
              ) ??
              resolvedInitialIndex;
          if (normalizedNavIndex >= 0) {
            initialNavigationIndex = normalizedNavIndex;
            resolvedInitialIndex = normalizedSectionIndex;
          }
        }
      }
      if (widget.searchTarget == null &&
          !widget.item.isPdf &&
          sections.isNotEmpty) {
        final selected = sections[resolvedInitialIndex];
        final savedLocationRequested =
            widget.item.lastOpened != null &&
            ((widget.item.epubHref ?? '').trim().isNotEmpty ||
                widget.item.spineIndex != null);
        final savedHref = (widget.item.epubHref ?? '').trim();
        final savedLocationUsed =
            savedLocationRequested &&
            ((savedHref.isNotEmpty &&
                    _hrefMatchesSection(selected.entryName, savedHref)) ||
                (widget.item.spineIndex != null &&
                    selected.spineIndex == widget.item.spineIndex));
        if (savedLocationUsed) {
          debugPrint(
            'default_open_saved_position_used workId=${widget.item.id} '
            'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id} '
            'selectedSectionId=${selected.entryName} '
            'selectedSectionTitle=${selected.title} '
            'reason=valid_saved_position',
          );
        } else {
          if (savedLocationRequested) {
            debugPrint(
              'default_open_saved_position_repaired workId=${widget.item.id} '
              'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id} '
              'selectedSectionId=${selected.entryName} '
              'selectedSectionTitle=${selected.title} '
              'reason=saved_section_missing_or_unreadable',
            );
          }
          final skipped = sections
              .take(resolvedInitialIndex)
              .where(
                (section) =>
                    libraryIsFrontMatterOpeningLabel(section.title) ||
                    libraryIsFrontMatterOpeningLabel(section.entryName),
              )
              .map((section) => '${section.entryName}:${section.title}')
              .join('|');
          if (skipped.isNotEmpty) {
            debugPrint(
              'default_open_front_matter_skipped workId=${widget.item.id} '
              'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id} '
              'selectedSectionId=${selected.entryName} '
              'selectedSectionTitle=${selected.title} '
              'skippedSectionIds=$skipped '
              'reason=first_substantive_section',
            );
          }
          debugPrint(
            resolvedInitialIndex == 0
                ? 'default_open_fallback_used workId=${widget.item.id} '
                      'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id} '
                      'selectedSectionId=${selected.entryName} '
                      'selectedSectionTitle=${selected.title} '
                      'reason=no_later_substantive_section'
                : 'default_open_substantive_section_selected '
                      'workId=${widget.item.id} '
                      'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id} '
                      'selectedSectionId=${selected.entryName} '
                      'selectedSectionTitle=${selected.title} '
                      'reason=first_substantive_section',
          );
        }
      }
      // Periodicals generate ref codes inline (libraryReaderPeriodicalRefCode)
      // and books load codes in the background after first paint; skipping
      // the DB scan here avoids ~1,900 serial async queries on RH open.
      final paragraphReferenceCodeLoadResult =
          const _ParagraphReferenceCodeLoadResult(
            bySection: <String, Map<int, String>>{},
            byLocation: <String, String>{},
          );
      final elibraryMarkupsByHref = await _loadElibraryMarkups(widget.item.id);
      if (!mounted) return;
      setState(() {
        _fontScale = savedFontScale;
        _zoomScale = savedZoomScale;
        _sections = sections;
        _navigationItems = navigationItems;
        _selectedIndex = resolvedInitialIndex;
        _selectedNavigationIndex = initialNavigationIndex;
        _ignoreSavedInitialLocation = ignoreSavedInitialLocation;
        _showRefCodes = savedShowRefCodes;
        // Codes are loaded lazily; the maps above are still empty here.
        _refCodesLoaded = false;
        _refCodeByLocation = paragraphReferenceCodeLoadResult.byLocation;
        _paragraphReferenceCodesBySection =
            paragraphReferenceCodeLoadResult.bySection;
        _elibraryMarkupsByHref = elibraryMarkupsByHref;
        _loading = false;
      });
      if (widget.searchTarget != null && sections.isNotEmpty) {
        debugPrint(
          'search_target_section_loaded '
          '${widget.searchTarget!.diagnosticSummary} '
          'resolvedSection=${sections[resolvedInitialIndex].entryName}',
        );
      }
      _initializeContinuousWindow();
      _publishLiveSectionLocation(_chapterGeneration);
      final targetKey = _initialScrollTargetKey();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToTarget(targetKey);
      });
      if (widget.searchTarget != null && targetKey != null) {
        // The continuous section list can publish its first visible item
        // immediately after the first frame. Re-assert the explicit search
        // target once after that bounded initialization settles.
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          _scrollToTarget(targetKey, attempt: 4);
        });
      }
      unawaited(
        LibraryReaderStateWriter.instance.stampLastOpened(widget.item.id),
      );
      if (savedShowRefCodes) {
        unawaited(_ensureParagraphReferenceCodesLoaded());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not open this book: $error';
        _loading = false;
      });
    }
  }

  Future<void> _openSearch() async {
    final selection = await showViewerSearchDialog(
      context,
      fontScale: _fontScale,
      lastSearchTerm: _lastSearchTerm,
      initialMode: ReaderSearchMode.elibrary,
      onReturnToBible: widget.onReturnToBible,
    );
    if (!mounted || selection == null) return;
    final selectedSearchTerm = selection.lastSearchTerm.trim();
    if (selectedSearchTerm.isNotEmpty) {
      _lastSearchTerm = selectedSearchTerm;
    }
  }

  bool get _hasSearchSession {
    final session = widget.searchSession;
    return session != null && session.results.isNotEmpty;
  }

  Future<void> _navigateSearchHit(int delta) async {
    final session = widget.searchSession;
    if (session == null || session.results.isEmpty) return;
    final nextIndex = session.currentIndex + delta;
    if (nextIndex < 0 || nextIndex >= session.results.length) return;
    final nextSession = session.copyWithIndex(nextIndex);
    final nextResult = nextSession.currentResult;
    await _saveCurrentLocation();
    await AppSettingsService.instance.saveLastElibrarySearchSessionJson(
      LibraryCatalogSearchSessionSnapshot.fromSession(
        nextSession,
      ).toJsonString(),
    );
    await AppSettingsService.instance.saveLastElibrarySearch(nextSession.query);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LibraryBookReaderScreen(
          item: nextResult.item,
          searchTarget: nextResult.targetForQuery(nextSession.query),
          searchQuery: nextSession.query,
          highlightTerms: extractLibrarySearchHighlightTerms(nextSession.query),
          searchSession: nextSession,
          onReturnToBible: widget.onReturnToBible,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    );
  }

  void _beginLibraryRangeSelection(int blockIndex, int tokenIndex) {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.beginAt(blockIndex, tokenIndex);
    });
  }

  void _completeLibraryRangeSelection(int blockIndex, int tokenIndex) {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.completeAt(blockIndex, tokenIndex);
    });
  }

  void _clearLibraryRangeSelection() {
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.clear();
    });
  }

  void _handleLibraryWordLongPress({
    required int blockIndex,
    required int tokenIndex,
  }) {
    if (_rangeSelection.isPendingRange) {
      _completeLibraryRangeSelection(blockIndex, tokenIndex);
      return;
    }
    _beginLibraryRangeSelection(blockIndex, tokenIndex);
  }

  void _handleLibraryWordLongPressMove({
    required int blockIndex,
    required int tokenIndex,
  }) {
    if (!_rangeSelection.hasSelection) {
      _beginLibraryRangeSelection(blockIndex, tokenIndex);
      return;
    }
    if (!mounted) return;
    setState(() {
      _rangeSelection = _rangeSelection.completeAt(blockIndex, tokenIndex);
    });
  }

  String? _referenceCodeForSectionBlock({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required LibraryBookBlock block,
    required int blockIndex,
    required int paragraphIndex,
    required int devotionalFallbackParagraphCount,
    required Map<int, String> sectionReferenceCodes,
  }) {
    if (block.kind != 'paragraph') return null;
    final sectionTitle = libraryReaderDisplaySectionTitle(section?.title ?? '');
    if (item.isDevotional) {
      return libraryReaderDevotionalFallbackRefCodeForBlock(
        item: item,
        sectionTitle: sectionTitle,
        block: block,
        fallbackParagraphCount: devotionalFallbackParagraphCount,
      );
    }
    if (item.isPeriodical) {
      return libraryReaderPeriodicalRefCode(
        item: item,
        sectionTitle: sectionTitle,
        paragraphIndex: paragraphIndex,
      );
    }

    return _refCodeByLocation[_refCodeLocationKey(
          libraryItemId: item.id,
          href: section?.entryName ?? '',
          paragraphIndex: paragraphIndex,
        )] ??
        sectionReferenceCodes[paragraphIndex];
  }

  String _buildLibrarySelectionReferenceLabel({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    return _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    ).compactRef;
  }

  ({String refStart, String refEnd, String compactRef})
  _buildLibrarySelectionReferenceEndpoints({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    final low = _rangeSelection.lowerAnchor;
    final high = _rangeSelection.upperAnchor;
    if (low == null || high == null) {
      final fallback = _buildEpubSelectionFallbackReference(
        item: item,
        section: section,
      );
      return (refStart: fallback, refEnd: fallback, compactRef: fallback);
    }

    final sectionReferenceCodes = section == null
        ? const <int, String>{}
        : item.isDevotional
        ? const <int, String>{}
        : _paragraphReferenceCodesBySection[_sectionKey(section.entryName)] ??
              const <int, String>{};

    final refs = <String>[];
    var paragraphIndex = 0;
    var devotionalFallbackParagraphCount = 0;
    for (var index = 0; index < sectionBlocks.length; index++) {
      final block = sectionBlocks[index];
      final isParagraph = block.kind == 'paragraph';
      if (isParagraph) {
        paragraphIndex += 1;
      }

      final referenceCode = _referenceCodeForSectionBlock(
        item: item,
        section: section,
        block: block,
        blockIndex: index,
        paragraphIndex: paragraphIndex,
        devotionalFallbackParagraphCount: devotionalFallbackParagraphCount,
        sectionReferenceCodes: sectionReferenceCodes,
      );
      if (item.isDevotional && referenceCode != null) {
        devotionalFallbackParagraphCount += 1;
      }

      if (index < low.blockIndex || index > high.blockIndex) continue;
      if (referenceCode == null) continue;
      final ref = cleanDisplayRefCode(referenceCode);
      if (ref != null && ref.trim().isNotEmpty) {
        refs.add(ref);
      }
    }

    if (refs.isEmpty) {
      final fallback = _buildEpubSelectionFallbackReference(
        item: item,
        section: section,
      );
      return (refStart: fallback, refEnd: fallback, compactRef: fallback);
    }
    final refStart = refs.first;
    final refEnd = refs.last;
    final compactRef = refs.length == 1
        ? refStart
        : libraryCompactReferenceRangeLabel(refStart, refEnd);
    return (refStart: refStart, refEnd: refEnd, compactRef: compactRef);
  }

  String _buildEpubSelectionFallbackReference({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
  }) {
    final title = item.displayTitle.trim();
    final sectionTitle = libraryReaderDisplaySectionTitle(section?.title ?? '');

    if (title.isNotEmpty && sectionTitle.isNotEmpty) {
      return '$title, $sectionTitle';
    }
    if (title.isNotEmpty) {
      return title;
    }
    if (sectionTitle.isNotEmpty) {
      return sectionTitle;
    }
    return 'eLibrary';
  }

  Future<void> _showLibrarySelectionActionsMenu({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    if (_librarySelectionActionsOpen) return;
    final selectedText = buildLibrarySelectionText(
      blocks: sectionBlocks,
      selection: _rangeSelection,
    );
    if (selectedText.trim().isEmpty) return;
    await _tiltAutoScroll.stop();
    if (!mounted) return;

    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    _librarySelectionActionsOpen = true;
    final action = await showLibrarySelectionRangeActionsSheet(
      context,
      payload: LibrarySelectionRangeActionsPayload(
        referenceLabel: referenceLabel,
        previewText: selectedText,
        enableClearMarkup: _hasElibraryMarkupOverlapForSelection(
          section: section,
          sectionBlocks: sectionBlocks,
        ),
      ),
      fontScale: _fontScale,
    );
    _librarySelectionActionsOpen = false;
    if (!mounted || action == null) return;

    switch (action) {
      case LibrarySelectionRangeAction.copyNoCitation:
        await _copyLibrarySelectionToClipboard(selectedText);
        return;
      case LibrarySelectionRangeAction.copyWithCitation:
        await _copyLibrarySelectionWithReferenceToClipboard(
          selectedText: selectedText,
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.copyWithMarkup:
        await _copyLibrarySelectionWithMarkupToClipboard(selectedText);
        return;
      case LibrarySelectionRangeAction.copyWithMarkupAndCitation:
        await _copyLibrarySelectionWithMarkupAndReferenceToClipboard(
          selectedText: selectedText,
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.highlight:
        final chosenColor = await showElibraryHighlightColorPicker(context);
        if (!mounted || chosenColor == null) return;
        await AppSettingsService.instance.saveDefaultElibraryHighlightColorHex(
          chosenColor,
        );
        await _saveElibraryHighlightForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
          referenceLabel: referenceLabel,
          selectedText: selectedText,
          colorHex: chosenColor,
        );
        return;
      case LibrarySelectionRangeAction.addHashTag:
        await _addElibraryHashTagForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
          selectedText: selectedText,
        );
        return;
      case LibrarySelectionRangeAction.clearMarkup:
        await _clearElibraryMarkupForSelection(
          item: item,
          section: section,
          sectionBlocks: sectionBlocks,
        );
        return;
      case LibrarySelectionRangeAction.resetRange:
        _clearLibraryRangeSelection();
        return;
    }
  }

  Future<void> _copyLibrarySelectionToClipboard(String selectedText) async {
    await _copyLibrarySelectionPayloadToClipboard(selectedText: selectedText);
  }

  Future<void> _copyLibrarySelectionWithReferenceToClipboard({
    required String selectedText,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    await _copyLibrarySelectionPayloadToClipboard(
      selectedText: selectedText,
      referenceLabel: referenceLabel,
    );
  }

  Future<void> _copyLibrarySelectionWithMarkupToClipboard(
    String selectedText,
  ) async {
    // Rich clipboard export is not available yet, so markup copies intentionally
    // fall back to plain text until a safe rich path exists.
    await _copyLibrarySelectionPayloadToClipboard(selectedText: selectedText);
  }

  Future<void> _copyLibrarySelectionWithMarkupAndReferenceToClipboard({
    required String selectedText,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    final referenceLabel = _buildLibrarySelectionReferenceLabel(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    // Rich clipboard export is not available yet, so markup copies intentionally
    // fall back to plain text until a safe rich path exists.
    await _copyLibrarySelectionPayloadToClipboard(
      selectedText: selectedText,
      referenceLabel: referenceLabel,
    );
  }

  Future<void> _copyLibrarySelectionPayloadToClipboard({
    required String selectedText,
    String? referenceLabel,
  }) async {
    final trimmedText = selectedText.trimRight();
    final payload = referenceLabel == null
        ? trimmedText
        : trimmedText.isEmpty
        ? referenceLabel
        : '$trimmedText\n— $referenceLabel';
    if (payload.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: payload));
  }

  Future<Map<String, List<ElibraryMarkupRecord>>> _loadElibraryMarkups(
    String libraryItemId,
  ) async {
    try {
      return await ElibraryMarkupRepository().loadMarkupsBySectionForItem(
        libraryItemId,
      );
    } catch (error) {
      debugPrint('[LibraryBookReader] Failed to load eLibrary markups: $error');
      return const <String, List<ElibraryMarkupRecord>>{};
    }
  }

  ({
    int startBlockIndex,
    int startCharOffset,
    int endBlockIndex,
    int endCharOffset,
  })?
  _librarySelectionCharRange({required List<LibraryBookBlock> sectionBlocks}) {
    final low = _rangeSelection.lowerAnchor;
    final high = _rangeSelection.upperAnchor;
    if (low == null || high == null) return null;
    if (low.blockIndex < 0 ||
        high.blockIndex < low.blockIndex ||
        high.blockIndex >= sectionBlocks.length) {
      return null;
    }

    final startBlock = sectionBlocks[low.blockIndex];
    final endBlock = sectionBlocks[high.blockIndex];
    final startSpan = _libraryTokenSpanForIndex(
      startBlock.text,
      low.tokenIndex,
    );
    final endSpan = _libraryTokenSpanForIndex(endBlock.text, high.tokenIndex);
    if (startSpan == null || endSpan == null) return null;

    return (
      startBlockIndex: low.blockIndex,
      startCharOffset: startSpan.startOffset,
      endBlockIndex: high.blockIndex,
      endCharOffset: endSpan.endOffset,
    );
  }

  int? _libraryParagraphIndexForBlockIndex(
    List<LibraryBookBlock> sectionBlocks,
    int blockIndex,
  ) {
    if (blockIndex < 0 || blockIndex >= sectionBlocks.length) return null;
    var paragraphIndex = 0;
    for (var index = 0; index <= blockIndex; index++) {
      if (sectionBlocks[index].kind == 'paragraph') {
        paragraphIndex += 1;
      }
    }
    return paragraphIndex > 0 ? paragraphIndex : null;
  }

  bool _elibraryMarkupOverlapsSelection(
    ElibraryMarkupRecord record, {
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
  }) {
    if (record.deletedAt != null || !record.isHighlight) return false;
    if (record.endBlockIndex < startBlockIndex) return false;
    if (record.endBlockIndex == startBlockIndex &&
        record.endCharOffset <= startCharOffset) {
      return false;
    }
    if (record.startBlockIndex > endBlockIndex) return false;
    if (record.startBlockIndex == endBlockIndex &&
        record.startCharOffset >= endCharOffset) {
      return false;
    }
    return true;
  }

  bool _hasElibraryMarkupOverlapForSelection({
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) {
    if (section == null) return false;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return false;
    final highlights =
        _elibraryMarkupsByHref[section.entryName] ??
        const <ElibraryMarkupRecord>[];
    for (final record in highlights) {
      if (_elibraryMarkupOverlapsSelection(
        record,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
      )) {
        return true;
      }
    }
    return false;
  }

  Future<void> _saveElibraryHighlightForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String referenceLabel,
    required String selectedText,
    required String colorHex,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final endpoints = _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );

    try {
      final saved = await ElibraryMarkupRepository().saveHighlight(
        libraryItemId: item.id,
        epubHref: section.entryName,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        startTokenIndex: _rangeSelection.lowerAnchor?.tokenIndex,
        endTokenIndex: _rangeSelection.upperAnchor?.tokenIndex,
        refStart: endpoints.refStart,
        refEnd: endpoints.refEnd,
        compactRef: referenceLabel,
        selectedTextSnapshot: selectedText,
        color: colorHex,
      );
      if (saved == null) {
        throw StateError('Unable to save eLibrary highlight.');
      }
      if (!mounted) return;
      setState(() {
        final sectionKey = section.entryName;
        final existing = List<ElibraryMarkupRecord>.of(
          _elibraryMarkupsByHref[sectionKey] ?? const <ElibraryMarkupRecord>[],
        );
        existing.removeWhere((record) {
          return record.markupType == ElibraryMarkupRepository.highlightType &&
              record.startBlockIndex == saved.startBlockIndex &&
              record.startCharOffset == saved.startCharOffset &&
              record.endBlockIndex == saved.endBlockIndex &&
              record.endCharOffset == saved.endCharOffset;
        });
        existing.add(saved);
        existing.sort((left, right) {
          final blockCompare = left.startBlockIndex.compareTo(
            right.startBlockIndex,
          );
          if (blockCompare != 0) return blockCompare;
          final charCompare = left.startCharOffset.compareTo(
            right.startCharOffset,
          );
          if (charCompare != 0) return charCompare;
          return left.id.compareTo(right.id);
        });
        _elibraryMarkupsByHref = <String, List<ElibraryMarkupRecord>>{
          ..._elibraryMarkupsByHref,
          sectionKey: existing,
        };
        _rangeSelection = _rangeSelection.clear();
      });
    } catch (error) {
      debugPrint(
        '[LibraryBookReader] Failed to save eLibrary highlight: $error',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save highlight for $referenceLabel.'),
        ),
      );
    }
  }

  Future<void> _clearElibraryMarkupForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final existing =
        _elibraryMarkupsByHref[section.entryName] ??
        const <ElibraryMarkupRecord>[];
    final overlapping = existing
        .where((record) {
          return _elibraryMarkupOverlapsSelection(
            record,
            startBlockIndex: selectionRange.startBlockIndex,
            startCharOffset: selectionRange.startCharOffset,
            endBlockIndex: selectionRange.endBlockIndex,
            endCharOffset: selectionRange.endCharOffset,
          );
        })
        .toList(growable: false);
    if (overlapping.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved eLibrary markup overlaps this selection.'),
        ),
      );
      return;
    }

    final cleared = await ElibraryMarkupRepository()
        .clearHighlightsOverlappingSelection(
          libraryItemId: item.id,
          epubHref: section.entryName,
          startBlockIndex: selectionRange.startBlockIndex,
          startCharOffset: selectionRange.startCharOffset,
          endBlockIndex: selectionRange.endBlockIndex,
          endCharOffset: selectionRange.endCharOffset,
        );
    if (!mounted) return;
    if (cleared <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No saved eLibrary markup overlaps this selection.'),
        ),
      );
      return;
    }

    setState(() {
      final sectionKey = section.entryName;
      final updated =
          List<ElibraryMarkupRecord>.of(
            _elibraryMarkupsByHref[sectionKey] ??
                const <ElibraryMarkupRecord>[],
          )..removeWhere((record) {
            return _elibraryMarkupOverlapsSelection(
              record,
              startBlockIndex: selectionRange.startBlockIndex,
              startCharOffset: selectionRange.startCharOffset,
              endBlockIndex: selectionRange.endBlockIndex,
              endCharOffset: selectionRange.endCharOffset,
            );
          });
      _elibraryMarkupsByHref = <String, List<ElibraryMarkupRecord>>{
        ..._elibraryMarkupsByHref,
        sectionKey: updated,
      };
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Markup cleared for selected eLibrary range.'),
      ),
    );
  }

  Future<void> _addElibraryHashTagForSelection({
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String selectedText,
  }) async {
    if (section == null) return;
    final selectionRange = _librarySelectionCharRange(
      sectionBlocks: sectionBlocks,
    );
    if (selectionRange == null) return;

    final endpoints = _buildLibrarySelectionReferenceEndpoints(
      item: item,
      section: section,
      sectionBlocks: sectionBlocks,
    );
    final passage = PassageData(
      bookNumber: null,
      bookName: item.displayTitle,
      chapter: 0,
      lines: const <VerseLine>[],
    );

    final repository = HashTagRepository();
    final defaultTag = repository.normalizeTagName(
      await repository.loadDefaultTag() ?? '',
    );
    if (!mounted) return;
    if (defaultTag.isNotEmpty) {
      final result = await _applyElibraryHashTagSelectionToTag(
        repository: repository,
        item: item,
        section: section,
        sectionBlocks: sectionBlocks,
        selectedText: selectedText,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        compactRef: endpoints.compactRef,
        tag: defaultTag,
      );
      if (!mounted) return;
      if (result.tag != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tagged selected range with ${result.tag}'
              '${result.skipped > 0 ? ' (${result.skipped} already in this tag)' : ''}.',
            ),
          ),
        );
        return;
      }
    }

    await showHashTagScreen(
      Navigator.of(context),
      passage: passage,
      selection: const ViewerRangeSelection(),
      selectionTargets: const <HashTagTarget>[],
      fontScale: _fontScale,
      selectionLabelOverride: endpoints.compactRef,
      onApplySelectionOverride: (tag) => _applyElibraryHashTagSelectionToTag(
        repository: repository,
        item: item,
        section: section,
        sectionBlocks: sectionBlocks,
        selectedText: selectedText,
        startBlockIndex: selectionRange.startBlockIndex,
        startCharOffset: selectionRange.startCharOffset,
        endBlockIndex: selectionRange.endBlockIndex,
        endCharOffset: selectionRange.endCharOffset,
        compactRef: endpoints.compactRef,
        tag: tag,
      ),
    );
  }

  Future<HashTagQuickApplyResult> _applyElibraryHashTagSelectionToTag({
    required HashTagRepository repository,
    required LibraryCatalogItem item,
    required LibraryBookSection? section,
    required List<LibraryBookBlock> sectionBlocks,
    required String selectedText,
    required int startBlockIndex,
    required int startCharOffset,
    required int endBlockIndex,
    required int endCharOffset,
    required String compactRef,
    required String tag,
  }) async {
    if (section == null) {
      return const HashTagQuickApplyResult(tag: null, inserted: 0, skipped: 0);
    }
    final result = await repository.quickApplyELibrarySearchResult(
      bookTitle: item.displayTitle,
      locationText: compactRef,
      paragraphText: selectedText,
      stableRef:
          'elibrary-range:${item.id}:${section.entryName}:$startBlockIndex:$startCharOffset:$endBlockIndex:$endCharOffset',
      referenceText: compactRef,
      sourceHref: section.entryName,
      sourceAnchorId: item.anchorId,
      sourceSpineIndex: section.spineIndex,
      sourceParagraphIndex: _libraryParagraphIndexForBlockIndex(
        sectionBlocks,
        startBlockIndex,
      ),
      sourceRelativePath: item.relativePath,
      sourceLibraryItemId: item.id,
      selectedTextSnapshot: selectedText,
      selectionStartBlockIndex: startBlockIndex,
      selectionStartCharOffset: startCharOffset,
      selectionEndBlockIndex: endBlockIndex,
      selectionEndCharOffset: endCharOffset,
      selectionStartTokenIndex: _rangeSelection.lowerAnchor?.tokenIndex,
      selectionEndTokenIndex: _rangeSelection.upperAnchor?.tokenIndex,
      tag: tag,
    );
    return HashTagQuickApplyResult(
      tag: result.tag,
      inserted: result.inserted,
      skipped: result.skipped,
    );
  }

  ({int startOffset, int endOffset})? _libraryTokenSpanForIndex(
    String text,
    int tokenIndex,
  ) {
    final runs = _splitLibraryTextRuns(text);
    for (final run in runs) {
      if (run.tokenIndex != tokenIndex) continue;
      final startOffset = run.startOffset;
      final endOffset = run.endOffset;
      if (startOffset == null || endOffset == null) return null;
      return (startOffset: startOffset, endOffset: endOffset);
    }
    return null;
  }

  Future<void> _backToBible() async {
    final returnToBible = widget.onReturnToBible;
    final navigator = Navigator.of(context);
    await _saveCurrentLocation();
    if (!mounted) return;
    if (returnToBible != null) {
      returnToBible();
      return;
    }
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.maybePop();
    }
  }

  Future<void> _closeToLibrary() async {
    final navigator = Navigator.of(context);
    await _saveCurrentLocation();
    if (!mounted) return;
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.maybePop();
    }
  }

  bool get _canDropImportedBook {
    return libraryReaderCanManageImportedBook(widget.item);
  }

  Future<void> _dropImportedBook() async {
    if (!_canDropImportedBook) return;

    await _tiltAutoScroll.stop();
    if (!mounted) return;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Current Book from Library?'),
        content: Text(
          'This removes the imported database copy only. It does not delete '
          'or modify the original CaptureClipper source files.\n\n'
          'Book: "${widget.item.displayTitle}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final removed = await PioneerTextImportService.instance
        .removeImportedLibraryItem(widget.item.id);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That book could not be removed from the library.'),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed "${widget.item.displayTitle}" from eLibrary.'),
      ),
    );
    await _closeToLibrary();
  }

  Future<void> _repairImportedBook() async {
    if (!_canDropImportedBook) return;

    await _tiltAutoScroll.stop();
    if (!mounted) return;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repair Current Imported Book?'),
        content: Text(
          'This removes the imported database copy and reimports it from the '
          'configured CaptureClipper source folder.\n\n'
          'The original source files are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
            ),
            child: const Text('Repair'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    var report = await PioneerCapturedHtmlImportFolderService.instance
        .repairImportedCaptureClipperBook(libraryItemId: widget.item.id);
    if (!mounted) return;
    if (report == null || report.entries.isEmpty) {
      final selectPackage = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Select ${widget.item.sourceWorkId ?? 'book'} .zip to Repair',
          ),
          content: const Text(
            'The preserved local package source is unavailable. Select the '
            'matching .zip package (or .studybook). It will be copied into '
            'app-managed storage before repair; the selected file will not '
            'be changed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Select Package'),
            ),
          ],
        ),
      );
      if (!mounted || selectPackage != true) return;
      try {
        final selectedPath = await LibraryRootNative.pickStudyBookPackage();
        if (selectedPath == null || !mounted) return;
        await PioneerBookPackageImportService.instance.importPackage(
          selectedPath,
          setAsConfiguredFolder: false,
          expectedWorkId: widget.item.sourceWorkId,
          expectedPackageId: widget.item.sourcePackageId,
        );
        report = await PioneerCapturedHtmlImportFolderService.instance
            .repairImportedCaptureClipperBook(libraryItemId: widget.item.id);
      } on PioneerBookPackageImportException catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
        return;
      }
      if (!mounted) return;
      if (report == null || report.entries.isEmpty) {
        final failure =
            PioneerCapturedHtmlImportFolderService.instance.lastRepairFailure;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure ?? 'Repair failed without a diagnostic result.',
            ),
          ),
        );
        return;
      }
    }

    final completedReport = report;
    final repaired = completedReport.entries.firstWhere(
      (entry) => entry.libraryItemId == widget.item.id,
      orElse: () => completedReport.entries.first,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Repaired "${repaired.title}" from its CaptureClipper source.',
        ),
      ),
    );
    await _load();
  }

  Future<void> _openELibrarySetup() async {
    await _tiltAutoScroll.stop();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ELibrarySetupScreen()),
    );
  }

  Widget _buildReaderActionsMenu({
    required ThemeData theme,
    required Color textColor,
    required Color cardBackground,
    required Color cardBorder,
  }) {
    return PopupMenuButton<_ReaderBookMenuAction>(
      tooltip: 'Library actions',
      onSelected: (action) {
        switch (action) {
          case _ReaderBookMenuAction.openELibrarySetup:
            unawaited(_openELibrarySetup());
            return;
          case _ReaderBookMenuAction.removeCurrentBook:
            unawaited(_dropImportedBook());
            return;
          case _ReaderBookMenuAction.repairCurrentImportedBook:
            unawaited(_repairImportedBook());
            return;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<_ReaderBookMenuAction>>[
          const PopupMenuItem<_ReaderBookMenuAction>(
            value: _ReaderBookMenuAction.openELibrarySetup,
            child: Text('Open eLibrary Setup'),
          ),
        ];
        if (_canDropImportedBook) {
          items.addAll(const [
            PopupMenuItem<_ReaderBookMenuAction>(
              enabled: false,
              child: Text('Maintenance'),
            ),
            PopupMenuItem<_ReaderBookMenuAction>(
              value: _ReaderBookMenuAction.removeCurrentBook,
              child: Text('Remove Current Book from Library'),
            ),
            PopupMenuItem<_ReaderBookMenuAction>(
              value: _ReaderBookMenuAction.repairCurrentImportedBook,
              child: Text('Repair Current Imported Book'),
            ),
          ]);
        }
        return items;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.more_horiz,
              size: 18,
              color: textColor.withValues(alpha: 0.82),
            ),
            const SizedBox(width: 6),
            Text(
              'Menu',
              style: libraryControlTextStyle(
                context,
                theme.textTheme.labelLarge,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              color: textColor.withValues(alpha: 0.82),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCurrentLocation() async {
    if (widget.searchTarget != null && !_searchTargetPositioned) return;
    final locationIndex = _stableLiveSectionIndex ?? _selectedIndex;
    if (_sections.isEmpty ||
        locationIndex < 0 ||
        locationIndex >= _sections.length) {
      return;
    }

    final currentSection = _sections[locationIndex];
    final currentNavigationItem = _navigationItemForSectionIndex(locationIndex);
    final visibleBlock = _visibleBlockForSection(locationIndex);
    final savedHref = visibleBlock != null
        ? currentSection.entryName
        : currentNavigationItem?.href?.trim();
    final visibleAnchorId = visibleBlock?.anchorId?.trim();
    final savedAnchorId = visibleBlock != null
        ? (visibleAnchorId?.isNotEmpty == true ? visibleAnchorId : null)
        : currentNavigationItem?.parentId != null
        ? currentNavigationItem?.anchorId?.trim()
        : null;
    final savedParagraphIndex =
        visibleBlock?.bodyOrder ??
        _paragraphOrdinalForBlock(currentSection, visibleBlock) ??
        (currentNavigationItem?.parentId != null
            ? currentNavigationItem?.bodyOrder
            : null);
    await LibraryReaderStateWriter.instance.saveCurrentLocation(
      libraryItemId: widget.item.id,
      currentSectionEntryName: currentSection.entryName,
      currentSectionSpineIndex: currentSection.spineIndex,
      savedHref: savedHref,
      savedAnchorId: savedAnchorId,
      savedParagraphIndex: savedParagraphIndex,
    );
  }

  int? _paragraphOrdinalForBlock(
    LibraryBookSection section,
    LibraryBookBlock? target,
  ) {
    if (target == null || target.kind != 'paragraph') return null;
    var paragraphOrdinal = 0;
    for (final block in section.blocks) {
      if (block.kind == 'paragraph') paragraphOrdinal += 1;
      if (identical(block, target)) return paragraphOrdinal;
    }
    return null;
  }

  LibraryBookBlock? _visibleBlockForSection(int sectionIndex) {
    final section = _contentSectionForIndex(sectionIndex);
    final viewport = _continuousScrollViewKey.currentContext
        ?.findRenderObject();
    if (section == null || viewport is! RenderBox || !viewport.attached) {
      return null;
    }
    final probeY = viewport.localToGlobal(Offset.zero).dy + 24;
    LibraryBookBlock? firstBelowProbe;
    for (var index = 0; index < section.blocks.length; index++) {
      final block = section.blocks[index];
      final targetKey = _blockTargetKey(block, index);
      final blockBox = _bodyBlockKeys[targetKey]?.currentContext
          ?.findRenderObject();
      if (blockBox is! RenderBox || !blockBox.attached) continue;
      final top = blockBox.localToGlobal(Offset.zero).dy;
      final bottom = top + blockBox.size.height;
      if (top <= probeY && bottom > probeY) return block;
      if (top > probeY && firstBelowProbe == null) firstBelowProbe = block;
    }
    return firstBelowProbe;
  }

  void _selectSection(int index) {
    if (index < 0 || index >= _sections.length) return;
    final navIndex = _navigationIndexForSectionIndex(index);
    final generation = ++_chapterGeneration;
    setState(() {
      _bodyBlockKeys.clear();
      _bodyTextKeys.clear();
      _geometryRegistry.clear();
      _selectedIndex = index;
      if (navIndex != null) {
        _selectedNavigationIndex = navIndex;
      }
      _selectedHeadingTargetIndex = null;
      _pendingBodyScrollTargetKey = null;
      if (_readableSectionIndices.isNotEmpty) {
        final resolvedIndex = _readableSectionIndices.contains(index)
            ? index
            : _readableSectionIndices.firstWhere(
                (candidate) =>
                    _sectionKey(
                      _contentSectionForIndex(candidate)?.entryName ?? '',
                    ) ==
                    _sectionKey(
                      _contentSectionForIndex(index)?.entryName ?? '',
                    ),
                orElse: () => index,
              );
        _selectedIndex = resolvedIndex;
        _sectionWindow = LibraryContinuousSectionWindow(
          readableIndices: _readableSectionIndices,
          centerIndex: resolvedIndex,
        );
      }
    });
    _stableLiveSectionIndex = _selectedIndex;
    _sectionVisibilityHysteresis.reset();
    _publishLiveSectionLocation(generation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _chapterGeneration) {
        _scrollToSectionUnit(_selectedIndex);
      }
    });
  }

  void _scrollToSectionUnit(
    int index, {
    int attempt = 0,
    int? chapterGeneration,
  }) {
    final generation = chapterGeneration ?? _chapterGeneration;
    if (generation != _chapterGeneration) return;
    final itemIndex = _readableSectionIndices.indexOf(index);
    if (itemIndex >= 0 && _itemScrollController.isAttached) {
      _itemScrollController.jumpTo(index: itemIndex, alignment: 0);
      if (attempt < 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _chapterGeneration) return;
          // jumpTo can silently fail to land when the target item hasn't
          // been laid out yet — most visible on macOS jumping far across a
          // long compiled work like Early Writings. Verify the section
          // actually reached the top of the viewport and retry if not.
          final onScreenOffset = _sectionViewportOffset(index);
          if (onScreenOffset == null || onScreenOffset.abs() > 4) {
            _scrollToSectionUnit(
              index,
              attempt: attempt + 1,
              chapterGeneration: generation,
            );
          }
        });
      }
      return;
    }
    final context = _sectionUnitKeys[index]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(context, alignment: 0, duration: Duration.zero);
      return;
    }
    if (attempt < 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _chapterGeneration) return;
        _scrollToSectionUnit(
          index,
          attempt: attempt + 1,
          chapterGeneration: generation,
        );
      });
      return;
    }
    _scrollToTarget(null, chapterGeneration: generation);
  }

  LibraryBookSection? get _currentSection {
    if (_sections.isEmpty) return null;
    final index = _selectedIndex.clamp(0, _sections.length - 1);
    return _sections[index];
  }

  LibraryCatalogNavigationItem? _navigationItemForSectionIndex(int index) {
    final navigationIndex = _navigationIndexForSectionIndex(index);
    final ordered = _orderedNavigationItems;
    if (navigationIndex == null ||
        navigationIndex < 0 ||
        navigationIndex >= ordered.length) {
      return null;
    }
    return ordered[navigationIndex];
  }

  LibraryReaderDescendantChain? _readableDescendantForSectionIndex(int index) {
    if (index < 0 || index >= _sections.length || _navigationItems.isEmpty) {
      return null;
    }
    final section = _sections[index];
    if (section.blocks.isNotEmpty) return null;
    final navItem = _navigationItemForSectionIndex(index);
    if (navItem == null) return null;
    return libraryReaderFirstReadableDescendant(
      navItem: navItem,
      tree: buildLibraryNavigationTree(
        _navigationItems,
        devotionalMode: _isDevotionalNavigationBook,
        periodicalMode: widget.item.isPeriodical,
      ),
      sections: _sections,
    );
  }

  LibraryBookSection? _contentSectionForIndex(int index) {
    if (index < 0 || index >= _sections.length) return null;
    return _readableDescendantForSectionIndex(index)?.readableSection ??
        _sections[index];
  }

  List<LibraryBookSection> _composedHeadingSectionsForIndex(int index) {
    if (index < 0 || index >= _sections.length) {
      return const <LibraryBookSection>[];
    }
    final section = _sections[index];
    final navItem = _navigationItemForSectionIndex(index);
    if (navItem == null || _navigationItems.isEmpty) {
      return <LibraryBookSection>[section];
    }
    return libraryReaderComposedHeadingSections(
      navItem: navItem,
      tree: buildLibraryNavigationTree(
        _navigationItems,
        devotionalMode: _isDevotionalNavigationBook,
        periodicalMode: widget.item.isPeriodical,
      ),
      sections: _sections,
      descendantChain: _readableDescendantForSectionIndex(index),
    );
  }

  List<int> _buildReadableSectionIndices() {
    final result = <int>[];
    final seenContentIdentities = <String>{};
    for (var index = 0; index < _sections.length; index++) {
      if (!_sectionIsReadableForAutomaticContinuation(index)) continue;
      final content = _contentSectionForIndex(index);
      if (content == null) continue;
      // One XHTML spine item can legitimately be split into several reader
      // sections (chapter plus anchored subheadings). Deduplicating by href
      // alone drops every subsection after the first and makes its TOC target
      // impossible to mount. Title distinguishes those real boundaries while
      // still collapsing duplicate structural/readable representations.
      final identity =
          '${_sectionKey(content.entryName)}|'
          '${_normalizeReaderLabel(content.title)}';
      if (!seenContentIdentities.add(identity)) continue;
      result.add(index);
    }
    return List<int>.unmodifiable(result);
  }

  void _initializeContinuousWindow() {
    _readableSectionIndices = _buildReadableSectionIndices();
    if (!_readableSectionIndices.contains(_selectedIndex)) {
      final selectedContent = _contentSectionForIndex(_selectedIndex);
      final selectedIdentity = selectedContent == null
          ? ''
          : _sectionKey(selectedContent.entryName);
      _selectedIndex = _readableSectionIndices.firstWhere(
        (index) =>
            _sectionKey(_contentSectionForIndex(index)?.entryName ?? '') ==
            selectedIdentity,
        orElse: () => _readableSectionIndices.isEmpty
            ? _selectedIndex
            : _readableSectionIndices.first,
      );
    }
    final selectedLabel = _sections.isEmpty
        ? ''
        : libraryReaderDisplaySectionTitle(_sections[_selectedIndex].title);
    final selectedPosition = _readableSectionIndices.indexOf(_selectedIndex);
    _sectionWindow = _readableSectionIndices.isEmpty
        ? null
        : LibraryContinuousSectionWindow(
            readableIndices: _readableSectionIndices,
            centerIndex: _selectedIndex,
            minimumReadablePosition: _isReaderChapterOneLabel(selectedLabel)
                ? selectedPosition.clamp(0, _readableSectionIndices.length)
                : 0,
          );
    _stableLiveSectionIndex = _selectedIndex;
    _sectionVisibilityHysteresis.reset();
  }

  List<int> get _mountedSectionIndices =>
      _sectionWindow?.mountedIndices ??
      (_sections.isEmpty ? const <int>[] : <int>[_selectedIndex]);

  int? _adjacentWindowReadableIndex({required bool forward}) {
    final position = _readableSectionIndices.indexOf(
      _stableLiveSectionIndex ?? _selectedIndex,
    );
    if (position < 0) return null;
    final nextPosition = forward ? position + 1 : position - 1;
    if (nextPosition < 0 || nextPosition >= _readableSectionIndices.length) {
      return null;
    }
    return _readableSectionIndices[nextPosition];
  }

  void _updateContinuousWindowFromVisibility() {
    final positions =
        _itemPositionsListener.itemPositions.value
            .where((position) => position.itemTrailingEdge > 0)
            .toList(growable: false)
          ..sort((left, right) => left.index.compareTo(right.index));
    if (positions.isEmpty || _readableSectionIndices.isEmpty) return;

    // The probe is inside the viewport. A section becomes current only when
    // its own pixels naturally cross that line; the resulting identity update
    // never changes the list, scroll position, or mounted children.
    var visiblePosition = positions.first;
    for (final position in positions) {
      if (position.itemLeadingEdge > 0.25) break;
      visiblePosition = position;
    }
    if (visiblePosition.index < 0 ||
        visiblePosition.index >= _readableSectionIndices.length) {
      return;
    }
    final visibleIndex = _readableSectionIndices[visiblePosition.index];
    final sectionChanged = _stableLiveSectionIndex != visibleIndex;
    _stableLiveSectionIndex = visibleIndex;
    _publishLiveSectionLocationForIndex(
      visibleIndex,
      ++_liveSectionGeneration,
      includeVisibleHeading: true,
    );
    if (sectionChanged) {
      _selectedHeadingTargetIndex = null;
    }
  }

  LibraryCatalogNavigationItem? get _selectedNavigationItem {
    final navigationItems = _orderedNavigationItems;
    if (_selectedNavigationIndex < 0 ||
        _selectedNavigationIndex >= navigationItems.length) {
      return null;
    }
    return navigationItems[_selectedNavigationIndex];
  }

  /// Resolves the first readable descendant within the currently selected
  /// TOC node's own subtree, for composing a useful display when that node
  /// is heading-only. Returns null when the node has readable content of
  /// its own, or no readable descendant exists in its subtree.
  LibraryReaderDescendantChain? get _currentSectionReadableDescendantChain {
    return _readableDescendantForSectionIndex(_selectedIndex);
  }

  List<LibraryBookSection> _currentComposedHeadingSections() {
    return _composedHeadingSectionsForIndex(_selectedIndex);
  }

  void _publishLiveSectionLocation(int generation) {
    _publishLiveSectionLocationForIndex(
      _stableLiveSectionIndex ?? _selectedIndex,
      generation,
    );
  }

  void _publishLiveSectionLocationForIndex(
    int index,
    int generation, {
    bool includeVisibleHeading = false,
  }) {
    if (index < 0 || index >= _sections.length) return;
    final currentSection = _sections[index];
    final composedSections = _composedHeadingSectionsForIndex(index);
    debugPrint(
      'SL27_TRACE index=$index '
      'navItemId=${_navigationItemForSectionIndex(index)?.id} '
      'composedSections=${composedSections.map((s) => s.entryName).toList()}',
    );
    final labels = libraryReaderLiveSectionHeadingLabels(
      composedSections: composedSections,
      bookTitle: widget.item.displayTitle,
    ).toList(growable: true);
    if (includeVisibleHeading) {
      final visibleHeading = _visibleHeadingForSection(index);
      if (visibleHeading != null &&
          visibleHeading.isNotEmpty &&
          (labels.isEmpty ||
              _normalizeReaderLabel(labels.last) !=
                  _normalizeReaderLabel(visibleHeading))) {
        labels.add(visibleHeading);
      }
    }
    if (labels.isEmpty) return;
    _liveSection.update(
      LibraryLiveSectionLocation(
        navigationId: _navigationItemForSectionIndex(index)?.id,
        sectionEntryName: currentSection.entryName,
        headingLabels: labels,
        generation: generation,
      ),
    );
  }

  String? _visibleHeadingForSection(int sectionIndex) {
    final section = _contentSectionForIndex(sectionIndex);
    final viewport = _continuousScrollViewKey.currentContext
        ?.findRenderObject();
    if (section == null ||
        viewport is! RenderBox ||
        !viewport.attached ||
        section.blocks.isEmpty) {
      return null;
    }

    final probeY = viewport.localToGlobal(Offset.zero).dy + 40;
    String? nearestHeading;
    for (var blockIndex = 0; blockIndex < section.blocks.length; blockIndex++) {
      final block = section.blocks[blockIndex];
      if (!_isReaderStructuralHeading(block)) continue;
      final key = _blockTargetKey(block, blockIndex);
      final renderObject = _bodyBlockKeys[key]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) continue;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      if (top > probeY) break;
      final label = libraryReaderDisplaySectionTitle(block.text);
      if (label.isNotEmpty) nearestHeading = label;
    }
    return nearestHeading;
  }

  bool _isReaderStructuralHeading(LibraryBookBlock block) {
    if (block.isHeading) return true;
    final text = block.text.trim();
    return RegExp(
      r'^(?:chapter\s+\d+\b|introduction\b|preface\b|appendix\b|response\s+of\s+history\b)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool get _isDevotionalNavigationBook {
    return widget.item.isDevotional || isDevotionalNavigation(_navigationItems);
  }

  String get _currentSubtitle {
    return libraryReaderBookSubtitle(
      widget.item,
      sectionTitle: libraryReaderDisplaySectionTitle(
        _currentSection?.title ?? '',
      ),
    );
  }

  int _initialSectionIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required bool devotionalMode,
  }) {
    return libraryReaderInitialSectionIndex(
      item: widget.item,
      sections: sections,
      navigationItems: navigationItems,
      devotionalMode: devotionalMode,
      initialHref: widget.initialHref,
      initialSpineIndex: widget.initialSpineIndex,
    );
  }

  int? _readableSectionIndexForHref(
    List<LibraryBookSection> sections,
    String href,
  ) {
    final sectionIndex = _sectionIndexForHref(sections, href);
    if (sectionIndex == null) return null;
    return _isRealContentSection(sections[sectionIndex]) ? sectionIndex : null;
  }

  int? _sectionIndexForSpineIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    if (navigationItems.isNotEmpty) {
      for (var i = 0; i < navigationItems.length; i++) {
        final nav = navigationItems[i];
        if (nav.spineIndex == spineIndex) {
          final sectionIndex = _sectionIndexForNavigationItemInSections(
            sections,
            nav,
          );
          if (sectionIndex != null) return sectionIndex;
        }
      }
    }

    if (spineIndex > 0 && spineIndex <= sections.length) {
      return spineIndex - 1;
    }

    return null;
  }

  int? _navigationIndexForSavedState({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    if (navigationItems.isEmpty) return null;
    for (var i = 0; i < navigationItems.length; i++) {
      final nav = navigationItems[i];
      if (nav.spineIndex == spineIndex) {
        final sectionIndex = _sectionIndexForNavigationItemInSections(
          sections,
          nav,
        );
        if (sectionIndex != null) return sectionIndex;
      }
    }
    if (spineIndex > 0 && spineIndex <= sections.length) {
      return spineIndex - 1;
    }
    return null;
  }

  int? _readableSectionIndexForSpineIndex({
    required List<LibraryBookSection> sections,
    required List<LibraryCatalogNavigationItem> navigationItems,
    required int spineIndex,
  }) {
    final sectionIndex = _sectionIndexForSpineIndex(
      sections: sections,
      navigationItems: navigationItems,
      spineIndex: spineIndex,
    );
    if (sectionIndex == null) return null;
    return _isRealContentSection(sections[sectionIndex]) ? sectionIndex : null;
  }

  int? _sectionIndexForHref(List<LibraryBookSection> sections, String href) {
    final normalizedHref = p.normalize(href).toLowerCase();
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (_hrefMatchesSection(section.entryName, normalizedHref)) {
        return index;
      }
    }
    return null;
  }

  int? _firstRealContentSectionIndex(List<LibraryBookSection> sections) {
    int? firstMeaningfulIndex;
    for (var index = 0; index < sections.length; index++) {
      final section = sections[index];
      if (!libraryIsMeaningfulReadingSection(
        title: section.title,
        href: section.entryName,
        paragraphs: section.paragraphs,
        bookTitle: widget.item.displayTitle,
      )) {
        continue;
      }
      firstMeaningfulIndex ??= index;
      if (libraryIsFrontMatterOpeningLabel(section.title) ||
          libraryIsFrontMatterOpeningLabel(
            p.basenameWithoutExtension(section.entryName),
          )) {
        continue;
      }
      return index;
    }
    if (firstMeaningfulIndex != null) return firstMeaningfulIndex;
    return sections.isEmpty ? null : 0;
  }

  bool _isRealContentSection(LibraryBookSection section) {
    return libraryIsMeaningfulReadingSection(
      title: section.title,
      href: section.entryName,
      paragraphs: section.paragraphs,
      bookTitle: widget.item.displayTitle,
    );
  }

  bool _isReaderChapterOneLabel(String value) {
    final normalized = _normalizeReaderLabel(value);
    if (normalized.isEmpty) return false;

    const prefixes = <String>[
      'chapter 1',
      'chapter i',
      'chapter one',
      '1 ',
      '1.',
      '1)',
      'i ',
      'i.',
      'i)',
    ];
    for (final prefix in prefixes) {
      if (normalized == prefix.trim() || normalized.startsWith(prefix)) {
        return true;
      }
    }

    return false;
  }

  List<LibraryCatalogNavigationItem> get _orderedNavigationItems {
    if (_navigationItems.isEmpty) return const [];

    final tree = buildLibraryNavigationTree(
      libraryReaderContentsDisplayNavigationItems(
        items: _navigationItems,
        sections: _sections,
        bookTitle: widget.item.displayTitle,
      ),
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    return tree.items;
  }

  int? _navigationIndexForSectionIndex(int sectionIndex) {
    if (sectionIndex < 0 || sectionIndex >= _sections.length) return null;
    final section = _sections[sectionIndex];
    final sectionHref = p.normalize(section.entryName).toLowerCase();
    final sectionSpineIndex = section.spineIndex;
    final navigationItems = _orderedNavigationItems;

    // Exact, fragment-preserving match first: entryName commonly embeds the
    // in-file anchor (e.g. "content.xhtml#heading-2-4"), and several
    // sections legitimately share one physical file with only their anchor
    // telling them apart. The fragment-stripped/spine-index fallback below
    // can't distinguish those — it matches whichever nav item for that file
    // comes first, which silently mis-resolves every other heading in the
    // file to that one.
    for (var index = 0; index < navigationItems.length; index++) {
      final rawNavHref = p
          .normalize((navigationItems[index].href ?? '').trim())
          .toLowerCase();
      if (rawNavHref.isNotEmpty && rawNavHref == sectionHref) {
        return index;
      }
    }

    for (var index = 0; index < navigationItems.length; index++) {
      final nav = navigationItems[index];
      final navHref = _cleanNavigationHref(nav.href);
      if (navHref != null && _hrefMatchesSection(navHref, sectionHref)) {
        return index;
      }
      if (sectionSpineIndex != null && nav.spineIndex == sectionSpineIndex) {
        return index;
      }
    }
    return null;
  }

  int? _sectionIndexForNavigationItem(LibraryCatalogNavigationItem item) {
    return _librarySectionIndexForNavigationItem(
      sections: _sections,
      navItem: item,
    );
  }

  int? _sectionIndexForNavigationItemInSections(
    List<LibraryBookSection> sections,
    LibraryCatalogNavigationItem item,
  ) {
    if (sections.isEmpty) return null;
    final href = _cleanNavigationHref(item.href);
    if (href != null) {
      final normalizedHref = href.toLowerCase();
      for (var index = 0; index < sections.length; index++) {
        if (_hrefMatchesSection(sections[index].entryName, normalizedHref)) {
          return index;
        }
      }
    }

    if (item.spineIndex != null) {
      for (var index = 0; index < sections.length; index++) {
        if (sections[index].spineIndex == item.spineIndex) return index;
      }
    }

    return null;
  }

  String? _firstRealContentNavigationHref(
    List<LibraryCatalogNavigationItem> navigationItems,
  ) {
    if (navigationItems.isEmpty) return null;

    // Imports can mark an intro/preface as the body start when it carries
    // enough text, so a body-start flag alone is not trusted; the label must
    // not look like front matter either.
    bool looksLikeFrontMatter(LibraryCatalogNavigationItem item, String href) {
      return item.isFrontMatter ||
          libraryIsFrontMatterOpeningLabel(item.label) ||
          libraryIsFrontMatterOpeningLabel(p.basenameWithoutExtension(href));
    }

    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (looksLikeFrontMatter(item, href)) continue;
      return href;
    }

    // Every navigation item looks like front matter; fall back to the first
    // one that is at least not pure metadata (cover/TOC/copyright).
    for (final item in navigationItems) {
      final href = _cleanNavigationHref(item.href);
      if (href == null) continue;
      if (_isReaderMetadataHelpLabel(item.label) ||
          _isReaderMetadataHelpLabel(p.basenameWithoutExtension(href)) ||
          item.isFrontMatter) {
        continue;
      }
      return href;
    }

    return null;
  }

  String? _devotionalInitialNavigationHref(
    List<LibraryCatalogNavigationItem> navigationItems,
  ) {
    if (navigationItems.isEmpty) return null;

    final tree = buildLibraryNavigationTree(
      navigationItems,
      devotionalMode: true,
    );
    final roots = tree.childrenByParent[null] ?? const [];
    if (roots.isEmpty) return null;

    final now = DateTime.now();
    final currentMonth = _devotionalMonthName(now.month);
    final currentDay = now.day;

    final todayTarget = _devotionalNavigationHrefForMonthAndDay(
      roots: roots,
      tree: tree,
      monthName: currentMonth,
      day: currentDay,
    );
    if (todayTarget != null) return todayTarget;

    final currentMonthTarget = _devotionalNavigationHrefForMonth(
      roots: roots,
      tree: tree,
      monthName: currentMonth,
    );
    if (currentMonthTarget != null) return currentMonthTarget;

    final januaryTarget = _devotionalNavigationHrefForMonth(
      roots: roots,
      tree: tree,
      monthName: 'january',
    );
    if (januaryTarget != null) return januaryTarget;

    return _firstRealContentNavigationHref(navigationItems);
  }

  String? _devotionalNavigationHrefForMonthAndDay({
    required List<LibraryCatalogNavigationItem> roots,
    required LibraryNavigationTreeResult tree,
    required String monthName,
    required int day,
  }) {
    final monthRoot = _devotionalMonthRoot(roots, monthName);
    if (monthRoot == null) return null;

    final children = tree.childrenByParent[monthRoot.id] ?? const [];
    final dayMatch = _devotionalDayChild(children, monthName, day);
    if (dayMatch != null) return _cleanNavigationHref(dayMatch.href);

    return null;
  }

  String? _devotionalNavigationHrefForMonth({
    required List<LibraryCatalogNavigationItem> roots,
    required LibraryNavigationTreeResult tree,
    required String monthName,
  }) {
    final monthRoot = _devotionalMonthRoot(roots, monthName);
    if (monthRoot == null) return null;

    final children = tree.childrenByParent[monthRoot.id] ?? const [];
    final firstChild = children.firstWhere(
      (child) => _cleanNavigationHref(child.href) != null,
      orElse: () => monthRoot,
    );
    final firstChildHref = _cleanNavigationHref(firstChild.href);
    if (firstChildHref != null) return firstChildHref;

    return _cleanNavigationHref(monthRoot.href);
  }

  LibraryCatalogNavigationItem? _devotionalMonthRoot(
    List<LibraryCatalogNavigationItem> roots,
    String monthName,
  ) {
    for (final root in roots) {
      final labelInfo = parseDevotionalNavigationLabel(root.label);
      if (labelInfo != null &&
          labelInfo.isMonthHeading &&
          _devotionalMonthName(labelInfo.monthIndex) == monthName) {
        return root;
      }
    }
    return null;
  }

  LibraryCatalogNavigationItem? _devotionalDayChild(
    List<LibraryCatalogNavigationItem> children,
    String monthName,
    int day,
  ) {
    for (final child in children) {
      final labelInfo = parseDevotionalNavigationLabel(child.label);
      if (labelInfo == null || labelInfo.isMonthHeading) continue;
      if (_devotionalMonthName(labelInfo.monthIndex) != monthName) continue;
      if (labelInfo.day == day) return child;
    }
    return null;
  }

  String _devotionalMonthName(int monthIndex) {
    const months = <String>[
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];
    if (monthIndex < 1 || monthIndex > months.length) return '';
    return months[monthIndex - 1];
  }

  void _selectNavigationItem(LibraryCatalogNavigationItem navItem) {
    final navigationItems = _orderedNavigationItems;
    final navIndex = navigationItems.indexWhere((nav) => nav.id == navItem.id);
    final tree = buildLibraryNavigationTree(
      navigationItems,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    final normalizedNavItem = libraryReaderVisibleContentsNavigationItem(
      navItem: navItem,
      tree: tree,
      sections: _sections,
    );
    final effectiveNavItem = normalizedNavItem ?? navItem;
    final effectiveNavIndex = normalizedNavItem == null
        ? navIndex
        : navigationItems.indexWhere((nav) => nav.id == normalizedNavItem.id);
    final matchedSectionIndex = _sectionIndexForNavigationItem(
      effectiveNavItem,
    );
    final effectiveSectionIndex = matchedSectionIndex == null
        ? null
        : _readableSectionIndexForSelection(matchedSectionIndex);
    final targetSection =
        effectiveSectionIndex != null &&
            effectiveSectionIndex >= 0 &&
            effectiveSectionIndex < _sections.length
        ? _sections[effectiveSectionIndex]
        : _currentSection;
    final targetKey =
        libraryReaderContentsTargetKeyForNavigationItem(
          navItem: effectiveNavItem,
          sections: _sections,
        ) ??
        _fallbackTargetKeyForNavigationItem(
          effectiveNavItem,
          section: targetSection,
        );
    final shouldJumpToSectionStart =
        libraryReaderNavigationItemTargetsSectionStart(
          navItem: effectiveNavItem,
          sections: _sections,
        );
    final changesSection =
        effectiveSectionIndex != null &&
        effectiveSectionIndex != _selectedIndex;
    final generation = changesSection
        ? ++_chapterGeneration
        : _chapterGeneration;
    setState(() {
      if (changesSection) {
        _bodyBlockKeys.clear();
        _bodyTextKeys.clear();
        _geometryRegistry.clear();
      }
      if (effectiveNavIndex >= 0) {
        _selectedNavigationIndex = effectiveNavIndex;
      }
      if (effectiveSectionIndex != null) {
        _selectedIndex = effectiveSectionIndex;
      }
      _pendingBodyScrollTargetKey = targetKey;
    });
    _publishLiveSectionLocation(generation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _chapterGeneration) return;

      // A block inside another section cannot be resolved until that section
      // has first been brought into ScrollablePositionedList's mounted range.
      // This is especially visible when navigating backwards to the opening
      // chapters of a book from a later chapter on macOS.
      if (changesSection) {
        _scrollToSectionUnit(
          effectiveSectionIndex,
          chapterGeneration: generation,
        );
        if (shouldJumpToSectionStart || targetKey == null) {
          _pendingBodyScrollTargetKey = null;
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _chapterGeneration) return;
          _scrollToTarget(targetKey, chapterGeneration: generation);
        });
        return;
      }

      if ((shouldJumpToSectionStart || targetKey == null) &&
          effectiveSectionIndex != null) {
        _scrollToSectionUnit(
          effectiveSectionIndex,
          chapterGeneration: generation,
        );
        _pendingBodyScrollTargetKey = null;
        return;
      }
      _scrollToTarget(targetKey, chapterGeneration: generation);
    });
  }

  int _readableSectionIndexForSelection(int sectionIndex) {
    if (_readableSectionIndices.isEmpty ||
        _readableSectionIndices.contains(sectionIndex)) {
      return sectionIndex;
    }
    final targetSection = _contentSectionForIndex(sectionIndex);
    final targetEntryName = targetSection?.entryName;
    if (targetSection == null ||
        targetEntryName == null ||
        targetEntryName.trim().isEmpty) {
      return sectionIndex;
    }
    final targetKey = _sectionKey(targetEntryName);
    final targetTitle = _normalizeReaderLabel(targetSection.title);
    return _readableSectionIndices.firstWhere((candidate) {
      final candidateSection = _contentSectionForIndex(candidate);
      return _sectionKey(candidateSection?.entryName ?? '') == targetKey &&
          _normalizeReaderLabel(candidateSection?.title ?? '') == targetTitle;
    }, orElse: () => sectionIndex);
  }

  double _pageScrollStep() {
    final position = _bodyScrollPosition;
    if (position != null) {
      final viewportHeight = position.viewportDimension;
      if (viewportHeight > 0) {
        return viewportHeight * 0.9;
      }
    }
    return MediaQuery.sizeOf(context).height * 0.9;
  }

  double? _scrollOffsetForContext(BuildContext targetContext) {
    if (_bodyScrollPosition == null) return null;
    final renderObject = targetContext.findRenderObject();
    if (renderObject == null) return null;
    final viewport = RenderAbstractViewport.of(renderObject);
    return viewport.getOffsetToReveal(renderObject, 0).offset;
  }

  List<_ReaderHeadingTarget> _headingTargetsForCurrentSection() {
    final currentSection = _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) {
      return const [];
    }

    final targets = <_ReaderHeadingTarget>[];
    final currentSectionHref = p
        .normalize(currentSection.entryName)
        .toLowerCase();
    final currentSectionSpineIndex = currentSection.spineIndex;

    final navigationTargets = _orderedNavigationItems
        .where((navItem) {
          final contentKind = navItem.contentKind?.trim().toLowerCase();
          if (contentKind != 'body_subsection') return false;
          final navHref = _cleanNavigationHref(navItem.href);
          if (navHref != null &&
              _hrefMatchesSection(navHref, currentSectionHref)) {
            return true;
          }
          return currentSectionSpineIndex != null &&
              navItem.spineIndex == currentSectionSpineIndex;
        })
        .toList(growable: false);

    for (final navItem in navigationTargets) {
      final targetKey = _navigationTargetKey(navItem);
      if (targetKey == null) continue;
      final targetContext = _bodyBlockKeys[targetKey]?.currentContext;
      if (targetContext == null) continue;

      final targetOffset = _scrollOffsetForContext(targetContext);
      if (targetOffset == null) continue;

      targets.add(_ReaderHeadingTarget(key: targetKey, offset: targetOffset));
    }

    if (targets.isEmpty) {
      final normalizedSectionTitle = _normalizeReaderLabel(
        currentSection.title,
      );
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (!block.isHeading) continue;

        if (normalizedSectionTitle.isNotEmpty &&
            _normalizeReaderLabel(block.text) == normalizedSectionTitle) {
          continue;
        }

        final targetKey = _blockTargetKey(block, index);
        final targetContext = _bodyBlockKeys[targetKey]?.currentContext;
        if (targetContext == null) continue;

        final targetOffset = _scrollOffsetForContext(targetContext);
        if (targetOffset == null) continue;

        targets.add(_ReaderHeadingTarget(key: targetKey, offset: targetOffset));
      }
    }

    targets.sort((left, right) => left.offset.compareTo(right.offset));
    return targets;
  }

  void _scrollToAdjacentHeading({required bool forward}) {
    if (_sections.isEmpty) return;
    final position = _bodyScrollPosition;
    if (position == null) return;

    // Periodicals have one article per spine section; jump directly to the
    // adjacent section instead of hunting for sub-headings within the page.
    if (widget.item.isPeriodical) {
      final adjacent = _adjacentWindowReadableIndex(forward: forward);
      if (adjacent != null) _selectSection(adjacent);
      return;
    }

    final targets = _headingTargetsForCurrentSection();
    if (targets.isEmpty) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = _adjacentWindowReadableIndex(forward: forward);
      if (fallbackIndex != null) _selectSection(fallbackIndex);
      return;
    }

    final currentOffset = position.pixels;
    const epsilon = 1.0;

    _ReaderHeadingTarget? target;
    var targetIndex = _selectedHeadingTargetIndex;
    if (targetIndex != null &&
        (targetIndex < 0 || targetIndex >= targets.length)) {
      targetIndex = null;
    }

    if (targetIndex != null) {
      final candidateIndex = forward ? targetIndex + 1 : targetIndex - 1;
      if (candidateIndex >= 0 && candidateIndex < targets.length) {
        targetIndex = candidateIndex;
        target = targets[targetIndex];
      } else {
        targetIndex = null;
      }
    }

    if (target == null) {
      if (forward) {
        for (var index = 0; index < targets.length; index++) {
          final candidate = targets[index];
          if (candidate.offset > currentOffset + epsilon) {
            target = candidate;
            targetIndex = index;
            break;
          }
        }
      } else {
        for (var index = targets.length - 1; index >= 0; index--) {
          final candidate = targets[index];
          if (candidate.offset < currentOffset - epsilon) {
            target = candidate;
            targetIndex = index;
            break;
          }
        }
      }
    }

    if (target == null) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = _adjacentWindowReadableIndex(forward: forward);
      if (fallbackIndex != null) _selectSection(fallbackIndex);
      return;
    }

    final targetContext = _bodyBlockKeys[target.key]?.currentContext;
    if (targetContext == null) {
      _selectedHeadingTargetIndex = null;
      final fallbackIndex = _adjacentWindowReadableIndex(forward: forward);
      if (fallbackIndex != null) _selectSection(fallbackIndex);
      return;
    }

    _selectedHeadingTargetIndex = targetIndex;

    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.08,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  String? _initialScrollTargetKey() {
    if (_hasExplicitInitialSourceLocation) {
      return _explicitInitialScrollTargetKey();
    }

    final savedTargetKey =
        _isDevotionalNavigationBook || _ignoreSavedInitialLocation
        ? null
        : _savedLocationTargetKey();
    if (savedTargetKey != null) return savedTargetKey;

    final selectedNavigationItem = _selectedNavigationItem;
    if (selectedNavigationItem != null &&
        !libraryIsFrontMatterOpeningLabel(selectedNavigationItem.label)) {
      final navigationTarget = _fallbackTargetKeyForNavigationItem(
        selectedNavigationItem,
      );
      if (navigationTarget != null) return navigationTarget;
    }

    final headingTargets = _headingTargetsForCurrentSection();
    if (headingTargets.isNotEmpty) {
      return headingTargets.first.key;
    }

    return null;
  }

  bool get _hasExplicitInitialSourceLocation {
    return widget.searchTarget != null ||
        (widget.initialHref?.trim().isNotEmpty ?? false) ||
        (widget.initialAnchorId?.trim().isNotEmpty ?? false) ||
        (widget.initialSpineIndex != null && widget.initialSpineIndex! > 0) ||
        (widget.initialParagraphIndex != null &&
            widget.initialParagraphIndex! > 0);
  }

  String? _explicitInitialScrollTargetKey() {
    // Structural TOC entries may be heading-only shells whose readable
    // descendant is what the continuous reader actually renders.
    final currentSection =
        _contentSectionForIndex(_selectedIndex) ?? _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final initialHrefParts = _splitReaderHref(
      widget.searchTarget?.href ?? widget.initialHref,
    );
    final initialAnchorId =
        widget.initialAnchorId?.trim() ?? initialHrefParts.anchor ?? '';
    if (initialAnchorId.isNotEmpty) {
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (block.anchorId?.trim() == initialAnchorId) {
          return _blockTargetKey(block, index);
        }
      }
    }

    final initialParagraphIndex =
        widget.searchTarget?.paragraphOnSection ?? widget.initialParagraphIndex;
    if (initialParagraphIndex != null && initialParagraphIndex > 0) {
      var paragraphCounter = 0;
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (block.kind != 'paragraph') continue;
        paragraphCounter += 1;
        if (paragraphCounter == initialParagraphIndex) {
          final matchedText = widget.searchTarget?.matchedText?.trim() ?? '';
          if (matchedText.isEmpty ||
              _searchTargetTextMatches(block.text, matchedText)) {
            return _blockTargetKey(block, index);
          }
          break;
        }
      }
    }

    // Legacy indexes and EPUB renderers do not universally agree on whether
    // headings and zero-based ordinals participate in paragraph numbering.
    // The indexed paragraph snapshot is retained on the typed target, so use
    // it as a deterministic fallback inside the already-resolved section.
    final matchedText = widget.searchTarget?.matchedText?.trim() ?? '';
    if (matchedText.isNotEmpty) {
      final normalizedMatch = _normalizedSearchTargetText(matchedText);
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (block.kind != 'paragraph') continue;
        final normalizedBlock = _normalizedSearchTargetText(block.text);
        if (_searchTargetTextMatches(normalizedBlock, normalizedMatch)) {
          return _blockTargetKey(block, index);
        }
      }
    }

    return null;
  }

  String _normalizedSearchTargetText(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  bool _searchTargetTextMatches(String left, String right) {
    final normalizedLeft = _normalizedSearchTargetText(left);
    final normalizedRight = _normalizedSearchTargetText(right);
    return normalizedLeft == normalizedRight ||
        normalizedLeft.contains(normalizedRight) ||
        normalizedRight.contains(normalizedLeft);
  }

  String? _savedLocationTargetKey() {
    final currentSection = _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final savedAnchorId = widget.item.anchorId?.trim() ?? '';
    final savedBodyOrder = widget.item.paragraphIndex;
    if (savedAnchorId.isEmpty && savedBodyOrder == null) return null;

    for (var index = 0; index < currentSection.blocks.length; index++) {
      final block = currentSection.blocks[index];
      if (savedAnchorId.isNotEmpty && block.anchorId?.trim() == savedAnchorId) {
        return _blockTargetKey(block, index);
      }
      if (savedBodyOrder != null && block.bodyOrder == savedBodyOrder) {
        return _blockTargetKey(block, index);
      }
    }

    return null;
  }

  String? _fallbackTargetKeyForNavigationItem(
    LibraryCatalogNavigationItem navItem, {
    LibraryBookSection? section,
  }) {
    final currentSection = section ?? _currentSection;
    if (currentSection == null || currentSection.blocks.isEmpty) return null;

    final normalizedNavLabel = _normalizeReaderLabel(
      navigationDisplayLabel(
        navItem,
        devotionalMode: _isDevotionalNavigationBook,
      ),
    );
    final normalizedRawLabel = _normalizeReaderLabel(navItem.label);
    final isChapterOneNavigation =
        _isReaderChapterOneLabel(navItem.label) ||
        _isReaderChapterOneLabel(normalizedNavLabel) ||
        _isReaderChapterOneLabel(normalizedRawLabel);

    for (var index = 0; index < currentSection.blocks.length; index++) {
      final block = currentSection.blocks[index];
      if (!block.isHeading) continue;
    }

    if (isChapterOneNavigation) {
      for (var index = 0; index < currentSection.blocks.length; index++) {
        final block = currentSection.blocks[index];
        if (!block.isHeading) continue;
        if (_isReaderChapterOneLabel(block.text)) {
          return _blockTargetKey(block, index);
        }
      }
    }

    return null;
  }

  void _scrollToTarget(
    String? targetKey, {
    int attempt = 0,
    int? chapterGeneration,
  }) {
    final generation = chapterGeneration ?? _chapterGeneration;
    if (generation != _chapterGeneration) return;
    final position = _bodyScrollPosition;
    if (position == null) {
      if (attempt < 6) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || generation != _chapterGeneration) return;
          _scrollToTarget(
            targetKey,
            attempt: attempt + 1,
            chapterGeneration: generation,
          );
        });
      }
      return;
    }
    final resolvedTargetKey = targetKey ?? _pendingBodyScrollTargetKey;
    final targetContext = resolvedTargetKey == null
        ? null
        : _bodyBlockKeys[resolvedTargetKey]?.currentContext;
    if (targetContext != null) {
      _selectedHeadingTargetIndex = null;
      final target = widget.searchTarget;
      if (target != null) {
        debugPrint('search_target_widget_found ${target.diagnosticSummary}');
      }
      // ScrollablePositionedList can shift its internal origin when jumping
      // between distant items. A cached ScrollPosition offset is therefore
      // not a reliable coordinate for a newly mounted block on macOS. Reveal
      // the actual render object through its owning scrollable instead.
      final scroll = Scrollable.ensureVisible(
        targetContext,
        alignment: 0.08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
      );
      _pendingBodyScrollTargetKey = null;
      unawaited(
        scroll.then((_) {
          if (!mounted) return;
          _searchTargetPositioned = true;
          if (target != null) {
            debugPrint(
              'search_target_scroll_completed ${target.diagnosticSummary}',
            );
          }
        }),
      );
      return;
    }

    if (resolvedTargetKey != null && attempt < 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || generation != _chapterGeneration) return;
        _scrollToTarget(
          resolvedTargetKey,
          attempt: attempt + 1,
          chapterGeneration: generation,
        );
      });
      return;
    }

    _pendingBodyScrollTargetKey = null;
    _selectedHeadingTargetIndex = null;
    final searchTarget = widget.searchTarget;
    if (searchTarget != null) {
      debugPrint(
        'search_target_resolution_failed ${searchTarget.diagnosticSummary} '
        'reason=legacy target widget not mounted after bounded retries',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The exact search location could not be positioned.'),
        ),
      );
      return;
    }
    position.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  void _scrollPageUp() {
    final position = _bodyScrollPosition;
    if (position == null) return;
    _selectedHeadingTargetIndex = null;
    final target = (position.pixels - _pageScrollStep()).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    position.jumpTo(target);
  }

  void _scrollPageDown() {
    final position = _bodyScrollPosition;
    if (position == null) return;
    _selectedHeadingTargetIndex = null;
    final target = (position.pixels + _pageScrollStep()).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return;
    position.jumpTo(target);
  }

  String? _navigationTargetKey(LibraryCatalogNavigationItem navItem) {
    final anchorId = navItem.anchorId?.trim();
    if (anchorId != null && anchorId.isNotEmpty) {
      return 'anchor:${_normalizeBlockKey(anchorId)}';
    }
    final bodyOrder = navItem.bodyOrder;
    if (bodyOrder != null) {
      return 'body:$bodyOrder';
    }
    return null;
  }

  String _blockTargetKey(LibraryBookBlock block, int index) {
    final anchorId = block.anchorId?.trim();
    if (anchorId != null && anchorId.isNotEmpty) {
      return 'anchor:${_normalizeBlockKey(anchorId)}';
    }
    final bodyOrder = block.bodyOrder;
    if (bodyOrder != null) {
      return 'body:$bodyOrder';
    }
    return 'block:$index';
  }

  GlobalKey _keyForBlock(String key) {
    return _bodyBlockKeys.putIfAbsent(key, GlobalKey.new);
  }

  GlobalKey _textKeyForBlock(String key) {
    return _bodyTextKeys.putIfAbsent(key, GlobalKey.new);
  }

  ({int blockIndex, int tokenIndex})? _resolveLibraryDragTokenHit({
    required Offset globalPosition,
    required List<LibraryBookBlock> sectionBlocks,
    required int preferredBlockIndex,
    required double bodyFontSize,
    required Color textColor,
    required bool isNightMode,
    required String? highlightQuery,
    required List<String> highlightTerms,
    required TextDirection textDirection,
  }) {
    ({int blockIndex, int tokenIndex})? bestHit;
    var bestDistance = double.infinity;
    final theme = Theme.of(context);

    for (var index = 0; index < sectionBlocks.length; index++) {
      final block = sectionBlocks[index];
      final key = _bodyTextKeys[_blockTargetKey(block, index)];
      final context = key?.currentContext;
      final renderObject = context?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;

      final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
      final distance = _distanceSquaredToRect(globalPosition, rect);
      if (distance > bestDistance) continue;

      final isHeading = block.isHeading;
      final className = block.className ?? '';
      final isChapterTitle =
          isHeading && _hasEpubClass(className, 'chapterhead');
      final isSectionTitle =
          isHeading && _hasEpubClass(className, 'sectionhead');
      final isDevotionalLead =
          _hasEpubClass(className, 'devotionaltext') ||
          _hasEpubClass(className, 'bibletext') ||
          _hasEpubClass(className, 'center');
      final fontSize = isChapterTitle
          ? bodyFontSize * 1.95
          : isHeading
          ? bodyFontSize * _headingFontScale(block.headingLevel)
          : isDevotionalLead
          ? bodyFontSize * 1.02
          : bodyFontSize;
      final textAlign = isChapterTitle || isSectionTitle || isDevotionalLead
          ? TextAlign.center
          : TextAlign.start;
      final style =
          (isChapterTitle
                  ? theme.textTheme.headlineSmall
                  : isHeading
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.bodyLarge)
              ?.copyWith(
                color: textColor,
                fontWeight: isChapterTitle || isSectionTitle || isDevotionalLead
                    ? FontWeight.w800
                    : isHeading
                    ? FontWeight.w700
                    : FontWeight.w400,
                fontSize: fontSize,
                height: isChapterTitle
                    ? 1.12
                    : isHeading
                    ? 1.35
                    : isDevotionalLead
                    ? 1.45
                    : block.isBlockquote
                    ? 1.7
                    : 1.6,
                fontStyle: block.isBlockquote ? FontStyle.italic : null,
              );
      final resolvedStyle =
          style ??
          theme.textTheme.bodyLarge?.copyWith(color: textColor) ??
          TextStyle(color: textColor, fontSize: bodyFontSize, height: 1.6);

      final localPosition = renderObject.globalToLocal(globalPosition);
      final tokenIndex = hitTestLibraryInteractiveEpubTokenIndex(
        html: block.html,
        fallbackText: block.text,
        baseStyle: resolvedStyle,
        maxWidth: renderObject.size.width,
        localPosition: localPosition,
        textDirection: textDirection,
        textAlign: textAlign,
        highlightQuery: highlightQuery,
        highlightTerms: highlightTerms,
      );
      if (tokenIndex == null || tokenIndex <= 0) continue;
      bestDistance = distance;
      bestHit = (blockIndex: index, tokenIndex: tokenIndex);
    }

    return bestHit;
  }

  String _normalizeBlockKey(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  double _distanceSquaredToRect(Offset point, Rect rect) {
    final clampedX = point.dx < rect.left
        ? rect.left
        : point.dx > rect.right
        ? rect.right
        : point.dx;
    final clampedY = point.dy < rect.top
        ? rect.top
        : point.dy > rect.bottom
        ? rect.bottom
        : point.dy;
    final dx = point.dx - clampedX;
    final dy = point.dy - clampedY;
    return dx * dx + dy * dy;
  }

  ({String href, String? anchor}) _splitReaderHref(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return (href: '', anchor: null);
    }
    final parts = trimmed.split('#');
    final href = parts.first.trim();
    final anchor = parts.length > 1 ? parts.skip(1).join('#').trim() : '';
    return (href: href, anchor: anchor.isEmpty ? null : anchor);
  }

  List<_NavigationDisplayEntry> get _navigationDisplayEntries {
    final items = _orderedNavigationItems;
    if (items.isEmpty) return const [];
    final tree = buildLibraryNavigationTree(
      items,
      devotionalMode: _isDevotionalNavigationBook,
      periodicalMode: widget.item.isPeriodical,
    );
    final childrenByParent = tree.childrenByParent;
    final roots = childrenByParent[null] ?? const [];
    if (roots.isEmpty) {
      return [
        for (var i = 0; i < items.length; i++)
          _NavigationDisplayEntry(item: items[i], depth: 0, displayIndex: i),
      ];
    }

    final result = <_NavigationDisplayEntry>[];
    final visited = <String>{};
    final visibleTargetIds = <String>{};

    bool hasReadableDestination(LibraryCatalogNavigationItem item) {
      final sectionIndex = _sectionIndexForNavigationItem(item);
      if (sectionIndex != null &&
          _sectionIsReadableForAutomaticContinuation(sectionIndex)) {
        return true;
      }
      return libraryReaderFirstReadableDescendant(
            navItem: item,
            tree: tree,
            sections: _sections,
          ) !=
          null;
    }

    void visit(LibraryCatalogNavigationItem item, int depth) {
      if (!visited.add(item.id)) return;
      final visibleItem = libraryReaderVisibleContentsNavigationItem(
        navItem: item,
        tree: tree,
        sections: _sections,
      );
      final shouldDisplay =
          visibleItem != null &&
          hasReadableDestination(visibleItem) &&
          !_isMeaninglessNumericNavigationLabel(item);
      if (shouldDisplay) {
        if (!visibleTargetIds.add(visibleItem.id)) {
          return;
        }
        result.add(
          _NavigationDisplayEntry(
            item: visibleItem,
            depth: depth,
            displayIndex: result.length,
          ),
        );
      }
      for (final child in childrenByParent[item.id] ?? const []) {
        visit(child, shouldDisplay ? depth + 1 : depth);
      }
    }

    for (final root in roots) {
      visit(root, 0);
    }

    for (final item in tree.items) {
      if (visited.contains(item.id)) continue;
      visit(item, 0);
    }

    return result;
  }

  bool _isMeaninglessNumericNavigationLabel(LibraryCatalogNavigationItem item) {
    final label = item.label.trim();
    if (label.isEmpty) return false;
    if (!RegExp(r'^\d+$').hasMatch(label)) return false;
    return !RegExp(r'^chapter\s+\d+$', caseSensitive: false).hasMatch(label);
  }

  void _zoomIn() {
    setState(() {
      _zoomScale = (_zoomScale + 0.1).clamp(0.85, 1.6).toDouble();
    });
    unawaited(AppSettingsService.instance.saveElibraryZoomScale(_zoomScale));
  }

  void _zoomOut() {
    setState(() {
      _zoomScale = (_zoomScale - 0.1).clamp(0.85, 1.6).toDouble();
    });
    unawaited(AppSettingsService.instance.saveElibraryZoomScale(_zoomScale));
  }

  Future<void> _toggleShowRefCodes() async {
    final nextValue = !_showRefCodes;
    setState(() {
      _showRefCodes = nextValue;
    });
    await LocalSettingsStore.instance.saveLibraryReaderShowRefCodes(nextValue);
    if (nextValue) {
      await _ensureParagraphReferenceCodesLoaded();
    }
  }

  Future<void> _ensureParagraphReferenceCodesLoaded() async {
    if (_refCodesLoaded ||
        widget.item.isPdf ||
        widget.item.isPeriodical ||
        _sections.isEmpty) {
      return;
    }
    final paragraphReferenceCodeLoadResult = await _loadParagraphReferenceCodes(
      sections: _sections,
      libraryItemId: widget.item.id,
      rootPath:
          (await LibraryRootService.instance.accessibleLibraryRootPath())
              ?.trim() ??
          (await LibraryRootService.instance.loadSelection()).path?.trim() ??
          '',
    );
    if (!mounted) return;
    setState(() {
      _refCodeByLocation = paragraphReferenceCodeLoadResult.byLocation;
      _paragraphReferenceCodesBySection =
          paragraphReferenceCodeLoadResult.bySection;
      _refCodesLoaded = true;
    });
  }

  Future<_ParagraphReferenceCodeLoadResult> _loadParagraphReferenceCodes({
    required List<LibraryBookSection> sections,
    required String libraryItemId,
    required String rootPath,
  }) async {
    final itemAbbreviation = libraryReaderBookAbbreviation(widget.item);
    final isManagedGreatControversy =
        itemAbbreviation == 'GC' || itemAbbreviation == 'GC88';
    if (isManagedGreatControversy) {
      final db = await UserDatabase.instance.database;
      await _service.ensureManagedEgwReferenceIndex(
        db: db,
        rootPath: rootPath,
        libraryItemId: libraryItemId,
        relativePath: widget.item.relativePath,
        bookTitle: widget.item.displayTitle,
        bookAbbrev: itemAbbreviation ?? 'GC',
        workKey: 'great_controversy',
        editionKey: itemAbbreviation ?? 'GC',
        editionYear: itemAbbreviation == 'GC88' ? 1888 : 1911,
        refresh: false,
      );
      final byLocation = await _service.loadManagedEgwReferenceCodesForItem(
        db: db,
        libraryItemId: libraryItemId,
      );
      return _ParagraphReferenceCodeLoadResult(
        bySection: _paragraphReferenceCodesBySectionFromLocation(byLocation),
        byLocation: byLocation,
      );
    }

    final result = <String, Map<int, String>>{};
    for (final section in sections) {
      final sectionKey = _sectionKey(section.entryName);
      final sectionCodes = await _loadSectionReferenceCodes(
        libraryItemId: libraryItemId,
        section: section,
        itemAbbreviation: itemAbbreviation,
        isDevotional: widget.item.isDevotional,
      );
      if (sectionCodes.isNotEmpty) {
        result[sectionKey] = sectionCodes;
      }
    }

    final generatedByLocation =
        widget.item.isDevotional ||
            itemAbbreviation == null ||
            itemAbbreviation.trim().isEmpty
        ? const <String, String>{}
        : _buildGeneratedParagraphReferenceCodes(
            sections: sections,
            libraryItemId: libraryItemId,
            itemAbbreviation: itemAbbreviation,
          );
    if (generatedByLocation.isNotEmpty) {
      final generatedBySection = _paragraphReferenceCodesBySectionFromLocation(
        generatedByLocation,
      );
      final mergedBySection = <String, Map<int, String>>{};
      for (final entry in result.entries) {
        mergedBySection[entry.key] = Map<int, String>.from(entry.value);
      }
      for (final entry in generatedBySection.entries) {
        mergedBySection
            .putIfAbsent(entry.key, () => <int, String>{})
            .addAll(entry.value);
      }
      return _ParagraphReferenceCodeLoadResult(
        bySection: mergedBySection,
        byLocation: generatedByLocation,
      );
    }

    return _ParagraphReferenceCodeLoadResult(
      bySection: result,
      byLocation: const <String, String>{},
    );
  }

  Future<Map<int, String>> _loadSectionReferenceCodes({
    required String libraryItemId,
    required LibraryBookSection section,
    required String? itemAbbreviation,
    required bool isDevotional,
  }) async {
    return loadReaderSectionReferenceCodes(
      libraryItemId: libraryItemId,
      section: section,
      itemAbbreviation: itemAbbreviation,
      isDevotional: isDevotional,
    );
  }

  String? _displayReferenceCodeForParagraph({
    required String? itemAbbreviation,
    required int? pageNumber,
    required int? pageParagraphIndex,
    required int paragraphIndex,
  }) {
    final abbreviation = cleanDisplayRefCode(itemAbbreviation);
    if (abbreviation == null || abbreviation.isEmpty) {
      return null;
    }
    if (abbreviation == 'GC' || abbreviation == 'GC88') {
      return null;
    }

    if (pageNumber != null &&
        pageParagraphIndex != null &&
        pageNumber > 0 &&
        pageParagraphIndex > 0) {
      final paragraphNumber = paragraphIndex - pageParagraphIndex + 1;
      if (paragraphNumber <= 0) return null;
      return cleanDisplayRefCode('$abbreviation $pageNumber.$paragraphNumber');
    }
    return null;
  }

  Map<String, String> _buildGeneratedParagraphReferenceCodes({
    required List<LibraryBookSection> sections,
    required String libraryItemId,
    required String? itemAbbreviation,
  }) {
    final abbreviation = cleanDisplayRefCode(itemAbbreviation);
    if (abbreviation == null || abbreviation.isEmpty) {
      return const <String, String>{};
    }

    final generatedByLocation = <String, String>{};
    final markerSamples = <String>[];
    final content02Samples = <String>[];
    final content02Href = _sectionKey('OEBPS/content02.xhtml');
    int? currentPageNumber;
    var paragraphNumberOnPage = 0;
    int? content02InitialPage;

    // Pre-scan to find the first pagebreak marker anywhere in the book.
    // Sections with no markers that precede the first marker (e.g. content00 in
    // EGW pamphlets) belong to the page before [N], so paragraphs there can
    // receive ref codes instead of being silently skipped.
    int? bookInitialPageNumber;
    for (final preScanSection in sections) {
      final firstMarker = _firstPageBreakMarkerOccurrence(
        preScanSection.blocks
            .where((b) => b.kind == 'paragraph')
            .toList(growable: false),
      );
      if (firstMarker != null) {
        bookInitialPageNumber = firstMarker.isInsideParagraph
            ? (firstMarker.pageNumber > 1 ? firstMarker.pageNumber - 1 : 1)
            : firstMarker.pageNumber;
        break;
      }
    }

    for (final section in sections) {
      final paragraphBlocks = section.blocks
          .where((block) => block.kind == 'paragraph')
          .toList(growable: false);
      if (paragraphBlocks.isEmpty) {
        continue;
      }

      final firstMarkerInSection = _firstPageBreakMarkerOccurrence(
        paragraphBlocks,
      );
      if (currentPageNumber == null && firstMarkerInSection != null) {
        currentPageNumber = firstMarkerInSection.isInsideParagraph
            ? (firstMarkerInSection.pageNumber > 1
                  ? firstMarkerInSection.pageNumber - 1
                  : 1)
            : firstMarkerInSection.pageNumber;
        if (_sectionKey(section.entryName) == content02Href) {
          content02InitialPage = currentPageNumber;
        }
      }

      var paragraphIndex = 0;
      for (final block in section.blocks) {
        if (block.kind != 'paragraph') {
          continue;
        }
        paragraphIndex += 1;
        final markers = _extractPageBreakMarkers(block.html);
        if (markers.isEmpty) {
          if (currentPageNumber == null) {
            if (bookInitialPageNumber == null) continue;
            currentPageNumber = bookInitialPageNumber;
          }
        } else {
          final firstMarkerBeforeText = markers.firstWhere(
            (marker) => !marker.isInsideParagraph,
            orElse: () => markers.first,
          );
          if (firstMarkerBeforeText.isInsideParagraph &&
              currentPageNumber == null) {
            currentPageNumber = firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
            if (_sectionKey(section.entryName) == content02Href) {
              content02InitialPage ??= currentPageNumber;
            }
          } else if (firstMarkerBeforeText.isInsideParagraph) {
            currentPageNumber ??= firstMarkerBeforeText.pageNumber > 1
                ? firstMarkerBeforeText.pageNumber - 1
                : 1;
          } else {
            currentPageNumber = firstMarkerBeforeText.pageNumber;
          }
        }

        final locationKey = _refCodeLocationKey(
          libraryItemId: libraryItemId,
          href: section.entryName,
          paragraphIndex: paragraphIndex,
        );
        paragraphNumberOnPage += 1;
        final generatedRefCode =
            '$abbreviation $currentPageNumber.$paragraphNumberOnPage';
        generatedByLocation[locationKey] = generatedRefCode;
        if (_sectionKey(section.entryName) == content02Href) {
          if (content02Samples.length < 5) {
            content02Samples.add(
              'paragraphIndex=$paragraphIndex ref=$generatedRefCode preview=${_paragraphPreview(block.text)}',
            );
          }
        }

        final preview = _paragraphPreview(block.text);
        if (markerSamples.length < 20) {
          final markerPreview = markers.isEmpty
              ? '(none)'
              : markers.first.preview;
          markerSamples.add(
            'href=${section.entryName} paragraphIndex=$paragraphIndex '
            'page=$currentPageNumber ref=$generatedRefCode '
            'markerPreview=$markerPreview preview=$preview',
          );
        }

        if (markers.isNotEmpty) {
          final lastMarker = markers.last;
          currentPageNumber = lastMarker.pageNumber;
          paragraphNumberOnPage = 0;
        }
      }
    }

    return generatedByLocation;
  }

  Map<String, Map<int, String>> _paragraphReferenceCodesBySectionFromLocation(
    Map<String, String> byLocation,
  ) {
    final result = <String, Map<int, String>>{};
    for (final entry in byLocation.entries) {
      final parts = entry.key.split('|');
      if (parts.length < 3) continue;
      final href = parts[1];
      final paragraphIndex = int.tryParse(parts[2]);
      if (paragraphIndex == null || paragraphIndex <= 0) continue;
      final sectionKey = _sectionKey(href);
      result.putIfAbsent(sectionKey, () => <int, String>{})[paragraphIndex] =
          entry.value;
    }
    return result;
  }

  _GeneratedPageBreakMarkerOccurrence? _firstPageBreakMarkerOccurrence(
    List<LibraryBookBlock> blocks,
  ) {
    for (final block in blocks) {
      final markers = _extractPageBreakMarkers(block.html);
      if (markers.isNotEmpty) {
        return markers.first;
      }
    }
    return null;
  }

  List<_GeneratedPageBreakMarkerOccurrence> _extractPageBreakMarkers(
    String html,
  ) {
    final markers = <_GeneratedPageBreakMarkerOccurrence>[];
    final spanPattern = RegExp(
      r'<span\b([^>]*)>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );
    for (final match in spanPattern.allMatches(html)) {
      final attrs = match.group(1) ?? '';
      final lowerAttrs = attrs.toLowerCase();
      if (!lowerAttrs.contains('pagebreak')) {
        continue;
      }
      final titleMatch = RegExp(
        r'''title\s*=\s*["'](\d{1,4})["']''',
        caseSensitive: false,
      ).firstMatch(attrs);
      int? pageNumber;
      if (titleMatch != null) {
        pageNumber = int.tryParse(titleMatch.group(1)!);
      } else {
        final inner = (match.group(2) ?? '').trim();
        final innerMatch = RegExp(r'^\[(\d{1,4})\]$').firstMatch(inner);
        if (innerMatch != null) {
          pageNumber = int.tryParse(innerMatch.group(1)!);
        }
      }
      if (pageNumber == null) continue;
      final textBefore = _stripHtmlForRefCode(html.substring(0, match.start));
      final isInsideParagraph = textBefore.trim().isNotEmpty;
      final preview = _pageBreakPreview(match.group(0) ?? '');
      markers.add(
        _GeneratedPageBreakMarkerOccurrence(
          pageNumber: pageNumber,
          isInsideParagraph: isInsideParagraph,
          preview: preview,
        ),
      );
    }
    return markers;
  }

  String _paragraphPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  String _pageBreakPreview(String value) {
    final cleaned = _stripHtmlForRefCode(value);
    if (cleaned.isEmpty) {
      return '(none)';
    }
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  String _stripHtmlForRefCode(String value) {
    final stripped = value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return stripped;
  }

  String _refCodeLocationKey({
    required String libraryItemId,
    required String href,
    required int paragraphIndex,
  }) {
    return '$libraryItemId|${_sectionKey(href)}|$paragraphIndex';
  }

  _PageMarker? _pageMarkerFromText(String? text) {
    final clean = text?.trim() ?? '';
    if (clean.isEmpty) return null;
    final match = RegExp(r'\[(\d{1,4})\]').firstMatch(clean);
    if (match == null) return null;
    final pageNumber = int.tryParse(match.group(1)!);
    if (pageNumber == null) return null;
    return _PageMarker(pageNumber);
  }

  String _sectionKey(String value) {
    return p.normalize(value).toLowerCase();
  }

  Future<void> _openContentsPopup() async {
    await _tiltAutoScroll.stop();
    if (!mounted) return;
    final entries = _navigationDisplayEntries;
    if (entries.isEmpty && _sections.isEmpty) return;

    final selected = await showModalBottomSheet<Object?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return LibraryFontScaleScope(
          scale: _fontScale,
          child: _ContentsPopupSheet(
            itemTitle: widget.item.displayTitle,
            itemSubtitle: '',
            entries: entries,
            sections: _sections,
            currentSectionEntryName: _currentSection?.entryName,
            currentSectionTitle: libraryReaderDisplaySectionTitle(
              _currentSection?.title ?? '',
            ),
            currentSectionSpineIndex: _currentSection?.spineIndex,
            selectedNavigationItemId: _selectedNavigationItem?.id,
            selectedNavigationIndex: _selectedNavigationIndex,
            selectedSectionIndex: _selectedIndex,
            isNightMode: _nightMode,
            isDevotionalNavigation: _isDevotionalNavigationBook,
            isPeriodical: widget.item.isPeriodical,
          ),
        );
      },
    );

    if (!mounted || selected == null) return;
    if (selected is LibraryCatalogNavigationItem) {
      _selectNavigationItem(selected);
    } else if (selected is int) {
      _selectSection(selected);
    }
  }

  Widget _buildContinuousSectionUnit({
    required BuildContext context,
    required int sectionIndex,
    int? previousReadableSectionIndex,
    required Color textColor,
    required Color subduedColor,
    required Color cardBackground,
    required bool isNight,
    required double bodyFontSize,
    required double titleFontSize,
  }) {
    final item = widget.item;
    final contentSection = _contentSectionForIndex(sectionIndex);
    if (contentSection == null) return const SizedBox.shrink();
    final blocks = contentSection.blocks;
    final title = libraryReaderDisplaySectionTitle(contentSection.title);
    final composedHeadings = _composedHeadingSectionsForIndex(sectionIndex)
        .where((section) {
          final label = libraryReaderDisplaySectionTitle(section.title);
          if (label.isEmpty) return false;
          if (identical(section, contentSection)) {
            return _shouldShowSectionTitle(blocks, title);
          }
          return true;
        })
        .toList(growable: false);
    final headings = libraryReaderContinuousUnitHeadings(
      composedHeadings: composedHeadings,
      previousComposedHeadings: previousReadableSectionIndex == null
          ? const <LibraryBookSection>[]
          : _composedHeadingSectionsForIndex(previousReadableSectionIndex),
    );
    final markups =
        _elibraryMarkupsByHref[contentSection.entryName] ??
        const <ElibraryMarkupRecord>[];
    final referenceCodes = item.isDevotional
        ? const <int, String>{}
        : _paragraphReferenceCodesBySection[_sectionKey(
                contentSection.entryName,
              )] ??
              const <int, String>{};
    final selectionSpec = resolveHighlightRender(
      Theme.of(context).colorScheme.primary,
      isNight,
      layerType: HighlightLayerType.temporarySelection,
      readerBackground: cardBackground,
    );
    final active = sectionIndex == _selectedIndex;
    var paragraphIndex = 0;
    var devotionalFallbackParagraphCount = 0;
    final children = <Widget>[];
    for (final heading in headings) {
      children.add(
        SelectableText(
          libraryReaderDisplaySectionTitle(heading.title),
          style: libraryScaledTextStyle(
            Theme.of(context).textTheme.headlineSmall,
            _fontScale * _zoomScale,
            fontWeight: FontWeight.w800,
            color: textColor,
            fontSize: titleFontSize,
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final isParagraph = block.kind == 'paragraph';
      if (isParagraph) paragraphIndex += 1;
      final referenceCode = isParagraph && !_isReaderStructuralHeading(block)
          ? (item.isDevotional
                ? libraryReaderDevotionalFallbackRefCodeForBlock(
                    item: item,
                    sectionTitle: title,
                    block: block,
                    fallbackParagraphCount: devotionalFallbackParagraphCount,
                  )
                : item.isPeriodical
                ? libraryReaderPeriodicalRefCode(
                    item: item,
                    sectionTitle: title,
                    paragraphIndex: paragraphIndex,
                  )
                : _refCodeByLocation[_refCodeLocationKey(
                        libraryItemId: item.id,
                        href: contentSection.entryName,
                        paragraphIndex: paragraphIndex,
                      )] ??
                      referenceCodes[paragraphIndex] ??
                      block.referenceCode)
          : null;
      if (item.isDevotional && referenceCode != null) {
        devotionalFallbackParagraphCount += 1;
      }
      final targetKey = _blockTargetKey(block, index);
      children.add(
        _SectionBlockView(
          key: active
              ? _keyForBlock(targetKey)
              : ValueKey('${contentSection.entryName}:block:$index'),
          block: block,
          blockIndex: index,
          geometryRegistry: _geometryRegistry,
          geometryScopeId:
              'elibrary:${widget.item.id}:${contentSection.entryName}',
          geometryRevision: _enableTextRangeGeometry ? _geometryTick : 0,
          sectionTitle: title,
          sectionEntryName: contentSection.entryName,
          paragraphIndex: isParagraph ? paragraphIndex : null,
          textColor: textColor,
          subduedColor: subduedColor,
          bodyFontSize: bodyFontSize,
          searchQuery: widget.searchQuery,
          highlightTerms: widget.highlightTerms,
          topPadding: index == 0 ? 0 : (block.isHeading ? 18 : 6),
          bottomPadding: block.isHeading ? 12 : 14,
          isNightMode: isNight,
          showRefCodes: _showRefCodes,
          referenceCode: referenceCode,
          hasUserMarkup: markups.isNotEmpty,
          selectionHighlightSpec: selectionSpec,
          rangeSelection: active
              ? _rangeSelection
              : const LibraryRangeSelection(),
          persistedHighlights: markups,
          onBlockTap:
              active &&
                  _rangeSelection.hasCompletedRange &&
                  _rangeSelection.containsBlock(index)
              ? () => _showLibrarySelectionActionsMenu(
                  item: item,
                  section: contentSection,
                  sectionBlocks: blocks,
                )
              : null,
          onWordLongPress: active
              ? (token) => _handleLibraryWordLongPress(
                  blockIndex: index,
                  tokenIndex: token,
                )
              : (_) {},
          onWordLongPressMove: active
              ? (token) => _handleLibraryWordLongPressMove(
                  blockIndex: index,
                  tokenIndex: token,
                )
              : (_) {},
          onWordLongPressMoveDetails: active
              ? (details) {
                  final hit = _resolveLibraryDragTokenHit(
                    globalPosition: details.globalPosition,
                    sectionBlocks: blocks,
                    preferredBlockIndex: index,
                    bodyFontSize: bodyFontSize,
                    textColor: textColor,
                    isNightMode: isNight,
                    highlightQuery: widget.searchQuery,
                    highlightTerms: widget.highlightTerms,
                    textDirection: Directionality.of(context),
                  );
                  if (hit == null) return;
                  _handleLibraryWordLongPressMove(
                    blockIndex: hit.blockIndex,
                    tokenIndex: hit.tokenIndex,
                  );
                }
              : null,
          onWordTap: active
              ? (token) {
                  if (_rangeSelection.hasCompletedRange &&
                      _rangeSelection.containsTokenPosition(index, token)) {
                    _showLibrarySelectionActionsMenu(
                      item: item,
                      section: contentSection,
                      sectionBlocks: blocks,
                    );
                  } else if (_rangeSelection.hasCompletedRange) {
                    _clearLibraryRangeSelection();
                  }
                }
              : (_) {},
          textKey: active
              ? _textKeyForBlock(targetKey)
              : ValueKey('${contentSection.entryName}:text:$index'),
          diagnosticLoggingEnabled: false,
        ),
      );
    }
    return KeyedSubtree(
      key: _sectionUnitKeys.putIfAbsent(
        sectionIndex,
        () => GlobalKey(
          debugLabel: 'elibrary-section-${contentSection.entryName}',
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (shouldAttemptCanonicalDocumentReader(
      item: widget.item,
      routingEnabled: widget.enableCanonicalReader,
    )) {
      return CanonicalLibraryReaderGate(
        item: widget.item,
        searchTarget: widget.searchTarget,
        highlightTerms: widget.highlightTerms,
        themeMode: widget.themeMode,
        onThemeChanged: widget.onThemeChanged,
        onBack: _backToBible,
        onSearch: _openSearch,
        onLibrary: _closeToLibrary,
        actionsBuilder: (context) {
          final theme = Theme.of(context);
          final isNight =
              theme.brightness == Brightness.dark ||
              widget.themeMode == AppThemeMode.night;
          return <Widget>[
            _buildReaderActionsMenu(
              theme: theme,
              textColor: _readerTextColor(theme, isNight),
              cardBackground: _readerSurfaceColor(theme, isNight),
              cardBorder: _readerBorderColor(theme, isNight),
            ),
          ];
        },
        legacyBuilder: (_) => LibraryBookReaderScreen(
          item: widget.item,
          initialHref: widget.initialHref,
          initialAnchorId: widget.initialAnchorId,
          initialSpineIndex: widget.initialSpineIndex,
          initialParagraphIndex: widget.initialParagraphIndex,
          searchTarget: widget.searchTarget,
          searchQuery: widget.searchQuery,
          highlightTerms: widget.highlightTerms,
          searchSession: widget.searchSession,
          onReturnToBible: widget.onReturnToBible,
          themeMode: widget.themeMode,
          onThemeChanged: widget.onThemeChanged,
          enableCanonicalReader: false,
        ),
      );
    }
    final theme = Theme.of(context);
    final isNight = theme.brightness == Brightness.dark || _nightMode;
    final background = _readerBackgroundColor(theme, isNight);
    final summaryBackground = _readerSurfaceHighColor(theme, isNight);
    final cardBackground = _readerSurfaceColor(theme, isNight);
    final cardBorder = _readerBorderColor(theme, isNight);
    final textColor = _readerTextColor(theme, isNight);
    final subduedColor = _readerSubduedColor(theme, isNight);
    final item = widget.item;
    final bodyFontSize =
        (theme.textTheme.bodyLarge?.fontSize ?? 16) * _fontScale * _zoomScale;
    final titleFontSize =
        (theme.textTheme.headlineSmall?.fontSize ?? 24) *
        _fontScale *
        _zoomScale;
    final scaffold = LibraryFontScaleScope(
      scale: _fontScale,
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: [
            PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) {
                  _saveCurrentLocation();
                }
              },
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (MediaQuery.sizeOf(context).width < 900) ...[
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _backToBible,
                              icon: const Icon(Icons.arrow_back),
                              label: Text(
                                'Back to Bible',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'eLibrary',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryScaledTextStyle(
                                  theme.textTheme.headlineMedium?.copyWith(
                                    fontFamily: 'Roboto',
                                  ),
                                  libraryTitleScale(_fontScale),
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _openSearch,
                              icon: const Icon(Icons.search),
                              label: Text(
                                'Search',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            if (_hasSearchSession)
                              _SearchHitNavigator(
                                label: widget.searchSession!.counterLabel,
                                canGoPrevious:
                                    widget.searchSession!.hasPrevious,
                                canGoNext: widget.searchSession!.hasNext,
                                onPrevious: () => _navigateSearchHit(-1),
                                onNext: () => _navigateSearchHit(1),
                                textColor: textColor,
                                backgroundColor: cardBackground,
                                borderColor: cardBorder,
                              ),
                            FilledButton.tonalIcon(
                              onPressed: _closeToLibrary,
                              icon: const Icon(Icons.library_books_outlined),
                              label: Text(
                                'Library',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            _buildReaderActionsMenu(
                              theme: theme,
                              textColor: textColor,
                              cardBackground: cardBackground,
                              cardBorder: cardBorder,
                            ),
                          ],
                        ),
                      ] else ...[
                        Row(
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: _backToBible,
                              icon: const Icon(Icons.arrow_back),
                              label: Text(
                                'Back to Bible',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'eLibrary',
                              style: libraryScaledTextStyle(
                                theme.textTheme.headlineMedium?.copyWith(
                                  fontFamily: 'Roboto',
                                ),
                                libraryTitleScale(_fontScale),
                                fontWeight: FontWeight.w800,
                                color: textColor,
                              ),
                            ),
                            const Spacer(),
                            FilledButton.tonalIcon(
                              onPressed: _openSearch,
                              icon: const Icon(Icons.search),
                              label: Text(
                                'Search',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            if (_hasSearchSession) ...[
                              const SizedBox(width: 10),
                              _SearchHitNavigator(
                                label: widget.searchSession!.counterLabel,
                                canGoPrevious:
                                    widget.searchSession!.hasPrevious,
                                canGoNext: widget.searchSession!.hasNext,
                                onPrevious: () => _navigateSearchHit(-1),
                                onNext: () => _navigateSearchHit(1),
                                textColor: textColor,
                                backgroundColor: cardBackground,
                                borderColor: cardBorder,
                              ),
                            ],
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed: _closeToLibrary,
                              icon: const Icon(Icons.library_books_outlined),
                              label: Text(
                                'Library',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: libraryControlTextStyle(
                                  context,
                                  theme.textTheme.labelLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                foregroundColor: textColor,
                                backgroundColor: cardBackground,
                                side: BorderSide(color: cardBorder),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildReaderActionsMenu(
                              theme: theme,
                              textColor: textColor,
                              cardBackground: cardBackground,
                              cardBorder: cardBorder,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Material(
                        color: summaryBackground,
                        borderRadius: BorderRadius.circular(18),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.displayTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: libraryTitleTextStyle(
                                  context,
                                  theme.textTheme.titleLarge,
                                  fontWeight: FontWeight.w800,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: libraryStableLiveIndicatorHeight(
                                  _fontScale,
                                ),
                                child:
                                    ValueListenableBuilder<
                                      LibraryLiveSectionLocation?
                                    >(
                                      valueListenable: _liveSection,
                                      builder: (context, location, child) {
                                        final label = location?.displayLabel
                                            .trim();
                                        return Text(
                                          label == null || label.isEmpty
                                              ? _currentSubtitle
                                              : label,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: libraryBodyTextStyle(
                                            context,
                                            theme.textTheme.bodyMedium,
                                            color: subduedColor,
                                          ),
                                        );
                                      },
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ReaderTiltAutoScrollActiveIndicator(
                        controller: _tiltAutoScroll,
                      ),
                      Expanded(
                        child: Material(
                          color: cardBackground,
                          borderRadius: BorderRadius.circular(26),
                          borderOnForeground: true,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: _loading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : _error != null
                                  ? Center(
                                      child: Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: libraryBodyTextStyle(
                                          context,
                                          theme.textTheme.bodyLarge,
                                          color: textColor,
                                        ),
                                      ),
                                    )
                                  : _sections.isEmpty
                                  ? Center(
                                      child: Text(
                                        item.isPdf
                                            ? 'PDF reading is not wired yet.'
                                            : 'This book does not expose readable sections yet.',
                                        textAlign: TextAlign.center,
                                        style: libraryBodyTextStyle(
                                          context,
                                          theme.textTheme.bodyLarge,
                                          color: textColor,
                                        ),
                                      ),
                                    )
                                  : GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTap: () {
                                        _readerFocusNode.requestFocus();
                                        if (_tiltAutoScroll.isActive) {
                                          _tiltAutoScroll.showStatusBanner();
                                        }
                                        if (_rangeSelection.hasCompletedRange) {
                                          _clearLibraryRangeSelection();
                                        }
                                      },
                                      child: NotificationListener<ScrollMetricsNotification>(
                                        onNotification:
                                            _handleReaderScrollMetricsNotification,
                                        child: NotificationListener<ScrollNotification>(
                                          onNotification: (notification) {
                                            final notificationContext =
                                                notification.context;
                                            if (notificationContext != null) {
                                              _bodyScrollPosition =
                                                  Scrollable.maybeOf(
                                                    notificationContext,
                                                  )?.position;
                                            }
                                            return _handleReaderScrollNotification(
                                              notification,
                                            );
                                          },
                                          child: ScrollablePositionedList.builder(
                                            key: _continuousScrollViewKey,
                                            itemCount:
                                                _readableSectionIndices.length,
                                            initialScrollIndex:
                                                _readableSectionIndices
                                                    .indexOf(_selectedIndex)
                                                    .clamp(
                                                      0,
                                                      _readableSectionIndices
                                                              .length -
                                                          1,
                                                    ),
                                            itemScrollController:
                                                _itemScrollController,
                                            itemPositionsListener:
                                                _itemPositionsListener,
                                            itemBuilder: (context, itemIndex) {
                                              _bodyScrollPosition ??=
                                                  Scrollable.maybeOf(
                                                    context,
                                                  )?.position;
                                              final sectionIndex =
                                                  _readableSectionIndices[itemIndex];
                                              return _buildContinuousSectionUnit(
                                                context: context,
                                                sectionIndex: sectionIndex,
                                                previousReadableSectionIndex:
                                                    itemIndex > 0
                                                    ? _readableSectionIndices[itemIndex -
                                                          1]
                                                    : null,
                                                textColor: textColor,
                                                subduedColor: subduedColor,
                                                cardBackground: cardBackground,
                                                isNight: isNight,
                                                bodyFontSize: bodyFontSize,
                                                titleFontSize: titleFontSize,
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            MacReaderAutoscrollStatusOverlay(
              controller: _steadyAutoScroll,
              foregroundColor: textColor,
              backgroundColor: background,
            ),
          ],
        ),
        bottomNavigationBar: LayoutBuilder(
          builder: (context, _) => SafeArea(
            key: const ValueKey('elibrary-toolbar-safe-area'),
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: DecoratedBox(
                key: const ValueKey('elibrary-bottom-toolbar'),
                decoration: BoxDecoration(
                  color: _readerSurfaceHighColor(theme, isNight),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: SingleChildScrollView(
                  key: const ValueKey('elibrary-secondary-toolbar-scroll'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ToolbarPillButton(
                        isNightMode: isNight,
                        icon: Icons.list_alt_outlined,
                        label: 'Contents',
                        onPressed: _sections.isEmpty
                            ? null
                            : _openContentsPopup,
                      ),
                      const SizedBox(width: 12),
                      if (libraryReaderUsesSteadyAutoscroll(
                        defaultTargetPlatform,
                      )) ...[
                        if (defaultTargetPlatform == TargetPlatform.macOS)
                          MacReaderAutoScrollButton(
                            controller: _steadyAutoScroll,
                            enabled: libraryReaderSteadyAutoscrollEnabled(
                              item: item,
                              hasReadableSections: _sections.isNotEmpty,
                            ),
                            onPressed: _toggleSteadyAutoscroll,
                            onLongPress: _openSteadyAutoscrollSettings,
                          )
                        else
                          ReaderAutoScrollButton(
                            controller: _steadyAutoScroll,
                            enabled: libraryReaderSteadyAutoscrollEnabled(
                              item: item,
                              hasReadableSections: _sections.isNotEmpty,
                            ),
                            onPressed: _toggleSteadyAutoscroll,
                            onLongPress: _openSteadyAutoscrollSettings,
                          ),
                        const SizedBox(width: 12),
                      ],
                      // Placed immediately after Contents (ahead of Library
                      // and Day/Night) rather than after the zoom cluster:
                      // autoscroll is used far more often on phones than the
                      // theme toggle, and the toolbar row scrolls
                      // horizontally, so a low-priority position left it
                      // hidden off-screen for most phone widths.
                      if (_tiltAutoScroll.motionSource.isSupported) ...[
                        ReaderTiltAutoScrollIconButton(
                          key: const ValueKey('elibrary-tilt-auto-scroll'),
                          controller: _tiltAutoScroll,
                          interactionGeneration: _chapterGeneration,
                          compact: false,
                          enabled: _sections.isNotEmpty && !item.isPdf,
                          onPressed: _toggleTiltAutoscroll,
                          onLongPress: _openTiltSettings,
                        ),
                        const SizedBox(width: 12),
                      ],
                      _ToolbarPillButton(
                        isNightMode: isNight,
                        icon: Icons.library_books_outlined,
                        label: 'Library',
                        onPressed: _closeToLibrary,
                      ),
                      const SizedBox(width: 12),
                      _ToolbarPillButton(
                        isNightMode: isNight,
                        icon: isNight
                            ? Icons.wb_sunny_outlined
                            : Icons.nightlight_round,
                        label: isNight ? 'Day' : 'Night',
                        onPressed: () {
                          final next = isNight
                              ? AppThemeMode.sepia
                              : AppThemeMode.night;
                          setState(
                            () => _nightMode = next == AppThemeMode.night,
                          );
                          final onThemeChanged = widget.onThemeChanged;
                          if (onThemeChanged != null) {
                            onThemeChanged(next);
                          } else {
                            ThemePreferences.instance.saveThemeMode(next);
                          }
                        },
                      ),
                      const SizedBox(width: 12),
                      _ToolbarPillButton(
                        isNightMode: isNight,
                        icon: _showRefCodes
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        label: _showRefCodes
                            ? 'Hide Ref Codes'
                            : 'Show Ref Codes',
                        onPressed: _sections.isEmpty
                            ? null
                            : _toggleShowRefCodes,
                      ),
                      const SizedBox(width: 12),
                      _ZoomCluster(
                        key: const ValueKey('elibrary-font-size-control'),
                        isNightMode: isNight,
                        valueLabel: '${(_zoomScale * 100).round()}%',
                        onZoomOut: _zoomOut,
                        onZoomIn: _zoomIn,
                      ),
                      const SizedBox(width: 12),
                      _NavCluster(
                        isNightMode: isNight,
                        canGoFirst: _sections.isNotEmpty,
                        canGoPrevious: _sections.isNotEmpty,
                        canGoNext: _sections.isNotEmpty,
                        canGoLast: _sections.isNotEmpty,
                        onGoFirst: () =>
                            _scrollToAdjacentHeading(forward: false),
                        onGoPrevious: _scrollPageUp,
                        onGoNext: _scrollPageDown,
                        onGoLast: () => _scrollToAdjacentHeading(forward: true),
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
    final guardedScaffold = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        scaffold,
        ReaderAutoscrollTapShield(
          listenables: <Listenable>[_tiltAutoScroll, _steadyAutoScroll],
          isScrolling: () =>
              _tiltAutoScroll.isActive || _steadyAutoScroll.isScrolling,
          onStop: () {
            _steadyAutoScroll.stopForManualInteraction();
            _tiltAutoScroll.stopSynchronously(
              diagnosticCause: 'pointer-interaction',
            );
            _readerFocusNode.requestFocus();
          },
        ),
      ],
    );
    if (defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return guardedScaffold;
    }
    return Focus(
      focusNode: _readerFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
        event: event,
        readerFocusNode: node,
        controller: _steadyAutoScroll,
        suspended: _readerShortcutsSuspended,
      ),
      child: guardedScaffold,
    );
  }
}

class _PageMarker {
  const _PageMarker(this.pageNumber);

  final int pageNumber;
}

class _ParagraphReferenceCodeLoadResult {
  const _ParagraphReferenceCodeLoadResult({
    required this.bySection,
    required this.byLocation,
  });

  final Map<String, Map<int, String>> bySection;
  final Map<String, String> byLocation;
}

class _GeneratedPageBreakMarkerOccurrence {
  const _GeneratedPageBreakMarkerOccurrence({
    required this.pageNumber,
    required this.isInsideParagraph,
    required this.preview,
  });

  final int pageNumber;
  final bool isInsideParagraph;
  final String preview;
}

class _SearchHitNavigator extends StatelessWidget {
  const _SearchHitNavigator({
    required this.label,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.onPrevious,
    required this.onNext,
    required this.textColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final bool canGoPrevious;
  final bool canGoNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final Color textColor;
  final Color backgroundColor;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = libraryControlTextStyle(
      context,
      theme.textTheme.labelLarge,
      fontWeight: FontWeight.w800,
      color: textColor,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: canGoPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Previous hit',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(label, style: labelStyle),
            ),
            IconButton(
              onPressed: canGoNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              color: textColor,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 30, height: 30),
              padding: EdgeInsets.zero,
              tooltip: 'Next hit',
            ),
          ],
        ),
      ),
    );
  }
}
