import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_settings_service.dart';
import '../../data/presentation/presentation_prep_db_models.dart';
import '../../data/presentation/presentation_prep_repository.dart';
import '../../data/tags/unified_tag_models.dart';
import 'presentation_ui_helpers.dart';
import 'tag_presentation_prep_models.dart';
import 'tag_presentation_prep_state.dart';
import 'tag_presentation_slide_preview.dart';
import 'tag_prepared_slide_renderer.dart';
import 'tag_slide_grid_models.dart';

class TagPresentationRunScreen extends StatefulWidget {
  const TagPresentationRunScreen({
    super.key,
    required this.presentationId,
    required this.presentationName,
  });

  final int presentationId;
  final String presentationName;

  @override
  State<TagPresentationRunScreen> createState() =>
      _TagPresentationRunScreenState();
}

class _TagPresentationRunScreenState extends State<TagPresentationRunScreen> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'presentation-run');
  bool _loading = true;
  String? _error;
  double _fontScale = 1.0;
  List<TagPresentationPrepSlide> _slides = const [];
  TagPresentationPrepWorkspace? _workspace;
  PresentationSharedData? _sharedData;
  int _currentIndex = 0;
  final Map<int, Map<String, Widget>> _widgetCache = {};
  bool _focusRequested = false;

  @override
  void initState() {
    super.initState();
    _loadFontScale();
    _init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusRequested) return;
      _focusRequested = true;
      _focusNode.requestFocus();
    });
  }

  Future<void> _loadFontScale() async {
    final scale = await AppSettingsService.instance.loadViewerFontScale();
    if (!mounted) return;
    setState(() => _fontScale = scale.clamp(0.8, 2.4).toDouble());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    PresentationLoadedGroup? loaded;
    try {
      loaded = await PresentationPrepRepository.instance.loadPresentation(
        widget.presentationId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load "${widget.presentationName}": $e';
      });
      return;
    }

    if (loaded == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '"${widget.presentationName}" was not found.';
      });
      return;
    }

    PresentationSharedData sharedData;
    try {
      sharedData = await loadPresentationSharedData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load slide data: $e';
      });
      return;
    }

    final workspace = _buildRunScreenWorkspace(loaded);
    if (!mounted) return;
    setState(() {
      _workspace = workspace;
      _slides = List.unmodifiable(workspace.slides);
      _sharedData = sharedData;
      _loading = false;
    });

    if (_slides.isNotEmpty) _loadSlide(0);
  }

  Future<void> _loadSlide(int index) async {
    if (_widgetCache.containsKey(index)) return;
    final workspace = _workspace;
    final sharedData = _sharedData;
    if (workspace == null || sharedData == null) return;
    if (index < 0 || index >= _slides.length) return;

    try {
      final widgets = await buildPresentationSlideWidgets(
        slide: _slides[index],
        workspace: workspace,
        sharedData: sharedData,
      );
      if (!mounted) return;
      setState(() => _widgetCache[index] = widgets);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not prepare slide ${index + 1}: $e';
      });
    }
  }

  void _goTo(int index) {
    if (index < 0 || index >= _slides.length) return;
    setState(() => _currentIndex = index);
    _loadSlide(index);
    if (index + 1 < _slides.length) _loadSlide(index + 1);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space) {
      _goTo(_currentIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      _goTo(_currentIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF050506),
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final navHeight = compact ? 72.0 : 64.0;
    final closeButtonExtent = compact ? 42.0 : 44.0;
    final navButtonExtent = compact ? 44.0 : 48.0;
    final errorStyle = presentationTextStyle(
      context,
      theme.textTheme.bodyLarge,
      _fontScale,
      color: const Color(0xFFF2EFE8),
      minFontSize: 15,
      maxFontSize: 20,
    );
    final emptyStyle = presentationTextStyle(
      context,
      theme.textTheme.titleMedium,
      _fontScale,
      color: const Color(0xFFF2EFE8),
      minFontSize: 17,
      maxFontSize: 22,
    );
    final counterStyle = presentationTextStyle(
      context,
      theme.textTheme.labelLarge,
      _fontScale,
      color: const Color(0xAAF3EFE4),
      fontWeight: FontWeight.w600,
      minFontSize: 12,
      maxFontSize: 16,
    );
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF0D68A)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(_error!, style: errorStyle, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF0D68A),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    if (_slides.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.slideshow_outlined,
                size: 64,
                color: const Color(0xFFF0D68A).withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'This presentation has no slides.',
                style: emptyStyle,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF0D68A),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    }

    final slide = _slides[_currentIndex];
    final itemWidgets = _widgetCache[_currentIndex] ?? const {};
    final isFirst = _currentIndex == 0;
    final isLast = _currentIndex == _slides.length - 1;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Stack(
      children: [
        // Background
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.2),
                radius: 1.2,
                colors: [Color(0xFF151518), Color(0xFF050506)],
                stops: [0.0, 1.0],
              ),
            ),
          ),
        ),

        // Slide content — top: below close button area, bottom: above nav bar
        Positioned(
          top: 52,
          bottom: navHeight,
          left: 0,
          right: 0,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: TagPreparedSlideRenderer(
                slide: slide,
                itemWidgetsById: itemWidgets,
                aspectRatio: slide.aspectRatio.aspectRatio,
              ),
            ),
          ),
        ),

        // Left tap zone — previous slide
        Positioned(
          left: 0,
          top: 52,
          bottom: navHeight,
          width: screenWidth * 0.30,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: isFirst ? null : () => _goTo(_currentIndex - 1),
              child: const SizedBox.expand(),
            ),
          ),
        ),

        // Right tap zone — next slide
        Positioned(
          right: 0,
          top: 52,
          bottom: navHeight,
          width: screenWidth * 0.30,
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: isLast ? null : () => _goTo(_currentIndex + 1),
              child: const SizedBox.expand(),
            ),
          ),
        ),

        // Close button — top right
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: const Color(0xAA141417),
            borderRadius: BorderRadius.circular(999),
            elevation: 4,
            child: IconButton(
              constraints: BoxConstraints.tightFor(
                width: closeButtonExtent,
                height: closeButtonExtent,
              ),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
              tooltip: 'Exit presentation',
              color: const Color(0xFFF3EFE4),
            ),
          ),
        ),

        // Bottom navigation bar: prev | counter | next
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: navHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Material(
                  color: isFirst ? Colors.transparent : const Color(0x99141417),
                  borderRadius: BorderRadius.circular(999),
                  child: IconButton(
                    constraints: BoxConstraints.tightFor(
                      width: navButtonExtent,
                      height: navButtonExtent,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: isFirst ? null : () => _goTo(_currentIndex - 1),
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    color: const Color(0xFFF3EFE4),
                    disabledColor: const Color(0x44F3EFE4),
                    tooltip: 'Previous slide',
                  ),
                ),
              ),
              Text(
                '${_currentIndex + 1} / ${_slides.length}',
                style: counterStyle,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Material(
                  color: isLast ? Colors.transparent : const Color(0x99141417),
                  borderRadius: BorderRadius.circular(999),
                  child: IconButton(
                    constraints: BoxConstraints.tightFor(
                      width: navButtonExtent,
                      height: navButtonExtent,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: isLast ? null : () => _goTo(_currentIndex + 1),
                    icon: const Icon(Icons.arrow_forward_ios, size: 20),
                    color: const Color(0xFFF3EFE4),
                    disabledColor: const Color(0x44F3EFE4),
                    tooltip: 'Next slide',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Workspace reconstruction for the run screen
// (mirrors the equivalent in tag_saved_presentations_screen.dart)
// ---------------------------------------------------------------------------

TagPresentationPrepWorkspace _buildRunScreenWorkspace(
  PresentationLoadedGroup loaded,
) {
  final allItems = <UnifiedTagChainItem>[];
  final seenIds = <String>{};

  for (final ls in loaded.slides) {
    for (final item in ls.items) {
      final id = item.sourceItemId ?? 'saved:${item.id}';
      if (!seenIds.add(id)) continue;
      allItems.add(_runToChainItem(loaded.group.id, item));
    }
  }

  final slides = loaded.slides.map(_runToSlide).toList(growable: false);

  final preview = TagPresentationPrepPreview(
    requestedTagName: loaded.group.sourceTagName ?? loaded.group.name,
    sourceSummary: 'Saved presentation: ${loaded.group.name}',
    resolvedChains: const [],
    items: List.unmodifiable(allItems),
    slides: List.unmodifiable(slides),
  );
  return TagPresentationPrepWorkspace.fromPreview(preview);
}

UnifiedTagChainItem _runToChainItem(int groupId, PresentationItemRecord item) {
  final id = item.sourceItemId ?? 'saved:${item.id}';
  final itemType = _runItemTypeFromString(item.itemType);
  final mediaPath = item.mediaPath;
  final media = mediaPath != null
      ? [
          UnifiedTagMedia(
            id: 'saved-media:${item.id}',
            itemId: id,
            relativePath: mediaPath,
            mediaType: _runGuessMediaType(mediaPath),
            sortOrder: 0,
            caption: item.mediaCaption,
          ),
        ]
      : const <UnifiedTagMedia>[];

  return UnifiedTagChainItem(
    id: id,
    chainId: 'saved:$groupId',
    storageKind: UnifiedTagStorageKind.unified,
    sourceType: _runSourceTypeFromItemType(itemType),
    itemType: itemType,
    sortOrder: item.itemOrder,
    displayTitle: item.titleOverride,
    textSnapshot: item.bodyOverride,
    media: media,
    rawFields: const <String, Object?>{},
  );
}

TagPresentationPrepSlide _runToSlide(PresentationLoadedSlide ls) {
  final profile = ls.profile;
  final rows = profile?.rows ?? 2;
  final columns = profile?.columns ?? 2;

  final zoneItemIds = <String, List<String>>{};
  for (final item in ls.items) {
    final id = item.sourceItemId ?? 'saved:${item.id}';
    zoneItemIds.putIfAbsent(item.zoneKey, () => []).add(id);
  }

  final mergedRegions = <TagPresentationMergedRegion>[];
  for (final zone in ls.zones.where((z) => z.zoneType == 'merged')) {
    final itemIds = zoneItemIds[zone.zoneKey] ?? const [];
    final regionId = zone.zoneKey.startsWith('merge:')
        ? zone.zoneKey.substring(6)
        : zone.zoneKey;
    mergedRegions.add(
      TagPresentationMergedRegion(
        id: regionId,
        startRow: zone.startRow,
        startColumn: zone.startColumn,
        rowSpan: zone.rowSpan,
        columnSpan: zone.columnSpan,
        itemIds: List.unmodifiable(itemIds),
      ),
    );
  }

  final cells = <TagPresentationGridCell>[
    for (var row = 0; row < rows; row++)
      for (var col = 0; col < columns; col++)
        TagPresentationGridCell(
          row: row,
          column: col,
          itemIds: List.unmodifiable(zoneItemIds['cell:$row:$col'] ?? const []),
        ),
  ];

  final gridLayout = TagPresentationGridLayout(
    rows: rows,
    columns: columns,
    cells: cells,
    mergedRegions: mergedRegions,
  );

  return TagPresentationPrepSlide(
    slideNumber: ls.slide.slideOrder + 1,
    label: ls.slide.title,
    gridLayout: gridLayout,
    isDraft: false,
    aspectRatio: _runAspectRatioFromProfile(profile),
    topHeaderText: ls.slide.topHeaderText,
    bottomFooterText: ls.slide.bottomFooterText,
  );
}

TagPresentationAspectRatio _runAspectRatioFromProfile(
  PresentationProfileRecord? profile,
) {
  if (profile == null) return const TagPresentationAspectRatio.sixteenByNine();
  return switch (profile.aspectRatioPreset) {
    'sixteenByNine' => const TagPresentationAspectRatio.sixteenByNine(),
    'fourByThree' => const TagPresentationAspectRatio.fourByThree(),
    'sixteenByTen' => const TagPresentationAspectRatio.sixteenByTen(),
    'nineBySixteen' => const TagPresentationAspectRatio.nineBySixteen(),
    _ => TagPresentationAspectRatio.custom(
      profile.aspectRatioValue > 0 ? profile.aspectRatioValue : 16 / 9,
    ),
  };
}

UnifiedTagItemType _runItemTypeFromString(String? value) {
  return switch (value) {
    'bibleVerse' => UnifiedTagItemType.bibleVerse,
    'bibleRange' => UnifiedTagItemType.bibleRange,
    'eLibraryRange' => UnifiedTagItemType.eLibraryRange,
    'note' => UnifiedTagItemType.note,
    'image' => UnifiedTagItemType.image,
    'media' => UnifiedTagItemType.media,
    'heading' => UnifiedTagItemType.heading,
    _ => UnifiedTagItemType.unknownLegacy,
  };
}

UnifiedTagSourceType _runSourceTypeFromItemType(UnifiedTagItemType itemType) {
  return switch (itemType) {
    UnifiedTagItemType.bibleVerse => UnifiedTagSourceType.bible,
    UnifiedTagItemType.bibleRange => UnifiedTagSourceType.bibleRange,
    UnifiedTagItemType.eLibraryRange => UnifiedTagSourceType.eLibrary,
    UnifiedTagItemType.note => UnifiedTagSourceType.note,
    UnifiedTagItemType.image => UnifiedTagSourceType.image,
    UnifiedTagItemType.media => UnifiedTagSourceType.media,
    UnifiedTagItemType.heading => UnifiedTagSourceType.heading,
    UnifiedTagItemType.unknownLegacy => UnifiedTagSourceType.unknownLegacy,
  };
}

String _runGuessMediaType(String path) {
  final lower = path.trim().toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}
