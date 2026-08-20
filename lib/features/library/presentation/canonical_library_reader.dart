import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../../core/database/elibrary_database.dart';
import '../../../core/bootstrap/local_settings_store.dart';
import '../../../core/bootstrap/library_root_service.dart';
import '../../../core/theme/app_theme_mode.dart';
import '../../../core/theme/app_settings_service.dart';
import '../data/canonical_activation.dart';
import '../data/library_catalog_service.dart';
import '../data/library_document_canonicalizer.dart';
import '../data/library_document_models.dart';
import '../data/library_document_repository.dart';
import '../data/library_item_identity.dart';
import '../data/elibrary_markup_repository.dart';
import '../data/library_reader_state_writer.dart';
import '../data/library_search_navigation_target.dart';
import '../../search/search_highlight_helper.dart';
import 'canonical_local_image.dart';
import 'canonical_scroll_diagnostics.dart';
import 'elibrary_highlight_color_picker.dart';
import 'library_document_controller.dart';
import 'reader_tilt_autoscroll_controller.dart';
import 'reader_tilt_autoscroll_controls.dart';
import 'reader_tilt_motion_source.dart';
import 'reader_tilt_preferences.dart';
import 'mac_reader_autoscroll_controller.dart';
import 'mac_reader_autoscroll_controls.dart';

/// Legacy developer override retained for proof-harness compatibility.
///
/// Production routing no longer depends on this value. Supported readable
/// documents always attempt canonical preparation and safely fall back when
/// preparation is unavailable.
const bool useCanonicalCaptureClipperReader = bool.fromEnvironment(
  'USE_CANONICAL_CAPTURECLIPPER_READER',
  defaultValue: false,
);

// Retained for proof-harness compatibility only.
const bool useCanonicalLibraryReader = useCanonicalCaptureClipperReader;

enum LibraryReaderImplementation { legacy, canonical }

LibraryReaderImplementation selectLibraryReaderImplementation({
  required bool featureEnabled,
  required bool canonicalComplete,
}) => featureEnabled && canonicalComplete
    ? LibraryReaderImplementation.canonical
    : LibraryReaderImplementation.legacy;

bool supportsCanonicalCaptureClipperReader(LibraryCatalogItem item) {
  if ((item.fileFormat ?? '').trim().toLowerCase() != 'html') return false;
  final sourceType = (item.sourceType ?? '').trim().toLowerCase();
  return sourceType.contains('captured_html') ||
      sourceType.contains('html_capture') ||
      sourceType.contains('pioneer_captured_html');
}

/// Whether normal production routing should attempt the canonical pipeline.
///
/// This is capability-based and deliberately independent of compile-time
/// rollout flags. The gate still falls back to the established reader when
/// preparation cannot produce a current, complete canonical generation.
bool supportsCanonicalDocumentReader(LibraryCatalogItem item) =>
    supportsCanonicalCaptureClipperReader(item) ||
    supportsCanonicalEpubReader(item);

bool shouldAttemptCanonicalDocumentReader({
  required LibraryCatalogItem item,
  bool routingEnabled = true,
}) => routingEnabled && supportsCanonicalDocumentReader(item);

bool shouldUseMacReaderAutoscroll({
  required bool isMacOS,
  required bool isProofHarness,
  bool? override,
}) => shouldUseSteadyReaderAutoscroll(
  isIOS: !isMacOS,
  isProofHarness: isProofHarness,
  override: override,
);

bool shouldUseSteadyReaderAutoscroll({
  required bool isIOS,
  bool isAndroid = false,
  required bool isProofHarness,
  bool? override,
}) => override ?? (!isIOS && !isAndroid && !isProofHarness);

String? canonicalVisibleReaderSubtitle(LibraryDocumentLocation? location) {
  final heading = location?.heading?.plainText.trim() ?? '';
  if (heading.isNotEmpty) return heading;
  final sectionTitle = location?.sectionTitle?.trim() ?? '';
  if (sectionTitle.isEmpty) return null;
  final normalized = sectionTitle.toLowerCase().replaceAll(
    RegExp(r'[^a-z]'),
    '',
  );
  const hiddenProvenance = <String>{
    'capture',
    'capturedhtml',
    'captureclipper',
    'importedhtml',
    'html',
  };
  return hiddenProvenance.contains(normalized) ? null : sectionTitle;
}

@visibleForTesting
bool canonicalSavedOrderIsSubstantive({
  required int savedOrder,
  required int? openingOrder,
}) => openingOrder == null || savedOrder >= openingOrder;

({Color background, Color foreground}) canonicalReaderPalette(
  ThemeData theme,
  AppThemeMode mode,
) => mode == AppThemeMode.night
    ? (background: const Color(0xFF0B0D11), foreground: const Color(0xFFF7F1E5))
    : (
        background: theme.scaffoldBackgroundColor,
        foreground: theme.colorScheme.onSurface,
      );

String? canonicalInlineReferenceCode(
  LibraryDocumentBlock block, {
  required bool visible,
}) {
  if (!visible ||
      block.isHeading ||
      block.blockType == LibraryDocumentBlockType.image ||
      block.blockType == LibraryDocumentBlockType.horizontalRule) {
    return null;
  }
  final code = block.sourceRefcode?.trim() ?? '';
  if (code.isEmpty || block.plainText.contains(code)) return null;
  return code;
}

List<InlineSpan> canonicalInlineTextSpans({
  required LibraryDocumentBlock block,
  required LibraryFormattedContent formatted,
  required TextStyle bodyStyle,
  required TextStyle referenceStyle,
  required bool showReferenceCode,
  List<String> highlightTerms = const <String>[],
}) => <InlineSpan>[
  ...formatted.nodes.map((node) {
    if (node['type'] == 'line_break') return const TextSpan(text: '\n');
    final marks = (node['marks'] as List<Object?>? ?? const <Object?>[])
        .map((value) => value.toString())
        .toSet();
    final nodeStyle = bodyStyle.copyWith(
      fontWeight: marks.contains('bold') ? FontWeight.w700 : null,
      fontStyle: marks.contains('italic') ? FontStyle.italic : null,
      decoration: marks.contains('underline') ? TextDecoration.underline : null,
      fontFeatures: marks.contains('superscript')
          ? const <FontFeature>[FontFeature.superscripts()]
          : marks.contains('subscript')
          ? const <FontFeature>[FontFeature.subscripts()]
          : null,
    );
    final text = node['text']?.toString() ?? '';
    if (highlightTerms.isEmpty) return TextSpan(text: text, style: nodeStyle);
    return TextSpan(
      children: buildHighlightedSearchSpans(
        text,
        highlightTerms,
        baseStyle: nodeStyle,
      ),
    );
  }),
  if (canonicalInlineReferenceCode(block, visible: showReferenceCode)
      case final code?)
    TextSpan(text: ' $code', style: referenceStyle),
];

class CanonicalReaderPreparation {
  const CanonicalReaderPreparation({
    required this.repository,
    required this.sourceRoot,
  });

  final LibraryDocumentRepository repository;
  final Directory sourceRoot;
}

typedef CanonicalReaderPrepare =
    Future<CanonicalReaderPreparation?> Function(LibraryCatalogItem item);

Future<CanonicalReaderPreparation?> prepareCanonicalCaptureClipperReader(
  LibraryCatalogItem item,
) async {
  if (!supportsCanonicalCaptureClipperReader(item)) return null;
  final relativePath = item.relativePath.trim();
  if (relativePath.isEmpty) return null;
  final rootPath =
      (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
  if (rootPath == null || rootPath.isEmpty) return null;
  final resolvedPath = await LibraryRootService.instance.resolveRelativePath(
    relativePath: relativePath,
    rootPath: rootPath,
  );
  final source = File(resolvedPath);
  if (!await source.exists()) return null;

  final db = await ELibraryDatabase.instance.database;
  final outcome = await CanonicalActivation.activate(
    db: db,
    libraryItemId: item.id,
    source: source,
  );
  if (!outcome.isReady) return null;
  return CanonicalReaderPreparation(
    repository: LibraryDocumentRepository(db),
    sourceRoot: source.parent,
  );
}

/// Legacy developer override retained for proof-harness compatibility.
///
/// Production routing is capability-based and does not consult this value.
const bool useCanonicalEpubReader = bool.fromEnvironment(
  'USE_CANONICAL_EPUB_READER',
  defaultValue: false,
);

/// General capability/provenance eligibility for routing a real downloaded
/// EPUB through the canonical database-backed reader. Deliberately not a
/// hardcoded per-title allowlist: any EPUB that is (a) actually an EPUB, (b)
/// downloaded via the official managed pipeline, and (c) physically stored
/// under one of the app's recognized managed EGW folders is *eligible* to
/// attempt canonical routing. Eligibility alone does not mean the book opens
/// canonically — [prepareCanonicalEpubReader] still requires a validated,
/// activated canonical generation (see [LibraryDocumentRepository.isCurrentComplete])
/// before it ever routes away from the legacy reader, so a failed or
/// not-yet-indexed EPUB always keeps its existing fallback behavior.
bool supportsCanonicalEpubReader(LibraryCatalogItem item) {
  if ((item.fileFormat ?? '').trim().toLowerCase() != 'epub') return false;
  final relativePath = item.relativePath.trim();
  if (relativePath.isEmpty) return false;
  final sourceType = (item.sourceType ?? '').trim().toLowerCase();
  if (sourceType == 'official_download') {
    return isManagedEgwRelativePath(relativePath);
  }
  // Added for "Add My Own EPUB" (Phase 2): a user-selected individual EPUB
  // is only eligible when it was actually copied into the dedicated
  // user-imports folder by that flow — never an arbitrary path, and never
  // any other source type. Official EGW eligibility above is unchanged.
  if (sourceType == 'user_import') {
    return isUserImportedEpubRelativePath(relativePath);
  }
  // Added for the raw Pioneer EPUB folder bulk import (Phase 3): a Pioneer
  // EPUB is only eligible when it was actually copied into the dedicated
  // ImportedPioneerEpubs folder by that flow — never an arbitrary path, and
  // never any other source type.
  if (sourceType == 'pioneer_epub_import') {
    return isPioneerImportedEpubRelativePath(relativePath);
  }
  // Added for per-title EGW EPUB downloads made by "Import Pioneer Library"
  // (pioneer_text_import_service.dart): the real .epub egwwritings.org
  // publishes for the title, persisted after a successful canonicalization
  // so its images can be shown alongside the existing flattened-text import.
  // Only eligible when copied into the dedicated managed folder — never an
  // arbitrary path.
  if (sourceType == 'pioneer_egw_epub_source') {
    return isPioneerEgwEpubSourceRelativePath(relativePath);
  }
  return false;
}

/// Canonicalizes (if needed) and prepares a real downloaded EPUB for the
/// canonical reader. If the canonical generation is already complete, the
/// EPUB archive is never even checked for existence — the book must open
/// independently of it, since the storage policy may have already removed
/// it. Only reaches for the EPUB file when a (re)canonicalization is
/// actually required, and only applies the storage policy immediately after
/// a freshly validated + activated import.
Future<CanonicalReaderPreparation?> prepareCanonicalEpubReader(
  LibraryCatalogItem item,
) async {
  if (!supportsCanonicalEpubReader(item)) return null;
  final relativePath = item.relativePath.trim();
  if (relativePath.isEmpty) return null;
  final rootPath =
      (await LibraryRootService.instance.accessibleLibraryRootPath())?.trim();
  if (rootPath == null || rootPath.isEmpty) return null;
  final resolvedPath = await LibraryRootService.instance.resolveRelativePath(
    relativePath: relativePath,
    rootPath: rootPath,
  );
  final source = File(resolvedPath);

  final db = await ELibraryDatabase.instance.database;
  final repository = LibraryDocumentRepository(db);
  final alreadyComplete = await repository.isCurrentComplete(
    item.id,
    canonicalizerVersion: LibraryDocumentCanonicalizer.version,
  );
  if (!alreadyComplete) {
    if (!await source.exists()) return null;
    final outcome = await CanonicalActivation.activate(
      db: db,
      libraryItemId: item.id,
      source: source,
      applyStoragePolicy: true,
      rootPath: rootPath,
    );
    if (!outcome.isReady) return null;
  }

  if (await repository.hasPathologicalNumericTocMarkers(item.id)) {
    debugPrint(
      'canonical_reader_fallback workId=${item.id} '
      'reason=pathological_numeric_toc_markers',
    );
    return null;
  }

  final assetDirectory = Directory(
    p.join(source.parent.path, '_canonical_assets', item.id),
  );
  return CanonicalReaderPreparation(
    repository: repository,
    sourceRoot: await assetDirectory.exists() ? assetDirectory : source.parent,
  );
}

/// Dispatcher used as the default `prepare` for [CanonicalLibraryReaderGate]:
/// tries CaptureClipper first, then managed EPUB preparation.
Future<CanonicalReaderPreparation?> prepareCanonicalDocumentReader(
  LibraryCatalogItem item,
) async {
  final captureClipper = await prepareCanonicalCaptureClipperReader(item);
  if (captureClipper != null) return captureClipper;
  return prepareCanonicalEpubReader(item);
}

class CanonicalLibraryReaderGate extends StatefulWidget {
  const CanonicalLibraryReaderGate({
    super.key,
    required this.item,
    required this.legacyBuilder,
    this.themeMode,
    this.prepare = prepareCanonicalDocumentReader,
    this.onThemeChanged,
    this.actionsBuilder,
    this.macosAutoscroll,
    this.onBack,
    this.onSearch,
    this.onLibrary,
    this.searchTarget,
    this.highlightTerms = const <String>[],
  });

  final LibraryCatalogItem item;
  final WidgetBuilder legacyBuilder;
  final AppThemeMode? themeMode;
  final CanonicalReaderPrepare prepare;
  final ValueChanged<AppThemeMode>? onThemeChanged;
  final List<Widget> Function(BuildContext context)? actionsBuilder;
  final bool? macosAutoscroll;
  final VoidCallback? onBack;
  final VoidCallback? onSearch;
  final VoidCallback? onLibrary;
  final LibrarySearchNavigationTarget? searchTarget;
  final List<String> highlightTerms;

  @override
  State<CanonicalLibraryReaderGate> createState() =>
      _CanonicalLibraryReaderGateState();
}

class _CanonicalLibraryReaderGateState
    extends State<CanonicalLibraryReaderGate> {
  late final Future<CanonicalReaderPreparation?> _preparation;

  @override
  void initState() {
    super.initState();
    _preparation = widget.prepare(widget.item).catchError((
      Object error,
      StackTrace stackTrace,
    ) {
      debugPrint('Canonical reader preparation failed; using legacy: $error');
      return null;
    });
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<CanonicalReaderPreparation?>(
        future: _preparation,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final preparation = snapshot.data;
          if (preparation == null) return widget.legacyBuilder(context);
          return CanonicalLibraryReaderScreen(
            item: widget.item,
            repository: preparation.repository,
            themeMode: widget.themeMode,
            sourceRoot: preparation.sourceRoot,
            onThemeChanged: widget.onThemeChanged,
            actionsBuilder: widget.actionsBuilder,
            macosAutoscroll: widget.macosAutoscroll,
            onBack: widget.onBack,
            onSearch: widget.onSearch,
            onLibrary: widget.onLibrary,
            searchTarget: widget.searchTarget,
            highlightTerms: widget.highlightTerms,
          );
        },
      );
}

class CanonicalLibraryReaderScreen extends StatefulWidget {
  const CanonicalLibraryReaderScreen({
    super.key,
    required this.item,
    required this.repository,
    this.themeMode,
    this.motionSource,
    this.sourceRoot,
    this.proofLabel,
    this.diagnostics,
    this.onThemeChanged,
    this.actionsBuilder,
    this.macosAutoscroll,
    this.onBack,
    this.onSearch,
    this.onLibrary,
    this.searchTarget,
    this.highlightTerms = const <String>[],
  });
  final LibraryCatalogItem item;
  final LibraryDocumentRepository repository;
  final AppThemeMode? themeMode;
  final ReaderTiltMotionSource? motionSource;
  final Directory? sourceRoot;
  final String? proofLabel;
  final CanonicalScrollDiagnostics? diagnostics;
  final ValueChanged<AppThemeMode>? onThemeChanged;
  final List<Widget> Function(BuildContext context)? actionsBuilder;
  final bool? macosAutoscroll;
  final VoidCallback? onBack;
  final VoidCallback? onSearch;
  final VoidCallback? onLibrary;
  final LibrarySearchNavigationTarget? searchTarget;
  final List<String> highlightTerms;

  @override
  State<CanonicalLibraryReaderScreen> createState() =>
      _CanonicalLibraryReaderScreenState();
}

/// Development/test-only entry point. Its repository and source root must be
/// injected, so it cannot accidentally open the installed library database.
class CanonicalSspProofHarness extends StatelessWidget {
  const CanonicalSspProofHarness({
    super.key,
    required this.item,
    required this.repository,
    required this.sourceRoot,
    this.motionSource,
    this.diagnostics,
  });

  final LibraryCatalogItem item;
  final LibraryDocumentRepository repository;
  final Directory sourceRoot;
  final ReaderTiltMotionSource? motionSource;
  final CanonicalScrollDiagnostics? diagnostics;

  @override
  Widget build(BuildContext context) => CanonicalLibraryReaderScreen(
    item: item,
    repository: repository,
    sourceRoot: sourceRoot,
    proofLabel: 'CANONICAL SSP PROOF',
    motionSource: motionSource,
    diagnostics: diagnostics,
  );
}

class _CanonicalLibraryReaderScreenState
    extends State<CanonicalLibraryReaderScreen>
    with WidgetsBindingObserver {
  late final LibraryDocumentController _controller;
  final CallbackReaderAutoScrollTarget _scrollTarget =
      CallbackReaderAutoScrollTarget();
  late final ReaderTiltAutoScrollController _autoScroll;
  final ReaderTiltPreferencesStore _tiltPreferencesStore =
      const ReaderTiltPreferencesStore();
  MacReaderAutoScrollController? _macAutoScroll;
  late final bool _usesMacAutoscroll;
  final FocusNode _readerFocusNode = FocusNode(
    debugLabel: 'canonical-reader-keyboard-focus',
  );
  bool _readerShortcutsSuspended = false;
  int _lastMacStatusRevision = 0;
  LibraryDocumentLocation? _location;
  Timer? _visibleThrottle;
  int _latestVisibleOrder = 0;
  double _fontScale = 1;
  bool _showRefCodes = false;
  int? _initialSearchOrder;
  bool _searchTargetPositioned = false;
  LibraryDocumentBlock? _selectedMarkupBlock;
  TextSelection? _selectedMarkupRange;
  Map<String, List<ElibraryMarkupRecord>> _canonicalHighlights =
      const <String, List<ElibraryMarkupRecord>>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = LibraryDocumentController(
      libraryItemId: widget.item.id,
      repository: widget.repository,
    );
    _autoScroll = ReaderTiltAutoScrollController(
      motionSource: widget.motionSource ?? PlatformReaderTiltMotionSource(),
      scrollTarget: _scrollTarget,
    );
    _tiltPreferencesStore.load().then((value) {
      if (mounted) _autoScroll.updatePreferences(value, showBanner: false);
    });
    _usesMacAutoscroll = shouldUseSteadyReaderAutoscroll(
      isIOS: Platform.isIOS,
      isAndroid: Platform.isAndroid,
      isProofHarness: widget.proofLabel != null,
      override: widget.macosAutoscroll,
    );
    if (_usesMacAutoscroll) {
      _macAutoScroll = MacReaderAutoScrollController(
        scrollTarget: _scrollTarget,
      )..addListener(_macAutoscrollChanged);
      AppSettingsService.instance.loadMacAutoscrollPreferences().then((value) {
        if (mounted) _macAutoScroll?.updatePreferences(value);
      });
    }
    _initializeAtSearchTarget();
    LocalSettingsStore.instance
        .loadLibraryReaderShowRefCodes()
        .then((value) {
          if (mounted) setState(() => _showRefCodes = value);
        })
        .catchError((Object _) {});
    _loadCanonicalHighlights();
    AppSettingsService.instance.loadViewerFontScale().then((value) {
      if (mounted) setState(() => _fontScale = value.clamp(.75, 2.0));
    });
  }

  Future<void> _initializeAtSearchTarget() async {
    final target = widget.searchTarget;
    if (target == null) {
      debugPrint(
        'default_open_resolution_started workId=${widget.item.id} '
        'sourceEditionId=${widget.item.sourceWorkId ?? widget.item.id}',
      );
      final savedOrder = widget.item.lastOpened != null
          ? widget.item.paragraphIndex
          : null;
      final openingOrder = await widget.repository.openingDisplayOrder(
        widget.item.id,
        bookTitle: widget.item.displayTitle,
      );
      if (savedOrder != null &&
          canonicalSavedOrderIsSubstantive(
            savedOrder: savedOrder,
            openingOrder: openingOrder,
          ) &&
          await widget.repository.containsDisplayOrder(
            widget.item.id,
            savedOrder,
          )) {
        debugPrint(
          'default_open_saved_position_used workId=${widget.item.id} '
          'selectedSectionId=${widget.item.epubHref ?? "(canonical)"} '
          'selectedSectionTitle=(saved) reason=valid_saved_position',
        );
        _initialSearchOrder = savedOrder;
        await _controller.initialize(centerOrder: savedOrder);
        return;
      }
      _initialSearchOrder = openingOrder;
      if (savedOrder != null) {
        debugPrint(
          'default_open_saved_position_repaired workId=${widget.item.id} '
          'selectedSectionId=(canonical) selectedSectionTitle=(resolved) '
          'reason=saved_display_order_missing',
        );
      }
      debugPrint(
        openingOrder == null
            ? 'default_open_fallback_used workId=${widget.item.id} '
                  'selectedSectionId=(first) selectedSectionTitle=(first) '
                  'reason=no_substantive_section'
            : 'default_open_front_matter_skipped workId=${widget.item.id} '
                  'skippedSectionIds=(canonical-front-matter) '
                  'selectedSectionId=(canonical-order-$openingOrder) '
                  'selectedSectionTitle=(resolved) '
                  'reason=first_substantive_section',
      );
      if (openingOrder != null) {
        debugPrint(
          'default_open_substantive_section_selected '
          'workId=${widget.item.id} sourceEditionId='
          '${widget.item.sourceWorkId ?? widget.item.id} '
          'selectedSectionId=(canonical-order-$openingOrder) '
          'selectedSectionTitle=(resolved) '
          'reason=first_substantive_section',
        );
      }
      await _controller.initialize(centerOrder: openingOrder ?? 0);
      return;
    }
    debugPrint('search_target_received ${target.diagnosticSummary}');
    final order = await widget.repository.displayOrderForSearchTarget(target);
    if (order == null) {
      debugPrint(
        'search_target_resolution_failed ${target.diagnosticSummary} '
        'reason=canonical source map did not resolve',
      );
      await _controller.initialize();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('The exact search location could not be positioned.'),
          ),
        );
      });
      return;
    }
    _initialSearchOrder = order;
    debugPrint(
      'search_target_section_loaded ${target.diagnosticSummary} order=$order',
    );
    await _controller.initialize(centerOrder: order);
  }

  void _visible(int order) {
    _latestVisibleOrder = order;
    _controller.ensureWindow(order);
    if (_visibleThrottle != null) return;
    _visibleThrottle = Timer(const Duration(milliseconds: 400), () async {
      _visibleThrottle = null;
      final location = await widget.repository.resolveLocation(
        widget.item.id,
        _latestVisibleOrder,
      );
      if (!mounted || location == null) return;
      final oldSubtitle = canonicalVisibleReaderSubtitle(_location);
      final newSubtitle = canonicalVisibleReaderSubtitle(location);
      _location = location;
      if (oldSubtitle != newSubtitle) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_saveCurrentLocation());
    _visibleThrottle?.cancel();
    _macAutoScroll
      ?..removeListener(_macAutoscrollChanged)
      ..dispose();
    _autoScroll.dispose();
    _readerFocusNode.dispose();
    _scrollTarget.detach();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentLocation() async {
    if (widget.searchTarget != null && !_searchTargetPositioned) return;
    final block = _location?.block;
    if (block == null) return;
    await LibraryReaderStateWriter.instance.saveCurrentLocation(
      libraryItemId: widget.item.id,
      currentSectionEntryName: block.sourceHref ?? block.sectionId,
      currentSectionSpineIndex: null,
      savedHref: block.sourceHref,
      savedAnchorId: block.sourceAnchor,
      savedParagraphIndex: block.displayOrder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNight = widget.themeMode == AppThemeMode.night;
    final theme = Theme.of(context);
    final palette = canonicalReaderPalette(
      theme,
      isNight ? AppThemeMode.night : AppThemeMode.sepia,
    );
    final background = palette.background;
    final foreground = palette.foreground;
    final subtitle = canonicalVisibleReaderSubtitle(_location);
    final scaffold = Scaffold(
      backgroundColor: background,
      appBar: widget.proofLabel == null
          ? null
          : AppBar(
              title: Text(widget.proofLabel ?? widget.item.displayTitle),
              backgroundColor: background,
              foregroundColor: foreground,
              actions: null,
            ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              if (widget.proofLabel == null)
                _CanonicalProductionHeader(
                  item: widget.item,
                  foreground: foreground,
                  background: background,
                  onBack: widget.onBack ?? () => Navigator.of(context).pop(),
                  onSearch: widget.onSearch,
                  onLibrary: widget.onLibrary,
                  menu: widget.actionsBuilder?.call(context).firstOrNull,
                ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      subtitle,
                      key: const ValueKey('canonical-visible-heading'),
                      style: TextStyle(
                        color: foreground.withValues(alpha: .72),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, child) => CanonicalLibraryDocumentBody(
                    controller: _controller,
                    autoScrollTarget: _scrollTarget,
                    onVisibleOrderChanged: _visible,
                    textColor: foreground,
                    onManualScroll: _usesMacAutoscroll
                        ? () {
                            _macAutoScroll!.stopForManualInteraction();
                            _autoScroll.stopForManualInteraction();
                          }
                        : _autoScroll.stopForManualInteraction,
                    onReaderInteraction: _readerFocusNode.requestFocus,
                    sourceRoot: widget.sourceRoot,
                    diagnostics: widget.diagnostics,
                    proofCommands: _commands,
                    fontScale: _fontScale,
                    showRefCodes: _showRefCodes,
                    highlightTerms: widget.highlightTerms,
                    initialScrollOrder: _initialSearchOrder,
                    onInitialScrollCompleted: () {
                      _searchTargetPositioned = true;
                      final target = widget.searchTarget;
                      if (target != null) {
                        debugPrint(
                          'search_target_scroll_completed '
                          '${target.diagnosticSummary}',
                        );
                      }
                    },
                    highlightedBlockIds: _canonicalHighlights.keys
                        .map((key) => key.substring('canonical:'.length))
                        .toSet(),
                    onSelectionChanged: (block, selection) {
                      if (!selection.isCollapsed) {
                        _selectedMarkupBlock = block;
                        _selectedMarkupRange = selection;
                      }
                    },
                    onOpenSelectionMenu: _openCanonicalSelectionMenu,
                  ),
                ),
              ),
              if (widget.proofLabel == null)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _CanonicalToolbarButton(
                            icon: Icons.list_alt_outlined,
                            label: 'Contents',
                            onPressed: _openContents,
                          ),
                          const SizedBox(width: 12),
                          // Placed immediately after Contents (ahead of
                          // Library and Day/Night) rather than after the
                          // zoom cluster: autoscroll is used far more often
                          // on phones than the theme toggle, and the toolbar
                          // row scrolls horizontally, so a low-priority
                          // position left it hidden off-screen for most
                          // phone widths.
                          _usesMacAutoscroll &&
                                  !Platform.isMacOS &&
                                  _autoScroll.motionSource.isSupported
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReaderTiltAutoScrollIconButton(
                                      controller: _autoScroll,
                                      onPressed: _toggleTiltAutoscroll,
                                      onLongPress: _openTiltAutoscrollSettings,
                                    ),
                                    ReaderAutoScrollButton(
                                      controller: _macAutoScroll!,
                                      onPressed: _toggleSteadyAutoscroll,
                                      onLongPress: _openMacAutoscrollSettings,
                                    ),
                                  ],
                                )
                              : _usesMacAutoscroll
                              ? Platform.isMacOS
                                    ? MacReaderAutoScrollButton(
                                        controller: _macAutoScroll!,
                                        onPressed: _toggleSteadyAutoscroll,
                                        onLongPress: _openMacAutoscrollSettings,
                                      )
                                    : ReaderAutoScrollButton(
                                        controller: _macAutoScroll!,
                                        onPressed: () {
                                          _macAutoScroll!.toggle();
                                          _readerFocusNode.requestFocus();
                                        },
                                        onLongPress: _openMacAutoscrollSettings,
                                      )
                              : ReaderTiltAutoScrollIconButton(
                                  controller: _autoScroll,
                                  onPressed: _toggleTiltAutoscroll,
                                  onLongPress: _openTiltAutoscrollSettings,
                                ),
                          const SizedBox(width: 12),
                          _CanonicalToolbarButton(
                            icon: Icons.library_books_outlined,
                            label: 'Library',
                            onPressed: widget.onLibrary,
                          ),
                          const SizedBox(width: 12),
                          _CanonicalToolbarButton(
                            key: const ValueKey('canonical-theme-toggle'),
                            icon: isNight
                                ? Icons.wb_sunny_outlined
                                : Icons.nightlight_round,
                            label: isNight ? 'Day' : 'Night',
                            onPressed: widget.onThemeChanged == null
                                ? null
                                : () => widget.onThemeChanged!(
                                    isNight
                                        ? AppThemeMode.sepia
                                        : AppThemeMode.night,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          _CanonicalToolbarButton(
                            icon: _showRefCodes
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            label: _showRefCodes
                                ? 'Hide Ref Codes'
                                : 'Show Ref Codes',
                            onPressed: _toggleRefCodes,
                          ),
                          const SizedBox(width: 12),
                          _CanonicalZoomCluster(
                            valueLabel: '${(_fontScale * 100).round()}%',
                            onZoomOut: () => _setFontScale(_fontScale - .1),
                            onZoomIn: () => _setFontScale(_fontScale + .1),
                          ),
                          const SizedBox(width: 12),
                          _CanonicalNavCluster(
                            onPreviousHeading: () => _jumpHeading(false),
                            onPageUp: () => _scrollTarget.scrollBy(-500),
                            onPageDown: () => _scrollTarget.scrollBy(500),
                            onNextHeading: () => _jumpHeading(true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_macAutoScroll != null)
            MacReaderAutoscrollStatusOverlay(
              controller: _macAutoScroll!,
              foregroundColor: foreground,
              backgroundColor: background,
            ),
        ],
      ),
    );
    final guardedScaffold = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        scaffold,
        ReaderAutoscrollTapShield(
          listenables: <Listenable>[_autoScroll, ?_macAutoScroll],
          isScrolling: () =>
              _autoScroll.isActive || (_macAutoScroll?.isScrolling ?? false),
          onStop: () {
            _macAutoScroll?.stopForManualInteraction();
            _autoScroll.stopSynchronously(
              diagnosticCause: 'pointer-interaction',
            );
          },
        ),
      ],
    );
    if (!_usesMacAutoscroll || (!Platform.isMacOS && !Platform.isWindows)) {
      return guardedScaffold;
    }
    return Focus(
      focusNode: _readerFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => handleMacReaderAutoscrollKeyEvent(
        event: event,
        readerFocusNode: node,
        controller: _macAutoScroll!,
        suspended: _readerShortcutsSuspended,
      ),
      child: guardedScaffold,
    );
  }

  void _macAutoscrollChanged() {
    final controller = _macAutoScroll;
    if (!mounted || controller == null) return;
    if (controller.statusRevision == _lastMacStatusRevision) return;
    _lastMacStatusRevision = controller.statusRevision;
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

  Future<void> _openMacAutoscrollSettings() async {
    if (!Platform.isMacOS && _autoScroll.motionSource.isSupported) {
      await _openTiltAutoscrollSettings();
      return;
    }
    final controller = _macAutoScroll!;
    _readerShortcutsSuspended = true;
    final initial = MacAutoscrollPreferences(
      baseSpeed: controller.baseSpeed,
      lastNonzeroStep: controller.lastNonzeroStep,
      maximumStep: controller.maximumStep,
      statusBannerMode: controller.statusBannerMode,
    );
    final dialog = Platform.isMacOS
        ? showMacAutoscrollSettingsDialog(context: context, initial: initial)
        : showReaderAutoscrollSettingsDialog(
            context: context,
            initial: initial,
          );
    final result = await dialog;
    if (!mounted) return;
    _readerShortcutsSuspended = false;
    if (result != null) {
      controller.updatePreferences(result);
      await AppSettingsService.instance.saveMacAutoscrollPreferences(result);
    }
    _readerFocusNode.requestFocus();
  }

  void _toggleSteadyAutoscroll() {
    if (!_macAutoScroll!.isActive) _autoScroll.stop(notify: false);
    _macAutoScroll!.toggle();
    _readerFocusNode.requestFocus();
  }

  void _toggleTiltAutoscroll() {
    if (_autoScroll.isActive) {
      _autoScroll.stop();
    } else {
      _macAutoScroll?.stopWithoutNotification();
      _autoScroll.activate();
    }
  }

  Future<void> _openTiltAutoscrollSettings() async {
    await _autoScroll.stop();
    if (!mounted) return;
    await showReaderTiltSettingsSheet(
      context,
      preferences: _autoScroll.preferences,
      includeChapterTilt: false,
      onChanged: (preferences) async {
        _autoScroll.updatePreferences(preferences);
        await _tiltPreferencesStore.save(preferences);
      },
      onRecalibrate: () {
        Navigator.of(context).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _autoScroll.activate();
        });
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _autoScroll.stop(notify: false);
    _macAutoScroll?.stopWithoutNotification();
  }

  void _setFontScale(double value) {
    final next = value.clamp(.75, 2.0);
    setState(() => _fontScale = next);
    unawaited(AppSettingsService.instance.saveViewerFontScale(next));
  }

  Future<void> _toggleRefCodes() async {
    final next = !_showRefCodes;
    setState(() => _showRefCodes = next);
    await LocalSettingsStore.instance.saveLibraryReaderShowRefCodes(next);
  }

  Future<void> _openContents() async {
    final headings = await widget.repository.loadHeadings(widget.item.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contents'),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: headings
                .map(
                  (heading) => ListTile(
                    title: Text(heading.plainText),
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_jumpToBlock(heading));
                    },
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  final CanonicalLibraryProofCommands _commands =
      CanonicalLibraryProofCommands();

  Future<void> _jumpToBlock(LibraryDocumentBlock block) async {
    await _controller.ensureWindow(block.displayOrder);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _commands.jumpToOrder(block.displayOrder);
    });
  }

  Future<void> _jumpHeading(bool forward) async {
    final current = _location?.block.displayOrder ?? 0;
    final headings = (await widget.repository.loadHeadings(widget.item.id))
        .where(
          (block) => forward
              ? block.displayOrder > current
              : block.displayOrder < current,
        )
        .toList(growable: false);
    if (headings.isEmpty) return;
    await _jumpToBlock(forward ? headings.first : headings.last);
  }

  Future<void> _loadCanonicalHighlights() async {
    Map<String, List<ElibraryMarkupRecord>> byLocation;
    try {
      byLocation = await ElibraryMarkupRepository().loadMarkupsBySectionForItem(
        widget.item.id,
      );
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _canonicalHighlights = <String, List<ElibraryMarkupRecord>>{
        for (final entry in byLocation.entries)
          if (entry.key.startsWith('canonical:')) entry.key: entry.value,
      };
    });
  }

  Future<void> _highlightCanonicalSelection() async {
    final block = _selectedMarkupBlock;
    final range = _selectedMarkupRange;
    if (block == null || range == null || range.isCollapsed) return;
    final start = range.start.clamp(0, block.plainText.length);
    final end = range.end.clamp(start, block.plainText.length);
    if (end <= start) return;
    final color = await showElibraryHighlightColorPicker(context);
    if (!mounted || color == null) return;
    await ElibraryMarkupRepository().saveHighlight(
      libraryItemId: widget.item.id,
      epubHref: 'canonical:${block.id}',
      startBlockIndex: 0,
      startCharOffset: start,
      endBlockIndex: 0,
      endCharOffset: end,
      refStart: block.sourceRefcode ?? widget.item.displayTitle,
      refEnd: block.sourceRefcode ?? widget.item.displayTitle,
      compactRef: block.sourceRefcode ?? widget.item.displayTitle,
      selectedTextSnapshot: block.plainText.substring(start, end),
      color: color,
    );
    await _loadCanonicalHighlights();
  }

  Future<void> _openCanonicalSelectionMenu() async {
    final block = _selectedMarkupBlock;
    final range = _selectedMarkupRange;
    if (block == null || range == null || range.isCollapsed) return;
    final start = range.start.clamp(0, block.plainText.length);
    final end = range.end.clamp(start, block.plainText.length);
    if (end <= start) return;
    final selectedText = block.plainText.substring(start, end);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Range Actions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(block.sourceRefcode ?? widget.item.displayTitle),
              const SizedBox(height: 8),
              Text(selectedText),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop('copy'),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Copy No Citation'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop('highlight'),
                    icon: const Icon(Icons.format_paint_outlined),
                    label: const Text('Highlight'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed:
                        _canonicalHighlights['canonical:${block.id}']
                                ?.isNotEmpty ==
                            true
                        ? () => Navigator.of(context).pop('clear')
                        : null,
                    icon: const Icon(Icons.layers_clear_outlined),
                    label: const Text('Clear Markup'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.of(context).pop('reset'),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Reset Range'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: selectedText));
        return;
      case 'highlight':
        await _highlightCanonicalSelection();
        return;
      case 'clear':
        await ElibraryMarkupRepository().clearHighlightsOverlappingSelection(
          libraryItemId: widget.item.id,
          epubHref: 'canonical:${block.id}',
          startBlockIndex: 0,
          startCharOffset: start,
          endBlockIndex: 0,
          endCharOffset: end,
        );
        await _loadCanonicalHighlights();
        return;
      case 'reset':
        _selectedMarkupBlock = null;
        _selectedMarkupRange = null;
        return;
    }
  }
}

class _CanonicalProductionHeader extends StatelessWidget {
  const _CanonicalProductionHeader({
    required this.item,
    required this.foreground,
    required this.background,
    required this.onBack,
    required this.onSearch,
    required this.onLibrary,
    required this.menu,
  });

  final LibraryCatalogItem item;
  final Color foreground;
  final Color background;
  final VoidCallback onBack;
  final VoidCallback? onSearch;
  final VoidCallback? onLibrary;
  final Widget? menu;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String label, VoidCallback? onPressed) =>
        FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        );
    final back = button(Icons.arrow_back, 'Back to Bible', onBack);
    final title = Text(
      'eLibrary',
      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
        fontFamily: 'Roboto',
        color: foreground,
        fontWeight: FontWeight.w800,
      ),
    );
    final actions = <Widget>[
      button(Icons.search, 'Search', onSearch),
      button(Icons.library_books_outlined, 'Library', onLibrary),
      ?menu,
    ];
    return SafeArea(
      bottom: false,
      child: Padding(
        key: const ValueKey('canonical-production-header'),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 900) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          back,
                          const SizedBox(width: 12),
                          title,
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: actions),
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    back,
                    const SizedBox(width: 12),
                    title,
                    const Spacer(),
                    ...actions.expand(
                      (action) => <Widget>[action, const SizedBox(width: 12)],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.displayAuthor.trim().isNotEmpty &&
                        item.displayAuthor != 'Unknown author')
                      Text(
                        item.displayAuthor,
                        style: TextStyle(color: foreground),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CanonicalToolbarButton extends StatelessWidget {
  const _CanonicalToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonalIcon(
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

class _CanonicalZoomCluster extends StatelessWidget {
  const _CanonicalZoomCluster({
    required this.valueLabel,
    required this.onZoomOut,
    required this.onZoomIn,
  });
  final String valueLabel;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          key: const ValueKey('canonical-font-decrease'),
          tooltip: 'Zoom out',
          onPressed: onZoomOut,
          icon: const Icon(Icons.zoom_out),
        ),
        Text(valueLabel),
        IconButton(
          key: const ValueKey('canonical-font-increase'),
          tooltip: 'Zoom in',
          onPressed: onZoomIn,
          icon: const Icon(Icons.zoom_in),
        ),
      ],
    ),
  );
}

class _CanonicalNavCluster extends StatelessWidget {
  const _CanonicalNavCluster({
    required this.onPreviousHeading,
    required this.onPageUp,
    required this.onPageDown,
    required this.onNextHeading,
  });
  final VoidCallback onPreviousHeading;
  final VoidCallback onPageUp;
  final VoidCallback onPageDown;
  final VoidCallback onNextHeading;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      IconButton(
        tooltip: 'Previous section heading',
        onPressed: onPreviousHeading,
        icon: const Icon(Icons.keyboard_double_arrow_left),
      ),
      IconButton(
        tooltip: 'Page up',
        onPressed: onPageUp,
        icon: const Icon(Icons.chevron_left),
      ),
      IconButton(
        tooltip: 'Page down',
        onPressed: onPageDown,
        icon: const Icon(Icons.chevron_right),
      ),
      IconButton(
        tooltip: 'Next section heading',
        onPressed: onNextHeading,
        icon: const Icon(Icons.keyboard_double_arrow_right),
      ),
    ],
  );
}

class CanonicalLibraryDocumentBody extends StatefulWidget {
  const CanonicalLibraryDocumentBody({
    super.key,
    required this.controller,
    required this.autoScrollTarget,
    required this.onVisibleOrderChanged,
    required this.textColor,
    this.onManualScroll,
    this.sourceRoot,
    this.diagnostics,
    this.proofCommands,
    this.fontScale = 1,
    this.onReaderInteraction,
    this.showRefCodes = false,
    this.highlightTerms = const <String>[],
    this.initialScrollOrder,
    this.onInitialScrollCompleted,
    this.highlightedBlockIds = const <String>{},
    this.onSelectionChanged,
    this.onOpenSelectionMenu,
  });
  final LibraryDocumentController controller;
  final CallbackReaderAutoScrollTarget autoScrollTarget;
  final ValueChanged<int> onVisibleOrderChanged;
  final Color textColor;
  final VoidCallback? onManualScroll;
  final Directory? sourceRoot;
  final CanonicalScrollDiagnostics? diagnostics;
  final CanonicalLibraryProofCommands? proofCommands;
  final double fontScale;
  final VoidCallback? onReaderInteraction;
  final bool showRefCodes;
  final List<String> highlightTerms;
  final int? initialScrollOrder;
  final VoidCallback? onInitialScrollCompleted;
  final Set<String> highlightedBlockIds;
  final void Function(LibraryDocumentBlock block, TextSelection selection)?
  onSelectionChanged;
  final VoidCallback? onOpenSelectionMenu;

  @override
  State<CanonicalLibraryDocumentBody> createState() =>
      _CanonicalLibraryDocumentBodyState();
}

class _CanonicalLibraryDocumentBodyState
    extends State<CanonicalLibraryDocumentBody> {
  final ItemScrollController _itemController = ItemScrollController();
  final ItemPositionsListener _positions = ItemPositionsListener.create();
  final GlobalKey _visibleListKey = GlobalKey(
    debugLabel: 'canonical-visible-scroll-list',
  );
  ScrollPosition? _position;
  int _firstVisibleOrder = 0;
  bool _initialScrollApplied = false;
  Timer? _autoScrollIdleTimer;
  bool _frameAutoScrollActive = false;
  int _frameAutoScrollDirection = 1;
  DateTime? _lastAutoScrollFrame;

  void _captureVisiblePosition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void inspect(Element element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          final position = (element.state as ScrollableState).position;
          if (position.hasPixels) _position = position;
          return;
        }
        element.visitChildElements(inspect);
      }

      (_visibleListKey.currentContext as Element?)?.visitChildElements(inspect);
    });
  }

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.autoScrollTarget.attach(_scrollByPixels);
      widget.proofCommands?._attach(_jumpToOrder);
      _applyInitialScroll();
    });
    _captureVisiblePosition();
  }

  void _applyInitialScroll() {
    if (_initialScrollApplied) return;
    final order = widget.initialScrollOrder;
    if (order == null || !_itemController.isAttached) return;
    _initialScrollApplied = true;
    debugPrint('search_target_widget_found order=$order');
    _itemController.jumpTo(index: order, alignment: 0.08);
    widget.onInitialScrollCompleted?.call();
  }

  @override
  void didUpdateWidget(covariant CanonicalLibraryDocumentBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialScrollOrder != widget.initialScrollOrder) {
      _initialScrollApplied = false;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyInitialScroll(),
      );
    }
  }

  void _jumpToOrder(int order) {
    if (!_itemController.isAttached || widget.controller.blockCount == 0) {
      return;
    }
    _itemController.jumpTo(
      index: order.clamp(0, widget.controller.blockCount - 1),
    );
  }

  bool _scrollByPixels(double delta) {
    final position = _position;
    if (position == null || !position.hasPixels) {
      return false;
    }
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() <= .01) {
      return false;
    }
    final direction = delta < 0 ? -1 : 1;
    _lastAutoScrollFrame = DateTime.now();
    if (!_frameAutoScrollActive || direction != _frameAutoScrollDirection) {
      _frameAutoScrollActive = true;
      _frameAutoScrollDirection = direction;
      unawaited(
        widget.controller.beginAutoScroll(
          _firstVisibleOrder,
          direction: direction,
        ),
      );
      _scheduleAutoScrollIdleCheck();
    }
    final before = position.pixels;
    position.jumpTo(target);
    final appliedDelta = position.pixels - before;
    final diagnostics = widget.diagnostics;
    if (diagnostics != null) {
      final block = widget.controller.blockAt(_firstVisibleOrder);
      final heading = widget.controller.headingAtOrBefore(_firstVisibleOrder);
      diagnostics.record(
        CanonicalScrollDiagnosticSample(
          timestamp: DateTime.now().toUtc(),
          requestedDelta: delta,
          appliedDelta: appliedDelta,
          firstVisibleBlockId: block?.id,
          firstVisibleDisplayOrder: _firstVisibleOrder,
          headingBlockId: heading?.id,
          headingTitle: heading?.plainText,
          direction: delta < 0 ? 'backward' : 'forward',
          programmaticItemJump: false,
          controllerIdentity: identityHashCode(widget.controller),
          chapterNavigationFired: false,
        ),
      );
    }
    return appliedDelta.abs() > .01;
  }

  void _scheduleAutoScrollIdleCheck() {
    if (_autoScrollIdleTimer != null) return;
    _autoScrollIdleTimer = Timer(const Duration(milliseconds: 350), () {
      _autoScrollIdleTimer = null;
      final lastFrame = _lastAutoScrollFrame;
      if (lastFrame != null &&
          DateTime.now().difference(lastFrame) <
              const Duration(milliseconds: 300)) {
        _scheduleAutoScrollIdleCheck();
        return;
      }
      _frameAutoScrollActive = false;
      widget.controller.endAutoScroll(_firstVisibleOrder);
    });
  }

  void _onPositions() {
    final samples = _positions.itemPositions.value.map(
      (item) => (
        index: item.index,
        leading: item.itemLeadingEdge,
        trailing: item.itemTrailingEdge,
      ),
    );
    final order = firstMeaningfullyVisibleCanonicalOrder(samples);
    if (order >= 0) {
      final changed = order != _firstVisibleOrder;
      _firstVisibleOrder = order;
      if (changed && _frameAutoScrollActive) {
        unawaited(
          widget.controller.beginAutoScroll(
            order,
            direction: _frameAutoScrollDirection,
          ),
        );
      }
      widget.onVisibleOrderChanged(order);
    }
  }

  @override
  void dispose() {
    _autoScrollIdleTimer?.cancel();
    widget.controller.endAutoScroll(_firstVisibleOrder);
    widget.autoScrollTarget.detach();
    widget.proofCommands?._detach();
    _positions.itemPositions.removeListener(_onPositions);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _position = Scrollable.maybeOf(notification.context)?.position;
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            final notificationContext = notification.context;
            if (notificationContext != null) {
              _position = Scrollable.maybeOf(notificationContext)?.position;
            }
            if (readerScrollNotificationIsManual(notification)) {
              widget.onManualScroll?.call();
            }
            return false;
          },
          child: Listener(
            onPointerDown: (_) => widget.onReaderInteraction?.call(),
            child: KeyedSubtree(
              key: const ValueKey('canonical-flat-list'),
              child: ScrollablePositionedList.builder(
                key: _visibleListKey,
                itemCount: widget.controller.blockCount,
                itemScrollController: _itemController,
                itemPositionsListener: _positions,
                initialScrollIndex: (widget.initialScrollOrder ?? 0).clamp(
                  0,
                  widget.controller.blockCount > 0
                      ? widget.controller.blockCount - 1
                      : 0,
                ),
                initialAlignment: widget.initialScrollOrder == null ? 0 : 0.08,
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                itemBuilder: (context, order) {
                  _position ??= Scrollable.maybeOf(context)?.position;
                  if (_position == null || !_position!.hasPixels) {
                    _captureVisiblePosition();
                  }
                  final block = widget.controller.blockAt(order);
                  if (block == null) {
                    widget.controller.ensureWindow(order);
                    // Directional prefetch keeps ordinary sequential scrolling
                    // out of this path. Do not inject a fabricated row height:
                    // it changes the sliver geometry when real content arrives.
                    return const SizedBox.shrink();
                  }
                  return KeyedSubtree(
                    key: ValueKey(block.id),
                    child: _CanonicalBlockView(
                      block: block,
                      color: widget.textColor,
                      sourceRoot: widget.sourceRoot,
                      fontScale: widget.fontScale,
                      showRefCode: widget.showRefCodes,
                      highlightTerms: widget.highlightTerms,
                      highlighted: widget.highlightedBlockIds.contains(
                        block.id,
                      ),
                      onSelectionChanged: (selection) =>
                          widget.onSelectionChanged?.call(block, selection),
                      onOpenSelectionMenu: widget.onOpenSelectionMenu,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
}

class _CanonicalBlockView extends StatelessWidget {
  const _CanonicalBlockView({
    required this.block,
    required this.color,
    required this.sourceRoot,
    required this.fontScale,
    required this.showRefCode,
    this.highlightTerms = const <String>[],
    required this.highlighted,
    required this.onSelectionChanged,
    required this.onOpenSelectionMenu,
  });
  final LibraryDocumentBlock block;
  final Color color;
  final Directory? sourceRoot;
  final double fontScale;
  final bool showRefCode;
  final List<String> highlightTerms;
  final bool highlighted;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final VoidCallback? onOpenSelectionMenu;

  @override
  Widget build(BuildContext context) {
    // Hide page markers already stored by canonicalizer v5. New imports omit
    // them at ingestion, while this compatibility guard cleans existing
    // libraries without requiring the original EPUB archive to still exist.
    if (canonicalBlockIsPrintPageMarker(block)) {
      return const SizedBox.shrink();
    }
    if (block.blockType == LibraryDocumentBlockType.horizontalRule) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Divider(),
      );
    }
    final formatted = LibraryFormattedContent.fromJson(block.formattedContent);
    if (block.blockType == LibraryDocumentBlockType.image) {
      Map<String, Object?>? imageNode;
      for (final node in formatted.nodes) {
        if (node['type'] == 'image') {
          imageNode = node;
          break;
        }
      }
      final source = imageNode?['source']?.toString() ?? '';
      final resolution = sourceRoot == null
          ? const CanonicalLocalImageResolution(
              status: CanonicalLocalImageStatus.rejected,
            )
          : resolveCanonicalLocalImage(sourceRoot: sourceRoot!, source: source);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: resolution.status == CanonicalLocalImageStatus.resolved
            ? Image.file(
                resolution.file!,
                key: const ValueKey('canonical-local-image'),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    _CanonicalImageFallback(color: color, alt: block.plainText),
              )
            : _CanonicalImageFallback(color: color, alt: block.plainText),
      );
    }
    final heading = block.blockType == LibraryDocumentBlockType.heading;
    final quotation = block.blockType == LibraryDocumentBlockType.quotation;
    final poem = block.blockType == LibraryDocumentBlockType.poem;
    final base = TextStyle(
      color: color,
      fontSize: (heading ? 24 : 18) * fontScale,
      height: heading ? 1.3 : 1.6,
      fontWeight: heading ? FontWeight.w800 : FontWeight.w400,
      fontStyle: quotation ? FontStyle.italic : null,
    );
    final align = switch (formatted.alignment) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      _ => TextAlign.start,
    };
    return Padding(
      padding: EdgeInsets.only(
        top: heading ? 20 : 6,
        bottom: heading ? 12 : 14,
        left: quotation ? 12 : 0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: highlighted
              ? Colors.amber.withValues(alpha: .35)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SelectableText.rich(
              TextSpan(
                style: base,
                children: canonicalInlineTextSpans(
                  block: block,
                  formatted: formatted,
                  bodyStyle: base,
                  referenceStyle: base.copyWith(
                    fontSize: (heading ? 24 : 18) * fontScale * .72,
                    color: color.withValues(alpha: .65),
                    fontWeight: FontWeight.w500,
                  ),
                  showReferenceCode: showRefCode,
                  highlightTerms: highlightTerms,
                ),
              ),
              textAlign: align,
              style: poem ? base.copyWith(fontFamily: 'monospace') : base,
              onSelectionChanged: (selection, _) =>
                  onSelectionChanged?.call(selection),
              onTap: onOpenSelectionMenu,
            ),
          ],
        ),
      ),
    );
  }
}

@visibleForTesting
bool canonicalBlockIsPrintPageMarker(LibraryDocumentBlock block) {
  if (!RegExp(r'^\d{1,4}$').hasMatch(block.plainText.trim())) return false;
  final formatted = LibraryFormattedContent.fromJson(block.formattedContent);
  if (formatted.metadata['classification_reason'] ==
      'numeric-only heading treated as page marker, not a real heading') {
    return true;
  }
  if (block.blockType != LibraryDocumentBlockType.listItem) return false;
  final href = (block.sourceHref ?? '').toLowerCase();
  return href.contains('toc.') ||
      href.contains('/toc') ||
      href.contains('nav.') ||
      href.contains('/nav');
}

/// Development-only command seam for explicit proof controls. Ordinary pixel
/// autoscroll never calls this object, so diagnostic jump counts can distinguish
/// a user-requested reposition from continuous scrolling.
class CanonicalLibraryProofCommands {
  void Function(int order)? _jump;
  int explicitJumpCount = 0;

  bool get isAttached => _jump != null;

  void jumpToOrder(int order) {
    final callback = _jump;
    if (callback == null) return;
    explicitJumpCount++;
    callback(order);
  }

  void _attach(void Function(int order) callback) => _jump = callback;
  void _detach() => _jump = null;
}

class _CanonicalImageFallback extends StatelessWidget {
  const _CanonicalImageFallback({required this.color, required this.alt});
  final Color color;
  final String alt;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: alt,
    child: Column(
      key: const ValueKey('canonical-image-fallback'),
      children: <Widget>[
        Icon(Icons.broken_image_outlined, color: color),
        if (alt.isNotEmpty) Text(alt, style: TextStyle(color: color)),
      ],
    ),
  );
}
